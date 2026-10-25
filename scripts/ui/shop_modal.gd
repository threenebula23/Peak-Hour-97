class_name ShopModal
extends Control
## Магазин v2: окно 900×600, ровно 3 карточки в ряд, реролл 40/80/120 и
## замок отдельного предложения. Крестика нет — только «ЗАКРЫТЬ» или Esc (D24).
##
## Новый API (магазин v2, main.gd подключат позже):
##   modal.open_prep(shop, Game.money, Game.hour)
##   modal.buy_requested.connect(_on_buy)
##   modal.reroll_requested.connect(_on_reroll)
##   modal.lock_toggled.connect(_on_lock)
##   modal.closed.connect(_on_closed)
##
## Legacy-совместимость (main.gd и modals_preview до перехода на v2):
##   modal.open(Game.money, Game.upgrades)
##   modal.refresh(Game.money, Game.upgrades)
##
## Все строки — через Data.tr с fallback в коде; шрифты — Theme90 10/12/16/24.

signal buy_requested(id: String)
signal reroll_requested
signal lock_toggled(index: int)
signal closed

const SHOP := preload("res://scripts/systems/shop.gd")

const W := 900.0
const H := 600.0
const DIM := Color(0.11, 0.12, 0.11, 0.30)

# --- геометрия -------------------------------------------------------------
const HEADER_H := 40.0
const CARD_W := 260.0
const CARD_H := 360.0
const CARD_GAP := 24.0
const CARD_Y := 88.0
const CARD_PAD := 12.0
const FOOTER_Y := H - 52.0
const FOOTER_H := 28.0
const MAX_CARDS := 3

const FALLBACK_DIMS := [[5, 4], [6, 4], [7, 5], [8, 5], [8, 6], [9, 6]]

## Текстовые fallback'и (ключи shop.* есть в data/strings_ru.json).
const FALLBACK := {
	"title_offers": "МАГАЗИН · 3 ПРЕДЛОЖЕНИЯ",
	"subtitle": "Новые предложения после каждого часа",
	"reroll": "ОБНОВИТЬ АССОРТИМЕНТ · %d $",
	"reroll_limit": "ЛИМИТ ОБНОВЛЕНИЙ",
	"level": "УРОВЕНЬ %d/%d",
	"now": "СЕЙЧАС",
	"after": "ПОСЛЕ",
	"maxed": "МАКСИМУМ",
	"not_enough": "НЕ ХВАТАЕТ %d $",
	"all_bought": "ВСЁ КУПЛЕНО",
	"lock": "ЗАКРЕПИТЬ",
	"unlock": "ОТКРЕПИТЬ",
	"next_level": "Следующий: %s",
	"balance": "БАЛАНС: %s $",
	"hint": "Улучшения окупаются к часу 8–9.",
}

# --- состояние -------------------------------------------------------------
var _shop = null
var _money := 0
var _hour := 0
var _legacy := false
var _levels: Dictionary = {}

var _cards: Array[Dictionary] = []
var _card_ids: Array[String] = []
var _card_rects: Array[Rect2] = []
var _legacy_items_cache: Array = []

var _buy_buttons: Array = []
var _locks: Array = []
var _reroll_btn: Button90
var _close_btn: Button90


# --- замок в углу карточки -------------------------------------------------
class LockToggle:
	extends Control
	signal toggled

	var locked := false
	var index := 0
	var _hover := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(_on_hover.bind(true))
		mouse_exited.connect(_on_hover.bind(false))

	func _on_hover(value: bool) -> void:
		_hover = value
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			toggled.emit()
			accept_event()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if locked:
			draw_style_box(Theme90.box(Theme90.ACCENT_PALE,
				Color(Theme90.ACCENT.r, Theme90.ACCENT.g, Theme90.ACCENT.b, 0.55), 3, 1), r)
		elif _hover:
			draw_style_box(Theme90.fill_box(Color(1, 1, 1, 0.65), 3), r)
		var color := Theme90.ACCENT if locked else Theme90.SHADE
		Theme90.draw_lock_icon(self, Vector2(5, 5), color)


