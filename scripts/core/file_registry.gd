class_name FileRegistry
extends RefCounted
## Реестр склада: секции, папки, файлы и их состояния.
##
## v2: каждая папка — клеточная сетка (cols x rows), файл — полимино
## (shape_id + origin + rotation). Позиции хранятся ТОЛЬКО в folder.files /
## table при сохранении (review M12) и восстанавливаются в runtime-карту
## Folder.cells (Vector2i -> owner_id). Резервации приёма тоже занимают клетки
## (review M14: cell_occupied истинно и для файлов, и для резерваций).
##
## ВАЖНО: global class cache при `--script` может быть пустым, поэтому
## свои классы подключаем через preload, а не по имени.

signal file_added(file)
signal file_removed(file)
signal file_changed(file)
signal folder_added(folder)
signal folder_removed(folder)
signal folder_changed(folder)
signal grid_changed(folder_id)
signal table_changed
signal registry_changed

const MAX_SECTIONS = 6
const MAX_FOLDERS_PER_SECTION = 12
const MAX_FILES_PER_FOLDER = 16 # legacy (v1 capacity), v2 измеряется клетками
const MAX_FOLDER_NAME = 16
const SECTION_LETTERS: Array[String] = ["C", "D", "E", "F", "G", "H"]

const DEFAULT_COLS = 5
const DEFAULT_ROWS = 4
const DEFAULT_TABLE_COLS = 4
const DEFAULT_TABLE_ROWS = 6
const DEFAULT_FOLDERS_START = 2

## Fallback, если data/balance.json ещё не содержит grid.folder_dims.
const GRID_DIMS = [[5, 4], [6, 4], [7, 5], [8, 5], [8, 6], [9, 6]]

## Fallback-формы (совпадают с data/balance.json → grid.shapes).
const SHAPES = {
	"O1": {"cells": [[0, 0]], "w": 1, "h": 1},
	"I2H": {"cells": [[0, 0], [1, 0]], "w": 2, "h": 1},
	"I2V": {"cells": [[0, 0], [0, 1]], "w": 1, "h": 2},
	"I3H": {"cells": [[0, 0], [1, 0], [2, 0]], "w": 3, "h": 1},
	"I3V": {"cells": [[0, 0], [0, 1], [0, 2]], "w": 1, "h": 3},
	"L3a": {"cells": [[0, 0], [0, 1], [1, 1]], "w": 2, "h": 2},
	"L3b": {"cells": [[0, 0], [1, 0], [0, 1]], "w": 2, "h": 2},
	"L3c": {"cells": [[1, 0], [0, 1], [1, 1]], "w": 2, "h": 2},
	"L3d": {"cells": [[0, 0], [1, 0], [1, 1]], "w": 2, "h": 2},
	"I4H": {"cells": [[0, 0], [1, 0], [2, 0], [3, 0]], "w": 4, "h": 1},
	"I4V": {"cells": [[0, 0], [0, 1], [0, 2], [0, 3]], "w": 1, "h": 4},
	"O4": {"cells": [[0, 0], [1, 0], [0, 1], [1, 1]], "w": 2, "h": 2},
	"T4a": {"cells": [[0, 0], [1, 0], [2, 0], [1, 1]], "w": 3, "h": 2},
	"T4b": {"cells": [[0, 1], [1, 1], [2, 1], [1, 0]], "w": 3, "h": 2},
	"T4c": {"cells": [[0, 0], [0, 1], [1, 1], [0, 2]], "w": 2, "h": 3},
	"T4d": {"cells": [[1, 0], [1, 1], [0, 1], [1, 2]], "w": 2, "h": 3},
	"L4a": {"cells": [[0, 0], [0, 1], [0, 2], [1, 2]], "w": 2, "h": 3},
	"L4b": {"cells": [[0, 0], [1, 0], [2, 0], [0, 1]], "w": 3, "h": 2},
	"L4c": {"cells": [[0, 0], [1, 0], [1, 1], [1, 2]], "w": 2, "h": 3},
	"L4d": {"cells": [[2, 0], [0, 1], [1, 1], [2, 1]], "w": 3, "h": 2},
	"J4a": {"cells": [[1, 0], [1, 1], [1, 2], [0, 2]], "w": 2, "h": 3},
	"J4b": {"cells": [[0, 0], [1, 0], [2, 0], [2, 1]], "w": 3, "h": 2},
	"J4c": {"cells": [[0, 0], [0, 1], [1, 1], [2, 1]], "w": 3, "h": 2},
	"J4d": {"cells": [[0, 0], [0, 1], [0, 2], [1, 0]], "w": 2, "h": 3},
	"S4": {"cells": [[1, 0], [2, 0], [0, 1], [1, 1]], "w": 3, "h": 2},
	"Z4": {"cells": [[0, 0], [1, 0], [1, 1], [2, 1]], "w": 3, "h": 2},
}

## Fallback: тип -> формы (если data/balance.json без types.*.shapes).
const TYPE_SHAPES = {
	"text": ["O1"],
	"sound": ["I2H", "I2V"],
	"photo": ["I3H", "I3V", "L3a", "L3b", "L3c", "L3d"],
	"video": [
		"I4H", "I4V", "O4",
		"T4a", "T4b", "T4c", "T4d",
		"L4a", "L4b", "L4c", "L4d",
		"J4a", "J4b", "J4c", "J4d",
		"S4", "Z4",
	],
}

## Тип -> расширение/размер по умолчанию (если Data недоступен).
const TYPE_INFO = {
	"text": {"ext": "txt", "size_kb": 64},
	"sound": {"ext": "mp3", "size_kb": 3072},
	"photo": {"ext": "jpg", "size_kb": 5120},
	"video": {"ext": "mp4", "size_kb": 20480},
}
const DEFAULT_TYPE_INFO = {"ext": "bin", "size_kb": 128}

const FILE_ITEM_SCRIPT = preload("res://scripts/entities/file_item.gd")
const FOLDER_SCRIPT = preload("res://scripts/entities/folder.gd")
const SECTION_SCRIPT = preload("res://scripts/entities/section.gd")

var sections: Dictionary = {}
var folders: Dictionary = {}
var files: Dictionary = {}
var rng_seed: int = 0

## Стол сортировки: своя сетка 4x6, не привязан к папке.
var table_cols: int = DEFAULT_TABLE_COLS
var table_rows: int = DEFAULT_TABLE_ROWS

var _table_cells: Dictionary = {} # Vector2i -> file_id
var _reservations: Dictionary = {} # packet_id -> folder_id
var _next_folder_id: int = 1
var _next_file_id: int = 1

var _rng = RandomNumberGenerator.new()
var _rng_seed: int = 0


# --- новая смена -----------------------------------------------------------

## Чистый склад: секция C + constants.folders_start папок, файлов нет.
func setup_new_run() -> void:
	sections.clear()
	folders.clear()
	files.clear()
	_table_cells.clear()
	_reservations.clear()
	_next_folder_id = 1
	_next_file_id = 1
	table_cols = maxi(1, _const_int("table_cols", _grid_int("table_cols", DEFAULT_TABLE_COLS)))
	table_rows = maxi(1, _const_int("table_rows", _grid_int("table_rows", DEFAULT_TABLE_ROWS)))
	set_rng_seed(rng_seed)
	var section = create_section("C")
	if section != null:
		var names = ["Разное", "Входящие"]
		var count = maxi(1, _const_int("folders_start", DEFAULT_FOLDERS_START))
		for i in range(count):
			var folder_name = names[i] if i < names.size() else "Папка %d" % (i + 1)
			create_folder(section.id, folder_name)
	registry_changed.emit()


func set_rng_seed(seed_value: int) -> void:
	rng_seed = seed_value
	_rng_seed = seed_value
	_rng.seed = seed_value if seed_value != 0 else 1


# --- секции ----------------------------------------------------------------

func create_section(letter: String):
	var clean = letter.strip_edges().to_upper()
	if clean.length() != 1:
		return null
	if not SECTION_LETTERS.has(clean):
		return null
	if sections.has(clean):
		return null
	if sections.size() >= MAX_SECTIONS:
		return null
	var section = SECTION_SCRIPT.new()
	section.id = clean
	section.letter = clean
	section.name = "Секция %s" % clean
	sections[clean] = section
	registry_changed.emit()
	return section


func section_count() -> int:
	return sections.size()


# --- папки -----------------------------------------------------------------

## Новые папки допускаются только в рамках лимита 12 на секцию.
func create_folder(section_id: String, name: String):
	var section = sections.get(section_id)
	if section == null:
		return null
	var clean = name.strip_edges()
	if clean.is_empty() or clean.length() > MAX_FOLDER_NAME:
		return null
	if _folder_count_in_section(section_id) >= MAX_FOLDERS_PER_SECTION:
		return null
	if _folder_name_taken(section_id, clean):
		return null
	var dims = current_folder_dims()
	var folder = FOLDER_SCRIPT.new()
	folder.id = "fold_%d" % _next_folder_id
	_next_folder_id += 1
	folder.section = section_id
	folder.name = clean
	folder.cols = maxi(1, dims.x)
	folder.rows = maxi(1, dims.y)
	folders[folder.id] = folder
	section.folder_ids.append(folder.id)
	folder_added.emit(folder)
	registry_changed.emit()
	return folder


