class_name SettingsModal
extends Control
## Модальное окно «НАСТРОЙКИ»: громкость звуков и музыки, спокойный фон,
## полный экран. Ползунки и галочки — собственные, в стиле 90-х.
##
## Только UI: изменения отдаются наружу сигналом settings_changed(dict)
## с ключами sfx (0..100), music (0..100), calm_bg (bool), fullscreen (bool).

signal settings_changed(values: Dictionary)
signal closed

const W := 540.0
const H := 320.0
const TITLE_H := 20.0
const DIM := Color(0.0, 0.0, 0.0, 0.35)

const DEFAULT_STATE := {"sfx": 70, "music": 55, "calm_bg": true, "fullscreen": false}


## Ползунок 90-х: утопленный жёлоб с насечками и объёмный бегунок 9×14.
class Slider90:
	extends Control

	signal changed(value: int)

	var value := 70

	var _dragging := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		custom_minimum_size = Vector2(120, 14)

	func set_value(v: int, notify: bool = true) -> void:
		var nv := clampi(int(roundf(float(v) / 5.0)) * 5, 0, 100)
		var did_change := nv != value
		value = nv
		queue_redraw()
		if notify and did_change:
			changed.emit(value)

	func _track() -> Rect2:
		return Rect2(0, 3, size.x, 8)

	func _grabber() -> Rect2:
		var travel := maxf(0.0, size.x - 9.0)
		return Rect2(roundf(travel * float(value) / 100.0), 0, 9, 14)

	func _draw() -> void:
		var track := _track()
		draw_rect(track, Theme90.FACE_LO)
		Theme90.draw_bevel(self, track, true, 1.0, Theme90.FACE_LO)
		for i in 11:
			var tx := roundf(track.position.x + travel_hint(i))
			draw_rect(Rect2(tx, track.position.y + 2, 1, 4), Theme90.SHADE)
		var g := _grabber()
		Theme90.draw_bevel(self, g, false, 2.0, Theme90.FACE)
		var gy := roundf(g.position.y + g.size.y * 0.5)
		for i in 3:
			draw_rect(Rect2(g.position.x + 3, gy - 3 + i * 2, 3, 1), Theme90.SHADE)

	func travel_hint(i: int) -> float:
		return roundf((size.x - 1.0) * float(i) / 10.0)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_set_from_x(event.position.x)
				accept_event()
			elif _dragging:
				_dragging = false
				accept_event()
		elif event is InputEventMouseMotion and _dragging:
			_set_from_x(event.position.x)
			accept_event()
		elif event is InputEventKey and event.pressed:
			if event.keycode == KEY_LEFT or event.keycode == KEY_DOWN:
				set_value(value - 5)
				accept_event()
			elif event.keycode == KEY_RIGHT or event.keycode == KEY_UP:
				set_value(value + 5)
				accept_event()
			elif event.keycode == KEY_HOME:
				set_value(0)
				accept_event()
			elif event.keycode == KEY_END:
				set_value(100)
				accept_event()

	func _set_from_x(x: float) -> void:
		var travel := maxf(1.0, size.x - 9.0)
		var t := clampf((x - 4.5) / travel, 0.0, 1.0)
		set_value(int(roundf(t * 100.0)))


var _state: Dictionary = DEFAULT_STATE.duplicate(true)
var _silent := false

var _sfx: Slider90
var _music: Slider90
var _calm: Check90
var _full: Check90
var _btn_back: Button90
var _btn_reset: Button90
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

func open(state: Dictionary = {}) -> void:
	_apply_state(state)
	visible = true
	queue_redraw()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func get_state() -> Dictionary:
	return _state.duplicate(true)


func _apply_state(state: Dictionary) -> void:
	_silent = true
	var src := DEFAULT_STATE.duplicate(true)
	for key in state.keys():
		src[key] = state[key]
	_state["sfx"] = clampi(int(src.get("sfx", 70)), 0, 100)
	_state["music"] = clampi(int(src.get("music", 55)), 0, 100)
	_state["calm_bg"] = bool(src.get("calm_bg", true))
	_state["fullscreen"] = bool(src.get("fullscreen", false))
	if _sfx != null:
		_sfx.set_value(int(_state["sfx"]), false)
	if _music != null:
		_music.set_value(int(_state["music"]), false)
	_set_check(_calm, bool(_state["calm_bg"]))
	_set_check(_full, bool(_state["fullscreen"]))
	_silent = false
	queue_redraw()


