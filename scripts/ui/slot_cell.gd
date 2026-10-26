class_name SlotCell
extends Control
## Ячейка канала 236×44.
##
## kind:
##   "packet"/"request" — направление, файл, тонкий прогресс (прежний вид);
##   "tcp_connection"   — имя клиента, IP, статус связи, прогресс передачи и
##                        кнопка ОТКЛЮЧИТЬ. Файлов и required здесь нет.
## Пустая — пунктир; заблокированная — замок и цена в магазине.

signal close_pressed(id: String)
signal cell_pressed(id: String)
signal packet_dropped(cell_id: String, payload: Dictionary)
## Игрок закрывает TCP-соединение: id — id соединения (conn_N), не запроса.
signal disconnect_pressed(id: String)

const CELL := Vector2(236, 44)

# --- Motion (Lane B) -------------------------------------------------------
const ENTER_DUR := 0.16
const BORDER_FLASH_DUR := 0.25
const HOVER_DUR := 0.10
const METER_TAU := 0.12
## Пульс точек TCP-связи.
const LINK_PULSE := 0.5
const DROP_FLASH_DUR := 0.18
const ERROR_FLASH_DUR := 0.22
## Пульс прогресс-полосы активной передачи.
const PROGRESS_PULSE := 0.9

var id := ""
var file_name := ""
var direction := "down"   # down — приём, up — отправка
var progress := 0.0
var state := "empty"      # empty / active / locked
var sub_text := ""
var slot_label := ""
## Тип занятости слота: "packet" / "request" / "tcp_connection" ("" — пусто).
var kind := ""
## Дополнительная строка: для tcp_connection — IP клиента.
var detail := ""
var can_disconnect := false
## tcp_connection: по соединению сейчас идёт передача.
var sending := false

var hovered := false:
	set(v):
		hovered = v
		set_process(true)
		queue_redraw()
var drop_active := false:
	set(v):
		if drop_active != v:
			drop_active = v
			if v:
				_drop_clock = 0.0
			set_process(true)
			queue_redraw()

var _x: Button90
var _disconnect: Button90

var _hover_amt := 0.0
## Время с начала enter(): alpha + вспышка рамки.
var _enter_elapsed := ENTER_DUR
var _flash_clock := -1.0
var _meter := 0.0
var _meter_ready := false
var _link_phase := 0.0
var _pulse_phase := 0.0
var _drop_clock := -1.0
var _error_clock := -1.0
var _motion_on := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = CELL
	if size == Vector2.ZERO:
		size = CELL
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	mouse_entered.connect(func() -> void: hovered = true)
	mouse_exited.connect(func() -> void: hovered = false)
	_x = Button90.new()
	_x.name = "CloseButton"
	_x.icon = Button90.Icon.X
	_x.size = Vector2(14, 14)
	_x.position = Vector2(216, 5)
	_x.tooltip_text = "Прервать передачу"
	add_child(_x)
	_x.pressed.connect(func() -> void: close_pressed.emit(id))

	# Закрытие TCP-соединения: отдельная кнопка, только у connection-слота.
	_disconnect = Button90.new()
	_disconnect.name = "DisconnectButton"
	_disconnect.caption = "ОТКЛЮЧИТЬ"
	_disconnect.caption_size = 10
	_disconnect.position = Vector2(146, 4)
	_disconnect.size = Vector2(84, 16)
	_disconnect.tooltip_text = "Закрыть соединение и освободить слот"
	_disconnect.visible = false
	add_child(_disconnect)
	_disconnect.pressed.connect(func() -> void: disconnect_pressed.emit(id))
	set_process(false)
	enter(0)


# --- motion (Lane B) -------------------------------------------------------

## Появление: alpha 0.16 c + вспышка рамки 0.25 c.
func enter(_index: int = 0) -> void:
	if _reduced():
		_enter_elapsed = ENTER_DUR
		_flash_clock = -1.0
		modulate.a = 1.0
		return
	_enter_elapsed = 0.0
	_flash_clock = 0.0
	modulate.a = 0.0
	set_process(true)


## Короткий отказ: красная рамка гаснет (position/размер не меняются).
func flash_error() -> void:
	_error_clock = 0.0
	set_process(true)
	queue_redraw()


## Внешний переключатель движения (Lane A / настройки).
func set_motion_enabled(on: bool) -> void:
	_motion_on = on
	if _reduced():
		_hover_amt = 1.0 if hovered else 0.0
		modulate.a = 1.0
		_enter_elapsed = ENTER_DUR
		_flash_clock = -1.0
		_drop_clock = -1.0
		_error_clock = -1.0
		_link_phase = 0.0
	queue_redraw()


