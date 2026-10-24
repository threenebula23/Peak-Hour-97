class_name SlotCell
extends Control
## Ячейка TCP-канала 236×44: стрелка, файл, мини-прогресс, ×.
## Пустая — пунктир; заблокированная — замок и цена.

signal close_pressed(id: String)
signal cell_pressed(id: String)
signal packet_dropped(cell_id: String, payload: Dictionary)

const CELL := Vector2(236, 44)

var id := ""
var file_name := ""
var direction := "down"   # down — приём, up — отправка
var progress := 0.0
var state := "empty"      # empty / active / locked
var sub_text := ""
var slot_label := ""

var hovered := false:
	set(v):
		hovered = v
		queue_redraw()
var drop_active := false:
	set(v):
		if drop_active != v:
			drop_active = v
			queue_redraw()

var _x: Button90


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = CELL
	if size == Vector2.ZERO:
		size = CELL
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	mouse_entered.connect(func() -> void: hovered = true)
	mouse_exited.connect(func() -> void: hovered = false)
	_x = Button90.new()
	_x.name = "CloseButton"
	_x.icon = Button90.Icon.X
	_x.size = Vector2(14, 14)
	_x.position = Vector2(216, 4)
	_x.tooltip_text = "Прервать передачу"
	add_child(_x)
	_x.pressed.connect(func() -> void: close_pressed.emit(id))


func setup(p_id: String, p_name: String, p_dir: String, p_progress: float, p_state: String,
		p_sub: String = "", p_label: String = "") -> void:
	id = p_id
	file_name = p_name
	direction = p_dir
	progress = p_progress
	state = p_state
	sub_text = p_sub
	slot_label = p_label
	_x.visible = p_state == "active"
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var f := Theme90.ui()
	match state:
		"active":
			Theme90.draw_bevel(self, r, false, 2.0, Theme90.FACE_HI if hovered else Theme90.FACE)
		"locked":
			Theme90.draw_bevel(self, r, true, 2.0, Theme90.FACE)
			Theme90.draw_hatch(self, Rect2(2, 2, size.x - 4, size.y - 4), Color(1, 1, 1, 0.16), 8.0)
		_:
			Theme90.draw_bevel(self, r, true, 2.0, Theme90.FACE)
			Theme90.draw_dashed_box(self, Rect2(3, 3, size.x - 6, size.y - 6), Theme90.SHADE, 3.0, 1.0)

	if state == "active":
		var ab := Rect2(6, 12, 20, 20)
		Theme90.draw_bevel(self, ab, true, 1.0, Theme90.WHITE)
		Theme90.draw_arrow(self, ab, 1 if direction == "down" else 0,
			Theme90.SUCCESS if direction == "down" else Theme90.NAVY)
		Theme90.text(self, f, Vector2(32, 4), Theme90.fit(f, file_name, 12, 150), 12, Theme90.INK, 150)
		var word := "ПРИЁМ " if direction == "down" else "ПЕРЕДАЧА "
		Theme90.text(self, f, Vector2(32, 20), word, 10, Theme90.DARK)
		var ww := f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		Theme90.num_line(self, Vector2(32 + ww, 20), str(int(progress * 100.0)), 8,
			Theme90.DARK, "%", 8)
		var bar := Rect2(32, 33, 150, 5)
		draw_rect(bar, Theme90.FACE_LO)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x, 1)), Theme90.SHADE)
		draw_rect(Rect2(bar.position.x, bar.position.y, floorf(bar.size.x * progress), bar.size.y),
			Theme90.SUCCESS if direction == "down" else Theme90.ACCENT)
		return

	if state == "locked":
		Theme90.draw_lock_icon(self, Vector2(10, 15), Theme90.DARK)
		Theme90.text(self, f, Vector2(30, 4), "СЛОТ %s" % slot_label, 12, Theme90.DARK, 90)
		Theme90.text(self, f, Vector2(30, 20), sub_text if not sub_text.is_empty() else "КУПИТЬ В МАГАЗИНЕ", 10,
			Theme90.SHADE, 180)
		return

	# пустой слот
	Theme90.text(self, f, Vector2(30, 6), sub_text if not sub_text.is_empty() else "СВОБОДЕН", 12,
		Theme90.DARK, 180)
	Theme90.text(self, f, Vector2(30, 22), "ПЕРЕТАЩИТЕ ПАКЕТ СЮДА", 10,
		Theme90.NAVY if drop_active else Theme90.SHADE, 190)
	var plus := Rect2(10, 14, 16, 16)
	draw_rect(plus, Theme90.FACE)
	draw_rect(Rect2(plus.get_center().x, plus.position.y + 3, 1, 10), Theme90.SHADE)
	draw_rect(Rect2(plus.position.x + 3, plus.get_center().y, 10, 1), Theme90.SHADE)
	if drop_active:
		Theme90.draw_dashed_box(self, Rect2(3, 3, size.x - 6, size.y - 6), Theme90.NAVY, 3.0, 2.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		cell_pressed.emit(id)
		accept_event()


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	var ok: bool = data.get("kind", "") == "packet" and state == "empty"
	drop_active = ok
	return ok


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	drop_active = false
	packet_dropped.emit(id, data)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		drop_active = false
