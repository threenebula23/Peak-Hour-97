extends SceneTree
## Fuzz/инварианты реестра + точечные проверки cooldown и отмены запросов
## по failed-файлу.
##
## Запуск:
##   godot --headless --path . --script tests/test_fuzz.gd
##
## Все шаги детерминированы (фиксированный seed). Виртуальное время
## передаётся в lock/cooldown/tick явно, поэтому тест не зависит от
## системных часов и порядка выполнения.

const FR := preload("res://scripts/core/file_registry.gd")
const HD := preload("res://scripts/core/hour_director.gd")

const STEPS := 1200
const SEED := 20261025
const MAX_FILES := 110

var _checks: int = 0
var _fails: int = 0
var _known: int = 0
var _case: String = ""
var _rng := RandomNumberGenerator.new()
var _now: float = 10000.0
var _seq: int = 0
var _reg = null
var _game = null


func _init() -> void:
	await process_frame
	_game = root.get_node_or_null("Game")
	if _game == null:
		_fail("autoload Game недоступен")
		_finish()
		return
	_fuzz_registry()
	_cooldown_case()
	_attach_once_case()
	_failed_cancels_all_requests()
	_send_cooldown_case()
	_finish()


# --- фаззинг ---------------------------------------------------------------

func _fuzz_registry() -> void:
	_set_case("fuzz")
	_reg = FR.new()
	_reg.setup_new_run()
	_rng.seed = SEED
	_now = 10000.0
	_seq = 0
	for step in range(STEPS):
		_now += 0.25
		var op := _rng.randi_range(0, 17)
		match op:
			0: _op_create_section()
			1: _op_create_folder()
			2: _op_rename_folder()
			3: _op_delete_folder()
			4, 5: _op_create_file()
			6, 7: _op_move_file()
			8: _op_attach()
			9: _op_detach()
			10: _op_mark_failed()
			11: _op_mark_malicious()
			12: _op_remove()
			13: _op_destroy_malicious()
			14: _op_lock()
			15: _op_unlock()
			16: _op_reserve_or_release()
			17: _op_tick()
		_check_invariants("шаг %d" % step)


func _op_create_section() -> void:
	var letters: Array[String] = ["C", "D", "E", "F", "G", "H"]
	var letter := letters[_rng.randi_range(0, letters.size() - 1)]
	var existed: bool = _reg.sections.has(letter)
	var full: bool = _reg.sections.size() >= FR.MAX_SECTIONS
	var section = _reg.create_section(letter)
	if existed or full:
		_ok(section == null, "create_section(%s): отказ при дубле/лимите" % letter)
	else:
		_ok(section != null, "create_section(%s): создана" % letter)


func _op_create_folder() -> void:
	if _reg.sections.is_empty():
		return
	var section_id := _pick_key(_reg.sections)
	var count: int = int(_reg._folder_count_in_section(section_id))
	_seq += 1
	var folder = _reg.create_folder(section_id, "fz_%d" % _seq)
	if count >= FR.MAX_FOLDERS_PER_SECTION:
		_ok(folder == null, "create_folder: отказ при лимите 12")
	else:
		_ok(folder != null, "create_folder: создана папка")


func _op_rename_folder() -> void:
	if _reg.folders.is_empty():
		return
	var folder_id := _pick_key(_reg.folders)
	var folder = _reg.folders[folder_id]
	_seq += 1
	var new_name := "rn_%d" % _seq
	var expected: bool = new_name.strip_edges().length() > 0 and new_name.length() <= FR.MAX_FOLDER_NAME
	if expected and new_name.to_lower() != str(folder.name).to_lower():
		expected = not _reg._folder_name_taken(str(folder.section), new_name)
	_ok(_reg.rename_folder(folder_id, new_name) == expected, "rename_folder")


func _op_delete_folder() -> void:
	if _reg.folders.is_empty():
		return
	var folder_id := _pick_key(_reg.folders)
	var folder = _reg.folders[folder_id]
	var expected: bool = folder.count() == 0 and int(folder.reserved) == 0
	if expected:
		for f in _reg.files.values():
			if str(f.folder_id) == folder_id:
				expected = false
				break
	_ok(_reg.delete_folder(folder_id) == expected, "delete_folder")


