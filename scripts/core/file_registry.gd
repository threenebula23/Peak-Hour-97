class_name FileRegistry
extends RefCounted
## Реестр склада: секции, папки, файлы и их состояния.
##
## ВАЖНО: global class cache при `--script` может быть пустым, поэтому
## свои классы подключаем через preload, а не по имени.

signal file_added(file)
signal file_removed(file)
signal file_changed(file)
signal folder_added(folder)
signal folder_removed(folder)
signal folder_changed(folder)
signal registry_changed

const MAX_SECTIONS := 6
const MAX_FOLDERS_PER_SECTION := 12
const MAX_FILES_PER_FOLDER := 16
const MAX_FOLDER_NAME := 16
const SECTION_LETTERS: Array[String] = ["C", "D", "E", "F", "G", "H"]

const FILE_ITEM_SCRIPT := preload("res://scripts/entities/file_item.gd")
const FOLDER_SCRIPT := preload("res://scripts/entities/folder.gd")
const SECTION_SCRIPT := preload("res://scripts/entities/section.gd")

## Тип -> расширение/размер по умолчанию (если Data недоступен).
const TYPE_INFO := {
	"text": {"ext": "txt", "size_kb": 64},
	"sound": {"ext": "mp3", "size_kb": 3072},
	"photo": {"ext": "jpg", "size_kb": 5120},
	"video": {"ext": "mp4", "size_kb": 20480},
}
const DEFAULT_TYPE_INFO := {"ext": "bin", "size_kb": 128}

var sections: Dictionary = {}
var folders: Dictionary = {}
var files: Dictionary = {}
var rng_seed: int = 0

var _next_folder_id: int = 1
var _next_file_id: int = 1


# --- новая смена -----------------------------------------------------------

## Чистый склад: секция C, папка «Разное», файлов нет.
func setup_new_run() -> void:
	sections.clear()
	folders.clear()
	files.clear()
	_next_folder_id = 1
	_next_file_id = 1
	var section = create_section("C")
	if section != null:
		create_folder(section.id, "Разное")
	registry_changed.emit()


# --- секции ----------------------------------------------------------------

func create_section(letter: String):
	var clean := letter.strip_edges().to_upper()
	if clean.length() != 1:
		return null
	if not SECTION_LETTERS.has(clean):
		return null
	if sections.has(clean):
		return null
	if sections.size() >= MAX_SECTIONS:
		return null
	var section = SECTION_SCRIPT.new()
	section.id = clean
	section.letter = clean
	section.name = "Секция %s" % clean
	sections[clean] = section
	registry_changed.emit()
	return section


func section_count() -> int:
	return sections.size()


# --- папки -----------------------------------------------------------------

## Новые папки допускаются только в рамках лимита 12 на секцию.
func create_folder(section_id: String, name: String):
	var section = sections.get(section_id)
	if section == null:
		return null
	var clean := name.strip_edges()
	if clean.is_empty() or clean.length() > MAX_FOLDER_NAME:
		return null
	if _folder_count_in_section(section_id) >= MAX_FOLDERS_PER_SECTION:
		return null
	if _folder_name_taken(section_id, clean):
		return null
	var folder = FOLDER_SCRIPT.new()
	folder.id = "fold_%d" % _next_folder_id
	_next_folder_id += 1
	folder.section = section_id
	folder.name = clean
	folders[folder.id] = folder
	section.folder_ids.append(folder.id)
	folder_added.emit(folder)
	registry_changed.emit()
	return folder


func rename_folder(folder_id: String, new_name: String) -> bool:
	var folder = folders.get(folder_id)
	if folder == null:
		return false
	var clean := new_name.strip_edges()
	if clean.is_empty() or clean.length() > MAX_FOLDER_NAME:
		return false
	if clean == folder.name:
		return true
	if _folder_name_taken(folder.section, clean):
		return false
	folder.name = clean
	folder_changed.emit(folder)
	registry_changed.emit()
	return true


## Удалить можно только пустую папку без резерваций.
func delete_folder(folder_id: String) -> bool:
	var folder = folders.get(folder_id)
	if folder == null:
		return false
	if folder.count() > 0 or folder.reserved > 0:
		return false
	for f in files.values():
		if f.folder_id == folder_id:
			return false
	var section = sections.get(folder.section)
	if section != null:
		section.folder_ids.erase(folder_id)
	folders.erase(folder_id)
	folder_removed.emit(folder)
	registry_changed.emit()
	return true