# --- жизненный цикл --------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_controls()
	resized.connect(_layout)
	_layout()
	visible = false


# --- публичный API ---------------------------------------------------------

## Универсальный вход: open(Shop, money, hour) — v2; open(money, levels) — legacy.
func open(shop_or_money, money = -1, hour: int = 0) -> void:
	if _is_shop(shop_or_money):
		var balance := int(money) if not (money is Dictionary) else -1
		open_prep(shop_or_money, balance, hour)
		return
	var levels: Dictionary = {}
	if money is Dictionary:
		levels = money
	_open_legacy(int(shop_or_money), levels)


## Новый путь: магазин сам знает офферы/уровни/цены.
func open_prep(shop, money: int = -1, hour: int = 0) -> void:
	_bind_shop(shop)
	_hour = maxi(0, int(hour))
	if money < 0:
		_money = _game_money()
	else:
		_money = maxi(0, int(money))
	_legacy = false
	_levels.clear()
	_ensure_offers()
	_rebuild()
	visible = true


## Перечитать данные. Для v2 без аргументов берёт Game.money; для legacy
## принимает money/levels как раньше.
func refresh(p_money: int = -1, p_levels: Dictionary = {}) -> void:
	if _shop != null:
		if p_money >= 0:
			_money = maxi(0, int(p_money))
		else:
			_money = _game_money()
	else:
		if p_money >= 0:
			_money = maxi(0, int(p_money))
		if not p_levels.is_empty():
			_levels = p_levels.duplicate(true)
	_rebuild()
	if visible:
		visible = true


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


# --- тестовые/интеграционные геттеры --------------------------------------

func window_rect() -> Rect2:
	return _window_rect()


func card_rects() -> Array[Rect2]:
	return _card_rects.duplicate()


func card_infos() -> Array[Dictionary]:
	return _cards.duplicate(true)


func card_ids() -> Array[String]:
	return _card_ids.duplicate()


func is_all_bought() -> bool:
	return _card_ids.is_empty()


func balance_text() -> String:
	return _balance_line()


func reroll_text() -> String:
	return _reroll_btn.caption if _reroll_btn != null else ""


func reroll_disabled() -> bool:
	return _reroll_btn.disabled if _reroll_btn != null else true


func close_text() -> String:
	return _close_btn.caption if _close_btn != null else ""


func is_card_locked(index: int) -> bool:
	if index < 0 or index >= _cards.size():
		return false
	return bool(_cards[index].get("locked", false))


## Публичный программный клик по замку: эмитит lock_toggled(index).
func toggle_lock(index: int) -> void:
	if index < 0 or index >= _card_ids.size():
		return
	lock_toggled.emit(index)
	# Если подписчик уже переключил Shop, offers_changed обновит карточки сам.
	# Повторный refresh нужен, когда сигнал никто не слушает (dev/preview).
	refresh()


# --- сборка Controls -------------------------------------------------------

func _build_controls() -> void:
	_buy_buttons.clear()
	_locks.clear()
	for i in MAX_CARDS:
		var b := Button90.new()
		b.name = "Buy_%d" % i
		b.caption_size = Theme90.FS_BODY
		b.accent = true
		b.pressed.connect(_on_buy_pressed.bind(i))
		add_child(b)
		_buy_buttons.append(b)

		var lock := LockToggle.new()
		lock.name = "Lock_%d" % i
		lock.index = i
		lock.toggled.connect(_on_lock_pressed.bind(i))
		add_child(lock)
		_locks.append(lock)

	_reroll_btn = Button90.new()
	_reroll_btn.name = "RerollButton"
	_reroll_btn.caption_size = Theme90.FS_MICRO
	_reroll_btn.pressed.connect(_on_reroll_pressed)
	add_child(_reroll_btn)

	_close_btn = Button90.new()
	_close_btn.name = "CloseButton"
	_close_btn.caption_size = Theme90.FS_BODY
	_close_btn.pressed.connect(close)
	add_child(_close_btn)


