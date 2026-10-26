class_name AttackDirector
extends Node
## Атаки часа v2: каждая атака — собственная мини-игра (§8).
##
## Старые карточки/оверлеи/пакеты атак удалены: AttackDirector не создаёт
## пакетов, запросов и файлов. Он только планирует атаки, открывает мини-игру,
## ставит час на паузу (H6: ДО emit show_attack_minigame) и применяет
## награду/штраф из data/balance.json → attacks.
##
## Щит («Заземление»): заряд тратится автоматически до открытия мини-игры,
## атака считается отражённой, награда 50%, штрафа нет.

signal attack_added(id: String)
signal attack_changed(id: String)
signal attack_removed(id: String)
signal toast(text: String)
signal resolved(id: String, success: bool)
signal attack_resolved(kind: String, success: bool, tier: int)
signal show_attack_minigame(game, kind: String)

const FACTORY := preload("res://scripts/minigames/minigame_factory.gd")
const ECONOMY := preload("res://scripts/core/economy.gd")

const KINDS: Array[String] = ["junk", "ddos", "phishing", "ransomware"]
## Legacy-окно (fallback, если в data нет ratio-ключей).
const WINDOW_MIN := 60.0
const WINDOW_MAX := 240.0
## Окно атак v3: start=clamp(start_ratio*duration, start_min, start_max),
## end=min(end_ratio*duration, duration-end_margin).
const DEFAULT_START_RATIO := 0.25
const DEFAULT_END_RATIO := 0.85
const DEFAULT_START_MIN_SEC := 20.0
const DEFAULT_START_MAX_SEC := 60.0
const DEFAULT_END_MARGIN_SEC := 20.0
const DEFAULT_SCHEDULE: Array[int] = [0, 1, 1, 2, 2, 3, 3, 4, 4]

## Fallback-таблицы §8 (если Data/balance.json недоступны).
const FALLBACK_TIERS := {
	"junk": [
		{"reward_money": 5, "reward_sla": 1, "fail_money": -10, "fail_sla": -5, "threshold": 0.60},
		{"reward_money": 10, "reward_sla": 2, "fail_money": -15, "fail_sla": -7, "threshold": 0.65},
		{"reward_money": 15, "reward_sla": 3, "fail_money": -20, "fail_sla": -9, "threshold": 0.70},
		{"reward_money": 20, "reward_sla": 4, "fail_money": -25, "fail_sla": -12, "threshold": 0.75},
	],
	"ddos": [
		{"reward_money": 30, "reward_sla": 2, "fail_money": -10, "fail_sla": -15, "channel_debuff": 0.4, "debuff_sec": 15, "threshold": 0.60},
		{"reward_money": 40, "reward_sla": 3, "fail_money": -15, "fail_sla": -20, "channel_debuff": 0.4, "debuff_sec": 15, "threshold": 0.65},
		{"reward_money": 50, "reward_sla": 4, "fail_money": -20, "fail_sla": -25, "channel_debuff": 0.4, "debuff_sec": 15, "threshold": 0.70},
		{"reward_money": 60, "reward_sla": 5, "fail_money": -25, "fail_sla": -30, "channel_debuff": 0.4, "debuff_sec": 15, "threshold": 0.75},
	],
	"phishing": [
		{"reward_money": 20, "reward_sla": 2, "fail_money": -40, "fail_sla": -10, "file_lock_sec": 60, "send_penalty_sec": 5, "threshold": 0.75},
		{"reward_money": 30, "reward_sla": 3, "fail_money": -50, "fail_sla": -12, "file_lock_sec": 60, "send_penalty_sec": 5, "threshold": 0.75},
		{"reward_money": 40, "reward_sla": 4, "fail_money": -60, "fail_sla": -15, "file_lock_sec": 60, "send_penalty_sec": 5, "threshold": 0.80},
		{"reward_money": 50, "reward_sla": 5, "fail_money": -70, "fail_sla": -18, "file_lock_sec": 60, "send_penalty_sec": 5, "threshold": 0.80},
	],
	"ransomware": [
		{"reward_money": 25, "reward_sla": 2, "fail_money": -30, "fail_sla": -10, "folder_block_sec": 15, "threshold": 0.50},
		{"reward_money": 35, "reward_sla": 3, "fail_money": -40, "fail_sla": -12, "folder_block_sec": 15, "threshold": 0.55},
		{"reward_money": 45, "reward_sla": 4, "fail_money": -50, "fail_sla": -15, "folder_block_sec": 15, "threshold": 0.60},
		{"reward_money": 55, "reward_sla": 5, "fail_money": -60, "fail_sla": -18, "folder_block_sec": 15, "threshold": 0.65},
	],
}

