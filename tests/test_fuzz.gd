extends SceneTree
## Fuzz/инварианты реестра v2 + точечные проверки расхода файлов и отмены.
##
## Запуск:
##   godot --headless --path . --script tests/test_fuzz.gd
##
## Все шаги детерминированы (фиксированный seed). Виртуальное время
## передаётся в lock/tick явно, поэтому тест не зависит от системных часов.
## v4: успешная отправка НЕ удаляет файл из registry — он возвращается в папку
## (detach_file + cooldown=0), отмена/таймаут тоже сохраняют. consume_file
## остаётся registry-операцией для уничтожения файлов, но не вызывается из
## отправки.

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
	_consumption_case()
	_attach_once_case()
	_failed_file_detaches()
	_send_consumes_case()
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
			16: _op_table()
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
	var expected: bool = folder.count() == 0 and folder.reserved.is_empty()
	if expected:
		for f in _reg.files.values():
			if str(f.folder_id) == folder_id and str(f.location) != "table":
				expected = false
				break
	_ok(_reg.delete_folder(folder_id) == expected, "delete_folder")


func _op_create_file() -> void:
	if _reg.files.size() >= MAX_FILES:
		return
	_seq += 1
	var types: Array[String] = ["text", "sound", "photo", "video"]
	var file_type := types[_rng.randi_range(0, types.size() - 1)]
	# v2: создаём в registry (без места в папке), затем двигаем move-операцией.
	var file = _reg.create_file("fz_%d" % _seq, file_type, "", &"registry")
	_ok(file != null, "create_file в registry")
	if file != null:
		_eq(str(file.location), "registry", "create_file: location registry")


func _op_move_file() -> void:
	if _reg.files.is_empty() or _reg.folders.is_empty():
		return
	var file_id := _pick_key(_reg.files)
	var target_id := _pick_key(_reg.folders)
	var file = _reg.files[file_id]
	var target = _reg.folders[target_id]
	var loc := str(file.location)
	if not str(file.attached_request).is_empty():
		_ok(not _reg.move_file(file_id, target_id), "move_file: attached запрещён")
		return
	if loc != "folder" and loc != "registry" and loc != "table":
		_ok(not _reg.move_file(file_id, target_id), "move_file: %s запрещён" % loc)
		return
	# Перемещение в ту же папку не проверяем: first-fit видит собственные клетки.
	if loc == "folder" and str(file.folder_id) == target_id:
		return
	var expected: bool = not _reg._find_fit(target, str(file.shape_id), int(file.rotation)).is_empty()
	var result: bool = _reg.move_file(file_id, target_id)
	_ok(result == expected, "move_file")
	if result:
		_eq(str(file.location), "folder", "move_file: location folder")
		_eq(str(file.folder_id), target_id, "move_file: folder_id")
		_eq(target.file_ids.count(file_id), 1, "move_file: ровно одна запись в папке")


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
		_ok(str(file.location) == "attached" and str(file.attached_request) == req_id,
			"attach: состояние")


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
	# Стол не участвует в failed/malicious-сценариях игры.
	if str(file.location) == "table":
		return
	_ok(_reg.mark_failed(file_id), "mark_failed")
	_ok(str(file.location) == "failed", "mark_failed: location")
	_ok(str(file.attached_request).is_empty(), "mark_failed: откреплён")
	_ok(float(file.lock_until) <= 0.0 and float(file.cooldown_until) <= 0.0,
		"mark_failed: таймеры сброшены")
	_ok(not _reg.attach_file(file_id, "rX", _now), "failed не attach")


func _op_mark_malicious() -> void:
	if _reg.files.is_empty():
		return
	var file_id := _pick_key(_reg.files)
	var file = _reg.files[file_id]
	if str(file.location) == "table":
		return
	_ok(_reg.mark_malicious(file_id, "test"), "mark_malicious")
	_ok(str(file.location) == "malicious", "mark_malicious: location")
	_ok(str(file.malicious_kind) == "test", "mark_malicious: kind")
	_ok(not _reg.attach_file(file_id, "rX", _now), "malicious не attach")


