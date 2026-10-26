extends SceneTree
## Тесты SaveManager v2: v2 roundtrip, приём v1, отклонение v3, атомарность.
##
## Standalone:  godot --headless --path . --script tests/test_save.gd
## Harness:     tests/run_tests.gd вызывает run(self).

const S := preload("res://scripts/systems/save_system.gd")
const R := preload("res://scripts/core/file_registry.gd")

var _checks: int = 0
var _fails: int = 0
var _case: String = ""
var _had_save: bool = false
var _backup: String = ""


func _init() -> void:
	if Engine.get_main_loop() != null:
		return
	await process_frame
	run(self)
	print("test_save: проверок %d, провалов %d" % [_checks, _fails])
	print("PASS test_save" if _fails == 0 else "FAIL test_save")
	quit(0 if _fails == 0 else 1)


func run(t) -> void:
	_backup_save()
	_test_version(t)
	_test_roundtrip(t)
	_test_corrupt(t)
	_test_versions(t)
	_test_registry_v2_roundtrip(t)
	_test_udp_shop_save(t)
	_test_delete(t)
	_restore_save()


# --- версия -----------------------------------------------------------------

func _test_version(t) -> void:
	t.set_case("version")
	t.eq(int(S.VERSION), 2, "SaveManager.VERSION = 2")
	t.ok(S.SUPPORTED_VERSIONS.has(1), "v1 поддерживается для миграции")
	t.ok(S.SUPPORTED_VERSIONS.has(2), "v2 поддерживается")


# --- базовый roundtrip ------------------------------------------------------

func _test_roundtrip(t) -> void:
	t.set_case("roundtrip")
	t.ok(S.save({
		"money": 321,
		"sla": 60.0,
		"name": "Смена",
		"nested": {"a": [1, 2, 3], "b": true},
		"upgrades": {"shop_channel": 2},
	}), "save вернул true")
	t.ok(S.has_save(), "has_save после записи")
	t.ok(not FileAccess.file_exists(S.TMP_PATH), "временный файл убран")

	var got: Dictionary = S.load()
	t.eq(int(got.get("version", 0)), 2, "version = 2")
	t.ok(got.has("timestamp"), "timestamp")
	t.eq(int(got.get("money", 0)), 321, "money")
	t.approx(float(got.get("sla", 0.0)), 60.0, 0.0001, "sla")
	t.eq(str(got.get("name", "")), "Смена", "кириллица")
	var nested = got.get("nested", {})
	t.ok(nested is Dictionary, "вложенный словарь")
	if nested is Dictionary:
		var arr = nested.get("a", [])
		t.ok(arr is Array, "вложенный массив")
		if arr is Array:
			t.eq(int(arr[1]), 2, "элемент массива")
		t.eq(bool(nested.get("b", false)), true, "bool")


# --- битый json -------------------------------------------------------------

func _test_corrupt(t) -> void:
	t.set_case("corrupt")
	_write("{ это не json")
	var corrupt: Dictionary = S.load()
	t.eq(corrupt.size(), 0, "битый JSON → {}")
	t.ok(S.has_save(), "битый файл существует")
	t.ok(S.save({"money": 5}), "save поверх битого файла")
	t.eq(int(S.load().get("money", 0)), 5, "данные восстановлены")


# --- версии -----------------------------------------------------------------

func _test_versions(t) -> void:
	t.set_case("versions")
	_write(JSON.stringify({"version": 1, "money": 77, "registry": {}}))
	var v1: Dictionary = S.load()
	t.eq(int(v1.get("version", 0)), 1, "v1 принимается")
	t.eq(int(v1.get("money", 0)), 77, "данные v1 доступны")

	_write(JSON.stringify({"version": 3, "money": 1}))
	t.eq(S.load().size(), 0, "v3 отклоняется")
	_write(JSON.stringify({"version": 0, "money": 1}))
	t.eq(S.load().size(), 0, "v0 отклоняется")
	_write(JSON.stringify({"money": 1}))
	t.eq(S.load().size(), 0, "нет version → {}")
	_write("[]")
	t.eq(S.load().size(), 0, "JSON-массив → {}")
	_write("null")
	t.eq(S.load().size(), 0, "JSON null → {}")


