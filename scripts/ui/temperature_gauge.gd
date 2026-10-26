class_name TemperatureGauge
extends Control
## Термометр «ЖАРА» в меню-баре: уровень, колба, деления, маркер и °C.
## Заменяет часы 03:42 и скрытую дату. Размер 216×18, высоту MenuBar (20)
## не меняет. В критическом уровне — штриховка, пульс подчёркивания и «КРИТ».
## Внутри °C доводится мягко (tau 0.25) и меняется только при смене целого.

const FLASK := Rect2(44.0, 7.0, 118.0, 6.0)
const BULB := Vector2(44.0, 10.0)
const BULB_R := 4.0
const UNDERLINE := Rect2(44.0, 15.0, 118.0, 2.0)
const TICKS := [84.0, 112.0, 138.0]
const RIGHT_X := 208.0
const DISPLAY_TAU := 0.25
const BREAKDOWN_MS := 500

var _heat := 0.0
var _disp := 0.0
var _level := 0
var _temp := 36
var _shown_temp := 36
var _pulse_t := 0.0
var _reduced := false
var _breakdown: Dictionary = {}
var _last_breakdown_ms := -1000
var _hovered := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_HELP
	custom_minimum_size = Vector2(216, 18)
	if size.x <= 0.0:
		size = Vector2(216, 18)
	mouse_entered.connect(func() -> void:
		_hovered = true
		_refresh_tooltip())
	mouse_exited.connect(func() -> void: _hovered = false)
	set_process(false)
	_refresh_tooltip()


func set_heat(heat: float, temp: int, level: int) -> void:
	var next_heat := clampf(heat, 0.0, 1.0)
	var next_level := clampi(level, 0, 3)
	var next_temp := clampi(temp, 36, 95)
	# Основной вызов идёт каждый кадр: не дёргаем перерисовку на шум < 0.005.
	if absf(next_heat - _heat) < 0.005 and next_level == _level \
			and next_temp == _temp:
		return
	_heat = next_heat
	_level = next_level
	_temp = next_temp
	if _heat <= 0.001 and _level <= 0:
		# Подготовка/полный покой: колба пустая, 36 °C без инерции.
		_disp = 0.0
		_shown_temp = 36
	elif _reduced:
		_disp = _heat
		_shown_temp = _display_temp()
	else:
		# Первый кадр после reset/prep: без ложного «нагрева» из прошлого.
		if _heat <= 0.001 and _disp < 0.001:
			_shown_temp = 36
	set_process(_needs_process())
	_refresh_tooltip_throttled()
	queue_redraw()


func set_reduced(value: bool) -> void:
	_reduced = bool(value)
	if _reduced:
		_disp = _heat
		_shown_temp = _display_temp()
		_pulse_t = 0.0
	set_process(_needs_process())
	queue_redraw()


func set_breakdown(values: Dictionary) -> void:
	# Ссылка без deep copy; строку тултипа собираем не чаще 2 Гц и по hover.
	if values == _breakdown:
		return
	_breakdown = values
	_refresh_tooltip_throttled()


func _refresh_tooltip_throttled() -> void:
	if not _hovered:
		return
	var now := Time.get_ticks_msec()
	if now - _last_breakdown_ms < BREAKDOWN_MS:
		return
	_last_breakdown_ms = now
	_refresh_tooltip()


func get_level_name() -> String:
	return Theme90.heat_level_name(_level)


func _needs_process() -> bool:
	if _reduced:
		return false
	return _level >= 3 or absf(_heat - _disp) > 0.002


func _display_temp() -> int:
	return clampi(int(roundf(36.0 + 59.0 * _disp)), 36, 95)


func _process(delta: float) -> void:
	_pulse_t += delta
	var diff := _heat - _disp
	if absf(diff) > 0.002:
		_disp += diff * UiMotion.k(delta, DISPLAY_TAU)
		var shown := _display_temp()
		if shown != _shown_temp:
			_shown_temp = shown
			_refresh_tooltip_throttled()
		queue_redraw()
	elif diff != 0.0:
		_disp = _heat
		var shown2 := _display_temp()
		if shown2 != _shown_temp:
			_shown_temp = shown2
			_refresh_tooltip_throttled()
		queue_redraw()
	elif _level >= 3:
		# Пульс критического подчёркивания.
		queue_redraw()
	if not _needs_process():
		set_process(false)


