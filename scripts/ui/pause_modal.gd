class_name PauseModal
extends Control
## Модальное окно «ПАУЗА»: продолжить, настройки, выход в главное меню.
##
## Только UI и сигналы. «Настройки» и «В главное меню» не закрывают окно сами:
## интеграция решает, показать ли поверх настройки или подтверждение выхода.

signal resumed
signal settings_requested
signal menu_requested
signal closed

const W := 440.0
const H := 224.0
const TITLE_H := 20.0
const DIM := Color(0.0, 0.0, 0.0, 0.35)

var _btn_resume: Button90
var _btn_settings: Button90
var _btn_menu: Button90
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


func open() -> void:
	visible = true
	_layout()
	queue_redraw()
	if _btn_resume != null:
		_btn_resume.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _build() -> void:
	_btn_resume = _make_button(_tr("btn.continue", "Продолжить"), true)
	_btn_resume.pressed.connect(_resume)
	_btn_settings = _make_button(_tr("btn.settings", "Настройки"), false)
	_btn_settings.pressed.connect(func() -> void: settings_requested.emit())
	_btn_menu = _make_button("В главное меню", false)
	_btn_menu.danger = true
	_btn_menu.pressed.connect(func() -> void: menu_requested.emit())

	_btn_x = Button90.new()
	_btn_x.icon = Button90.Icon.X
	_btn_x.tooltip_text = "Продолжить"
	_btn_x.pressed.connect(_resume)
	add_child(_btn_x)


func _make_button(caption: String, accent: bool) -> Button90:
	var b := Button90.new()
	b.caption = caption
	b.accent = accent
	b.caption_size = Theme90.FS_BODY
	add_child(b)
	return b


func _tr(key: String, fallback: String) -> String:
	var data := get_node_or_null("/root/Data")
	if data != null and data.has_method("has_string") and data.has_string(key):
		var value := str(data.tr(key))
		if not value.is_empty() and value != key:
			return value
	return fallback


func _resume() -> void:
	resumed.emit()
	close()


func _window_rect() -> Rect2:
	var s := size
	if s.x <= 0.0 or s.y <= 0.0:
		s = Vector2(1280, 720)
	return Rect2(((s - Vector2(W, H)) * 0.5).round(), Vector2(W, H))


func _layout() -> void:
	var r := _window_rect()
	var x := r.position.x + 70.0
	var y := r.position.y + 96.0
	for b in [_btn_resume, _btn_settings, _btn_menu]:
		if b != null:
			b.position = Vector2(x, y)
			b.size = Vector2(300, 24)
		y += 32.0
	if _btn_x != null:
		_btn_x.position = r.position + Vector2(W - 22, 4)
		_btn_x.size = Vector2(16, 16)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_resume()
		get_viewport().set_input_as_handled()


# --- отрисовка -------------------------------------------------------------

func _draw() -> void:
	var full := Rect2(Vector2.ZERO, size)
	if size.x <= 0.0 or size.y <= 0.0:
		full = Rect2(0, 0, 1280, 720)
	draw_rect(full, DIM)
	_draw_frame(_window_rect())


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

	# пиктограмма паузы
	var ix := tr.position.x + 6.0
	var iy := tr.position.y + 5.0
	draw_rect(Rect2(ix, iy, 3, 10), Theme90.WHITE)
	draw_rect(Rect2(ix + 6, iy, 3, 10), Theme90.WHITE)

	var f := Theme90.ui()
	Theme90.text_vcenter(self, f, Rect2(tr.position.x + 22, tr.position.y, 140, TITLE_H),
		_tr("ui.pause_title", "Пауза").to_upper(), Theme90.FS_BODY, Theme90.WHITE)
	Theme90.text_vcenter(self, f, Rect2(tr.position.x, tr.position.y, tr.size.x - 40, TITLE_H),
		"ЧАС 3 · 03:42", Theme90.FS_MICRO, Theme90.ACCENT_LIGHT,
		-1, HORIZONTAL_ALIGNMENT_RIGHT)

	# информационная плашка
	var well := Rect2(r.position + Vector2(14, 28), Vector2(r.size.x - 28, 56))
	Theme90.draw_bevel(self, well, true, 2.0, Theme90.FACE)
	var bx := well.position.x + 14.0
	var by := well.position.y + 18.0
	draw_rect(Rect2(bx, by, 9, 20), Theme90.NAVY)
	draw_rect(Rect2(bx + 14, by, 9, 20), Theme90.NAVY)
	draw_rect(Rect2(bx, by, 9, 2), Theme90.ACCENT_LIGHT)
	draw_rect(Rect2(bx + 14, by, 9, 2), Theme90.ACCENT_LIGHT)
	Theme90.text(self, f, Vector2(well.position.x + 44, well.position.y + 10),
		"СМЕНА ПРИОСТАНОВЛЕНА", Theme90.FS_BODY, Theme90.INK)
	Theme90.text(self, f, Vector2(well.position.x + 44, well.position.y + 27),
		"Таймеры, касса и канал ждут оператора", Theme90.FS_MICRO, Theme90.DARK)

	Theme90.text_vcenter(self, f, Rect2(r.position.x + 10, r.position.y + 194, r.size.x - 20, 12),
		"ESC — ПРОДОЛЖИТЬ СМЕНУ", Theme90.FS_MICRO, Theme90.DARK,
		-1, HORIZONTAL_ALIGNMENT_CENTER)
