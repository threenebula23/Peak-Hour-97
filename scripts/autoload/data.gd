extends Node
## Data — доступ к JSON-данным из res://data (autoload).
##
## v2: новые секции balance.json (constants/hours/grid/shop_rules/shop/
## minigames/attacks/payout/sla). Отсутствующие ключи заменяются безопасными
## дефолтами с push_warning; игра не должна падать из-за данных.
##
## Legacy-API (tr, type_def, difficulty_for, shop_item, available_shop,
## folder_name) сохранён для ещё не переписанных систем.

const DATA_DIR := "res://data"

const DEFAULT_TYPES := {
	"text": {
		"name_ru": "Текст", "ext": "txt", "icon": "text",
		"size_kb": 64,
		"cells": 1, "base_time_sec": 3, "recv_fee": 1,
		"base_pay": 18, "weight": 1, "minigame_coeff": 1, "sla_loss": 2,
		"shapes": ["O1"],
	},
	"sound": {
		"name_ru": "Звук", "ext": "mp3", "icon": "sound",
		"size_kb": 3072,
		"cells": 2, "base_time_sec": 5, "recv_fee": 2,
		"base_pay": 30, "weight": 2, "minigame_coeff": 2, "sla_loss": 4,
		"shapes": ["I2H", "I2V"],
	},
	"photo": {
		"name_ru": "Фото", "ext": "jpg", "icon": "photo",
		"size_kb": 5120,
		"cells": 3, "base_time_sec": 8, "recv_fee": 4,
		"base_pay": 44, "weight": 4, "minigame_coeff": 4, "sla_loss": 8,
		"shapes": ["I3H", "I3V", "L3a", "L3b", "L3c", "L3d"],
	},
	"video": {
		"name_ru": "Видео", "ext": "mp4", "icon": "video",
		"size_kb": 20480,
		"cells": 4, "base_time_sec": 12, "recv_fee": 6,
		"base_pay": 69, "weight": 8, "minigame_coeff": 8, "sla_loss": 16,
		"shapes": ["I4H", "I4V", "O4", "T4a", "T4b", "T4c", "T4d",
			"L4a", "L4b", "L4c", "L4d", "J4a", "J4b", "J4c", "J4d", "S4", "Z4"],
	},
}

## Таблица сложности v1 — оставлена для legacy difficulty_for().
const DEFAULT_DIFFICULTY := [
	{"hour": 1, "max_requests": 2, "spawn_sec": 7.0},
	{"hour": 2, "max_requests": 5, "spawn_sec": 6.5},
	{"hour": 3, "max_requests": 7, "spawn_sec": 6.0},
	{"hour": 4, "max_requests": 9, "spawn_sec": 5.5},
	{"hour": 5, "max_requests": 10, "spawn_sec": 5.0},
	{"hour": 6, "max_requests": 11, "spawn_sec": 4.5},
	{"hour": 7, "max_requests": 11, "spawn_sec": 4.2},
	{"hour": 8, "max_requests": 12, "spawn_sec": 4.0},
]

const DEFAULT_SEND_ORDER := ["dots", "sound", "text", "video", "photo", "maze"]
const DEFAULT_ACHIEVABLE_SUMS := [
	1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
	21, 22, 24, 25, 26, 28, 32,
]

const DEFAULT_HOUR_FILES := [4, 8, 12, 16, 20, 20, 20, 20, 20]
const DEFAULT_REQUEST_CAP := [2, 5, 7, 9, 10, 11, 11, 12, 12]
const DEFAULT_ACTIVE_REQUESTS := [1, 2, 2, 3, 3, 3, 4, 4, 4]
const DEFAULT_ATTACKS := [0, 1, 1, 2, 2, 3, 3, 4, 4]
const DEFAULT_INCOME_TARGET := [90, 220, 380, 560, 760, 980, 1200, 1450, 1700]
const DEFAULT_RECV_INTERVAL := [12, 11, 10, 9, 8, 7.5, 7, 6.5, 6]
const DEFAULT_SEND_INTERVAL := [22, 20, 18, 17, 15, 14, 13, 12, 12]
## Порядок: text, sound, photo, video (§2.5).
const DEFAULT_TYPE_WEIGHTS := [
	[0.70, 0.30, 0.00, 0.00],
	[0.55, 0.30, 0.15, 0.00],
	[0.40, 0.30, 0.22, 0.08],
	[0.30, 0.25, 0.28, 0.17],
	[0.22, 0.20, 0.32, 0.26],
	[0.15, 0.15, 0.35, 0.35],
	[0.10, 0.12, 0.35, 0.43],
	[0.06, 0.08, 0.32, 0.54],
	[0.04, 0.04, 0.30, 0.62],
]
## Доли числа файлов в запросе: 1..4 (§2.6). Добавлен ключ "4" (4 файла).
const DEFAULT_REQUEST_MIX := {"1": 0.76, "2": 0.24, "3": 0.0, "4": 0.0}