func rename_folder(folder_id: String, new_name: String) -> bool:
	var folder = folders.get(folder_id)
	if folder == null:
		return false
	var clean = new_name.strip_edges()
	if clean.is_empty() or clean.length() > MAX_FOLDER_NAME:
		return false
	if clean == folder.name:
		return true
	if _folder_name_taken(folder.section, clean):
		return false
	folder.name = clean
	folder_changed.emit(folder)
	registry_changed.emit()
	return true


## Удалить можно только пустую папку без файлов и резерваций.
func delete_folder(folder_id: String) -> bool:
	var folder = folders.get(folder_id)
	if folder == null:
		return false
	if folder.count() > 0 or folder.reserved_count() > 0 or folder.legacy_slots > 0:
		return false
	for f in files.values():
		if f.folder_id == folder_id and f.location != &"table":
			return false
	var section = sections.get(folder.section)
	if section != null:
		section.folder_ids.erase(folder_id)
	folders.erase(folder_id)
	folder_removed.emit(folder)
	registry_changed.emit()
	return true


func folder_count() -> int:
	return folders.size()


func _folder_count_in_section(section_id: String) -> int:
	var n = 0
	for folder in folders.values():
		if folder.section == section_id:
			n += 1
	return n


func _folder_name_taken(section_id: String, name: String) -> bool:
	var probe = name.to_lower()
	for folder in folders.values():
		if folder.section == section_id and folder.name.to_lower() == probe:
			return true
	return false


# --- формы -----------------------------------------------------------------

## Определение формы: data/balance.json → grid.shapes, иначе const SHAPES.
static func shape_def(shape_id: String) -> Dictionary:
	var data = _data_node()
	if data != null and data.has_method("shape_def"):
		var def = data.shape_def(str(shape_id))
		if def is Dictionary and not def.is_empty():
			var cells = _raw_cells(def.get("cells", []))
			if not cells.is_empty():
				var b = shape_bounds(cells)
				return {
					"id": str(shape_id),
					"cells": cells,
					"w": int(def.get("w", b.x)),
					"h": int(def.get("h", b.y)),
				}
	var fallback = SHAPES.get(str(shape_id), null)
	if fallback is Dictionary:
		return {
			"id": str(shape_id),
			"cells": _raw_cells(fallback.get("cells", [])),
			"w": int(fallback.get("w", 1)),
			"h": int(fallback.get("h", 1)),
		}
	return {"id": "O1", "cells": [Vector2i.ZERO], "w": 1, "h": 1}


## Клетки формы после поворота по часовой стрелке (0..3), нормализованы в 0.
## Статический кэш убран: он переживал смену Data/перезагрузку сцены и мог
## отдавать пустые/чужие клетки (регрессия «ЗАЙМЁТ 0 КЛЕТОК»). Вычисляем
## каждый вызов — shapes маленькие, цена незначительна.
static func shape_cells(shape_id: String, rotation: int = 0) -> Array:
	var rot := posmod(int(rotation), 4)
	var def = shape_def(shape_id)
	var cells: Array = []
	for p in def.get("cells", []):
		cells.append(_vec(p))
	for _i in range(rot):
		cells = _rotate_cw(cells)
	if cells.is_empty():
		return [Vector2i.ZERO]
	return cells


static func shape_bounds(cells: Array) -> Vector2i:
	var w = 0
	var h = 0
	for p in cells:
		var v = _vec(p)
		w = maxi(w, v.x + 1)
		h = maxi(h, v.y + 1)
	return Vector2i(w, h)


## Верхняя левая ЗАНЯТАЯ клетка (не пустой угол bbox у S/Z).
static func label_cell(cells: Array) -> Vector2i:
	if cells.is_empty():
		return Vector2i.ZERO
	var top = 2147483647
	for p in cells:
		top = mini(top, _vec(p).y)
	var left = 2147483647
	for p in cells:
		var v = _vec(p)
		if v.y == top:
			left = mini(left, v.x)
	return Vector2i(left if left != 2147483647 else 0, top if top != 2147483647 else 0)


## Случайная форма для типа. rng — RandomNumberGenerator (nullable).
static func shape_for_type(file_type: String, rng = null) -> String:
	var candidates = shape_ids_for_type(file_type)
	if candidates.is_empty():
		return "O1"
	var idx = 0
	if rng != null and rng.has_method("randi_range"):
		idx = int(rng.randi_range(0, candidates.size() - 1))
	else:
		idx = randi() % candidates.size()
	return str(candidates[idx])


static func shape_ids_for_type(file_type: String) -> Array:
	var data = _data_node()
	if data != null and data.has_method("type_def"):
		var def = data.type_def(str(file_type))
		if def is Dictionary:
			var shapes = def.get("shapes", null)
			if shapes is Array and not (shapes as Array).is_empty():
				var out: Array = []
				for s in shapes:
					out.append(str(s))
				return out
	var fallback = TYPE_SHAPES.get(str(file_type), null)
	if fallback is Array:
		return (fallback as Array).duplicate()
	return ["O1"]


static func cells_for_type(file_type: String) -> int:
	var data = _data_node()
	if data != null and data.has_method("type_def"):
		var def = data.type_def(str(file_type))
		if def is Dictionary and def.has("cells"):
			return maxi(1, int(def.get("cells", 1)))
	match str(file_type):
		"text":
			return 1
		"sound":
			return 2
		"photo":
			return 3
		"video":
			return 4
	return 1


static func _rotate_cw(cells: Array) -> Array:
	var height = 0
	for p in cells:
		height = maxi(height, _vec(p).y + 1)
	var out: Array = []
	for p in cells:
		var v = _vec(p)
		out.append(Vector2i(height - 1 - v.y, v.x))
	return _normalize_cells(out)


static func _normalize_cells(cells: Array) -> Array:
	if cells.is_empty():
		return cells
	var min_c = 2147483647
	var min_r = 2147483647
	for p in cells:
		var v = _vec(p)
		min_c = mini(min_c, v.x)
		min_r = mini(min_r, v.y)
	var out: Array = []
	for p in cells:
		var v = _vec(p)
		out.append(Vector2i(v.x - min_c, v.y - min_r))
	return out


static func _raw_cells(raw) -> Array:
	var out: Array = []
	if raw is Array:
		for p in raw:
			out.append(_vec(p))
	return out


static func _vec(value) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Vector2:
		return Vector2i(int(value.x), int(value.y))
	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	if value is Dictionary:
		return Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))
	return Vector2i.ZERO


# --- размеры сетки ---------------------------------------------------------

## Текущий размер сетки: Game.folder_dims() (учитывает лот), иначе данные.
func current_folder_dims() -> Vector2i:
	var game = _game_node()
	if game != null and game.has_method("folder_dims"):
		var dims = game.call("folder_dims")
		if dims is Vector2i and (dims as Vector2i).x > 0 and (dims as Vector2i).y > 0:
			return dims
	var level = 0
	if game != null:
		var upgrades = game.get("upgrades")
		if upgrades is Dictionary:
			level = int((upgrades as Dictionary).get("folder_level", 0))
	var table = grid_dims_table()
	if table.is_empty():
		return Vector2i(DEFAULT_COLS, DEFAULT_ROWS)
	var pair = table[clampi(level, 0, table.size() - 1)]
	if pair is Array and (pair as Array).size() >= 2:
		return Vector2i(int(pair[0]), int(pair[1]))
	return Vector2i(DEFAULT_COLS, DEFAULT_ROWS)


func grid_dims_table() -> Array:
	var data = _data_node()
	if data != null:
		var constants = data.get("constants")
		if constants is Dictionary:
			var raw = (constants as Dictionary).get("grid_dims", null)
			if raw is Array and not (raw as Array).is_empty():
				return _pairs(raw)
		var grid = data.get("grid")
		if grid is Dictionary:
			var raw2 = (grid as Dictionary).get("folder_dims", null)
			if raw2 is Array and not (raw2 as Array).is_empty():
				return _pairs(raw2)
		if data.has_method("folder_dims_table"):
			var raw3 = data.folder_dims_table()
			if raw3 is Array and not (raw3 as Array).is_empty():
				return _pairs(raw3)
	return _pairs(GRID_DIMS)


func _pairs(raw: Array) -> Array:
	var out: Array = []
	for pair in raw:
		if pair is Array and (pair as Array).size() >= 2:
			out.append([int(pair[0]), int(pair[1])])
		elif pair is Vector2i:
			out.append([(pair as Vector2i).x, (pair as Vector2i).y])
	return out


# --- размещение в папке ----------------------------------------------------

func can_place(folder_ref, shape_id: String, origin: Vector2i, rotation: int, ignore_file_id: String = "") -> bool:
	var folder = _resolve_folder(folder_ref)
	if folder == null:
		return false
	for cell in shape_cells(shape_id, rotation):
		var c = origin.x + cell.x
		var r = origin.y + cell.y
		if c < 0 or r < 0 or c >= folder.cols or r >= folder.rows:
			return false
		var owner = folder.owner_at(c, r)
		if not owner.is_empty() and owner != ignore_file_id:
			return false
	return true


## Точное размещение файла (origin/rotation уже выбраны).
func place_file(file_id: String, folder_id: String, origin: Vector2i, rotation: int) -> bool:
	var file = files.get(file_id)
	var folder = folders.get(folder_id)
	if file == null or folder == null:
		return false
	if file.location == &"attached" or not file.attached_request.is_empty():
		return false
	if file.location == &"locked" or file.location == &"failed" or file.location == &"malicious":
		return false
	_ensure_shape(file)
	if not can_place(folder, file.shape_id, origin, rotation, file.id):
		return false
	_clear_file_placement(file)
	_put_in_folder(file, folder, origin, rotation)
	_after_placement_change(file, folder, "")
	return true