# --- v2: реестр целиком -----------------------------------------------------

func _test_registry_v2_roundtrip(t) -> void:
	t.set_case("registry_v2")
	var reg = R.new()
	reg.setup_new_run()
	var section = reg.sections.get("C", null)
	var folder_id := ""
	if section != null and not section.folder_ids.is_empty():
		folder_id = str(section.folder_ids[0])
	t.ok(not folder_id.is_empty(), "стартовая папка есть")

	var text = reg.create_file("Сейв-текст", "text", folder_id, &"folder", 7)
	t.ok(text != null, "text создан")
	var video = reg.create_file("Сейв-видео", "video", folder_id)
	t.ok(video != null, "video создан")
	# Зафиксируем точную позицию/поворот для проверки roundtrip.
	if video != null:
		video.shape_id = "I4V"
		t.ok(reg.move_file(video.id, folder_id, Vector2i(1, 0), 0), "видео поставлено вручную")
	if text != null:
		t.ok(reg.move_file(text.id, folder_id, Vector2i(0, 0), 0), "текст поставлен вручную")

	var table_file = reg.create_file("Стол", "text", "", &"table")
	t.ok(table_file != null, "файл на столе создан")
	if text != null:
		t.eq(int(text.icon_id), 7, "icon_id задан при создании")
		text.hours_lived = 3
	if video != null:
		t.ok(int(video.icon_id) >= 0 and int(video.icon_id) < R.FILE_ICON_COUNT,
			"create_file: icon_id в 0..63 (%d)" % int(video.icon_id))

	t.eq(reg.validate().size(), 0, "реестр валиден до save")
	var payload := {
		"version": S.VERSION,
		"money": 100,
		"registry": reg.to_dict(),
	}
	t.ok(S.save(payload), "save payload v2")
	var loaded: Dictionary = S.load()
	t.eq(int(loaded.get("version", 0)), 2, "загружена версия 2")
	var raw_registry = loaded.get("registry", {})
	t.ok(raw_registry is Dictionary, "registry в save")
	if raw_registry is Dictionary:
		var reg2 = R.new()
		t.ok(reg2.from_dict(raw_registry), "from_dict сохранённого registry")
		t.eq(reg2.files.size(), reg.files.size(), "файлы восстановлены")
		if video != null:
			t.eq(reg2.file_origin(video.id), Vector2i(1, 0), "origin видео сохранён")
			t.eq(str(reg2.get_file(video.id).shape_id), "I4V", "shape_id видео сохранён")
		if text != null:
			t.eq(int(reg2.get_file(text.id).icon_id), 7, "icon_id сохранён roundtrip")
			t.eq(int(reg2.get_file(text.id).hours_lived), 3, "hours_lived сохранён roundtrip")
		if table_file != null:
			t.eq(str(reg2.get_file(table_file.id).location), "table", "location table сохранён")
		t.eq(reg2.validate().size(), 0, "registry после load валиден: %s" % str(reg2.validate()))

		# Старый сейв без hours_lived: файл считается новым (0).
		var legacy_raw: Dictionary = (raw_registry as Dictionary).duplicate(true)
		var legacy_files = legacy_raw.get("files", {})
		if legacy_files is Dictionary:
			for meta in (legacy_files as Dictionary).values():
				if meta is Dictionary:
					(meta as Dictionary).erase("hours_lived")
		var reg_legacy = R.new()
		t.ok(reg_legacy.from_dict(legacy_raw), "from_dict старого сейва без hours_lived")
		if text != null:
			var legacy_text = reg_legacy.get_file(text.id)
			t.ok(legacy_text != null, "старый файл восстановлен")
			if legacy_text != null:
				t.eq(int(legacy_text.hours_lived), 0, "старый сейв: hours_lived = 0")


# --- v3: UDP-лот в сейве ----------------------------------------------------

