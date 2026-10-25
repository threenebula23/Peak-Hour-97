class_name Shop
extends RefCounted
## Магазин v2: 8 семейств лотов, ровно 3 предложения, реролл 40/80/120
## (максимум 3 за подготовку) и замок отдельного предложения.
##
## Уровни покупок хранятся в Game.upgrades под id лота и под агрегированным
## ключом эффекта (slot_level, speed_level, ...). Эффекты применяет Game
## (set_lot_level + динамические геттеры), магазин только списывает деньги и
## повышает уровень.

signal offers_changed
signal purchased(id: String)

const EFFECT_TARGETS := {
	"connection_slots": "slot_level",
	"transfer_speed": "speed_level",
	"sla_cap": "sla_level",
	"shield_charge": "shield_level",
	"money_mult": "money_level",
	"folder_cells": "folder_level",
	"channel_capacity": "channel_level",
	"request_timer": "timer_level",
}

const DEFAULT_RULES := {
	"offers": 3,
	"reroll_costs": [40, 80, 120],
	"max_rerolls": 3,
	"last_offer_weight": 0.5,
	"pity_hours": 2,
	"pity_weight": 1.5,
}

## Резерв, если data/balance.json недоступен. Совпадает с §3.2/3.3.
const FALLBACK_ITEMS := [
	{"id": "lot_slots", "name_ru": "Порты коммутатора", "effect": "connection_slots", "value": 1,
		"max_level": 4, "prices": [120, 300, 650, 1200],
		"weight_by_hour": [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.8, 0.8, 0.8]},
	{"id": "lot_speed", "name_ru": "Оптоволокно", "effect": "transfer_speed", "value": 0.08,
		"max_level": 6, "prices": [90, 130, 180, 250, 340, 450],
		"weight_by_hour": [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.8, 0.8, 0.8]},
	{"id": "lot_sla", "name_ru": "Резервный ИБП", "effect": "sla_cap", "value": 35,
		"max_level": 4, "prices": [120, 260, 480, 800],
		"weight_by_hour": [0.8, 0.8, 0.8, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]},
	{"id": "lot_shield", "name_ru": "Заземление", "effect": "shield_charge", "value": 1,
		"max_level": 3, "prices": [150, 400, 800],
		"weight_by_hour": [0.3, 0.3, 0.3, 0.8, 0.8, 0.8, 1.0, 1.0, 1.0]},
	{"id": "lot_money", "name_ru": "Корпоративный контракт", "effect": "money_mult", "value": 0.05,
		"max_level": 8, "prices": [80, 110, 150, 200, 260, 340, 440, 560],
		"weight_by_hour": [0.6, 0.6, 0.6, 1.0, 1.0, 1.0, 1.2, 1.2, 1.2]},
	{"id": "lot_folder", "name_ru": "Складской стеллаж", "effect": "folder_cells", "value": 1,
		"max_level": 5, "prices": [80, 180, 360, 650, 1000],
		"weight_by_hour": [1.0, 1.0, 1.0, 0.9, 0.9, 0.9, 0.8, 0.8, 0.8]},
	{"id": "lot_channel", "name_ru": "Пропускная способность", "effect": "channel_capacity", "value": 6,
		"buffer_value": 1, "max_level": 6, "prices": [70, 100, 140, 190, 250, 330],
		"weight_by_hour": [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.9, 0.9, 0.9]},
	{"id": "lot_timer", "name_ru": "Регламент обработки", "effect": "request_timer", "value": 5,
		"max_level": 5, "prices": [70, 110, 160, 230, 320],
		"weight_by_hour": [1.0, 1.0, 1.0, 0.9, 0.9, 0.9, 0.7, 0.7, 0.7]},
]

var _items: Array = []


func _init() -> void:
	_load_items()


# --- каталог ---------------------------------------------------------------

func items() -> Array:
	return _items.duplicate(true)


func item_count() -> int:
	return _items.size()


func get_item(id: String) -> Dictionary:
	for item in _items:
		if item is Dictionary and str(item.get("id", "")) == str(id):
			return item.duplicate(true)
	return {}


## Позиции каталога без гейта прогрессии (v2: все лоты доступны с H2,
## видимость магазина решает фаза/час).
func available_items() -> Array:
	return _items.duplicate(true)


func item_unlocked(_item: Dictionary) -> bool:
	return true


func level(id: String) -> int:
	var game = _game()
	if game != null and game.has_method("level"):
		return int(game.level(id))
	return level_for(get_item(id), _levels(game))


func max_level(id: String) -> int:
	var item := get_item(id)
	if item.is_empty():
		return 0
	return maxi(1, int(item.get("max_level", 1)))


