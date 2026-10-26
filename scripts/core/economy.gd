class_name Economy
extends RefCounted
## Чистая экономика и тайминги v2. Все методы статические, без состояния
## и без обращений к сценам — удобно тестировать headless.
##
## ВАЖНО: только float-арифметика в формулах выплаты (никаких int/int) и
## только pow() для степеней (никакого ^).

## Канал: load = Σ weight(активных передач). Фон и занятые слоты не грузят.
const CHANNEL_BG_BASE := 0.0
const CHANNEL_BG_PER_HOUR := 0.0
const SLOT_LOAD := 0.0
const CHANNEL_CAPACITY_BASE := 10.0
const CHANNEL_CAPACITY_STEP := 6.0

const PACKET_TIMER_BASE := 20.0
const REQUEST_TIMER_BASE := 30.0
const REQUEST_TIMER_STEP := 7.0
const REQUEST_TIMER_MAX := 65.0

const BUFFER_BASE := 6
const BUFFER_PER_LEVEL := 1
const BUFFER_MAX := 12

## Множитель времени передачи за уровень «Оптоволокна» (10% за уровень).
const SPEED_STEP := 0.90

## Коэффициенты мини-игр: text 1, sound 2, photo 4, video 8.
const MINIGAME_COEFF := {
	"text": 1,
	"sound": 2,
	"photo": 4,
	"video": 8,
}

## Игры отправки (wires удалена). Порядок совпадает с data.gd/minigame_factory.
const SEND_ORDER := ["dots", "sound", "text", "video", "photo", "maze"]

## Игра по rank (позиция суммы в ACHIEVABLE_SUMS). Прямая таблица, без modulo.
const RANK_GAMES := [
	"text", "sound", "dots", "photo", "maze",
	"dots", "photo", "video", "dots", "text",
	"video", "maze", "photo", "sound", "video",
	"text", "maze", "sound", "video", "sound",
	"photo", "dots", "dots", "maze", "maze",
	"photo", "video",
]

## Достижимые суммы коэффициентов для 1–4 файлов: 27 значений.
const ACHIEVABLE_SUMS := [
	1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14,
	15, 16, 17, 18, 19, 20, 21, 22, 24, 25, 26, 28, 32,
]

## rank 0..7 → T1, 8..13 → T2, 14..26 → T3.
const TIER_MAX_RANK := [7, 13]

const PAYOUT_SPEED_BASE := 0.6
const PAYOUT_SPEED_BONUS := 0.4
const PAYOUT_QUALITY_BASE := 0.5
const PAYOUT_QUALITY_BONUS := 0.5
const PAYOUT_MULTI_STEP := 0.15
const PAYOUT_TCP_MULT := 1.15
const PAYOUT_UDP_MULT := 0.85
const PAYOUT_UDP_TIME_MULT := 0.8
const PAYOUT_STREAK_STEP := 0.02
const PAYOUT_STREAK_CAP := 10
const PAYOUT_MONEY_STEP := 0.05

## UDP: база 40%, +10% за уровень «UDP-повторителя», кап 80%.
const UDP_SUCCESS_BASE := 0.40
const UDP_SUCCESS_STEP := 0.10
const UDP_SUCCESS_MAX := 0.80


# --- канал -----------------------------------------------------------------

## load = Σ weight(active_transfers) — только файлы в процессе загрузки
## (packet.loading) или отправки (request.sending). idle-канал = 0.
## hour/used_slots оставлены в сигнатуре для совместимости и игнорируются.
static func channel_load(_hour: int, _used_slots: int, active_weights: Array, _upgrades: Dictionary = {}) -> float:
	var weight_sum := 0.0
	for weight in active_weights:
		weight_sum += maxf(0.0, float(weight))
	return weight_sum


static func channel_capacity(upgrades: Dictionary = {}) -> float:
	var level := _level(upgrades, ["channel", "channel_level", "channel_lvl", "lot_channel", "channel_capacity"])
	return CHANNEL_CAPACITY_BASE + CHANNEL_CAPACITY_STEP * float(level)


## factor = max(1.0, load / capacity). Второй аргумент — число capacity
## или словарь upgrades (тогда capacity считается из уровня канала).
static func channel_factor(load: float, capacity_or_upgrades = null) -> float:
	var capacity := CHANNEL_CAPACITY_BASE
	if capacity_or_upgrades is Dictionary:
		capacity = channel_capacity(capacity_or_upgrades)
	elif capacity_or_upgrades != null:
		capacity = float(capacity_or_upgrades)
	if capacity <= 0.0:
		return 1.0
	return maxf(1.0, maxf(0.0, load) / capacity)


