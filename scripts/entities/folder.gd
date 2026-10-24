class_name Folder
extends RefCounted
## Папка секции. Хранит только id файлов; сами файлы — в FileRegistry.
##
## `reserved` — счётчик слотов, зарезервированных под ещё не завершённые
## загрузки. В save не пишется: после перезапуска незавершённых загрузок нет.

var id: String = ""
var section: String = ""
var name: String = ""
var file_ids: Array[String] = []

## Служебное: зарезервированные слоты (в файл сохранения не попадает).
var reserved: int = 0


func count() -> int:
	return file_ids.size()


## Свободно ли место с учётом резерваций.
func has_free_slot(capacity: int = 16) -> bool:
	return count() + reserved < capacity


func to_dict() -> Dictionary:
	return {
		"id": id,
		"section": section,
		"name": name,
		"file_ids": file_ids.duplicate(),
	}


static func from_dict(d: Dictionary):
	var f = new()
	f.id = str(d.get("id", ""))
	f.section = str(d.get("section", ""))
	f.name = str(d.get("name", ""))
	var raw = d.get("file_ids", [])
	if raw is Array:
		for value in raw:
			f.file_ids.append(str(value))
	f.reserved = 0
	return f