# --- данные ----------------------------------------------------------------

func _ensure_offers() -> void:
	if _shop == null:
		return
	if not _shop.offers().is_empty():
		return
	if _hour <= 1:
		return
	if _shop.has_method("refresh"):
		_shop.refresh(_hour, _money)


func _rebuild() -> void:
	_cards.clear()
	_card_ids.clear()
	_card_rects.clear()
	if _shop != null:
		var offer_index := 0
		for raw_id in _shop.offers():
			if _cards.size() >= MAX_CARDS:
				break
			var id := str(raw_id)
			var item: Dictionary = _shop.get_item(id)
			if item.is_empty():
				offer_index += 1
				continue
			var level := int(_shop.level(id))
			var max_level := int(_shop.max_level(id))
			var cost := int(_shop.price(id))
			var locked := false
			if _shop.has_method("is_locked"):
				locked = bool(_shop.is_locked(offer_index))
			_cards.append(_make_card(item, id, level, max_level, cost, locked))
			_card_ids.append(id)
			offer_index += 1
	else:
		for item in _legacy_items():
			if _cards.size() >= MAX_CARDS:
				break
			var id := str(item.get("id", ""))
			var level := SHOP.level_for(item, _levels)
			var max_level := maxi(1, int(item.get("max_level", 1)))
			var cost := SHOP.price_for(item, level)
			_cards.append(_make_card(item, id, level, max_level, cost, false))
			_card_ids.append(id)

	_sync_controls()
	_layout()
	queue_redraw()


func _make_card(item: Dictionary, id: String, level: int, max_level: int,
		cost: int, locked: bool) -> Dictionary:
	var maxed := level >= max_level or cost < 0
	var values := _effect_values(item, level)
	var price := maxi(0, cost)
	var button_text := ""
	var affordable := false
	if maxed:
		button_text = _tr("shop.maxed", FALLBACK["maxed"])
	elif price > _money:
		button_text = _tr("shop.not_enough", FALLBACK["not_enough"]) % (price - _money)
	else:
		button_text = "%s $" % _fmt(price)
		affordable = true
	var next_name := _next_level_name(item, level)
	return {
		"id": id,
		"title": str(item.get("name_ru", item.get("name", id))),
		"desc": str(item.get("desc_ru", "")),
		"effect": str(item.get("effect", "")),
		"level": level,
		"max_level": max_level,
		"price": price,
		"maxed": maxed,
		"affordable": affordable,
		"locked": locked,
		"level_text": _tr("shop.level", FALLBACK["level"]) % [level, max_level],
		"now_text": str(values.get("now", "—")),
		"after_text": str(values.get("after", "—")),
		"button_text": button_text,
		"next_name": next_name,
		"rect": Rect2(),
	}


func _legacy_items() -> Array:
	if not _legacy_items_cache.is_empty():
		return _legacy_items_cache
	var tmp = SHOP.new()
	_legacy_items_cache = tmp.items()
	return _legacy_items_cache


func _next_level_name(item: Dictionary, level: int) -> String:
	var names = item.get("level_names", [])
	if names is Array and level < (names as Array).size():
		return str((names as Array)[level])
	return ""


func _is_shop(value) -> bool:
	return typeof(value) == TYPE_OBJECT and value != null and value.has_method("offers")


func _bind_shop(shop) -> void:
	if _shop == shop:
		return
	if _shop != null and _shop.has_signal("offers_changed") \
			and _shop.offers_changed.is_connected(_on_shop_changed):
		_shop.offers_changed.disconnect(_on_shop_changed)
	_shop = shop
	if _shop != null and _shop.has_signal("offers_changed"):
		_shop.offers_changed.connect(_on_shop_changed)