func _reduced() -> bool:
	return not _motion_on or UiMotion.reduced


func _proc_needed() -> bool:
	if _enter_elapsed < ENTER_DUR:
		return true
	if _flash_clock >= 0.0 or _drop_clock >= 0.0 or _error_clock >= 0.0:
		return true
	if not is_equal_approx(_hover_amt, 1.0 if hovered else 0.0):
		return true
	if not is_equal_approx(_meter, progress):
		return true
	# Пульс прогресса активной передачи.
	if _progress_pulsing():
		return true
	# Пульс точек связи живёт только у TCP-слота и молчит в reduced.
	return kind == "tcp_connection" and not _reduced()


func _process(delta: float) -> void:
	if _enter_elapsed < ENTER_DUR:
		if _reduced():
			_enter_elapsed = ENTER_DUR
			modulate.a = 1.0
		else:
			_enter_elapsed = minf(ENTER_DUR, _enter_elapsed + delta)
			modulate.a = clampf(_enter_elapsed / ENTER_DUR, 0.0, 1.0)
	var hov := 1.0 if hovered else 0.0
	if _reduced():
		_hover_amt = hov
	elif not is_equal_approx(_hover_amt, hov):
		_hover_amt = move_toward(_hover_amt, hov, delta / HOVER_DUR)
	if _flash_clock >= 0.0:
		_flash_clock += delta
		if _flash_clock >= BORDER_FLASH_DUR:
			_flash_clock = -1.0
	if _drop_clock >= 0.0:
		_drop_clock += delta
		if _drop_clock >= DROP_FLASH_DUR:
			_drop_clock = -1.0
	if _error_clock >= 0.0:
		_error_clock += delta
		if _error_clock >= ERROR_FLASH_DUR:
			_error_clock = -1.0
	if not _meter_ready:
		_meter = progress
		_meter_ready = true
	elif not is_equal_approx(_meter, progress):
		if _reduced():
			_meter = progress
		else:
			_meter = lerpf(_meter, progress, UiMotion.k(delta, METER_TAU))
			if absf(_meter - progress) < 0.002:
				_meter = progress
	if kind == "tcp_connection" and not _reduced():
		_link_phase = fmod(_link_phase + delta, LINK_PULSE)
	if _progress_pulsing():
		_pulse_phase = fmod(_pulse_phase + delta, PROGRESS_PULSE)
	queue_redraw()
	if not _proc_needed():
		set_process(false)


func _draw_hover() -> float:
	if _reduced():
		return 1.0 if hovered else 0.0
	return _hover_amt


## 0..1 — насколько ярко светится рамка сразу после появления.
func _enter_flash() -> float:
	if _flash_clock < 0.0:
		return 0.0
	return clampf(1.0 - _flash_clock / BORDER_FLASH_DUR, 0.0, 1.0)


## Полоса прогресса «дышит», пока идёт передача (0 в покое/reduced).
func _progress_pulsing() -> bool:
	if _reduced() or progress <= 0.0 or progress >= 1.0:
		return false
	if kind == "tcp_connection":
		return sending
	return state == "active"


func _progress_pulse() -> float:
	if not _progress_pulsing():
		return 0.0
	return 0.5 - 0.5 * cos(TAU * _pulse_phase)


## Прогресс-полоса с пульсом и бегущим бликом (draw-only).
func _draw_progress(rect: Rect2, ratio: float, col: Color) -> void:
	var pulse := _progress_pulse()
	var c := col
	if pulse > 0.0:
		c = c.lerp(Theme90.WHITE, 0.18 * pulse)
	Theme90.draw_meter(self, rect, ratio, c)
	if pulse <= 0.0:
		return
	var inner := rect.grow(-1.0)
	var w := inner.size.x * clampf(ratio, 0.0, 1.0)
	if w >= 3.0:
		var x := inner.position.x + maxf(0.0, w - 3.0) * _pulse_phase
		draw_rect(Rect2(x, inner.position.y, 2.0, inner.size.y),
			Color(1, 1, 1, 0.22 * pulse))


