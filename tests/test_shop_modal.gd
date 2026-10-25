extends SceneTree
## Headless-тест v2-окна магазина: 3 карточки, тексты, состояния кнопок,
## реролл 40/80/120, «ВСЁ КУПЛЕНО», замок и закрытие.
## Запуск: godot --headless --path . --script tests/test_shop_modal.gd

const SHOP := preload("res://scripts/systems/shop.gd")
const MODAL := preload("res://scripts/ui/shop_modal.gd")

const IDS := [
	"lot_slots", "lot_speed", "lot_sla", "lot_shield",
	"lot_money", "lot_folder", "lot_channel", "lot_timer",
]
const MAX_LEVELS := {
	"lot_slots": 4, "lot_speed": 6, "lot_sla": 4, "lot_shield": 3,
	"lot_money": 8, "lot_folder": 5, "lot_channel": 6, "lot_timer": 5,
}

var _checks := 0
var _fails := 0
var _case := ""
var _game = null
var _modal = null
var _shop = null


func _init() -> void:
	await process_frame
	_game = root.get_node_or_null("Game")
	var stage := Control.new()
	stage.name = "ShopModalStage"
	stage.size = Vector2(1280, 720)
	root.add_child(stage)
	_modal = MODAL.new()
	_modal.name = "ShopModalTest"
	stage.add_child(_modal)
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	if _game == null:
		_test_fallback_without_game()
		_finish()
		return

	_test_layout_and_texts()
	_test_maxed_card()
	_test_unaffordable_card()
	_test_reroll_costs()
	_test_all_bought()
	_test_lock_persists()
	_test_fewer_offers()
	_test_close_and_escape()
	_test_legacy_open()
	_finish()


# --- кейсы -----------------------------------------------------------------

func _test_layout_and_texts() -> void:
	_set_case("layout/texts")
	var shop = _reset(2, 1000)
	shop.refresh(2, 1000, true)
	_modal.open_prep(shop, 1000, 2)

	var win: Rect2 = _modal.window_rect()
	_approx(win.size.x, 900.0, 0.001, "окно 900 px")
	_approx(win.size.y, 600.0, 0.001, "окно 600 px")
	_eq(_modal.card_rects().size(), 3, "ровно 3 карточки")
	_ok(_modal.is_open(), "open_prep делает окно видимым")

	var rects: Array = _modal.card_rects()
	for i in rects.size():
		var r: Rect2 = rects[i]
		_approx(r.size.x, 260.0, 0.001, "card %d: ширина 260" % i)
		_approx(r.size.y, 360.0, 0.001, "card %d: высота 360" % i)
		_ok(r.position.x >= win.position.x and r.position.y >= win.position.y,
			"card %d: внутри окна (лево/верх)" % i)
		_ok(r.end.x <= win.end.x and r.end.y <= win.end.y,
			"card %d: внутри окна (право/низ)" % i)
	# Константы раскладки: 3*260 + 2*24 = 828; поля (900-828)/2 = 36.
	var base_x: float = win.position.x + 36.0
	_approx(rects[0].position.x, base_x, 0.001, "card 0 x = окно + 36")
	_approx(rects[1].position.x, base_x + 284.0, 0.001, "card 1 x = +284 (260+24)")
	_approx(rects[2].position.x, base_x + 568.0, 0.001, "card 2 x = +568")
	_approx(rects[0].position.y, win.position.y + 88.0, 0.001, "cards y = окно + 88")

	var infos: Array = _modal.card_infos()
	_eq(infos.size(), 3, "card_infos: 3 записи")
	for i in infos.size():
		var info: Dictionary = infos[i]
		_ok(not str(info.get("id", "")).is_empty(), "card %d: id не пуст" % i)
		_ok(not str(info.get("title", "")).is_empty(), "card %d: заголовок не пуст" % i)
		_ok(not str(info.get("level_text", "")).is_empty(), "card %d: уровень не пуст" % i)
		_ok(str(info.get("level_text", "")).begins_with("УРОВЕНЬ"),
			"card %d: текст уровня из shop.level" % i)
		_ok(not str(info.get("now_text", "")).is_empty(), "card %d: СЕЙЧАС не пуст" % i)
		_ok(not str(info.get("after_text", "")).is_empty(), "card %d: ПОСЛЕ не пуст" % i)
		_ok(not str(info.get("button_text", "")).is_empty(), "card %d: кнопка цены не пуста" % i)
		_ok(int(info.get("price", 0)) > 0, "card %d: цена > 0" % i)
		_ok(not bool(info.get("maxed", true)), "card %d: не максимален" % i)
		_ok(str(info.get("button_text", "")).contains("$"),
			"card %d: доступная кнопка показывает цену" % i)

	_ok(_modal.balance_text().contains("БАЛАНС"), "баланс содержит БАЛАНС")
	_ok(_modal.close_text().contains("ЗАКРЫТ"), "кнопка закрытия — ЗАКРЫТЬ")
	_ok(_modal.reroll_text().contains("40"), "реролл на старте 40 $")


