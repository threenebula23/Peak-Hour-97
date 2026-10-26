class_name Slot
extends RefCounted
## Слот соединения. Направление: "in" (приём TCP) или "out" (отправка).
##
## kind: "packet" (приём файла) / "request" (UDP-отправка) /
## "tcp_connection" (установленное TCP-соединение). Для tcp_connection
## entity_id — id соединения, entity_name — имя клиента, detail — IP,
## linked_request_id — запрос, который пользуется соединением.

var index: int = 0
var direction: String = ""
var entity_id: String = ""
var entity_name: String = ""
var progress: float = 0.0
var occupied: bool = false

var kind: String = ""
## Дополнительная строка для UI: у tcp_connection — IP.
var detail: String = ""
var can_disconnect: bool = false
var linked_request_id: String = ""


func reset() -> void:
	direction = ""
	entity_id = ""
	entity_name = ""
	progress = 0.0
	occupied = false
	kind = ""
	detail = ""
	can_disconnect = false
	linked_request_id = ""


func occupy(p_direction: String, p_entity_id: String, p_entity_name: String = "",
		p_kind: String = "", p_detail: String = "", p_can_disconnect: bool = false,
		p_linked_request_id: String = "") -> void:
	direction = p_direction
	entity_id = p_entity_id
	entity_name = p_entity_name
	kind = _clean_kind(p_kind, p_direction)
	detail = p_detail
	can_disconnect = p_can_disconnect
	linked_request_id = p_linked_request_id
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
		"kind": kind,
		"detail": detail,
		"can_disconnect": can_disconnect,
		"linked_request_id": linked_request_id,
	}


static func from_dict(d: Dictionary):
	var s = new()
	s.index = int(d.get("index", 0))
	s.direction = str(d.get("direction", ""))
	s.entity_id = str(d.get("entity_id", ""))
	s.entity_name = str(d.get("entity_name", ""))
	s.progress = float(d.get("progress", 0.0))
	s.occupied = bool(d.get("occupied", false))
	s.kind = _clean_kind(str(d.get("kind", "")), s.direction)
	s.detail = str(d.get("detail", ""))
	s.can_disconnect = bool(d.get("can_disconnect", false))
	s.linked_request_id = str(d.get("linked_request_id", ""))
	return s


## Пустой kind выводится из направления (совместимость со старыми сейвами).
static func _clean_kind(value: String, direction: String) -> String:
	var clean := str(value).to_lower()
	if clean == "packet" or clean == "request" or clean == "tcp_connection":
		return clean
	if direction == "in":
		return "packet"
	if direction == "out":
		return "request"
	return ""
