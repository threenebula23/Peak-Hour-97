extends SceneTree
## Headless-тест магазина v2: 8 лотов, 3 предложения, веса/pity, реролл
## 40/80/120 (макс 3), замки, покупки/эффекты, save/load.
## Запуск: godot --headless --path . --script tests/test_shop.gd

const SHOP := preload("res://scripts/systems/shop.gd")
const SM := preload("res://scripts/core/slot_manager.gd")

const IDS := [
	"lot_slots", "lot_speed", "lot_sla", "lot_shield",
	"lot_money", "lot_folder", "lot_channel", "lot_timer", "lot_udp",
]
const FIRST_PRICES := {
	"lot_slots": 90, "lot_speed": 55, "lot_sla": 80, "lot_shield": 100,
	"lot_money": 70, "lot_folder": 50, "lot_channel": 45, "lot_timer": 45,
	"lot_udp": 60,
}
const MAX_LEVELS := {
	"lot_slots": 4, "lot_speed": 6, "lot_sla": 4, "lot_shield": 3,
	"lot_money": 8, "lot_folder": 5, "lot_channel": 6, "lot_timer": 5,
	"lot_udp": 4,
}

var _checks: int = 0
var _fails: int = 0
var _case: String = ""
var _purchased: Array[String] = []
var _offers_changed: int = 0
var _game = null


func _init() -> void:
	await process_frame
	_game = root.get_node_or_null("Game")
	if _game == null:
		_fail("autoload Game недоступен")
		_finish()
		return
	_test_catalog()
	_test_refresh()
	_test_weights()
	_test_affordable()
	_test_reroll()
	_test_lock()
	_test_buy_and_effects()
	_test_slot_and_folder_effects()
	_test_maxed()
	_test_save_load()
	_test_signals()
	_finish()


# --- кейсы -----------------------------------------------------------------

func _test_catalog() -> void:
	_set_case("catalog")
	_game.start_new_run(1)
	var shop = SHOP.new()
	_eq(shop.item_count(), 9, "ровно 9 лотов")
	var total := 0
	for id in IDS:
		var item: Dictionary = shop.get_item(id)
		_ok(not item.is_empty(), "лот %s есть" % id)
		_eq(shop.price(id), int(FIRST_PRICES[id]), "цена первого уровня %s" % id)
		_eq(shop.max_level(id), int(MAX_LEVELS[id]), "max_level %s" % id)
		_eq(shop.level(id), 0, "начальный уровень %s" % id)
		for p in item.get("prices", []):
			total += int(p)
	_eq(total, 8825, "сумма цен всех лотов = 8 825")
	_ok(shop.get_item("scanner").is_empty(), "сканера нет")
	var udp_item: Dictionary = shop.get_item("lot_udp")
	_eq(str(udp_item.get("effect", "")), "udp_success", "lot_udp effect")
	_approx(float(udp_item.get("value", 0.0)), 0.10, 0.0001, "lot_udp value")
	_eq(shop.max_level("lot_udp"), 4, "lot_udp max_level 4")
	_eq(shop.max_level("нет_товара"), 0, "неизвестный лот → max_level 0")
	_eq(shop.price("нет_товара"), 0, "неизвестный лот → price 0")
	# Максимальный уровень: price() = -1, без индексации prices[max_level].
	_game.upgrades["lot_timer"] = 5
	_game.upgrades["timer_level"] = 5
	_eq(shop.price("lot_timer"), -1, "maxed lot_timer → price -1")
	_ok(not shop.can_buy("lot_timer"), "maxed нельзя купить")
	_game.upgrades.clear()


