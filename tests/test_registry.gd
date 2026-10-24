extends RefCounted
## Тесты реестра склада: секции/папки/файлы, лимиты, состояния, save/load.

const R := preload("res://scripts/core/file_registry.gd")

var _hits: Dictionary = {}


func run(t) -> void:
	_test_setup(t)
	_test_sections(t)
	_test_folders(t)
	_test_files_and_limits(t)
	_test_move(t)
	_test_attach(t)
	_test_states(t)
	_test_remove(t)
	_test_reserve(t)
	_test_roundtrip(t)
	_test_signals(t)


func _test_setup(t) -> void:
	t.set_case("setup_new_run")
	var reg = R.new()
	reg.setup_new_run()
	t.eq(reg.sections.size(), 1, "одна стартовая секция")
	t.eq(reg.folders.size(), 1, "одна стартовая папка")
	t.eq(reg.files.size(), 0, "файлов нет")
	var section = reg.sections.get("C", null)
	t.ok(section != null, "секция C существует")
	t.eq(str(section.letter), "C", "буква секции C")
	t.eq(str(section.id), "C", "id секции C")
	var folder_id := _default_folder_id(reg)
	t.ok(not folder_id.is_empty(), "у секции C есть папка")
	var folder = reg.folders.get(folder_id, null)
	t.ok(folder != null, "папка найдена")
	t.eq(str(folder.name), "Разное", "папка называется «Разное»")
	t.eq(int(folder.count()), 0, "папка пуста")


func _test_sections(t) -> void:
	t.set_case("sections")
	var reg = R.new()
	reg.setup_new_run()
	for letter in ["D", "E", "F", "G", "H"]:
		var section = reg.create_section(letter)
		t.ok(section != null, "создана секция " + letter)
	t.eq(reg.sections.size(), 6, "лимит 6 секций")
	t.ok(reg.create_section("C") == null, "дубль секции запрещён")
	t.ok(reg.create_section("I") == null, "буква вне C..H запрещена")
	t.ok(reg.create_section("B") == null, "буква до C запрещена")
	t.ok(reg.create_section("") == null, "пустая буква запрещена")
	t.ok(reg.create_section("CC") == null, "две буквы запрещены")
	var d = reg.sections.get("D", null)
	t.ok(d != null and not str(d.name).is_empty(), "у секции есть имя")


func _test_folders(t) -> void:
	t.set_case("folders")
	var reg = R.new()
	reg.setup_new_run()
	t.ok(reg.create_folder("C", "Дубликат") != null, "новая папка создана")
	t.ok(reg.create_folder("C", "дубликат") == null, "дубль имени без учёта регистра")
	t.ok(reg.create_folder("C", "") == null, "пустое имя запрещено")
	t.ok(reg.create_folder("C", "12345678901234567") == null, "имя 17 символов запрещено")
	t.ok(reg.create_folder("C", "1234567890123456") != null, "имя 16 символов разрешено")
	t.ok(reg.create_folder("Z", "Куда") == null, "неизвестная секция запрещена")

	var guard := 0
	while _folder_count(reg, "C") < 12 and guard < 30:
		guard += 1
		reg.create_folder("C", "Доп %02d" % guard)
	t.eq(_folder_count(reg, "C"), 12, "лимит 12 папок в секции")
	t.ok(reg.create_folder("C", "Лишняя") == null, "13-я папка в секции запрещена")

	var other = reg.create_section("D")
	t.ok(other != null, "новая секция для проверки лимита")
	t.ok(reg.create_folder("D", "Лишняя") != null, "в другой секции имя допустимо")

	var folder_id := _default_folder_id(reg)
	t.ok(reg.rename_folder(folder_id, "Новое имя"), "переименование папки")
	t.eq(str(reg.folders[folder_id].name), "Новое имя", "имя изменилось")
	t.ok(not reg.rename_folder(folder_id, "12345678901234567"), "длинное имя при переименовании запрещено")
	t.ok(not reg.rename_folder(folder_id, "Дубликат"), "дубль при переименовании запрещён")
	t.ok(not reg.rename_folder("fold_nope", "Имя"), "несуществующая папка")
	t.ok(reg.create_file("Занято", "text", folder_id) != null, "файл в папке")
	t.ok(not reg.delete_folder(folder_id), "непустую папку удалить нельзя")


