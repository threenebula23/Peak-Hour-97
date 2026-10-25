extends Node
## Game — верхнеуровневое состояние забега (autoload).
##
## Не знает о сценах и UI: только данные, переходы фаз и сигналы.
## Фазы: menu → prep → hour → ... → results.

signal money_changed(v)
signal sla_changed(v)
signal hour_changed(v)
signal phase_changed(p)
signal run_ended(reason)
signal toast(text)

const START_MONEY := 150
const START_SLA := 128.0
const HOURS_PER_RUN := 9
const MAX_SLA := 200.0

const REGISTRY_SCRIPT := preload("res://scripts/core/file_registry.gd")
const SAVE_SCRIPT := preload("res://scripts/systems/save_system.gd")

## Резерв, если Data ещё не готов (id → товар).
const FALLBACK_SHOP := {
	"shop_slot3": {"id": "shop_slot3", "name_ru": "Третий слот", "price": 250, "max_level": 1},
	"shop_slot4": {"id": "shop_slot4", "name_ru": "Четвёртый слот", "price": 450, "max_level": 1},
	"shop_buffer": {"id": "shop_buffer", "name_ru": "Буфер +2", "price": 200, "max_level": 2},
	"shop_timer": {"id": "shop_timer", "name_ru": "Таймер пакетов +4 с", "price": 350, "max_level": 3},
	"shop_zone": {"id": "shop_zone", "name_ru": "Зона +5%", "price": 300, "max_level": 3},
	"shop_channel": {"id": "shop_channel", "name_ru": "Канал +25", "price": 250, "max_level": 4},
	"shop_section": {"id": "shop_section", "name_ru": "Новая секция", "price": 300, "max_level": 5},
	"shop_search": {"id": "shop_search", "name_ru": "Поиск", "price": 250, "max_level": 1},
	"shop_shield": {"id": "shop_shield", "name_ru": "Щит", "price": 400, "max_level": 1},
	"shop_sla": {"id": "shop_sla", "name_ru": "SLA +24", "price": 300, "max_level": 3},
}

var money: int = START_MONEY
var sla: float = START_SLA
var hour: int = 1
var phase: StringName = &"menu"
var streak: int = 0
var stats: Dictionary = {}
var upgrades: Dictionary = {}
## Мета-открытия между забегами: ключ meta_rewards → true (переживает reset_run).
var meta_unlocks: Dictionary = {}
## Награды, выданные в текущем забеге (для итогового экрана); чистится новым забегом.
var run_meta_awards: Array[String] = []
## FileRegistry; без type hint, чтобы работать без прогретого class cache.
var registry = null
var rng_seed: int = 0


func _ready() -> void:
	reset_run()


# --- жизненный цикл --------------------------------------------------------

func start_new_run(seed: int = 0) -> void:
	# Мета-прогресс (unlocks за прошлые забеги) не стирается новым забегом.
	_reset_fields(true)
	run_meta_awards.clear()
	rng_seed = seed
	var rng = _rng_node()
	if rng != null and rng.has_method("start_run"):
		rng.start_run(seed)
		if rng.has_method("get_seed"):
			rng_seed = int(rng.get_seed())
	elif seed == 0:
		rng_seed = int(Time.get_unix_time_from_system() * 1000.0) % 2147483647
	registry.rng_seed = rng_seed
	phase = &"prep"
	_emit_all()
	toast.emit(_tr("msg.run_start", "Смена началась"))


func start_hour() -> bool:
	if phase == &"results":
		return false
	if registry == null:
		registry = _make_registry()
	phase = &"hour"
	phase_changed.emit(phase)
	toast.emit(_tr("msg.hour_start", "Час %d" % hour))
	return true


func end_hour() -> bool:
	if phase == &"results":
		return false
	stats["hours_done"] = int(stats.get("hours_done", 0)) + 1
	# Мета-награды выдаём сразу за отработанные часы, а не только в _finish_run:
	# игрок может выйти в меню после 6 часов и всё равно получить survive_hour_5.
	# Метод идемпотентен, поэтому повторный вызов из GameController._finish_run
	# (в т.ч. на 9-м часе) ничего не дублирует.
	award_meta_for_run(int(stats.get("hours_done", 0)))
	if hour >= HOURS_PER_RUN:
		_finish_run("victory")
		return true
	var finished := hour
	hour += 1
	phase = &"prep"
	hour_changed.emit(hour)
	phase_changed.emit(phase)
	toast.emit(_tr("msg.hour_end", "Час %d завершён" % finished))
	return true


