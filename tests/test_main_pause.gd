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
## Оригинальный user://save.json, чтобы тест не испортил сохранение игрока.
var _had_save := false
var _backup_save := ""
var _save_backed_up := false


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

	_game = root.get_node_or_null("Game")
	_audio = root.get_node_or_null("Audio")
	_ok(_game != null, "autoload Game доступен")
	_ok(_audio != null, "autoload Audio доступен")
	_ok(_main.controller != null, "controller создан")
	if _game == null or _main.controller == null:
		_finish()
		return
	_controller = _main.controller
	_had_save = SaveManager.has_save()
	if _had_save:
		_backup_save = FileAccess.get_file_as_string(SaveManager.SAVE_PATH)
	_save_backed_up = true

	# До старта забега — проверяем, что настройки из меню не пишут save.
	_test_menu_settings_no_write()
	_test_menu_layout()

	_main._start_new_run()
	await process_frame
	_eq(_controller.phase, &"prep", "после нового забега фаза prep")
	_ok(_main._settings_persist_allowed(), "в фазе prep запись настроек в save разрешена")
	SaveManager.delete_save()
	_main._apply_settings({"sfx": 33, "music": 44, "calm_bg": true, "fullscreen": false})
	_ok(SaveManager.has_save(), "настройки в фазе prep пишут save.json")

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
	_test_modal_pause()
	_test_modal_no_x_and_close()
	_test_settings()
	_test_confirm_to_menu()
	_test_escape()
	_test_run_result_settings_no_write()

	await process_frame
	print("")
	print("Проверок: %d, провалов: %d" % [_checks, _fails])
	_finish()


## В главном меню «Подтвердить» не создаёт и не перезаписывает save.json.
func _test_menu_settings_no_write() -> void:
	# --- холодный старт: save.json ещё нет ---------------------------------
	SaveManager.delete_save()
	_main.main_menu.set_has_save(false)
	_eq(_controller.phase, &"menu", "до старта забега фаза menu")
	_ok(not _main._settings_persist_allowed(),
		"в фазе menu запись настроек в save запрещена")
	_ok(not SaveManager.has_save(), "перед проверкой меню save.json отсутствует")

	_main._open_settings()
	_main.settings_modal._sfx.set_value(40)
	_main.settings_modal._confirm()
	_ok(not _main.settings_modal.visible, "настройки из меню закрылись по «Подтвердить»")
	_eq(int((_game.stats.get("settings", {}) as Dictionary).get("sfx", -1)), 40,
		"настройки из меню попали в Game.stats")
	_ok(not SaveManager.has_save(), "настройки в меню не создают save.json")
	_eq(_main.main_menu.has_save, false, "Continue отражает отсутствие save")
	_ok(bool(_main.main_menu._btn_continue.disabled),
		"Continue неактивна без сохранения")

	# --- существующий save.json не перезаписывается -------------------------
	_ok(SaveManager.save({"money": 321, "phase": "prep"}),
		"подготовлен существующий save.json")
	var before_text := FileAccess.get_file_as_string(SaveManager.SAVE_PATH)
	var before_mtime := FileAccess.get_modified_time(SaveManager.SAVE_PATH)
	_main.main_menu.set_has_save(true)
	_ok(not bool(_main.main_menu._btn_continue.disabled),
		"Continue активна при существующем save")

	_main._open_settings()
	_main.settings_modal._sfx.set_value(55)
	_main.settings_modal._confirm()
	_eq(FileAccess.get_file_as_string(SaveManager.SAVE_PATH), before_text,
		"существующий save.json не изменён настройками из меню")
	_eq(FileAccess.get_modified_time(SaveManager.SAVE_PATH), before_mtime,
		"mtime существующего save.json не изменился")
	_eq(int((_game.stats.get("settings", {}) as Dictionary).get("sfx", -1)), 55,
		"настройки из меню применены и при существующем save")
	_ok(SaveManager.has_save(), "save.json остаётся на месте")


## SFX из user://save.json (или -1, если файла/поля нет).
func _saved_settings_sfx() -> int:
	if not SaveManager.has_save():
		return -1
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SaveManager.SAVE_PATH))
	if not (parsed is Dictionary):
		return -1
	var stats = (parsed as Dictionary).get("stats", {})
	if not (stats is Dictionary):
		return -1
	var settings = (stats as Dictionary).get("settings", {})
	if not (settings is Dictionary):
		return -1
	return int((settings as Dictionary).get("sfx", -1))


