class_name TutorialMascot
extends Control
## Маскот «БАЙТ» — дружелюбный робот-дискета 96×96, нарисованный кодом.
## Умеет показывать облачко с текстом и номер шага туториала.
##
##   mascot.show_message("Привет! Я БАЙТ. Начнём со смены?", 4.0)
##   mascot.set_step(1)
##   mascot.hide_message()
##
## Контрол не блокирует мышь. Высота подстраивается под облачко; робот
## прижат к нижнему левому углу, поэтому в игре его удобно ставить у края.

signal message_finished

const ROBOT := 96.0
const GAP := 10.0
const BUBBLE_W := 244.0

var is_visible := false
var step := 0
var bubble_width := BUBBLE_W
## Масштаб только робота (облачко остаётся читаемым). 1.0 — базовые 96 px.
var robot_scale := 1.0

var _text := ""
var _lines := PackedStringArray()
var _auto_hide := -1.0
var _timer := 0.0
var _t := 0.0
var _appear := 0.0
var _blink_t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = _robot_size()
	size = _robot_size()
	visible = false
	set_process(false)


func _robot_size() -> Vector2:
	var s := ROBOT * robot_scale
	return Vector2(s, s)


## Уменьшить/увеличить только робота, не трогая кегль облачка.
func set_robot_scale(value: float) -> void:
	robot_scale = clampf(value, 0.5, 2.0)
	custom_minimum_size = _robot_size()
	if not _text.is_empty():
		_relayout()
	else:
		size = _robot_size()
	queue_redraw()


## Показать облачко. seconds > 0 — спрятать автоматически.
func show_message(text: String, seconds: float = -1.0) -> void:
	_text = text
	is_visible = true
	visible = true
	_auto_hide = seconds
	_timer = 0.0
	_appear = 0.0
	_relayout()
	set_process(true)
	queue_redraw()


## Спрятать маскота целиком вместе с облачком.
func hide_message() -> void:
	is_visible = false
	visible = false
	_text = ""
	_lines = PackedStringArray()
	_auto_hide = -1.0
	_timer = 0.0
	_appear = 0.0
	size = _robot_size()
	custom_minimum_size = size
	set_process(false)
	queue_redraw()


## Номер шага: 0 — без шага; 1..N показывается чипом в облачке.
func set_step(index: int) -> void:
	step = maxi(0, index)
	if is_visible and not _text.is_empty():
		_relayout()
	queue_redraw()


func _relayout() -> void:
	var f := Theme90.ui()
	_lines = Theme90.wrap(f, _text, 12, bubble_width - 26.0, 4)
	var bh := _bubble_height()
	var rs := _robot_size()
	var total := maxf(rs.y, bh)
	size = Vector2(rs.x + GAP + bubble_width, total)
	custom_minimum_size = size


func _bubble_height() -> float:
	if _text.is_empty():
		return 0.0
	var pad_top := 25.0 if step > 0 else 12.0
	return maxf(56.0, pad_top + _lines.size() * 14.0 + 12.0)


func _process(delta: float) -> void:
	_t += delta
	_blink_t += delta
	if _blink_t > 3.4:
		_blink_t = 0.0
	if _appear < 1.0:
		_appear = minf(1.0, _appear + delta * 5.5)
	if _auto_hide > 0.0:
		_timer += delta
		if _timer >= _auto_hide:
			hide_message()
			message_finished.emit()
			return
	queue_redraw()


func _draw() -> void:
	var bob := sin(_t * 2.1) * 1.1
	var rs := _robot_size()
	var ry := size.y - rs.y + bob
	_draw_robot(ry)
	if not _text.is_empty() and _appear > 0.0:
		_draw_bubble(ry)


