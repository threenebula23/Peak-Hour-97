class_name AttackDirector
extends Node
## Атаки часа: мусор, DDoS, фишинг, шифровальщик.
##
## Тик идёт из HourDirector (единый Clock). Атаки не занимают буфер (D07),
## спавнятся в окне 60–240 с часа и не открываются во время мини-игры.
## Расписание: min(4, 1 + floor((hour−2)/2)); час 1 — без атак
## (junk открывается с часа 2, D23).

signal attack_added(id: String)
signal attack_changed(id: String)
signal attack_removed(id: String)
signal toast(text: String)
signal resolved(id: String, success: bool)

const KINDS: Array[String] = ["junk", "ddos", "phishing", "ransomware"]
const KIND_WEIGHTS: Array[float] = [3.0, 2.0, 2.0, 2.0]
const WINDOW_MIN := 60.0
const WINDOW_MAX := 240.0
const DDOS_RESPONSE_SEC := 8.0

const FALLBACK = {
	"junk": {
		"name_ru": "Мусорный пакет", "duration_sec": 15.0,
		"reward_money": 5, "reward_sla": 1, "fail_money": -10, "fail_sla": -5,
		"filter_disabled_sec": 10.0,
	},
	"ddos": {
		"name_ru": "DDoS", "cards_min": 8, "cards_max": 12,
		"spawn_window_sec": 2.0, "shield_hold_sec": 1.5,
		"reward_money": 30, "reward_sla": 2, "fail_sla": -15,
		"channel_debuff": 0.4, "channel_debuff_sec": 15.0,
		"packets_lost": 2, "recv_disabled_sec": 5.0,
	},
	"phishing": {
		"name_ru": "Фишинг",
		"reward_money": 20, "reward_sla": 2, "fail_money": -40, "fail_sla": -10,
		"file_lock_sec": 60.0, "send_disabled_sec": 5.0,
		"timeout_money": -20, "timeout_sla": -5, "timeout_lock_sec": 30.0,
	},
	"ransomware": {
		"name_ru": "Шифровальщик", "folder_block_delay_sec": 3.0,
		"auto_unlock_sec": 30.0, "auto_unlock_money": -30, "auto_unlock_sla": -10,
		"reward_money": 25, "reward_sla": 2,
	},
}

## Ссылка на HourDirector (без type hint — избегаем циклических preload).
var director = null
var active_attacks: Dictionary = {}
var hour: int = 1
var elapsed: float = 0.0

var _schedule: Array[float] = []
var _next_index: int = 0
var _counter: int = 0
var _allow_spawn: bool = true
var _ransomware_files: Dictionary = {}
## Апгрейд «Щит»: сколько раз автоотражение уже сработало в этом часе.
var shield_used_this_hour: int = 0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func setup(director_node) -> void:
	director = director_node


func reset(p_hour: int) -> void:
	# Старые атаки часа не переносятся.
	for id in active_attacks.keys():
		active_attacks.erase(id)
		attack_removed.emit(str(id))
	_ransomware_files.clear()
	hour = maxi(1, int(p_hour))
	elapsed = 0.0
	_counter = 0
	_next_index = 0
	_schedule.clear()
	var count := attacks_for_hour(hour)
	for i in range(count):
		_schedule.append(_randf_range(WINDOW_MIN, WINDOW_MAX))
	_schedule.sort()
	_allow_spawn = true
	shield_used_this_hour = 0


func set_allow_spawn(value: bool) -> void:
	_allow_spawn = value


## Сколько атак запланировано на час (D23: атаки с часа 2, час 1 — 0).
static func attacks_for_hour(p_hour: int) -> int:
	var h := maxi(1, int(p_hour))
	if h == 1:
		return 0
	return clampi(1 + int(floor(float(h - 2) / 2.0)), 1, 4)


func tick(delta: float) -> void:
	# HourDirector уже применил D11-кап и timescale, поэтому здесь не режем
	# delta повторно (иначе ускоренные тесты не доживают до окна атак).
	var dt := maxf(delta, 0.0)
	elapsed += dt
	_tick_active(dt)
	_tick_ransomware(dt)
	_maybe_spawn()