## Цена следующего уровня. -1, если лот максимален (никогда не индексируем
## prices[max_level]).
func price(id: String) -> int:
	var item := get_item(id)
	if item.is_empty():
		return 0
	return price_for(item, level(id))


func can_buy(id: String) -> bool:
	var game = _game()
	if game == null:
		return false
	if not offers().has(str(id)):
		return false
	var item := get_item(id)
	if item.is_empty():
		return false
	if level(id) >= max_level(id):
		return false
	var cost := price(id)
	if cost < 0:
		return false
	return int(game.money) >= cost


func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	var game = _game()
	if game == null:
		return false
	var cost := price(id)
	if cost < 0:
		return false
	game.money = maxi(0, int(game.money) - cost)
	if game.has_signal("money_changed"):
		game.money_changed.emit(game.money)
	var new_level := level(id) + 1
	if game.has_method("set_lot_level"):
		game.set_lot_level(id, new_level)
	else:
		_apply_level_fallback(game, id, new_level)
	_play_sfx(&"money_down")
	purchased.emit(id)
	offers_changed.emit()
	if game.has_signal("toast"):
		game.toast.emit("Куплено: %s" % str(get_item(id).get("name_ru", id)))
	return true


## Агрегированный уровень эффекта (для UI/тестов).
func effect_level(effect: String) -> int:
	var game = _game()
	if game == null:
		return 0
	var target := str(EFFECT_TARGETS.get(str(effect), ""))
	if target.is_empty():
		return 0
	return int(_levels(game).get(target, 0))


# --- v2: предложения/реролл -----------------------------------------------

func offers() -> Array[String]:
	var out: Array[String] = []
	var game = _game()
	if game == null:
		return out
	for id in game.shop_offers:
		out.append(str(id))
	return out


## Сгенерировать 3 предложения на подготовку. Идемпотентно: повторный вызов
## для того же часа ничего не меняет, пока force = true.
func refresh(hour: int = 0, money: int = -1, force: bool = false) -> void:
	_load_items()
	if hour <= 0:
		return
	var game = _game()
	if game == null:
		return
	var h := maxi(1, int(hour))
	if not force and int(game.shop_offer_hour) == h and not game.shop_offers.is_empty():
		offers_changed.emit()
		return
	var m := int(money) if money >= 0 else int(game.money)
	var previous: Array = []
	for id in game.shop_offers:
		previous.append(str(id))
	game.shop_offer_hour = h
	game.shop_rerolls = 0
	game.shop_locked.clear()
	var selected := select_offers(h, _items, _levels(game), m, previous,
		_seen(game), [], _offer_count())
	_write_offers(game, selected, h)
	offers_changed.emit()


func reroll_cost() -> int:
	var game = _game()
	if game == null:
		return -1
	var max_rerolls := int(_rules().get("max_rerolls", 3))
	if int(game.shop_rerolls) >= max_rerolls:
		return -1
	if _non_maxed_count(_levels(game)) <= 0:
		return -1
	return _cost_for(int(game.shop_rerolls))


func can_reroll() -> bool:
	var game = _game()
	if game == null:
		return false
	if game.shop_offers.is_empty():
		return false
	var cost := reroll_cost()
	if cost < 0:
		return false
	return int(game.money) >= cost


## Реролл сохраняет закреплённые предложения. Стоимость 40/80/120.
func reroll() -> bool:
	if not can_reroll():
		return false
	var game = _game()
	if game == null:
		return false
	var cost := reroll_cost()
	if cost < 0:
		return false
	game.money = maxi(0, int(game.money) - cost)
	if game.has_signal("money_changed"):
		game.money_changed.emit(game.money)
	game.shop_rerolls = int(game.shop_rerolls) + 1
	var h := maxi(1, int(game.hour))
	var previous: Array = []
	for id in game.shop_offers:
		previous.append(str(id))
	var locked: Array = []
	for id in game.shop_locked:
		locked.append(str(id))
	var selected := select_offers(h, _items, _levels(game), int(game.money), previous,
		_seen(game), locked, _offer_count())
	game.shop_offer_hour = h
	_write_offers(game, selected, h)
	offers_changed.emit()
	return true


## Переключить замок предложения. Возвращает новое состояние (true = locked).
func toggle_lock(index: int) -> bool:
	var game = _game()
	if game == null:
		return false
	var ofs := offers()
	if index < 0 or index >= ofs.size():
		return false
	var id := ofs[index]
	if game.shop_locked.has(id):
		game.shop_locked.erase(id)
	else:
		game.shop_locked.append(id)
	offers_changed.emit()
	return game.shop_locked.has(id)


func is_locked(index: int) -> bool:
	var game = _game()
	if game == null:
		return false
	var ofs := offers()
	if index < 0 or index >= ofs.size():
		return false
	return game.shop_locked.has(ofs[index])