func _op_remove() -> void:
	if _reg.files.is_empty():
		return
	var file_id := _pick_key(_reg.files)
	var file = _reg.files[file_id]
	if str(file.location) == "table":
		return
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
	# Атака блокирует только доступные файлы (не стол/не прикреплённые).
	if str(file.location) == "table" or str(file.location) == "attached" \
			or not str(file.attached_request).is_empty():
		return
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
		var loc := str(file.location)
		_ok(loc == "folder" or loc == "registry" or loc == "table", "unlock: location")
		_ok(float(file.lock_until) <= 0.0, "unlock: lock_until = 0")


## Стол сортировки: файл можно унести на стол и вернуть в папку.
func _op_table() -> void:
	if _rng.randf() < 0.5:
		if _reg.files.is_empty():
			return
		var file_id := _pick_key(_reg.files)
		var file = _reg.files[file_id]
		var loc := str(file.location)
		if loc == "table":
			return
		if loc != "folder" and loc != "registry":
			return
		if not str(file.attached_request).is_empty():
			return
		var fit_ok: bool = not _reg._find_table_fit(str(file.shape_id), int(file.rotation)).is_empty()
		var result: bool = _reg.move_file_to_table(file_id)
		_ok(result == fit_ok, "move_file_to_table")
		if result:
			_eq(str(file.location), "table", "table: location")
			_ok(_reg.is_table_file(file_id), "table: is_table_file")
	else:
		var table_ids := []
		for id in _reg.files.keys():
			if str(_reg.files[id].location) == "table":
				table_ids.append(id)
		if table_ids.is_empty():
			return
		var file_id := str(table_ids[_rng.randi_range(0, table_ids.size() - 1)])
		var file = _reg.files[file_id]
		var has_target: bool = not _reg._first_folder_id_with_space(file).is_empty()
		var result: bool = _reg.move_from_table(file_id)
		_ok(result == has_target, "move_from_table")
		if result:
			_eq(str(file.location), "folder", "table: вернулся в папку")


func _op_tick() -> void:
	var changed: int = _reg.tick(_now)
	_checks += 1
	if changed < 0:
		_fail("tick вернул отрицательное число")


func _check_invariants(tag: String) -> void:
	var errors: Array = []
	errors.append_array(_reg.validate())

	var membership := {}
	for folder in _reg.folders.values():
		if folder.cells.size() > folder.total_cells():
			errors.append("клеток в папке %s больше %d" % [folder.id, folder.total_cells()])
		var seen := {}
		for file_id in folder.file_ids:
			var fid := str(file_id)
			if not _reg.files.has(fid):
				errors.append("папка %s ссылается на несуществующий %s" % [folder.id, fid])
				continue
			seen[fid] = int(seen.get(fid, 0)) + 1
			membership[fid] = int(membership.get(fid, 0)) + 1
			if str(_reg.files[fid].folder_id) != str(folder.id):
				errors.append("файл %s лежит в %s, но folder_id=%s" % [
					fid, folder.id, _reg.files[fid].folder_id])
		for fid in seen.keys():
			if int(seen[fid]) > 1:
				errors.append("файл %s дважды в папке %s" % [fid, folder.id])

	for file in _reg.files.values():
		var fid := str(file.id)
		var loc := str(file.location)
		var count := int(membership.get(fid, 0))
		if count > 1:
			errors.append("файл %s в двух папках" % fid)
		if loc == "table":
			if count != 0:
				errors.append("файл %s на столе, но в folder.file_ids" % fid)
			if not _reg.is_table_file(fid):
				errors.append("файл %s имеет location=table, но не в _table_cells" % fid)
		elif str(file.folder_id).is_empty():
			if count != 0:
				errors.append("файл %s без папки, но в folder.file_ids" % fid)
		elif count != 1:
			errors.append("файл %s должен быть ровно в одной папке (location=%s)" % [fid, loc])
		if loc == "attached":
			if str(file.attached_request).is_empty():
				errors.append("attached-файл %s без запроса" % fid)
		elif not str(file.attached_request).is_empty():
			errors.append("файл %s прикреплён, но location=%s" % [fid, loc])
		if (loc == "failed" or loc == "locked" or loc == "malicious") \
				and not str(file.attached_request).is_empty():
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
				errors.append("секция %s ссылается на несуществующую папку %s" % [
					section.id, folder_id])
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