## Кнопки главного меню центрированы по панели действий (x ≈ центр ±2 px).
func _test_menu_layout() -> void:
	var menu = _main.main_menu
	_ok(menu != null, "main_menu доступен для проверки раскладки")
	if menu == null:
		return
	var panel: Rect2 = menu._panel_rect(menu._window())
	var center_x: float = panel.position.x + panel.size.x * 0.5
	var buttons: Array = [menu._btn_continue, menu._btn_new, menu._btn_tutorial,
		menu._btn_settings, menu._btn_about]
	for b in buttons:
		_ok(b != null, "кнопка меню создана")
		if b == null:
			continue
		_approx(float(b.position.x) + float(b.size.x) * 0.5, center_x, 2.0,
			"menu «%s» центрирована в панели действий" % str(b.caption))


func _test_pause_resume() -> void:
	_main._pause_game()
	_ok(bool(_controller.paused), "_pause_game ставит controller.paused=true")
	_ok(_main.pause_modal.visible, "_pause_game показывает PauseModal")

	_main._resume_game()
	_ok(not bool(_controller.paused), "_resume_game снимает паузу")
	_ok(not _main.pause_modal.visible, "_resume_game скрывает PauseModal")


## Служебное окно (настройки) в час ставит таймер на паузу и снимает её.
func _test_modal_pause() -> void:
	var director = _controller.hour_director
	_ok(director != null, "hour_director доступен для проверки паузы")
	if director == null:
		return
	_controller.set_paused(false)
	_main._on_menu_pick("Настройки")
	_ok(_main.settings_modal.visible, "настройки открыты из меню")
	_ok(bool(_controller.paused), "открытые настройки ставят час на паузу")
	var before := float(director.time_left)
	_controller.tick(0.5)
	_approx(float(director.time_left), before, 0.001,
		"на паузе tick не уменьшает time_left")

	_main.settings_modal.close()
	_ok(not bool(_controller.paused), "закрытие настроек снимает автопаузу")
	_controller.tick(0.2)
	_ok(float(director.time_left) < before, "после закрытия время снова идёт")

	# Подтверждение (About использует ту же модалку) тоже держит паузу.
	_main._show_about()
	_ok(bool(_controller.paused), "окно «О программе» ставит паузу")
	_main.confirm_modal._answer(false)
	_ok(not bool(_controller.paused), "закрытие «О программе» снимает паузу")

	# Переименование папки — тоже служебное окно часа.
	var fid := ""
	for section in _game.registry.sections.values():
		if not section.folder_ids.is_empty():
			fid = str(section.folder_ids[0])
			break
	if not fid.is_empty():
		_main._open_rename(fid)
		_ok(_main.rename_modal.visible, "окно переименования открыто")
		_ok(bool(_controller.paused), "окно переименования ставит паузу")
		_main.rename_modal.close()
		_ok(not bool(_controller.paused), "закрытие переименования снимает паузу")


## v5: Settings/About/Confirm без «крестика» — закрытие только явной кнопкой.
func _test_modal_no_x_and_close() -> void:
	# Settings: отмена — явная кнопка, крестика окна нет.
	_main._open_settings()
	_ok(_main.settings_modal.visible, "Settings открыт")
	_assert_no_window_x(_main.settings_modal, "Settings")
	_ok(_main.settings_modal._btn_cancel != null, "Settings: кнопка «Отмена» есть")
	if _main.settings_modal._btn_cancel != null:
		_main.settings_modal._btn_cancel.pressed.emit()
	_ok(not _main.settings_modal.visible, "Settings: «Отмена» закрывает окно")

	# About использует ConfirmModal: крестика нет, закрывает «Отмена».
	_main._show_about()
	_ok(_main.confirm_modal.visible, "About открыт")
	_assert_no_window_x(_main.confirm_modal, "About")
	_ok(_main.confirm_modal._btn_no != null, "About: кнопка закрытия есть")
	if _main.confirm_modal._btn_no != null:
		_main.confirm_modal._btn_no.pressed.emit()
	_ok(not _main.confirm_modal.visible, "About: явная кнопка закрывает окно")

	# Confirm выхода в меню: крестика нет, _answer(false) закрывает и не выходит.
	_main._confirm_to_menu()
	_ok(_main.confirm_modal.visible, "Confirm выхода открыт")
	_assert_no_window_x(_main.confirm_modal, "Confirm")
	_main.confirm_modal._answer(false)
	_ok(not _main.confirm_modal.visible, "Confirm: _answer(false) закрывает окно")
	_eq(_controller.phase, &"hour", "Confirm(false) не выходит из часа")