func _op_create_file() -> void:
	if _reg.files.size() >= MAX_FILES:
		return
	_seq += 1
	var types: Array[String] = ["text", "sound", "photo", "video"]
	var file_type := types[_rng.randi_range(0, types.size() - 1)]
	var use_folder: bool = _rng.randf() < 0.65 and not _reg.folders.is_empty()
	if use_folder:
		var folder_id := _pick_key(_reg.folders)
		var folder = _reg.folders[folder_id]
		var has_room: bool = folder.has_free_slot(FR.MAX_FILES_PER_FOLDER)
		var file = _reg.create_file("fz_%d" % _seq, file_type, folder_id, &"folder")
		if has_room:
			_ok(file != null, "create_file в папку при наличии места")
		else:
			_ok(file == null, "create_file: отказ при переполнении папки")
	else:
		var file = _reg.create_file("fz_%d" % _seq, file_type, "", &"registry")
		_ok(file != null, "create_file в registry")


func _op_move_file() -> void:
	if _reg.files.is_empty() or _reg.folders.is_empty():
		return
	var file_id := _pick_key(_reg.files)
	var target_id := _pick_key(_reg.folders)
	var file = _reg.files[file_id]
	var target = _reg.folders[target_id]
	var expected := true
	if str(file.location) != "folder" and str(file.location) != "registry":
		expected = false
	elif not str(file.attached_request).is_empty():
		expected = false
	elif file.folder_id == target_id and str(file.location) == "folder":
		expected = true
	else:
		var occupied: int = target.count()
		if file.folder_id == target_id:
			occupied -= 1
		expected = occupied + int(target.reserved) < FR.MAX_FILES_PER_FOLDER
	var result: bool = _reg.move_file(file_id, target_id)
	_ok(result == expected, "move_file")
	if result:
		_ok(str(file.location) == "folder" and file.folder_id == target_id, "move_file: состояние файла")
		_ok(target.file_ids.count(file_id) == 1, "move_file: ровно одна запись в папке")


func _op_attach() -> void:
	if _reg.files.is_empty():
		return
	var file_id := _pick_key(_reg.files)
	var file = _reg.files[file_id]
	var req_id := "r%d" % _rng.randi_range(1, 3)
	var expected: bool = file.can_attach(_now) and str(file.attached_request).is_empty()
	var result: bool = _reg.attach_file(file_id, req_id, _now)
	_ok(result == expected, "attach_file")
	if expected:
		_ok(str(file.location) == "attached" and str(file.attached_request) == req_id, "attach: состояние")


func _op_detach() -> void:
	if _reg.files.is_empty():
		return
	var file_id := _pick_key(_reg.files)
	var file = _reg.files[file_id]
	var expected: bool = str(file.location) == "attached" or not str(file.attached_request).is_empty()
	var result: bool = _reg.detach_file(file_id)
	_ok(result == expected, "detach_file")
	if expected:
		_ok(str(file.attached_request).is_empty(), "detach: attached_request пуст")


func _op_mark_failed() -> void:
	if _reg.files.is_empty():
		return
	var file_id := _pick_key(_reg.files)
	var file = _reg.files[file_id]
	_ok(_reg.mark_failed(file_id), "mark_failed")
	_ok(str(file.location) == "failed", "mark_failed: location")
	_ok(str(file.attached_request).is_empty(), "mark_failed: откреплён")
	_ok(float(file.lock_until) <= 0.0 and float(file.cooldown_until) <= 0.0, "mark_failed: таймеры сброшены")
	_ok(not _reg.attach_file(file_id, "rX", _now), "failed не attach")


func _op_mark_malicious() -> void:
	if _reg.files.is_empty():
		return
	var file_id := _pick_key(_reg.files)
	var file = _reg.files[file_id]
	_ok(_reg.mark_malicious(file_id, "test"), "mark_malicious")
	_ok(str(file.location) == "malicious", "mark_malicious: location")
	_ok(str(file.malicious_kind) == "test", "mark_malicious: kind")
	_ok(not _reg.attach_file(file_id, "rX", _now), "malicious не attach")


