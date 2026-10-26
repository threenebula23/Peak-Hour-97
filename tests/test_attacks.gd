extends SceneTree
## Headless-тест v2 AttackDirector: расписание, окно спавна, ступени по часу,
## щит-заряды, награды/штрафы из данных, H6-гонка «пауза до показа»,
## null-фабрика и отсутствие старых сущностей атак.
##
## Запуск:
##   godot --headless --path . --script tests/test_attacks.gd

const HD := preload("res://scripts/core/hour_director.gd")
const AD := preload("res://scripts/systems/attack_director.gd")
const ECONOMY := preload("res://scripts/core/economy.gd")

var _checks: int = 0
var _fails: int = 0
var _case: String = ""
var _game = null
var _hd = null
var _data = null
var _toasts: Array = []
var _resolved_events: Array = []
var _attack_shows: int = 0
var _hour_resolved: Array = []


class FakeGame:
	extends Node
	signal finished(quality: float)


func _init() -> void:
	await process_frame
	_game = root.get_node_or_null("Game")
	_data = root.get_node_or_null("Data")
	if _game == null:
		_fail("autoload Game недоступен")
		_finish()
		return
	_hd = HD.new()
	_hd.name = "HourDirectorAttacksTest"
	root.add_child(_hd)
	_hd.toast.connect(_on_toast)
	_hd.show_attack_minigame.connect(_on_attack_show)
	_hd.attack_resolved.connect(_on_attack_resolved)

	_test_schedule_table()
	_test_window_by_duration()
	_test_tier_by_hour()
	_test_schedule_window()
	_test_pause_before_emit_race()
	_test_shield_auto_block()
	_test_rewards_and_fines()
	_test_null_factory()
	_test_no_old_entities()
	_finish()


# --- расписание ------------------------------------------------------------

func _test_schedule_table() -> void:
	_set_case("schedule_table")
	var expected: Array[int] = [0, 1, 1, 2, 2, 3, 3, 4, 4]
	for h in range(1, 10):
		_fresh(h)
		var ad = _hd.attack_director
		_eq(AD.attacks_for_hour(h), expected[h - 1], "атак в часе %d" % h)
		_eq(ad._schedule.size(), expected[h - 1], "часть расписания H%d" % h)
		var prev := ""
		var win_min := clampf(0.25 * _hour_seconds(h), 20.0, 60.0)
		var win_max := minf(0.85 * _hour_seconds(h), _hour_seconds(h) - 20.0)
		for i in range(ad._schedule.size()):
			var t := float(ad._schedule[i])
			_ok(t >= win_min - 0.001 and t <= win_max + 0.001,
				"H%d: время атаки в окне %.1f–%.1f (t=%.2f)" % [h, win_min, win_max, t])
			if i > 0:
				_ok(t >= float(ad._schedule[i - 1]), "H%d: расписание отсортировано" % h)
			var kind := str(ad._schedule_kinds[i])
			_ok(AD.KINDS.has(kind), "H%d: корректный вид атаки (%s)" % [h, kind])
			if i > 0 and expected[h - 1] >= 2:
				_ok(kind != prev, "H%d: вид не повторяется дважды подряд" % h)
			prev = kind