func _test_refresh() -> void:
	_set_case("refresh")
	var shop = _reset(2, 1000)
	shop.refresh(2, 1000, true)
	var ofs: Array = shop.offers()
	_eq(ofs.size(), 3, "ровно 3 предложения")
	_eq(_distinct(ofs), 3, "предложения без дублей")
	for id in ofs:
		_ok(IDS.has(id), "оффер %s из каталога" % id)
		_ok(shop.level(id) < shop.max_level(id), "оффер %s не максимален" % id)
	_eq(int(_game.shop_offer_hour), 2, "shop_offer_hour = 2")
	_eq(int(_game.shop_rerolls), 0, "после новой подготовки рероллы = 0")
	_eq(shop.offers(), _game.shop_offers, "offers() читает Game.shop_offers")
	# Повторный refresh в том же часу идемпотентен (без force).
	var before: Array = shop.offers()
	shop.refresh(2, 1000)
	_eq(shop.offers(), before, "refresh без force не меняет ассортимент")

	# Инварианты на 40 генерациях (force).
	for i in range(40):
		shop.refresh(2, 1000, true)
		var current: Array = shop.offers()
		if current.size() != 3:
			_fail("генерация %d: не 3 оффера (%d)" % [i, current.size()])
			break
		if _distinct(current) != current.size():
			_fail("генерация %d: дубли в офферах" % i)
			break
		var bad := false
		for id in current:
			if shop.level(id) >= shop.max_level(id):
				bad = true
		if bad:
			_fail("генерация %d: максимальный лот в офферах" % i)
			break
	_ok(true, "40 генераций: 3/без дублей/без maxed")


func _test_weights() -> void:
	_set_case("weights")
	var shop = SHOP.new()
	var slots: Dictionary = shop.get_item("lot_slots")
	_approx(SHOP.lot_weight(slots, 2, [], {}), 1.0, 0.0001, "lot_slots H2 = 1.0")
	_approx(SHOP.lot_weight(slots, 5, [], {}), 1.0, 0.0001, "lot_slots H5 = 1.0")
	_approx(SHOP.lot_weight(slots, 9, [], {}), 0.8, 0.0001, "lot_slots H9 = 0.8")
	_approx(SHOP.lot_weight(slots, 9, ["lot_slots"], {}), 0.4, 0.0001, "прошлый оффер ×0.5")
	_approx(SHOP.lot_weight(slots, 9, [], {"lot_slots": 7}), 1.2, 0.0001, "pity (2 часа) ×1.5")
	_approx(SHOP.lot_weight(slots, 9, [], {"lot_slots": 8}), 0.8, 0.0001, "1 час назад — без pity")
	_approx(SHOP.lot_weight(slots, 9, ["lot_slots"], {"lot_slots": 7}), 0.6, 0.0001, "×0.5 и ×1.5 вместе")
	_approx(SHOP.lot_weight(shop.get_item("lot_shield"), 2, [], {}), 0.3, 0.0001, "lot_shield H2 = 0.3")
	_approx(SHOP.lot_weight(shop.get_item("lot_shield"), 9, [], {}), 1.0, 0.0001, "lot_shield H9 = 1.0")
	_approx(SHOP.lot_weight(shop.get_item("lot_money"), 9, [], {}), 1.2, 0.0001, "lot_money H9 = 1.2")
	_approx(SHOP.lot_weight(shop.get_item("lot_timer"), 9, [], {}), 0.7, 0.0001, "lot_timer H9 = 0.7")
	_approx(SHOP.lot_weight(shop.get_item("lot_folder"), 5, [], {}), 0.9, 0.0001, "lot_folder H5 = 0.9")

	# Pity через реальную генерацию: лот, которого не было 2+ часа, получает ×1.5.
	var seen := {"lot_shield": 1}
	var weights: Array = []
	for lot in shop.items():
		weights.append(SHOP.lot_weight(lot, 3, [], seen))
	_ok(weights.size() == 9, "веса считаются для всех 9 лотов")
	_approx(SHOP.lot_weight(shop.get_item("lot_udp"), 2, [], {}), 0.8, 0.0001,
		"lot_udp H2 = 0.8")
	_approx(SHOP.lot_weight(shop.get_item("lot_udp"), 9, [], {}), 1.0, 0.0001,
		"lot_udp H9 = 1.0")