## В модалках нет «крестика» (ни _btn_x, ни кнопки BtnX, ни WindowFrame-закрытия).
func _assert_no_window_x(node, label: String) -> void:
	if node == null:
		_fail("%s: модалка отсутствует" % label)
		return
	_eq(node.get("_btn_x"), null, "%s: _btn_x отсутствует" % label)
	var x_btn = node.get_node_or_null("BtnX")
	_ok(x_btn == null or not (x_btn as Control).visible,
		"%s: кнопки-крестика нет" % label)
	for child in node.get_children():
		if child is Control and child.get("close_enabled") != null:
			_ok(not bool(child.get("close_enabled")),
				"%s: WindowFrame.close_enabled = false" % label)


func _test_settings() -> void:
	_main._open_settings()
	_ok(_main.settings_modal.visible, "_open_settings показывает SettingsModal")

	# До «Подтвердить» изменения остаются черновиком и не применяются.
	var sfx_before := float(_audio.sfx_volume)
	_main.settings_modal._sfx.set_value(20)
	_main.settings_modal._music.set_value(30)
	_main.settings_modal._on_calm(true)
	_approx(float(_audio.sfx_volume), sfx_before, 0.001,
		"ползунок не применяет громкость до подтверждения")
	SaveManager.delete_save()
	_main.settings_modal._confirm()
	_ok(not _main.settings_modal.visible, "«Подтвердить» закрывает настройки")
	_approx(float(_audio.sfx_volume), 0.2, 0.001, "громкость SFX применена")
	_approx(float(_audio.music_volume), 0.3, 0.001, "громкость музыки применена")
	_ok(_main._settings_persist_allowed(), "в фазе hour запись настроек в save разрешена")
	_ok(SaveManager.has_save(), "настройки в фазе hour пишут save.json")
	_eq(_saved_settings_sfx(), 20, "save.json содержит применённые настройки")
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

	# Отмена/X не применяют черновик и не пишут save.
	_main._open_settings()
	_main.settings_modal._sfx.set_value(90)
	_main.settings_modal.close()
	_approx(float(_audio.sfx_volume), 0.2, 0.001, "отмена не применяет громкость")
	var saved_after_cancel = _game.stats.get("settings", {})
	_ok(saved_after_cancel is Dictionary and int(saved_after_cancel.get("sfx", -1)) == 20,
		"отмена не пишет настройки в save")
	_eq(_saved_settings_sfx(), 20, "отмена не переписывает save.json")

	# «Сброс» возвращает черновик к DEFAULT_STATE, но не применяет.
	_main._open_settings()
	_main.settings_modal._on_reset()
	var draft: Dictionary = _main.settings_modal.get_state()
	_eq(int(draft.get("sfx", -1)), 70, "«Сброс» вернул SFX к 70")
	_approx(float(_audio.sfx_volume), 0.2, 0.001, "«Сброс» не применяет настройки")
	_main.settings_modal.close()

	# Выключение спокойного фона возвращает dither, Backdrop остаётся видимым.
	_main.settings_modal.open({
		"sfx": 20, "music": 30, "calm_bg": false, "fullscreen": false,
	})
	_main.settings_modal._confirm()
	_ok(_main._backdrop != null and bool(_main._backdrop.visible),
		"обычный фон не скрывает Backdrop")
	_ok(_main._backdrop != null and not bool(_main._backdrop.calm),
		"обычный фон сбрасывает Backdrop.calm=false")


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


## На экране итогов настройки применяются, но results-save не перезаписывается.
func _test_run_result_settings_no_write() -> void:
	_controller._finish_run("test")
	_eq(_controller.phase, &"run_result", "контроллер перешёл в run_result")
	_ok(not _main._settings_persist_allowed(),
		"в фазе run_result запись настроек в save запрещена")
	_ok(SaveManager.has_save(), "_finish_run записал results-save")
	_ok(_main.run_result_modal.visible, "экран итогов показан")
	var before_text := FileAccess.get_file_as_string(SaveManager.SAVE_PATH)
	var before_mtime := FileAccess.get_modified_time(SaveManager.SAVE_PATH)

	_main._open_settings()
	_main.settings_modal._sfx.set_value(15)
	_main.settings_modal._confirm()
	_eq(FileAccess.get_file_as_string(SaveManager.SAVE_PATH), before_text,
		"results-save не перезаписан настройками с экрана итогов")
	_eq(FileAccess.get_modified_time(SaveManager.SAVE_PATH), before_mtime,
		"mtime results-save не изменился")
	_eq(int((_game.stats.get("settings", {}) as Dictionary).get("sfx", -1)), 15,
		"настройки с экрана итогов применены в памяти")


func _to_menu() -> void:
	_main._to_menu()


func _esc() -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	return ev


func _finish() -> void:
	# Возвращаем пользовательский save.json в исходное состояние.
	if _save_backed_up:
		if _had_save:
			var file := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
			if file != null:
				file.store_string(_backup_save)
				file.flush()
				file.close()
		else:
			SaveManager.delete_save()
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