func _tr(key: String, fallback: String) -> String:
	var data := get_node_or_null("/root/Data")
	if data != null and data.has_method("has_string") and data.has_string(key):
		var value := str(data.tr(key))
		if not value.is_empty() and value != key:
			return value
	return fallback


func _set_check(cb: Check90, on: bool) -> void:
	if cb == null:
		return
	if cb.button_pressed != on:
		cb.button_pressed = on
	cb.checked = on
	cb.queue_redraw()


# --- сборка ----------------------------------------------------------------

func _build() -> void:
	_sfx = Slider90.new()
	_sfx.value = 70
	add_child(_sfx)
	_sfx.set_value(70, false)
	_sfx.changed.connect(_on_sfx)

	_music = Slider90.new()
	_music.value = 55
	add_child(_music)
	_music.set_value(55, false)
	_music.changed.connect(_on_music)

	_calm = Check90.new()
	_calm.caption = _tr("ui.calm_background", "Спокойный фон")
	_calm.caption_size = Theme90.FS_BODY
	add_child(_calm)
	_calm.button_pressed = true
	_calm.checked = true
	_calm.toggled.connect(_on_calm)

	_full = Check90.new()
	_full.caption = _tr("ui.fullscreen", "Полный экран")
	_full.caption_size = Theme90.FS_BODY
	add_child(_full)
	_full.toggled.connect(_on_full)

	_btn_reset = Button90.new()
	_btn_reset.caption = "Сброс"
	add_child(_btn_reset)
	_btn_reset.pressed.connect(_on_reset)

	_btn_back = Button90.new()
	_btn_back.caption = "Назад"
	add_child(_btn_back)
	_btn_back.pressed.connect(close)

	_btn_x = Button90.new()
	_btn_x.icon = Button90.Icon.X
	_btn_x.tooltip_text = "Закрыть"
	_btn_x.pressed.connect(close)
	add_child(_btn_x)


func _window_rect() -> Rect2:
	var s := size
	if s.x <= 0.0 or s.y <= 0.0:
		s = Vector2(1280, 720)
	return Rect2(((s - Vector2(W, H)) * 0.5).round(), Vector2(W, H))


func _layout() -> void:
	var r := _window_rect()
	if _sfx != null:
		_sfx.position = r.position + Vector2(120, 57)
		_sfx.size = Vector2(330, 14)
	if _music != null:
		_music.position = r.position + Vector2(120, 89)
		_music.size = Vector2(330, 14)
	if _calm != null:
		_calm.position = r.position + Vector2(28, 174)
		_calm.size = Vector2(400, 16)
	if _full != null:
		_full.position = r.position + Vector2(28, 202)
		_full.size = Vector2(400, 16)
	if _btn_reset != null:
		_btn_reset.position = r.position + Vector2(270, 278)
		_btn_reset.size = Vector2(116, 24)
	if _btn_back != null:
		_btn_back.position = r.position + Vector2(396, 278)
		_btn_back.size = Vector2(130, 24)
	if _btn_x != null:
		_btn_x.position = r.position + Vector2(W - 22, 4)
		_btn_x.size = Vector2(16, 16)


# --- события ---------------------------------------------------------------

func _on_sfx(v: int) -> void:
	_state["sfx"] = v
	_emit()

func _on_music(v: int) -> void:
	_state["music"] = v
	_emit()

func _on_calm(on: bool) -> void:
	_state["calm_bg"] = on
	_emit()

func _on_full(on: bool) -> void:
	_state["fullscreen"] = on
	_emit()

func _on_reset() -> void:
	_apply_state(DEFAULT_STATE)
	if not _silent:
		settings_changed.emit(get_state())


