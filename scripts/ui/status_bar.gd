class_name StatusBar
extends Control
## Строка состояния: одна светлая полоса, тонкие разделители и цветные шкалы.
## Без утопленных коробок и лишних подписей. Ключи сегментов прежние:
## tcp / channel / sla / buffer / money / hour.
##
## Над сегментом приёма лежит прозрачная зона подсказки: наведение показывает,
## что такое буфер и сколько места занято сейчас.

var segments: Array[Dictionary] = []
var _floats: Array[Control] = []
var _buffer_hint: Control = null
var _channel_hint: Control = null

## «ЖАРА»: пульс подчёркивания SLA и линия CRIT. Раскладку не меняет.
var _stress_heat := 0.0
var _stress_level := 0
var _stress_time := 0.0
var _reduced := false
var _last_sla_share := -1.0

const PAD := 14.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	segments = [
		{"key": "tcp", "label": "TCP", "value": "0 / 1", "w": 132.0, "fill": 0.0},
		{"key": "channel", "label": "КАНАЛ", "value": "0/10", "w": 222.0, "fill": 0.0,
			"danger": false},
		{"key": "sla", "label": "SLA", "value": "60 / 60", "w": 188.0, "fill": 1.0},
		{"key": "buffer", "label": "МЕСТО В ПРИЁМЕ", "value": "0 / 6", "w": 158.0, "fill": 0.0},
		{"key": "money", "label": "СЧЁТ", "value": "$ 50", "w": 176.0},
		{"key": "hour", "label": "СМЕНА", "value": "ЧАС 1 05:00", "w": 356.0, "fill": 0.0},
	]
	_buffer_hint = _make_hint("BufferHint", "buffer")
	_channel_hint = _make_hint("ChannelHint", "channel")
	resized.connect(_layout_hint)
	call_deferred("_layout_hint")
	set_process(false)


func set_stress(heat: float, level: int) -> void:
	var next_level := clampi(level, 0, 3)
	var sla_share := snappedf(_sla_fill(), 0.01)
	var changed := next_level != _stress_level \
		or not is_equal_approx(sla_share, _last_sla_share)
	_stress_heat = clampf(heat, 0.0, 1.0)
	_stress_level = next_level
	_last_sla_share = sla_share
	var active := _sla_fill() < 0.4 or _stress_level >= 3
	if not active:
		_stress_time = 0.0
	set_process(active and not _reduced)
	# Пульс сам перерисовывается в _process; здесь — только на смену состояния.
	if changed:
		queue_redraw()


func set_reduced(value: bool) -> void:
	_reduced = bool(value)
	if _reduced:
		_stress_time = 0.0
	set_process((_sla_fill() < 0.4 or _stress_level >= 3) and not _reduced)
	queue_redraw()


func _sla_fill() -> float:
	for s in segments:
		if str(s.get("key", "")) == "sla":
			return float(s.get("fill", 1.0))
	return 1.0


func _process(delta: float) -> void:
	_stress_time += delta
	queue_redraw()


func _make_hint(node_name: String, key: String) -> Control:
	var hint := Control.new()
	hint.name = node_name
	hint.mouse_filter = Control.MOUSE_FILTER_PASS
	hint.mouse_default_cursor_shape = Control.CURSOR_HELP
	hint.focus_mode = Control.FOCUS_NONE
	add_child(hint)
	hint.tooltip_text = _tooltip_for(key)
	return hint


func _metric_value(key: String) -> String:
	for s in segments:
		if str(s["key"]) == key:
			return str(s["value"])
	return ""


func _metric_pair(key: String) -> Vector2i:
	var raw := _metric_value(key)
	var parts := raw.split("/")
	var used := 0
	var cap := 0
	if parts.size() == 2:
		used = parts[0].strip_edges().to_int()
		cap = parts[1].strip_edges().to_int()
	return Vector2i(used, cap)


## Подсказка «что такое буфер» с текущим значением сегмента.
func _buffer_tooltip() -> String:
	var pair := _metric_pair("buffer")
	var used := pair.x
	var cap := pair.y
	var out := "Буфер (место в приёме) — сколько пакетов можно держать одновременно\n"
	out += "Сейчас: %d / %d" % [used, cap]
	if cap > 0:
		out += " · свободно %d" % maxi(0, cap - used)
		if used >= cap:
			out += "\nБуфер заполнен: новые пакеты не примутся, пока место не освободится."
	return out


