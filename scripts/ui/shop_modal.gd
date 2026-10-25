class_name ShopModal
extends Control
## Магазин: светлое окно, до 10 позиций, компактные строки, без крестика.
## Закрытие — только кнопкой «Закрыть» (или Esc).
##
##   shop.open(Game.money, Game.upgrades)
##   shop.buy_requested.connect(_on_buy)
##   shop.closed.connect(_on_closed)

signal buy_requested(id: String)
signal closed

const W := 900.0
const H := 600.0
const HEADER_H := 40.0
const ROW_Y := 96.0
const ROWS_BOTTOM := 536.0
const MAX_ROW_H := 52.0
const DIM := Color(0.11, 0.12, 0.11, 0.30)

## Копия data/balance.json → shop. Backend может добавить shop_sla и фильтр
## Data.available_shop(); здесь — безопасный fallback на 10 позиций.
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
	{"id": "shop_sla", "name_ru": "SLA +24", "price": 300, "max_level": 3, "effect": "sla_add"},
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
	"sla_add": "Запас SLA на смену",
}

var money := 0
var levels: Dictionary = {}

var _items: Array = []
var _buttons: Array[Button90] = []
var _close_btn: Button90
var _row_h := MAX_ROW_H


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
	# available_shop() зависит от часа и мета-разблокировок — читаем при каждом открытии.
	_items = _load_items()
	_rebuild_buttons()
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
	if data == null:
		return _fallback_items()

	# Основной путь: готовый отфильтрованный каталог. Показываем ровно его.
	if data.has_method("available_shop"):
		var filtered = data.call("available_shop")
		var from_filter := _normalize_items(filtered)
		if not from_filter.is_empty():
			return from_filter

	# Data есть, но фильтр недоступен/пуст: берём Data.shop.
	var raw = data.get("shop")
	var out := _normalize_items(raw)
	if data.has_method("shop_item_unlocked"):
		var opened: Array = []
		for item in out:
			var src := _find_raw(raw, str(item["id"]))
			if src.is_empty() or bool(data.call("shop_item_unlocked", src)):
				opened.append(item)
		out = opened
	if not out.is_empty():
		return out

	# Совсем нет данных — безопасный статический fallback (dev/превью).
	return _fallback_items()


func _normalize_items(raw: Variant) -> Array:
	var out: Array = []
	if raw is Array:
		for it in raw:
			if it is Dictionary and not str(it.get("id", "")).is_empty():
				out.append(_normalize(it))
	return out


func _find_raw(raw: Variant, id: String) -> Dictionary:
	if raw is Array:
		for it in raw:
			if it is Dictionary and str(it.get("id", "")) == id:
				return it
	return {}


func _fallback_items() -> Array:
	var out: Array = []
	for fb in FALLBACK_SHOP:
		out.append(_normalize(fb))
	return out


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
	_rebuild_buttons()

	_close_btn = Button90.new()
	_close_btn.name = "CloseButton"
	_close_btn.caption = _tr("btn.close", "Закрыть")
	_close_btn.caption_size = Theme90.FS_BODY
	_close_btn.pressed.connect(close)
	add_child(_close_btn)


## Пересоздаёт кнопки под актуальный список позиций (каталог меняется
## при разблокировке магазина/поиска/щита).
func _rebuild_buttons() -> void:
	for b in _buttons:
		if is_instance_valid(b):
			if b.get_parent() != null:
				b.get_parent().remove_child(b)
			b.queue_free()
	_buttons.clear()
	for it in _items:
		var b := Button90.new()
		b.name = "Buy_" + str(it["id"])
		b.caption = _tr("btn.buy", "Купить")
		b.caption_size = Theme90.FS_MICRO
		b.pressed.connect(_on_buy.bind(str(it["id"])))
		add_child(b)
		_buttons.append(b)


func _window_rect() -> Rect2:
	var s := size
	if s.x <= 0.0 or s.y <= 0.0:
		s = Vector2(1280, 720)
	return Rect2(((s - Vector2(W, H)) * 0.5).round(), Vector2(W, H))