func folder_count() -> int:
	return folders.size()


func _folder_count_in_section(section_id: String) -> int:
	var n := 0
	for folder in folders.values():
		if folder.section == section_id:
			n += 1
	return n


func _folder_name_taken(section_id: String, name: String) -> bool:
	var probe := name.to_lower()
	for folder in folders.values():
		if folder.section == section_id and folder.name.to_lower() == probe:
			return true
	return false


# --- файлы -----------------------------------------------------------------

## Создать файл. Имя уникально в пределах забега (без учёта регистра).
## Возвращает null при дубле, неверной папке или переполнении.
func create_file(name: String, type: String, folder_id: String, location: StringName = &"folder"):
	var clean := name.strip_edges()
	if clean.is_empty():
		return null
	if find_by_name(clean) != null:
		return null
	if location != &"folder" and location != &"registry":
		return null
	var actual_folder := ""
	if location == &"folder":
		var folder = folders.get(folder_id)
		if folder == null:
			return null
		if not folder.has_free_slot(MAX_FILES_PER_FOLDER):
			return null
		actual_folder = folder_id
	var info := _type_info(type)
	var file = FILE_ITEM_SCRIPT.new()
	file.id = "file_%d" % _next_file_id
	_next_file_id += 1
	file.name = clean
	file.type = type
	file.ext = FILE_ITEM_SCRIPT.normalize_ext(str(info.get("ext", "")))
	file.folder_id = actual_folder
	file.location = location
	file.size_kb = int(info.get("size_kb", 0))
	file.created_at = FILE_ITEM_SCRIPT.now_unix()
	files[file.id] = file
	if not actual_folder.is_empty():
		var folder = folders[actual_folder]
		folder.file_ids.append(file.id)
		folder_changed.emit(folder)
	file_added.emit(file)
	registry_changed.emit()
	return file


func move_file(file_id: String, folder_id: String) -> bool:
	var file = files.get(file_id)
	if file == null:
		return false
	if file.location != &"folder" and file.location != &"registry":
		return false
	if not file.attached_request.is_empty():
		return false
	var target = folders.get(folder_id)
	if target == null:
		return false
	if file.folder_id == folder_id and file.location == &"folder":
		return true
	var occupied: int = int(target.count())
	if file.folder_id == folder_id:
		occupied -= 1
	if occupied + target.reserved >= MAX_FILES_PER_FOLDER:
		return false
	if not file.folder_id.is_empty():
		var old = folders.get(file.folder_id)
		if old != null:
			old.file_ids.erase(file_id)
			folder_changed.emit(old)
	target.file_ids.append(file_id)
	file.folder_id = folder_id
	file.location = &"folder"
	file_changed.emit(file)
	folder_changed.emit(target)
	registry_changed.emit()
	return true


## Удалять можно только malicious/failed. Обычные файлы — нет (D02).
func remove_file(file_id: String) -> bool:
	var file = files.get(file_id)
	if file == null:
		return false
	if file.location != &"malicious" and file.location != &"failed":
		return false
	_detach_from_folder(file)
	files.erase(file_id)
	file_removed.emit(file)
	registry_changed.emit()
	return true


func destroy_malicious(file_id: String) -> bool:
	var file = files.get(file_id)
	if file == null or file.location != &"malicious":
		return false
	return remove_file(file_id)


# --- слоты загрузки --------------------------------------------------------

## Зарезервировать слот под незавершённую загрузку.
func reserve_slot(folder_id: String) -> bool:
	var folder = folders.get(folder_id)
	if folder == null:
		return false
	if folder.count() + folder.reserved >= MAX_FILES_PER_FOLDER:
		return false
	folder.reserved += 1
	folder_changed.emit(folder)
	registry_changed.emit()
	return true


func release_slot(folder_id: String) -> bool:
	var folder = folders.get(folder_id)
	if folder == null:
		return false
	if folder.reserved <= 0:
		return false
	folder.reserved -= 1
	folder_changed.emit(folder)
	registry_changed.emit()
	return true


# --- прикрепление к запросам ----------------------------------------------

