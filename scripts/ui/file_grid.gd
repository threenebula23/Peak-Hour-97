class_name FileGrid
extends Control
## Явная клеточная сетка папки: 5×4 … 8×6, файл — полимино, подпись в
## верхней левой ЗАНЯТОЙ клетке. Никаких дочерних Control-узлов на файл:
## всё рисуется в `_draw`, попадание считается по координатам мыши.
##
## Источник данных — Game.registry (`grid_changed(folder_id)`), позиции
## хранятся в папке. Drag: FileShape-превью + ghost с текущим поворотом,
## R/ПКМ вращает. Бросок пакета НЕ вызывает HourDirector — только сигнал
## packet_dropped(payload, origin, rotation).

signal file_selected(id: String)
signal file_activated(id: String)
signal context_requested(id: String)
signal file_dropped(payload: Dictionary)
signal packet_dropped(payload: Dictionary, origin: Vector2i, rotation: int)
signal selection_changed(id: String)
signal drop_rejected(reason: String)
# legacy-сигналы main.gd на время интеграционного перехода
signal file_context_requested(id: String, global_pos: Vector2)
signal service_filter_changed(on: bool)

const FR = preload("res://scripts/core/file_registry.gd")
const FILE_SHAPE = preload("res://scripts/ui/file_shape.gd")
const DRAG_CONTROLLER = preload("res://scripts/ui/drag_controller.gd")

const GAP := 6.0
const CELL_MIN := 56.0
const CELL_MAX := 104.0
## Внутренний отступ сетки: фигура расширяет заливку/контур на GAP/2 + 1.3 px
## (выделение 2.6) за границу клетки, ghost рисует dashed-box +2.6 px. Без
## запаса клип Control (и clip_contents родителя) срезал левый/правый край
## файла в клетках (0,*) и (cols-1,*).
const GRID_PAD := 5.0
const DEFAULT_COLS := 5
const DEFAULT_ROWS := 4

var folder_id: String = ""
var folder_name: String = ""
var path_text: String = ""
var service_filter: bool = false
## Назначает Main. Если пусто — ищем узел в группе "drag_controller".
var drag_controller: Node = null

var _registry = null
var _folder = null
var _files: Array = []
var _by_id: Dictionary = {}
var _cells_owner: Dictionary = {} # Vector2i -> owner_id (файлы + резервации)
var _reservations: Array = []
var _cols: int = DEFAULT_COLS
var _rows: int = DEFAULT_ROWS
var _cell: float = CELL_MAX
var _grid_origin: Vector2 = Vector2.ZERO

var _selected: String = ""
var _hover_id: String = ""
var _filter: String = ""
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


# --- публичный API ---------------------------------------------------------

func set_folder(p_id: String, p_name: String = "", p_path: String = "") -> void:
	if folder_id != p_id:
		_selected = ""
		_hover_id = ""
	folder_id = p_id
	folder_name = p_name
	path_text = p_path
	refresh()


