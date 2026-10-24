class_name FileCard
extends Control
## Плитка файла 132×84: иконка типа, имя в 2 строки, расширение, размер.
## Состояния: stored / attached / locked / malicious / failed.
## Перетаскивается как {"kind": "file", "id": ...}.

signal file_selected(id: String)
signal file_activated(id: String)
signal context_requested(id: String, global_pos: Vector2)
signal drag_started(id: String)

const CARD := Vector2(132, 84)

var id := ""
var file_name := ""
var ext := ""
var size_kb := 0
var type := "text"
var state := "stored"
var selected := false:
	set(v):
		selected = v
		queue_redraw()
var hovered := false:
	set(v):
		hovered = v
		queue_redraw()

var _press_pos := Vector2.ZERO
var _drag_ready := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = CARD
	if size == Vector2.ZERO:
		size = CARD
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	mouse_entered.connect(func() -> void: hovered = true)
	mouse_exited.connect(func() -> void: hovered = false)
	_update_tooltip()


func setup(p_id: String, p_name: String, p_ext: String, p_size: int, p_type: String,
		p_state: String) -> void:
	id = p_id
	file_name = p_name
	ext = p_ext
	size_kb = p_size
	type = p_type
	state = p_state
	_update_tooltip()
	queue_redraw()


func _update_tooltip() -> void:
	tooltip_text = "%s.%s\n%d КБ" % [file_name, ext, size_kb]


static func type_title(t: String) -> String:
	match t:
		"sound":
			return "ЗВУК"
		"photo":
			return "ФОТО"
		"video":
			return "ВИДЕО"
		_:
			return "ТЕКСТ"


static func type_color(t: String) -> Color:
	match t:
		"sound":
			return Theme90.WARN
		"photo":
			return Theme90.SUCCESS
		"video":
			return Theme90.ERROR
		_:
			return Theme90.NAVY


func state_caption() -> String:
	match state:
		"attached":
			return "В ЗАПРОСЕ"
		"locked":
			return "ЗАБЛОКИРОВАН"
		"malicious":
			return "ОПАСНО"
		"failed":
			return "ОШИБКА"
		_:
			return "В ПАПКЕ"


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var f := Theme90.ui()
	var tc := type_color(type)

	if selected:
		Theme90.draw_bevel(self, r, true, 2.0, Theme90.NAVY)
	elif hovered:
		Theme90.draw_bevel(self, r, false, 2.0, Theme90.FACE)
		draw_rect(Rect2(2, 2, size.x - 4, size.y - 4), Theme90.FACE_HI, false, 1.0)
	else:
		Theme90.draw_bevel(self, r, false, 2.0, Theme90.FACE)

	var sc := Theme90.ACCENT_LIGHT if selected else Theme90.SHADE
	var fg := Theme90.WHITE if selected else Theme90.INK
	if not selected:
		if state == "locked":
			fg = Theme90.SHADE
			sc = Theme90.SHADE
		elif state == "failed":
			fg = Theme90.DARK

	# лёгкая фактура «мёртвых» состояний — под содержимым, а не поверх
	if state == "locked":
		Theme90.draw_hatch(self, Rect2(3, 3, size.x - 6, 56), Color(1, 1, 1, 0.20), 8.0)
	elif state == "failed":
		Theme90.draw_hatch(self, Rect2(3, 3, size.x - 6, 56), Color(0.752941, 0.0, 0.0, 0.10), 8.0)
	elif state == "malicious":
		draw_rect(Rect2(2, 2, size.x - 4, 3), Theme90.ERROR)

	# иконка 24×24
	Theme90.draw_doc_icon(self, Rect2(6, 6, 24, 24), type, tc)

	# тип и состояние рядом с иконкой
	Theme90.text(self, f, Vector2(36, 6), type_title(type), 10,
		Theme90.WHITE if selected else tc, 70)
	Theme90.text(self, f, Vector2(36, 18), state_caption(), 10,
		Theme90.ACCENT_LIGHT if selected else _state_color(), 70)

	# имя в две строки
	var lines := Theme90.wrap(f, file_name, 10, 118.0, 2)
	var ly := 36.0
	for line in lines:
		Theme90.text(self, f, Vector2(6, ly), line, 10, fg, 120)
		ly += 11.0

	# разделитель и метаданные
	draw_rect(Rect2(4, 60, size.x - 8, 1), Theme90.SHADE if not selected else Theme90.NAVY_DEEP)
	draw_rect(Rect2(4, 61, size.x - 8, 1), Theme90.FACE_HI if not selected else Color(0.1, 0.1, 0.6))
	var ext_s := "%s · " % ext.to_upper()
	Theme90.text(self, f, Vector2(6, 64), ext_s, 10, sc)
	var mw := f.get_string_size(ext_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	Theme90.num_line(self, Vector2(6 + mw, 64), _spaced(size_kb), 8, sc, " КБ", 10)

	# бейдж состояния
	_draw_state_badge(Rect2(size.x - 20, 62, 14, 14), tc)

	# выделение — синяя внутренняя рамка
	if selected:
		draw_rect(Rect2(2, 2, size.x - 4, size.y - 4), Theme90.ACCENT_LIGHT, false, 1.0)


func _state_color() -> Color:
	match state:
		"malicious", "failed":
			return Theme90.ERROR
		"attached":
			return Theme90.NAVY
		"locked":
			return Theme90.SHADE
		_:
			return Theme90.SHADE


func _draw_state_badge(r: Rect2, tc: Color) -> void:
	if state == "stored":
		return
	var bg := Theme90.NAVY
	match state:
		"locked":
			bg = Theme90.DARK
		"malicious", "failed":
			bg = Theme90.ERROR
		_:
			bg = Theme90.NAVY
	draw_rect(r, bg)
	match state:
		"attached":
			Theme90.draw_arrow(self, r.grow(-2), 2, Theme90.WHITE)
		"locked":
			Theme90.draw_lock_icon(self, Vector2(r.position.x + 2, r.position.y + 2), Theme90.FACE)
		"malicious":
			draw_rect(Rect2(r.get_center().x - 0.5, r.position.y + 3, 2, 5), Theme90.WHITE)
			draw_rect(Rect2(r.get_center().x - 0.5, r.position.y + 9, 2, 2), Theme90.WHITE)
		"failed":
			Theme90.draw_x(self, r, Theme90.WHITE, 1.0)


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


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_press_pos = event.position
				_drag_ready = true
				selected = true
				file_selected.emit(id)
			else:
				_drag_ready = false
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			selected = true
			file_selected.emit(id)
			context_requested.emit(id, get_global_mouse_position())
			accept_event()
	elif event is InputEventMouseMotion and _drag_ready:
		if event.position.distance_to(_press_pos) > 6.0:
			_drag_ready = false


func _get_drag_data(_at_position: Vector2) -> Variant:
	drag_started.emit(id)
	var ghost := Theme90.DragGhost.new("%s.%s" % [file_name, ext], "%s КБ · %s" % [_spaced(size_kb), ext.to_upper()], "file", type_color(type))
	ghost.size = Vector2(168, 30)
	set_drag_preview(ghost)
	return {"kind": "file", "id": id, "name": file_name, "type": type, "ext": ext}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	return data.get("kind", "") == "file" or data.get("kind", "") == "packet"


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var p := get_parent()
	while p != null:
		if p.has_method("accept_dropped_file"):
			p.call("accept_dropped_file", data)
			return
		p = p.get_parent()
