#!/usr/bin/env python3
"""Симуляция баланса PEAK HOUR без Godot.

Модель повторяет формулы из data/balance.json и production-кода:
спавн пакетов/запросов, таймеры, буфер, слоты, канал, выплаты, атаки и
магазин. Играет «компетентный игрок»: принимает все пакеты, выполняет все
запросы, отражает все атаки, покупает апгрейды в подготовке.

Запуск:
    python3 tests/sim_balance.py

Скрипт ничего не пишет в data/ и не меняет production-код. Итог — таблица
дохода по часам и отклонения от целей D12 (500/800/1200/1800/2200 ±10%).
"""

from __future__ import annotations

import json
import math
import random
import statistics
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BALANCE = json.loads((ROOT / "data" / "balance.json").read_text(encoding="utf-8"))

CONST = BALANCE["constants"]
TYPES = BALANCE["types"]
DIFFICULTY = {int(row["hour"]): row for row in BALANCE["difficulty"]}
SHOP = BALANCE["shop"]
ATTACKS = BALANCE["attacks"]

TARGETS = {1: 500, 2: 800, 3: 1200, 5: 1800, 9: 2200}
SEEDS = 40
DT = 0.1
HOUR_SECONDS = float(CONST.get("hour_seconds", 300))
SLA_MAX = float(CONST.get("sla_max", 200))
SLA_START = float(CONST.get("sla_start", 200))
MONEY_START = int(CONST.get("money_start", 150))

SHOP_BY_ID = {str(item["id"]): item for item in SHOP}
SHOP_MAX = {str(item["id"]): int(item.get("max_level", 1)) for item in SHOP}
SHOP_PRICE = {str(item["id"]): int(item.get("price", item.get("cost", 0))) for item in SHOP}

# Приоритет закупки: сначала то, что влияет на доход/пропускную способность.
BUY_ORDER = [
    "shop_buffer",
    "shop_slot3",
    "shop_timer",
    "shop_channel",
    "shop_slot4",
    "shop_section",
    "shop_zone",
    "shop_search",
    "shop_shield",
]

ATTACK_WEIGHTS = [3.0, 2.0, 2.0, 2.0]  # junk, ddos, phishing, ransomware
ATTACK_KINDS = ["junk", "ddos", "phishing", "ransomware"]
TYPE_POOL_BY_HOUR = BALANCE["spawn"]["type_pool_by_hour"]


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def weighted_index(rng: random.Random, weights: list[float]) -> int:
    total = sum(max(0.0, w) for w in weights)
    if total <= 0.0:
        return 0
    roll = rng.random() * total
    acc = 0.0
    for index, weight in enumerate(weights):
        acc += max(0.0, weight)
        if roll < acc:
            return index
    return len(weights) - 1