func _on_shop_changed() -> void:
	if visible:
		refresh()


func _open_legacy(p_money: int, p_levels: Dictionary) -> void:
	_bind_shop(null)
	_legacy = true
	_hour = 0
	_money = maxi(0, int(p_money))
	_levels = p_levels.duplicate(true)
	_legacy_items_cache.clear()
	_rebuild()
	visible = true


# --- эффекты: конкретные «СЕЙЧАС» и «ПОСЛЕ» --------------------------------

func _effect_values(item: Dictionary, level: int) -> Dictionary:
	var effect := str(item.get("effect", ""))
	var value := float(item.get("value", 1.0))
	var game = _game_node()
	match effect:
		"connection_slots":
			var now_slots := int(game.connection_slots()) if game != null else 1 + level
			return {"now": str(now_slots), "after": str(now_slots + maxi(1, int(value)))}
		"transfer_speed":
			var now_time := float(game.speed_mult()) if game != null else pow(0.90, float(level))
			var after_time := now_time * (1.0 - clampf(value, 0.01, 0.5))
			return {"now": "×%.2f" % (1.0 / now_time), "after": "×%.2f" % (1.0 / after_time)}
		"sla_cap":
			var now_cap := int(game.sla_cap()) if game != null else 60 + 40 * level
			var current := int(minf(float(game.sla), float(now_cap))) if game != null else now_cap
			var after_cap := mini(220, now_cap + int(value))
			var after_current := mini(after_cap, current + int(value))
			return {"now": "%d / %d" % [current, now_cap],
				"after": "%d / %d" % [after_current, after_cap]}
		"shield_charge":
			var now_max := int(game.shield_max()) if game != null else level
			var now_charges := int(game.shield_charges) if game != null else 0
			now_charges = mini(now_charges, now_max)
			var after_max := now_max + maxi(1, int(value))
			var after_charges := mini(after_max, now_charges + maxi(1, int(value)))
			return {"now": "%d / %d" % [now_charges, now_max],
				"after": "%d / %d" % [after_charges, after_max]}
		"money_mult":
			var now_mult := float(game.money_mult()) if game != null else 1.0 + 0.05 * level
			var after_mult := now_mult + value
			return {"now": "×%.2f" % now_mult, "after": "×%.2f" % after_mult}
		"folder_cells":
			var dims := _folder_dims_table()
			var now_pair := _dims_at(dims, level)
			var after_pair := _dims_at(dims, level + 1)
			var now_cells := int(now_pair[0]) * int(now_pair[1])
			var after_cells := int(after_pair[0]) * int(after_pair[1])
			return {
				"now": "%d · %d×%d" % [now_cells, int(now_pair[0]), int(now_pair[1])],
				"after": "%d · %d×%d" % [after_cells, int(after_pair[0]), int(after_pair[1])],
			}
		"channel_capacity":
			var now_channel := int(game.channel_capacity()) if game != null else 10 + 6 * level
			var now_buffer := int(game.buffer_limit()) if game != null else 6 + level
			var add_channel := maxi(1, int(value))
			var add_buffer := maxi(1, int(item.get("buffer_value", 1)))
			return {"now": "%d / %d" % [now_channel, now_buffer],
				"after": "%d / %d" % [now_channel + add_channel, now_buffer + add_buffer]}
		"request_timer":
			var now_timer := int(game.request_timer()) if game != null else 30 + 7 * level
			return {"now": "%d с" % now_timer, "after": "%d с" % (now_timer + maxi(1, int(value)))}
	return {"now": "—", "after": "—"}


func _folder_dims_table() -> Array:
	var data = _data_node()
	if data != null and data.has_method("folder_dims_table"):
		var table = data.folder_dims_table()
		if table is Array and not (table as Array).is_empty():
			return table
	return FALLBACK_DIMS