## Публичный спавн (UI/тесты). kind="" — случайный по весам среди открытых.
## Закрытая в прогрессии атака не спавнится (п.16).
func spawn_attack(kind: String = "") -> String:
	var chosen := kind
	if chosen.is_empty():
		chosen = _pick_kind()
	if chosen.is_empty():
		return ""
	if not KINDS.has(chosen):
		chosen = "junk"
	if not _kind_unlocked(chosen):
		return ""
	var id := "atk_%d_%d" % [hour, _counter]
	_counter += 1
	# Апгрейд «Щит» (shop_shield): первый DDoS часа отражается автоматически —
	# награда как за ручное отражение, без урона по каналу и SLA.
	if chosen == "ddos" and shield_unlocked() and shield_used_this_hour < 1:
		shield_used_this_hour += 1
		var ddos_cfg := _cfg("ddos")
		_add_money(int(ddos_cfg.get("reward_money", 30)))
		_add_sla(float(ddos_cfg.get("reward_sla", 2)))
		toast.emit("ЩИТ ОТРАЗИЛ DDoS")
		_play_sfx(&"attack_blocked")
		# Атака не попадает в active_attacks, но учитывается как отражённая.
		resolved.emit(id, true)
		return id
	var cfg := _cfg(chosen)
	var data := {
		"id": id,
		"kind": chosen,
		"name": str(cfg.get("name_ru", chosen)),
		"time_left": 0.0,
		"total": 0.0,
		"cards": 1,
		"shield_hold": 0.0,
		"shield_needed": 0.0,
		"request_id": "",
		"packet_id": "",
		"file_id": "",
	}
	match chosen:
		"junk":
			var duration := float(cfg.get("duration_sec", 15.0))
			data["time_left"] = duration
			data["total"] = duration
			var junk_packet := ""
			if director != null and director.has_method("spawn_junk_packet"):
				junk_packet = str(director.spawn_junk_packet(id))
			if junk_packet.is_empty():
				return ""
			data["packet_id"] = junk_packet
		"ddos":
			var cards := _randi_range(int(cfg.get("cards_min", 8)), int(cfg.get("cards_max", 12)))
			var window := float(cfg.get("spawn_window_sec", 2.0)) + DDOS_RESPONSE_SEC
			data["cards"] = cards
			data["time_left"] = window
			data["total"] = window
			data["shield_needed"] = float(cfg.get("shield_hold_sec", 1.5))
		"phishing":
			var request_id := ""
			if director != null and director.has_method("spawn_phishing_request"):
				request_id = str(director.spawn_phishing_request(id))
			if request_id.is_empty():
				return ""
			data["request_id"] = request_id
			data["time_left"] = 30.0
			data["total"] = 30.0
		"ransomware":
			var packet_id := ""
			if director != null and director.has_method("spawn_ransomware_packet"):
				packet_id = str(director.spawn_ransomware_packet(id))
			if packet_id.is_empty():
				return ""
			data["packet_id"] = packet_id
			data["time_left"] = 20.0
			data["total"] = 20.0
	active_attacks[id] = data
	attack_added.emit(id)
	toast.emit("АТАКА: %s" % str(data.get("name", chosen)))
	_play_sfx(&"attack")
	return id


## Уничтожить карточку атаки (мусор/шифровальщик). Возвращает true при успехе.
func destroy(id: String) -> bool:
	if not active_attacks.has(id):
		return false
	var data: Dictionary = active_attacks[id]
	var kind := str(data.get("kind", ""))
	match kind:
		"junk":
			var packet_id := str(data.get("packet_id", ""))
			if not packet_id.is_empty() and director != null and director.has_method("destroy_attack_packet"):
				return bool(director.destroy_attack_packet(packet_id))
			var cfg := _cfg("junk")
			_add_money(int(cfg.get("reward_money", 5)))
			_add_sla(float(cfg.get("reward_sla", 1)))
			_remove(id, true)
			return true
		"ransomware":
			var packet_id := str(data.get("packet_id", ""))
			if not packet_id.is_empty() and director != null and director.has_method("destroy_attack_packet"):
				return bool(director.destroy_attack_packet(packet_id))
			return false
	return false