## Прикрепить файл к запросу. Файл остаётся в папке, меняется location.
func attach_file(file_id: String, request_id: String, now: float = -1.0) -> bool:
	var file = files.get(file_id)
	if file == null:
		return false
	if request_id.is_empty():
		return false
	if not file.attached_request.is_empty():
		return false
	if not file.can_attach(now):
		return false
	file.attached_request = request_id
	file.location = &"attached"
	file_changed.emit(file)
	registry_changed.emit()
	return true


func detach_file(file_id: String) -> bool:
	var file = files.get(file_id)
	if file == null:
		return false
	if file.location != &"attached" and file.attached_request.is_empty():
		return false
	file.attached_request = ""
	if not file.folder_id.is_empty() and folders.has(file.folder_id):
		file.location = &"folder"
	else:
		file.location = &"registry"
		file.folder_id = ""
	file_changed.emit(file)
	registry_changed.emit()
	return true


# --- состояния -------------------------------------------------------------

func mark_failed(file_id: String) -> bool:
	var file = files.get(file_id)
	if file == null:
		return false
	file.location = &"failed"
	file.attached_request = ""
	file.lock_until = 0.0
	file.cooldown_until = 0.0
	file._location_before_lock = &"folder" if not file.folder_id.is_empty() else &"registry"
	file_changed.emit(file)
	registry_changed.emit()
	return true


func mark_malicious(file_id: String, kind: String) -> bool:
	var file = files.get(file_id)
	if file == null:
		return false
	file.location = &"malicious"
	file.malicious_kind = kind
	file.attached_request = ""
	file.lock_until = 0.0
	file.cooldown_until = 0.0
	file._location_before_lock = &"folder" if not file.folder_id.is_empty() else &"registry"
	file_changed.emit(file)
	registry_changed.emit()
	return true


func lock_file(file_id: String, seconds: float, now: float = -1.0) -> bool:
	var file = files.get(file_id)
	if file == null:
		return false
	if file.location == &"failed" or file.location == &"malicious":
		return false
	if now < 0.0:
		now = FILE_ITEM_SCRIPT.now_unix()
	if file.location == &"folder" or file.location == &"registry":
		file._location_before_lock = file.location
	if file.location == &"attached":
		file.attached_request = ""
	file.location = &"locked"
	file.lock_until = now + maxf(0.0, seconds)
	file_changed.emit(file)
	registry_changed.emit()
	return true


func unlock_file(file_id: String) -> bool:
	var file = files.get(file_id)
	if file == null or file.location != &"locked":
		return false
	var prev: StringName = file._location_before_lock
	if prev != &"folder" and prev != &"registry":
		prev = &"folder" if not file.folder_id.is_empty() else &"registry"
	if prev == &"folder" and not folders.has(file.folder_id):
		prev = &"registry"
	file.location = prev
	file.lock_until = 0.0
	if prev == &"registry":
		file.folder_id = ""
	file_changed.emit(file)
	registry_changed.emit()
	return true


## Выставить cooldown после успешной отправки (D02, 20 с).
func set_cooldown(file_id: String, seconds: float, now: float = -1.0) -> bool:
	var file = files.get(file_id)
	if file == null:
		return false
	if now < 0.0:
		now = FILE_ITEM_SCRIPT.now_unix()
	file.cooldown_until = now + maxf(0.0, seconds)
	file_changed.emit(file)
	registry_changed.emit()
	return true


## Снять истёкшие lock/cooldown. Возвращает число изменённых файлов.
func tick(now: float) -> int:
	var changed := 0
	for file_id in files.keys():
		var file = files[file_id]
		if file.lock_until > 0.0 and now >= file.lock_until:
			if unlock_file(file_id):
				changed += 1
			continue
		if file.cooldown_until > 0.0 and now >= file.cooldown_until:
			file.cooldown_until = 0.0
			file_changed.emit(file)
			registry_changed.emit()
			changed += 1
	return changed


# --- выборки ---------------------------------------------------------------

func get_folder_files(folder_id: String) -> Array:
	var out: Array = []
	var folder = folders.get(folder_id)
	if folder == null:
		return out
	for file_id in folder.file_ids:
		if files.has(file_id):
			out.append(files[file_id])
	return out


func get_available_files(now: float = -1.0) -> Array:
	var out: Array = []
	for file in files.values():
		if file.is_available(now):
			out.append(file)
	return out


