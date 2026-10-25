class_name ConnectionGame
extends Control
## Мини-игра «полоска соединения» (D04).
##
## Окно 640×240, полоса 480×40, зелёная зона по формуле:
##   W = clamp(0.30 − 0.005×(hour−1) − 0.005×successes
##             + 0.05×zone_level, 0.18, 0.36)
## Три палочки 3×18 со скоростями 440/340/280 px/с. Три клика ЛКМ/Space
## строго по очереди. Промах/уход за край — красная вспышка 0.8 с, затем
## finished(false) и закрытие панели (без автоповтора): игрок сам нажимает
## «Соединиться» заново. Esc — тоже finished(false). Всё рисуется вручную,
## UI-компоненты не используются.

signal finished(success: bool, request_id: String)

const WINDOW_SIZE := Vector2(640.0, 240.0)
const BAR_RECT := Rect2(80.0, 122.0, 480.0, 40.0)
const STICK_W := 3.0
const STICK_H := 18.0
const STICK_SPEEDS: Array[float] = [440.0, 340.0, 280.0]
const FLASH_SEC := 0.8
const CLICKS_REQUIRED := 3

var hour: int = 1
var successes: int = 0
var zone_level: int = 0
var request_id: String = ""

var zone_ratio: float = 0.30
var active_index: int = 0
var stick_positions: Array[float] = [0.0, 0.0, 0.0]
var hit_positions: Array[float] = [-1.0, -1.0, -1.0]
var flash_left: float = 0.0
var running: bool = false
var missed: bool = false
var game_over: bool = false

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


func start(p_hour: int, p_successes: int, p_zone_level: int, p_request_id: String) -> void:
	hour = maxi(1, int(p_hour))
	successes = maxi(0, int(p_successes))
	zone_level = maxi(0, int(p_zone_level))
	request_id = str(p_request_id)
	zone_ratio = compute_zone(hour, successes, zone_level)
	game_over = false
	_emitted = false
	running = true
	missed = false
	flash_left = 0.0
	_reset_attempt()
	visible = true
	set_process(true)
	set_process_input(true)
	_center_on_screen()
	queue_redraw()


## Формула D04 — единственный источник ширины зоны.
static func compute_zone(p_hour: int, p_successes: int, p_zone_level: int) -> float:
	var h := maxi(1, int(p_hour))
	var value := 0.30 - 0.005 * float(h - 1) - 0.005 * float(maxi(0, p_successes)) + 0.05 * float(maxi(0, p_zone_level))
	return clampf(value, 0.18, 0.36)


static func speed_for(index: int) -> float:
	if index < 0:
		return STICK_SPEEDS[0]
	return STICK_SPEEDS[index % STICK_SPEEDS.size()]


## Ширина зоны в пикселях.
func zone_width_px() -> float:
	return zone_ratio * BAR_RECT.size.x


## Совместимость со старым именем из IMPLEMENTATION.md.
func width() -> float:
	return zone_ratio


## Совместимость со старым именем open(request_id, hour, successes, zone_level).
func open(p_request_id: String, p_hour: int, p_successes: int, p_zone_level: int) -> void:
	start(p_hour, p_successes, p_zone_level, p_request_id)


func zone_start_x() -> float:
	return BAR_RECT.position.x + (BAR_RECT.size.x - zone_width_px()) * 0.5


func _reset_attempt() -> void:
	active_index = 0
	missed = false
	for i in range(CLICKS_REQUIRED):
		stick_positions[i] = BAR_RECT.position.x
		hit_positions[i] = -1.0
	queue_redraw()


func _process(delta: float) -> void:
	if not running or game_over:
		return
	# Вспышка идёт по реальному delta, движение палочек — с D11-капом 0.1.
	var raw_dt := maxf(delta, 0.0)
	if flash_left > 0.0:
		flash_left = maxf(0.0, flash_left - raw_dt)
		if flash_left <= 0.0:
			# Промах закрывает панель: без автоповтора, новый проход — только
			# по повторному «Соединиться» (connect_packet/connect_request).
			_finish(false)
			return
		queue_redraw()
		return
	var dt := minf(raw_dt, 0.1)
	if active_index >= CLICKS_REQUIRED:
		return
	var speed := speed_for(active_index)
	stick_positions[active_index] += speed * dt
	if stick_positions[active_index] > BAR_RECT.position.x + BAR_RECT.size.x - STICK_W:
		_miss()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not running or game_over:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_mark_input_handled()
			_finish(false)
			return
		if event.keycode == KEY_SPACE:
			_mark_input_handled()
			_attempt_click()
			return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_mark_input_handled()
			_attempt_click()


