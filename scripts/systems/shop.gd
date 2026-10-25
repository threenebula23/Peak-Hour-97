class_name Shop
extends RefCounted
## Магазин: 10 позиций из data/balance.json → shop (D13 + SLA +24, п.13).
##
## Уровни покупок хранятся в Game.upgrades. Для совместимости с ядром
## дублируются агрегированные ключи эффектов: slot_level, buffer_level,
## timer_level, zone_level, channel_level, sections_unlocked,
## search_unlocked, shield_unlocked.

signal purchased(id: String)

const EFFECT_TARGETS := {
	"connection_slots": "slot_level",
	"buffer_slots": "buffer_level",
	"packet_timer": "timer_level",
	"zone_width": "zone_level",
	"channel_capacity": "channel_level",
	"sections": "sections_unlocked",
	"search_highlight": "search_unlocked",
	"shield": "shield_unlocked",
	"sla_add": "sla_level",
}

const FALLBACK_ITEMS := [
	{"id": "shop_slot3", "name_ru": "Третий слот", "effect": "connection_slots", "value": 1, "price": 250, "max_level": 1},
	{"id": "shop_slot4", "name_ru": "Четвёртый слот", "effect": "connection_slots", "value": 1, "price": 450, "max_level": 1},
	{"id": "shop_buffer", "name_ru": "Буфер +2", "effect": "buffer_slots", "value": 2, "price": 200, "max_level": 2},
	{"id": "shop_timer", "name_ru": "Таймер пакетов +4 с", "effect": "packet_timer", "value": 4, "price": 350, "max_level": 3},
	{"id": "shop_zone", "name_ru": "Зона +5%", "effect": "zone_width", "value": 0.05, "price": 300, "max_level": 3},
	{"id": "shop_channel", "name_ru": "Канал +25", "effect": "channel_capacity", "value": 25, "price": 250, "max_level": 4},
	{"id": "shop_section", "name_ru": "Новая секция", "effect": "sections", "value": 1, "price": 300, "max_level": 5},
	{"id": "shop_search", "name_ru": "Поиск", "effect": "search_highlight", "value": 1, "price": 250, "max_level": 1},
	{"id": "shop_shield", "name_ru": "Щит", "effect": "shield", "value": 1, "price": 400, "max_level": 1},
	{"id": "shop_sla", "name_ru": "SLA +24", "effect": "sla_add", "value": 24, "price": 300, "max_level": 3},
]

var _items: Array = []


func _init() -> void:
	refresh()


func refresh() -> void:
	_items = []
	var data = _data_node()
	var raw = null
	if data != null and data.get("balance") is Dictionary:
		raw = data.balance.get("shop", null)
	if raw is Array and not raw.is_empty():
		for item in raw:
			if item is Dictionary and not str(item.get("id", "")).is_empty():
				_items.append(item.duplicate(true))
	if _items.is_empty():
		for item in FALLBACK_ITEMS:
			_items.append(item.duplicate(true))


func items() -> Array:
	return _items.duplicate(true)


## Каталог без закрытых прогрессией позиций. shop_sla доступен всегда.
func available_items() -> Array:
	var out: Array = []
	for item in _items:
		if item is Dictionary and item_unlocked(item):
			out.append(item.duplicate(true))
	return out


## Открыта ли позиция: shop_sla всегда; shop_search/shield — по мета-награде;
## остальные — по открытию магазина (progression.unlocks.shop).
func item_unlocked(item: Dictionary) -> bool:
	var key := _unlock_key(str(item.get("id", "")))
	if key.is_empty():
		return true
	var game = _game()
	if game != null and game.has_method("feature_unlocked"):
		return bool(game.feature_unlocked(key))
	return true


func item_count() -> int:
	return _items.size()


func get_item(id: String) -> Dictionary:
	for item in _items:
		if str(item.get("id", "")) == str(id):
			return item.duplicate(true)
	return {}


