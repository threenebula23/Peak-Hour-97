class_name SettingsModal
extends Control
## Модальное окно «НАСТРОЙКИ»: громкость звуков и музыки, спокойный фон,
## полный экран. Ползунки и галочки — собственные, в стиле 90-х.
##
## Окно работает с черновиком: ползунки и галочки меняют только внутреннее
## состояние. Наружу настройки уходят одним сигналом settings_changed(dict)
## по кнопке «Подтвердить»; «Отмена», Esc и X закрывают окно без применения.
## Ключи: sfx (0..100), music (0..100), calm_bg (bool), fullscreen (bool),
## vhs (bool).

signal settings_changed(values: Dictionary)
signal closed

const W := 540.0
const H := 320.0
const TITLE_H := 20.0
const DIM := Color(0.0, 0.0, 0.0, 0.35)

const DEFAULT_STATE := {"sfx": 70, "music": 55, "calm_bg": true, "fullscreen": false,
	"vhs": true}


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
		var track := Rect2(0, 6, size.x, 4)
		Theme90.draw_meter(self, track, float(value) / 100.0, Theme90.ACCENT,
			Theme90.PAPER_LO)
		var g := _grabber()
		draw_style_box(Theme90.box(Theme90.WHITE, Theme90.ACCENT_LIGHT, 3, 1,
			Theme90.SHADOW), g)
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

var _sfx: Slider90
var _music: Slider90
var _calm: Check90
var _full: Check90
var _vhs: Check90
var _btn_cancel: Button90
var _btn_apply: Button90
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


## Обновить черновик извне (например, если браузер отклонил fullscreen).
func set_state(state: Dictionary) -> void:
	_apply_state(state)


func set_fullscreen(on: bool) -> void:
	_state["fullscreen"] = bool(on)
	_set_check(_full, bool(on))
	queue_redraw()


func _apply_state(state: Dictionary) -> void:
	var src := DEFAULT_STATE.duplicate(true)
	for key in state.keys():
		src[key] = state[key]
	_state["sfx"] = clampi(int(src.get("sfx", 70)), 0, 100)
	_state["music"] = clampi(int(src.get("music", 55)), 0, 100)
	_state["calm_bg"] = bool(src.get("calm_bg", true))
	_state["fullscreen"] = bool(src.get("fullscreen", false))
	_state["vhs"] = bool(src.get("vhs", true))
	if _sfx != null:
		_sfx.set_value(int(_state["sfx"]), false)
	if _music != null:
		_music.set_value(int(_state["music"]), false)
	_set_check(_calm, bool(_state["calm_bg"]))
	_set_check(_full, bool(_state["fullscreen"]))
	_set_check(_vhs, bool(_state["vhs"]))
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

	_vhs = Check90.new()
	_vhs.caption = _tr("ui.vhs_effect", "VHS-эффект")
	_vhs.caption_size = Theme90.FS_BODY
	add_child(_vhs)
	_vhs.button_pressed = true
	_vhs.checked = true
	_vhs.toggled.connect(_on_vhs)

	_btn_reset = Button90.new()
	_btn_reset.caption = "Сброс"
	add_child(_btn_reset)
	_btn_reset.pressed.connect(_on_reset)

	_btn_cancel = Button90.new()
	_btn_cancel.caption = "Отмена"
	add_child(_btn_cancel)
	_btn_cancel.pressed.connect(close)

	_btn_apply = Button90.new()
	_btn_apply.caption = "Подтвердить"
	_btn_apply.accent = true
	add_child(_btn_apply)
	_btn_apply.pressed.connect(_confirm)

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
	if _sfx != null:
		_sfx.position = r.position + Vector2(120, 57)
		_sfx.size = Vector2(330, 14)
	if _music != null:
		_music.position = r.position + Vector2(120, 89)
		_music.size = Vector2(330, 14)
	if _calm != null:
		_calm.position = r.position + Vector2(28, 172)
		_calm.size = Vector2(400, 16)
	if _full != null:
		_full.position = r.position + Vector2(28, 198)
		_full.size = Vector2(400, 16)
	if _vhs != null:
		_vhs.position = r.position + Vector2(28, 224)
		_vhs.size = Vector2(400, 16)
	if _btn_reset != null:
		_btn_reset.position = r.position + Vector2(264, 278)
		_btn_reset.size = Vector2(70, 24)
	if _btn_cancel != null:
		_btn_cancel.position = r.position + Vector2(342, 278)
		_btn_cancel.size = Vector2(80, 24)
	if _btn_apply != null:
		_btn_apply.position = r.position + Vector2(430, 278)
		_btn_apply.size = Vector2(96, 24)
	if _btn_x != null:
		_btn_x.position = r.position + Vector2(W - 26, 4)
		_btn_x.size = Vector2(16, 16)


# --- события ---------------------------------------------------------------

func _on_sfx(v: int) -> void:
	_state["sfx"] = v
	queue_redraw()

func _on_music(v: int) -> void:
	_state["music"] = v
	queue_redraw()

func _on_calm(on: bool) -> void:
	_state["calm_bg"] = on
	queue_redraw()

func _on_full(on: bool) -> void:
	_state["fullscreen"] = on
	queue_redraw()


func _on_vhs(on: bool) -> void:
	_state["vhs"] = on
	queue_redraw()

func _on_reset() -> void:
	_apply_state(DEFAULT_STATE)


## «Подтвердить» — единственная точка применения draft-настроек.
func _confirm() -> void:
	if not visible:
		return
	settings_changed.emit(get_state())
	close()


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
	_draw_group(Rect2(r.position + Vector2(14, 144), Vector2(r.size.x - 28, 104)), "ЭКРАН")
	_draw_labels(r)


func _draw_frame(r: Rect2) -> void:
	Theme90.draw_bevel(self, r, false, Theme90.BEVEL, Theme90.WHITE)
	Theme90.modal_header(self, r, _tr("ui.settings_title", "Настройки").to_upper(),
		"УЗЕЛ 7 · ПРОФИЛЬ ОПЕРАТОРА")


func _draw_group(r: Rect2, title: String) -> void:
	Theme90.draw_sunken(self, r)
	var inner := r.grow(-Theme90.BEVEL)
	var f := Theme90.ui()
	draw_circle(Vector2(inner.position.x + 8, inner.position.y + 10), 2.0, Theme90.ACCENT)
	Theme90.text(self, f, Vector2(inner.position.x + 15, inner.position.y + 5),
		title, Theme90.FS_MICRO, Theme90.NAVY)
	var ly := inner.position.y + 22
	draw_rect(Rect2(inner.position.x + 4, ly, inner.size.x - 8, 1), Theme90.HAIRLINE)


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
		"ESC — ОТМЕНА · ПРИМЕНЯЕТСЯ ПО «ПОДТВЕРДИТЬ»", Theme90.FS_MICRO, Theme90.DARK)


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