func _draw() -> void:
	var col := Theme90.heat_color(_level)
	var text_col := Theme90.heat_text_color(_level)
	var fill_w := 0.0
	if _disp > 0.001:
		fill_w = maxf(2.0, floorf(FLASK.size.x * _disp))

	# Колба: дорожка всегда, ртуть — только при нагреве.
	draw_style_box(Theme90.box(Theme90.PAPER_LO, Theme90.BORDER_SOFT, 3, 1), FLASK)
	if fill_w > 0.0:
		draw_style_box(Theme90.fill_box(col, 3), Rect2(FLASK.position, Vector2(fill_w, FLASK.size.y)))
		if _level >= 3:
			# Критическая штриховка поверх ртути.
			Theme90.draw_hatch(self,
				Rect2(FLASK.position, Vector2(fill_w, FLASK.size.y)),
				Color(1.0, 1.0, 1.0, 0.32), 3.0)

	# Деления на порогах 0.34 / 0.58 / 0.80.
	for tx in TICKS:
		draw_rect(Rect2(float(tx), FLASK.position.y - 2.0, 1.0, FLASK.size.y + 4.0),
			Color(Theme90.SHADE.r, Theme90.SHADE.g, Theme90.SHADE.b, 0.45))

	# Луковица: заполненная на нагреве, контур — в покое.
	if fill_w > 0.0:
		draw_circle(BULB, BULB_R, col)
	else:
		draw_arc(BULB, BULB_R - 0.5, 0.0, TAU, 18, col, 1.0)

	# Маркер текущей температуры.
	if _disp > 0.001:
		var mx := roundf(FLASK.position.x + FLASK.size.x * _disp)
		draw_rect(Rect2(mx, FLASK.position.y - 2.0, 1.0, FLASK.size.y + 4.0), text_col)

	# Подпись уровня и число справа.
	Theme90.text(self, Theme90.ui(), Vector2(6.0, 3.0),
		Theme90.heat_short_name(_level), 10, text_col)
	Theme90.num_right(self, RIGHT_X, 4.0, str(_shown_temp), 9, text_col, " °C", 9)

	# Критическое подчёркивание: пульс 1.0 с, в reduce — статично.
	if _level >= 3:
		var alpha := 0.7
		if not _reduced:
			alpha = 0.55 + 0.45 * (0.5 + 0.5 * sin(TAU * _pulse_t))
		draw_rect(UNDERLINE, Color(Theme90.ERROR.r, Theme90.ERROR.g,
			Theme90.ERROR.b, alpha))


func _refresh_tooltip() -> void:
	var title := "ТЕМПЕРАТУРА УЗЛА · %d °C · %s" % [_shown_temp, get_level_name()]
	if _breakdown.is_empty():
		tooltip_text = title
		return
	var sla := int(roundf(float(_breakdown.get("sla", 0.0))))
	var sla_cap := maxi(1, int(roundf(float(_breakdown.get("sla_cap", 60.0)))))
	var sla_pct := int(roundf(float(_breakdown.get("sla_ratio", 0.0)) * 100.0))
	var req_active := int(_breakdown.get("req_active", 0))
	var req_limit := maxi(1, int(_breakdown.get("req_limit", 1)))
	var recv_active := int(_breakdown.get("recv_active",
		_breakdown.get("buffer_used", 0)))
	var recv_limit := maxi(1, int(_breakdown.get("recv_limit",
		_breakdown.get("buffer_max", 1))))
	var attacks := int(_breakdown.get("attacks", 0))
	var tier := int(_breakdown.get("attack_tier", 0))
	var channel := int(roundf(float(_breakdown.get("channel", 0.0))))
	var channel_cap := maxi(1, int(roundf(float(_breakdown.get("channel_capacity", 10.0)))))
	var queued := int(_breakdown.get("queued", 0))
	var sending := int(_breakdown.get("sending", 0))
	var urgent := int(_breakdown.get("urgent", 0))
	var lines := PackedStringArray([
		title,
		"SLA %d/%d · %d%%" % [sla, sla_cap, sla_pct],
		"Отправка %d/%d · срочных %d" % [req_active, req_limit, urgent],
		"Приём %d/%d · атаки %d (тир %d)" % [recv_active, recv_limit, attacks, tier],
		"Канал %d/%d · очередь %d · отправка %d" % [channel, channel_cap, queued, sending],
	])
	tooltip_text = "\n".join(lines)