func reset_run() -> void:
	# reset_run — сброс забега, мета-открытия остаются.
	_reset_fields(true)
	run_meta_awards.clear()
	phase = &"menu"
	rng_seed = 0
	_emit_all()


# --- ресурсы ---------------------------------------------------------------

func add_money(delta: int, reason: String = "") -> void:
	var d := int(delta)
	if d != 0:
		money = maxi(0, money + d)
		if d > 0:
			stats["money_earned"] = int(stats.get("money_earned", 0)) + d
		if not reason.is_empty():
			stats["last_reason"] = reason
	money_changed.emit(money)


func add_sla(delta: float, reason: String = "") -> void:
	sla = clampf(sla + float(delta), 0.0, MAX_SLA)
	if not reason.is_empty():
		stats["last_reason"] = reason
	sla_changed.emit(sla)
	if sla <= 0.0 and phase == &"hour":
		_finish_run("sla")


func add_stat(key: String, delta: int = 1) -> void:
	stats[key] = int(stats.get(key, 0)) + int(delta)


# --- прогрессия/открытия ---------------------------------------------------

## Открыта ли фича по data/balance.json → progression.unlocks.
## Неизвестный id считается открытым (обратная совместимость).
## run_hour сравнивается с текущим Game.hour; meta — с meta_unlocks.
func feature_unlocked(id: String) -> bool:
	var data = _data_node()
	var defs: Dictionary = {}
	if data != null and data.get("unlocks") is Dictionary:
		defs = data.unlocks
	var def = defs.get(str(id), null)
	if not (def is Dictionary):
		return true
	var info: Dictionary = def
	if info.has("meta") and not meta_unlocks.has(str(info.get("meta", ""))):
		return false
	if info.has("run_hour") and hour < int(info.get("run_hour", 1)):
		return false
	return true


## Начислить мета-награды за завершённый забег (hours часов).
## Возвращает список выданных ключей meta_rewards; сохраняет прогресс.
func award_meta_for_run(hours: int) -> Array[String]:
	var awarded: Array[String] = []
	var data = _data_node()
	var rewards: Dictionary = {}
	if data != null and data.get("meta_rewards") is Dictionary:
		rewards = data.meta_rewards
	if rewards.is_empty():
		return awarded
	var played := maxi(0, int(hours))
	for key in rewards.keys():
		var reward_key := str(key)
		var info = rewards[key]
		if not (info is Dictionary):
			continue
		var min_hours := int((info as Dictionary).get("min_hours", 999))
		if played < min_hours or meta_unlocks.has(reward_key):
			continue
		meta_unlocks[reward_key] = true
		if not run_meta_awards.has(reward_key):
			run_meta_awards.append(reward_key)
		awarded.append(reward_key)
	if not awarded.is_empty():
		save_game()
		toast.emit(_tr("msg.meta_unlock", "Открыто: %s") % ", ".join(awarded))
	return awarded


# --- магазин (заглушка эффектов) ------------------------------------------

## Покупка проверяет деньги и max_level, но не применяет эффект (P1).
func buy_upgrade(id: String) -> bool:
	var item := _shop_item(id)
	if item.is_empty():
		return false
	var level := int(upgrades.get(id, 0))
	var max_level := int(item.get("max_level", 1))
	if max_level > 0 and level >= max_level:
		return false
	var cost := _item_cost(item, level)
	if money < cost:
		toast.emit(_tr("msg.money_short", "Недостаточно денег"))
		return false
	money -= cost
	upgrades[id] = level + 1
	money_changed.emit(money)
	toast.emit(_tr("msg.upgrade_bought", "Куплено: %s") % _item_name(item, id))
	return true


# --- save/load -------------------------------------------------------------

func save_game() -> bool:
	if registry == null:
		registry = _make_registry()
	var rng = _rng_node()
	var rng_state := ""
	if rng != null and rng.has_method("state_string"):
		rng_state = str(rng.state_string())
	var payload := {
		"money": money,
		"sla": sla,
		"hour": hour,
		"phase": String(phase),
		"streak": streak,
		"stats": stats.duplicate(true),
		"upgrades": upgrades.duplicate(true),
		"meta": meta_unlocks.duplicate(true),
		"run_meta_awards": run_meta_awards.duplicate(),
		"rng_seed": rng_seed,
		"rng_state": rng_state,
		"registry": registry.to_dict(),
	}
	return SAVE_SCRIPT.save(payload)