## First-fit: текущий поворот, затем 0..3; строки, потом столбцы.
func auto_place_file(file_id: String, folder_id: String) -> bool:
	var file = files.get(file_id)
	var folder = folders.get(folder_id)
	if file == null or folder == null:
		return false
	if file.location == &"attached" or not file.attached_request.is_empty():
		return false
	if file.location == &"locked" or file.location == &"failed" or file.location == &"malicious":
		return false
	_ensure_shape(file)
	var fit = _find_fit(folder, file.shape_id, file.rotation)
	if fit.is_empty():
		return false
	_clear_file_placement(file)
	_put_in_folder(file, folder, fit.origin, fit.rotation)
	_after_placement_change(file, folder, "")
	return true


## Перемещение: origin=(-1,-1) → auto-place, иначе точное размещение.
## Файл, зарезервированный под запрос (required_by), ПЕРЕМЕЩАТЬ МЕЖДУ ПАПКАМИ
## можно: запрос ищет файл по id и остаётся выполнимым из любой папки, а карточка
## запроса показывает актуальную папку. Блокируются только разрушительные
## действия (destroy_file/remove_file/move_file_to_table) и прикрепление к
## другому запросу (attach_file).
func move_file(file_id: String, folder_id: String, origin: Vector2i = Vector2i(-1, -1), rotation: int = -1) -> bool:
	var file = files.get(file_id)
	if file == null:
		return false
	if file.location == &"attached" or not file.attached_request.is_empty():
		return false
	if file.location == &"locked" or file.location == &"failed" or file.location == &"malicious":
		return false
	var target = folders.get(folder_id)
	if target == null:
		return false
	if origin.x < 0 or origin.y < 0:
		return auto_place_file(file_id, folder_id)
	var use_rotation = file.rotation if rotation < 0 else rotation
	return place_file(file_id, folder_id, origin, use_rotation)


func file_origin(file_id: String) -> Vector2i:
	var file = files.get(file_id)
	return file.origin if file != null else Vector2i(-1, -1)


func file_rotation(file_id: String) -> int:
	var file = files.get(file_id)
	return int(file.rotation) if file != null else 0


func file_shape_cells(file_id: String) -> Array:
	var file = files.get(file_id)
	if file == null:
		return []
	return shape_cells(file.shape_id, file.rotation)


## Абсолютная клетка подписи файла в сетке папки/стола.
func file_label_cell(file_id: String) -> Vector2i:
	var file = files.get(file_id)
	if file == null:
		return Vector2i(-1, -1)
	return file.origin + label_cell(shape_cells(file.shape_id, file.rotation))


func occupied_cells(folder_id: String = "") -> int:
	if folder_id == "table":
		return _table_cells.size()
	if folder_id.is_empty():
		var total = 0
		for folder in folders.values():
			total += folder.cells.size()
		return total
	var folder = folders.get(folder_id)
	return folder.cells.size() if folder != null else 0


func free_cells(folder_id: String = "") -> int:
	if folder_id == "table":
		return maxi(0, table_cols * table_rows - _table_cells.size())
	if folder_id.is_empty():
		var total = 0
		for folder in folders.values():
			total += folder.free_cell_count()
		return total
	var folder = folders.get(folder_id)
	return folder.free_cell_count() if folder != null else 0


func total_cells(folder_id: String = "") -> int:
	if folder_id == "table":
		return table_cols * table_rows
	if folder_id.is_empty():
		var total = 0
		for folder in folders.values():
			total += folder.total_cells()
		return total
	var folder = folders.get(folder_id)
	return folder.total_cells() if folder != null else 0


## Влезает ли фигура (любой поворот) хоть в одну незаблокированную папку.
## excluded_folders — dictionary, где ключи — id заблокированных папок.
func can_fit_anywhere(shape_id: String, preferred_rotation: int = 0,
		excluded_folders: Dictionary = {}) -> bool:
	var shape := str(shape_id)
	if shape.is_empty():
		shape = "O1"
	return _shape_fits_in_any_folder(shape, preferred_rotation, excluded_folders)


## Общий precheck: в папке должно быть хотя бы cells.size() свободных клеток.
func _shape_fits_in_any_folder(shape: String, preferred_rotation: int,
		excluded_folders: Dictionary) -> bool:
	var need := shape_cells(shape, preferred_rotation).size()
	for folder_id in folders.keys():
		if excluded_folders.has(str(folder_id)):
			continue
		var folder = folders[folder_id]
		if folder == null:
			continue
		if folder.free_cell_count() < need:
			continue
		if not _find_fit(folder, shape, preferred_rotation).is_empty():
			return true
	return false


## Влезает ли хоть одна фигура указанного типа в незаблокированную папку.
## Использует кэш shape_cells и тот же precheck по свободным клеткам.
func can_fit_type_anywhere(file_type: String, excluded_folders: Dictionary = {}) -> bool:
	for shape_id in shape_ids_for_type(str(file_type)):
		if _shape_fits_in_any_folder(str(shape_id), 0, excluded_folders):
			return true
	return false


## Первая фигура типа, которая реально влезает в незаблокированную папку.
## "" — ни одна не влезает. rng зарезервирован для будущей вариативности.
func shape_for_type_fitting(file_type: String, excluded_folders: Dictionary = {},
		_rng = null) -> String:
	for shape_id in shape_ids_for_type(str(file_type)):
		if _shape_fits_in_any_folder(str(shape_id), 0, excluded_folders):
			return str(shape_id)
	return ""


func folder_cell_stats(folder_id: String) -> Dictionary:
	return {
		"occupied": occupied_cells(folder_id),
		"free": free_cells(folder_id),
		"total": total_cells(folder_id),
		"files": get_folder_files(folder_id).size() if folder_id != "table" else table_file_count(),
		"reserved": reservation_count(folder_id) if folder_id != "table" else 0,
	}


# --- файлы -----------------------------------------------------------------

## Создать файл. Имя уникально в пределах забега (без учёта регистра).
## Форма выбирается случайно; при location="folder" файл сразу раскладывается
## first-fit. Если места нет — null (пакет остаётся в буфере/на столе).
func create_file(name: String, type: String, folder_id: String, location: StringName = &"folder"):
	var clean = name.strip_edges()
	if clean.is_empty():
		return null
	if find_by_name(clean) != null:
		return null
	var loc = String(location)
	if loc != "folder" and loc != "registry" and loc != "table":
		return null
	_sync_rng()
	var shape = shape_for_type(type, _rng)
	var folder = null
	var fit: Dictionary = {}
	if loc == "folder":
		folder = folders.get(folder_id)
		if folder == null:
			return null
		fit = _find_fit(folder, shape, 0)
		if fit.is_empty():
			return null
	elif loc == "table":
		fit = _find_table_fit(shape, 0)
		if fit.is_empty():
			return null
	var file = _make_file(clean, type, shape)
	if loc == "folder":
		_put_in_folder(file, folder, fit.origin, fit.rotation)
		file.location = &"folder"
	elif loc == "table":
		_stamp_table(file, fit.origin, fit.rotation)
		file.location = &"table"
	else:
		file.location = &"registry"
		file.folder_id = ""
	files[file.id] = file
	file_added.emit(file)
	if loc == "folder":
		_emit_grid(folder)
	elif loc == "table":
		table_changed.emit()
	registry_changed.emit()
	return file


# --- стол сортировки -------------------------------------------------------

func table_total_cells() -> int:
	return maxi(0, table_cols) * maxi(0, table_rows)


func table_occupied_cells() -> int:
	return _table_cells.size()


func table_free_cells() -> int:
	return maxi(0, table_total_cells() - _table_cells.size())


func table_file_count() -> int:
	var n = 0
	for file in files.values():
		if file.location == &"table":
			n += 1
	return n


func table_files() -> Array:
	var out: Array = []
	for file in files.values():
		if file.location == &"table":
			out.append(file)
	return out


func is_table_file(file_id: String) -> bool:
	var file = files.get(file_id)
	return file != null and file.location == &"table"


func can_place_table(shape_id: String, origin: Vector2i, rotation: int, ignore_file_id: String = "") -> bool:
	for cell in shape_cells(shape_id, rotation):
		var c = origin.x + cell.x
		var r = origin.y + cell.y
		if c < 0 or r < 0 or c >= table_cols or r >= table_rows:
			return false
		var owner = str(_table_cells.get(Vector2i(c, r), ""))
		if not owner.is_empty() and owner != ignore_file_id:
			return false
	return true


func auto_place_table(file_id: String) -> bool:
	var file = files.get(file_id)
	if file == null:
		return false
	if file.location == &"attached" or not file.attached_request.is_empty():
		return false
	_ensure_shape(file)
	var fit = _find_table_fit(file.shape_id, file.rotation)
	if fit.is_empty():
		return false
	_clear_table_cells(file.id)
	_stamp_table(file, fit.origin, fit.rotation)
	file.location = &"table"
	file_changed.emit(file)
	table_changed.emit()
	registry_changed.emit()
	return true