func _op_remove() -> void:
	if _reg.files.is_empty():
		return
	var file_id := _pick_key(_reg.files)
	var file = _reg.files[file_id]
	var expected: bool = str(file.location) == "malicious" or str(file.location) == "failed"
	var result: bool = _reg.remove_file(file_id)
	_ok(result == expected, "remove_file")
	if result:
		_ok(not _reg.files.has(file_id), "remove_file: запись удалена")


func _op_destroy_malicious() -> void:
	if _reg.files.is_empty():
		return
	var file_id := _pick_key(_reg.files)
	var file = _reg.files[file_id]
	var expected: bool = str(file.location) == "malicious"
	_ok(_reg.destroy_malicious(file_id) == expected, "destroy_malicious")


func _op_lock() -> void:
	if _reg.files.is_empty():
		return
	var file_id := _pick_key(_reg.files)
	var file = _reg.files[file_id]
	var expected: bool = str(file.location) != "failed" and str(file.location) != "malicious"
	var result: bool = _reg.lock_file(file_id, 5.0, _now)
	_ok(result == expected, "lock_file")
	if expected:
		_ok(str(file.location) == "locked", "lock_file: location")
		_approx(float(file.lock_until), _now + 5.0, 0.0001, "lock_file: lock_until")
		_ok(str(file.attached_request).is_empty(), "lock_file: откреплён")
		_ok(not _reg.attach_file(file_id, "rX", _now), "locked не attach")


func _op_unlock() -> void:
	if _reg.files.is_empty():
		return
	var file_id := _pick_key(_reg.files)
	var file = _reg.files[file_id]
	var expected: bool = str(file.location) == "locked"
	var result: bool = _reg.unlock_file(file_id)
	_ok(result == expected, "unlock_file")
	if expected:
		_ok(str(file.location) == "folder" or str(file.location) == "registry", "unlock: location")
		_ok(float(file.lock_until) <= 0.0, "unlock: lock_until = 0")


func _op_reserve_or_release() -> void:
	if _reg.folders.is_empty():
		return
	var folder_id := _pick_key(_reg.folders)
	var folder = _reg.folders[folder_id]
	if _rng.randf() < 0.5:
		var expected: bool = folder.count() + int(folder.reserved) < FR.MAX_FILES_PER_FOLDER
		var before: int = int(folder.reserved)
		_ok(_reg.reserve_slot(folder_id) == expected, "reserve_slot")
		if expected:
			_ok(int(folder.reserved) == before + 1, "reserve_slot: +1")
	else:
		var expected: bool = int(folder.reserved) > 0
		var before: int = int(folder.reserved)
		_ok(_reg.release_slot(folder_id) == expected, "release_slot")
		if expected:
			_ok(int(folder.reserved) == before - 1, "release_slot: -1")


func _op_tick() -> void:
	var changed: int = _reg.tick(_now)
	_checks += 1
	if changed < 0:
		_fail("tick вернул отрицательное число")