func _test_files_and_limits(t) -> void:
	t.set_case("files")
	var reg = R.new()
	reg.setup_new_run()
	var folder_id := _default_folder_id(reg)
	var file = reg.create_file("Отчёт", "text", folder_id)
	t.ok(file != null, "файл создан")
	t.eq(str(file.ext), "txt", "расширение text")
	t.eq(str(file.location), "folder", "location folder")
	t.eq(str(file.folder_id), folder_id, "folder_id проставлен")
	t.eq(str(file.display_name()), "Отчёт.txt", "display_name")
	t.eq(int(reg.folders[folder_id].count()), 1, "файл в папке")

	t.ok(reg.create_file("отчёт", "text", folder_id) == null, "дубль имени без учёта регистра")
	t.ok(reg.create_file("Отчёт", "text", folder_id) == null, "точный дубль имени")
	t.ok(reg.create_file("", "text", folder_id) == null, "пустое имя файла")
	t.ok(reg.create_file("Без папки", "text", "fold_nope") == null, "несуществующая папка")
	t.ok(reg.create_file("Плохо", "text", folder_id, &"attached") == null, "недопустимый location")

	var stored = reg.create_file("На складе", "sound", "", &"registry")
	t.ok(stored != null, "файл в registry создан")
	t.eq(str(stored.location), "registry", "location registry")
	t.eq(str(stored.folder_id), "", "у registry нет папки")
	t.eq(reg.get_pending_files().size(), 1, "registry-файл в pending")

	for i in range(15):
		var added = reg.create_file("Файл %02d" % i, "photo", folder_id)
		t.ok(added != null, "файл %d добавлен" % i)
	t.eq(int(reg.folders[folder_id].count()), 16, "в папке 16 файлов")
	t.eq(reg.files.size(), 17, "16 в папке + 1 в registry")
	t.ok(reg.create_file("Семнадцатый", "text", folder_id) == null, "17-й файл не создаётся")

	var available: Array = reg.get_available_files()
	t.eq(available.size(), 17, "все 17 файлов доступны")


func _test_move(t) -> void:
	t.set_case("move")
	var reg = R.new()
	reg.setup_new_run()
	var a_id := _default_folder_id(reg)
	var b = reg.create_folder("C", "Вторая")
	var c = reg.create_folder("C", "Третья")
	t.ok(b != null and c != null, "папки для move")
	var file = reg.create_file("Переезд", "text", a_id)
	t.ok(reg.move_file(file.id, b.id), "move в другую папку")
	t.eq(str(file.folder_id), str(b.id), "folder_id обновился")
	t.ok(not reg.folders[a_id].file_ids.has(file.id), "из старой папки удалён")
	t.ok(reg.folders[b.id].file_ids.has(file.id), "в новой папке есть")
	t.ok(reg.move_file(file.id, b.id), "move в ту же папку — true")
	t.ok(not reg.move_file(file.id, "fold_nope"), "move в несуществующую папку")
	t.ok(not reg.move_file("file_nope", b.id), "move несуществующего файла")

	var extra = reg.create_file("Лишний", "text", a_id)
	for i in range(15):
		reg.create_file("B %02d" % i, "text", b.id)
	t.eq(int(reg.folders[b.id].count()), 16, "целевая папка заполнена")
	t.ok(not reg.move_file(extra.id, b.id), "move в полную папку запрещён")

	t.ok(reg.attach_file(extra.id, "req_move", 1000.0), "attach для проверки move")
	t.ok(not reg.move_file(extra.id, c.id), "attached нельзя перемещать")
	reg.detach_file(extra.id)
	t.ok(reg.move_file(extra.id, c.id), "после detach move разрешён")

	var locked = reg.create_file("Замок", "text", c.id)
	t.ok(reg.lock_file(locked.id, 5.0, 1000.0), "lock файла")
	t.ok(not reg.move_file(locked.id, a_id), "locked нельзя перемещать")
	reg.tick(1005.0)
	t.ok(reg.move_file(locked.id, a_id), "после unlock move разрешён")


