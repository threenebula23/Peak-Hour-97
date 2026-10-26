extends Node
## Game — верхнеуровневое состояние забега (autoload).
##
## v2-экономика: старт 50 $, SLA 60/60, 1 слот, сетка 5×4, канал 10,
## буфер 6, таймер запроса 30 с. Уровни лотов хранятся в Game.upgrades
## одновременно под id лота и под агрегированным ключом эффекта.
##
## Не знает о сценах и UI: только данные, переходы фаз и сигналы.
## Фазы: menu → prep → hour → ... → results.

signal money_changed(v)
signal sla_changed(v)
signal hour_changed(v)
signal phase_changed(p)
signal run_ended(reason)
signal toast(text)

const START_MONEY := 50
const START_SLA := 60.0
const HOURS_PER_RUN := 9
## Жёсткий кап SLA (main.gd показывает его в статус-баре). Рабочий кап —
## sla_cap(): 60 + 40 * sla_level, не выше MAX_SLA.
const MAX_SLA := 220.0

const REGISTRY_SCRIPT := preload("res://scripts/core/file_registry.gd")
const SAVE_SCRIPT := preload("res://scripts/systems/save_system.gd")
const SHOP_SCRIPT := preload("res://scripts/systems/shop.gd")

## effect → агрегированный ключ уровня в Game.upgrades.
const LOT_EFFECT_KEYS := {
	"connection_slots": "slot_level",
	"transfer_speed": "speed_level",
	"sla_cap": "sla_level",
	"shield_charge": "shield_level",
	"money_mult": "money_level",
	"folder_cells": "folder_level",
	"channel_capacity": "channel_level",
	"request_timer": "timer_level",
	"udp_success": "udp_level",
}

const FALLBACK_LOT_DIMS := [[5, 4], [6, 4], [7, 5], [8, 5], [8, 6], [9, 6]]

## Резерв, если Data ещё не готов (id → лот минимально необходимых полей).
const FALLBACK_SHOP := {
	"lot_slots": {"id": "lot_slots", "name_ru": "Порты коммутатора", "effect": "connection_slots", "value": 1, "max_level": 4, "prices": [90, 200, 400, 700]},
	"lot_speed": {"id": "lot_speed", "name_ru": "Оптоволокно", "effect": "transfer_speed", "value": 0.10, "max_level": 6, "prices": [55, 75, 100, 135, 180, 245]},
	"lot_sla": {"id": "lot_sla", "name_ru": "Резервный ИБП", "effect": "sla_cap", "value": 40, "max_level": 4, "prices": [80, 160, 270, 430]},
	"lot_shield": {"id": "lot_shield", "name_ru": "Заземление", "effect": "shield_charge", "value": 1, "max_level": 3, "prices": [100, 220, 410]},
	"lot_money": {"id": "lot_money", "name_ru": "Корпоративный контракт", "effect": "money_mult", "value": 0.05, "max_level": 8, "prices": [70, 95, 130, 170, 220, 285, 365, 465]},
	"lot_folder": {"id": "lot_folder", "name_ru": "Складской стеллаж", "effect": "folder_cells", "value": 1, "max_level": 5, "prices": [50, 100, 180, 290, 440]},
	"lot_channel": {"id": "lot_channel", "name_ru": "Пропускная способность", "effect": "channel_capacity", "value": 6, "buffer_value": 1, "max_level": 6, "prices": [45, 70, 95, 130, 175, 230]},
	"lot_timer": {"id": "lot_timer", "name_ru": "Регламент обработки", "effect": "request_timer", "value": 7, "max_level": 5, "prices": [45, 75, 115, 165, 230]},
	"lot_udp": {"id": "lot_udp", "name_ru": "UDP-повторитель", "effect": "udp_success", "value": 0.10, "max_level": 4, "prices": [60, 120, 210, 350]},
}

## Публичный алиас каталога-резерва (удобно тестам/UI).
const LOT_DEFS := FALLBACK_SHOP

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

## v2-магазин: 3 id, счётчик рероллов, час генерации, pity-история и замки.
var shop_offers: Array[String] = []
var shop_rerolls: int = 0
var shop_offer_hour: int = 0
var shop_last_seen: Dictionary = {}
var shop_locked: Array[String] = []

## Заряды «Заземления»: восстанавливаются в начале часа.
var shield_charges: int = 0
## Час, за который SLA-реген уже выдан (идемпотентность вызова).
var _sla_regen_hour: int = 0

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
	regen_sla_for_hour()
	regen_shield_for_hour()
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
	# Рероллы живут одну подготовку.
	shop_rerolls = 0
	shop_locked.clear()
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
	sla = clampf(sla + float(delta), 0.0, sla_cap())
	if not reason.is_empty():
		stats["last_reason"] = reason
	sla_changed.emit(sla)
	if sla <= 0.0 and phase == &"hour":
		_finish_run("sla")


