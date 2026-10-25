class_name RenameModal
extends Control
## Модальное окно «ПЕРЕИМЕНОВАТЬ ПАПКУ» в стиле shareware 90-х.
##
##   rename_modal.open("ПРИЁМ")
##   rename_modal.renamed.connect(_on_rename_confirmed)
##
## Окно только собирает строку: проверка пустоты/длины/дублей — на вызывающей
## стороне. Enter в поле = «ОК», Esc = «Отмена».

## В Godot 4 у Control уже есть нативный сигнал `renamed`, поэтому свой
## называем `rename_confirmed` (иначе Parse Error: member redefined).
signal rename_confirmed(new_name: String)
signal closed

const W := 400.0
const H := 152.0
const TITLE_H := 20.0
const DIM := Color(0.0, 0.0, 0.0, 0.35)
const MAX_NAME := 16

var edit: LineEdit
var _btn_ok: Button90
var _btn_cancel: Button90
var _btn_x: Button90


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	resized.connect(_layout)
	_layout()
	visible = false


# --- публичное -------------------------------------------------------------

func open(current_name: String) -> void:
	if edit == null:
		return
	edit.max_length = MAX_NAME
	edit.text = current_name.left(MAX_NAME)
	visible = true
	queue_redraw()
	edit.grab_focus()
	edit.select_all()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func get_text() -> String:
	return edit.text if edit != null else ""


# --- сборка ----------------------------------------------------------------

func _build() -> void:
	edit = LineEdit.new()
	edit.name = "FolderName"
	edit.placeholder_text = "имя папки…"
	edit.max_length = MAX_NAME
	edit.add_theme_font_override("font", Theme90.ui())
	edit.add_theme_font_size_override("font_size", Theme90.FS_BODY)
	edit.add_theme_color_override("font_color", Theme90.INK)
	edit.add_theme_color_override("font_placeholder_color", Theme90.SHADE)
	edit.add_theme_color_override("caret_color", Theme90.INK)
	var box := Theme90.sunken_box()
	box.set_content_margin_all(1)
	box.content_margin_left = 4
	box.content_margin_right = 4
	edit.add_theme_stylebox_override("normal", box)
	edit.add_theme_stylebox_override("focus", box)
	edit.text_submitted.connect(func(_text: String) -> void: _submit())
	add_child(edit)

	_btn_ok = Button90.new()
	_btn_ok.caption = "ОК"
	_btn_ok.accent = true
	_btn_ok.pressed.connect(_submit)
	add_child(_btn_ok)

	_btn_cancel = Button90.new()
	_btn_cancel.caption = "Отмена"
	_btn_cancel.pressed.connect(close)
	add_child(_btn_cancel)

	_btn_x = Button90.new()
	_btn_x.icon = Button90.Icon.X
	_btn_x.tooltip_text = "Отмена"
	_btn_x.pressed.connect(close)
	add_child(_btn_x)


func _window_rect() -> Rect2:
	var s := size
	if s.x <= 0.0 or s.y <= 0.0:
		s = Vector2(1280, 720)
	return Rect2(((s - Vector2(W, H)) * 0.5).round(), Vector2(W, H))


func _layout() -> void:
	var r := _window_rect()
	if edit != null:
		edit.position = r.position + Vector2(18, 52)
		edit.size = Vector2(W - 36, 22)
	if _btn_cancel != null:
		_btn_cancel.position = r.position + Vector2(178, 118)
		_btn_cancel.size = Vector2(100, 24)
	if _btn_ok != null:
		_btn_ok.position = r.position + Vector2(286, 118)
		_btn_ok.size = Vector2(96, 24)
	if _btn_x != null:
		_btn_x.position = r.position + Vector2(W - 22, 4)
		_btn_x.size = Vector2(16, 16)


func _submit() -> void:
	if not visible:
		return
	var value := get_text()
	visible = false
	rename_confirmed.emit(value)


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
	_draw_frame(_window_rect())


func _draw_frame(r: Rect2) -> void:
	Theme90.draw_bevel(self, r, false, Theme90.BEVEL, Theme90.WHITE)
	Theme90.modal_header(self, r, "ПЕРЕИМЕНОВАТЬ ПАПКУ", "ПАПКА · 16 СИМВОЛОВ")

	# подпись поля
	var f := Theme90.ui()
	Theme90.text(self, f, Vector2(r.position.x + 18, r.position.y + 34),
		"ИМЯ ПАПКИ:", Theme90.FS_BODY, Theme90.INK)
	Theme90.text_vcenter(self, f, Rect2(r.position.x + 18, r.position.y + 80, W - 36, 14),
		"ENTER — ОК · ESC — ОТМЕНА", Theme90.FS_MICRO, Theme90.SHADE)

	# разделитель над кнопками
	var ly := r.position.y + 104
	draw_rect(Rect2(r.position.x + 10, ly, r.size.x - 20, 1), Theme90.SHADE)
	draw_rect(Rect2(r.position.x + 10, ly + 1, r.size.x - 20, 1), Theme90.FACE_HI)
