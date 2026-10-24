class_name FolderRow
extends Control
## Строка дерева 24 px: квадрат +/−, папка, имя, счётчик «3/16».
## Секции C:/D:/E: — отдельный вид (sunken-полоса с гравировкой).
## Принимает drag&drop {kind:"file"} и {kind:"packet"}.

signal folder_selected(folder_id: String)
signal expansion_toggled(folder_id: String)
signal file_dropped(folder_id: String, payload: Dictionary)
signal context_menu_requested(folder_id: String, global_pos: Vector2)

const ROW_H := 24.0
const SECTION_H := 22.0

var folder_id := ""
var folder_name := ""
var count := 0
var capacity := 16
var free_text := ""
var depth := 0
var is_section := false
var expandable := true
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
		draw_rect(r, Theme90.NAVY)
	elif drop_active:
		draw_rect(r, Theme90.ACCENT_PALE)
	elif hovered:
		draw_rect(r, Color(0.941176, 0.956863, 1.0))

	var fg := Theme90.WHITE if selected else Theme90.INK
	var sub := Theme90.ACCENT_LIGHT if selected else Theme90.SHADE
	var sx := 5.0 + depth * 12.0

	# квадрат +/−
	if expandable:
		var sq := Rect2(sx, 5, 12, 12)
		Theme90.draw_bevel(self, sq, false, 1.0, Theme90.FACE)
		var gc := Theme90.INK if not selected else Theme90.INK
		draw_rect(Rect2(sq.position.x + 3, sq.position.y + 5, 6, 1), gc)
		if not expanded:
			draw_rect(Rect2(sq.position.x + 5, sq.position.y + 3, 1, 6), gc)
	else:
		draw_rect(Rect2(sx + 3, 11, 6, 1), sub)

	# иконка папки
	var icon_x := sx + 16.0
	Theme90.draw_folder_icon(self, Vector2(icon_x, 6), Theme90.WARN if not locked else Theme90.SHADE,
		expanded and not is_section)

	# имя
	var tx := icon_x + 17.0
	var name_w := size.x - tx - 50.0
	var label := Theme90.fit(f, folder_name, 12, name_w)
	Theme90.text_vcenter(self, f, Rect2(tx, 0, name_w, size.y), label, 12, fg)

	# счётчик
	if capacity > 0:
		var cnt := "%d/%d" % [count, capacity]
		Theme90.num_right(self, size.x - 6.0, 5.0, cnt, 8, sub)

	if locked:
		Theme90.draw_lock_icon(self, Vector2(size.x - 62, 7), Theme90.SHADE)

	# подсветка drop
	if drop_active:
		draw_rect(Rect2(1, 1, size.x - 2, size.y - 2), Theme90.NAVY, false, 1.0)
		draw_rect(Rect2(2, 2, size.x - 4, size.y - 4), Theme90.ACCENT_PALE, false, 1.0)


func _draw_section(r: Rect2, f: Font) -> void:
	Theme90.draw_bevel(self, r, false, 1.0, Theme90.FACE)
	draw_rect(Rect2(1, 1, size.x - 2, 1), Theme90.FACE_HI)
	var sx := 4.0
	if expandable:
		var sq := Rect2(sx, 5, 12, 12)
		Theme90.draw_bevel(self, sq, false, 1.0, Theme90.FACE)
		draw_rect(Rect2(sq.position.x + 3, sq.position.y + 5, 6, 1), Theme90.INK)
		if not expanded:
			draw_rect(Rect2(sq.position.x + 5, sq.position.y + 3, 1, 6), Theme90.INK)
	Theme90.draw_drive_icon(self, Vector2(sx + 16, 6), Theme90.NAVY)
	Theme90.text_engraved(self, f, Vector2(sx + 32, 4), folder_name, 10)
	if not free_text.is_empty():
		var w := f.get_string_size(free_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		Theme90.text_engraved(self, f, Vector2(size.x - w - 6, 4), free_text, 10)


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
	return true


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	drop_active = false
	if is_section:
		return
	file_dropped.emit(folder_id, data)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		drop_active = false