func _test_affordable() -> void:
	_set_case("affordable")
	var shop = _reset(2, 0)
	shop.refresh(2, 0, true)
	_eq(shop.offers().size(), 3, "при 0 $ всё равно 3 оффера (без краша)")
	for i in range(30):
		_game.money = 49
		shop.refresh(2, 49, true)
		var ofs: Array = shop.offers()
		var has_cheap := false
		for id in ofs:
			var cost := int(shop.price(str(id)))
			if cost >= 0 and cost <= 49:
				has_cheap = true
		if not has_cheap:
			_fail("при 49 $ нет доступного лота (офферы: %s)" % str(ofs))
			break
	_ok(true, "при 49 $ всегда есть доступный лот")
	# Дорогие лоты не заменяются, если доступных нет.
	_game.money = 40
	shop.refresh(2, 40, true)
	_eq(shop.offers().size(), 3, "при 40 $ предложения не ломаются")


func _test_reroll() -> void:
	_set_case("reroll")
	var shop = _reset(2, 1000)
	shop.refresh(2, 1000, true)
	_eq(shop.reroll_cost(), 40, "первый реролл 40 $")
	_ok(shop.can_reroll(), "реролл доступен")
	_ok(shop.reroll(), "reroll #1")
	_eq(int(_game.money), 960, "списано 40")
	_eq(int(_game.shop_rerolls), 1, "shop_rerolls = 1")
	_eq(shop.offers().size(), 3, "после реролла 3 оффера")
	_eq(_distinct(shop.offers()), 3, "после реролла без дублей")
	_eq(shop.reroll_cost(), 80, "второй реролл 80 $")
	_ok(shop.reroll(), "reroll #2")
	_eq(int(_game.money), 880, "списано 80")
	_eq(shop.reroll_cost(), 120, "третий реролл 120 $")
	_ok(shop.reroll(), "reroll #3")
	_eq(int(_game.money), 760, "списано 120")
	_eq(int(_game.shop_rerolls), 3, "shop_rerolls = 3")
	_eq(shop.reroll_cost(), -1, "после лимита cost = -1")
	_ok(not shop.can_reroll(), "после лимита реролл недоступен")
	_ok(not shop.reroll(), "4-й reroll → false")
	_eq(int(_game.money), 760, "деньги не списаны после лимита")

	# Недостаточно денег.
	shop = _reset(2, 39)
	shop.refresh(2, 39, true)
	_eq(shop.reroll_cost(), 40, "цена реролла 40 $")
	_ok(not shop.can_reroll(), "39 $ мало для реролла")
	_ok(not shop.reroll(), "reroll без денег → false")
	_eq(int(_game.money), 39, "деньги не списаны")

	# end_hour сбрасывает рероллы на новой подготовке.
	shop = _reset(2, 1000)
	shop.refresh(2, 1000, true)
	shop.reroll()
	_eq(int(_game.shop_rerolls), 1, "перед end_hour: 1 реролл")
	_game.end_hour()
	_eq(int(_game.shop_rerolls), 0, "end_hour сбрасывает рероллы")
	_eq(_game.shop_locked.size(), 0, "end_hour очищает замки")


func _test_lock() -> void:
	_set_case("lock")
	var shop = _reset(2, 1000)
	shop.refresh(2, 1000, true)
	var ofs: Array = shop.offers()
	var locked_id: String = str(ofs[1])
	_ok(shop.toggle_lock(1), "toggle_lock(1) → locked")
	_ok(shop.is_locked(1), "is_locked(1)")
	_ok(_game.shop_locked.has(locked_id), "id попал в Game.shop_locked")
	_ok(not shop.toggle_lock(-1), "невалидный индекс → false")
	_ok(not shop.is_locked(99), "is_locked(99) → false")

	_ok(shop.reroll(), "реролл с замком")
	_ok(shop.offers().has(locked_id), "закреплённый лот остался после реролла")
	_ok(shop.is_locked(0), "закреплённый лот стоит первым (must_keep)")
	_eq(shop.offers().size(), 3, "после реролла с замком всё ещё 3 оффера")

	_ok(not shop.toggle_lock(0), "toggle_lock(0) → unlocked")
	_ok(not shop.is_locked(0), "замок снят")
	shop.reroll()
	_ok(shop.offers().size() == 3, "реролл без замков")