func locked_ids() -> Array[String]:
	var out: Array[String] = []
	var game = _game()
	if game == null:
		return out
	for id in game.shop_locked:
		out.append(str(id))
	return out


# --- v2: генерация (статические, тестируемые) ------------------------------

## Вес лота: база по часу × 0.5 за прошлое предложение × 1.5 за pity.
static func lot_weight(lot: Dictionary, hour: int, last_offers: Array, last_seen: Dictionary) -> float:
	var id := str(lot.get("id", ""))
	var w := 1.0
	var arr = lot.get("weight_by_hour", null)
	if arr is Array and not (arr as Array).is_empty():
		var table: Array = arr
		w = float(table[clampi(int(hour) - 1, 0, table.size() - 1)])
	var rules: Dictionary = DEFAULT_RULES
	if last_offers.has(id):
		w *= float(rules.get("last_offer_weight", 0.5))
	if last_seen is Dictionary and last_seen.has(id):
		var since := int(hour) - int(last_seen[id])
		if since >= int(rules.get("pity_hours", 2)):
			w *= float(rules.get("pity_weight", 1.5))
	return maxf(0.0, w)


## Цена следующего уровня лота. -1 при максимальном уровне.
static func price_for(lot: Dictionary, lvl: int) -> int:
	if lot.is_empty():
		return 0
	var max_level := maxi(1, int(lot.get("max_level", 1)))
	if lvl >= max_level:
		return -1
	var prices = lot.get("prices", null)
	if prices is Array and not (prices as Array).is_empty():
		var arr: Array = prices
		return maxi(0, int(arr[clampi(lvl, 0, arr.size() - 1)]))
	if lot.has("price"):
		return maxi(0, int(lot.get("price", 0)))
	return maxi(0, int(lot.get("cost", 0)))


## Уровень лота из словаря upgrades: id лота → агрегат эффекта → 0.
static func level_for(lot: Dictionary, levels: Dictionary) -> int:
	if lot.is_empty():
		return 0
	var id := str(lot.get("id", ""))
	var max_level := maxi(1, int(lot.get("max_level", 1)))
	if levels.has(id):
		return clampi(int(levels[id]), 0, max_level)
	var effect := str(lot.get("effect", ""))
	var agg := str(EFFECT_TARGETS.get(effect, ""))
	if not agg.is_empty() and levels.has(agg):
		return clampi(int(levels[agg]), 0, max_level)
	return 0


## Выбрать до count различных не-максимальных лотов.
## must_keep — закреплённые id (сохраняются в выдаче).
static func select_offers(
	hour: int,
	lots: Array,
	levels: Dictionary,
	money: int,
	last_offers: Array,
	last_seen: Dictionary,
	must_keep: Array = [],
	count: int = 3,
	rand_source = null
) -> Array[String]:
	var h := maxi(1, int(hour))
	var lot_map: Dictionary = {}
	for lot in lots:
		if lot is Dictionary:
			var id := str(lot.get("id", ""))
			if not id.is_empty():
				lot_map[id] = lot

	var result: Array[String] = []
	for raw_id in must_keep:
		var kept := str(raw_id)
		if result.has(kept) or not lot_map.has(kept):
			continue
		var kept_lot: Dictionary = lot_map[kept]
		if level_for(kept_lot, levels) >= maxi(1, int(kept_lot.get("max_level", 1))):
			continue
		result.append(kept)

	var pool: Array = []
	for lot in lots:
		if not (lot is Dictionary):
			continue
		var id := str(lot.get("id", ""))
		if id.is_empty() or result.has(id):
			continue
		if level_for(lot, levels) >= maxi(1, int(lot.get("max_level", 1))):
			continue
		pool.append(lot)

	var target := mini(maxi(0, int(count)), result.size() + pool.size())
	while result.size() < target and not pool.is_empty():
		var picked_index := _pick_weighted(pool, h, last_offers, last_seen, rand_source)
		var picked: Dictionary = pool[picked_index]
		result.append(str(picked.get("id", "")))
		pool.remove_at(picked_index)

	# Хотя бы одно доступное по деньгам предложение (если такое существует).
	if money >= 0 and not _any_affordable(result, lot_map, levels, money):
		_try_swap_affordable(result, lots, lot_map, levels, money, must_keep)
	return result


# --- служебное -------------------------------------------------------------

func _load_items() -> void:
	_items = []
	var data = _data_node()
	if data != null and data.has_method("lot_defs"):
		var raw = data.lot_defs()
		if raw is Array and not (raw as Array).is_empty():
			for item in raw:
				if item is Dictionary and not str(item.get("id", "")).is_empty():
					_items.append((item as Dictionary).duplicate(true))
	if _items.is_empty():
		for item in FALLBACK_ITEMS:
			_items.append((item as Dictionary).duplicate(true))


