extends SceneTree
## Headless-тест магазина (10 позиций, цены, покупки, эффекты, unlock-гейты).
## Запуск: godot --headless --path . --script tests/test_shop.gd

const SHOP := preload("res://scripts/systems/shop.gd")
const SM := preload("res://scripts/core/slot_manager.gd")

const IDS := [
	"shop_slot3", "shop_slot4", "shop_buffer", "shop_timer", "shop_zone",
	"shop_channel", "shop_section", "shop_search", "shop_shield", "shop_sla",
]
const PRICES := {
	"shop_slot3": 250, "shop_slot4": 450, "shop_buffer": 200,
	"shop_timer": 350, "shop_zone": 300, "shop_channel": 250,
	"shop_section": 300, "shop_search": 250, "shop_shield": 400,
	"shop_sla": 300,
}

var _checks: int = 0
var _fails: int = 0
var _case: String = ""
var _purchased: Array[String] = []


func _init() -> void:
	await process_frame
	var game = root.get_node_or_null("Game")
	if game == null:
		_fail("autoload Game недоступен")
		_finish()
		return
	game.start_new_run(1)
	_test_catalog()
	_test_unlocks()
	# Дальнейшие кейсы — в часе 2, когда магазин и базовые позиции открыты.
	game.hour = 2
	game.meta_unlocks["survive_hour_3"] = true
	game.meta_unlocks["survive_hour_5"] = true
	_test_money_gate()
	_test_slots()
	_test_effects()
	_test_sla_effect()
	_test_limits()
	_test_signal()
	_finish()


func _test_catalog() -> void:
	_set_case("catalog")
	var shop = SHOP.new()
	_eq(shop.item_count(), 10, "ровно 10 позиций")
	for id in IDS:
		var item := shop.get_item(id)
		_ok(not item.is_empty(), "товар %s есть" % id)
		_eq(shop.price(id), int(PRICES[id]), "цена %s" % id)
		_eq(shop.max_level(id), int(item.get("max_level", 1)), "max_level %s" % id)
		_eq(shop.level(id), 0, "начальный уровень %s" % id)
	_ok(shop.get_item("scanner").is_empty(), "сканера нет (D13)")
	_ok(shop.get_item("autosort").is_empty(), "автосортировки нет (D13)")
	var sla_item := shop.get_item("shop_sla")
	_eq(str(sla_item.get("effect", "")), "sla_add", "shop_sla: effect sla_add")
	_eq(int(sla_item.get("value", 0)), 24, "shop_sla: +24")
	_eq(shop.max_level("shop_sla"), 3, "shop_sla: max 3 уровня")


func _test_unlocks() -> void:
	_set_case("unlocks")
	var game = root.get_node("Game")
	var shop = SHOP.new()
	# Час 1: магазин ещё закрыт, но shop_sla доступен всегда.
	game.start_new_run(1)
	_ok(not shop.item_unlocked(shop.get_item("shop_slot3")), "час 1: slot3 закрыт")
	_ok(not shop.can_buy("shop_slot3"), "час 1: slot3 нельзя купить")
	_ok(shop.item_unlocked(shop.get_item("shop_sla")), "shop_sla открыт всегда")
	game.money = 300
	_ok(shop.can_buy("shop_sla"), "shop_sla можно купить на часе 1")
	game.money = 150
	var available = shop.available_items()
	_eq(available.size(), 1, "час 1: в available_items только shop_sla")
	_ok(not shop.item_unlocked(shop.get_item("shop_search")), "search закрыт до мета")
	_ok(not shop.item_unlocked(shop.get_item("shop_shield")), "shield закрыт до мета")
	game.hour = 2
	_ok(shop.item_unlocked(shop.get_item("shop_slot3")), "час 2: базовые позиции открыты")
	_ok(not shop.item_unlocked(shop.get_item("shop_search")), "час 2: search ещё закрыт")
	game.meta_unlocks["survive_hour_3"] = true
	_ok(shop.item_unlocked(shop.get_item("shop_search")), "мета survive_hour_3 открывает search")
	_ok(not shop.item_unlocked(shop.get_item("shop_shield")), "shield ещё закрыт")
	game.meta_unlocks["survive_hour_5"] = true
	_ok(shop.item_unlocked(shop.get_item("shop_shield")), "мета survive_hour_5 открывает shield")
	_eq(shop.available_items().size(), 10, "все 10 позиций открыты")