## Drag в карантин: для мусора эквивалентно уничтожению.
func quarantine(id: String) -> bool:
	return destroy(id)


## Пакет-мусор уничтожен/отправлен в карантин: награда, карточка убирается.
func on_junk_packet_destroyed(packet_id: String) -> bool:
	for id in active_attacks.keys():
		var data: Dictionary = active_attacks[id]
		if str(data.get("kind", "")) == "junk" and str(data.get("packet_id", "")) == packet_id:
			var cfg := _cfg("junk")
			_add_money(int(cfg.get("reward_money", 5)))
			_add_sla(float(cfg.get("reward_sla", 1)))
			_remove(str(id), true)
			return true
	return false


## Удержание щита против DDoS: накапливает секунды, при 1.5 с — отражение.
func hold_shield(seconds: float) -> bool:
	var held := false
	for id in active_attacks.keys():
		var data: Dictionary = active_attacks[id]
		if str(data.get("kind", "")) != "ddos":
			continue
		held = true
		data["shield_hold"] = float(data.get("shield_hold", 0.0)) + maxf(0.0, seconds)
		if float(data.get("shield_hold", 0.0)) >= float(data.get("shield_needed", 1.5)):
			_resolve_ddos(str(id), true)
		else:
			attack_changed.emit(str(id))
	if held:
		_play_sfx(&"attack_blocked")
	return held


## Завершение фишинга: "rejected", "timeout", "sent" или "destroyed".
func resolve_phishing(request_id: String, outcome: String) -> void:
	var attack_id := ""
	for id in active_attacks.keys():
		if str(active_attacks[id].get("request_id", "")) == request_id:
			attack_id = str(id)
			break
	if attack_id.is_empty():
		return
	var cfg := _cfg("phishing")
	match outcome:
		"rejected", "destroyed":
			_add_money(int(cfg.get("reward_money", 20)))
			_add_sla(float(cfg.get("reward_sla", 2)))
			_remove(attack_id, true)
		"timeout":
			_add_money(int(cfg.get("timeout_money", -20)))
			_add_sla(float(cfg.get("timeout_sla", -5)))
			if director != null and director.has_method("attack_lock_random_file"):
				director.attack_lock_random_file(float(cfg.get("timeout_lock_sec", 30.0)))
			_remove(attack_id, false)
		_:
			_add_money(int(cfg.get("fail_money", -40)))
			_add_sla(float(cfg.get("fail_sla", -10)))
			if director != null:
				if director.has_method("attack_disable_send"):
					director.attack_disable_send(float(cfg.get("send_disabled_sec", 5.0)))
				if director.has_method("attack_lock_random_file"):
					director.attack_lock_random_file(float(cfg.get("file_lock_sec", 60.0)))
			_remove(attack_id, false)


## Шифровальщик попал на склад: файл помечен malicious и ждёт 30 с.
func on_ransomware_file(file_id: String, attack_id: String) -> void:
	if file_id.is_empty():
		return
	var game = _game()
	var folder_id := ""
	if game != null and game.registry != null:
		game.registry.mark_malicious(file_id, "ransomware")
		var registry_file = game.registry.files.get(file_id)
		if registry_file != null:
			folder_id = str(registry_file.folder_id)
	var cfg := _cfg("ransomware")
	_ransomware_files[file_id] = {
		"attack_id": attack_id,
		"folder_id": folder_id,
		"left": float(cfg.get("auto_unlock_sec", 30.0)),
		"block_left": float(cfg.get("folder_block_delay_sec", 3.0)),
		"blocked": false,
	}
	if active_attacks.has(attack_id):
		active_attacks[attack_id]["file_id"] = file_id
		active_attacks[attack_id]["packet_id"] = ""
		attack_changed.emit(attack_id)
	toast.emit("ШИФРОВАЛЬЩИК: файл заблокирован, уничтожьте его")


