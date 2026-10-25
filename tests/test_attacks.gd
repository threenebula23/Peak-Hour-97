extends SceneTree
## Атаки: расписание, окно спавна, мини-игры и эффекты всех четырёх атак.
##
## Запуск:
##   godot --headless --path . --script tests/test_attacks.gd
##
## Тесты используют публичные методы HourDirector/AttackDirector и, где
## это необходимо для детерминизма, читают служебные поля (schedule/elapsed).
## Числа берутся из data/balance.json (через Data), а не хардкодятся.

const HD := preload("res://scripts/core/hour_director.gd")
const AD := preload("res://scripts/systems/attack_director.gd")

var _checks: int = 0
var _fails: int = 0
var _known: int = 0
var _case: String = ""
var _game = null
var _hd = null
var _seq: int = 0
var _attack_marks: Array = []


func _init() -> void:
	await process_frame
	_game = root.get_node_or_null("Game")
	if _game == null:
		_fail("autoload Game недоступен")
		_finish()
		return
	_hd = HD.new()
	_hd.attack_added.connect(_on_attack_added)
	_test_schedule_table()
	_test_attack_unlocks()
	_test_spawn_window()
	_test_no_spawn_in_minigame()
	_test_junk()
	_test_ddos()
	_test_shield_upgrade()
	_test_phishing()
	_test_ransomware()
	_finish()


# --- расписание ------------------------------------------------------------

func _test_schedule_table() -> void:
	_set_case("schedule_table")
	var expected: Array[int] = [0, 1, 1, 2, 2, 3, 3, 4, 4]
	for i in range(expected.size()):
		_eq(AD.attacks_for_hour(i + 1), expected[i], "атак в часе %d" % (i + 1))
	# Данные difficulty.attacks должны совпадать с расписанием (час 1 — 0, атаки с часа 2).
	var data = root.get_node_or_null("Data")
	if data != null:
		for h in range(1, 10):
			var row: Dictionary = data.difficulty_for(h)
			if row.has("attacks"):
				_eq(int(row["attacks"]), expected[h - 1], "balance difficulty.attacks для часа %d" % h)


func _test_attack_unlocks() -> void:
	_set_case("attack_unlocks")
	# п.16: attack_junk/ddos — с часа 2, phishing — с 3, ransomware — с 4.
	_reset(900, 1)
	var ad = _hd.attack_director
	_ok(str(ad.spawn_attack("junk")).is_empty(), "час 1: junk закрыт")
	_eq(ad._unlocked_kinds().size(), 0, "час 1: открытых атак нет")
	_reset(901, 2)
	ad = _hd.attack_director
	_ok(not str(ad.spawn_attack("junk")).is_empty(), "час 2: junk открыт")
	_ok(not str(ad.spawn_attack("ddos")).is_empty(), "час 2: ddos открыт")
	_ok(str(ad.spawn_attack("phishing")).is_empty(), "час 2: phishing закрыт")
	_reset(902, 3)
	ad = _hd.attack_director
	_ok(not str(ad.spawn_attack("phishing")).is_empty(), "час 3: phishing открыт")
	_ok(str(ad.spawn_attack("ransomware")).is_empty(), "час 3: ransomware закрыт")
	_reset(903, 4)
	ad = _hd.attack_director
	_ok(not str(ad.spawn_attack("ransomware")).is_empty(), "час 4: ransomware открыт")


func _test_spawn_window() -> void:
	_set_case("spawn_window")
	for h in range(1, 10):
		_game.start_new_run(1000 + h)
		# feature_unlocked смотрит на Game.hour — синхронизируем с часом теста.
		_game.hour = h
		_hd.start_hour(h)
		_hd.set_time_scale(1.0)
		_attack_marks.clear()
		var guard := 0
		while _hd.running and guard < 4000:
			_hd.tick(0.1)
			guard += 1
		_ok(not _hd.running, "час %d завершился" % h)
		# Час 1: расписание есть, но ни одна атака ещё не открыта.
		var expected: int = 0 if h == 1 else AD.attacks_for_hour(h)
		_eq(_attack_marks.size(), expected, "час %d: число заспавненных атак (с учётом unlock)" % h)
		for mark in _attack_marks:
			var t: float = float(mark.get("t", -1.0))
			_ok(t >= 59.5 and t <= 240.5, "час %d: окно спавна 60–240 (t=%.1f)" % [h, t])