func _emit() -> void:
	if _silent:
		return
	settings_changed.emit(get_state())
	queue_redraw()


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
	_draw_group(Rect2(r.position + Vector2(14, 28), Vector2(r.size.x - 28, 108)), "ЗВУК")
	_draw_group(Rect2(r.position + Vector2(14, 144), Vector2(r.size.x - 28, 96)), "ЭКРАН")
	_draw_labels(r)


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

	# три ползунка — пиктограмма окна
	for i in 3:
		var ly := tr.position.y + 5.0 + i * 3.0
		draw_rect(Rect2(tr.position.x + 5, ly, 10, 1), Theme90.WHITE)
		draw_rect(Rect2(tr.position.x + 7 + i * 2, ly - 1, 2, 3), Theme90.ACCENT_LIGHT)

	var f := Theme90.ui()
	Theme90.text_vcenter(self, f, Rect2(tr.position.x + 22, tr.position.y, 200, TITLE_H),
		_tr("ui.settings_title", "Настройки").to_upper(), Theme90.FS_BODY, Theme90.WHITE)
	Theme90.text_vcenter(self, f, Rect2(tr.position.x, tr.position.y, tr.size.x - 40, TITLE_H),
		"УЗЕЛ 7 · ПРОФИЛЬ ОПЕРАТОРА", Theme90.FS_MICRO, Theme90.ACCENT_LIGHT,
		-1, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_group(r: Rect2, title: String) -> void:
	Theme90.draw_bevel(self, r, true, Theme90.BEVEL, Theme90.FACE)
	var inner := r.grow(-Theme90.BEVEL)
	var f := Theme90.ui()
	Theme90.text(self, f, Vector2(inner.position.x + 8, inner.position.y + 5),
		title, Theme90.FS_MICRO, Theme90.NAVY)
	var ly := inner.position.y + 22
	draw_rect(Rect2(inner.position.x + 4, ly, inner.size.x - 8, 1), Theme90.SHADE)
	draw_rect(Rect2(inner.position.x + 4, ly + 1, inner.size.x - 8, 1), Theme90.LIGHT)


func _draw_labels(r: Rect2) -> void:
	var f := Theme90.ui()

	# звук
	_draw_speaker(Rect2(r.position + Vector2(28, 58), Vector2(12, 12)))
	_draw_note(Rect2(r.position + Vector2(28, 90), Vector2(12, 12)))
	Theme90.text(self, f, Vector2(r.position.x + 46, r.position.y + 57),
		_tr("ui.volume_sfx", "Звуки"), Theme90.FS_BODY, Theme90.INK)
	Theme90.text(self, f, Vector2(r.position.x + 46, r.position.y + 89),
		_tr("ui.volume_music", "Музыка"), Theme90.FS_BODY, Theme90.INK)
	Theme90.text_vcenter(self, Theme90.logo(), Rect2(r.position.x + 436, r.position.y + 56, 58, 14),
		str(int(_state["sfx"])), 10, Theme90.INK, -1, HORIZONTAL_ALIGNMENT_RIGHT)
	Theme90.text_vcenter(self, Theme90.logo(), Rect2(r.position.x + 436, r.position.y + 88, 58, 14),
		str(int(_state["music"])), 10, Theme90.INK, -1, HORIZONTAL_ALIGNMENT_RIGHT)
	Theme90.text_vcenter(self, f, Rect2(r.position.x + 496, r.position.y + 56, 14, 14),
		"%", Theme90.FS_MICRO, Theme90.DARK)
	Theme90.text_vcenter(self, f, Rect2(r.position.x + 496, r.position.y + 88, 14, 14),
		"%", Theme90.FS_MICRO, Theme90.DARK)

	# подсказки
	Theme90.text(self, f, Vector2(r.position.x + 16, r.position.y + 254),
		"ESC — ЗАКРЫТЬ · ЗВУК И ЭКРАН", Theme90.FS_MICRO, Theme90.DARK)


func _draw_speaker(r: Rect2) -> void:
	var x := r.position.x
	var y := r.position.y
	draw_rect(Rect2(x + 1, y + 4, 3, 5), Theme90.NAVY)
	draw_colored_polygon(PackedVector2Array([
		Vector2(x + 4, y + 4), Vector2(x + 7, y + 1), Vector2(x + 7, y + 11), Vector2(x + 4, y + 8)]),
		Theme90.NAVY)
	draw_rect(Rect2(x + 9, y + 4, 1, 5), Theme90.NAVY)
	draw_rect(Rect2(x + 11, y + 3, 1, 7), Theme90.NAVY)


func _draw_note(r: Rect2) -> void:
	var x := r.position.x
	var y := r.position.y
	draw_rect(Rect2(x + 3, y + 2, 1, 8), Theme90.NAVY)
	draw_rect(Rect2(x + 4, y + 2, 4, 1), Theme90.NAVY)
	draw_rect(Rect2(x + 7, y + 2, 1, 4), Theme90.NAVY)
	draw_rect(Rect2(x + 1, y + 8, 4, 3), Theme90.NAVY)