## Файл-шифровальщик уничтожен игроком — награда.
func on_file_destroyed(file_id: String) -> bool:
	if not _ransomware_files.has(file_id):
		return false
	var info: Dictionary = _ransomware_files[file_id]
	var attack_id := str(info.get("attack_id", ""))
	_clear_folder_block(info)
	var cfg := _cfg("ransomware")
	_add_money(int(cfg.get("reward_money", 25)))
	_add_sla(float(cfg.get("reward_sla", 2)))
	_ransomware_files.erase(file_id)
	if active_attacks.has(attack_id):
		_remove(attack_id, true)
	else:
		toast.emit("Шифровальщик уничтожен")
	return true


## Пакет-шифровальщик уничтожен до заноса.
func on_ransomware_packet_destroyed(packet_id: String) -> bool:
	for id in active_attacks.keys():
		var data: Dictionary = active_attacks[id]
		if str(data.get("kind", "")) == "ransomware" and str(data.get("packet_id", "")) == packet_id:
			var cfg := _cfg("ransomware")
			_add_money(int(cfg.get("reward_money", 25)))
			_add_sla(float(cfg.get("reward_sla", 2)))
			_remove(str(id), true)
			return true
	return false


func kind_name(kind: String) -> String:
	return str(_cfg(kind).get("name_ru", kind))


## Куплен ли апгрейд «Щит» (shop_shield → Game.upgrades.shield_unlocked).
func shield_unlocked() -> bool:
	var game = _game()
	if game == null:
		return false
	var upgrades = game.get("upgrades")
	if not (upgrades is Dictionary):
		return false
	return int((upgrades as Dictionary).get("shield_unlocked", 0)) > 0


# --- тик -------------------------------------------------------------------

func _tick_active(dt: float) -> void:
	for id in active_attacks.keys():
		if not active_attacks.has(id):
			continue
		var data: Dictionary = active_attacks[id]
		var kind := str(data.get("kind", ""))
		if kind == "phishing":
			# Таймер запроса ведёт HourDirector; здесь только синхронизация карточки.
			if data.get("request_id", "") != "" and director != null and not director.has_request(str(data.get("request_id", ""))):
				_remove(str(id), false)
			continue
		if kind == "ransomware":
			var packet_id := str(data.get("packet_id", ""))
			if packet_id.is_empty():
				continue
			if director != null and not director.has_packet(packet_id):
				# Пакет уже занесён/уничтожен — карточку атаки убираем.
				_remove(str(id), false)
			continue
		if kind == "junk":
			var junk_packet := str(data.get("packet_id", ""))
			if junk_packet.is_empty() or (director != null and not director.has_packet(junk_packet)):
				# Пакет вытеснен из буфера/уже обработан — карточка неактуальна.
				_remove(str(id), false)
				continue
		data["time_left"] = float(data.get("time_left", 0.0)) - dt
		if kind == "junk" and float(data["time_left"]) <= 0.0:
			_fail_junk(str(id))
		elif kind == "ddos":
			if float(data["time_left"]) <= 0.0:
				_resolve_ddos(str(id), false)
			else:
				attack_changed.emit(str(id))


func _tick_ransomware(dt: float) -> void:
	var game = _game()
	for file_id in _ransomware_files.keys():
		if not _ransomware_files.has(file_id):
			continue
		var info: Dictionary = _ransomware_files[file_id]
		var attack_id := str(info.get("attack_id", ""))
		# Файл уже уничтожен через FileRegistry — засчитываем отражение.
		if game == null or game.registry == null or not game.registry.files.has(file_id):
			_reward_ransomware(str(file_id), attack_id)
			continue
		# folder_block_delay_sec: папка и файл блокируются с задержкой.
		if not bool(info.get("blocked", false)):
			info["block_left"] = float(info.get("block_left", 0.0)) - dt
			if float(info["block_left"]) <= 0.0:
				var folder_id := str(info.get("folder_id", ""))
				var left: float = maxf(0.1, float(info.get("left", 30.0)))
				if director != null and director.has_method("lock_ransomware_folder"):
					director.lock_ransomware_folder(folder_id, str(file_id), left)
				info["blocked"] = true
		info["left"] = float(info.get("left", 0.0)) - dt
		if float(info["left"]) > 0.0:
			continue
		var cfg := _cfg("ransomware")
		_add_money(int(cfg.get("auto_unlock_money", -30)))
		_add_sla(float(cfg.get("auto_unlock_sla", -10)))
		_remove_ransomware_file(str(file_id))
		_clear_folder_block(info)
		_ransomware_files.erase(file_id)
		if active_attacks.has(attack_id):
			_remove(attack_id, false)
		toast.emit("Шифровальщик: файл потерян, −30 $, −10 SLA")


