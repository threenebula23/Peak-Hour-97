extends SceneTree
## Headless-тест атак часа на экране Main.tscn.
##
## Проверяет UI-интеграцию AttackDirector:
##   • junk: карточка в приёме → drop на ShieldDrop → +5 $ / +1 SLA;
##   • DDoS: плашка в ПРИЁМЕ и удержание щита 1.5 с → +30 $ / +2 SLA;
##   • phishing: приглушённый RequestCard → отклонение → +20 $ / +2 SLA;
##   • ransomware: карточка .exe → щит-карантин → +25 $ / +2 SLA;
##   • обычный пакет на щите: −2 SLA, пакет остаётся.
##
## Запуск:
##   godot --headless --path . --script tests/test_main_attacks.gd

const MAIN_SCENE := "res://scenes/Main.tscn"

var _checks := 0
var _fails := 0
var _main: Node = null
var _controller = null
var _director = null
var _game = null
var _folder_id := ""


func _init() -> void:
	await process_frame
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("не удалось загрузить Main.tscn")
		_finish()
		return
	_main = packed.instantiate()
	root.add_child(_main)
	await process_frame

	_main._start_new_run()
	await process_frame

	_game = root.get_node_or_null("Game")
	_ok(_game != null, "autoload Game доступен")
	_ok(_main.controller != null, "controller создан")
	if _game == null or _main.controller == null:
		_finish()
		return
	_controller = _main.controller
	_director = _controller.hour_director
	_ok(_director != null, "hour_director доступен")
	if _director == null:
		_finish()
		return

	_ok(_main._shield_receive != null and _main._shield_send != null, "щиты ПРИЁМ/ОТПРАВКА созданы")

	_folder_id = _first_folder_id()
	_ok(not _folder_id.is_empty(), "в реестре есть папка")
	for i in 4:
		_ok(_game.registry.create_file("атака_%d" % i, "text", _folder_id) != null,
			"создан файл атака_%d" % i)

	_main._on_start_hour()
	await process_frame
	_eq(_controller.phase, &"hour", "фаза контроллера — hour")
	_ok(_director.attack_director != null, "attack_director доступен")

	await _test_junk()
	await _test_ddos()
	await _test_phishing()
	await _test_ransomware()
	await _test_regular_packet()

	await process_frame
	print("")
	print("Проверок: %d, провалов: %d" % [_checks, _fails])
	_finish()


# --- сценарии ---------------------------------------------------------------

func _test_junk() -> void:
	var aid: String = _director.spawn_attack_now("junk")
	_ok(not aid.is_empty(), "junk-атака создана")
	if aid.is_empty():
		return
	_main._refresh_hour()
	await process_frame

	var card = _find_packet_attack("junk")
	_ok(card != null, "junk-карточка в приёме")
	if card == null:
		return
	var pid: String = str(card.id)
	var payload := {
		"kind": "packet", "id": pid, "name": "?",
		"is_attack": true, "attack_kind": "junk", "attack_id": aid,
	}
	var shield = _main._shield_receive
	_ok(shield._can_drop_data(Vector2.ZERO, payload), "щит принимает junk-карточку")
	_ok(not shield._can_drop_data(Vector2.ZERO, {"kind": "packet", "id": pid}),
		"обычный пакет щит не принимает")

	_game.sla = 150.0
	var money0 := int(_game.money)
	shield._drop_data(Vector2.ZERO, payload)
	await process_frame
	_eq(int(_game.money), money0 + 5, "junk: +5 $")
	_ok(absf(float(_game.sla) - 151.0) < 0.01, "junk: +1 SLA (%.1f)" % float(_game.sla))
	_ok(not _director.active_packets.has(pid), "junk-пакет удалён")
	_ok(not _director.attack_director.active_attacks.has(aid), "junk-атака снята")
	_ok(_find_packet_attack("junk") == null, "junk-карточка убрана из приёма")


func _test_ddos() -> void:
	var aid: String = _director.spawn_attack_now("ddos")
	_ok(not aid.is_empty(), "DDoS-атака создана")
	if aid.is_empty():
		return
	_main._refresh_hour()
	await process_frame

	_ok(_main._ddos_overlay != null, "DDoS-плашка показана в ПРИЁМЕ")
	_ok(float(_main._packet_shift) > 0.0, "карточки приёма сдвинуты под плашкой")

	_game.sla = 150.0
	var money0 := int(_game.money)
	var held = _director.hold_shield(1.6)
	_ok(held, "щит удерживается при активном DDoS")
	_eq(int(_game.money), money0 + 30, "DDoS: +30 $")
	_ok(absf(float(_game.sla) - 152.0) < 0.01, "DDoS: +2 SLA (%.1f)" % float(_game.sla))
	_ok(not _director.attack_director.active_attacks.has(aid), "DDoS-атака отражена")

	_main._refresh_hour()
	await process_frame
	_ok(_main._ddos_overlay == null, "DDoS-плашка убрана после отражения")


