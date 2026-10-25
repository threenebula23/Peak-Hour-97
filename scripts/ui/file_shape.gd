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
	var pad := 3.0
	var icon := Rect2(lr.position + Vector2(pad, pad), Vector2(8, 8))
	draw_type_icon(ci, icon, file_type, base, alpha)

	var tx := lr.position.x + 13.0
	var tw := maxf(8.0, lr.size.x - 16.0)
	var ty := lr.position.y + 2.0
	if cell_min >= 72.0:
		var lines := Theme90.wrap(f, name, 10, tw, 2)
		for i in lines.size():
			Theme90.text(ci, f, Vector2(tx, ty + float(i) * 11.0), lines[i], 10,
				_with_alpha(ink, alpha), tw)
		var ey := ty + float(maxi(1, lines.size())) * 11.0 + 1.0
		if not ext_value.is_empty():
			Theme90.text(ci, f, Vector2(lr.position.x + pad, ey),
				Theme90.fit(f, ext_value, 10, lr.size.x - pad * 2.0), 10,
				_with_alpha(shade, alpha), lr.size.x - pad * 2.0)
	else:
		var line := Theme90.fit(f, name, 10, tw)
		Theme90.text(ci, f, Vector2(tx, ty), line, 10, _with_alpha(ink, alpha), tw)
		if not ext_value.is_empty():
			Theme90.text(ci, f, Vector2(lr.position.x + pad, ty + 12.0),
				Theme90.fit(f, ext_value, 10, lr.size.x - pad * 2.0), 10,
				_with_alpha(shade, alpha), lr.size.x - pad * 2.0)

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
	var has_name := cell_min >= 40.0 and not name.is_empty()
	var icon_size := clampf(cell_min * 0.34, 9.0, 18.0)
	var icon_y := lr.get_center().y - icon_size * 0.5
	if has_name:
		icon_y -= 6.0
	var icon := Rect2(lr.get_center().x - icon_size * 0.5, icon_y,
		icon_size, icon_size)
	draw_type_icon(ci, icon, file_type, base, alpha)
	if has_name:
		var col := Theme90.SHADE if locked else Theme90.INK
		Theme90.text(ci, f, Vector2(lr.position.x + 3.0, lr.end.y - 14.0),
			Theme90.fit(f, name, 10, lr.size.x - 6.0), 10, _with_alpha(col, alpha),
			lr.size.x - 6.0)


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