## Авто-unlock: снять lock и убрать файл (lock не даёт remove_file напрямую).
func _remove_ransomware_file(file_id: String) -> void:
	var game = _game()
	if game == null or game.registry == null or not game.registry.files.has(file_id):
		return
	var file = game.registry.files[file_id]
	if str(file.location) == "locked":
		game.registry.unlock_file(file_id)
		file = game.registry.files.get(file_id)
		if file == null:
			return
	if str(file.location) != "malicious":
		game.registry.mark_malicious(file_id, "ransomware")
	game.registry.remove_file(file_id)


func _clear_folder_block(info: Dictionary) -> void:
	var folder_id := str(info.get("folder_id", ""))
	if folder_id.is_empty() or director == null:
		return
	if director.has_method("unlock_ransomware_folder"):
		director.unlock_ransomware_folder(folder_id)


func _reward_ransomware(file_id: String, attack_id: String) -> void:
	var cfg := _cfg("ransomware")
	if _ransomware_files.has(file_id):
		_clear_folder_block(_ransomware_files[file_id])
	_add_money(int(cfg.get("reward_money", 25)))
	_add_sla(float(cfg.get("reward_sla", 2)))
	_ransomware_files.erase(file_id)
	if active_attacks.has(attack_id):
		_remove(attack_id, true)
	else:
		toast.emit("Шифровальщик уничтожен")


func _maybe_spawn() -> void:
	if not _allow_spawn:
		return
	if _next_index >= _schedule.size():
		return
	if elapsed > WINDOW_MAX:
		_next_index = _schedule.size()
		return
	if elapsed < float(_schedule[_next_index]):
		return
	var kind := "junk" if hour <= 1 else _pick_kind()
	if spawn_attack(kind).is_empty():
		# Не удалось (например, нет файлов для фишинга) — пропускаем слот.
		pass
	_next_index += 1


func _fail_junk(id: String) -> void:
	var cfg := _cfg("junk")
	var data: Dictionary = active_attacks.get(id, {})
	var packet_id := str(data.get("packet_id", ""))
	if not packet_id.is_empty() and director != null and director.has_method("junk_auto_carry"):
		director.junk_auto_carry(packet_id, id)
	_add_money(int(cfg.get("fail_money", -10)))
	_add_sla(float(cfg.get("fail_sla", -5)))
	if director != null:
		if director.has_method("attack_disable_recv"):
			director.attack_disable_recv(float(cfg.get("filter_disabled_sec", 10.0)))
		if director.has_method("attack_disable_send"):
			director.attack_disable_send(5.0)
	_remove(id, false)
	toast.emit("Мусор попал в приём: −10 $, −5 SLA")


func _resolve_ddos(id: String, success: bool) -> void:
	if not active_attacks.has(id):
		return
	var cfg := _cfg("ddos")
	if success:
		_add_money(int(cfg.get("reward_money", 30)))
		_add_sla(float(cfg.get("reward_sla", 2)))
	else:
		_add_sla(float(cfg.get("fail_sla", -15)))
		if director != null:
			if director.has_method("attack_channel_debuff"):
				director.attack_channel_debuff(float(cfg.get("channel_debuff_sec", 15.0)))
			if director.has_method("attack_lose_packets"):
				director.attack_lose_packets(int(cfg.get("packets_lost", 2)))
			if director.has_method("attack_disable_recv"):
				director.attack_disable_recv(float(cfg.get("recv_disabled_sec", 5.0)))
		toast.emit("DDoS пробил канал: −15 SLA, канал замедлен")
	if success:
		toast.emit("DDoS отражён: +30 $, +2 SLA")
	_remove(id, success)


