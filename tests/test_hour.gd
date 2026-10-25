extends SceneTree
## Headless-тест часа: старт, спавн, буфер, таймауты, модалки, отправка,
## выплата, атаки и полный час на ускоренном времени.
## Запуск: godot --headless --path . --script tests/test_hour.gd

const HD := preload("res://scripts/core/hour_director.gd")
const AD := preload("res://scripts/systems/attack_director.gd")

var _checks: int = 0
var _fails: int = 0
var _case: String = ""
var _game = null
var _hd = null
var _flip: Dictionary = {}
var _hour_report: Dictionary = {}
var _hour_events: int = 0
var _frozen_events: int = 0
var _name_seq: int = 0


func _init() -> void:
	await process_frame
	_game = root.get_node_or_null("Game")
	if _game == null:
		_fail("autoload Game недоступен")
		_finish()
		return
	_game.start_new_run(1)
	_hd = HD.new()
	_test_start_hour()
	_test_spawn_and_buffer()
	_test_receive()
	_test_timeouts()
	_test_failed_file_cancel()
	_test_modal_freeze()
	_test_send_payout()
	_test_minigame_fallback()
	_test_attacks()
	_test_connection_failure()
	_test_full_hour_timescale()
	_finish()


func _test_start_hour() -> void:
	_set_case("start_hour")
	_game.start_new_run(1)
	_hd.start_hour(1)
	_eq(_hd.hour, 1, "hour = 1")
	_eq(_hd.time_left, 300.0, "длительность часа 300 с")
	_ok(_hd.running, "час запущен")
	_eq(_hd.active_packets.size(), 0, "активных пакетов нет")
	_eq(_hd.active_requests.size(), 0, "активных запросов нет")
	_eq(_hd._buffer_limit(), 4, "буфер 4 на старте")
	_approx(_hd._recv_interval(), 12.0, 0.0001, "recv_interval часа 1")
	_eq(_hd._send_interval(), 22.0, "send_interval часа 1")
	_eq(_hd._max_requests(), 2, "max_requests часа 1")
	_eq(_hd.slots.max_slots(), 2, "2 слота соединений")
	_ok(_hd.attack_director != null, "AttackDirector создан")
	_eq(_hd.attack_director.active_attacks.size(), 0, "атаки сброшены")
	_approx(_hd.channel_load(), 0.0, 0.0001, "idle-канал не нагружен")
	_eq(_hd._type_pool(), ["text"], "час 1: открыт только text (sound с часа 2)")


func _test_spawn_and_buffer() -> void:
	_set_case("spawn/buffer")
	_hd.start_hour(1)
	var ids: Array[String] = []
	for i in range(4):
		var id := str(_hd.spawn_packet_now("text", "tcp"))
		ids.append(id)
		_ok(id != "", "пакет %d заспавнен" % i)
	_eq(_hd.active_packets.size(), 4, "буфер заполнен до 4")
	_eq(_hd._buffer_used(), 4, "buffer_used = 4")
	_approx(_hd.channel_load(), 0.0, 0.0001, "waiting-пакеты не грузят канал")
	_eq(_hd._active_weights().size(), 0, "active_weights пуст без loading/sending")
	var packet = _hd.active_packets[ids[0]]
	_approx(float(packet.timer_total), 30.0, 0.0001, "таймер пакета часа 1: 30 с (grace 1.5)")
	_eq(str(packet.protocol), "tcp", "протокол tcp")
	_eq(str(packet.state), "waiting", "состояние waiting")

	# Полный буфер останавливает обычный спавн по таймеру.
	_frozen_events = 0
	_hd.spawn_frozen.connect(_on_spawn_frozen)
	_hd._recv_interval_current = 0.1
	_hd.spawn_recv_accum = 0.0
	_hd.tick(0.1)
	_eq(_hd.active_packets.size(), 4, "при полном буфере таймер не спавнит")
	_ok(_frozen_events > 0, "сигнал spawn_frozen(buffer_full)")

	# Прямой спавн = переполнение: вытесняется самый старый, штраф по типу.
	var sla_before: float = _game.sla
	var oldest_id: String = ids[0]
	var new_id := str(_hd.spawn_packet_now("sound", "udp"))
	_eq(_hd.active_packets.size(), 4, "размер буфера не превышен")
	_ok(new_id != "", "новый пакет добавлен")
	_ok(not _hd.active_packets.has(oldest_id), "самый старый пакет вытеснен")
	_approx(_game.sla, sla_before - 2.0, 0.001, "переполнение: вытеснен text → −2 SLA")
	# Штраф зависит от типа вытесненного пакета (п.13).
	_hd.start_hour(2)
	var sound_id := str(_hd.spawn_packet_now("sound", "tcp"))
	for i in range(3):
		_hd.spawn_packet_now("text", "tcp")
	sla_before = _game.sla
	_hd.spawn_packet_now("text", "tcp")
	_ok(not _hd.active_packets.has(sound_id), "sound вытеснен из буфера")
	_approx(_game.sla, sla_before - 4.0, 0.001, "вытеснение sound → −4 SLA")

	_hd.start_hour(2)
	var video_id := str(_hd.spawn_packet_now("video", "tcp"))
	for i in range(3):
		_hd.spawn_packet_now("text", "tcp")
	sla_before = _game.sla
	_hd.spawn_packet_now("text", "tcp")
	_ok(not _hd.active_packets.has(video_id), "video вытеснен из буфера")
	_approx(_game.sla, sla_before - 16.0, 0.001, "вытеснение video → −16 SLA")
	# Прибираем пакеты, чтобы не мешали следующим кейсам.
	for id in _hd.active_packets.keys():
		_hd._remove_packet(str(id))


