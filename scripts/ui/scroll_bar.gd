class_name ScrollBar90
extends Control
## Вертикальный скроллбар 14 px: стрелки, дизеренный жёлоб и объёмный ползунок.

signal value_changed(value: float)

const W := 14.0
const ARROW := 14.0

@export var page := 100.0
@export var max_value := 100.0

var value := 0.0:
	set(v):
		var nv := clampf(v, 0.0, _limit())
		if is_equal_approx(nv, value):
			return
		value = nv
		queue_redraw()
		value_changed.emit(value)

var _dragging := false
var _drag_offset := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(W, 48)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_ARROW


func _limit() -> float:
	return maxf(0.0, max_value - page)


func set_metrics(p_page: float, p_max: float, p_value: float = -1.0) -> void:
	page = maxf(1.0, p_page)
	max_value = maxf(page, p_max)
	if p_value >= 0.0:
		value = clampf(p_value, 0.0, _limit())
	else:
		value = clampf(value, 0.0, _limit())
	queue_redraw()


func _thumb_rect() -> Rect2:
	var track_h := size.y - ARROW * 2.0
	var lim := _limit()
	var ratio := clampf(page / maxf(1.0, max_value), 0.0, 1.0)
	var th := clampf(track_h * ratio, 20.0, track_h)
	if lim <= 0.0:
		return Rect2(0, ARROW, W, track_h)
	var t := (value / lim) * (track_h - th)
	return Rect2(0, ARROW + t, W, th)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	# жёлоб
	draw_rect(Rect2(0, ARROW, W, size.y - ARROW * 2.0), Theme90.FACE)
	var y := ARROW
	while y < size.y - ARROW:
		draw_rect(Rect2(0, y, W, 1), Theme90.FACE_LO)
		y += 3
	draw_rect(Rect2(0, ARROW, 1, size.y - ARROW * 2.0), Theme90.SHADE)
	draw_rect(Rect2(W - 1, ARROW, 1, size.y - ARROW * 2.0), Theme90.FACE_HI)
	# стрелки
	var top := Rect2(0, 0, W, ARROW)
	var bot := Rect2(0, size.y - ARROW, W, ARROW)
	Theme90.draw_bevel(self, top, false, 1.0, Theme90.FACE)
	Theme90.draw_bevel(self, bot, false, 1.0, Theme90.FACE)
	Theme90.draw_arrow(self, top, 0, Theme90.INK)
	Theme90.draw_arrow(self, bot, 1, Theme90.INK)
	# ползунок
	var tb := _thumb_rect()
	Theme90.draw_bevel(self, tb, false, 2.0, Theme90.FACE)
	var gy := roundf(tb.position.y + tb.size.y * 0.5)
	for i in 3:
		draw_rect(Rect2(tb.position.x + 3, gy - 2 + i * 2, 8, 1), Theme90.SHADE)
	# размер не нужен — просто визуальная граница
	draw_rect(Rect2(0, 0, 1, size.y), Theme90.FACE_HI)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			value -= 32.0
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			value += 32.0
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if event.position.y < ARROW:
					value -= 24.0
					accept_event()
					return
				if event.position.y > size.y - ARROW:
					value += 24.0
					accept_event()
					return
				var tb := _thumb_rect()
				if tb.has_point(event.position):
					_dragging = true
					_drag_offset = event.position.y - tb.position.y
					accept_event()
				else:
					value += page if event.position.y > tb.position.y else -page
					accept_event()
			else:
				_dragging = false
				accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var track_h := size.y - ARROW * 2.0
		var tb := _thumb_rect()
		var lim := _limit()
		if lim > 0.0 and track_h - tb.size.y > 0.0:
			var t := clampf(event.position.y - _drag_offset - ARROW, 0.0, track_h - tb.size.y)
			value = (t / (track_h - tb.size.y)) * lim
		accept_event()
