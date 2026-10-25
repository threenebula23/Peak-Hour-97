class_name FileShape
extends Control
## Одна фигура-полимино: превью drag, карточка пакета, стол сортировки.
##
## Рисуется без дочерних узлов: заливка занятых клеток, ОДИН внешний контур
## 2 px (внутренние границы не рисуются), подпись в верхней левой ЗАНЯТОЙ
## клетке. Тот же painter (`paint`) использует FileGrid — так превью и сетка
## выглядят одинаково.
##
## Режимы:
##   shape  — полимино по shape_id/rotation (для сетки и стола);
##   square — одна клетка 1×1 (для карточки запроса: файл = квадрат).
##
## ВАЖНО: global class cache при `--script` может быть пустым, поэтому
## FileRegistry подключаем через preload.

const FR = preload("res://scripts/core/file_registry.gd")

const GAP := 0.0

var file_type: String = "text"
var shape_id: String = "O1"
var shape_rotation: int = 0
var file_name: String = ""
var ext: String = ""
var cell_size: float = 48.0
var mode: String = "shape"
var state: String = "stored"
var selected: bool = false
var hovered: bool = false
var show_label: bool = true
var alpha: float = 1.0
## Непрозрачная замена контура/заливки (ghost, ошибки). Alpha 0 — обычные.
var outline_override: Color = Color(0, 0, 0, 0)
var fill_override: Color = Color(0, 0, 0, 0)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sync_size()


func setup(p_type: String, p_shape_id: String, p_rotation: int, p_name: String,
		p_ext: String, p_cell: float) -> void:
	file_type = p_type
	shape_id = p_shape_id if not p_shape_id.is_empty() else "O1"
	shape_rotation = posmod(int(p_rotation), 4)
	file_name = p_name
	ext = p_ext
	cell_size = maxf(8.0, p_cell)
	_sync_size()


func set_mode(value: String) -> void:
	var next := "square" if value == "square" else "shape"
	if mode == next:
		return
	mode = next
	_sync_size()
	queue_redraw()


func get_mode() -> String:
	return mode


func set_state(value: String) -> void:
	state = value
	queue_redraw()


func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()


func resolved_cells() -> Array:
	if mode == "square":
		return [Vector2i.ZERO]
	return FR.shape_cells(shape_id, shape_rotation)


func _sync_size() -> void:
	var cells := resolved_cells()
	var b := FR.shape_bounds(cells)
	var w := maxf(1.0, float(b.x) * cell_size)
	var h := maxf(1.0, float(b.y) * cell_size)
	custom_minimum_size = Vector2(w, h)
	size = custom_minimum_size


func _draw() -> void:
	var cells := resolved_cells()
	paint(self, Vector2.ZERO, cells, cell_size, {
		"type": file_type,
		"name": file_name,
		"ext": ext,
		"state": state,
		"selected": selected,
		"hovered": hovered,
		"alpha": alpha,
		"show_label": show_label,
		"gap": GAP,
		"square": mode == "square",
		"outline": outline_override,
		"fill": fill_override,
	})


# --- палитра ---------------------------------------------------------------

static func type_color(file_type: String) -> Color:
	match file_type:
		"sound":
			return Theme90.WARN
		"photo":
			return Theme90.SUCCESS
		"video":
			return Theme90.ERROR
		_:
			return Theme90.ACCENT


static func ext_color(file_type: String, ext_value: String) -> Color:
	var cat := Theme90.ext_category(ext_value)
	if not cat.is_empty():
		return Theme90.ext_color(cat)
	return type_color(file_type)


static func _with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)


# --- геометрия -------------------------------------------------------------

