class_name StatusBar
extends Control
## Статус-строка 1280×60: шесть утопленных сегментов с гравированными
## подписями и крупными значениями. Канал краснеет >80 %, SLA — <40 %.
## Всплывающие +/− при изменении показателей.

var segments: Array[Dictionary] = []
var _floats: Array[Control] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	segments = [
		{"key": "tcp", "label": "TCP-КАНАЛЫ", "value": "2 / 3", "w": 148.0,
			"blocks": 6, "fill": 0.667},
		{"key": "channel", "label": "ЗАГРУЗКА КАНАЛА", "value": "45%", "w": 258.0,
			"blocks": 8, "fill": 0.45},
		{"key": "sla", "label": "SLA", "value": "168 / 200", "w": 176.0,
			"bar": true, "fill": 0.84},
		{"key": "buffer", "label": "БУФЕР ПРИЁМА", "value": "3 / 4", "w": 152.0,
			"blocks": 4, "fill": 0.75},
		{"key": "money", "label": "СЧЁТ", "value": "$ 1 240", "w": 158.0},
		{"key": "hour", "label": "ЧАС 3", "value": "03:42", "w": 352.0,
			"blocks": 16, "fill": 0.463, "sub": "СМЕНА 8 Ч · ПИК 12–14"},
	]


func _segment_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var gap := 4.0
	var total := 0.0
	for s in segments:
		total += float(s["w"])
	var avail := size.x - 16.0 - gap * (segments.size() - 1)
	var extra := maxf(0.0, avail - total)
	var x := 8.0
	for s in segments:
		var w: float = float(s["w"]) + extra * (float(s["w"]) / maxf(1.0, total))
		w = floorf(w)
		out.append(Rect2(x, 4, w, size.y - 8.0))
		x += w + gap
	return out


func _draw() -> void:
	Theme90.draw_bevel(self, Rect2(Vector2.ZERO, size), false, Theme90.BEVEL, Theme90.FACE)
	var f := Theme90.ui()
	var rects := _segment_rects()
	for i in segments.size():
		var s := segments[i]
		var r: Rect2 = rects[i]
		Theme90.draw_bevel(self, r, true, 2.0, Theme90.FACE)
		Theme90.text(self, f, Vector2(r.position.x + 8, r.position.y + 4), str(s["label"]), 10,
			Theme90.DARK, r.size.x - 16)
		var col := _value_color(s)
		Theme90.num_line(self, Vector2(r.position.x + 8, r.position.y + 19), str(s["value"]), 12, col)

		if s.has("blocks"):
			_draw_blocks(r, int(s["blocks"]), float(s.get("fill", 0.0)), _gauge_color(s))
		elif s.has("bar") and bool(s["bar"]):
			_draw_bar(r, float(s.get("fill", 0.0)), _gauge_color(s))

		if s.has("sub"):
			var sub := str(s["sub"])
			var f2 := Theme90.ui()
			var w := f2.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			Theme90.text(self, f2, Vector2(r.end.x - w - 8, r.position.y + 8), sub, 10, Theme90.DARK)


func _gauge_color(s: Dictionary) -> Color:
	match str(s["key"]):
		"channel":
			var fill := float(s.get("fill", 0.0))
			if fill > 0.8:
				return Theme90.ERROR
			if fill > 0.6:
				return Theme90.WARN
			return Theme90.NAVY
		"sla":
			var fill2 := float(s.get("fill", 1.0))
			if fill2 < 0.4:
				return Theme90.ERROR
			if fill2 < 0.6:
				return Theme90.WARN
			return Theme90.SUCCESS
		_:
			return Theme90.NAVY


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


func _draw_blocks(r: Rect2, n: int, fill: float, col: Color) -> void:
	if n <= 0:
		return
	var area_w := r.size.x - 16.0
	var bw := floorf((area_w - (n - 1) * 2.0) / n)
	var by := r.position.y + 40.0
	var filled := int(roundf(fill * n))
	for i in n:
		var br := Rect2(r.position.x + 8 + i * (bw + 2), by, bw, 8)
		if i < filled:
			draw_rect(br, col)
			draw_rect(Rect2(br.position, Vector2(br.size.x, 1)), col.lightened(0.45))
		else:
			draw_rect(br, Theme90.FACE_LO)
			draw_rect(Rect2(br.position, Vector2(br.size.x, 1)), Theme90.SHADE)


func _draw_bar(r: Rect2, fill: float, col: Color) -> void:
	var bar := Rect2(r.position.x + 8, r.position.y + 41, r.size.x - 16, 6)
	draw_rect(bar, Theme90.FACE_LO)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x, 1)), Theme90.SHADE)
	draw_rect(Rect2(bar.position.x, bar.position.y, floorf(bar.size.x * clampf(fill, 0.0, 1.0)),
		bar.size.y), col)


func set_metric(key: String, value: String, fill: float = -1.0) -> void:
	for s in segments:
		if str(s["key"]) == key:
			s["value"] = value
			if fill >= 0.0:
				s["fill"] = fill
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
	ft.position = Vector2(r.position.x + 12, r.position.y + 6)
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
		size = Vector2(w + 4, 16)
		for o in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
			Theme90.text(self, f, o, txt, 12, Theme90.INK)
		Theme90.text(self, f, Vector2.ZERO, txt, 12, col)
