extends RefCounted
## Тесты SaveManager: roundtrip, битый JSON, несовпадение версии, атомарность.

const S := preload("res://scripts/systems/save_system.gd")
const G := preload("res://scripts/autoload/game.gd")

var _had_save: bool = false
var _backup: String = ""


func run(t) -> void:
	_backup_save()
	t.set_case("roundtrip")
	t.ok(S.save({
		"money": 321,
		"sla": 198.5,
		"name": "Смена",
		"nested": {"a": [1, 2, 3], "b": true},
		"upgrades": {"shop_channel": 2},
	}), "save вернул true")
	t.ok(S.has_save(), "has_save после записи")
	t.ok(not FileAccess.file_exists(S.TMP_PATH), "временный файл убран")

	var got: Dictionary = S.load()
	t.eq(int(got.get("version", 0)), S.VERSION, "version")
	t.ok(got.has("timestamp"), "timestamp")
	t.eq(int(got.get("money", 0)), 321, "money")
	t.approx(float(got.get("sla", 0.0)), 198.5, 0.0001, "sla")
	t.eq(str(got.get("name", "")), "Смена", "кириллица")
	var nested = got.get("nested", {})
	t.ok(nested is Dictionary, "вложенный словарь")
	if nested is Dictionary:
		var arr = nested.get("a", [])
		t.ok(arr is Array, "вложенный массив")
		if arr is Array:
			t.eq(int(arr[1]), 2, "элемент массива")
		t.eq(bool(nested.get("b", false)), true, "bool")
	var upgrades = got.get("upgrades", {})
	t.ok(upgrades is Dictionary, "upgrades")
	if upgrades is Dictionary:
		t.eq(int(upgrades.get("shop_channel", 0)), 2, "уровень апгрейда")

	t.set_case("corrupt")
	_write("{ это не json")
	var corrupt: Dictionary = S.load()
	t.eq(corrupt.size(), 0, "битый JSON → {}")
	t.ok(S.has_save(), "битый файл существует")
	t.ok(S.save({"money": 5}), "save поверх битого файла")
	t.eq(int(S.load().get("money", 0)), 5, "данные восстановлены")

	t.set_case("version")
	_write(JSON.stringify({"version": 999, "money": 1}))
	t.eq(S.load().size(), 0, "version mismatch → {}")
	_write(JSON.stringify({"money": 1}))
	t.eq(S.load().size(), 0, "нет version → {}")
	_write("[]")
	t.eq(S.load().size(), 0, "JSON-массив → {}")

	t.set_case("delete")
	t.ok(S.delete_save(), "delete_save")
	t.ok(not S.has_save(), "после delete_save файла нет")
	t.ok(not S.delete_save(), "повторный delete_save — false")

	_test_game_roundtrip(t)
	_restore_save()


# --- служебное -------------------------------------------------------------

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


func _test_game_roundtrip(t) -> void:
	t.set_case("game")
	var game = G.new()
	game.start_new_run(4242)
	t.eq(int(game.money), 150, "стартовые деньги")
	t.approx(float(game.sla), 200.0, 0.0001, "стартовый SLA")
	t.eq(str(game.phase), "prep", "фаза prep")
	t.eq(int(game.rng_seed), 4242, "сид забега")
	var folder_id := ""
	var section = game.registry.sections.get("C", null)
	if section != null and not section.folder_ids.is_empty():
		folder_id = str(section.folder_ids[0])
	t.ok(not folder_id.is_empty(), "стартовая папка в registry")
	t.ok(game.registry.create_file("Сейв-файл", "text", folder_id) != null, "файл в registry")
	game.add_money(100)
	game.add_sla(5.0)
	t.eq(int(game.money), 250, "деньги после add_money")
	t.approx(float(game.sla), 200.0, 0.0001, "SLA после add_sla клампится на 200")

	t.ok(game.save_game(), "Game.save_game")
	var game2 = G.new()
	t.ok(game2.load_game(), "Game.load_game")
	t.eq(int(game2.money), 250, "деньги восстановлены")
	t.approx(float(game2.sla), 200.0, 0.0001, "SLA восстановлен")
	t.eq(str(game2.phase), "prep", "фаза восстановлена")
	t.eq(int(game2.rng_seed), 4242, "сид восстановлен")
	t.eq(game2.registry.files.size(), game.registry.files.size(), "файлы восстановлены")
	t.ok(game2.registry.find_by_name("Сейв-файл") != null, "файл найден после load")
	game.free()
	game2.free()