func _write_offers(game, ids: Array, hour: int) -> void:
	game.shop_offers.clear()
	for id in ids:
		game.shop_offers.append(str(id))
	if not (game.shop_last_seen is Dictionary):
		game.shop_last_seen = {}
	for id in game.shop_offers:
		game.shop_last_seen[str(id)] = int(hour)


func _apply_level_fallback(game, id: String, new_level: int) -> void:
	if not (game.upgrades is Dictionary):
		game.upgrades = {}
	game.upgrades[id] = new_level
	var effect := str(get_item(id).get("effect", ""))
	var target := str(EFFECT_TARGETS.get(effect, ""))
	if not target.is_empty():
		game.upgrades[target] = new_level


func _offer_count() -> int:
	return maxi(1, int(_rules().get("offers", 3)))


func _cost_for(reroll_index: int) -> int:
	var costs = _rules().get("reroll_costs", [40, 80, 120])
	if costs is Array and not (costs as Array).is_empty():
		var arr: Array = costs
		return maxi(0, int(arr[clampi(int(reroll_index), 0, arr.size() - 1)]))
	return 40


func _non_maxed_count(levels: Dictionary) -> int:
	var count := 0
	for lot in _items:
		if not (lot is Dictionary):
			continue
		if level_for(lot, levels) < maxi(1, int(lot.get("max_level", 1))):
			count += 1
	return count


func _rules() -> Dictionary:
	var data = _data_node()
	var out: Dictionary = DEFAULT_RULES.duplicate(true)
	if data != null and data.has_method("shop_rules"):
		var raw = data.shop_rules()
		if raw is Dictionary and not (raw as Dictionary).is_empty():
			for key in raw.keys():
				out[str(key)] = raw[key]
	return out


func _seen(game) -> Dictionary:
	if game == null or not (game.shop_last_seen is Dictionary):
		return {}
	return game.shop_last_seen


func _levels(game) -> Dictionary:
	if game == null:
		return {}
	if game.upgrades is Dictionary:
		return game.upgrades
	return {}


func _game():
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("Game")
	return null


func _data_node():
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("Data")
	return null


func _play_sfx(id: StringName) -> void:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return
	var audio = (loop as SceneTree).root.get_node_or_null("Audio")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(str(id))


# --- статические хелперы выбора -------------------------------------------

static func _pick_weighted(pool: Array, hour: int, last_offers: Array, last_seen: Dictionary, rand_source) -> int:
	var weights: Array = []
	var total := 0.0
	for lot in pool:
		var w := lot_weight(lot, hour, last_offers, last_seen)
		weights.append(w)
		total += w
	if total <= 0.0:
		return int(float(_randf(rand_source)) * float(pool.size())) % pool.size()
	var roll := _randf(rand_source) * total
	var acc := 0.0
	for i in range(weights.size()):
		acc += float(weights[i])
		if roll < acc:
			return i
	return pool.size() - 1


static func _any_affordable(ids: Array, lot_map: Dictionary, levels: Dictionary, money: int) -> bool:
	for raw_id in ids:
		var id := str(raw_id)
		if not lot_map.has(id):
			continue
		var p := price_for(lot_map[id], level_for(lot_map[id], levels))
		if p >= 0 and p <= money:
			return true
	return false


static func _try_swap_affordable(ids: Array, lots: Array, lot_map: Dictionary, levels: Dictionary, money: int, must_keep: Array) -> void:
	var candidate := ""
	var best := 2147483647
	for lot in lots:
		if not (lot is Dictionary):
			continue
		var id := str(lot.get("id", ""))
		if id.is_empty() or ids.has(id):
			continue
		var lvl := level_for(lot, levels)
		if lvl >= maxi(1, int(lot.get("max_level", 1))):
			continue
		var p := price_for(lot, lvl)
		if p >= 0 and p <= money and p < best:
			best = p
			candidate = id
	if candidate.is_empty():
		return
	# Заменяем самое дорогое незакреплённое предложение.
	var swap_index := -1
	var worst := -1
	for i in range(ids.size()):
		var id := str(ids[i])
		if must_keep.has(id):
			continue
		if not lot_map.has(id):
			continue
		var p := price_for(lot_map[id], level_for(lot_map[id], levels))
		if p > worst:
			worst = p
			swap_index = i
	if swap_index >= 0:
		ids[swap_index] = candidate


static func _randf(rand_source) -> float:
	if rand_source != null and rand_source.has_method("randf"):
		return clampf(float(rand_source.randf()), 0.0, 0.999999)
	return clampf(randf(), 0.0, 0.999999)