static func buffer_limit(upgrades: Dictionary = {}) -> int:
	var level := _level(upgrades, ["channel", "channel_level", "buffer", "buffer_level", "lot_channel"])
	return clampi(BUFFER_BASE + BUFFER_PER_LEVEL * level, BUFFER_BASE, BUFFER_MAX)


## pow(0.90, speed_level): 0 → 1.0, 6 → ≈0.531.
static func speed_mult(speed_level: int) -> float:
	return pow(SPEED_STEP, float(maxi(0, int(speed_level))))


## Базовое время типа: v2-поле base_time_sec с fallback на legacy.
static func type_base_time(type_def: Dictionary) -> float:
	if type_def.has("base_time_sec"):
		return maxf(0.0, float(type_def.get("base_time_sec", 0.0)))
	if type_def.has("recv_time"):
		return maxf(0.0, float(type_def.get("recv_time", 0.0)))
	return 0.0


## Время приёма: base_time_sec × pow(0.90, speed_level) × channel_factor.
## У приёма нет протокольного множителя.
static func recv_transfer_time(type_def: Dictionary, channel_factor_value: float = 1.0, speed_level: int = 0) -> float:
	return type_base_time(type_def) * speed_mult(speed_level) * maxf(0.0, channel_factor_value)


## Время отправки: то же + UDP ×0.8 (TCP ×1.0).
static func send_transfer_time(type_def: Dictionary, channel_factor_value: float = 1.0, speed_level: int = 0, protocol = "tcp") -> float:
	var mult := 1.0
	if str(protocol).to_lower() == "udp":
		mult = PAYOUT_UDP_TIME_MULT
	return type_base_time(type_def) * speed_mult(speed_level) * maxf(0.0, channel_factor_value) * mult


## Legacy-обёртки: factor — channel_factor, upgrades даёт speed_level.
static func recv_time(type_def: Dictionary, factor: float, upgrades: Dictionary = {}) -> float:
	var level := _level(upgrades, ["speed", "speed_level", "transfer_speed", "lot_speed"])
	return recv_transfer_time(type_def, factor, level)


static func send_time(type_def: Dictionary, factor: float, upgrades: Dictionary = {}) -> float:
	var level := _level(upgrades, ["speed", "speed_level", "transfer_speed", "lot_speed"])
	return send_transfer_time(type_def, factor, level, "tcp")


# --- таймеры ---------------------------------------------------------------

## v2: таймер пакета фиксирован — 20 с, не покупается и не зависит от часа.
static func packet_timer(_hour: int = 1, _upgrades: Dictionary = {}) -> float:
	return PACKET_TIMER_BASE


## v2: 30 + 7 × timer_level, не выше 65 с.
static func request_timer(_hour: int = 1, upgrades: Dictionary = {}) -> float:
	var level := _level(upgrades, ["timer", "timer_level", "request_timer", "request_timer_level", "lot_timer"])
	var value := REQUEST_TIMER_BASE + REQUEST_TIMER_STEP * float(level)
	return clampf(value, REQUEST_TIMER_BASE, REQUEST_TIMER_MAX)


## Legacy-хуки: в v2 grace не используется.
static func timer_grace(_hour: int) -> float:
	return 1.0


static func request_timer_grace(_hour: int) -> float:
	return 1.0


# --- мини-игры -------------------------------------------------------------

## Средний коэффициент сложности (legacy-эвристика).
static func minigame_difficulty(types: Array) -> float:
	if types.is_empty():
		return 1.0
	var total := 0.0
	for type in types:
		total += float(MINIGAME_COEFF.get(str(type), 1))
	return total / float(types.size())


static func minigame_type(types: Array) -> String:
	var difficulty := minigame_difficulty(types)
	if difficulty < 1.5:
		return "text"
	if difficulty < 2.5:
		return "sound"
	if difficulty < 3.5:
		return "photo"
	return "video"


## Выбор мини-игры отправки по сумме коэффициентов (1–4 файла).
##
## rank — позиция суммы S в списке ACHIEVABLE_SUMS (для недостижимой S —
## позиция ближайшей меньшей достижимой). tier: rank 0..7 → T1, 8..13 → T2,
## 14..26 → T3. Игра берётся напрямую из RANK_GAMES[rank], без modulo.
##
## S = 0 (нет файлов) → dots/T1.
static func send_minigame_for(types: Array) -> Dictionary:
	var total := 0
	for type in types:
		total += int(MINIGAME_COEFF.get(str(type).to_lower(), 1))
	return selection_for_sum(total)


