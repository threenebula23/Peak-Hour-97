extends Node
## Data — доступ к JSON-данным из res://data (autoload).
##
## Файлы данных сейчас заготовки, поэтому отсутствующие ключи заменяются
## безопасными дефолтами с push_warning; игра не должна падать из-за данных.

const DATA_DIR := "res://data"

const DEFAULT_TYPES := {
	"text": {
		"name_ru": "Текст", "ext": "txt", "icon": "text",
		"recv_time": 2.0, "send_time": 1.5, "recv_fee": 1,
		"base_pay": 80, "weight": 8, "minigame_coeff": 1.0, "size_kb": 64,
		"sla_loss": 2,
	},
	"sound": {
		"name_ru": "Звук", "ext": "mp3", "icon": "sound",
		"recv_time": 3.5, "send_time": 2.5, "recv_fee": 2,
		"base_pay": 140, "weight": 12, "minigame_coeff": 2.0, "size_kb": 3072,
		"sla_loss": 4,
	},
	"photo": {
		"name_ru": "Фото", "ext": "jpg", "icon": "photo",
		"recv_time": 5.0, "send_time": 3.5, "recv_fee": 3,
		"base_pay": 220, "weight": 18, "minigame_coeff": 3.0, "size_kb": 5120,
		"sla_loss": 8,
	},
	"video": {
		"name_ru": "Видео", "ext": "mp4", "icon": "video",
		"recv_time": 8.0, "send_time": 6.0, "recv_fee": 4,
		"base_pay": 380, "weight": 22, "minigame_coeff": 4.0, "size_kb": 20480,
		"sla_loss": 16,
	},
}

## Таблица сложности — до часа 8 (D12); дальше используется последняя строка.
const DEFAULT_DIFFICULTY := [
	{"hour": 1, "max_requests": 2, "spawn_sec": 7.0},
	{"hour": 2, "max_requests": 3, "spawn_sec": 6.5},
	{"hour": 3, "max_requests": 3, "spawn_sec": 6.0},
	{"hour": 4, "max_requests": 4, "spawn_sec": 5.5},
	{"hour": 5, "max_requests": 4, "spawn_sec": 5.0},
	{"hour": 6, "max_requests": 5, "spawn_sec": 4.5},
	{"hour": 7, "max_requests": 5, "spawn_sec": 4.2},
	{"hour": 8, "max_requests": 6, "spawn_sec": 4.0},
]

const DEFAULT_SHOP := [
	{"id": "slot_3", "name": "3-й слот", "cost": 250, "max_level": 1},
	{"id": "slot_4", "name": "4-й слот", "cost": 450, "max_level": 1},
	{"id": "buffer", "name": "Буфер +2", "cost": 200, "max_level": 2},
	{"id": "packet_timer", "name": "Таймер пакетов +4 с", "cost": 350, "max_level": 3},
	{"id": "zone", "name": "Зона +5 %", "cost": 300, "max_level": 3},
	{"id": "channel", "name": "Канал +25", "cost": 250, "max_level": 4},
	{"id": "section", "name": "Секция", "cost": 300, "max_level": 5},
	{"id": "search", "name": "Поиск", "cost": 250, "max_level": 1},
	{"id": "shield", "name": "Щит", "cost": 400, "max_level": 1},
	{"id": "shop_sla", "name": "SLA +24", "effect": "sla_add", "value": 24, "cost": 300, "max_level": 3},
]

## Прогрессия/открытия (дублирует data/balance.json → progression).
const DEFAULT_PROGRESSION := {
	"unlocks": {
		"shop": {"run_hour": 2, "label": "Магазин"},
		"search": {"meta": "survive_hour_3", "label": "Поиск"},
		"shield": {"meta": "survive_hour_5", "label": "Щит"},
		"minigame_text": {"run_hour": 1},
		"minigame_sound": {"run_hour": 2},
		"minigame_photo": {"run_hour": 3},
		"minigame_video": {"run_hour": 4},
		"minigame_advanced": {"meta": "complete_run", "label": "Продвинутые мини-игры"},
		"attack_junk": {"run_hour": 2},
		"attack_ddos": {"run_hour": 2},
		"attack_phishing": {"run_hour": 3},
		"attack_ransomware": {"run_hour": 4},
	},
	"meta_rewards": {
		"survive_hour_3": {"min_hours": 3, "unlocks": ["search"]},
		"survive_hour_5": {"min_hours": 5, "unlocks": ["shield"]},
		"complete_run": {"min_hours": 9, "unlocks": ["minigame_advanced"]},
	},
}

