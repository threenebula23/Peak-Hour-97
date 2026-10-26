class_name Request
extends RefCounted
## Клиентский запрос на отправку файлов.
##
## `required` — конкретные id файлов (D01), `attached` — какие из них уже
## прикреплены. Файл может быть required в нескольких запросах, но attached
## только в одном (D06). Состояния — флаги D09.

var id: String = ""
var client_name: String = ""
var client_id: String = ""
var avatar: String = ""
var protocol: String = "tcp"
var required: Array[String] = []
var attached: Array[String] = []
var time_left: float = 0.0
var timer_total: float = 0.0

var slot_reserved: bool = false
var connected: bool = false
## TCP: id активного TcpConnection ("" — соединения нет). Файлы нельзя
## прикреплять, пока connection_id пуст.
var connection_id: String = ""
## TCP: идёт мини-игра установления соединения (полоска). Таймер заморожен.
var connecting: bool = false
## TCP: сколько раз игрок пытался установить соединение в этом часе.
var connect_attempts: int = 0
## TCP: до какого hour_elapsed действует пауза после неудачи.
var connect_cooldown_until: float = 0.0
var minigame_active: bool = false
var sending: bool = false

## UDP: число потерь пакета за час и момент, до которого повтор запрещён.
var udp_failures: int = 0
var udp_retry_until: float = 0.0

var quality: float = 1.0
var send_progress: float = 0.0
var is_attack: bool = false
var attack_kind: String = ""

## Служебные поля, заполняются директором при старте отправки.
var attack_id: String = ""
var required_types: Array[String] = []
var send_duration: float = 0.0
var send_base_sum: float = 0.0

## v2: выбор мини-игры отправки. Сумма коэффициентов типов, выбранная игра и
## её ступень. Заполняются HourDirector/Economy, в save опциональны.
var send_sum: int = 0
var minigame_id: String = ""
var minigame_tier: int = 0


## Готов ли запрос к отправке: все required прикреплены, TCP подключён.
func is_ready() -> bool:
	if missing_count() > 0:
		return false
	if protocol.to_lower() == "tcp" and not has_connection():
		return false
	return true


## Есть ли реальное TCP-соединение (одного флага connected мало).
func has_connection() -> bool:
	return not connection_id.is_empty()


func missing_count() -> int:
	var missing := 0
	for file_id in required:
		if not attached.has(file_id):
			missing += 1
	return missing


func missing_files() -> Array[String]:
	var out: Array[String] = []
	for file_id in required:
		if not attached.has(file_id):
			out.append(file_id)
	return out


func required_count() -> int:
	return required.size()


func time_ratio() -> float:
	if timer_total <= 0.0:
		return 0.0
	return clampf(time_left / timer_total, 0.0, 1.0)


func is_phishing() -> bool:
	return is_attack and attack_kind == "phishing"


func to_dict() -> Dictionary:
	return {
		"id": id,
		"client_name": client_name,
		"client_id": client_id,
		"avatar": avatar,
		"protocol": protocol,
		"required": required.duplicate(),
		"attached": attached.duplicate(),
		"time_left": time_left,
		"timer_total": timer_total,
		"slot_reserved": slot_reserved,
		"connected": connected,
		"connection_id": connection_id,
		"connecting": connecting,
		"connect_attempts": connect_attempts,
		"connect_cooldown_until": connect_cooldown_until,
		"minigame_active": minigame_active,
		"sending": sending,
		"udp_failures": udp_failures,
		"udp_retry_until": udp_retry_until,
		"quality": quality,
		"send_progress": send_progress,
		"is_attack": is_attack,
		"attack_kind": attack_kind,
		"attack_id": attack_id,
		"required_types": required_types.duplicate(),
		"send_duration": send_duration,
		"send_base_sum": send_base_sum,
		"send_sum": send_sum,
		"minigame_id": minigame_id,
		"minigame_tier": minigame_tier,
	}


static func from_dict(d: Dictionary):
	var r = new()
	r.id = str(d.get("id", ""))
	r.client_name = str(d.get("client_name", ""))
	r.client_id = str(d.get("client_id", ""))
	r.avatar = str(d.get("avatar", ""))
	r.protocol = str(d.get("protocol", "tcp")).to_lower()
	r.required = _string_array(d.get("required", []))
	r.attached = _string_array(d.get("attached", []))
	r.time_left = float(d.get("time_left", 0.0))
	r.timer_total = float(d.get("timer_total", 0.0))
	r.slot_reserved = bool(d.get("slot_reserved", false))
	r.connected = bool(d.get("connected", false))
	r.connection_id = str(d.get("connection_id", ""))
	r.connecting = bool(d.get("connecting", false))
	r.connect_attempts = maxi(0, int(d.get("connect_attempts", 0)))
	r.connect_cooldown_until = maxf(0.0, float(d.get("connect_cooldown_until", 0.0)))
	r.minigame_active = bool(d.get("minigame_active", false))
	r.sending = bool(d.get("sending", false))
	r.udp_failures = maxi(0, int(d.get("udp_failures", 0)))
	r.udp_retry_until = maxf(0.0, float(d.get("udp_retry_until", 0.0)))
	r.quality = clampf(float(d.get("quality", 1.0)), 0.0, 1.0)
	r.send_progress = float(d.get("send_progress", 0.0))
	r.is_attack = bool(d.get("is_attack", false))
	r.attack_kind = str(d.get("attack_kind", ""))
	r.attack_id = str(d.get("attack_id", ""))
	r.required_types = _string_array(d.get("required_types", []))
	r.send_duration = float(d.get("send_duration", 0.0))
	r.send_base_sum = float(d.get("send_base_sum", 0.0))
	r.send_sum = int(d.get("send_sum", 0))
	r.minigame_id = str(d.get("minigame_id", ""))
	r.minigame_tier = int(d.get("minigame_tier", 0))
	return r


static func _string_array(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in value:
			out.append(str(item))
	return out
