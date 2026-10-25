extends Control
## Главный экран PEAK HOUR 97 — собранный каркас в стиле shareware 90-х.
##
## Только UI и мок-данные: настоящей игровой логики здесь нет.
## Раскладка фиксированная, 1280×720, без контейнеров — всё на абсолютных
## координатах, чтобы пиксели совпадали с макетом.

const W := 1280.0
const H := 720.0
## Размер окна в оконном режиме (project.godot: window_width/height_override).
const DESKTOP_WINDOW_SIZE := Vector2i(1920, 1080)

## Preload вместо глобального имени: работает и без прогретого class cache.
const GAME_CONTROLLER := preload("res://scripts/game_controller.gd")
const RENAME_MODAL := preload("res://scripts/ui/rename_modal.gd")

var title_bar: WindowFrame
var menu_bar: Panel90
var workspace: Panel90
var tree_window: WindowFrame
var files_window: WindowFrame
var receive_window: WindowFrame
var send_window: WindowFrame
var slots_strip: Panel90
var status_bar: StatusBar
var toast_layer: ToastLayer

var tree: TreePanel
var grid: FileGrid
## Маскот-туториал (scripts/ui/tutorial_mascot.gd).
var mascot: TutorialMascot = null
## Кнопка «МАГАЗИН» в строке меню: видна только в подготовке и после открытия.
var _shop_btn: Button90 = null
## Кнопка «НАЧАТЬ ЧАС»: акцентная и только в подготовке.
var _start_btn: Button90 = null
## Кнопка «МЕНЮ» в верхней строке (единственная, без демо-пунктов).
var _menu_btn: Button90 = null

var packets: Array[PacketCard] = []
var requests: Array[RequestCard] = []
var slot_cells: Array[SlotCell] = []
var slot_count_label: Label

var _menus: Dictionary = {}
var _selected_file := ""
var _extra_folders: Array = []

## Интеграция с игровым циклом (см. scripts/game_controller.gd).
var controller = null
var modal_root: Control
var main_menu: MainMenu
var shop_modal: ShopModal
var hour_result_modal: HourResultModal
var run_result_modal: RunResultModal
var pause_modal: PauseModal
var settings_modal: SettingsModal
var confirm_modal: ConfirmModal
var rename_modal = null
var _rename_folder_id := ""
## Какое действие подтверждает confirm_modal: "" / "menu" (см. _confirm_to_menu).
var _confirm_action := ""
var _backdrop: Control = null
var _hour_ui_shown := false
var _hour_signals_connected := false
## Активная модалка мини-игры (соединение/отправка); вторая не открывается.
var _modal_game: Control = null

## Туториал первого часа показывается один раз за запуск.
var _tutorial_shown := false
var _tutorial_intro_shown := false
var _tutorial_after_shown := false
## Шаги первого часа: текст, номер шага и задержка от старта часа.
const TUTORIAL_STEPS := [
	{"text": "Перетащи пакет в папку", "step": 1, "delay": 2.0},
	{"text": "Собери файлы в запрос", "step": 2, "delay": 20.0},
	{"text": "TCP: нажми Соединиться и попади три раза", "step": 3, "delay": 40.0},
]
const TUTORIAL_STEP_SECONDS := 7.0

## --- Автообновление подготовки по сигналам FileRegistry -------------------
## Реестр, к которому подключены сигналы (меняется после load/new_run).
var _bound_registry = null
var _registry_refresh_queued := false
## Последние применённые настройки: Game.start_new_run очищает stats,
## поэтому кэшируем их здесь и возвращаем в stats после нового забега.
var _settings_cache: Dictionary = {}

## --- Атаки часа: оверлей DDoS и щит-карантин -----------------------------
var _ddos_overlay = null
var _packet_shift := 0.0
var _shield_receive = null
var _shield_send = null
var _shield_holding := false
var _shield_hold_acc := 0.0

## Автопауза часа, пока открыты служебные модалки (настройки/подтверждение/имя).
var _auto_paused := false
## Проверка web-fullscreen после асинхронного запроса браузера.
var _fs_verify_token := 0

## --- Скролл списка ПРИЁМ (5–8 пакетов не влезают в 416×264) ---------------
var _recv_bar: ScrollBar90
var _recv_scroll := 0.0
const RECV_CARD_H := 48.0
const RECV_WHEEL_STEP := 24.0

## --- Карточки ОТПРАВКИ: 3–4 запроса не влезают в 252 px при шаге 64 -------
## Внутри RequestCard контент заканчивается на y=56, поэтому 60 px достаточно.
const REQ_CARD_H := 64.0
const REQ_CARD_H_COMPACT := 60.0

## --- Поиск по файлам (апгрейд shop_search) --------------------------------
var _search_edit: LineEdit
## Полный список файлов текущей папки; в grid уходит отфильтрованный.
var _current_files: Array = []


func _ready() -> void:
	_build()
	_connect_all()
	controller = GAME_CONTROLLER.new()
	controller.name = "GameController"
	add_child(controller)
	controller.phase_changed.connect(_on_phase)
	_build_modals()
	_apply_saved_settings()
	_init_mascot()
	_bind_registry_signals()
	main_menu.set_has_save(controller.has_save())
	main_menu.visible = true
	_update_shop_visibility()
	if _demo_requested():
		call_deferred("_start_demo")


func _process(delta: float) -> void:
	if controller == null:
		return
	if controller.phase == GAME_CONTROLLER.PHASE_HOUR:
		_sync_modal_pause()
		_tick_shield_hold(delta)
		controller.tick(delta)
		# tick мог завершить час — тогда экран уже переключился на отчёт.
		if controller.phase == GAME_CONTROLLER.PHASE_HOUR:
			_refresh_hour()


## Отпускание ЛКМ в любом месте снимает удержание щита.
func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
		_on_shield_release()


## Esc: закрывает верхнюю модалку, ставит смену на паузу или игнорируется.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo or key.keycode != KEY_ESCAPE:
		return
	# Мини-игра сама обрабатывает Esc — не перехватываем.
	if _modal_game != null:
		return
	if settings_modal != null and settings_modal.visible:
		settings_modal.close()
		_mark_input_handled()
		return
	if rename_modal != null and rename_modal.visible:
		rename_modal.close()
		_mark_input_handled()
		return
	if confirm_modal != null and confirm_modal.visible:
		confirm_modal._answer(false)
		_mark_input_handled()
		return
	if pause_modal != null and pause_modal.visible:
		_resume_game()
		_mark_input_handled()
		return
	if controller != null and controller.phase == GAME_CONTROLLER.PHASE_HOUR:
		_pause_game()
		_mark_input_handled()
		return
	# Главное меню и остальные экраны Esc не трогают.


func _mark_input_handled() -> void:
	if is_inside_tree() and get_viewport() != null:
		get_viewport().set_input_as_handled()


## Потеря фокуса окна во время часа — автоматическая пауза.
func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_FOCUS_OUT:
		return
	if controller == null or controller.phase != GAME_CONTROLLER.PHASE_HOUR:
		return
	if _modal_game != null:
		return
	if pause_modal != null and pause_modal.visible:
		return
	_pause_game()


# --------------------------------------------------------------------------
# Пауза, настройки, выход в меню
# --------------------------------------------------------------------------

func _pause_game() -> void:
	if controller == null or controller.phase != GAME_CONTROLLER.PHASE_HOUR:
		return
	if _modal_game != null:
		return
	controller.set_paused(true)
	if pause_modal != null:
		pause_modal.open()


func _resume_game() -> void:
	if controller != null:
		controller.set_paused(false)
	_auto_paused = false
	if pause_modal != null:
		pause_modal.visible = false


## Служебные окна часа (настройки, подтверждение, переименование) держат
## таймеры на паузе. Игровые окна ConnectionGame/MiniGame сюда не входят.
func _sync_modal_pause() -> void:
	if controller == null or controller.phase != GAME_CONTROLLER.PHASE_HOUR:
		_auto_paused = false
		return
	if _modal_game != null:
		return
	var blocking := false
	if settings_modal != null and settings_modal.visible:
		blocking = true
	elif confirm_modal != null and confirm_modal.visible:
		blocking = true
	elif rename_modal != null and rename_modal.visible:
		blocking = true
	if blocking:
		if not controller.paused:
			controller.set_paused(true)
			_auto_paused = true
	elif _auto_paused and (pause_modal == null or not pause_modal.visible):
		controller.set_paused(false)
		_auto_paused = false


func _on_settings_closed() -> void:
	_sync_modal_pause()


func _open_settings() -> void:
	if settings_modal == null:
		return
	if mascot != null:
		mascot.hide_message()
	var calm := false
	if _backdrop != null:
		calm = bool(_backdrop.calm)
	# Галочка полного экрана — применённая настройка. DisplayServer.window_get_mode()
	# на Wayland/niri может ложно сообщать FULLSCREEN для окна 1920×1080, поэтому
	# фактический режим окна используем только если настройка ещё не известна.
	var full := bool(_settings_cache.get("fullscreen", false))
	if not _settings_cache.has("fullscreen") and DisplayServer.get_name() != "headless":
		var mode := DisplayServer.window_get_mode()
		full = mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
			or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	settings_modal.open({
		"sfx": int(round(Audio.sfx_volume * 100.0)),
		"music": int(round(Audio.music_volume * 100.0)),
		"calm_bg": calm,
		"fullscreen": full,
		"vhs": main_menu.is_vhs_enabled() if main_menu != null \
			else bool(_settings_cache.get("vhs", true)),
	})
	_sync_modal_pause()


## Применить настройки из SettingsModal и (по умолчанию) сохранить их.
func _apply_settings(values: Dictionary, persist: bool = true) -> void:
	var sfx := clampi(int(values.get("sfx", int(round(Audio.sfx_volume * 100.0)))), 0, 100)
	var music := clampi(int(values.get("music", int(round(Audio.music_volume * 100.0)))), 0, 100)
	var calm := bool(values.get("calm_bg", true))
	var full := bool(values.get("fullscreen", false))
	var vhs := bool(values.get("vhs", true))
	Audio.set_sfx_volume(float(sfx) / 100.0)
	Audio.set_music_volume(float(music) / 100.0)
	if _backdrop != null:
		# Спокойный фон — та же подложка, но залитая бумагой вместо dither.
		_backdrop.visible = true
		_backdrop.calm = calm
		_backdrop.queue_redraw()
	if main_menu != null:
		# VHS живёт только на главном меню; игровые панели и модалки не трогаем.
		main_menu.set_vhs_enabled(vhs)
	_apply_fullscreen(full)
	_settings_cache = {"sfx": sfx, "music": music, "calm_bg": calm,
		"fullscreen": full, "vhs": vhs}
	if Game.stats != null:
		Game.stats["settings"] = _settings_cache.duplicate(true)
	# В главном меню забега ещё нет: настройки живут в Game.stats, но не должны
	# создавать/перезаписывать save.json пустым состоянием холодного старта.
	if persist and _settings_persist_allowed():
		Game.save_game()


## Можно ли писать настройки в игровой save.
## Явный whitelist активного забега: только подготовка и час. В MENU,
## HOUR_RESULT и RUN_RESULT настройки применяются в памяти, но save.json
## не трогаем — иначе настройки из меню перезапишут отчёт/итоги забега.
func _settings_persist_allowed() -> bool:
	if controller == null:
		return false
	return controller.phase == GAME_CONTROLLER.PHASE_PREP \
		or controller.phase == GAME_CONTROLLER.PHASE_HOUR


## Загрузить сохранённые настройки (если забег их принёс из сейва).
func _apply_saved_settings() -> void:
	var saved = Game.stats.get("settings", {})
	if not (saved is Dictionary) or (saved as Dictionary).is_empty():
		return
	_settings_cache = (saved as Dictionary).duplicate(true)
	_apply_settings(_settings_cache, false)