func _dims_at(table: Array, level: int) -> Array:
	var idx := clampi(level, 0, table.size() - 1)
	var pair = table[idx]
	if pair is Array and (pair as Array).size() >= 2:
		return pair
	return [5, 4]


# --- раскладка/синхронизация ----------------------------------------------

func _window_rect() -> Rect2:
	var s := size
	if s.x <= 0.0 or s.y <= 0.0:
		s = Vector2(1280, 720)
	return Rect2(((s - Vector2(W, H)) * 0.5).round(), Vector2(W, H))


func _card_rect_at(index: int, count: int, win: Rect2) -> Rect2:
	var safe_count := maxi(1, count)
	var total_w := safe_count * CARD_W + maxi(0, safe_count - 1) * CARD_GAP
	var start_x := win.position.x + roundf((W - total_w) * 0.5)
	return Rect2(Vector2(start_x + index * (CARD_W + CARD_GAP),
		win.position.y + CARD_Y), Vector2(CARD_W, CARD_H))


func _layout() -> void:
	var win := _window_rect()
	_card_rects.clear()
	var count := _cards.size()
	for i in count:
		var r := _card_rect_at(i, count, win)
		_cards[i]["rect"] = r
		_card_rects.append(r)

	for i in MAX_CARDS:
		var b: Button90 = _buy_buttons[i]
		var lock: LockToggle = _locks[i]
		if i < count:
			var r := _card_rects[i]
			b.visible = true
			b.position = r.position + Vector2(CARD_PAD, CARD_H - 46.0)
			b.size = Vector2(CARD_W - CARD_PAD * 2.0, FOOTER_H + 2.0)
			lock.visible = true
			lock.position = r.position + Vector2(CARD_W - 32.0, 8.0)
			lock.size = Vector2(20, 20)
		else:
			b.visible = false
			lock.visible = false

	_reroll_btn.position = win.position + Vector2(20, FOOTER_Y)
	_reroll_btn.size = Vector2(300, FOOTER_H)
	_close_btn.position = win.position + Vector2(W - 20 - 120, FOOTER_Y)
	_close_btn.size = Vector2(120, FOOTER_H)


func _sync_controls() -> void:
	for i in MAX_CARDS:
		var b: Button90 = _buy_buttons[i]
		var lock: LockToggle = _locks[i]
		if i >= _cards.size():
			b.visible = false
			lock.visible = false
			continue
		var card: Dictionary = _cards[i]
		b.visible = true
		b.caption = str(card["button_text"])
		b.disabled = bool(card["maxed"]) or not bool(card["affordable"])
		b.accent = not b.disabled
		b.caption_size = Theme90.FS_BODY if bool(card["affordable"]) else Theme90.FS_MICRO
		b.tooltip_text = "%s · %s" % [str(card["title"]), str(card["level_text"])]

		lock.visible = true
		lock.locked = bool(card["locked"])
		lock.index = i
		lock.tooltip_text = _tr("shop.unlock", FALLBACK["unlock"]) if lock.locked \
			else _tr("shop.lock", FALLBACK["lock"])
		lock.queue_redraw()

	_reroll_btn.caption = _reroll_label()
	_reroll_btn.disabled = _reroll_is_disabled()
	_reroll_btn.accent = not _reroll_btn.disabled
	_reroll_btn.tooltip_text = _reroll_tooltip()
	_close_btn.caption = _tr("btn.close", "ЗАКРЫТЬ").to_upper()


func _reroll_label() -> String:
	if _shop == null:
		return _tr("shop.reroll", FALLBACK["reroll"]) % 40
	if _card_ids.is_empty():
		return _tr("shop.reroll_limit", FALLBACK["reroll_limit"])
	var cost := int(_shop.reroll_cost())
	if cost < 0:
		return _tr("shop.reroll_limit", FALLBACK["reroll_limit"])
	return _tr("shop.reroll", FALLBACK["reroll"]) % cost


