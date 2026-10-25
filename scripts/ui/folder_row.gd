class_name FolderRow
extends Control
## Строка дерева 24 px: мягкий шеврон, папка, имя, счётчик «3/16».
## Выделение — светлая teal-подложка с тонкой полоской слева, без инверсии.
## Секции C:/D:/E: — спокойная строка с волосяной линией снизу.

signal folder_selected(folder_id: String)
signal expansion_toggled(folder_id: String)
signal file_dropped(folder_id: String, payload: Dictionary)
signal packet_dropped(folder_id: String, payload: Dictionary)
signal context_menu_requested(folder_id: String, global_pos: Vector2)
## Папка раскрыта/открыта наведением во время drag (250 мс).
signal hover_open_requested(folder_id: String)

const ROW_H := 24.0
const SECTION_H := 22.0

var folder_id := ""
var folder_name := ""
## v2: count — занятые КЛЕТКИ, capacity — всего клеток.
var count := 0
var capacity := 16
## Число файлов (для тултипа «N файлов · X из Y клеток»).
var files_count := 0
var free_text := ""
var depth := 0
var is_section := false
var expandable := true
var hover_open := false:
	set(v):
		if hover_open == v:
			return
		hover_open = v
		queue_redraw()
		if v and not is_section:
			hover_open_requested.emit(folder_id)
var expanded := true:
	set(v):
		expanded = v
		queue_redraw()
var selected := false:
	set(v):
		selected = v
		queue_redraw()
var hovered := false:
	set(v):
		hovered = v
		queue_redraw()
var drop_active := false:
	set(v):
		if drop_active != v:
			drop_active = v
			queue_redraw()
var locked := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	custom_minimum_size = Vector2(0, SECTION_H if is_section else ROW_H)
	if size.y == 0.0:
		size.y = custom_minimum_size.y
	mouse_entered.connect(func() -> void: hovered = true)
	mouse_exited.connect(func() -> void: hovered = false)
	set_process(false)


func setup(p_id: String, p_name: String, p_depth: int, p_section: bool = false) -> void:
	folder_id = p_id
	folder_name = p_name
	depth = p_depth
	is_section = p_section
	custom_minimum_size.y = SECTION_H if p_section else ROW_H
	if size.y < custom_minimum_size.y:
		size.y = custom_minimum_size.y
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var f := Theme90.ui()
	if is_section:
		_draw_section(r, f)
		return

	if selected:
		draw_style_box(Theme90.box(Theme90.ACCENT_PALE, Color(0, 0, 0, 0), 3, 0),
			Rect2(2, 1, size.x - 4, size.y - 2))
		draw_rect(Rect2(2, 5, 2, size.y - 10), Theme90.ACCENT)
	elif drop_active:
		draw_style_box(Theme90.box(Theme90.ACCENT_PALE, Theme90.ACCENT, 3, 1),
			Rect2(2, 1, size.x - 4, size.y - 2))
	elif hover_open:
		draw_style_box(Theme90.box(Theme90.ACCENT_PALE, Theme90.ACCENT_LIGHT, 3, 1),
			Rect2(2, 1, size.x - 4, size.y - 2))
		draw_rect(Rect2(2, 5, 2, size.y - 10), Theme90.ACCENT_LIGHT)
	elif hovered:
		draw_rect(Rect2(2, 1, size.x - 4, size.y - 2), Color(1, 1, 1, 0.45))

	var fg := Theme90.NAVY if selected else Theme90.INK
	var sub := Theme90.ACCENT if selected else Theme90.SHADE
	var sx := 5.0 + depth * 12.0

	# тонкий шеврон вместо объёмного квадрата
	if expandable:
		Theme90.draw_chevron(self, Vector2(sx + 6, size.y * 0.5), 1 if expanded else 2,
			sub, 3.0, 1.3)
	else:
		draw_circle(Vector2(sx + 6, size.y * 0.5), 1.2, sub)

	# иконка папки
	var icon_x := sx + 15.0
	Theme90.draw_folder_icon(self, Vector2(icon_x, 7),
		Theme90.ACCENT if not locked else Theme90.SHADE, expanded and not is_section)

	# имя
	var tx := icon_x + 17.0
	var name_w := maxf(20.0, size.x - tx - 56.0)
	var label := Theme90.fit(f, folder_name, 12, name_w)
	Theme90.text_vcenter(self, f, Rect2(tx, 0, name_w, size.y), label, 12, fg)

	# счётчик — спокойные цифры без «логотипного» шрифта
	if capacity > 0:
		var cnt := "%d/%d" % [count, capacity]
		var cw := f.get_string_size(cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		Theme90.text_vcenter(self, f, Rect2(size.x - cw - 8.0, 0, cw + 2, size.y),
			cnt, 10, sub)

	if locked:
		Theme90.draw_lock_icon(self, Vector2(size.x - 58, 8), Theme90.SHADE)


func _draw_section(r: Rect2, f: Font) -> void:
	if hovered:
		draw_rect(r, Color(1, 1, 1, 0.35))
	draw_rect(Rect2(2, size.y - 1, maxf(0.0, size.x - 4), 1), Theme90.HAIRLINE)
	var sx := 4.0
	if expandable:
		Theme90.draw_chevron(self, Vector2(sx + 6, size.y * 0.5), 1 if expanded else 2,
			Theme90.NAVY, 3.0, 1.3)
	Theme90.draw_drive_icon(self, Vector2(sx + 16, 6), Theme90.NAVY)
	var fg := Theme90.NAVY if selected else Theme90.INK
	Theme90.text_vcenter(self, f, Rect2(sx + 32, 0, size.x - 80, size.y),
		Theme90.fit(f, folder_name, 12, size.x - 110), 12, fg)
	if not free_text.is_empty():
		var tw := f.get_string_size(free_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		Theme90.text(self, f, Vector2(size.x - tw - 8, 6), free_text, 10, Theme90.SHADE)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var sx := 5.0 + (0.0 if is_section else depth * 12.0)
			if expandable and Rect2(sx, 5, 12, 12).has_point(event.position):
				expanded = not expanded
				expansion_toggled.emit(folder_id)
			else:
				if not is_section:
					folder_selected.emit(folder_id)
				else:
					expanded = not expanded
					expansion_toggled.emit(folder_id)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			context_menu_requested.emit(folder_id, get_global_mouse_position())
			accept_event()


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	var k: String = data.get("kind", "")
	if k != "file" and k != "packet":
		return false
	drop_active = true
	if not is_section:
		_request_hover_open()
	return true


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	drop_active = false
	hover_open = false
	_reset_hover_timer()
	if is_section or not (data is Dictionary):
		return
	if str(data.get("kind", "")) == "packet":
		packet_dropped.emit(folder_id, data)
	else:
		file_dropped.emit(folder_id, data)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		drop_active = false
		hover_open = false
		_reset_hover_timer()
	elif what == NOTIFICATION_MOUSE_EXIT:
		if drop_active or hover_open:
			drop_active = false
			hover_open = false
			_reset_hover_timer()


func set_hover(on: bool) -> void:
	hover_open = on


func _request_hover_open() -> void:
	if not is_inside_tree():
		return
	var dc := get_tree().get_first_node_in_group("drag_controller")
	if dc != null and dc.has_method("hover_folder"):
		dc.call("hover_folder", folder_id)


func _reset_hover_timer() -> void:
	if not is_inside_tree():
		return
	var dc := get_tree().get_first_node_in_group("drag_controller")
	if dc != null and dc.has_method("reset_hover"):
		dc.call("reset_hover")
