extends SceneTree
## Узкая регрессия по двум багам debugger-сессии (main.gd / file_grid.gd):
##   A) drop пакета на строку НЕ открытой папки → сетка переключается на цель
##      (`_focus_folder`), файл после `_finish_loading` виден в `grid._files`.
##   B) reject запроса → карточка не остаётся ребёнком `send_window.content`
##      даже спустя 0.3 c, `requests` пуст, нет обращений к freed instance.
##
## Запуск:
##   godot --headless --path . --script tests/test_debug_focus_drop.gd

const MAIN_SCENE := "res://scenes/Main.tscn"

var _checks := 0
var _fails := 0
var _finished := false
var _main: Node = null
var _game = null
var _director = null


func _init() -> void:
	create_timer(90.0).timeout.connect(_on_timeout)
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
	if _game == null or _main.controller == null:
		_finish()
		return
	_director = _main.controller.hour_director
	_ok(_director != null, "hour_director доступен")
	if _director == null:
		_finish()
		return
	_main._on_start_hour()
	await process_frame
	_eq(_main.controller.phase, &"hour", "фаза hour")

	await _test_focus_folder_direct()
	await _test_cross_folder_drop_visible()
	await _test_reject_removes_card()

	print("")
	print("Проверок: %d, провалов: %d" % [_checks, _fails])
	_finish()


# --- A1: прямой _focus_folder ------------------------------------------------

func _test_focus_folder_direct() -> void:
	_set_case("A1 _focus_folder")
	var a := _folder_id_at(0)
	var b := _folder_id_at(1)
	if a.is_empty() or b.is_empty():
		_fail("нужны две папки")
		return
	_main._on_folder_selected(a)
	await process_frame
	_eq(str(_main.grid.folder_id), a, "открыта папка A")

	# В B заранее лежит файл: после _focus_folder он обязан быть в _files.
	var seed_file = _game.registry.create_file("фокус_97", "text", b)
	_ok(seed_file != null, "в папке B создан файл")
	if seed_file == null:
		return
	_main._focus_folder(b)
	await process_frame
	_eq(str(_main.grid.folder_id), b, "_focus_folder переключил сетку на B")
	_eq(str(_main.tree._selected), b, "_focus_folder выделил строку B")
	ok_in_grid(seed_file, "файл B виден в grid._files после _focus_folder")
	_eq(_main.grid.file_count(), _game.registry.get_folder_files(b).size(),
		"file_count сетки = файлам папки B")


# --- A2: drop пакета в неоткрытую папку -------------------------------------

func _test_cross_folder_drop_visible() -> void:
	_set_case("A2 cross-folder drop")
	var a := _folder_id_at(0)
	var b := _folder_id_at(1)
	if a.is_empty() or b.is_empty():
		_fail("нужны две папки")
		return
	_main._on_folder_selected(a)
	await process_frame
	_eq(str(_main.grid.folder_id), a, "перед drop открыта папка A")

	var pid: String = _director.spawn_packet_now("text")
	_ok(not pid.is_empty(), "пакет заспавнен")
	if pid.is_empty():
		return
	var packet = _director.active_packets.get(pid)
	var file_name := str(packet.file_name)
	_eq(str(packet.loading_folder_id), "", "пакет ещё не грузится")

	# drop на строку B (папка не открыта)
	_main._on_drop_to_folder(b, {"kind": "packet", "id": pid})
	await process_frame
	_eq(str(_director.active_packets[pid].state), "loading",
		"drop в B начал загрузку (слот занят)")
	_eq(str(_main.grid.folder_id), b, "сетка сразу переключена на B")

	# Догружаем до _finish_loading.
	for i in 400:
		if not _director.active_packets.has(pid):
			break
		_director.tick(0.1)
		await process_frame
	_eq(_director.active_packets.has(pid), false, "пакет завершил загрузку")
	await process_frame

	var file = _game.registry.find_by_name(file_name)
	_ok(file != null, "файл в registry после _finish_loading")
	if file == null:
		return
	_eq(str(file.folder_id), b, "файл лежит в целевой папке B")
	_ok(_game.registry.get_folder(b).file_ids.has(str(file.id)),
		"файл в folder.file_ids папки B")
	ok_in_grid(file, "файл виден в grid._files после загрузки")
	_eq(_main.grid.file_count(), _game.registry.get_folder_files(b).size(),
		"file_count сетки = файлам B после загрузки")
	_eq(str(_main.tree._selected), b, "строка дерева — B")


