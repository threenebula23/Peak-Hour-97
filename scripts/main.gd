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
const ATTACK_ALERT := preload("res://scripts/ui/attack_alert.gd")

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
## «ЖАРА»: термометр в меню-баре и полноэкранный слой нагрева.
var temperature_gauge: TemperatureGauge
var stress_overlay: StressOverlay

var tree: TreePanel
var grid: FileGrid
## Стол сортировки v2: правая колонка подготовки вместо ПРИЁМ/ОТПРАВКА.
var sorting_table: SortingTable
## Центральный drag-контроллер (превью фигура/квадрат, hover-open папок).
var drag_controller: DragController = null
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
## M8: троттлинг тоста «буфер полон» (не чаще раза в ~5 с).
var _spawn_frozen_toast_ms: int = -100000
## Активная модалка мини-игры (отправка/атака/соединение); вторая не открывается.
var _modal_game: Node = null
## Тип активной модалки: "send" / "attack" / "connection" / "".
var _modal_kind := ""
## Полноэкранное предупреждение «ИДЁТ АТАКА» перед мини-игрой.
var _attack_alert = null
## Последние значения для flash/pulse счётчиков и ценника папки.
var _last_money_seen := -1
var _last_sla_seen := -1.0
var _pulse_tweens: Dictionary = {}
## M2: шаг обучения «send» подтверждается один раз за открытие мини-игры.
var _send_tutorial_notified := false

## Туториал первого часа показывается один раз за забег/реплей.
var _tutorial_shown := false
var _tutorial_intro_shown := false
var _tutorial_after_shown := false
## Шаги обучения: key — событие завершения, timeout — аварийный автопереход.
const TUTORIAL_STEPS := [
	{"key": "packet",
		"text": "Перетащи пакет из «ПРИЁМА» в папку", "timeout": 30.0},
	{"key": "attach",
		"text": "Открой папку и перетащи файл в карточку запроса", "timeout": 40.0},
	{"key": "connect",
		"text": "Нажми «ПОДКЛЮЧИТЬСЯ» и попади в зелёную зону три раза",
		"timeout": 45.0},
	{"key": "send",
		"text": "Пройди мини-игру: качество влияет на оплату", "timeout": 40.0},
	{"key": "sla", "text": "Следи за SLA и отражай атаки", "timeout": 12.0},
]
const TUTORIAL_ACK_SECONDS := 0.6
const TUTORIAL_CLOSE_SECONDS := 0.9

var _tutorial_active := false
var _tutorial_pending := false
var _tutorial_closing := false
var _tutorial_step := -1
var _tutorial_step_elapsed := 0.0
var _tutorial_ack_left := 0.0
var _tutorial_close_left := 0.0
var _tutorial_waiting_spawn := false
var _tutorial_force_show := false
var _tutorial_overlay = null
var _tutorial_next_btn: Button90 = null
## Пустое состояние ОТПРАВКИ: неинтерактивная плашка внутри content.
var _requests_empty: Control = null
var _requests_empty_hint: Label = null

## --- Автообновление подготовки по сигналам FileRegistry -------------------
## Реестр, к которому подключены сигналы (меняется после load/new_run).
var _bound_registry = null
var _registry_refresh_queued := false
## Последние применённые настройки: Game.start_new_run очищает stats,
## поэтому кэшируем их здесь и возвращаем в stats после нового забега.
var _settings_cache: Dictionary = {}

## Канал был перегружен в прошлом кадре — чтобы flash не спамил.
var _channel_hot := false

## Автопауза часа, пока открыты служебные модалки (настройки/подтверждение/имя).
var _auto_paused := false
## Проверка web-fullscreen после асинхронного запроса браузера.
var _fs_verify_token := 0

## --- «ЖАРА»: снимок часа и прошлые значения для ΔSLA ----------------------
## Длительность часа в начале смены (fallback, если core не отдаёт hour_total).
var _hour_total_cache := 0.0
## SLA на прошлом снимке; -1 — ещё не инициализировано.
var _last_sla := -1.0
## Исходные позиции панелей на время событийного сдвига (≤140 мс).
var _kick_origin: Dictionary = {}
var _kick_tweens: Dictionary = {}
## Карточки, которые сейчас доигрывают loss-анимацию (instance_id -> true).
## Их нельзя считать orphan-детьми при rebuild, пока идёт fade.
var _loss_cards: Dictionary = {}
## Твины фазовых фейдов, чтобы не наслаивать.
var _phase_tweens: Dictionary = {}
## Исходные позиции панелей для фазового сдвига 6→0 (не двигаем layout навсегда).
var _phase_origin: Dictionary = {}

## --- Скролл списка ПРИЁМ (5–8 пакетов не влезают в 416×264) ---------------
var _recv_bar: ScrollBar90
var _recv_scroll := 0.0
const RECV_CARD_H := 56.0
const RECV_WHEEL_STEP := 24.0

## --- Скролл карточек ОТПРАВКИ: карточка v2 (2×2 чипа), запросов до 4 --------
var _send_bar: ScrollBar90
var _send_scroll := 0.0
const REQ_CARD_H := 128.0

## --- Поиск по файлам (апгрейд shop_search) --------------------------------
var _search_edit: LineEdit
## Полный список файлов текущей папки; в grid уходит отфильтрованный.
var _current_files: Array = []


func _ready() -> void:
	_create_drag_controller()
	_build()
	_bind_game_juice_signals()
	_connect_all()
	_rename_slot_labels()
	controller = GAME_CONTROLLER.new()
	controller.name = "GameController"
	add_child(controller)
	controller.phase_changed.connect(_on_phase)
	controller.shop_changed.connect(_on_shop_changed)
	_build_modals()
	_apply_saved_settings()
	_init_mascot()
	_init_tutorial_hud()
	_bind_registry_signals()
	main_menu.set_has_save(controller.can_continue())
	if not controller.can_continue() and controller.has_save():
		main_menu.set_has_save(false, "Забег завершён — начните новый")
	main_menu.visible = true
	_apply_phase_panels(true)
	_update_shop_visibility()
	_fade_modal(main_menu, 0.20)
	if _demo_requested():
		call_deferred("_start_demo")


## Один DragController под Main: его находят FileGrid/SortingTable/TreePanel.
func _create_drag_controller() -> void:
	drag_controller = DragController.new()
	drag_controller.name = "DragController"
	add_child(drag_controller)


func _process(delta: float) -> void:
	_tutorial_tick(delta)
	if controller == null:
		return
	_clear_modal_if_dead()
	var phase: StringName = controller.phase
	var d: Dictionary = {}
	if phase == GAME_CONTROLLER.PHASE_HOUR:
		_sync_modal_pause()
		controller.tick(delta)
		# Один снимок часа на кадр: и для карточек, и для heat-модели.
		d = controller.hour_data()
		# tick мог завершить час — тогда экран уже переключился на отчёт.
		if controller.phase == GAME_CONTROLLER.PHASE_HOUR:
			_refresh_hour(d)
	elif phase == GAME_CONTROLLER.PHASE_HOUR_RESULT \
			or phase == GAME_CONTROLLER.PHASE_RUN_RESULT:
		d = controller.hour_data()
	_tick_stress(delta, d)


## Esc: закрывает верхнюю модалку, ставит смену на паузу или игнорируется.
func _unhandled_input(event: InputEvent) -> void:
	# Во время «ИДЁТ АТАКА» ввод заблокирован полноэкранным alert.
	if _attack_alert != null and is_instance_valid(_attack_alert) \
			and _attack_alert.visible:
		_mark_input_handled()
		return
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
		_fade_modal(pause_modal, 0.16)


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
		"reduce_motion": bool(_settings_cache.get("reduce_motion", false)),
	})
	_sync_modal_pause()
	_fade_modal(settings_modal, 0.16)


## Применить настройки из SettingsModal и (по умолчанию) сохранить их.
func _apply_settings(values: Dictionary, persist: bool = true) -> void:
	var sfx := clampi(int(values.get("sfx", int(round(Audio.sfx_volume * 100.0)))), 0, 100)
	var music := clampi(int(values.get("music", int(round(Audio.music_volume * 100.0)))), 0, 100)
	var calm := bool(values.get("calm_bg", true))
	var full := bool(values.get("fullscreen", false))
	var vhs := bool(values.get("vhs", true))
	# Ключ reduce_motion может отсутствовать в старом сейве — тогда не сбрасываем.
	var reduce_motion := bool(_settings_cache.get("reduce_motion", false))
	if values.has("reduce_motion"):
		reduce_motion = bool(values.get("reduce_motion", false))
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
	UiMotion.reduced = reduce_motion
	if reduce_motion:
		_restore_event_motion()
	if stress_overlay != null:
		stress_overlay.set_reduced(reduce_motion)
	if temperature_gauge != null:
		temperature_gauge.set_reduced(reduce_motion)
	if status_bar != null:
		status_bar.set_reduced(reduce_motion)
	_settings_cache = {"sfx": sfx, "music": music, "calm_bg": calm,
		"fullscreen": full, "vhs": vhs, "reduce_motion": reduce_motion}
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
	_fade_modal(confirm_modal, 0.16)


## Информационное окно «О программе» (пункт меню МЕНЮ).
func _show_about() -> void:
	if confirm_modal == null:
		return
	_confirm_action = ""
	confirm_modal.ask("PEAK HOUR 97",
		"Диспетчер файлового обмена · версия 0.1.0 · Godot 4.7.2",
		"OK", "Закрыть")
	_sync_modal_pause()
	_fade_modal(confirm_modal, 0.16)


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
		_refresh_menu_save_state()
		main_menu.visible = true
		_fade_modal(main_menu, 0.20)


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
	main_menu.tutorial_requested.connect(_on_menu_tutorial)
	main_menu.settings.connect(_open_settings)
	main_menu.about.connect(_show_about)
	main_menu.visible = true

	shop_modal = ShopModal.new()
	shop_modal.name = "ShopModal"
	modal_root.add_child(shop_modal)
	shop_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shop_modal.buy_requested.connect(_on_shop_buy)
	shop_modal.reroll_requested.connect(_on_shop_reroll)
	shop_modal.lock_toggled.connect(_on_shop_lock)
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
			elif action.begins_with("file:"):
				_destroy_normal_file(action.substr("file:".length()))
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
	# start_tutorial(replay) из меню до «Нового забега» не должен теряться.
	var tutorial_replay_pending := _tutorial_pending or _tutorial_force_show
	_tutorial_reset()
	if tutorial_replay_pending:
		_tutorial_pending = true
		_tutorial_force_show = true
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
	_reset_stress()
	# Game.start_new_run создаёт новый FileRegistry — переподключаем сигналы.
	_bind_registry_signals()
	main_menu.visible = false
	_refresh_prep()


## Публичный алиас для тестов/инструментов.
func start_new_run() -> void:
	_start_new_run()


## «ОБУЧЕНИЕ» в главном меню: сбрасываем tutorial_done и стартуем новый забег,
## чтобы обучение прошло в подготовке и первом часу. Если забег уже идёт,
## не начинаем второй — просто перезапускаем обучение на текущем часу.
func _on_menu_tutorial() -> void:
	if controller != null and controller.phase != GAME_CONTROLLER.PHASE_MENU:
		start_tutorial(true)
		return
	start_tutorial(true)
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
		_toast("ЗАБЕГ ЗАВЕРШЁН · НАЧНИТЕ НОВЫЙ", "warn")
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
	var d: Dictionary = _enrich_prep_data(controller.prep_data())
	var sections: Array = d.get("sections", [])
	tree.set_data(sections)
	_refresh_folder_price()
	tree_window.set_title("ДИСКИ",
		_plural_ru(_count_folders(sections), "ПАПКА", "ПАПКИ", "ПАПОК"))

	var folder_id := ""
	var folder_name := ""
	var section_id := ""
	var keep := str(grid.folder_id) if grid != null else ""
	var first_meta: Dictionary = {}
	for sec in sections:
		for fol in sec.get("folders", []):
			var meta := {"id": str(fol.get("id", "")),
				"name": str(fol.get("name", "")),
				"section": str(sec.get("id", ""))}
			if first_meta.is_empty():
				first_meta = meta
			if not keep.is_empty() and str(meta["id"]) == keep:
				folder_id = str(meta["id"])
				folder_name = str(meta["name"])
				section_id = str(meta["section"])
				break
		if not folder_id.is_empty():
			break
	if folder_id.is_empty() and not first_meta.is_empty():
		folder_id = str(first_meta.get("id", ""))
		folder_name = str(first_meta.get("name", ""))
		section_id = str(first_meta.get("section", ""))

	_clear_hour_panels()
	if folder_id.is_empty():
		grid.set_folder("", "ПАПКА", "C: \\")
		_current_files = []
		grid.set_filter("")
		files_window.set_title("ФАЙЛЫ · ПУСТО")
		if workspace != null:
			workspace.title_right = ""
	else:
		tree.select_folder(folder_id)
		_show_folder(folder_id, folder_name, section_id, d)
	if sorting_table != null:
		sorting_table.refresh()
	_apply_phase_panels(true)
	_update_status(d)
	_update_shop_visibility()
	_maybe_show_prep_tutorial()


## v2: prep_data контроллера ещё отдаёт capacity=16; заменяем на реальные
## клетки папки из реестра, чтобы дерево показывало «занято/всего клеток».
func _enrich_prep_data(d: Dictionary) -> Dictionary:
	var out := d.duplicate(true)
	var registry = Game.registry
	if registry == null:
		return out
	for sec in out.get("sections", []):
		var free_cells := 0
		var capacity_total := 0
		for fol in sec.get("folders", []):
			var folder = registry.folders.get(str(fol.get("id", "")))
			if folder == null:
				continue
			var stats: Dictionary = registry.folder_cell_stats(str(folder.id))
			fol["occupied_cells"] = int(stats.get("occupied", 0))
			fol["total_cells"] = int(stats.get("total", 20))
			fol["files"] = int(stats.get("files", 0))
			fol["count"] = int(stats.get("occupied", 0))
			fol["capacity"] = int(stats.get("total", 20))
			free_cells += int(stats.get("free", 0))
			capacity_total += int(stats.get("total", 20))
		sec["free_cells"] = free_cells
		sec["capacity"] = capacity_total
	return out


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


## Подсветка цели и маленький «ДАЛЕЕ»: оба не перекрывают игровой ввод.
func _init_tutorial_hud() -> void:
	_tutorial_overlay = TutorialHighlight.new()
	_tutorial_overlay.name = "TutorialHighlight"
	add_child(_tutorial_overlay)
	_tutorial_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tutorial_overlay.visible = false

	_tutorial_next_btn = Button90.new()
	_tutorial_next_btn.name = "TutorialNext"
	_tutorial_next_btn.caption = "ДАЛЕЕ"
	_tutorial_next_btn.caption_size = 10
	_tutorial_next_btn.flat_style = true
	_tutorial_next_btn.size = Vector2(58, 16)
	_tutorial_next_btn.tooltip_text = "Пропустить шаг обучения"
	_tutorial_next_btn.pressed.connect(_tutorial_skip_current)
	add_child(_tutorial_next_btn)
	_tutorial_next_btn.visible = false
	if modal_root != null:
		move_child(_tutorial_overlay, modal_root.get_index())
		move_child(_tutorial_next_btn, modal_root.get_index())


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


