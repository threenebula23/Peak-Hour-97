class_name TcpConnection
extends RefCounted
## Установленное TCP-соединение клиента.
##
## Живёт отдельно от Request: запрос может быть удалён после успешной
## отправки, а соединение продолжает занимать out-слот до явного
## disconnect_connection() или конца часа. В слоте видны только имя клиента
## и IP (detail), данные запроса туда не попадают.

var id: String = ""
var client_name: String = ""
var client_id: String = ""
var ip: String = ""
## Запрос, который сейчас пользуется соединением. "" — соединение свободно
## после успешной отправки (слот остаётся занятым).
var request_id: String = ""
var slot_index: int = -1
var hour: int = 0
## Момент открытия (hour_elapsed часа) — для отладки/UI.
var connected_at: float = 0.0


func has_request() -> bool:
	return not request_id.is_empty()


func display_name() -> String:
	if client_name.is_empty():
		return ip
	return client_name


func to_dict() -> Dictionary:
	return {
		"id": id,
		"client_name": client_name,
		"client_id": client_id,
		"ip": ip,
		"request_id": request_id,
		"slot_index": slot_index,
		"hour": hour,
		"connected_at": connected_at,
	}


static func from_dict(d: Dictionary):
	var c = new()
	c.id = str(d.get("id", ""))
	c.client_name = str(d.get("client_name", ""))
	c.client_id = str(d.get("client_id", ""))
	c.ip = str(d.get("ip", ""))
	c.request_id = str(d.get("request_id", ""))
	c.slot_index = int(d.get("slot_index", -1))
	c.hour = int(d.get("hour", 0))
	c.connected_at = float(d.get("connected_at", 0.0))
	return c