func _check_invariants(tag: String) -> void:
	var errors: Array = []
	errors.append_array(_reg.validate())

	var membership := {}
	var folder_owner := {}
	for folder in _reg.folders.values():
		if folder.count() + int(folder.reserved) > FR.MAX_FILES_PER_FOLDER:
			errors.append("capacity папки %s > %d" % [folder.id, FR.MAX_FILES_PER_FOLDER])
		var seen := {}
		for file_id in folder.file_ids:
			var fid := str(file_id)
			if not _reg.files.has(fid):
				errors.append("папка %s ссылается на несуществующий %s" % [folder.id, fid])
				continue
			seen[fid] = int(seen.get(fid, 0)) + 1
			membership[fid] = int(membership.get(fid, 0)) + 1
			if folder_owner.has(fid):
				errors.append("файл %s в папках %s и %s" % [fid, folder_owner[fid], folder.id])
			folder_owner[fid] = folder.id
			if str(_reg.files[fid].folder_id) != str(folder.id):
				errors.append("файл %s лежит в %s, но folder_id=%s" % [fid, folder.id, _reg.files[fid].folder_id])
		for fid in seen.keys():
			if int(seen[fid]) > 1:
				errors.append("файл %s дважды в папке %s" % [fid, folder.id])

	for file in _reg.files.values():
		var fid := str(file.id)
		var loc := str(file.location)
		var count := int(membership.get(fid, 0))
		if count > 1:
			errors.append("файл %s в двух папках" % fid)
		if str(file.folder_id).is_empty() and count != 0:
			errors.append("файл %s без папки, но в folder.file_ids" % fid)
		if not str(file.folder_id).is_empty() and count != 1:
			errors.append("файл %s должен быть ровно в одной папке" % fid)
		if loc == "attached":
			if str(file.attached_request).is_empty():
				errors.append("attached-файл %s без запроса" % fid)
		elif not str(file.attached_request).is_empty():
			errors.append("файл %s прикреплён, но location=%s" % [fid, loc])
		if (loc == "failed" or loc == "locked" or loc == "malicious") and not str(file.attached_request).is_empty():
			errors.append("%s-файл %s прикреплён" % [loc, fid])
		if not FR.FILE_ITEM_SCRIPT.LOCATIONS.has(loc):
			errors.append("неверный location %s" % loc)

	if _reg.sections.size() > FR.MAX_SECTIONS:
		errors.append("секций > %d" % FR.MAX_SECTIONS)
	for section in _reg.sections.values():
		var section_folders := 0
		var seen_folders := {}
		for folder_id in section.folder_ids:
			section_folders += 1
			if not _reg.folders.has(str(folder_id)):
				errors.append("секция %s ссылается на несуществующую папку %s" % [section.id, folder_id])
			if seen_folders.has(str(folder_id)):
				errors.append("папка %s дважды в секции %s" % [folder_id, section.id])
			seen_folders[str(folder_id)] = true
		if section_folders > FR.MAX_FOLDERS_PER_SECTION:
			errors.append("папок в секции %s > %d" % [section.id, FR.MAX_FOLDERS_PER_SECTION])

	var names := {}
	var display_names := {}
	for file in _reg.files.values():
		var probe: String = str(file.name).to_lower()
		if probe.is_empty():
			errors.append("пустое имя файла %s" % file.id)
		if names.has(probe):
			errors.append("дубль имени файла: %s" % file.name)
		names[probe] = true
		var display := str(file.display_name()).to_lower()
		if not display.is_empty():
			if display_names.has(display):
				errors.append("дубль отображаемого имени: %s" % file.display_name())
			display_names[display] = true

	_checks += 1
	if not errors.is_empty():
		_fails += 1
		print("FAIL [%s/%s] %s" % [_case, tag, "; ".join(errors.slice(0, 5))])


# --- точечные сценарии -----------------------------------------------------

func _cooldown_case() -> void:
	_set_case("cooldown")
	_reg = FR.new()
	_reg.setup_new_run()
	var folder_id := _first_folder(_reg)
	var file = _reg.create_file("cooldown.txt", "text", folder_id)
	_ok(file != null, "cooldown: файл создан")
	if file == null:
		return
	var base: float = 50000.0
	_ok(_reg.set_cooldown(str(file.id), 20.0, base), "cooldown: установлен на 20 с")
	_ok(not _reg.attach_file(str(file.id), "req_a", base), "cooldown: сразу после отправки attach=false")
	_approx(float(file.cooldown_until), base + 20.0, 0.0001, "cooldown_until = now + 20")
	# Через 21 секунду tick снимает cooldown.
	_eq(_reg.tick(base + 21.0), 1, "tick(now+21) снял cooldown")
	_ok(_reg.attach_file(str(file.id), "req_a", base + 21.0), "cooldown: после tick attach=true")


func _attach_once_case() -> void:
	_set_case("attach_once")
	_reg = FR.new()
	_reg.setup_new_run()
	var folder_id := _first_folder(_reg)
	var file = _reg.create_file("attach_once.txt", "text", folder_id)
	_ok(file != null, "attach_once: файл создан")
	if file == null:
		return
	_ok(_reg.attach_file(str(file.id), "req_1", 1000.0), "attach_once: первое прикрепление")
	_ok(not _reg.attach_file(str(file.id), "req_2", 1000.0), "attach_once: второе прикрепление запрещено")
	_ok(str(file.attached_request) == "req_1", "attach_once: запрос не перезаписан")
	_ok(_reg.detach_file(str(file.id)), "attach_once: открепление")
	_ok(_reg.attach_file(str(file.id), "req_2", 1000.0), "attach_once: после detach можно прикрепить к другому")


