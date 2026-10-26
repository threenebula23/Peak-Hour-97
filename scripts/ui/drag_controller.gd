class_name DragController
extends Node
## Центральный контроллер перетаскивания: держит одно превью (FileShape) и
## его режим (shape | square), двигает превью за мышью и отсчитывает 250 мс
## наведения на папку БЕЗ Timer-узлов.
##
## Владелец — Main. Компоненты находят его через группу "drag_controller"
## или через свойство drag_controller.
##
## ВАЖНО: при отсутствии превью контроллер не должен падать — все вызовы
## проверяют is_instance_valid.

signal hover_open(folder_id: String)
signal drag_ended
## Пользователь повернул фигуру (R / ПКМ). Слушают все сетки, чтобы ghost
## обновлялся даже у той, которая не получила событие ввода.
signal rotation_changed(rotation: int)

const HOVER_DELAY := 0.25
const PREVIEW_OFFSET := Vector2(9, 9)

## Сглаживание превью за мышью и «жизнь» drag (Lane B). Всё — только
## transform превью: позиции источника/цели и drop-логику не трогаем.
const SMOOTH_TAU := 0.035
const TILT_TAU := 0.12
## Скорость мыши (px/s), при которой наклон максимальный.
const TILT_MAX_SPEED := 1400.0
const POP_DUR := 0.10
const POP_SCALE := 1.04
const DRAG_ALPHA := 0.92
const FLINCH_DUR := 0.16
const FLINCH_PX := 3.0

var _preview: Control = null
var _mode: String = "shape"
var _rotation: int = 0
var _rotate_frame: int = -1
var _hover_id: String = ""
var _hover_left: float = 0.0
var _hover_fired: bool = false

var _pos := Vector2.ZERO
var _mouse_prev := Vector2.ZERO
var _tilt := 0.0
var _pop_t := 1.0
var _rot_pop_t := 1.0
var _flinch_left := 0.0
var _placing := false
var _motion_on := true


func _ready() -> void:
	if not is_in_group("drag_controller"):
		add_to_group("drag_controller")
	set_process(false)


func begin(preview_control: Control, p_mode: String = "shape",
		p_initial_rotation: int = 0) -> void:
	end()
	_preview = preview_control
	_mode = _normalize(p_mode)
	# Пакет создаёт превью со своим поворотом, но зовёт begin() без третьего
	# аргумента. Берём поворот из превью, чтобы drop не сбрасывал его в 0.
	var seeded := posmod(int(p_initial_rotation), 4)
	if seeded == 0 and is_instance_valid(preview_control):
		var preview_rotation = preview_control.get("shape_rotation")
		if preview_rotation != null:
			seeded = posmod(int(preview_rotation), 4)
	_rotation = seeded
	_rotate_frame = -1
	_pos = Vector2.ZERO
	_tilt = 0.0
	_pop_t = 1.0
	_rot_pop_t = 1.0
	_flinch_left = 0.0
	if is_instance_valid(_preview):
		_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_preview.top_level = true
		_preview.z_index = 200
		if _preview.get_parent() == null:
			add_child(_preview)
		if _preview.has_method("set_mode"):
			_preview.set_mode(_mode)
		else:
			_preview.set("mode", _mode)
		_preview.visible = true
		_preview.modulate.a = DRAG_ALPHA
		_preview.scale = Vector2.ONE
		_preview.rotation = 0.0
		_placing = true
		_sync_preview_rotation()
		# Первый кадр — сразу под курсором, чтобы не было рывка из (0,0).
		_place()
		_pop_t = 0.0 if not _reduced() else 1.0
		_mouse_prev = _mouse_pos()
		_apply_transform()
		_preview.queue_redraw()
	set_process(true)


func set_mode(p_mode: String) -> void:
	var next := _normalize(p_mode)
	_mode = next
	if is_instance_valid(_preview):
		if _preview.has_method("set_mode"):
			_preview.set_mode(next)
		else:
			_preview.set("mode", next)
		_preview.queue_redraw()


func end(_absorb_to: Variant = null) -> void:
	var had := is_instance_valid(_preview) or not _hover_id.is_empty()
	if is_instance_valid(_preview):
		_preview.visible = false
		var parent := _preview.get_parent()
		if parent != null:
			parent.remove_child(_preview)
		_preview.queue_free()
	# preview() обязан вернуть null сразу после end() — без ожидания кадра.
	_preview = null
	_rotation = 0
	_rotate_frame = -1
	_pos = Vector2.ZERO
	_tilt = 0.0
	_pop_t = 1.0
	_rot_pop_t = 1.0
	_flinch_left = 0.0
	_placing = false
	reset_hover()
	if had:
		drag_ended.emit()
	set_process(false)


func preview() -> Control:
	return _preview if is_instance_valid(_preview) else null


func mode() -> String:
	return _mode


# --- поворот ---------------------------------------------------------------

## Текущий поворот фигуры (0..3). Авторитетное состояние на время drag.
func rotation() -> int:
	return _rotation


func set_rotation(value: int) -> void:
	var next := posmod(int(value), 4)
	if next == _rotation:
		return
	_rotation = next
	_sync_preview_rotation()
	_rot_pop_t = 0.0 if not _reduced() else 1.0
	_apply_transform()
	rotation_changed.emit(_rotation)