func _test_money_gate() -> void:
	_set_case("money")
	var game = root.get_node("Game")
	var shop = SHOP.new()
	game.money = 249
	_ok(not shop.can_buy("shop_slot3"), "249 $ мало для слота за 250")
	_ok(not shop.buy("shop_slot3"), "buy без денег → false")
	_eq(game.money, 249, "деньги не списаны")
	game.money = 250
	_ok(shop.can_buy("shop_slot3"), "250 $ хватает")
	_ok(not shop.can_buy("shop_slot4"), "на 450 не хватает")


func _test_slots() -> void:
	_set_case("slots")
	var game = root.get_node("Game")
	var shop = SHOP.new()
	game.money = 1000
	_ok(shop.buy("shop_slot3"), "покупка третьего слота")
	_eq(game.money, 750, "списано 250")
	_eq(shop.level("shop_slot3"), 1, "уровень товара 1")
	_eq(int(game.upgrades.get("slot_level", 0)), 1, "slot_level = 1")
	_eq(SM.new().max_slots(), 3, "SlotManager видит 3 слота")
	_ok(not shop.can_buy("shop_slot3"), "повторно слот 3 не купить")
	_ok(shop.buy("shop_slot4"), "покупка четвёртого слота")
	_eq(int(game.upgrades.get("slot_level", 0)), 2, "slot_level = 2")
	_eq(SM.new().max_slots(), 4, "SlotManager видит 4 слота")
	_eq(game.money, 300, "после двух слотов 300 $")

	# Обратный порядок покупки: четвёртый слот не должен «съедать» третий.
	game.upgrades.clear()
	game.money = 1000
	var shop2 = SHOP.new()
	_ok(shop2.buy("shop_slot4"), "сначала куплен 4-й слот")
	_eq(shop2.level("shop_slot3"), 0, "3-й слот ещё не куплен")
	_ok(shop2.can_buy("shop_slot3"), "3-й слот доступен после 4-го")
	_ok(not shop2.can_buy("shop_slot4"), "4-й слот больше не купить")
	_ok(shop2.buy("shop_slot3"), "3-й слот куплен вторым")
	_eq(int(game.upgrades.get("slot_level", 0)), 2, "slot_level = 2 в обратном порядке")


func _test_effects() -> void:
	_set_case("effects")
	var game = root.get_node("Game")
	var shop = SHOP.new()
	game.money = 100000
	_ok(shop.buy("shop_buffer"), "буфер куплен")
	_eq(int(game.upgrades.get("buffer_level", 0)), 1, "buffer_level = 1")
	_ok(shop.buy("shop_timer"), "таймер куплен")
	_eq(int(game.upgrades.get("timer_level", 0)), 1, "timer_level = 1")
	_ok(shop.buy("shop_zone"), "зона куплена")
	_eq(int(game.upgrades.get("zone_level", 0)), 1, "zone_level = 1")
	_ok(shop.buy("shop_channel"), "канал куплен")
	_eq(int(game.upgrades.get("channel_level", 0)), 1, "channel_level = 1")
	_ok(shop.buy("shop_section"), "секция куплена")
	_eq(int(game.upgrades.get("sections_unlocked", 0)), 1, "sections_unlocked = 1")
	_ok(game.registry.sections.has("D"), "реестр получил секцию D")
	_ok(shop.buy("shop_search"), "поиск куплен")
	_eq(int(game.upgrades.get("search_unlocked", 0)), 1, "search_unlocked = 1")
	_ok(shop.buy("shop_shield"), "щит куплен")
	_eq(int(game.upgrades.get("shield_unlocked", 0)), 1, "shield_unlocked = 1")