func _test_buy_and_effects() -> void:
	_set_case("buy")
	var shop = _reset(2, 10000)
	_set_offers(["lot_sla", "lot_slots", "lot_money"])
	_eq(shop.price("lot_sla"), 80, "lot_sla цена 80")
	_ok(shop.buy("lot_sla"), "покупка lot_sla")
	_eq(int(_game.money), 9920, "списано 80")
	_eq(shop.level("lot_sla"), 1, "уровень lot_sla = 1")
	_eq(_game.level("sla_level"), 1, "агрегат sla_level = 1")
	_approx(_game.sla_cap(), 100.0, 0.0001, "кап SLA 60 → 100")
	_approx(float(_game.sla), 100.0, 0.0001, "SLA сразу 60 → 100")
	_eq(shop.price("lot_sla"), 160, "цена 2-го уровня 160")
	_ok(shop.buy("lot_sla"), "покупка lot_sla 2-й раз")
	_eq(shop.price("lot_sla"), 270, "цена 3-го уровня 270")
	_eq(int(_game.money), 9760, "после второй покупки 9760")
	_approx(float(_game.sla), 140.0, 0.0001, "SLA 100 → 140")

	_ok(shop.buy("lot_slots"), "покупка lot_slots")
	_eq(shop.level("lot_slots"), 1, "lot_slots = 1")
	_eq(_game.level("slot_level"), 1, "slot_level = 1")
	_ok(shop.buy("lot_money"), "покупка lot_money")
	_approx(_game.money_mult(), 1.05, 0.0001, "money_mult ×1.05")
	_eq(shop.level("lot_money"), 1, "lot_money уровень 1")

	# channel/speed/timer/shield — каждый эффект применяется сразу.
	_set_offers(["lot_channel", "lot_speed", "lot_timer"])
	_ok(shop.buy("lot_channel"), "покупка lot_channel")
	_approx(_game.channel_capacity(), 16.0, 0.0001, "канал 10 → 16")
	_eq(_game.buffer_limit(), 7, "буфер 6 → 7")
	_ok(shop.buy("lot_speed"), "покупка lot_speed")
	_approx(_game.speed_mult(), 0.90, 0.0001, "скорость ×0.90")
	_ok(shop.buy("lot_timer"), "покупка lot_timer")
	_approx(_game.request_timer(), 37.0, 0.0001, "таймер запроса 30 → 37")

	_set_offers(["lot_shield", "lot_sla", "lot_money"])
	_ok(shop.buy("lot_shield"), "покупка lot_shield")
	_eq(_game.shield_max(), 1, "1 заряд щита")
	_eq(_game.shield_charges, 1, "щит заряжен сразу")

	# UDP-повторитель: 40% → 50% за уровень, кап 80%.
	_set_offers(["lot_udp", "lot_sla", "lot_money"])
	_approx(_game.udp_success_chance(), 0.40, 0.0001, "UDP до покупки 40%")
	_ok(shop.buy("lot_udp"), "покупка lot_udp")
	_eq(shop.level("lot_udp"), 1, "lot_udp = 1")
	_approx(_game.udp_success_chance(), 0.50, 0.0001, "UDP после покупки 50%")
	_ok(shop.buy("lot_udp"), "lot_udp уровень 2")
	_ok(shop.buy("lot_udp"), "lot_udp уровень 3")
	_approx(_game.udp_success_chance(), 0.70, 0.0001, "lot_udp 3 → 70%")
	_ok(shop.buy("lot_udp"), "lot_udp уровень 4")
	_approx(_game.udp_success_chance(), 0.80, 0.0001, "lot_udp 4 → 80%")
	_eq(shop.price("lot_udp"), -1, "maxed lot_udp → price -1")
	_ok(not shop.buy("lot_udp"), "5-й уровень lot_udp не продаётся")

	# Купить можно только то, что в текущих предложениях.
	_set_offers(["lot_channel", "lot_speed", "lot_timer"])
	_ok(not shop.buy("lot_money"), "лот вне предложений купить нельзя")
	_ok(not shop.can_buy("lot_money"), "can_buy вне предложений → false")
	_ok(not shop.buy("нет_такого"), "неизвестный id → false")

	# Недостаточно денег.
	shop = _reset(2, 10000)
	_set_offers(["lot_slots"])
	_game.money = 89
	_ok(not shop.can_buy("lot_slots"), "89 $ мало для 90")
	_ok(not shop.buy("lot_slots"), "buy без денег → false")
	_eq(int(_game.money), 89, "деньги не списаны")


