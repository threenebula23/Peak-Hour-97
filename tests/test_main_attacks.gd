extends SceneTree
## Headless-тест атак v2: только модальная мини-игра, без карточек/оверлеев.
##
## Проверяет:
##   • controller.show_attack_minigame открывает модалку в modal_root;
##   • час встаёт на паузу на время мини-игры и продолжается после;
##   • успех/провал применяют деньги/SLA;
##   • в ПРИЁМЕ/ОТПРАВКЕ нет сущностей-атак, щит-удержание удалено.
##
## Запуск:
##   godot --headless --path . --script tests/test_main_attacks.gd

const MAIN_SCENE := "res://scenes/Main.tscn"

var _checks := 0
var _fails := 0
var _finished := false
var _main: Node = null
var _controller = null
var _director = null
var _game = null
var _show_attack_signals := 0


func _init() -> void:
	var watchdog := create_timer(90.0)
	watchdog.timeout.connect(_on_timeout)
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
	_controller.show_attack_minigame.connect(_on_show_attack_minigame)

	_main._on_start_hour()
	await process_frame
	_eq(_controller.phase, &"hour", "фаза контроллера — hour")
	_ok(_director.attack_director != null, "attack_director доступен")

	# Старый UI атак удалён.
	_ok(_main.get("_shield_receive") == null, "щита ПРИЁМ больше нет")
	_ok(_main.get("_shield_send") == null, "щита ОТПРАВКА больше нет")
	_ok(_main.get("_ddos_overlay") == null, "оверлея DDoS больше нет")
	_ok(not _main.has_method("_on_quarantine_drop"), "карантин-drop удалён")
	_ok(not _main.has_method("_on_shield_press"), "удержание щита удалено")
	_ok(not _main.has_method("_refresh_attacks"), "карточки атак удалены")
	_ok(not _director.hold_shield(1.5), "hold_shield больше не работает")

	var packets_before: int = _main.packets.size()
	var requests_before: int = _main.requests.size()

	await _run_attack("junk", 1.0, true)
	await _run_attack("ddos", 1.0, true)
	await _run_attack("phishing", 0.0, false)
	await _run_attack("ransomware", 1.0, true)

	_eq(_show_attack_signals, 4, "controller.show_attack_minigame эмитился 4 раза")
	_ok(_main._modal_game == null, "после всех атак модалки нет")
	_ok(not bool(_controller.modal_open), "controller.modal_open сброшен")
	_ok(not bool(_director.is_attack_paused()), "час не остался на паузе")
	_eq(_main.packets.size(), packets_before, "атаки не добавляют карточки в ПРИЁМ")
	_eq(_main.requests.size(), requests_before, "атаки не добавляют карточки в ОТПРАВКУ")
	for card in _main.packets:
		_ok(card.get("is_attack") == null, "в PacketCard нет ветки атаки")
	for card in _main.requests:
		_ok(card.get("is_attack") == null, "в RequestCard нет ветки атаки")

	print("")
	print("Проверок: %d, провалов: %d" % [_checks, _fails])
	_finish()