const FALLBACK_NAMES := {
	"junk": "Мусорный пакет",
	"ddos": "DDoS",
	"phishing": "Фишинг",
	"ransomware": "Шифровальщик",
}

## Ссылка на HourDirector (без type hint — избегаем циклических preload).
var director = null
## Активная запись атаки (только пока открыта мини-игра) для UI.
var active_attacks: Dictionary = {}
var hour: int = 1
var elapsed: float = 0.0
var shield_charges: int = 0
## Legacy-счётчик; оставлен для старых тестов/UI.
var shield_used_this_hour: int = 0

## Инъекция для тестов: Callable(kind, tier, seed, context) → Node|null.
var create_game_override: Callable = Callable()

var _schedule: Array[float] = []
var _schedule_kinds: Array[String] = []
var _next_index: int = 0
var _counter: int = 0
var _window_min: float = WINDOW_MIN
var _window_max: float = WINDOW_MAX
var _allow_spawn: bool = true
var _active_game = null
var _active_id: String = ""
var _active_kind: String = ""
var _active_tier: int = 1


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func setup(director_node) -> void:
	director = director_node


# --- планирование ----------------------------------------------------------

func reset(p_hour: int) -> void:
	for id in active_attacks.keys().duplicate():
		active_attacks.erase(id)
		attack_removed.emit(str(id))
	_cancel_active_game()
	if director != null and director.has_method("set_attack_paused"):
		director.call("set_attack_paused", false)
	hour = maxi(1, int(p_hour))
	elapsed = 0.0
	_counter = 0
	_next_index = 0
	shield_used_this_hour = 0
	_allow_spawn = true
	_schedule.clear()
	_schedule_kinds.clear()

	var count := attacks_for_hour(hour)
	_update_spawn_window()
	var entries: Array = []
	for i in range(count):
		entries.append({"t": _randf_range(_window_min, _window_max)})
	entries.sort_custom(func(a, b) -> bool: return float(a.get("t", 0.0)) < float(b.get("t", 0.0)))
	var previous := ""
	for entry in entries:
		var kind := _pick_kind_for_hour(hour, previous)
		_schedule.append(float(entry.get("t", _window_min)))
		_schedule_kinds.append(kind)
		if not kind.is_empty():
			previous = kind

	var game = _game()
	if game != null and game.get("shield_charges") != null:
		shield_charges = maxi(0, int(game.shield_charges))
		# Если заряд не был выставлен Game.start_hour, добираем его из уровня
		# «Заземления». Уже выставленные вручную заряды не перетираем.
		if shield_charges == 0 and game.has_method("regen_shield_for_hour"):
			var max_shield := 0
			if game.has_method("shield_max"):
				max_shield = int(game.shield_max())
			if max_shield > 0:
				shield_charges = maxi(0, int(game.regen_shield_for_hour()))
	else:
		shield_charges = 0


func set_allow_spawn(value: bool) -> void:
	_allow_spawn = bool(value)


# --- окно/счётчики ---------------------------------------------------------

## Окно атак под длительность часа. H2 (150 c): 37.5–127.5; H9 (360 c): 60–306.
func _update_spawn_window() -> void:
	var duration := _hour_duration_for_reset()
	var cfg := _spawn_window_cfg()
	if cfg.has("start_ratio") and cfg.has("end_ratio"):
		var start_min := float(cfg.get("start_min_sec", DEFAULT_START_MIN_SEC))
		var start_max := float(cfg.get("start_max_sec", DEFAULT_START_MAX_SEC))
		var margin := maxf(0.0, float(cfg.get("end_margin_sec", DEFAULT_END_MARGIN_SEC)))
		if start_max < start_min:
			var tmp := start_min
			start_min = start_max
			start_max = tmp
		_window_min = clampf(
			duration * clampf(float(cfg.get("start_ratio", DEFAULT_START_RATIO)), 0.0, 1.0),
			start_min, start_max
		)
		_window_max = minf(
			duration * clampf(float(cfg.get("end_ratio", DEFAULT_END_RATIO)), 0.0, 1.0),
			duration - margin
		)
	else:
		_window_min = WINDOW_MIN
		_window_max = WINDOW_MAX
	if _window_max < _window_min:
		_window_max = _window_min