func _test_slot_and_folder_effects() -> void:
	_set_case("slots/folder")
	var shop = _reset(2, 100000)
	_set_offers(["lot_slots"])
	_ok(shop.buy("lot_slots"), "slot #1")
	_eq(SM.new().max_slots(), 2, "SlotManager видит 2 слота")
	_ok(shop.buy("lot_slots"), "slot #2")
	_eq(SM.new().max_slots(), 3, "SlotManager видит 3 слота")
	_ok(shop.buy("lot_slots"), "slot #3")
	_ok(shop.buy("lot_slots"), "slot #4")
	_eq(SM.new().max_slots(), 5, "SlotManager видит 5 слотов")
	_eq(shop.price("lot_slots"), -1, "maxed lot_slots → price -1")
	_ok(not shop.buy("lot_slots"), "5-й уровень не продаётся")

	shop = _reset(2, 100000)
	_set_offers(["lot_folder"])
	var folder = _first_folder()
	_ok(folder != null, "есть существующая папка для роста")
	var probe = null
	if folder != null:
		probe = _game.registry.create_file("рост_папки", "text", str(folder.id))
		_ok(probe != null, "файл в папке до покупки лота создан")
	var probe_origin: Vector2i = probe.origin if probe != null else Vector2i.ZERO
	var probe_shape := str(probe.shape_id) if probe != null else "O1"
	var probe_rotation := int(probe.rotation) if probe != null else 0
	var dims: Vector2i = _game.folder_dims()
	_eq(dims.x, 5, "folder старт: 5")
	_eq(dims.y, 4, "folder старт: 4")
	_ok(shop.buy("lot_folder"), "folder #1")
	dims = _game.folder_dims()
	_eq(dims.x, 6, "folder #1: 6 столбцов")
	_eq(dims.y, 4, "folder #1: 4 строки")
	if folder != null:
		_eq(int(folder.cols), 6, "существующая папка выросла до 6 столбцов")
		_eq(int(folder.rows), 4, "существующая папка выросла до 4 строк")
		if probe != null:
			_eq(probe.origin, probe_origin, "origin файла не изменился при росте")
			_ok(_game.registry.can_place(folder, probe_shape, probe_origin,
				probe_rotation, str(probe.id)),
				"файл после роста лежит в валидных клетках")
	for i in range(4):
		shop.buy("lot_folder")
	dims = _game.folder_dims()
	_eq(dims.x, 9, "folder max: 9 столбцов")
	_eq(dims.y, 6, "folder max: 6 строк")
	if folder != null:
		_eq(int(folder.cols), 9, "существующая папка выросла до 9 столбцов")
		_eq(int(folder.rows), 6, "существующая папка выросла до 6 строк")
		if probe != null:
			_eq(probe.origin, probe_origin, "origin файла не изменился на max")
			_ok(_game.registry.can_place(folder, probe_shape, probe_origin,
				probe_rotation, str(probe.id)),
				"файл после max-роста лежит в валидных клетках")
	_eq(shop.level("lot_folder"), 5, "folder уровень 5")
	_eq(shop.price("lot_folder"), -1, "maxed lot_folder → price -1")