func _reroll_is_disabled() -> bool:
	if _shop == null:
		return true
	if _card_ids.is_empty():
		return true
	var cost := int(_shop.reroll_cost())
	if cost < 0:
		return true
	if _money < cost:
		return true
	# Бэкенд может запретить реролл по своим причинам (например, лимит/деньги).
	# Сверяемся только когда UI показывает тот же баланс, что и Game.
	var game = _game_node()
	if game != null and _money == int(game.money) and _shop.has_method("can_reroll"):
		return not bool(_shop.can_reroll())
	return false


func _reroll_tooltip() -> String:
	if _shop == null:
		return _tr("shop.reroll_limit", FALLBACK["reroll_limit"])
	var cost := int(_shop.reroll_cost())
	if cost >= 0 and _money < cost:
		return _tr("shop.not_enough", FALLBACK["not_enough"]) % (cost - _money)
	if cost < 0 or _card_ids.is_empty() or _reroll_is_disabled():
		return _tr("shop.reroll_limit", FALLBACK["reroll_limit"])
	return ""


# --- сигналы Controls ------------------------------------------------------

func _on_buy_pressed(index: int) -> void:
	if index < 0 or index >= _card_ids.size():
		return
	var card: Dictionary = _cards[index]
	if bool(card["maxed"]) or not bool(card["affordable"]):
		return
	buy_requested.emit(_card_ids[index])


func _on_reroll_pressed() -> void:
	if _reroll_is_disabled():
		return
	reroll_requested.emit()
	refresh()


func _on_lock_pressed(index: int) -> void:
	if index < 0 or index >= _card_ids.size():
		return
	lock_toggled.emit(index)
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


# --- отрисовка -------------------------------------------------------------

func _draw() -> void:
	var full := Rect2(Vector2.ZERO, size)
	if size.x <= 0.0 or size.y <= 0.0:
		full = Rect2(0, 0, 1280, 720)
	draw_rect(full, DIM)
	var win := _window_rect()
	_draw_frame(win)
	if _cards.is_empty():
		_draw_empty(win)
	else:
		for i in _cards.size():
			_draw_card(i)
	_draw_hints(win)


func _draw_frame(win: Rect2) -> void:
	draw_style_box(Theme90.box(Theme90.WHITE, Theme90.BORDER, 6, 1,
		Color(0, 0, 0, 0.16)), win)
	var header := Rect2(win.position.x + 1, win.position.y + 1,
		win.size.x - 2, HEADER_H - 1)
	draw_style_box(Theme90.top_box(Theme90.PAPER_HI, 6), header)
	draw_circle(Vector2(header.position.x + 20, header.position.y + HEADER_H * 0.5),
		3.5, Theme90.ACCENT)

	var f := Theme90.ui()
	Theme90.text_vcenter(self, f, Rect2(header.position.x + 31, header.position.y,
		header.size.x - 260, HEADER_H),
		_tr("shop.title_offers", FALLBACK["title_offers"]), Theme90.FS_HEAD,
		Theme90.NAVY, -1, HORIZONTAL_ALIGNMENT_LEFT)
	Theme90.text_vcenter(self, f, Rect2(header.position.x + 40, header.position.y,
		header.size.x - 60, HEADER_H), _balance_line(), Theme90.FS_BODY,
		Theme90.INK, -1, HORIZONTAL_ALIGNMENT_RIGHT)

	draw_rect(Rect2(win.position.x + 1, win.position.y + HEADER_H,
		win.size.x - 2, 1), Theme90.HAIRLINE)
	Theme90.text(self, f, Vector2(win.position.x + 22, win.position.y + HEADER_H + 7),
		_tr("shop.subtitle", FALLBACK["subtitle"]), Theme90.FS_MICRO,
		Theme90.SHADE, win.size.x - 44)


