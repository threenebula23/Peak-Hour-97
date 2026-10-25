class_name FileCard
extends Control
## Плитка файла 132×84: цветная иконка типа, имя в 2 строки, размер.
## Светлая карточка с 1 px контуром и мягкой тенью; attached — зелёная
## галочка, locked/malicious — маленькие значки. Перетаскивается как
## {"kind": "file", "id": ...}.

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
			return Theme90.ACCENT


## Цвет иконки: по расширению, если оно известно, иначе — по типу файла.
static func icon_color(t: String, e: String) -> Color:
	var cat := Theme90.ext_category(e)
	if not cat.is_empty():
		return Theme90.ext_color(cat)
	return type_color(t)


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
	var tc := icon_color(type, ext)
	var locked := state == "locked"
	var bad := state == "malicious" or state == "failed"

	var bg := Theme90.PAPER_HI
	var border := Theme90.BORDER
	var shadow := Theme90.SHADOW
	if selected:
		bg = Theme90.ACCENT_PALE
		border = Color(Theme90.ACCENT.r, Theme90.ACCENT.g, Theme90.ACCENT.b, 0.8)
		shadow = Color(0, 0, 0, 0.12)
	elif hovered:
		bg = Theme90.WHITE
		border = Theme90.ACCENT_LIGHT
		shadow = Color(0, 0, 0, 0.11)

	draw_style_box(Theme90.box(bg, border, 4, 1, shadow), r)
	if selected:
		draw_rect(Rect2(1.5, 12, 2.5, size.y - 24), Theme90.ACCENT)

	if locked:
		tc = Theme90.SHADE
	Theme90.draw_doc_icon(self, Rect2(10, 10, 24, 24), type, tc, ext)

	# состояние — только маленькими значками, без подписей
	if state == "attached":
		Theme90.draw_check_badge(self, Vector2(size.x - 14, 14), 7.0)
	elif locked:
		draw_circle(Vector2(size.x - 14, 14), 7.0, Color(Theme90.SHADE.r, Theme90.SHADE.g,
			Theme90.SHADE.b, 0.16))
		Theme90.draw_lock_icon(self, Vector2(size.x - 18, 9), Theme90.SHADE)
	elif state == "malicious":
		draw_circle(Vector2(size.x - 14, 14), 7.0, Color(Theme90.ERROR.r, Theme90.ERROR.g,
			Theme90.ERROR.b, 0.16))
		draw_rect(Rect2(size.x - 14.5, 10, 1.6, 5), Theme90.ERROR)
		draw_circle(Vector2(size.x - 13.7, 17.5), 1.0, Theme90.ERROR)
	elif state == "failed":
		draw_circle(Vector2(size.x - 14, 14), 7.0, Color(Theme90.ERROR.r, Theme90.ERROR.g,
			Theme90.ERROR.b, 0.16))
		Theme90.draw_x(self, Rect2(size.x - 21, 7, 14, 14), Theme90.ERROR, 1.3)

	var name_color := Theme90.SHADE if locked else Theme90.INK
	var lines := Theme90.wrap(f, file_name, 12, size.x - 20.0, 2)
	var ly := 40.0
	for line in lines:
		Theme90.text(self, f, Vector2(10, ly), line, 12, name_color, size.x - 20.0)
		ly += 13.0

	# тип и размер — одна спокойная строка
	var meta_col := Theme90.SHADE
	if state == "malicious" or state == "failed":
		meta_col = Theme90.ERROR
	var ext_s := ext.to_upper()
	Theme90.text(self, f, Vector2(10, 68), ext_s, 10, meta_col)
	var ew := f.get_string_size(ext_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	Theme90.text(self, f, Vector2(10 + ew + 5, 68), _spaced(size_kb) + " КБ", 10,
		meta_col)

	if hovered and not selected:
		draw_rect(Rect2(10, 34, size.x - 20, 1), Theme90.HAIRLINE)


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
	var ghost := Theme90.DragGhost.new("%s.%s" % [file_name, ext], "%s КБ · %s" % [_spaced(size_kb), ext.to_upper()], "file", icon_color(type, ext), "text", ext)
	ghost.size = Vector2(172, 32)
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