func move_file_to_table(file_id: String, origin: Vector2i = Vector2i(-1, -1), rotation: int = -1) -> bool:
	var file = files.get(file_id)
	if file == null:
		return false
	if not file.required_by.is_empty():
		return false
	if file.location == &"attached" or not file.attached_request.is_empty():
		return false
	if file.location == &"locked" or file.location == &"failed" or file.location == &"malicious":
		return false
	_ensure_shape(file)
	var use_rotation = file.rotation if rotation < 0 else rotation
	var target = origin
	if target.x < 0 or target.y < 0:
		var fit = _find_table_fit(file.shape_id, use_rotation)
		if fit.is_empty():
			return false
		target = fit.origin
		use_rotation = fit.rotation
	elif not can_place_table(file.shape_id, target, use_rotation, file.id):
		return false
	var old_folder = folders.get(file.folder_id)
	_clear_file_placement(file)
	_stamp_table(file, target, use_rotation)
	file.location = &"table"
	file.attached_request = ""
	if old_folder != null:
		folder_changed.emit(old_folder)
	file_changed.emit(file)
	table_changed.emit()
	registry_changed.emit()
	return true


func move_from_table(file_id: String, folder_id: String = "", origin: Vector2i = Vector2i(-1, -1), rotation: int = -1) -> bool:
	var file = files.get(file_id)
	if file == null or file.location != &"table":
		return false
	var target_id = folder_id
	if target_id.is_empty():
		target_id = file.folder_id
	if target_id.is_empty() or not folders.has(target_id):
		target_id = _first_folder_id_with_space(file)
	if target_id.is_empty():
		return false
	var folder = folders.get(target_id)
	_ensure_shape(file)
	var use_rotation = file.rotation if rotation < 0 else rotation
	var target = origin
	if target.x < 0 or target.y < 0:
		var fit = _find_fit(folder, file.shape_id, use_rotation)
		if fit.is_empty():
			return false
		target = fit.origin
		use_rotation = fit.rotation
	elif not can_place(folder, file.shape_id, target, use_rotation, file.id):
		return false
	_clear_table_cells(file.id)
	_put_in_folder(file, folder, target, use_rotation)
	file.location = &"folder"
	file_changed.emit(file)
	table_changed.emit()
	_emit_grid(folder)
	registry_changed.emit()
	return true


## Вернуть все файлы со стола в папки (перед стартом часа).
## false, если хотя бы один не влез — он остаётся на столе.
func auto_return_table() -> bool:
	var all_ok = true
	for file in table_files():
		var ok = false
		if not file.folder_id.is_empty() and folders.has(file.folder_id):
			ok = move_from_table(file.id, file.folder_id)
		if not ok:
			var target = _first_folder_id_with_space(file)
			if not target.is_empty():
				ok = move_from_table(file.id, target)
		if not ok:
			all_ok = false
	return all_ok


# --- резервации приёма -----------------------------------------------------

func reserve_packet(packet_id: String, folder_id: String, shape_id: String, rotation: int, origin: Vector2i) -> bool:
	var folder = folders.get(folder_id)
	if folder == null or packet_id.is_empty():
		return false
	if _reservations.has(packet_id):
		return false
	var shape = shape_id if not shape_id.is_empty() else "O1"
	if not can_place(folder, shape, origin, rotation):
		return false
	var rot = posmod(int(rotation), 4)
	folder.reserved[packet_id] = {
		"shape_id": shape,
		"origin": origin,
		"rotation": rot,
	}
	for cell in shape_cells(shape, rot):
		folder.cells[origin + cell] = packet_id
	_reservations[packet_id] = folder.id
	folder_changed.emit(folder)
	grid_changed.emit(folder.id)
	registry_changed.emit()
	return true


func auto_reserve_packet(packet_id: String, folder_id: String, shape_id: String, preferred_rotation: int = 0) -> Dictionary:
	var folder = folders.get(folder_id)
	if folder == null or packet_id.is_empty():
		return {"ok": false}
	if _reservations.has(packet_id):
		return get_reservation(packet_id)
	var shape = shape_id if not shape_id.is_empty() else "O1"
	var fit = _find_fit(folder, shape, preferred_rotation)
	if fit.is_empty():
		return {"ok": false}
	if not reserve_packet(packet_id, folder_id, shape, fit.rotation, fit.origin):
		return {"ok": false}
	return {
		"ok": true,
		"packet_id": packet_id,
		"folder_id": folder_id,
		"shape_id": shape,
		"origin": fit.origin,
		"rotation": fit.rotation,
	}


## Завершить загрузку: превратить резервацию в файл на тех же клетках.
func confirm_reservation(packet_id: String, name: String, type: String):
	var folder = _folder_for_reservation(packet_id)
	if folder == null:
		return null
	var res: Dictionary = folder.reserved.get(packet_id, {})
	if res.is_empty():
		return null
	var clean = name.strip_edges()
	if clean.is_empty() or find_by_name(clean) != null:
		return null
	_sync_rng()
	var shape = str(res.get("shape_id", "O1"))
	var origin: Vector2i = res.get("origin", Vector2i.ZERO)
	var rot = int(res.get("rotation", 0))
	_release_reservation(packet_id, folder)
	var file = _make_file(clean, type, shape)
	_put_in_folder(file, folder, origin, rot)
	file.location = &"folder"
	files[file.id] = file
	file_added.emit(file)
	_emit_grid(folder)
	registry_changed.emit()
	return file


func cancel_reservation(packet_id: String) -> bool:
	var folder = _folder_for_reservation(packet_id)
	if folder == null:
		return false
	_release_reservation(packet_id, folder)
	folder_changed.emit(folder)
	grid_changed.emit(folder.id)
	registry_changed.emit()
	return true


func get_reservation(packet_id: String) -> Dictionary:
	var folder = _folder_for_reservation(packet_id)
	if folder == null:
		return {"ok": false}
	var res: Dictionary = folder.reserved.get(packet_id, {})
	if res.is_empty():
		return {"ok": false}
	return {
		"ok": true,
		"packet_id": packet_id,
		"folder_id": folder.id,
		"shape_id": str(res.get("shape_id", "O1")),
		"origin": res.get("origin", Vector2i.ZERO),
		"rotation": int(res.get("rotation", 0)),
	}


func reservation_count(folder_id: String = "") -> int:
	if folder_id.is_empty():
		return _reservations.size()
	if folder_id == "table":
		return 0
	var folder = folders.get(folder_id)
	return folder.reserved.size() if folder != null else 0


func folder_reservations(folder_id: String) -> Array:
	var out: Array = []
	var folder = folders.get(folder_id)
	if folder == null:
		return out
	for packet_id in folder.reserved.keys():
		var info = get_reservation(str(packet_id))
		if not info.is_empty() and bool(info.get("ok", false)):
			out.append(info)
	return out


func reserved_cells(folder_id: String) -> Array:
	var out: Array = []
	var folder = folders.get(folder_id)
	if folder == null:
		return out
	for packet_id in folder.reserved.keys():
		for cell in shape_cells(str(folder.reserved[packet_id].get("shape_id", "O1")), int(folder.reserved[packet_id].get("rotation", 0))):
			out.append(Vector2i(folder.reserved[packet_id].get("origin", Vector2i.ZERO)) + cell)
	return out


# --- legacy-слоты загрузки (v1 API) ---------------------------------------

func reserve_slot(folder_id: String) -> bool:
	var folder = folders.get(folder_id)
	if folder == null:
		return false
	if folder.free_cell_count() <= folder.legacy_slots:
		return false
	folder.legacy_slots += 1
	folder_changed.emit(folder)
	registry_changed.emit()
	return true


func release_slot(folder_id: String) -> bool:
	var folder = folders.get(folder_id)
	if folder == null or folder.legacy_slots <= 0:
		return false
	folder.legacy_slots -= 1
	folder_changed.emit(folder)
	registry_changed.emit()
	return true


# --- прикрепление к запросам ----------------------------------------------

## Прикрепить файл к запросу. Файл остаётся в папке, меняется location.
func attach_file(file_id: String, request_id: String, now: float = -1.0) -> bool:
	var file = files.get(file_id)
	if file == null:
		return false
	if request_id.is_empty():
		return false
	if file.location == &"table":
		return false
	if not file.required_by.is_empty() and file.required_by != request_id:
		return false
	if not file.attached_request.is_empty():
		return false
	if not file.can_attach(now):
		return false
	file.attached_request = request_id
	file.location = &"attached"
	file_changed.emit(file)
	# Смена location не меняет клетки, но FileGrid должен перечитать состояние
	# файла (attached-бейдж/подпись), иначе UI живёт со старым снимком.
	_emit_grid(folders.get(file.folder_id))
	registry_changed.emit()
	return true


func detach_file(file_id: String) -> bool:
	var file = files.get(file_id)
	if file == null:
		return false
	if file.location != &"attached" and file.attached_request.is_empty():
		return false
	file.attached_request = ""
	if file.location != &"table":
		if not file.folder_id.is_empty() and folders.has(file.folder_id):
			file.location = &"folder"
		else:
			file.location = &"registry"
			file.folder_id = ""
	file_changed.emit(file)
	# После detach файл снова должен быть виден в своей папке: старый grid
	# мог быть отрисован, пока файл числился attached/в другой папке.
	_emit_grid(folders.get(file.folder_id))
	registry_changed.emit()
	return true


# --- состояния -------------------------------------------------------------

