class_name SlotCell
extends Control
## Ячейка TCP-канала 236×44: направление, файл, тонкий прогресс, ×.
## Пустая — пунктир; заблокированная — замок и цена в магазине.

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
	_x.position = Vector2(216, 5)
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

	if state == "active":
		var border := Theme90.ACCENT_LIGHT if hovered else Theme90.BORDER
		draw_style_box(Theme90.box(Theme90.WHITE, border, 4, 1, Theme90.SHADOW), r)
		var accent := Theme90.SUCCESS if direction == "down" else Theme90.ACCENT
		draw_style_box(Theme90.box(Color(accent.r, accent.g, accent.b, 0.12),
			Color(0, 0, 0, 0), 3, 0), Rect2(8, 11, 20, 20))
		Theme90.draw_arrow(self, Rect2(8, 11, 20, 20), 1 if direction == "down" else 0,
			accent)
		Theme90.text(self, f, Vector2(34, 4), Theme90.fit(f, file_name, 12, 166), 12,
			Theme90.INK, 166)
		var word := "ПРИЁМ" if direction == "down" else "ПЕРЕДАЧА"
		Theme90.text(self, f, Vector2(34, 20), word, 10, Theme90.SHADE)
		var ww := f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		Theme90.text(self, f, Vector2(34 + ww + 6, 20), "%d%%" % int(roundf(progress * 100.0)),
			10, accent)
		Theme90.draw_meter(self, Rect2(34, 33, 160, 4), progress, accent)
		return

	if state == "locked":
		draw_style_box(Theme90.box(Theme90.PAPER, Theme90.BORDER_SOFT, 4, 1), r)
		Theme90.draw_lock_icon(self, Vector2(11, 15), Theme90.SHADE)
		Theme90.text(self, f, Vector2(28, 4), "СЛОТ %s" % slot_label, 11, Theme90.DARK, 120)
		Theme90.text(self, f, Vector2(28, 20), sub_text if not sub_text.is_empty()
			else "КУПИТЬ В МАГАЗИНЕ", 10, Theme90.SHADE, 198)
		return

	# пустой слот
	draw_style_box(Theme90.box(Theme90.PAPER_HI, Theme90.BORDER_SOFT, 4, 1), r)
	Theme90.draw_dashed_box(self, Rect2(3, 3, size.x - 6, size.y - 6),
		Color(Theme90.SHADE.r, Theme90.SHADE.g, Theme90.SHADE.b, 0.45), 3.0, 1.0)
	draw_style_box(Theme90.box(Color(1, 1, 1, 0.7), Theme90.BORDER_SOFT, 3, 1),
		Rect2(10, 14, 16, 16))
	draw_rect(Rect2(17.5, 18, 1.2, 8), Theme90.SHADE)
	draw_rect(Rect2(14, 21.4, 8, 1.2), Theme90.SHADE)
	Theme90.text(self, f, Vector2(32, 6), sub_text if not sub_text.is_empty()
		else "СВОБОДЕН", 12, Theme90.DARK, 190)
	Theme90.text(self, f, Vector2(32, 24), "перетащите пакет", 10,
		Theme90.ACCENT if drop_active else Theme90.SHADE, 190)
	if drop_active:
		Theme90.draw_dashed_box(self, Rect2(2, 2, size.x - 4, size.y - 4),
			Theme90.ACCENT, 3.0, 1.4)


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