func _draw_empty(win: Rect2) -> void:
	var f := Theme90.ui()
	var cy := win.position.y + CARD_Y + CARD_H * 0.5
	Theme90.text_vcenter(self, f, Rect2(win.position.x + 20, cy - 20,
		win.size.x - 40, 40), _tr("shop.all_bought", FALLBACK["all_bought"]),
		Theme90.FS_LOGO, Theme90.NAVY, -1, HORIZONTAL_ALIGNMENT_CENTER)
	Theme90.text_vcenter(self, f, Rect2(win.position.x + 20, cy + 24,
		win.size.x - 40, 20), _tr("shop.reroll_limit", FALLBACK["reroll_limit"]),
		Theme90.FS_MICRO, Theme90.SHADE, -1, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_card(index: int) -> void:
	if index < 0 or index >= _cards.size():
		return
	var card: Dictionary = _cards[index]
	var r: Rect2 = _card_rects[index]
	var locked := bool(card.get("locked", false))
	var bg := Theme90.ACCENT_PALE if locked else Theme90.WHITE
	var border := Color(Theme90.ACCENT.r, Theme90.ACCENT.g, Theme90.ACCENT.b, 0.65) \
		if locked else Theme90.BORDER
	draw_style_box(Theme90.box(bg, border, 4, 1, Color(0, 0, 0, 0.13)), r)

	var f := Theme90.ui()
	var x := r.position.x
	var y := r.position.y
	var inner := CARD_W - CARD_PAD * 2.0

	# Цветная полоска эффекта — только как маркер, без иконок-ассетов.
	draw_rect(Rect2(x + 1, y + 1, CARD_W - 2, 3),
		_effect_color(str(card.get("effect", ""))))

	# Заголовок: максимум 2 строки.
	var title_lines := Theme90.wrap(f, str(card.get("title", "")), Theme90.FS_HEAD,
		inner - 30.0, 2)
	for i in title_lines.size():
		Theme90.text(self, f, Vector2(x + CARD_PAD, y + 12 + i * 18),
			title_lines[i], Theme90.FS_HEAD, Theme90.INK, inner)

	# Практическое описание: 10 px, 2–3 строки.
	var desc := str(card.get("desc", ""))
	if desc.is_empty():
		desc = _effect_fallback_desc(str(card.get("effect", "")))
	var desc_lines := Theme90.wrap(f, desc, Theme90.FS_MICRO, inner, 3)
	for i in desc_lines.size():
		Theme90.text(self, f, Vector2(x + CARD_PAD, y + 56 + i * 12),
			desc_lines[i], Theme90.FS_MICRO, Theme90.SHADE, inner)

	draw_rect(Rect2(x + CARD_PAD, y + 100, inner, 1), Theme90.HAIRLINE)

	# Уровень + пипсы.
	Theme90.text(self, f, Vector2(x + CARD_PAD, y + 108),
		str(card.get("level_text", "")), Theme90.FS_MICRO, Theme90.SHADE, inner)
	var level := int(card.get("level", 0))
	var max_level := int(card.get("max_level", 1))
	var pip_y := y + 124.0
	for i in max_level:
		var pip := Rect2(x + CARD_PAD + i * 10.0, pip_y, 7, 6)
		if i < level:
			draw_style_box(Theme90.fill_box(Theme90.ACCENT, 3), pip)
		else:
			draw_style_box(Theme90.box(Theme90.PAPER_HI, Theme90.BORDER_SOFT, 3, 1), pip)

	_draw_stat_row(r, y + 140.0, _tr("shop.now", FALLBACK["now"]),
		str(card.get("now_text", "")), Theme90.PAPER)
	_draw_stat_row(r, y + 168.0, _tr("shop.after", FALLBACK["after"]),
		str(card.get("after_text", "")), Theme90.PAPER_HI)

	var next_name := str(card.get("next_name", ""))
	if not next_name.is_empty():
		Theme90.text(self, f, Vector2(x + CARD_PAD, y + 204),
			Theme90.fit(f, _tr("shop.next_level", FALLBACK["next_level"]) % next_name,
				Theme90.FS_MICRO, inner), Theme90.FS_MICRO, Theme90.SHADE, inner)

	if locked:
		# Замок уже нарисован Control'ом; лёгкая подпись делает состояние явным.
		var lock_label := _tr("shop.unlock", FALLBACK["unlock"])
		Theme90.text(self, f, Vector2(x + CARD_PAD, y + 244),
			Theme90.fit(f, lock_label, Theme90.FS_MICRO, inner), Theme90.FS_MICRO,
			Theme90.ACCENT, inner)


func _draw_stat_row(card_rect: Rect2, y: float, label: String, value: String,
		bg: Color) -> void:
	var box := Rect2(card_rect.position.x + CARD_PAD, y,
		CARD_W - CARD_PAD * 2.0, 24)
	draw_style_box(Theme90.box(bg, Theme90.BORDER_SOFT, 3, 1), box)
	var f := Theme90.ui()
	Theme90.text_vcenter(self, f, Rect2(box.position.x + 8, box.position.y,
		box.size.x - 16, box.size.y), label, Theme90.FS_MICRO, Theme90.SHADE,
		box.size.x - 16, HORIZONTAL_ALIGNMENT_LEFT)
	Theme90.text_vcenter(self, f, Rect2(box.position.x + 8, box.position.y,
		box.size.x - 16, box.size.y), value, Theme90.FS_BODY, Theme90.INK,
		box.size.x - 16, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_hints(win: Rect2) -> void:
	var f := Theme90.ui()
	Theme90.text(self, f, Vector2(win.position.x + 22, win.position.y + FOOTER_Y - 22),
		_tr("hint.shop", FALLBACK["hint"]), Theme90.FS_MICRO, Theme90.SHADE,
		win.size.x - 44)


# --- утилиты ---------------------------------------------------------------

func _balance_line() -> String:
	return _tr("shop.balance", FALLBACK["balance"]) % _fmt(_money)


func _effect_color(effect: String) -> Color:
	match effect:
		"connection_slots", "channel_capacity":
			return Theme90.ACCENT
		"transfer_speed", "request_timer":
			return Theme90.NAVY
		"sla_cap", "shield_charge":
			return Theme90.SUCCESS
		"folder_cells":
			return Theme90.WARN
		"money_mult":
			return Theme90.ERROR
	return Theme90.ACCENT


func _effect_fallback_desc(effect: String) -> String:
	match effect:
		"connection_slots":
			return "Ещё один порт: приём и отправка могут идти параллельно."
		"transfer_speed":
			return "Скорость приёма и отправки выше на 10% за уровень."
		"sla_cap":
			return "Держит узел живым: кап SLA +40 и сразу +40 SLA."
		"shield_charge":
			return "Автоматически гасит атаку: 70% награды, без штрафа."
		"money_mult":
			return "Оплата за контейнеры +5% за уровень."
		"folder_cells":
			return "Больше места под фигуры в каждой папке."
		"channel_capacity":
			return "Канал +6 и буфер приёма +1 за уровень."
		"request_timer":
			return "Больше времени на поиск файлов и прикрепление."
	return "Улучшение рабочего места."


func _tr(key: String, fallback: String) -> String:
	var data = _data_node()
	if data != null and data.has_method("has_string") and data.has_string(key):
		var value := str(data.tr(key))
		if not value.is_empty() and value != key:
			return value
	return fallback


func _game_node():
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("Game")
	return get_node_or_null("/root/Game")


func _data_node():
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("Data")
	return get_node_or_null("/root/Data")


func _game_money() -> int:
	var game = _game_node()
	if game == null:
		return 0
	return maxi(0, int(game.money))


func _fmt(value: int) -> String:
	var neg := value < 0
	var digits := str(absi(value))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = " " + out
	return ("-" if neg else "") + out