func mark_failed(file_id: String) -> bool:
	var file = files.get(file_id)
	if file == null:
		return false
	file.location = &"failed"
	file.attached_request = ""
	# Проваленный файл больше не может обслужить запрос: снимаем резерв,
	# иначе он навсегда остаётся «занятым» и его нельзя уничтожить.
	file.required_by = ""
	file.lock_until = 0.0
	file.cooldown_until = 0.0
	file._location_before_lock = &"folder" if not file.folder_id.is_empty() else &"registry"
	file_changed.emit(file)
	registry_changed.emit()
	return true


func mark_malicious(file_id: String, kind: String) -> bool:
	var file = files.get(file_id)
	if file == null:
		return false
	file.location = &"malicious"
	file.malicious_kind = kind
	file.attached_request = ""
	# Заражённый файл не является валидной резервацией запроса: снимаем
	# required_by, иначе запрос навсегда ждёт мёртвый файл, а удалить его нельзя.
	file.required_by = ""
	file.lock_until = 0.0
	file.cooldown_until = 0.0
	file._location_before_lock = &"folder" if not file.folder_id.is_empty() else &"registry"
	file_changed.emit(file)
	registry_changed.emit()
	return true


func lock_file(file_id: String, seconds: float, now: float = -1.0) -> bool:
	var file = files.get(file_id)
	if file == null:
		return false
	if file.location == &"failed" or file.location == &"malicious":
		return false
	if now < 0.0:
		now = FILE_ITEM_SCRIPT.now_unix()
	if file.location == &"folder" or file.location == &"registry" or file.location == &"table":
		file._location_before_lock = file.location
	if file.location == &"attached":
		file.attached_request = ""
	file.location = &"locked"
	file.lock_until = now + maxf(0.0, seconds)
	file_changed.emit(file)
	registry_changed.emit()
	return true


func unlock_file(file_id: String) -> bool:
	var file = files.get(file_id)
	if file == null or file.location != &"locked":
		return false
	var prev: StringName = file._location_before_lock
	if prev != &"folder" and prev != &"registry":
		prev = &"folder" if not file.folder_id.is_empty() else &"registry"
	if prev == &"folder" and not folders.has(file.folder_id):
		prev = &"registry"
	file.location = prev
	file.lock_until = 0.0
	if prev == &"registry":
		file.folder_id = ""
	file_changed.emit(file)
	registry_changed.emit()
	return true


## Выставить cooldown после успешной отправки (D02).
func set_cooldown(file_id: String, seconds: float, now: float = -1.0) -> bool:
	var file = files.get(file_id)
	if file == null:
		return false
	if now < 0.0:
		now = FILE_ITEM_SCRIPT.now_unix()
	file.cooldown_until = now + maxf(0.0, seconds)
	file_changed.emit(file)
	registry_changed.emit()
	return true


## Снять истёкшие lock/cooldown. Возвращает число изменённых файлов.
func tick(now: float) -> int:
	var changed = 0
	for file_id in files.keys():
		var file = files[file_id]
		if file.lock_until > 0.0 and now >= file.lock_until:
			if unlock_file(file_id):
				changed += 1
			continue
		if file.cooldown_until > 0.0 and now >= file.cooldown_until:
			file.cooldown_until = 0.0
			file_changed.emit(file)
			registry_changed.emit()
			changed += 1
	return changed


# --- удаление / расход -----------------------------------------------------

## Успешная отправка: файл исчезает из папки/стола и реестра.
func consume_file(file_id: String) -> bool:
	var file = files.get(file_id)
	if file == null:
		return false
	_clear_file_placement(file)
	files.erase(file_id)
	file_removed.emit(file)
	registry_changed.emit()
	return true


## v1-совместимое удаление: без force только malicious/failed.
## force=true разрешает любой НЕ прикреплённый файл (M16: выход из soft-lock
## при нехватке денег), но не attached.
func remove_file(file_id: String, force: bool = false) -> bool:
	var file = files.get(file_id)
	if file == null:
		return false
	# Файл зарезервирован под конкретный запрос: удалять нельзя.
	if not file.required_by.is_empty():
		return false
	if file.location == &"attached" or not file.attached_request.is_empty():
		return false
	if not force and file.location != &"malicious" and file.location != &"failed":
		return false
	_clear_file_placement(file)
	files.erase(file_id)
	file_removed.emit(file)
	registry_changed.emit()
	return true


## Явное уничтожение (контекстное меню/модалка). Attached нельзя.
func destroy_file(file_id: String) -> bool:
	return remove_file(file_id, true)


func destroy_malicious(file_id: String) -> bool:
	var file = files.get(file_id)
	if file == null or file.location != &"malicious":
		return false
	return remove_file(file_id)


# --- рост сетки и дефрагментация ------------------------------------------

## Лоты only grow: меньшие размеры игнорируются по каждой оси.
func resize_folders(new_dims: Vector2i) -> void:
	var changed_any = false
	for folder in folders.values():
		var nc = maxi(folder.cols, maxi(1, new_dims.x))
		var nr = maxi(folder.rows, maxi(1, new_dims.y))
		if nc != folder.cols or nr != folder.rows:
			folder.cols = nc
			folder.rows = nr
			folder_changed.emit(folder)
			grid_changed.emit(folder.id)
			changed_any = true
	if changed_any:
		registry_changed.emit()


## First-fit repack. При неудаче откатывает исходные позиции.
func defrag_folder(folder_id: String) -> bool:
	var folder = folders.get(folder_id)
	if folder == null:
		return false
	var snapshot: Array = []
	for fid in folder.file_ids:
		var file = files.get(fid)
		if file == null:
			continue
		snapshot.append({"file": file, "origin": file.origin, "rotation": file.rotation})
	folder.cells.clear()
	var pending: Array = []
	for item in snapshot:
		var file = item["file"]
		var fit = _find_fit(folder, file.shape_id, file.rotation)
		if fit.is_empty():
			pending.append(item)
			continue
		_stamp_file(folder, file, fit.origin, fit.rotation)
	if not pending.is_empty():
		folder.cells.clear()
		for item in snapshot:
			var file = item["file"]
			_stamp_file(folder, file, item["origin"], item["rotation"])
		return false
	for item in snapshot:
		var file = item["file"]
		file_changed.emit(file)
	_emit_grid(folder)
	registry_changed.emit()
	return true


# --- выборки ---------------------------------------------------------------

func get_folder_files(folder_id: String) -> Array:
	var out: Array = []
	var folder = folders.get(folder_id)
	if folder == null:
		return out
	for file_id in folder.file_ids:
		if files.has(file_id):
			out.append(files[file_id])
	return out


func get_available_files(now: float = -1.0) -> Array:
	var out: Array = []
	for file in files.values():
		if file.is_available(now):
			out.append(file)
	return out


## Файлы, полученные, но ещё не разложенные по папкам (location == registry).
func get_pending_files() -> Array:
	var out: Array = []
	for file in files.values():
		if file.location == &"registry":
			out.append(file)
	return out


func find_by_name(name: String):
	var probe = name.strip_edges().to_lower()
	if probe.is_empty():
		return null
	for file in files.values():
		if file.name.to_lower() == probe or file.display_name().to_lower() == probe:
			return file
	return null


func all_files() -> Array:
	return files.values()


func file_count() -> int:
	return files.size()


func get_file(file_id: String):
	return files.get(file_id)


func get_folder(folder_id: String):
	return folders.get(folder_id)


func folder_files_count(folder_id: String) -> int:
	var folder = folders.get(folder_id)
	return folder.count() if folder != null else 0


# --- сохранение ------------------------------------------------------------

func to_dict() -> Dictionary:
	var raw_sections = {}
	for key in sections.keys():
		raw_sections[key] = sections[key].to_dict()
	var raw_folders = {}
	for folder in folders.values():
		var placements: Array = []
		for file_id in folder.file_ids:
			var file = files.get(file_id)
			if file == null:
				continue
			placements.append({
				"id": file.id,
				"shape_id": file.shape_id,
				"origin": [file.origin.x, file.origin.y],
				"rotation": file.rotation,
			})
		var reserved: Array = []
		for packet_id in folder.reserved.keys():
			var res: Dictionary = folder.reserved[packet_id]
			var origin: Vector2i = res.get("origin", Vector2i.ZERO)
			reserved.append({
				"packet_id": str(packet_id),
				"shape_id": str(res.get("shape_id", "O1")),
				"origin": [origin.x, origin.y],
				"rotation": int(res.get("rotation", 0)),
			})
		raw_folders[folder.id] = {
			"id": folder.id,
			"section": folder.section,
			"name": folder.name,
			"cols": folder.cols,
			"rows": folder.rows,
			"files": placements,
			"reserved": reserved,
		}
	var raw_files = {}
	for file in files.values():
		# Позиции НЕ дублируем: они живут в folders[].files / table.
		raw_files[file.id] = file.to_dict(false)
	var table: Array = []
	for file in files.values():
		if file.location == &"table":
			table.append({
				"file_id": file.id,
				"origin": [file.origin.x, file.origin.y],
				"rotation": file.rotation,
			})
	return {
		"rng_seed": rng_seed,
		"next_folder_id": _next_folder_id,
		"next_file_id": _next_file_id,
		"sections": raw_sections,
		"folders": raw_folders,
		"files": raw_files,
		"table": table,
	}