## Рёбра внешнего контура в координатах клеток. Каждое ребро — словарь
## {"from": Vector2i-клетка, "dir": Vector2i-направление наружу}.
## Внутренние границы (сосед занят) не попадают в список.
static func outer_edges(cells: Array) -> Array:
	var out: Array = []
	var occupied := {}
	for c in cells:
		occupied[Vector2i(c)] = true
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1),
	]
	for c in cells:
		var p := Vector2i(c)
		for d in dirs:
			if not occupied.has(p + d):
				out.append({"from": p, "dir": d})
	return out


static func _cell_vec(value) -> Vector2:
	if value is Vector2:
		return value
	var s := float(value)
	return Vector2(s, s)


## Прямоугольник клетки в пикселях. gap расширяет заливку на половину зазора,
## чтобы соседние клетки одной фигуры сливались в цельное полимино.
## cell_px — float (квадрат) или Vector2 (прямоугольная клетка стола).
static func cell_pixel_rect(pos: Vector2, cell: Vector2i, cell_px, gap: float) -> Rect2:
	var cs := _cell_vec(cell_px)
	var step := cs + Vector2(gap, gap)
	var p := pos + Vector2(float(cell.x) * step.x, float(cell.y) * step.y)
	if gap > 0.0:
		var e := gap * 0.5
		return Rect2(p - Vector2(e, e), cs + Vector2(gap, gap))
	return Rect2(p, cs)


## Отрезок внешнего ребра в пикселях.
static func edge_segment(pos: Vector2, from_cell: Vector2i, dir: Vector2i,
		cell_px, gap: float) -> PackedVector2Array:
	var cs := _cell_vec(cell_px)
	var step := cs + Vector2(gap, gap)
	var p := pos + Vector2(float(from_cell.x) * step.x, float(from_cell.y) * step.y)
	var e := gap * 0.5 if gap > 0.0 else 0.0
	var l := p.x - e
	var t := p.y - e
	var r := p.x + cs.x + e
	var b := p.y + cs.y + e
	if dir == Vector2i(1, 0):
		return PackedVector2Array([Vector2(r, t), Vector2(r, b)])
	if dir == Vector2i(-1, 0):
		return PackedVector2Array([Vector2(l, t), Vector2(l, b)])
	if dir == Vector2i(0, 1):
		return PackedVector2Array([Vector2(l, b), Vector2(r, b)])
	return PackedVector2Array([Vector2(l, t), Vector2(r, t)])


# --- painter ---------------------------------------------------------------

