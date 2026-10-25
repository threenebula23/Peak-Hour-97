extends SceneTree
## Headless-тесты базы мини-игр, фабрики и выбора игры.
## Запуск: godot --headless --path . --script tests/test_minigame.gd

const MG := preload("res://scripts/minigames/minigame_base.gd")
const FACTORY := preload("res://scripts/minigames/minigame_factory.gd")

var _checks: int = 0
var _fails: int = 0
var _case: String = ""
var _last_q: float = -1.0
var _finish_count: int = 0


func _init() -> void:
	await process_frame
	_test_base_contract()
	_test_base_finish()
	_test_base_skip_and_esc()
	_test_verdicts()
	_test_factory_send()
	_test_selection()
	_test_attack_placeholder()
	_test_no_timers()
	_finish()


func _test_base_contract() -> void:
	_set_case("base_contract")
	var mg = MG.new()
	_ok(mg.process_mode == Node.PROCESS_MODE_ALWAYS, "PROCESS_MODE_ALWAYS")
	_ok(mg.mouse_filter == Control.MOUSE_FILTER_STOP, "mouse_filter STOP")
	_eq(mg.custom_minimum_size, Vector2(640, 360), "окно 640×360")
	_ok(not mg.visible, "до start окно скрыто")
	_ok(not mg.is_finished(), "до start не завершена")
	mg.start("dots", 2, 12345, {"request_id": "req_1"})
	_eq(mg.game_id, "dots", "game_id из известного id")
	_eq(mg.tier, 2, "tier из difficulty")
	_eq(mg.seed_value, 12345, "seed сохранён")
	_eq(mg.rng.seed, 12345, "локальный RNG засеян")
	_ok(mg.running, "running = true")
	_ok(mg.visible, "окно видимо")
	_eq(str(mg.context.get("request_id", "")), "req_1", "context сохранён")
	_approx(mg.quality(), 0.0, 0.0001, "quality стартует с 0")

	# Два одинаковых сида дают одинаковую последовательность локального RNG.
	var a = MG.new()
	var b = MG.new()
	a.start("sound", 1, 777)
	b.start("sound", 1, 777)
	for i in range(5):
		_approx(a.rng.randf(), b.rng.randf(), 0.0, "RNG сида совпадает #%d" % i)
	var c = MG.new()
	c.start("sound", 1, 778)
	var differs := false
	for i in range(5):
		if not is_equal_approx(a.rng.randf(), c.rng.randf()):
			differs = true
	_ok(differs, "разные сиды дают разные значения")

	# Старый вызов start(type, difficulty) продолжает парситься/работать.
	var legacy = MG.new()
	legacy.start("photo", 2.5)
	_eq(legacy.game_id, "photo", "legacy type → game_id")
	_ok(legacy.tier >= 2 and legacy.tier <= 3, "legacy difficulty → tier")
	a.free()
	b.free()
	c.free()
	legacy.free()
	mg.free()


func _test_base_finish() -> void:
	_set_case("base_finish")
	var mg = MG.new()
	_finish_count = 0
	_last_q = -1.0
	mg.finished.connect(_on_finished)
	mg.start("dots", 1, 5)
	mg._finish(1.7)
	_eq(_finish_count, 1, "finished эмитится один раз")
	_approx(_last_q, 1.0, 0.0001, "q клампится сверху в 1.0")
	_approx(mg.quality(), 1.0, 0.0001, "quality() = 1.0")
	_ok(mg.is_finished(), "is_finished = true")
	_ok(not mg.running, "running = false")
	_ok(mg.result_text().contains("100%"), "result_text содержит q%")
	_ok(mg.result_text().contains("ЧИСТО"), "result_text содержит вердикт")
	mg._finish(0.0)
	_eq(_finish_count, 1, "повторный _finish не эмитит")
	_approx(mg.quality(), 1.0, 0.0001, "повторный _finish не меняет q")

	var neg = MG.new()
	neg.finished.connect(_on_finished)
	_finish_count = 0
	_last_q = -1.0
	neg.start("maze", 4, 9)
	neg._finish(-0.5)
	_approx(_last_q, 0.0, 0.0001, "q клампится снизу в 0.0")
	neg.free()
	mg.free()


