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

var _preview: Control = null
var _mode: String = "shape"
var _rotation: int = 0
var _rotate_frame: int = -1
var _hover_id: String = ""
var _hover_left: float = 0.0
var _hover_fired: bool = false


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
		_sync_preview_rotation()
		_preview.queue_redraw()
		_place()
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


func end() -> void:
	var had := is_instance_valid(_preview) or not _hover_id.is_empty()
	if is_instance_valid(_preview):
		_preview.visible = false
		var parent := _preview.get_parent()
		if parent != null:
			parent.remove_child(_preview)
		_preview.queue_free()
	_preview = null
	_rotation = 0
	_rotate_frame = -1
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
		_place()
	if not is_instance_valid(_preview) and (_hover_id.is_empty() or _hover_fired):
		set_process(false)


func _place() -> void:
	if not is_instance_valid(_preview):
		return
	var vp := get_viewport()
	if vp == null:
		return
	_preview.position = vp.get_mouse_position() - _preview.custom_minimum_size * 0.5 \
		+ PREVIEW_OFFSET


func _normalize(value: String) -> String:
	return "square" if value == "square" else "shape"