func _test_receive() -> void:
	_set_case("receive")
	_hd.start_hour(1)
	_hd._recv_interval_current = 9999.0
	var folder_id := _folder_id()
	_ok(not folder_id.is_empty(), "есть папка для приёма")
	var files_before: int = _game.registry.files.size()
	var money_before: int = _game.money
	var sla_before: float = _game.sla
	var packet_id := str(_hd.spawn_packet_now("text", "tcp"))
	var expected_name := str(_hd.active_packets[packet_id].file_name)
	_ok(_hd.receive_packet(packet_id, folder_id), "пакет принят в загрузку")
	var packet = _hd.active_packets.get(packet_id)
	_ok(packet != null and str(packet.state) == "loading", "state loading")
	_approx(_hd.channel_load(), 6.0, 0.0001, "loading text грузит канал на weight 6")
	for i in range(60):
		_hd.tick(0.1)
		if not _hd.active_packets.has(packet_id):
			break
	_ok(not _hd.active_packets.has(packet_id), "пакет ушёл из буфера")
	_eq(_game.registry.files.size(), files_before + 1, "файл создан в реестре")
	_ok(_game.registry.find_by_name(expected_name) != null, "имя файла сохранено без лишнего суффикса")
	# Прерванная загрузка возвращает резерв папки.
	var packet2 := str(_hd.spawn_packet_now("text", "tcp"))
	_ok(_hd.receive_packet(packet2, folder_id), "вторая загрузка начата")
	var folder = _game.registry.folders.get(folder_id)
	_ok(folder != null and int(folder.reserved) >= 1, "папка зарезервирована под загрузку")
	_hd._remove_packet(packet2)
	_ok(folder != null and int(folder.reserved) == 0, "прерванная загрузка сняла резерв")
	_eq(_game.money, money_before + 2, "recv_fee text = +2 $")
	_approx(_game.sla, sla_before + 0.5, 0.001, "+0.5 SLA за приём")