## +90° по часовой. Повторный вызов в том же кадре игнорируется: R/ПКМ
## приходят и источнику, и цели drop, а повернуть нужно один раз.
func rotate_cw() -> int:
	var frame := Engine.get_process_frames()
	if _rotate_frame == frame:
		return _rotation
	_rotate_frame = frame
	set_rotation(_rotation + 1)
	return _rotation


## Есть ли активное превью — то есть drag действительно идёт.
func is_active() -> bool:
	return is_instance_valid(_preview)


func _sync_preview_rotation() -> void:
	if not is_instance_valid(_preview):
		return
	if _preview.has_method("setup"):
		_preview.setup(str(_preview.get("file_type")), str(_preview.get("shape_id")),
			_rotation, str(_preview.get("file_name")), str(_preview.get("ext")),
			float(_preview.get("cell_size")))
		if _preview.has_method("set_mode"):
			_preview.set_mode(_mode)
	else:
		_preview.set("shape_rotation", _rotation)
	_preview.queue_redraw()
	# setup() меняет custom_minimum_size — превью должно остаться под курсором.
	_place()


func hover_folder(folder_id: String) -> void:
	if folder_id.is_empty():
		reset_hover()
		return
	if folder_id == _hover_id:
		# повторный вход в ту же папку не сбрасывает и не дублирует таймер
		return
	_hover_id = folder_id
	_hover_left = HOVER_DELAY
	_hover_fired = false
	set_process(true)


func reset_hover() -> void:
	_hover_id = ""
	_hover_left = 0.0
	_hover_fired = false
	if not is_instance_valid(_preview):
		set_process(false)


func hover_id() -> String:
	return _hover_id


func _process(delta: float) -> void:
	if not _hover_id.is_empty() and not _hover_fired:
		_hover_left -= delta
		if _hover_left <= 0.0:
			_hover_fired = true
			hover_open.emit(_hover_id)
	if is_instance_valid(_preview) and _preview.visible:
		_animate(delta)
	if not is_instance_valid(_preview) and (_hover_id.is_empty() or _hover_fired):
		set_process(false)


## Локальный выключатель движения (Lane A зовёт через has_method).
func set_motion_enabled(on: bool) -> void:
	_motion_on = on
	if _reduced():
		_tilt = 0.0
		_flinch_left = 0.0
		_pop_t = 1.0
		_rot_pop_t = 1.0
		if is_instance_valid(_preview):
			_pos = _target_pos()
	_apply_transform()


## Короткий отказ: превью дёргается по X, не меняя реальную позицию drag.
func flinch() -> void:
	if _reduced():
		return
	_flinch_left = FLINCH_DUR
	if is_instance_valid(_preview):
		set_process(true)


func _reduced() -> bool:
	return not _motion_on or UiMotion.reduced


func _mouse_pos() -> Vector2:
	var vp := get_viewport()
	return vp.get_mouse_position() if vp != null else Vector2.ZERO


## Куда превью стремится: под курсором, с прежним смещением.
func _target_pos() -> Vector2:
	if not is_instance_valid(_preview):
		return _pos
	return _mouse_pos() - _preview.custom_minimum_size * 0.5 + PREVIEW_OFFSET


func _animate(delta: float) -> void:
	if not is_instance_valid(_preview):
		return
	var target := _target_pos()
	if _reduced():
		_pos = target
		_tilt = 0.0
		_pop_t = 1.0
		_rot_pop_t = 1.0
		_flinch_left = 0.0
	else:
		_pos = _pos.lerp(target, UiMotion.k(delta, SMOOTH_TAU))
		var mouse := _mouse_pos()
		if delta > 0.0001:
			var vel := (mouse - _mouse_prev) / delta
			var want := clampf(vel.x / TILT_MAX_SPEED, -1.0, 1.0) * UiMotion.DRAG_TILT
			_tilt = lerpf(_tilt, want, UiMotion.k(delta, TILT_TAU))
		_mouse_prev = mouse
		_pop_t = minf(1.0, _pop_t + delta / POP_DUR)
		_rot_pop_t = minf(1.0, _rot_pop_t + delta / POP_DUR)
		_flinch_left = maxf(0.0, _flinch_left - delta)
	_apply_transform()


func _apply_transform() -> void:
	if not is_instance_valid(_preview):
		return
	_preview.pivot_offset = _preview.custom_minimum_size * 0.5
	# Лёгкая «пружина»: основная волна + малый обратный горб, мягко гаснет.
	var pop := sin(PI * _pop_t) + 0.22 * sin(TAU * _pop_t)
	var rpop := sin(PI * _rot_pop_t) + 0.35 * sin(TAU * _rot_pop_t)
	var s := 1.0 + (POP_SCALE - 1.0) * pop + (POP_SCALE - 1.0) * rpop
	_preview.scale = Vector2(s, s)
	_preview.rotation = _tilt if not _reduced() else 0.0
	var off := Vector2.ZERO
	if _flinch_left > 0.0 and not _reduced():
		var p := _flinch_left / FLINCH_DUR
		off.x = sin(p * PI * 3.0) * FLINCH_PX * p
	_preview.position = _pos + off


func _place() -> void:
	if not is_instance_valid(_preview):
		return
	if _placing:
		_pos = _target_pos()
		_placing = false
	_apply_transform()


func _normalize(value: String) -> String:
	return "square" if value == "square" else "shape"
