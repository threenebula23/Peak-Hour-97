class_name Folder
extends RefCounted
## Папка секции. Хранит id файлов; сами файлы — в FileRegistry.
##
## v2: папка — клеточная сетка `cols` x `rows`. `cells` — служебная карта
## Vector2i -> owner_id (id файла или id пакета для резервации). В save
## `cells` не пишется: позиции восстанавливаются из placements в FileRegistry.
##
## `reserved` — резервации пакетов: packet_id -> {shape_id, origin, rotation}.
## Клетки резервации тоже лежат в `cells`, поэтому cell_occupied() возвращает
## true и для файлов, и для резерваций.

var id: String = ""
var section: String = ""
var name: String = ""
var cols: int = 5
var rows: int = 4
var file_ids: Array[String] = []

## Служебное: резервации приёма (в save пишутся отдельным списком).
var reserved: Dictionary = {}
## Служебное: занятость клеток (не сохраняется).
var cells: Dictionary = {}
## Legacy-совместимость со старым reserve_slot()/release_slot() (v1 API).
var legacy_slots: int = 0


func count() -> int:
	return file_ids.size()


func total_cells() -> int:
	return maxi(0, cols) * maxi(0, rows)


func cell_occupied(c: int, r: int) -> bool:
	return cells.has(Vector2i(c, r))


func owner_at(c: int, r: int) -> String:
	return str(cells.get(Vector2i(c, r), ""))


func is_reserved_cell(c: int, r: int) -> bool:
	var owner := owner_at(c, r)
	return not owner.is_empty() and reserved.has(owner)


func has_free_cell() -> bool:
	return cells.size() < total_cells()


func occupied_cell_count() -> int:
	return cells.size()


func free_cell_count() -> int:
	return maxi(0, total_cells() - cells.size())


func reserved_count() -> int:
	return reserved.size()


## Legacy: раньше ёмкость измерялась слотами (16 файлов).
func has_free_slot(capacity: int = 16) -> bool:
	return count() + reserved.size() + legacy_slots < capacity


## Служебный API для FileRegistry: занять клетку владельцем.
func set_cell(cell: Vector2i, owner_id: String) -> void:
	cells[cell] = owner_id


## Служебный API: освободить клетки, принадлежащие owner_id.
func clear_owner(owner_id: String) -> void:
	for cell in cells.keys():
		if str(cells[cell]) == owner_id:
			cells.erase(cell)


func clear_cells() -> void:
	cells.clear()


func to_dict() -> Dictionary:
	return {
		"id": id,
		"section": section,
		"name": name,
		"cols": cols,
		"rows": rows,
		"file_ids": file_ids.duplicate(),
	}


static func from_dict(d: Dictionary):
	var f = new()
	f.id = str(d.get("id", ""))
	f.section = str(d.get("section", ""))
	f.name = str(d.get("name", ""))
	f.cols = maxi(0, int(d.get("cols", 0)))
	f.rows = maxi(0, int(d.get("rows", 0)))
	var raw = d.get("file_ids", [])
	if raw is Array:
		for value in raw:
			f.file_ids.append(str(value))
	# v2: placements могут лежать в files — id подтянет FileRegistry.
	var placements = d.get("files", [])
	if placements is Array:
		for entry in placements:
			if entry is Dictionary:
				var fid := str(entry.get("id", ""))
				if not fid.is_empty() and not f.file_ids.has(fid):
					f.file_ids.append(fid)
	f.reserved = {}
	f.cells = {}
	return f