## Registry-level consume_file: используется уничтожением/атаками, НЕ отправкой.
func _consumption_case() -> void:
	_set_case("consumption")
	_reg = FR.new()
	_reg.setup_new_run()
	var folder_id := _first_folder(_reg)
	var folder = _reg.folders[folder_id]
	var file = _reg.create_file("consume.txt", "text", folder_id)
	_ok(file != null, "consumption: файл создан")
	if file == null:
		return
	var fid := str(file.id)
	var base: float = 50000.0
	_ok(_reg.attach_file(fid, "req_a", base), "consumption: прикреплён")
	_ok(_reg.detach_file(fid), "consumption: отмена возвращает файл")
	_ok(_reg.attach_file(fid, "req_b", base), "consumption: снова прикреплён")
	_eq(str(file.location), "attached", "consumption: location attached")
	var free_before: int = folder.free_cell_count()
	_ok(_reg.consume_file(fid), "consumption: файл израсходован")
	_ok(not _reg.files.has(fid), "consumption: файла нет в реестре")
	_ok(folder.free_cell_count() > free_before, "consumption: клетки освобождены")
	_ok(not _reg.attach_file(fid, "req_c", base), "consumption: израсходованный не attach")
	_ok(_reg.validate().is_empty(), "consumption: реестр валиден")


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
	_ok(not _reg.attach_file(str(file.id), "req_2", 1000.0),
		"attach_once: второе прикрепление запрещено")
	_ok(str(file.attached_request) == "req_1", "attach_once: запрос не перезаписан")
	_ok(_reg.detach_file(str(file.id)), "attach_once: открепление")
	_ok(_reg.attach_file(str(file.id), "req_2", 1000.0),
		"attach_once: после detach можно прикрепить к другому")


## v2: провал файла только открепляет его; запросы не отменяются и не штрафуются.
func _failed_file_detaches() -> void:
	_set_case("failed_file_detaches")
	_game.start_new_run(4242)
	var hd = HD.new()
	hd.start_hour(1)
	hd.set_time_scale(1.0)
	hd._next_spawn_at = 9999.0
	var folder_id := _first_folder(_game.registry)
	var file = _game.registry.create_file("failed_detach.txt", "text", folder_id)
	_ok(file != null, "failed_file: файл создан")
	if file == null:
		hd.free()
		return
	var fid := str(file.id)
	var req_a := str(hd._make_request([file], "udp", false, "", ""))
	var req_b := str(hd._make_request([file], "udp", false, "", ""))
	_ok(not req_a.is_empty() and not req_b.is_empty(), "failed_file: два запроса созданы")
	_ok(hd.attach_file(req_a, fid), "failed_file: файл прикреплён к запросу A")
	_game.money = 1000
	_game.sla = 150.0
	_game.registry.mark_failed(fid)
	hd.tick(0.1)
	_ok(hd.active_requests.has(req_a), "failed_file: запрос A остался")
	_ok(hd.active_requests.has(req_b), "failed_file: запрос B остался")
	var req = hd.active_requests.get(req_a)
	_ok(req != null and req.attached.is_empty(), "failed_file: файл откреплён от запроса")
	_eq(_game.money, 1000, "failed_file: штрафа за отмену нет")
	_approx(_game.sla, 150.0, 0.0001, "failed_file: штрафа SLA нет")
	_ok(hd.reject_request(req_a), "failed_file: запрос A можно отклонить")
	_ok(_game.registry.validate().is_empty(), "failed_file: реестр валиден")
	hd.free()