## Подсказка канала (M19): почему передачи замедлились.
func _channel_tooltip() -> String:
	var pair := _metric_pair("channel")
	var out := "Канал — суммарный вес активных приёма и отправки.\n"
	out += "Сейчас: %d / %d" % [pair.x, pair.y]
	if pair.y > 0 and pair.x > pair.y:
		out += "\nКанал перегружен: передачи идут медленнее, пока нагрузка выше нормы."
	elif pair.y > 0 and pair.x == pair.y:
		out += "\nКанал загружен полностью: следующая передача начнёт замедлять остальные."
	else:
		out += "\nЧем больше файлов одновременно, тем медленнее каждая передача."
	return out


func _tooltip_for(key: String) -> String:
	if key == "channel":
		return _channel_tooltip()
	return _buffer_tooltip()


## Прозрачные зоны над сегментами: только подсказки, без отрисовки.
func _layout_hint() -> void:
	var rects := _segment_rects()
	for i in segments.size():
		var key := str(segments[i]["key"])
		var hint: Control = null
		if key == "buffer":
			hint = _buffer_hint
		elif key == "channel":
			hint = _channel_hint
		if hint == null or i >= rects.size():
			continue
		var r: Rect2 = rects[i]
		hint.position = Vector2(r.position.x, 0.0)
		hint.size = Vector2(r.size.x, size.y)
		hint.tooltip_text = _tooltip_for(key)


func _segment_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var total := 0.0
	for s in segments:
		total += float(s["w"])
	var avail := maxf(0.0, size.x - 16.0)
	var x := 8.0
	for s in segments:
		var w := floorf(avail * (float(s["w"]) / maxf(1.0, total)))
		out.append(Rect2(x, 0, w, size.y))
		x += w
	return out


func _draw() -> void:
	var full := Rect2(Vector2.ZERO, size)
	draw_rect(full, Theme90.PAPER_HI)
	draw_rect(Rect2(0, 0, size.x, 1), Theme90.BORDER_SOFT)
	draw_rect(Rect2(0, size.y - 1, size.x, 1), Color(0, 0, 0, 0.05))

	var f := Theme90.ui()
	var rects := _segment_rects()
	for i in segments.size():
		var s := segments[i]
		var r: Rect2 = rects[i]
		if i > 0:
			draw_rect(Rect2(r.position.x, 9, 1, size.y - 20), Theme90.HAIRLINE)
		Theme90.text(self, f, Vector2(r.position.x + PAD, 9), str(s["label"]),
			Theme90.FS_MICRO, Theme90.SHADE)
		if str(s["key"]) == "buffer":
			_draw_help_badge(f, r, str(s["label"]))
		var col := _value_color(s)
		var val := str(s["value"])
		var vf := f
		if _is_numeric(val):
			Theme90.num_line(self, Vector2(r.position.x + PAD, 23), val, 14, col)
		else:
			Theme90.text(self, vf, Vector2(r.position.x + PAD, 23), val, 14, col)

		if s.has("blocks") or s.has("bar") or s.has("fill"):
			var ratio := float(s.get("fill", 0.0))
			var bar := Rect2(r.position.x + PAD, size.y - 16.0, maxf(4.0, r.size.x - PAD * 2.0), 4.0)
			Theme90.draw_meter(self, bar, ratio, _gauge_color(s), Theme90.PAPER_LO)

	# «ЖАРА»: подчёркивание SLA при <40% и линия CRIT поверх полосы.
	var sla_idx := -1
	for i in segments.size():
		if str(segments[i].get("key", "")) == "sla":
			sla_idx = i
			break
	var sla_fill := _sla_fill()
	if sla_idx >= 0 and (sla_fill < 0.4 or _stress_level >= 3):
		var alpha := 0.7
		if not _reduced:
			var period := 1.0 if sla_fill < 0.2 else 1.2
			alpha = 0.55 + 0.45 * (0.5 + 0.5 * sin(TAU * _stress_time / period))
		var sr: Rect2 = rects[sla_idx]
		draw_rect(Rect2(sr.position.x + PAD, size.y - 9.0,
			maxf(4.0, sr.size.x - PAD * 2.0), 1.0),
			Color(Theme90.ERROR.r, Theme90.ERROR.g, Theme90.ERROR.b, alpha))
	if _stress_level >= 3:
		draw_rect(Rect2(0, 0, size.x, 1), Theme90.ERROR)