func _test_no_spawn_in_minigame() -> void:
	_set_case("no_spawn_in_minigame")
	_reset(555, 2)
	var ad = _hd.attack_director
	_ok(ad != null, "attack director есть")
	if ad == null:
		return
	# Фиксируем момент спавна и подводим часы к нему вручную.
	ad._schedule[0] = 100.0
	ad._next_index = 0
	ad.elapsed = 99.95
	var mg := Node.new()
	_hd._minigame = mg
	_attack_marks.clear()
	_hd.tick(0.1)
	_eq(_attack_marks.size(), 0, "во время мини-игры спавна нет")
	_ok(not ad._allow_spawn, "allow_spawn=false во время мини-игры")
	_hd._minigame = null
	mg.free()
	_hd.tick(0.1)
	_eq(_attack_marks.size(), 1, "после закрытия мини-игры атака спавнится")


# --- мусор -----------------------------------------------------------------

func _test_junk() -> void:
	_set_case("junk")
	_reset(201, 2)
	var ad = _hd.attack_director
	var folder_id := _first_folder()
	var money_before: int = _game.money
	var sla_before: float = _game.sla
	var id := str(ad.spawn_attack("junk"))
	_ok(not id.is_empty(), "мусор заспавнен")
	var junk_packet_id := str(ad.active_attacks[id].get("packet_id", ""))
	_ok(not junk_packet_id.is_empty(), "мусорный пакет создан")
	_ok(_hd.active_packets.has(junk_packet_id), "мусор занимает буфер приёма")
	_eq(str(_hd.active_packets[junk_packet_id].attack_kind), "junk", "тип пакета — junk")
	_ok(not _hd.receive_packet(junk_packet_id, folder_id), "мусор нельзя занести в папку")

	_ok(ad.quarantine(id), "карантин мусора")
	_eq(_game.money, money_before + 5, "мусор в карантин: +5 $")
	_approx(_game.sla, sla_before + 1.0, 0.001, "мусор в карантин: +1 SLA")
	_ok(not ad.active_attacks.has(id), "карточка мусора убрана")
	_ok(not _hd.active_packets.has(junk_packet_id), "пакет мусора убран из приёма")

	# Игнор 15 с → авто-занос (malicious/fake) и штраф.
	_reset(202, 2)
	ad = _hd.attack_director
	money_before = _game.money
	sla_before = _game.sla
	id = str(ad.spawn_attack("junk"))
	junk_packet_id = str(ad.active_attacks[id].get("packet_id", ""))
	ad.tick(15.1)
	_ok(not ad.active_attacks.has(id), "мусор исчез после 15 с")
	_ok(not _hd.active_packets.has(junk_packet_id), "пакет мусора ушёл из приёма")
	_eq(_game.money, money_before - 10, "мусор попал в приём: −10 $")
	_approx(_game.sla, sla_before - 5.0, 0.001, "мусор попал в приём: −5 SLA")
	var fake = _find_file_by_kind("junk")
	_ok(fake != null, "авто-занос создал malicious/fake файл")
	if fake != null:
		_eq(str(fake.location), "malicious", "fake-файл помечен malicious")
		_eq(str(fake.malicious_kind), "junk", "malicious_kind = junk")
		_eq(str(fake.type), "", "у fake-файла нет типа")
		_eq(str(fake.ext), "", "у fake-файла нет расширения")
	# Приём/отправка временно отключены (filter_disabled_sec = 10).
	_ok(_hd.recv_disabled_until > _hd.hour_elapsed, "после провала мусора приём отключён")


# --- DDoS ------------------------------------------------------------------