## v4: окно атак масштабируется длительностью часа:
## start=clamp(0.25*duration,20,60), end=min(0.85*duration,duration-20).
func _test_window_by_duration() -> void:
	_set_case("window_by_duration")
	var expected := {
		1: [30.0, 100.0],
		2: [37.5, 127.5],
		3: [45.0, 153.0],
		4: [52.5, 178.5],
		5: [60.0, 204.0],
		6: [60.0, 229.5],
		7: [60.0, 255.0],
		8: [60.0, 280.5],
		9: [60.0, 306.0],
	}
	for h in range(1, 10):
		_fresh(h)
		var ad = _hd.attack_director
		var pair: Array = expected[h]
		_approx(float(ad._window_min), float(pair[0]), 0.001,
			"H%d: window_min = %.1f" % [h, float(pair[0])])
		_approx(float(ad._window_max), float(pair[1]), 0.001,
			"H%d: window_max = %.1f" % [h, float(pair[1])])
		_eq(ad.total_count(), int(AD.attacks_for_hour(h)), "H%d: total_count" % h)
		_eq(ad.pending_count(), ad.total_count(), "H%d: pending = total до спавна" % h)
		_eq(ad.active_count(), 0, "H%d: active_count = 0 до спавна" % h)
		_eq(ad.current_tier(), ECONOMY.attack_tier(h),
			"H%d: current_tier по часу" % h)
		if ad.total_count() == 0:
			continue
		var fake := FakeGame.new()
		ad.create_game_override = func(_kind, _tier, _seed, _ctx) -> Node:
			return fake
		var id := str(ad.spawn_attack("junk"))
		_ok(not id.is_empty(), "H%d: атака открыта вручную" % h)
		_eq(ad.active_count(), 1, "H%d: active_count = 1" % h)
		_eq(ad.current_tier(), ECONOMY.attack_tier(h),
			"H%d: current_tier активной атаки" % h)
		_eq(ad.pending_count(), ad.total_count(),
			"H%d: ручной спавн не съедает расписание" % h)
		fake.emit_signal("finished", 1.0)
		_eq(ad.active_count(), 0, "H%d: после finished active_count = 0" % h)
		fake.queue_free()


func _test_tier_by_hour() -> void:
	_set_case("tier_by_hour")
	_eq(ECONOMY.attack_tier(1), 1, "H1 → T1")
	_eq(ECONOMY.attack_tier(2), 1, "H2 → T1")
	_eq(ECONOMY.attack_tier(3), 1, "H3 → T1")
	_eq(ECONOMY.attack_tier(4), 2, "H4 → T2")
	_eq(ECONOMY.attack_tier(5), 2, "H5 → T2")
	_eq(ECONOMY.attack_tier(6), 3, "H6 → T3")
	_eq(ECONOMY.attack_tier(8), 4, "H8 → T4")
	_eq(ECONOMY.attack_tier(9), 4, "H9 → T4")
	for pair in [[2, 1], [4, 2], [6, 3], [8, 4]]:
		var h := int(pair[0])
		var want := int(pair[1])
		_fresh(h)
		var ad = _hd.attack_director
		var captured: Dictionary = {}
		var fake := FakeGame.new()
		ad.create_game_override = func(_kind, tier, _seed, _ctx) -> Node:
			captured["tier"] = tier
			return fake
		ad.spawn_attack("junk")
		_eq(int(captured.get("tier", 0)), want, "H%d: мини-игра открыта со ступенью T%d" % [h, want])
		fake.emit_signal("finished", 1.0)


func _test_schedule_window() -> void:
	_set_case("spawn_window")
	_fresh(2)
	var ad = _hd.attack_director
	var fake := FakeGame.new()
	ad.create_game_override = func(_kind, _tier, _seed, _ctx) -> Node:
		return fake
	var auto_finish := func(_game_node, _kind) -> void:
		fake.emit_signal("finished", 1.0)
	_hd.show_attack_minigame.connect(auto_finish)
	ad._schedule.clear()
	ad._schedule.append(100.0)
	ad._schedule_kinds.clear()
	ad._schedule_kinds.append("junk")
	ad._next_index = 0
	ad.elapsed = 99.8
	_attack_shows = 0
	ad.tick(0.1)
	_eq(_attack_shows, 0, "до 100 с атака не спавнится")
	ad.tick(0.2)
	_eq(_attack_shows, 1, "после 100 с атака спавнится")
	_ok(ad.elapsed >= 99.999, "время атаки достигнуто")
	_ok(not _hd.is_attack_paused(), "после завершения мини-игры пауза снята")
	_hd.show_attack_minigame.disconnect(auto_finish)
	fake.queue_free()

	# Атака не спавнится, пока идёт мини-игра отправки.
	_fresh(2)
	ad = _hd.attack_director
	_hd._minigame = Node.new()
	_attack_shows = 0
	ad._schedule.clear()
	ad._schedule.append(0.0)
	ad._schedule_kinds.clear()
	ad._schedule_kinds.append("junk")
	ad._next_index = 0
	ad.elapsed = 0.0
	_hd.tick(0.1)
	_eq(_attack_shows, 0, "при открытой мини-игре отправки атака не спавнится")
	_hd._minigame.queue_free()
	_hd._minigame = null