func _hour_duration_for_reset() -> float:
	if director != null:
		if director.has_method("hour_seconds"):
			return maxf(1.0, float(director.call("hour_seconds")))
		if director.has_method("_hour_seconds"):
			return maxf(1.0, float(director.call("_hour_seconds")))
	return 120.0 + 30.0 * float(maxi(0, hour - 1))


func _spawn_window_cfg() -> Dictionary:
	var data = _data()
	if data != null and data.get("attacks") is Dictionary:
		var raw = (data.attacks as Dictionary).get("spawn_window", null)
		if raw is Dictionary:
			return raw
	return {}


## Сколько запланированных атак ещё не сработало.
func pending_count() -> int:
	return maxi(0, _schedule.size() - _next_index)


func total_count() -> int:
	return _schedule.size()


func active_count() -> int:
	if not active_attacks.is_empty():
		return active_attacks.size()
	return 1 if _active_game != null else 0


## Ступень активной атаки или ступень текущего часа.
func current_tier() -> int:
	if _active_game != null:
		return clampi(_active_tier, 1, 4)
	return ECONOMY.attack_tier(hour)


static func attacks_for_hour(p_hour: int) -> int:
	var h := maxi(1, int(p_hour))
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var data = (loop as SceneTree).root.get_node_or_null("Data")
		if data != null and data.has_method("hour_def"):
			var def = data.hour_def(h)
			if def is Dictionary and def.has("attacks"):
				return clampi(int(def.get("attacks", 0)), 0, 4)
		if data != null and data.has_method("attack_schedule"):
			var raw = data.attack_schedule()
			if raw is Array and not (raw as Array).is_empty():
				var idx := clampi(h - 1, 0, (raw as Array).size() - 1)
				return clampi(int((raw as Array)[idx]), 0, 4)
	if h <= DEFAULT_SCHEDULE.size():
		return int(DEFAULT_SCHEDULE[h - 1])
	return 4


func is_minigame_active() -> bool:
	return _active_game != null


func tick(delta: float) -> void:
	if _active_game != null or not _allow_spawn:
		return
	if director != null:
		if bool(director.get("paused")):
			return
		if director.has_method("is_attack_paused") and bool(director.call("is_attack_paused")):
			return
		if not bool(director.get("running")):
			return
		if bool(director.get("modal_open")):
			return
	var dt := maxf(delta, 0.0)
	elapsed += dt
	if _next_index >= _schedule.size():
		return
	var due := float(_schedule[_next_index])
	if elapsed < due:
		# Атака ещё не наступила. Если окно уже закрыто — расписание исчерпано.
		if elapsed > _window_max:
			_next_index = _schedule.size()
		return
	# elapsed >= due: атака была запланирована внутри окна, поэтому она должна
	# сработать, даже если большой шаг тика (time_scale/dev) уже перепрыгнул
	# _window_max. Ровно один спавн за тик.
	var kind := str(_schedule_kinds[_next_index]) if _next_index < _schedule_kinds.size() else ""
	_next_index += 1
	if kind.is_empty():
		kind = _pick_kind_for_hour(hour, "")
	if not kind.is_empty():
		spawn_attack(kind)


# --- атака -----------------------------------------------------------------

