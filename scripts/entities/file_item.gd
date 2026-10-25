class_name FileItem
extends RefCounted
## Один файл-пакет в реестре узла.
##
## Состояние хранится флагами (D09): `location` — где файл находится,
## `attached_request` — к какому запросу прикреплён, `lock_until` /
## `cooldown_until` — таймеры (unix-время).
##
## v2: файл — полимино на сетке папки. `shape_id` + `rotation` задают форму,
## `origin` — верхняя левая клетка bounding box, `shape_cells` — производное
## поле (пересчитывается из shape_id/rotation, в save не пишется).
##
## ВАЖНО: проект запускается без прогретого global class cache, поэтому
## между своими скриптами используем `preload`, а не имя класса. Внутри
## этого файла допустим `new()` (не `FileItem.new()`).

const LOCATIONS: Array[String] = [
	"registry", # получен, ещё не разложен по папке
	"folder", # лежит в папке
	"table", # лежит на столе сортировки (не в папке, нельзя attach)
	"attached", # прикреплён к запросу (остаётся в папке)
	"locked", # заблокирован атакой/шифровальщиком
	"malicious", # вредоносный, можно уничтожить
	"failed", # сбой, в запросы не возвращается
]

var id: String = ""
var name: String = ""
var ext: String = ""
var type: String = "text"
var folder_id: String = ""
var location: StringName = &"folder"
var attached_request: String = ""
## Runtime-резерв: id запроса, для которого файл обязателен (не сохраняется).
var required_by: String = ""
var malicious_kind: String = ""
var lock_until: float = 0.0
var cooldown_until: float = 0.0
var size_kb: int = 0
var created_at: float = 0.0

## Форма на сетке (v2).
var shape_id: String = "O1"
## Производное от shape_id/rotation; в save не входит.
var shape_cells: Array = []
## Верхняя левая клетка bounding box в сетке папки/стола.
var origin: Vector2i = Vector2i.ZERO
## 0..3, по часовой стрелке.
var rotation: int = 0

## Куда файл вернётся после снятия lock (служебное поле, в save пишется).
var _location_before_lock: StringName = &"folder"


static func now_unix() -> float:
	return Time.get_unix_time_from_system()


## Расширение без ведущей точки, в нижнем регистре.
static func normalize_ext(value: String) -> String:
	var cleaned := value.strip_edges().to_lower()
	while cleaned.begins_with("."):
		cleaned = cleaned.substr(1)
	return cleaned


func display_name() -> String:
	if ext.is_empty():
		return name
	if name.is_empty():
		return ext
	return "%s.%s" % [name, ext]


## Можно ли использовать файл как кандидат на прикрепление прямо сейчас.
func is_available(now: float = -1.0) -> bool:
	if now < 0.0:
		now = now_unix()
	if location != &"folder" and location != &"registry":
		return false
	if not attached_request.is_empty():
		return false
	if lock_until > 0.0 and now < lock_until:
		return false
	if cooldown_until > 0.0 and now < cooldown_until:
		return false
	return true


## Синоним is_available() для читаемости мест вызова.
func can_attach(now: float = -1.0) -> bool:
	return is_available(now)


func is_on_table() -> bool:
	return location == &"table"


func cell_count() -> int:
	if not shape_cells.is_empty():
		return shape_cells.size()
	return 1


## Позиция не входит в метаданные save v2 (единый источник — folder.files /
## table), поэтому по умолчанию include_placement=true нужен только для
## прямого roundtrip FileItem.
func to_dict(include_placement: bool = true) -> Dictionary:
	var out := {
		"id": id,
		"name": name,
		"ext": ext,
		"type": type,
		"folder_id": folder_id,
		"location": String(location),
		"attached_request": attached_request,
		"malicious_kind": malicious_kind,
		"lock_until": lock_until,
		"cooldown_until": cooldown_until,
		"size_kb": size_kb,
		"created_at": created_at,
		"location_before_lock": String(_location_before_lock),
		"shape_id": shape_id,
	}
	if include_placement:
		out["origin"] = [origin.x, origin.y]
		out["rotation"] = rotation
	return out


static func from_dict(d: Dictionary):
	var f = new()
	f.id = str(d.get("id", ""))
	f.name = str(d.get("name", ""))
	f.ext = normalize_ext(str(d.get("ext", "")))
	f.type = str(d.get("type", "text"))
	f.folder_id = str(d.get("folder_id", ""))
	var loc := StringName(str(d.get("location", "folder")))
	if not LOCATIONS.has(String(loc)):
		loc = &"folder" if not f.folder_id.is_empty() else &"registry"
	f.location = loc
	f.attached_request = str(d.get("attached_request", ""))
	f.malicious_kind = str(d.get("malicious_kind", ""))
	f.lock_until = float(d.get("lock_until", 0.0))
	f.cooldown_until = float(d.get("cooldown_until", 0.0))
	f.size_kb = int(d.get("size_kb", 0))
	f.created_at = float(d.get("created_at", 0.0))
	var prev := StringName(str(d.get("location_before_lock", "folder")))
	if prev != &"registry" and prev != &"folder" and prev != &"table":
		prev = &"folder"
	f._location_before_lock = prev
	f.shape_id = str(d.get("shape_id", "O1"))
	if f.shape_id.is_empty():
		f.shape_id = "O1"
	f.rotation = posmod(int(d.get("rotation", 0)), 4)
	f.origin = _vec_from(d.get("origin", [0, 0]))
	var raw_cells = d.get("shape_cells", [])
	if raw_cells is Array:
		for cell in raw_cells:
			f.shape_cells.append(_vec_from(cell))
	# Инварианты: attached без запроса и failed/malicious не бывают прикреплены.
	if f.location == &"attached" and f.attached_request.is_empty():
		f.location = &"folder" if not f.folder_id.is_empty() else &"registry"
	if f.location == &"failed" or f.location == &"malicious":
		f.attached_request = ""
	if f.location == &"table":
		f.attached_request = ""
	return f


static func _vec_from(value) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Vector2:
		return Vector2i(int(value.x), int(value.y))
	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	if value is Dictionary:
		return Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))
	return Vector2i.ZERO