# --- H6: пауза до emit -----------------------------------------------------

func _test_pause_before_emit_race() -> void:
	_set_case("pause_before_emit")
	_fresh(2)
	var ad = _hd.attack_director
	var fake := FakeGame.new()
	ad.create_game_override = func(_kind, _tier, _seed, _ctx) -> Node:
		return fake
	var race: Dictionary = {"paused_at_show": false, "public_paused": false}
	var instant_finish := func(_game_node, _kind) -> void:
		race["paused_at_show"] = _hd.is_attack_paused()
		race["public_paused"] = _hd.paused
		fake.emit_signal("finished", 1.0)
	_hd.show_attack_minigame.connect(instant_finish)
	var money_before: int = _game.money
	_resolved_events.clear()
	_hour_resolved.clear()
	var attack_id := str(ad.spawn_attack("junk"))
	_ok(not attack_id.is_empty(), "атака заспавнена")
	_ok(bool(race.get("paused_at_show", false)), "H6: час на паузе ДО show_attack_minigame")
	_ok(bool(race.get("public_paused", false)), "H6: публичный paused=true до показа окна")
	_ok(not _hd.is_attack_paused(), "H6: мгновенный finished снял паузу")
	_ok(not _hd.paused, "H6: публичный paused снят после finished")
	_eq(ad.active_attacks.size(), 0, "атака закрыта")
	_ok(_game.money > money_before, "мгновенный успех начислил награду")
	_ok(_resolved_events.size() >= 1, "resolved эмитится")
	_ok(_hour_resolved.size() >= 1, "hour.attack_resolved эмитится")
	if not _hour_resolved.is_empty():
		_eq(str(_hour_resolved[_hour_resolved.size() - 1].get("kind", "")), "junk", "attack_resolved: kind")
		_eq(bool(_hour_resolved[_hour_resolved.size() - 1].get("success", false)), true, "attack_resolved: success")
		_eq(int(_hour_resolved[_hour_resolved.size() - 1].get("tier", 0)), 1, "attack_resolved: tier")
	_hd.show_attack_minigame.disconnect(instant_finish)

	# Пока мини-игра открыта, время часа не тикает.
	_fresh(2)
	ad = _hd.attack_director
	fake = FakeGame.new()
	ad.create_game_override = func(_kind, _tier, _seed, _ctx) -> Node:
		return fake
	var time_before: float = _hd.time_left
	ad.spawn_attack("ddos")
	_ok(_hd.is_attack_paused(), "атака поставила час на паузу")
	for i in range(10):
		_hd.tick(0.1)
	_approx(_hd.time_left, time_before, 0.0001, "во время атаки час стоит")
	fake.emit_signal("finished", 0.0)
	_ok(not _hd.is_attack_paused(), "после провала пауза снята")
	_hd.tick(0.1)
	_ok(_hd.time_left < time_before, "после атаки час снова идёт")


# --- щит -------------------------------------------------------------------

