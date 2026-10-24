extends SceneTree
## Headless-тест мини-игр: формула зоны D04, скорости, выбор типа, quality.
## Запуск: godot --headless --path . --script tests/test_minigame.gd

const CG := preload("res://scripts/minigames/connection_game.gd")
const MG := preload("res://scripts/minigames/minigame_base.gd")
const ECONOMY := preload("res://scripts/core/economy.gd")

var _checks: int = 0
var _fails: int = 0
var _case: String = ""
var _connection_result: int = -1
var _minigame_quality: float = -1.0


func _init() -> void:
	await process_frame
	_test_zone_formula()
	_test_speeds()
	_test_type_selection()
	_test_minigame_stub()
	_test_connection_node()
	_finish()


func _test_zone_formula() -> void:
	_set_case("zone")
	_approx(CG.compute_zone(1, 0, 0), 0.30, 0.0001, "час 1, 0 успехов, 0 зон")
	_approx(CG.compute_zone(9, 0, 0), 0.26, 0.0001, "час 9 → 0.26")
	_approx(CG.compute_zone(1, 10, 0), 0.25, 0.0001, "10 успехов → 0.25")
	_approx(CG.compute_zone(1, 0, 1), 0.35, 0.0001, "зона +5%")
	_approx(CG.compute_zone(1, 0, 3), 0.36, 0.0001, "cap 0.36")
	_approx(CG.compute_zone(1, 80, 0), 0.18, 0.0001, "нижний clamp 0.18")
	_approx(CG.compute_zone(25, 0, 0), 0.18, 0.0001, "поздний час → clamp 0.18")
	_approx(CG.compute_zone(12, 10, 1), 0.245, 0.0001, "смешанный пример")
	_approx(CG.compute_zone(0, 0, 0), 0.30, 0.0001, "час < 1 клампится")
	_approx(CG.compute_zone(1, -5, 0), 0.30, 0.0001, "отрицательные успехи клампятся")


func _test_speeds() -> void:
	_set_case("speeds")
	_approx(CG.speed_for(0), 440.0, 0.0001, "палочка 1 = 440")
	_approx(CG.speed_for(1), 340.0, 0.0001, "палочка 2 = 340")
	_approx(CG.speed_for(2), 280.0, 0.0001, "палочка 3 = 280")
	_approx(CG.speed_for(3), 440.0, 0.0001, "индекс зацикливается")


func _test_type_selection() -> void:
	_set_case("type")
	_eq(ECONOMY.minigame_type([]), "text", "пусто → text")
	_eq(ECONOMY.minigame_type(["text"]), "text", "text → text")
	_eq(ECONOMY.minigame_type(["text", "sound"]), "sound", "среднее 1.5 → sound")
	_eq(ECONOMY.minigame_type(["text", "photo"]), "sound", "среднее 2.0 → sound")
	_eq(ECONOMY.minigame_type(["text", "video"]), "photo", "среднее 2.5 → photo")
	_eq(ECONOMY.minigame_type(["photo", "video"]), "video", "среднее 3.5 → video")
	_eq(ECONOMY.minigame_type(["video"]), "video", "video → video")
	_eq(MG.select_type(["sound", "photo"]), "photo", "MiniGame.select_type повторяет правило")
	_approx(ECONOMY.minigame_difficulty(["text", "video"]), 2.5, 0.0001, "difficulty = mean")


func _test_minigame_stub() -> void:
	_set_case("minigame")
	var mg = MG.new()
	_ok(mg.process_mode == Node.PROCESS_MODE_ALWAYS, "MiniGame PROCESS_MODE_ALWAYS")
	mg.start("photo", 2.5)
	_eq(mg.game_type, "photo", "тип сохранён")
	_approx(mg.difficulty, 2.5, 0.0001, "сложность сохранена")
	_approx(mg.quality(), 1.0, 0.0001, "quality-заглушка = 1.0")
	_approx(mg.progress, 0.0, 0.0001, "полоса стартует с 0")
	mg.progress = 1.5
	mg._restart_bar()
	_approx(mg.progress, 0.0, 0.0001, "«Переделать» перезапускает полосу")
	_approx(mg.quality(), 1.0, 0.0001, "«Переделать» не меняет quality")
	_eq(MG.type_label("video"), "ВИДЕО", "заголовок ВИДЕО")
	_eq(MG.type_label("sound"), "ЗВУК", "заголовок ЗВУК")
	var esc := InputEventKey.new()
	esc.pressed = true
	esc.keycode = KEY_ESCAPE
	mg._input(esc)
	_ok(mg.running, "Esc в мини-игре — no-op")
	mg.finished.connect(_on_minigame_finished)
	mg._send()
	_approx(_minigame_quality, 1.0, 0.0001, "finished(1.0)")


func _test_connection_node() -> void:
	_set_case("connection")
	var cg = CG.new()
	_ok(cg.process_mode == Node.PROCESS_MODE_ALWAYS, "ConnectionGame PROCESS_MODE_ALWAYS")
	cg.finished.connect(_on_connection_finished)
	cg.start(3, 2, 1, "req_test")
	_approx(cg.zone_ratio, 0.33, 0.0001, "зона из формулы для hour 3/succ 2/zone 1")
	_approx(cg.zone_width_px(), 0.33 * 480.0, 0.0001, "ширина зоны в px")
	_eq(cg.request_id, "req_test", "request_id сохранён")
	_ok(cg.running, "игра запущена")
	_ok(cg.visible, "окно видимо")
	# Три попадания строго по очереди.
	_connection_result = -1
	for i in range(3):
		var x: float = cg.zone_start_x() + 1.0
		cg.stick_positions[i] = x
		cg._attempt_click()
	_ok(_connection_result == 1, "три попадания → finished(true)")
	# Esc — отмена.
	_connection_result = -1
	var cg2 = CG.new()
	cg2.finished.connect(_on_connection_finished)
	cg2.start(1, 0, 0, "req_cancel")
	var esc := InputEventKey.new()
	esc.pressed = true
	esc.keycode = KEY_ESCAPE
	cg2._input(esc)
	_eq(_connection_result, 0, "Esc → finished(false)")


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


func _on_minigame_finished(quality: float) -> void:
	_minigame_quality = quality


func _on_connection_finished(success: bool, _request_id: String) -> void:
	_connection_result = 1 if success else 0


func _finish() -> void:
	print("test_minigame: проверок %d, провалов %d" % [_checks, _fails])
	print("PASS test_minigame" if _fails == 0 else "FAIL test_minigame")
	quit(0 if _fails == 0 else 1)