func _attempt_click() -> void:
	if not running or game_over or flash_left > 0.0:
		return
	if active_index >= CLICKS_REQUIRED:
		return
	var x := stick_positions[active_index]
	var zone_start := zone_start_x()
	var zone_end := zone_start + zone_width_px()
	if x >= zone_start and x <= zone_end:
		hit_positions[active_index] = x
		active_index += 1
		_play_sfx(&"click")
		if active_index >= CLICKS_REQUIRED:
			_finish(true)
		else:
			stick_positions[active_index] = BAR_RECT.position.x
			queue_redraw()
	else:
		_miss()


func _miss() -> void:
	if flash_left > 0.0:
		return
	missed = true
	flash_left = FLASH_SEC
	_play_sfx(&"connect_fail")
	queue_redraw()


func _finish(success: bool) -> void:
	if _emitted:
		return
	_emitted = true
	game_over = true
	running = false
	set_process(false)
	set_process_input(false)
	finished.emit(success, request_id)
	queue_free()


func _draw() -> void:
	var font := Theme90.ui()
	var full := Rect2(Vector2.ZERO, WINDOW_SIZE)
	Theme90.draw_bevel(self, full, false, Theme90.BEVEL, Theme90.PAPER)

	# Светлый титлбар: тёмный текст и teal-акцент.
	var tr := Rect2(1.0, 1.0, WINDOW_SIZE.x - 2.0, 28.0)
	draw_style_box(Theme90.top_box(Theme90.PAPER_HI, 4), tr)
	draw_rect(Rect2(tr.position.x + 1.0, tr.end.y, tr.size.x - 2.0, 1.0),
		Theme90.HAIRLINE)
	draw_circle(Vector2(tr.position.x + 14.0, tr.position.y + 14.0), 3.0, Theme90.ACCENT)
	draw_string(font, Vector2(tr.position.x + 25.0, tr.position.y + 19.0),
		"УСТАНОВЛЕНИЕ СОЕДИНЕНИЯ", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Theme90.NAVY)
	draw_string(font, Vector2(80.0, 76.0),
		"Проведите три палочки через зелёную зону по очереди.",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Theme90.SHADE)

	# Полоса: мягкий жёлоб, зона успеха и тонкие границы.
	draw_style_box(Theme90.well_box(Theme90.PAPER_LO), BAR_RECT)
	var zone_start := zone_start_x()
	var green_rect := Rect2(zone_start, BAR_RECT.position.y, zone_width_px(),
		BAR_RECT.size.y)
	draw_style_box(Theme90.fill_box(Color(Theme90.SUCCESS.r, Theme90.SUCCESS.g,
		Theme90.SUCCESS.b, 0.24), 3), green_rect.grow(-1.0))
	draw_rect(Rect2(green_rect.position.x, BAR_RECT.position.y + 1.0, 1.0,
		BAR_RECT.size.y - 2.0), Theme90.SUCCESS)
	draw_rect(Rect2(green_rect.end.x - 1.0, BAR_RECT.position.y + 1.0, 1.0,
		BAR_RECT.size.y - 2.0), Theme90.SUCCESS)

	# Палочки.
	for i in range(CLICKS_REQUIRED):
		var x := -1.0
		var color := Theme90.SHADE
		var is_hit := hit_positions[i] >= 0.0
		if is_hit:
			x = hit_positions[i]
			color = Theme90.SUCCESS
		elif i == active_index:
			x = stick_positions[i]
			color = Theme90.ACCENT
		elif i > active_index:
			x = BAR_RECT.position.x
		if x < 0.0:
			continue
		if missed and flash_left > 0.0 and i == active_index:
			color = Theme90.ERROR
		var y := BAR_RECT.position.y + (BAR_RECT.size.y - STICK_H) * 0.5
		if is_hit and not missed:
			draw_style_box(Theme90.box(Theme90.WHITE, Theme90.SUCCESS, 2, 1),
				Rect2(x - 1.0, y - 1.0, STICK_W + 2.0, STICK_H + 2.0))
		else:
			draw_style_box(Theme90.fill_box(color, 1), Rect2(x, y, STICK_W, STICK_H))

	# Подсказки.
	draw_string(font, Vector2(80.0, 196.0),
		"ЛКМ / ПРОБЕЛ — три попадания по очереди. Esc — отмена.",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Theme90.DARK)
	draw_string(font, Vector2(80.0, 214.0),
		"ЗОНА %.0f%% · попаданий %d/3" % [zone_ratio * 100.0, active_index],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Theme90.SHADE)
	if flash_left > 0.0:
		draw_rect(Rect2(0.0, 28.0, WINDOW_SIZE.x, WINDOW_SIZE.y - 28.0),
			Color(Theme90.ERROR.r, Theme90.ERROR.g, Theme90.ERROR.b, 0.08), true)
		draw_string(font, Vector2(80.0, 96.0),
			"ПРОМАХ — СОЕДИНЕНИЕ НЕ УСТАНОВЛЕНО",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Theme90.ERROR)


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
