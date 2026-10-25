class_name Economy
extends RefCounted
## Чистая экономика и тайминги (D12). Все методы статические, без состояния
## и без обращений к сценам — удобно тестировать headless.

## Фон/слоты НЕ входят в load (уточнение п.11): канал грузят только
## активные передачи. Константы оставлены нулевыми для совместимости.
const CHANNEL_BG_BASE := 0.0
const CHANNEL_BG_PER_HOUR := 0.0
const SLOT_LOAD := 0.0
const CHANNEL_CAPACITY_BASE := 80.0
const CHANNEL_CAPACITY_STEP := 25.0

const PACKET_TIMER_BASE := 20.0
const REQUEST_TIMER_BASE := 30.0
const TIMER_PER_HOUR := 0.5
const TIMER_UPGRADE_STEP := 4.0
const PACKET_TIMER_MIN := 12.0
const REQUEST_TIMER_MIN := 20.0
const TIMER_MAX := 999.0

## Grace-множитель первых часов (п.10): больше времени на старте.
## h1 1.5, h2 1.35, h3 1.2, h4+ 1.0 — для таймера пакетов.
const TIMER_GRACE := {1: 1.5, 2: 1.35, 3: 1.2}

## Отдельный grace для таймера запросов: в начале игроку нужно больше времени,
## чтобы собрать файлы. h1 2.0, h2 1.7, h3 1.4, h4+ 1.0.
## h1: 30×2.0 = 60, h2: 29.5×1.7 = 50.15, h3: 29×1.4 = 40.6.
const REQUEST_TIMER_GRACE := {1: 2.0, 2: 1.7, 3: 1.4}

const MINIGAME_COEFF := {
	"text": 1.0,
	"sound": 2.0,
	"photo": 3.0,
	"video": 4.0,
}

const PAYOUT_SPEED_BASE := 0.6
const PAYOUT_SPEED_BONUS := 0.4
const PAYOUT_QUALITY_BASE := 0.5
const PAYOUT_QUALITY_BONUS := 0.5
const PAYOUT_MULTI_STEP := 0.1
const PAYOUT_TCP_MULT := 1.15
const PAYOUT_STREAK_STEP := 0.02
const PAYOUT_STREAK_CAP := 10


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
	var level := _level(upgrades, ["channel", "channel_level", "channel_lvl", "shop_channel", "channel_capacity"])
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


## Базовое время приёма/отправки умножается на фактор канала.
static func recv_time(type_def: Dictionary, factor: float, _upgrades: Dictionary = {}) -> float:
	return maxf(0.0, float(type_def.get("recv_time", 0.0))) * maxf(0.0, factor)


static func send_time(type_def: Dictionary, factor: float, _upgrades: Dictionary = {}) -> float:
	return maxf(0.0, float(type_def.get("send_time", 0.0))) * maxf(0.0, factor)


# --- таймеры ---------------------------------------------------------------

## Формула (п.10): (base − 0.5*(h−1)) * grace(h) + 4*level.
## Grace умножает только базовую часть; апгрейд таймера даёт чистые +4 с.
static func packet_timer(hour: int, upgrades: Dictionary = {}) -> float:
	var h := maxi(1, hour)
	var level := _level(upgrades, ["timer", "timer_level", "packet_timer", "packet_timer_level", "shop_timer"])
	var base := PACKET_TIMER_BASE - TIMER_PER_HOUR * float(h - 1)
	var value := base * timer_grace(h) + TIMER_UPGRADE_STEP * float(level)
	return clampf(value, PACKET_TIMER_MIN, TIMER_MAX)


static func request_timer(hour: int, upgrades: Dictionary = {}) -> float:
	var h := maxi(1, hour)
	var level := _level(upgrades, ["timer", "timer_level", "request_timer", "request_timer_level", "shop_timer"])
	var base := REQUEST_TIMER_BASE - TIMER_PER_HOUR * float(h - 1)
	var value := base * request_timer_grace(h) + TIMER_UPGRADE_STEP * float(level)
	return clampf(value, REQUEST_TIMER_MIN, TIMER_MAX)


## Grace-множитель таймеров по часу: h1 1.5, h2 1.35, h3 1.2, h4+ 1.0.
static func timer_grace(hour: int) -> float:
	return float(TIMER_GRACE.get(maxi(1, hour), 1.0))


## Grace-множитель таймера запросов: h1 2.0, h2 1.7, h3 1.4, h4+ 1.0.
static func request_timer_grace(hour: int) -> float:
	return float(REQUEST_TIMER_GRACE.get(maxi(1, hour), 1.0))


# --- мини-игры -------------------------------------------------------------

## Средний коэффициент сложности. Пустой/неизвестный тип трактуем как text.
static func minigame_difficulty(types: Array) -> float:
	if types.is_empty():
		return 1.0
	var total := 0.0
	for type in types:
		total += float(MINIGAME_COEFF.get(str(type), 1.0))
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


# --- выплата ---------------------------------------------------------------

static func payout(
	base_sum: float,
	n: int,
	time_left: float,
	timer_total: float,
	mini_quality: float,
	protocol,
	streak: int,
	_upgrades: Dictionary = {}
) -> int:
	if n <= 0:
		return 0
	var time_ratio := 1.0
	if timer_total > 0.0:
		time_ratio = clampf(time_left / timer_total, 0.0, 1.0)
	var speed := PAYOUT_SPEED_BASE + PAYOUT_SPEED_BONUS * time_ratio
	var quality := PAYOUT_QUALITY_BASE + PAYOUT_QUALITY_BONUS * clampf(mini_quality, 0.0, 1.0)
	var multi := 1.0 + PAYOUT_MULTI_STEP * float(n - 1)
	var protocol_mult := PAYOUT_TCP_MULT if str(protocol).to_lower() == "tcp" else 1.0
	var streak_mult := 1.0 + PAYOUT_STREAK_STEP * float(clampi(streak, 0, PAYOUT_STREAK_CAP))
	var value := maxf(0.0, base_sum) * speed * quality * multi * protocol_mult * streak_mult
	return int(round(value))


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