func _remove(id: String, success: bool) -> void:
	if not active_attacks.has(id):
		return
	active_attacks.erase(id)
	attack_removed.emit(id)
	resolved.emit(id, success)


# --- служебное -------------------------------------------------------------

## Открыта ли атака: progression.unlocks → attack_<kind>.
func _kind_unlocked(kind: String) -> bool:
	return _feature_unlocked("attack_" + str(kind))


func _feature_unlocked(id: String) -> bool:
	var game = _game()
	if game != null and game.has_method("feature_unlocked"):
		return bool(game.feature_unlocked(id))
	return true


func _unlocked_kinds() -> Array[String]:
	var out: Array[String] = []
	for kind in KINDS:
		if _kind_unlocked(kind):
			out.append(kind)
	return out


func _pick_kind() -> String:
	var kinds := _unlocked_kinds()
	if kinds.is_empty():
		return ""
	if hour <= 1:
		return "junk" if kinds.has("junk") else ""
	var weights: Array[float] = []
	for kind in kinds:
		weights.append(KIND_WEIGHTS[KINDS.find(kind)])
	var index := _weighted_index(weights)
	if index < 0 or index >= kinds.size():
		return kinds[0]
	return kinds[index]


func _weighted_index(weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += maxf(0.0, float(w))
	if total <= 0.0:
		return 0
	var roll := _randf() * total
	var acc := 0.0
	for i in range(weights.size()):
		acc += maxf(0.0, float(weights[i]))
		if roll < acc:
			return i
	return weights.size() - 1


func _cfg(kind: String) -> Dictionary:
	var data = _data()
	if data != null and data.get("balance") is Dictionary:
		var attacks = data.balance.get("attacks", null)
		if attacks is Dictionary and attacks.get(kind, null) is Dictionary:
			return attacks[kind]
	return FALLBACK.get(kind, FALLBACK["junk"])


func _add_money(delta: int) -> void:
	var game = _game()
	if game == null:
		return
	if game.has_method("add_money"):
		game.add_money(delta, "attack")
	else:
		game.money = maxi(0, int(game.money) + delta)


func _add_sla(delta: float) -> void:
	var game = _game()
	if game == null:
		return
	if game.has_method("add_sla"):
		game.add_sla(delta, "attack")


func _randf() -> float:
	if director != null and director.get("rng") != null:
		var rng = director.rng
		if rng.has_method("randf"):
			return float(rng.randf())
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var rng = (loop as SceneTree).root.get_node_or_null("Rng")
		if rng != null and rng.has_method("randf"):
			return float(rng.randf())
	return randf()


func _randf_range(from: float, to: float) -> float:
	if director != null and director.get("rng") != null:
		var rng = director.rng
		if rng.has_method("randf_range"):
			return float(rng.randf_range(from, to))
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var rng = (loop as SceneTree).root.get_node_or_null("Rng")
		if rng != null and rng.has_method("randf_range"):
			return float(rng.randf_range(from, to))
	return randf_range(from, to)


func _randi_range(from: int, to: int) -> int:
	if director != null and director.get("rng") != null:
		var rng = director.rng
		if rng.has_method("randi_range"):
			return int(rng.randi_range(from, to))
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var rng = (loop as SceneTree).root.get_node_or_null("Rng")
		if rng != null and rng.has_method("randi_range"):
			return int(rng.randi_range(from, to))
	return randi_range(from, to)


func _game():
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("Game")
	return null


func _data():
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("Data")
	return null


func _play_sfx(id: StringName) -> void:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return
	var audio = (loop as SceneTree).root.get_node_or_null("Audio")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(str(id))