func _test_attach(t) -> void:
	t.set_case("attach")
	var reg = R.new()
	reg.setup_new_run()
	var folder_id := _default_folder_id(reg)
	var file = reg.create_file("Прикрепляемый", "text", folder_id)
	var now := 1000.0

	t.ok(not reg.attach_file(file.id, "", now), "пустой request_id запрещён")
	t.ok(reg.attach_file(file.id, "req_1", now), "attach успешен")
	t.eq(str(file.location), "attached", "location attached")
	t.eq(str(file.attached_request), "req_1", "attached_request")
	t.eq(int(reg.folders[folder_id].count()), 1, "файл остался в папке")
	t.ok(reg.folders[folder_id].file_ids.has(file.id), "папка по-прежнему ссылается на файл")
	t.ok(not reg.attach_file(file.id, "req_1", now), "повторный attach к тому же запросу")
	t.ok(not reg.attach_file(file.id, "req_2", now), "attach ко второму запросу")
	t.ok(not reg.attach_file("file_nope", "req_1", now), "attach несуществующего файла")

	t.ok(reg.detach_file(file.id), "detach")
	t.eq(str(file.location), "folder", "после detach location folder")
	t.eq(str(file.attached_request), "", "attached_request очищен")
	t.ok(not reg.detach_file(file.id), "повторный detach — false")
	t.ok(reg.attach_file(file.id, "req_3", now), "повторный attach после detach")

	var second = reg.create_file("Второй", "text", folder_id)
	t.ok(reg.attach_file(second.id, "req_3", now), "два файла в одном запросе допустимы")


func _test_states(t) -> void:
	t.set_case("states")
	var reg = R.new()
	reg.setup_new_run()
	var folder_id := _default_folder_id(reg)
	var now := 1000.0

	var failed = reg.create_file("Сбой", "text", folder_id)
	t.ok(reg.mark_failed(failed.id), "mark_failed")
	t.eq(str(failed.location), "failed", "location failed")
	t.ok(not reg.attach_file(failed.id, "req_f", now), "failed нельзя attach")
	t.ok(not reg.get_available_files(now).has(failed), "failed не в available")
	t.ok(not reg.get_pending_files().has(failed), "failed не в pending")

	var malicious = reg.create_file("Вирус", "text", folder_id)
	t.ok(reg.mark_malicious(malicious.id, "virus"), "mark_malicious")
	t.eq(str(malicious.location), "malicious", "location malicious")
	t.eq(str(malicious.malicious_kind), "virus", "malicious_kind")
	t.ok(not reg.attach_file(malicious.id, "req_m", now), "malicious нельзя attach")

	var locked = reg.create_file("Заблокирован", "text", folder_id)
	t.ok(reg.lock_file(locked.id, 10.0, now), "lock")
	t.eq(str(locked.location), "locked", "location locked")
	t.ok(not reg.attach_file(locked.id, "req_l", now + 5.0), "locked нельзя attach до истечения")
	t.ok(not reg.move_file(locked.id, reg.create_folder("C", "Куда").id), "locked нельзя move")
	t.eq(int(reg.tick(now + 10.0)), 1, "tick снял один lock")
	t.eq(str(locked.location), "folder", "после tick location folder")
	t.ok(reg.attach_file(locked.id, "req_l", now + 10.0), "после unlock attach разрешён")

	reg.detach_file(locked.id)
	t.ok(reg.set_cooldown(locked.id, 5.0, now + 10.0), "set_cooldown")
	t.ok(not reg.attach_file(locked.id, "req_c", now + 12.0), "cooldown блокирует attach")
	t.ok(reg.attach_file(locked.id, "req_c", now + 15.0), "после cooldown attach разрешён")
	reg.tick(now + 15.0)
	t.eq(int(reg.tick(now + 20.0)), 0, "tick без изменений")