## Файлы, полученные, но ещё не разложенные по папкам (location == registry).
func get_pending_files() -> Array:
	var out: Array = []
	for file in files.values():
		if file.location == &"registry":
			out.append(file)
	return out


func find_by_name(name: String):
	var probe := name.strip_edges().to_lower()
	if probe.is_empty():
		return null
	for file in files.values():
		if file.name.to_lower() == probe or file.display_name().to_lower() == probe:
			return file
	return null


func all_files() -> Array:
	return files.values()


func file_count() -> int:
	return files.size()


func get_file(file_id: String):
	return files.get(file_id)


func get_folder(folder_id: String):
	return folders.get(folder_id)


# --- сохранение ------------------------------------------------------------

func to_dict() -> Dictionary:
	var raw_sections := {}
	for key in sections.keys():
		raw_sections[key] = sections[key].to_dict()
	var raw_folders := {}
	for key in folders.keys():
		raw_folders[key] = folders[key].to_dict()
	var raw_files := {}
	for key in files.keys():
		raw_files[key] = files[key].to_dict()
	return {
		"rng_seed": rng_seed,
		"next_folder_id": _next_folder_id,
		"next_file_id": _next_file_id,
		"sections": raw_sections,
		"folders": raw_folders,
		"files": raw_files,
	}


func from_dict(d: Dictionary) -> bool:
	if d == null or d.is_empty():
		return false
	sections.clear()
	folders.clear()
	files.clear()
	rng_seed = int(d.get("rng_seed", 0))
	_next_folder_id = maxi(1, int(d.get("next_folder_id", 1)))
	_next_file_id = maxi(1, int(d.get("next_file_id", 1)))

	var raw_sections := _dict_of(d.get("sections", {}))
	for key in raw_sections.keys():
		var raw = raw_sections[key]
		if not (raw is Dictionary):
			continue
		var section = SECTION_SCRIPT.from_dict(raw)
		if section.id.is_empty():
			section.id = str(key)
		if section.letter.is_empty():
			section.letter = section.id
		sections[section.id] = section

	var raw_folders := _dict_of(d.get("folders", {}))
	for key in raw_folders.keys():
		var raw = raw_folders[key]
		if not (raw is Dictionary):
			continue
		var folder = FOLDER_SCRIPT.from_dict(raw)
		if folder.id.is_empty():
			folder.id = str(key)
		if not sections.has(folder.section):
			continue
		folders[folder.id] = folder

	var raw_files := _dict_of(d.get("files", {}))
	for key in raw_files.keys():
		var raw = raw_files[key]
		if not (raw is Dictionary):
			continue
		var file = FILE_ITEM_SCRIPT.from_dict(raw)
		if file.id.is_empty():
			file.id = str(key)
		files[file.id] = file

	_repair_after_load()
	registry_changed.emit()
	return true