## Совместимость с dev_capture: показать конкретный шаг без таймеров.
func _show_tutorial_step(index: int) -> void:
	if not _tutorial_enabled():
		return
	_tutorial_reset()
	_tutorial_shown = true
	_tutorial_active = true
	_tutorial_force_show = true
	_tutorial_begin_step(clampi(int(index), 0, TUTORIAL_STEPS.size() - 1))


## Публичный запуск/реплей обучения (вызывает главное меню или тесты).
func start_tutorial(replay: bool = false) -> void:
	if replay and Game.stats != null:
		Game.stats["tutorial_done"] = false
	_tutorial_reset()
	_tutorial_shown = true
	_tutorial_active = true
	_tutorial_pending = true
	_tutorial_force_show = true
	if controller != null and controller.phase == GAME_CONTROLLER.PHASE_HOUR:
		_tutorial_pending = false
		_tutorial_begin_auto()


## Автозапуск только на первом часу и только пока обучение не пройдено.
func _maybe_show_tutorial() -> void:
	if not _tutorial_enabled() or controller == null:
		return
	if controller.phase != GAME_CONTROLLER.PHASE_HOUR:
		return
	if _tutorial_active:
		# Возврат из меню/настроек: bubble мог быть скрыт — восстанавливаем.
		_tutorial_restore_bubble()
		return
	if _tutorial_pending:
		_tutorial_pending = false
		_tutorial_begin_auto()
		return
	if _tutorial_shown or int(Game.hour) != 1:
		return
	if Game.stats != null and bool(Game.stats.get("tutorial_done", false)):
		return
	_tutorial_shown = true
	_tutorial_begin_auto()


## Сразу начинаем шаг (a), если пакет уже есть; иначе ждём packet_added.
func _tutorial_begin_auto() -> void:
	_tutorial_active = true
	_tutorial_closing = false
	_tutorial_step = -1
	_tutorial_step_elapsed = 0.0
	_tutorial_ack_left = 0.0
	_tutorial_waiting_spawn = false
	if _tutorial_force_show or _has_hour_packet():
		_tutorial_begin_step(0)
	else:
		_tutorial_waiting_spawn = true
		if mascot != null:
			mascot.set_step(1)
			mascot.show_message("Ждём первый пакет…", -1.0)
		_tutorial_hide_targets()


func _has_hour_packet() -> bool:
	if not packets.is_empty():
		return true
	var director = _hour_director()
	return director != null and not director.active_packets.is_empty()


## HourDirector текущего контроллера (null до создания/после перезапуска).
func _hour_director():
	return controller.hour_director if controller != null else null


func _on_hour_packet_added(_id: String) -> void:
	_kick_panels(1)
	if _tutorial_active and _tutorial_waiting_spawn:
		_tutorial_waiting_spawn = false
		_tutorial_begin_step(0)


func _on_hour_request_added(_id: String) -> void:
	_kick_panels(1)


func _tutorial_begin_step(index: int) -> void:
	if not _tutorial_active:
		return
	if index >= TUTORIAL_STEPS.size():
		_tutorial_close()
		return
	_tutorial_step = index
	_tutorial_step_elapsed = 0.0
	_tutorial_ack_left = 0.0
	_tutorial_waiting_spawn = false
	_tutorial_closing = false
	var step: Dictionary = TUTORIAL_STEPS[index]
	if mascot != null:
		mascot.set_step(index + 1)
		mascot.show_message(str(step.get("text", "")), -1.0)
	_tutorial_update_targets()
	_position_tutorial_next()
	if _tutorial_next_btn != null:
		_tutorial_next_btn.visible = true


func _tutorial_tick(delta: float) -> void:
	if controller != null and controller.phase != GAME_CONTROLLER.PHASE_HOUR:
		return
	if _tutorial_closing:
		_tutorial_close_left = maxf(0.0, _tutorial_close_left - delta)
		if _tutorial_close_left <= 0.0:
			_tutorial_hide()
		return
	if not _tutorial_active or _tutorial_step < 0:
		return
	if _tutorial_step >= TUTORIAL_STEPS.size():
		return
	if _tutorial_ack_left > 0.0:
		_tutorial_ack_left = maxf(0.0, _tutorial_ack_left - delta)
		if _tutorial_ack_left <= 0.0:
			_tutorial_begin_step(_tutorial_step)
		return
	_tutorial_step_elapsed += delta
	var step: Dictionary = TUTORIAL_STEPS[_tutorial_step]
	if _tutorial_step_elapsed >= float(step.get("timeout", 30.0)):
		_tutorial_advance(true)


## Событие шага: принимаем только текущий key (остальные игнорируем).
func _tutorial_notify(key: String) -> void:
	if not _tutorial_active or _tutorial_closing or _tutorial_step < 0:
		return
	if _tutorial_ack_left > 0.0 or _tutorial_step >= TUTORIAL_STEPS.size():
		return
	if str(TUTORIAL_STEPS[_tutorial_step].get("key", "")) != key:
		return
	_tutorial_advance(false)


## Пропуск текущего шага кнопкой «ДАЛЕЕ».
func _tutorial_skip_current() -> void:
	if not _tutorial_active or _tutorial_closing:
		return
	_tutorial_advance(true)


func _tutorial_advance(skipped: bool) -> void:
	if not _tutorial_active or _tutorial_step < 0:
		return
	if _tutorial_step >= TUTORIAL_STEPS.size() - 1:
		_tutorial_close()
		return
	_tutorial_step += 1
	_tutorial_step_elapsed = 0.0
	_tutorial_ack_left = TUTORIAL_ACK_SECONDS
	if mascot != null:
		mascot.set_step(0)
		mascot.show_message("ПРОПУСК" if skipped else "ГОТОВО", -1.0)
	_tutorial_hide_targets()
	if _tutorial_next_btn != null:
		_tutorial_next_btn.visible = false


## Финал: фиксируем прохождение в stats (они уже сохраняются в save.json).
func _tutorial_close() -> void:
	_tutorial_active = false
	_tutorial_closing = true
	_tutorial_close_left = TUTORIAL_CLOSE_SECONDS
	_tutorial_step = -1
	_tutorial_step_elapsed = 0.0
	_tutorial_ack_left = 0.0
	_tutorial_waiting_spawn = false
	_tutorial_hide_targets()
	if mascot != null:
		mascot.set_step(0)
		mascot.show_message("ГОТОВО · ОБУЧЕНИЕ ЗАВЕРШЕНО", -1.0)
	if Game.stats != null:
		Game.stats["tutorial_done"] = true
	if controller != null:
		controller.save()


func _tutorial_hide() -> void:
	_tutorial_active = false
	_tutorial_pending = false
	_tutorial_closing = false
	_tutorial_step = -1
	_tutorial_step_elapsed = 0.0
	_tutorial_ack_left = 0.0
	_tutorial_waiting_spawn = false
	_tutorial_force_show = false
	if mascot != null:
		mascot.hide_message()
	_tutorial_hide_targets()


func _tutorial_reset() -> void:
	_tutorial_active = false
	_tutorial_pending = false
	_tutorial_closing = false
	_tutorial_step = -1
	_tutorial_step_elapsed = 0.0
	_tutorial_ack_left = 0.0
	_tutorial_close_left = 0.0
	_tutorial_waiting_spawn = false
	_tutorial_force_show = false
	_tutorial_hide_targets()
	if mascot != null:
		mascot.hide_message()


func _tutorial_restore_bubble() -> void:
	if not _tutorial_active or _tutorial_closing or mascot == null:
		return
	if mascot.visible:
		return
	if _tutorial_step >= 0 and _tutorial_step < TUTORIAL_STEPS.size():
		mascot.set_step(_tutorial_step + 1)
		mascot.show_message(str(TUTORIAL_STEPS[_tutorial_step].get("text", "")), -1.0)
		_tutorial_update_targets()
		_position_tutorial_next()
		if _tutorial_next_btn != null:
			_tutorial_next_btn.visible = true
	elif _tutorial_waiting_spawn:
		mascot.set_step(1)
		mascot.show_message("Ждём первый пакет…", -1.0)


func _position_tutorial_next() -> void:
	if mascot == null or _tutorial_next_btn == null:
		return
	_tutorial_next_btn.position = mascot.position + Vector2(
		maxf(0.0, mascot.size.x - _tutorial_next_btn.size.x),
		mascot.size.y + 2.0)


func _tutorial_hide_targets() -> void:
	if _tutorial_overlay != null:
		_tutorial_overlay.set_targets([])
		_tutorial_overlay.visible = false
	if _tutorial_next_btn != null:
		_tutorial_next_btn.visible = false


func _tutorial_update_targets() -> void:
	if _tutorial_overlay == null:
		return
	var rects: Array = _tutorial_targets(_tutorial_step)
	_tutorial_overlay.set_targets(rects)
	_tutorial_overlay.visible = not rects.is_empty()


func _tutorial_targets(index: int) -> Array:
	if index < 0 or index >= TUTORIAL_STEPS.size():
		return []
	var key := str(TUTORIAL_STEPS[index].get("key", ""))
	match key:
		"packet":
			return [_control_rect(receive_window)]
		"attach":
			return [_control_rect(files_window.content if files_window != null else null),
				_control_rect(send_window)]
		"connect":
			for card in requests:
				if card != null and is_instance_valid(card):
					return [_control_rect(card)]
			return [_control_rect(send_window)]
		"send":
			return [_control_rect(send_window)]
		"sla":
			return [_status_segment_rect("sla")]
	return []


## Прямоугольник контрола в координатах Main (оверлей — тоже ребёнок Main).
func _control_rect(control: Control) -> Rect2:
	if control == null or not is_instance_valid(control):
		return Rect2()
	var global := control.get_global_rect()
	return Rect2(global.position - get_global_position(), global.size)


## Сегмент статус-бара по key: повторяем публичную раскладку segments,
## не трогая status_bar.gd другого lane.
func _status_segment_rect(key: String) -> Rect2:
	if status_bar == null:
		return Rect2()
	var segs: Array = status_bar.segments
	var total := 0.0
	for s in segs:
		total += float(s.get("w", 0.0))
	if total <= 0.0:
		return Rect2()
	var start := 8.0
	var right := maxf(start + 1.0, status_bar.size.x - 8.0)
	var span := right - start
	var acc := 0.0
	var left := start
	for i in segs.size():
		var s: Dictionary = segs[i]
		acc += float(s.get("w", 0.0))
		var x1 := right
		if i < segs.size() - 1:
			x1 = roundf(start + span * (acc / total))
		if str(s.get("key", "")) == key:
			return Rect2(status_bar.position + Vector2(left, 0.0),
				Vector2(maxf(1.0, x1 - left), status_bar.size.y))
		left = x1
	return Rect2()


## Слоты полосы — общие для приёма и отправки, поэтому подпись «СЛОТЫ».
func _rename_slot_labels() -> void:
	if status_bar == null:
		return
	var segs: Array = status_bar.segments
	for s in segs:
		if s is Dictionary and str(s.get("key", "")) == "tcp":
			s["label"] = "СЛОТЫ"
			break
	status_bar.queue_redraw()


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
	var sections: Array = _enrich_prep_data(d).get("sections", [])
	var known: Dictionary = {}
	for sec in sections:
		for fol in sec.get("folders", []):
			known[str(fol.get("id", ""))] = {
				"files": int(fol.get("files", 0)),
				"occupied": int(fol.get("occupied_cells", 0)),
				"total": int(fol.get("total_cells", 0)),
			}
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
		var info: Dictionary = known[id]
		if same:
			tree.update_stats(str(id), int(info["files"]), int(info["occupied"]),
				int(info["total"]))
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
	# Магазин появляется после первого часа и скрыт во время часа.
	_shop_btn.visible = in_prep and int(Game.hour) > 1
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


## Заголовок окна ФАЙЛЫ: имя папки и (при фильтре) число найденных файлов.
## Занятость диска в заголовке не дублируем — счётчики остаются в дереве/сетке.
func _update_files_title() -> void:
	if files_window == null or grid == null:
		return
	var folder_label := _folder_name(grid.folder_id).to_upper()
	if folder_label.is_empty():
		folder_label = "ПАПКА"
	var hint := ""
	var query := ""
	if _search_edit != null and _search_edit.visible:
		query = _search_edit.text.strip_edges()
	if not query.is_empty():
		hint = "найдено %d" % _filtered_files().size()
	files_window.set_title("ФАЙЛЫ · %s" % folder_label, hint)
	if workspace != null:
		workspace.title_right = ""


## Файлы текущей папки, подходящие под строку поиска.
func _filtered_files() -> Array:
	var query := ""
	if _search_edit != null and _search_edit.visible:
		query = _search_edit.text.strip_edges().to_lower()
	if query.is_empty():
		return _current_files.duplicate()
	var filtered: Array = []
	for f in _current_files:
		var name := str(f.get("name", "")).to_lower()
		var ext := str(f.get("ext", "")).to_lower()
		if name.find(query) >= 0 or ("%s.%s" % [name, ext]).find(query) >= 0:
			filtered.append(f)
	return filtered


## Фильтр сетки по подстроке имени: FileGrid приглушает несовпадения,
## позиции фигур сохраняются (set_filter, а не пересоздание списка).
func _apply_file_filter() -> void:
	if grid == null:
		return
	var query := ""
	if _search_edit != null and _search_edit.visible:
		query = _search_edit.text.strip_edges().to_lower()
	grid.set_filter(query)
	_update_files_title()


func _folder_meta(d: Dictionary, folder_id: String) -> Dictionary:
	for sec in d.get("sections", []):
		for fol in sec.get("folders", []):
			if str(fol.get("id", "")) == folder_id:
				return {"name": str(fol.get("name", "")), "section": str(sec.get("id", ""))}
	return {}


func _tcp_max(_upgrades: Dictionary) -> int:
	return maxi(1, int(Game.connection_slots()))