## Старый сейв без lot_udp/udp_level читается как 40%; новый сейв сохраняет
## уровень лота и шанс 40% + 10%×уровень.
func _test_udp_shop_save(t) -> void:
	t.set_case("udp_shop_save")
	var loop = Engine.get_main_loop()
	var game = null
	if loop is SceneTree:
		game = (loop as SceneTree).root.get_node_or_null("Game")
	t.ok(game != null, "Game autoload доступен")
	if game == null:
		return

	game.start_new_run(321)
	# Старый формат: в upgrades нет ни lot_udp, ни агрегата udp_level.
	var old_payload := {
		"version": S.VERSION,
		"money": 100,
		"sla": 60.0,
		"hour": 1,
		"phase": "prep",
		"upgrades": {"lot_speed": 1, "speed_level": 1},
		"registry": game.registry.to_dict(),
	}
	t.ok(S.save(old_payload), "save старого сейва без lot_udp")
	t.ok(game.load_game(), "load старого сейва")
	t.eq(game.level("lot_udp"), 0, "старого lot_udp нет → уровень 0")
	t.eq(game.level("udp_level"), 0, "старого udp_level нет → 0")
	t.approx(game.udp_success_chance(), 0.40, 0.0001, "старый сейв → 40%")

	# Новый сейв: уровень лота пишется в оба ключа и переживает load.
	game.set_lot_level("lot_udp", 2)
	t.eq(game.level("lot_udp"), 2, "lot_udp = 2")
	t.eq(game.level("udp_level"), 2, "агрегат udp_level = 2")
	t.approx(game.udp_success_chance(), 0.60, 0.0001, "перед save 60%")
	t.ok(game.save_game(), "save_game с lot_udp")
	game.upgrades.clear()
	t.approx(game.udp_success_chance(), 0.40, 0.0001, "после очистки снова 40%")
	t.ok(game.load_game(), "load_game с lot_udp")
	t.eq(game.level("lot_udp"), 2, "уровень lot_udp восстановлен")
	t.eq(game.level("udp_level"), 2, "агрегат udp_level восстановлен")
	t.approx(game.udp_success_chance(), 0.60, 0.0001, "после load 60%")


# --- delete -----------------------------------------------------------------

func _test_delete(t) -> void:
	t.set_case("delete")
	t.ok(S.delete_save(), "delete_save")
	t.ok(not S.has_save(), "после delete_save файла нет")
	t.ok(not S.delete_save(), "повторный delete_save — false")


# --- служебное --------------------------------------------------------------

func _backup_save() -> void:
	_had_save = FileAccess.file_exists(S.SAVE_PATH)
	if _had_save:
		_backup = FileAccess.get_file_as_string(S.SAVE_PATH)


func _restore_save() -> void:
	if _had_save:
		var file = FileAccess.open(S.SAVE_PATH, FileAccess.WRITE)
		if file != null:
			file.store_string(_backup)
			file.flush()
			file.close()
	else:
		S.delete_save()
	if FileAccess.file_exists(S.TMP_PATH):
		DirAccess.remove_absolute(S.TMP_PATH)


func _write(text: String) -> void:
	var file = FileAccess.open(S.SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.flush()
		file.close()


# --- assert-хелперы ---------------------------------------------------------

func set_case(name: String) -> void:
	_case = name


func ok(condition: bool, message: String) -> bool:
	_checks += 1
	if condition:
		return true
	fail(message + " — ожидалось true")
	return false


func eq(actual, expected, message: String) -> bool:
	_checks += 1
	if actual == expected:
		return true
	fail("%s — получено %s, ожидалось %s" % [message, str(actual), str(expected)])
	return false


func approx(actual: float, expected: float, eps: float, message: String) -> bool:
	_checks += 1
	if absf(float(actual) - float(expected)) <= eps:
		return true
	fail("%s — получено %.6f, ожидалось %.6f" % [message, actual, expected])
	return false


func fail(message: String) -> void:
	_fails += 1
	print("FAIL [%s] %s" % [_case, message])
