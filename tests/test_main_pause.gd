extends SceneTree
## Headless-тест паузы, настроек и выхода в меню на экране Main.tscn.
##
## Проверяет:
##   • _pause_game / _resume_game — controller.paused и видимость PauseModal;
##   • _open_settings + settings_changed — громкости Audio и спокойный фон;
##   • _confirm_to_menu / _to_menu — подтверждение и главное меню;
##   • Esc в фазе часа — пауза и повторное снятие.
##
## Запуск:
##   godot --headless --path . --script tests/test_main_pause.gd

const MAIN_SCENE := "res://scenes/Main.tscn"

var _checks := 0
var _fails := 0
var _main: Node = null
var _controller = null
var _game = null
var _audio: Node = null


func _init() -> void:
	await process_frame
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("не удалось загрузить Main.tscn")
		_finish()
		return
	_main = packed.instantiate()
	root.add_child(_main)
	await process_frame

	_main._start_new_run()
	await process_frame

	_game = root.get_node_or_null("Game")
	_audio = root.get_node_or_null("Audio")
	_ok(_game != null, "autoload Game доступен")
	_ok(_audio != null, "autoload Audio доступен")
	_ok(_main.controller != null, "controller создан")
	if _game == null or _main.controller == null:
		_finish()
		return
	_controller = _main.controller

	_main._on_start_hour()
	await process_frame
	_eq(_controller.phase, &"hour", "фаза контроллера — hour")
	_ok(_main.pause_modal != null, "PauseModal создана")
	_ok(_main.settings_modal != null, "SettingsModal создана")
	_ok(_main.confirm_modal != null, "ConfirmModal создана")
	if _main.pause_modal == null or _main.settings_modal == null or _main.confirm_modal == null:
		_finish()
		return

	_test_pause_resume()
	_test_settings()
	_test_confirm_to_menu()
	_test_escape()

	await process_frame
	print("")
	print("Проверок: %d, провалов: %d" % [_checks, _fails])
	_finish()


func _test_pause_resume() -> void:
	_main._pause_game()
	_ok(bool(_controller.paused), "_pause_game ставит controller.paused=true")
	_ok(_main.pause_modal.visible, "_pause_game показывает PauseModal")

	_main._resume_game()
	_ok(not bool(_controller.paused), "_resume_game снимает паузу")
	_ok(not _main.pause_modal.visible, "_resume_game скрывает PauseModal")


func _test_settings() -> void:
	_main._open_settings()
	_ok(_main.settings_modal.visible, "_open_settings показывает SettingsModal")

	_main.settings_modal.settings_changed.emit({
		"sfx": 20, "music": 30, "calm_bg": true, "fullscreen": false,
	})
	_approx(float(_audio.sfx_volume), 0.2, 0.001, "громкость SFX применена")
	_approx(float(_audio.music_volume), 0.3, 0.001, "громкость музыки применена")
	_ok(_main._backdrop != null and bool(_main._backdrop.visible),
		"спокойный фон не скрывает Backdrop")
	_ok(_main._backdrop != null and bool(_main._backdrop.calm),
		"спокойный фон переключает Backdrop.calm=true")
	var clear = ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color")
	_ok(clear is Color and (clear as Color).is_equal_approx(Theme90.PAPER),
		"clear color проекта — бумага, а не серый")
	var saved = _game.stats.get("settings", {})
	_ok(saved is Dictionary and int(saved.get("sfx", -1)) == 20,
		"настройки сохранены в Game.stats")

	# Выключение спокойного фона возвращает dither, Backdrop остаётся видимым.
	_main.settings_modal.settings_changed.emit({
		"sfx": 20, "music": 30, "calm_bg": false, "fullscreen": false,
	})
	_ok(_main._backdrop != null and bool(_main._backdrop.visible),
		"обычный фон не скрывает Backdrop")
	_ok(_main._backdrop != null and not bool(_main._backdrop.calm),
		"обычный фон сбрасывает Backdrop.calm=false")
	_main.settings_modal.visible = false


func _test_confirm_to_menu() -> void:
	_main._confirm_to_menu()
	_ok(_main.confirm_modal.visible, "_confirm_to_menu показывает подтверждение")
	_to_menu()
	_ok(_main.main_menu.visible, "_to_menu показывает главное меню")
	_ok(not _main.pause_modal.visible, "_to_menu скрывает PauseModal")
	_ok(not _main.settings_modal.visible, "_to_menu скрывает SettingsModal")
	_ok(not _main.confirm_modal.visible, "_to_menu скрывает ConfirmModal")
	_ok(bool(_controller.paused), "_to_menu держит час на паузе")


func _test_escape() -> void:
	_main._unhandled_input(_esc())
	_ok(_main.pause_modal.visible, "Esc в фазе hour открывает паузу")
	_main._unhandled_input(_esc())
	_ok(not _main.pause_modal.visible, "повторный Esc снимает паузу")
	_ok(not bool(_controller.paused), "после второго Esc пауза снята")


func _to_menu() -> void:
	_main._to_menu()


func _esc() -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	return ev


func _finish() -> void:
	if _fails == 0:
		print("PASS")
	else:
		print("FAIL")
	quit(0 if _fails == 0 else 1)


func _ok(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_fails += 1
	print("FAIL: %s" % message)


func _eq(actual, expected, message: String) -> void:
	_checks += 1
	if actual == expected:
		return
	_fails += 1
	print("FAIL: %s — получено %s, ожидалось %s" % [message, actual, expected])


func _approx(actual: float, expected: float, eps: float, message: String) -> void:
	_checks += 1
	if absf(float(actual) - float(expected)) <= eps:
		return
	_fails += 1
	print("FAIL: %s — получено %.4f, ожидалось %.4f" % [message, actual, expected])


func _fail(message: String) -> void:
	_checks += 1
	_fails += 1
	print("FAIL: %s" % message)