func _test_base_skip_and_esc() -> void:
	_set_case("base_skip")
	var mg = MG.new()
	_finish_count = 0
	_last_q = -1.0
	mg.finished.connect(_on_finished)
	mg.start("wires", 1, 3)
	mg._on_skip_clicked()
	_ok(mg._skip_armed, "первый клик только взводит пропуск")
	_ok(not mg.is_finished(), "первый клик не завершает")
	mg._on_skip_clicked()
	_eq(_finish_count, 1, "второй клик — finished")
	_approx(_last_q, 0.0, 0.0001, "пропуск даёт q=0")

	var esc_game = MG.new()
	esc_game.start("text", 2, 4)
	var esc := InputEventKey.new()
	esc.pressed = true
	esc.keycode = KEY_ESCAPE
	esc_game._input(esc)
	_ok(not esc_game.is_finished(), "Esc в игре отправки — no-op")
	esc_game.free()
	mg.free()


func _test_verdicts() -> void:
	_set_case("verdicts")
	_eq(MG.verdict(1.0), "ЧИСТО", "1.0 → ЧИСТО")
	_eq(MG.verdict(0.75), "ЧИСТО", "0.75 → ЧИСТО")
	_eq(MG.verdict(0.74), "НОРМАЛЬНО", "0.74 → НОРМАЛЬНО")
	_eq(MG.verdict(0.45), "НОРМАЛЬНО", "0.45 → НОРМАЛЬНО")
	_eq(MG.verdict(0.44), "СЛАБО", "0.44 → СЛАБО")
	_eq(MG.verdict(0.0), "СЛАБО", "0.0 → СЛАБО")


func _test_factory_send() -> void:
	_set_case("factory_send")
	_eq(FACTORY.send_ids().size(), 7, "зарегистрировано 7 игр")
	for id in FACTORY.send_ids():
		var game = FACTORY.create_send(str(id), 1, 123)
		_ok(game != null, "create_send(%s) не null" % str(id))
		if game == null:
			continue
		_ok(game is MiniGame, "create_send(%s) — MiniGame" % str(id))
		_eq(game.game_id, str(id), "game_id %s" % str(id))
		_eq(game.tier, 1, "tier T1")
		_eq(game.seed_value, 123, "seed проброшен")
		_ok(game.visible, "игра показана после start")
		game.free()

	for id in ["dots", "sound", "wires", "text", "video", "photo", "maze"]:
		var hard = FACTORY.create_send(id, 4, 99)
		_ok(hard != null, "T4 create_send(%s)" % id)
		if hard != null:
			_eq(hard.tier, 4, "T4 tier у %s" % id)
			hard.free()

	_ok(FACTORY.create_send("nope", 1, 1) == null, "неизвестная игра → null")
	_ok(FACTORY.is_send_id("maze"), "is_send_id maze")
	_ok(not FACTORY.is_send_id("junk"), "is_send_id junk = false")
	_eq(FACTORY.tier_for_hour(1), 1, "tier_for_hour 1 → 1")
	_eq(FACTORY.tier_for_hour(2), 1, "tier_for_hour 2 → 1")
	_eq(FACTORY.tier_for_hour(4), 2, "tier_for_hour 4 → 2")
	_eq(FACTORY.tier_for_hour(6), 3, "tier_for_hour 6 → 3")
	_eq(FACTORY.tier_for_hour(8), 4, "tier_for_hour 8 → 4")
	_eq(FACTORY.tier_for_hour(9), 4, "tier_for_hour 9 → 4")