## Публичный алиас выбора по готовой сумме (для MiniGameFactory/тестов).
static func selection_for_sum(total: int) -> Dictionary:
	var sum := maxi(0, int(total))
	if sum <= 0:
		return {"id": "dots", "tier": 1, "index": 0, "sum": 0}
	var count := ACHIEVABLE_SUMS.size()
	var rank := 0
	for i in range(count):
		if int(ACHIEVABLE_SUMS[i]) <= sum:
			rank = i
		else:
			break
	var tier := 1
	if rank > int(TIER_MAX_RANK[1]):
		tier = 3
	elif rank > int(TIER_MAX_RANK[0]):
		tier = 2
	return {
		"id": str(RANK_GAMES[clampi(rank, 0, RANK_GAMES.size() - 1)]),
		"tier": tier,
		"index": rank,
		"sum": sum,
	}


## Список достижимых сумм коэффициентов (копия, чтобы нельзя было испортить const).
static func achievable_sums() -> Array:
	return ACHIEVABLE_SUMS.duplicate()


## Ступень атаки: H2-3 → T1, H4-5 → T2, H6-7 → T3, H8-9 → T4.
static func attack_tier(hour: int) -> int:
	return clampi(1 + int(floor(float(maxi(1, int(hour)) - 2) / 2.0)), 1, 4)


# --- выплата ---------------------------------------------------------------

## payout = round(base_sum × speed × quality × multi × protocol × streak ×
##              money_mult). TCP ×1.15, UDP ×0.85; money_level из upgrades.
static func payout(
	base_sum: float,
	n: int,
	time_left: float,
	timer_total: float,
	mini_quality: float,
	protocol,
	streak: int,
	upgrades: Dictionary = {}
) -> int:
	if n <= 0:
		return 0
	var time_ratio := 1.0
	if timer_total > 0.0:
		time_ratio = clampf(float(time_left) / float(timer_total), 0.0, 1.0)
	var speed := PAYOUT_SPEED_BASE + PAYOUT_SPEED_BONUS * time_ratio
	var quality := PAYOUT_QUALITY_BASE + PAYOUT_QUALITY_BONUS * clampf(float(mini_quality), 0.0, 1.0)
	var multi := 1.0 + PAYOUT_MULTI_STEP * float(n - 1)
	var protocol_mult := PAYOUT_TCP_MULT if str(protocol).to_lower() == "tcp" else PAYOUT_UDP_MULT
	var streak_mult := 1.0 + PAYOUT_STREAK_STEP * float(clampi(streak, 0, PAYOUT_STREAK_CAP))
	var money_level := _level(upgrades, ["money", "money_level", "money_mult", "lot_money"])
	var money_mult := 1.0 + PAYOUT_MONEY_STEP * float(money_level)
	var value := maxf(0.0, float(base_sum)) * speed * quality * multi * protocol_mult * streak_mult * money_mult
	return int(round(value))


static func money_mult(upgrades: Dictionary = {}) -> float:
	var level := _level(upgrades, ["money", "money_level", "money_mult", "lot_money"])
	return 1.0 + PAYOUT_MONEY_STEP * float(level)


## Шанс успешной UDP-отправки: base + step × уровень, не выше cap.
## Чистая функция для тестов и HourDirector/Game.
static func udp_success_chance(upgrades: Dictionary = {},
		base: float = UDP_SUCCESS_BASE, step: float = UDP_SUCCESS_STEP,
		cap: float = UDP_SUCCESS_MAX) -> float:
	var level := _level(upgrades, ["udp", "udp_level", "lot_udp", "udp_success"])
	var safe_base := clampf(float(base), 0.0, 1.0)
	var safe_cap := clampf(float(cap), safe_base, 1.0)
	var value := safe_base + maxf(0.0, float(step)) * float(level)
	return clampf(value, safe_base, safe_cap)


## Итоговый счёт: часы × 1000 + заработанные деньги + SLA × 10.
static func score(hours: int, money_earned_total: int, sla: float) -> int:
	var safe_hours := maxi(0, hours)
	var safe_money := maxi(0, money_earned_total)
	var safe_sla := maxf(0.0, sla)
	return int(round(float(safe_hours) * 1000.0 + float(safe_money) + safe_sla * 10.0))


# --- служебное -------------------------------------------------------------

static func _level(upgrades: Dictionary, keys: Array) -> int:
	if upgrades.is_empty():
		return 0
	for key in keys:
		if upgrades.has(key):
			return int(upgrades[key])
	return 0
