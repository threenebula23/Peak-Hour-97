extends SceneTree
## Headless-тесты базы мини-игр, фабрики и выбора игры.
## Запуск: godot --headless --path . --script tests/test_minigame.gd

const MG := preload("res://scripts/minigames/minigame_base.gd")
const FACTORY := preload("res://scripts/minigames/minigame_factory.gd")
const ECONOMY := preload("res://scripts/core/economy.gd")
const CONNECTION := preload("res://scripts/minigames/connection_game.gd")

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
	_test_connection_grace()
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
	_eq(str(mg.tier_label()), "СЛОЖНОСТЬ 2/3", "tier_label отправки 2/3")

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
	mg.start("sound", 1, 3)
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
	_eq(FACTORY.send_ids().size(), 6, "зарегистрировано 6 игр")
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

	for id in ["dots", "sound", "text", "video", "photo", "maze"]:
		var hard = FACTORY.create_send(id, 4, 99)
		_ok(hard != null, "T4 create_send(%s)" % id)
		if hard != null:
			_eq(hard.tier, 3, "tier 4 клампится в 3 у %s" % id)
			_eq(str(hard.tier_label()), "СЛОЖНОСТЬ 3/3", "tier_label отправки %s" % id)
			hard.free()

	_ok(FACTORY.create_send("nope", 1, 1) == null, "неизвестная игра → null")
	_ok(FACTORY.is_send_id("maze"), "is_send_id maze")
	_ok(not FACTORY.is_send_id("junk"), "is_send_id junk = false")
	_eq(FACTORY.tier_for_hour(1), 1, "tier_for_hour 1 → 1")
	_eq(FACTORY.tier_for_hour(2), 1, "tier_for_hour 2 → 1")
	_eq(FACTORY.tier_for_hour(4), 2, "tier_for_hour 4 → 2")
	_eq(FACTORY.tier_for_hour(6), 3, "tier_for_hour 6 → 3")
	_eq(FACTORY.tier_for_hour(8), 3, "tier_for_hour 8 → 3")
	_eq(FACTORY.tier_for_hour(9), 3, "tier_for_hour 9 → 3")