func _update_status(d: Dictionary) -> void:
	var sla := int(round(float(d.get("sla", 0.0))))
	var hour := int(d.get("hour", 1))
	var sla_cap := maxi(1, int(round(float(Game.sla_cap()))))
	var channel_cap := maxi(1, int(round(float(Game.channel_capacity()))))
	var slots_max := maxi(1, int(Game.connection_slots()))
	var buffer_max := maxi(1, int(Game.buffer_limit()))
	status_bar.set_metric("money", "$ %d" % int(d.get("money", 0)))
	status_bar.set_metric("sla", "%d / %d" % [sla, sla_cap],
		clampf(float(sla) / float(sla_cap), 0.0, 1.0))
	status_bar.set_metric("hour", "ЧАС %d" % hour,
		float(hour - 1) / float(GAME_CONTROLLER.HOURS_PER_RUN))
	status_bar.set_metric("tcp", "0 / %d" % slots_max, 0.0)
	status_bar.set_metric("buffer", "0 / %d" % buffer_max, 0.0)
	status_bar.set_metric("channel", "0/%d" % channel_cap, 0.0, false)
	_channel_hot = false


func _clear_hour_panels() -> void:
	_requests_empty = null
	_requests_empty_hint = null
	for c in receive_window.content.get_children():
		# Скроллбар ПРИЁМА живёт всё время — его не пересоздаём.
		if c == _recv_bar:
			continue
		receive_window.content.remove_child(c)
		c.queue_free()
	for c in send_window.content.get_children():
		if c == _send_bar:
			continue
		send_window.content.remove_child(c)
		c.queue_free()
	packets.clear()
	requests.clear()
	_recv_scroll = 0.0
	_send_scroll = 0.0
	if _recv_bar != null:
		var h := maxf(1.0, receive_window.content.size.y)
		_recv_bar.set_metrics(h, h, 0.0)
		_recv_bar.visible = false
	if _send_bar != null:
		var h2 := maxf(1.0, send_window.content.size.y)
		_send_bar.set_metrics(h2, h2, 0.0)
		_send_bar.visible = false
	for c in slot_cells:
		if is_instance_valid(c):
			if c.get_parent() != null:
				c.get_parent().remove_child(c)
			c.queue_free()
	slot_cells.clear()
	if slot_count_label != null:
		slot_count_label.text = "0/%d" % _tcp_max(Game.upgrades)
	receive_window.set_title("ПРИЁМ", _plural_ru(0, "ПАКЕТ", "ПАКЕТА", "ПАКЕТОВ"))
	send_window.set_title("ОТПРАВКА", _plural_ru(0, "ЗАПРОС", "ЗАПРОСА", "ЗАПРОСОВ"))


func _on_phase(phase: StringName) -> void:
	if _attack_alert != null and is_instance_valid(_attack_alert):
		_attack_alert.finish_now()
		_attack_alert = null
	_clear_modal_if_dead()
	if phase != GAME_CONTROLLER.PHASE_HOUR:
		# Вне часа не должно оставаться ни одной игровой модалки: send/attack
		# иначе висят поверх итогов часа/забега.
		_drop_active_game_modal()
		# Обучение живёт только внутри часа 1; вне часа шаги не тикают.
		if _tutorial_active or _tutorial_closing:
			_tutorial_hide()
	match phase:
		GAME_CONTROLLER.PHASE_PREP:
			_hour_ui_shown = false
			if main_menu != null:
				main_menu.visible = false
			if hour_result_modal != null:
				hour_result_modal.visible = false
			_reset_stress()
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
	_fade_phase()


## v2: в подготовке правая колонка — стол сортировки (4×6), в час —
## окна ПРИЁМ и ОТПРАВКА. Окна не пересоздаются, только переключаются.
func _apply_phase_panels(is_prep: bool) -> void:
	if receive_window != null:
		receive_window.visible = not is_prep
	if send_window != null:
		send_window.visible = not is_prep
	if sorting_table != null:
		sorting_table.visible = is_prep


## Настоящий экран часа: карточки пакетов/запросов, слоты и статус.
func _show_hour() -> void:
	if _hour_ui_shown:
		_refresh_hour()
		return
	_hour_ui_shown = true
	if mascot != null:
		mascot.hide_message()
	_reset_stress()
	var active_director = _hour_director()
	_hour_total_cache = maxf(0.0, float(active_director.time_left)) \
		if active_director != null else 0.0
	_clear_hour_panels()
	_apply_phase_panels(false)
	_refresh_folder_price()
	_connect_hour_signals()
	_bind_attack_stress_signals()
	_refresh_hour()
	_update_shop_visibility()
	_toast("ЧАС %d НАЧАЛСЯ" % Game.hour, "success")


## Сигналы контроллера, которые нужны UI часа (подключаются один раз).
func _connect_hour_signals() -> void:
	if controller == null or _hour_signals_connected:
		return
	_hour_signals_connected = true
	controller.hour_finished.connect(_on_hour_finished)
	controller.run_finished.connect(_on_run_finished)
	controller.toast.connect(func(text: String) -> void: _toast(text, "info"))
	controller.show_minigame.connect(_on_show_minigame)
	controller.show_connection.connect(_on_show_connection)
	controller.show_attack_minigame.connect(_on_show_attack_minigame)
	# Принудительное закрытие (конец часа / отмена атаки) освобождает ноду
	# раньше, чем UI успевает получить finished — чистим висячий указатель.
	controller.minigame_closed.connect(_on_minigame_closed_ui)
	controller.attack_resolved.connect(_on_attack_resolved_ui)
	if controller.has_signal("slot_changed") \
			and not controller.slot_changed.is_connected(_on_slot_changed_ui):
		controller.slot_changed.connect(_on_slot_changed_ui)
	# Прямая страховка: HourDirector может эмитить packet_added сам.
	var director = _hour_director()
	if director != null:
		if director.has_signal("packet_added") \
				and not director.packet_added.is_connected(_on_hour_packet_added):
			director.packet_added.connect(_on_hour_packet_added)
		if director.has_signal("request_added") \
				and not director.request_added.is_connected(_on_hour_request_added):
			director.request_added.connect(_on_hour_request_added)
		# M8: спавн замер из-за полного буфера — раньше сигнал никто не слушал.
		if director.has_signal("spawn_frozen") \
				and not director.spawn_frozen.is_connected(_on_spawn_frozen_ui):
			director.spawn_frozen.connect(_on_spawn_frozen_ui)
		# «ЖАРА»: потеря/просрочка и снятие сущностей с доски.
		if director.has_signal("packet_removed") \
				and not director.packet_removed.is_connected(_on_packet_removed_stress):
			director.packet_removed.connect(_on_packet_removed_stress)
		if director.has_signal("request_removed") \
				and not director.request_removed.is_connected(_on_request_removed_stress):
			director.request_removed.connect(_on_request_removed_stress)
		# Core может добавить эти сигналы параллельно — подключаемся только если есть.
		if director.has_signal("packet_lost") \
				and not director.packet_lost.is_connected(_on_packet_lost_stress):
			director.packet_lost.connect(_on_packet_lost_stress)
		if director.has_signal("request_expired") \
				and not director.request_expired.is_connected(_on_request_expired_stress):
			director.request_expired.connect(_on_request_expired_stress)
		_bind_attack_stress_signals()


## M8: тост о заморозке приёма, не чаще раза в ~5 секунд.
## `no_space` — склад (папки/клетки) заполнен, иначе — буфер приёма.
func _on_spawn_frozen_ui(reason: String) -> void:
	if stress_overlay != null:
		stress_overlay.notify("spawn_frozen", 1.0)
	var now := Time.get_ticks_msec()
	if now - _spawn_frozen_toast_ms < 5000:
		return
	_spawn_frozen_toast_ms = now
	if reason == "no_space":
		_toast("СКЛАД ЗАПОЛНЕН · ПРИЁМ ОСТАНОВЛЕН", "error")
	else:
		_toast("БУФЕР ПРИЁМА ПОЛОН · ПРИЁМ ОСТАНОВЛЕН", "warn")


## Атака v2 — только модальная мини-игра, без карточек/оверлеев.
## Перед показом — короткий alert «ИДЁТ АТАКА» (1.1 с). В headless — сразу.
func _on_show_attack_minigame(game_node, kind: String) -> void:
	var attack_name := _attack_display_name(kind)
	_toast("АТАКА: %s" % attack_name.to_upper(), "warn")
	var headless := DisplayServer.get_name() == "headless"
	if not headless and game_node != null and is_instance_valid(game_node):
		var briefing := bool(game_node.get("_briefing")) \
			if game_node.get("_briefing") != null else false
		if not briefing:
			game_node.set_process(false)
			game_node.set_process_input(false)
		_attack_alert = ATTACK_ALERT.new()
		_attack_alert.name = "AttackAlert"
		if modal_root != null:
			modal_root.add_child(_attack_alert)
			modal_root.move_child(_attack_alert, -1)
		else:
			add_child(_attack_alert)
		_attack_alert.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_attack_alert.play("ИДЁТ АТАКА", attack_name, 1.1)
		await _attack_alert.finished
		_attack_alert = null
		# Игра умерла/отменена за время предупреждения — безопасно выходим.
		if not is_instance_valid(game_node) or game_node.is_queued_for_deletion():
			_restore_modal_open_state()
			return
		if controller == null or controller.phase != GAME_CONTROLLER.PHASE_HOUR:
			_restore_modal_open_state()
			return
		# Briefing-режим Lane B сам держит set_process(false) до кнопки СТАРТ.
		if not briefing:
			game_node.set_process(true)
			game_node.set_process_input(true)
	_show_attack_game(game_node, kind)


func _show_attack_game(game_node, _kind: String) -> void:
	if _show_modal_game(game_node, "attack"):
		_tutorial_notify("sla")
		return
	# C1: модалку не показали (экран занят) — атаку отменяем без штрафа,
	# иначе HourDirector останется в _attack_paused и час замрёт.
	var director = _hour_director()
	if director != null and director.attack_director != null \
			and director.attack_director.has_method("cancel_active"):
		director.attack_director.cancel_active()
	_restore_modal_open_state()


## Название атаки для alert: Data.attack_def(kind).name_ru, иначе kind.
func _attack_display_name(kind: String) -> String:
	if Data != null and Data.has_method("attack_def"):
		var def: Dictionary = Data.attack_def(kind)
		var name := str(def.get("name_ru", "")).strip_edges()
		if not name.is_empty():
			return name
	return _attack_kind_name(kind)


## C1: после отката чужой модалки вернуть controller.modal_open в актуальное
## состояние, не разблокировав час под всё ещё открытым окном.
func _restore_modal_open_state() -> void:
	if controller == null:
		return
	var open := _modal_game != null and is_instance_valid(_modal_game)
	if controller.has_method("set_modal_open"):
		controller.set_modal_open(open)
	else:
		controller.modal_open = open


func _attack_kind_name(kind: String) -> String:
	match kind:
		"junk":
			return "ФИЛЬТР"
		"ddos":
			return "ЩИТ"
		"phishing":
			return "ПАСПОРТ"
		"ransomware":
			return "КАРАНТИН"
	return kind.to_upper()


## HourDirector уже создал и запустил ConnectionGame — монтируем модалку.
func _on_show_connection(game_node) -> void:
	if game_node == null or not (game_node is Node):
		return
	if _show_connection_modal(game_node):
		return
	# C1: экран занят другой модалкой — откатываем соединение, чтобы запрос
	# не остался в connecting навсегда, и освобождаем не показанную ноду.
	var req_id := ""
	var raw_req = game_node.get("request_id")
	if raw_req != null:
		req_id = str(raw_req)
	var director = _hour_director()
	if not req_id.is_empty() and director != null \
			and director.has_method("connection_finished"):
		director.connection_finished(req_id, false)
	if not game_node.is_queued_for_deletion():
		game_node.queue_free()
	_restore_modal_open_state()


## ConnectionGame сам не ставит час на паузу: modal_open останавливает спавн,
## а таймер запроса заморожен флагом req.connecting в HourDirector.
## C1: возвращает false, если экран уже занят другой модалкой (не освобождая её).
func _show_connection_modal(game_node) -> bool:
	if game_node == null or modal_root == null:
		return false
	if _modal_game != null and _modal_game != game_node:
		# C1: чужую модалку НЕ освобождаем. Атака с открытым экраном
		# результата уже сбросила running, но ещё не эмитила finished —
		# queue_free здесь оставил бы час в _attack_paused навсегда.
		if is_instance_valid(_modal_game) and not _modal_game.is_queued_for_deletion():
			_toast("СНАЧАЛА ЗАКРОЙТЕ ТЕКУЩЕЕ ОКНО", "warn")
			return false
		# Указатель на уже освобождённую/закрывающуюся ноду — просто чистим.
		_modal_game = null
		_modal_kind = ""
	_modal_kind = "connection"
	_modal_game = game_node
	if controller != null:
		if controller.has_method("set_modal_open"):
			controller.set_modal_open(true)
		else:
			controller.modal_open = true
	if game_node.get_parent() == null:
		modal_root.add_child(game_node)
	elif game_node.get_parent() != modal_root:
		game_node.reparent(modal_root)
	if game_node is Control:
		# Окна мини-игр фиксированного размера — ставим по центру, не растягиваем.
		# PRESET_CENTER + MINSIZE обнуляет offsets, если размер ещё не применён:
		# сначала фиксируем минимальный размер, затем центрируем KEEP_SIZE.
		var ctl := game_node as Control
		ctl.size = ctl.get_combined_minimum_size()
		ctl.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	if game_node.has_signal("finished") \
			and game_node.finished.get_connections().is_empty():
		game_node.finished.connect(_on_connection_finished.bind(game_node))
	return true


## ConnectionGame.finished(success, request_id): применяем исход в директоре.
func _on_connection_finished(success: bool, req_id: String, game_node = null) -> void:
	var client := _request_client_name(str(req_id))
	var was_current: bool = _modal_game == game_node
	# Промах читаем ДО queue_free(): после удаления узел уже недоступен.
	var missed := false
	if game_node != null and is_instance_valid(game_node):
		missed = bool(game_node.get("missed"))
	if game_node != null and is_instance_valid(game_node):
		if game_node.get_parent() != null:
			game_node.get_parent().remove_child(game_node)
		if not game_node.is_queued_for_deletion():
			game_node.queue_free()
	if was_current:
		_modal_game = null
		_modal_kind = ""
		if controller != null:
			if controller.has_method("set_modal_open"):
				controller.set_modal_open(false)
			else:
				controller.modal_open = false
	var director = _hour_director()
	var connected_now := false
	if director != null and director.has_method("connection_finished"):
		director.connection_finished(str(req_id), bool(success), missed)
		if director.has_method("is_request_connected"):
			connected_now = bool(director.is_request_connected(str(req_id)))
	# Успех мини-игры создаёт соединение и занимает слот, но не открывает
	# отправку (её запускает только start_send). Если слота не было, тост
	# «УСТАНОВЛЕНО» врал бы — поэтому проверяем реальное соединение.
	if bool(success) and connected_now:
		_toast("СОЕДИНЕНИЕ УСТАНОВЛЕНО · %s" % client, "success")
		_tutorial_notify("connect")
	# BUG B: неуспех уже озвучивает HourDirector.connection_finished()
	# («СОЕДИНЕНИЕ НЕ УСТАНОВЛЕНО» + штраф за промах) — второй тост не нужен.
	_refresh_hour()