func _test_timeouts() -> void:
	_set_case("timeouts")
	_hd.start_hour(1)
	_hd._recv_interval_current = 9999.0
	var sla_before: float = _game.sla
	var packet_id := str(_hd.spawn_packet_now("text", "tcp"))
	_hd.active_packets[packet_id].time_left = 0.05
	_hd.tick(0.1)
	_ok(not _hd.active_packets.has(packet_id), "пакет удалён по таймауту")
	_approx(_game.sla, sla_before - 2.0, 0.001, "таймаут text-пакета: −2 SLA")
	# Фото/видео штрафуются строже (п.13).
	_game.sla = 200.0
	var photo_id := str(_hd.spawn_packet_now("photo", "tcp"))
	_hd.active_packets[photo_id].time_left = 0.05
	_hd.tick(0.1)
	_approx(_game.sla, 192.0, 0.001, "таймаут photo: −8 SLA")
	_game.sla = 200.0
	var video_id := str(_hd.spawn_packet_now("video", "tcp"))
	_hd.active_packets[video_id].time_left = 0.05
	_hd.tick(0.1)
	_approx(_game.sla, 184.0, 0.001, "таймаут video: −16 SLA")

	_hd.start_hour(1)
	_game.sla = 200.0
	sla_before = _game.sla
	var req_id := str(_hd._make_request([], "udp", false, "", ""))
	var req = _hd.active_requests[req_id]
	req.time_left = 0.05
	var failed_before: int = _hd._failed
	_hd.tick(0.1)
	_ok(not _hd.active_requests.has(req_id), "запрос удалён по таймауту")
	_approx(_game.sla, sla_before - 12.0, 0.001, "таймаут запроса: −(10+2×hour)")
	_eq(_hd._failed, failed_before + 1, "провал учтён")


func _test_failed_file_cancel() -> void:
	_set_case("failed_file")
	_hd.start_hour(1)
	_hd._recv_interval_current = 9999.0
	_game.money = 1000
	_game.sla = 100.0
	var file = _new_file("Сбойный", "text", _folder_id())
	_ok(file != null, "файл для сбоя создан")
	if file == null:
		return
	var req_id := str(_hd._make_request([file], "udp", false, "", ""))
	_ok(_hd.attach_file(req_id, str(file.id)), "файл прикреплён")
	_game.registry.mark_failed(str(file.id))
	var money_before: int = _game.money
	var sla_before: float = _game.sla
	_hd.tick(0.1)
	_ok(not _hd.active_requests.has(req_id), "запрос отменён при failed-файле (D06)")
	_eq(_game.money, money_before - 15, "failed-файл: −15 $")
	_approx(_game.sla, sla_before - 10.0, 0.001, "failed-файл: −10 SLA")


func _test_modal_freeze() -> void:
	_set_case("modal")
	_hd.start_hour(1)
	_hd._recv_interval_current = 0.1
	_hd.spawn_recv_accum = 0.0
	var packet_id := str(_hd.spawn_packet_now("text", "tcp"))
	var req_id := str(_hd._make_request([], "udp", false, "", ""))
	_hd.modal_open = true
	var packet = _hd.active_packets[packet_id]
	var req = _hd.active_requests[req_id]
	var packet_time: float = packet.time_left
	var req_time: float = req.time_left
	var packets_before: int = _hd.active_packets.size()
	for i in range(10):
		_hd.tick(0.1)
	_approx(packet.time_left, packet_time, 0.0001, "таймер пакета заморожен модалкой")
	_approx(req.time_left, req_time - 1.0, 0.001, "таймер запроса идёт при модалке")
	_eq(_hd.active_packets.size(), packets_before, "спавн приёма остановлен")
	_hd.modal_open = false
	_hd._remove_packet(packet_id)
	_hd._cleanup_request(req_id, false)


func _test_send_payout() -> void:
	_set_case("send/payout")
	_hd.start_hour(1)
	_hd._recv_interval_current = 9999.0
	_game.sla = 150.0
	var folder_id := _folder_id()
	var file = _new_file("Отправка", "text", folder_id)
	_ok(file != null, "файл для отправки создан")
	if file == null:
		return
	var req_id := str(_hd._make_request([file], "tcp", false, "", ""))
	var req = _hd.active_requests[req_id]
	_ok(_hd.attach_file(req_id, str(file.id)), "файл прикреплён")
	req.connected = true
	_ok(req.is_ready(), "запрос готов (TCP подключён)")
	var money_before: int = _game.money
	var sla_before: float = _game.sla
	_ok(_hd.start_send(req_id), "мини-игра открыта")
	_ok(_hd.modal_open, "модалка отмечена")
	_ok(req.minigame_active, "флаг minigame_active")
	var mg = _hd._minigame
	_ok(mg != null, "MiniGame создан")
	if mg != null:
		mg._send()
	_ok(req.sending, "отправка началась после мини-игры")
	_approx(_hd.channel_load(), 6.0, 0.0001, "sending text грузит канал на weight 6")
	_ok(not _hd.modal_open, "модалка закрыта")
	_ok(float(req.send_duration) > 0.0, "send_duration > 0")
	for i in range(200):
		_hd.tick(0.1)
		if not _hd.active_requests.has(req_id):
			break
	_ok(not _hd.active_requests.has(req_id), "запрос завершён")
	_ok(_game.money > money_before, "выплата начислена")
	_approx(_game.sla, sla_before + 1.0, 0.001, "+1 SLA за отправку")
	_eq(_hd._completed, 1, "completed = 1")
	_ok(float(file.cooldown_until) > 0.0, "cooldown файла после отправки (D02)")
	_ok(str(file.attached_request).is_empty(), "файл откреплён")