func validate() -> Array:
	var errors: Array = []
	if sections.size() > MAX_SECTIONS:
		errors.append("секций больше %d" % MAX_SECTIONS)

	var folder_membership := {}
	for folder in folders.values():
		if not sections.has(folder.section):
			errors.append("папка %s ссылается на несуществующую секцию" % folder.id)
		if folder.name.strip_edges().is_empty() or folder.name.length() > MAX_FOLDER_NAME:
			errors.append("неверное имя папки %s" % folder.id)
		if folder.count() + folder.reserved > MAX_FILES_PER_FOLDER:
			errors.append("переполнение папки %s" % folder.id)
		var seen := {}
		for file_id in folder.file_ids:
			if not files.has(file_id):
				errors.append("папка %s ссылается на несуществующий файл %s" % [folder.id, file_id])
				continue
			seen[file_id] = int(seen.get(file_id, 0)) + 1
			folder_membership[file_id] = int(folder_membership.get(file_id, 0)) + 1
		for file_id in seen.keys():
			if int(seen[file_id]) > 1:
				errors.append("файл %s дважды в папке %s" % [file_id, folder.id])

	var per_section := {}
	for folder in folders.values():
		per_section[folder.section] = int(per_section.get(folder.section, 0)) + 1
	for section_id in per_section.keys():
		if int(per_section[section_id]) > MAX_FOLDERS_PER_SECTION:
			errors.append("в секции %s больше %d папок" % [section_id, MAX_FOLDERS_PER_SECTION])

	for section in sections.values():
		var seen_ids := {}
		for folder_id in section.folder_ids:
			if not folders.has(folder_id):
				errors.append("секция %s ссылается на несуществующую папку %s" % [section.id, folder_id])
			if seen_ids.has(folder_id):
				errors.append("папка %s дважды в секции %s" % [folder_id, section.id])
			seen_ids[folder_id] = true

	var names := {}
	for file in files.values():
		var probe: String = str(file.name).to_lower()
		if probe.is_empty():
			errors.append("пустое имя файла %s" % file.id)
		if names.has(probe):
			errors.append("дубль имени файла: %s" % file.name)
		names[probe] = true
		if not FILE_ITEM_SCRIPT.LOCATIONS.has(String(file.location)):
			errors.append("неверный location у %s" % file.id)
		if file.location == &"attached":
			if file.attached_request.is_empty():
				errors.append("attached-файл %s без запроса" % file.id)
		elif not file.attached_request.is_empty():
			errors.append("файл %s прикреплён, но location=%s" % [file.id, file.location])
		if file.location == &"failed" and not file.attached_request.is_empty():
			errors.append("failed-файл %s прикреплён" % file.id)
		if file.folder_id.is_empty():
			if int(folder_membership.get(file.id, 0)) != 0:
				errors.append("файл %s без папки, но лежит в folder.file_ids" % file.id)
		else:
			if not folders.has(file.folder_id):
				errors.append("файл %s ссылается на несуществующую папку" % file.id)
			elif int(folder_membership.get(file.id, 0)) != 1:
				errors.append("файл %s должен быть ровно в одной папке" % file.id)
	return errors


# --- служебное -------------------------------------------------------------

func _type_info(file_type: String) -> Dictionary:
	var data = _data_node()
	if data != null and data.has_method("type_def"):
		var def = data.type_def(file_type)
		if def is Dictionary and not def.is_empty():
			return def
	var fallback = TYPE_INFO.get(file_type)
	if fallback is Dictionary:
		return fallback
	return DEFAULT_TYPE_INFO


func _data_node():
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("Data")
	return null


func _detach_from_folder(file) -> void:
	if file.folder_id.is_empty():
		return
	var folder = folders.get(file.folder_id)
	if folder != null:
		folder.file_ids.erase(file.id)
		folder_changed.emit(folder)
	file.folder_id = ""


func _dict_of(value) -> Dictionary:
	if value is Dictionary:
		return value
	return {}


func _repair_after_load() -> void:
	for section in sections.values():
		section.folder_ids.clear()
	for folder in folders.values():
		folder.reserved = 0
		folder.file_ids.clear()
		var section = sections.get(folder.section)
		if section != null:
			section.folder_ids.append(folder.id)

	var max_folder_num := 0
	for folder_id in folders.keys():
		max_folder_num = maxi(max_folder_num, _numeric_suffix(str(folder_id)))
	_next_folder_id = maxi(_next_folder_id, max_folder_num + 1)

	var max_file_num := 0
	for file_id in files.keys():
		max_file_num = maxi(max_file_num, _numeric_suffix(str(file_id)))
	_next_file_id = maxi(_next_file_id, max_file_num + 1)

	for file in files.values():
		var folder = folders.get(file.folder_id) if not file.folder_id.is_empty() else null
		if folder == null:
			file.folder_id = ""
			if file.location == &"folder" or file.location == &"attached" or file.location == &"locked":
				file.location = &"registry"
		else:
			if not folder.file_ids.has(file.id):
				folder.file_ids.append(file.id)
		if file.location == &"attached" and file.attached_request.is_empty():
			file.location = &"folder" if folder != null else &"registry"
		if (file.location == &"failed" or file.location == &"malicious") and not file.attached_request.is_empty():
			file.attached_request = ""
		if file.location == &"locked" and file._location_before_lock != &"folder" and file._location_before_lock != &"registry":
			file._location_before_lock = &"folder" if folder != null else &"registry"


func _numeric_suffix(value: String) -> int:
	var idx := value.rfind("_")
	if idx < 0 or idx + 1 >= value.length():
		return 0
	var tail := value.substr(idx + 1)
	if not tail.is_valid_int():
		return 0
	return int(tail)