func spawn_attack(kind: String = "") -> String:
	if _active_game != null:
		return ""
	var chosen := str(kind).strip_edges().to_lower()
	if chosen.is_empty():
		chosen = _pick_kind_for_hour(hour, "")
	if chosen.is_empty() or not KINDS.has(chosen):
		return ""
	var tier := ECONOMY.attack_tier(hour)
	var id := "atk_%d_%d" % [hour, _counter]
	_counter += 1
	var cfg := _cfg(chosen)
	var tier_row := _tier_row(chosen, tier)

	# «Заземление»: заряд гасит атаку автоматически, 50% награды, без штрафа.
	if shield_charges > 0:
		shield_charges -= 1
		shield_used_this_hour += 1
		_sync_game_shield()
		var scale := _money_scale()
		var reward := int(round(float(tier_row.get("reward_money", 0)) * scale * _shield_scale()))
		var reward_sla := float(tier_row.get("reward_sla", 0)) * _shield_scale()
		_add_money(reward)
		_add_sla(reward_sla)
		toast.emit("ЩИТ ПОГЛОТИЛ АТАКУ")
		_play_sfx(&"attack_blocked")
		_emit_resolved(id, chosen, true, tier)
		return id

	var context := {
		"attack_id": id,
		"kind": chosen,
		"tier": tier,
		"name": str(cfg.get("name_ru", FALLBACK_NAMES.get(chosen, chosen))),
		"reward_text": "АТАКА ОТРАЖЕНА",
		"penalty_text": "АТАКА ПРОШЛА",
	}
	var seed_value := _randi_range(1, 2147483646)
	var game_node = null
	if create_game_override.is_valid():
		game_node = create_game_override.call(chosen, tier, seed_value, context)
	else:
		game_node = FACTORY.create_attack(chosen, tier, seed_value, context)

	if game_node == null:
		# Мини-игра атаки ещё не реализована: автоуспех без паузы/софтлока.
		_apply_outcome(chosen, tier, true)
		toast.emit("АТАКА: %s · АВТООТРАЖЕНА" % _attack_name(chosen))
		_emit_resolved(id, chosen, true, tier)
		return id

	# Мини-игра атаки: кнопка отказа — СДАТЬСЯ, Esc подтверждает сдачу.
	if game_node is MiniGame:
		game_node.is_attack = true
	_active_game = game_node
	_active_id = id
	_active_kind = chosen
	_active_tier = tier
	active_attacks[id] = {
		"id": id,
		"kind": chosen,
		"name": _attack_name(chosen),
		"tier": tier,
		"state": "minigame",
	}
	attack_added.emit(id)
	if game_node.has_signal("finished"):
		game_node.finished.connect(_on_minigame_finished)
	if game_node is Node and game_node.get_parent() == null:
		add_child(game_node)

	# H6: пауза ставится ДО показа мини-игры, иначе час успевает тикнуть.
	if director != null and director.has_method("set_attack_paused"):
		director.call("set_attack_paused", true)
	show_attack_minigame.emit(game_node, chosen)
	return id


func _on_minigame_finished(quality: float) -> void:
	if _active_game == null and _active_kind.is_empty():
		return
	var id := _active_id
	var kind := _active_kind
	var tier := clampi(_active_tier, 1, 4)
	var game_node = _active_game
	_active_game = null
	_active_id = ""
	_active_kind = ""
	_active_tier = 1
	if game_node != null and is_instance_valid(game_node):
		game_node.queue_free()
	if active_attacks.has(id):
		active_attacks.erase(id)
		attack_removed.emit(id)

	var success := clampf(float(quality), 0.0, 1.0) >= _threshold(kind, tier)
	_apply_outcome(kind, tier, success)
	if director != null and director.has_method("set_attack_paused"):
		director.call("set_attack_paused", false)
	toast.emit("АТАКА ОТРАЖЕНА" if success else "АТАКА ПРОШЛА")
	_emit_resolved(id, kind, success, tier)


## Отмена без награды/штрафа (на случай внешнего конца часа).
func cancel_active() -> void:
	if _active_game == null:
		return
	var id := _active_id
	var kind := _active_kind
	var tier := _active_tier
	_cancel_active_game()
	if active_attacks.has(id):
		active_attacks.erase(id)
		attack_removed.emit(id)
	if director != null and director.has_method("set_attack_paused"):
		director.call("set_attack_paused", false)
	resolved.emit(id, false)
	attack_resolved.emit(kind, false, tier)


func _cancel_active_game() -> void:
	if _active_game != null and is_instance_valid(_active_game):
		_active_game.queue_free()
	_active_game = null
	_active_id = ""
	_active_kind = ""
	_active_tier = 1


# --- награда/штраф ---------------------------------------------------------