func _apply_fullscreen(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	# В web DisplayServer-режим может игнорироваться внутри iframe: просим
	# Fullscreen API у браузера и проверяем результат асинхронно.
	if OS.has_feature("web"):
		_apply_fullscreen_web(on)
		return
	if not on:
		# Wayland/niri после выхода из fullscreen тайлит окно (~936×979):
		# сразу просим оконный размер, а затем подтверждаем его следующим
		# кадром — tiling-WM применяет свой тайл уже после смены режима и
		# игнорирует размер, запрошенный в том же кадре.
		if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(DESKTOP_WINDOW_SIZE)
		_confirm_desktop_size()
		return
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


## Повторно просит оконный размер после того, как WM применил WINDOWED.
func _confirm_desktop_size() -> void:
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless" or OS.has_feature("web"):
		return
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED \
			and DisplayServer.window_get_size() != DESKTOP_WINDOW_SIZE:
		DisplayServer.window_set_size(DESKTOP_WINDOW_SIZE)


func _apply_fullscreen_web(on: bool) -> void:
	var script := ""
	if on:
		script = "(function(){try{var d=document.documentElement;"
		script += "var p=d.requestFullscreen?d.requestFullscreen():Promise.reject();"
		script += "if(p&&p.catch){p.catch(function(){});}return true;}catch(e){return false;}})()"
	else:
		script = "(function(){try{if(document.fullscreenElement){"
		script += "var p=document.exitFullscreen();if(p&&p.catch){p.catch(function(){});}"
		script += "}return true;}catch(e){return false;}})()"
	var js_ok := false
	if JavaScriptBridge.get_interface("document") != null:
		js_ok = bool(JavaScriptBridge.eval(script, true))
	if not js_ok:
		# Fallback: платформенный режим окна (работает, если браузер разрешает).
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if on \
			else DisplayServer.WINDOW_MODE_WINDOWED
		DisplayServer.window_set_mode(mode)
		return
	# requestFullscreen асинхронен: подтвердим через кадр-другой.
	_fs_verify_token += 1
	_verify_web_fullscreen.call_deferred(on, _fs_verify_token)


func _verify_web_fullscreen(on: bool, token: int) -> void:
	await get_tree().create_timer(0.25).timeout
	if token != _fs_verify_token or not is_inside_tree():
		return
	var actual := false
	if JavaScriptBridge.get_interface("document") != null:
		actual = bool(JavaScriptBridge.eval("!!document.fullscreenElement", true))
	if on and not actual:
		_on_fullscreen_denied()


## Браузер/iframe не дал полный экран — снимаем ложную галочку и сообщаем.
func _on_fullscreen_denied() -> void:
	_settings_cache["fullscreen"] = false
	if Game.stats != null:
		Game.stats["settings"] = _settings_cache.duplicate(true)
	if settings_modal != null:
		settings_modal.set_fullscreen(false)
	_toast("БРАУЗЕР НЕ РАЗРЕШИЛ ПОЛНЫЙ ЭКРАН", "warn")


func _confirm_to_menu() -> void:
	if confirm_modal == null:
		return
	_confirm_action = "menu"
	var in_hour: bool = controller != null \
		and controller.phase == GAME_CONTROLLER.PHASE_HOUR
	var detail := "Текущий час будет прерван, прогресс подготовки сохранён."
	if not in_hour:
		detail = "Прогресс подготовки сохранён."
	confirm_modal.ask("Выйти в главное меню?", detail, "Выйти", "Отмена", true)
	_sync_modal_pause()


## Информационное окно «О программе» (пункт меню МЕНЮ).
func _show_about() -> void:
	if confirm_modal == null:
		return
	_confirm_action = ""
	confirm_modal.ask("PEAK HOUR 97",
		"Диспетчер файлового обмена · версия 0.1.0 · Godot 4.7.2",
		"OK", "Закрыть")
	_sync_modal_pause()


func _to_menu() -> void:
	if controller != null:
		controller.save()
	if pause_modal != null:
		pause_modal.visible = false
	if settings_modal != null:
		settings_modal.visible = false
	if confirm_modal != null:
		confirm_modal.visible = false
	_auto_paused = false
	if controller != null:
		# В час фаза остаётся hour: таймер держим на паузе до «Продолжить».
		controller.set_paused(controller.phase == GAME_CONTROLLER.PHASE_HOUR)
	if main_menu != null:
		main_menu.set_has_save(true)
		main_menu.visible = true


# --------------------------------------------------------------------------
# Интеграция: меню, магазин, подготовка
# --------------------------------------------------------------------------

func _build_modals() -> void:
	modal_root = Control.new()
	modal_root.name = "ModalRoot"
	modal_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(modal_root)

	main_menu = MainMenu.new()
	main_menu.name = "MainMenu"
	modal_root.add_child(main_menu)
	main_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_menu.new_run.connect(_start_new_run)
	main_menu.continue_run.connect(_continue_run)
	main_menu.settings.connect(_open_settings)
	main_menu.about.connect(_show_about)
	main_menu.visible = true

	shop_modal = ShopModal.new()
	shop_modal.name = "ShopModal"
	modal_root.add_child(shop_modal)
	shop_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shop_modal.buy_requested.connect(_on_shop_buy)
	shop_modal.closed.connect(func() -> void: shop_modal.visible = false)
	shop_modal.visible = false

	hour_result_modal = HourResultModal.new()
	hour_result_modal.name = "HourResultModal"
	modal_root.add_child(hour_result_modal)
	hour_result_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hour_result_modal.next_pressed.connect(_on_hour_result_next)
	hour_result_modal.closed.connect(func() -> void: hour_result_modal.visible = false)
	hour_result_modal.visible = false

	run_result_modal = RunResultModal.new()
	run_result_modal.name = "RunResultModal"
	modal_root.add_child(run_result_modal)
	run_result_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	run_result_modal.new_run.connect(_on_run_result_new)
	run_result_modal.to_menu.connect(_on_run_result_menu)
	run_result_modal.closed.connect(func() -> void: run_result_modal.visible = false)
	run_result_modal.visible = false

	pause_modal = PauseModal.new()
	pause_modal.name = "PauseModal"
	modal_root.add_child(pause_modal)
	pause_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_modal.resumed.connect(_resume_game)
	pause_modal.settings_requested.connect(_open_settings)
	pause_modal.menu_requested.connect(_confirm_to_menu)
	pause_modal.visible = false

	settings_modal = SettingsModal.new()
	settings_modal.name = "SettingsModal"
	modal_root.add_child(settings_modal)
	settings_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_modal.settings_changed.connect(_apply_settings)
	settings_modal.closed.connect(_on_settings_closed)
	settings_modal.visible = false

	confirm_modal = ConfirmModal.new()
	confirm_modal.name = "ConfirmModal"
	modal_root.add_child(confirm_modal)
	confirm_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	confirm_modal.answered.connect(func(yes: bool) -> void:
		var action := _confirm_action
		_confirm_action = ""
		if yes:
			if action == "menu":
				_to_menu()
			elif action.begins_with("destroy:"):
				_destroy_folder_contents(action.substr("destroy:".length()))
		_sync_modal_pause()
	)
	confirm_modal.visible = false

	rename_modal = RENAME_MODAL.new()
	rename_modal.name = "RenameModal"
	modal_root.add_child(rename_modal)
	rename_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rename_modal.rename_confirmed.connect(_on_rename_confirmed)
	rename_modal.closed.connect(func() -> void:
		rename_modal.visible = false
		_sync_modal_pause())
	rename_modal.visible = false


func _start_new_run() -> void:
	if controller == null:
		return
	_hour_ui_shown = false
	_tutorial_shown = false
	_tutorial_intro_shown = false
	_tutorial_after_shown = false
	if mascot != null:
		mascot.hide_message()
	if hour_result_modal != null:
		hour_result_modal.visible = false
	if run_result_modal != null:
		run_result_modal.visible = false
	controller.new_run(int(Time.get_unix_time_from_system()))
	# new_run сбрасывает stats — возвращаем настройки, чтобы они жили между забегами.
	if not _settings_cache.is_empty() and Game.stats != null:
		Game.stats["settings"] = _settings_cache.duplicate(true)
	# Game.start_new_run создаёт новый FileRegistry — переподключаем сигналы.
	_bind_registry_signals()
	main_menu.visible = false
	_refresh_prep()


## Публичный алиас для тестов/инструментов.
func start_new_run() -> void:
	_start_new_run()


# --------------------------------------------------------------------------
# Demo-режим для скриншотов (?demo=1 в web-сборке)
# --------------------------------------------------------------------------

func _demo_requested() -> bool:
	if not OS.has_feature("web"):
		return false
	var query := str(JavaScriptBridge.eval("window.location.search", true))
	return query.find("demo=1") >= 0


## Чистая сцена часа для скриншотов: 3 пакета и 2 запроса, без атак.
func _start_demo() -> void:
	if controller == null:
		return
	_start_new_run()
	# Запросы спавнятся только при наличии файлов в реестре.
	var prep: Dictionary = controller.prep_data()
	var folder_id := ""
	for sec in prep.get("sections", []):
		var folders: Array = sec.get("folders", [])
		if not folders.is_empty():
			folder_id = str(folders[0].get("id", ""))
			break
	if Game.registry != null and not folder_id.is_empty():
		var demo_files := [["договор_97", "text"], ["смета_демо", "text"],
			["логотип_демо", "photo"]]
		for pair in demo_files:
			if Game.registry.find_by_name(str(pair[0])) == null:
				Game.registry.create_file(str(pair[0]), str(pair[1]), folder_id)
		_refresh_prep()
	_on_start_hour()
	var director = controller.hour_director
	if director != null:
		director.spawn_packet_now("text", "tcp")
		director.spawn_packet_now("sound", "udp")
		director.spawn_packet_now("photo", "tcp")
		director.spawn_request_now()
		director.spawn_request_now()
	_refresh_hour()
	_toast("DEMO", "success")


func _continue_run() -> void:
	if controller == null:
		return
	if not controller.continue_run():
		_toast("СОХРАНЕНИЕ НЕ НАЙДЕНО", "warn")
		return
	# load_game восстанавливает реестр — сигналы старого больше не нужны.
	_bind_registry_signals()
	_apply_saved_settings()
	main_menu.visible = false
	_refresh_prep()


func _refresh_prep() -> void:
	if controller == null:
		return
	_sync_search_layout()
	var d: Dictionary = controller.prep_data()
	var sections: Array = d.get("sections", [])
	tree.set_data(sections)
	tree_window.set_title("ДИСКИ",
		_plural_ru(_count_folders(sections), "ПАПКА", "ПАПКИ", "ПАПОК"))

	var folder_id := ""
	var folder_name := ""
	var section_id := ""
	for sec in sections:
		var folders: Array = sec.get("folders", [])
		if not folders.is_empty():
			folder_id = str(folders[0].get("id", ""))
			folder_name = str(folders[0].get("name", ""))
			section_id = str(sec.get("id", ""))
			break

	_clear_hour_panels()
	if folder_id.is_empty():
		grid.set_folder("", "ПАПКА", "C: \\")
		_current_files = []
		grid.set_files([])
		files_window.set_title("ФАЙЛЫ · ПУСТО",
			_plural_ru(0, "ОБЪЕКТ", "ОБЪЕКТА", "ОБЪЕКТОВ"))
		if workspace != null:
			workspace.title_right = _plural_ru(0, "ОБЪЕКТ", "ОБЪЕКТА", "ОБЪЕКТОВ")
	else:
		tree.select_folder(folder_id)
		_show_folder(folder_id, folder_name, section_id, d)
	_update_status(d)
	_update_shop_visibility()
	_maybe_show_prep_tutorial()


func _count_folders(sections: Array) -> int:
	var n := 0
	for sec in sections:
		n += (sec.get("folders", []) as Array).size()
	return n


## Русская плюрализация счётчика: 1 папка / 2 папки / 5 папок.
func _plural_ru(n: int, one: String, few: String, many: String) -> String:
	var a := absi(n) % 100
	if a >= 11 and a <= 14:
		return "%d %s" % [n, many]
	match a % 10:
		1: return "%d %s" % [n, one]
		2, 3, 4: return "%d %s" % [n, few]
		_: return "%d %s" % [n, many]


func _show_folder(folder_id: String, folder_name: String, section_id: String, d: Dictionary) -> void:
	var letter := section_id.left(1).to_upper()
	if letter.is_empty():
		letter = "C"
	var path := "%s: \\ %s" % [letter, folder_name.to_upper()]
	# Смена папки — сбрасываем строку поиска, чтобы фильтр не «терял» файлы.
	if _search_edit != null and grid != null and grid.folder_id != folder_id:
		_search_edit.text = ""
	grid.set_folder(folder_id, folder_name.to_upper(), path)
	var files: Array = (d.get("files", {}) as Dictionary).get(folder_id, [])
	_current_files = files.duplicate()
	_apply_file_filter()


# --------------------------------------------------------------------------
# Маскот-туториал (БАЙТ)
# --------------------------------------------------------------------------

func _init_mascot() -> void:
	mascot = TutorialMascot.new()
	mascot.name = "TutorialMascot"
	# Компактный БАЙТ: 64 px робот + облачко 210 px, в свободном низу сетки.
	mascot.bubble_width = 210.0
	mascot.set_robot_scale(0.67)
	add_child(mascot)
	mascot.position = Vector2(548, 492)
	mascot.visible = false
	# Маскот живёт под модалками, но над рабочим столом.
	if modal_root != null:
		move_child(mascot, modal_root.get_index())


## В headless маскот не показываем: он не должен влиять на тесты.
func _tutorial_enabled() -> bool:
	return mascot != null and DisplayServer.get_name() != "headless"


func _maybe_show_prep_tutorial() -> void:
	if not _tutorial_enabled() or controller == null:
		return
	if controller.phase != GAME_CONTROLLER.PHASE_PREP:
		return
	if not _tutorial_intro_shown:
		_tutorial_intro_shown = true
		mascot.set_step(0)
		mascot.show_message("Привет, я БАЙТ. Час пик начинается с приёма пакетов.", 8.0)
		return
	var hours_done := int(Game.stats.get("hours_done", 0)) if Game.stats != null else 0
	if _tutorial_after_shown or Game.hour <= 1 or hours_done <= 0:
		return
	_tutorial_after_shown = true
	mascot.set_step(0)
	if Game.feature_unlocked("shop"):
		mascot.show_message("Магазин открылся — загляни в «МАГАЗИН» в строке меню.", 7.0)
	else:
		mascot.show_message("Дальше будет сложнее. Держи SLA выше нуля.", 7.0)


## Шаг туториала часа 1; вызывается по таймеру и не блокирует игру.
func _show_tutorial_step(index: int) -> void:
	if not _tutorial_enabled() or controller == null:
		return
	if controller.phase != GAME_CONTROLLER.PHASE_HOUR or Game.hour != 1:
		return
	if index < 0 or index >= TUTORIAL_STEPS.size():
		return
	var step: Dictionary = TUTORIAL_STEPS[index]
	mascot.set_step(int(step.get("step", index + 1)))
	mascot.show_message(str(step.get("text", "")), TUTORIAL_STEP_SECONDS)


# --------------------------------------------------------------------------
# Автообновление подготовки по сигналам FileRegistry
# --------------------------------------------------------------------------

## Переподключить registry_changed к актуальному реестру Game.
func _bind_registry_signals() -> void:
	var reg = Game.registry
	if reg == _bound_registry:
		return
	if _bound_registry != null and is_instance_valid(_bound_registry):
		if _bound_registry.has_signal("registry_changed") \
				and _bound_registry.registry_changed.is_connected(_on_registry_changed):
			_bound_registry.registry_changed.disconnect(_on_registry_changed)
	_bound_registry = reg
	if reg != null and reg.has_signal("registry_changed") \
			and not reg.registry_changed.is_connected(_on_registry_changed):
		reg.registry_changed.connect(_on_registry_changed)


func _on_registry_changed() -> void:
	# Сигнал приходит пачками (file + folder + registry) — склеиваем в один кадр.
	if _registry_refresh_queued:
		return
	_registry_refresh_queued = true
	call_deferred("_apply_registry_refresh")


func _apply_registry_refresh() -> void:
	_registry_refresh_queued = false
	if controller == null or not is_inside_tree():
		return
	var d: Dictionary = controller.prep_data()
	var folder_id := str(grid.folder_id) if grid != null else ""
	var files_map: Dictionary = d.get("files", {})
	if not folder_id.is_empty() and files_map.has(folder_id):
		_refresh_tree_counts(d)
		_refresh_current_folder(d, folder_id)
	elif controller.phase == GAME_CONTROLLER.PHASE_PREP:
		# Текущей папки больше нет — безопасно перерисовать подготовку.
		_refresh_prep()
	else:
		_refresh_tree_counts(d)


## Обновить только сетку текущей папки, не пересоздавая дерево.
func _refresh_current_folder(d: Dictionary, folder_id: String) -> void:
	var files_map: Dictionary = d.get("files", {})
	_current_files = (files_map.get(folder_id, []) as Array).duplicate()
	var meta := _folder_meta(d, folder_id)
	if not meta.is_empty():
		var folder_name := str(meta.get("name", ""))
		var section_id := str(meta.get("section", ""))
		var letter := section_id.left(1).to_upper()
		if letter.is_empty():
			letter = "C"
		grid.set_folder(folder_id, folder_name.to_upper(),
			"%s: \\ %s" % [letter, folder_name.to_upper()])
	# set_files заново строит FileCard с актуальным state (attached/locked/…).
	_apply_file_filter()


func _refresh_tree_counts(d: Dictionary) -> void:
	if tree == null:
		return
	var sections: Array = d.get("sections", [])
	var known: Dictionary = {}
	for sec in sections:
		for fol in sec.get("folders", []):
			known[str(fol.get("id", ""))] = int(fol.get("count", 0))
	var current: Dictionary = {}
	for e in tree.get("_rows"):
		var row = e["row"]
		if row != null and not row.is_section:
			current[str(row.folder_id)] = true
	var same := known.size() == current.size()
	if same:
		for id in known.keys():
			if not current.has(id):
				same = false
				break
	if not same:
		var selected := str(grid.folder_id) if grid != null else ""
		tree.set_data(sections)
		if known.has(selected):
			tree.select_folder(selected)
	for id in known.keys():
		if same:
			tree.update_count(str(id), int(known[id]))
	if tree_window != null:
		tree_window.set_title("ДИСКИ",
			_plural_ru(_count_folders(sections), "ПАПКА", "ПАПКИ", "ПАПОК"))


# --------------------------------------------------------------------------
# Магазин: доступен только в подготовке и после открытия (час 2)
# --------------------------------------------------------------------------

func _update_shop_visibility() -> void:
	if _shop_btn == null:
		return
	var in_prep: bool = controller != null \
		and controller.phase == GAME_CONTROLLER.PHASE_PREP
	_shop_btn.visible = in_prep and Game.feature_unlocked("shop")
	if _start_btn != null:
		_start_btn.visible = in_prep


# --------------------------------------------------------------------------
# Поиск по файлам (апгрейд shop_search)
# --------------------------------------------------------------------------

func _file_search_unlocked() -> bool:
	return int(Game.upgrades.get("search_unlocked", 0)) > 0


## Показать/скрыть поле поиска и освободить под него полосу над сеткой.
func _sync_search_layout() -> void:
	if _search_edit == null or grid == null or files_window == null \
			or files_window.content == null:
		return
	var on := _file_search_unlocked()
	_search_edit.visible = on
	var top := 22.0 if on else 0.0
	grid.position = Vector2(0, top)
	grid.size = Vector2(files_window.content.size.x,
		maxf(80.0, files_window.content.size.y - top))


func _on_search_changed(_text: String) -> void:
	_apply_file_filter()


## Заголовок окна ФАЙЛЫ: при активном фильтре показываем «N ИЗ M».
func _update_files_title() -> void:
	if files_window == null or grid == null:
		return
	var folder_label := _folder_name(grid.folder_id).to_upper()
	if folder_label.is_empty():
		folder_label = "ПАПКА"
	var total := _current_files.size()
	var shown := grid.get_cards().size()
	var hint := "ПУСТО"
	if total > 0:
		if shown == total:
			hint = _plural_ru(total, "ОБЪЕКТ", "ОБЪЕКТА", "ОБЪЕКТОВ")
		else:
			hint = "%d из %s" % [shown,
				_plural_ru(total, "ОБЪЕКТ", "ОБЪЕКТА", "ОБЪЕКТОВ")]
	files_window.set_title("ФАЙЛЫ · %s" % folder_label, hint)
	if workspace != null:
		workspace.title_right = _plural_ru(total, "ОБЪЕКТ", "ОБЪЕКТА", "ОБЪЕКТОВ")


## Фильтр текущей папки по подстроке имени (регистронезависимо).
func _apply_file_filter() -> void:
	if grid == null:
		return
	var query := ""
	if _search_edit != null and _search_edit.visible:
		query = _search_edit.text.strip_edges().to_lower()
	if query.is_empty():
		grid.set_files(_current_files)
		_update_files_title()
		return
	var filtered: Array = []
	for f in _current_files:
		var name := str(f.get("name", "")).to_lower()
		var ext := str(f.get("ext", "")).to_lower()
		if name.find(query) >= 0 or ("%s.%s" % [name, ext]).find(query) >= 0:
			filtered.append(f)
	grid.set_files(filtered)
	_update_files_title()


func _folder_meta(d: Dictionary, folder_id: String) -> Dictionary:
	for sec in d.get("sections", []):
		for fol in sec.get("folders", []):
			if str(fol.get("id", "")) == folder_id:
				return {"name": str(fol.get("name", "")), "section": str(sec.get("id", ""))}
	return {}


func _tcp_max(upgrades: Dictionary) -> int:
	return 2 + int(upgrades.get("shop_slot3", 0)) + int(upgrades.get("shop_slot4", 0))


func _update_status(d: Dictionary) -> void:
	var sla := int(round(float(d.get("sla", 0.0))))
	var hour := int(d.get("hour", 1))
	var tcp_max := _tcp_max(d.get("upgrades", {}))
	var max_sla := maxi(1, int(Game.MAX_SLA))
	status_bar.set_metric("money", "$ %d" % int(d.get("money", 0)))
	status_bar.set_metric("sla", "%d / %d" % [sla, max_sla],
		clampf(float(sla) / float(max_sla), 0.0, 1.0))
	status_bar.set_metric("hour", "ЧАС %d" % hour, float(hour - 1) / 9.0)
	status_bar.set_metric("tcp", "0 / %d" % tcp_max, 0.0)
	var buffer_max := 4
	if controller != null and controller.hour_director != null:
		buffer_max = maxi(1, int(controller.hour_director.buffer_limit()))
	status_bar.set_metric("buffer", "0 / %d" % buffer_max, 0.0)
	status_bar.set_metric("channel", "0%", 0.0)


func _clear_hour_panels() -> void:
	_ddos_overlay = null
	_packet_shift = 0.0
	_shield_holding = false
	_shield_hold_acc = 0.0
	for c in receive_window.content.get_children():
		# Скроллбар ПРИЁМА живёт всё время — его не пересоздаём.
		if c == _recv_bar:
			continue
		receive_window.content.remove_child(c)
		c.queue_free()
	for c in send_window.content.get_children():
		send_window.content.remove_child(c)
		c.queue_free()
	packets.clear()
	requests.clear()
	_recv_scroll = 0.0
	if _recv_bar != null:
		var h := maxf(1.0, receive_window.content.size.y)
		_recv_bar.set_metrics(h, h, 0.0)
		_recv_bar.visible = false
	for c in slot_cells:
		if is_instance_valid(c):
			if c.get_parent() != null:
				c.get_parent().remove_child(c)
			c.queue_free()
	slot_cells.clear()
	if slot_count_label != null:
		slot_count_label.text = "0/%d" % _tcp_max(Game.upgrades)
	receive_window.set_title(_padded_title("ПРИЁМ"),
		_plural_ru(0, "ПАКЕТ", "ПАКЕТА", "ПАКЕТОВ"))
	send_window.set_title(_padded_title("ОТПРАВКА"),
		_plural_ru(0, "ЗАПРОС", "ЗАПРОСА", "ЗАПРОСОВ"))
	_update_shield_visuals({})


func _on_phase(phase: StringName) -> void:
	match phase:
		GAME_CONTROLLER.PHASE_PREP:
			_hour_ui_shown = false
			if main_menu != null:
				main_menu.visible = false
			if hour_result_modal != null:
				hour_result_modal.visible = false
			_refresh_prep()
		GAME_CONTROLLER.PHASE_HOUR:
			_show_hour()
			_maybe_show_tutorial()
		GAME_CONTROLLER.PHASE_HOUR_RESULT:
			# Час закончен: _process больше не тикает (phase != hour).
			_hour_ui_shown = false
			if mascot != null:
				mascot.hide_message()
			_open_hour_result()
		GAME_CONTROLLER.PHASE_RUN_RESULT:
			_hour_ui_shown = false
			if mascot != null:
				mascot.hide_message()
			if hour_result_modal != null:
				hour_result_modal.visible = false
			_show_run_result()
		_:
			pass
	_update_shop_visibility()


## Настоящий экран часа: карточки пакетов/запросов, слоты и статус.
func _show_hour() -> void:
	if _hour_ui_shown:
		_refresh_hour()
		return
	_hour_ui_shown = true
	if mascot != null:
		mascot.hide_message()
	_clear_hour_panels()
	_connect_hour_signals()
	_refresh_hour()
	_update_shop_visibility()
	_toast("ЧАС %d НАЧАЛСЯ" % Game.hour, "success")


## Подсказки первого часа: три шага маскота с задержкой, один раз за запуск.
func _maybe_show_tutorial() -> void:
	if _tutorial_shown or not _tutorial_enabled():
		return
	if Game.hour != 1:
		return
	_tutorial_shown = true
	for i in TUTORIAL_STEPS.size():
		var step: Dictionary = TUTORIAL_STEPS[i]
		var timer := get_tree().create_timer(float(step.get("delay", 0.0)))
		timer.timeout.connect(_show_tutorial_step.bind(i))


## Сигналы контроллера, которые нужны UI часа (подключаются один раз).
func _connect_hour_signals() -> void:
	if controller == null or _hour_signals_connected:
		return
	_hour_signals_connected = true
	controller.hour_finished.connect(_on_hour_finished)
	controller.run_finished.connect(_on_run_finished)
	controller.toast.connect(func(text: String) -> void: _toast(text, "info"))
	controller.show_connection.connect(_on_show_connection)
	controller.show_minigame.connect(_on_show_minigame)
	var director = controller.hour_director
	if director != null:
		director.attack_added.connect(_on_attack_added_ui)
		director.attack_changed.connect(_on_attack_changed_ui)
		director.attack_removed.connect(_on_attack_removed_ui)


func _on_attack_added_ui(_id: String) -> void:
	_refresh_attacks()
	_refresh_hour()


func _on_attack_changed_ui(_id: String) -> void:
	_refresh_attacks()
	_refresh_hour()


func _on_attack_removed_ui(_id: String) -> void:
	_refresh_attacks()
	_refresh_hour()


## HourDirector уже вызвал start() — здесь только показываем готовую модалку.
func _on_show_connection(game_node) -> void:
	_show_modal_game(game_node)


## Отправка: HourDirector уже вызвал start() и создал MiniGame.
func _on_show_minigame(game_node) -> void:
	_show_modal_game(game_node)


func _show_modal_game(game_node) -> void:
	if game_node == null or modal_root == null:
		return
	# Вторую модалку не показываем: директор сам блокирует параллельный старт,
	# это защита от двойного сигнала. Но если старая уже завершилась (running
	# сброшен до emit finished, например UDP-перезапуск мини-игры) — заменяем.
	if _modal_game != null and _modal_game != game_node:
		if is_instance_valid(_modal_game) and not _modal_game.is_queued_for_deletion():
			var old_running = _modal_game.get("running")
			if old_running == null or bool(old_running):
				return
		_modal_game = null
	_modal_game = game_node
	if game_node.get_parent() == null:
		modal_root.add_child(game_node)
	elif game_node.get_parent() != modal_root:
		game_node.reparent(modal_root)
	if game_node is Control:
		# Окна мини-игр фиксированного размера — ставим по центру, не растягиваем.
		(game_node as Control).set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	if game_node.has_signal("finished"):
		game_node.finished.connect(_on_modal_game_finished.bind(game_node))


## Общий обработчик finished у ConnectionGame (2 арг) и MiniGame (1 арг).
## Третий параметр приходит из bind(); для мини-игры он окажется во втором.
func _on_modal_game_finished(_a = null, _b = null, game_node = null) -> void:
	if game_node == null:
		if _b is Node:
			game_node = _b
		elif _a is Node:
			game_node = _a
	if game_node != null and is_instance_valid(game_node) and not game_node.is_queued_for_deletion():
		game_node.queue_free()
	if game_node == null or _modal_game == game_node:
		_modal_game = null
	if controller != null:
		controller.modal_open = false
	# TCP-запрос подключён: если файлы уже собраны, отправка стартует сразу,
	# без дополнительного клика по карточке (start_send сам защищён от повтора).
	if _b is String and controller != null and controller.hour_director != null:
		var req_id := str(_b)
		if controller.hour_director.active_requests.has(req_id):
			_maybe_start_send(req_id)
	_refresh_hour()


# --------------------------------------------------------------------------
# Час: синхронизация карточек со снимком контроллера
# --------------------------------------------------------------------------

func _refresh_hour() -> void:
	if controller == null:
		return
	var d: Dictionary = controller.hour_data()
	var packet_data: Array = d.get("packets", [])
	var request_data: Array = d.get("requests", [])
	var slots_data: Array = d.get("slots", [])
	var status: Dictionary = d.get("status", {})

	_refresh_attacks()
	_refresh_packets(packet_data)
	_refresh_requests(request_data)
	_refresh_slots(slots_data, packet_data, request_data)
	_refresh_hour_status(status)
	_refresh_hour_titles(packet_data, request_data, status)


func _refresh_hour_titles(packets_data: Array, requests_data: Array, _status: Dictionary) -> void:
	receive_window.set_title(_padded_title("ПРИЁМ"),
		_plural_ru(packets_data.size(), "ПАКЕТ", "ПАКЕТА", "ПАКЕТОВ"))
	send_window.set_title(_padded_title("ОТПРАВКА"),
		_plural_ru(requests_data.size(), "ЗАПРОС", "ЗАПРОСА", "ЗАПРОСОВ"))


# --------------------------------------------------------------------------
# Атаки: оверлей DDoS и щит-карантин
# --------------------------------------------------------------------------

## Активная DDoS-атака (Dictionary) или {}.
func _active_ddos() -> Dictionary:
	if controller == null or controller.hour_director == null:
		return {}
	var director = controller.hour_director
	if director.attack_director == null:
		return {}
	for id in director.attack_director.active_attacks:
		var data: Dictionary = director.attack_director.active_attacks[id]
		if str(data.get("kind", "")) == "ddos":
			return data
	return {}


func _reposition_packet_cards() -> void:
	var card_w := 392.0
	if receive_window != null and receive_window.content != null:
		# Оставляем 14 px справа под скроллбар + 6 px отступа слева.
		card_w = maxf(120.0, receive_window.content.size.x - 20.0)
	for i in packets.size():
		if is_instance_valid(packets[i]):
			packets[i].position = Vector2(6,
				1 + _packet_shift + i * RECV_CARD_H - _recv_scroll)
			packets[i].size = Vector2(card_w, 44)


## Высота списка пакетов: сдвиг DDoS-плашки + по 48 px на карточку.
func _recv_content_height(count: int) -> float:
	return _packet_shift + float(maxi(0, count)) * RECV_CARD_H


## Пересчитать метрики скроллбара и вернуть карточки в актуальные позиции.
func _sync_recv_scroll(count: int = -1) -> void:
	if _recv_bar == null or receive_window == null or receive_window.content == null:
		return
	var n := packets.size() if count < 0 else count
	var view_h := maxf(1.0, receive_window.content.size.y)
	var content_h := _recv_content_height(n)
	_recv_bar.position = Vector2(
		maxf(0.0, receive_window.content.size.x - Theme90.SCROLLBAR), 0.0)
	_recv_bar.size = Vector2(Theme90.SCROLLBAR, view_h)
	_recv_bar.visible = content_h > view_h
	_recv_scroll = clampf(_recv_scroll, 0.0, maxf(0.0, content_h - view_h))
	_recv_bar.set_metrics(view_h, maxf(view_h, content_h), _recv_scroll)
	_reposition_packet_cards()


func _on_recv_scroll(value: float) -> void:
	_recv_scroll = maxf(0.0, value)
	_reposition_packet_cards()


func _nudge_recv_scroll(delta: float) -> void:
	if _recv_bar == null:
		return
	var next := clampf(_recv_scroll + delta, 0.0, _recv_bar._limit())
	_recv_scroll = next
	_recv_bar.value = next
	_reposition_packet_cards()


## Колесо мыши над ПРИЁМОМ: карточки пропускают событие вверх к content.
func _on_recv_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return
	var step := 0.0
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		step = -RECV_WHEEL_STEP
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		step = RECV_WHEEL_STEP
	if is_zero_approx(step):
		return
	_nudge_recv_scroll(step)
	if receive_window != null and receive_window.content != null:
		receive_window.content.accept_event()


## Оверлей DDoS в ПРИЁМЕ (плашка + красные мини-карточки) и состояние щитов.
func _refresh_attacks() -> void:
	var ddos := _active_ddos()
	if ddos.is_empty():
		if _ddos_overlay != null and is_instance_valid(_ddos_overlay):
			var parent = _ddos_overlay.get_parent()
			if parent != null:
				parent.remove_child(_ddos_overlay)
			_ddos_overlay.queue_free()
		_ddos_overlay = null
		_packet_shift = 0.0
		_shield_holding = false
		_update_shield_visuals({})
		_sync_recv_scroll()
		return

	if _ddos_overlay == null or not is_instance_valid(_ddos_overlay):
		_ddos_overlay = DdosOverlay.new()
		_ddos_overlay.name = "DdosOverlay"
		receive_window.content.add_child(_ddos_overlay)
		receive_window.content.move_child(_ddos_overlay, 0)
		_ddos_overlay.position = Vector2(6, 1)
		_ddos_overlay.size = Vector2(
			maxf(120.0, receive_window.content.size.x - 20.0), 34)
	_packet_shift = 36.0
	_ddos_overlay.cards = int(ddos.get("cards", 10))
	_ddos_overlay.hold = float(ddos.get("shield_hold", 0.0))
	_ddos_overlay.needed = maxf(0.1, float(ddos.get("shield_needed", 1.5)))
	_ddos_overlay.queue_redraw()
	_update_shield_visuals(ddos)
	_sync_recv_scroll()


func _update_shield_visuals(ddos: Dictionary) -> void:
	var active := not ddos.is_empty()
	var progress := 0.0
	var needed := 1.5
	if active:
		needed = maxf(0.1, float(ddos.get("shield_needed", 1.5)))
		progress = clampf(float(ddos.get("shield_hold", 0.0)) / needed, 0.0, 1.0)
	for shield in [_shield_receive, _shield_send]:
		if shield == null or not is_instance_valid(shield):
			continue
		shield.active = active
		shield.progress = progress
		shield.holding = _shield_holding
		shield.tooltip_text = "ЩИТ · УДЕРЖИВАЙТЕ ПРОТИВ DDoS" if active \
			else "ЩИТ · ПЕРЕТАЩИТЕ СЮДА УГРОЗУ"
		shield.queue_redraw()


func _tick_shield_hold(delta: float) -> void:
	if not _shield_holding:
		return
	if controller == null or controller.hour_director == null:
		return
	var ddos := _active_ddos()
	if ddos.is_empty():
		_shield_holding = false
		_update_shield_visuals({})
		return
	var step := minf(maxf(delta, 0.0), 0.1)
	if step <= 0.0:
		return
	_shield_hold_acc += step
	controller.hour_director.hold_shield(step)
	_update_shield_visuals(_active_ddos())


func _on_shield_press(_target: String = "") -> void:
	if controller == null or controller.hour_director == null:
		return
	if _active_ddos().is_empty():
		_toast("DDoS НЕТ · ЩИТ НЕ НУЖЕН", "info")
		return
	_shield_holding = true
	_shield_hold_acc = 0.0
	_toast("ДЕРЖИТЕ ЩИТ · ОТРАЖЕНИЕ DDoS", "warn")
	_update_shield_visuals(_active_ddos())


func _on_shield_release() -> void:
	if not _shield_holding:
		return
	_shield_holding = false
	_update_shield_visuals(_active_ddos())


## Drop любой карточки-угрозы на щит. Возвращает true, если угроза обезврежена.
func _on_quarantine_drop(payload: Dictionary) -> bool:
	if controller == null or controller.hour_director == null:
		return false
	if str(payload.get("kind", "")) != "packet":
		return false
	var is_threat := bool(payload.get("is_attack", false)) \
		or not str(payload.get("attack_kind", "")).is_empty()
	if not is_threat:
		_toast("ЭТО НЕ УГРОЗА · −2 SLA", "warn")
		Game.add_sla(-2.0, "quarantine")
		_refresh_hour()
		return false
	var director = controller.hour_director
	var attack_id := str(payload.get("attack_id", ""))
	var packet_id := str(payload.get("id", ""))
	var ok := false
	if not attack_id.is_empty():
		ok = director.quarantine_attack(attack_id)
	if not ok and not packet_id.is_empty():
		ok = director.destroy_attack_packet(packet_id)
	if ok:
		_toast("УГРОЗА В КАРАНТИНЕ", "success")
	else:
		_toast("НЕ УДАЛОСЬ ОБЕЗВРЕДИТЬ УГРОЗУ", "warn")
	_refresh_hour()
	return ok


func _card_ids(cards: Array) -> Array:
	var out: Array = []
	for c in cards:
		out.append(str(c.id))
	return out


func _same_ids(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if str(a[i]) != str(b[i]):
			return false
	return true


func _ext_for_type(type: String) -> String:
	if type.is_empty():
		return ""
	var def = Data.types.get(type, null)
	if def is Dictionary:
		return str(def.get("ext", "")).lstrip(".")
	return ""


func _refresh_packets(data: Array) -> void:
	var ids: Array = []
	for p in data:
		ids.append(str(p.get("id", "")))
	var rebuilt := false
	if not _same_ids(ids, _card_ids(packets)):
		rebuilt = true
		for c in packets:
			receive_window.content.remove_child(c)
			c.queue_free()
		packets.clear()
		for i in data.size():
			var card := PacketCard.new()
			card.name = "Packet_%s" % str(data[i].get("id", ""))
			receive_window.content.add_child(card)
			card.custom_minimum_size = Vector2.ZERO
			card.position = Vector2(6, 1 + _packet_shift + i * RECV_CARD_H - _recv_scroll)
			card.size = Vector2(maxf(120.0, receive_window.content.size.x - 20.0), 44)
			card.connect_pressed.connect(_on_packet_connect)
			packets.append(card)

	for i in data.size():
		if i >= packets.size():
			break
		var p: Dictionary = data[i]
		var card := packets[i]
		var left := float(p.get("time_left", 0.0))
		var total := float(p.get("timer_total", 0.0))
		card.setup(str(p.get("id", "")), str(p.get("file_name", "")),
			_ext_for_type(str(p.get("type", ""))), str(p.get("type", "")),
			str(p.get("protocol", "")).to_upper(), left, total,
			float(p.get("loading_progress", 0.0)), int(p.get("size_kb", 0)),
			bool(p.get("is_attack", false)), str(p.get("attack_kind", "")),
			str(p.get("attack_id", "")), str(p.get("state", "waiting")))
		card.set_time(left, total)

	_sync_recv_scroll(data.size())
	if rebuilt:
		# Пришли новые пакеты — показываем последний, не заставляя скроллить.
		_recv_scroll = maxf(0.0,
			_recv_content_height(data.size()) - maxf(1.0, receive_window.content.size.y))
		_sync_recv_scroll(data.size())


func _refresh_requests(data: Array) -> void:
	var visible: Array = data.slice(0, 4)
	var ids: Array = []
	for r in visible:
		ids.append(str(r.get("id", "")))
	if not _same_ids(ids, _card_ids(requests)):
		for c in requests:
			send_window.content.remove_child(c)
			c.queue_free()
		requests.clear()
		for i in visible.size():
			var card := RequestCard.new()
			card.name = "Request_%s" % str(visible[i].get("id", ""))
			send_window.content.add_child(card)
			card.custom_minimum_size = Vector2.ZERO
			card.position = Vector2(6, i * REQ_CARD_H)
			card.size = Vector2(400, REQ_CARD_H)
			card.connect_pressed.connect(_on_request_connect)
			card.reject_pressed.connect(_on_request_reject)
			card.file_dropped.connect(_on_file_to_request)
			card.detach_pressed.connect(_on_request_detach)
			requests.append(card)
	# Раскладка каждый кадр: при 3–4 запросах шаг меньше, чтобы все влезли в 252 px.
	_layout_request_cards(visible.size())

	for i in visible.size():
		if i >= requests.size():
			break
		var r: Dictionary = visible[i]
		var progress := 0.0
		var duration := float(r.get("send_duration", 0.0))
		if bool(r.get("sending", false)) and duration > 0.0:
			progress = clampf(float(r.get("send_progress", 0.0)) / duration, 0.0, 1.0)
		var is_phish := bool(r.get("is_attack", false)) and str(r.get("attack_kind", "")) == "phishing"
		requests[i].setup(str(r.get("id", "")), str(r.get("client_name", "")),
			str(r.get("client_id", "")), str(r.get("protocol", "")).to_upper(),
			_request_slots(r), float(r.get("time_left", 0.0)),
			float(r.get("timer_total", 0.0)), progress,
			bool(r.get("is_attack", false)), str(r.get("attack_kind", "")),
			str(r.get("attack_id", "")), is_phish)
		requests[i].queue_redraw()


## Высота карточки запроса: 3–4 штуки должны целиком влезать в 252 px.
func _request_card_height(count: int) -> float:
	return REQ_CARD_H_COMPACT if count >= 3 else REQ_CARD_H


## Разложить карточки запросов по вертикали без пересоздания.
func _layout_request_cards(count: int) -> void:
	if send_window == null or send_window.content == null:
		return
	var h := _request_card_height(count)
	var w := maxf(120.0, send_window.content.size.x - 12.0)
	for i in requests.size():
		var card := requests[i]
		if card == null or not is_instance_valid(card):
			continue
		card.position = Vector2(6, i * h)
		card.size = Vector2(w, h)
		card.queue_redraw()


## Слоты запроса: required-файлы из реестра; отсутствующий файл — null.
func _request_slots(request: Dictionary) -> Array:
	var out: Array = []
	var attached: Array = request.get("attached", [])
	var registry = Game.registry
	for file_id in request.get("required", []):
		var fid := str(file_id)
		var file = null
		if registry != null:
			file = registry.files.get(fid)
		if file == null:
			out.append(null)
			continue
		var folder_name := ""
		if not str(file.folder_id).is_empty() and registry.folders.has(file.folder_id):
			folder_name = str(registry.folders[file.folder_id].name)
		out.append({
			"name": str(file.name),
			"ext": str(file.ext),
			"type": str(file.type),
			"folder": folder_name,
			"attached": attached.has(fid),
		})
	return out


func _refresh_slots(data: Array, packets_data: Array = [],
		requests_data: Array = []) -> void:
	if slot_cells.size() != 4:
		for c in slot_cells:
			if is_instance_valid(c):
				if c.get_parent() != null:
					c.get_parent().remove_child(c)
				c.queue_free()
		slot_cells.clear()
		for i in 4:
			var cell := SlotCell.new()
			cell.name = "Slot_%d" % i
			slots_strip.add_child(cell)
			cell.position = Vector2(58 + i * 240, 5)
			cell.size = Vector2(236, 44)
			cell.close_pressed.connect(_on_slot_close)
			cell.cell_pressed.connect(_on_slot_press)
			cell.packet_dropped.connect(_on_packet_to_slot)
			slot_cells.append(cell)

	for i in 4:
		var cell := slot_cells[i]
		if i >= data.size():
			cell.setup("", "", "down", 0.0, "empty", "СВОБОДЕН", "")
			continue
		var s: Dictionary = data[i]
		var occupied := bool(s.get("occupied", false))
		var dir := "down" if str(s.get("direction", "")) == "in" else "up"
		var progress := 0.0
		if occupied:
			progress = _slot_entity_progress(str(s.get("entity_id", "")), dir,
				packets_data, requests_data)
		cell.setup(str(s.get("entity_id", "")), str(s.get("entity_name", "")), dir,
			progress,
			"active" if occupied else "empty",
			"" if occupied else "СВОБОДЕН", str(int(s.get("index", i)) + 1))


## Прогресс занятого слота: загрузка пакета или отправка запроса.
func _slot_entity_progress(entity_id: String, dir: String, packets_data: Array,
		requests_data: Array) -> float:
	if entity_id.is_empty():
		return 0.0
	if dir == "down":
		for p in packets_data:
			if str(p.get("id", "")) != entity_id:
				continue
			if str(p.get("state", "")) != "loading":
				return 0.0
			var total := float(p.get("timer_total", 0.0))
			if total <= 0.0:
				return 0.0
			return clampf(1.0 - float(p.get("time_left", 0.0)) / total, 0.0, 1.0)
		return 0.0
	for r in requests_data:
		if str(r.get("id", "")) != entity_id:
			continue
		if not bool(r.get("sending", false)):
			return 0.0
		var duration := float(r.get("send_duration", 0.0))
		if duration <= 0.0:
			return 0.0
		return clampf(float(r.get("send_progress", 0.0)) / duration, 0.0, 1.0)
	return 0.0


func _refresh_hour_status(status: Dictionary) -> void:
	var used := int(status.get("tcp_used", 0))
	var max_slots := maxi(1, int(status.get("tcp_max", 0)))
	var percent := float(status.get("channel_percent", 0.0))
	var sla := int(round(float(status.get("sla", 0.0))))
	var buffer_used := int(status.get("buffer_used", 0))
	var buffer_max := maxi(1, int(status.get("buffer_max", 0)))
	var hour := int(status.get("hour", 1))
	var left := maxf(0.0, float(status.get("time_left", 0.0)))
	var secs := int(ceilf(left))

	status_bar.set_metric("tcp", "%d / %d" % [used, max_slots],
		clampf(float(used) / float(max_slots), 0.0, 1.0))
	status_bar.set_metric("channel", "%d%%" % int(round(percent)),
		clampf(percent / 100.0, 0.0, 1.0))
	var max_sla := maxi(1, int(Game.MAX_SLA))
	status_bar.set_metric("sla", "%d / %d" % [sla, max_sla],
		clampf(float(sla) / float(max_sla), 0.0, 1.0))
	status_bar.set_metric("buffer", "%d / %d" % [buffer_used, buffer_max],
		clampf(float(buffer_used) / float(buffer_max), 0.0, 1.0))
	status_bar.set_metric("money", "$ %d" % int(status.get("money", 0)))
	status_bar.set_metric("hour", "ЧАС %d  %02d:%02d" % [hour, secs / 60, secs % 60],
		float(hour - 1) / float(GAME_CONTROLLER.HOURS_PER_RUN))
	if slot_count_label != null:
		slot_count_label.text = "%d/%d" % [used, max_slots]


# --------------------------------------------------------------------------
# Итоги часа и забега
# --------------------------------------------------------------------------

func _on_hour_finished(_report: Dictionary) -> void:
	_open_hour_result()


func _open_hour_result() -> void:
	if hour_result_modal == null or controller == null:
		return
	if hour_result_modal.visible:
		return
	var report: Dictionary = controller.current_report
	var sla := float(Game.sla)
	hour_result_modal.open({
		"hour": int(report.get("hour", Game.hour)),
		"hours_total": GAME_CONTROLLER.HOURS_PER_RUN,
		"earned": int(report.get("earned", 0)),
		"done": int(report.get("completed", 0)),
		"failed": int(report.get("failed", 0)),
		"reflected": int(report.get("attacks", 0)),
		"missed": int(report.get("attacks_failed", 0)),
		"sla_delta": int(round(float(report.get("sla_delta", 0.0)))),
		"sla": int(round(sla)),
		"sla_max": maxi(1, int(Game.MAX_SLA)),
	})


func _on_hour_result_next() -> void:
	if controller == null:
		return
	controller.next_after_hour()
	if controller.phase == GAME_CONTROLLER.PHASE_RUN_RESULT:
		_show_run_result()
	elif controller.phase == GAME_CONTROLLER.PHASE_PREP:
		# _on_phase(prep) уже перерисовал экран; повторный вызов безвреден.
		_refresh_prep()


func _on_run_finished(_report: Dictionary) -> void:
	_show_run_result()


func _show_run_result() -> void:
	if run_result_modal == null or controller == null:
		return
	if run_result_modal.visible:
		return
	var r: Dictionary = controller.run_result()
	run_result_modal.open({
		"won": bool(r.get("won", false)),
		"reason": _run_reason_text(str(r.get("reason", ""))),
		"score": int(r.get("score", 0)),
		"best": int(r.get("best", 0)),
		"hours": int(r.get("hours", 0)),
		"hours_total": GAME_CONTROLLER.HOURS_PER_RUN,
		"money": int(r.get("money", 0)),
		"sla": int(round(float(r.get("sla", 0.0)))),
		"sla_max": maxi(1, int(Game.MAX_SLA)),
		"unlocked": (r.get("unlocked", []) as Array).duplicate(),
	})
	var unlocked: Array = r.get("unlocked", [])
	if not unlocked.is_empty():
		_toast("ОТКРЫТО: %s" % ", ".join(unlocked), "success")


func _run_reason_text(reason: String) -> String:
	match reason:
		"victory":
			return "СМЕНА ОТРАБОТАНА. ВСЕ 9 ЧАСОВ."
		"sla":
			return "SLA УПАЛ ДО НУЛЯ. СМЕНА СОРВАНА."
		_:
			return reason


func _on_run_result_new() -> void:
	_start_new_run()


func _on_run_result_menu() -> void:
	if run_result_modal != null:
		run_result_modal.visible = false
	if hour_result_modal != null:
		hour_result_modal.visible = false
	_hour_ui_shown = false
	if main_menu != null:
		main_menu.set_has_save(controller != null and controller.has_save())
		main_menu.visible = true


# --------------------------------------------------------------------------
# Сборка экрана
# --------------------------------------------------------------------------

func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(W, H)

	var desk := Backdrop.new()
	_backdrop = desk
	desk.name = "Desktop"
	desk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desk.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(desk)

	# титлбар приложения (0,0,1280,24)
	title_bar = WindowFrame.new()
	title_bar.name = "TitleBar"
	title_bar.title = "PEAK HOUR 97"
	title_bar.title_logo = true
	title_bar.icon_kind = "app"
	title_bar.title_hint = "УЗЕЛ 7 · СМЕНА 3"
	title_bar.accent_line = true
	title_bar.title_only = true
	title_bar.close_enabled = false
	_place(self, title_bar, Rect2(0, 0, W, 24))

	# строка меню (0,24,1280,20)
	menu_bar = Panel90.new()
	menu_bar.name = "MenuBar"
	menu_bar.kind = Panel90.Kind.FLAT
	_place(self, menu_bar, Rect2(0, 24, W, 20))

	var sep := ColorRect.new()
	sep.color = Theme90.SHADE
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_bar.add_child(sep)
	sep.position = Vector2(0, 19)
	sep.size = Vector2(W, 1)

	# Одна рабочая кнопка меню вместо демо-пунктов ФАЙЛ/ВИД/СПРАВКА.
	var menu_btn := Button90.new()
	menu_btn.name = "MenuButton"
	menu_btn.caption = "МЕНЮ"
	menu_btn.flat_style = true
	menu_btn.caption_size = Theme90.FS_BODY
	menu_bar.add_child(menu_btn)
	menu_btn.position = Vector2(6, 1)
	menu_btn.size = Vector2(72, 18)
	menu_btn.pressed.connect(func() -> void: _popup_main_menu(menu_btn))
	_menu_btn = menu_btn

	# правая часть меню-бара: дата, часы, магазин, старт часа
	var date_lbl := Label.new()
	date_lbl.name = "DateLabel"
	date_lbl.text = "СБ 12 ОКТ 1997"
	date_lbl.add_theme_font_override("font", Theme90.ui())
	date_lbl.add_theme_font_size_override("font_size", Theme90.FS_MICRO)
	date_lbl.add_theme_color_override("font_color", Theme90.DARK)
	date_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	date_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	date_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_bar.add_child(date_lbl)
	date_lbl.position = Vector2(852, 1)
	date_lbl.size = Vector2(140, 18)
	date_lbl.visible = false

	var clock := Label.new()
	clock.name = "Clock"
	clock.text = "03:42"
	clock.add_theme_font_override("font", Theme90.logo())
	clock.add_theme_font_size_override("font_size", 10)
	clock.add_theme_color_override("font_color", Theme90.DARK)
	clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	clock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_bar.add_child(clock)
	clock.position = Vector2(998, 1)
	clock.size = Vector2(54, 18)

	var shop := Button90.new()
	shop.name = "ShopButton"
	shop.caption = "МАГАЗИН"
	shop.flat_style = true
	shop.size = Vector2(82, 18)
	menu_bar.add_child(shop)
	shop.position = Vector2(1078, 1)
	shop.pressed.connect(_on_shop)
	_shop_btn = shop

	var start := Button90.new()
	start.name = "StartHourButton"
	start.caption = "НАЧАТЬ ЧАС"
	start.accent = true
	start.size = Vector2(108, 18)
	menu_bar.add_child(start)
	start.position = Vector2(1164, 1)
	start.pressed.connect(_on_start_hour)
	_start_btn = start

	# рабочая область (8,48,840,548) — утопленная группа
	workspace = Panel90.new()
	workspace.name = "Workspace"
	workspace.kind = Panel90.Kind.GROUP
	workspace.title = "ДИСК C:"
	workspace.title_right = _plural_ru(0, "ОБЪЕКТ", "ОБЪЕКТА", "ОБЪЕКТОВ")
	_place(self, workspace, Rect2(8, 48, 840, 548))

	# окно дерева (16,72,240,516)
	tree_window = WindowFrame.new()
	tree_window.name = "TreeWindow"
	tree_window.title = "ДИСКИ"
	tree_window.title_hint = _plural_ru(6, "ПАПКА", "ПАПКИ", "ПАПОК")
	tree_window.icon_kind = "tree"
	_place(workspace, tree_window, Rect2(8, 24, 240, 516))

	tree = TreePanel.new()
	tree.name = "TreePanel"
	tree.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	add_child_to(tree_window.content, tree, Vector2.ZERO, tree_window.content.size)

	# окно файлов (264,72,576,516)
	files_window = WindowFrame.new()
	files_window.name = "FilesWindow"
	files_window.title = "ФАЙЛЫ · ПРИЁМ"
	files_window.title_hint = _plural_ru(12, "ОБЪЕКТ", "ОБЪЕКТА", "ОБЪЕКТОВ")
	files_window.icon_kind = "files"
	_place(workspace, files_window, Rect2(256, 24, 576, 516))

	grid = FileGrid.new()
	grid.name = "FileGrid"
	add_child_to(files_window.content, grid, Vector2.ZERO, files_window.content.size)
	_build_search_field()

	# окно ПРИЁМ (856,48,416,264)
	receive_window = WindowFrame.new()
	receive_window.name = "ReceiveWindow"
	receive_window.title = _padded_title("ПРИЁМ")
	receive_window.title_hint = _plural_ru(5, "ПАКЕТ", "ПАКЕТА", "ПАКЕТОВ")
	receive_window.icon_kind = "inbox"
	_place(self, receive_window, Rect2(856, 48, 416, 264))
	_build_receive_scroll()

	# окно ОТПРАВКА (856,320,416,276)
	send_window = WindowFrame.new()
	send_window.name = "SendWindow"
	send_window.title = _padded_title("ОТПРАВКА")
	send_window.title_hint = _plural_ru(4, "ЗАПРОС", "ЗАПРОСА", "ЗАПРОСОВ")
	send_window.icon_kind = "outbox"
	_place(self, send_window, Rect2(856, 320, 416, 276))
	_build_shields()

	# полоса TCP-слотов (8,604,1264,52)
	slots_strip = Panel90.new()
	slots_strip.name = "SlotsStrip"
	slots_strip.kind = Panel90.Kind.RAISED
	_place(self, slots_strip, Rect2(8, 604, 1264, 52))

	var head := Panel90.new()
	head.name = "SlotHead"
	head.kind = Panel90.Kind.SUNKEN
	slots_strip.add_child(head)
	head.position = Vector2(6, 5)
	head.size = Vector2(46, 42)

	var tcp_lbl := Label.new()
	tcp_lbl.text = "TCP"
	tcp_lbl.add_theme_font_override("font", Theme90.ui(800))
	tcp_lbl.add_theme_font_size_override("font_size", Theme90.FS_BODY)
	tcp_lbl.add_theme_color_override("font_color", Theme90.NAVY)
	tcp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tcp_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tcp_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(tcp_lbl)
	tcp_lbl.position = Vector2(0, 4)
	tcp_lbl.size = Vector2(46, 18)

	var tcp_cnt := Label.new()
	tcp_cnt.name = "SlotCount"
	slot_count_label = tcp_cnt
	tcp_cnt.text = "2/5"
	tcp_cnt.add_theme_font_override("font", Theme90.logo())
	tcp_cnt.add_theme_font_size_override("font_size", 8)
	tcp_cnt.add_theme_color_override("font_color", Theme90.DARK)
	tcp_cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tcp_cnt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tcp_cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(tcp_cnt)
	tcp_cnt.position = Vector2(0, 22)
	tcp_cnt.size = Vector2(46, 14)

	# статус-бар (0,660,1280,60)
	status_bar = StatusBar.new()
	status_bar.name = "StatusBar"
	_place(self, status_bar, Rect2(0, 660, W, 60))

	# слой сообщений
	toast_layer = ToastLayer.new()
	toast_layer.name = "ToastLayer"
	toast_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(toast_layer)


func _place(parent: Node, c: Control, rect: Rect2) -> void:
	parent.add_child(c)
	c.custom_minimum_size = Vector2.ZERO
	c.size = rect.size
	c.position = rect.position


# --------------------------------------------------------------------------
# Скролл ПРИЁМА и поле поиска
# --------------------------------------------------------------------------

func _build_receive_scroll() -> void:
	if receive_window == null or receive_window.content == null:
		return
	receive_window.content.clip_contents = true
	_recv_bar = ScrollBar90.new()
	_recv_bar.name = "ReceiveScroll"
	receive_window.content.add_child(_recv_bar)
	_recv_bar.position = Vector2(
		maxf(0.0, receive_window.content.size.x - Theme90.SCROLLBAR), 0.0)
	_recv_bar.size = Vector2(Theme90.SCROLLBAR, receive_window.content.size.y)
	_recv_bar.visible = false
	_recv_bar.value_changed.connect(_on_recv_scroll)
	receive_window.content.gui_input.connect(_on_recv_gui_input)


func _build_search_field() -> void:
	if files_window == null or files_window.content == null:
		return
	_search_edit = LineEdit.new()
	_search_edit.name = "FileSearch"
	_search_edit.placeholder_text = "поиск по имени…"
	_search_edit.max_length = 48
	_search_edit.add_theme_font_override("font", Theme90.ui())
	_search_edit.add_theme_font_size_override("font_size", Theme90.FS_MICRO)
	_search_edit.add_theme_color_override("font_color", Theme90.INK)
	_search_edit.add_theme_color_override("font_placeholder_color", Theme90.SHADE)
	var box := Theme90.sunken_box()
	box.set_content_margin_all(1)
	box.content_margin_left = 4
	box.content_margin_right = 2
	_search_edit.add_theme_stylebox_override("normal", box)
	_search_edit.add_theme_stylebox_override("focus", box)
	_search_edit.text_changed.connect(_on_search_changed)
	files_window.content.add_child(_search_edit)
	files_window.content.move_child(_search_edit, 0)
	_search_edit.position = Vector2(2, 2)
	_search_edit.size = Vector2(180, 18)
	_search_edit.visible = false


func add_child_to(parent: Node, c: Control, pos: Vector2, sz: Vector2) -> void:
	parent.add_child(c)
	c.custom_minimum_size = Vector2.ZERO
	c.position = pos
	c.size = sz


# --------------------------------------------------------------------------
# Щит-карантин в заголовках ПРИЁМ/ОТПРАВКА
# --------------------------------------------------------------------------

const SHIELD_W := 48.0
const SHIELD_H := 20.0
const SHIELD_X := 22.0

## Отступ заголовка, чтобы текст не заезжал под щит (щит стоит сразу за иконкой).
func _padded_title(t: String) -> String:
	var f := Theme90.ui()
	var space_w := f.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, Theme90.FS_BODY).x
	if space_w <= 0.0:
		return "          " + t
	var n := int(ceil((SHIELD_W + 34.0) / space_w))
	return " ".repeat(n) + t


func _build_shields() -> void:
	_shield_receive = _make_shield("receive", receive_window)
	_shield_send = _make_shield("send", send_window)


func _make_shield(target: String, frame: WindowFrame) -> Control:
	var shield := ShieldDrop.new()
	shield.name = "ShieldDrop"
	shield.main = self
	shield.target = target
	frame.add_child(shield)
	shield.position = Vector2(SHIELD_X, 2)
	shield.size = Vector2(SHIELD_W, SHIELD_H)
	return shield


func _make_menu(labels: Array) -> PopupMenu:
	var pm := ContextMenu90.new()
	pm.name = "Popup"
	add_child(pm)
	var idx := 0
	for l in labels:
		var label := str(l)
		if label == "-":
			pm.add_separator()
			continue
		pm.add_item(label, idx)
		idx += 1
	pm.id_pressed.connect(func(id: int) -> void:
		var i := pm.get_item_index(id)
		if i >= 0:
			_on_menu_pick(pm.get_item_text(i)))
	pm.popup_hide.connect(func() -> void:
		if is_instance_valid(pm):
			pm.queue_free())
	return pm


## Пункты верхнего меню зависят от фазы: в меню нет выхода в само меню.
func _main_menu_items() -> Array:
	var items: Array = ["Настройки", "О программе"]
	if controller != null and (controller.phase == GAME_CONTROLLER.PHASE_PREP \
			or controller.phase == GAME_CONTROLLER.PHASE_HOUR):
		items.append_array(["-", "В главное меню"])
	if not OS.has_feature("web"):
		items.append_array(["-", "Выход"])
	return items


func _popup_main_menu(button: Button90) -> void:
	if button == null:
		return
	var pm := _make_menu(_main_menu_items())
	_menus["МЕНЮ"] = pm
	button.active = true
	pm.popup_hide.connect(func() -> void:
		if is_instance_valid(button):
			button.active = false)
	pm.popup(Rect2i(Vector2i(int(button.global_position.x), 44), Vector2i.ZERO))


## Реальные действия верхнего меню (алиасы сохранены для старых тестов).
func _on_menu_pick(text: String) -> void:
	var key := text.to_lower()
	if key.contains("параметр") or key.contains("настрой"):
		_open_settings()
		return
	if key.contains("о программе"):
		_show_about()
		return
	if key.contains("главное меню"):
		_confirm_to_menu()
		return
	if key.contains("выход"):
		if OS.has_feature("web"):
			_toast("ЗАКРОЙТЕ ВКЛАДКУ БРАУЗЕРА", "info")
		else:
			get_tree().quit()
		return
	_toast("ПУНКТ МЕНЮ НЕДОСТУПЕН: %s" % text.to_upper(), "warn")


# --------------------------------------------------------------------------
# Мок-данные
# --------------------------------------------------------------------------

func _apply_mock() -> void:
	tree.set_data(_mock_tree())
	tree.select_folder("inbox")

	grid.set_folder("inbox", "ПРИЁМ", "C: \\ ПРИЁМ")
	grid.set_files(_files_for("inbox"))
	files_window.set_title("ФАЙЛЫ · ПРИЁМ",
		_plural_ru(12, "ОБЪЕКТ", "ОБЪЕКТА", "ОБЪЕКТОВ"))

	var pk := _mock_packets()
	var y := 1.0
	for d in pk:
		var card := PacketCard.new()
		card.name = "Packet_%s" % str(d["id"])
		receive_window.content.add_child(card)
		card.custom_minimum_size = Vector2.ZERO
		card.position = Vector2(6, y)
		card.size = Vector2(400, 44)
		card.setup(str(d["id"]), str(d["name"]), str(d["ext"]), str(d["type"]),
			str(d["protocol"]), float(d["left"]), float(d["total"]), float(d["progress"]),
			int(d["size_kb"]))
		card.connect_pressed.connect(_on_packet_connect)
		packets.append(card)
		y += 48.0

	var rq := _mock_requests()
	y = 0.0
	for d in rq:
		var card := RequestCard.new()
		card.name = "Request_%s" % str(d["id"])
		send_window.content.add_child(card)
		card.custom_minimum_size = Vector2.ZERO
		card.position = Vector2(6, y)
		card.size = Vector2(400, 60)
		card.setup(str(d["id"]), str(d["client"]), str(d["client_id"]), str(d["protocol"]),
			d["slots"], float(d["left"]), float(d["total"]), float(d["progress"]))
		card.connect_pressed.connect(_on_request_connect)
		card.reject_pressed.connect(_on_request_reject)
		card.file_dropped.connect(_on_file_to_request)
		card.detach_pressed.connect(_on_request_detach)
		requests.append(card)
		y += 64.0

	var sl := _mock_slots()
	for i in sl.size():
		var d: Dictionary = sl[i]
		var cell := SlotCell.new()
		cell.name = "Slot_%d" % i
		slots_strip.add_child(cell)
		cell.position = Vector2(58 + i * 240, 5)
		cell.size = Vector2(236, 44)
		cell.setup(str(d["id"]), str(d["name"]), str(d["dir"]), float(d["progress"]),
			str(d["state"]), str(d.get("sub", "")), str(d.get("label", "")))
		cell.close_pressed.connect(_on_slot_close)
		cell.cell_pressed.connect(_on_slot_press)
		cell.packet_dropped.connect(_on_packet_to_slot)
		slot_cells.append(cell)


func _mock_tree() -> Array:
	var c_folders: Array = [
		{"id": "inbox", "name": "ПРИЁМ", "count": 3, "capacity": 16},
		{"id": "outbox", "name": "ОТПРАВКА", "count": 2, "capacity": 16},
		{"id": "archive", "name": "АРХИВ", "count": 7, "capacity": 16},
	]
	for f in _extra_folders:
		c_folders.append(f)
	return [
		{"id": "sec_c", "name": "C:  ЛОКАЛЬНЫЙ", "free": "412 МБ", "folders": c_folders},
		{"id": "sec_d", "name": "D:  РАБОЧИЙ", "free": "1,2 ГБ", "folders": [
			{"id": "projects", "name": "ПРОЕКТЫ", "count": 5, "capacity": 16},
			{"id": "scans", "name": "СКАНЫ", "count": 1, "capacity": 16},
		]},
		{"id": "sec_e", "name": "E:  СЕТЕВОЙ", "free": "—", "folders": [
			{"id": "y1996", "name": "1996", "count": 12, "capacity": 16, "locked": true},
		]},
	]


func _file_pool() -> Array:
	return [
		# ПРИЁМ — 12 объектов
		{"id": "f_report", "name": "отчёт_смены", "ext": "xls", "size_kb": 148, "type": "text", "state": "stored"},
		{"id": "f_contract", "name": "договор_11", "ext": "doc", "size_kb": 96, "type": "text", "state": "attached"},
		{"id": "f_estimate", "name": "смета_объекта", "ext": "xls", "size_kb": 212, "type": "text", "state": "stored"},
		{"id": "f_radio", "name": "реклама_радио", "ext": "mp3", "size_kb": 1840, "type": "sound", "state": "stored"},
		{"id": "f_jingle", "name": "джингл", "ext": "wav", "size_kb": 620, "type": "sound", "state": "locked"},
		{"id": "f_passport", "name": "скан_паспорта", "ext": "jpg", "size_kb": 780, "type": "photo", "state": "stored"},
		{"id": "f_frame4", "name": "кадр_4", "ext": "jpg", "size_kb": 340, "type": "photo", "state": "attached"},
		{"id": "f_logo2", "name": "логотип_2", "ext": "png", "size_kb": 72, "type": "photo", "state": "stored"},
		{"id": "f_pres", "name": "презентация_97", "ext": "avi", "size_kb": 12400, "type": "video", "state": "stored"},
		{"id": "f_promo", "name": "промо_ролик", "ext": "avi", "size_kb": 8800, "type": "video", "state": "malicious"},
		{"id": "f_invoice", "name": "счёт_фактура", "ext": "doc", "size_kb": 64, "type": "text", "state": "failed"},
		{"id": "f_price", "name": "прайс_весна", "ext": "xls", "size_kb": 38, "type": "text", "state": "stored"},
		# ОТПРАВКА — 4
		{"id": "f_letter", "name": "письмо_клиенту", "ext": "doc", "size_kb": 24, "type": "text", "state": "stored"},
		{"id": "f_sticker", "name": "наклейка", "ext": "png", "size_kb": 18, "type": "photo", "state": "stored"},
		{"id": "f_horn", "name": "сигнал_эфир", "ext": "wav", "size_kb": 410, "type": "sound", "state": "stored"},
		{"id": "f_reel", "name": "ролик_осень", "ext": "avi", "size_kb": 7600, "type": "video", "state": "stored"},
		# АРХИВ — 3
		{"id": "f_old1", "name": "акт_1995", "ext": "doc", "size_kb": 12, "type": "text", "state": "stored"},
		{"id": "f_old2", "name": "фото_склад", "ext": "jpg", "size_kb": 520, "type": "photo", "state": "stored"},
		{"id": "f_old3", "name": "запись_эфир", "ext": "wav", "size_kb": 2300, "type": "sound", "state": "stored"},
		# ПРОЕКТЫ — 2
		{"id": "f_proj1", "name": "план_смены", "ext": "xls", "size_kb": 44, "type": "text", "state": "stored"},
		{"id": "f_proj2", "name": "макет_узла", "ext": "png", "size_kb": 220, "type": "photo", "state": "stored"},
		# СКАНЫ — 1
		{"id": "f_scan1", "name": "скан_акта", "ext": "jpg", "size_kb": 640, "type": "photo", "state": "locked"},
	]


func _files_for(folder_id: String) -> Array:
	var pool := _file_pool()
	match folder_id:
		"outbox":
			return pool.slice(12, 16)
		"archive":
			return pool.slice(16, 19)
		"projects":
			return pool.slice(19, 21)
		"scans":
			return pool.slice(21, 22)
		"y1996":
			return []
		_:
			return pool.slice(0, 12)


func _folder_name(fid: String) -> String:
	# Сначала настоящий реестр: мок-дерево нужно только демо-сцене.
	if Game.registry != null and Game.registry.folders.has(fid):
		return str(Game.registry.folders[fid].name)
	if grid != null and grid.folder_id == fid and not grid.folder_name.is_empty():
		return grid.folder_name
	for s in _mock_tree():
		for f in s["folders"]:
			if str(f["id"]) == fid:
				return str(f["name"])
		if str(s["id"]) == fid:
			return str(s["name"])
	return "ПАПКА"


func _mock_packets() -> Array:
	return [
		{"id": "p1", "name": "договор_11", "ext": "doc", "type": "text", "protocol": "TCP",
			"left": 28.0, "total": 40.0, "progress": 0.0, "size_kb": 96},
		{"id": "p2", "name": "смета_объекта", "ext": "xls", "type": "text", "protocol": "UDP",
			"left": 12.0, "total": 30.0, "progress": 0.0, "size_kb": 212},
		{"id": "p3", "name": "реклама_радио", "ext": "mp3", "type": "sound", "protocol": "TCP",
			"left": 4.0, "total": 25.0, "progress": 0.42, "size_kb": 1840},
		{"id": "p4", "name": "скан_паспорта", "ext": "jpg", "type": "photo", "protocol": "TCP",
			"left": 18.0, "total": 35.0, "progress": 0.78, "size_kb": 780},
		{"id": "p5", "name": "промо_ролик", "ext": "avi", "type": "video", "protocol": "TCP",
			"left": 1.4, "total": 30.0, "progress": 0.0, "size_kb": 8800},
	]


func _mock_requests() -> Array:
	return [
		{"id": "r1", "client": "ООО «Вектор»", "client_id": "cl-4217", "protocol": "TCP",
			"slots": [
				{"name": "отчёт_смены", "ext": "xls", "type": "text"},
				{"name": "смета", "ext": "doc", "type": "text"},
				null,
			],
			"left": 45.0, "total": 60.0, "progress": 0.0},
		{"id": "r2", "client": "ИП Кузнецов", "client_id": "cl-1189", "protocol": "UDP",
			"slots": [
				{"name": "логотип_2", "ext": "png", "type": "photo"},
				null,
				null,
			],
			"left": 24.0, "total": 45.0, "progress": 0.0},
		{"id": "r3", "client": "Студия «Гром»", "client_id": "cl-9314", "protocol": "TCP",
			"slots": [
				{"name": "джингл", "ext": "wav", "type": "sound"},
				null,
				null,
			],
			"left": 8.0, "total": 40.0, "progress": 0.0},
		{"id": "r4", "client": "АО «Северный»", "client_id": "cl-7772", "protocol": "TCP",
			"slots": [
				{"name": "промо_осень", "ext": "avi", "type": "video"},
				{"name": "кадр_4", "ext": "jpg", "type": "photo"},
				null,
			],
			"left": 38.0, "total": 60.0, "progress": 0.62},
	]


func _mock_slots() -> Array:
	return [
		{"id": "s1", "name": "реклама_радио.mp3", "dir": "down", "progress": 0.42, "state": "active"},
		{"id": "s2", "name": "отчёт_07.xls", "dir": "up", "progress": 0.78, "state": "active"},
		{"id": "s3", "name": "", "dir": "down", "progress": 0.0, "state": "empty",
			"sub": "СВОБОДЕН"},
		{"id": "s4", "name": "", "dir": "down", "progress": 0.0, "state": "locked",
			"slot": "4", "sub": "КУПИТЬ В МАГАЗИНЕ · 450 $", "label": "4"},
		{"id": "s5", "name": "", "dir": "down", "progress": 0.0, "state": "locked",
			"slot": "5", "sub": "КУПИТЬ В МАГАЗИНЕ · 700 $", "label": "5"},
	]


# --------------------------------------------------------------------------
# Сигналы
# --------------------------------------------------------------------------

func _connect_all() -> void:
	tree.folder_selected.connect(_on_folder_selected)
	tree.file_dropped.connect(_on_drop_to_folder)
	tree.context_menu_requested.connect(_on_tree_context)
	tree.new_folder_requested.connect(_on_new_folder)

	grid.file_selected.connect(_on_file_selected)
	grid.file_activated.connect(_on_file_activated)
	grid.file_context_requested.connect(_on_file_context)
	grid.file_dropped.connect(_on_drop_to_folder)
	grid.service_filter_changed.connect(_on_service_filter)


func _on_folder_selected(folder_id: String) -> void:
	if controller == null:
		return
	var d: Dictionary = controller.prep_data()
	var meta := _folder_meta(d, folder_id)
	if meta.is_empty():
		return
	_show_folder(folder_id, str(meta["name"]), str(meta["section"]), d)


func _on_file_selected(id: String) -> void:
	_selected_file = id
	for c in grid.get_cards():
		if c.id == id:
			files_window.set_title("ФАЙЛЫ · %s" % _folder_name(grid.folder_id),
				"ВЫБРАН: %s.%s" % [c.file_name, c.ext])
			return


func _on_file_activated(id: String) -> void:
	for c in grid.get_cards():
		if c.id == id:
			_toast("ПРОСМОТР: %s.%s" % [c.file_name, c.ext], "info")


func _on_service_filter(on: bool) -> void:
	if on:
		var hidden := 0
		if grid != null:
			hidden = grid.hidden_count()
		_toast("СКРЫТО ОПАСНЫХ ОБЪЕКТОВ · %d" % hidden,
			"warn" if hidden > 0 else "info")
	else:
		_toast("ПОКАЗАНЫ ВСЕ ОБЪЕКТЫ", "info")


func _on_packet_connect(id: String) -> void:
	if controller == null or controller.hour_director == null:
		return
	var director = controller.hour_director
	var packet = director.active_packets.get(id)
	if packet == null:
		return
	if str(packet.protocol).to_lower() != "tcp":
		_toast("UDP-ПАКЕТ: СОЕДИНЕНИЕ НЕ ТРЕБУЕТСЯ", "warn")
		return
	# Успех: HourDirector сам эмитит show_connection, модалку покажет _on_show_connection.
	if director.connect_packet(id):
		return
	_toast("НЕ УДАЛОСЬ СОЕДИНИТЬСЯ: НЕТ СЛОТА ИЛИ ПАКЕТ НЕ ГОТОВ", "warn")


func _on_request_connect(id: String) -> void:
	if controller == null or controller.hour_director == null:
		return
	var director = controller.hour_director
	var req = director.active_requests.get(id)
	if req == null:
		return
	if str(req.protocol).to_lower() != "tcp":
		_toast("UDP-ЗАПРОС · СОЕДИНЕНИЕ НЕ ТРЕБУЕТСЯ", "warn")
		return
	if director.connect_request(id):
		return
	_toast("НЕ УДАЛОСЬ СОЕДИНИТЬСЯ: НЕТ СЛОТА ИЛИ ЗАПРОС УЖЕ ПОДКЛЮЧЁН", "warn")


func _on_request_reject(id: String) -> void:
	if controller == null or controller.hour_director == null:
		return
	if controller.hour_director.reject_request(id):
		_toast("ЗАПРОС ОТКЛОНЁН", "error")
		_refresh_hour()
	else:
		_toast("ЗАПРОС НЕ НАЙДЕН", "warn")


func _on_request_detach(request_id: String, slot_index: int) -> void:
	if controller == null or controller.hour_director == null:
		return
	var req = controller.hour_director.active_requests.get(request_id)
	if req == null:
		return
	if slot_index < 0 or slot_index >= req.required.size():
		return
	var file_id := str(req.required[slot_index])
	if not req.attached.has(file_id):
		_toast("ФАЙЛ НЕ ПРИКРЕПЛЁН", "info")
		return
	if controller.hour_director.detach_file(request_id, file_id):
		_toast("ФАЙЛ ОТСОЕДИНЁН ОТ ЗАПРОСА", "info")
		_refresh_hour()
	else:
		_toast("НЕ УДАЛОСЬ ОТСОЕДИНИТЬ", "warn")


func _on_file_to_request(request_id: String, _slot_index: int, payload: Dictionary) -> void:
	if controller == null or controller.hour_director == null:
		return
	var file_id := str(payload.get("id", ""))
	if file_id.is_empty():
		return
	if controller.hour_director.attach_file(request_id, file_id):
		_toast("ФАЙЛ ПРИКРЕПЛЁН", "success")
		_refresh_hour()
		_maybe_start_send(request_id)
	else:
		_toast("НЕ УДАЛОСЬ ПРИКРЕПИТЬ ФАЙЛ", "warn")


## Автостарт отправки, когда запрос собран и не занят мини-игрой/слотом.
func _maybe_start_send(req_id: String) -> void:
	if controller == null or controller.hour_director == null:
		return
	var director = controller.hour_director
	var req = director.active_requests.get(req_id)
	if req == null:
		return
	if not req.is_ready() or req.minigame_active or req.sending:
		return
	if director.start_send(req_id):
		return
	_toast("ОТПРАВКА НЕ НАЧАЛАСЬ: НЕТ СЛОТА ИЛИ ПАПКА ЗАБЛОКИРОВАНА", "warn")


func _on_slot_close(id: String) -> void:
	if controller == null or controller.hour_director == null or id.is_empty():
		return
	var director = controller.hour_director
	var handled := false
	var req = director.active_requests.get(id)
	if req != null:
		if director.slots != null:
			director.slots.release_by_entity(id)
		req.connected = false
		req.slot_reserved = false
		req.sending = false
		req.send_progress = 0.0
		handled = true
	else:
		var packet = director.active_packets.get(id)
		if packet != null:
			if director.slots != null:
				director.slots.release_by_entity(id)
			# Прерванная загрузка возвращает резерв слота папки.
			if str(packet.state) == "loading" and not str(packet.loading_folder_id).is_empty():
				if Game.registry != null:
					Game.registry.release_slot(str(packet.loading_folder_id))
				packet.loading_folder_id = ""
			packet.state = "waiting"
			packet.loading_progress = 0.0
			handled = true
	if handled:
		_toast("ПЕРЕДАЧА ПРЕРВАНА · СЛОТ СВОБОДЕН", "warn")
		_refresh_hour()


func _on_slot_press(id: String) -> void:
	for c in slot_cells:
		if c.id == id and c.state == "locked":
			_toast("СЛОТ ДОСТУПЕН В МАГАЗИНЕ", "info")


func _on_packet_to_slot(_cell_id: String, payload: Dictionary) -> void:
	# Слот занимает только настоящее соединение; drop — это попытка подключить.
	if bool(payload.get("is_attack", false)) \
			or not str(payload.get("attack_kind", "")).is_empty():
		_toast("УГРОЗУ — В ЩИТ", "warn")
		return
	var packet_id := str(payload.get("id", ""))
	if packet_id.is_empty():
		return
	_on_packet_connect(packet_id)


func _on_drop_to_folder(folder_id: String, payload: Dictionary) -> void:
	if controller == null:
		return
	var kind := str(payload.get("kind", "file"))
	var entity_id := str(payload.get("id", ""))
	var folder_label := folder_id
	if Game.registry != null and Game.registry.folders.has(folder_id):
		folder_label = str(Game.registry.folders[folder_id].name)
	if kind == "packet":
		if entity_id.is_empty() or controller.hour_director == null:
			return
		if controller.hour_director.receive_packet(entity_id, folder_id):
			_toast("ПАКЕТ ПРИНЯТ В «%s»" % folder_label, "success")
			_refresh_hour()
		else:
			_toast("ПАПКА ЗАПОЛНЕНА ИЛИ НЕТ СОЕДИНЕНИЯ", "warn")
		return
	if kind != "file":
		return
	if entity_id.is_empty() or Game.registry == null:
		return
	if Game.registry.move_file(entity_id, folder_id):
		controller.save()
		if controller.phase == GAME_CONTROLLER.PHASE_PREP:
			_refresh_prep()
		else:
			_refresh_hour()
		_toast("ПЕРЕМЕЩЕНО: %s → «%s»" % [str(payload.get("name", "файл")), folder_label], "success")
	else:
		_toast("НЕ УДАЛОСЬ ПЕРЕМЕСТИТЬ ФАЙЛ", "warn")


func _on_tree_context(folder_id: String, pos: Vector2) -> void:
	var is_section := folder_id.begins_with("sec_")
	var items := [
		{"label": "Новая папка", "id": "new"},
		{"label": "Переименовать", "id": "rename", "disabled": is_section},
		{"label": "Удалить", "id": "delete", "disabled": is_section},
		{"sep": true},
		{"label": "Уничтожить содержимое", "id": "destroy", "danger": true},
	]
	ContextMenu90.show_items(self, items, pos, _on_tree_menu.bind(folder_id))


func _on_tree_menu(action: String, folder_id: String) -> void:
	match action:
		"new":
			_new_folder_in(folder_id)
		"rename":
			_open_rename(folder_id)
		"delete":
			_delete_folder(folder_id)
		"destroy":
			_confirm_destroy_folder(folder_id)
		_:
			_toast("НЕИЗВЕСТНОЕ ДЕЙСТВИЕ", "warn")


## «Уничтожить содержимое»: спрашиваем подтверждение, если папка не пуста.
func _confirm_destroy_folder(folder_id: String) -> void:
	if Game.registry == null or not Game.registry.folders.has(folder_id):
		_toast("ПАПКА НЕ НАЙДЕНА", "warn")
		return
	var file_ids := _folder_file_ids(folder_id)
	if file_ids.is_empty():
		_toast("ПАПКА ПУСТА", "warn")
		return
	if confirm_modal == null:
		return
	var folder_name := str(Game.registry.folders[folder_id].name)
	_confirm_action = "destroy:" + folder_id
	confirm_modal.ask("Уничтожить содержимое?",
		"Файлы папки «%s» будут удалены. Штраф −5 SLA." % folder_name,
		"Уничтожить", "Отмена", true)


func _folder_file_ids(folder_id: String) -> Array:
	var out: Array = []
	if Game.registry == null:
		return out
	for file_id in Game.registry.files.keys():
		var file = Game.registry.files[file_id]
		if file != null and str(file.folder_id) == folder_id:
			out.append(str(file_id))
	return out


## Реальное уничтожение: удаляем файлы папки и списываем 5 SLA.
func _destroy_folder_contents(folder_id: String) -> void:
	if Game.registry == null or not Game.registry.folders.has(folder_id):
		_toast("ПАПКА НЕ НАЙДЕНА", "warn")
		return
	var file_ids := _folder_file_ids(folder_id)
	if file_ids.is_empty():
		_toast("ПАПКА ПУСТА", "warn")
		return
	var registry = Game.registry
	for file_id in file_ids:
		# remove_file штатно удаляет только malicious/failed; для осознанного
		# уничтожения помечаем файл и сразу удаляем.
		if not registry.remove_file(file_id):
			registry.mark_malicious(file_id, "destroy")
			registry.remove_file(file_id)
		if _selected_file == file_id:
			_selected_file = ""
	Game.add_sla(-5.0, "destroy")
	if controller != null:
		controller.save()
	if controller != null and controller.phase == GAME_CONTROLLER.PHASE_PREP:
		_refresh_prep()
	else:
		_refresh_hour()
	_toast("СОДЕРЖИМОЕ УНИЧТОЖЕНО · SLA −5", "error")
	if status_bar != null:
		status_bar.flash("sla", "−5", Theme90.ERROR)


## Открыть диалог переименования папки (только для реальных папок, не секций).
func _open_rename(folder_id: String) -> void:
	if Game.registry == null or not Game.registry.folders.has(folder_id):
		_toast("ПАПКА НЕ НАЙДЕНА", "warn")
		return
	if rename_modal == null:
		return
	_rename_folder_id = folder_id
	rename_modal.open(str(Game.registry.folders[folder_id].name))
	_sync_modal_pause()


## Применить новое имя из RenameModal: пустое/длинное/дубль — только тост.
func _on_rename_confirmed(new_name: String) -> void:
	_sync_modal_pause()
	var folder_id := _rename_folder_id
	_rename_folder_id = ""
	if Game.registry == null or not Game.registry.folders.has(folder_id):
		_toast("ПАПКА НЕ НАЙДЕНА", "warn")
		return
	var clean := new_name.strip_edges()
	if clean.is_empty():
		_toast("ИМЯ ПАПКИ НЕ МОЖЕТ БЫТЬ ПУСТЫМ", "warn")
		return
	if clean.length() > 16:
		_toast("ИМЯ ДЛИННЕЕ 16 СИМВОЛОВ", "warn")
		return
	if not Game.registry.rename_folder(folder_id, clean):
		_toast("ПАПКА С ТАКИМ ИМЕНЕМ УЖЕ ЕСТЬ", "warn")
		return
	if controller != null:
		controller.save()
	_refresh_prep()
	_toast("ПАПКА ПЕРЕИМЕНОВАНА", "success")


## Удаление папки: реестр разрешает только пустые (без файлов и резерваций).
func _delete_folder(folder_id: String) -> void:
	if Game.registry == null:
		_toast("ХРАНИЛИЩЕ НЕДОСТУПНО", "error")
		return
	if not Game.registry.delete_folder(folder_id):
		_toast("МОЖНО УДАЛИТЬ ТОЛЬКО ПУСТУЮ ПАПКУ", "warn")
		return
	if controller != null:
		controller.save()
	if _selected_file.is_empty() or not Game.registry.files.has(_selected_file):
		_selected_file = ""
	if controller != null and controller.phase == GAME_CONTROLLER.PHASE_PREP:
		_refresh_prep()
	elif controller != null:
		_refresh_hour()
	_toast("ПАПКА УДАЛЕНА", "success")


func _on_file_context(id: String, pos: Vector2) -> void:
	var items := [
		{"label": "Открыть", "id": "open"},
		{"label": "Прикрепить к запросу", "id": "attach"},
		{"label": "Переименовать", "id": "rename"},
		{"sep": true},
		{"label": "Уничтожить", "id": "destroy", "danger": true},
	]
	ContextMenu90.show_items(self, items, pos, _on_file_menu.bind(id))


func _on_file_menu(action: String, file_id: String) -> void:
	match action:
		"open":
			_on_file_activated(file_id)
		"attach":
			_toast("ВЫБЕРИТЕ ЗАПРОС В ОКНЕ «ОТПРАВКА»", "info")
		"rename":
			_toast("ПЕРЕИМЕНОВАНИЕ ФАЙЛА НЕДОСТУПНО", "info")
		"destroy":
			_destroy_selected_file(file_id)
		_:
			_toast("НЕИЗВЕСТНОЕ ДЕЙСТВИЕ", "warn")


## Уничтожение файла: malicious/locked — это угроза, остальное не удаляется.
func _destroy_selected_file(file_id: String) -> void:
	if Game.registry == null or not Game.registry.files.has(file_id):
		_toast("ФАЙЛ НЕ НАЙДЕН", "warn")
		return
	var file = Game.registry.files[file_id]
	var loc := str(file.location)
	if loc != "malicious" and loc != "locked":
		_toast("ОБЫЧНЫЕ ФАЙЛЫ НЕ УДАЛЯЮТСЯ", "warn")
		return
	var director = controller.hour_director if controller != null else null
	var ok := false
	if director != null and director.has_method("destroy_attack_file"):
		ok = bool(director.destroy_attack_file(file_id))
	if not ok and Game.registry.has_method("destroy_malicious"):
		ok = bool(Game.registry.destroy_malicious(file_id))
	if not ok:
		_toast("НЕ УДАЛОСЬ УНИЧТОЖИТЬ УГРОЗУ", "warn")
		return
	if controller != null:
		controller.save()
	if controller != null and controller.phase == GAME_CONTROLLER.PHASE_PREP:
		_refresh_prep()
	else:
		_refresh_hour()
	_toast("УГРОЗА УНИЧТОЖЕНА", "success")


func _on_new_folder() -> void:
	_new_folder_in(grid.folder_id)


## «Новая папка» — реальная папка в FileRegistry, затем перерисовка подготовки.
func _new_folder_in(folder_id: String) -> void:
	var section_id := _section_of_folder(folder_id)
	if section_id.is_empty() and controller != null:
		var d: Dictionary = controller.prep_data()
		if not (d.get("sections", []) as Array).is_empty():
			section_id = str(d["sections"][0].get("id", ""))
	if section_id.is_empty():
		_toast("НЕ ВЫБРАНА СЕКЦИЯ", "warn")
		return
	if Game.registry == null:
		_toast("ХРАНИЛИЩЕ НЕДОСТУПНО", "error")
		return
	if _section_folder_count(section_id) >= 12:
		_toast("В СЕКЦИИ УЖЕ 12 ПАПОК", "warn")
		return
	# Имя генерируется из пула Data и делается уникальным внутри секции.
	var folder_name := _unique_folder_name(section_id, Data.folder_name())
	var folder = Game.registry.create_folder(section_id, folder_name)
	if folder == null:
		_toast("НЕ УДАЛОСЬ СОЗДАТЬ ПАПКУ", "error")
		return
	if controller != null:
		controller.save()
	_refresh_prep()
	_on_folder_selected(str(folder.id))
	_toast("СОЗДАНА ПАПКА «%s»" % str(folder.name), "success")


## Уникальное имя в секции: «Имя», «Имя 2», «Имя 3», … с обрезкой до 16.
func _unique_folder_name(section_id: String, base: String) -> String:
	var clean := base.strip_edges()
	if clean.is_empty():
		clean = "Разное"
	if clean.length() > 16:
		clean = clean.substr(0, 16)
	if not _folder_name_taken(section_id, clean):
		return clean
	var index := 2
	while index < 100:
		var suffix := " %d" % index
		var stem := clean.substr(0, maxi(1, 16 - suffix.length()))
		var candidate := (stem + suffix).strip_edges()
		if not _folder_name_taken(section_id, candidate):
			return candidate
		index += 1
	return clean.substr(0, 16)


func _folder_name_taken(section_id: String, candidate: String) -> bool:
	if Game.registry == null:
		return false
	var probe := candidate.to_lower()
	for folder in Game.registry.folders.values():
		if str(folder.section) == section_id \
				and str(folder.name).to_lower() == probe:
			return true
	return false


func _section_folder_count(section_id: String) -> int:
	if Game.registry == null:
		return 0
	var n := 0
	for folder in Game.registry.folders.values():
		if str(folder.section) == section_id:
			n += 1
	return n


func _section_of_folder(folder_id: String) -> String:
	if folder_id.is_empty():
		return ""
	if folder_id.begins_with("sec_"):
		return folder_id
	if Game.registry == null:
		return ""
	var folder = Game.registry.folders.get(folder_id)
	if folder == null:
		return ""
	return str(folder.section)


func _on_shop() -> void:
	if shop_modal == null:
		return
	# Магазин доступен только в подготовке и после открытия (час 2).
	if controller == null or controller.phase != GAME_CONTROLLER.PHASE_PREP:
		_toast("МАГАЗИН ДОСТУПЕН В ПОДГОТОВКЕ", "warn")
		return
	if not Game.feature_unlocked("shop"):
		_toast("МАГАЗИН ОТКРОЕТСЯ ПОСЛЕ ПЕРВОГО ЧАСА", "warn")
		return
	if mascot != null:
		mascot.hide_message()
	shop_modal.open(Game.money, Game.upgrades)


func _on_shop_buy(id: String) -> void:
	if controller == null:
		return
	if controller.buy(id):
		_toast("КУПЛЕНО: %s" % _shop_item_name(id), "success")
	shop_modal.refresh(Game.money, Game.upgrades)
	_refresh_prep()


## Название позиции магазина для тоста (id — только фолбэк).
func _shop_item_name(id: String) -> String:
	var data := get_node_or_null("/root/Data")
	if data != null and data.has_method("shop_item"):
		var item: Dictionary = data.call("shop_item", id)
		var item_name := str(item.get("name_ru", item.get("name", "")))
		if not item_name.is_empty():
			return item_name
	if controller != null and controller.shop != null \
			and controller.shop.has_method("get_item"):
		var item2: Dictionary = controller.shop.get_item(id)
		var item_name2 := str(item2.get("name_ru", item2.get("name", "")))
		if not item_name2.is_empty():
			return item_name2
	return id


func _on_start_hour() -> void:
	if controller == null:
		return
	if controller.phase != GAME_CONTROLLER.PHASE_PREP:
		_toast("ЧАС УЖЕ ИДЁТ", "warn")
		return
	if not controller.start_hour():
		_toast("ЧАС НЕ МОЖЕТ НАЧАТЬСЯ", "warn")
		return
	# phase_changed уже вызвал _on_phase("hour"); вызов идемпотентен.
	_on_phase(GAME_CONTROLLER.PHASE_HOUR)


func _toast(text: String, kind: String = "info") -> void:
	if toast_layer != null:
		toast_layer.toast(text, kind)


# --------------------------------------------------------------------------
# Фон
# --------------------------------------------------------------------------

class Backdrop:
	extends Control

	## Спокойный фон: без dither, ровная бумажная заливка.
	var calm := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		if calm:
			draw_rect(Rect2(Vector2.ZERO, size), Theme90.PAPER)
		else:
			draw_texture_rect(Theme90.dither_texture(), Rect2(Vector2.ZERO, size), true)
		draw_rect(Rect2(0, 0, size.x, 1), Theme90.SHADE)
		draw_rect(Rect2(0, 0, 1, size.y), Theme90.SHADE)
		draw_rect(Rect2(size.x - 1, 0, 1, size.y), Theme90.FACE_HI)
		draw_rect(Rect2(0, size.y - 1, size.x, 1), Theme90.FACE_HI)


# --------------------------------------------------------------------------
# Щит-карантин (drop-зона + кнопка удержания против DDoS)
# --------------------------------------------------------------------------

class ShieldDrop:
	extends Control

	var main: Node = null
	var target := "receive"
	var active := false
	var progress := 0.0
	var holding := false
	var _hover := false


	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func() -> void:
			_hover = true
			queue_redraw())
		mouse_exited.connect(func() -> void:
			_hover = false
			queue_redraw())
		tooltip_text = "ЩИТ · ПЕРЕТАЩИТЕ СЮДА УГРОЗУ"


	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var bg := Theme90.NAVY_DEEP if active else Theme90.NAVY
		draw_rect(r, bg)
		var edge := Theme90.ERROR if active else (Theme90.ACCENT_LIGHT if _hover else Theme90.FACE_LO)
		draw_rect(r, edge, false, 1.0)

		# щит: полигон + крест
		var fill := Theme90.ERROR if active and holding else Theme90.FACE_HI
		var shield := PackedVector2Array([
			Vector2(10, 2), Vector2(17, 4), Vector2(16, 11),
			Vector2(10, 16), Vector2(4, 11), Vector2(3, 4),
		])
		draw_colored_polygon(shield, fill)
		draw_polyline(PackedVector2Array([
			Vector2(10, 2), Vector2(17, 4), Vector2(16, 11),
			Vector2(10, 16), Vector2(4, 11), Vector2(3, 4), Vector2(10, 2),
		]), Theme90.WHITE, 1.0)
		var cross := Theme90.ERROR if not active else Theme90.WHITE
		draw_line(Vector2(10, 5), Vector2(10, 12), cross, 1.0)
		draw_line(Vector2(6, 8), Vector2(14, 8), cross, 1.0)

		var f := Theme90.ui()
		Theme90.text(self, f, Vector2(20, 3), "ЩИТ", 8,
			Theme90.ERROR if active else Theme90.ACCENT_LIGHT, 26)

		# прогресс удержания
		if active:
			var bar := Rect2(20, 13, 25, 3)
			draw_rect(bar, Theme90.NAVY_DEEP)
			var ratio := clampf(progress, 0.0, 1.0)
			draw_rect(Rect2(bar.position, Vector2(floorf(bar.size.x * ratio), bar.size.y)),
				Theme90.SUCCESS if ratio >= 1.0 else Theme90.ERROR)
		else:
			Theme90.text(self, f, Vector2(20, 12), "DROP", 7, Theme90.FACE_LO, 26)


	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		if not (data is Dictionary):
			return false
		if str(data.get("kind", "")) != "packet":
			return false
		return bool(data.get("is_attack", false)) or not str(data.get("attack_kind", "")).is_empty()


	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		if main != null and data is Dictionary and main.has_method("_on_quarantine_drop"):
			main.call("_on_quarantine_drop", data)


	func _gui_input(event: InputEvent) -> void:
		if not (event is InputEventMouseButton):
			return
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			if main != null and main.has_method("_on_shield_press"):
				main.call("_on_shield_press", target)
		else:
			if main != null and main.has_method("_on_shield_release"):
				main.call("_on_shield_release")
		accept_event()