func load_game() -> bool:
	var data := SAVE_SCRIPT.load()
	if data.is_empty():
		return false
	var raw_registry = data.get("registry", {})
	if not (raw_registry is Dictionary):
		push_warning("Game: в save нет корректного registry")
		return false
	var reg = REGISTRY_SCRIPT.new()
	if not reg.from_dict(raw_registry):
		push_warning("Game: не удалось восстановить registry")
		return false
	registry = reg

	money = maxi(0, int(data.get("money", START_MONEY)))
	sla = clampf(float(data.get("sla", START_SLA)), 0.0, MAX_SLA)
	hour = clampi(int(data.get("hour", 1)), 1, HOURS_PER_RUN)
	phase = StringName(str(data.get("phase", "menu")))
	streak = maxi(0, int(data.get("streak", 0)))
	upgrades = _dict_of(data.get("upgrades", {}))
	meta_unlocks = _dict_of(data.get("meta", {}))
	run_meta_awards = _string_array_of(data.get("run_meta_awards", []))
	stats = _default_stats()
	var raw_stats = data.get("stats", {})
	if raw_stats is Dictionary:
		for key in raw_stats.keys():
			stats[key] = raw_stats[key]
	rng_seed = int(data.get("rng_seed", 0))

	var rng = _rng_node()
	if rng != null and rng.has_method("restore_state"):
		var state := str(data.get("rng_state", ""))
		if state.is_empty() or not rng.restore_state(state):
			if rng.has_method("start_run"):
				rng.start_run(rng_seed)

	_emit_all()
	return true


# --- служебное -------------------------------------------------------------

func _reset_fields(keep_meta: bool = true) -> void:
	money = START_MONEY
	sla = START_SLA
	hour = 1
	streak = 0
	stats = _default_stats()
	upgrades = {}
	if not keep_meta:
		meta_unlocks = {}
	registry = _make_registry()


func _make_registry():
	var reg = REGISTRY_SCRIPT.new()
	reg.setup_new_run()
	return reg


func _emit_all() -> void:
	money_changed.emit(money)
	sla_changed.emit(sla)
	hour_changed.emit(hour)
	phase_changed.emit(phase)


func _finish_run(reason: String) -> void:
	phase = &"results"
	phase_changed.emit(phase)
	run_ended.emit(reason)


func _default_stats() -> Dictionary:
	return {
		"hours_done": 0,
		"money_earned": 0,
		"requests_done": 0,
		"files_received": 0,
		"attacks_blocked": 0,
		"failed": 0,
	}


func _shop_item(id: String) -> Dictionary:
	var data = _data_node()
	if data != null and data.has_method("shop_item"):
		var item = data.shop_item(id)
		if item is Dictionary and not item.is_empty():
			return item
	var fallback = FALLBACK_SHOP.get(id, null)
	if fallback is Dictionary:
		return fallback.duplicate(true)
	return {}


func _item_cost(item: Dictionary, level: int) -> int:
	var prices = item.get("prices", null)
	if prices is Array and not prices.is_empty():
		var arr: Array = prices
		if level < arr.size():
			return maxi(0, int(arr[level]))
		return maxi(0, int(arr[arr.size() - 1]))
	if item.has("price"):
		return maxi(0, int(item.get("price", 0)))
	return maxi(0, int(item.get("cost", 0)))


func _item_name(item: Dictionary, fallback_id: String) -> String:
	var item_name := str(item.get("name_ru", ""))
	if item_name.is_empty():
		item_name = str(item.get("name", ""))
	return item_name if not item_name.is_empty() else fallback_id


func _tr(key: String, fallback: String) -> String:
	var data = _data_node()
	if data == null:
		return fallback
	if data.has_method("has_string") and not data.has_string(key):
		return fallback
	if data.has_method("tr"):
		var value := str(data.tr(key))
		if not value.is_empty() and value != key:
			return value
	return fallback


func _data_node():
	return _autoload_node("Data")


func _rng_node():
	return _autoload_node("Rng")


func _autoload_node(name: String):
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null(name)
	return null


func _dict_of(value) -> Dictionary:
	if value is Dictionary:
		return value.duplicate(true)
	return {}


func _string_array_of(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in value:
			out.append(str(item))
	return out
