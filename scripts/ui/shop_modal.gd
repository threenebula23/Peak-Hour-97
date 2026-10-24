class_name ShopModal
extends Control
## Модальное окно «МАГАЗИН»: 9 улучшений из Data.shop (fallback встроен).
##
## Только UI: ничего не покупает и не меняет состояние игры. Нажатие на
## «Купить» отдаёт id наружу сигналом buy_requested; интеграция решает сама,
## списать деньги и вызвать refresh(). Данные уровней и денег — снаружи.
##
##   shop.open(Game.money, Game.upgrades)
##   shop.buy_requested.connect(_on_buy)
##   shop.closed.connect(_on_closed)

signal buy_requested(id: String)
signal closed

const W := 920.0
const H := 584.0
const TITLE_H := 20.0
const ROW_Y := 64.0
const ROW_H := 52.0
const DIM := Color(0.0, 0.0, 0.0, 0.35)

## Копия data/balance.json → shop: те же id, цены и потолки уровней.
const FALLBACK_SHOP := [
	{"id": "shop_slot3", "name_ru": "Третий слот", "price": 250, "max_level": 1, "effect": "connection_slots"},
	{"id": "shop_slot4", "name_ru": "Четвёртый слот", "price": 450, "max_level": 1, "effect": "connection_slots"},
	{"id": "shop_buffer", "name_ru": "Буфер +2", "price": 200, "max_level": 2, "effect": "buffer_slots"},
	{"id": "shop_timer", "name_ru": "Таймер пакетов +4 с", "price": 350, "max_level": 3, "effect": "packet_timer"},
	{"id": "shop_zone", "name_ru": "Зона +5%", "price": 300, "max_level": 3, "effect": "zone_width"},
	{"id": "shop_channel", "name_ru": "Канал +25", "price": 250, "max_level": 4, "effect": "channel_capacity"},
	{"id": "shop_section", "name_ru": "Новая секция", "price": 300, "max_level": 5, "effect": "sections"},
	{"id": "shop_search", "name_ru": "Поиск", "price": 250, "max_level": 1, "effect": "search_highlight"},
	{"id": "shop_shield", "name_ru": "Щит", "price": 400, "max_level": 1, "effect": "shield"},
]

const EFFECT_DESC := {
	"connection_slots": "Ещё одно соединение одновременно",
	"buffer_slots": "Приём выдерживает больше пакетов",
	"packet_timer": "Больше времени на каждый пакет",
	"zone_width": "Шире зона попадания в мини-игре",
	"channel_capacity": "Канал держит больше нагрузки",
	"sections": "Ещё одна секция для папок",
	"search_highlight": "Подсветка нужных файлов",
	"shield": "Автоматически отражает атаки",
}

var money := 0
var levels: Dictionary = {}

var _items: Array = []
var _buttons: Array[Button90] = []
var _close_btn: Button90


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_items = _load_items()
	_build()
	resized.connect(_layout)
	_layout()
	visible = false


# --- публичное -------------------------------------------------------------

func open(p_money: int, p_levels: Dictionary = {}) -> void:
	money = maxi(0, p_money)
	levels = p_levels.duplicate(true)
	visible = true
	_sync_buttons()
	_layout()
	queue_redraw()


func refresh(p_money: int, p_levels: Dictionary = {}) -> void:
	open(p_money, p_levels)


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


## Цена позиции (для интеграции и предпросмотра).
func item_price(id: String) -> int:
	for item in _items:
		if str(item["id"]) == id:
			return int(item["price"])
	return 0


func item_name(id: String) -> String:
	for item in _items:
		if str(item["id"]) == id:
			return str(item["name"])
	return id


func item_max_level(id: String) -> int:
	for item in _items:
		if str(item["id"]) == id:
			return int(item["max_level"])
	return 1


# --- данные ----------------------------------------------------------------

func _load_items() -> Array:
	var data := get_node_or_null("/root/Data")
	var raw = null
	if data != null:
		raw = data.get("shop")
	if raw is Array and not (raw as Array).is_empty():
		var out: Array = []
		for it in raw:
			if it is Dictionary and not str(it.get("id", "")).is_empty():
				out.append(_normalize(it))
		if out.size() >= 9:
			return out
		# Данные короче — добираем недостающие позиции из встроенной копии.
		for fb in FALLBACK_SHOP:
			var fid := str(fb["id"])
			var has := false
			for item in out:
				if str(item["id"]) == fid:
					has = true
					break
			if not has:
				out.append(_normalize(fb))
		return out
	var fallback: Array = []
	for fb in FALLBACK_SHOP:
		fallback.append(_normalize(fb))
	return fallback


