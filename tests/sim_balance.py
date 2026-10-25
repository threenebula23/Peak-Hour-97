#!/usr/bin/env python3
"""PEAK HOUR v3 balance simulator (pure Python 3, no third-party deps).

Reads ``data/balance.json`` from the repository and models hours H1-H9:
file budget/spawn window, type weights, request cap/active limit/request mix,
file consumption on send, receive/send transfer times, channel load,
connection slots, request timers, payout formula, recv_fee, SLA regen/fines,
attacks, folder cells/shapes, buffer-full spawn hold and shop purchases.

The simulator is *read-only*: it never writes data/ or production scripts.
The only file it writes is ``tests/SIM_BALANCE_REPORT.md``.

Run:
    python tests/sim_balance.py
    py -3 tests/sim_balance.py

Exit code:
    0 - every hour mean is inside +-20% of its income target AND every
        analytical maximum cap is at least the target;
    1 - otherwise (so CI catches B1-style economic blockers).
"""

from __future__ import annotations

import json
import math
import random
import statistics
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

ROOT = Path(__file__).resolve().parent.parent
BALANCE_PATH = ROOT / "data" / "balance.json"
REPORT_PATH = Path(__file__).resolve().parent / "SIM_BALANCE_REPORT.md"

BALANCE = json.loads(BALANCE_PATH.read_text(encoding="utf-8"))

CONST = BALANCE["constants"]
TYPES = BALANCE["types"]
HOURS = {int(row["hour"]): row for row in BALANCE["hours"]}
PAYOUT = BALANCE["payout"]
SHOP = list(BALANCE["shop"])
SHOP_BY_ID = {str(lot["id"]): lot for lot in SHOP}
SHOP_RULES = BALANCE["shop_rules"]
SLA_CFG = BALANCE["sla"]
ATTACKS = BALANCE["attacks"]
GRID = BALANCE["grid"]

TYPE_ORDER = ["text", "sound", "photo", "video"]
TOTAL_TREE = sum(int(p) for lot in SHOP for p in lot["prices"])

# --- model assumptions ------------------------------------------------------
SEEDS = 240                 # spec asks 200+ (not the old 40)
DT = 0.25                   # seconds per tick
SPAWN_WINDOW_RATIO = float(CONST.get("spawn_window_ratio", 0.75))
SPAWN_JITTER = float(CONST.get("spawn_jitter", 0.2))
HOUR_SECONDS = float(CONST.get("hour_seconds", 300))
MAX_FILES_PER_HOUR = 20
RUN_HOURS = int(CONST.get("run_hours", 9))

Q_SEND = 0.85               # competent player: send minigame quality
Q_ATTACK = 0.85             # competent player: attack minigame quality
HUMAN_ATTACH_BASE = 1.5     # see/read request and start attaching
HUMAN_ATTACH_PER_FILE = 1.0
MINIGAME_BASE = 7.0         # no timer: competent player still needs time
MINIGAME_PER_TIER = 1.5
PROTOCOL = "tcp"            # production default; TCP is +15% payout
TCP_CONNECT_SEC = 4.2       # production TCP connection minigame, competent player
TCP_CONNECT_FAIL = 0.04     # 4% missed TCP connection
TCP_CONNECT_FAIL_SLA = 4.0  # and -4 SLA
CHECK_TOL = 0.20            # +-20% per hour
PURCHASE_ROI_MIN = 0.5      # regular prep: buy while predicted value >= 0.5x price
FINAL_PREP_ROI_MIN = 0.0    # before H9 there is no future shop: spend on any positive ROI

TARGETS = {int(h): float(HOURS[h]["income_target"]) for h in HOURS}
BAND_LOW = int(sum(TARGETS.values()))
BAND_HIGH = 8500
BAND_TEXT = f"{BAND_LOW:,} - {BAND_HIGH:,}".replace(",", " ")
MAX_SLA = float(CONST.get("sla_hard_cap", 220))
SLA_REGEN = float(CONST.get("sla_regen_per_hour", 15))

# type helpers
BASE_PAY = {t: float(TYPES[t]["base_pay"]) for t in TYPES}
RECV_FEE = {t: float(TYPES[t]["recv_fee"]) for t in TYPES}
RECV_TIME = {t: float(TYPES[t]["base_time_sec"]) for t in TYPES}
TYPE_WEIGHT = {t: float(TYPES[t]["weight"]) for t in TYPES}
SLA_LOSS = {t: float(TYPES[t]["sla_loss"]) for t in TYPES}
CELLS = {t: int(TYPES[t]["cells"]) for t in TYPES}
MINIGAME_COEFF = {t: int(TYPES[t]["minigame_coeff"]) for t in TYPES}

