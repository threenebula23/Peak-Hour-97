class_name FileGrid
extends Control
## Сетка файлов 4×132 с отступом 8: светлое поле, аккуратный путь сверху,
## спокойный подвал. Пустая папка — мягкий пунктир. Принимает файлы/пакеты.

signal file_selected(id: String)
signal file_activated(id: String)
signal file_context_requested(id: String, global_pos: Vector2)
signal file_dropped(folder_id: String, payload: Dictionary)
signal service_filter_changed(on: bool)

const COLS := 4
const CARD := Vector2(132, 84)
const GAP := 8.0

var folder_id := ""
var folder_name := "ПАПКА"
var path_text := "C: \\ ПРИЁМ"
var total_kb := 0

var _view: Control
var _content: Control
var _bar: ScrollBar90
var _cards: Array[FileCard] = []
var _selected := ""
var _drop_hover := false
var _check: Check90
var service_filter := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_view = Control.new()
	_view.name = "View"
	_view.mouse_filter = Control.MOUSE_FILTER_PASS
	_view.clip_contents = true
	add_child(_view)
	_content = Control.new()
	_content.name = "Content"
	_content.mouse_filter = Control.MOUSE_FILTER_PASS
	_view.add_child(_content)
	_bar = ScrollBar90.new()
	_bar.name = "Scroll"
	add_child(_bar)
	_bar.value_changed.connect(_on_scroll)
	_check = Check90.new()
	_check.name = "ServiceCheck"
	_check.caption = "СКРЫТЬ СЛУЖЕБНЫЕ"
	add_child(_check)
	_check.toggled.connect(_on_service_toggled)

	resized.connect(_relayout)
	_relayout()


func _on_service_toggled(on: bool) -> void:
	service_filter = on
	_apply_filter()
	service_filter_changed.emit(on)


func _apply_filter() -> void:
	for c in _cards:
		var hidden := service_filter and (c.state == "locked" or c.state == "malicious"
			or c.state == "failed")
		c.visible = not hidden
	queue_redraw()


func _visible_count() -> int:
	if not service_filter:
		return _cards.size()
	var n := 0
	for c in _cards:
		if c.visible:
			n += 1
	return n


func _visible_kb() -> int:
	var n := 0
	for c in _cards:
		if c.visible:
			n += int(c.size_kb)
	return n


func _path_rect() -> Rect2:
	return Rect2(2, 2, maxf(0.0, size.x - 4.0), 22)


func _view_rect() -> Rect2:
	return Rect2(2, 26, maxf(0.0, size.x - 18.0), maxf(0.0, size.y - 44.0))


func _footer_rect() -> Rect2:
	return Rect2(2, size.y - 17, maxf(0.0, size.x - 4.0), 14)


func _relayout() -> void:
	if _view == null:
		return
	var vr := _view_rect()
	_view.position = vr.position
	_view.size = vr.size
	_bar.position = Vector2(size.x - 16.0, vr.position.y + 4.0)
	_bar.size = Vector2(Theme90.SCROLLBAR, maxf(8.0, vr.size.y - 8.0))
	if _check != null:
		_check.position = Vector2(158, size.y - 18.0)
		_check.size = Vector2(160, 14)
	_content_height()
	queue_redraw()


func _content_height() -> float:
	var rows := int(ceilf(_cards.size() / float(COLS)))
	var h := maxf(0.0, rows * (CARD.y + GAP) - GAP + 2.0)
	if _bar != null and _view != null:
		_bar.set_metrics(_view.size.y, maxf(_view.size.y, h))
	return h


func set_folder(p_id: String, p_name: String, p_path: String) -> void:
	folder_id = p_id
	folder_name = p_name
	path_text = p_path
	queue_redraw()


## files: [{id, name, ext, size_kb, type, state}]
func set_files(files: Array) -> void:
	for c in _cards:
		c.queue_free()
	_cards.clear()
	total_kb = 0
	for i in files.size():
		var d: Dictionary = files[i]
		var card := FileCard.new()
		card.name = "File_%s" % str(d.get("id", i))
		card.setup(str(d.get("id", "")), str(d.get("name", "")), str(d.get("ext", "")),
			int(d.get("size_kb", 0)), str(d.get("type", "text")), str(d.get("state", "stored")))
		var col := i % COLS
		var row := i / COLS
		card.position = Vector2(1 + col * (CARD.x + GAP), 4 + row * (CARD.y + GAP))
		card.size = CARD
		card.file_selected.connect(_on_card_selected)
		card.file_activated.connect(func(id: String) -> void: file_activated.emit(id))
		card.context_requested.connect(func(id: String, pos: Vector2) -> void:
			file_context_requested.emit(id, pos))
		_content.add_child(card)
		_cards.append(card)
		total_kb += int(d.get("size_kb", 0))
	_content_height()
	_apply_filter()
	if not _selected.is_empty():
		select_file(_selected)