func _normalize(src: Dictionary) -> Dictionary:
	var id := str(src.get("id", ""))
	var item_name := str(src.get("name_ru", src.get("name", "")))
	if item_name.is_empty():
		item_name = _tr("shop." + id, id)
	var price := int(src.get("price", src.get("cost", 0)))
	var max_level := maxi(1, int(src.get("max_level", 1)))
	var effect := str(src.get("effect", ""))
	var desc := str(src.get("desc_ru", ""))
	if desc.is_empty():
		desc = str(EFFECT_DESC.get(effect, "Улучшение рабочего места"))
	return {"id": id, "name": item_name, "price": maxi(0, price), "max_level": max_level,
		"effect": effect, "desc": desc}


func _tr(key: String, fallback: String) -> String:
	var data := get_node_or_null("/root/Data")
	if data != null and data.has_method("has_string") and data.has_string(key):
		var value := str(data.tr(key))
		if not value.is_empty() and value != key:
			return value
	return fallback


func _level_of(id: String) -> int:
	return clampi(int(levels.get(id, 0)), 0, 99)


func _maxed(item: Dictionary) -> bool:
	return _level_of(str(item["id"])) >= int(item["max_level"])


func _can_afford(item: Dictionary) -> bool:
	return money >= int(item["price"])


# --- сборка ----------------------------------------------------------------

func _build() -> void:
	for it in _items:
		var b := Button90.new()
		b.name = "Buy_" + str(it["id"])
		b.caption = _tr("btn.buy", "Купить")
		b.caption_size = Theme90.FS_BODY
		b.pressed.connect(_on_buy.bind(str(it["id"])))
		add_child(b)
		_buttons.append(b)

	_close_btn = Button90.new()
	_close_btn.name = "CloseButton"
	_close_btn.caption = _tr("btn.close", "Закрыть")
	_close_btn.caption_size = Theme90.FS_BODY
	_close_btn.pressed.connect(close)
	add_child(_close_btn)

	var x_btn := Button90.new()
	x_btn.name = "CloseX"
	x_btn.icon = Button90.Icon.X
	x_btn.caption = ""
	x_btn.tooltip_text = "Закрыть"
	x_btn.pressed.connect(close)
	add_child(x_btn)
	x_btn.set_meta("is_close_x", true)


func _window_rect() -> Rect2:
	var s := size
	if s.x <= 0.0 or s.y <= 0.0:
		s = Vector2(1280, 720)
	return Rect2(((s - Vector2(W, H)) * 0.5).round(), Vector2(W, H))


func _layout() -> void:
	var r := _window_rect()
	for i in _buttons.size():
		_buttons[i].position = r.position + Vector2(796, ROW_Y + i * ROW_H + 14)
		_buttons[i].size = Vector2(104, 24)
	_close_btn.position = r.position + Vector2(782, 546)
	_close_btn.size = Vector2(110, 24)
	for child in get_children():
		if child is Button90 and child.has_meta("is_close_x"):
			child.position = r.position + Vector2(W - 22, 4)
			child.size = Vector2(16, 16)


func _sync_buttons() -> void:
	for i in _items.size():
		if i >= _buttons.size():
			break
		var item: Dictionary = _items[i]
		var b := _buttons[i]
		if _maxed(item):
			b.caption = "Максимум"
			b.disabled = true
			b.accent = false
		elif not _can_afford(item):
			b.caption = _tr("btn.buy", "Купить")
			b.disabled = true
			b.accent = false
		else:
			b.caption = _tr("btn.buy", "Купить")
			b.disabled = false
			b.accent = true


func _on_buy(id: String) -> void:
	buy_requested.emit(id)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


# --- отрисовка -------------------------------------------------------------

func _draw() -> void:
	var full := Rect2(Vector2.ZERO, size)
	if size.x <= 0.0 or size.y <= 0.0:
		full = Rect2(0, 0, 1280, 720)
	draw_rect(full, DIM)
	var r := _window_rect()
	_draw_frame(r)
	_draw_header(r)
	for i in _items.size():
		_draw_row(r, i)
	_draw_footer(r)