## +15 SLA в начале часа (не выше динамического капа). Возвращает новый SLA.
## Идемпотентно в пределах одного часа: повторный вызов не добавляет SLA.
func regen_sla_for_hour() -> float:
	if _sla_regen_hour == hour:
		return sla
	_sla_regen_hour = hour
	var regen := _const("sla_regen_per_hour", 15.0)
	sla = clampf(sla + regen, 0.0, sla_cap())
	sla_changed.emit(sla)
	return sla


## Заряды щита восстанавливаются до максимума в начале часа.
func regen_shield_for_hour() -> int:
	shield_charges = shield_max()
	return shield_charges


func add_stat(key: String, delta: int = 1) -> void:
	stats[key] = int(stats.get(key, 0)) + int(delta)


# --- v2: уровни лотов и производные статы ----------------------------------

## Уровень по id лота (lot_*) или по эффекту/агрегату
## (connection_slots / slot_level / ...).
func level(effect_or_lot: String) -> int:
	var key := str(effect_or_lot)
	if key.is_empty():
		return 0
	if key.begins_with("lot_"):
		if upgrades.has(key):
			return int(upgrades[key])
		var def := _lot_def(key)
		var effect := str(def.get("effect", ""))
		var agg := str(LOT_EFFECT_KEYS.get(effect, ""))
		if not agg.is_empty():
			return int(upgrades.get(agg, 0))
		return 0
	if upgrades.has(key):
		return int(upgrades[key])
	if LOT_EFFECT_KEYS.has(key):
		return int(upgrades.get(str(LOT_EFFECT_KEYS[key]), 0))
	return 0


## Записать уровень лота в оба ключа и сразу применить мгновенные эффекты
## (SLA-кап/щит). Остальные статы читаются геттерами динамически.
func set_lot_level(id: String, new_level: int) -> int:
	var def := _lot_def(id)
	if def.is_empty():
		return 0
	if not (upgrades is Dictionary):
		upgrades = {}
	var max_level := maxi(1, int(def.get("max_level", 1)))
	var old_level := level(id)
	var lvl := clampi(int(new_level), 0, max_level)
	upgrades[id] = lvl
	var effect := str(def.get("effect", ""))
	var agg := str(LOT_EFFECT_KEYS.get(effect, ""))
	if not agg.is_empty():
		upgrades[agg] = lvl
	if effect == "sla_cap" and lvl > old_level:
		# Кап уже вырос (sla_cap() читает новый уровень), добавляем +40 сразу.
		var gain := _lot_value(def, 40.0) * float(lvl - old_level)
		sla = clampf(sla + gain, 0.0, sla_cap())
		sla_changed.emit(sla)
	elif effect == "shield_charge" and lvl > old_level:
		shield_charges = mini(shield_max(), shield_charges + (lvl - old_level))
	if effect == "folder_cells" and lvl != old_level and registry != null \
			and registry.has_method("resize_folders"):
		# Лот растит уже существующие папки, а не только будущие.
		registry.resize_folders(folder_dims())
	return lvl


func sla_cap() -> float:
	var base := _const("sla_base", START_SLA)
	var step := _lot_effect_value("lot_sla", "value", _const("sla_per_level", 40.0))
	var hard := _const("sla_hard_cap", MAX_SLA)
	return clampf(base + step * float(level("sla_level")), base, hard)


func money_mult() -> float:
	var step := _lot_effect_value("lot_money", "value", _const("money_mult_step", 0.05))
	return 1.0 + step * float(level("money_level"))


## pow(0.90, speed_level) — множитель времени передачи (10% за уровень).
func speed_mult() -> float:
	var cut := clampf(_lot_effect_value("lot_speed", "value", 0.10), 0.01, 0.9)
	return pow(1.0 - cut, float(maxi(0, level("speed_level"))))


func folder_dims() -> Vector2i:
	var table := _folder_dims_table()
	if table.is_empty():
		table = FALLBACK_LOT_DIMS
	var idx := clampi(level("folder_level"), 0, table.size() - 1)
	var pair = table[idx]
	if pair is Array and (pair as Array).size() >= 2:
		return Vector2i(int(pair[0]), int(pair[1]))
	return Vector2i(5, 4)


## Цена следующей папки: 150 + 100 за каждую сверх стартовых 2.
## count < 0 → берём текущее число папок из реестра.
func folder_price(count: int = -1) -> int:
	var base := int(_const("folder_price_start", 150.0))
	var step := int(_const("folder_price_step", 100.0))
	var start := int(_const("folders_start", 2.0))
	var total := int(count)
	if total < 0:
		total = 0
		if registry != null and registry.has_method("folder_count"):
			total = int(registry.folder_count())
	return base + step * maxi(0, total - start)


