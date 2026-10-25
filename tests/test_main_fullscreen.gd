extends SceneTree
## Headless-регресс: переключение «Полного экрана» не должно сбрасывать
## галочки настроек и attached-данные файла/запроса.
##
## Баг: _open_settings() брал fullscreen только из
## DisplayServer.window_get_mode(). На платформах, где режим окна приходит
## асинхронно или не сообщается (web-iframe без allowfullscreen, часть WM,
## headless), после включения fullscreen повторное открытие настроек
## показывало снятую галочку, хотя настройка применена и сохранена.
##
## Проверяет:
##   • после _apply_settings(fullscreen=true) чекбокс и get_state() — true;
##   • attached файла/запроса и зелёные галочки не меняются;
##   • состояние переживает закрытие и повторное открытие настроек.
##
## Запуск:
##   godot --headless --path . --script tests/test_main_fullscreen.gd

const MAIN_SCENE := "res://scenes/Main.tscn"

var _checks := 0
var _fails := 0
var _main: Node = null
var _game: Node = null
var _controller = null


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

	_game = root.get_node_or_null("Game")
	_ok(_game != null, "autoload Game доступен")
	_ok(_main.controller != null, "controller создан")
	if _game == null or _main.controller == null:
		_finish()
		return
	_controller = _main.controller
	_ok(DisplayServer.get_name() == "headless", "тест идёт headless (DisplayServer — no-op)")

	_main._start_new_run()
	await process_frame

	# Файлы, из которых спавнятся запросы.
	var folder_id := ""
	for section in _game.registry.sections.values():
		if not section.folder_ids.is_empty():
			folder_id = str(section.folder_ids[0])
			break
	_ok(folder_id != "", "в реестре есть папка для файлов")
	for i in 4:
		_ok(_game.registry.create_file("тест_%d" % i, "text", folder_id) != null,
			"файл тест_%d создан" % i)
	_main._refresh_prep()
	await process_frame

	var started: bool = _controller.start_hour()
	_ok(started, "controller.start_hour() запускает час")
	await process_frame
	_eq(_controller.phase, &"hour", "фаза контроллера — hour")

	# Запрос + прикреплённый файл: фиксируем attached-данные и галочки.
	var director = _controller.hour_director
	var rid: String = director.spawn_request_now()
	var req = director.active_requests.get(rid)
	_ok(req != null, "запрос создан")
	if req == null:
		_finish()
		return
	var fid := str(req.required[0])
	_ok(director.attach_file(rid, fid), "файл прикреплён к запросу")
	_main._refresh_hour()
	await process_frame
	await process_frame  # даём отработать deferred registry-refresh сетки

	var attached_before: Array = req.attached.duplicate()
	_ok(attached_before.has(fid), "req.attached содержит файл")
	_ok(_slot_attached(rid, fid), "слот запроса показывает attached=true")
	_eq(_file_card_state(fid), "attached", "FileCard показывает attached")
	_eq(str(_game.registry.files[fid].attached_request), rid,
		"file.attached_request указывает на запрос")

	# --- Включаем полный экран (в headless DisplayServer — no-op) ----------
	_main._apply_settings({
		"sfx": 40, "music": 45, "calm_bg": true, "fullscreen": true,
	}, false)
	_ok(bool(_settings_cache().get("fullscreen", false)),
		"_apply_settings(fullscreen=true) сохранил настройку")

	_main._pause_game()
	_main._open_settings()
	await process_frame
	var sm = _main.settings_modal
	_ok(sm != null and sm.visible, "настройки открыты на паузе")
	_ok(sm._full.button_pressed, "чекбокс «Полный экран» отмечен (button_pressed)")
	_ok(sm._full.checked, "чекбокс «Полный экран» отмечен (checked)")
	_ok(bool(sm.get_state().get("fullscreen", false)),
		"get_state().fullscreen — true")
	_ok(sm._calm.checked, "чекбокс «Спокойный фон» не сброшен")
	_eq(int(sm.get_state().get("sfx", -1)), 40, "громкость SFX не сброшена")

	# attached-данные и галочки после переключения не изменились.
	_eq(req.attached, attached_before, "req.attached не изменился после fullscreen")
	_ok(_slot_attached(rid, fid), "слот запроса по-прежнему attached")
	_eq(_file_card_state(fid), "attached", "FileCard по-прежнему attached")
	_eq(str(_game.registry.files[fid].attached_request), rid,
		"file.attached_request не изменился")

	# Повторное открытие настроек не снимает галочку.
	sm.close()
	_main._open_settings()
	await process_frame
	_ok(sm._full.checked, "после повторного открытия галочка «Полный экран» на месте")
	_ok(bool(sm.get_state().get("fullscreen", false)),
		"после повторного открытия state.fullscreen — true")

	# Возврат к игре: attached не теряется при resume/refresh.
	_main._resume_game()
	_main._refresh_hour()
	await process_frame
	_eq(_controller.phase, &"hour", "фаза осталась hour")
	_ok(_request_card_attached(rid, fid), "RequestCard после resume показывает attached")

	# Возвращаем оконный режим, чтобы не тащить состояние в другие тесты.
	_main._apply_settings({
		"sfx": 40, "music": 45, "calm_bg": true, "fullscreen": false,
	}, false)

	print("")
	print("Проверок: %d, провалов: %d" % [_checks, _fails])
	_finish()


func _settings_cache() -> Dictionary:
	var cache = _main._settings_cache
	return cache if cache is Dictionary else {}


func _slot_attached(rid: String, fid: String) -> bool:
	var req = _controller.hour_director.active_requests.get(rid)
	if req == null:
		return false
	var slots: Array = _main._request_slots({"required": req.required,
		"attached": req.attached})
	var index: int = (req.required as Array).find(fid)
	if index < 0 or index >= slots.size() or slots[index] == null:
		return false
	return bool((slots[index] as Dictionary).get("attached", false))


func _file_card_state(fid: String) -> String:
	if _main.grid == null:
		return ""
	for card in _main.grid.get_cards():
		if str(card.id) == fid:
			return str(card.state)
	return ""


func _request_card_attached(rid: String, fid: String) -> bool:
	var req = _controller.hour_director.active_requests.get(rid)
	if req == null:
		return false
	var index: int = (req.required as Array).find(fid)
	for card in _main.requests:
		if card == null or not is_instance_valid(card) or str(card.id) != rid:
			continue
		if index < 0 or index >= card.slots.size() or card.slots[index] == null:
			return false
		return bool((card.slots[index] as Dictionary).get("attached", false))
	return false


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