func _apply_outcome(kind: String, tier: int, success: bool) -> void:
	var row := _tier_row(kind, tier)
	var scale := _money_scale()
	if success:
		_add_money(int(round(float(row.get("reward_money", 0)) * scale)))
		_add_sla(float(row.get("reward_sla", 0)))
		return
	_add_money(int(round(float(row.get("fail_money", 0)) * scale)))
	_add_sla(float(row.get("fail_sla", 0)))
	if director == null:
		return
	match kind:
		"ddos":
			if director.has_method("attack_channel_debuff"):
				director.call("attack_channel_debuff", float(row.get("debuff_sec", 15)))
		"phishing":
			if director.has_method("attack_lock_random_file"):
				director.call("attack_lock_random_file", float(row.get("file_lock_sec", 60)))
			if director.has_method("attack_disable_send"):
				director.call("attack_disable_send", float(row.get("send_penalty_sec", 5)))
		"ransomware":
			if director.has_method("lock_random_folder"):
				director.call("lock_random_folder", float(row.get("folder_block_sec", 15)))


func _threshold(kind: String, tier: int) -> float:
	return float(_tier_row(kind, tier).get("threshold", 0.6))


func _tier_row(kind: String, tier: int) -> Dictionary:
	var cfg := _cfg(kind)
	var scaled_tier := clampi(int(tier), 1, 4)
	var tiers = cfg.get("tiers", null)
	if tiers is Array:
		var arr: Array = tiers
		if scaled_tier - 1 < arr.size() and arr[scaled_tier - 1] is Dictionary:
			return (arr[scaled_tier - 1] as Dictionary).duplicate(true)
	var fallback = FALLBACK_TIERS.get(kind, FALLBACK_TIERS["junk"])
	if fallback is Array:
		var fb: Array = fallback
		if scaled_tier - 1 < fb.size() and fb[scaled_tier - 1] is Dictionary:
			return (fb[scaled_tier - 1] as Dictionary).duplicate(true)
	return {}


func _cfg(kind: String) -> Dictionary:
	var data = _data()
	if data != null and data.has_method("attack_def"):
		var def = data.attack_def(kind)
		if def is Dictionary and not (def as Dictionary).is_empty():
			return def
	return {
		"name_ru": str(FALLBACK_NAMES.get(kind, kind)),
		"tiers": (FALLBACK_TIERS.get(kind, FALLBACK_TIERS["junk"]) as Array).duplicate(true),
	}


func _attack_name(kind: String) -> String:
	return str(_cfg(kind).get("name_ru", FALLBACK_NAMES.get(kind, kind)))


func _money_scale() -> float:
	var scale := maxf(0.75, float(hour) / 3.0)
	var data = _data()
	if data != null and data.get("balance") is Dictionary:
		var attacks = (data.balance as Dictionary).get("attacks", null)
		if attacks is Dictionary:
			var by_hour = (attacks as Dictionary).get("money_scale_by_hour", null)
			if by_hour is Array and not (by_hour as Array).is_empty():
				var arr: Array = by_hour
				scale = float(arr[clampi(hour - 1, 0, arr.size() - 1)])
			elif by_hour is Dictionary:
				scale = float((by_hour as Dictionary).get(str(hour), scale))
			var mult := float((attacks as Dictionary).get("money_scale", 1.0))
			scale *= mult
	return maxf(0.0, scale)


func _shield_scale() -> float:
	var data = _data()
	if data != null and data.get("balance") is Dictionary:
		var attacks = (data.balance as Dictionary).get("attacks", null)
		if attacks is Dictionary:
			return maxf(0.0, float((attacks as Dictionary).get("shield_reward_scale", 0.5)))
	return 0.5


func _emit_resolved(id: String, kind: String, success: bool, tier: int) -> void:
	resolved.emit(id, success)
	attack_resolved.emit(kind, success, tier)


# --- выбор атаки -----------------------------------------------------------

