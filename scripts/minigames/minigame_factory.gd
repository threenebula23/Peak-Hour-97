class_name MiniGameFactory
extends RefCounted
## Фабрика мини-игр v2 и выбор игры для отправки.
##
## create_send() загружает res://scripts/minigames/send/<id>.gd.
## create_attack() — заготовка: возвращает null, если скрипта атаки ещё нет.
## send_for_types() сначала спрашивает Economy.send_minigame_for(), если этот
## метод уже реализован другим агентом, иначе использует локальную формулу.

const SEND_IDS: Array[String] = [
	"dots", "sound", "wires", "text", "video", "photo", "maze",
]
const ATTACK_IDS: Array[String] = [
	"junk", "ddos", "phishing", "ransomware",
]
const COEFF := {
	"text": 1,
	"sound": 2,
	"photo": 4,
	"video": 8,
}
const SEND_DIR := "res://scripts/minigames/send"
const ATTACK_DIR := "res://scripts/minigames/attack"
const ECONOMY_PATH := "res://scripts/core/economy.gd"


static func create_send(game_id: String, tier: int, seed: int,
		context: Dictionary = {}) -> MiniGame:
	var id := str(game_id).strip_edges().to_lower()
	if not SEND_IDS.has(id):
		id = MiniGame.resolve_game_id(id)
	if not SEND_IDS.has(id):
		return null
	var path := "%s/%s.gd" % [SEND_DIR, id]
	if not ResourceLoader.exists(path):
		return null
	var script = load(path)
	if script == null:
		return null
	var node = script.new()
	if node == null or not (node is MiniGame):
		if node != null:
			node.free()
		return null
	node.start(id, clampi(tier, 1, 4), seed, context)
	return node


## Атаки добавляются отдельным агентом. Пока скрипта нет — null.
static func create_attack(kind: String, tier: int, seed: int,
		context: Dictionary = {}):
	var id := str(kind).strip_edges().to_lower()
	if id.is_empty():
		return null
	var path := "%s/%s.gd" % [ATTACK_DIR, id]
	if not ResourceLoader.exists(path):
		return null
	var script = load(path)
	if script == null:
		return null
	var node = script.new()
	if node == null or not (node is MiniGame):
		if node != null:
			node.free()
		return null
	node.start(id, clampi(tier, 1, 4), seed, context)
	return node


static func is_send_id(game_id: String) -> bool:
	return SEND_IDS.has(str(game_id).strip_edges().to_lower())


static func send_ids() -> Array[String]:
	return SEND_IDS.duplicate()


static func tier_for_hour(hour: int) -> int:
	return clampi(1 + int(floor(float(maxi(1, hour) - 2) / 2.0)), 1, 4)


## Единая формула выбора: idx = S-1, tier = floor(idx/7)+1,
## игра = SEND_ORDER[idx % 7].
static func selection_for_sum(total: int) -> Dictionary:
	var sum := maxi(total, 0)
	var idx := clampi(sum - 1, 0, 27)
	return {
		"id": SEND_IDS[idx % 7],
		"tier": int(idx / 7) + 1,
		"index": idx,
		"sum": sum,
	}


static func send_for_types(types: Array) -> Dictionary:
	var delegated := _economy_selection(types)
	if not delegated.is_empty():
		if not delegated.has("id") and delegated.has("game"):
			delegated["id"] = str(delegated["game"])
		if delegated.has("id"):
			var id := str(delegated["id"])
			if SEND_IDS.has(id):
				if not delegated.has("tier"):
					delegated["tier"] = 1
				return delegated
	var sum := 0
	for type in types:
		sum += int(COEFF.get(str(type).to_lower(), 1))
	return selection_for_sum(sum)


static func _economy_selection(types: Array) -> Dictionary:
	if not ResourceLoader.exists(ECONOMY_PATH):
		return {}
	var script = load(ECONOMY_PATH)
	if script == null:
		return {}
	var has_method := false
	for method in script.get_script_method_list():
		if str(method.get("name", "")) == "send_minigame_for":
			has_method = true
			break
	if not has_method:
		return {}
	var instance = script.new()
	if instance == null:
		return {}
	var result = instance.call("send_minigame_for", types)
	if result is Dictionary:
		return (result as Dictionary).duplicate(true)
	return {}