func _draw_help_badge(f: Font, r: Rect2, label: String) -> void:
	var lw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, Theme90.FS_MICRO).x
	var b := Rect2(r.position.x + PAD + lw + 6.0, 10.0, 9.0, 9.0)
	draw_style_box(Theme90.fill_box(Color(Theme90.SHADE.r, Theme90.SHADE.g,
		Theme90.SHADE.b, 0.13), 4), b)
	Theme90.text_vcenter(self, f, b, "?", 9, Theme90.SHADE, -1, HORIZONTAL_ALIGNMENT_CENTER)


func _is_numeric(s: String) -> bool:
	for ch in s:
		if ch.is_valid_int() or " /%$.,:".contains(ch):
			continue
		return false
	return true


func _gauge_color(s: Dictionary) -> Color:
	if bool(s.get("danger", false)):
		return Theme90.ERROR
	match str(s["key"]):
		"channel":
			var fill := float(s.get("fill", 0.0))
			if fill > 0.8:
				return Theme90.ERROR
			if fill > 0.6:
				return Theme90.WARN
			return Theme90.ACCENT
		"sla":
			var fill2 := float(s.get("fill", 1.0))
			if fill2 < 0.4:
				return Theme90.ERROR
			if fill2 < 0.6:
				return Theme90.WARN
			return Theme90.SUCCESS
		"money":
			return Theme90.SUCCESS
		"hour":
			return Theme90.ACCENT_LIGHT
		_:
			return Theme90.ACCENT


func _value_color(s: Dictionary) -> Color:
	if bool(s.get("danger", false)):
		return Theme90.ERROR
	match str(s["key"]):
		"channel":
			var fill := float(s.get("fill", 0.0))
			if fill > 0.8:
				return Theme90.ERROR
			if fill > 0.6:
				return Theme90.WARN
			return Theme90.INK
		"sla":
			var fill2 := float(s.get("fill", 1.0))
			if fill2 < 0.4:
				return Theme90.ERROR
			if fill2 < 0.6:
				return Theme90.WARN
			return Theme90.INK
		"money":
			return Theme90.SUCCESS
		"hour":
			return Theme90.NAVY
		_:
			return Theme90.INK


func set_metric(key: String, value: String, fill: float = -1.0,
		danger: bool = false) -> void:
	for s in segments:
		if str(s["key"]) == key:
			var new_fill := float(s.get("fill", 0.0)) if fill < 0.0 else fill
			if str(s["value"]) == value \
					and is_equal_approx(float(s.get("fill", 0.0)), new_fill) \
					and bool(s.get("danger", false)) == danger:
				return
			s["value"] = value
			s["fill"] = new_fill
			s["danger"] = danger
			if key == "buffer" and _buffer_hint != null:
				_buffer_hint.tooltip_text = _buffer_tooltip()
			elif key == "channel" and _channel_hint != null:
				_channel_hint.tooltip_text = _channel_tooltip()
			queue_redraw()
			return


func get_metric(key: String) -> Dictionary:
	for s in segments:
		if str(s["key"]) == key:
			return s
	return {}


## Всплывающая надпись над сегментом (+50, −10 и т.п.).
func flash(key: String, text: String, color: Color = Theme90.SUCCESS) -> void:
	var rects := _segment_rects()
	var idx := -1
	for i in segments.size():
		if str(segments[i]["key"]) == key:
			idx = i
			break
	if idx < 0:
		return
	var r: Rect2 = rects[idx]
	var ft := FloatNote.new(text, color)
	add_child(ft)
	ft.position = Vector2(r.position.x + PAD, 4)
	_floats.append(ft)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(ft, "position:y", ft.position.y - 22.0, 1.1)
	tw.tween_property(ft, "modulate:a", 0.0, 0.5).set_delay(0.55)
	tw.chain().tween_callback(func() -> void:
		_floats.erase(ft)
		ft.queue_free())


class FloatNote:
	extends Control
	var txt := ""
	var col := Color.WHITE

	func _init(p_text: String, p_color: Color) -> void:
		txt = p_text
		col = p_color
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var f := Theme90.ui()
		var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		size = Vector2(w + 10, 18)
		draw_style_box(Theme90.box(Color(1, 1, 1, 0.92), Theme90.BORDER_SOFT, 3, 1,
			Theme90.SHADOW), Rect2(Vector2.ZERO, size))
		Theme90.text(self, f, Vector2(5, 3), txt, 11, col)