func _drop_connection_modal() -> void:
	if _modal_kind != "connection":
		return
	if _modal_game != null and is_instance_valid(_modal_game):
		if _modal_game.get_parent() != null:
			_modal_game.get_parent().remove_child(_modal_game)
		_modal_game.queue_free()
	_modal_game = null
	_modal_kind = ""
	if controller != null:
		if controller.has_method("set_modal_open"):
			controller.set_modal_open(false)
		else:
			controller.modal_open = false


## Снимает любую живую игровую модалку (send/connection/attack).
func _drop_active_game_modal() -> void:
	if _modal_game == null:
		_modal_kind = ""
		return
	if is_instance_valid(_modal_game):
		if _modal_game.get_parent() != null:
			_modal_game.get_parent().remove_child(_modal_game)
		if not _modal_game.is_queued_for_deletion():
			_modal_game.queue_free()
	_modal_game = null
	_modal_kind = ""
	if controller != null:
		if controller.has_method("set_modal_open"):
			controller.set_modal_open(false)
		else:
			controller.modal_open = false


func _request_client_name(req_id: String) -> String:
	var director = _hour_director()
	if director != null:
		var req = director.active_requests.get(str(req_id))
		if req != null:
			var client := str(req.client_name)
			if not client.is_empty():
				return client
	return "КЛИЕНТ"


## Отправка: HourDirector уже вызвал start() и создал MiniGame.
func _on_show_minigame(game_node) -> void:
	if _show_modal_game(game_node, "send"):
		return
	# C1: экран занят — мини-игру не показываем; принудительно закрываем её
	# в директоре, иначе запрос навсегда останется в minigame_active.
	var director = _hour_director()
	if director != null and director.has_method("force_close_send_minigame"):
		director.force_close_send_minigame()
	_restore_modal_open_state()


## HourDirector.force_close_send_minigame(): нода уже queue_free — снимаем модалку.
## M2: сигнал о закрытии приходит, пока _modal_kind ещё равен "send", — именно
## здесь фиксируем шаг обучения, иначе _clear_modal_if_dead обнулит kind раньше
## _on_modal_game_finished и «send» никогда не засчитается.
func _on_minigame_closed_ui(_req_id: String) -> void:
	if _modal_kind == "send" and not _send_tutorial_notified:
		_send_tutorial_notified = true
		_tutorial_notify("send")
	_clear_modal_if_dead()


## AttackDirector закончил/отменил атаку: нода уже queue_free — снимаем модалку.
func _on_attack_resolved_ui(_kind: String, success: bool, _tier: int) -> void:
	if _attack_alert != null and is_instance_valid(_attack_alert):
		_attack_alert.finish_now()
		_attack_alert = null
	if stress_overlay != null:
		stress_overlay.notify("relief" if success else "attack_fail")
	_clear_modal_if_dead()


## Сбрасывает _modal_game, если нода освобождена или стоит в очереди на free.
## Не трогает живую мини-игру и не запускает отправку запросов.
func _clear_modal_if_dead() -> void:
	if _modal_game != null:
		var dead := not is_instance_valid(_modal_game) \
			or _modal_game.is_queued_for_deletion()
		if not dead:
			return
		_modal_game = null
		_modal_kind = ""
		if controller != null:
			if controller.has_method("set_modal_open"):
				controller.set_modal_open(false)
			else:
				controller.modal_open = false
	# C1: страховка от soft-lock. Если модалок больше нет, но час всё ещё
	# заморожен незавершённой атакой — снимаем _attack_paused.
	if _modal_game == null:
		var director = _hour_director()
		if director != null and director.has_method("is_attack_paused") \
				and director.is_attack_paused() and bool(director.get("running")):
			director.set_attack_paused(false)


## C1: возвращает false, если экран уже занят другой модалкой. Чужую
## модалку НЕ освобождаем: атака на экране результата уже сбросила running,
## но ещё ждёт «ПРОДОЛЖИТЬ» — queue_free оставил бы час в _attack_paused.
func _show_modal_game(game_node, kind: String = "send") -> bool:
	if game_node == null or modal_root == null:
		return false
	if _modal_game != null and _modal_game != game_node:
		if is_instance_valid(_modal_game) and not _modal_game.is_queued_for_deletion():
			_toast("СНАЧАЛА ЗАКРОЙТЕ ТЕКУЩЕЕ ОКНО", "warn")
			return false
		# Указатель на уже освобождённую/закрывающуюся ноду — просто чистим.
		_modal_game = null
		_modal_kind = ""
	_modal_game = game_node
	_modal_kind = kind
	if kind == "send":
		_send_tutorial_notified = false
	# D2 (§5.5): модальные мини-игры сначала показывают q%/вердикт/ПРОДОЛЖИТЬ,
	# и только клик по кнопке эмитит finished (директор применяет исход).
	var deferred = game_node.get("defer_finish_signal")
	if deferred != null:
		game_node.set("defer_finish_signal", true)
	if controller != null:
		if controller.has_method("set_modal_open"):
			controller.set_modal_open(true)
		else:
			controller.modal_open = true
	if game_node.get_parent() == null:
		modal_root.add_child(game_node)
	elif game_node.get_parent() != modal_root:
		game_node.reparent(modal_root)
	if game_node is Control:
		# Окна мини-игр фиксированного размера — ставим по центру, не растягиваем.
		# PRESET_CENTER + MINSIZE обнуляет offsets, пока размер не устоялся:
		# сначала фиксируем минимальный размер, затем центрируем KEEP_SIZE.
		var ctl := game_node as Control
		ctl.size = ctl.get_combined_minimum_size()
		ctl.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	if game_node.has_signal("finished") \
			and game_node.finished.get_connections().is_empty():
		game_node.finished.connect(_on_modal_game_finished.bind(game_node))
	return true


## Общий обработчик finished у MiniGame (1 арг: quality).
## Параметр game_node приходит из bind(); атаку закрывает AttackDirector.
## ВАЖНО: сбрасываем _modal_game только для ЭТОЙ ноды и НЕ стартуем отправку.
func _on_modal_game_finished(_a = null, game_node = null) -> void:
	var was_send := _modal_kind == "send"
	if game_node == null and _a is Node:
		game_node = _a
	if game_node != null and is_instance_valid(game_node):
		# D2: отложенный MiniGame освобождает себя сам в _continue_clicked(),
		# а директор очереди/атаки — своим обработчиком finished. Не убиваем
		# ноду раньше, чем игрок увидел экран результата.
		var deferred = game_node.get("defer_finish_signal")
		var keep_alive: bool = deferred != null and bool(deferred)
		if not keep_alive and not game_node.is_queued_for_deletion():
			game_node.queue_free()
		if _modal_game == game_node:
			_modal_game = null
	_clear_modal_if_dead()
	if _modal_game == null and controller != null:
		if controller.has_method("set_modal_open"):
			controller.set_modal_open(false)
		else:
			controller.modal_open = false
	_modal_kind = ""
	if was_send and not _send_tutorial_notified:
		_send_tutorial_notified = true
		_tutorial_notify("send")
	# v2: отправка НЕ стартует автоматически по закрытию мини-игры — только
	# явная кнопка ОТПРАВИТЬ (или очередь слота внутри HourDirector).
	_refresh_hour()


# --------------------------------------------------------------------------
# Час: синхронизация карточек со снимком контроллера
# --------------------------------------------------------------------------

func _refresh_hour(data: Dictionary = {}) -> void:
	if controller == null:
		return
	var d: Dictionary = data if not data.is_empty() else controller.hour_data()
	var packet_data: Array = d.get("packets", [])
	var request_data: Array = d.get("requests", [])
	var slots_data: Array = d.get("slots", [])
	var status: Dictionary = d.get("status", {})

	_refresh_packets(packet_data)
	_refresh_requests(request_data)
	_refresh_slots(slots_data, packet_data, request_data)
	_refresh_hour_status(status)
	_refresh_hour_titles(packet_data, request_data, status)


func _refresh_hour_titles(packets_data: Array, requests_data: Array, _status: Dictionary) -> void:
	receive_window.set_title("ПРИЁМ",
		_plural_ru(packets_data.size(), "ПАКЕТ", "ПАКЕТА", "ПАКЕТОВ"))
	send_window.set_title("ОТПРАВКА",
		_plural_ru(requests_data.size(), "ЗАПРОС", "ЗАПРОСА", "ЗАПРОСОВ"))


# --------------------------------------------------------------------------
# Час: списки пакетов (скролл)
# --------------------------------------------------------------------------

func _reposition_packet_cards() -> void:
	var card_w := 392.0
	if receive_window != null and receive_window.content != null:
		# Оставляем 14 px справа под скроллбар + 6 px отступа слева.
		card_w = maxf(120.0, receive_window.content.size.x - 20.0)
	for i in packets.size():
		if is_instance_valid(packets[i]):
			packets[i].position = Vector2(6, 1 + i * RECV_CARD_H - _recv_scroll)
			packets[i].size = Vector2(card_w, 52)


## Высота списка пакетов: по RECV_CARD_H на карточку (DDoS-плашки больше нет).
func _recv_content_height(count: int) -> float:
	return float(maxi(0, count)) * RECV_CARD_H


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


func _card_ids(cards: Array) -> Array:
	# Lane B: play_loss() самоосвобождает карточку через ~0.58 c. Чистим
	# невалидные ссылки до сравнения ids, чтобы rebuild не падал на freed instance.
	for i in range(cards.size() - 1, -1, -1):
		var c = cards[i]
		if c == null or not is_instance_valid(c):
			cards.remove_at(i)
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
			if not is_instance_valid(c):
				continue
			receive_window.content.remove_child(c)
			c.queue_free()
		packets.clear()
		for i in data.size():
			var card := PacketCard.new()
			card.name = "Packet_%s" % str(data[i].get("id", ""))
			receive_window.content.add_child(card)
			card.custom_minimum_size = Vector2.ZERO
			card.position = Vector2(6, 1 + i * RECV_CARD_H - _recv_scroll)
			card.size = Vector2(maxf(120.0, receive_window.content.size.x - 20.0), 52)
			packets.append(card)

	for i in data.size():
		if i >= packets.size():
			break
		var p: Dictionary = data[i]
		var card := packets[i]
		if card == null or not is_instance_valid(card):
			continue
		var left := float(p.get("time_left", 0.0))
		var total := float(p.get("timer_total", 0.0))
		var progress := 0.0
		var duration := float(p.get("loading_duration", 0.0))
		if str(p.get("state", "")) == "loading" and duration > 0.0:
			progress = clampf(float(p.get("loading_progress", 0.0)) / duration, 0.0, 1.0)
		card.setup(str(p.get("id", "")), str(p.get("file_name", "")),
			_ext_for_type(str(p.get("type", ""))), str(p.get("type", "")),
			str(p.get("protocol", "")).to_upper(), left, total, progress,
			int(p.get("size_kb", 0)), str(p.get("state", "waiting")),
			str(p.get("shape_id", "O1")), int(p.get("rotation", 0)))
		card.set_time(left, total)

	_sync_recv_scroll(data.size())
	if rebuilt:
		# Пришли новые пакеты — показываем последний, не заставляя скроллить.
		_recv_scroll = maxf(0.0,
			_recv_content_height(data.size()) - maxf(1.0, receive_window.content.size.y))
		_sync_recv_scroll(data.size())


## Rebuild списка запросов не должен оставлять в дереве карточек, которых уже
## нет в `requests` (reject/timeout/успешная отправка). Карточки, доигрывающие
## fade (_loss_cards), не трогаем: их освободит tween.
func _prune_request_orphans() -> void:
	if send_window == null or send_window.content == null:
		return
	var known: Dictionary = {}
	for c in requests:
		if c != null and is_instance_valid(c):
			known[c.get_instance_id()] = true
	for child in send_window.content.get_children():
		if not (child is RequestCard):
			continue
		var cid := child.get_instance_id()
		if known.has(cid) or _loss_cards.has(cid):
			continue
		send_window.content.remove_child(child)
		child.queue_free()


func _refresh_requests(data: Array) -> void:
	if not data.is_empty():
		_remove_requests_empty()
	var ids: Array = []
	for r in data:
		ids.append(str(r.get("id", "")))
	if not _same_ids(ids, _card_ids(requests)):
		for c in requests:
			if not is_instance_valid(c):
				continue
			send_window.content.remove_child(c)
			c.queue_free()
		requests.clear()
		_prune_request_orphans()
		for i in data.size():
			var card := RequestCard.new()
			card.name = "Request_%s" % str(data[i].get("id", ""))
			send_window.content.add_child(card)
			card.custom_minimum_size = Vector2.ZERO
			card.position = Vector2(6, i * REQ_CARD_H - _send_scroll)
			card.size = Vector2(400, REQ_CARD_H)
			card.send_pressed.connect(_on_request_send)
			card.reject_pressed.connect(_on_request_reject)
			card.file_dropped.connect(_on_file_to_request)
			card.detach_pressed.connect(_on_request_detach)
			card.protocol_toggle_requested.connect(_on_request_protocol_toggle)
			card.connect_pressed.connect(_on_request_connect)
			requests.append(card)
	_layout_request_cards(data.size())

	for i in data.size():
		if i >= requests.size():
			break
		var r: Dictionary = data[i]
		if requests[i] == null or not is_instance_valid(requests[i]):
			continue
		var progress := 0.0
		var duration := float(r.get("send_duration", 0.0))
		if bool(r.get("sending", false)) and duration > 0.0:
			progress = clampf(float(r.get("send_progress", 0.0)) / duration, 0.0, 1.0)
		var required := int(r.get("required_count", 0))
		requests[i].setup(str(r.get("id", "")), str(r.get("client_name", "")),
			str(r.get("client_id", "")), str(r.get("protocol", "")).to_upper(),
			_request_slots(r), float(r.get("time_left", 0.0)),
			float(r.get("timer_total", 0.0)), progress, required,
			bool(r.get("queued", false)), bool(r.get("sending", false)),
			int(r.get("send_sum", 0)), str(r.get("minigame_id", "")),
			int(r.get("minigame_tier", 0)), bool(r.get("minigame_active", false)),
			bool(r.get("ready", false)), bool(r.get("connecting", false)),
			bool(r.get("connected", false)), str(r.get("connection_id", "")),
			float(r.get("udp_chance", 0.0)), float(r.get("udp_retry_left", 0.0)))
	_sync_send_scroll(data.size())
	if data.is_empty():
		_ensure_requests_empty()


## Высота карточки запроса v2 (контент с кнопками и предсказанием).
func _request_card_height(_count: int) -> float:
	return REQ_CARD_H