const DEFAULT_LOT_IDS := [
	"lot_slots", "lot_speed", "lot_sla", "lot_shield",
	"lot_money", "lot_folder", "lot_channel", "lot_timer",
]
const DEFAULT_LOT_NAMES := [
	"Порты коммутатора", "Оптоволокно", "Резервный ИБП", "Заземление",
	"Корпоративный контракт", "Складской стеллаж", "Пропускная способность",
	"Регламент обработки",
]
const DEFAULT_LOT_EFFECTS := [
	"connection_slots", "transfer_speed", "sla_cap", "shield_charge",
	"money_mult", "folder_cells", "channel_capacity", "request_timer",
]
const DEFAULT_LOT_VALUES := [1, 0.10, 40, 1, 0.05, 1, 6, 7]
const DEFAULT_LOT_MAX := [4, 6, 4, 3, 8, 5, 6, 5]
const DEFAULT_LOT_PRICES := [
	[90, 200, 400, 700],
	[55, 75, 100, 135, 180, 245],
	[80, 160, 270, 430],
	[100, 220, 410],
	[70, 95, 130, 170, 220, 285, 365, 465],
	[50, 100, 180, 290, 440],
	[45, 70, 95, 130, 175, 230],
	[45, 75, 115, 165, 230],
]
const DEFAULT_LOT_WEIGHTS := [
	[1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.8, 0.8, 0.8],
	[1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.8, 0.8, 0.8],
	[0.8, 0.8, 0.8, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
	[0.3, 0.3, 0.3, 0.8, 0.8, 0.8, 1.0, 1.0, 1.0],
	[0.6, 0.6, 0.6, 1.0, 1.0, 1.0, 1.2, 1.2, 1.2],
	[1.0, 1.0, 1.0, 0.9, 0.9, 0.9, 0.8, 0.8, 0.8],
	[1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.9, 0.9, 0.9],
	[1.0, 1.0, 1.0, 0.9, 0.9, 0.9, 0.7, 0.7, 0.7],
]

const DEFAULT_SHOP_RULES := {
	"offers": 3,
	"unlock_hour": 2,
	"reroll_costs": [40, 80, 120],
	"max_rerolls": 3,
	"last_offer_weight": 0.5,
	"pity_hours": 2,
	"pity_weight": 1.5,
}

const DEFAULT_GRID_DIMS := [[5, 4], [6, 4], [7, 5], [8, 5], [8, 6], [9, 6]]

var balance: Dictionary = {}
var constants: Dictionary = {}
var economy: Dictionary = {}
var types: Dictionary = {}
var hours: Array = []
var grid: Dictionary = {}
var shop_lots: Array = []
var rules: Dictionary = {}
var minigames: Dictionary = {}
var attacks: Dictionary = {}
var payout_rules: Dictionary = {}
var sla_rules: Dictionary = {}

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
	constants = _as_dict(balance.get("constants", null))
	economy = _as_dict(balance.get("economy", null))
	types = _merge_types(balance.get("types", null))
	hours = _load_hours(balance.get("hours", null))
	grid = _as_dict(balance.get("grid", null))
	if grid.is_empty():
		push_warning("Data: balance.json → grid отсутствует, используются дефолты")
		grid = {"folder_cols": 5, "folder_rows": 4, "gap": 6,
			"cell_min": 56, "cell_max": 104, "table_cols": 4, "table_rows": 6,
			"folder_dims": DEFAULT_GRID_DIMS.duplicate(true), "shapes": {}}
	shop_lots = _load_shop_lots(balance.get("shop", null))
	shop = shop_lots
	rules = _load_rules(balance.get("shop_rules", null))
	minigames = _as_dict(balance.get("minigames", null))
	if minigames.is_empty():
		push_warning("Data: balance.json → minigames отсутствует")
		minigames = {"games": {}, "selection": {}}
	attacks = _as_dict(balance.get("attacks", null))
	payout_rules = _as_dict(balance.get("payout", null))
	sla_rules = _as_dict(balance.get("sla", null))
	difficulty = _load_difficulty(balance.get("difficulty", null))
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


## Строка таблицы сложности; для hour > max — последняя строка (legacy).
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


# --- v2: часы --------------------------------------------------------------

## Строка бюджета часа (files/request_cap/active_requests/attacks/
## income_target/type_weights/request_mix). hour > 9 → последняя строка.
func hour_def(hour: int) -> Dictionary:
	var h := maxi(1, int(hour))
	if hours.is_empty():
		push_warning("Data: balance.json → hours отсутствует, дефолт часа %d" % h)
		return _default_hour_row(h)
	var prev: Dictionary = hours[0]
	for row in hours:
		if not (row is Dictionary):
			continue
		var row_hour := int(row.get("hour", 0))
		if row_hour == h:
			return row.duplicate(true)
		if row_hour < h:
			prev = row
		elif row_hour > h:
			return prev.duplicate(true)
	return (hours[hours.size() - 1] as Dictionary).duplicate(true)


func hour_count() -> int:
	return maxi(1, hours.size())


# --- v2: магазин -----------------------------------------------------------

func lot_defs() -> Array:
	return shop_lots.duplicate(true)


func lot_def(id: String) -> Dictionary:
	for lot in shop_lots:
		if lot is Dictionary and str(lot.get("id", "")) == str(id):
			return lot.duplicate(true)
	push_warning("Data: нет лота '%s'" % str(id))
	return {}


func shop_rules() -> Dictionary:
	return rules.duplicate(true)


# --- v2: мини-игры ---------------------------------------------------------

func minigame_def(id: String) -> Dictionary:
	var games = minigames.get("games", null)
	if games is Dictionary:
		var def = (games as Dictionary).get(str(id), null)
		if def is Dictionary:
			return (def as Dictionary).duplicate(true)
	push_warning("Data: нет мини-игры '%s'" % str(id))
	return {}


func minigame_selection() -> Dictionary:
	var out: Dictionary = {}
	var raw = minigames.get("selection", null)
	if raw is Dictionary:
		out = (raw as Dictionary).duplicate(true)
	if not (out.get("order", null) is Array) or (out.get("order", null) as Array).is_empty():
		out["order"] = DEFAULT_SEND_ORDER.duplicate()
	if not (out.get("achievable_sums", null) is Array) or (out.get("achievable_sums", null) as Array).is_empty():
		out["achievable_sums"] = DEFAULT_ACHIEVABLE_SUMS.duplicate()
	out["max_index"] = int(out.get("max_index", 26))
	var coeff: Dictionary = {}
	for key in ["text", "sound", "photo", "video"]:
		coeff[key] = int(type_def(key).get("minigame_coeff", DEFAULT_TYPES[key].get("minigame_coeff", 1)))
	out["coeff"] = coeff
	return out


## Legacy-ступень для индекса (idx / 6 + 1), три ступени отправки.
func minigame_tier(index: int) -> int:
	return clampi(1 + int(floor(float(maxi(0, index)) / 6.0)), 1, 3)


# --- v2: атаки -------------------------------------------------------------

func attack_def(id: String) -> Dictionary:
	var kinds = attacks.get("kinds", null)
	if kinds is Dictionary:
		var def = (kinds as Dictionary).get(str(id), null)
		if def is Dictionary:
			return (def as Dictionary).duplicate(true)
	push_warning("Data: нет атаки '%s'" % str(id))
	return {}


func attack_tier(hour: int) -> int:
	return clampi(1 + int(floor(float(maxi(1, int(hour)) - 2) / 2.0)), 1, 4)


func attack_schedule() -> Array:
	var raw = attacks.get("schedule", null)
	if raw is Array:
		return (raw as Array).duplicate()
	return DEFAULT_ATTACKS.duplicate()


# --- v2: сетка -------------------------------------------------------------

func grid_rules() -> Dictionary:
	return grid.duplicate(true)


func shape_def(id: String) -> Dictionary:
	var shapes = grid.get("shapes", null)
	if shapes is Dictionary:
		var def = (shapes as Dictionary).get(str(id), null)
		if def is Dictionary:
			return (def as Dictionary).duplicate(true)
	push_warning("Data: нет фигуры '%s'" % str(id))
	return {}


func shapes() -> Dictionary:
	var raw = grid.get("shapes", null)
	if raw is Dictionary:
		return (raw as Dictionary).duplicate(true)
	return {}


func folder_dims_table() -> Array:
	var raw = grid.get("folder_dims", null)
	if raw is Array and not (raw as Array).is_empty():
		return (raw as Array).duplicate(true)
	return DEFAULT_GRID_DIMS.duplicate(true)


# --- legacy shop API -------------------------------------------------------

func shop_item(id: String) -> Dictionary:
	for item in shop:
		if item is Dictionary and str(item.get("id", "")) == str(id):
			return item.duplicate(true)
	push_warning("Data: нет товара '%s'" % str(id))
	return {}


## Ключ открытия для позиции магазина. "" — позиция доступна всегда.
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
	var id := str(item.get("id", ""))
	if id.begins_with("lot_"):
		return true
	var key := shop_unlock_key(id)
	if key.is_empty():
		return true
	var game = _game_node()
	if game != null and game.has_method("feature_unlocked"):
		return bool(game.feature_unlocked(key))
	return true


## Каталог магазина без закрытых позиций.
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


## Значение из constants с fallback (для других систем).
func const_value(key: String, fallback_value = null):
	if constants.has(key):
		return constants[key]
	return fallback_value


# --- служебное -------------------------------------------------------------

func _game_node():
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("Game")
	return null


func _as_dict(raw) -> Dictionary:
	if raw is Dictionary:
		return (raw as Dictionary).duplicate(true)
	return {}


func _load_unlocks(progression) -> Dictionary:
	if progression is Dictionary:
		var raw = progression.get("unlocks", null)
		if raw is Dictionary and not raw.is_empty():
			return raw.duplicate(true)
	push_warning("Data: balance.json → progression.unlocks отсутствует, используются дефолты")
	return {
		"shop": {"run_hour": 2, "label": "Магазин"},
		"search": {"meta": "survive_hour_3", "label": "Поиск"},
		"shield": {"meta": "survive_hour_5", "label": "Щит"},
		"minigame_text": {"run_hour": 1},
		"minigame_sound": {"run_hour": 2},
		"minigame_photo": {"run_hour": 3},
		"minigame_video": {"run_hour": 4},
		"attack_junk": {"run_hour": 2},
		"attack_ddos": {"run_hour": 2},
		"attack_phishing": {"run_hour": 3},
		"attack_ransomware": {"run_hour": 4},
	}


func _load_meta_rewards(progression) -> Dictionary:
	if progression is Dictionary:
		var raw = progression.get("meta_rewards", null)
		if raw is Dictionary and not raw.is_empty():
			return raw.duplicate(true)
	push_warning("Data: balance.json → progression.meta_rewards отсутствует, используются дефолты")
	return {
		"survive_hour_3": {"min_hours": 3, "unlocks": ["search"]},
		"survive_hour_5": {"min_hours": 5, "unlocks": ["shield"]},
		"complete_run": {"min_hours": 9, "unlocks": ["minigame_advanced"]},
	}


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


func _load_hours(raw) -> Array:
	if raw is Array and not (raw as Array).is_empty():
		var out: Array = []
		for row in raw:
			if row is Dictionary:
				out.append(row.duplicate(true))
		if not out.is_empty():
			out.sort_custom(func(a, b): return int(a.get("hour", 0)) < int(b.get("hour", 0)))
			return out
	push_warning("Data: balance.json → hours отсутствует, используются дефолты")
	var fallback: Array = []
	for i in range(9):
		fallback.append(_default_hour_row(i + 1))
	return fallback


func _default_hour_row(hour: int) -> Dictionary:
	var idx := clampi(hour - 1, 0, 8)
	var type_keys := ["text", "sound", "photo", "video"]
	var weights: Dictionary = {}
	for i in range(type_keys.size()):
		weights[type_keys[i]] = DEFAULT_TYPE_WEIGHTS[idx][i]
	return {
		"hour": maxi(1, hour),
		"files": DEFAULT_HOUR_FILES[idx],
		"request_cap": DEFAULT_REQUEST_CAP[idx],
		"active_requests": DEFAULT_ACTIVE_REQUESTS[idx],
		"attacks": DEFAULT_ATTACKS[idx],
		"income_target": DEFAULT_INCOME_TARGET[idx],
		"recv_interval": DEFAULT_RECV_INTERVAL[idx],
		"send_interval": DEFAULT_SEND_INTERVAL[idx],
		"type_weights": weights,
		"request_mix": DEFAULT_REQUEST_MIX.duplicate(),
	}


func _load_shop_lots(raw) -> Array:
	if raw is Array and not (raw as Array).is_empty():
		var out: Array = []
		for item in raw:
			if item is Dictionary and not str(item.get("id", "")).is_empty():
				out.append(item.duplicate(true))
		if not out.is_empty():
			return out
	push_warning("Data: balance.json → shop отсутствует, используются 8 дефолтных лотов")
	var fallback: Array = []
	for i in range(DEFAULT_LOT_IDS.size()):
		fallback.append({
			"id": DEFAULT_LOT_IDS[i],
			"name_ru": DEFAULT_LOT_NAMES[i],
			"desc_ru": "",
			"effect": DEFAULT_LOT_EFFECTS[i],
			"value": DEFAULT_LOT_VALUES[i],
			"max_level": DEFAULT_LOT_MAX[i],
			"prices": DEFAULT_LOT_PRICES[i].duplicate(),
			"level_names": [],
			"weight_by_hour": DEFAULT_LOT_WEIGHTS[i].duplicate(),
		})
	return fallback


func _load_rules(raw) -> Dictionary:
	var out: Dictionary = DEFAULT_SHOP_RULES.duplicate(true)
	if raw is Dictionary and not raw.is_empty():
		for key in raw.keys():
			out[str(key)] = raw[key]
		return out
	push_warning("Data: balance.json → shop_rules отсутствует, используются дефолты")
	return out


func _load_names(raw) -> Dictionary:
	if raw is Dictionary and not raw.is_empty():
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
