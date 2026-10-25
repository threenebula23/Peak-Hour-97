extends SceneTree
## Headless-тест слотов соединений v2 (база 1, максимум 5).
## Запуск: godot --headless --path . --script tests/test_slots.gd

const SM := preload("res://scripts/core/slot_manager.gd")

var _checks: int = 0
var _fails: int = 0
var _case: String = ""
var _changes: int = 0


func _init() -> void:
	await process_frame
	var game = root.get_node_or_null("Game")
	if game == null:
		_fail("autoload Game недоступен")
		_finish()
		return
	game.start_new_run(1)
	_test_sizes()
	_test_reserve_release()
	_test_directions_and_entity()
	_test_weights()
	_finish()


func _test_sizes() -> void:
	_set_case("sizes")
	var game = root.get_node("Game")
	game.upgrades.clear()
	var sm = SM.new()
	_eq(SM.BASE_SLOTS, 1, "BASE_SLOTS = 1")
	_eq(SM.MAX_SLOTS, 5, "MAX_SLOTS = 5")
	_eq(sm.max_slots(), 1, "старт: 1 слот")
	_eq(sm.slots.size(), 1, "массив слотов размера 1")
	_eq(sm.used_count(), 0, "на старте слоты свободны")
	game.upgrades["slot_level"] = 1
	_eq(sm.max_slots(), 2, "slot_level=1 → 2 слота")
	game.upgrades["slot_level"] = 4
	_eq(sm.max_slots(), 5, "slot_level=4 → 5 слотов")
	game.upgrades["slot_level"] = 99
	_eq(sm.max_slots(), 5, "cap: максимум 5 слотов")
	# Агрегат читается и по id лота (v2-сейв пишет оба ключа).
	game.upgrades.clear()
	game.upgrades["lot_slots"] = 2
	_eq(sm.max_slots(), 3, "lot_slots=2 → 3 слота")
	game.upgrades.clear()


func _test_reserve_release() -> void:
	_set_case("reserve/release")
	var game = root.get_node("Game")
	# База: 1 слот — второй reserve отклоняется.
	game.upgrades.clear()
	var one = SM.new()
	_eq(one.reserve("in", "pkt_solo", "A"), 0, "1 слот: reserve → 0")
	_eq(one.reserve("out", "req_solo", "B"), -1, "1 слот: второй reserve → -1")
	_eq(one.used_count(), 1, "1 слот: занят 1")
	_eq(one.free_count(), 0, "1 слот: свободно 0")
	_ok(one.release(0), "release(0)")

	game.upgrades["slot_level"] = 1
	var sm = SM.new()
	sm.changed.connect(_on_changed)
	_changes = 0
	var a := sm.reserve("in", "pkt_a", "A")
	var b := sm.reserve("out", "req_b", "B")
	_eq(a, 0, "первый reserve → индекс 0")
	_eq(b, 1, "второй reserve → индекс 1")
	_eq(sm.reserve("in", "pkt_c", "C"), -1, "третий при 2 слотах → -1")
	_eq(sm.used_count(), 2, "занято 2")
	_eq(sm.used_count("in"), 1, "in занят 1")
	_eq(sm.used_count("out"), 1, "out занят 1")
	_ok(_changes >= 2, "сигнал changed эмитится")
	_ok(sm.release(a), "release(a)")
	_eq(sm.used_count(), 1, "после release занят 1")
	_ok(not sm.release(a), "повторный release(a) → false")
	_eq(sm.reserve("in", "pkt_c", "C"), 0, "освободившийся слот переиспользован")
	_eq(sm.release_by_entity("pkt_c"), 1, "release_by_entity")
	_eq(sm.release_by_entity("нет"), 0, "release_by_entity неизвестного → 0")
	_eq(sm.free_count(), 1, "свободен один слот")
	game.upgrades["slot_level"] = 0


func _test_directions_and_entity() -> void:
	_set_case("entity")
	var game = root.get_node("Game")
	game.upgrades["slot_level"] = 0
	var sm = SM.new()
	var index := sm.reserve("bad", "entity_1", "Имя")
	_eq(index, 0, "неизвестное направление всё равно занимает слот")
	_eq(sm.slots[index].direction, "", "направление очищено")
	_eq(sm.slots[index].entity_id, "entity_1", "entity_id сохранён")
	_eq(sm.slots[index].entity_name, "Имя", "entity_name сохранён")
	_eq(sm.reserve("in", "entity_1", "Дубль"), -1, "одна сущность не занимает два слота")
	_eq(sm.find_entity("entity_1"), 0, "find_entity")
	_eq(sm.find_entity("entity_2"), -1, "find_entity неизвестного")
	_ok(sm.set_progress(index, 0.5), "set_progress")
	_approx(sm.slots[index].progress, 0.5, 0.0001, "progress обновлён")


func _test_weights() -> void:
	_set_case("active_weights")
	var game = root.get_node("Game")
	game.upgrades["slot_level"] = 0
	var reg = game.registry
	var section = reg.sections.get("C")
	var folder_id := str(section.folder_ids[0])
	var file = reg.create_file("Слотовый файл", "photo", folder_id)
	_ok(file != null, "файл для веса создан")
	var sm = SM.new()
	if file != null:
		sm.reserve("in", str(file.id), "Файл")
		var weights: Array = sm.active_weights(reg)
		_eq(weights.size(), 1, "один вес для одного файла")
		if weights.size() == 1:
			_approx(float(weights[0]), 4.0, 0.0001, "вес photo = 4 (v2)")
	var reg2_file = reg.create_file("Слотовый запрос", "sound", folder_id)
	if reg2_file != null:
		reg.attach_file(reg2_file.id, "req_slot_test")
		var sm2 = SM.new()
		sm2.reserve("out", "req_slot_test", "Клиент")
		var weights2: Array = sm2.active_weights(reg)
		_eq(weights2.size(), 1, "вес запроса по прикреплённым файлам")
		if weights2.size() == 1:
			_approx(float(weights2[0]), 2.0, 0.0001, "вес sound = 2 (v2)")


# --- assert-хелперы --------------------------------------------------------

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
	if absf(actual - expected) <= eps:
		return true
	_fail("%s — получено %.6f, ожидалось %.6f" % [message, actual, expected])
	return false


func _fail(message: String) -> void:
	_fails += 1
	print("FAIL [%s] %s" % [_case, message])


func _on_changed() -> void:
	_changes += 1


func _finish() -> void:
	print("test_slots: проверок %d, провалов %d" % [_checks, _fails])
	print("PASS test_slots" if _fails == 0 else "FAIL test_slots")
	quit(0 if _fails == 0 else 1)