func _layout() -> void:
	var r := _window_rect()
	var n := maxi(1, _items.size())
	_row_h = clampf(floorf((ROWS_BOTTOM - ROW_Y) / float(n)), 30.0, MAX_ROW_H)
	var btn_h := minf(24.0, _row_h - 10.0)
	for i in _buttons.size():
		var ry := ROW_Y + i * _row_h
		_buttons[i].position = r.position + Vector2(W - 128.0, ry + (_row_h - btn_h) * 0.5)
		_buttons[i].size = Vector2(104, btn_h)
	_close_btn.position = r.position + Vector2(W - 136.0, H - 40.0)
	_close_btn.size = Vector2(112, 24)


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
	for i in _items.size():
		_draw_row(r, i)


func _draw_frame(r: Rect2) -> void:
	draw_style_box(Theme90.box(Theme90.WHITE, Theme90.BORDER, 6, 1,
		Color(0, 0, 0, 0.16)), r)
	var header := Rect2(r.position.x + 1, r.position.y + 1, r.size.x - 2, HEADER_H - 1)
	draw_style_box(Theme90.top_box(Theme90.PAPER_HI, 6), header)

	# заголовок: точка + название, подпись справа
	draw_circle(Vector2(header.position.x + 20, header.position.y + 20), 3.5,
		Theme90.ACCENT)
	var f := Theme90.ui()
	Theme90.text(self, f, Vector2(header.position.x + 31, header.position.y + 11),
		"МАГАЗИН", 16, Theme90.NAVY, 160)
	var sub := "УЛУЧШЕНИЯ · %d" % _items.size()
	var sw := f.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	Theme90.text(self, f, Vector2(header.end.x - sw - 20, header.position.y + 14),
		sub, 10, Theme90.SHADE)
	draw_rect(Rect2(r.position.x + 1, r.position.y + HEADER_H, r.size.x - 2, 1),
		Theme90.HAIRLINE)

	# баланс
	var hdr := Rect2(r.position.x + 20, r.position.y + 52, r.size.x - 40, 32)
	draw_style_box(Theme90.box(Theme90.PAPER_HI, Theme90.BORDER_SOFT, 3, 1), hdr)
	Theme90.text_vcenter(self, f, Rect2(hdr.position.x + 12, hdr.position.y, 54,
		hdr.size.y), "БАЛАНС", 10, Theme90.SHADE)
	Theme90.text_vcenter(self, Theme90.logo(), Rect2(hdr.position.x + 62, hdr.position.y,
		200, hdr.size.y), _fmt(money) + " $", 12, Theme90.INK)
	var bought := 0
	for it in _items:
		if _level_of(str(it["id"])) > 0:
			bought += 1
	Theme90.text_vcenter(self, f, Rect2(hdr.position.x, hdr.position.y,
		hdr.size.x - 12, hdr.size.y), "КУПЛЕНО %d ИЗ %d" % [bought, _items.size()],
		10, Theme90.SHADE, -1, HORIZONTAL_ALIGNMENT_RIGHT)

	# подвал
	Theme90.text(self, f, Vector2(r.position.x + 22, r.position.y + H - 31),
		"Улучшения действуют до конца смены · Esc — закрыть", 10, Theme90.SHADE)