class Simulation:
    def __init__(self, seed: int) -> None:
        self.seed = seed
        self.rng = random.Random(seed)
        self.money = MONEY_START
        self.sla = SLA_START
        self.streak = 0
        self.levels: dict[str, int] = {item_id: 0 for item_id in SHOP_BY_ID}
        self.sections = 1
        self.folder_counts = [1]  # папок в каждой секции; в C уже есть «Разное»
        self.folders: list[dict] = [{"section": 0, "files": 0, "reserved": 0}]
        self.files: list[dict] = []
        self.file_seq = 0
        self.earned = 0
        self.total_spent = 0
        self.all_maxed_hour: int | None = None
        self.storage_blocked = 0
        self.request_timeouts = 0
        self.packet_timeouts = 0
        self.completed = 0
        self.failed = 0
        self.received = 0
        self.attacks_blocked = 0
        self.hourly: list[dict] = []
        self.channel_samples: list[float] = []
        self.channel_max = 1.0

    # ------------------------------------------------------------------ shop
    def _buy(self, item_id: str) -> bool:
        if self.levels.get(item_id, 0) >= SHOP_MAX.get(item_id, 0):
            return False
        price = SHOP_PRICE[item_id]
        if self.money < price:
            return False
        self.money -= price
        self.total_spent += price
        self.levels[item_id] += 1
        if str(SHOP_BY_ID[item_id].get("effect", "")) == "sections":
            self.sections += 1
            self.folder_counts.append(1)
            self.folders.append({"section": self.sections - 1, "files": 0, "reserved": 0})
        return True

    def buy_prep(self) -> None:
        changed = True
        while changed:
            changed = False
            for item_id in BUY_ORDER:
                if self._buy(item_id):
                    changed = True
                    break
        if self.all_maxed_hour is None and all(
            self.levels[i] >= SHOP_MAX[i] for i in SHOP_BY_ID
        ):
            self.all_maxed_hour = self._prep_hour

    def _buy_section_for_storage(self) -> bool:
        return self._buy("shop_section")

    # --------------------------------------------------------------- ресурсы
    def buffer_limit(self) -> int:
        base = int(CONST.get("buffer_base", 4))
        per = int(CONST.get("buffer_per_upgrade", 2))
        cap = int(CONST.get("buffer_max", 8))
        return int(clamp(base + per * self.levels.get("shop_buffer", 0), base, cap))

    def slot_limit(self) -> int:
        return 2 + (1 if self.levels.get("shop_slot3", 0) else 0) + (
            1 if self.levels.get("shop_slot4", 0) else 0
        )

    def timer_level(self) -> int:
        return self.levels.get("shop_timer", 0)

    def channel_capacity(self) -> float:
        base = float(BALANCE["channel"]["CHANNEL_CAPACITY"])
        step = float(BALANCE["channel"]["capacity_per_upgrade"])
        return base + step * self.levels.get("shop_channel", 0)

    def packet_timer(self, hour: int) -> float:
        return clamp(
            20.0 - 0.5 * (hour - 1) + 4.0 * self.timer_level(),
            12.0,
            999.0,
        )

    def request_timer(self, hour: int) -> float:
        return clamp(
            30.0 - 0.5 * (hour - 1) + 4.0 * self.timer_level(),
            20.0,
            999.0,
        )

    def difficulty_row(self, hour: int) -> dict:
        if hour in DIFFICULTY:
            return DIFFICULTY[hour]
        return DIFFICULTY[max(DIFFICULTY)]

    def recv_interval(self, hour: int) -> float:
        interval = float(self.difficulty_row(hour).get("recv_interval", 12.0))
        if hour > 8:
            periods = int(math.floor((hour - 8) / 2.0))
            interval /= 1.0 + 0.05 * periods
        return max(0.2, interval)

    def send_interval(self, hour: int) -> float:
        return max(0.5, float(self.difficulty_row(hour).get("send_interval", 22.0)))

    def max_requests(self, hour: int) -> int:
        return max(1, int(self.difficulty_row(hour).get("max_requests", 2)))

    def type_pool(self, hour: int) -> list[str]:
        key = "1" if hour <= 1 else ("2" if hour == 2 else "3+")
        pool = TYPE_POOL_BY_HOUR.get(key)
        return list(pool) if pool else ["text", "sound", "photo", "video"]

    def channel_factor(self, hour: int, used_slots: int, packets: list[dict], sends: list[dict]) -> float:
        weights = 0.0
        for packet in packets:
            if packet["state"] == "loading":
                weights += float(TYPES[packet["type"]].get("weight", 0.0))
        for send in sends:
            for file in send["files"]:
                weights += float(TYPES[file["type"]].get("weight", 0.0))
        load = (
            float(BALANCE["channel"]["CHANNEL_BG_BASE"])
            + float(BALANCE["channel"]["CHANNEL_BG_PER_HOUR"]) * (hour - 1)
            + float(BALANCE["channel"]["SLOT_LOAD"]) * used_slots
            + weights
        )
        capacity = self.channel_capacity()
        if capacity <= 0.0:
            return 1.0
        return max(1.0, load / capacity)

    # --------------------------------------------------------------- склад
    def _create_folder(self) -> int | None:
        for section in range(self.sections):
            if self.folder_counts[section] < int(CONST.get("folders_per_section", 12)):
                self.folder_counts[section] += 1
                self.folders.append({"section": section, "files": 0, "reserved": 0})
                return len(self.folders) - 1
        if self._buy_section_for_storage():
            # _buy уже добавил одну папку в новую секцию.
            return len(self.folders) - 1
        self.storage_blocked += 1
        return None

    def _folder_with_space(self) -> int | None:
        for index, folder in enumerate(self.folders):
            if folder["files"] + folder["reserved"] < int(CONST.get("files_per_folder", 16)):
                return index
        return self._create_folder()

    def prepare_storage(self, hour: int) -> None:
        """Компетентный игрок заранее создаёт папки под ожидаемые файлы."""
        expected_new = int(HOUR_SECONDS / max(0.2, self.recv_interval(hour))) + 4
        per_folder = int(CONST.get("files_per_folder", 16))
        total_files = len(self.files)
        needed = int(math.ceil((total_files + expected_new) / per_folder)) + 1
        guard = 0
        while len(self.folders) < needed and guard < 100:
            guard += 1
            if self._create_folder() is None:
                break

    # --------------------------------------------------------------- запросы
    def _attached_files(self) -> set[int]:
        attached: set[int] = set()
        for index, file in enumerate(self.files):
            if file["attached"]:
                attached.add(index)
        return attached

    def _available_files(self, now: float) -> list[int]:
        available: list[int] = []
        for index, file in enumerate(self.files):
            if file["attached"]:
                continue
            if file["cooldown"] > now:
                continue
            available.append(index)
        return available

    def _roll_required_count(self) -> int:
        roll = self.rng.random()
        if roll < 0.6:
            return 1
        if roll < 0.9:
            return 2
        return 3

    def _spawn_request(self, hour: int, now: float, timer_total: float) -> dict | None:
        available = self._available_files(now)
        count = min(self._roll_required_count(), len(available))
        if count <= 0:
            return None
        chosen = self.rng.sample(available, count)
        for index in chosen:
            self.files[index]["attached"] = True
        return {
            "files": chosen,
            "protocol": "tcp" if self.rng.random() < 0.5 else "udp",
            "deadline": now + timer_total,
            "timer_total": timer_total,
        }

    # --------------------------------------------------------------- выплата
    def _payout(self, request: dict, now: float) -> int:
        base_sum = sum(float(TYPES[self.files[i]["type"]].get("base_pay", 0)) for i in request["files"])
        time_ratio = clamp((request["deadline"] - now) / max(0.001, request["timer_total"]), 0.0, 1.0)
        speed = 0.6 + 0.4 * time_ratio
        quality = 1.0  # заглушка MiniGame, D17
        multi = 1.0 + 0.1 * (len(request["files"]) - 1)
        protocol_mult = 1.15 if request["protocol"] == "tcp" else 1.0
        streak_mult = 1.0 + 0.02 * min(10, self.streak)
        value = base_sum * speed * quality * multi * protocol_mult * streak_mult
        return int(round(value))

    def _release_files(self, request: dict, now: float, cooldown: bool) -> None:
        for index in request["files"]:
            self.files[index]["attached"] = False
            if cooldown:
                self.files[index]["cooldown"] = now + 20.0

    # --------------------------------------------------------------- час
    def run_hour(self, hour: int) -> dict:
        self._prep_hour = hour
        start_spent = self.total_spent
        self.buy_prep()
        self.prepare_storage(hour)
        start_earned = self.earned
        start_completed = self.completed
        start_failed = self.failed
        start_received = self.received
        start_attacks = self.attacks_blocked

        now = 0.0
        packets: list[dict] = []
        pending: list[dict] = []
        sends: list[dict] = []
        busy: dict | None = None
        used_slots = 0
        recv_accum = 0.0
        send_accum = 0.0
        next_recv = self.recv_interval(hour) * self.rng.uniform(0.8, 1.2)
        packet_timer_total = self.packet_timer(hour)
        request_timer_total = self.request_timer(hour)
        max_requests = self.max_requests(hour)

        attack_count = int(self.difficulty_row(hour).get("attacks", 1))
        attack_times = sorted(self.rng.uniform(60.0, 240.0) for _ in range(attack_count))
        next_attack = 0

        channel_sum = 0.0
        channel_steps = 0

        def fail_request(request: dict, fine: float) -> None:
            nonlocal used_slots
            self.money = max(0, self.money - int(round(fine)))
            self.sla = max(0.0, self.sla - fine)
            self.failed += 1
            self.request_timeouts += 1
            self._release_files(request, now, cooldown=False)
            if request.get("slot"):
                used_slots = max(0, used_slots - 1)

        def complete_send(job: dict) -> None:
            nonlocal used_slots
            request = job["request"]
            payout = self._payout(request, now)
            self.money += payout
            self.earned += payout
            self.sla = min(SLA_MAX, self.sla + 1.0)
            self.completed += 1
            self.streak += 1
            self._release_files(request, now, cooldown=True)
            if request.get("slot"):
                used_slots = max(0, used_slots - 1)

        steps = int(round(HOUR_SECONDS / DT))
        for _ in range(steps):
            now = round(now + DT, 6)
            modal = False

            # 1. Игрок: соединение / мини-игра.
            if busy is not None:
                busy["left"] -= DT
                if busy["phase"] in ("connect", "minigame"):
                    modal = True
                if busy["left"] <= 0.0:
                    if busy["phase"] == "connect":
                        busy["phase"] = "minigame"
                        busy["left"] = 2.0
                        modal = True
                    elif busy["phase"] == "minigame":
                        request = busy["request"]
                        factor = self.channel_factor(hour, used_slots, packets, sends)
                        duration = 0.0
                        for index in request["files"]:
                            duration += float(TYPES[self.files[index]["type"]].get("send_time", 0.0)) * factor
                        sends.append(
                            {
                                "request": request,
                                "left": max(0.1, duration),
                                "files": [self.files[i] for i in request["files"]],
                            }
                        )
                        busy = None

            # 2. Отправки (идут в фоне, слот держится).
            for job in list(sends):
                job["left"] -= DT
                if job["left"] <= 0.0:
                    complete_send(job)
                    sends.remove(job)

            # 3. Таймеры запросов (идут даже при модалке).
            for request in list(pending):
                if now >= request["deadline"]:
                    pending.remove(request)
                    fail_request(request, 10.0 + 2.0 * hour)
            if busy is not None and now >= busy["request"]["deadline"]:
                fail_request(busy["request"], 10.0 + 2.0 * hour)
                busy = None
            for job in list(sends):
                if now >= job["request"]["deadline"]:
                    sends.remove(job)
                    fail_request(job["request"], 10.0 + 2.0 * hour)

            # 4. Мир: спавн/таймеры пакетов, запросы, атаки — только без модалки.
            if not modal:
                recv_accum += DT
                while recv_accum >= next_recv:
                    recv_accum -= next_recv
                    next_recv = self.recv_interval(hour) * self.rng.uniform(0.8, 1.2)
                    if len(packets) >= self.buffer_limit():
                        recv_accum = 0.0
                        break
                    packet_type = self.rng.choice(self.type_pool(hour))
                    protocol = "tcp" if self.rng.random() < clamp(0.50 + 0.025 * (hour - 1), 0.50, 0.70) else "udp"
                    packets.append(
                        {
                            "type": packet_type,
                            "protocol": protocol,
                            "timer": packet_timer_total,
                            "state": "waiting",
                            "load_left": 0.0,
                            "folder": None,
                        }
                    )

                for packet in list(packets):
                    if packet["state"] == "waiting":
                        packet["timer"] -= DT
                        if packet["timer"] <= 0.0:
                            packets.remove(packet)
                            self.sla = max(0.0, self.sla - 5.0)
                            self.failed += 1
                            self.packet_timeouts += 1
                    elif packet["state"] == "loading":
                        packet["load_left"] -= DT
                        if packet["load_left"] <= 0.0:
                            folder_index = packet["folder"]
                            folder = self.folders[folder_index]
                            folder["reserved"] -= 1
                            folder["files"] += 1
                            self.file_seq += 1
                            self.files.append(
                                {
                                    "type": packet["type"],
                                    "folder": folder_index,
                                    "attached": False,
                                    "cooldown": 0.0,
                                }
                            )
                            self.received += 1
                            self.money += int(TYPES[packet["type"]].get("recv_fee", 0))
                            self.earned += int(TYPES[packet["type"]].get("recv_fee", 0))
                            self.sla = min(SLA_MAX, self.sla + 0.5)
                            packets.remove(packet)

                # Приём: стартуем загрузку всех ожидающих пакетов.
                for packet in packets:
                    if packet["state"] != "waiting":
                        continue
                    folder_index = self._folder_with_space()
                    if folder_index is None:
                        continue
                    factor = self.channel_factor(hour, used_slots, packets, sends)
                    packet["state"] = "loading"
                    packet["folder"] = folder_index
                    packet["load_left"] = max(
                        0.1, float(TYPES[packet["type"]].get("recv_time", 1.0)) * factor
                    )
                    self.folders[folder_index]["reserved"] += 1

                send_accum += DT
                while send_accum >= self.send_interval(hour):
                    send_accum -= self.send_interval(hour)
                    active = len(pending) + len(sends) + (1 if busy is not None else 0)
                    if active >= max_requests:
                        send_accum = 0.0
                        break
                    request = self._spawn_request(hour, now, request_timer_total)
                    if request is not None:
                        pending.append(request)

                while next_attack < len(attack_times) and now >= attack_times[next_attack]:
                    next_attack += 1
                    kind = "junk" if hour <= 1 else ATTACK_KINDS[weighted_index(self.rng, ATTACK_WEIGHTS)]
                    cfg = ATTACKS[kind]
                    self.money += int(cfg.get("reward_money", 0))
                    self.earned += int(cfg.get("reward_money", 0))
                    self.sla = min(SLA_MAX, self.sla + float(cfg.get("reward_sla", 0)))
                    self.attacks_blocked += 1

            # 5. Игрок берёт следующий запрос, если свободен.
            if busy is None and pending:
                pending.sort(key=lambda req: req["deadline"])
                chosen = None
                for request in pending:
                    is_tcp = request["protocol"] == "tcp"
                    if (not is_tcp) or used_slots < self.slot_limit():
                        chosen = request
                        break
                if chosen is not None:
                    pending.remove(chosen)
                    chosen["slot"] = chosen["protocol"] == "tcp"
                    if chosen["slot"]:
                        used_slots += 1
                        busy = {"phase": "connect", "left": 1.0, "request": chosen}
                    else:
                        busy = {"phase": "minigame", "left": 2.0, "request": chosen}

            factor = self.channel_factor(hour, used_slots, packets, sends)
            channel_sum += factor
            channel_steps += 1
            self.channel_max = max(self.channel_max, factor)

            if self.sla <= 0.0:
                # Компетентный игрок не должен доводить до этого; фиксируем.
                break

        self.sla = float(clamp(self.sla, 0.0, SLA_MAX))
        row = {
            "hour": hour,
            "income": self.earned - start_earned,
            "sla": self.sla,
            "completed": self.completed - start_completed,
            "failed": self.failed - start_failed,
            "received": self.received - start_received,
            "attacks": self.attacks_blocked - start_attacks,
            "shop_spent": self.total_spent - start_spent,
            "channel_avg": channel_sum / max(1, channel_steps),
            "channel_max": self.channel_max,
            "left_requests": len(pending) + len(sends) + (1 if busy else 0),
        }
        self.hourly.append(row)
        return row