func _test_selection() -> void:
	_set_case("selection")
	var one := FACTORY.send_for_types(["text"])
	_eq(str(one.get("id", "")), "dots", "S=1 → dots")
	_eq(int(one.get("tier", 0)), 1, "S=1 → T1")
	_eq(int(one.get("sum", 0)), 1, "sum=1")

	var video := FACTORY.send_for_types(["video"])
	_eq(str(video.get("id", "")), "dots", "S=8 → dots")
	_eq(int(video.get("tier", 0)), 2, "S=8 → T2")

	var three_video := FACTORY.send_for_types(["video", "video", "video"])
	_ok(FACTORY.send_ids().has(str(three_video.get("id", ""))), "S=24 → известная игра")
	_ok(int(three_video.get("tier", 0)) >= 1 and int(three_video.get("tier", 0)) <= 4,
		"S=24 → допустимая ступень")
	_eq(int(three_video.get("sum", 0)), 24, "sum=24")
	# Каноническая формула спецификации (idx = S-1) отдельно от Economy-делегата.
	var canonical := FACTORY.selection_for_sum(24)
	_eq(str(canonical.get("id", "")), "wires", "канон S=24 → wires")
	_eq(int(canonical.get("tier", 0)), 4, "канон S=24 → T4")
	_eq(str(FACTORY.selection_for_sum(8).get("id", "")), "dots", "канон S=8 → dots/T2")
	_eq(int(FACTORY.selection_for_sum(8).get("tier", 0)), 2, "канон S=8 → T2")

	var mix := FACTORY.send_for_types(["text", "sound"])
	_eq(str(mix.get("id", "")), "wires", "S=3 → wires")
	_eq(int(mix.get("tier", 0)), 1, "S=3 → T1")

	var photo := FACTORY.send_for_types(["photo"])
	_eq(str(photo.get("id", "")), "text", "S=4 → text")

	var seven := FACTORY.send_for_types(["text", "sound", "photo"])
	_ok(FACTORY.send_ids().has(str(seven.get("id", ""))), "S=7 → известная игра")
	_eq(int(seven.get("sum", 0)), 7, "S=7 sum")
	_eq(str(FACTORY.selection_for_sum(7).get("id", "")), "maze", "канон S=7 → maze")
	_eq(int(FACTORY.selection_for_sum(7).get("tier", 0)), 1, "канон S=7 → T1")

	var empty := FACTORY.selection_for_sum(0)
	_eq(str(empty.get("id", "")), "dots", "S=0 клампится в dots/T1")
	_eq(int(empty.get("tier", 0)), 1, "S=0 → T1")
	var cap := FACTORY.selection_for_sum(99)
	_eq(int(cap.get("index", -1)), 27, "idx клампится в 27")
	_eq(int(cap.get("tier", 0)), 4, "idx 27 → T4")


func _test_attack_placeholder() -> void:
	_set_case("attack_placeholder")
	var attack = FACTORY.create_attack("junk", 1, 7)
	if attack == null:
		_ok(true, "атакующий скрипт ещё не добавлен — null допустим")
	else:
		_ok(attack is MiniGame, "существующая атака — MiniGame")
		attack.free()
	var missing = FACTORY.create_attack("not_a_real_attack", 1, 7)
	_ok(missing == null, "неизвестная атака → null")


func _test_no_timers() -> void:
	_set_case("no_timers")
	for id in FACTORY.send_ids():
		var game = FACTORY.create_send(str(id), 2, 55)
		if game == null:
			_fail("нет игры %s" % str(id))
			continue
		_eq(_count_timers(game), 0, "нет Timer-узлов в %s" % str(id))
		# _process не должен падать и не должен завершать игру сам.
		game._process(0.1)
		_ok(not game.is_finished(), "один кадр не завершает %s" % str(id))
		game.free()


func _count_timers(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		if child is Timer:
			count += 1
		count += _count_timers(child)
	return count


# --- assert-хелперы --------------------------------------------------------

func _set_case(name: String) -> void:
	_case = name


func _ok(condition: bool, message: String) -> bool:
	_checks += 1
	if condition:
		return true
	_fail(message + " — ожидалось true")
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
	_fail("%s — получено %.6f, ожидалось %.6f" % [message, float(actual),
		float(expected)])
	return false


func _fail(message: String) -> void:
	_fails += 1
	print("FAIL [%s] %s" % [_case, message])


func _on_finished(q: float) -> void:
	_finish_count += 1
	_last_q = q


func _finish() -> void:
	print("test_minigame: проверок %d, провалов %d" % [_checks, _fails])
	print("PASS test_minigame" if _fails == 0 else "FAIL test_minigame")
	quit(0 if _fails == 0 else 1)