## Рисует фигуру. opts: type, name, ext, state, selected, hovered, alpha,
## show_label, gap, square, outline, fill.
static func paint(ci: CanvasItem, pos: Vector2, cells: Array, cell_px,
		opts: Dictionary = {}) -> void:
	var cs := _cell_vec(cell_px)
	if cells.is_empty() or cs.x <= 0.0 or cs.y <= 0.0:
		return
	var file_type := str(opts.get("type", "text"))
	var name := str(opts.get("name", ""))
	var ext_value := str(opts.get("ext", ""))
	var state := str(opts.get("state", "stored"))
	var selected := bool(opts.get("selected", false))
	var hovered := bool(opts.get("hovered", false))
	var alpha := clampf(float(opts.get("alpha", 1.0)), 0.0, 1.0)
	if alpha <= 0.01:
		return
	var show_label := bool(opts.get("show_label", true))
	var gap := float(opts.get("gap", 0.0))
	var square := bool(opts.get("square", false))
	var outline_override: Color = opts.get("outline", Color(0, 0, 0, 0))
	var fill_override: Color = opts.get("fill", Color(0, 0, 0, 0))

	var base := type_color(file_type)
	var locked := state == "locked"
	var bad := state == "malicious" or state == "failed"
	if locked:
		base = base.lerp(Theme90.SHADE, 0.55)

	var fill := fill_override if fill_override.a > 0.0 else _with_alpha(base, 0.22)
	if hovered and fill_override.a <= 0.0:
		fill = _with_alpha(base, 0.30)
	fill.a *= alpha

	var outline := outline_override
	if outline.a <= 0.0:
		if selected:
			outline = Theme90.ACCENT
		elif bad:
			outline = Theme90.ERROR
		elif locked:
			outline = Theme90.SHADE
		else:
			outline = base
	outline.a *= alpha
	var outline_w := 2.6 if selected else 2.0

	# 1) заливка занятых клеток (без внутренних швов)
	for c in cells:
		var cell := Vector2i(c)
		var r := cell_pixel_rect(pos, cell, cell_px, gap)
		ci.draw_rect(r, fill)
		if hovered and fill_override.a <= 0.0:
			ci.draw_rect(r, Color(1, 1, 1, 0.09 * alpha))

	# 2) один внешний контур
	for edge in outer_edges(cells):
		var seg := edge_segment(pos, Vector2i(edge["from"]), Vector2i(edge["dir"]),
			cell_px, gap)
		ci.draw_line(seg[0], seg[1], outline, outline_w, false)

	# 3) тонкая красная рамка вокруг bbox для malicious/failed
	if bad:
		var b := FR.shape_bounds(cells)
		var step := cs + Vector2(gap, gap)
		var frame := Rect2(pos - Vector2(2, 2),
			Vector2(float(b.x) * step.x - gap + 4.0, float(b.y) * step.y - gap + 4.0))
		ci.draw_rect(frame, _with_alpha(Theme90.ERROR, 0.55 * alpha), false, 1.0)

	if not show_label:
		return
	var lbl := FR.label_cell(cells)
	if square:
		_paint_square_label(ci, pos, lbl, cs, gap, base, file_type, name, alpha, locked)
	else:
		_paint_cell_label(ci, pos, lbl, cs, gap, base, file_type, name, ext_value,
			alpha, locked, state)


## Кегль подписи файла по размеру клетки: 12 / 14 / 16 px.
## Используется и в сетке, и в карточке запроса (square), чтобы имена
## не были микроскопическими на больших клетках.
## Это БАЗОВЫЙ кегль: если имя не влезает в отведённые строки, painter
## уменьшает его на 1 px (не ниже 11) прежде чем обрезать многоточием.
static func label_font_size(cell_px: float) -> int:
	if cell_px > 96.0:
		return 16
	if cell_px >= 72.0:
		return 14
	return 12


## Сколько строк имени даёт клетка: 3 при >= 88, 2 при 72–87, 1 ниже 72.
## Больше строк — длинные имена читаются целиком, а не «запас_е…».
static func label_max_lines(cell_px: float) -> int:
	if cell_px >= 88.0:
		return 3
	if cell_px >= 72.0:
		return 2
	return 1