func _draw_robot(ry: float) -> void:
	var x := 0.0
	var y := roundf(ry)
	var outline := Color(Theme90.NAVY.r, Theme90.NAVY.g, Theme90.NAVY.b, 0.55)
	var rs := robot_scale
	draw_set_transform(Vector2(0, y - y * rs), 0.0, Vector2(rs, rs))

	# тень
	draw_style_box(Theme90.fill_box(Color(0, 0, 0, 0.07), 5),
		Rect2(x + 17, y + 87, 62, 7))

	# антенна
	draw_line(Vector2(x + 48, y + 15), Vector2(x + 48, y + 7), outline, 1.4)
	draw_circle(Vector2(x + 48, y + 5), 3.0, Theme90.ACCENT)

	# корпус
	draw_style_box(Theme90.box(Theme90.PAPER_HI, outline, 11, 1, Theme90.SHADOW),
		Rect2(x + 12, y + 14, 72, 72))

	# щель дискеты
	draw_style_box(Theme90.fill_box(Theme90.NAVY_DEEP, 2),
		Rect2(x + 36, y + 18, 24, 7))
	draw_rect(Rect2(x + 49, y + 19, 2, 5), Color(1, 1, 1, 0.35))

	# экран-лицо
	draw_style_box(Theme90.box(Theme90.ACCENT_PALE, Theme90.BORDER_SOFT, 7, 1),
		Rect2(x + 24, y + 31, 48, 30))
	# глаза с редким морганием
	var blink := _blink_t > 3.22 and _blink_t < 3.34
	if blink:
		draw_rect(Rect2(x + 39, y + 47, 5, 1.4), Theme90.NAVY)
		draw_rect(Rect2(x + 53, y + 47, 5, 1.4), Theme90.NAVY)
	else:
		draw_style_box(Theme90.fill_box(Theme90.NAVY, 2),
			Rect2(x + 39, y + 42, 5, 7))
		draw_style_box(Theme90.fill_box(Theme90.NAVY, 2),
			Rect2(x + 53, y + 42, 5, 7))
		draw_circle(Vector2(x + 40.5, y + 44), 1.0, Color(1, 1, 1, 0.8))
		draw_circle(Vector2(x + 54.5, y + 44), 1.0, Color(1, 1, 1, 0.8))
	# улыбка
	draw_arc(Vector2(x + 48, y + 51), 6.0, 0.20 * PI, 0.80 * PI, 10, Theme90.NAVY, 1.8)
	# щёки
	draw_circle(Vector2(x + 31, y + 55), 2.4, Color(Theme90.ERROR.r, Theme90.ERROR.g,
		Theme90.ERROR.b, 0.18))
	draw_circle(Vector2(x + 65, y + 55), 2.4, Color(Theme90.ERROR.r, Theme90.ERROR.g,
		Theme90.ERROR.b, 0.18))

	# подпись на корпусе
	var f := Theme90.ui()
	var label := "БАЙТ"
	var lw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	Theme90.text(self, f, Vector2(x + 48 - lw * 0.5, y + 66), label, 9, Theme90.NAVY)
	if step > 0 and _text.is_empty():
		draw_circle(Vector2(x + 72, y + 76), 6.0, Theme90.ACCENT)
		var sn := str(step)
		var sw := f.get_string_size(sn, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		Theme90.text(self, f, Vector2(x + 72 - sw * 0.5, y + 71), sn, 9, Theme90.WHITE)

	# руки и ноги
	draw_style_box(Theme90.box(Theme90.ACCENT_LIGHT, Color(0, 0, 0, 0), 4, 0),
		Rect2(x + 3, y + 42, 9, 22))
	draw_style_box(Theme90.box(Theme90.ACCENT_LIGHT, Color(0, 0, 0, 0), 4, 0),
		Rect2(x + 84, y + 42, 9, 22))
	draw_style_box(Theme90.fill_box(Theme90.NAVY, 3), Rect2(x + 23, y + 86, 18, 7))
	draw_style_box(Theme90.fill_box(Theme90.NAVY, 3), Rect2(x + 55, y + 86, 18, 7))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_bubble(ry: float) -> void:
	var a := _appear
	var bh := _bubble_height()
	var bx := _robot_size().x + GAP
	var by := roundf((size.y - bh) * 0.5)
	var rect := Rect2(bx, by, bubble_width, bh)
	var f := Theme90.ui()

	# хвостик к роботу
	var tail_y := by + bh * 0.5
	draw_colored_polygon(PackedVector2Array([
		Vector2(bx + 2, tail_y - 7), Vector2(bx - 8, tail_y), Vector2(bx + 2, tail_y + 7)]),
		Color(1, 1, 1, a))
	draw_line(Vector2(bx + 2, tail_y - 7), Vector2(bx - 8, tail_y),
		Color(Theme90.BORDER.r, Theme90.BORDER.g, Theme90.BORDER.b, a * 0.9), 1.0)
	draw_line(Vector2(bx - 8, tail_y), Vector2(bx + 2, tail_y + 7),
		Color(Theme90.BORDER.r, Theme90.BORDER.g, Theme90.BORDER.b, a * 0.9), 1.0)

	draw_style_box(Theme90.box(Color(1, 1, 1, a),
		Color(Theme90.BORDER.r, Theme90.BORDER.g, Theme90.BORDER.b, a), 8, 1,
		Color(0, 0, 0, 0.08 * a)), rect)

	var ty := by + (25.0 if step > 0 else 12.0)
	if step > 0:
		var chip := Rect2(bx + 12, by + 8, 40, 14)
		draw_style_box(Theme90.box(Color(Theme90.ACCENT_PALE.r, Theme90.ACCENT_PALE.g,
			Theme90.ACCENT_PALE.b, a), Color(0, 0, 0, 0), 3, 0), chip)
		Theme90.text(self, f, Vector2(chip.position.x + 7, chip.position.y + 2),
			"ШАГ %d" % step, 9, Theme90.NAVY, -1, HORIZONTAL_ALIGNMENT_LEFT)

	var ink := Color(Theme90.INK.r, Theme90.INK.g, Theme90.INK.b, a)
	for i in _lines.size():
		Theme90.text(self, f, Vector2(bx + 13, ty + i * 14), _lines[i], 12, ink,
			bubble_width - 26.0)