func _test_sla_effect() -> void:
	_set_case("sla_add")
	var game = root.get_node("Game")
	var shop = SHOP.new()
	game.money = 10000
	game.upgrades.erase("shop_sla")
	game.upgrades.erase("sla_level")
	game.sla = 128.0
	_ok(shop.buy("shop_sla"), "shop_sla куплен")
	_approx(float(game.sla), 152.0, 0.0001, "SLA 128 → 152")
	_eq(shop.level("shop_sla"), 1, "уровень shop_sla = 1")
	_eq(shop.effect_level("sla_add"), 1, "effect_level(sla_add) = 1")
	_eq(int(game.money), 9700, "списано 300")
	_ok(shop.buy("shop_sla"), "shop_sla куплен 2-й раз")
	_approx(float(game.sla), 176.0, 0.0001, "SLA 152 → 176")
	_ok(shop.buy("shop_sla"), "shop_sla куплен 3-й раз")
	_approx(float(game.sla), 200.0, 0.0001, "SLA 176 → 200")
	_eq(shop.level("shop_sla"), 3, "уровень shop_sla = 3")
	_ok(not shop.can_buy("shop_sla"), "4-й уровень не продаётся (max 3)")
	# add_sla клампит: покупка при 180 не поднимает выше 200.
	game.upgrades.erase("shop_sla")
	game.upgrades.erase("sla_level")
	game.sla = 180.0
	_ok(shop.buy("shop_sla"), "shop_sla при SLA 180")
	_approx(float(game.sla), 200.0, 0.0001, "SLA клампится на 200")


func _test_limits() -> void:
	_set_case("limits")
	var game = root.get_node("Game")
	var shop = SHOP.new()
	game.money = 100000
	game.upgrades["shop_buffer"] = 2
	game.upgrades["buffer_level"] = 2
	_ok(not shop.can_buy("shop_buffer"), "буфер max 2")
	_ok(not shop.buy("shop_buffer"), "buy сверх max → false")
	game.upgrades["shop_timer"] = 3
	game.upgrades["timer_level"] = 3
	_ok(not shop.can_buy("shop_timer"), "таймер max 3")
	_ok(shop.can_buy("shop_zone"), "зону ещё можно купить")
	_ok(not shop.can_buy("нет_товара"), "неизвестный id → false")


func _test_signal() -> void:
	_set_case("signal")
	var game = root.get_node("Game")
	var shop = SHOP.new()
	game.money = 10000
	shop.purchased.connect(_on_purchased)
	_purchased.clear()
	_ok(shop.buy("shop_zone"), "покупка для сигнала")
	_eq(_purchased.size(), 1, "purchased эмитится")
	if not _purchased.is_empty():
		_eq(_purchased[0], "shop_zone", "id в сигнале")


# --- assert-хелперы --------------------------------------------------------

func _set_case(name: String) -> void:
	_case = name


func _ok(condition: bool, message: String) -> bool:
	_checks += 1
	if condition:
		return true
	_fail(message)
	return false


func _eq(actual, expected, message: String) -> bool:
	_checks += 1
	if actual == expected:
		return true
	_fail("%s — получено %s, ожидалось %s" % [message, str(actual), str(expected)])
	return false


func _approx(actual: float, expected: float, eps: float, message: String) -> bool:
	_checks += 1
	if absf(actual - expected) <= eps:
		return true
	_fail("%s — получено %.6f, ожидалось %.6f" % [message, actual, expected])
	return false


func _fail(message: String) -> void:
	_fails += 1
	print("FAIL [%s] %s" % [_case, message])


func _on_purchased(id: String) -> void:
	_purchased.append(id)


func _finish() -> void:
	print("test_shop: проверок %d, провалов %d" % [_checks, _fails])
	print("PASS test_shop" if _fails == 0 else "FAIL test_shop")
	quit(0 if _fails == 0 else 1)