func _on_card_selected(id: String) -> void:
	_selected = id
	for c in _cards:
		c.selected = c.id == id
	file_selected.emit(id)


func select_file(id: String) -> void:
	_selected = id
	for c in _cards:
		c.selected = c.id == id


func _on_scroll(v: float) -> void:
	if _content != null:
		_content.position = Vector2(0, -v)


func get_cards() -> Array[FileCard]:
	return _cards


## Запрос от FileCard: файл бросили на другой файл — считаем, что в эту папку.
func accept_dropped_file(data: Dictionary) -> void:
	if data.get("kind", "") == "file" and data.get("id", "") == _selected:
		return
	file_dropped.emit(folder_id, data)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	var k: String = data.get("kind", "")
	if k != "file" and k != "packet":
		return false
	if not _drop_hover:
		_drop_hover = true
		queue_redraw()
	return true


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_drop_hover = false
	queue_redraw()
	file_dropped.emit(folder_id, data)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_drop_hover = false
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_bar.value -= 32.0
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_bar.value += 32.0
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_selected = ""
			for c in _cards:
				c.selected = false
			accept_event()


func _draw() -> void:
	var f := Theme90.ui()
	var pr := _path_rect()
	var vr := _view_rect()
	var fr := _footer_rect()

	# путь — светлая полоса без утопленной рамки
	draw_style_box(Theme90.box(Theme90.PAPER_HI, Theme90.BORDER_SOFT, 3, 1), pr)
	draw_style_box(Theme90.fill_box(Color(Theme90.ACCENT.r, Theme90.ACCENT.g,
		Theme90.ACCENT.b, 0.14), 2), Rect2(pr.position.x + 7, pr.position.y + 5, 12, 12))
	Theme90.draw_folder_icon(self, Vector2(pr.position.x + 6, pr.position.y + 6),
		Theme90.ACCENT, true)
	Theme90.text_vcenter(self, f, Rect2(pr.position.x + 24, pr.position.y,
		pr.size.x - 150, pr.size.y), Theme90.fit(f, path_text, 12, pr.size.x - 160),
		12, Theme90.INK)
	var cnt := "%d объектов" % _visible_count()
	var cw := f.get_string_size(cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	Theme90.text(self, f, Vector2(pr.end.x - cw - 9, pr.position.y + 6), cnt, 10,
		Theme90.SHADE)

	# поле сетки
	draw_style_box(Theme90.box(Theme90.PAPER_HI, Theme90.BORDER_SOFT, 3, 1), vr)

	if _cards.is_empty():
		var dz := Rect2(vr.position.x + 24, vr.position.y + 24, vr.size.x - 48, vr.size.y - 48)
		Theme90.draw_dashed_box(self, dz, Color(Theme90.SHADE.r, Theme90.SHADE.g,
			Theme90.SHADE.b, 0.45), 5.0, 1.0)
		var t1 := "ПУСТО"
		var t2 := "перетащите сюда пакет или файл"
		var w1 := f.get_string_size(t1, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var w2 := f.get_string_size(t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var cy := vr.get_center().y
		Theme90.text(self, f, Vector2(vr.get_center().x - w1 * 0.5, cy - 18), t1, 16,
			Theme90.NAVY)
		Theme90.text(self, f, Vector2(vr.get_center().x - w2 * 0.5, cy + 6), t2, 11,
			Theme90.SHADE)

	if _drop_hover:
		draw_style_box(Theme90.box(Color(Theme90.ACCENT_PALE.r, Theme90.ACCENT_PALE.g,
			Theme90.ACCENT_PALE.b, 0.55), Theme90.ACCENT, 3, 1), vr.grow(-2.0))
		var hint := "переместить в «%s»" % folder_name
		var hw := f.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var pill := Rect2(vr.get_center().x - hw * 0.5 - 14, vr.position.y + 8,
			hw + 28, 24)
		draw_style_box(Theme90.box(Theme90.WHITE, Theme90.ACCENT_LIGHT, 4, 1,
			Theme90.SHADOW), pill)
		Theme90.text_vcenter(self, f, pill, hint, 12, Theme90.NAVY, -1,
			HORIZONTAL_ALIGNMENT_CENTER)
		Theme90.draw_dashed_box(self, vr.grow(-1.0), Theme90.ACCENT, 4.0, 1.2)

	# подвал
	Theme90.text(self, f, Vector2(fr.position.x + 2, fr.position.y),
		"%s КБ · сортировка по имени" % _spaced(_visible_kb()), 10, Theme90.SHADE)
	var free := "свободно 8,5 МБ"
	var fw := f.get_string_size(free, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	Theme90.text(self, f, Vector2(fr.end.x - fw - 2, fr.position.y), free, 10,
		Theme90.SHADE)


static func _spaced(v: int) -> String:
	var s := str(v)
	var out := ""
	var n := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		n += 1
		if n % 3 == 0 and i > 0:
			out = " " + out
	return out