# --- B: reject --------------------------------------------------------------

func _test_reject_removes_card() -> void:
	_set_case("B reject")
	# 1) через main._on_request_reject (с путём «жары»)
	var rid := str(_director.spawn_request_now(1))
	_ok(not rid.is_empty(), "запрос для reject создан")
	if rid.is_empty():
		return
	_main._refresh_hour()
	await process_frame
	_ok(_find_card(rid) != null, "карточка запроса в списке до reject")
	_main._last_sla = float(_game.sla)
	_main._on_request_reject(rid)
	await _wait(0.3)
	_check_rejected(rid, "_on_request_reject")
	_check_no_invalid_cards("после _on_request_reject")

	# 2) через director.reject_request (путь без «жары»)
	var rid2 := str(_director.spawn_request_now(1))
	_ok(not rid2.is_empty(), "второй запрос создан")
	if rid2.is_empty():
		return
	_main._refresh_hour()
	await process_frame
	_ok(_find_card(rid2) != null, "вторая карточка в списке")
	_ok(_director.reject_request(rid2), "director.reject_request вернул true")
	_main._refresh_hour()
	await _wait(0.3)
	_check_rejected(rid2, "director.reject_request")
	_check_no_invalid_cards("после director.reject_request")

	# 3) ещё один rebuild спустя 0.3 c не должен падать на freed instance.
	_main._refresh_hour()
	await process_frame
	_eq(_main.requests.size(), _request_card_children(),
		"после повторного rebuild карточек = элементов requests")


func _check_rejected(rid: String, source: String) -> void:
	_ok(not _director.active_requests.has(rid), "%s: запрос ушёл из director" % source)
	_ok(_find_card(rid) == null,
		"%s: карточки нет в send_window.content спустя 0.3 c" % source)
	_ok(not _main._card_ids(_main.requests).has(rid),
		"%s: отклонённого запроса нет в массиве requests" % source)
	_eq(_main._card_ids(_main.requests).size(), _request_card_children(),
		"%s: карточек в контейнере = элементов requests" % source)


## Любая карточка в контейнере должна быть валидной (иначе движок уже кинул
## freed-instance). Плюс у неё должен быть живой владелец в requests.
func _check_no_invalid_cards(label: String) -> void:
	var invalid := 0
	for child in _main.send_window.content.get_children():
		if child is RequestCard and not is_instance_valid(child):
			invalid += 1
	_eq(invalid, 0, "%s: нет freed-instance карточек" % label)


func _wait(seconds: float) -> void:
	var until := _now() + seconds
	while _now() < until:
		await process_frame
	await process_frame


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


# --- хелперы ----------------------------------------------------------------

func _set_case(name: String) -> void:
	print("-- %s" % name)


func _folder_id_at(index: int) -> String:
	if _game == null or _game.registry == null:
		return ""
	for section in _game.registry.sections.values():
		if index < section.folder_ids.size():
			return str(section.folder_ids[index])
		index -= section.folder_ids.size()
	return ""


func ok_in_grid(file, message: String) -> void:
	var id := str(file.id)
	var found := false
	for f in _main.grid._files:
		if f != null and is_instance_valid(f) and str(f.id) == id:
			found = true
			break
	_ok(found, message)
	_ok(_main.grid._by_id.has(id), message + " (в _by_id)")


func _find_card(id: String):
	for child in _main.send_window.content.get_children():
		if child is RequestCard and str(child.get("id")) == id:
			return child
	return null


func _request_card_children() -> int:
	var n := 0
	for child in _main.send_window.content.get_children():
		if child is RequestCard:
			n += 1
	return n


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
	var audio = root.get_node_or_null("Audio")
	if audio != null:
		if audio.has_method("stop_music"):
			audio.call("stop_music")
		for child in audio.get_children():
			if child is AudioStreamPlayer:
				(child as AudioStreamPlayer).stop()
				(child as AudioStreamPlayer).stream = null
		audio.queue_free()
	for i in 4:
		await process_frame
	await create_timer(0.1).timeout
	print("PASS" if _fails == 0 else "FAIL")
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