func connection_slots() -> int:
	var base := int(_const("slots_start", 1.0))
	var cap := int(_const("slots_max", 5.0))
	return clampi(base + level("slot_level"), base, cap)


func channel_capacity() -> float:
	var base := _const("channel_capacity", 10.0)
	var step := _lot_effect_value("lot_channel", "value", _const("channel_per_level", 6.0))
	return base + step * float(level("channel_level"))


func buffer_limit() -> int:
	var base := int(_const("buffer_base", 6.0))
	var step := int(_lot_effect_value("lot_channel", "buffer_value", _const("buffer_per_level", 1.0)))
	var cap := int(_const("buffer_max", 12.0))
	return clampi(base + step * level("channel_level"), base, cap)


func request_timer() -> float:
	var base := _const("request_timer", 30.0)
	var step := _lot_effect_value("lot_timer", "value", _const("request_timer_per_level", 7.0))
	var cap := _const("request_timer_max", 65.0)
	return clampf(base + step * float(level("timer_level")), base, cap)


func packet_timer() -> float:
	return _const("packet_timer", 20.0)


func shield_max() -> int:
	return maxi(0, level("shield_level"))


## Шанс успешной UDP-отправки: 40% + 10% за уровень «UDP-повторителя»,
## не выше 80%. Зеркалит Economy.udp_success_chance() для UI/контроллера.
func udp_success_chance() -> float:
	var base := _const("udp_success_base", 0.40)
	var cap := _const("udp_success_max", 0.80)
	var step := _lot_effect_value("lot_udp", "value", 0.10)
	return clampf(base + step * float(level("udp_level")), base, cap)


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


# --- магазин (legacy-фасад) ------------------------------------------------

## Покупка по id лота (legacy-путь; UI v2 использует Shop.buy).
func buy_upgrade(id: String) -> bool:
	var item := _shop_item(id)
	if item.is_empty():
		return false
	var lvl := level(id)
	var max_level := int(item.get("max_level", 1))
	if max_level > 0 and lvl >= max_level:
		return false
	var cost := _item_cost(item, lvl)
	if money < cost:
		toast.emit(_tr("msg.money_short", "Недостаточно денег"))
		return false
	money -= cost
	set_lot_level(id, lvl + 1)
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
		"shop_offers": shop_offers.duplicate(),
		"shop_rerolls": shop_rerolls,
		"shop_offer_hour": shop_offer_hour,
		"shop_last_seen": shop_last_seen.duplicate(true),
		"shop_locked": shop_locked.duplicate(),
		"shield_charges": shield_charges,
		"sla_regen_hour": _sla_regen_hour,
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
	# runtime-резервы под запросы не переживают загрузку: сами запросы не
	# сохраняются, поэтому file.required_by/attached_request и location
	# "attached" после load указывали бы на несуществующий запрос. Такой файл
	# нельзя ни переместить, ни удалить — он навсегда занимает клетку.
	for file in reg.files.values():
		file.required_by = ""
		file.attached_request = ""
		if String(file.location) == "attached":
			file.location = &"folder" if not String(file.folder_id).is_empty() else &"registry"
		# _repair_after_load уже разложил файл по папкам/клеткам. Если папки
		# (или её bookkeeping) нет, файл должен быть видимым в реестре, а не
		# числиться в несуществующем месте.
		if String(file.location) == "folder":
			var folder = reg.folders.get(String(file.folder_id), null)
			if folder == null or not folder.file_ids.has(file.id):
				file.folder_id = ""
				file.location = &"registry"
	registry = reg

	upgrades = _dict_of(data.get("upgrades", {}))
	money = maxi(0, int(data.get("money", START_MONEY)))
	hour = clampi(int(data.get("hour", 1)), 1, HOURS_PER_RUN)
	phase = StringName(str(data.get("phase", "menu")))
	streak = maxi(0, int(data.get("streak", 0)))
	sla = clampf(float(data.get("sla", START_SLA)), 0.0, sla_cap())
	meta_unlocks = _dict_of(data.get("meta", {}))
	run_meta_awards = _string_array_of(data.get("run_meta_awards", []))
	stats = _default_stats()
	var raw_stats = data.get("stats", {})
	if raw_stats is Dictionary:
		for key in raw_stats.keys():
			stats[key] = raw_stats[key]
	rng_seed = int(data.get("rng_seed", 0))
	shield_charges = clampi(int(data.get("shield_charges", 0)), 0, shield_max())
	_sla_regen_hour = int(data.get("sla_regen_hour", 0))

	_restore_shop_state(data)

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
	shop_offers.clear()
	shop_rerolls = 0
	shop_offer_hour = 0
	shop_last_seen.clear()
	shop_locked.clear()
	shield_charges = 0
	_sla_regen_hour = 0
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