ACHIEVABLE_SUMS = [int(v) for v in BALANCE["minigames"]["selection"]["achievable_sums"]]
SEND_ORDER = list(BALANCE["minigames"]["selection"]["order"])
SEL = BALANCE["minigames"]["selection"]
TIER_MAX_RANK = [int(v) for v in SEL.get("tier_max_rank", [7, 13])]
RANK_GAMES = list(SEL.get(
    "rank_games",
    ["text", "sound", "dots", "photo", "maze", "dots", "photo", "video",
     "dots", "text", "video", "maze", "photo", "sound", "video", "text",
     "maze", "sound", "video", "sound", "photo", "dots", "dots", "maze",
     "maze", "photo", "video"],
))
FOLDER_NEW_COST = int(CONST.get("folder_new_cost", 180))
SHIELD_REWARD_SCALE = float(ATTACKS.get("shield_reward_scale", 0.7))


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def percentile(values: list[float], q: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    if len(ordered) == 1:
        return float(ordered[0])
    pos = (len(ordered) - 1) * clamp(q, 0.0, 1.0)
    low = int(math.floor(pos))
    high = int(math.ceil(pos))
    if low == high:
        return float(ordered[low])
    frac = pos - low
    return float(ordered[low]) * (1.0 - frac) + float(ordered[high]) * frac


def weighted_choice(rng: random.Random, weights: dict[str, float]) -> str:
    total = sum(max(0.0, float(w)) for w in weights.values())
    if total <= 0.0:
        return TYPE_ORDER[0]
    roll = rng.random() * total
    acc = 0.0
    last = TYPE_ORDER[0]
    for key, weight in weights.items():
        w = max(0.0, float(weight))
        if w <= 0.0:
            continue
        last = key
        acc += w
        if roll < acc:
            return key
    return last


def weighted_index(rng: random.Random, values: list[str], weights: list[float]) -> int:
    total = sum(max(0.0, w) for w in weights)
    if total <= 0.0:
        return 0
    roll = rng.random() * total
    acc = 0.0
    for index, weight in enumerate(weights):
        acc += max(0.0, weight)
        if roll < acc:
            return index
    return len(values) - 1


def send_minigame_for(types: list[str]) -> dict[str, int | str]:
    """Economy.selection_for_sum: 27 dense sums, 3 tiers, direct rank table."""
    total = sum(MINIGAME_COEFF.get(str(t).lower(), 1) for t in types)
    if total <= 0:
        return {"id": "dots", "tier": 1, "index": 0, "sum": 0}
    rank = 0
    for i, value in enumerate(ACHIEVABLE_SUMS):
        if value <= total:
            rank = i
        else:
            break
    if rank > TIER_MAX_RANK[1]:
        tier = 3
    elif rank > TIER_MAX_RANK[0]:
        tier = 2
    else:
        tier = 1
    return {
        "id": RANK_GAMES[min(rank, len(RANK_GAMES) - 1)],
        "tier": tier,
        "index": rank,
        "sum": total,
    }


def payout(base_sum: float, n: int, time_left: float, timer_total: float,
           quality_q: float, protocol: str, streak: int, money_level: int) -> int:
    """Exactly the formula from data/balance.json payout section."""
    if n <= 0:
        return 0
    ratio = clamp(time_left / timer_total, 0.0, 1.0) if timer_total > 0.0 else 1.0
    speed = float(PAYOUT["speed_base"]) + float(PAYOUT["speed_bonus"]) * ratio
    quality = float(PAYOUT["quality_base"]) + float(PAYOUT["quality_bonus"]) * clamp(quality_q, 0.0, 1.0)
    multi = 1.0 + float(PAYOUT["multi_step"]) * float(n - 1)
    protocol_mult = float(PAYOUT["protocol_mult"].get(str(protocol).upper(), 1.0))
    streak_mult = 1.0 + float(PAYOUT["streak_step"]) * float(min(10, max(0, streak)))
    money_mult = 1.0 + float(PAYOUT["money_mult_step"]) * float(money_level)
    value = (max(0.0, float(base_sum)) * speed * quality * multi
             * protocol_mult * streak_mult * money_mult)
    return int(math.floor(value + 0.5))


def attack_tier(hour: int) -> int:
    return int(clamp(1 + math.floor((max(1, hour) - 2) / 2.0), 1, 4))


# ---------------------------------------------------------------------------
# per-hour state
# ---------------------------------------------------------------------------

@dataclass
class FileRec:
    type: str
    cells: int
    req_id: Optional[int] = None


@dataclass
class PacketRec:
    type: str
    cells: int
    state: str = "waiting"       # waiting | loading
    timer: float = 0.0           # packet timer (20 s), only while waiting
    load_left: float = 0.0


@dataclass
class RequestRec:
    rid: int
    file_ids: list[int]
    types: list[str]
    state: str = "pending"       # pending | attaching | minigame | queued | sending
    spawn_t: float = 0.0
    timer_total: float = 30.0
    timer_left: float = 30.0
    attach_end: float = 0.0
    mini_end: float = 0.0
    send_start_left: float = 0.0
    send_left: float = 0.0
    protocol: str = "tcp"
    minigame: str = "dots"
    tier: int = 1


@dataclass
class HourRow:
    hour: int
    income: int
    payout_income: int
    recv_income: int
    attack_income: int
    target: int
    sla_end: float
    requests_done: int
    requests_failed: int
    packets_failed: int
    files_received: int
    files_sent: int
    files_left: int
    cells_occupied_peak: int
    cells_capacity: int
    cells_free_min: int
    attacks_blocked: int
    attacks_shielded: int
    attacks_failed: int
    spend: int
    busy_frac: float
    send_wait_sec: float
    channel_penalty: float
    cell_short_events: int
    slot_block_events: int
    spawn_pause_sec: float
    carry_out: int


@dataclass
class LotStat:
    spend: int = 0
    value: float = 0.0
    buys: int = 0
    first_hour: int = 0
    last_hour: int = 0
    levels: int = 0


# ---------------------------------------------------------------------------
# simulation
# ---------------------------------------------------------------------------

class Simulation:
    def __init__(self, seed: int) -> None:
        self.seed = seed
        self.rng = random.Random(seed)
        self.money = int(CONST.get("money_start", 50))
        self.sla = float(CONST.get("sla_start", 60))
        self.streak = 0
        self.hour = 1
        self.levels: dict[str, int] = {str(lot["id"]): 0 for lot in SHOP}
        self.lot_stats: dict[str, LotStat] = {str(lot["id"]): LotStat() for lot in SHOP}
        self.total_spent = 0
        self.folder_spend = 0
        self.earned = 0
        self.carry = 0
        self.stored_types: list[str] = []
        self.folders = 2
        self.offers: list[str] = []
        self.last_offers: list[str] = []
        self.last_seen: dict[str, int] = {}
        self.hourly: list[HourRow] = []
        self.defeated = False
        self.defeat_hour = 0
        self.attacks_blocked = 0
        self.attacks_failed = 0
        self.attacks_shielded = 0
        self.requests_done = 0
        self.requests_failed = 0
        self.files_received = 0
        self.files_sent = 0
        self.files_left_total = 0
        self.last_metrics: dict[str, float] = {
            "busy_frac": 0.0,
            "send_wait_sec": 0.0,
            "channel_penalty": 0.0,
            "timeouts": 0.0,
            "cell_short": 0.0,
            "income": 0.0,
            "sla_ratio": 1.0,
        }

    # --- derived stats ----------------------------------------------------
    def slot_limit(self) -> int:
        return int(clamp(1 + self.levels["lot_slots"], 1, int(CONST.get("slots_max", 5))))

    def lot_value(self, lot_id: str, fallback: float) -> float:
        return float(SHOP_BY_ID[lot_id].get("value", fallback))

    def transfer_speed_mult(self) -> float:
        cut = float(clamp(self.lot_value("lot_speed", 0.10), 0.01, 0.9))
        return float(1.0 - cut) ** self.levels["lot_speed"]

    def channel_capacity(self) -> float:
        return float(CONST.get("channel_capacity", 10)) + \
            self.lot_value("lot_channel", 6.0) * self.levels["lot_channel"]

    def buffer_limit(self) -> int:
        base = int(CONST.get("buffer_base", 6))
        step = int(self.lot_value("lot_channel", 1.0))
        return int(clamp(base + step * self.levels["lot_channel"],
                         base, int(CONST.get("buffer_max", 12))))

    def request_timer(self) -> float:
        base = float(CONST.get("request_timer", 30))
        return float(clamp(base + self.lot_value("lot_timer", 7.0) * self.levels["lot_timer"],
                           base, float(CONST.get("request_timer_max", 65))))

    def sla_cap(self) -> float:
        base = float(CONST.get("sla_base", 60))
        return float(clamp(base + self.lot_value("lot_sla", 40.0) * self.levels["lot_sla"],
                           base, MAX_SLA))

    def money_mult(self) -> float:
        return 1.0 + self.lot_value("lot_money", 0.05) * self.levels["lot_money"]

    def folder_cells(self) -> int:
        dims = GRID.get("folder_dims") or [[5, 4]]
        idx = int(clamp(self.levels["lot_folder"], 0, len(dims) - 1))
        pair = dims[idx]
        return int(pair[0]) * int(pair[1])

    def cell_capacity(self) -> int:
        return self.folders * self.folder_cells()

    def price(self, lot_id: str) -> int:
        lot = SHOP_BY_ID[lot_id]
        level = self.levels[lot_id]
        prices = lot["prices"]
        if level >= int(lot["max_level"]) or not prices:
            return -1
        return int(prices[int(clamp(level, 0, len(prices) - 1))])

    # --- prep -------------------------------------------------------------
    def prepare_folders(self, hour: int, files_budget: int, occupied: int = 0) -> None:
        """Competent player buys free folders for folder_new_cost (spec 2.1)."""
        weights = HOURS[hour]["type_weights"]
        avg_cells = sum(float(weights.get(t, 0.0)) * CELLS[t] for t in TYPE_ORDER)
        expected = occupied + files_budget * max(1.0, avg_cells) * 0.9
        cap = self.cell_capacity()
        max_folders = int(CONST.get("folders_max", 6))
        guard = 0
        while cap < expected * 1.15 and self.folders < max_folders and guard < 20:
            if FOLDER_NEW_COST > self.money:
                break
            self.money -= FOLDER_NEW_COST
            self.folder_spend += FOLDER_NEW_COST
            self.folders += 1
            cap = self.cell_capacity()
            guard += 1

    def generate_offers(self, hour: int) -> list[str]:
        pool = [lot for lot in SHOP if self.levels[str(lot["id"])] < int(lot["max_level"])]
        result: list[str] = []
        affordable_ok = False
        while len(result) < int(SHOP_RULES.get("offers", 3)) and pool:
            weights: list[float] = []
            for lot in pool:
                lot_id = str(lot["id"])
                idx = int(clamp(hour - 1, 0, len(lot["weight_by_hour"]) - 1))
                weight = float(lot["weight_by_hour"][idx])
                if lot_id in self.last_offers:
                    weight *= float(SHOP_RULES.get("last_offer_weight", 0.5))
                if lot_id in self.last_seen:
                    since = hour - int(self.last_seen[lot_id])
                    if since >= int(SHOP_RULES.get("pity_hours", 2)):
                        weight *= float(SHOP_RULES.get("pity_weight", 1.5))
                weights.append(max(0.0, weight))
            index = weighted_index(self.rng, [str(l["id"]) for l in pool], weights)
            result.append(str(pool[index]["id"]))
            pool.pop(index)

        # At least one affordable offer if such a lot exists.
        if result and not any(0 <= self.price(lid) <= self.money for lid in result):
            candidates = [lot for lot in SHOP
                          if self.levels[str(lot["id"])] < int(lot["max_level"])
                          and str(lot["id"]) not in result
                          and 0 <= self.price(str(lot["id"])) <= self.money]
            if candidates:
                candidates.sort(key=lambda lot: self.price(str(lot["id"])))
                swap = candidates[0]
                worst_id = max(result, key=lambda lid: self.price(lid))
                result[result.index(worst_id)] = str(swap["id"])

        self.last_offers = list(self.offers)
        self.offers = result
        for lot_id in result:
            self.last_seen[lot_id] = hour
        return result

    def projected_income(self, hour: int) -> float:
        remaining = sum(TARGETS[h] for h in range(hour, RUN_HOURS + 1))
        previous_target = TARGETS.get(hour - 1, 0.0)
        if previous_target > 0.0 and self.last_metrics["income"] > 0.0:
            scale = clamp(self.last_metrics["income"] / previous_target, 0.6, 1.4)
        else:
            scale = 1.0
        return remaining * scale

    def lot_value_estimate(self, lot_id: str, hour: int) -> float:
        """Deterministic marginal-value proxy in dollars, documented in report."""
        proj = self.projected_income(hour)
        hours_left = max(0, RUN_HOURS - hour + 1)
        effect = str(SHOP_BY_ID[lot_id]["effect"])
        level = self.levels[lot_id]
        busy = clamp(self.last_metrics["busy_frac"], 0.0, 1.0)
        wait_sec = max(0.0, self.last_metrics["send_wait_sec"])
        penalty = max(0.0, self.last_metrics["channel_penalty"])

        if effect == "money_mult":
            # Relative payout gain of the next level (shop[].value).
            step = self.lot_value("lot_money", 0.05)
            return step * proj / (1.0 + step * level)
        if effect == "transfer_speed":
            # 10% shorter transfers only matter when the pipe is the bottleneck.
            return self.lot_value("lot_speed", 0.10) * proj * busy * 0.5
        if effect == "connection_slots":
            base = 0.06 if wait_sec > 0.5 else 0.02
            return proj * base / (1.0 + 0.35 * (self.slot_limit() - 1))
        if effect == "channel_capacity":
            return proj * penalty * 0.5
        if effect == "request_timer":
            return proj * (0.10 if self.last_metrics["timeouts"] > 0.0 else 0.01)
        if effect == "folder_cells":
            return proj * (0.10 if self.last_metrics["cell_short"] > 0.0 else 0.002)
        if effect == "sla_cap":
            return proj * (0.12 if self.last_metrics["sla_ratio"] < 0.5 else 0.003)
        if effect == "shield_charge":
            # One auto-block per hour, shield_reward_scale of the reward, no penalty.
            remaining_attacks = sum(int(HOURS[h].get("attacks", 0))
                                    for h in range(hour, RUN_HOURS + 1))
            avg_fail = 25.0 + 5.0 * max(0, hour - 2) / 2.0
            return min(float(remaining_attacks), float(hours_left)) * \
                SHIELD_REWARD_SCALE * avg_fail
        return 0.0

    def buy_best_roi(self, hour: int, offers: list[str]) -> None:
        guard = 0
        threshold = FINAL_PREP_ROI_MIN if hour >= RUN_HOURS else PURCHASE_ROI_MIN
        while guard < 40:
            guard += 1
            best_id = ""
            best_roi = threshold
            best_value = 0.0
            for lot_id in offers:
                if self.levels[lot_id] >= int(SHOP_BY_ID[lot_id]["max_level"]):
                    continue
                price = self.price(lot_id)
                if price < 0 or price > self.money:
                    continue
                value = self.lot_value_estimate(lot_id, hour)
                roi = value / float(max(1, price))
                if roi > best_roi:
                    best_roi = roi
                    best_id = lot_id
                    best_value = value
            if not best_id:
                break
            price = self.price(best_id)
            value = best_value
            self.money -= price
            self.levels[best_id] += 1
            self.total_spent += price
            stat = self.lot_stats[best_id]
            stat.spend += price
            stat.value += value
            stat.buys += 1
            stat.levels = self.levels[best_id]
            stat.first_hour = stat.first_hour or hour
            stat.last_hour = hour

    # --- hour -------------------------------------------------------------
    def run_hour(self, hour: int) -> HourRow:
        self.hour = hour
        self.sla = min(self.sla_cap(), self.sla + SLA_REGEN)
        self.shield_charges = self.levels["lot_shield"]

        spend_before = self.total_spent
        if hour > 1:
            offers = self.generate_offers(hour)
            self.buy_best_roi(hour, offers)
        hour_spend = self.total_spent - spend_before

        hour_def = HOURS[hour]
        files_budget = min(MAX_FILES_PER_HOUR, int(hour_def["files"]) + self.carry)

        files: dict[int, FileRec] = {}
        next_file_id = 0
        for stored_type in self.stored_types:
            files[next_file_id] = FileRec(stored_type, CELLS.get(stored_type, 1))
            next_file_id += 1
        occupied = sum(file.cells for file in files.values())
        self.prepare_folders(hour, files_budget, occupied)

        request_cap = int(hour_def["request_cap"])
        active_limit = int(hour_def["active_requests"])
        type_weights = {str(k): float(v) for k, v in hour_def["type_weights"].items()}
        mix = {int(k): float(v) for k, v in hour_def["request_mix"].items()}
        attack_count = int(hour_def.get("attacks", 0))
        request_timer_total = self.request_timer()
        slots = self.slot_limit()
        buffer_limit = self.buffer_limit()
        capacity = self.cell_capacity()

        earned_start = self.earned
        done_start = self.requests_done
        received_start = self.files_received
        sent_start = self.files_sent
        blocked_start = self.attacks_blocked
        shielded_start = self.attacks_shielded
        attack_failed_start = self.attacks_failed

        packets: list[PacketRec] = []
        requests: list[RequestRec] = []
        out_queue: list[RequestRec] = []
        next_req_id = 0
        mode: Optional[RequestRec] = None

        cells_peak = occupied
        cells_free_min = capacity - occupied
        files_spawned = 0
        requests_spawned = 0
        next_spawn_t = 0.0
        spawn_interval = 225.0 / max(1, files_budget)
        if hour > 1:
            next_spawn_t = spawn_interval * self.rng.uniform(
                1.0 - SPAWN_JITTER, 1.0 + SPAWN_JITTER)
        request_accum = 0.0
        request_interval = max(0.5, float(hour_def.get("send_interval", 20.0)))

        attack_times = sorted(self.rng.uniform(60.0, 240.0) for _ in range(attack_count))
        attack_idx = 0
        last_attack_kind = ""

        busy_steps = 0
        total_steps = 0
        send_wait_sec = 0.0
        channel_penalty_sum = 0.0
        channel_penalty_steps = 0
        cell_short_events = 0
        slot_block_events = 0
        spawn_pause_sec = 0.0
        timeouts = 0
        packets_failed = 0
        payout_income = 0
        recv_income = 0
        attack_income = 0

        def active_slot_count() -> int:
            loading = sum(1 for p in packets if p.state == "loading")
            sending = sum(1 for r in requests if r.state == "sending")
            return loading + sending

        def channel_factor() -> float:
            load = 0.0
            for packet in packets:
                if packet.state == "loading":
                    load += TYPE_WEIGHT.get(packet.type, 0.0)
            for request in requests:
                if request.state != "sending":
                    continue
                for fid in request.file_ids:
                    if fid in files:
                        load += TYPE_WEIGHT.get(files[fid].type, 0.0)
            capacity_now = self.channel_capacity()
            if capacity_now <= 0.0:
                return 1.0
            return max(1.0, load / capacity_now)

        def release_request_files(request: RequestRec) -> None:
            for fid in request.file_ids:
                if fid in files:
                    files[fid].req_id = None

        def finish_request(request: RequestRec) -> None:
            nonlocal mode, payout_income, occupied
            if request.state == "sending":
                snapshot = request.send_start_left
                base_sum = sum(BASE_PAY.get(files[fid].type, 0.0)
                               for fid in request.file_ids if fid in files)
                value = payout(base_sum, len(request.file_ids), snapshot,
                               request.timer_total, Q_SEND, request.protocol,
                               self.streak, self.levels["lot_money"])
                self.money += value
                self.earned += value
                payout_income += value
                self.streak += 1
                self.requests_done += 1
                for fid in request.file_ids:
                    file = files.pop(fid, None)
                    if file is not None:
                        occupied -= file.cells
                request.file_ids.clear()
                self.files_sent += len(request.types)
            if mode is request:
                mode = None
            if request in requests:
                requests.remove(request)
            if request in out_queue:
                out_queue.remove(request)

        def timeout_request(request: RequestRec) -> None:
            nonlocal timeouts, mode
            release_request_files(request)
            self.sla = max(0.0, self.sla - (10.0 + 2.0 * hour))
            timeouts += 1
            self.requests_failed += 1
            if mode is request:
                mode = None
            if request in requests:
                requests.remove(request)
            if request in out_queue:
                out_queue.remove(request)

        def start_send(request: RequestRec, now: float) -> None:
            nonlocal mode
            factor = channel_factor()
            duration = 0.0
            for fid in request.file_ids:
                file = files.get(fid)
                if file is None:
                    continue
                duration += RECV_TIME.get(file.type, 3.0) * self.transfer_speed_mult() * factor
                if str(request.protocol).lower() == "udp":
                    duration *= float(PAYOUT.get("udp_time_mult", 0.8))
            if str(request.protocol).lower() == "tcp":
                # Production TCP: connection minigame before the send minigame.
                duration += TCP_CONNECT_SEC
                if self.rng.random() < TCP_CONNECT_FAIL:
                    self.sla = max(0.0, self.sla - TCP_CONNECT_FAIL_SLA)
            request.state = "sending"
            request.send_left = max(0.1, duration)
            request.send_start_left = request.timer_left
            if mode is request:
                mode = None

        def maybe_start_next_send() -> None:
            while out_queue and active_slot_count() < slots:
                request = out_queue.pop(0)
                if request not in requests:
                    continue
                start_send(request, 0.0)

        def pick_attack_kind() -> str:
            nonlocal last_attack_kind
            weights: list[float] = []
            kinds: list[str] = []
            for kind, cfg in ATTACKS["kinds"].items():
                idx = int(clamp(hour - 1, 0, len(cfg["weight_by_hour"]) - 1))
                weight = float(cfg["weight_by_hour"][idx])
                if weight <= 0.0:
                    continue
                kinds.append(kind)
                weights.append(weight)
            if not kinds:
                return ""
            if len(kinds) > 1 and last_attack_kind in kinds:
                weights[kinds.index(last_attack_kind)] = 0.0
            index = weighted_index(self.rng, kinds, weights)
            last_attack_kind = kinds[index]
            return kinds[index]

        def resolve_attack() -> None:
            nonlocal attack_income
            kind = pick_attack_kind()
            if not kind:
                return
            tier = attack_tier(hour)
            row = ATTACKS["kinds"][kind]["tiers"][tier - 1]
            if self.shield_charges > 0:
                self.shield_charges -= 1
                self.attacks_shielded += 1
                self.attacks_blocked += 1
                reward = int(round(float(row["reward_money"]) * SHIELD_REWARD_SCALE))
                reward_sla = float(row["reward_sla"]) * SHIELD_REWARD_SCALE
                self.money += reward
                self.earned += reward
                attack_income += reward
                self.sla = min(self.sla_cap(), self.sla + reward_sla)
                return
            threshold = float(row.get("threshold", 0.6))
            if Q_ATTACK >= threshold:
                reward = int(round(float(row["reward_money"])))
                self.money += reward
                self.earned += reward
                attack_income += reward
                self.sla = min(self.sla_cap(), self.sla + float(row["reward_sla"]))
                self.attacks_blocked += 1
            else:
                self.money = max(0, self.money + int(round(float(row["fail_money"]))))
                self.sla = max(0.0, self.sla + float(row["fail_sla"]))
                self.attacks_failed += 1

        steps = int(round(HOUR_SECONDS / DT))
        now = 0.0
        for step in range(steps):
            now = round((step + 1) * DT, 6)
            total_steps += 1
            modal = mode is not None and mode.state == "minigame"

            # 1. Player state machine (attach -> minigame -> send/queue).
            if mode is None:
                pending = [r for r in requests if r.state == "pending"]
                if pending:
                    request = min(pending, key=lambda r: r.timer_left)
                    request.state = "attaching"
                    request.attach_end = now + HUMAN_ATTACH_BASE + \
                        HUMAN_ATTACH_PER_FILE * len(request.file_ids)
                    mode = request
            if mode is not None and mode.state == "attaching" and now >= mode.attach_end:
                request = mode
                request.state = "minigame"
                request.mini_end = now + MINIGAME_BASE + MINIGAME_PER_TIER * (request.tier + 1)
            if mode is not None and mode.state == "minigame" and now >= mode.mini_end:
                request = mode
                mode = None
                if active_slot_count() < slots:
                    start_send(request, now)
                else:
                    request.state = "queued"
                    out_queue.append(request)

            # 2. Request timers (queued requests are frozen; the request that is
            #    currently in its own minigame is also frozen). Production ticks
            #    timers before send progress, so a deadline wins ties.
            for request in list(requests):
                if request.state in ("pending", "attaching", "sending"):
                    request.timer_left -= DT
                    if request.timer_left <= 0.0:
                        timeout_request(request)

            # 3. Sends progress even while a minigame modal is open (production
            #    ticks requests before the modal guard); packet loading does not.
            for request in list(requests):
                if request.state != "sending":
                    continue
                if request.send_left >= 1e9:
                    continue
                request.send_left -= DT
                if request.send_left <= 0.0:
                    finish_request(request)

            # 4. Receive progress and packet timers (paused by a minigame modal).
            if not modal:
                for packet in list(packets):
                    if packet.state == "loading":
                        packet.load_left -= DT
                        if packet.load_left <= 0.0:
                            packets.remove(packet)
                            file = FileRec(packet.type, packet.cells)
                            files[next_file_id] = file
                            next_file_id += 1
                            fee = int(RECV_FEE.get(packet.type, 0))
                            self.money += fee
                            self.earned += fee
                            recv_income += fee
                            self.files_received += 1
                    else:
                        packet.timer -= DT
                        if packet.timer <= 0.0:
                            packets.remove(packet)
                            occupied -= packet.cells
                            self.sla = max(0.0, self.sla - SLA_LOSS.get(packet.type, 2.0))
                            packets_failed += 1

            # 5. Spawn packets (75% of the hour, hold on full buffer).
            if not modal and files_spawned < files_budget and now <= 225.0:
                if files_spawned >= files_budget:
                    pass
                elif len(packets) >= buffer_limit:
                    spawn_pause_sec += DT
                elif now >= next_spawn_t:
                    packet_type = weighted_choice(self.rng, type_weights)
                    packets.append(PacketRec(packet_type, CELLS.get(packet_type, 1),
                                             timer=float(CONST.get("packet_timer", 20))))
                    files_spawned += 1
                    next_spawn_t = now + spawn_interval * self.rng.uniform(
                        1.0 - SPAWN_JITTER, 1.0 + SPAWN_JITTER)

            # 6. Competent player accepts packets while a slot and cells are free.
            if not modal:
                for packet in list(packets):
                    if packet.state != "waiting":
                        continue
                    if active_slot_count() >= slots:
                        slot_block_events += 1
                        break
                    if occupied + packet.cells > capacity:
                        cell_short_events += 1
                        continue
                    packet.state = "loading"
                    packet.load_left = RECV_TIME.get(packet.type, 3.0) * \
                        self.transfer_speed_mult() * channel_factor()
                    occupied += packet.cells
                    cells_peak = max(cells_peak, occupied)
                    cells_free_min = min(cells_free_min, capacity - occupied)

            # 6. Spawn requests (cap + active limit + available files).
            if not modal:
                if requests_spawned < request_cap and len(requests) < active_limit:
                    request_accum += DT
                    while request_accum >= request_interval:
                        request_accum -= request_interval
                        if requests_spawned >= request_cap or len(requests) >= active_limit:
                            break
                        available = [fid for fid, file in files.items() if file.req_id is None]
                        if not available:
                            continue
                        total_weight = sum(max(0.0, w) for w in mix.values())
                        if total_weight <= 0.0:
                            n = 1
                        else:
                            roll = self.rng.random() * total_weight
                            acc = 0.0
                            n = min(mix) if mix else 1
                            for key in sorted(mix):
                                acc += max(0.0, mix[key])
                                if roll < acc:
                                    n = key
                                    break
                        n = min(n, len(available))
                        if n <= 0:
                            continue
                        chosen = self.rng.sample(available, n)
                        for fid in chosen:
                            files[fid].req_id = next_req_id
                        types = [files[fid].type for fid in chosen]
                        selection = send_minigame_for(types)
                        request = RequestRec(
                            rid=next_req_id,
                            file_ids=chosen,
                            types=types,
                            spawn_t=now,
                            timer_total=request_timer_total,
                            timer_left=request_timer_total,
                            protocol=PROTOCOL,
                            minigame=str(selection["id"]),
                            tier=int(selection["tier"]),
                        )
                        requests.append(request)
                        requests_spawned += 1
                        next_req_id += 1
                else:
                    request_accum = 0.0

            # 7. Attacks (spawn window 60-240 s, paused while a modal is open).
            while not modal and attack_idx < len(attack_times) and now >= attack_times[attack_idx]:
                attack_idx += 1
                resolve_attack()

            # 8. Release waiting queues when a slot frees.
            maybe_start_next_send()

            # 9. Bookkeeping.
            if active_slot_count() > 0:
                busy_steps += 1
            if out_queue:
                send_wait_sec += DT
            factor = channel_factor()
            if factor > 1.0001:
                channel_penalty_sum += factor - 1.0
                channel_penalty_steps += 1

            self.money = max(0, self.money)
            if self.sla <= 0.0:
                self.defeated = True
                self.defeat_hour = hour
                break

        # End of hour: do not finish in-flight sends; count leftover files.
        self.carry = int(clamp(files_budget - files_spawned, 0, MAX_FILES_PER_HOUR))
        files_left = len(files)
        self.stored_types = [file.type for file in files.values()]
        self.files_left_total = len(self.stored_types)
        busy_frac = busy_steps / max(1, total_steps)
        channel_penalty = channel_penalty_sum / max(1, channel_penalty_steps)
        self.last_metrics = {
            "busy_frac": busy_frac,
            "send_wait_sec": send_wait_sec,
            "channel_penalty": channel_penalty,
            "timeouts": float(timeouts),
            "cell_short": float(cell_short_events),
            "income": float(self.earned - earned_start),
            "sla_ratio": self.sla / max(1.0, self.sla_cap()),
        }

        row = HourRow(
            hour=hour,
            income=self.earned - earned_start,
            payout_income=payout_income,
            recv_income=recv_income,
            attack_income=attack_income,
            target=int(TARGETS[hour]),
            sla_end=self.sla,
            requests_done=self.requests_done - done_start,
            requests_failed=timeouts,
            packets_failed=packets_failed,
            files_received=self.files_received - received_start,
            files_sent=self.files_sent - sent_start,
            files_left=files_left,
            cells_occupied_peak=cells_peak,
            cells_capacity=capacity,
            cells_free_min=max(0, cells_free_min),
            attacks_blocked=self.attacks_blocked - blocked_start,
            attacks_shielded=self.attacks_shielded - shielded_start,
            attacks_failed=self.attacks_failed - attack_failed_start,
            spend=hour_spend,
            busy_frac=busy_frac,
            send_wait_sec=send_wait_sec,
            channel_penalty=channel_penalty,
            cell_short_events=cell_short_events,
            slot_block_events=slot_block_events,
            spawn_pause_sec=spawn_pause_sec,
            carry_out=self.carry,
        )
        self.hourly.append(row)
        return row


# ---------------------------------------------------------------------------
# analytical check (B1)
# ---------------------------------------------------------------------------

def analytical_rows() -> list[dict[str, float]]:
    rows: list[dict[str, float]] = []
    for hour in range(1, RUN_HOURS + 1):
        hour_def = HOURS[hour]
        weights = {t: float(hour_def["type_weights"].get(t, 0.0)) for t in TYPE_ORDER}
        total_w = sum(weights.values()) or 1.0
        weights = {t: w / total_w for t, w in weights.items()}
        e_base = sum(weights[t] * BASE_PAY[t] for t in TYPE_ORDER)
        e_recv = sum(weights[t] * RECV_FEE[t] for t in TYPE_ORDER)
        e_cells = sum(weights[t] * CELLS[t] for t in TYPE_ORDER)
        mix = {int(k): float(v) for k, v in hour_def["request_mix"].items()}
        total_mix = sum(mix.values()) or 1.0
        e_n = sum(n * p / total_mix for n, p in mix.items())
        files_budget = int(hour_def["files"])
        cap = int(hour_def["request_cap"])
        reqs_by_files = math.floor(files_budget / max(0.001, e_n))
        effective_reqs = min(cap, reqs_by_files)
        expected_base = effective_reqs * e_n * e_base
        expected_recv = files_budget * e_recv
        allowed = [t for t in TYPE_ORDER if weights.get(t, 0.0) > 0.0]
        max_base_file = max(BASE_PAY[t] for t in allowed)
        max_recv_file = max(RECV_FEE[t] for t in allowed)
        # Upper bound: request cap x 4 files, limited by the hour file budget.
        max_files = min(files_budget, cap * 4)
        max_base = max_files * max_base_file
        max_income = max_base * 1.4 + max_files * max_recv_file
        rows.append({
            "hour": hour,
            "files": files_budget,
            "cap": cap,
            "active": int(hour_def["active_requests"]),
            "e_n": e_n,
            "e_base_file": e_base,
            "e_base_req": e_n * e_base,
            "e_cells": e_cells,
            "effective_reqs": effective_reqs,
            "expected_base": expected_base,
            "expected_recv": expected_recv,
            "expected_115": expected_base * 1.15 + expected_recv,
            "expected_125": expected_base * 1.25 + expected_recv,
            "expected_140": expected_base * 1.40 + expected_recv,
            "max_base": max_base,
            "max_income": max_income,
            "target": TARGETS[hour],
            "low": TARGETS[hour] * (1.0 - CHECK_TOL),
            "high": TARGETS[hour] * (1.0 + CHECK_TOL),
        })
    return rows


# ---------------------------------------------------------------------------
# run + report
# ---------------------------------------------------------------------------

def run_seeds(seeds: int) -> list[Simulation]:
    runs: list[Simulation] = []
    for seed in range(1, seeds + 1):
        sim = Simulation(seed)
        for hour in range(1, RUN_HOURS + 1):
            sim.run_hour(hour)
            if sim.defeated:
                break
        runs.append(sim)
    return runs


def fmt_money(value: float) -> str:
    return f"{value:,.0f}".replace(",", " ")


def suggested_caps(hour_means: dict[int, float]) -> dict[int, int]:
    """Linear cap correction for every hour outside +/-20%."""
    caps: dict[int, int] = {}
    for hour in range(1, RUN_HOURS + 1):
        cap = int(HOURS[hour]["request_cap"])
        mean = hour_means.get(hour)
        if not mean:
            caps[hour] = cap
            continue
        if abs(mean - TARGETS[hour]) / TARGETS[hour] > CHECK_TOL:
            cap = int(clamp(round(cap * TARGETS[hour] / max(1.0, mean)), 1,
                            int(HOURS[hour]["files"])))
        caps[hour] = cap
    return caps


def project_caps(caps: dict[int, int], seeds: int = 100) -> dict[str, object]:
    """Refine caps in memory (2-3 passes); never writes balance.json."""
    current = dict(caps)
    last: dict[str, object] = {}
    for _ in range(6):
        saved = {hour: int(HOURS[hour]["request_cap"]) for hour in range(1, RUN_HOURS + 1)}
        try:
            for hour, cap in current.items():
                HOURS[hour]["request_cap"] = int(cap)
            runs = run_seeds(seeds)
        finally:
            for hour, cap in saved.items():
                HOURS[hour]["request_cap"] = cap
        means: dict[int, float] = {}
        for hour in range(1, RUN_HOURS + 1):
            incomes = [float(r.income) for sim in runs for r in sim.hourly if r.hour == hour]
            means[hour] = statistics.fmean(incomes) if incomes else 0.0
        total = statistics.fmean([sum(r.income for r in sim.hourly) for sim in runs])
        spend = statistics.fmean([sim.total_spent for sim in runs])
        last = {"means": means, "total": total, "spend": spend, "seeds": seeds,
                "caps": dict(current)}
        changed = False
        for hour in range(2, RUN_HOURS + 1):
            mean = means[hour]
            if mean <= 0.0:
                continue
            target = TARGETS[hour]
            if abs(mean - target) / target <= CHECK_TOL:
                continue
            new_cap = int(clamp(round(current[hour] * target / mean), 1,
                                int(HOURS[hour]["files"])))
            if new_cap != current[hour]:
                current[hour] = new_cap
                changed = True
        if not changed:
            break
    last["caps"] = dict(current)
    return last


def build_report(runs: list[Simulation], analytical: list[dict[str, float]],
                 projection: Optional[dict[str, object]] = None,
                 caps: Optional[dict[int, int]] = None) -> tuple[str, bool]:
    lines: list[str] = []
    failures: list[str] = []

    per_hour: dict[int, list[HourRow]] = defaultdict(list)
    for sim in runs:
        for row in sim.hourly:
            per_hour[row.hour].append(row)

    lines.append("# PEAK HOUR v3 - balance simulation report")
    lines.append("")
    lines.append(f"Generated by `tests/sim_balance.py` from `data/balance.json`.")
    lines.append(f"Seeds: **{len(runs)}**, hours: **{RUN_HOURS}**, dt: **{DT} s**, "
                 f"send quality q=**{Q_SEND}**, attack quality q=**{Q_ATTACK}**, "
                 f"protocol: **{PROTOCOL.upper()}**.")
    lines.append("")
    lines.append("## Model assumptions")
    lines.append("")
    lines.append("- Spawn: file budget from `hours[].files` (+ carry), spawn only during "
                 "75% of the hour (225 s), interval 225/budget with +/-20% jitter; H1 "
                 "spawns its first packet at t=0. A full buffer freezes spawns without "
                 "burning the budget.")
    lines.append("- Types: `hours[].type_weights` only; zero weight never spawns.")
    lines.append("- Unsent files persist across hours (the folder is not cleared); only "
                 "files consumed by a successful send disappear. Unspawned budget is carried "
                 "separately, capped at 20 files/hour.")
    lines.append("- Requests: `request_cap` and `active_requests` from `hours[]`; "
                 "interval `hours[].send_interval`; count from `request_mix`; a request "
                 "reserves available files at spawn and does not consume request budget "
                 "when no files exist.")
    lines.append(f"- Player: competent, attaches after {HUMAN_ATTACH_BASE:g} s + "
                 f"{HUMAN_ATTACH_PER_FILE:g} s/file, plays a no-timer send minigame for "
                 f"{MINIGAME_BASE:g} + {MINIGAME_PER_TIER:g}*(tier+1) seconds "
                 f"(3 tiers). TCP adds {TCP_CONNECT_SEC:g} s connection time and "
                 f"{TCP_CONNECT_FAIL * 100:.0f}% of attempts miss it "
                 f"(-{TCP_CONNECT_FAIL_SLA:g} SLA). "
                 "The minigame pauses packet spawn/loading but not other request timers "
                 "(production order).")
    lines.append("- Timers: request `30 + 7*timer_level` (cap 65), packet 20 s. "
                 "Timers pause in the player's own minigame and in the out-slot queue; "
                 "payout uses `time_left` snapshotted at send start.")
    lines.append("- Transfers: `base_time_sec * 0.90^speed_level * max(1, load/capacity)`; "
                 "slots are shared by receive and send; files are consumed on successful send.")
    lines.append("- Payout: exact `round(base_sum * speed * quality * multi * protocol * "
                 "streak * money_mult)`; TCP x1.15, UDP x0.85; recv_fee is added on receive "
                 "and is not multiplied.")
    lines.append("- Folder: `grid.folder_dims[folder_level]`, 2 free folders at start; "
                 f"each extra folder costs `constants.folder_new_cost` ({FOLDER_NEW_COST} $) "
                 "in prep, up to `constants.folders_max` (6). `lot_folder` buys more cells; "
                 "fragmentation is not modelled, cell capacity/occupancy is.")
    lines.append("- Shop: 3 weighted offers after each hour, `last_offer` x0.5, pity x1.5, "
                 "no rerolls (locks are irrelevant), at least one affordable offer; buy the "
                 "best affordable predicted-ROI lot while ROI >= 0.5 before H9, and any "
                 "positive ROI in the final prep (there is no shop after H9).")
    lines.append("- ROI proxy: `money` = next `shop[].value` step of projected remaining "
                 "income; `slots`/`speed`/`channel`/`timer`/`folder`/`sla`/`shield` use "
                 "measured bottlenecks from the previous hour. It is deterministic, not an "
                 "oracle.")
    lines.append("")
    lines.append("## Analytical check (B1)")
    lines.append("")
    lines.append("Expected base_sum assumes the full `request_cap` is reachable and the "
                 "request mix/type weights are independent. `max income` is the hard upper "
                 "bound (cap x 4 files, best allowed type, multiplier 1.4, recv fees).")
    lines.append("")
    lines.append("| H | files | cap | act | E[n] | E[base/file] | E[base/req] | eff.reqs | "
                 "E[base] | E[payout@1.15] | @1.25 | @1.40 | max base | max income | target | verdict |")
    lines.append("|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|")
    for row in analytical:
        target = row["target"]
        if row["max_income"] < target:
            verdict = "CAP<TARGET"
            failures.append(
                f"analytical max income H{int(row['hour'])} {row['max_income']:.0f} < target {target:.0f}")
        elif row["expected_115"] < target * (1.0 - CHECK_TOL):
            verdict = "expected low"
        elif row["expected_115"] > target * (1.0 + CHECK_TOL):
            verdict = "expected high"
        elif row["expected_140"] > target * 2.0:
            verdict = "headroom high"
        else:
            verdict = "ok"
        lines.append(
            f"| {int(row['hour'])} | {int(row['files'])} | {int(row['cap'])} | "
            f"{int(row['active'])} | {row['e_n']:.2f} | {row['e_base_file']:.1f} | "
            f"{row['e_base_req']:.1f} | {row['effective_reqs']} | {row['expected_base']:.0f} | "
            f"{row['expected_115']:.0f} | {row['expected_125']:.0f} | {row['expected_140']:.0f} | "
            f"{row['max_base']:.0f} | {row['max_income']:.0f} | {target:.0f} | {verdict} |")
    lines.append("")

    # --- simulation table -------------------------------------------------
    lines.append("## Simulation: per-hour income")
    lines.append("")
    lines.append("| H | target | mean | median | P10 | P90 | dev | done | failed | "
                 "files sent/left | cells peak/cap/free | SLA end | attacks B/F | spend | verdict |")
    lines.append("|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|")
    hour_stats: dict[int, dict[str, float]] = {}
    for hour in range(1, RUN_HOURS + 1):
        rows = per_hour.get(hour, [])
        if not rows:
            continue
        incomes = [float(r.income) for r in rows]
        mean = statistics.fmean(incomes)
        median = statistics.median(incomes)
        p10 = percentile(incomes, 0.10)
        p90 = percentile(incomes, 0.90)
        target = float(TARGETS[hour])
        dev = (mean - target) / target * 100.0
        ok = abs(dev) <= CHECK_TOL * 100.0
        if not ok:
            failures.append(f"H{hour} mean {mean:.0f} vs target {target:.0f} ({dev:+.1f}%)")
        hour_stats[hour] = {
            "mean": mean, "median": median, "p10": p10, "p90": p90,
            "dev": dev, "target": target, "ok": 1.0 if ok else 0.0,
        }
        lines.append(
            f"| {hour} | {target:.0f} | {fmt_money(mean)} | {fmt_money(median)} | "
            f"{fmt_money(p10)} | {fmt_money(p90)} | {dev:+.1f}% | "
            f"{statistics.fmean([r.requests_done for r in rows]):.1f} | "
            f"{statistics.fmean([r.requests_failed for r in rows]):.1f} | "
            f"{statistics.fmean([r.files_sent for r in rows]):.1f}/"
            f"{statistics.fmean([r.files_left for r in rows]):.1f} | "
            f"{statistics.fmean([r.cells_occupied_peak for r in rows]):.0f}/"
            f"{statistics.fmean([r.cells_capacity for r in rows]):.0f}/"
            f"{statistics.fmean([r.cells_free_min for r in rows]):.0f} | "
            f"{statistics.fmean([r.sla_end for r in rows]):.0f} | "
            f"{statistics.fmean([r.attacks_blocked for r in rows]):.1f}/"
            f"{statistics.fmean([r.attacks_failed for r in rows]):.1f} | "
            f"{statistics.fmean([r.spend for r in rows]):.0f} | "
            f"{'PASS' if ok else 'FAIL'} |")
    lines.append("")
    lines.append("`spend` is the gold spent in the prep before that hour; H9 is the final "
                 "prep, where the policy spends on any positive ROI because no shop follows.")
    lines.append("")

    # --- totals -----------------------------------------------------------
    total_income = statistics.fmean([sum(r.income for r in sim.hourly) for sim in runs])
    total_payout = statistics.fmean([sum(r.payout_income for r in sim.hourly) for sim in runs])
    total_recv = statistics.fmean([sum(r.recv_income for r in sim.hourly) for sim in runs])
    total_attack = statistics.fmean([sum(r.attack_income for r in sim.hourly) for sim in runs])
    total_spent = statistics.fmean([sim.total_spent for sim in runs])
    folder_spend = statistics.fmean([sim.folder_spend for sim in runs])
    money_end = statistics.fmean([sim.money for sim in runs])
    total_done = statistics.fmean([sim.requests_done for sim in runs])
    total_received = statistics.fmean([sim.files_received for sim in runs])
    total_sent = statistics.fmean([sim.files_sent for sim in runs])
    total_left = statistics.fmean([sim.files_left_total for sim in runs])
    sla_end = statistics.fmean([sim.hourly[-1].sla_end for sim in runs if sim.hourly])
    defeated = sum(1 for sim in runs if sim.defeated)
    attacks_blocked = statistics.fmean([sim.attacks_blocked for sim in runs])
    attacks_failed = statistics.fmean([sim.attacks_failed for sim in runs])
    attacks_shielded = statistics.fmean([sim.attacks_shielded for sim in runs])
    tree_pct = total_spent / TOTAL_TREE * 100.0

    lines.append("## Run totals")
    lines.append("")
    lines.append(f"- Mean total income: **{fmt_money(total_income)} $** "
                 f"(payout {fmt_money(total_payout)} + recv_fee {fmt_money(total_recv)} "
                 f"+ attacks {fmt_money(total_attack)}). Spec band: {BAND_TEXT} $.")
    lines.append(f"- Mean shop spend: **{fmt_money(total_spent)} $** = "
                 f"**{tree_pct:.1f}%** of the {fmt_money(TOTAL_TREE)} $ tree (target 55-65%). "
                 f"Mean money left after H9: **{fmt_money(money_end)} $**. "
                 f"Mean folder spend: **{fmt_money(folder_spend)} $**.")
    lines.append(f"- Mean requests done: **{total_done:.1f}**; files received "
                 f"**{total_received:.1f}**, sent **{total_sent:.1f}**, left unsent "
                 f"**{total_left:.1f}**.")
    lines.append(f"- Mean SLA at end of H9: **{sla_end:.1f}**; defeated runs: **{defeated}**.")
    lines.append(f"- Attacks blocked/failed/shielded per run: "
                 f"**{attacks_blocked:.1f}/{attacks_failed:.1f}/{attacks_shielded:.1f}**.")
    lines.append("")

    # --- purchases --------------------------------------------------------
    lines.append("## Purchases and ROI proxy")
    lines.append("")
    lines.append("| lot | effect | levels | buys | spend | value proxy | ROI | share of spend |")
    lines.append("|---|---|---:|---:|---:|---:|---:|---:|")
    lot_totals = []
    for lot in SHOP:
        lot_id = str(lot["id"])
        spend = sum(sim.lot_stats[lot_id].spend for sim in runs)
        value = sum(sim.lot_stats[lot_id].value for sim in runs)
        buys = sum(sim.lot_stats[lot_id].buys for sim in runs)
        levels = statistics.fmean([sim.levels[lot_id] for sim in runs])
        roi = value / spend if spend > 0 else 0.0
        share = spend / max(1.0, sum(s.total_spent for s in runs)) * 100.0
        lot_totals.append((lot_id, str(lot["effect"]), levels, buys, spend, value, roi, share))
    lot_totals.sort(key=lambda x: -x[4])
    for lot_id, effect, levels, buys, spend, value, roi, share in lot_totals:
        lines.append(f"| {lot_id} | {effect} | {levels:.1f} | {buys / len(runs):.1f} | "
                     f"{fmt_money(spend / len(runs))} | {fmt_money(value / len(runs))} | "
                     f"{roi:.2f} | {share:.1f}% |")
    lines.append("")

    # --- tuning -----------------------------------------------------------
    lines.append("## Tuning recommendations (not applied)")
    lines.append("")
    if not failures:
        lines.append("- No blockers: every hour mean is inside +/-20% and every analytical "
                     "maximum cap is at least its target.")
    else:
        lines.append("### Hourly income / caps")
        lines.append("")
        for hour in range(1, RUN_HOURS + 1):
            stats = hour_stats.get(hour)
            if not stats or stats["ok"]:
                continue
            cap = int(HOURS[hour]["request_cap"])
            mean = stats["mean"]
            target = stats["target"]
            suggested = int(clamp(round(cap * target / max(1.0, mean)), 1,
                                  int(HOURS[hour]["files"])))
            if caps:
                suggested = int(caps.get(hour, suggested))
            direction = "lower" if mean > target else "raise"
            lines.append(f"- **H{hour}**: mean {mean:.0f} $ vs target {target:.0f} $ "
                         f"({stats['dev']:+.1f}%). Suggest {direction} `request_cap` "
                         f"{cap} -> **{suggested}** (spec 2.4 reference cap: "
                         f"{[2, 3, 4, 5, 6, 7, 8, 9, 10][hour - 1]}).")
        lines.append("")
        lines.append("### Early request caps H2-H4 (B2)")
        early = [h for h in (2, 3, 4) if hour_stats.get(h) and not hour_stats[h]["ok"]]
        if early:
            if caps:
                local_caps = {h: int(caps[h]) for h in range(1, RUN_HOURS + 1)}
            else:
                local_caps = {h: int(HOURS[h]["request_cap"]) for h in range(1, RUN_HOURS + 1)}
                for h in range(2, RUN_HOURS + 1):
                    stats = hour_stats.get(h)
                    if not stats or stats["ok"]:
                        continue
                    local_caps[h] = int(clamp(
                        round(local_caps[h] * TARGETS[h] / max(1.0, stats["mean"])), 1,
                        int(HOURS[h]["files"])))
            lines.append("- Current data caps: " + ", ".join(
                f"H{h}={int(HOURS[h]['request_cap'])}" for h in range(1, RUN_HOURS + 1)) + ".")
            lines.append("- Suggested caps from this run: " + ", ".join(
                f"H{h}={local_caps[h]}" for h in range(1, RUN_HOURS + 1)) + ".")
            lines.append("- H2-H4 caps are the numbers from `hours[].request_cap`; the "
                         "simulated means above show whether the spec reference caps "
                         "[2, 3, 4, 5, 6, 7, 8, 9, 10] should be revisited.")
        else:
            lines.append("- H2-H4 are inside +/-20%; no early-cap change required by this run.")
        lines.append("")
        if total_income < BAND_LOW or total_income > BAND_HIGH:
            cap_failures = [h for h in hour_stats if not hour_stats[h]["ok"]]
            if cap_failures:
                lines.append(f"- Total income {total_income:.0f} $ is outside {BAND_TEXT} $, "
                             "but most of the gap is explained by the hourly caps above. "
                             "Re-run after applying those caps before touching `base_pay`.")
            else:
                scale = (BAND_LOW + BAND_HIGH) * 0.5 / max(1.0, total_income)
                lines.append(f"- Total income {total_income:.0f} $ is outside {BAND_TEXT} $. "
                             f"Global `base_pay` scale for the band: **x{scale:.2f}** "
                             f"(or adjust `income_target` instead).")
        if tree_pct < 55.0 or tree_pct > 65.0:
            h9_income = statistics.fmean([r.income for sim in runs
                                          for r in sim.hourly if r.hour == RUN_HOURS])
            ceiling = (total_income - h9_income + int(CONST.get("money_start", 50))) / \
                TOTAL_TREE * 100.0
            lines.append(f"- Shop spend is {tree_pct:.1f}% of the tree (target 55-65%). "
                         f"Arithmetic ceiling before H9: **{ceiling:.1f}%** "
                         "(H9 income cannot be spent). "
                         + ("The 55-65% expectation is unreachable without a post-H9 shop "
                            "or higher H1-H8 income." if ceiling < 55.0
                            else "The target is reachable only near this ceiling."))
        lines.append("")

    # Money lot front-loading check.
    money = next((row for row in lot_totals if row[0] == "lot_money"), None)
    if money and money[6] > 1.5:
        lines.append("### Money lot price curve")
        lines.append("")
        lines.append(f"- `lot_money` ROI proxy is **{money[6]:.2f}** and it takes "
                     f"**{money[7]:.1f}%** of spend. The early prices are front-loaded: "
                     "one `+money_mult` step of remaining income is worth more than the "
                     "first levels cost. This is a recommendation only.")
        lines.append("")

    # Dead-lot checks.
    dead = [row for row in lot_totals
            if row[6] < 0.35 and row[1] != "money_mult" and row[4] > 0]
    if dead:
        lines.append("### Weak lots")
        lines.append("")
        lines.append("These lots are bought only by the final-prep money dump "
                     "(no shop after H9), so their spend is not evidence of value.")
        lines.append("")
        for lot_id, effect, levels, _buys, _spend, _value, roi, _share in dead:
            if effect == "folder_cells":
                hint = ("Each extra folder costs folder_new_cost and the lot raises the "
                        "cell ceiling; check whether cells are actually the bottleneck.")
            elif effect == "sla_cap":
                hint = (f"SLA binds only in {defeated}/{len(runs)} runs. Either lower the "
                        "price/raise the effect or make timeouts hurt more.")
            elif effect == "shield_charge":
                hint = ("q=0.85 clears every attack threshold, so auto-blocks only add "
                        f"{SHIELD_REWARD_SCALE * 100:.0f}% rewards. Lower the price or raise "
                        "attack rewards/fail costs.")
            else:
                hint = "Strengthen the effect or lower the price."
            lines.append(f"- `{lot_id}` ({effect}): mean level {levels:.2f}, ROI {roi:.2f}. "
                         + hint)
        lines.append("")

    best = max(lot_totals, key=lambda row: row[6]) if lot_totals else None
    if best and best[0] != "lot_money" and best[6] > 1.5:
        lines.append("### Best ROI is not the money lot")
        lines.append("")
        lines.append(f"- Best ROI proxy is `{best[0]}` ({best[1]}) at **{best[6]:.2f}**, "
                     f"spend share {best[7]:.1f}%. `lot_money` is not the primary lever in "
                     "this model, so a money-price change alone will not fix the tree "
                     "coverage; check channel/slot/speed prices too.")
        money_row = next((row for row in lot_totals if row[0] == "lot_money"), None)
        if money_row:
            lines.append(f"- `lot_money` ROI is **{money_row[6]:.2f}** "
                         f"(spend share {money_row[7]:.1f}%). It is a good buy but not "
                         "front-loaded enough to justify a new price curve from this run.")
        lines.append("")

    if projection and caps:
        lines.append("## Projection after recommended caps (in-memory, no data edit)")
        lines.append("")
        lines.append("Suggested `request_cap` vector: **[" +
                     ", ".join(str(caps[h]) for h in range(1, RUN_HOURS + 1)) + "]**; "
                     f"Projection seeds: {projection['seeds']}.")
        lines.append("")
        lines.append("| H | current cap | suggested cap | projected mean | target | dev | verdict |")
        lines.append("|---:|---:|---:|---:|---:|---:|---|")
        for hour in range(1, RUN_HOURS + 1):
            mean = float(projection["means"].get(hour, 0.0))
            target_disp = TARGETS[hour]
            dev = (mean - target_disp) / target_disp * 100.0
            ok = abs(dev) <= CHECK_TOL * 100.0
            target_text = f"{target_disp:.0f}"
            lines.append(f"| {hour} | {int(HOURS[hour]['request_cap'])} | {caps[hour]} | "
                         f"{fmt_money(mean)} | {target_text} | {dev:+.1f}% | "
                         f"{'PASS' if ok else 'FAIL'} |")
        lines.append("")
        lines.append(f"Projected total income: **{fmt_money(float(projection['total']))} $**; "
                     f"projected shop spend: **{fmt_money(float(projection['spend']))} $** "
                     f"({float(projection['spend']) / TOTAL_TREE * 100.0:.1f}% of the tree).")
        proj_h9 = float(projection["means"].get(RUN_HOURS, 0.0))
        proj_ceiling = (float(projection["total"]) - proj_h9 +
                        int(CONST.get("money_start", 50))) / TOTAL_TREE * 100.0
        lines.append(f"Pre-H9 spend ceiling at this income: **{proj_ceiling:.1f}%** of the "
                     "tree. " + ("The 55-65% target is therefore unreachable without a "
                                 "post-H9 shop or higher H1-H8 income."
                                 if proj_ceiling < 55.0 else
                                 "55-65% is reachable only near this ceiling."))
        lines.append("Note: recommended H9 cap can be lower than H8 because unsent files "
                     "persist across hours and raise the effective supply in H9.")
        if BAND_LOW <= float(projection["total"]) <= BAND_HIGH:
            lines.append(f"The projected total is inside the {BAND_TEXT} $ band.")
        lines.append("")

    lines.append("## Verdict")
    lines.append("")
    if failures:
        lines.append("**FAIL** - the following blockers were detected:")
        lines.append("")
        for failure in failures:
            lines.append(f"- {failure}")
        if projection:
            projected_ok = all(
                abs(float(projection["means"].get(h, 0.0)) - TARGETS[h]) /
                TARGETS[h] <= CHECK_TOL
                for h in range(1, RUN_HOURS + 1))
            if projected_ok and BAND_LOW <= float(projection["total"]) <= BAND_HIGH:
                lines.append("")
                lines.append("The in-memory projection with the recommended caps "
                             "passes all nine hours and lands in the income band. "
                             "No data file was modified.")
    else:
        lines.append("**PASS** - every hour is inside +/-20% and no analytical cap is below "
                     "its target.")
    lines.append("")
    return "\n".join(lines), not failures


def main() -> int:
    print("PEAK HOUR v3 - balance simulation (no Godot)")
    print(f"data: {BALANCE_PATH}")
    print(f"seeds: {SEEDS}, hours: {RUN_HOURS}, dt: {DT}s, "
          f"q_send={Q_SEND}, q_attack={Q_ATTACK}, protocol={PROTOCOL.upper()}")
    print("")

    analytical = analytical_rows()
    header = ("H | files | cap | E[base] | @1.15 | @1.25 | @1.40 | max | target | verdict")
    print(header)
    print("-" * len(header))
    for row in analytical:
        target = row["target"]
        if row["max_income"] < target:
            verdict = "CAP<TARGET"
        elif row["expected_115"] < target * (1.0 - CHECK_TOL):
            verdict = "expected low"
        elif row["expected_115"] > target * (1.0 + CHECK_TOL):
            verdict = "expected high"
        elif row["expected_140"] > target * 2.0:
            verdict = "headroom high"
        else:
            verdict = "ok"
        print(f"{int(row['hour']):>1} | {int(row['files']):>5} | {int(row['cap']):>3} | "
              f"{row['expected_base']:>7.0f} | {row['expected_115']:>5.0f} | "
              f"{row['expected_125']:>5.0f} | {row['expected_140']:>5.0f} | "
              f"{row['max_income']:>4.0f} | {target:>6.0f} | {verdict}")
    print("")

    runs = run_seeds(SEEDS)

    per_hour: dict[int, list[HourRow]] = defaultdict(list)
    for sim in runs:
        for row in sim.hourly:
            per_hour[row.hour].append(row)

    print("H |  target |    mean |  median |     P10 |     P90 |    dev | done | fail | "
          "sent/left | cells peak/cap/free | SLA | atk B/F | spend | verdict")
    print("-" * 132)
    failures: list[str] = []
    hour_means: dict[int, float] = {}
    for hour in range(1, RUN_HOURS + 1):
        rows = per_hour.get(hour, [])
        if not rows:
            continue
        incomes = [float(r.income) for r in rows]
        mean = statistics.fmean(incomes)
        median = statistics.median(incomes)
        p10 = percentile(incomes, 0.10)
        p90 = percentile(incomes, 0.90)
        target = float(TARGETS[hour])
        dev = (mean - target) / target * 100.0
        ok = abs(dev) <= CHECK_TOL * 100.0
        hour_means[hour] = mean
        if not ok:
            failures.append(f"H{hour} mean {mean:.0f} vs target {target:.0f} ({dev:+.1f}%)")
        print(f"{hour:>1} | {target:>7.0f} | {mean:>7.0f} | {median:>7.0f} | "
              f"{p10:>7.0f} | {p90:>7.0f} | {dev:>+6.1f}% | "
              f"{statistics.fmean([r.requests_done for r in rows]):>4.1f} | "
              f"{statistics.fmean([r.requests_failed for r in rows]):>4.1f} | "
              f"{statistics.fmean([r.files_sent for r in rows]):>4.1f}/"
              f"{statistics.fmean([r.files_left for r in rows]):<4.1f} | "
              f"{statistics.fmean([r.cells_occupied_peak for r in rows]):>4.0f}/"
              f"{statistics.fmean([r.cells_capacity for r in rows]):<4.0f}/"
              f"{statistics.fmean([r.cells_free_min for r in rows]):<4.0f} | "
              f"{statistics.fmean([r.sla_end for r in rows]):>3.0f} | "
              f"{statistics.fmean([r.attacks_blocked for r in rows]):>4.1f}/"
              f"{statistics.fmean([r.attacks_failed for r in rows]):<4.1f} | "
              f"{statistics.fmean([r.spend for r in rows]):>5.0f} | "
              f"{'PASS' if ok else 'FAIL'}")

    total_income = statistics.fmean([sum(r.income for r in sim.hourly) for sim in runs])
    total_spent = statistics.fmean([sim.total_spent for sim in runs])
    folder_spend = statistics.fmean([sim.folder_spend for sim in runs])
    money_end = statistics.fmean([sim.money for sim in runs])
    total_done = statistics.fmean([sim.requests_done for sim in runs])
    total_received = statistics.fmean([sim.files_received for sim in runs])
    total_sent = statistics.fmean([sim.files_sent for sim in runs])
    total_left = statistics.fmean([sim.files_left_total for sim in runs])
    sla_end = statistics.fmean([sim.hourly[-1].sla_end for sim in runs if sim.hourly])
    defeated = sum(1 for sim in runs if sim.defeated)
    attacks_blocked = statistics.fmean([sim.attacks_blocked for sim in runs])
    attacks_failed = statistics.fmean([sim.attacks_failed for sim in runs])
    attacks_shielded = statistics.fmean([sim.attacks_shielded for sim in runs])
    tree_pct = total_spent / TOTAL_TREE * 100.0
    print("")
    print(f"total income: {total_income:.0f} $ (spec {BAND_TEXT})")
    print(f"shop spend:   {total_spent:.0f} $ = {tree_pct:.1f}% of {TOTAL_TREE} $ tree "
          f"(target 55-65%); folder spend {folder_spend:.0f} $; money left {money_end:.0f} $")
    print(f"requests done: {total_done:.1f}; files received {total_received:.1f}, "
          f"sent {total_sent:.1f}, left unsent {total_left:.1f}")
    print(f"SLA end: {sla_end:.1f}; defeated runs: {defeated}")
    print(f"attacks blocked/failed/shielded: {attacks_blocked:.1f}/"
          f"{attacks_failed:.1f}/{attacks_shielded:.1f}")
    print("")

    caps: Optional[dict[int, int]] = None
    projection: Optional[dict[str, object]] = None
    if failures:
        caps = suggested_caps(hour_means)
        projection = project_caps(caps, 100)
        caps = projection["caps"]
        print("PROJECTION after recommended caps (100 seeds, data untouched)")
        print("  caps: " + ", ".join(f"H{h}={caps[h]}" for h in range(1, RUN_HOURS + 1)))
        for hour in range(1, RUN_HOURS + 1):
            mean = float(projection["means"].get(hour, 0.0))
            target_disp = TARGETS[hour]
            dev = (mean - target_disp) / target_disp * 100.0
            ok = abs(dev) <= CHECK_TOL * 100.0
            print(f"  H{hour}: mean {mean:.0f} vs target {target_disp:.0f}"
                  f" ({dev:+.1f}%) {'PASS' if ok else 'FAIL'}")
        print(f"  total {float(projection['total']):.0f} $; "
              f"spend {float(projection['spend']):.0f} $ "
              f"({float(projection['spend']) / TOTAL_TREE * 100.0:.1f}% of tree)")
        print("")

    # explicit analytical cap failure
    for row in analytical:
        if row["max_income"] < row["target"]:
            failures.append(
                f"analytical max income H{int(row['hour'])} {row['max_income']:.0f} "
                f"< target {row['target']:.0f}")

    print("TUNING NOTES (recommendations only; data/balance.json is not edited)")
    if failures:
        for hour in range(1, RUN_HOURS + 1):
            mean = hour_means.get(hour)
            if mean is None:
                continue
            target = TARGETS[hour]
            if abs(mean - target) / target <= CHECK_TOL:
                continue
            cap = int(HOURS[hour]["request_cap"])
            suggested = int(clamp(round(cap * target / max(1.0, mean)), 1,
                                  int(HOURS[hour]["files"])))
            if caps:
                suggested = int(caps.get(hour, suggested))
            print(f"  H{hour}: cap {cap} -> {suggested} (mean {mean:.0f} vs target {target:.0f})")
        if total_income < BAND_LOW or total_income > BAND_HIGH:
            cap_failures = [h for h in hour_means
                            if abs(hour_means[h] - TARGETS[h]) / TARGETS[h] > CHECK_TOL]
            if cap_failures:
                print(f"  total: outside {BAND_TEXT} mainly due to hourly caps; "
                      "re-run after cap changes before scaling base_pay")
            else:
                print(f"  total: scale base_pay by "
                      f"x{(BAND_LOW + BAND_HIGH) * 0.5 / max(1.0, total_income):.2f} "
                      f"or adjust targets")
        if tree_pct < 55.0 or tree_pct > 65.0:
            ceiling = (total_income - statistics.fmean(
                [r.income for sim in runs for r in sim.hourly if r.hour == RUN_HOURS])
                + int(CONST.get("money_start", 50))) / TOTAL_TREE * 100.0
            note = (" -> 55-65% unreachable without post-H9 shop"
                    if ceiling < 55.0 else "")
            print(f"  shop: spend {tree_pct:.1f}% of tree; ceiling before H9 "
                  f"~{ceiling:.0f}%{note}")
        money_stat = sum(sim.lot_stats['lot_money'].value for sim in runs) / max(
            1.0, sum(sim.lot_stats['lot_money'].spend for sim in runs))
        if money_stat > 1.5:
            print(f"  money lot ROI proxy {money_stat:.2f}: early prices are front-loaded; "
                  "suggest [120,170,230,300,390,500,640,800]")
    else:
        print("  none: all hours inside +/-20%, all analytical caps above target")
    print("")

    report, passed = build_report(runs, analytical, projection, caps)
    REPORT_PATH.write_text(report, encoding="utf-8")
    print(f"report written: {REPORT_PATH}")
    if passed:
        print("PASS sim_balance")
        return 0
    print("FAIL sim_balance")
    for failure in failures:
        print(f"  FAIL: {failure}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