func from_dict(d: Dictionary) -> bool:
	if d == null or d.is_empty():
		return false
	sections.clear()
	folders.clear()
	files.clear()
	_table_cells.clear()
	_reservations.clear()
	rng_seed = int(d.get("rng_seed", 0))
	set_rng_seed(rng_seed)
	_next_folder_id = maxi(1, int(d.get("next_folder_id", 1)))
	_next_file_id = maxi(1, int(d.get("next_file_id", 1)))
	table_cols = maxi(1, _const_int("table_cols", _grid_int("table_cols", DEFAULT_TABLE_COLS)))
	table_rows = maxi(1, _const_int("table_rows", _grid_int("table_rows", DEFAULT_TABLE_ROWS)))

	var raw_sections = _dict_of(d.get("sections", {}))
	for key in raw_sections.keys():
		var raw = raw_sections[key]
		if not (raw is Dictionary):
			continue
		var section = SECTION_SCRIPT.from_dict(raw)
		if section.id.is_empty():
			section.id = str(key)
		if section.letter.is_empty():
			section.letter = section.id
		sections[section.id] = section

	var specs = {}
	var raw_folders = _dict_of(d.get("folders", {}))
	for key in raw_folders.keys():
		var raw = raw_folders[key]
		if not (raw is Dictionary):
			continue
		var folder = FOLDER_SCRIPT.from_dict(raw)
		if folder.id.is_empty():
			folder.id = str(key)
		if not sections.has(folder.section):
			continue
		folders[folder.id] = folder
		specs[folder.id] = {
			"files": raw.get("files", []),
			"file_ids": raw.get("file_ids", []),
			"reserved": raw.get("reserved", []),
		}

	var raw_files = _dict_of(d.get("files", {}))
	for key in raw_files.keys():
		var raw = raw_files[key]
		if not (raw is Dictionary):
			continue
		var file = FILE_ITEM_SCRIPT.from_dict(raw)
		if file.id.is_empty():
			file.id = str(key)
		files[file.id] = file

	_migrate(raw_files, specs)
	_restore_table(d.get("table", []))
	_repair_after_load()
	registry_changed.emit()
	return true


## Разложить файлы по папкам, мигрируя v1 и восстанавливая позиции v2.
func _migrate(raw_files: Dictionary, specs: Dictionary) -> void:
	var legacy_dims = current_folder_dims()
	var leftovers: Array = []
	for folder in folders.values():
		var spec: Dictionary = specs.get(folder.id, {})
		var legacy_missing_dims = folder.cols <= 0 or folder.rows <= 0
		var dims = Vector2i(folder.cols, folder.rows)
		if legacy_missing_dims:
			dims = legacy_dims
		folder.cols = maxi(1, dims.x)
		folder.rows = maxi(1, dims.y)
		folder.file_ids.clear()
		folder.cells.clear()
		folder.reserved.clear()

		var order: Array = []
		var placement_by_id = {}
		var raw_placements = spec.get("files", [])
		if raw_placements is Array:
			for entry in raw_placements:
				if entry is Dictionary:
					var fid = str(entry.get("id", ""))
					if fid.is_empty():
						continue
					if not order.has(fid):
						order.append(fid)
					placement_by_id[fid] = entry
		var raw_ids = spec.get("file_ids", [])
		if raw_ids is Array:
			for value in raw_ids:
				var fid2 = str(value)
				if not fid2.is_empty() and not order.has(fid2):
					order.append(fid2)
		for fid3 in files.keys():
			var f = files[fid3]
			if f.folder_id == folder.id and f.location != &"table" and not order.has(str(fid3)):
				order.append(str(fid3))

		if legacy_missing_dims:
			_ensure_legacy_capacity(folder, order.size())

		var pending: Array = []
		for idx in range(order.size()):
			var fid4 = str(order[idx])
			var file = files.get(fid4)
			if file == null:
				continue
			var entry: Dictionary = placement_by_id.get(fid4, {})
			var raw_meta = raw_files.get(fid4, {})
			if entry.has("shape_id") and not str(entry.get("shape_id", "")).is_empty():
				file.shape_id = str(entry.get("shape_id"))
			elif not (raw_meta is Dictionary and (raw_meta as Dictionary).has("shape_id")):
				file.shape_id = _shape_for_migration(file.type, idx)
			if file.shape_id.is_empty():
				file.shape_id = "O1"
			file.rotation = posmod(int(entry.get("rotation", file.rotation)), 4)
			if entry.has("origin"):
				var origin: Vector2i = _vec(entry.get("origin"))
				if can_place(folder, file.shape_id, origin, file.rotation):
					_stamp_file(folder, file, origin, file.rotation)
					_mark_placed(file)
					continue
			pending.append(file)

		var unresolved: Array = []
		for file in pending:
			var fit = _find_fit(folder, file.shape_id, file.rotation)
			if fit.is_empty():
				unresolved.append(file)
			else:
				_stamp_file(folder, file, fit.origin, fit.rotation)
				_mark_placed(file)
		if not unresolved.is_empty():
			unresolved = _try_grow_and_place(folder, unresolved)
		for file in unresolved:
			leftovers.append(file)

		_restore_reservations(folder, spec.get("reserved", []))

	# Файлы, которым не хватило папок: сначала стол, потом registry (без потерь).
	for file in leftovers:
		file.folder_id = ""
		file.origin = Vector2i.ZERO
		file.rotation = 0
		file.shape_cells = shape_cells(file.shape_id, 0)
		var fit_table = _find_table_fit(file.shape_id, 0)
		if not fit_table.is_empty():
			_stamp_table(file, fit_table.origin, fit_table.rotation)
			file.location = &"table"
		else:
			file.location = &"registry"
			push_warning("FileRegistry: файл %s не влез ни в папку, ни на стол" % file.id)


## Пытается вырастить папку до ближайшей grid_dims, где влезают все файлы.
func _try_grow_and_place(folder, unresolved: Array) -> Array:
	var origin_dims = Vector2i(folder.cols, folder.rows)
	var candidates = grid_dims_table()
	for candidate in candidates:
		var target = Vector2i(maxi(origin_dims.x, int(candidate[0])), maxi(origin_dims.y, int(candidate[1])))
		if target == origin_dims:
			continue
		if target.x < folder.cols or target.y < folder.rows:
			continue
		folder.cols = target.x
		folder.rows = target.y
		var still: Array = []
		for file in unresolved:
			var fit = _find_fit(folder, file.shape_id, file.rotation)
			if fit.is_empty():
				still.append(file)
			else:
				_stamp_file(folder, file, fit.origin, fit.rotation)
				_mark_placed(file)
		if still.is_empty():
			return []
		unresolved = still
	return unresolved


## v1: не уменьшать ёмкость старой папки (16 файлов) при миграции.
func _ensure_legacy_capacity(folder, file_count: int) -> void:
	var needed = maxi(MAX_FILES_PER_FOLDER, maxi(0, file_count))
	if folder.total_cells() >= needed:
		return
	for pair in grid_dims_table():
		if int(pair[0]) * int(pair[1]) >= needed:
			folder.cols = maxi(folder.cols, int(pair[0]))
			folder.rows = maxi(folder.rows, int(pair[1]))
			return
	folder.cols = maxi(folder.cols, 8)
	folder.rows = maxi(folder.rows, 6)


func _mark_placed(file) -> void:
	if file.location == &"attached" or file.location == &"locked" or file.location == &"failed" or file.location == &"malicious":
		return
	file.location = &"folder"


func _restore_table(raw_table) -> void:
	if not (raw_table is Array):
		return
	var unplaced: Array = []
	for entry in raw_table:
		if not (entry is Dictionary):
			continue
		var fid = str(entry.get("file_id", entry.get("id", "")))
		var file = files.get(fid)
		if file == null:
			continue
		if file.shape_id.is_empty():
			file.shape_id = "O1"
		var origin: Vector2i = _vec(entry.get("origin"))
		var rot = posmod(int(entry.get("rotation", 0)), 4)
		if can_place_table(file.shape_id, origin, rot) and file.location != &"attached":
			# Стол — единственный источник позиции: убираем возможный дубль
			# из папки, чтобы не было двух мест у одного файла.
			if not file.folder_id.is_empty() and folders.has(file.folder_id):
				var home = folders[file.folder_id]
				home.clear_owner(file.id)
				home.file_ids.erase(file.id)
			_stamp_table(file, origin, rot)
			file.location = &"table"
			file.attached_request = ""
		else:
			unplaced.append(file)
	for file in unplaced:
		var fit = _find_table_fit(file.shape_id, file.rotation)
		if not fit.is_empty():
			_stamp_table(file, fit.origin, fit.rotation)
			file.location = &"table"
		elif not _return_to_folder(file):
			_detach_from_folder(file)
			file.location = &"registry"
			file.folder_id = ""


func _restore_reservations(folder, raw_reserved) -> void:
	if not (raw_reserved is Array):
		return
	for entry in raw_reserved:
		if not (entry is Dictionary):
			continue
		var packet_id = str(entry.get("packet_id", ""))
		var shape = str(entry.get("shape_id", "O1"))
		var origin: Vector2i = _vec(entry.get("origin"))
		var rot = posmod(int(entry.get("rotation", 0)), 4)
		if packet_id.is_empty() or _reservations.has(packet_id):
			continue
		if not can_place(folder, shape, origin, rot):
			# Осиротевшая/пересекающаяся резервация: чистим (review M13).
			continue
		folder.reserved[packet_id] = {"shape_id": shape, "origin": origin, "rotation": rot}
		for cell in shape_cells(shape, rot):
			folder.cells[origin + cell] = packet_id
		_reservations[packet_id] = folder.id