func _test_ddos() -> void:
	_set_case("ddos")
	_reset(301, 2)
	var ad = _hd.attack_director
	var money_before: int = _game.money
	var sla_before: float = _game.sla
	var id := str(ad.spawn_attack("ddos"))
	_ok(not id.is_empty(), "DDoS заспавнен")
	var cards := int(ad.active_attacks[id].get("cards", 0))
	_ok(cards >= 8 and cards <= 12, "DDoS: 8–12 карточек (получено %d)" % cards)
	_ok(ad.hold_shield(0.8), "щит: первое удержание")
	_ok(ad.hold_shield(0.8), "щит: второе удержание (1.6 с)")
	_ok(not ad.active_attacks.has(id), "DDoS отражён за 1.5 с")
	_eq(_game.money, money_before + 30, "DDoS отражён: +30 $")
	_approx(_game.sla, sla_before + 2.0, 0.001, "DDoS отражён: +2 SLA")
	_eq(int(_hd._attacks_blocked), 1, "DDoS учтён как отражённая атака")

	# Провал: 2 пакета теряются, канал −40% на 15 с, приём off 5 с.
	_reset(302, 2)
	ad = _hd.attack_director
	money_before = _game.money
	sla_before = _game.sla
	var packets: Array[String] = []
	for i in range(3):
		packets.append(str(_hd.spawn_packet_now("text", "tcp")))
	_eq(_hd.active_packets.size(), 3, "DDoS: три обычных пакета в буфере")
	var factor_before: float = _hd.channel_factor()
	id = str(ad.spawn_attack("ddos"))
	ad.tick(10.1)
	_ok(not ad.active_attacks.has(id), "DDoS провален по таймауту")
	_eq(_hd.active_packets.size(), 1, "DDoS: потеряно ровно 2 пакета")
	_eq(int(_hd._failed), 2, "DDoS: потери учтены")
	# −15 за DDoS + 2 потерянных text-пакета × 2 SLA (п.13).
	_approx(_game.sla, sla_before - 19.0, 0.001, "DDoS: −15 SLA и −2×2 за потерю пакетов")
	_ok(_hd.recv_disabled_until - _hd.hour_elapsed >= 4.99, "DDoS: приём off 5 с")
	_ok(_hd.channel_debuff_until - _hd.hour_elapsed >= 14.99, "DDoS: дебафф канала 15 с")
	var factor_after: float = _hd.channel_factor()
	_approx(factor_after, factor_before * 1.4, 0.0001, "DDoS: канал −40% (factor ×1.4)")


# --- апгрейд «Щит» ---------------------------------------------------------

func _test_shield_upgrade() -> void:
	_set_case("shield_upgrade")
	_reset(601, 2)
	var ad = _hd.attack_director
	_game.upgrades["shield_unlocked"] = 1
	var money_before: int = _game.money
	var sla_before: float = _game.sla
	var id := str(ad.spawn_attack("ddos"))
	_ok(not id.is_empty(), "щит: спавн DDoS обработан")
	_ok(not ad.active_attacks.has(id), "щит: первый DDoS часа отражён автоматически")
	_eq(_game.money, money_before + 30, "щит: автоотражение +30 $")
	_approx(_game.sla, sla_before + 2.0, 0.001, "щит: автоотражение +2 SLA")
	_eq(int(ad.shield_used_this_hour), 1, "щит: израсходован 1 раз за час")
	_eq(int(_hd._attacks_blocked), 1, "щит: атака учтена как отражённая")
	_ok(not _hd.recv_disabled_until > _hd.hour_elapsed, "щит: урона по приёму нет")

	# Второй DDoS в том же часу автоотражением не покрывается.
	money_before = _game.money
	sla_before = _game.sla
	id = str(ad.spawn_attack("ddos"))
	_ok(ad.active_attacks.has(id), "щит: второй DDoS в часе не отражён автоматически")
	var cards := int(ad.active_attacks.get(id, {}).get("cards", 0))
	_ok(cards >= 8 and cards <= 12, "щит: второй DDoS — обычная волна карточек")
	_ok(ad.hold_shield(0.8), "щит: второй DDoS — первое удержание")
	_ok(ad.hold_shield(0.8), "щит: второй DDoS — второе удержание")
	_ok(not ad.active_attacks.has(id), "щит: второй DDoS отражён вручную")
	_eq(_game.money, money_before + 30, "щит: ручное отражение +30 $")
	_approx(_game.sla, sla_before + 2.0, 0.001, "щит: ручное отражение +2 SLA")

	# Счётчик сбрасывается в start_hour.
	_hd.start_hour(3)
	_eq(int(_hd.attack_director.shield_used_this_hour), 0, "щит: счётчик сброшен в start_hour")

	# Без апгрейда автоматического отражения нет.
	ad = _hd.attack_director
	_game.upgrades.erase("shield_unlocked")
	money_before = _game.money
	sla_before = _game.sla
	id = str(ad.spawn_attack("ddos"))
	_ok(ad.active_attacks.has(id), "без щита DDoS требует ручного отражения")
	_approx(_game.sla, sla_before, 0.001, "без щита урона ещё нет")
	_ok(ad.hold_shield(1.6), "без щита ручное удержание работает")
	_ok(not ad.active_attacks.has(id), "без щита DDoS отражён вручную")
	_eq(_game.money, money_before + 30, "без щита ручное отражение +30 $")


# --- фишинг ----------------------------------------------------------------

