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

const PAD := 14.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	segments = [
		{"key": "tcp", "label": "TCP", "value": "2 / 3", "w": 132.0, "fill": 0.667},
		{"key": "channel", "label": "КАНАЛ", "value": "45%", "w": 222.0, "fill": 0.45},
		{"key": "sla", "label": "SLA", "value": "128 / 200", "w": 188.0, "fill": 0.64},
		{"key": "buffer", "label": "МЕСТО В ПРИЁМЕ", "value": "3 / 4", "w": 158.0, "fill": 0.75},
		{"key": "money", "label": "СЧЁТ", "value": "$ 1 240", "w": 176.0},
		{"key": "hour", "label": "СМЕНА", "value": "ЧАС 3 03:42", "w": 356.0, "fill": 0.463},
	]
	_buffer_hint = Control.new()
	_buffer_hint.name = "BufferHint"
	_buffer_hint.mouse_filter = Control.MOUSE_FILTER_PASS
	_buffer_hint.mouse_default_cursor_shape = Control.CURSOR_HELP
	_buffer_hint.focus_mode = Control.FOCUS_NONE
	add_child(_buffer_hint)
	resized.connect(_layout_hint)
	call_deferred("_layout_hint")


## Подсказка «что такое буфер» с текущим значением сегмента.
func _buffer_tooltip() -> String:
	var raw := ""
	for s in segments:
		if str(s["key"]) == "buffer":
			raw = str(s["value"])
			break
	var parts := raw.split("/")
	var used := 0
	var cap := 0
	if parts.size() == 2:
		used = parts[0].strip_edges().to_int()
		cap = parts[1].strip_edges().to_int()
	var out := "Буфер (место в приёме) — сколько пакетов можно держать одновременно\n"
	out += "Сейчас: %d / %d" % [used, cap]
	if cap > 0:
		out += " · свободно %d" % maxi(0, cap - used)
		if used >= cap:
			out += "\nБуфер заполнен: новые пакеты не примутся, пока место не освободится."
	return out


## Прозрачная зона над сегментом буфера: только подсказка, без отрисовки.
func _layout_hint() -> void:
	if _buffer_hint == null:
		return
	var idx := -1
	for i in segments.size():
		if str(segments[i]["key"]) == "buffer":
			idx = i
			break
	if idx < 0:
		return
	var rects := _segment_rects()
	if idx >= rects.size():
		return
	var r: Rect2 = rects[idx]
	_buffer_hint.position = Vector2(r.position.x, 0.0)
	_buffer_hint.size = Vector2(r.size.x, size.y)
	_buffer_hint.tooltip_text = _buffer_tooltip()


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


func set_metric(key: String, value: String, fill: float = -1.0) -> void:
	for s in segments:
		if str(s["key"]) == key:
			s["value"] = value
			if fill >= 0.0:
				s["fill"] = fill
			if key == "buffer" and _buffer_hint != null:
				_buffer_hint.tooltip_text = _buffer_tooltip()
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