func _test_shield_auto_block() -> void:
	_set_case("shield")
	_game.start_new_run(7001)
	_game.hour = 2
	_game.phase = &"hour"
	_game.money = 500
	_game.sla = 150.0
	_game.upgrades["sla_level"] = 4
	_game.upgrades["shield_level"] = 1
	_game.regen_shield_for_hour()
	_hd.reset_carry()
	_hd.start_hour(2)
	_game.phase = &"hour"
	_game.money = 500
	_game.sla = 150.0
	var ad = _hd.attack_director
	ad.resolved.connect(_on_resolved)
	_eq(int(ad.shield_charges), 1, "1 заряд щита из Game")
	_toasts.clear()
	_attack_shows = 0
	_resolved_events.clear()
	var row := _tier_row("ddos", ECONOMY.attack_tier(2))
	var shield_scale := _shield_scale()
	var expected := int(round(float(row.get("reward_money", 0)) * _money_scale(2) * shield_scale))
	var money_before: int = _game.money
	var sla_before: float = _game.sla
	var id := str(ad.spawn_attack("ddos"))
	_ok(not id.is_empty(), "атака обработана щитом")
	_eq(ad.active_attacks.size(), 0, "мини-игра не открывалась")
	_eq(_attack_shows, 0, "show_attack_minigame не эмитится при щите")
	_ok(not _hd.is_attack_paused(), "щит не ставит час на паузу")
	_eq(int(ad.shield_charges), 0, "заряд израсходован")
	_eq(int(_game.shield_charges), 0, "Game.shield_charges синхронизирован")
	_eq(_game.money, money_before + expected,
		"награда щита: x%.2f от денег атаки" % shield_scale)
	_approx(_game.sla, sla_before + float(row.get("reward_sla", 0)) * shield_scale, 0.001,
		"награда щита: x%.2f от SLA атаки" % shield_scale)
	_ok(_has_toast("ЩИТ ПОГЛОТИЛ АТАКУ"), "тост «ЩИТ ПОГЛОТИЛ АТАКУ»")
	_ok(_resolved_events.size() >= 1, "resolved(true) при щите")
	if not _resolved_events.is_empty():
		_ok(bool(_resolved_events[0].get("success", false)), "щит: success = true")


# --- награды/штрафы -------------------------------------------------------

func _test_rewards_and_fines() -> void:
	_set_case("reward_junk")
	_fresh(2)
	var ad = _hd.attack_director
	var fake := FakeGame.new()
	ad.create_game_override = func(_kind, _tier, _seed, _ctx) -> Node:
		return fake
	var row := _tier_row("junk", ECONOMY.attack_tier(2))
	var money_before: int = _game.money
	var sla_before: float = _game.sla
	ad.spawn_attack("junk")
	fake.emit_signal("finished", 1.0)
	_eq(_game.money, money_before + int(round(float(row.get("reward_money", 0)) * _money_scale(2))),
		"junk успех: деньги")
	_approx(_game.sla, sla_before + float(row.get("reward_sla", 0)), 0.001, "junk успех: SLA")

	_set_case("fail_ddos")
	_fresh(4)
	ad = _hd.attack_director
	fake = FakeGame.new()
	ad.create_game_override = func(_kind, _tier, _seed, _ctx) -> Node:
		return fake
	row = _tier_row("ddos", ECONOMY.attack_tier(4))
	money_before = _game.money
	sla_before = _game.sla
	ad.spawn_attack("ddos")
	fake.emit_signal("finished", 0.0)
	_eq(_game.money, money_before + int(round(float(row.get("fail_money", 0)) * _money_scale(4))),
		"DDoS провал: деньги")
	_approx(_game.sla, sla_before + float(row.get("fail_sla", 0)), 0.001, "DDoS провал: SLA")
	_ok(_hd.channel_debuff_until > _hd.hour_elapsed, "DDoS провал: дебафф канала 15 с")

	_set_case("fail_phishing")
	_fresh(4)
	ad = _hd.attack_director
	fake = FakeGame.new()
	ad.create_game_override = func(_kind, _tier, _seed, _ctx) -> Node:
		return fake
	var file = _new_file("Фишинг-цель", "text")
	row = _tier_row("phishing", ECONOMY.attack_tier(4))
	ad.spawn_attack("phishing")
	fake.emit_signal("finished", 0.0)
	_ok(_hd.send_disabled_until > _hd.hour_elapsed, "Фишинг провал: отправка -5 с")
	_ok(file != null and str(file.location) == "locked", "Фишинг провал: файл заблокирован на 60 с")

	_set_case("fail_ransomware")
	_fresh(5)
	ad = _hd.attack_director
	fake = FakeGame.new()
	ad.create_game_override = func(_kind, _tier, _seed, _ctx) -> Node:
		return fake
	ad.spawn_attack("ransomware")
	fake.emit_signal("finished", 0.0)
	_ok(not _hd.blocked_folders.is_empty(), "Шифровальщик провал: папка заблокирована на 15 с")

	_set_case("threshold")
	_fresh(2)
	ad = _hd.attack_director
	fake = FakeGame.new()
	ad.create_game_override = func(_kind, _tier, _seed, _ctx) -> Node:
		return fake
	ad.spawn_attack("junk")
	fake.emit_signal("finished", 0.59)
	_ok(not _resolved_events.is_empty(), "порог: resolved есть")
	if not _resolved_events.is_empty():
		_eq(bool(_resolved_events[_resolved_events.size() - 1].get("success", true)), false,
			"порог T1 junk 0.60: q=0.59 — провал")


