class_name MiniGameFactory
extends RefCounted
## Фабрика мини-игр v2 и выбор игры для отправки.
##
## create_send() загружает res://scripts/minigames/send/<id>.gd.
## create_attack() — заготовка: возвращает null, если скрипта атаки ещё нет.
## selection_for_sum()/send_for_types() делегируют Economy (единственный
## источник правды: 6 игр, 3 ступени, 27 достижимых сумм).

const SEND_IDS: Array[String] = [
	"dots", "sound", "text", "video", "photo", "maze",
]
const SEND_TIERS := 3
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
const ECONOMY_SCRIPT := preload("res://scripts/core/economy.gd")


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
	node.start(id, clampi(tier, 1, SEND_TIERS), seed, context)
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
	return clampi(1 + int(floor(float(maxi(1, hour) - 2) / 2.0)), 1, SEND_TIERS)


## Канонический выбор: полностью делегируется Economy.selection_for_sum()
## (rank в achievable_sums, таблица rank_games, 3 ступени). Здесь только
## страховка: не пропускаем наружу неизвестную игру и ступень вне 1..3.
static func selection_for_sum(total: int) -> Dictionary:
	var sum := maxi(total, 0)
	var result: Dictionary = ECONOMY_SCRIPT.selection_for_sum(sum)
	var id := str(result.get("id", "")).strip_edges().to_lower()
	if not SEND_IDS.has(id):
		id = SEND_IDS[0]
	result["id"] = id
	result["tier"] = clampi(int(result.get("tier", 1)), 1, SEND_TIERS)
	result["sum"] = sum
	return result


static func send_for_types(types: Array) -> Dictionary:
	var delegated := _economy_selection(types)
	if not delegated.is_empty():
		if not delegated.has("id") and delegated.has("game"):
			delegated["id"] = str(delegated["game"])
		var id := str(delegated.get("id", "")).strip_edges().to_lower()
		# Economy может работать по старым таблицам: «wires» уже нет, а
		# ступень могла остаться четвёртой. Не пропускаем такое наружу.
		if SEND_IDS.has(id):
			delegated["id"] = id
			delegated["tier"] = clampi(int(delegated.get("tier", 1)), 1, SEND_TIERS)
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