func _draw_row(r: Rect2, index: int) -> void:
	var item: Dictionary = _items[index]
	var ry := r.position.y + ROW_Y + index * _row_h
	var row := Rect2(r.position.x + 20, ry, r.size.x - 40, _row_h)
	var level := _level_of(str(item["id"]))
	var max_level := int(item["max_level"])
	var price := int(item["price"])
	var f := Theme90.ui()

	if index > 0:
		draw_rect(Rect2(row.position.x, row.position.y, row.size.x, 1), Theme90.HAIRLINE)

	var icon_box := Rect2(row.position.x + 8, ry + (_row_h - 28.0) * 0.5, 28, 28)
	var tint := _effect_color(str(item["effect"]))
	draw_style_box(Theme90.box(Color(tint.r, tint.g, tint.b, 0.12), Color(0, 0, 0, 0), 5, 0),
		icon_box)
	_draw_item_icon(str(item["effect"]), icon_box, tint)

	Theme90.text(self, f, Vector2(row.position.x + 46, ry + 7),
		Theme90.fit(f, str(item["name"]), 12, 360), 12, Theme90.INK)
	Theme90.text(self, f, Vector2(row.position.x + 46, ry + 23),
		Theme90.fit(f, str(item["desc"]), 10, 380), 10, Theme90.SHADE)

	# уровень: подпись + точки
	var lx := row.position.x + 452
	Theme90.text(self, f, Vector2(lx, ry + 6), "УРОВЕНЬ %d/%d" % [level, max_level], 10,
		Theme90.SHADE)
	var px := lx
	var py := ry + 23.0
	for i in max_level:
		var pip := Rect2(px + i * 10, py, 7, 6)
		if i < level:
			draw_style_box(Theme90.fill_box(Theme90.ACCENT, 3), pip)
		else:
			draw_style_box(Theme90.box(Theme90.PAPER_HI, Theme90.BORDER_SOFT, 3, 1), pip)

	# цена и подсказка — двумя строками, без наложений
	Theme90.text_vcenter(self, f, Rect2(row.position.x + 596, ry + 3, 150, 20),
		_fmt(price) + " $", 14, Theme90.INK, -1, HORIZONTAL_ALIGNMENT_RIGHT)
	if _maxed(item):
		Theme90.text_vcenter(self, f, Rect2(row.position.x + 566, ry + 23,
			180, 14), "ВСЁ КУПЛЕНО", 10, Theme90.SUCCESS, -1,
			HORIZONTAL_ALIGNMENT_RIGHT)
	elif not _can_afford(item):
		Theme90.text_vcenter(self, f, Rect2(row.position.x + 546, ry + 23,
			200, 14), "НЕ ХВАТАЕТ %d" % (price - money), 10, Theme90.ERROR, -1,
			HORIZONTAL_ALIGNMENT_RIGHT)


func _effect_color(effect: String) -> Color:
	match effect:
		"packet_timer", "sections":
			return Theme90.WARN
		"zone_width", "shield":
			return Theme90.SUCCESS
		"search_highlight", "sla_max":
			return Theme90.NAVY
		_:
			return Theme90.ACCENT


func _draw_item_icon(effect: String, box: Rect2, c: Color) -> void:
	var x := box.position.x + 5.0
	var y := box.position.y + 4.0
	var a := Theme90.NAVY
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
			Theme90.draw_folder_icon(self, Vector2(x + 3, y + 5), c, false)
		"search_highlight":
			draw_rect(Rect2(x + 3, y + 3, 10, 10), c, false, 1.0)
			draw_rect(Rect2(x + 5, y + 5, 6, 6), a)
			draw_line(Vector2(x + 12, y + 12), Vector2(x + 17, y + 17), c, 2.0)
		"shield":
			draw_colored_polygon(PackedVector2Array([
				Vector2(x + 10, y + 2), Vector2(x + 17, y + 5), Vector2(x + 16, y + 12),
				Vector2(x + 10, y + 18), Vector2(x + 4, y + 12), Vector2(x + 3, y + 5)]), c)
			draw_rect(Rect2(x + 9, y + 7, 2, 5), Theme90.WHITE)
			draw_rect(Rect2(x + 9, y + 13, 2, 2), Theme90.WHITE)
		"sla_max":
			draw_rect(Rect2(x + 3, y + 3, 14, 14), c, false, 1.0)
			draw_rect(Rect2(x + 6, y + 6, 8, 2), c)
			draw_rect(Rect2(x + 6, y + 10, 5, 2), c)
			draw_rect(Rect2(x + 6, y + 14, 3, 2), a)
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
