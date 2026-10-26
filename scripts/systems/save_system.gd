class_name SaveManager
extends RefCounted
## Атомарное сохранение в user://save.json (без секретов).
##
## Схема: пишем во временный файл, затем rename; после записи читаем обратно
## и проверяем версию. На web вызываем force_fs_sync(), чтобы IndexedDB
## успел синхронизироваться.

const SAVE_PATH := "user://save.json"
const TMP_PATH := "user://save.tmp"
## v2: клеточные сетки/фигуры. v1 читается для миграции (Game/FileRegistry).
const VERSION := 2
const SUPPORTED_VERSIONS: Array[int] = [1, 2]


static func save(data: Dictionary) -> bool:
	var payload := data.duplicate(true)
	payload["version"] = VERSION
	payload["timestamp"] = Time.get_unix_time_from_system()
	var text := JSON.stringify(payload, "\t")

	var file := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("SaveManager: не удалось открыть %s (код %s)" % [TMP_PATH, FileAccess.get_open_error()])
		return false
	file.store_string(text)
	file.flush()
	file.close()

	if not _replace_file(TMP_PATH, SAVE_PATH):
		# Резервный путь: прямая перезапись, если rename не поддерживается.
		var direct := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if direct == null:
			push_warning("SaveManager: не удалось записать %s" % SAVE_PATH)
			_remove_if_exists(TMP_PATH)
			return false
		direct.store_string(text)
		direct.flush()
		direct.close()
		_remove_if_exists(TMP_PATH)

	_web_fs_sync()

	var check := _read_save()
	if check.is_empty() or int(check.get("version", 0)) != VERSION:
		push_warning("SaveManager: проверка после записи не прошла")
		return false
	return true


static func load() -> Dictionary:
	return _read_save()


static func _read_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("SaveManager: не удалось открыть %s (код %s)" % [SAVE_PATH, FileAccess.get_open_error()])
		return {}
	var text := file.get_as_text()
	file.close()
	var parser := JSON.new()
	var err := parser.parse(text)
	if err != OK:
		push_warning("SaveManager: %s повреждён (строка %d: %s)" % [SAVE_PATH, parser.get_error_line(), parser.get_error_message()])
		return {}
	var parsed = parser.data
	if not (parsed is Dictionary):
		push_warning("SaveManager: %s повреждён (не JSON-объект)" % SAVE_PATH)
		return {}
	var data: Dictionary = parsed
	var version := int(data.get("version", -1))
	if not SUPPORTED_VERSIONS.has(version):
		push_warning("SaveManager: версия save %d не поддерживается (ожидается %d)" % [version, VERSION])
		return {}
	return data


static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## Можно ли продолжить забег: файл читается и забег ещё не завершён.
## Не мутирует Game и не меняет сейв — только решает, показывать ли «Продолжить».
static func can_continue() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var data := _read_save()
	if data.is_empty():
		return false
	var registry = data.get("registry", null)
	if not (registry is Dictionary):
		return false
	if str(data.get("phase", "")) == "results":
		return false
	if float(data.get("sla", 0.0)) <= 0.0:
		return false
	# Должно совпадать с GameController.HOURS_PER_RUN (9): 9-й час — финал.
	if int(data.get("hour", 0)) > 9:
		return false
	return true


static func delete_save() -> bool:
	return _remove_if_exists(SAVE_PATH)


# --- служебное -------------------------------------------------------------

static func _replace_file(from_path: String, to_path: String) -> bool:
	var err := DirAccess.rename_absolute(from_path, to_path)
	if err != OK:
		_remove_if_exists(to_path)
		err = DirAccess.rename_absolute(from_path, to_path)
	return err == OK


static func _remove_if_exists(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(path) == OK


static func _web_fs_sync() -> void:
	if not OS.has_feature("web"):
		return
	if not Engine.has_singleton("JavaScriptBridge"):
		return
	var bridge = Engine.get_singleton("JavaScriptBridge")
	if bridge != null and bridge.has_method("force_fs_sync"):
		bridge.force_fs_sync()
