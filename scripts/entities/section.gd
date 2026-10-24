class_name Section
extends RefCounted
## Секция буквенного склада (C..H). Содержит папки.

var id: String = ""
var letter: String = ""
var name: String = ""
var folder_ids: Array[String] = []


func to_dict() -> Dictionary:
	return {
		"id": id,
		"letter": letter,
		"name": name,
		"folder_ids": folder_ids.duplicate(),
	}


static func from_dict(d: Dictionary):
	var s = new()
	s.id = str(d.get("id", d.get("letter", "")))
	s.letter = str(d.get("letter", s.id))
	if s.id.is_empty():
		s.id = s.letter
	if s.letter.is_empty():
		s.letter = s.id
	s.name = str(d.get("name", ""))
	var raw = d.get("folder_ids", [])
	if raw is Array:
		for value in raw:
			s.folder_ids.append(str(value))
	return s