func _test_maxed_card() -> void:
	_set_case("maxed")
	var shop = _reset(2, 10000)
	_game.set_lot_level("lot_timer", int(MAX_LEVELS["lot_timer"]))
	_set_offers(["lot_timer", "lot_slots", "lot_money"])
	_modal.open_prep(shop, 10000, 2)
	var infos: Array = _modal.card_infos()
	_eq(infos.size(), 3, "maxed-кейс: 3 карточки без краша")
	var first: Dictionary = infos[0]
	_ok(bool(first.get("maxed", false)), "lot_timer maxed")
	_ok(str(first.get("button_text", "")).contains("МАКСИМУМ"),
		"maxed-карточка показывает МАКСИМУМ")
	_ok(int(first.get("price", 0)) <= 0, "maxed price = -1/0")
	_ok(_modal._buy_buttons[0].disabled, "maxed-кнопка disabled")


func _test_unaffordable_card() -> void:
	_set_case("unaffordable")
	var shop = _reset(2, 0)
	_set_offers(["lot_slots", "lot_speed", "lot_money"])
	_modal.open_prep(shop, 0, 2)
	var infos: Array = _modal.card_infos()
	_eq(infos.size(), 3, "unaffordable: 3 карточки")
	for i in infos.size():
		var info: Dictionary = infos[i]
		_ok(str(info.get("button_text", "")).contains("НЕ ХВАТАЕТ"),
			"card %d: НЕ ХВАТАЕТ" % i)
		_ok(not bool(info.get("affordable", true)), "card %d: not affordable" % i)
	_ok(_modal._buy_buttons[0].disabled, "не хватает — кнопка disabled")


func _test_reroll_costs() -> void:
	_set_case("reroll")
	var shop = _reset(2, 1000)
	shop.refresh(2, 1000, true)
	_modal.open_prep(shop, 1000, 2)
	_ok(_modal.reroll_text().contains("40"), "реролл #1 = 40 $")
	_ok(not _modal.reroll_disabled(), "реролл #1 доступен")

	_ok(shop.reroll(), "reroll #1")
	_ok(_modal.reroll_text().contains("80"), "реролл #2 = 80 $")
	_ok(shop.reroll(), "reroll #2")
	_ok(_modal.reroll_text().contains("120"), "реролл #3 = 120 $")
	_ok(shop.reroll(), "reroll #3")
	_ok(_modal.reroll_text().contains("ЛИМИТ ОБНОВЛЕНИЙ"),
		"после 3-го — ЛИМИТ ОБНОВЛЕНИЙ")
	_ok(_modal.reroll_disabled(), "после лимита кнопка disabled")


func _test_all_bought() -> void:
	_set_case("all_bought")
	var shop = _reset(2, 100000)
	for id in IDS:
		_game.set_lot_level(id, int(MAX_LEVELS[id]))
	shop.refresh(2, 100000, true)
	_modal.open_prep(shop, 100000, 2)
	_eq(_modal.card_rects().size(), 0, "все лоты maxed → 0 карточек")
	_ok(_modal.is_all_bought(), "is_all_bought true")
	_ok(_modal.reroll_text().contains("ЛИМИТ ОБНОВЛЕНИЙ"),
		"all bought: ЛИМИТ ОБНОВЛЕНИЙ")
	_ok(_modal.reroll_disabled(), "all bought: реролл disabled")


