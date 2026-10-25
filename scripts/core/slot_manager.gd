class_name SlotManager
extends RefCounted
## Слоты соединений v2. Всего 1 + slot_level, но не больше 5.
##
## Слоты общие для приёма и отправки; направление хранится для UI и канала.
## manager не тикает сам: прогресс обновляет HourDirector.

signal changed

const SLOT_SCRIPT := preload("res://scripts/entities/slot.gd")
const BASE_SLOTS := 1
const MAX_SLOTS := 5

var slots: Array = []
var _fallback_level: int = 0


func _init() -> void:
	refresh_max_slots()


## Перечитать уровень из Game.upgrades и привести массив слотов к размеру.
func refresh_max_slots() -> void:
	var level := _slot_level()
	_fallback_level = level
	var target := clampi(BASE_SLOTS + level, BASE_SLOTS, MAX_SLOTS)
	var old_size := slots.size()
	if old_size < target:
		for i in range(old_size, target):
			var slot = SLOT_SCRIPT.new()
			slot.index = i
			slots.append(slot)
	elif old_size > target:
		# Урезаем только пустые хвосты; занятые слоты не выбрасываем.
		for i in range(old_size - 1, target - 1, -1):
			if slots[i].occupied:
				target = i + 1
				break
		slots.resize(target)
		for i in range(slots.size()):
			slots[i].index = i
	if slots.size() != old_size:
		changed.emit()


func max_slots() -> int:
	refresh_max_slots()
	return slots.size()


func used_count(direction: String = "") -> int:
	refresh_max_slots()
	var count := 0
	for slot in slots:
		if not slot.occupied:
			continue
		if direction.is_empty() or slot.direction == direction:
			count += 1
	return count


func free_count(direction: String = "") -> int:
	return max_slots() - used_count(direction)


## Занять свободный слот. Возвращает индекс или -1, если мест нет.
func reserve(direction: String, entity_id: String, entity_name: String = "") -> int:
	refresh_max_slots()
	if entity_id.is_empty():
		return -1
	# Не разрешаем одной сущности занимать два слота.
	if find_entity(entity_id) >= 0:
		return -1
	for slot in slots:
		if slot.occupied:
			continue
		slot.occupy(_clean_direction(direction), entity_id, entity_name)
		changed.emit()
		return slot.index
	return -1


func release(index: int) -> bool:
	refresh_max_slots()
	if index < 0 or index >= slots.size():
		return false
	if not slots[index].occupied:
		return false
	slots[index].reset()
	changed.emit()
	return true


## Освободить все слоты, занятые сущностью. Возвращает число освобождённых.
func release_by_entity(entity_id: String) -> int:
	if entity_id.is_empty():
		return 0
	refresh_max_slots()
	var released := 0
	for slot in slots:
		if slot.occupied and slot.entity_id == entity_id:
			slot.reset()
			released += 1
	if released > 0:
		changed.emit()
	return released


func find_entity(entity_id: String) -> int:
	for slot in slots:
		if slot.occupied and slot.entity_id == entity_id:
			return slot.index
	return -1


func get_slot(index: int):
	if index < 0 or index >= slots.size():
		return null
	return slots[index]


func set_progress(index: int, progress: float) -> bool:
	if index < 0 or index >= slots.size() or not slots[index].occupied:
		return false
	slots[index].progress = clampf(progress, 0.0, 1.0)
	changed.emit()
	return true


## Веса активных передач для формулы канала (D12 §9).
## entity_id может быть id файла (приём) или id запроса (отправка).
func active_weights(registry) -> Array:
	var weights: Array = []
	if registry == null:
		return weights
	for slot in slots:
		if not slot.occupied:
			continue
		var weight := _entity_weight(registry, slot.entity_id)
		if weight > 0.0:
			weights.append(weight)
	return weights


func to_dict() -> Dictionary:
	var raw: Array = []
	for slot in slots:
		raw.append(slot.to_dict())
	return {"slots": raw}


func from_dict(d: Dictionary) -> bool:
	if d == null or not (d.get("slots", null) is Array):
		return false
	slots.clear()
	for raw in d.get("slots", []):
		if raw is Dictionary:
			slots.append(SLOT_SCRIPT.from_dict(raw))
	changed.emit()
	return true


# --- служебное -------------------------------------------------------------

func _entity_weight(registry, entity_id: String) -> float:
	if registry == null:
		return 0.0
	var files = registry.files if registry.get("files") != null else null
	if files == null:
		return 0.0
	if files.has(entity_id):
		return _type_weight(files[entity_id].type)
	# Запрос: сумма весов прикреплённых к нему файлов.
	var total := 0.0
	for file in files.values():
		if str(file.attached_request) == entity_id:
			total += _type_weight(file.type)
	return total


func _type_weight(type: String) -> float:
	var data = _data_node()
	if data != null and data.has_method("type_def"):
		var def = data.type_def(type)
		if def is Dictionary:
			return maxf(0.0, float(def.get("weight", 0.0)))
	return 0.0


func _slot_level() -> int:
	var game = _autoload("Game")
	if game == null:
		return _fallback_level
	var upgrades: Dictionary = game.upgrades if game.upgrades is Dictionary else {}
	# v2: агрегированный уровень, который пишет Shop/Game (lot_slots → slot_level).
	for key in ["slot_level", "connection_slots", "lot_slots"]:
		if upgrades.has(key):
			return int(upgrades[key])
	# Совместимость с v1-покупками по id (если такие остались в старом сейве).
	var level := 0
	for key in ["shop_slot3", "shop_slot4"]:
		level += int(upgrades.get(key, 0))
	return level


func _clean_direction(direction: String) -> String:
	var clean := direction.to_lower()
	if clean != "in" and clean != "out":
		return ""
	return clean


func _data_node():
	return _autoload("Data")


func _autoload(name: String):
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null(name)
	return null