func _test_selection() -> void:
	_set_case("selection")
	var data = _data()
	var selection: Dictionary = {}
	if data != null and data.has_method("minigame_selection"):
		selection = data.minigame_selection()
	var sums: Array = selection.get("achievable_sums", ECONOMY.achievable_sums())
	var rank_games: Array = selection.get("rank_games", ECONOMY.RANK_GAMES)
	var tier_max: Array = selection.get("tier_max_rank", ECONOMY.TIER_MAX_RANK)
	var coeff: Dictionary = selection.get("coeff", ECONOMY.MINIGAME_COEFF)

	# Схема §6: ровно 27 достижимых сумм коэффициентов 1/2/4/8 для 1–4 файлов.
	_eq(ECONOMY.achievable_sums(),
		[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18,
			19, 20, 21, 22, 24, 25, 26, 28, 32],
		"27 достижимых сумм [1..22,24,25,26,28,32]")
	_eq(sums.size(), 27, "в данных 27 сумм")
	_eq(_ints(ECONOMY.achievable_sums()), _ints(sums),
		"Economy и Data согласованы по суммам")
	_eq(str(ECONOMY.RANK_GAMES), str(rank_games), "Economy и Data согласованы по rank_games")
	_eq(_ints(ECONOMY.TIER_MAX_RANK), _ints(tier_max),
		"Economy и Data согласованы по границам ступеней")
	for type_id in ["text", "sound", "photo", "video"]:
		_eq(int(coeff.get(type_id, -1)), int(ECONOMY.MINIGAME_COEFF[type_id]),
			"коэффициент %s = %d" % [type_id, int(ECONOMY.MINIGAME_COEFF[type_id])])

	# Суммы действительно достижимы 1–4 файлами (и других нет).
	var coeffs: Array = [1, 2, 4, 8]
	var reachable: Dictionary = {}
	for a in coeffs:
		reachable[a] = true
		for b in coeffs:
			if b < a:
				continue
			reachable[a + b] = true
			for c in coeffs:
				if c < b:
					continue
				reachable[a + b + c] = true
				for d in coeffs:
					if d < c:
						continue
					reachable[a + b + c + d] = true
	var reachable_sorted: Array = reachable.keys()
	reachable_sorted.sort()
	_eq(_ints(reachable_sorted), _ints(sums),
		"список сумм = все суммы 1–4 коэффициентов")

	# rank → игра и ступень: 0–7 → T1, 8–13 → T2, 14–26 → T3.
	for idx in range(sums.size()):
		var total := int(sums[idx])
		var pick: Dictionary = FACTORY.selection_for_sum(total)
		_eq(int(pick.get("index", -1)), idx, "S=%d: rank %d" % [total, idx])
		_eq(int(pick.get("sum", -1)), total, "S=%d: сумма сохранена" % total)
		_eq(str(pick.get("id", "")), str(rank_games[idx]),
			"S=%d: игра из GAME_BY_RANK[%d]" % [total, idx])
		var expected_tier := 1
		if idx > int(tier_max[1]):
			expected_tier = 3
		elif idx > int(tier_max[0]):
			expected_tier = 2
		_eq(int(pick.get("tier", 0)), expected_tier,
			"S=%d: ступень %d" % [total, expected_tier])
		_ok(FACTORY.send_ids().has(str(pick.get("id", ""))),
			"S=%d: игра зарегистрирована" % total)
		_ok(str(pick.get("id", "")) != "wires", "S=%d: wires не выбирается" % total)

	# Коэффициенты типов дают ту же сумму/игру, что и прямой выбор по rank.
	var combos := [
		["text"], ["sound"], ["photo"], ["video"],
		["text", "sound"], ["text", "text"], ["sound", "sound"],
		["video", "video"], ["video", "video", "video"],
		["video", "video", "video", "video"],
	]
	for types in combos:
		var total := 0
		for t in types:
			total += int(coeff.get(str(t), 1))
		var direct: Dictionary = FACTORY.selection_for_sum(total)
		var pick: Dictionary = FACTORY.send_for_types(types)
		_eq(str(pick.get("id", "")), str(direct.get("id", "")),
			"%s: игра совпадает с выбором по сумме %d" % [str(types), total])
		_eq(int(pick.get("tier", 0)), int(direct.get("tier", 0)),
			"%s: ступень совпадает с суммой %d" % [str(types), total])
		_eq(int(pick.get("sum", -1)), total, "%s: sum=%d" % [str(types), total])
		_ok(str(pick.get("id", "")) != "wires", "%s: не wires" % str(types))

	# S=0 клампится в dots/T1, сверх максимума — последний rank.
	var empty: Dictionary = FACTORY.selection_for_sum(0)
	_eq(str(empty.get("id", "")), "dots", "S=0 клампится в dots/T1")
	_eq(int(empty.get("tier", 0)), 1, "S=0 → T1")
	_eq(int(empty.get("index", -1)), 0, "S=0 → rank 0")
	var cap: Dictionary = FACTORY.selection_for_sum(99)
	_eq(int(cap.get("index", -1)), sums.size() - 1, "idx клампится в последний rank")
	_eq(int(cap.get("tier", 0)), 3, "последний rank → T3")
	_eq(str(cap.get("id", "")), str(rank_games[rank_games.size() - 1]),
		"последний rank → игра из таблицы")


func _test_attack_placeholder() -> void:
	_set_case("attack_placeholder")
	var attack = FACTORY.create_attack("junk", 1, 7)
	if attack == null:
		_ok(true, "атакующий скрипт ещё не добавлен — null допустим")
	else:
		_ok(attack is MiniGame, "существующая атака — MiniGame")
		_eq(str(attack.tier_label()), "СЛОЖНОСТЬ 1/4", "у атаки 4 ступени")
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


func _test_connection_grace() -> void:
	_set_case("connection_grace")
	var game = CONNECTION.new()
	root.add_child(game)
	game.start(1, 0, 0, "req")
	_ok(game._input_grace > 0.0, "start() взводит grace")
	_ok(not game._armed, "до истечения grace попытки запрещены")

	# Клик, который открыл модалку (и его release), не должен быть попыткой.
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = game.global_position + Vector2(320.0, 140.0)
	game._input(press)
	_ok(not game.missed, "клик в grace не даёт промах")
	_approx(game.flash_left, 0.0, 0.0001, "клик в grace не включает красную вспышку")
	_eq(game.active_index, 0, "клик в grace не засчитывает попадание")
	_ok(not game._emitted, "клик в grace не завершает игру")

	# После grace палочка уходит из зелёной зоны — обычный клик штрафует.
	game._process(0.4)
	_ok(game._input_grace <= 0.0, "grace истекает по _process")
	_ok(game._armed, "после grace попытки разрешены")
	_ok(game.stick_positions[0] < game.zone_start_x(), "палочка вне зоны")
	game._input(press)
	_ok(game.missed, "клик вне зоны после grace = промах")
	_ok(game.flash_left > 0.0, "промах включает красную вспышку")
	game.free()


func _count_timers(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		if child is Timer:
			count += 1
		count += _count_timers(child)
	return count


# --- assert-хелперы --------------------------------------------------------

func _data():
	return root.get_node_or_null("Data")


## JSON парсит числа как float — нормализуем к int для сравнения таблиц.
func _ints(values: Array) -> Array:
	var out: Array = []
	for value in values:
		out.append(int(value))
	return out


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