# --- валидация -------------------------------------------------------------

func validate() -> Array:
	var errors: Array = []
	if sections.size() > MAX_SECTIONS:
		errors.append("секций больше %d" % MAX_SECTIONS)
	if table_cols <= 0 or table_rows <= 0:
		errors.append("неверный размер стола %dx%d" % [table_cols, table_rows])

	var all_membership = {} # file_id -> count
	for folder in folders.values():
		if not sections.has(folder.section):
			errors.append("папка %s ссылается на несуществующую секцию" % folder.id)
		if folder.name.strip_edges().is_empty() or folder.name.length() > MAX_FOLDER_NAME:
			errors.append("неверное имя папки %s" % folder.id)
		if folder.cols <= 0 or folder.rows <= 0:
			errors.append("неверная сетка папки %s (%dx%d)" % [folder.id, folder.cols, folder.rows])
		var used = {}
		var seen = {}
		for file_id in folder.file_ids:
			if not files.has(file_id):
				errors.append("папка %s ссылается на несуществующий файл %s" % [folder.id, file_id])
				continue
			seen[file_id] = int(seen.get(file_id, 0)) + 1
			all_membership[file_id] = int(all_membership.get(file_id, 0)) + 1
			var file = files[file_id]
			for cell in shape_cells(file.shape_id, file.rotation):
				var pos: Vector2i = file.origin + cell
				if pos.x < 0 or pos.y < 0 or pos.x >= folder.cols or pos.y >= folder.rows:
					errors.append("файл %s вне сетки папки %s" % [file_id, folder.id])
					continue
				if used.has(pos):
					errors.append("пересечение файлов %s и %s в папке %s" % [used[pos], file_id, folder.id])
				else:
					used[pos] = file_id
		for file_id in seen.keys():
			if int(seen[file_id]) > 1:
				errors.append("файл %s дважды в папке %s" % [file_id, folder.id])
		var reserved_cell_total = 0
		for packet_id in folder.reserved.keys():
			var res_def: Dictionary = folder.reserved[packet_id]
			reserved_cell_total += shape_cells(str(res_def.get("shape_id", "O1")), int(res_def.get("rotation", 0))).size()
		if folder.cells.size() != used.size() + reserved_cell_total:
			errors.append("карта клеток папки %s рассинхронизирована" % folder.id)
		for packet_id in folder.reserved.keys():
			var res: Dictionary = folder.reserved[packet_id]
			var room_ok = true
			for cell in shape_cells(str(res.get("shape_id", "O1")), int(res.get("rotation", 0))):
				var pos2: Vector2i = Vector2i(res.get("origin", Vector2i.ZERO)) + cell
				if pos2.x < 0 or pos2.y < 0 or pos2.x >= folder.cols or pos2.y >= folder.rows:
					errors.append("резервация %s вне сетки папки %s" % [packet_id, folder.id])
					room_ok = false
					continue
				if used.has(pos2):
					errors.append("резервация %s пересекает файл %s" % [packet_id, used[pos2]])
					room_ok = false
			if not room_ok:
				continue
			if not _reservations.has(packet_id) or str(_reservations[packet_id]) != folder.id:
				errors.append("осиротевшая резервация %s в папке %s" % [packet_id, folder.id])

	var per_section = {}
	for folder in folders.values():
		per_section[folder.section] = int(per_section.get(folder.section, 0)) + 1
	for section_id in per_section.keys():
		if int(per_section[section_id]) > MAX_FOLDERS_PER_SECTION:
			errors.append("в секции %s больше %d папок" % [section_id, MAX_FOLDERS_PER_SECTION])

	for section in sections.values():
		var seen_ids = {}
		for folder_id in section.folder_ids:
			if not folders.has(folder_id):
				errors.append("секция %s ссылается на несуществующую папку %s" % [section.id, folder_id])
			if seen_ids.has(folder_id):
				errors.append("папка %s дважды в секции %s" % [folder_id, section.id])
			seen_ids[folder_id] = true

	var table_used = {}
	for file in table_files():
		for cell in shape_cells(file.shape_id, file.rotation):
			var pos3: Vector2i = file.origin + cell
			if pos3.x < 0 or pos3.y < 0 or pos3.x >= table_cols or pos3.y >= table_rows:
				errors.append("файл %s вне сетки стола" % file.id)
				continue
			if table_used.has(pos3):
				errors.append("пересечение на столе: %s и %s" % [table_used[pos3], file.id])
			else:
				table_used[pos3] = file.id
	if _table_cells.size() != table_used.size():
		errors.append("карта клеток стола рассинхронизирована")

	var names = {}
	for file in files.values():
		var probe: String = str(file.name).to_lower()
		if probe.is_empty():
			errors.append("пустое имя файла %s" % file.id)
		if names.has(probe):
			errors.append("дубль имени файла: %s" % file.name)
		names[probe] = true
		if not FILE_ITEM_SCRIPT.LOCATIONS.has(String(file.location)):
			errors.append("неверный location у %s" % file.id)
		if file.location == &"attached":
			if file.attached_request.is_empty():
				errors.append("attached-файл %s без запроса" % file.id)
		elif file.attached_request != "" and file.location != &"table":
			errors.append("файл %s прикреплён, но location=%s" % [file.id, file.location])
		if file.location == &"table":
			if int(all_membership.get(file.id, 0)) != 0:
				errors.append("файл %s на столе, но лежит в folder.file_ids" % file.id)
			if not _table_cells.values().has(file.id):
				errors.append("файл %s на столе без клетки" % file.id)
		elif file.location == &"registry":
			if int(all_membership.get(file.id, 0)) != 0:
				errors.append("registry-файл %s лежит в folder.file_ids" % file.id)
		else:
			if file.folder_id.is_empty():
				if int(all_membership.get(file.id, 0)) != 0:
					errors.append("файл %s без папки, но лежит в folder.file_ids" % file.id)
			else:
				if not folders.has(file.folder_id):
					errors.append("файл %s ссылается на несуществующую папку" % file.id)
				elif int(all_membership.get(file.id, 0)) != 1:
					errors.append("файл %s должен быть ровно в одной папке" % file.id)
	return errors


# --- служебное -------------------------------------------------------------

func _make_file(clean: String, type: String, shape: String):
	var info = _type_info(type)
	var file = FILE_ITEM_SCRIPT.new()
	file.id = "file_%d" % _next_file_id
	_next_file_id += 1
	file.name = clean
	file.type = type
	file.ext = FILE_ITEM_SCRIPT.normalize_ext(str(info.get("ext", "")))
	file.size_kb = int(info.get("size_kb", 0))
	file.created_at = FILE_ITEM_SCRIPT.now_unix()
	file.shape_id = shape if not shape.is_empty() else "O1"
	file.shape_cells = shape_cells(file.shape_id, 0)
	if file.shape_cells.is_empty():
		file.shape_cells = [Vector2i.ZERO]
	file.rotation = 0
	file.origin = Vector2i.ZERO
	return file


func _ensure_shape(file) -> void:
	if file.shape_id.is_empty():
		file.shape_id = "O1"
	if file.shape_cells.is_empty():
		file.shape_cells = shape_cells(file.shape_id, file.rotation)


func _put_in_folder(file, folder, origin: Vector2i, rotation: int) -> void:
	var safe := _safe_folder_placement(folder, file.shape_id, origin, rotation)
	file.shape_cells = safe.get("cells", [Vector2i.ZERO])
	file.origin = safe.get("origin", Vector2i.ZERO)
	file.rotation = posmod(int(rotation), 4)
	file.folder_id = folder.id
	if not folder.file_ids.has(file.id):
		folder.file_ids.append(file.id)
	_stamp_file(folder, file, file.origin, rotation)


func _stamp_file(folder, file, origin: Vector2i, rotation: int) -> void:
	var safe := _safe_folder_placement(folder, file.shape_id, origin, rotation)
	var cells: Array = safe.get("cells", [Vector2i.ZERO])
	var safe_origin: Vector2i = safe.get("origin", Vector2i.ZERO)
	file.shape_cells = cells
	file.origin = safe_origin
	file.rotation = posmod(int(rotation), 4)
	file.folder_id = folder.id
	for cell in cells:
		folder.cells[safe_origin + cell] = file.id


## Безопасное размещение: origin зажимается в границы папки; пустая форма или
## форма, не влезающая с этим origin, деградирует до одной клетки [0,0].
func _safe_folder_placement(folder, shape_id: String, origin: Vector2i,
		rotation: int) -> Dictionary:
	var cells := shape_cells(shape_id, rotation)
	if cells.is_empty():
		cells = [Vector2i.ZERO]
	var safe_origin := Vector2i(
		clampi(origin.x, 0, maxi(0, int(folder.cols) - 1)),
		clampi(origin.y, 0, maxi(0, int(folder.rows) - 1)))
	for cell in cells:
		var v := _vec(cell)
		var c := safe_origin.x + v.x
		var r := safe_origin.y + v.y
		if c < 0 or r < 0 or c >= int(folder.cols) or r >= int(folder.rows):
			return {"origin": Vector2i.ZERO, "cells": [Vector2i.ZERO]}
	return {"origin": safe_origin, "cells": cells}