var balance: Dictionary = {}
var types: Dictionary = {}
var difficulty: Array = []
var shop: Array = []
var names: Dictionary = {}
var strings: Dictionary = {}
var unlocks: Dictionary = {}
var meta_rewards: Dictionary = {}

var _cache: Dictionary = {}


func _ready() -> void:
	load_all()


func load_all() -> void:
	_cache.clear()
	balance = load_json("balance.json")
	types = _merge_types(balance.get("types", null))
	difficulty = _load_difficulty(balance.get("difficulty", null))
	shop = _load_shop(balance.get("shop", null))
	names = _load_names(load_json("names_ru.json"))
	strings = load_json("strings_ru.json")
	var progression = balance.get("progression", null)
	unlocks = _load_unlocks(progression)
	meta_rewards = _load_meta_rewards(progression)


## Прочитать data/<file_name> как Dictionary. Ошибки — warning + {}.
func load_json(file_name: String) -> Dictionary:
	if _cache.has(file_name):
		return _cache[file_name]
	var path := DATA_DIR.path_join(file_name)
	if not FileAccess.file_exists(path):
		push_warning("Data: файл не найден: %s — используются дефолты" % path)
		_cache[file_name] = {}
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Data: не удалось открыть %s (код %s)" % [path, FileAccess.get_open_error()])
		_cache[file_name] = {}
		return {}
	var text := file.get_as_text()
	file.close()
	var parser := JSON.new()
	var err := parser.parse(text)
	if err != OK:
		push_warning("Data: %s — ошибка JSON (строка %d: %s), используются дефолты" % [path, parser.get_error_line(), parser.get_error_message()])
		_cache[file_name] = {}
		return {}
	var parsed = parser.data
	if not (parsed is Dictionary):
		push_warning("Data: %s не является JSON-объектом — используются дефолты" % path)
		_cache[file_name] = {}
		return {}
	_cache[file_name] = parsed
	return parsed


@warning_ignore("native_method_override")
func tr(key: StringName, plural: StringName = &"") -> String:
	var k := str(key)
	var value = _lookup_key(strings, k)
	if value == null:
		push_warning("Data: нет строки '%s'" % k)
		return k
	return str(value)


## Есть ли строка (без warning), поддержка вложенных ключей.
func has_string(key: StringName) -> bool:
	return _lookup_key(strings, str(key)) != null


## Достать значение по ключу с вложенностью ("ui.title") или плоскому ключу.
func _lookup_key(source: Dictionary, path: String):
	if source.has(path):
		return source[path]
	if not path.contains("."):
		return null
	var current = source
	for part in path.split(".", false):
		if not (current is Dictionary) or not current.has(part):
			return null
		current = current[part]
	return current


func type_def(type: String) -> Dictionary:
	var key := str(type)
	var value = types.get(key, null)
	if value is Dictionary and not value.is_empty():
		return value
	push_warning("Data: неизвестный тип файла '%s' — дефолт text" % key)
	var fallback = types.get("text", null)
	if fallback is Dictionary:
		return fallback
	return DEFAULT_TYPES["text"].duplicate(true)


## Строка таблицы сложности; для hour > max — последняя строка.
func difficulty_for(hour: int) -> Dictionary:
	var h := maxi(1, int(hour))
	if difficulty.is_empty():
		push_warning("Data: пустая таблица сложности — дефолт часа 1")
		return DEFAULT_DIFFICULTY[0].duplicate(true)
	var prev: Dictionary = DEFAULT_DIFFICULTY[0].duplicate(true)
	var last: Dictionary = prev
	for row in difficulty:
		if not (row is Dictionary):
			continue
		last = row
		var row_hour := int(row.get("hour", 0))
		if row_hour == h:
			return row.duplicate(true)
		if row_hour < h:
			prev = row
		else:
			return prev.duplicate(true) if not prev.is_empty() else row.duplicate(true)
	return last.duplicate(true)


func shop_item(id: String) -> Dictionary:
	for item in shop:
		if item is Dictionary and str(item.get("id", "")) == str(id):
			return item.duplicate(true)
	push_warning("Data: нет товара '%s'" % str(id))
	return {}