func _test_phishing() -> void:
	_set_case("phishing")
	# Отказ бесплатный (и даёт награду за отражение).
	_reset(401, 3)
	var ad = _hd.attack_director
	var file = _new_file("phish", "text")
	_ok(file != null, "фишинг: файл для блокировки")
	var money_before: int = _game.money
	var sla_before: float = _game.sla
	var id := str(ad.spawn_attack("phishing"))
	_ok(not id.is_empty(), "фишинг заспавнен")
	var req_id := str(ad.active_attacks[id].get("request_id", ""))
	_ok(not req_id.is_empty(), "фишинг создал фейковый запрос")
	_ok(_hd.active_requests.has(req_id), "фейковый запрос в директоре")
	_ok(_hd.reject_request(req_id), "фишинг отклонён")
	_eq(_game.money, money_before + 20, "отказ от фишинга: +20 $ (без штрафа)")
	_approx(_game.sla, sla_before + 2.0, 0.001, "отказ от фишинга: +2 SLA")
	_ok(not ad.active_attacks.has(id), "атака фишинга закрыта после отказа")
	_ok(not _hd.active_requests.has(req_id), "фейковый запрос убран")

	# Отправка фишинга: −40 $, −10 SLA, lock файла на 60 с.
	_reset(402, 3)
	ad = _hd.attack_director
	file = _new_file("phish_send", "text")
	money_before = _game.money
	sla_before = _game.sla
	id = str(ad.spawn_attack("phishing"))
	req_id = str(ad.active_attacks[id].get("request_id", ""))
	ad.resolve_phishing(req_id, "sent")
	_eq(_game.money, money_before - 40, "фишинг отправлен: −40 $")
	_approx(_game.sla, sla_before - 10.0, 0.001, "фишинг отправлен: −10 SLA")
	_ok(not ad.active_attacks.has(id), "атака фишинга закрыта после отправки")
	_ok(_hd.send_disabled_until - _hd.hour_elapsed >= 4.99, "фишинг: отправка off 5 с")
	_check_lock(file, 60.0, "фишинг: lock 60 с")

	# Таймаут: −20 $, −5 SLA, lock файла на 30 с.
	_reset(403, 3)
	ad = _hd.attack_director
	file = _new_file("phish_timeout", "text")
	money_before = _game.money
	sla_before = _game.sla
	id = str(ad.spawn_attack("phishing"))
	req_id = str(ad.active_attacks[id].get("request_id", ""))
	ad.resolve_phishing(req_id, "timeout")
	_eq(_game.money, money_before - 20, "фишинг-таймаут: −20 $")
	_approx(_game.sla, sla_before - 5.0, 0.001, "фишинг-таймаут: −5 SLA")
	_ok(not ad.active_attacks.has(id), "атака фишинга закрыта после таймаута")
	_check_lock(file, 30.0, "фишинг-таймаут: lock 30 с")


# --- шифровальщик ----------------------------------------------------------