func _draw_link(center: Vector2, col: Color) -> void:
	# Точки «дышат» 0.5 c, только пока соединение живо.
	var pulse := 0.0
	if kind == "tcp_connection" and not _reduced():
		pulse = 0.5 + 0.5 * sin(_link_phase / LINK_PULSE * TAU)
	var link_a := 0.75 + 0.25 * pulse
	var lc := col
	lc.a *= link_a
	draw_line(center + Vector2(-5, 0), center + Vector2(5, 0), lc, 1.4)
	draw_circle(center + Vector2(-5, 0), 2.8 + 0.5 * pulse, lc)
	draw_circle(center + Vector2(5, 0), 2.8 + 0.5 * pulse, lc)
	draw_circle(center + Vector2(-5, 0), 1.2, Theme90.WHITE)
	draw_circle(center + Vector2(5, 0), 1.2, Theme90.WHITE)


func setup(p_id: String, p_name: String, p_dir: String, p_progress: float, p_state: String,
		p_sub: String = "", p_label: String = "", p_kind: String = "",
		p_detail: String = "", p_can_disconnect: bool = false,
		p_sending: bool = false) -> void:
	id = p_id
	file_name = p_name
	direction = p_dir
	progress = clampf(p_progress, 0.0, 1.0)
	state = p_state
	sub_text = p_sub
	slot_label = p_label
	kind = p_kind
	detail = p_detail
	can_disconnect = p_can_disconnect
	sending = p_sending
	var connection := kind == "tcp_connection"
	# Старый крестик не мешает кнопке ОТКЛЮЧИТЬ и не нужен connection-слоту.
	if _x != null:
		_x.visible = p_state == "active" and not connection
	if _disconnect != null:
		_disconnect.visible = connection and can_disconnect
	set_process(true)
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var f := Theme90.ui()

	if kind == "tcp_connection":
		_draw_connection(r, f)
		_draw_flashes(r)
		return

	if state == "active":
		var border := Theme90.BORDER.lerp(Theme90.ACCENT_LIGHT, _draw_hover())
		draw_style_box(Theme90.box(Theme90.WHITE, border, 4, 1, Theme90.SHADOW), r)
		var accent := Theme90.SUCCESS if direction == "down" else Theme90.ACCENT
		draw_style_box(Theme90.box(Color(accent.r, accent.g, accent.b, 0.12),
			Color(0, 0, 0, 0), 3, 0), Rect2(8, 11, 20, 20))
		Theme90.draw_arrow(self, Rect2(8, 11, 20, 20), 1 if direction == "down" else 0,
			accent)
		Theme90.text(self, f, Vector2(34, 4), Theme90.fit(f, file_name, 12, 166), 12,
			Theme90.INK, 166)
		var word := "ПРИЁМ" if direction == "down" else "ПЕРЕДАЧА"
		Theme90.text(self, f, Vector2(34, 20), word, 10, Theme90.SHADE)
		var ww := f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		Theme90.text(self, f, Vector2(34 + ww + 6, 20), "%d%%" % int(roundf(progress * 100.0)),
			10, accent)
		_draw_progress(Rect2(34, 33, 160, 4),
			_meter if _meter_ready else progress, accent)
		_draw_flashes(r)
		return

	if state == "locked":
		draw_style_box(Theme90.box(Theme90.PAPER, Theme90.BORDER_SOFT, 4, 1), r)
		Theme90.draw_lock_icon(self, Vector2(11, 15), Theme90.SHADE)
		Theme90.text(self, f, Vector2(28, 4), "СЛОТ %s" % slot_label, 11, Theme90.DARK, 120)
		Theme90.text(self, f, Vector2(28, 20), sub_text if not sub_text.is_empty()
			else "КУПИТЬ В МАГАЗИНЕ", 10, Theme90.SHADE, 198)
		_draw_flashes(r)
		return

	# пустой слот
	draw_style_box(Theme90.box(Theme90.PAPER_HI, Theme90.BORDER_SOFT, 4, 1), r)
	Theme90.draw_dashed_box(self, Rect2(3, 3, size.x - 6, size.y - 6),
		Color(Theme90.SHADE.r, Theme90.SHADE.g, Theme90.SHADE.b, 0.45), 3.0, 1.0)
	draw_style_box(Theme90.box(Color(1, 1, 1, 0.7), Theme90.BORDER_SOFT, 3, 1),
		Rect2(10, 14, 16, 16))
	draw_rect(Rect2(17.5, 18, 1.2, 8), Theme90.SHADE)
	draw_rect(Rect2(14, 21.4, 8, 1.2), Theme90.SHADE)
	Theme90.text(self, f, Vector2(32, 6), sub_text if not sub_text.is_empty()
		else "СВОБОДЕН", 12, Theme90.DARK, 190)
	Theme90.text(self, f, Vector2(32, 24), "перетащите пакет", 10,
		Theme90.ACCENT if drop_active else Theme90.SHADE, 190)
	if drop_active:
		Theme90.draw_dashed_box(self, Rect2(2, 2, size.x - 4, size.y - 4),
			Theme90.ACCENT, 3.0, 1.4)
	_draw_flashes(r)