def run_seed(seed: int) -> Simulation:
    sim = Simulation(seed)
    for hour in range(1, int(CONST.get("run_hours", 9)) + 1):
        sim.run_hour(hour)
    # Финальная подготовка после 9-го часа — проверка «полный выкуп к 8–9».
    sim._prep_hour = 10
    sim.buy_prep()
    return sim


def main() -> int:
    runs = [run_seed(seed) for seed in range(1, SEEDS + 1)]

    print("PEAK HOUR — balance simulation (no Godot)")
    print(f"сидов: {SEEDS}, часов: {CONST.get('run_hours', 9)}, dt: {DT} с")
    print("")

    per_hour_income: dict[int, list[int]] = defaultdict(list)
    per_hour_sla: dict[int, list[float]] = defaultdict(list)
    per_hour_completed: dict[int, list[int]] = defaultdict(list)
    per_hour_failed: dict[int, list[int]] = defaultdict(list)
    per_hour_received: dict[int, list[int]] = defaultdict(list)
    per_hour_attacks: dict[int, list[int]] = defaultdict(list)
    per_hour_channel: dict[int, list[float]] = defaultdict(list)
    per_hour_shop: dict[int, list[int]] = defaultdict(list)

    for sim in runs:
        for row in sim.hourly:
            hour = int(row["hour"])
            per_hour_income[hour].append(int(row["income"]))
            per_hour_sla[hour].append(float(row["sla"]))
            per_hour_completed[hour].append(int(row["completed"]))
            per_hour_failed[hour].append(int(row["failed"]))
            per_hour_received[hour].append(int(row["received"]))
            per_hour_attacks[hour].append(int(row["attacks"]))
            per_hour_channel[hour].append(float(row["channel_avg"]))
            per_hour_shop[hour].append(int(row["shop_spent"]))

    header = (
        "час | доход   | цель | откл    | SLA   | вып.  | провал | принято | атаки | канал | магазин $"
    )
    print(header)
    print("-" * len(header))
    fails: list[str] = []
    for hour in range(1, 10):
        incomes = per_hour_income[hour]
        mean_income = statistics.fmean(incomes) if incomes else 0.0
        target = TARGETS.get(hour)
        if target is not None:
            deviation = (mean_income - target) / target * 100.0
            dev_text = f"{deviation:+6.1f}%"
            if abs(deviation) > 10.0:
                fails.append(
                    f"час {hour}: доход {mean_income:.0f} против цели {target} ({deviation:+.1f}%)"
                )
        else:
            dev_text = "   —  "
        sla = statistics.fmean(per_hour_sla[hour]) if per_hour_sla[hour] else 0.0
        print(
            f"{hour:>3} | {mean_income:>8.0f} | {str(target) if target else '  — ':>4} | "
            f"{dev_text:>7} | {sla:>5.1f} | {statistics.fmean(per_hour_completed[hour]):>5.1f} | "
            f"{statistics.fmean(per_hour_failed[hour]):>6.1f} | "
            f"{statistics.fmean(per_hour_received[hour]):>7.1f} | "
            f"{statistics.fmean(per_hour_attacks[hour]):>5.1f} | "
            f"{statistics.fmean(per_hour_channel[hour]):>5.2f} | "
            f"{statistics.fmean(per_hour_shop[hour]):>9.0f}"
        )

    total_income = statistics.fmean([sum(r["income"] for r in sim.hourly) for sim in runs])
    total_spent = statistics.fmean([sim.total_spent for sim in runs])
    total_completed = statistics.fmean([sim.completed for sim in runs])
    total_received = statistics.fmean([sim.received for sim in runs])
    total_timeouts = sum(sim.request_timeouts for sim in runs)
    packet_timeouts = sum(sim.packet_timeouts for sim in runs)
    blocked_storage = sum(sim.storage_blocked for sim in runs)
    maxed_hours = [sim.all_maxed_hour for sim in runs]
    full_buyout = all(h is not None and h <= 9 for h in maxed_hours)
    channel_max = max(sim.channel_max for sim in runs)
    sla_ok = all(0.0 <= row["sla"] <= SLA_MAX for sim in runs for row in sim.hourly)
    money_ok = all(sim.money >= 0 for sim in runs)

    print("")
    print(f"суммарный доход за 9 ч (ср.): {total_income:.0f} $")
    print(f"потрачено в магазине (ср.): {total_spent:.0f} $")
    print(f"выполнено запросов (ср.): {total_completed:.1f}, принято файлов (ср.): {total_received:.1f}")
    print(f"таймауты запросов: {total_timeouts}, таймауты пакетов: {packet_timeouts}")
    print(f"отказы склада (нет места): {blocked_storage}")
    print(f"макс. factor канала: {channel_max:.2f}")
    if full_buyout:
        print(f"полный выкуп магазина: да (не позднее часа {max(h for h in maxed_hours)})")
    else:
        missing = [h for h in maxed_hours if h is None]
        fails.append(f"полный выкуп магазина не достигнут к 9-му часу (сидов без выкупа: {len(missing)})")
        print("полный выкуп магазина: НЕТ")
    print("")

    if not sla_ok:
        fails.append("SLA вышел за пределы 0..200")
    if not money_ok:
        fails.append("money ушёл в минус")
    if blocked_storage:
        fails.append(f"дедлок склада: {blocked_storage} отказов (нет папки/секции)")
    if total_timeouts:
        fails.append(f"таймауты запросов у компетентного игрока: {total_timeouts}")
    if packet_timeouts:
        fails.append(f"таймауты пакетов у компетентного игрока: {packet_timeouts}")

    print("ПРОВЕРКИ")
    print(f"  SLA 0..200: {'PASS' if sla_ok else 'FAIL'}")
    print(f"  money >= 0: {'PASS' if money_ok else 'FAIL'}")
    print(f"  склад без дедлока: {'PASS' if blocked_storage == 0 else 'FAIL'}")
    print(f"  запросы без таймаутов: {'PASS' if total_timeouts == 0 else 'FAIL'}")
    print(f"  пакеты без таймаутов: {'PASS' if packet_timeouts == 0 else 'FAIL'}")
    print(f"  полный выкуп к 9 ч: {'PASS' if full_buyout else 'FAIL'}")
    print(f"  доход в пределах ±10% D12: {'PASS' if not any('доход' in f for f in fails) else 'FAIL'}")
    if fails:
        print("")
        for failure in fails:
            print(f"FAIL: {failure}")
        print("FAIL sim_balance")
        return 1
    print("PASS sim_balance")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