func _test_ransomware() -> void:
	_set_case("ransomware")
	# Уничтожение .exe до заноса: +25 $, +2 SLA.
	_reset(501, 4)
	var file = null
	var ad = _hd.attack_director
	var money_before: int = _game.money
	var sla_before: float = _game.sla
	var id := str(ad.spawn_attack("ransomware"))
	_ok(not id.is_empty(), "шифровальщик заспавнен")
	var packet_id := str(ad.active_attacks[id].get("packet_id", ""))
	_ok(_hd.active_packets.has(packet_id), "пакет .exe в приёме")
	_ok(ad.quarantine(id), "пакет-шифровальщик уничтожен до заноса")
	_eq(_game.money, money_before + 25, "шифровальщик уничтожен: +25 $")
	_approx(_game.sla, sla_before + 2.0, 0.001, "шифровальщик уничтожен: +2 SLA")
	_ok(not _hd.active_packets.has(packet_id), "пакет удалён")
	_ok(not ad.active_attacks.has(id), "атака закрыта")

	# Занос в папку: файл становится malicious, через 3 с должен быть locked.
	_reset(502, 4)
	ad = _hd.attack_director
	file = null
	id = str(ad.spawn_attack("ransomware"))
	packet_id = str(ad.active_attacks[id].get("packet_id", ""))
	var folder_id := _first_folder()
	_ok(_hd.receive_packet(packet_id, folder_id), "шифровальщик принят в папку")
	for i in range(100):
		_hd.tick(0.1)
		if not _hd.active_packets.has(packet_id):
			break
	_ok(not _hd.active_packets.has(packet_id), "пакет .exe загружен в папку")
	file = _find_file_by_name("счёт")
	_ok(file != null, "файл шифровальщика создан в реестре")
	if file == null:
		return
	_ok(str(file.ext) == "exe", "расширение .exe")
	_ok(str(file.location) == "malicious", "файл помечен malicious")
	_ok(str(file.malicious_kind) == "ransomware", "malicious_kind = ransomware")
	# D08: через folder_block_delay_sec (3 с) файл — locked, папка — blocked.
	# Прокручиваем время, а не проверяем locked сразу после загрузки.
	ad.tick(3.1)
	_eq(str(file.location), "locked", "через 3.1 с файл locked")
	_ok(_hd.is_folder_locked(folder_id), "через 3.1 с папка заблокирована")
	_ok(not _game.registry.attach_file(str(file.id), "probe_req"),
		"заблокированный шифровальщик недоступен для attach")
	var probe_packet := str(_hd.spawn_packet_now("text", "tcp"))
	_ok(not _hd.receive_packet(probe_packet, folder_id), "в заблокированную папку приём отклонён")
	_hd._remove_packet(probe_packet)
	money_before = _game.money
	sla_before = _game.sla
	_ok(_hd.destroy_attack_file(str(file.id)), "шифровальщик уничтожен (locked → malicious → remove)")
	_ok(not _hd.is_folder_locked(folder_id), "после уничтожения папка разблокирована")
	_eq(_game.money, money_before + 25, "уничтожение шифровальщика: +25 $")
	_approx(_game.sla, sla_before + 2.0, 0.001, "уничтожение шифровальщика: +2 SLA")
	_ok(not ad.active_attacks.has(id), "атака закрыта после уничтожения файла")

	# Авто-unlock через 30 с: −30 $, −10 SLA, файл пропадает.
	_reset(503, 4)
	ad = _hd.attack_director
	id = str(ad.spawn_attack("ransomware"))
	packet_id = str(ad.active_attacks[id].get("packet_id", ""))
	_ok(_hd.receive_packet(packet_id, folder_id), "шифровальщик принят в папку (авто-unlock)")
	for i in range(100):
		_hd.tick(0.1)
		if not _hd.active_packets.has(packet_id):
			break
	file = _find_file_by_name("счёт")
	_ok(file != null, "файл шифровальщика создан")
	if file == null:
		return
	var file_id := str(file.id)
	money_before = _game.money
	sla_before = _game.sla
	ad.tick(30.5)
	_eq(_game.money, money_before - 30, "авто-unlock: −30 $")
	_approx(_game.sla, sla_before - 10.0, 0.001, "авто-unlock: −10 SLA")
	_ok(not _game.registry.files.has(file_id), "авто-unlock: файл потерян")
	_ok(not _hd.is_folder_locked(folder_id), "авто-unlock: папка разблокирована")
	_ok(not ad.active_attacks.has(id), "авто-unlock: атака закрыта")


# --- служебное -------------------------------------------------------------

func _reset(seed: int, hour: int) -> void:
	_game.start_new_run(seed)
	_game.hour = hour
	_hd.start_hour(hour)
	_hd.set_time_scale(1.0)
	_hd._recv_interval_current = 9999.0
	_hd.spawn_recv_accum = 0.0
	_game.money = 500
	_game.sla = 150.0


func _first_folder() -> String:
	var section = _game.registry.sections.get("C")
	if section == null or section.folder_ids.is_empty():
		return ""
	return str(section.folder_ids[0])


func _new_file(base: String, type: String):
	_seq += 1
	return _game.registry.create_file("%s_%d" % [base, _seq], type, _first_folder())


func _find_file_by_name(name: String):
	for file in _game.registry.files.values():
		if str(file.name) == name:
			return file
	return null


func _count_location(loc: String) -> int:
	var n := 0
	for file in _game.registry.files.values():
		if str(file.location) == loc:
			n += 1
	return n


func _find_file_by_kind(kind: String):
	for file in _game.registry.files.values():
		if str(file.malicious_kind) == kind:
			return file
	return null


func _check_lock(file, seconds: float, message: String) -> void:
	if file == null:
		_fail(message + ": файла нет")
		return
	_ok(str(file.location) == "locked", message + ": location locked")
	var remaining: float = float(file.lock_until) - Time.get_unix_time_from_system()
	_approx(remaining, seconds, 2.0, message + ": срок lock")


func _on_attack_added(_id: String) -> void:
	_attack_marks.append({"t": float(_hd.hour_elapsed), "hour": int(_hd.hour)})


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
	_fail("%s — получено %.6f, ожидалось %.6f" % [message, actual, expected])
	return false


func _fail(message: String) -> void:
	_fails += 1
	print("FAIL [%s] %s" % [_case, message])


func _finish() -> void:
	if _hd != null:
		_hd.free()
	print("test_attacks: проверок %d, провалов %d, known bug %d" % [_checks, _fails, _known])
	print("PASS test_attacks" if _fails == 0 else "FAIL test_attacks")
	quit(0 if _fails == 0 else 1)