func _failed_cancels_all_requests() -> void:
	_set_case("failed_cancels_all")
	_game.start_new_run(4242)
	var hd = HD.new()
	hd.start_hour(1)
	hd._recv_interval_current = 9999.0
	hd.spawn_recv_accum = 0.0
	var folder_id := _first_folder(_game.registry)
	var file = _game.registry.create_file("failed_cancel.txt", "text", folder_id)
	_ok(file != null, "failed_cancels_all: файл создан")
	if file == null:
		hd.free()
		return
	var req_a := str(hd._make_request([file], "udp", false, "", ""))
	var req_b := str(hd._make_request([file], "udp", false, "", ""))
	_ok(not req_a.is_empty() and not req_b.is_empty(), "failed_cancels_all: два запроса с одним required")
	_ok(hd.attach_file(req_a, str(file.id)), "failed_cancels_all: файл прикреплён к первому")
	_game.money = 1000
	_game.sla = 150.0
	_game.registry.mark_failed(str(file.id))
	hd.tick(0.1)
	_ok(not hd.active_requests.has(req_a), "failed_cancels_all: запрос A отменён")
	_ok(not hd.active_requests.has(req_b), "failed_cancels_all: запрос B отменён")
	_eq(_game.money, 970, "failed_cancels_all: два штрафа по −15 $")
	_approx(_game.sla, 130.0, 0.001, "failed_cancels_all: два штрафа по −10 SLA")
	_eq(int(hd._failed), 2, "failed_cancels_all: оба провала учтены")
	_ok(_game.registry.validate().is_empty(), "failed_cancels_all: реестр валиден")
	hd.free()


func _send_cooldown_case() -> void:
	_set_case("send_cooldown")
	_game.start_new_run(5151)
	var hd = HD.new()
	hd.start_hour(1)
	hd.set_time_scale(1.0)
	hd._recv_interval_current = 9999.0
	hd.spawn_recv_accum = 0.0
	var folder_id := _first_folder(_game.registry)
	var file = _game.registry.create_file("send_cd.txt", "text", folder_id)
	_ok(file != null, "send_cooldown: файл создан")
	if file == null:
		hd.free()
		return
	var req_id := str(hd._make_request([file], "tcp", false, "", ""))
	_ok(hd.attach_file(req_id, str(file.id)), "send_cooldown: файл прикреплён")
	var req = hd.active_requests.get(req_id)
	req.connected = true
	_ok(hd.start_send(req_id), "send_cooldown: мини-игра открыта")
	var mg = hd._minigame
	_ok(mg != null, "send_cooldown: MiniGame создан")
	if mg != null:
		mg._send()
	_ok(req.sending, "send_cooldown: отправка началась")
	for i in range(300):
		hd.tick(0.1)
		if not hd.active_requests.has(req_id):
			break
	_ok(not hd.active_requests.has(req_id), "send_cooldown: запрос завершён")
	_ok(float(file.cooldown_until) > 0.0, "send_cooldown: cooldown выставлен")
	_ok(not _game.registry.attach_file(str(file.id), "after_send"), "send_cooldown: сразу после отправки attach=false")
	var now := Time.get_unix_time_from_system()
	_eq(_game.registry.tick(now + 21.0), 1, "send_cooldown: tick(now+21) снял cooldown")
	_ok(_game.registry.attach_file(str(file.id), "after_send"), "send_cooldown: после tick attach=true")
	hd.free()


# --- служебное -------------------------------------------------------------

func _first_folder(reg) -> String:
	var section = reg.sections.get("C")
	if section == null or section.folder_ids.is_empty():
		return ""
	return str(section.folder_ids[0])


func _pick_key(d: Dictionary) -> String:
	var keys := d.keys()
	if keys.is_empty():
		return ""
	return str(keys[_rng.randi_range(0, keys.size() - 1)])


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
	print("test_fuzz: проверок %d, провалов %d, known bug %d" % [_checks, _fails, _known])
	print("PASS test_fuzz" if _fails == 0 else "FAIL test_fuzz")
	quit(0 if _fails == 0 else 1)