## Разложить карточки запросов по вертикали без пересоздания.
func _layout_request_cards(_count: int) -> void:
	if send_window == null or send_window.content == null:
		return
	var h := REQ_CARD_H
	# Карточка рисует фиксированную геометрию 400 px по ширине, поэтому тянем
	# её до 400, а ужимаем только если контент реально уже 400+отступов.
	var avail := send_window.content.size.x - 8.0
	var w := minf(400.0, maxf(120.0, avail))
	for i in requests.size():
		var card := requests[i]
		if card == null or not is_instance_valid(card):
			continue
		card.position = Vector2(6, i * h - _send_scroll)
		card.size = Vector2(w, h)
		card.queue_redraw()


## Слоты запроса: конкретные REQUIRED-файлы в порядке запроса (до 4).
## attached = файл уже в контейнере; null — required-файл исчез из реестра.
## Порядок attached не используется: слот i всегда соответствует required[i].
func _request_slots(request: Dictionary) -> Array:
	var ids: Array = request.get("required", [])
	if not (ids is Array):
		ids = []
	if ids.is_empty():
		var director = _hour_director()
		if director != null and director.has_method("request_required_ids"):
			ids = director.request_required_ids(str(request.get("id", "")))
	var attached: Array = request.get("attached", [])
	var registry = Game.registry
	var out: Array = []
	for i in mini(ids.size(), 4):
		var fid := str(ids[i])
		var file = registry.files.get(fid) if registry != null else null
		if file == null:
			# Required-файл исчез из реестра — не null, а явный «потерян»,
			# чтобы карточка показала красное состояние.
			out.append({
				"id": fid,
				"name": "ПОТЕРЯН",
				"ext": "",
				"type": "",
				"folder": "",
				"attached": false,
				"required": true,
				"missing": true,
			})
			continue
		var folder_name := ""
		if not str(file.folder_id).is_empty() and registry.folders.has(file.folder_id):
			folder_name = str(registry.folders[file.folder_id].name)
		out.append({
			"id": fid,
			"name": str(file.name),
			"ext": str(file.ext),
			"type": str(file.type),
			"folder": folder_name,
			"attached": attached.has(fid),
			"required": true,
		})
	if not out.is_empty():
		return out
	# Legacy-фолбэк, пока HourDirector не заполняет required конкретными id.
	var need := maxi(0, int(request.get("required_count", 0)))
	if need <= 0:
		need = maxi(1, attached.size())
	for i in need:
		if i >= attached.size():
			out.append(null)
			continue
		var fid2 := str(attached[i])
		var file2 = registry.files.get(fid2) if registry != null else null
		if file2 == null:
			out.append({
				"id": fid2,
				"name": "ПОТЕРЯН",
				"ext": "",
				"type": "",
				"folder": "",
				"attached": false,
				"required": true,
				"missing": true,
			})
			continue
		out.append({
			"id": fid2,
			"name": str(file2.name),
			"ext": str(file2.ext),
			"type": str(file2.type),
			"folder": "",
			"attached": true,
			"required": true,
		})
	return out


## Плашка пустого ОТПРАВКИ: не интерактивна и не мешает скроллу.
func _ensure_requests_empty() -> void:
	if send_window == null or send_window.content == null:
		return
	if _requests_empty != null and is_instance_valid(_requests_empty):
		_update_requests_empty()
		return
	var box := Control.new()
	box.name = "RequestsEmpty"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.focus_mode = Control.FOCUS_NONE
	send_window.content.add_child(box)
	_requests_empty = box

	var title := Label.new()
	title.name = "Title"
	title.text = "ОЖИДАНИЕ ЗАПРОСА"
	title.add_theme_font_override("font", Theme90.ui(800))
	title.add_theme_font_size_override("font_size", Theme90.FS_MICRO)
	title.add_theme_color_override("font_color", Theme90.NAVY)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title)

	var hint := Label.new()
	hint.name = "Hint"
	hint.add_theme_font_override("font", Theme90.ui())
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Theme90.DARK)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(hint)
	_requests_empty_hint = hint

	var quiet := Label.new()
	quiet.name = "Quiet"
	quiet.text = "Файлы приходят в «ПРИЁМ» — раскладывайте их по папкам"
	quiet.add_theme_font_override("font", Theme90.ui())
	quiet.add_theme_font_size_override("font_size", 10)
	quiet.add_theme_color_override("font_color", Theme90.SHADE)
	quiet.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quiet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(quiet)
	_update_requests_empty()


func _update_requests_empty() -> void:
	if _requests_empty == null or not is_instance_valid(_requests_empty):
		return
	var content := send_window.content if send_window != null else null
	if content == null:
		return
	_requests_empty.position = Vector2(8, 8)
	_requests_empty.size = Vector2(maxf(80.0, content.size.x - 26.0),
		maxf(60.0, content.size.y - 16.0))
	var title := _requests_empty.get_node_or_null("Title") as Label
	var hint := _requests_empty.get_node_or_null("Hint") as Label
	var quiet := _requests_empty.get_node_or_null("Quiet") as Label
	var w := _requests_empty.size.x
	if title != null:
		title.position = Vector2(0, 0)
		title.size = Vector2(w, 18)
	if hint != null:
		hint.text = _next_request_hint_text()
		hint.position = Vector2(0, 24)
		hint.size = Vector2(w, 38)
	if quiet != null:
		quiet.position = Vector2(0, _requests_empty.size.y - 36.0)
		quiet.size = Vector2(w, 34)
	_requests_empty_hint = hint


func _next_request_hint_text() -> String:
	var director = _hour_director()
	if director != null and director.has_method("next_request_hint"):
		var hint := str(director.next_request_hint()).strip_edges()
		if not hint.is_empty():
			return hint
	return "Следующий запрос скоро"


func _remove_requests_empty() -> void:
	if _requests_empty == null:
		return
	if is_instance_valid(_requests_empty):
		if _requests_empty.get_parent() != null:
			_requests_empty.get_parent().remove_child(_requests_empty)
		_requests_empty.queue_free()
	_requests_empty = null
	_requests_empty_hint = null


func _refresh_slots(data: Array, packets_data: Array = [],
		requests_data: Array = []) -> void:
	if slot_cells.size() != 5:
		for c in slot_cells:
			if is_instance_valid(c):
				if c.get_parent() != null:
					c.get_parent().remove_child(c)
				c.queue_free()
		slot_cells.clear()
		for i in 5:
			var cell := SlotCell.new()
			cell.name = "Slot_%d" % i
			slots_strip.add_child(cell)
			cell.position = Vector2(58 + i * 240, 5)
			cell.size = Vector2(236, 44)
			cell.cell_pressed.connect(_on_slot_press)
			cell.disconnect_pressed.connect(_on_slot_disconnect)
			slot_cells.append(cell)

	for i in 5:
		var cell := slot_cells[i]
		if i >= data.size():
			# Слоты сверх купленных: показываем замок, а не пустую ячейку.
			cell.setup("", "", "down", 0.0, "locked", "КУПИТЬ В МАГАЗИНЕ",
				str(i + 1))
			_hide_slot_close(cell)
			continue
		var s: Dictionary = data[i]
		var occupied := bool(s.get("occupied", false))
		var kind := str(s.get("kind", ""))
		var dir := "down" if str(s.get("direction", "")) == "in" else "up"
		var progress := 0.0
		if occupied:
			if kind == "tcp_connection":
				# У connection-слота entity_id — id соединения, а не запроса:
				# прогресс приходит готовым из snapshot.
				progress = clampf(float(s.get("progress", 0.0)), 0.0, 1.0)
			else:
				progress = _slot_entity_progress(str(s.get("entity_id", "")), dir,
					packets_data, requests_data)
				if progress <= 0.0:
					progress = clampf(float(s.get("progress", 0.0)), 0.0, 1.0)
		cell.setup(str(s.get("entity_id", "")), str(s.get("entity_name", "")), dir,
			progress,
			"active" if occupied else "empty",
			"" if occupied else "СВОБОДЕН", str(int(s.get("index", i)) + 1),
			kind, str(s.get("detail", "")), bool(s.get("can_disconnect", false)),
			bool(s.get("sending", false)))
		# У connection-слота своя кнопка ОТКЛЮЧИТЬ; старый крестик не нужен.
		_hide_slot_close(cell)


func _hide_slot_close(cell: Control) -> void:
	var close_btn := cell.get_node_or_null("CloseButton")
	if close_btn != null:
		(close_btn as Control).visible = false


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
			var duration := float(p.get("loading_duration", 0.0))
			if duration <= 0.0:
				return 0.0
			return clampf(float(p.get("loading_progress", 0.0)) / duration, 0.0, 1.0)
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
	var load := maxi(0, int(round(float(status.get("channel", 0.0)))))
	var capacity := maxi(1, int(round(float(Game.channel_capacity()))))
	var factor := float(status.get("channel_factor", 1.0))
	var sla := int(round(float(status.get("sla", 0.0))))
	var sla_cap := maxi(1, int(round(float(Game.sla_cap()))))
	var buffer_used := int(status.get("buffer_used", 0))
	var buffer_max := maxi(1, int(status.get("buffer_max", 0)))
	var hour := int(status.get("hour", 1))
	var left := maxf(0.0, float(status.get("time_left", 0.0)))
	var secs := int(ceilf(left))
	var hot := factor > 1.0001

	status_bar.set_metric("tcp", "%d / %d" % [used, max_slots],
		clampf(float(used) / float(max_slots), 0.0, 1.0))
	status_bar.set_metric("channel", "%d/%d" % [load, capacity],
		clampf(float(load) / float(capacity), 0.0, 2.0), hot)
	if hot and not _channel_hot:
		status_bar.flash("channel", "×%.2f" % factor, Theme90.ERROR)
	_channel_hot = hot
	status_bar.set_metric("sla", "%d / %d" % [sla, sla_cap],
		clampf(float(sla) / float(sla_cap), 0.0, 1.0))
	status_bar.set_metric("buffer", "%d / %d" % [buffer_used, buffer_max],
		clampf(float(buffer_used) / float(buffer_max), 0.0, 1.0))
	status_bar.set_metric("money", "$ %d" % int(status.get("money", 0)))
	status_bar.set_metric("hour", "ЧАС %d  %02d:%02d" % [hour, secs / 60, secs % 60],
		float(hour - 1) / float(GAME_CONTROLLER.HOURS_PER_RUN))
	if slot_count_label != null:
		slot_count_label.text = "%d/%d" % [used, max_slots]


# --------------------------------------------------------------------------
# «ЖАРА»: снимок часа, heat-оверлей и событийная тряска
# --------------------------------------------------------------------------

func _reset_stress() -> void:
	_hour_total_cache = 0.0
	_last_sla = -1.0
	if stress_overlay != null:
		stress_overlay.reset()
	if temperature_gauge != null:
		temperature_gauge.set_heat(0.0, 36, 0)
		temperature_gauge.set_breakdown({})
	if status_bar != null:
		status_bar.set_stress(0.0, 0)


## Снимок состояния часа для модели heat. Поля core (`request_limit`,
## `attacks_active`, `attacks_tier`, `hour_total`, `sending_count`,
## `queued_count`) используются, если есть; иначе — fallback по директору.
func _stress_snapshot(data: Dictionary = {}) -> Dictionary:
	if controller == null:
		return {}
	var d: Dictionary = data if not data.is_empty() else controller.hour_data()
	var st: Dictionary = d.get("status", {})
	var reqs: Array = d.get("requests", [])
	var director = _hour_director()
	var attacks_director = director.attack_director if director != null else null

	var sla := float(st.get("sla", Game.sla if Game != null else 0.0))
	var sla_cap := maxf(1.0, float(Game.sla_cap()) if Game != null else 60.0)

	var req_limit := int(st.get("request_limit", -1))
	if req_limit <= 0:
		req_limit = int(director.active_request_limit) if director != null else 1
	req_limit = maxi(1, req_limit)

	var attacks := int(st.get("attacks_active", -1))
	if attacks < 0:
		attacks = attacks_director.active_attacks.size() if attacks_director != null else 0
	var attack_tier := int(st.get("attacks_tier", -1))
	if attack_tier < 0:
		attack_tier = int(attacks_director._active_tier) if attacks_director != null else 0

	var has_counts: bool = st.has("sending_count") and st.has("queued_count")
	var sending := int(st.get("sending_count", 0)) if has_counts else 0
	var queued := int(st.get("queued_count", 0)) if has_counts else 0
	var urgent := 0
	for r in reqs:
		if not (r is Dictionary):
			continue
		if not has_counts:
			if bool(r.get("sending", false)):
				sending += 1
			if bool(r.get("queued", false)):
				queued += 1
		if float(r.get("time_ratio", 1.0)) < 0.25:
			urgent += 1

	var hour_total := float(st.get("hour_total", 0.0))
	if hour_total <= 0.0:
		if _hour_total_cache <= 0.0 and director != null:
			_hour_total_cache = maxf(0.001, float(director.time_left))
		hour_total = _hour_total_cache
	var time_left := float(st.get("time_left", 0.0))
	if time_left <= 0.0 and director != null:
		time_left = float(director.time_left)
	var hour_progress := 0.0
	if hour_total > 0.0:
		hour_progress = clampf(1.0 - time_left / hour_total, 0.0, 1.0)

	var channel := float(st.get("channel", 0.0))
	var channel_cap := maxf(1.0, float(Game.channel_capacity()) if Game != null else 10.0)
	var buffer_used := int(st.get("buffer_used", 0))
	var buffer_max := maxi(1, int(st.get("buffer_max", 1)))
	var slots_max := maxi(1, int(Game.connection_slots()) if Game != null else 1)

	_last_sla = sla
	return {
		"sla": sla,
		"sla_cap": sla_cap,
		"req_active": reqs.size(),
		"req_limit": req_limit,
		"attacks": attacks,
		"attack_tier": attack_tier,
		"channel": channel,
		"channel_capacity": channel_cap,
		"channel_ratio": clampf(channel / channel_cap, 0.0, 1.0),
		"buffer_used": buffer_used,
		"buffer_max": buffer_max,
		"buffer_ratio": clampf(float(buffer_used) / float(buffer_max), 0.0, 1.0),
		"urgent": urgent,
		"sending": sending,
		"queued": queued,
		"slots_max": slots_max,
		"hour_progress": hour_progress,
	}


func _tick_stress(delta: float, data: Dictionary = {}) -> void:
	if stress_overlay == null or controller == null:
		return
	var phase: StringName = controller.phase
	if phase == GAME_CONTROLLER.PHASE_MENU or phase == GAME_CONTROLLER.PHASE_PREP:
		# Подготовка: heat = 0, колба пустая.
		if stress_overlay.heat > 0.001 or stress_overlay.level != 0:
			_reset_stress()
		return
	var paused := false
	if phase == GAME_CONTROLLER.PHASE_HOUR:
		paused = bool(controller.paused) or _modal_game != null
		if settings_modal != null and settings_modal.visible:
			paused = true
		if confirm_modal != null and confirm_modal.visible:
			paused = true
		if rename_modal != null and rename_modal.visible:
			paused = true
	stress_overlay.set_inputs(_stress_snapshot(data))
	stress_overlay.tick(delta, paused)
	_sync_stress_ui()


