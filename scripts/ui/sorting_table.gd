class_name SortingTable
extends Control
## Стол сортировки: сетка 4×6 (24 клетки) в правой колонке подготовки.
## Читает Game.registry.table_files(); drag folder→table, table→folder,
## table→table. Файл на столе нельзя прикрепить к запросу (это проверяет
## RequestCard), а переполненный стол отклоняет drop тостом «СТОЛ ЗАПОЛНЕН».
##
## Рисуется тем же painter'ом FileShape, что и FileGrid; дочерних узлов на
## файл нет.

signal file_dropped(payload: Dictionary)
signal table_changed
signal drop_rejected(reason: String)
signal file_selected(id: String)
signal selection_changed(id: String)
signal context_requested(id: String)

const FR = preload("res://scripts/core/file_registry.gd")
const FG = preload("res://scripts/ui/file_grid.gd")
const FILE_SHAPE = preload("res://scripts/ui/file_shape.gd")
const DRAG_CONTROLLER = preload("res://scripts/ui/drag_controller.gd")

const GAP := 6.0
const CELL_MIN := 56.0
const CELL_MAX := 110.0
## Внутренний отступ сетки: FileShape расширяет заливку/контур на GAP/2 + 1.3 px
## (выделение 2.6) за границу клетки, ghost рисует dashed-box +2.6 px. Без
## запаса clip Control срезал левый/правый край фигуры в клетках (0,*) и
## (cols-1,*). Аналог FileGrid.GRID_PAD.
const GRID_PAD := 5.0
## Нижний резерв: футер стола занимает нижние 16 px (заливка + hairline +
## текст), а фигура/ghost выступают за клетку на GAP/2 + 1.3 px. Без резерва
## нижний ряд и dashed-box ghost уходили под футер и срезались clip_contents.
## Аналог FileGrid.GRID_BOTTOM.
const GRID_BOTTOM := 20.0
const DEFAULT_COLS := 4
const DEFAULT_ROWS := 6

var drag_controller: Node = null

var _registry = null
var _files: Array = []
var _by_id: Dictionary = {}
var _cells_owner: Dictionary = {}
var _cols: int = DEFAULT_COLS
var _rows: int = DEFAULT_ROWS
var _cell: Vector2 = Vector2(CELL_MAX, CELL_MAX)
var _grid_origin: Vector2 = Vector2.ZERO

var _selected: String = ""
var _hover_id: String = ""
var _legacy_files: Array = []

var _drop_active: bool = false
var _drag_key: String = ""
var _drag_payload: Dictionary = {}
var _drag_rotation: int = 0
var _drag_active: bool = false
var _last_drop_pos: Vector2 = Vector2.ZERO
var _ghost_cells: Array = []
var _ghost_origin: Vector2i = Vector2i(-1, -1)
var _ghost_target: Vector2i = Vector2i(-1, -1)
var _ghost_rotation: int = 0
var _ghost_ok: bool = false
var _ghost_auto: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	mouse_exited.connect(_on_mouse_exited)
	resized.connect(_on_resized)
	_bind_registry()
	refresh()


# --- API -------------------------------------------------------------------

## data == bool → видимость; data == Array → legacy-снимок; иначе refresh().
func set_visible_data(data = null) -> void:
	if data is bool:
		visible = bool(data)
		return
	if data is Array:
		var arr: Array = data
		_legacy_files = arr.duplicate(true)
	refresh()