# --------------------------------------------------------------------------
# Плашка DDoS над карточками приёма
# --------------------------------------------------------------------------

class DdosOverlay:
	extends Control

	var cards := 10
	var hold := 0.0
	var needed := 1.5
	var _t := 0.0


	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)


	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()


	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Theme90.NAVY_DEEP)
		var pulse := 0.45 + 0.55 * absf(sin(_t * 4.0))
		draw_rect(r, Color(Theme90.ERROR, pulse), false, 1.0)
		draw_rect(Rect2(0, 0, size.x, 1), Theme90.ERROR)

		var f := Theme90.ui()
		Theme90.text(self, f, Vector2(6, 3), "DDoS · %d КАРТОЧЕК · ДЕРЖИТЕ ЩИТ" % cards,
			10, Theme90.WHITE, 392)

		# 8–12 маленьких красных прямоугольников
		var shown := mini(maxi(cards, 8), 12)
		for i in shown:
			draw_rect(Rect2(6.0 + i * 13.0, 19.0, 9.0, 8.0), Theme90.ERROR)
			draw_rect(Rect2(6.0 + i * 13.0, 19.0, 9.0, 1.0), Theme90.ERROR.lightened(0.45))

		# шкала удержания щита
		var bar := Rect2(180, 21, 214, 4)
		draw_rect(bar, Theme90.NAVY)
		draw_rect(Rect2(bar.position, Vector2(1, bar.size.y)), Theme90.SHADE)
		var ratio := clampf(hold / maxf(0.1, needed), 0.0, 1.0)
		draw_rect(Rect2(bar.position, Vector2(floorf(bar.size.x * ratio), bar.size.y)),
			Theme90.SUCCESS if ratio >= 1.0 else Theme90.ERROR)