func _sync_stress_ui() -> void:
	if stress_overlay == null:
		return
	if temperature_gauge != null:
		temperature_gauge.set_heat(stress_overlay.heat, stress_overlay.temp_c,
			stress_overlay.level)
		temperature_gauge.set_breakdown(stress_overlay.breakdown)
	if status_bar != null:
		status_bar.set_stress(stress_overlay.heat, stress_overlay.level)


func _on_stress_changed(_heat: float, _level: int, _temp_c: int) -> void:
	_sync_stress_ui()


func _on_attack_added_stress(_id: String) -> void:
	if stress_overlay == null:
		return
	stress_overlay.set_inputs(_stress_snapshot())
	stress_overlay.notify("attack_start")


## AttackDirector пересоздаётся каждый час — сигнал переподключаем перед стартом.
func _bind_attack_stress_signals() -> void:
	var director = _hour_director()
	var attacks = director.attack_director if director != null else null
	if attacks == null or not attacks.has_signal("attack_added"):
		return
	if not attacks.attack_added.is_connected(_on_attack_added_stress):
		attacks.attack_added.connect(_on_attack_added_stress)


func _on_packet_removed_stress(id: String) -> void:
	_check_sla_drop("packet", id)


func _on_request_removed_stress(id: String) -> void:
	_check_sla_drop("request", id)


## Core-сигналы появятся параллельно: подключаемся только при наличии.
func _on_packet_lost_stress(id: String) -> void:
	_mark_card_loss("packet", id)
	if stress_overlay != null:
		stress_overlay.notify("packet_lost")
	# Потерю SLA уже учли отдельным импульсом — не удваиваем на packet_removed.
	_last_sla = -1.0


func _on_request_expired_stress(id: String) -> void:
	_mark_card_loss("request", id)
	if stress_overlay != null:
		stress_overlay.notify("expired")
	_last_sla = -1.0


## Падение SLA между снимками: сила импульса зависит от абсолютной просадки.
func _check_sla_drop(kind: String = "", id: String = "") -> void:
	if stress_overlay == null or controller == null:
		return
	var d: Dictionary = controller.hour_data()
	var st: Dictionary = d.get("status", {})
	var now := float(st.get("sla", Game.sla if Game != null else 0.0))
	if _last_sla < 0.0:
		_last_sla = now
		return
	var drop := _last_sla - now
	_last_sla = now
	if drop > 0.5:
		stress_overlay.notify("sla_drop", drop)
		if not kind.is_empty():
			_mark_card_loss(kind, id)


## Безопасный крючок для Lane B: play_loss()/flash_error(), если реализованы.
## Карточка убирается из массива main.* сразу (rebuild не увидит freed instance),
## а из дерева — либо сама (PacketCard.play_loss), либо через короткий fade
## в _fade_out_card (RequestCard.flash_error не self-free).
func _mark_card_loss(kind: String, id: String) -> void:
	if kind == "packet":
		for i in range(packets.size() - 1, -1, -1):
			var c = packets[i]
			if c == null or not is_instance_valid(c):
				packets.remove_at(i)
				continue
			if str(c.get("id")) != str(id):
				continue
			_play_card_loss(c)
			packets.remove_at(i)
			return
		return
	for i in range(requests.size() - 1, -1, -1):
		var c = requests[i]
		if c == null or not is_instance_valid(c):
			requests.remove_at(i)
			continue
		if str(c.get("id")) != str(id):
			continue
		_play_card_loss(c)
		requests.remove_at(i)
		return


## PacketCard.play_loss() самоосвобождает ноду (Lane B) — его не трогаем.
## RequestCard.flash_error() только рисует тряску, поэтому такую карточку
## снимаем из дерева сами: иначе после reject она навсегда остаётся
## orphan-ребёнком send_window.content (в массиве её уже нет).
func _play_card_loss(c) -> void:
	if c.has_method("play_loss"):
		c.call("play_loss")
		return
	if c.has_method("flash_error"):
		c.call("flash_error")
	_fade_out_card(c)


## Короткий fade в main (без правок RequestCard) → remove_child + queue_free.
## В headless/«снизить эффекты» — сразу.
func _fade_out_card(c) -> void:
	if c == null or not is_instance_valid(c):
		return
	_loss_cards[c.get_instance_id()] = true
	if not _motion_enabled():
		_dispose_card(c)
		return
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.tween_property(c, "modulate:a", 0.0, 0.16)
	tw.tween_callback(_dispose_card.bind(c))


func _dispose_card(c) -> void:
	if c == null or not is_instance_valid(c):
		return
	_loss_cards.erase(c.get_instance_id())
	if c.get_parent() != null:
		c.get_parent().remove_child(c)
	c.queue_free()


## Событийный сдвиг панелей: целые пиксели, ≤2 px, 140 мс, без изменения layout.
func _kick_panels(px: int) -> void:
	if UiMotion.reduced or DisplayServer.get_name() == "headless":
		return
	var shift := clampi(px, -2, 2)
	if shift == 0:
		return
	for c in [workspace, receive_window, send_window, slots_strip]:
		if c == null or not is_instance_valid(c):
			continue
		var id: int = c.get_instance_id()
		if not _kick_origin.has(id):
			_kick_origin[id] = _phase_origin.get(id, c.position)
		if _kick_tweens.has(id):
			var old = _kick_tweens[id]
			if old != null and old.is_valid():
				old.kill()
		var base: Vector2 = _kick_origin[id]
		c.position = base + Vector2(float(shift), 0.0)
		var tw := create_tween()
		tw.tween_interval(0.10)
		tw.tween_property(c, "position", base, 0.04)
		tw.tween_callback(func() -> void: _kick_origin.erase(id))
		_kick_tweens[id] = tw


# --- фейды (в headless и reduce — без движения) ---------------------------

func _motion_enabled() -> bool:
	return DisplayServer.get_name() != "headless" and not UiMotion.reduced


func _fade_modal(control: Control, duration: float) -> void:
	if control == null or not is_instance_valid(control):
		return
	if not _motion_enabled():
		control.modulate.a = 1.0
		return
	control.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(control, "modulate:a", 1.0, maxf(0.01, duration))


func _restore_event_motion() -> void:
	# «Снизить эффекты» включили посреди 140-мс сдвига/фейда: вернуть layout.
	for id in _phase_tweens.keys():
		var tw = _phase_tweens[id]
		if tw != null and tw.is_valid():
			tw.kill()
		var c = instance_from_id(id)
		if c != null and is_instance_valid(c):
			if _phase_origin.has(id):
				c.position = _phase_origin[id]
			c.modulate.a = 1.0
	_phase_tweens.clear()
	for id in _kick_tweens.keys():
		var tw2 = _kick_tweens[id]
		if tw2 != null and tw2.is_valid():
			tw2.kill()
		var c2 = instance_from_id(id)
		if c2 != null and is_instance_valid(c2) and _kick_origin.has(id):
			c2.position = _kick_origin[id]
	_kick_tweens.clear()
	_kick_origin.clear()


func _fade_phase() -> void:
	if not _motion_enabled():
		_restore_event_motion()
		return
	for c in [workspace, receive_window, send_window, slots_strip, sorting_table]:
		if c == null or not is_instance_valid(c):
			continue
		var id: int = c.get_instance_id()
		if not _phase_origin.has(id):
			_phase_origin[id] = c.position
		if _phase_tweens.has(id):
			var old = _phase_tweens[id]
			if old != null and old.is_valid():
				old.kill()
		var base: Vector2 = _phase_origin[id]
		c.position = base + Vector2(0, 6)
		c.modulate.a = 0.0
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(c, "position", base, 0.16)
		tw.tween_property(c, "modulate:a", 1.0, 0.16)
		_phase_tweens[id] = tw


# --------------------------------------------------------------------------
# Итоги часа и забега
# --------------------------------------------------------------------------

func _on_hour_finished(_report: Dictionary) -> void:
	if stress_overlay != null:
		stress_overlay.notify("hour_end")
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
		"sla_max": maxi(1, int(round(float(Game.sla_cap())))),
	})
	_fade_modal(hour_result_modal, 0.16)


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
		"sla_max": maxi(1, int(round(float(Game.sla_cap())))),
		"unlocked": (r.get("unlocked", []) as Array).duplicate(),
	})
	_fade_modal(run_result_modal, 0.16)
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
		_refresh_menu_save_state()
		main_menu.visible = true
		_fade_modal(main_menu, 0.20)


## «Продолжить» активно только для незавершённого забега. Если сейв есть,
## но забег закончен — подсказка объясняет причину, а не «нет сохранения».
func _refresh_menu_save_state() -> void:
	if main_menu == null or controller == null:
		return
	var can: bool = controller.can_continue()
	var hint := ""
	if not can and controller.has_save():
		hint = "Забег завершён — начните новый"
	main_menu.set_has_save(can, hint)


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

	# правая часть меню-бара: термометр «ЖАРА», магазин, старт часа
	temperature_gauge = TemperatureGauge.new()
	temperature_gauge.name = "TemperatureGauge"
	menu_bar.add_child(temperature_gauge)
	temperature_gauge.position = Vector2(852, 1)
	temperature_gauge.size = Vector2(216, 18)
	temperature_gauge.set_heat(0.0, 36, 0)

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
	grid.drag_controller = drag_controller
	_build_search_field()

	# окно ПРИЁМ (856,48,416,264) — только в час
	receive_window = WindowFrame.new()
	receive_window.name = "ReceiveWindow"
	receive_window.title = "ПРИЁМ"
	receive_window.title_hint = _plural_ru(5, "ПАКЕТ", "ПАКЕТА", "ПАКЕТОВ")
	receive_window.icon_kind = "inbox"
	_place(self, receive_window, Rect2(856, 48, 416, 264))
	_build_receive_scroll()

	# окно ОТПРАВКА (856,320,416,276) — только в час
	send_window = WindowFrame.new()
	send_window.name = "SendWindow"
	send_window.title = "ОТПРАВКА"
	send_window.title_hint = _plural_ru(4, "ЗАПРОС", "ЗАПРОСА", "ЗАПРОСОВ")
	send_window.icon_kind = "outbox"
	_place(self, send_window, Rect2(856, 320, 416, 276))
	_build_send_scroll()

	# v2: стол сортировки на месте обоих окон — 856,48,416,548.
	sorting_table = SortingTable.new()
	sorting_table.name = "SortingTable"
	_place(self, sorting_table, Rect2(856, 48, 416, 548))
	sorting_table.drag_controller = drag_controller
	sorting_table.file_dropped.connect(_on_table_file_dropped)
	sorting_table.table_changed.connect(_on_table_changed)
	sorting_table.drop_rejected.connect(func(text: String) -> void: _toast(text, "warn"))
	sorting_table.tooltip_text = "Перетащите файлы, чтобы разложить по папкам"
	sorting_table.visible = true

	# полоса TCP-слотов (8,604,1264,52)
	slots_strip = Panel90.new()
	slots_strip.name = "SlotsStrip"
	slots_strip.kind = Panel90.Kind.RAISED
	slots_strip.tooltip_text = "Слоты передачи: приём и отправка"
	_place(self, slots_strip, Rect2(8, 604, 1264, 52))

	var head := Panel90.new()
	head.name = "SlotHead"
	head.kind = Panel90.Kind.SUNKEN
	slots_strip.add_child(head)
	head.position = Vector2(6, 5)
	head.size = Vector2(46, 42)

	var tcp_lbl := Label.new()
	tcp_lbl.text = "СЛОТЫ"
	tcp_lbl.tooltip_text = "Слоты передачи: приём и отправка"
	tcp_lbl.add_theme_font_override("font", Theme90.ui(800))
	tcp_lbl.add_theme_font_size_override("font_size", Theme90.FS_MICRO)
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
	tcp_cnt.add_theme_font_size_override("font_size", 10)
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

	# слой «ЖАРА»: поверх панелей, но под тостами и модалками.
	stress_overlay = StressOverlay.new()
	stress_overlay.name = "StressOverlay"
	add_child(stress_overlay)
	stress_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stress_overlay.kick.connect(_kick_panels)
	stress_overlay.heat_changed.connect(_on_stress_changed)

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


## Скролл ОТПРАВКИ: карточка запроса v2 выше, запросов бывает до 4.
func _build_send_scroll() -> void:
	if send_window == null or send_window.content == null:
		return
	send_window.content.clip_contents = true
	_send_bar = ScrollBar90.new()
	_send_bar.name = "SendScroll"
	send_window.content.add_child(_send_bar)
	_send_bar.position = Vector2(
		maxf(0.0, send_window.content.size.x - Theme90.SCROLLBAR), 0.0)
	_send_bar.size = Vector2(Theme90.SCROLLBAR, send_window.content.size.y)
	_send_bar.visible = false
	_send_bar.value_changed.connect(_on_send_scroll)
	send_window.content.gui_input.connect(_on_send_gui_input)


func _sync_send_scroll(count: int = -1) -> void:
	if _send_bar == null or send_window == null or send_window.content == null:
		return
	var n := requests.size() if count < 0 else count
	var view_h := maxf(1.0, send_window.content.size.y)
	var content_h := float(maxi(0, n)) * REQ_CARD_H
	_send_bar.position = Vector2(
		maxf(0.0, send_window.content.size.x - Theme90.SCROLLBAR), 0.0)
	_send_bar.size = Vector2(Theme90.SCROLLBAR, view_h)
	_send_bar.visible = content_h > view_h
	_send_scroll = clampf(_send_scroll, 0.0, maxf(0.0, content_h - view_h))
	_send_bar.set_metrics(view_h, maxf(view_h, content_h), _send_scroll)
	_layout_request_cards(n)


func _on_send_scroll(value: float) -> void:
	_send_scroll = maxf(0.0, value)
	_layout_request_cards(requests.size())


func _nudge_send_scroll(delta: float) -> void:
	if _send_bar == null:
		return
	var next := clampf(_send_scroll + delta, 0.0, _send_bar._limit())
	_send_scroll = next
	_send_bar.value = next
	_layout_request_cards(requests.size())