func refresh() -> void:
	_bind_registry()
	_files.clear()
	_by_id.clear()
	_cells_owner.clear()
	_cols = DEFAULT_COLS
	_rows = DEFAULT_ROWS
	if _registry != null:
		_cols = maxi(1, int(_registry.table_cols))
		_rows = maxi(1, int(_registry.table_rows))
		for file in _registry.table_files():
			_files.append(file)
			_by_id[str(file.id)] = file
			var cells := FR.shape_cells(str(file.shape_id), int(file.rotation))
			for cell in cells:
				_cells_owner[Vector2i(file.origin) + Vector2i(cell)] = str(file.id)
	_files.sort_custom(func(a, b) -> bool:
		return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	if not _selected.is_empty() and not _by_id.has(_selected):
		_selected = ""
		selection_changed.emit("")
	_recalc_layout()
	queue_redraw()


func occupied_cells() -> int:
	return _cells_owner.size()


func total_cells() -> int:
	return _cols * _rows


func file_count() -> int:
	return _files.size()


func footer_text() -> String:
	var total := _cols * _rows
	return "%d %s" % [total, FG.plural_cells(total)]


func grid_metrics() -> Dictionary:
	return {
		"cell": _cell,
		"cols": _cols,
		"rows": _rows,
		"origin": _grid_origin,
		"gap": GAP,
	}


## Статическая математика стола (для тестов/интеграции): 416×548 → 99×86.
static func cell_size(view: Vector2, cols: int, rows: int, gap: float = 6.0,
		lo: float = CELL_MIN, hi: float = CELL_MAX) -> Vector2:
	return FG.cell_size_pair(view, cols, rows, gap, lo, hi)


func select_file(id: String) -> void:
	if id == _selected:
		return
	_selected = id if _by_id.has(id) else ""
	selection_changed.emit(_selected)
	queue_redraw()


# --- registry --------------------------------------------------------------

func _bind_registry() -> void:
	if not is_inside_tree():
		return
	var game := get_tree().root.get_node_or_null("Game")
	if game == null:
		return
	var next = game.get("registry")
	if next == null:
		return
	if next != _registry:
		_registry = next
	if _registry.has_signal("table_changed") \
			and not _registry.is_connected("table_changed", Callable(self, "_on_registry_table")):
		_registry.connect("table_changed", Callable(self, "_on_registry_table"))


func _on_registry_table() -> void:
	refresh()


# --- layout / hit test -----------------------------------------------------

func _on_resized() -> void:
	_recalc_layout()
	queue_redraw()


func _recalc_layout() -> void:
	# Клетку считаем как раньше, но если сетка упирается в край ближе GRID_PAD
	# (сверху/по бокам) или GRID_BOTTOM (снизу), пересчитываем по уменьшенному
	# view (как FileGrid._recalc_layout). Иначе outline/label/ghost крайних
	# клеток попадают под clip_contents и под футер.
	_cell = FG.cell_size_pair(size, _cols, _rows, GAP, CELL_MIN, CELL_MAX)
	var avail := Vector2(maxf(0.0, size.x - GRID_PAD * 2.0),
		maxf(0.0, size.y - GRID_PAD - GRID_BOTTOM))
	var gs := FG.grid_size_pair(_cols, _rows, _cell, GAP)
	if gs.x > avail.x or gs.y > avail.y:
		_cell = FG.cell_size_pair(avail, _cols, _rows, GAP, CELL_MIN, CELL_MAX)
		gs = FG.grid_size_pair(_cols, _rows, _cell, GAP)
	# По Y центрируем в полосе между GRID_PAD и GRID_BOTTOM; финальный clamp —
	# гарантия, что низ сетки не залезает в резерв (при CELL_MIN на малом view).
	_grid_origin = Vector2(
		maxf(GRID_PAD, roundf((size.x - gs.x) * 0.5)),
		GRID_PAD + maxf(0.0, roundf((avail.y - gs.y) * 0.5)))
	_grid_origin.y = clampf(_grid_origin.y, GRID_PAD,
		maxf(GRID_PAD, size.y - GRID_BOTTOM - gs.y))


func _cell_rect(c: int, r: int) -> Rect2:
	return FG.cell_rect_pair(_grid_origin, _cell, GAP, c, r)


func _shape_pos(cell_pos: Vector2i) -> Vector2:
	return FG.shape_origin_pair(_grid_origin, _cell, GAP, cell_pos)


func _file_at(pos: Vector2) -> String:
	var c := FG.cell_at_rect(pos, _grid_origin, _cell, GAP, _cols, _rows)
	if c.x < 0:
		return ""
	return str(_cells_owner.get(c, ""))


func _get_cursor_shape(at_position: Vector2) -> int:
	if _drag_active:
		return Control.CURSOR_DRAG
	return Control.CURSOR_POINTING_HAND if not _file_at(at_position).is_empty() \
		else Control.CURSOR_ARROW


func _on_mouse_exited() -> void:
	if not _hover_id.is_empty():
		_hover_id = ""
		tooltip_text = ""
		queue_redraw()


func _update_hover(pos: Vector2) -> void:
	var id := _file_at(pos)
	if id == _hover_id:
		return
	_hover_id = id
	queue_redraw()
	if id.is_empty():
		tooltip_text = ""
	else:
		var file = _by_id.get(id)
		if file != null:
			tooltip_text = "%s.%s · на столе" % [str(file.name), str(file.ext)]


# --- ввод ------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_hover(event.position)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var id := _file_at(event.position)
			if id.is_empty():
				select_file("")
			else:
				_selected = id
				file_selected.emit(id)
				selection_changed.emit(id)
				queue_redraw()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if _drag_in_progress():
				accept_event()
				return
			var id := _file_at(event.position)
			if not id.is_empty():
				context_requested.emit(id)
				accept_event()


func _drag_in_progress() -> bool:
	if _drag_active:
		return true
	var dc := _existing_drag_controller()
	if dc != null and dc.has_method("is_active"):
		return bool(dc.is_active())
	return _drop_active


func _input(event: InputEvent) -> void:
	var vp := get_viewport()
	if vp != null and vp.is_input_handled():
		return
	var dc := _existing_drag_controller()
	if dc == null or not dc.has_method("is_active") or not bool(dc.is_active()):
		return
	if FG.is_rotate_key(event) or FG.is_rotate_click(event):
		_rotate_drag()
		vp.set_input_as_handled()


func _rotate_drag() -> void:
	var dc := _drag_controller()
	if dc != null and dc.has_method("rotate_cw"):
		_drag_rotation = int(dc.rotate_cw())
	else:
		_drag_rotation = posmod(_drag_rotation + 1, 4)
	if _drop_active and not _drag_payload.is_empty():
		_refresh_ghost(_last_drop_pos)
	queue_redraw()


func _on_drag_rotation_changed(value: int) -> void:
	_drag_rotation = posmod(int(value), 4)
	if _drop_active and not _drag_payload.is_empty():
		_refresh_ghost(_last_drop_pos)
	queue_redraw()


func _bind_rotation_signal(dc: Node) -> void:
	if dc == null or not dc.has_signal("rotation_changed"):
		return
	if not dc.is_connected("rotation_changed", Callable(self, "_on_drag_rotation_changed")):
		dc.connect("rotation_changed", Callable(self, "_on_drag_rotation_changed"))


# --- drag source -----------------------------------------------------------

func _get_drag_data(at_position: Vector2) -> Variant:
	var id := _file_at(at_position)
	if id.is_empty():
		return null
	var file = _by_id.get(id)
	if file == null:
		return null
	_drag_active = true
	_drag_rotation = posmod(int(file.rotation), 4)
	var payload := FG.shape_payload_for(str(file.id), str(file.name), str(file.type),
		str(file.ext), str(file.shape_id), int(file.rotation),
		Vector2i(file.origin), "table")
	_drag_payload = payload
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	var dc := _drag_controller()
	if dc != null:
		var preview := FILE_SHAPE.new()
		preview.setup(str(file.type), str(file.shape_id), int(file.rotation),
			str(file.name), str(file.ext),
			clampf(minf(_cell.x, _cell.y) * 0.55, 28.0, 56.0),
			int(file.icon_id))
		preview.set_mode("shape")
		dc.begin(preview, "shape", int(file.rotation))
	queue_redraw()
	return payload


func _drag_controller() -> Node:
	if drag_controller != null and is_instance_valid(drag_controller):
		_bind_rotation_signal(drag_controller)
		return drag_controller
	if not is_inside_tree():
		return null
	var dc := get_tree().get_first_node_in_group("drag_controller")
	if dc == null:
		dc = DRAG_CONTROLLER.new()
		dc.name = "DragControllerAuto"
		get_tree().root.add_child(dc)
	drag_controller = dc
	_bind_rotation_signal(dc)
	return dc


func _existing_drag_controller() -> Node:
	var dc: Node = null
	if drag_controller != null and is_instance_valid(drag_controller):
		dc = drag_controller
	elif is_inside_tree():
		dc = get_tree().get_first_node_in_group("drag_controller")
	_bind_rotation_signal(dc)
	return dc


# --- drop target -----------------------------------------------------------

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	var payload: Dictionary = data
	if str(payload.get("kind", "")) != "file":
		return false
	var dc := _drag_controller()
	var key := "file:" + str(payload.get("id", ""))
	if key != _drag_key:
		_drag_key = key
		if dc != null and dc.has_method("is_active") and bool(dc.is_active()):
			_drag_rotation = int(dc.rotation()) if dc.has_method("rotation") else \
				posmod(int(payload.get("rotation", 0)), 4)
		else:
			_drag_rotation = posmod(int(payload.get("rotation", 0)), 4)
			if dc != null and dc.has_method("set_rotation"):
				dc.set_rotation(_drag_rotation)
	elif dc != null and dc.has_method("rotation"):
		_drag_rotation = int(dc.rotation())
	_drop_active = true
	_drag_payload = payload
	_last_drop_pos = at_position
	_refresh_ghost(at_position)
	if dc != null:
		dc.set_mode("shape")
	return true


func _refresh_ghost(pos: Vector2) -> void:
	var payload := _drag_payload
	if payload.is_empty():
		_ghost_cells.clear()
		return
	var shape_id := str(payload.get("shape_id", "O1"))
	if shape_id.is_empty():
		shape_id = "O1"
	var target := FG.nearest_cell_rect(pos, _grid_origin, _cell, GAP, _cols, _rows)
	var fit := _resolve_placement(payload, target, _drag_rotation)
	_ghost_rotation = int(fit.get("rotation", _drag_rotation))
	_ghost_origin = fit.get("origin", target)
	_ghost_ok = bool(fit.get("ok", false))
	_ghost_auto = bool(fit.get("auto", false))
	_ghost_target = target
	_ghost_cells = FR.shape_cells(shape_id, _ghost_rotation)
	queue_redraw()


func _resolve_placement(payload: Dictionary, target: Vector2i,
		rotation: int) -> Dictionary:
	var shape_id := str(payload.get("shape_id", "O1"))
	if shape_id.is_empty():
		shape_id = "O1"
	var preferred := posmod(int(rotation), 4)
	var ignore := str(payload.get("id", ""))
	if target.x < 0 or target.y < 0:
		var auto := _find_fit(shape_id, preferred, ignore)
		if not auto.is_empty():
			var auto_rot := int(auto["rotation"])
			return {"ok": true, "origin": auto["origin"], "rotation": auto_rot,
				"auto": auto_rot != preferred}
		return {"ok": false, "origin": Vector2i(-1, -1), "rotation": preferred,
			"auto": false}
	for i in 4:
		var rot := posmod(preferred + i, 4)
		var origin := FG.anchor_origin(target, shape_id, rot)
		if _can_place(shape_id, origin, rot, ignore):
			return {"ok": true, "origin": origin, "rotation": rot,
				"auto": rot != preferred}
	return {
		"ok": false,
		"origin": FG.anchor_origin(target, shape_id, preferred),
		"rotation": preferred,
		"auto": false,
	}


func _find_fit(shape_id: String, preferred: int, ignore_id: String) -> Dictionary:
	for i in 4:
		var rot := posmod(preferred + i, 4)
		for r in _rows:
			for c in _cols:
				var origin := Vector2i(c, r)
				if _can_place(shape_id, origin, rot, ignore_id):
					return {"origin": origin, "rotation": rot}
	return {}


func _can_place(shape_id: String, origin: Vector2i, rotation: int,
		ignore_id: String) -> bool:
	if _registry != null and _registry.has_method("can_place_table"):
		return bool(_registry.can_place_table(shape_id, origin, rotation, ignore_id))
	for cell in FR.shape_cells(shape_id, rotation):
		var c := origin.x + int(cell.x)
		var r := origin.y + int(cell.y)
		if c < 0 or r < 0 or c >= _cols or r >= _rows:
			return false
		if not str(_cells_owner.get(Vector2i(c, r), "")).is_empty():
			return false
	return true


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not (data is Dictionary):
		_end_drop()
		return
	var payload: Dictionary = data
	if str(payload.get("kind", "")) != "file":
		_end_drop()
		return
	var target := FG.nearest_cell_rect(at_position, _grid_origin, _cell, GAP,
		_cols, _rows)
	var dc := _existing_drag_controller()
	if dc != null and dc.has_method("rotation"):
		_drag_rotation = int(dc.rotation())
	var fit: Dictionary
	if _ghost_target == target and not _ghost_cells.is_empty():
		fit = {"ok": _ghost_ok, "origin": _ghost_origin,
			"rotation": _ghost_rotation, "auto": _ghost_auto}
	else:
		fit = _resolve_placement(payload, target, _drag_rotation)
	if not bool(fit.get("ok", false)):
		_reject("СТОЛ ЗАПОЛНЕН")
		_end_drop()
		return
	var file_id := str(payload.get("id", ""))
	var ok := false
	if _registry != null and not file_id.is_empty() \
			and _registry.has_method("move_file_to_table"):
		ok = bool(_registry.move_file_to_table(file_id, Vector2i(fit["origin"]),
			int(fit["rotation"])))
	if not ok:
		_reject("СТОЛ ЗАПОЛНЕН")
		_end_drop()
		return
	var out := payload.duplicate(true)
	out["origin"] = Vector2i(fit["origin"])
	out["rotation"] = int(fit["rotation"])
	out["from"] = "table"
	file_dropped.emit(out)
	table_changed.emit()
	refresh()
	_end_drop()


func _reject(text: String) -> void:
	drop_rejected.emit(text)
	_notify(text)


func _notify(text: String) -> void:
	var node: Node = self
	while node != null:
		if node.has_method("_toast"):
			node.call("_toast", text, "warn")
			return
		node = node.get_parent()


func _end_drop() -> void:
	_drop_active = false
	_drag_key = ""
	_drag_rotation = 0
	_ghost_cells.clear()
	_ghost_target = Vector2i(-1, -1)
	_ghost_auto = false
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		var was_dragging := _drag_active
		_drag_active = false
		_end_drop()
		var dc := _existing_drag_controller()
		if dc != null:
			dc.reset_hover()
			if was_dragging:
				dc.end()


# --- отрисовка -------------------------------------------------------------

func _draw() -> void:
	if size.x < 2.0 or size.y < 2.0:
		return
	var f := Theme90.ui()
	draw_style_box(Theme90.box(Theme90.PAPER_HI, Theme90.BORDER_SOFT, 3, 1),
		Rect2(Vector2.ZERO, size))
	_draw_grid_lines()
	for file in _files:
		_draw_file(file)
	_draw_ghost(f)
	if _files.is_empty():
		_draw_empty(f)
	_draw_footer(f)


func _draw_grid_lines() -> void:
	var gs := FG.grid_size_pair(_cols, _rows, _cell, GAP)
	if gs.x <= 0.0 or gs.y <= 0.0:
		return
	for r in _rows:
		for c in _cols:
			if (c + r) % 2 == 1:
				draw_rect(_cell_rect(c, r), Color(0, 0, 0, 0.016))
	var line := Color(0, 0, 0, 0.10)
	var step := _cell + Vector2(GAP, GAP)
	for c in range(1, _cols):
		var x := _grid_origin.x + float(c) * step.x - GAP * 0.5
		draw_line(Vector2(x, _grid_origin.y), Vector2(x, _grid_origin.y + gs.y),
			line, 1.0, false)
	for r in range(1, _rows):
		var y := _grid_origin.y + float(r) * step.y - GAP * 0.5
		draw_line(Vector2(_grid_origin.x, y), Vector2(_grid_origin.x + gs.x, y),
			line, 1.0, false)
	draw_rect(Rect2(_grid_origin, gs), line, false, 1.0)


func _draw_file(file) -> void:
	var cells := FR.shape_cells(str(file.shape_id), int(file.rotation))
	FILE_SHAPE.paint(self, _shape_pos(Vector2i(file.origin)), cells, _cell, {
		"type": str(file.type),
		"name": str(file.name),
		"ext": str(file.ext),
		"icon_id": int(file.icon_id),
		"state": FG.file_state(file),
		"selected": str(file.id) == _selected,
		"hovered": str(file.id) == _hover_id,
		"alpha": 1.0,
		"show_label": true,
		"gap": GAP,
	})


func _draw_ghost(f: Font) -> void:
	if not _drop_active or _ghost_cells.is_empty():
		return
	var color := Theme90.SUCCESS if _ghost_ok else Theme90.ERROR
	var fill := Color(color.r, color.g, color.b, 0.16)
	FILE_SHAPE.paint(self, _shape_pos(_ghost_origin), _ghost_cells, _cell, {
		"type": "text",
		"alpha": 0.9,
		"show_label": false,
		"gap": GAP,
		"fill": fill,
		"outline": color,
	})
	var b := FR.shape_bounds(_ghost_cells)
	var step := _cell + Vector2(GAP, GAP)
	var box := Rect2(_shape_pos(_ghost_origin), Vector2(
			float(b.x) * step.x - GAP, float(b.y) * step.y - GAP))
	Theme90.draw_dashed_box(self, box.grow(2.0), color, 4.0, 1.2)
	var hint := "ОТПУСТИТЕ · R ПОВОРОТ" if _ghost_ok else "СТОЛ ЗАПОЛНЕН · R ПОВОРОТ"
	if _ghost_ok and _ghost_auto:
		hint = "ОТПУСТИТЕ · АВТОПОВОРОТ · R ПОВОРОТ"
	var hw := f.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	var pill := Rect2(size.x - hw - 20.0, 6.0, hw + 14.0, 18.0)
	draw_style_box(Theme90.box(Theme90.WHITE, color, 4, 1), pill)
	Theme90.text_vcenter(self, f, pill, hint, 10, Theme90.NAVY, -1,
		HORIZONTAL_ALIGNMENT_CENTER)


func _draw_empty(f: Font) -> void:
	var gs := FG.grid_size_pair(_cols, _rows, _cell, GAP)
	if gs.x <= 0.0 or gs.y <= 0.0:
		return
	var box := Rect2(_grid_origin, gs).grow(-10.0)
	Theme90.draw_dashed_box(self, box, Color(Theme90.SHADE.r, Theme90.SHADE.g,
		Theme90.SHADE.b, 0.40), 5.0, 1.0)
	var lines := Theme90.wrap(f, "Здесь можно разложить файлы после часа пика",
		12, minf(box.size.x - 24.0, 280.0), 2)
	var total_h := float(lines.size()) * 15.0
	var y := box.get_center().y - total_h * 0.5
	for i in lines.size():
		var w := f.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		Theme90.text(self, f, Vector2(box.get_center().x - w * 0.5, y + float(i) * 15.0),
			lines[i], 12, Theme90.SHADE)


func _draw_footer(f: Font) -> void:
	draw_rect(Rect2(0, size.y - 16.0, size.x, 16.0), Color(Theme90.PAPER_HI.r,
		Theme90.PAPER_HI.g, Theme90.PAPER_HI.b, 0.94))
	draw_line(Vector2(3, size.y - 16.0), Vector2(size.x - 3, size.y - 16.0),
		Theme90.HAIRLINE, 1.0)
	Theme90.text(self, f, Vector2(4, size.y - 12.0), footer_text(), 10,
		Theme90.SHADE, size.x - 8.0)