## Вспышки поверх любого состояния: появление, drop-accept, отказ.
func _draw_flashes(r: Rect2) -> void:
	var ef := _enter_flash()
	if ef > 0.01:
		draw_style_box(Theme90.box(
			Color(Theme90.ACCENT.r, Theme90.ACCENT.g, Theme90.ACCENT.b, 0.06 * ef),
			Color(Theme90.ACCENT.r, Theme90.ACCENT.g, Theme90.ACCENT.b, 0.75 * ef), 4, 2),
			r.grow(-1.0))
	if _drop_clock >= 0.0:
		var da := clampf(1.0 - _drop_clock / DROP_FLASH_DUR, 0.0, 1.0)
		draw_style_box(Theme90.box(
			Color(Theme90.ACCENT.r, Theme90.ACCENT.g, Theme90.ACCENT.b, 0.10 * da),
			Color(Theme90.ACCENT.r, Theme90.ACCENT.g, Theme90.ACCENT.b, 0.85 * da), 4, 2),
			r.grow(-1.0))
	if _error_clock >= 0.0:
		var ea := clampf(1.0 - _error_clock / ERROR_FLASH_DUR, 0.0, 1.0)
		draw_style_box(Theme90.box(
			Color(Theme90.ERROR.r, Theme90.ERROR.g, Theme90.ERROR.b, 0.06 * ea),
			Color(Theme90.ERROR.r, Theme90.ERROR.g, Theme90.ERROR.b, 0.85 * ea), 4, 2),
			r.grow(-1.0))


## Установленное TCP-соединение: клиент + IP + статус связи/передачи.
## Никаких имён файлов, required и attached здесь нет.
func _draw_connection(r: Rect2, f: Font) -> void:
	var hov := _draw_hover()
	var border := Theme90.BORDER.lerp(Theme90.ACCENT_LIGHT, hov)
	draw_style_box(Theme90.box(Theme90.WHITE, border, 4, 1, Theme90.SHADOW), r)
	# Маркер связи (две точки и линия) вместо иконки файла.
	draw_style_box(Theme90.box(Color(Theme90.ACCENT.r, Theme90.ACCENT.g,
		Theme90.ACCENT.b, 0.12), Color(0, 0, 0, 0), 3, 0), Rect2(8, 11, 20, 20))
	_draw_link(Vector2(18, 21), Theme90.ACCENT)

	# Верх: имя клиента. Правее (146, 4) начинается кнопка ОТКЛЮЧИТЬ.
	var name_w := 106.0 if can_disconnect else 166.0
	Theme90.text(self, f, Vector2(34, 4), Theme90.fit(f, file_name, 12, name_w), 12,
		Theme90.INK, name_w)

	if sending:
		var pct := int(roundf(progress * 100.0))
		Theme90.text(self, f, Vector2(34, 20), "ПЕРЕДАЧА · %d%%" % pct, 10,
			Theme90.ACCENT, 100)
		if not detail.is_empty():
			# Правый край — 230: в колонку с кнопкой ОТКЛЮЧИТЬ, 6 px до рамки.
			Theme90.text(self, f, Vector2(134, 20), Theme90.fit(f, detail, 10, 96), 10,
				Theme90.SHADE, 96, HORIZONTAL_ALIGNMENT_RIGHT)
		_draw_progress(Rect2(34, 33, 160, 4),
			_meter if _meter_ready else progress, Theme90.ACCENT)
		return

	# Idle: IP слева, статус связи справа. Без IP показываем только статус.
	Theme90.text(self, f, Vector2(34, 20), Theme90.fit(f, detail, 10, 108), 10,
		Theme90.SHADE, 108)
	Theme90.text(self, f, Vector2(144, 20), "ПОДКЛЮЧЕНО", 10, Theme90.SUCCESS,
		86, HORIZONTAL_ALIGNMENT_RIGHT)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		cell_pressed.emit(id)
		accept_event()


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	if kind == "tcp_connection" or state != "empty":
		drop_active = false
		return false
	var ok: bool = data.get("kind", "") == "packet" and state == "empty"
	drop_active = ok
	return ok


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	drop_active = false
	_drop_clock = 0.0
	set_process(true)
	packet_dropped.emit(id, data)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		drop_active = false