func _on_send_gui_input(event: InputEvent) -> void:
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
	_nudge_send_scroll(step)
	if send_window != null and send_window.content != null:
		send_window.content.accept_event()


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
		card.size = Vector2(400, 52)
		card.setup(str(d["id"]), str(d["name"]), str(d["ext"]), str(d["type"]),
			str(d["protocol"]), float(d["left"]), float(d["total"]), float(d["progress"]),
			int(d["size_kb"]))
		card.connect_pressed.connect(_on_packet_connect)
		packets.append(card)
		y += RECV_CARD_H

	var rq := _mock_requests()
	y = 0.0
	for d in rq:
		var card := RequestCard.new()
		card.name = "Request_%s" % str(d["id"])
		send_window.content.add_child(card)
		card.custom_minimum_size = Vector2.ZERO
		card.position = Vector2(6, y)
		card.size = Vector2(400, REQ_CARD_H)
		card.setup(str(d["id"]), str(d["client"]), str(d["client_id"]), str(d["protocol"]),
			d["slots"], float(d["left"]), float(d["total"]), float(d["progress"]),
			int(d.get("required", 0)), bool(d.get("queued", false)),
			bool(d.get("sending", false)), int(d.get("send_sum", 0)),
			str(d.get("minigame_id", "")), int(d.get("minigame_tier", 0)),
			bool(d.get("minigame_active", false)), bool(d.get("ready", false)),
			bool(d.get("connecting", false)), bool(d.get("connected", false)),
			str(d.get("connection_id", "")), float(d.get("udp_chance", 0.0)),
			float(d.get("udp_retry_left", 0.0)))
		card.connect_pressed.connect(_on_request_connect)
		card.reject_pressed.connect(_on_request_reject)
		card.file_dropped.connect(_on_file_to_request)
		card.detach_pressed.connect(_on_request_detach)
		requests.append(card)
		y += REQ_CARD_H

	var sl := _mock_slots()
	for i in sl.size():
		var d: Dictionary = sl[i]
		var cell := SlotCell.new()
		cell.name = "Slot_%d" % i
		slots_strip.add_child(cell)
		cell.position = Vector2(58 + i * 240, 5)
		cell.size = Vector2(236, 44)
		cell.setup(str(d["id"]), str(d["name"]), str(d["dir"]), float(d["progress"]),
			str(d["state"]), str(d.get("sub", "")), str(d.get("label", "")),
			str(d.get("kind", "")), str(d.get("detail", "")),
			bool(d.get("can_disconnect", false)), bool(d.get("sending", false)))
		cell.close_pressed.connect(_on_slot_close)
		cell.cell_pressed.connect(_on_slot_press)
		cell.packet_dropped.connect(_on_packet_to_slot)
		cell.disconnect_pressed.connect(_on_slot_disconnect)
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
				{"name": "отчёт_смены", "ext": "xls", "type": "text", "attached": true},
				{"name": "смета", "ext": "doc", "type": "text", "attached": true},
				null,
			],
			"left": 45.0, "total": 60.0, "progress": 0.0,
			"connection_id": "conn_1", "connected": true},
		{"id": "r2", "client": "ИП Кузнецов", "client_id": "cl-1189", "protocol": "UDP",
			"slots": [
				{"name": "логотип_2", "ext": "png", "type": "photo", "attached": true},
				null,
				null,
			],
			"left": 24.0, "total": 45.0, "progress": 0.0,
			"required": 1, "udp_chance": 0.4},
		{"id": "r3", "client": "Студия «Гром»", "client_id": "cl-9314", "protocol": "TCP",
			"slots": [
				{"name": "джингл", "ext": "wav", "type": "sound"},
				null,
				null,
			],
			"left": 8.0, "total": 40.0, "progress": 0.0},
		{"id": "r4", "client": "АО «Северный»", "client_id": "cl-7772", "protocol": "TCP",
			"slots": [
				{"name": "промо_осень", "ext": "avi", "type": "video", "attached": true},
				{"name": "кадр_4", "ext": "jpg", "type": "photo", "attached": true},
				null,
			],
			"left": 38.0, "total": 60.0, "progress": 0.62,
			"connection_id": "conn_2", "connected": true, "sending": true},
	]


