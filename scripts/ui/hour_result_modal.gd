class_name HourResultModal
extends Control
## Модальное окно «ИТОГИ ЧАСА N»: заработок, запросы, атаки, SLA.
##
## Данные приходят снаружи словарём, игра здесь не считается:
##   hour_results.open({
##       "hour": 3, "hours_total": 9,
##       "earned": 1240, "done": 8, "failed": 2,
##       "reflected": 3, "missed": 1,
##       "sla_delta": -12, "sla": 168, "sla_max": 200,
##   })

signal next_pressed
signal closed

const W := 560.0
const H := 292.0
const TITLE_H := 20.0
const DIM := Color(0.0, 0.0, 0.0, 0.35)

var _data: Dictionary = {}
var _btn_next: Button90


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_btn_next = Button90.new()
	_btn_next.caption = "Далее"
	_btn_next.accent = true
	add_child(_btn_next)
	_btn_next.pressed.connect(_next)

	resized.connect(_layout)
	_layout()
	visible = false


func open(data: Dictionary = {}) -> void:
	_data = data.duplicate(true)
	visible = true
	_layout()
	queue_redraw()
	if _btn_next != null:
		_btn_next.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _next() -> void:
	if not visible:
		return
	visible = false
	next_pressed.emit()


func _value(key: String, fallback: int) -> int:
	return int(_data.get(key, fallback))


func _window_rect() -> Rect2:
	var s := size
	if s.x <= 0.0 or s.y <= 0.0:
		s = Vector2(1280, 720)
	return Rect2(((s - Vector2(W, H)) * 0.5).round(), Vector2(W, H))


func _layout() -> void:
	var r := _window_rect()
	if _btn_next != null:
		_btn_next.position = r.position + Vector2(424, 244)
		_btn_next.size = Vector2(120, 24)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_next()
		get_viewport().set_input_as_handled()


# --- отрисовка -------------------------------------------------------------

func _draw() -> void:
	var full := Rect2(Vector2.ZERO, size)
	if size.x <= 0.0 or size.y <= 0.0:
		full = Rect2(0, 0, 1280, 720)
	draw_rect(full, DIM)
	var r := _window_rect()
	var hour := _value("hour", 1)
	var total := maxi(1, _value("hours_total", 9))

	_draw_frame(r, hour, total)

	var f := Theme90.ui()
	Theme90.text(self, f, Vector2(r.position.x + 16, r.position.y + 25),
		"ЗАРАБОТАНО ЗА ЧАС", Theme90.FS_MICRO, Theme90.DARK)
	Theme90.text(self, Theme90.logo(), Vector2(r.position.x + 16, r.position.y + 43),
		_fmt(_value("earned", 0)) + " $", 24, Theme90.INK)

	# штамп часа
	var stamp := Rect2(r.position + Vector2(392, 30), Vector2(152, 40))
	Theme90.draw_sunken(self, stamp)
	Theme90.text_vcenter(self, f, stamp, "ЧАС %d ИЗ %d" % [hour, total],
		Theme90.FS_BODY, Theme90.INK, -1, HORIZONTAL_ALIGNMENT_CENTER)

	var div := r.position.y + 76
	draw_rect(Rect2(r.position.x + 16, div, r.size.x - 32, 1), Theme90.HAIRLINE)

	_draw_pair_row(r, r.position.y + 88, "Выполнено / провалено",
		_value("done", 0), _value("failed", 0))
	_draw_pair_row(r, r.position.y + 118, "Атаки отражено / пропущено",
		_value("reflected", 0), _value("missed", 0))
	_draw_delta_row(r, r.position.y + 148, _value("sla_delta", 0))

	# итоговый SLA
	var sla := _value("sla", 0)
	var sla_max := maxi(1, _value("sla_max", 200))
	var well := Rect2(r.position + Vector2(16, 186), Vector2(r.size.x - 32, 46))
	Theme90.draw_sunken(self, well)
	Theme90.text(self, f, Vector2(well.position.x + 8, well.position.y + 6),
		"ИТОГОВЫЙ SLA", Theme90.FS_MICRO, Theme90.SHADE)
	Theme90.text_vcenter(self, Theme90.logo(),
		Rect2(well.position.x + well.size.x - 160, well.position.y + 3, 152, 14),
		"%d / %d" % [sla, sla_max], 12, Theme90.INK, -1, HORIZONTAL_ALIGNMENT_RIGHT)

	var bar := Rect2(well.position + Vector2(8, 26), Vector2(well.size.x - 16, 6))
	var ratio := clampf(float(sla) / float(sla_max), 0.0, 1.0)
	var col := Theme90.SUCCESS
	if ratio <= 0.3:
		col = Theme90.ERROR
	elif ratio <= 0.6:
		col = Theme90.WARN
	Theme90.draw_meter(self, bar, ratio, col, Theme90.PAPER_LO)

	# подвал
	Theme90.text(self, f, Vector2(r.position.x + 16, r.position.y + 252),
		("СЛЕДУЮЩИЙ ЧАС — ПОДГОТОВКА" if hour < total else "СМЕНА ЗАВЕРШЕНА")
		+ " · ESC — ПРОДОЛЖИТЬ", Theme90.FS_MICRO, Theme90.DARK)


