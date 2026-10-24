class_name MiniGame
extends Control
## Заглушка мини-игры запроса (D17).
##
## Окно 640×360, заголовок по типу файла, полоса заполняется за 2 с,
## кнопки «Отправить» / «Переделать». quality всегда 1.0; «Переделать»
## лишь перезапускает полосу и не меняет качество. Esc — no-op (D10).
## Рисуется кодом, без UI-компонентов.

signal finished(quality: float)

const WINDOW_SIZE := Vector2(640.0, 360.0)
const DURATION := 2.0
const QUALITY_STUB := 1.0

const SEND_RECT := Rect2(150.0, 282.0, 150.0, 34.0)
const REDO_RECT := Rect2(340.0, 282.0, 150.0, 34.0)
const BAR_RECT := Rect2(100.0, 210.0, 440.0, 22.0)

const COL_PANEL := Color("#c0c0c0")
const COL_TITLE := Color("#000080")
const COL_ZONE := Color("#007000")
const COL_MISS := Color("#c00000")
const COL_DARK := Color("#000000")
const COL_LIGHT := Color("#ffffff")

const TYPE_NAMES := {
	"text": "ТЕКСТ",
	"sound": "ЗВУК",
	"photo": "ФОТО",
	"video": "ВИДЕО",
}

var game_type: String = "text"
var difficulty: float = 1.0
var progress: float = 0.0
var running: bool = false

var _emitted: bool = false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	size = WINDOW_SIZE
	custom_minimum_size = WINDOW_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_process(false)
	set_process_input(true)


func _ready() -> void:
	_center_on_screen()
	get_viewport().size_changed.connect(_center_on_screen)


func start(type: String, p_difficulty: float = 1.0) -> void:
	game_type = str(type)
	if not TYPE_NAMES.has(game_type):
		game_type = "text"
	difficulty = maxf(0.0, float(p_difficulty))
	_emitted = false
	running = true
	progress = 0.0
	visible = true
	set_process(true)
	set_process_input(true)
	_center_on_screen()
	queue_redraw()


func quality() -> float:
	return QUALITY_STUB


## Правило выбора типа по среднему коэффициенту (GDD §8.4 / D17).
static func select_type(types: Array) -> String:
	var total := 0.0
	if types.is_empty():
		return "text"
	for type in types:
		total += _coeff(str(type))
	var difficulty := total / float(types.size())
	if difficulty < 1.5:
		return "text"
	if difficulty < 2.5:
		return "sound"
	if difficulty < 3.5:
		return "photo"
	return "video"


static func type_label(type: String) -> String:
	return str(TYPE_NAMES.get(str(type), "ТЕКСТ"))


static func _coeff(type: String) -> float:
	match type:
		"sound":
			return 2.0
		"photo":
			return 3.0
		"video":
			return 4.0
	return 1.0


func _process(delta: float) -> void:
	if not running:
		return
	if progress < DURATION:
		progress = minf(DURATION, progress + minf(maxf(delta, 0.0), 0.1))
		queue_redraw()


func _input(event: InputEvent) -> void:
	if not running:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			# D10: Esc в мини-игре — no-op, но событие не отдаём паузе часа.
			_mark_input_handled()
			return
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_mark_input_handled()
			_send()
			return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var local: Vector2 = event.position - global_position
		if SEND_RECT.has_point(local) and progress >= DURATION:
			_mark_input_handled()
			_send()
		elif REDO_RECT.has_point(local):
			_mark_input_handled()
			_restart_bar()


func _send() -> void:
	if _emitted:
		return
	_emitted = true
	running = false
	set_process(false)
	set_process_input(false)
	_play_sfx(&"minigame_win")
	finished.emit(QUALITY_STUB)
	queue_free()


func _restart_bar() -> void:
	# D17: «Переделать» перезапускает заглушку, quality не меняется.
	progress = 0.0
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, WINDOW_SIZE), COL_PANEL, true)
	draw_rect(Rect2(Vector2.ZERO, WINDOW_SIZE), COL_DARK, false, 2.0)
	draw_rect(Rect2(2.0, 2.0, WINDOW_SIZE.x - 4.0, 24.0), COL_TITLE, true)
	var title := "МИНИ-ИГРА: %s" % type_label(game_type)
	draw_string(font, Vector2(12.0, 20.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COL_LIGHT)

	draw_string(font, Vector2(40.0, 86.0), "заглушка", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, COL_DARK)
	draw_string(font, Vector2(40.0, 116.0), "Сложность: %.2f · quality = %.1f" % [difficulty, QUALITY_STUB], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_TITLE)
	draw_string(font, Vector2(40.0, 142.0), "Подготовьте файл к отправке. Esc не закрывает окно.", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_DARK)

	# Полоса 2 с.
	draw_rect(BAR_RECT, COL_TITLE, true)
	draw_rect(BAR_RECT, COL_DARK, false, 2.0)
	var ratio := clampf(progress / DURATION, 0.0, 1.0)
	if ratio > 0.0:
		draw_rect(Rect2(BAR_RECT.position.x, BAR_RECT.position.y, BAR_RECT.size.x * ratio, BAR_RECT.size.y), COL_ZONE, true)
	draw_string(font, Vector2(BAR_RECT.position.x, BAR_RECT.position.y - 8.0), "ОБРАБОТКА  %.1f / %.1f с" % [progress, DURATION], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_DARK)

	# Кнопки.
	_draw_button(SEND_RECT, "Отправить", ratio >= 1.0)
	_draw_button(REDO_RECT, "Переделать", true)


func _draw_button(rect: Rect2, label: String, enabled: bool) -> void:
	var font := get_theme_default_font()
	var fill := COL_TITLE if enabled else Color("#808080")
	draw_rect(rect, fill, true)
	draw_rect(rect, COL_DARK, false, 2.0)
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	var pos := Vector2(rect.position.x + (rect.size.x - text_size.x) * 0.5, rect.position.y + 22.0)
	draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_LIGHT)


func _center_on_screen() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var screen := get_viewport_rect().size
	position = ((screen - WINDOW_SIZE) * 0.5).floor()
	position.x = maxf(0.0, position.x)
	position.y = maxf(0.0, position.y)


func _mark_input_handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _play_sfx(id: StringName) -> void:
	var audio = _autoload("Audio")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(str(id))


func _autoload(name: String):
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null(name)
	return null