func _mock_slots() -> Array:
	return [
		{"id": "conn_1", "name": "ИП Кузнецов", "detail": "10.0.4.17", "dir": "up",
			"progress": 0.42, "state": "active", "kind": "tcp_connection",
			"sending": true, "can_disconnect": true},
		{"id": "conn_2", "name": "ООО «Вектор»", "detail": "10.0.0.8", "dir": "up",
			"progress": 0.0, "state": "active", "kind": "tcp_connection",
			"can_disconnect": true},
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
	tree.file_dropped.connect(_on_tree_file_drop)
	tree.packet_dropped.connect(_on_tree_packet_drop)
	tree.context_menu_requested.connect(_on_tree_context)
	tree.new_folder_requested.connect(_on_new_folder)

	grid.file_selected.connect(_on_file_selected)
	grid.file_activated.connect(_on_file_activated)
	grid.file_context_requested.connect(_on_file_context)
	grid.file_dropped.connect(_on_grid_file_drop)
	grid.packet_dropped.connect(_on_grid_packet_drop)
	grid.service_filter_changed.connect(_on_service_filter)
	grid.drop_rejected.connect(func(text: String) -> void: _toast(text, "warn"))


func _on_folder_selected(folder_id: String) -> void:
	if controller == null:
		return
	var d: Dictionary = controller.prep_data()
	var meta := _folder_meta(d, folder_id)
	if meta.is_empty():
		return
	_show_folder(folder_id, str(meta["name"]), str(meta["section"]), d)


## Показать папку, в которую реально попал файл/пакет: переключает строку
## дерева и сетку. Нужен после drop на НЕ открытую папку (иначе объект есть
## в registry, но не виден на экране).
func _focus_folder(folder_id: String) -> void:
	if controller == null or folder_id.is_empty():
		return
	var d: Dictionary = controller.prep_data()
	var meta := _folder_meta(d, folder_id)
	if meta.is_empty():
		return
	if tree != null:
		tree.select_folder(folder_id)
	_show_folder(folder_id, str(meta["name"]), str(meta["section"]), d)
	_refresh_tree_counts(d)


func _on_file_selected(id: String) -> void:
	_selected_file = id
	var file = Game.registry.get_file(id) if Game.registry != null else null
	if file != null:
		files_window.set_title("ФАЙЛЫ · %s" % _folder_name(grid.folder_id),
			"ВЫБРАН: %s.%s" % [str(file.name), str(file.ext)])


func _on_file_activated(id: String) -> void:
	var file = Game.registry.get_file(id) if Game.registry != null else null
	if file != null:
		_toast("ПРОСМОТР: %s.%s" % [str(file.name), str(file.ext)], "info")


func _on_service_filter(on: bool) -> void:
	# Сигнал приходит и от FileGrid.set_service_filter(), и от пункта меню:
	# применяем состояние к сетке без повторной эмиссии сигнала.
	if grid != null and bool(grid.service_filter) != bool(on):
		grid.service_filter = bool(on)
		grid.queue_redraw()
	if on:
		var hidden := 0
		if grid != null:
			hidden = grid.hidden_count()
		_toast("СКРЫТО ОПАСНЫХ ОБЪЕКТОВ · %d" % hidden,
			"warn" if hidden > 0 else "info")
	else:
		_toast("ПОКАЗАНЫ ВСЕ ОБЪЕКТЫ", "info")


## Legacy: соединений больше нет. Клик по пакету ничего не запускает.
func _on_packet_connect(_id: String) -> void:
	_toast("ПЕРЕТАЩИТЕ ПАКЕТ В ПАПКУ", "info")


## TCP: установка соединения отдельной кнопкой ПОДКЛЮЧИТЬСЯ.
## Директор сам проверяет слот/кулдаун/модалку и даёт короткий тост при отказе.
func _on_request_connect(req_id: String) -> void:
	if controller == null or controller.hour_director == null:
		return
	controller.hour_director.connect_request(req_id)
	_refresh_hour()


## TCP: игрок закрыл соединение из слота — слот освобождается, файлы
## возвращаются в папки (всё делает директор).
func _on_slot_disconnect(conn_id: String) -> void:
	if controller == null or controller.hour_director == null:
		return
	controller.hour_director.disconnect_connection(conn_id)
	_refresh_hour()


## C1: пока открыта игровая модалка, ввод под ней не должен менять состояние часа.
## Возвращает true, если ввод заблокирован (и показывает подсказку).
func _modal_blocks_input() -> bool:
	if _modal_game != null and is_instance_valid(_modal_game):
		_toast("СНАЧАЛА ЗАКРОЙТЕ ТЕКУЩЕЕ ОКНО", "warn")
		return true
	return false


func _on_request_reject(id: String) -> void:
	if _modal_blocks_input():
		return
	if controller == null or controller.hour_director == null:
		return
	if controller.hour_director.reject_request(id):
		_refresh_hour()
		_purge_rejected_card(id)
	elif str(controller.hour_director.last_toast_text).is_empty():
		_toast("ЗАПРОС НЕ НАЙДЕН", "warn")


## Кнопочный reject: карточку убираем из дерева и из `requests` сразу, не полагаясь
## на rebuild/fade. Fade-путь _mark_card_loss (timeout/director) не затрагиваем.
func _purge_rejected_card(id: String) -> void:
	if send_window == null or send_window.content == null:
		return
	for child in send_window.content.get_children():
		if not (child is RequestCard):
			continue
		if str(child.get("id")) != str(id):
			continue
		_loss_cards.erase(child.get_instance_id())
		send_window.content.remove_child(child)
		child.queue_free()
	for i in range(requests.size() - 1, -1, -1):
		var c = requests[i]
		if c == null or not is_instance_valid(c):
			requests.remove_at(i)
		elif str(c.get("id")) == str(id):
			requests.remove_at(i)
	_prune_request_orphans()


func _on_request_detach(request_id: String, slot_index: int) -> void:
	if _modal_blocks_input():
		return
	if controller == null or controller.hour_director == null:
		return
	var req = controller.hour_director.active_requests.get(request_id)
	if req == null:
		return
	# slot_index приходит из RequestCard в порядке REQUIRED-слотов, а
	# req.attached хранится в порядке вложения — индексируем required.
	if slot_index < 0 or slot_index >= req.required.size():
		_toast("ФАЙЛ НЕ ПРИКРЕПЛЁН", "info")
		return
	var file_id := str(req.required[slot_index])
	if not req.attached.has(file_id):
		_toast("ФАЙЛ НЕ ПРИКРЕПЛЁН", "info")
		return
	if controller.hour_director.detach_file(request_id, file_id):
		_toast("ФАЙЛ ОТСОЕДИНЁН ОТ ЗАПРОСА", "info")
		_refresh_hour()
		# Файл после detach снова лежит в папке — гарантируем, что сетка
		# перечитала registry сразу, не дожидаясь следующего refresh_hour.
		if grid != null and is_instance_valid(grid) and grid.has_method("refresh"):
			grid.refresh()
	else:
		_toast("НЕ УДАЛОСЬ ОТСОЕДИНИТЬ", "warn")


## Прикрепление файла к запросу: только attach, без автостарта отправки.
func _on_file_to_request(request_id: String, _slot_index: int, payload: Dictionary) -> void:
	if _modal_blocks_input():
		return
	if controller == null or controller.hour_director == null:
		return
	if str(payload.get("from", "")) == "table":
		_toast("ФАЙЛ НА СТОЛЕ — СНАЧАЛА ВЕРНИТЕ ЕГО В ПАПКУ", "warn")
		return
	var file_id := str(payload.get("id", ""))
	if file_id.is_empty():
		return
	if controller.hour_director.attach_file(request_id, file_id):
		_toast("ФАЙЛ ПРИКРЕПЛЁН", "success")
		_tutorial_notify("attach")
		_refresh_hour()
	elif str(controller.hour_director.last_toast_text).is_empty():
		_toast("НЕ УДАЛОСЬ ПРИКРЕПИТЬ ФАЙЛ", "warn")


## Явная отправка по кнопке ОТПРАВИТЬ (v2).
func _on_request_send(req_id: String) -> void:
	if _modal_blocks_input():
		return
	_maybe_start_send(req_id)


func _maybe_start_send(req_id: String) -> void:
	if controller == null or controller.hour_director == null:
		return
	if controller.hour_director.start_send(req_id):
		_refresh_hour()
	elif str(controller.hour_director.last_toast_text).is_empty():
		_toast("ОТПРАВКА НЕ НАЧАЛАСЬ", "warn")


func _on_request_protocol_toggle(req_id: String) -> void:
	if _modal_blocks_input():
		return
	if controller == null or controller.hour_director == null:
		return
	var req = controller.hour_director.active_requests.get(req_id)
	if req == null:
		return
	var next := "udp" if str(req.protocol).to_lower() == "tcp" else "tcp"
	if controller.hour_director.set_request_protocol(req_id, next):
		_refresh_hour()
	elif str(controller.hour_director.last_toast_text).is_empty():
		_toast("ПРОТОКОЛ НЕ ИЗМЕНЁН", "warn")


## v2: прервать передачу нельзя, слот освободится сам. Заглушка для совместимости.
func _on_slot_close(_id: String) -> void:
	pass


func _on_slot_press(id: String) -> void:
	for c in slot_cells:
		if c.id == id and c.state == "locked":
			_toast("СЛОТ ДОСТУПЕН В МАГАЗИНЕ", "info")


## Legacy: перетаскивание пакета на слот больше не запускает соединение.
func _on_packet_to_slot(_cell_id: String, _payload: Dictionary) -> void:
	_toast("ПЕРЕТАЩИТЕ ПАКЕТ В ПАПКУ", "info")


# --------------------------------------------------------------------------
# Drop-обработчики v2
# --------------------------------------------------------------------------

## Точный drop в сетку папки: origin/rotation уходят в HourDirector.
func _on_grid_packet_drop(payload: Dictionary, origin: Vector2i, rotation: int) -> void:
	if _modal_blocks_input():
		return
	if controller == null or controller.hour_director == null:
		return
	var packet_id := str(payload.get("id", ""))
	if packet_id.is_empty():
		return
	var folder_id := str(grid.folder_id)
	if controller.hour_director.receive_packet(packet_id, folder_id, origin, rotation):
		_toast("ПАКЕТ ПРИНЯТ", "success")
		_tutorial_notify("packet")
	else:
		_toast("ПАКЕТ НЕ ПРИНЯТ · ПАКЕТ ОСТАЛСЯ В БУФЕРЕ", "warn")
	_refresh_hour()


## Drop пакета на строку папки — auto-place первой подходящей фигурой.
func _on_tree_packet_drop(folder_id: String, payload: Dictionary) -> void:
	if _modal_blocks_input():
		return
	if controller == null or controller.hour_director == null:
		return
	var packet_id := str(payload.get("id", ""))
	if packet_id.is_empty():
		return
	if controller.hour_director.receive_packet(packet_id, folder_id):
		_toast("ПАКЕТ ПРИНЯТ В «%s»" % _folder_name(folder_id), "success")
		_tutorial_notify("packet")
		# Drop мог прийти на строку НЕ открытой папки: переключаем сетку на
		# цель, иначе файл после загрузки «исчезает» из вида (он в registry,
		# но нарисован в другой папке).
		_focus_folder(folder_id)
	else:
		_toast("ПАКЕТ НЕ ПРИНЯТ · НЕТ МЕСТА ИЛИ СЛОТА", "warn")
	_refresh_hour()


## Файл уже разложен самой сеткой — остаётся сохранить и обновить счётчики.
func _on_grid_file_drop(payload: Dictionary) -> void:
	if controller == null:
		return
	controller.save()
	if controller.phase == GAME_CONTROLLER.PHASE_PREP:
		var d: Dictionary = controller.prep_data()
		if not str(grid.folder_id).is_empty():
			_refresh_tree_counts(d)
			_refresh_current_folder(d, str(grid.folder_id))
	else:
		_refresh_hour()
	_toast("ПЕРЕМЕЩЕНО: %s" % str(payload.get("name", "файл")), "success")


## Drop на строку папки: auto-place (или со стола — move_from_table).
func _on_tree_file_drop(folder_id: String, payload: Dictionary) -> void:
	if controller == null or Game.registry == null:
		return
	var file_id := str(payload.get("id", ""))
	if file_id.is_empty():
		return
	var from := str(payload.get("from", "folder"))
	var file = Game.registry.files.get(file_id)
	if file != null and from != "table" and str(file.folder_id) == folder_id \
			and str(file.location) == "folder":
		_toast("ФАЙЛ УЖЕ В ЭТОЙ ПАПКЕ", "info")
		return
	var ok := false
	if from == "table" and Game.registry.has_method("move_from_table"):
		ok = bool(Game.registry.move_from_table(file_id, folder_id))
	else:
		ok = bool(Game.registry.move_file(file_id, folder_id))
	if ok:
		controller.save()
		# Та же причина, что и у пакетов: drop на строку неоткрытой папки
		# раньше оставлял файл вне текущей сетки.
		_focus_folder(folder_id)
		if controller.phase == GAME_CONTROLLER.PHASE_PREP:
			var d: Dictionary = controller.prep_data()
			_refresh_tree_counts(d)
			if not str(grid.folder_id).is_empty():
				_refresh_current_folder(d, str(grid.folder_id))
			if sorting_table != null:
				sorting_table.refresh()
		else:
			_refresh_hour()
		_toast("ПЕРЕМЕЩЕНО: %s → «%s»" % [str(payload.get("name", "файл")),
			_folder_name(folder_id)], "success")
	else:
		_toast("НЕ УДАЛОСЬ ПЕРЕМЕСТИТЬ ФАЙЛ: НЕТ МЕСТА", "warn")


## Файл уже перенесён SortingTable — обновляем счётчики и сохранение.
func _on_table_file_dropped(payload: Dictionary) -> void:
	if controller == null:
		return
	controller.save()
	if controller.phase == GAME_CONTROLLER.PHASE_PREP:
		var d: Dictionary = controller.prep_data()
		_refresh_tree_counts(d)
		if not str(grid.folder_id).is_empty():
			_refresh_current_folder(d, str(grid.folder_id))
		if sorting_table != null:
			sorting_table.refresh()
	_toast("НА СТОЛЕ: %s" % str(payload.get("name", "файл")), "info")


func _on_table_changed() -> void:
	if controller != null and controller.phase == GAME_CONTROLLER.PHASE_PREP:
		_refresh_tree_counts(controller.prep_data())


## Legacy-алиас: старые тесты/вызовы бросали сущность «в папку» без сигнала.
func _on_drop_to_folder(folder_id: String, payload: Dictionary) -> void:
	if str(payload.get("kind", "file")) == "packet":
		_on_tree_packet_drop(folder_id, payload)
	else:
		_on_tree_file_drop(folder_id, payload)


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
## Если папка состоит только из зарезервированных/неудаляемых файлов —
## ничего не удаляем и SLA НЕ списываем.
func _destroy_folder_contents(folder_id: String) -> void:
	if Game.registry == null or not Game.registry.folders.has(folder_id):
		_toast("ПАПКА НЕ НАЙДЕНА", "warn")
		return
	var file_ids := _folder_file_ids(folder_id)
	if file_ids.is_empty():
		_toast("ПАПКА ПУСТА", "warn")
		return
	var registry = Game.registry
	var removed := 0
	for file_id in file_ids:
		var file = registry.files.get(file_id)
		if file == null:
			continue
		# Файл зарезервирован активным запросом — уничтожать нельзя: запрос
		# останется без содержимого, а штраф всё равно спишется. Пропускаем.
		if not str(file.required_by).is_empty():
			continue
		var removed_one := false
		# remove_file штатно удаляет только malicious/failed; для осознанного
		# уничтожения помечаем файл и сразу удаляем.
		if registry.remove_file(file_id):
			removed_one = true
		elif registry.mark_malicious(file_id, "destroy"):
			removed_one = registry.remove_file(file_id)
		if removed_one:
			removed += 1
			if _selected_file == file_id:
				_selected_file = ""
	if removed <= 0:
		# Ничего не удалилось (все файлы под резервацией) — штрафа нет.
		if controller != null and controller.phase == GAME_CONTROLLER.PHASE_PREP:
			_refresh_prep()
		else:
			_refresh_hour()
		_toast("НЕЧЕГО УНИЧТОЖИТЬ", "warn")
		return
	Game.add_sla(-5.0, "destroy")
	if controller != null:
		controller.save()
	if controller != null and controller.phase == GAME_CONTROLLER.PHASE_PREP:
		_refresh_prep()
	else:
		_refresh_hour()
	_toast("СОДЕРЖИМОЕ УНИЧТОЖЕНО · SLA −5", "error")


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
	_refresh_folder_price()
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
## D2 (M16): обычный НЕприкреплённый файл можно уничтожить в подготовке после
## подтверждения и без штрафа SLA — это гарантированный выход из soft-lock,
## когда папка полна, а денег/запаса SLA на разбор нет.
func _destroy_selected_file(file_id: String) -> void:
	if Game.registry == null or not Game.registry.files.has(file_id):
		_toast("ФАЙЛ НЕ НАЙДЕН", "warn")
		return
	var file = Game.registry.files[file_id]
	var loc := str(file.location)
	if loc == "malicious" or loc == "locked":
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
		return

	if controller == null or controller.phase != GAME_CONTROLLER.PHASE_PREP:
		_toast(_tr_or("msg.delete_prep_only",
			"Обычные файлы удаляются только в подготовке"), "warn")
		return
	if loc == "attached" or not str(file.attached_request).is_empty():
		_toast("НЕЛЬЗЯ УДАЛИТЬ ПРИКРЕПЛЁННЫЙ ФАЙЛ", "warn")
		return
	if confirm_modal == null:
		return
	_confirm_action = "file:" + file_id
	var name := str(file.display_name()) if file.has_method("display_name") else str(file.name)
	confirm_modal.ask(_tr_or("msg.delete_file_confirm", "Удалить файл?"),
		_tr_or("msg.delete_file_detail",
			"Файл «%s» будет уничтожен без штрафа SLA.").replace("{name}", name),
		"Удалить", "Отмена", true)


## Подтверждённое уничтожение обычного файла: без SLA/денежных списаний.
func _destroy_normal_file(file_id: String) -> void:
	if Game.registry == null or not Game.registry.files.has(file_id):
		return
	var file = Game.registry.files[file_id]
	if str(file.location) == "attached" or not str(file.attached_request).is_empty():
		_toast("НЕЛЬЗЯ УДАЛИТЬ ПРИКРЕПЛЁННЫЙ ФАЙЛ", "warn")
		return
	if not Game.registry.destroy_file(file_id):
		_toast("НЕ УДАЛОСЬ УДАЛИТЬ ФАЙЛ", "warn")
		return
	if _selected_file == file_id:
		_selected_file = ""
	if controller != null:
		controller.save()
	if controller != null and controller.phase == GAME_CONTROLLER.PHASE_PREP:
		_refresh_prep()
	else:
		_refresh_hour()
	_toast("ФАЙЛ УНИЧТОЖЕН", "success")


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
	var cost := _folder_price_now()
	if cost > 0 and int(Game.money) < cost:
		_toast(_tr_or("msg.folder_need_money", "НУЖНО {cost} $")
			.replace("{cost}", str(cost)), "warn")
		return
	# Имя генерируется из пула Data и делается уникальным внутри секции.
	var folder_name := _unique_folder_name(section_id, Data.folder_name())
	if cost > 0:
		Game.add_money(-cost, "folder")
	var folder = Game.registry.create_folder(section_id, folder_name)
	if folder == null:
		if cost > 0:
			Game.add_money(cost, "folder_refund")
			# Возврат не должен засчитываться в заработок часа/забега.
			if Game.stats != null:
				Game.stats["money_earned"] = maxi(0,
					int(Game.stats.get("money_earned", 0)) - cost)
		_refresh_folder_price()
		_toast("НЕ УДАЛОСЬ СОЗДАТЬ ПАПКУ", "error")
		return
	if controller != null:
		controller.save()
	if controller != null and controller.phase == GAME_CONTROLLER.PHASE_PREP:
		_refresh_prep()
	else:
		_refresh_hour()
	_on_folder_selected(str(folder.id))
	_refresh_folder_price()
	_kick_panels(1)
	var price_text := " · −%d $" % cost if cost > 0 else ""
	_toast("СОЗДАНА ПАПКА «%s»%s" % [str(folder.name), price_text], "success")


## Цена следующей папки: backend Game.folder_price(), иначе старый fallback.
func _folder_price_now() -> int:
	if Game != null and Game.has_method("folder_price"):
		return maxi(0, int(Game.folder_price()))
	return maxi(0, int(Data.const_value("folder_new_cost", 180)))


func _refresh_folder_price() -> void:
	if tree != null:
		tree.set_new_folder_price(_folder_price_now())


func _bind_game_juice_signals() -> void:
	if Game == null:
		return
	if not Game.money_changed.is_connected(_on_money_changed_ui):
		Game.money_changed.connect(_on_money_changed_ui)
	if not Game.sla_changed.is_connected(_on_sla_changed_ui):
		Game.sla_changed.connect(_on_sla_changed_ui)
	_last_money_seen = int(Game.money)
	_last_sla_seen = float(Game.sla)
	_refresh_folder_price()


func _on_money_changed_ui(value: int) -> void:
	var now := int(value)
	if _last_money_seen >= 0 and now != _last_money_seen:
		var delta := now - _last_money_seen
		var in_game: bool = controller != null \
			and (controller.phase == GAME_CONTROLLER.PHASE_PREP \
				or controller.phase == GAME_CONTROLLER.PHASE_HOUR)
		if in_game and _motion_enabled() and status_bar != null:
			status_bar.flash("money", "%+d" % delta,
				Theme90.SUCCESS if delta > 0 else Theme90.ERROR)
	_last_money_seen = now
	_refresh_folder_price()


func _on_sla_changed_ui(value: float) -> void:
	var now := float(value)
	if _last_sla_seen >= 0.0:
		var delta := now - _last_sla_seen
		var in_hour: bool = controller != null \
			and controller.phase == GAME_CONTROLLER.PHASE_HOUR
		if absf(delta) >= 0.5 and in_hour and _motion_enabled() and status_bar != null:
			status_bar.flash("sla", "%+d" % int(roundf(delta)),
				Theme90.SUCCESS if delta > 0.0 else Theme90.ERROR)
	_last_sla_seen = now


func _pulse_control(c: Control) -> void:
	if c == null or not is_instance_valid(c) or not _motion_enabled():
		return
	var id := c.get_instance_id()
	if _pulse_tweens.has(id):
		var old = _pulse_tweens[id]
		if old != null and old.is_valid():
			old.kill()
	c.modulate = Color(1.14, 1.14, 1.14, 1.0)
	var tw := create_tween()
	tw.tween_property(c, "modulate", Color(1, 1, 1, 1), UiMotion.DUR_UI)
	_pulse_tweens[id] = tw


func _on_slot_changed_ui() -> void:
	_pulse_control(slot_count_label)


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
	if shop_modal == null or controller == null:
		return
	# Магазин доступен только в подготовке, после первого часа.
	if controller.phase != GAME_CONTROLLER.PHASE_PREP:
		_toast("МАГАЗИН ДОСТУПЕН В ПОДГОТОВКЕ", "warn")
		return
	if int(Game.hour) <= 1:
		_toast("МАГАЗИН ОТКРОЕТСЯ ПОСЛЕ ПЕРВОГО ЧАСА", "warn")
		return
	if mascot != null:
		mascot.hide_message()
	shop_modal.open_prep(controller.shop, int(Game.money), int(Game.hour))
	_fade_modal(shop_modal, 0.16)


func _on_shop_buy(id: String) -> void:
	if controller == null:
		return
	if controller.buy(id):
		_toast("КУПЛЕНО: %s" % _shop_item_name(id), "success")
	else:
		_toast("ПОКУПКА НЕ УДАЛАСЬ", "warn")
	shop_modal.refresh()
	if controller.phase == GAME_CONTROLLER.PHASE_PREP:
		_refresh_prep()
	_update_shop_visibility()


func _on_shop_reroll() -> void:
	if controller == null or controller.shop == null:
		return
	if not controller.shop.reroll():
		_toast("ОБНОВЛЕНИЕ НЕДОСТУПНО", "warn")
	shop_modal.refresh()
	if controller.phase == GAME_CONTROLLER.PHASE_PREP:
		_refresh_prep()


func _on_shop_lock(index: int) -> void:
	if controller == null or controller.shop == null:
		return
	controller.shop.toggle_lock(index)
	shop_modal.refresh()


## Shop изменился (покупка/реролл): обновить модалку и снимки экрана.
func _on_shop_changed() -> void:
	if shop_modal != null and shop_modal.visible:
		shop_modal.refresh()
	_update_shop_visibility()
	if controller != null and controller.phase == GAME_CONTROLLER.PHASE_PREP:
		_update_status(controller.prep_data())


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


## D2: строка из Data.tr с fallback, если ключ ещё не добавлен в strings_ru.
func _tr_or(key: String, fallback: String) -> String:
	if Data != null and Data.has_method("has_string") and Data.has_string(key):
		return Data.tr(key)
	return fallback


# --------------------------------------------------------------------------
# Фон
# --------------------------------------------------------------------------

class TutorialHighlight:
	extends Control
	## Тонкая пульсирующая рамка вокруг цели шага. Мышь не перехватывает.

	var rects: Array = []
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		focus_mode = Control.FOCUS_NONE
		set_process(false)

	func set_targets(value: Array) -> void:
		rects = value
		visible = not rects.is_empty()
		set_process(visible)
		queue_redraw()

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var pulse := 0.5 + 0.5 * sin(_t * 4.2)
		var col := Color(Theme90.ACCENT.r, Theme90.ACCENT.g, Theme90.ACCENT.b,
			0.55 + 0.35 * pulse)
		for r in rects:
			if not (r is Rect2):
				continue
			var rect := r as Rect2
			if rect.size.x <= 0.0 or rect.size.y <= 0.0:
				continue
			draw_rect(rect.grow(2.0), col, false, 2.0)


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
