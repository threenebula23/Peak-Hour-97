class_name VhsOverlay
extends ColorRect
## Нативный VHS/CRT-слой главного меню.
##
## Полноэкранный ColorRect с canvas_item-шейдером: читает готовый кадр через
## hint_screen_texture и добавляет скан-линии (2 физических px), очень слабое
## зерно, хроматику ≤0.0003 UV, виньетку и редкую полосу. Считается в
## разрешении фактического окна (1920×1080), а не в логических 1280×720,
## поэтому линии ровные, без блоков и banding; текст остаётся резким.
##
## Слой — ребёнок MainMenu и последний в дереве: он фильтрует меню (включая
## кнопки), но соседние модалки в modal_root рисуются поверх и не фильтруются.
##
## В HEADLESS материал не создаётся и слой скрыт — тесты не тормозят.

const SHADER_PATH := "res://shaders/vhs.gdshader"

## Включён ли эффект. Отключается кодом: menu.set_vhs_enabled(false)
## или напрямую overlay.set_enabled(false).
var enabled := true:
	set(value):
		enabled = value
		_refresh()

## Общая сила слоя, 0.0..0.55. Выше 0.55 текст начинает терять контраст.
var intensity := 0.40:
	set(value):
		intensity = clampf(value, 0.0, 0.55)
		if _mat != null:
			_mat.set_shader_parameter("intensity", intensity)

var _mat: ShaderMaterial = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	color = Color(1, 1, 1, 1)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_material()


## Публичный переключатель: true — эффект виден, false — слой полностью скрыт.
func set_enabled(value: bool) -> void:
	enabled = value


func is_available() -> bool:
	return _mat != null


func _build_material() -> void:
	# В headless экранный шейдер не нужен и только замедляет тесты.
	if DisplayServer.get_name() == "headless":
		visible = false
		set_process(false)
		return
	var shader := load(SHADER_PATH) as Shader
	if shader == null:
		push_warning("VHS: не удалось загрузить %s" % SHADER_PATH)
		visible = false
		return
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_mat.set_shader_parameter("intensity", intensity)
	material = _mat
	_refresh()


func _refresh() -> void:
	# Сеттер может сработать до _ready — тогда состоянием займётся _ready.
	if not is_node_ready():
		return
	var on: bool = enabled and _mat != null
	visible = on
	set_process(on)
	# TIME в canvas_item шейдере обновляется движком автоматически, пока
	# слой видим; ручных uniform-обновлений не нужно.