func _test_remove(t) -> void:
	t.set_case("remove")
	var reg = R.new()
	reg.setup_new_run()
	var folder_id := _default_folder_id(reg)

	var normal = reg.create_file("Обычный", "text", folder_id)
	t.ok(not reg.remove_file(normal.id), "обычный файл удалить нельзя")
	t.ok(not reg.destroy_malicious(normal.id), "destroy_malicious обычного — false")

	var failed = reg.create_file("Сломанный", "text", folder_id)
	reg.mark_failed(failed.id)
	t.ok(reg.remove_file(failed.id), "failed удалить можно")
	t.ok(not reg.files.has(failed.id), "failed удалён из словаря")
	t.ok(not reg.folders[folder_id].file_ids.has(failed.id), "failed убран из папки")

	var bad = reg.create_file("Зловред", "text", folder_id)
	reg.mark_malicious(bad.id, "junk")
	t.ok(reg.destroy_malicious(bad.id), "destroy_malicious работает")
	t.ok(not reg.files.has(bad.id), "malicious удалён")

	var bad2 = reg.create_file("Зловред 2", "text", folder_id)
	reg.mark_malicious(bad2.id, "phishing")
	t.ok(reg.remove_file(bad2.id), "remove_file для malicious работает")

	var empty = reg.create_folder("C", "Пустая")
	t.ok(empty != null, "пустая папка создана")
	t.ok(reg.delete_folder(empty.id), "пустую папку удалить можно")
	t.ok(not reg.folders.has(empty.id), "папка удалена")

	var reg2 = R.new()
	reg2.setup_new_run()
	var default_id := _default_folder_id(reg2)
	t.ok(reg2.delete_folder(default_id), "пустую «Разное» удалить можно")
	t.ok(not reg2.folders.has(default_id), "«Разное» удалена")


func _test_reserve(t) -> void:
	t.set_case("reserve")
	var reg = R.new()
	reg.setup_new_run()
	var folder_id := _default_folder_id(reg)
	var folder = reg.folders[folder_id]

	for i in range(15):
		t.ok(reg.create_file("Рез %02d" % i, "text", folder_id) != null, "файл %d" % i)
	t.eq(int(folder.count()), 15, "15 файлов")
	t.ok(reg.reserve_slot(folder_id), "первый reserve")
	t.eq(int(folder.reserved), 1, "reserved=1")
	t.ok(not reg.reserve_slot(folder_id), "16-й слот зарезервировать нельзя")
	t.ok(reg.create_file("Не пролезет", "text", folder_id) == null, "файл при reserve не влезает")
	t.ok(reg.release_slot(folder_id), "release")
	t.eq(int(folder.reserved), 0, "reserved=0")
	t.ok(reg.reserve_slot(folder_id), "reserve снова")
	t.ok(reg.create_file("Тоже не влезет", "text", folder_id) == null, "резерв всё ещё держит слот")
	t.ok(reg.release_slot(folder_id), "release второй")
	t.ok(reg.create_file("Шестнадцатый", "text", folder_id) != null, "16-й файл создан")
	t.ok(reg.create_file("Семнадцатый", "text", folder_id) == null, "17-й файл отклонён")
	t.ok(not reg.reserve_slot(folder_id), "reserve при полной папке — false")
	t.ok(not reg.reserve_slot("fold_nope"), "reserve несуществующей папки")
	t.ok(not reg.release_slot("fold_nope"), "release несуществующей папки")
	t.ok(not reg.release_slot(folder_id), "release без резерва — false")

	var reserved_folder = reg.create_folder("C", "Резервная")
	t.ok(reg.reserve_slot(reserved_folder.id), "reserve в пустой папке")
	t.ok(not reg.delete_folder(reserved_folder.id), "папку с резервом удалять нельзя")
	reg.release_slot(reserved_folder.id)
	t.ok(reg.delete_folder(reserved_folder.id), "после release папка удаляется")