## Ключ открытия для позиции магазина. "" — позиция доступна всегда.
## shop_sla продаётся вне прогрессии; поиск/щит открываются мета-наградами.
func shop_unlock_key(id: String) -> String:
	match str(id):
		"shop_sla":
			return ""
		"shop_search":
			return "search"
		"shop_shield":
			return "shield"
		_:
			return "shop"


## Открыта ли позиция магазина по текущему состоянию Game (run_hour/meta).
func shop_item_unlocked(item: Dictionary) -> bool:
	var key := shop_unlock_key(str(item.get("id", "")))
	if key.is_empty():
		return true
	var game = _game_node()
	if game != null and game.has_method("feature_unlocked"):
		return bool(game.feature_unlocked(key))
	return true


## Каталог магазина без закрытых позиций (shop_sla виден всегда).
func available_shop() -> Array:
	var out: Array = []
	for item in shop:
		if item is Dictionary and not str(item.get("id", "")).is_empty() and shop_item_unlocked(item):
			out.append(item.duplicate(true))
	return out


## Случайное имя папки из names_ru.json → folders (массив или {default: []}).
func folder_name() -> String:
	var pool = names.get("folders", null)
	var values: Array = []
	if pool is Array:
		values = pool
	elif pool is Dictionary:
		var default_pool = pool.get("default", [])
		if default_pool is Array:
			values = default_pool
	if values.is_empty():
		return "Разное"
	return str(values[randi_range(0, values.size() - 1)])


# --- служебное -------------------------------------------------------------

func _game_node():
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("Game")
	return null


func _load_unlocks(progression) -> Dictionary:
	if progression is Dictionary:
		var raw = progression.get("unlocks", null)
		if raw is Dictionary and not raw.is_empty():
			return raw.duplicate(true)
	push_warning("Data: balance.json → progression.unlocks отсутствует, используются дефолты")
	return DEFAULT_PROGRESSION["unlocks"].duplicate(true)


func _load_meta_rewards(progression) -> Dictionary:
	if progression is Dictionary:
		var raw = progression.get("meta_rewards", null)
		if raw is Dictionary and not raw.is_empty():
			return raw.duplicate(true)
	push_warning("Data: balance.json → progression.meta_rewards отсутствует, используются дефолты")
	return DEFAULT_PROGRESSION["meta_rewards"].duplicate(true)

func _merge_types(raw) -> Dictionary:
	var out: Dictionary = DEFAULT_TYPES.duplicate(true)
	if not (raw is Dictionary) or raw.is_empty():
		push_warning("Data: balance.json → types отсутствует, используются дефолты")
		return out
	for key in raw.keys():
		var src = raw[key]
		if not (src is Dictionary):
			continue
		var base: Dictionary = {}
		var existing = out.get(str(key), null)
		if existing is Dictionary:
			base = existing.duplicate(true)
		for field in src.keys():
			base[field] = src[field]
		out[str(key)] = base
	return out


func _load_difficulty(raw) -> Array:
	if raw is Array and not raw.is_empty():
		var out: Array = []
		for row in raw:
			if row is Dictionary and row.has("hour"):
				out.append(row.duplicate(true))
		if not out.is_empty():
			out.sort_custom(func(a, b): return int(a.get("hour", 0)) < int(b.get("hour", 0)))
			return out
	push_warning("Data: balance.json → difficulty отсутствует, используется дефолт")
	return DEFAULT_DIFFICULTY.duplicate(true)


func _load_shop(raw) -> Array:
	if raw is Array and not raw.is_empty():
		var out: Array = []
		for item in raw:
			if item is Dictionary and not str(item.get("id", "")).is_empty():
				out.append(item.duplicate(true))
		if not out.is_empty():
			return out
	push_warning("Data: balance.json → shop отсутствует, используется дефолт")
	return DEFAULT_SHOP.duplicate(true)


func _load_names(raw) -> Dictionary:
	if raw is Dictionary and not raw.is_empty():
		# Сохраняем все ключи файла (adjectives/nouns/organizations/folders/...),
		# а не только жёстко заданный набор.
		return raw.duplicate(true)
	push_warning("Data: names_ru.json пуст, используются пустые пулы имён")
	return {
		"adjectives": [],
		"nouns": [],
		"organizations": [],
		"avatar_captions": [],
		"first_names": [],
		"last_names": [],
		"folders": {"default": ["Разное"], "section_page_prefixes": []},
	}