func _test_maxed() -> void:
	_set_case("all_maxed")
	var shop = _reset(2, 100000)
	for id in IDS:
		_game.set_lot_level(id, int(MAX_LEVELS[id]))
	shop.refresh(2, 100000, true)
	_eq(shop.offers().size(), 0, "все лоты maxed → 0 офферов (без краша)")
	_eq(shop.reroll_cost(), -1, "реролл недоступен")
	_ok(not shop.can_reroll(), "can_reroll → false")
	_ok(not shop.reroll(), "reroll → false")
	for id in IDS:
		_eq(shop.price(id), -1, "maxed %s → price -1" % id)
		_ok(not shop.can_buy(id), "maxed %s нельзя купить" % id)


func _test_save_load() -> void:
	_set_case("save/load")
	var shop = _reset(2, 1000)
	shop.refresh(2, 1000, true)
	shop.toggle_lock(0)
	shop.reroll()
	_eq(int(_game.shop_rerolls), 1, "перед save: 1 реролл")
	var saved_offers: Array = shop.offers()
	var saved_locked: Array = shop.locked_ids()
	var saved_money := int(_game.money)
	_ok(_game.save_game(), "save_game")

	_game.shop_offers.clear()
	_game.shop_rerolls = 0
	_game.shop_offer_hour = 0
	_game.shop_locked.clear()
	_game.money = 1
	_ok(_game.load_game(), "load_game")
	_eq(shop.offers(), saved_offers, "офферы восстановлены из сейва")
	_eq(int(_game.shop_rerolls), 1, "рероллы восстановлены")
	_eq(int(_game.shop_offer_hour), 2, "час офферов восстановлен")
	_eq(shop.locked_ids(), saved_locked, "замки восстановлены")
	_eq(int(_game.money), saved_money, "деньги восстановлены")
	for id in shop.offers():
		_ok(shop.level(id) < shop.max_level(id), "восстановленный оффер %s не maxed" % id)
	# Перегенерация при пустых офферах на часе > 1.
	_game.hour = 3
	_game.shop_offers.clear()
	_game.shop_offer_hour = 0
	_game.save_game()
	_ok(_game.load_game(), "load_game с пустыми офферами")
	_eq(shop.offers().size(), 3, "пустые офферы догенерированы")
	_eq(int(_game.shop_offer_hour), 3, "shop_offer_hour = 3")


func _test_signals() -> void:
	_set_case("signals")
	var shop = _reset(2, 500)
	shop.purchased.connect(_on_purchased)
	shop.offers_changed.connect(_on_offers_changed)
	shop.refresh(2, 500, true)
	_ok(_offers_changed >= 1, "refresh эмитит offers_changed")
	_purchased.clear()
	var target := ""
	for id in shop.offers():
		if shop.can_buy(id):
			target = id
			break
	_ok(not target.is_empty(), "есть доступный оффер")
	if not target.is_empty():
		var before_changed := _offers_changed
		_ok(shop.buy(target), "покупка для сигналов")
		_eq(_purchased.size(), 1, "purchased эмитится")
		if _purchased.size() == 1:
			_eq(_purchased[0], target, "id в purchased")
		_ok(_offers_changed > before_changed, "покупка эмитит offers_changed")


# --- хелперы ---------------------------------------------------------------

func _reset(hour: int, money: int):
	_game.start_new_run(1)
	_game.hour = hour
	_game.money = money
	return SHOP.new()


func _set_offers(ids: Array) -> void:
	_game.shop_offers.clear()
	for id in ids:
		_game.shop_offers.append(str(id))


func _first_folder():
	var registry = _game.registry
	if registry == null:
		return null
	for section in registry.sections.values():
		if not section.folder_ids.is_empty():
			return registry.folders.get(str(section.folder_ids[0]))
	return null


func _distinct(arr: Array) -> int:
	var seen: Dictionary = {}
	for item in arr:
		seen[str(item)] = true
	return seen.size()


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


func _on_offers_changed() -> void:
	_offers_changed += 1


func _finish() -> void:
	print("test_shop: проверок %d, провалов %d" % [_checks, _fails])
	print("PASS test_shop" if _fails == 0 else "FAIL test_shop")
	quit(0 if _fails == 0 else 1)