func _test_roundtrip(t) -> void:
	t.set_case("save/load")
	var reg = R.new()
	reg.setup_new_run()
	var folder_id := _default_folder_id(reg)
	var a = reg.create_file("Файл A", "text", folder_id)
	var b = reg.create_file("Файл B", "photo", folder_id)
	var c = reg.create_file("Файл C", "sound", "", &"registry")
	var d = reg.create_file("Файл D", "video", folder_id)
	reg.attach_file(b.id, "req_7", 1000.0)
	reg.mark_malicious(c.id, "virus")
	reg.mark_failed(d.id)
	reg.lock_file(a.id, 30.0, 1000.0)
	reg.reserve_slot(folder_id)

	t.eq(reg.validate().size(), 0, "инварианты до сохранения")

	var data: Dictionary = reg.to_dict()
	var reg2 = R.new()
	t.ok(reg2.from_dict(data), "from_dict вернул true")
	t.eq(reg2.sections.size(), reg.sections.size(), "секции восстановлены")
	t.eq(reg2.folders.size(), reg.folders.size(), "папки восстановлены")
	t.eq(reg2.files.size(), reg.files.size(), "файлы восстановлены")
	t.eq(str(reg2.files[a.id].location), "locked", "locked сохранён")
	t.ok(float(reg2.files[a.id].lock_until) > 0.0, "lock_until сохранён")
	t.eq(str(reg2.files[b.id].location), "attached", "attached сохранён")
	t.eq(str(reg2.files[b.id].attached_request), "req_7", "attached_request сохранён")
	t.eq(str(reg2.files[c.id].location), "malicious", "malicious сохранён")
	t.eq(str(reg2.files[c.id].malicious_kind), "virus", "malicious_kind сохранён")
	t.eq(str(reg2.files[d.id].location), "failed", "failed сохранён")
	t.eq(int(reg2.folders[folder_id].reserved), 0, "reserved не сохраняется")

	var fresh = reg2.create_file("Новый после load", "text", folder_id)
	t.ok(fresh != null, "create_file после load")
	t.ok(not reg.files.has(fresh.id), "id не пересекается со старыми")
	t.eq(reg2.validate().size(), 0, "инварианты после load: %s" % str(reg2.validate()))

	var broken = R.new()
	t.ok(not broken.from_dict({}), "пустой dict не загружается")


func _test_signals(t) -> void:
	t.set_case("signals")
	_hits.clear()
	var reg = R.new()
	reg.file_added.connect(_on_file_added)
	reg.file_removed.connect(_on_file_removed)
	reg.file_changed.connect(_on_file_changed)
	reg.folder_added.connect(_on_folder_added)
	reg.folder_removed.connect(_on_folder_removed)
	reg.registry_changed.connect(_on_registry_changed)

	reg.setup_new_run()
	var folder_id := _default_folder_id(reg)
	t.eq(int(_hits.get("folder_added", 0)), 1, "folder_added на старте")
	var file = reg.create_file("Сигнал", "text", folder_id)
	t.eq(int(_hits.get("file_added", 0)), 1, "file_added")
	t.ok(int(_hits.get("registry_changed", 0)) >= 2, "registry_changed")
	reg.attach_file(file.id, "req", 1000.0)
	t.eq(int(_hits.get("file_changed", 0)), 1, "file_changed при attach")
	reg.detach_file(file.id)
	t.eq(int(_hits.get("file_changed", 0)), 2, "file_changed при detach")
	reg.mark_malicious(file.id, "junk")
	reg.destroy_malicious(file.id)
	t.eq(int(_hits.get("file_removed", 0)), 1, "file_removed")
	var empty = reg.create_folder("C", "Временная")
	reg.delete_folder(empty.id)
	t.eq(int(_hits.get("folder_removed", 0)), 1, "folder_removed")


# --- служебное -------------------------------------------------------------

func _default_folder_id(reg) -> String:
	var section = reg.sections.get("C", null)
	if section == null or section.folder_ids.is_empty():
		return ""
	return str(section.folder_ids[0])


func _folder_count(reg, section_id: String) -> int:
	var n := 0
	for folder in reg.folders.values():
		if str(folder.section) == section_id:
			n += 1
	return n


func _on_file_added(_file) -> void:
	_bump("file_added")


func _on_file_removed(_file) -> void:
	_bump("file_removed")


func _on_file_changed(_file) -> void:
	_bump("file_changed")


func _on_folder_added(_folder) -> void:
	_bump("folder_added")


func _on_folder_removed(_folder) -> void:
	_bump("folder_removed")


func _on_registry_changed() -> void:
	_bump("registry_changed")


func _bump(key: String) -> void:
	_hits[key] = int(_hits.get(key, 0)) + 1