func level(id: String) -> int:
	var game = _game()
	if game == null:
		return 0
	var upgrades: Dictionary = game.upgrades if game.upgrades is Dictionary else {}
	if upgrades.has(str(id)):
		return int(upgrades[str(id)])
	var item := get_item(id)
	if item.is_empty():
		return 0
	var effect := str(item.get("effect", ""))
	var target := str(EFFECT_TARGETS.get(effect, ""))
	var aggregate := 0
	if not target.is_empty():
		aggregate = int(upgrades.get(target, 0))
	# Для двух слотовых товаров агрегат slot_level раскладывается по порядку
	# с учётом уже купленного второго товара.
	if effect == "connection_slots":
		var other_id := "shop_slot4" if id == "shop_slot3" else "shop_slot3"
		var other_level := int(upgrades.get(other_id, 0))
		return clampi(aggregate - other_level, 0, 1)
	return clampi(aggregate, 0, max_level(id))


func max_level(id: String) -> int:
	var item := get_item(id)
	if item.is_empty():
		return 0
	return maxi(1, int(item.get("max_level", 1)))


func price(id: String) -> int:
	var item := get_item(id)
	if item.is_empty():
		return 0
	var current := level(id)
	var prices = item.get("prices", null)
	if prices is Array and not (prices as Array).is_empty():
		var arr: Array = prices
		return maxi(0, int(arr[mini(current, arr.size() - 1)]))
	if item.has("price"):
		return maxi(0, int(item.get("price", 0)))
	return maxi(0, int(item.get("cost", 0)))


func can_buy(id: String) -> bool:
	var item := get_item(id)
	if item.is_empty():
		return false
	if not item_unlocked(item):
		return false
	if level(id) >= max_level(id):
		return false
	var game = _game()
	if game == null:
		return false
	return int(game.money) >= price(id)


func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	var item := get_item(id)
	var game = _game()
	if game == null:
		return false
	var cost := price(id)
	game.money = maxi(0, int(game.money) - cost)
	if game.has_signal("money_changed"):
		game.money_changed.emit(game.money)
	if not (game.upgrades is Dictionary):
		game.upgrades = {}
	var current := level(id)
	game.upgrades[id] = current + 1
	var effect := str(item.get("effect", ""))
	var target := str(EFFECT_TARGETS.get(effect, ""))
	if not target.is_empty():
		game.upgrades[target] = int(game.upgrades.get(target, 0)) + 1
	if effect == "sections":
		_unlock_section(game)
	elif effect == "sla_add":
		# SLA +24 за уровень; Game.add_sla сам клампит до MAX_SLA.
		var value := float(item.get("value", 24))
		if game.has_method("add_sla"):
			game.add_sla(value, "shop")
	_play_sfx(&"money_down")
	purchased.emit(id)
	if game.has_signal("toast"):
		game.toast.emit("Куплено: %s" % str(item.get("name_ru", id)))
	return true


## Агрегированный уровень эффекта (для UI/тестов).
func effect_level(effect: String) -> int:
	var game = _game()
	if game == null:
		return 0
	var target := str(EFFECT_TARGETS.get(effect, ""))
	if target.is_empty():
		return 0
	return int(game.upgrades.get(target, 0))


# --- служебное -------------------------------------------------------------

## Ключ открытия позиции. Данные — из Data, иначе локальная копия правила.
func _unlock_key(id: String) -> String:
	var data = _data_node()
	if data != null and data.has_method("shop_unlock_key"):
		return str(data.shop_unlock_key(id))
	match id:
		"shop_sla":
			return ""
		"shop_search":
			return "search"
		"shop_shield":
			return "shield"
		_:
			return "shop"


func _unlock_section(game) -> void:
	if game.registry == null or not game.registry.has_method("create_section"):
		return
	for letter in ["D", "E", "F", "G", "H"]:
		if not game.registry.sections.has(letter):
			game.registry.create_section(letter)
			return


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