func _test_phishing() -> void:
	var aid: String = _director.spawn_attack_now("phishing")
	_ok(not aid.is_empty(), "phishing-атака создана")
	if aid.is_empty():
		return
	_main._refresh_hour()
	await process_frame

	var attack: Dictionary = _director.attack_director.active_attacks.get(aid, {})
	var rid := str(attack.get("request_id", ""))
	_ok(not rid.is_empty(), "у фишинга есть request_id")
	var card = _find_request(rid)
	_ok(card != null, "RequestCard фишинга в ОТПРАВКЕ")
	if card == null:
		return
	_ok(card.avatar_muted, "аватар фишинга приглушён")
	_ok(card.attack_kind == "phishing", "карточка помечена как phishing")

	_game.sla = 150.0
	var money0 := int(_game.money)
	_main._on_request_reject(rid)
	await process_frame
	_eq(int(_game.money), money0 + 20, "phishing: +20 $")
	_ok(absf(float(_game.sla) - 152.0) < 0.01, "phishing: +2 SLA (%.1f)" % float(_game.sla))
	_ok(not _director.active_requests.has(rid), "фишинг-запрос закрыт")
	_ok(not _director.attack_director.active_attacks.has(aid), "фишинг-атака снята")


func _test_ransomware() -> void:
	var aid: String = _director.spawn_attack_now("ransomware")
	_ok(not aid.is_empty(), "ransomware-атака создана")
	if aid.is_empty():
		return
	_main._refresh_hour()
	await process_frame

	var card = _find_packet_attack("ransomware")
	_ok(card != null, "ransomware-карточка в приёме")
	if card == null:
		return
	_ok(str(card.file_name).to_lower().ends_with(".exe"), "шифровальщик показан как .exe")
	var pid: String = str(card.id)

	_game.sla = 150.0
	var money0 := int(_game.money)
	var ok: bool = _main._on_quarantine_drop({
		"kind": "packet", "id": pid,
		"is_attack": true, "attack_kind": "ransomware", "attack_id": aid,
	})
	_ok(ok, "ransomware обезврежен через щит")
	await process_frame
	_eq(int(_game.money), money0 + 25, "ransomware: +25 $")
	_ok(absf(float(_game.sla) - 152.0) < 0.01, "ransomware: +2 SLA (%.1f)" % float(_game.sla))
	_ok(not _director.active_packets.has(pid), "ransomware-пакет удалён")
	_ok(not _director.attack_director.active_attacks.has(aid), "ransomware-атака снята")


func _test_regular_packet() -> void:
	var pid: String = _director.spawn_packet_now("text", "udp")
	_ok(not pid.is_empty(), "обычный UDP-пакет заспавнен")
	if pid.is_empty():
		return
	# UDP-потеря (20 %) — для теста возвращаем карточку сразу.
	if str(_director.active_packets[pid].state) == "lost":
		_director.active_packets[pid].state = "waiting"
	_main._refresh_hour()
	await process_frame

	_game.sla = 150.0
	var ok: bool = _main._on_quarantine_drop({
		"kind": "packet", "id": pid, "name": "обычный",
		"protocol": "UDP", "type": "text",
	})
	_ok(not ok, "обычный пакет не считается угрозой")
	_ok(absf(float(_game.sla) - 148.0) < 0.01, "обычный пакет: −2 SLA (%.1f)" % float(_game.sla))
	_ok(_director.active_packets.has(pid), "обычный пакет остался в приёме")


# --- хелперы ----------------------------------------------------------------

func _find_packet_attack(kind: String):
	for c in _main.packets:
		if is_instance_valid(c) and c.is_attack and str(c.attack_kind) == kind:
			return c
	return null


func _find_request(req_id: String):
	for c in _main.requests:
		if is_instance_valid(c) and str(c.id) == req_id:
			return c
	return null


func _first_folder_id() -> String:
	if _game == null or _game.registry == null:
		return ""
	for section in _game.registry.sections.values():
		if not section.folder_ids.is_empty():
			return str(section.folder_ids[0])
	return ""


func _finish() -> void:
	if _fails == 0:
		print("PASS")
	else:
		print("FAIL")
	quit(0 if _fails == 0 else 1)


func _ok(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_fails += 1
	print("FAIL: %s" % message)


func _eq(actual, expected, message: String) -> void:
	_checks += 1
	if actual == expected:
		return
	_fails += 1
	print("FAIL: %s — получено %s, ожидалось %s" % [message, actual, expected])


func _fail(message: String) -> void:
	_checks += 1
	_fails += 1
	print("FAIL: %s" % message)