## Одна атака: модалка + пауза, затем результат.
func _run_attack(kind: String, quality: float, expect_success: bool) -> void:
	var before_money := int(_game.money)
	_game.sla = 30.0 if expect_success else 50.0
	var before_sla := float(_game.sla)
	var packets_before: int = _main.packets.size()
	var requests_before: int = _main.requests.size()

	var aid: String = _director.spawn_attack_now(kind)
	_ok(not aid.is_empty(), "%s: атака создана" % kind)
	if aid.is_empty():
		return
	var ad = _director.attack_director
	var attack: Dictionary = ad.active_attacks.get(aid, {})
	_eq(str(attack.get("state", "")), "minigame", "%s: атака в состоянии minigame" % kind)
	_ok(ad.is_minigame_active(), "%s: мини-игра активна" % kind)

	# Модалка показана через controller.show_attack_minigame.
	_ok(_main._modal_game != null, "%s: модалка атаки показана" % kind)
	if _main._modal_game != null:
		_ok(_main._modal_game.get_parent() == _main.modal_root,
			"%s: модалка лежит в modal_root" % kind)
		_ok(_main._modal_game.has_signal("finished"),
			"%s: у модалки есть сигнал finished" % kind)
	_ok(bool(_controller.modal_open), "%s: controller.modal_open = true" % kind)

	# Час на паузе: время не идёт.
	_ok(bool(_director.paused), "%s: час помечен paused" % kind)
	_ok(bool(_director.is_attack_paused()), "%s: is_attack_paused = true" % kind)
	var time_before := float(_director.time_left)
	_controller.tick(1.0)
	_approx(float(_director.time_left), time_before, 0.001,
		"%s: время часа стоит на паузе" % kind)

	# Атак нет в списках пакетов/запросов.
	_eq(_main.packets.size(), packets_before, "%s: ПРИЁМ не изменился" % kind)
	_eq(_main.requests.size(), requests_before, "%s: ОТПРАВКА не изменилась" % kind)

	# Завершаем мини-игру напрямую (как сделал бы игрок).
	ad._on_minigame_finished(quality)
	await process_frame
	await process_frame
	_ok(not ad.active_attacks.has(aid), "%s: атака снята" % kind)
	_ok(not ad.is_minigame_active(), "%s: мини-игра закрыта" % kind)
	_eq(_main._modal_game, null, "%s: модалка снята" % kind)
	_ok(not bool(_controller.modal_open), "%s: modal_open сброшен" % kind)
	_ok(not bool(_director.is_attack_paused()), "%s: пауза снята" % kind)
	_ok(float(_director.time_left) > 0.0, "%s: час продолжает идти" % kind)

	if expect_success:
		_ok(int(_game.money) > before_money,
			"%s: успех повышает деньги (%d → %d)" % [kind, before_money, int(_game.money)])
		_ok(float(_game.sla) > before_sla,
			"%s: успех повышает SLA (%.1f → %.1f)" % [kind, before_sla, float(_game.sla)])
	else:
		_ok(int(_game.money) < before_money,
			"%s: провал снижает деньги (%d → %d)" % [kind, before_money, int(_game.money)])
		_ok(float(_game.sla) < before_sla,
			"%s: провал снижает SLA (%.1f → %.1f)" % [kind, before_sla, float(_game.sla)])


func _on_show_attack_minigame(_game_node, _kind: String) -> void:
	_show_attack_signals += 1


func _on_timeout() -> void:
	if _finished:
		return
	print("FAIL: тест превысил 90 секунд")
	_finished = true
	quit(1)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if _main != null and is_instance_valid(_main):
		_main.queue_free()
	_stop_audio()
	await process_frame
	await process_frame
	await process_frame
	var audio = root.get_node_or_null("Audio")
	if audio != null:
		audio.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	if _fails == 0:
		print("PASS")
	else:
		print("FAIL")
	quit(0 if _fails == 0 else 1)


func _stop_audio() -> void:
	var audio = root.get_node_or_null("Audio")
	if audio == null:
		return
	if audio.has_method("stop_music"):
		audio.call("stop_music")
	for child in audio.get_children():
		if child is AudioStreamPlayer:
			var player := child as AudioStreamPlayer
			player.stop()
			player.stream = null
	if audio.get("_sfx_streams") is Dictionary:
		(audio.get("_sfx_streams") as Dictionary).clear()
	if audio.get("_music_streams") is Dictionary:
		(audio.get("_music_streams") as Dictionary).clear()


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


func _approx(actual: float, expected: float, eps: float, message: String) -> void:
	_checks += 1
	if absf(float(actual) - float(expected)) <= eps:
		return
	_fails += 1
	print("FAIL: %s — получено %.6f, ожидалось %.6f" % [message, actual, expected])


func _fail(message: String) -> void:
	_checks += 1
	_fails += 1
	print("FAIL: %s" % message)
