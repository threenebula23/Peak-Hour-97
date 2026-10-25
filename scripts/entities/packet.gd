class_name Packet
extends RefCounted
## Входящий пакет (карточка в буфере приёма).
##
## ВАЖНО: пакет не тикает сам — все таймеры двигает HourDirector.tick().
## Состояния: waiting → (lost) → connected → loading → удалён из буфера.
## `lost` — карточка UDP-потери, 1.5 с она висит и возвращается с тем же
## оставшимся временем (D03/D09).

const STATE_WAITING := "waiting" # ждёт соединения/переноса в папку
const STATE_CONNECTED := "connected" # TCP-соединение установлено
const STATE_LOADING := "loading" # идёт загрузка в папку
const STATE_LOST := "lost" # UDP-потеря, карточка ещё 1.5 с

const UDP_LOST_SEC := 1.5
const UDP_LOST_CHANCE := 0.20

var id: String = ""
var file_name: String = ""
var type: String = "text"
var protocol: String = "tcp"
var time_left: float = 0.0
var timer_total: float = 0.0
var state: String = STATE_WAITING
var loading_progress: float = 0.0
var loading_folder_id: String = ""
var is_attack: bool = false
var attack_kind: String = ""
var size_kb: int = 0

## Форма, которую пакет займёт в папке. Выбирается при спавне, чтобы показать
## превью ещё до приёма. `shape_cells` — производное (не сохраняется).
var shape_id: String = "O1"
var rotation: int = 0
var shape_cells: Array = []

## Служебные поля (не входят в минимальный контракт, но нужны директору).
var lost_left: float = 0.0
var loading_duration: float = 0.0
var order: int = 0
var attack_id: String = ""


func is_tcp() -> bool:
	return protocol.to_lower() == "tcp"


func is_udp() -> bool:
	return protocol.to_lower() == "udp"


func in_buffer() -> bool:
	return state == STATE_WAITING or state == STATE_CONNECTED or state == STATE_LOST or state == STATE_LOADING


func can_connect() -> bool:
	return is_tcp() and state == STATE_WAITING


func can_receive() -> bool:
	return state == STATE_WAITING or state == STATE_CONNECTED


func is_loading() -> bool:
	return state == STATE_LOADING


func time_ratio() -> float:
	if timer_total <= 0.0:
		return 0.0
	return clampf(time_left / timer_total, 0.0, 1.0)


func display_name() -> String:
	if is_attack and attack_kind == "ransomware":
		return file_name
	var ext := _ext_for_type()
	if ext.is_empty():
		return file_name
	return "%s.%s" % [file_name, ext]


func to_dict() -> Dictionary:
	return {
		"id": id,
		"file_name": file_name,
		"type": type,
		"protocol": protocol,
		"time_left": time_left,
		"timer_total": timer_total,
		"state": state,
		"loading_progress": loading_progress,
		"loading_folder_id": loading_folder_id,
		"is_attack": is_attack,
		"attack_kind": attack_kind,
		"size_kb": size_kb,
		"lost_left": lost_left,
		"loading_duration": loading_duration,
		"order": order,
		"attack_id": attack_id,
		"shape_id": shape_id,
		"rotation": rotation,
	}


static func from_dict(d: Dictionary):
	var p = new()
	p.id = str(d.get("id", ""))
	p.file_name = str(d.get("file_name", ""))
	p.type = str(d.get("type", "text"))
	p.protocol = str(d.get("protocol", "tcp")).to_lower()
	p.time_left = float(d.get("time_left", 0.0))
	p.timer_total = float(d.get("timer_total", 0.0))
	p.state = str(d.get("state", STATE_WAITING))
	if p.state != STATE_WAITING and p.state != STATE_CONNECTED and p.state != STATE_LOADING and p.state != STATE_LOST:
		p.state = STATE_WAITING
	p.loading_progress = float(d.get("loading_progress", 0.0))
	p.loading_folder_id = str(d.get("loading_folder_id", ""))
	p.is_attack = bool(d.get("is_attack", false))
	p.attack_kind = str(d.get("attack_kind", ""))
	p.size_kb = int(d.get("size_kb", 0))
	p.lost_left = float(d.get("lost_left", 0.0))
	p.loading_duration = float(d.get("loading_duration", 0.0))
	p.order = int(d.get("order", 0))
	p.attack_id = str(d.get("attack_id", ""))
	p.shape_id = str(d.get("shape_id", "O1"))
	if p.shape_id.is_empty():
		p.shape_id = "O1"
	p.rotation = posmod(int(d.get("rotation", 0)), 4)
	p.shape_cells = []
	var raw_cells = d.get("shape_cells", [])
	if raw_cells is Array:
		for cell in raw_cells:
			if cell is Vector2i:
				p.shape_cells.append(cell)
			elif cell is Array and cell.size() >= 2:
				p.shape_cells.append(Vector2i(int(cell[0]), int(cell[1])))
	return p


func _ext_for_type() -> String:
	var data = _data_node()
	if data != null and data.has_method("type_def"):
		var def = data.type_def(type)
		if def is Dictionary:
			var ext := str(def.get("ext", "")).lstrip(".")
			if not ext.is_empty():
				return ext
	match type:
		"text":
			return "txt"
		"sound":
			return "wav"
		"photo":
			return "jpg"
		"video":
			return "mp4"
	return ""


func _data_node():
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("Data")
	return null
