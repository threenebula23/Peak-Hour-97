class_name ScrollBar90
extends Control
## Вертикальный скролл: тонкая дорожка, аккуратный скруглённый ползунок,
## едва заметные шевроны. Ширина 14 px сохранена для раскладки.

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
var _hover_thumb := false


func _ready() -> void:
	custom_minimum_size = Vector2(W, 48)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(func() -> void:
		_hover_thumb = false
		queue_redraw())


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


func _track_rect() -> Rect2:
	return Rect2(5, ARROW, 4, maxf(0.0, size.y - ARROW * 2.0))


func _thumb_rect() -> Rect2:
	var track_h := size.y - ARROW * 2.0
	var lim := _limit()
	var ratio := clampf(page / maxf(1.0, max_value), 0.0, 1.0)
	var th := clampf(track_h * ratio, 24.0, track_h)
	if lim <= 0.0:
		return Rect2(4, ARROW, 6, track_h)
	var t := (value / lim) * (track_h - th)
	return Rect2(4, ARROW + t, 6, th)


func _draw() -> void:
	if _limit() <= 0.0:
		# нечего прокручивать — не рисуем цветную полосу
		return
	var track := _track_rect()
	draw_style_box(Theme90.fill_box(Color(Theme90.SHADE.r, Theme90.SHADE.g, Theme90.SHADE.b,
		0.12), 2), track)
	# шевроны-подсказки, очень тихие
	Theme90.draw_chevron(self, Vector2(W * 0.5, ARROW * 0.5 - 1), 0,
		Color(Theme90.SHADE.r, Theme90.SHADE.g, Theme90.SHADE.b, 0.55), 2.6, 1.2)
	Theme90.draw_chevron(self, Vector2(W * 0.5, size.y - ARROW * 0.5 + 1), 1,
		Color(Theme90.SHADE.r, Theme90.SHADE.g, Theme90.SHADE.b, 0.55), 2.6, 1.2)

	var tb := _thumb_rect()
	var active := _hover_thumb or _dragging
	var col := Color(Theme90.ACCENT.r, Theme90.ACCENT.g, Theme90.ACCENT.b, 0.62) \
		if active else Color(Theme90.SHADE.r, Theme90.SHADE.g, Theme90.SHADE.b, 0.30)
	draw_style_box(Theme90.box(col, Color(0, 0, 0, 0), 3, 0), tb)
	if tb.size.y >= 20.0:
		var gy := roundf(tb.get_center().y)
		for i in 3:
			draw_rect(Rect2(tb.get_center().x - 1, gy - 3 + i * 3, 2, 1),
				Color(1, 1, 1, 0.65))


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
	elif event is InputEventMouseMotion:
		if _dragging:
			var track_h := size.y - ARROW * 2.0
			var tb := _thumb_rect()
			var lim := _limit()
			if lim > 0.0 and track_h - tb.size.y > 0.0:
				var t := clampf(event.position.y - _drag_offset - ARROW, 0.0,
					track_h - tb.size.y)
				value = (t / (track_h - tb.size.y)) * lim
			accept_event()
		else:
			var hover := _thumb_rect().grow(3.0).has_point(event.position)
			if hover != _hover_thumb:
				_hover_thumb = hover
				queue_redraw()