func _test_attacks() -> void:
	_set_case("attacks")
	_eq(AD.attacks_for_hour(1), 1, "час 1: 1 атака (D16)")
	_eq(AD.attacks_for_hour(2), 1, "час 2: 1 атака")
	_eq(AD.attacks_for_hour(4), 2, "час 4: 2 атаки")
	_eq(AD.attacks_for_hour(6), 3, "час 6: 3 атаки")
	_eq(AD.attacks_for_hour(8), 4, "час 8: 4 атаки")
	_eq(AD.attacks_for_hour(9), 4, "час 9: 4 атаки")

	# junk/ddos открыты с часа 2, phishing — с 3, ransomware — с 4 (п.16).
	_game.hour = 2
	_hd.start_hour(2)
	var ad = _hd.attack_director
	ad.reset(2)
	_game.sla = 150.0
	var money_before: int = _game.money
	var sla_before: float = _game.sla
	var junk_id := str(ad.spawn_attack("junk"))
	_ok(junk_id != "", "мусор заспавнен")
	_ok(ad.active_attacks.has(junk_id), "мусор в активных")
	_ok(ad.destroy(junk_id), "мусор уничтожен")
	_eq(_game.money, money_before + 5, "мусор: +5 $")
	_approx(_game.sla, sla_before + 1.0, 0.001, "мусор: +1 SLA")

	ad.reset(2)
	var ddos_id := str(ad.spawn_attack("ddos"))
	_ok(ddos_id != "", "DDoS заспавнен")
	var cards := int(ad.active_attacks[ddos_id].get("cards", 0))
	_ok(cards >= 8 and cards <= 12, "DDoS: 8–12 карточек")
	money_before = _game.money
	_ok(ad.hold_shield(0.8), "первое удержание щита")
	_ok(ad.hold_shield(0.8), "второе удержание щита")
	_ok(not ad.active_attacks.has(ddos_id), "1.5 с щита отражают DDoS")
	_eq(_game.money, money_before + 30, "DDoS: +30 $")

	_game.hour = 3
	_hd.start_hour(3)
	var file = _new_file("Фишинг", "text", _folder_id())
	_ok(file != null, "файл для фишинга")
	ad.reset(3)
	var phish_id := str(ad.spawn_attack("phishing"))
	_ok(phish_id != "", "фишинг заспавнен")
	var phish_req := str(ad.active_attacks[phish_id].get("request_id", ""))
	_ok(not phish_req.is_empty(), "фишинг создал фейковый запрос")
	_ok(_hd.active_requests.has(phish_req), "фейковый запрос в часа")
	money_before = _game.money
	_ok(_hd.reject_request(phish_req), "фишинг отклонён")
	_ok(not _hd.active_requests.has(phish_req), "фейковый запрос убран")
	_ok(not ad.active_attacks.has(phish_id), "атака фишинга закрыта")
	_ok(_game.money >= money_before + 20, "фишинг: награда без штрафа")

	_game.hour = 4
	_hd.start_hour(4)
	ad.reset(4)
	var rw_id := str(ad.spawn_attack("ransomware"))
	_ok(rw_id != "", "шифровальщик заспавнен")
	var packet_id := str(ad.active_attacks[rw_id].get("packet_id", ""))
	_ok(_hd.active_packets.has(packet_id), "пакет .exe в приёме")
	money_before = _game.money
	_ok(_hd.destroy_attack_packet(packet_id), "пакет-шифровальщик уничтожен")
	_eq(_game.money, money_before + 25, "шифровальщик: +25 $")
	_ok(not _hd.active_packets.has(packet_id), "пакет удалён")