func refresh() -> void:
	_bind_registry()
	_files.clear()
	_by_id.clear()
	_cells_owner.clear()
	_reservations.clear()
	_folder = null
	_cols = DEFAULT_COLS
	_rows = DEFAULT_ROWS
	if _registry != null:
		if not folder_id.is_empty() and _registry.has_method("get_folder"):
			_folder = _registry.get_folder(folder_id)
		if _folder != null:
			_cols = maxi(1, int(_folder.cols))
			_rows = maxi(1, int(_folder.rows))
			for file in _registry.get_folder_files(folder_id):
				_files.append(file)
				_by_id[str(file.id)] = file
			# Self-heal: файл с folder_id папки мог выпасть из file_ids/cells
			# (detach, старый сейв, гонка сигналов) — возвращаем его в сетку.
			_heal_folder_bookkeeping(_folder)
			for key in _folder.cells.keys():
				_cells_owner[Vector2i(key)] = str(_folder.cells[key])
			if _registry.has_method("folder_reservations"):
				_reservations = _registry.folder_reservations(folder_id)
		else:
			var dims: Vector2i = _registry.current_folder_dims()
			if dims.x > 0 and dims.y > 0:
				_cols = maxi(1, dims.x)
				_rows = maxi(1, dims.y)
	_files.sort_custom(func(a, b) -> bool:
		return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	if not _selected.is_empty() and not _by_id.has(_selected):
		_selected = ""
		selection_changed.emit("")
	_recalc_layout()
	queue_redraw()


## Self-heal bookkeeping папки: если файл в registry помнит folder_id, но его
## нет в folder.file_ids/cells, сетка всё равно обязана его показать.
## Чиним file_ids и клетки (first-fit), не эмитим сигналы — мы уже в refresh.
func _heal_folder_bookkeeping(folder) -> void:
	if folder == null or _registry == null:
		return
	var all_files = _registry.get("files")
	if not (all_files is Dictionary):
		return
	for file in all_files.values():
		if file == null or str(file.folder_id) != str(folder.id):
			continue
		var loc := str(file.location)
		# "moving" — транзиент внутри FileRegistry.move_*/place_*: старые клетки
		# уже освобождены, новые ещё не проштампованы. Лечить такой файл нельзя:
		# вернёт его в старую сетку как фантомный дубль при первом drag.
		if loc == "moving" or loc == "table" or loc == "registry":
			continue
		var file_id := str(file.id)
		if not _by_id.has(file_id):
			_files.append(file)
			_by_id[file_id] = file
		_heal_file_placement(folder, file)


func _heal_file_placement(folder, file) -> void:
	var file_id := str(file.id)
	var cells := _cells_of(file)
	var origin: Vector2i = file.origin
	if not _placement_is_valid(folder, cells, origin, file_id):
		var shape_id := str(file.shape_id)
		if shape_id.is_empty():
			shape_id = "O1"
		var rot := int(file.rotation)
		var fit: Dictionary = {}
		if _registry.has_method("_find_fit"):
			fit = _registry.call("_find_fit", folder, shape_id, rot)
		if fit is Dictionary and not fit.is_empty():
			origin = Vector2i(fit.get("origin", Vector2i.ZERO))
			rot = int(fit.get("rotation", rot))
			cells = _registry.call("shape_cells", shape_id, rot)
		else:
			# Места нет/размещение битое — хотя бы (0,0), чтобы файл был виден.
			origin = Vector2i.ZERO
			cells = [Vector2i.ZERO]
			rot = 0
		file.origin = origin
		file.rotation = posmod(rot, 4)
		file.shape_cells = cells
	# Анти-фантом: убираем все клетки этого файла, которых нет в актуальном
	# наборе, до штамповки новых (erase во время keys() — пропуски).
	var new_cells: Dictionary = {}
	for cell in cells:
		new_cells[origin + _cell_of(cell)] = true
	var stale: Array = []
	for key in folder.cells.keys():
		var pos := Vector2i(key)
		if str(folder.cells[key]) == file_id and not new_cells.has(pos):
			stale.append(pos)
	for pos in stale:
		folder.cells.erase(pos)
	for cell in cells:
		folder.cells[origin + _cell_of(cell)] = file_id
	# file.id должен присутствовать в file_ids ровно один раз.
	while folder.file_ids.has(file_id):
		folder.file_ids.erase(file_id)
	folder.file_ids.append(file_id)


func _placement_is_valid(folder, cells: Array, origin: Vector2i, file_id: String) -> bool:
	for cell in cells:
		var c: Vector2i = origin + _cell_of(cell)
		if c.x < 0 or c.y < 0 or c.x >= int(folder.cols) or c.y >= int(folder.rows):
			return false
		var owner := str(folder.cells.get(c, ""))
		if not owner.is_empty() and owner != file_id:
			return false
	return true


func _cells_of(file) -> Array:
	var cells: Array = file.shape_cells
	if cells.is_empty():
		var shape_id := str(file.shape_id)
		if shape_id.is_empty():
			shape_id = "O1"
		if _registry != null and _registry.has_method("shape_cells"):
			cells = _registry.call("shape_cells", shape_id, int(file.rotation))
	if cells.is_empty():
		cells = [Vector2i.ZERO]
	return cells


func _cell_of(value) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Vector2:
		return Vector2i(value)
	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i.ZERO


func set_filter(text: String) -> void:
	_filter = text.strip_edges().to_lower()
	queue_redraw()


func get_folder_id() -> String:
	return folder_id


func select_file(id: String) -> void:
	if id == _selected:
		return
	_selected = id if _by_id.has(id) else ""
	selection_changed.emit(_selected)
	queue_redraw()


func clear_selection() -> void:
	select_file("")


func set_service_filter(on: bool) -> void:
	service_filter = on
	service_filter_changed.emit(on)
	queue_redraw()


func hidden_count() -> int:
	var n := 0
	for file in _files:
		var state := file_state(file)
		if state == "locked" or state == "malicious" or state == "failed":
			n += 1
	return n


func file_count() -> int:
	return _files.size()


func occupied_cells() -> int:
	return _cells_owner.size()


func total_cells() -> int:
	return _cols * _rows


func stats() -> Dictionary:
	var occupied := _cells_owner.size()
	var total := _cols * _rows
	return {
		"occupied": occupied,
		"free": maxi(0, total - occupied),
		"total": total,
		"files": _files.size(),
		"reserved": _reservations.size(),
	}


## Подвал: счётчик файлов и размер сетки. Диск-«занято X из Y» убран.
func footer_text() -> String:
	var s := stats()
	var files := int(s["files"])
	return "%d %s · %d %s" % [
		files, plural_files(files), int(s["total"]), plural_cells(int(s["total"]))]


func grid_metrics() -> Dictionary:
	return {
		"cell": _cell,
		"cols": _cols,
		"rows": _rows,
		"origin": _grid_origin,
		"gap": GAP,
	}


# --- legacy-шимы main.gd ---------------------------------------------------

## main.gd ещё строит заголовки по get_cards(); до интеграции список пуст.
func get_cards() -> Array:
	return []


## main.gd присылает плоский список файлов v1. Храним, но рисуем registry.
func set_files(files: Array) -> void:
	_legacy_files = files.duplicate(true)
	queue_redraw()


## main.gd: файл бросили на другой файл/в пустую область — это drop в папку.
func accept_dropped_file(data: Dictionary) -> bool:
	if data.is_empty():
		return false
	var kind := str(data.get("kind", ""))
	if kind != "file" and kind != "packet":
		return false
	file_dropped.emit(data)
	return true


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
	if _registry.has_signal("grid_changed") \
			and not _registry.is_connected("grid_changed", Callable(self, "_on_grid_changed")):
		_registry.connect("grid_changed", Callable(self, "_on_grid_changed"))


func _on_grid_changed(changed_folder_id: String) -> void:
	if changed_folder_id.is_empty() or changed_folder_id == folder_id:
		refresh()


# --- геометрия (static: используется тестами и SortingTable) --------------

static func cell_size(view: Vector2, cols: int, rows: int, gap: float = 6.0,
		lo: float = CELL_MIN, hi: float = CELL_MAX) -> float:
	if cols <= 0 or rows <= 0:
		return lo
	var by_w := (view.x - gap * float(cols - 1)) / float(cols)
	var by_h := (view.y - gap * float(rows - 1)) / float(rows)
	return clampf(floorf(minf(by_w, by_h)), lo, hi)


static func grid_size_of(cols: int, rows: int, cell: float, gap: float = 6.0) -> Vector2:
	if cols <= 0 or rows <= 0:
		return Vector2.ZERO
	return Vector2(float(cols) * cell + gap * float(cols - 1),
		float(rows) * cell + gap * float(rows - 1))


static func cell_rect_of(origin: Vector2, cell: float, gap: float,
		c: int, r: int) -> Rect2:
	var step := cell + gap
	return Rect2(origin + Vector2(float(c) * step, float(r) * step), Vector2(cell, cell))


## Пиксельная позиция bbox-угла фигуры (её origin) внутри сетки. Раньше
## FileShape.paint() получал _grid_origin и все файлы рисовались в (0,0).
static func shape_origin(grid_origin: Vector2, cell: float, gap: float,
		cell_pos: Vector2i) -> Vector2:
	var step := cell + gap
	return grid_origin + Vector2(float(cell_pos.x) * step, float(cell_pos.y) * step)


static func shape_origin_pair(grid_origin: Vector2, cell: Vector2, gap: float,
		cell_pos: Vector2i) -> Vector2:
	var step := cell + Vector2(gap, gap)
	return grid_origin + Vector2(float(cell_pos.x) * step.x,
		float(cell_pos.y) * step.y)


## R (физическая клавиша — работает и в русской раскладке) / ПКМ.
static func is_rotate_key(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return false
	return key.physical_keycode == KEY_R or key.keycode == KEY_R


static func is_rotate_click(event: InputEvent) -> bool:
	if not (event is InputEventMouseButton):
		return false
	var mouse := event as InputEventMouseButton
	return mouse.pressed and mouse.button_index == MOUSE_BUTTON_RIGHT


## Прямоугольная клетка стола: ширина и высота считаются независимо
## (416×548 → 99×86), каждая зажата в [lo, hi].
static func cell_size_pair(view: Vector2, cols: int, rows: int, gap: float = 6.0,
		lo: float = CELL_MIN, hi: float = CELL_MAX) -> Vector2:
	if cols <= 0 or rows <= 0:
		return Vector2(lo, lo)
	var w := (view.x - gap * float(cols - 1)) / float(cols)
	var h := (view.y - gap * float(rows - 1)) / float(rows)
	return Vector2(clampf(floorf(w), lo, hi), clampf(floorf(h), lo, hi))


static func grid_size_pair(cols: int, rows: int, cell: Vector2, gap: float = 6.0) -> Vector2:
	if cols <= 0 or rows <= 0:
		return Vector2.ZERO
	return Vector2(float(cols) * cell.x + gap * float(cols - 1),
		float(rows) * cell.y + gap * float(rows - 1))


static func cell_rect_pair(origin: Vector2, cell: Vector2, gap: float,
		c: int, r: int) -> Rect2:
	var step := cell + Vector2(gap, gap)
	return Rect2(origin + Vector2(float(c) * step.x, float(r) * step.y), cell)


static func cell_at_rect(pos: Vector2, origin: Vector2, cell: Vector2, gap: float,
		cols: int, rows: int) -> Vector2i:
	if cols <= 0 or rows <= 0 or cell.x <= 0.0 or cell.y <= 0.0:
		return Vector2i(-1, -1)
	var step := cell + Vector2(gap, gap)
	var lx := pos.x - origin.x
	var ly := pos.y - origin.y
	if lx < 0.0 or ly < 0.0:
		return Vector2i(-1, -1)
	var c := int(floorf(lx / step.x))
	var r := int(floorf(ly / step.y))
	if c < 0 or r < 0 or c >= cols or r >= rows:
		return Vector2i(-1, -1)
	if lx - float(c) * step.x >= cell.x or ly - float(r) * step.y >= cell.y:
		return Vector2i(-1, -1)
	return Vector2i(c, r)


static func nearest_cell_rect(pos: Vector2, origin: Vector2, cell: Vector2,
		gap: float, cols: int, rows: int) -> Vector2i:
	var strict := cell_at_rect(pos, origin, cell, gap, cols, rows)
	if strict.x >= 0:
		return strict
	if cols <= 0 or rows <= 0:
		return Vector2i(-1, -1)
	var gs := grid_size_pair(cols, rows, cell, gap)
	if not Rect2(origin, gs).has_point(pos):
		return Vector2i(-1, -1)
	var step := cell + Vector2(gap, gap)
	var lx := pos.x - origin.x
	var ly := pos.y - origin.y
	var c := clampi(int(floorf(lx / step.x)), 0, cols - 1)
	var r := clampi(int(floorf(ly / step.y)), 0, rows - 1)
	if lx - float(c) * step.x > cell.x + gap * 0.5 and c < cols - 1:
		c += 1
	if ly - float(r) * step.y > cell.y + gap * 0.5 and r < rows - 1:
		r += 1
	return Vector2i(c, r)


## Строгий hit-test: точка в зазоре или вне поля → (-1,-1).
static func cell_at(pos: Vector2, origin: Vector2, cell: float, gap: float,
		cols: int, rows: int) -> Vector2i:
	if cols <= 0 or rows <= 0 or cell <= 0.0:
		return Vector2i(-1, -1)
	var step := cell + gap
	var lx := pos.x - origin.x
	var ly := pos.y - origin.y
	if lx < 0.0 or ly < 0.0:
		return Vector2i(-1, -1)
	var c := int(floorf(lx / step))
	var r := int(floorf(ly / step))
	if c < 0 or r < 0 or c >= cols or r >= rows:
		return Vector2i(-1, -1)
	if lx - float(c) * step >= cell or ly - float(r) * step >= cell:
		return Vector2i(-1, -1)
	return Vector2i(c, r)


## Ближайшая клетка для drop: зазор «прилипает» к клетке, за пределами поля
## возвращается (-1,-1) — это auto-place.
static func nearest_cell(pos: Vector2, origin: Vector2, cell: float, gap: float,
		cols: int, rows: int) -> Vector2i:
	var strict := cell_at(pos, origin, cell, gap, cols, rows)
	if strict.x >= 0:
		return strict
	if cols <= 0 or rows <= 0:
		return Vector2i(-1, -1)
	var gs := grid_size_of(cols, rows, cell, gap)
	if not Rect2(origin, gs).has_point(pos):
		return Vector2i(-1, -1)
	var step := cell + gap
	var lx := pos.x - origin.x
	var ly := pos.y - origin.y
	var c := clampi(int(floorf(lx / step)), 0, cols - 1)
	var r := clampi(int(floorf(ly / step)), 0, rows - 1)
	if lx - float(c) * step > cell + gap * 0.5 and c < cols - 1:
		c += 1
	if ly - float(r) * step > cell + gap * 0.5 and r < rows - 1:
		r += 1
	return Vector2i(c, r)


## Origin bbox так, чтобы ЗАНЯТАЯ label-клетка фигуры оказалась под курсором.
static func anchor_origin(target_cell: Vector2i, shape_id: String, rotation: int) -> Vector2i:
	var cells := FR.shape_cells(shape_id, rotation)
	return target_cell - FR.label_cell(cells)


## Первый подходящий поворот, начиная с preferred. fits.call(rotation) -> bool.
static func best_rotation(shape_id: String, preferred: int, fits: Callable) -> int:
	for i in 4:
		var rot := posmod(preferred + i, 4)
		if bool(fits.call(rot)):
			return rot
	return -1


static func fit_rotation(shape_id: String, preferred: int, fits: Callable) -> int:
	return best_rotation(shape_id, preferred, fits)


static func shape_cells(shape_id: String, rotation: int = 0) -> Array:
	return FR.shape_cells(shape_id, rotation)


static func label_cell(cells: Array) -> Vector2i:
	return FR.label_cell(cells)


static func shape_payload_for(id: String, name: String, type: String, ext: String,
		shape_id: String, rotation: int, origin: Vector2i, from: String) -> Dictionary:
	return {
		"kind": "file",
		"id": id,
		"name": name,
		"type": type,
		"ext": ext,
		"shape_id": shape_id,
		"rotation": posmod(rotation, 4),
		"origin": origin,
		"from": from,
		"cells": FR.shape_cells(shape_id, rotation),
	}


static func file_state(file) -> String:
	if file == null:
		return "stored"
	if not str(file.attached_request).is_empty():
		return "attached"
	var loc := String(file.location)
	if loc == "attached" or loc == "locked" or loc == "malicious" or loc == "failed":
		return loc
	return "stored"


static func plural_files(n: int) -> String:
	var n10 := n % 10
	var n100 := n % 100
	if n10 == 1 and n100 != 11:
		return "файл"
	if n10 >= 2 and n10 <= 4 and (n100 < 12 or n100 > 14):
		return "файла"
	return "файлов"


static func plural_cells(n: int) -> String:
	var n10 := n % 10
	var n100 := n % 100
	if n10 == 1 and n100 != 11:
		return "клетка"
	if n10 >= 2 and n10 <= 4 and (n100 < 12 or n100 > 14):
		return "клетки"
	return "клеток"


# --- layout ----------------------------------------------------------------

func _on_resized() -> void:
	_recalc_layout()
	queue_redraw()


func _recalc_layout() -> void:
	# Клетку считаем как раньше, но если сетка упирается в край ближе GRID_PAD,
	# пересчитываем по уменьшенному view. Так outline/label/ghost у крайних
	# клеток не попадают под clip, а обычный 5×4 не раздувается.
	_cell = cell_size(size, _cols, _rows)
	var gs := grid_size_of(_cols, _rows, _cell, GAP)
	if gs.x + GRID_PAD * 2.0 > size.x or gs.y + GRID_PAD * 2.0 > size.y:
		var inner := Vector2(maxf(0.0, size.x - GRID_PAD * 2.0),
			maxf(0.0, size.y - GRID_PAD * 2.0))
		_cell = cell_size(inner, _cols, _rows)
		gs = grid_size_of(_cols, _rows, _cell, GAP)
	_grid_origin = Vector2(
		maxf(GRID_PAD, roundf((size.x - gs.x) * 0.5)),
		maxf(GRID_PAD, roundf((size.y - gs.y) * 0.5)))


func _cell_rect(c: int, r: int) -> Rect2:
	return cell_rect_of(_grid_origin, _cell, GAP, c, r)


func _shape_pos(cell_pos: Vector2i) -> Vector2:
	return shape_origin(_grid_origin, _cell, GAP, cell_pos)


# --- hit test / hover ------------------------------------------------------

func _file_at(pos: Vector2) -> String:
	var c := cell_at(pos, _grid_origin, _cell, GAP, _cols, _rows)
	if c.x < 0:
		return ""
	var owner := str(_cells_owner.get(c, ""))
	if not _by_id.has(owner):
		return ""
	var file = _by_id[owner]
	var state := file_state(file)
	if service_filter and (state == "locked" or state == "malicious" or state == "failed"):
		return ""
	if not _filter.is_empty() and not _matches_filter(file):
		return ""
	return owner


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
	if id != _hover_id:
		_hover_id = id
		queue_redraw()
	if id.is_empty():
		tooltip_text = ""
		return
	var file = _by_id.get(id)
	if file != null:
		var cells := FR.shape_cells(str(file.shape_id), int(file.rotation))
		tooltip_text = "%s.%s · %d %s" % [str(file.name), str(file.ext), cells.size(),
			plural_cells(cells.size())]


# --- ввод ------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_hover(event.position)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var id := _file_at(event.position)
			if id.is_empty():
				clear_selection()
			else:
				_selected = id
				file_selected.emit(id)
				selection_changed.emit(id)
				queue_redraw()
				if event.double_click:
					file_activated.emit(id)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# ПКМ во время drag — это поворот, а не контекстное меню.
			if _drag_in_progress():
				accept_event()
				return
			var id := _file_at(event.position)
			if not id.is_empty():
				context_requested.emit(id)
				file_context_requested.emit(id, get_global_mouse_position())
				accept_event()


## Идёт ли drag (источник или цель). Опираемся на DragController, а не только
## на локальный _drag_active: у цели drop он вообще не выставлялся.
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
	# R/ПКМ работают и у цели drop: локальный _drag_active выставляет только
	# источник, а пакетный drag его вообще не трогает.
	if dc == null or not dc.has_method("is_active") or not bool(dc.is_active()):
		return
	if is_rotate_key(event) or is_rotate_click(event):
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


## DragController — единый источник поворота. Ghost пересчитывается даже
## если событие R получила другая сетка.
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
	var payload := shape_payload_for(str(file.id), str(file.name), str(file.type),
		str(file.ext), str(file.shape_id), int(file.rotation),
		Vector2i(file.origin), "folder")
	_drag_payload = payload
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	var dc := _drag_controller()
	if dc != null:
		var preview := FILE_SHAPE.new()
		preview.setup(str(file.type), str(file.shape_id), int(file.rotation),
			str(file.name), str(file.ext), clampf(_cell * 0.55, 28.0, 56.0),
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
	var kind := str(payload.get("kind", ""))
	if kind != "file" and kind != "packet":
		return false
	var dc := _drag_controller()
	var key := kind + ":" + str(payload.get("id", ""))
	if key != _drag_key:
		_drag_key = key
		# Поворот — состояние DragController: после R/ПКМ payload уже устарел.
		# Если контроллер пуст (пакет без превью), засеваем из payload.
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
	var target := nearest_cell(pos, _grid_origin, _cell, GAP, _cols, _rows)
	var fit := _resolve_placement(payload, target, _drag_rotation)
	_ghost_rotation = int(fit.get("rotation", _drag_rotation))
	_ghost_origin = fit.get("origin", target)
	_ghost_ok = bool(fit.get("ok", false))
	_ghost_auto = bool(fit.get("auto", false))
	_ghost_target = target
	_ghost_cells = FR.shape_cells(shape_id, _ghost_rotation)
	queue_redraw()


## Сначала пробуем ВЫБРАННЫЙ пользователем поворот. Остальные — только если
## он не влезает; тогда fit.auto = true, и ghost честно пишет про автоповорот.
func _resolve_placement(payload: Dictionary, target: Vector2i,
		rotation: int) -> Dictionary:
	var shape_id := str(payload.get("shape_id", "O1"))
	if shape_id.is_empty():
		shape_id = "O1"
	var preferred := posmod(int(rotation), 4)
	var ignore := ""
	if str(payload.get("kind", "")) == "file":
		ignore = str(payload.get("id", ""))
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
		var origin := anchor_origin(target, shape_id, rot)
		if _can_place(shape_id, origin, rot, ignore):
			return {"ok": true, "origin": origin, "rotation": rot,
				"auto": rot != preferred}
	return {
		"ok": false,
		"origin": anchor_origin(target, shape_id, preferred),
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
	if _registry != null and _folder != null and _registry.has_method("can_place"):
		return bool(_registry.can_place(_folder, shape_id, origin, rotation, ignore_id))
	for cell in FR.shape_cells(shape_id, rotation):
		var c := origin.x + int(cell.x)
		var r := origin.y + int(cell.y)
		if c < 0 or r < 0 or c >= _cols or r >= _rows:
			return false
	return true


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not (data is Dictionary):
		_end_drop()
		return
	var payload: Dictionary = data
	var kind := str(payload.get("kind", ""))
	var target := nearest_cell(at_position, _grid_origin, _cell, GAP, _cols, _rows)
	var dc := _existing_drag_controller()
	if dc != null and dc.has_method("rotation"):
		_drag_rotation = int(dc.rotation())
	# Роняем ровно туда и с тем поворотом, который показал ghost.
	var fit: Dictionary
	if _ghost_target == target and not _ghost_cells.is_empty():
		fit = {"ok": _ghost_ok, "origin": _ghost_origin,
			"rotation": _ghost_rotation, "auto": _ghost_auto}
	else:
		fit = _resolve_placement(payload, target, _drag_rotation)
	if kind == "packet":
		if not bool(fit.get("ok", false)):
			_reject("НЕТ МЕСТА В ПАПКЕ")
		else:
			packet_dropped.emit(payload, Vector2i(fit["origin"]), int(fit["rotation"]))
		_end_drop()
		return
	if kind != "file":
		_end_drop()
		return
	if not bool(fit.get("ok", false)):
		_reject("НЕТ МЕСТА В ПАПКЕ")
		_end_drop()
		return
	var file_id := str(payload.get("id", ""))
	var from := str(payload.get("from", "folder"))
	var ok := false
	if _registry != null and not file_id.is_empty():
		if from == "table" and _registry.has_method("move_from_table"):
			ok = bool(_registry.move_from_table(file_id, folder_id,
				Vector2i(fit["origin"]), int(fit["rotation"])))
		elif not folder_id.is_empty() and _registry.has_method("move_file"):
			ok = bool(_registry.move_file(file_id, folder_id,
				Vector2i(fit["origin"]), int(fit["rotation"])))
	if ok:
		var out := payload.duplicate(true)
		out["origin"] = Vector2i(fit["origin"])
		out["rotation"] = int(fit["rotation"])
		out["from"] = from
		file_dropped.emit(out)
		refresh()
	else:
		_reject("НЕТ МЕСТА В ПАПКЕ")
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
	for res in _reservations:
		_draw_reservation(res)
	_draw_ghost(f)
	if _files.is_empty() and _reservations.is_empty():
		_draw_empty(f)
	_draw_footer(f)


func _draw_grid_lines() -> void:
	var gs := grid_size_of(_cols, _rows, _cell, GAP)
	if gs.x <= 0.0 or gs.y <= 0.0:
		return
	for r in _rows:
		for c in _cols:
			if (c + r) % 2 == 1:
				draw_rect(_cell_rect(c, r), Color(0, 0, 0, 0.016))
	var line := Color(0, 0, 0, 0.10)
	var step := _cell + GAP
	for c in range(1, _cols):
		var x := _grid_origin.x + float(c) * step - GAP * 0.5
		draw_line(Vector2(x, _grid_origin.y), Vector2(x, _grid_origin.y + gs.y),
			line, 1.0, false)
	for r in range(1, _rows):
		var y := _grid_origin.y + float(r) * step - GAP * 0.5
		draw_line(Vector2(_grid_origin.x, y), Vector2(_grid_origin.x + gs.x, y),
			line, 1.0, false)
	draw_rect(Rect2(_grid_origin, gs), line, false, 1.0)


func _draw_file(file) -> void:
	var state := file_state(file)
	if service_filter and (state == "locked" or state == "malicious" or state == "failed"):
		return
	if not _filter.is_empty() and not _matches_filter(file):
		return
	var cells := FR.shape_cells(str(file.shape_id), int(file.rotation))
	if cells.is_empty():
		cells = [Vector2i.ZERO]
	var origin := Vector2i(file.origin)
	if origin.x < 0 or origin.y < 0 or origin.x >= _cols or origin.y >= _rows:
		origin = Vector2i(
			clampi(origin.x, 0, maxi(0, _cols - 1)),
			clampi(origin.y, 0, maxi(0, _rows - 1)))
	FILE_SHAPE.paint(self, _shape_pos(origin), cells, _cell, {
		"type": str(file.type),
		"name": str(file.name),
		"ext": str(file.ext),
		"icon_id": int(file.icon_id),
		"state": state,
		"selected": str(file.id) == _selected,
		"hovered": str(file.id) == _hover_id,
		"alpha": 1.0,
		"show_label": true,
		"gap": GAP,
	})


func _draw_reservation(res: Dictionary) -> void:
	var shape_id := str(res.get("shape_id", "O1"))
	var rot := int(res.get("rotation", 0))
	var origin: Vector2i = res.get("origin", Vector2i.ZERO)
	var cells := FR.shape_cells(shape_id, rot)
	var fill := Color(Theme90.ACCENT.r, Theme90.ACCENT.g, Theme90.ACCENT.b, 0.10)
	FILE_SHAPE.paint(self, _shape_pos(origin), cells, _cell, {
		"type": "text",
		"state": "stored",
		"alpha": 0.9,
		"show_label": false,
		"gap": GAP,
		"fill": fill,
		"outline": Color(Theme90.ACCENT_LIGHT.r, Theme90.ACCENT_LIGHT.g,
			Theme90.ACCENT_LIGHT.b, 0.9),
	})
	var lbl := origin + FR.label_cell(cells)
	var lr := _cell_rect(lbl.x, lbl.y)
	Theme90.draw_packet_icon(self, lr.position + Vector2(4, 4), Theme90.ACCENT)
	if _cell >= 72.0:
		Theme90.text(self, Theme90.ui(), lr.position + Vector2(4, 17), "ЗАГРУЗКА",
			10, Theme90.ACCENT, lr.size.x - 6.0)


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
	var step := _cell + GAP
	var box := Rect2(_shape_pos(_ghost_origin), Vector2(
			float(b.x) * step - GAP, float(b.y) * step - GAP))
	Theme90.draw_dashed_box(self, box.grow(2.0), color, 4.0, 1.2)
	var hint := "ОТПУСТИТЕ · R ПОВОРОТ" if _ghost_ok else "НЕ ВЛЕЗАЕТ · R ПОВОРОТ"
	if _ghost_ok and _ghost_auto:
		hint = "ОТПУСТИТЕ · АВТОПОВОРОТ · R ПОВОРОТ"
	var hw := f.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	var pill := Rect2(size.x - hw - 20.0, 6.0, hw + 14.0, 18.0)
	draw_style_box(Theme90.box(Theme90.WHITE, color, 4, 1), pill)
	Theme90.text_vcenter(self, f, pill, hint, 10, Theme90.NAVY, -1,
		HORIZONTAL_ALIGNMENT_CENTER)


func _draw_empty(f: Font) -> void:
	var gs := grid_size_of(_cols, _rows, _cell, GAP)
	if gs.x <= 0.0 or gs.y <= 0.0:
		return
	var box := Rect2(_grid_origin, gs).grow(-10.0)
	Theme90.draw_dashed_box(self, box, Color(Theme90.SHADE.r, Theme90.SHADE.g,
		Theme90.SHADE.b, 0.45), 5.0, 1.0)
	var hint := "ПУСТО · перетащите файл или пакет"
	var w := f.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	Theme90.text(self, f, Vector2(box.get_center().x - w * 0.5,
		box.get_center().y - 6.0), hint, 12, Theme90.SHADE)


func _draw_footer(f: Font) -> void:
	draw_line(Vector2(3, size.y - 17.0), Vector2(size.x - 3, size.y - 17.0),
		Theme90.HAIRLINE, 1.0)
	Theme90.text(self, f, Vector2(4, size.y - 13.0), footer_text(), 10,
		Theme90.SHADE, size.x - 12.0)
	if not folder_name.is_empty():
		var label := folder_name.to_upper()
		var w := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		if w < size.x * 0.45:
			Theme90.text(self, f, Vector2(size.x - w - 4.0, size.y - 13.0),
				label, 10, Theme90.SHADE, w + 2.0)


func _matches_filter(file) -> bool:
	var q := _filter
	if q.is_empty():
		return true
	return str(file.name).to_lower().contains(q) or str(file.ext).to_lower().contains(q)