func _draw_frame(r: Rect2) -> void:
	Theme90.draw_bevel(self, r, false, Theme90.BEVEL, Theme90.FACE)
	var inner := r.grow(-Theme90.BEVEL)
	draw_rect(Rect2(inner.position, Vector2(inner.size.x, 1)), Theme90.FACE_HI)
	draw_rect(Rect2(inner.position, Vector2(1, inner.size.y)), Theme90.FACE_HI)

	var tr := Rect2(r.position + Vector2(2, 2), Vector2(r.size.x - 4.0, TITLE_H))
	Theme90.draw_vgrad(self, tr, Theme90.NAVY, Theme90.NAVY_DEEP)
	draw_rect(Rect2(tr.position, Vector2(tr.size.x, 1)), Color(0.0, 0.0, 0.372549))
	draw_rect(Rect2(tr.position.x, tr.end.y - 1, tr.size.x, 1), Theme90.DARK)
	draw_rect(Rect2(tr.position.x, tr.end.y - 2, tr.size.x, 1), Theme90.ACCENT)

	# ценник
	Theme90.text_vcenter(self, Theme90.logo(), Rect2(tr.position.x + 4, tr.position.y, 14, TITLE_H),
		"$", 10, Theme90.WHITE)

	var f := Theme90.ui()
	Theme90.text_vcenter(self, f, Rect2(tr.position.x + 22, tr.position.y, 140, TITLE_H),
		"МАГАЗИН", Theme90.FS_BODY, Theme90.WHITE)

	var hint := "УЛУЧШЕНИЯ · %d ПОЗИЦИЙ" % _items.size()
	Theme90.text_vcenter(self, f, Rect2(tr.position.x, tr.position.y, tr.size.x - 40, TITLE_H),
		hint, Theme90.FS_MICRO, Theme90.ACCENT_LIGHT, -1, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_header(r: Rect2) -> void:
	var hdr := Rect2(r.position + Vector2(10, 26), Vector2(r.size.x - 20, 32))
	Theme90.draw_bevel(self, hdr, true, 2.0, Theme90.FACE)
	var f := Theme90.ui()
	Theme90.text_vcenter(self, f, Rect2(hdr.position.x + 8, hdr.position.y, 60, hdr.size.y),
		"БАЛАНС", Theme90.FS_MICRO, Theme90.DARK)
	Theme90.text_vcenter(self, Theme90.logo(), Rect2(hdr.position.x + 60, hdr.position.y, 240, hdr.size.y),
		_fmt(money) + " $", 14, Theme90.INK)

	var bought := 0
	for it in _items:
		if _level_of(str(it["id"])) > 0:
			bought += 1
	Theme90.text_vcenter(self, f, Rect2(hdr.position.x, hdr.position.y, hdr.size.x - 8, hdr.size.y),
		"КУПЛЕНО %d ИЗ %d" % [bought, _items.size()], Theme90.FS_MICRO, Theme90.DARK,
		-1, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_row(r: Rect2, index: int) -> void:
	var item: Dictionary = _items[index]
	var ry := r.position.y + ROW_Y + index * ROW_H
	var row := Rect2(r.position.x + 10, ry, r.size.x - 20, ROW_H)
	var level := _level_of(str(item["id"]))
	var max_level := int(item["max_level"])
	var price := int(item["price"])
	var f := Theme90.ui()

	# разделитель строки (у последней строки его нет — там уже линия подвала)
	if index < _items.size() - 1:
		draw_rect(Rect2(row.position.x, row.end.y - 1, row.size.x, 1), Theme90.SHADE)
		draw_rect(Rect2(row.position.x, row.end.y, row.size.x, 1), Theme90.FACE_HI)

	# иконка
	var icon_box := Rect2(row.position.x + 8, ry + 12, 28, 28)
	Theme90.draw_bevel(self, icon_box, true, 1.0, Theme90.FACE)
	_draw_item_icon(str(item["effect"]), icon_box)

	# название и эффект
	Theme90.text(self, f, Vector2(row.position.x + 46, ry + 6),
		Theme90.fit(f, str(item["name"]), Theme90.FS_BODY, 428), Theme90.FS_BODY, Theme90.INK)
	Theme90.text(self, f, Vector2(row.position.x + 46, ry + 23),
		Theme90.fit(f, str(item["desc"]), Theme90.FS_MICRO, 428), Theme90.FS_MICRO, Theme90.DARK)

	# уровень
	Theme90.text(self, f, Vector2(row.position.x + 486, ry + 5), "УРОВЕНЬ",
		Theme90.FS_MICRO, Theme90.DARK)
	Theme90.text(self, Theme90.logo(), Vector2(row.position.x + 486, ry + 18),
		"%d/%d" % [level, max_level], 9, Theme90.NAVY)
	var px := row.position.x + 486 + 36
	for i in max_level:
		var pip := Rect2(px + i * 10, ry + 25, 6, 5)
		if i < level:
			draw_rect(pip, Theme90.NAVY)
		else:
			draw_rect(pip, Theme90.FACE_LO)
			Theme90.draw_bevel(self, pip, true, 1.0, Theme90.FACE_LO)

	# цена
	Theme90.text_vcenter(self, f, Rect2(row.position.x + 600, ry + 4, 168, 12), "ЦЕНА",
		Theme90.FS_MICRO, Theme90.DARK, -1, HORIZONTAL_ALIGNMENT_RIGHT)
	var price_text := _fmt(price) + " $"
	Theme90.text_vcenter(self, Theme90.logo(), Rect2(row.position.x + 600, ry + 12, 168, 16),
		price_text, 12, Theme90.INK, -1, HORIZONTAL_ALIGNMENT_RIGHT)

	if _maxed(item):
		Theme90.text_vcenter(self, f, Rect2(row.position.x + 590, ry + 30, 178, 12), "ВСЁ КУПЛЕНО",
			Theme90.FS_MICRO, Theme90.SUCCESS, -1, HORIZONTAL_ALIGNMENT_RIGHT)
	elif not _can_afford(item):
		var short_by := price - money
		Theme90.text_vcenter(self, f, Rect2(row.position.x + 570, ry + 30, 198, 12),
			"НЕ ХВАТАЕТ %d" % short_by, Theme90.FS_MICRO, Theme90.ERROR,
			-1, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_footer(r: Rect2) -> void:
	var y := r.position.y + 538
	draw_rect(Rect2(r.position.x + 10, y, r.size.x - 20, 1), Theme90.SHADE)
	draw_rect(Rect2(r.position.x + 10, y + 1, r.size.x - 20, 1), Theme90.FACE_HI)
	var f := Theme90.ui()
	Theme90.text(self, f, Vector2(r.position.x + 16, y + 14),
		"УЛУЧШЕНИЯ ДЕЙСТВУЮТ ДО КОНЦА ЗАБЕГА · ESC — ЗАКРЫТЬ", Theme90.FS_MICRO, Theme90.DARK)


func _draw_item_icon(effect: String, box: Rect2) -> void:
	var x := box.position.x + 4.0
	var y := box.position.y + 4.0
	var c := Theme90.NAVY
	var a := Theme90.ACCENT
	match effect:
		"connection_slots":
			draw_rect(Rect2(x + 3, y + 4, 5, 9), c, false, 1.0)
			draw_rect(Rect2(x + 12, y + 4, 5, 9), c, false, 1.0)
			draw_rect(Rect2(x + 6, y + 7, 8, 1), c)
			draw_rect(Rect2(x + 9, y + 9, 2, 7), c)
			draw_rect(Rect2(x + 7, y + 16, 6, 2), c)
		"buffer_slots":
			for i in 3:
				draw_rect(Rect2(x + 3, y + 4 + i * 5, 14, 3), c if i < 2 else a)
			draw_rect(Rect2(x + 3, y + 4, 14, 1), Theme90.FACE_HI)
		"packet_timer":
			draw_rect(Rect2(x + 3, y + 4, 14, 14), c, false, 1.0)
			draw_rect(Rect2(x + 9, y + 6, 2, 5), c)
			draw_rect(Rect2(x + 10, y + 10, 4, 2), a)
			draw_rect(Rect2(x + 8, y + 1, 4, 2), c)
		"zone_width":
			draw_rect(Rect2(x + 2, y + 3, 16, 14), c, false, 1.0)
			draw_rect(Rect2(x + 6, y + 6, 8, 8), a, false, 1.0)
			draw_rect(Rect2(x + 9, y + 9, 2, 2), c)
		"channel_capacity":
			draw_rect(Rect2(x + 2, y + 6, 10, 8), c, false, 1.0)
			draw_colored_polygon(PackedVector2Array([
				Vector2(x + 12, y + 5), Vector2(x + 18, y + 10), Vector2(x + 12, y + 15)]), a)
		"sections":
			Theme90.draw_folder_icon(self, Vector2(x + 3, y + 5), Theme90.WARN, false)
		"search_highlight":
			draw_rect(Rect2(x + 3, y + 3, 10, 10), c, false, 1.0)
			draw_rect(Rect2(x + 5, y + 5, 6, 6), a)
			draw_line(Vector2(x + 12, y + 12), Vector2(x + 17, y + 17), c, 2.0)
		"shield":
			draw_colored_polygon(PackedVector2Array([
				Vector2(x + 10, y + 2), Vector2(x + 17, y + 5), Vector2(x + 16, y + 12),
				Vector2(x + 10, y + 18), Vector2(x + 4, y + 12), Vector2(x + 3, y + 5)]), a)
			draw_rect(Rect2(x + 9, y + 7, 2, 5), Theme90.WHITE)
			draw_rect(Rect2(x + 9, y + 13, 2, 2), Theme90.WHITE)
		_:
			draw_rect(Rect2(x + 4, y + 4, 12, 12), c, false, 1.0)
			draw_rect(Rect2(x + 7, y + 7, 6, 6), a)


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