func _test_minigame_fallback() -> void:
	_set_case("minigame_fallback")
	_game.hour = 1
	_hd.start_hour(1)
	_hd._recv_interval_current = 9999.0
	_game.sla = 150.0
	var file = _new_file("Фото-фолбэк", "photo", _folder_id())
	_ok(file != null, "файл photo создан")
	if file == null:
		return
	var req_id := str(_hd._make_request([file], "tcp", false, "", ""))
	_ok(_hd.attach_file(req_id, str(file.id)), "photo прикреплён")
	_hd.active_requests[req_id].connected = true
	_ok(_hd.start_send(req_id), "отправка открыла мини-игру")
	var mg = _hd._minigame
	_ok(mg != null, "мини-игра создана")
	if mg != null:
		_eq(str(mg.game_type), "text", "час 1: photo-мини-игра не открыта → fallback text")
	_hd._cleanup_request(req_id, true)
	_ok(not _hd.modal_open, "модалка мини-игры закрыта")


func _test_connection_failure() -> void:
	_set_case("connection_fail")
	_hd.start_hour(1)
	_hd._recv_interval_current = 9999.0
	var packet_id := str(_hd.spawn_packet_now("text", "tcp"))
	_ok(_hd.connect_packet(packet_id), "соединение открыто")
	_eq(_hd.slots.used_count(), 1, "слот занят на время соединения")
	var node = _hd._connection_games.get(packet_id)
	_hd._on_connection_finished(false, packet_id)
	_eq(_hd.slots.used_count(), 0, "провал соединения освобождает слот")
	_ok(not _hd.modal_open, "провал закрывает модалку")
	if _hd.active_packets.has(packet_id):
		_eq(str(_hd.active_packets[packet_id].state), "waiting", "пакет остаётся waiting")
	if node != null and is_instance_valid(node):
		node.free()
	# Повторное «Соединиться» создаёт новую панель.
	_ok(_hd.connect_packet(packet_id), "после провала можно соединиться снова")
	_hd._on_connection_finished(true, packet_id)
	_eq(_hd.slots.used_count(), 1, "успех снова занимает слот")
	_hd._remove_packet(packet_id)


func _test_full_hour_timescale() -> void:
	_set_case("full_hour")
	_game.hour = 2
	_hd.start_hour(2)
	_hour_events = 0
	_hour_report = {}
	_hd.hour_finished.connect(_on_hour_finished)
	_hd.set_time_scale(30.0)
	for i in range(120):
		_hd.tick(0.1)
		if not _hd.running:
			break
	_ok(not _hd.running, "час завершился")
	_approx(_hd.time_left, 0.0, 0.001, "time_left = 0")
	_eq(_hour_events, 1, "hour_finished эмитится один раз")
	if _hour_events > 0:
		_eq(int(_hour_report.get("hour", 0)), 2, "в отчёте час 2")
		_ok(_hour_report.has("earned"), "в отчёте есть earned")
		_ok(_hour_report.has("completed"), "в отчёте есть completed")
		_ok(_hour_report.has("failed"), "в отчёте есть failed")
		_ok(_hour_report.has("attacks"), "в отчёте есть attacks")
		_ok(_hour_report.has("sla_delta"), "в отчёте есть sla_delta")


# --- служебное -------------------------------------------------------------

func _folder_id() -> String:
	var section = _game.registry.sections.get("C")
	if section == null or section.folder_ids.is_empty():
		return ""
	return str(section.folder_ids[0])


func _new_file(base: String, type: String, folder_id: String):
	_name_seq += 1
	var file = _game.registry.create_file("%s %d" % [base, _name_seq], type, folder_id)
	return file


func _on_spawn_frozen(_reason: String) -> void:
	_frozen_events += 1


func _on_hour_finished(report: Dictionary) -> void:
	_hour_events += 1
	_hour_report = report


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
	if absf(actual - expected) <= eps:
		return true
	_fail("%s — получено %.6f, ожидалось %.6f" % [message, actual, expected])
	return false


func _fail(message: String) -> void:
	_fails += 1
	print("FAIL [%s] %s" % [_case, message])


func _finish() -> void:
	print("test_hour: проверок %d, провалов %d" % [_checks, _fails])
	print("PASS test_hour" if _fails == 0 else "FAIL test_hour")
	quit(0 if _fails == 0 else 1)