func _test_lock_persists() -> void:
	_set_case("lock")
	var shop = _reset(2, 1000)
	shop.refresh(2, 1000, true)
	_modal.open_prep(shop, 1000, 2)
	var locked_id: String = str(shop.offers()[0])
	var seen: Array = []
	var handler := func(index: int) -> void:
		seen.append(index)
		shop.toggle_lock(index)
		_modal.refresh()
	_modal.lock_toggled.connect(handler)
	_modal.toggle_lock(0)
	_eq(seen.size(), 1, "lock_toggled эмитится с индексом")
	_ok(shop.is_locked(0), "Shop.is_locked(0)")
	_ok(_modal.is_card_locked(0), "карточка показывает lock")
	_ok(bool(_modal.card_infos()[0].get("locked", false)), "locked в card_info")

	_ok(shop.reroll(), "реролл с закреплённым лотом")
	_ok(shop.offers().has(locked_id), "закреплённый лот остался после реролла")
	_ok(_modal.card_ids().has(locked_id), "UI показывает закреплённый лот")
	_ok(_modal.is_card_locked(0), "замок сохранился на первой карточке")
	_modal.lock_toggled.disconnect(handler)


func _test_fewer_offers() -> void:
	_set_case("fewer_offers")
	var shop = _reset(2, 1000)
	_set_offers(["lot_slots", "lot_speed"])
	_modal.open_prep(shop, 1000, 2)
	_eq(_modal.card_rects().size(), 2, "2 оффера → 2 карточки, без краша")
	var win: Rect2 = _modal.window_rect()
	for r in _modal.card_rects():
		_ok(r.position.x >= win.position.x and r.end.x <= win.end.x,
			"fewer: карточка внутри окна")


func _test_close_and_escape() -> void:
	_set_case("close")
	var shop = _reset(2, 1000)
	shop.refresh(2, 1000, true)
	_modal.open_prep(shop, 1000, 2)
	var closes: Array = []
	var on_closed := func() -> void:
		closes.append(true)
	_modal.closed.connect(on_closed)

	_modal.close()
	_eq(closes.size(), 1, "close() эмитит closed")
	_ok(not _modal.is_open(), "после close окно скрыто")

	_modal.open_prep(shop, 1000, 2)
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	_modal._unhandled_input(event)
	_eq(closes.size(), 2, "Esc эмитит closed")
	_ok(not _modal.is_open(), "после Esc окно скрыто")
	_modal.closed.disconnect(on_closed)


func _test_legacy_open() -> void:
	_set_case("legacy")
	_modal.open(500, {})
	_ok(_modal.is_open(), "legacy open(money, levels) открывает окно")
	_eq(_modal.card_rects().size(), 3, "legacy: 3 карточки из Data")
	for info in _modal.card_infos():
		_ok(not str(info.get("title", "")).is_empty(), "legacy: заголовок не пуст")
		_ok(not str(info.get("button_text", "")).is_empty(), "legacy: кнопка не пуста")
	_ok(_modal.reroll_disabled(), "legacy: реролл disabled (нет Shop)")
	_modal.close()


func _test_fallback_without_game() -> void:
	_set_case("fallback/no_game")
	print("Game autoload недоступен — legacy-проверка ShopModal")
	var fallback = SHOP.new()
	_ok(fallback.item_count() >= 8, "Shop: fallback-каталог загружен")
	_modal.open(500, {})
	_ok(_modal.is_open(), "legacy open без Game не падает")
	_eq(_modal.card_rects().size(), 3, "legacy без Game: 3 карточки")
	_modal.close()


# --- хелперы ---------------------------------------------------------------

func _reset(hour: int, money: int):
	_game.start_new_run(1)
	_game.hour = hour
	_game.money = money
	_game.shop_offers.clear()
	_game.shop_rerolls = 0
	_game.shop_offer_hour = 0
	_game.shop_locked.clear()
	_shop = SHOP.new()
	return _shop


func _set_offers(ids: Array) -> void:
	_game.shop_offers.clear()
	for id in ids:
		_game.shop_offers.append(str(id))


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


func _finish() -> void:
	print("test_shop_modal: проверок %d, провалов %d" % [_checks, _fails])
	print("PASS test_shop_modal" if _fails == 0 else "FAIL test_shop_modal")
	quit(0 if _fails == 0 else 1)