func _draw_frame(r: Rect2, hour: int, total: int) -> void:
	Theme90.draw_bevel(self, r, false, Theme90.BEVEL, Theme90.WHITE)
	Theme90.modal_header(self, r, "ИТОГИ ЧАСА %d" % hour, "УЗЕЛ 7 · СМЕНА %d" % hour)


func _draw_pair_row(r: Rect2, y: float, label: String, good: int, bad: int) -> void:
	var f := Theme90.ui()
	Theme90.text(self, f, Vector2(r.position.x + 16, y + 8), label, Theme90.FS_BODY, Theme90.INK)
	var good_s := str(good)
	var bad_s := str(bad)
	var sep := " / "
	var char_w := 12.0
	var total_w := (good_s.length() + bad_s.length()) * char_w + 3.0 * char_w
	var right := r.position.x + r.size.x - 16.0
	var left := right - total_w

	# точечный поводок
	var dot_x := r.position.x + 16.0 + f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1,
		Theme90.FS_BODY).x + 8.0
	var dot_y := y + 17.0
	while dot_x < left - 6.0:
		draw_rect(Rect2(dot_x, dot_y, 1, 1), Theme90.SHADE)
		dot_x += 4.0

	var lf := Theme90.logo()
	Theme90.text(self, lf, Vector2(left, y + 6), good_s, 12,
		Theme90.SUCCESS if good > 0 else Theme90.DARK)
	Theme90.text(self, lf, Vector2(left + good_s.length() * char_w, y + 6), sep, 12, Theme90.INK)
	Theme90.text(self, lf, Vector2(left + good_s.length() * char_w + sep.length() * char_w, y + 6),
		bad_s, 12, Theme90.ERROR if bad > 0 else Theme90.DARK)


func _draw_delta_row(r: Rect2, y: float, delta: int) -> void:
	var f := Theme90.ui()
	# треугольник «дельта» рисуем сами: в пиксельном шрифте он теряется
	var tx := r.position.x + 17.0
	draw_colored_polygon(PackedVector2Array([
		Vector2(tx, y + 18), Vector2(tx + 9, y + 18), Vector2(tx + 4.5, y + 9)]), Theme90.INK)
	Theme90.text(self, f, Vector2(tx + 13, y + 8), "SLA", Theme90.FS_BODY, Theme90.INK)

	var value := ("+" if delta > 0 else "") + str(delta)
	var col := Theme90.DARK
	if delta > 0:
		col = Theme90.SUCCESS
	elif delta < 0:
		col = Theme90.ERROR

	var dot_x := tx + 13.0 + f.get_string_size("SLA", HORIZONTAL_ALIGNMENT_LEFT, -1,
		Theme90.FS_BODY).x + 8.0
	var dot_y := y + 17.0
	var right := r.position.x + r.size.x - 16.0
	var left := right - value.length() * 12.0
	while dot_x < left - 6.0:
		draw_rect(Rect2(dot_x, dot_y, 1, 1), Theme90.SHADE)
		dot_x += 4.0

	Theme90.text(self, Theme90.logo(), Vector2(left, y + 6), value, 12, col)


func _fmt(value: int) -> String:
	var neg := value < 0
	var digits := str(absi(value))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = " " + out
	return ("-" if neg else "") + out