## Восстановить офферы/рероллы/last_seen/замки; выкинуть неизвестные и
## максимальные лоты; при необходимости догенерировать до 3.
func _restore_shop_state(data: Dictionary) -> void:
	shop_offers.clear()
	for raw_id in _string_array_of(data.get("shop_offers", [])):
		var id := str(raw_id)
		if not id.begins_with("lot_"):
			continue
		var def := _lot_def(id)
		if def.is_empty():
			continue
		if level(id) >= maxi(1, int(def.get("max_level", 1))):
			continue
		if shop_offers.has(id):
			continue
		shop_offers.append(id)
	shop_rerolls = clampi(int(data.get("shop_rerolls", 0)), 0, _max_rerolls())
	shop_offer_hour = int(data.get("shop_offer_hour", 0))
	shop_last_seen = _int_dict_of(data.get("shop_last_seen", {}))
	shop_locked.clear()
	for raw_id in _string_array_of(data.get("shop_locked", [])):
		var id := str(raw_id)
		if shop_offers.has(id) and not shop_locked.has(id):
			shop_locked.append(id)

	if hour <= 1:
		return
	var target := int(_shop_rules().get("offers", 3))
	if shop_offers.size() >= target and shop_offer_hour > 0:
		return
	var lots := _lot_defs()
	if lots.is_empty():
		return
	var selected := SHOP_SCRIPT.select_offers(
		hour, lots, upgrades, money, [], shop_last_seen,
		shop_offers.duplicate(), target)
	shop_offers.clear()
	for id in selected:
		shop_offers.append(str(id))
	if shop_offer_hour <= 0:
		shop_offer_hour = hour
	for id in shop_offers:
		shop_last_seen[str(id)] = hour


func _lot_def(id: String) -> Dictionary:
	var data = _data_node()
	if data != null and data.has_method("lot_def"):
		var def = data.lot_def(id)
		if def is Dictionary and not (def as Dictionary).is_empty():
			return def
	var fallback = FALLBACK_SHOP.get(str(id), null)
	if fallback is Dictionary:
		return (fallback as Dictionary).duplicate(true)
	return {}


func _lot_defs() -> Array:
	var data = _data_node()
	if data != null and data.has_method("lot_defs"):
		var lots = data.lot_defs()
		if lots is Array and not (lots as Array).is_empty():
			return lots
	var out: Array = []
	for id in FALLBACK_SHOP.keys():
		out.append((FALLBACK_SHOP[id] as Dictionary).duplicate(true))
	return out


func _shop_rules() -> Dictionary:
	var data = _data_node()
	if data != null and data.has_method("shop_rules"):
		var rules = data.shop_rules()
		if rules is Dictionary and not (rules as Dictionary).is_empty():
			return rules
	return {"offers": 3, "reroll_costs": [40, 80, 120], "max_rerolls": 3}


func _max_rerolls() -> int:
	return maxi(0, int(_shop_rules().get("max_rerolls", 3)))


func _folder_dims_table() -> Array:
	var data = _data_node()
	if data != null and data.has_method("folder_dims_table"):
		var table = data.folder_dims_table()
		if table is Array and not (table as Array).is_empty():
			return table
	return FALLBACK_LOT_DIMS.duplicate(true)


func _const(key: String, fallback_value: float) -> float:
	var data = _data_node()
	if data != null and data.get("constants") is Dictionary:
		var consts: Dictionary = data.constants
		if consts.has(key):
			return float(consts[key])
	return float(fallback_value)


func _lot_value(def: Dictionary, fallback_value: float) -> float:
	if def.has("value"):
		return float(def.get("value"))
	return float(fallback_value)


## Значение поля лота (source of truth для эффекта), fallback — константа.
func _lot_effect_value(id: String, field: String, fallback_value: float) -> float:
	var def := _lot_def(id)
	if def.has(field):
		return float(def.get(field))
	return float(fallback_value)


func _shop_item(id: String) -> Dictionary:
	var data = _data_node()
	if data != null and data.has_method("shop_item"):
		var item = data.shop_item(id)
		if item is Dictionary and not (item as Dictionary).is_empty():
			return item
	var fallback = FALLBACK_SHOP.get(id, null)
	if fallback is Dictionary:
		return (fallback as Dictionary).duplicate(true)
	return {}


func _item_cost(item: Dictionary, lvl: int) -> int:
	var prices = item.get("prices", null)
	if prices is Array and not (prices as Array).is_empty():
		var arr: Array = prices
		if lvl < arr.size():
			return maxi(0, int(arr[lvl]))
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


func _int_dict_of(value) -> Dictionary:
	var out: Dictionary = {}
	if value is Dictionary:
		for key in value.keys():
			out[str(key)] = int(value[key])
	return out


func _string_array_of(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in value:
			out.append(str(item))
	return out