## v4: успешная отправка НЕ расходует файл: он остаётся в папке с cooldown 0
## и снова доступен пулу запросов. Отмена/таймаут тоже сохраняют файл.
func _send_consumes_case() -> void:
	_set_case("send_keeps_file")
	_game.start_new_run(5151)
	var hd = HD.new()
	hd.send_game_factory = func(_id, _tier, _seed, _ctx):
		return StubGame.new()
	hd.start_hour(1)
	hd.set_time_scale(1.0)
	hd._next_spawn_at = 9999.0
	var folder_id := _first_folder(_game.registry)
	var folder = _game.registry.folders[folder_id]
	var file = _game.registry.create_file("send_ok.txt", "text", folder_id)
	_ok(file != null, "send_keeps: файл создан")
	if file == null:
		hd.free()
		return
	var fid := str(file.id)
	var free_before: int = folder.free_cell_count()
	var req_id := str(hd._make_request([file], "tcp", false, "", ""))
	_ok(hd.connect_request(req_id), "send_keeps: соединение установлено")
	_ok(hd.connection_finished(req_id, true), "send_keeps: connection_finished")
	_ok(hd.attach_file(req_id, fid), "send_keeps: файл прикреплён")
	var money_before := int(_game.money)
	_ok(hd.start_send(req_id), "send_keeps: мини-игра открыта")
	_ok(hd.is_minigame_active(), "send_keeps: мини-игра активна")
	hd._on_send_minigame_finished(0.8)
	var req = hd.active_requests.get(req_id)
	_ok(req != null and (req.sending or hd.is_request_queued(req_id)),
		"send_keeps: отправка/очередь после мини-игры")
	for i in range(300):
		hd.tick(0.1)
		if not hd.active_requests.has(req_id):
			break
	_ok(not hd.active_requests.has(req_id), "send_keeps: запрос завершён")
	_ok(int(_game.money) > money_before, "send_keeps: деньги выросли")
	_ok(_game.registry.files.has(fid), "send_keeps: файл остался в registry")
	var kept = _game.registry.files.get(fid)
	if kept != null:
		_eq(str(kept.location), "folder", "send_keeps: location folder")
		_eq(str(kept.attached_request), "", "send_keeps: attached_request пуст")
		_eq(str(kept.required_by), "", "send_keeps: required_by пуст")
		_eq(float(kept.cooldown_until), 0.0, "send_keeps: cooldown 0")
	_eq(folder.free_cell_count(), free_before, "send_keeps: клетки не освободились")
	# Тот же файл можно сразу затребовать новым запросом и прикрепить.
	var req_new := str(hd._create_request(1, "udp", [fid], false))
	_ok(not req_new.is_empty(), "send_keeps: новый запрос на тот же файл")
	_ok(hd.attach_file(req_new, fid), "send_keeps: повторное прикрепление успешно")
	hd._cleanup_request(req_new, true)

	# Отмена мини-игры: файл остаётся прикреплённым и не расходуется.
	var file2 = _game.registry.create_file("send_cancel.txt", "text", folder_id)
	_ok(file2 != null, "send_keeps: второй файл создан")
	if file2 == null:
		hd.free()
		return
	var fid2 := str(file2.id)
	var req2 := str(hd._make_request([file2], "udp", false, "", ""))
	_ok(hd.attach_file(req2, fid2), "send_keeps: второй файл прикреплён")
	_ok(hd.start_send(req2), "send_keeps: вторая мини-игра открыта")
	hd.force_close_send_minigame()
	_ok(_game.registry.files.has(fid2), "send_keeps: отмена сохранила файл")
	_eq(str(_game.registry.files[fid2].location), "attached",
		"send_keeps: файл остался прикреплён")
	_ok(hd.reject_request(req2), "send_keeps: запрос отклоняется после отмены")
	_ok(_game.registry.files.has(fid2), "send_keeps: отказ не расходует файл")
	_eq(str(_game.registry.files[fid2].location), "folder",
		"send_keeps: после отказа файл в папке")
	_eq(str(_game.registry.files[fid2].required_by), "",
		"send_keeps: после отказа required_by пуст")

	# Таймаут запроса тоже сохраняет файл.
	var file3 = _game.registry.create_file("send_timeout.txt", "text", folder_id)
	_ok(file3 != null, "send_keeps: третий файл создан")
	if file3 == null:
		hd.free()
		return
	var fid3 := str(file3.id)
	var req3 := str(hd._make_request([file3], "udp", false, "", ""))
	_ok(hd.attach_file(req3, fid3), "send_keeps: третий файл прикреплён")
	var live3 = hd.active_requests.get(req3)
	if live3 != null:
		live3.time_left = 0.05
	hd.tick(0.1)
	_ok(not hd.active_requests.has(req3), "send_keeps: запрос истёк по таймауту")
	_ok(_game.registry.files.has(fid3), "send_keeps: таймаут сохранил файл")
	_eq(str(_game.registry.files[fid3].location), "folder",
		"send_keeps: после таймаута файл в папке")
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
	_stop_audio()
	print("test_fuzz: проверок %d, провалов %d, known bug %d" % [_checks, _fails, _known])
	print("PASS test_fuzz" if _fails == 0 else "FAIL test_fuzz")
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


## Мини-игра-заглушка: сигнал finished, но игра сама не идёт.
class StubGame:
	extends Node

	signal finished(quality: float)

	var running := true
	var id := "stub"