func _test_null_factory() -> void:
	_set_case("null_factory")
	_fresh(2)
	var ad = _hd.attack_director
	ad.create_game_override = func(_kind, _tier, _seed, _ctx) -> Node:
		return null
	_toasts.clear()
	_resolved_events.clear()
	var money_before: int = _game.money
	var id := str(ad.spawn_attack("junk"))
	_ok(not id.is_empty(), "null-фабрика: id возвращён")
	_eq(ad.active_attacks.size(), 0, "null-фабрика: активной атаки нет")
	_ok(not _hd.is_attack_paused(), "null-фабрика: пауза снята")
	_ok(_game.money > money_before, "null-фабрика: автоуспех с наградой")
	_ok(_has_toast("АВТООТРАЖЕНА"), "null-фабрика: тост об автоуспехе")
	_ok(_resolved_events.size() >= 1, "null-фабрика: resolved(true)")
	if not _resolved_events.is_empty():
		_ok(bool(_resolved_events[0].get("success", false)), "null-фабрика: success = true")


func _test_no_old_entities() -> void:
	_set_case("no_old_entities")
	_fresh(5)
	var ad = _hd.attack_director
	var packets_before: int = _hd.active_packets.size()
	var requests_before: int = _hd.active_requests.size()
	for kind in AD.KINDS:
		var fake := FakeGame.new()
		ad.create_game_override = func(_kind, _tier, _seed, _ctx) -> Node:
			return fake
		var id := str(ad.spawn_attack(kind))
		_ok(not id.is_empty(), "атака %s открыла мини-игру" % kind)
		_ok(ad.active_attacks.has(id), "атака %s в активных до finished" % kind)
		fake.emit_signal("finished", 1.0)
		_ok(not ad.active_attacks.has(id), "атака %s закрыта после finished" % kind)
	_eq(_hd.active_packets.size(), packets_before, "атаки не создают пакеты")
	_eq(_hd.active_requests.size(), requests_before, "атаки не создают запросы")
	for packet in _hd.active_packets.values():
		_ok(not bool(packet.is_attack), "нет пакетов-атак")
	for req in _hd.active_requests.values():
		_ok(not bool(req.is_attack), "нет фишинговых запросов")


# --- служебное -------------------------------------------------------------