## Перенос по словам с РАЗНОЙ шириной строк: первая уже (в ней иконка),
## последующие занимают всю клетку за вычетом полей.
static func _wrap_name(f: Font, text: String, size: int, first_w: float,
		rest_w: float) -> PackedStringArray:
	var out := PackedStringArray()
	if text.is_empty():
		return out
	var cur := ""
	for raw in text.split(" ", false):
		var word := str(raw)
		var width := first_w if out.is_empty() else rest_w
		var cand := word if cur.is_empty() else cur + " " + word
		if f.get_string_size(cand, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
			cur = cand
		else:
			if not cur.is_empty():
				out.append(cur)
			cur = word
	if not cur.is_empty():
		out.append(cur)
	return out


## Имя целиком помещается в max_lines при данном кегле (без многоточия)?
static func _name_fits(f: Font, text: String, size: int, first_w: float,
		rest_w: float, max_lines: int) -> bool:
	var lines := _wrap_name(f, text, size, first_w, rest_w)
	if lines.size() > max_lines:
		return false
	for i in lines.size():
		var width := first_w if i == 0 else rest_w
		if f.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
			return false
	return true


## Самый крупный кегль от базового, при котором имя ещё влезает целиком.
## Ниже 11 px не опускаемся: лучше многоточие, чем нечитаемая строка.
static func name_font_size(cell_px: float, text: String, first_w: float,
		rest_w: float, max_lines: int) -> int:
	return _max_fit_size(Theme90.ui(), text, cell_px, first_w, rest_w, max_lines)


static func _max_fit_size(f: Font, text: String, cell_px: float, first_w: float,
		rest_w: float, max_lines: int) -> int:
	var base := label_font_size(cell_px)
	var lo := mini(11, base)
	for size in range(base, lo - 1, -1):
		if _name_fits(f, text, size, first_w, rest_w, max_lines):
			return size
	return lo


## Готовые строки для отрисовки. Если имя не влезает — последняя строка
## получает хвост и многоточие; отдельные слишком длинные слова режутся
## по ширине своей строки.
static func _build_lines(f: Font, text: String, size: int, first_w: float,
		rest_w: float, max_lines: int) -> PackedStringArray:
	var lines := _wrap_name(f, text, size, first_w, rest_w)
	if lines.size() > max_lines:
		var kept := PackedStringArray()
		for i in max_lines:
			kept.append(lines[i])
		kept[max_lines - 1] = Theme90.fit(f,
			kept[max_lines - 1] + " " + lines[max_lines], size,
			first_w if max_lines == 1 else rest_w)
		lines = kept
	for i in lines.size():
		var lw := first_w if i == 0 else rest_w
		if f.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > lw:
			lines[i] = Theme90.fit(f, lines[i], size, lw)
	return lines


## Сколько символов имени реально видно (без многоточий и пробелов).
static func _visible_chars(lines: PackedStringArray) -> int:
	var total := 0
	for line in lines:
		total += str(line).replace("…", "").replace(" ", "").length()
	return total


## Раскладка подписи. Обычно иконка стоит в верхнем левом углу, а первая
## строка начинается справа от неё (icon_inline = true).
## Если первое слово в такую строку не помещается даже после сжатия кегля,
## текст переносится ПОД иконку и все строки получают полную ширину:
## иначе длинное слово теряло бы начало («запас_енер…» вместо имени целиком).
## Возвращает {"size": int, "lines": PackedStringArray, "icon_inline": bool}.
static func _label_layout(f: Font, name: String, cell_px: float, first_w: float,
		rest_w: float, max_lines: int) -> Dictionary:
	var inline_size := name_font_size(cell_px, name, first_w, rest_w, max_lines)
	if _name_fits(f, name, inline_size, first_w, rest_w, max_lines):
		return {"size": inline_size, "icon_inline": true,
			"lines": _build_lines(f, name, inline_size, first_w, rest_w, max_lines)}
	var below_size := _max_fit_size(f, name, cell_px, rest_w, rest_w, max_lines)
	if _name_fits(f, name, below_size, rest_w, rest_w, max_lines):
		return {"size": below_size, "icon_inline": false,
			"lines": _build_lines(f, name, below_size, rest_w, rest_w, max_lines)}
	# Не влезает ни так, ни так — оставляем раскладку, где видно больше имени.
	var inline_lines := _build_lines(f, name, inline_size, first_w, rest_w, max_lines)
	var below_lines := _build_lines(f, name, below_size, rest_w, rest_w, max_lines)
	var below_better := below_size > inline_size \
		or (below_size == inline_size
			and _visible_chars(below_lines) > _visible_chars(inline_lines))
	if below_better:
		return {"size": below_size, "icon_inline": false, "lines": below_lines}
	return {"size": inline_size, "icon_inline": true, "lines": inline_lines}


static func _paint_cell_label(ci: CanvasItem, pos: Vector2, lbl: Vector2i,
		cs: Vector2, gap: float, base: Color, file_type: String, name: String,
		ext_value: String, alpha: float, locked: bool, state: String) -> void:
	var step := cs + Vector2(gap, gap)
	var lr := Rect2(pos + Vector2(float(lbl.x) * step.x, float(lbl.y) * step.y), cs)
	if lr.size.x < 16.0 or lr.size.y < 16.0:
		return
	var cell_min := minf(cs.x, cs.y)
	var f := Theme90.ui()
	var ink := Theme90.SHADE if locked else Theme90.INK
	var shade := Theme90.SHADE
	# Поля: строки после первой идут во всю ширину клетки (cell − 10 px).
	const PAD := 5.0
	var base_size := label_font_size(cell_min)
	var ext_size := maxi(9, base_size - 3)
	var max_lines := label_max_lines(cell_min)
	var icon_size := clampf(cs.x * 0.16, 10.0, 16.0)
	var ty := lr.position.y + 3.0
	# Иконка — в верхнем левом углу. Первая строка идёт справа от неё,
	# остальные — от левого поля, во всю ширину; если имя не влезает рядом
	# с иконкой, весь текст уходит под неё (см. _label_layout).
	var text_x := lr.position.x + PAD
	var first_x := text_x + icon_size + 2.0
	var badge_room := 10.0 if state == "attached" or state == "malicious" \
		or state == "failed" else 0.0
	var first_w := maxf(8.0, lr.end.x - first_x - PAD - badge_room)
	var rest_w := maxf(8.0, lr.size.x - PAD * 2.0)
	var layout := _label_layout(f, name, cell_min, first_w, rest_w, max_lines)
	var name_size: int = int(layout["size"])
	var lines: PackedStringArray = layout["lines"]
	var icon_inline: bool = bool(layout["icon_inline"])
	var line_h := float(name_size) + 1.0
	# Строка с иконкой занимает не меньше самой иконки — иначе вторая строка
	# наехала бы на неё.
	var first_h := maxf(line_h, icon_size + 2.0)
	var text_top := ty if icon_inline else ty + first_h
	var icon := Rect2(Vector2(text_x, ty + maxf(0.0, (line_h - icon_size) * 0.5))
		.round(), Vector2(icon_size, icon_size))
	if not Theme90.draw_file_icon(ci, icon, file_type, _with_alpha(Color.WHITE, alpha)):
		draw_type_icon(ci, icon, file_type, base, alpha)

	var last_bottom := ty
	for i in lines.size():
		var lx := text_x
		var lw := rest_w
		var ly := text_top + float(i) * line_h
		if icon_inline:
			if i == 0:
				lx = first_x
				lw = first_w
				ly = ty
			else:
				ly = ty + first_h + float(i - 1) * line_h
		Theme90.text(ci, f, Vector2(lx, ly), lines[i], name_size,
			_with_alpha(ink, alpha), lw)
		last_bottom = ly + line_h

	if not ext_value.is_empty():
		var ey := (last_bottom if not lines.is_empty() else ty) + 1.0
		# Расширение — отдельной мелкой строкой, если в клетке осталось место.
		if ey + float(ext_size) + 2.0 <= lr.end.y:
			Theme90.text(ci, f, Vector2(text_x, ey),
				Theme90.fit(f, ext_value, ext_size, rest_w),
				ext_size, _with_alpha(shade, alpha), rest_w)

	# состояния в верхнем правом углу label-клетки
	var badge := Vector2(lr.end.x - 8.0, lr.position.y + 8.0)
	if state == "attached":
		Theme90.draw_check_badge(ci, badge, 5.5, _with_alpha(Theme90.SUCCESS, alpha),
			_with_alpha(Theme90.WHITE, alpha))
	elif state == "malicious" or state == "failed":
		ci.draw_circle(badge, 5.5, _with_alpha(Theme90.ERROR, alpha))
		Theme90.text_vcenter(ci, f, Rect2(badge.x - 5.0, badge.y - 6.0, 10.0, 12.0),
			"!", 10, _with_alpha(Theme90.WHITE, alpha), 10.0, HORIZONTAL_ALIGNMENT_CENTER)
	elif locked:
		Theme90.draw_lock_icon(ci, Vector2(lr.end.x - 12.0, lr.end.y - 11.0),
			_with_alpha(Theme90.SHADE, alpha))


static func _paint_square_label(ci: CanvasItem, pos: Vector2, lbl: Vector2i,
		cs: Vector2, gap: float, base: Color, file_type: String, name: String,
		alpha: float, locked: bool) -> void:
	var step := cs + Vector2(gap, gap)
	var lr := Rect2(pos + Vector2(float(lbl.x) * step.x, float(lbl.y) * step.y), cs)
	var f := Theme90.ui()
	var cell_min := minf(cs.x, cs.y)
	var name_size := label_font_size(cell_min)
	var has_name := cell_min >= 40.0 and not name.is_empty()
	var icon_size := clampf(cell_min * 0.30, 14.0, 18.0)
	var name_y := lr.end.y - float(name_size) - 4.0
	var icon := Rect2(lr.get_center().x - icon_size * 0.5,
		lr.get_center().y - icon_size * 0.5, icon_size, icon_size)
	if has_name:
		# Иконка слева от имени, выровнена по строке подписи.
		icon = Rect2(lr.position.x + 3.0,
			name_y + (float(name_size) - icon_size) * 0.5,
			icon_size, icon_size)
	if not Theme90.draw_file_icon(ci, icon, file_type, _with_alpha(Color.WHITE, alpha)):
		draw_type_icon(ci, icon, file_type, base, alpha)
	if has_name:
		var col := Theme90.SHADE if locked else Theme90.INK
		var nx := icon.end.x + 2.0
		Theme90.text(ci, f, Vector2(nx, name_y),
			Theme90.fit(f, name, name_size, lr.end.x - nx - 3.0), name_size,
			_with_alpha(col, alpha), lr.end.x - nx - 3.0)


## 8×8 иконка типа: строки (text), волна (sound), горы (photo), play (video).
static func draw_type_icon(ci: CanvasItem, rect: Rect2, file_type: String,
		color: Color, alpha: float = 1.0) -> void:
	var s := minf(rect.size.x, rect.size.y)
	if s <= 0.0:
		return
	var r := Rect2(rect.position.round(), Vector2(s, s))
	var tint := _with_alpha(color, 0.18 * alpha)
	ci.draw_style_box(Theme90.fill_box(tint, 2), r)
	var c := _with_alpha(color, alpha)
	var x := r.position.x
	var y := r.position.y
	match file_type:
		"sound":
			var pts := PackedVector2Array([
				Vector2(x + 1.0, y + s * 0.55),
				Vector2(x + s * 0.30, y + s * 0.25),
				Vector2(x + s * 0.52, y + s * 0.75),
				Vector2(x + s * 0.74, y + s * 0.38),
				Vector2(x + s - 1.0, y + s * 0.55),
			])
			ci.draw_polyline(pts, c, 1.0, false)
		"photo":
			var pts := PackedVector2Array([
				Vector2(x + 1.0, y + s - 2.0),
				Vector2(x + s * 0.34, y + s * 0.30),
				Vector2(x + s * 0.56, y + s * 0.62),
				Vector2(x + s * 0.72, y + s * 0.44),
				Vector2(x + s - 1.0, y + s - 2.0),
			])
			ci.draw_polyline(pts, c, 1.0, false)
			ci.draw_circle(Vector2(x + s * 0.72, y + s * 0.26), 1.2, c)
		"video":
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(x + s * 0.30, y + s * 0.18),
				Vector2(x + s * 0.30, y + s * 0.82),
				Vector2(x + s * 0.82, y + s * 0.50),
			]), c)
		_:
			for i in 3:
				var ly := y + s * (0.30 + float(i) * 0.20)
				ci.draw_line(Vector2(x + s * 0.22, ly),
					Vector2(x + s * (0.78 - float(i) * 0.10), ly), c, 1.0, false)