func _stamp_table(file, origin: Vector2i, rotation: int) -> void:
	file.shape_cells = shape_cells(file.shape_id, rotation)
	if file.shape_cells.is_empty():
		file.shape_cells = [Vector2i.ZERO]
	file.origin = origin
	file.rotation = posmod(int(rotation), 4)
	# home folder_id сохраняется для auto_return_table()
	for cell in file.shape_cells:
		_table_cells[origin + cell] = file.id


func _stamp_reservation(folder, packet_id: String, res: Dictionary) -> void:
	for cell in shape_cells(str(res.get("shape_id", "O1")), int(res.get("rotation", 0))):
		folder.cells[Vector2i(res.get("origin", Vector2i.ZERO)) + cell] = packet_id


func _clear_file_placement(file) -> void:
	if not file.folder_id.is_empty():
		var folder = folders.get(file.folder_id)
		if folder != null:
			folder.clear_owner(str(file.id))
			# Убираем ВСЕ вхождения id (дубли могли накопиться старым кодом).
			while folder.file_ids.has(str(file.id)):
				folder.file_ids.erase(str(file.id))
			# Старая папка тоже должна перерисоваться (перенос/расход файла).
			grid_changed.emit(folder.id)
	_clear_table_cells(str(file.id))


func _clear_table_cells(file_id: String) -> void:
	# Собираем ключи и удаляем после обхода (erase во время keys() пропускает
	# часть клеток multi-cell фигуры).
	var to_erase: Array = []
	for cell in _table_cells.keys():
		if str(_table_cells[cell]) == file_id:
			to_erase.append(cell)
	for cell in to_erase:
		_table_cells.erase(cell)


func _release_reservation(packet_id: String, folder) -> void:
	folder.clear_owner(packet_id)
	folder.reserved.erase(packet_id)
	_reservations.erase(packet_id)


func _folder_for_reservation(packet_id: String):
	if not _reservations.has(packet_id):
		return null
	return folders.get(str(_reservations[packet_id]))


func _after_placement_change(file, folder, _ignored: String) -> void:
	file.location = &"folder"
	file_changed.emit(file)
	_emit_grid(folder)
	registry_changed.emit()


func _emit_grid(folder) -> void:
	if folder == null:
		return
	folder_changed.emit(folder)
	grid_changed.emit(folder.id)


func _find_fit(folder, shape_id: String, preferred_rotation: int) -> Dictionary:
	if folder == null:
		return {}
	var order: Array = [posmod(int(preferred_rotation), 4), 0, 1, 2, 3]
	var seen = {}
	for rot in order:
		if seen.has(rot):
			continue
		seen[rot] = true
		for r in range(folder.rows):
			for c in range(folder.cols):
				var origin = Vector2i(c, r)
				if can_place(folder, shape_id, origin, rot):
					return {"origin": origin, "rotation": rot}
	return {}


func _find_table_fit(shape_id: String, preferred_rotation: int) -> Dictionary:
	var order: Array = [posmod(int(preferred_rotation), 4), 0, 1, 2, 3]
	var seen = {}
	for rot in order:
		if seen.has(rot):
			continue
		seen[rot] = true
		for r in range(table_rows):
			for c in range(table_cols):
				var origin = Vector2i(c, r)
				if can_place_table(shape_id, origin, rot):
					return {"origin": origin, "rotation": rot}
	return {}


func _first_folder_id_with_space(file) -> String:
	var ids: Array = folders.keys()
	ids.sort()
	for fid in ids:
		var folder = folders[fid]
		if can_place(folder, file.shape_id, Vector2i.ZERO, file.rotation):
			return str(fid)
	for fid in ids:
		var folder2 = folders[fid]
		if not _find_fit(folder2, file.shape_id, file.rotation).is_empty():
			return str(fid)
	return ""


## Вернуть файл в папку first-fit (сначала home). false — места нет.
func _return_to_folder(file) -> bool:
	var candidates: Array = []
	if not file.folder_id.is_empty() and folders.has(file.folder_id):
		candidates.append(file.folder_id)
	for fid in folders.keys():
		if not candidates.has(str(fid)):
			candidates.append(str(fid))
	for fid in candidates:
		var folder = folders.get(str(fid))
		if folder == null:
			continue
		var fit := _find_fit(folder, file.shape_id, file.rotation)
		if fit.is_empty():
			continue
		_clear_file_placement(file)
		_put_in_folder(file, folder, fit.origin, fit.rotation)
		file.location = &"folder"
		return true
	return false


func _detach_from_folder(file) -> void:
	if file.folder_id.is_empty():
		return
	var folder = folders.get(file.folder_id)
	if folder != null:
		folder.clear_owner(file.id)
		folder.file_ids.erase(file.id)


func _resolve_folder(folder_ref):
	if folder_ref is String or folder_ref is StringName:
		return folders.get(str(folder_ref))
	if folder_ref is Object and folder_ref.has_method("cell_occupied"):
		return folder_ref
	return null


func _sync_rng() -> void:
	if _rng_seed != rng_seed:
		set_rng_seed(rng_seed)


func _shape_for_migration(file_type: String, index: int) -> String:
	var candidates = shape_ids_for_type(file_type)
	if candidates.is_empty():
		return "O1"
	var seed_value = int(hash("%s:%d" % [str(file_type), int(index)]))
	var rng = RandomNumberGenerator.new()
	rng.seed = abs(seed_value)
	return str(candidates[rng.randi_range(0, candidates.size() - 1)])


func _type_info(file_type: String) -> Dictionary:
	var data = _data_node()
	if data != null and data.has_method("type_def"):
		var def = data.type_def(file_type)
		if def is Dictionary and not def.is_empty():
			return def
	var fallback = TYPE_INFO.get(file_type)
	if fallback is Dictionary:
		return fallback
	return DEFAULT_TYPE_INFO


func _const_int(key: String, fallback_value: int) -> int:
	var data = _data_node()
	if data != null:
		var constants = data.get("constants")
		if constants is Dictionary and (constants as Dictionary).has(key):
			return int((constants as Dictionary)[key])
		if data.has_method("const_value"):
			var value = data.const_value(key, null)
			if value != null:
				return int(value)
	return fallback_value


func _grid_int(key: String, fallback_value: int) -> int:
	var data = _data_node()
	if data != null:
		var grid = data.get("grid")
		if grid is Dictionary and (grid as Dictionary).has(key):
			return int((grid as Dictionary)[key])
	return fallback_value


static func _data_node():
	var loop = Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("Data")
	return null


func _game_node():
	var loop = Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("Game")
	return null


func _dict_of(value) -> Dictionary:
	if value is Dictionary:
		return value
	return {}


func _repair_after_load() -> void:
	for section in sections.values():
		section.folder_ids.clear()
	for folder in folders.values():
		var section = sections.get(folder.section)
		if section != null:
			section.folder_ids.append(folder.id)
		folder.legacy_slots = 0
		var kept: Array[String] = []
		for file_id in folder.file_ids:
			if not files.has(file_id):
				continue
			if kept.has(file_id):
				continue
			kept.append(file_id)
		folder.file_ids = kept
		folder.cells.clear()
		for file_id in folder.file_ids:
			var file = files[file_id]
			_stamp_file(folder, file, file.origin, file.rotation)
		for packet_id in folder.reserved.keys():
			var res: Dictionary = folder.reserved[packet_id]
			_stamp_reservation(folder, str(packet_id), res)
			_reservations[str(packet_id)] = folder.id

	var max_folder_num = 0
	for folder_id in folders.keys():
		max_folder_num = maxi(max_folder_num, _numeric_suffix(str(folder_id)))
	_next_folder_id = maxi(_next_folder_id, max_folder_num + 1)

	var max_file_num = 0
	for file_id in files.keys():
		max_file_num = maxi(max_file_num, _numeric_suffix(str(file_id)))
	_next_file_id = maxi(_next_file_id, max_file_num + 1)

	for file in files.values():
		var folder = folders.get(file.folder_id) if not file.folder_id.is_empty() else null
		if file.location == &"table":
			if not _table_cells.values().has(file.id):
				var fit_table = _find_table_fit(file.shape_id, file.rotation)
				if not fit_table.is_empty():
					_stamp_table(file, fit_table.origin, fit_table.rotation)
				elif not _return_to_folder(file):
					_detach_from_folder(file)
					file.location = &"registry"
					file.folder_id = ""
			file.attached_request = ""
			continue
		if file.location == &"registry":
			file.folder_id = ""
			file.attached_request = ""
			continue
		if folder == null:
			file.folder_id = ""
			file.location = &"registry"
			file.attached_request = ""
			continue
		if not folder.file_ids.has(file.id):
			folder.file_ids.append(file.id)
			_stamp_file(folder, file, file.origin, file.rotation)
		if file.location == &"attached" and file.attached_request.is_empty():
			file.location = &"folder"
		if (file.location == &"failed" or file.location == &"malicious") and not file.attached_request.is_empty():
			file.attached_request = ""
		if file.location == &"locked" and file._location_before_lock != &"folder" and file._location_before_lock != &"registry" and file._location_before_lock != &"table":
			file._location_before_lock = &"folder"


func _numeric_suffix(value: String) -> int:
	var idx = value.rfind("_")
	if idx < 0 or idx + 1 >= value.length():
		return 0
	var tail = value.substr(idx + 1)
	if not tail.is_valid_int():
		return 0
	return int(tail)