func _fresh(hour: int) -> void:
	_game.start_new_run(5000 + int(hour) * 31)
	_game.hour = int(hour)
	_game.phase = &"hour"
	_game.money = 500
	_game.sla = 150.0
	_game.upgrades["sla_level"] = 4
	_game.shield_charges = 0
	_hd.reset_carry()
	_hd.start_hour(int(hour))
	_hd.set_time_scale(1.0)
	_hd.files_spawned = _hd.files_budget
	_hd._next_spawn_at = 999999.0
	_hd.active_request_limit = 0
	_hd.spawn_recv_accum = 0.0
	_hd.spawn_send_accum = 0.0
	_toasts.clear()
	_resolved_events.clear()
	_hour_resolved.clear()
	_attack_shows = 0
	var ad = _hd.attack_director
	if ad != null:
		ad.resolved.connect(_on_resolved)


func _tier_row(kind: String, tier: int) -> Dictionary:
	if _data != null and _data.has_method("attack_def"):
		var def: Dictionary = _data.attack_def(kind)
		var tiers = def.get("tiers", null)
		if tiers is Array:
			var arr: Array = tiers
			var idx := clampi(int(tier), 1, arr.size()) - 1
			if arr[idx] is Dictionary:
				return (arr[idx] as Dictionary).duplicate(true)
	return {}


## Длительность часа из data/balance.json → hours[].duration.
func _hour_seconds(hour: int) -> float:
	if _data != null and _data.has_method("hour_def"):
		var row: Dictionary = _data.hour_def(int(hour))
		if row.has("duration"):
			return float(row.get("duration", 300.0))
	return 300.0


func _money_scale(hour: int) -> float:
	var scale := maxf(0.75, float(hour) / 3.0)
	if _data != null and _data.get("balance") is Dictionary:
		var attacks = (_data.balance as Dictionary).get("attacks", null)
		if attacks is Dictionary:
			scale *= float((attacks as Dictionary).get("money_scale", 1.0))
	return scale


## Множитель награды щита — из balance.json → attacks.shield_reward_scale.
func _shield_scale() -> float:
	if _data != null and _data.get("balance") is Dictionary:
		var attacks = (_data.balance as Dictionary).get("attacks", null)
		if attacks is Dictionary:
			return maxf(0.0, float((attacks as Dictionary).get("shield_reward_scale", 0.5)))
	return 0.5


func _new_file(name: String, type: String):
	var section = _game.registry.sections.get("C")
	if section == null or section.folder_ids.is_empty():
		return null
	return _game.registry.create_file(name, type, str(section.folder_ids[0]))


func _has_toast(fragment: String) -> bool:
	for text in _toasts:
		if str(text).contains(fragment):
			return true
	return false


func _on_toast(text: String) -> void:
	_toasts.append(text)


func _on_attack_show(_game_node, _kind: String) -> void:
	_attack_shows += 1


func _on_attack_resolved(kind: String, success: bool, tier: int) -> void:
	_hour_resolved.append({"kind": kind, "success": success, "tier": tier})


func _on_resolved(id: String, success: bool) -> void:
	_resolved_events.append({"id": id, "success": success})


# --- assert-хелперы --------------------------------------------------------

func _set_case(name: String) -> void:
	_case = name


func _ok(condition: bool, message: String) -> bool:
	_checks += 1
	if condition:
		return true
	_fail(message)
	return false


func _eq(actual, expected, message: String) -> bool:
	_checks += 1
	if actual == expected:
		return true
	_fail("%s — получено %s, ожидалось %s" % [message, str(actual), str(expected)])
	return false


func _approx(actual: float, expected: float, eps: float, message: String) -> bool:
	_checks += 1
	if absf(float(actual) - float(expected)) <= eps:
		return true
	_fail("%s — получено %.6f, ожидалось %.6f" % [message, float(actual), float(expected)])
	return false


func _fail(message: String) -> void:
	_fails += 1
	print("FAIL [%s] %s" % [_case, message])


func _finish() -> void:
	if _hd != null and is_instance_valid(_hd):
		_hd.free()
	print("test_attacks: проверок %d, провалов %d" % [_checks, _fails])
	print("PASS test_attacks" if _fails == 0 else "FAIL test_attacks")
	quit(0 if _fails == 0 else 1)