func _pick_kind_for_hour(p_hour: int, previous: String) -> String:
	var candidates: Array[String] = []
	var weights: Array[float] = []
	var idx := clampi(int(p_hour) - 1, 0, 8)
	for kind in KINDS:
		var w := _kind_weight(kind, idx)
		if w <= 0.0:
			continue
		candidates.append(kind)
		weights.append(w)
	if candidates.is_empty():
		return ""
	if candidates.size() == 1:
		return candidates[0]
	# Не повторять вид дважды подряд, если есть альтернатива с весом > 0.
	if candidates.has(previous):
		var alternative := false
		for i in range(candidates.size()):
			if candidates[i] != previous and weights[i] > 0.0:
				alternative = true
				break
		if alternative:
			weights[candidates.find(previous)] = 0.0
	var total := 0.0
	for w in weights:
		total += maxf(0.0, float(w))
	if total <= 0.0:
		return candidates[0]
	var roll := _randf() * total
	var acc := 0.0
	for i in range(candidates.size()):
		acc += maxf(0.0, float(weights[i]))
		if roll < acc:
			return candidates[i]
	return candidates[candidates.size() - 1]


func _kind_weight(kind: String, idx: int) -> float:
	var data = _data()
	if data != null and data.has_method("attack_def"):
		var def = data.attack_def(kind)
		if def is Dictionary:
			var arr = def.get("weight_by_hour", null)
			if arr is Array and not (arr as Array).is_empty():
				var table: Array = arr
				return maxf(0.0, float(table[clampi(idx, 0, table.size() - 1)]))
	# Fallback: junk/ddos с H2, phishing с H4, ransomware с H5.
	match kind:
		"junk", "ddos":
			return 1.0 if idx >= 1 else 0.0
		"phishing":
			return 1.0 if idx >= 3 else 0.0
		"ransomware":
			return 1.0 if idx >= 4 else 0.0
	return 0.0


# --- legacy-заглушки (старый UI/тесты) -------------------------------------

func destroy(_id: String) -> bool:
	return false


func quarantine(_id: String) -> bool:
	return false


func hold_shield(_seconds: float) -> bool:
	return false


func resolve_phishing(_request_id: String, _outcome: String) -> void:
	pass


func on_junk_packet_destroyed(_packet_id: String) -> bool:
	return false


func on_ransomware_file(_file_id: String, _attack_id: String) -> void:
	pass


func on_file_destroyed(_file_id: String) -> bool:
	return false


func on_ransomware_packet_destroyed(_packet_id: String) -> bool:
	return false


func kind_name(kind: String) -> String:
	return _attack_name(kind)


func shield_unlocked() -> bool:
	var game = _game()
	if game == null:
		return false
	var max_shield := 0
	if game.has_method("shield_max"):
		max_shield = int(game.shield_max())
	return max_shield > 0


# --- служебное -------------------------------------------------------------

func _sync_game_shield() -> void:
	var game = _game()
	if game != null and game.get("shield_charges") != null:
		game.shield_charges = maxi(0, int(shield_charges))


func _add_money(delta: int) -> void:
	var game = _game()
	if game == null:
		return
	if game.has_method("add_money"):
		game.add_money(int(delta), "attack")
	else:
		game.money = maxi(0, int(game.money) + int(delta))


func _add_sla(delta: float) -> void:
	var game = _game()
	if game == null:
		return
	if game.has_method("add_sla"):
		game.add_sla(float(delta), "attack")


func _randf() -> float:
	if director != null and director.get("rng") != null:
		var r = director.rng
		if r.has_method("randf"):
			return clampf(float(r.randf()), 0.0, 0.999999)
	var rng = _autoload("Rng")
	if rng != null and rng.has_method("randf"):
		return clampf(float(rng.randf()), 0.0, 0.999999)
	return clampf(randf(), 0.0, 0.999999)


func _randf_range(from: float, to: float) -> float:
	if director != null and director.get("rng") != null:
		var r = director.rng
		if r.has_method("randf_range"):
			return float(r.randf_range(from, to))
	var rng = _autoload("Rng")
	if rng != null and rng.has_method("randf_range"):
		return float(rng.randf_range(from, to))
	return randf_range(from, to)


func _randi_range(from: int, to: int) -> int:
	if to < from:
		return from
	if director != null and director.get("rng") != null:
		var r = director.rng
		if r.has_method("randi_range"):
			return int(r.randi_range(from, to))
	var rng = _autoload("Rng")
	if rng != null and rng.has_method("randi_range"):
		return int(rng.randi_range(from, to))
	return randi_range(from, to)


func _game():
	return _autoload("Game")


func _data():
	return _autoload("Data")


func _autoload(name: String):
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null(name)
	return null


func _play_sfx(id: StringName) -> void:
	var audio = _autoload("Audio")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(str(id))
