class_name Slot
extends RefCounted
## Слот соединения. Направление: "in" (приём TCP) или "out" (отправка).

var index: int = 0
var direction: String = ""
var entity_id: String = ""
var entity_name: String = ""
var progress: float = 0.0
var occupied: bool = false


func reset() -> void:
	direction = ""
	entity_id = ""
	entity_name = ""
	progress = 0.0
	occupied = false


func occupy(p_direction: String, p_entity_id: String, p_entity_name: String = "") -> void:
	direction = p_direction
	entity_id = p_entity_id
	entity_name = p_entity_name
	progress = 0.0
	occupied = true


func to_dict() -> Dictionary:
	return {
		"index": index,
		"direction": direction,
		"entity_id": entity_id,
		"entity_name": entity_name,
		"progress": progress,
		"occupied": occupied,
	}


static func from_dict(d: Dictionary):
	var s = new()
	s.index = int(d.get("index", 0))
	s.direction = str(d.get("direction", ""))
	s.entity_id = str(d.get("entity_id", ""))
	s.entity_name = str(d.get("entity_name", ""))
	s.progress = float(d.get("progress", 0.0))
	s.occupied = bool(d.get("occupied", false))
	return s
