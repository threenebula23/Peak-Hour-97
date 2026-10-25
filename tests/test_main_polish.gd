extends SceneTree
## Headless-тест полировки экрана Main:
##   • скролл ПРИЁМА (4 пакета — скрыт, 8 — виден, последний доступен);
##   • поиск по файлам после покупки shop_search (search_unlocked);
##   • удаление папки (только пустой).
##
## Запуск:
##   godot --headless --path . --script tests/test_main_polish.gd

const MAIN_SCENE := "res://scenes/Main.tscn"

var _checks := 0
var _fails := 0
var _main: Node = null
var _game: Node = null
var _controller = null


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
	_ok(_game != null, "autoload Game доступен")
	_ok(_main.controller != null, "controller создан")
	if _game == null or _main.controller == null:
		_finish()
		return
	_controller = _main.controller

	_main._start_new_run()
	await process_frame
	_test_shop_and_meta()
	_main._on_start_hour()
	await process_frame
	_eq(_controller.phase, &"hour", "фаза контроллера — hour")

	# Замораживаем тик, чтобы автодокид пакетов не мешал подсчётам.
	_controller.set_paused(true)

	_test_receive_scroll()
	await _test_search()
	_test_delete_folder()
	_test_calm_backdrop()
	await _test_destroy_contents()
	_test_run_result_escape()

	await process_frame
	print("")
	print("Проверок: %d, провалов: %d" % [_checks, _fails])
	_finish()


## Магазин v2: закрыт до часа 2; 3 лота, без старых shop_search/shield.
func _test_shop_and_meta() -> void:
	_eq(int(_game.hour), 1, "подготовка первого часа")
	_ok(not _game.feature_unlocked("shop"), "магазин закрыт на часе 1")
	_main._on_shop()
	_ok(not _main.shop_modal.visible, "клик по МАГАЗИНУ на часе 1 не открывает окно")
	_ok(not _shop_has("shop_search"), "старого shop_search больше нет")
	_ok(not _shop_has("shop_shield"), "старого shop_shield больше нет")
	_ok(_shop_has("lot_sla"), "v2-лот lot_sla доступен")

	# Час 2: контроллер генерирует 3 предложения.
	_game.hour = 2
	_controller.shop.refresh(2, int(_game.money), true)
	_controller.shop_changed.emit()
	_main._update_shop_visibility()
	_ok(_main._shop_btn.visible, "на часе 2 кнопка МАГАЗИН видна")
	_ok(_game.feature_unlocked("shop"), "магазин открыт прогрессией часа 2")
	_eq(_controller.shop_data().size(), 3, "на часе 2 — 3 предложения")
	_main._on_shop()
	_ok(_main.shop_modal.visible, "магазин открывается в подготовке часа 2")
	_eq(_main.shop_modal.card_ids().size(), 3, "в магазине 3 карточки")
	_main.shop_modal.close()
	_ok(not _main.shop_modal.visible, "магазин закрывается по Закрыть/Esc")

	# Возвращаем H1, чтобы основной сценарий часа остался прежним.
	_game.hour = 1
	_game.shop_offers.clear()
	_game.shop_offer_hour = 0
	_game.shop_locked.clear()
	_main._update_shop_visibility()
	_ok(not _main._shop_btn.visible, "на часе 1 магазин снова скрыт")


func _shop_has(id: String) -> bool:
	if _controller == null or _controller.shop == null:
		return false
	for item in _controller.shop.available_items():
		if str(item.get("id", "")) == id:
			return true
	return false


func _test_receive_scroll() -> void:
	var bar = _main._recv_bar
	_ok(bar != null, "скроллбар ПРИЁМА создан")
	if bar == null:
		return

	var director = _controller.hour_director
	_ok(director != null, "hour_director доступен")
	if director == null:
		return

	# 4 пакета (базовый буфер 6) — всё влезает, скроллбар скрыт.
	for i in 4:
		director.spawn_packet_now("text", "tcp")
	_main._refresh_hour()
	await process_frame
	_eq(_main.packets.size(), 4, "4 карточки пакетов")
	_ok(not bar.visible, "при 4 пакетах скроллбар скрыт")

	# Канал+буфер до 8 (лот lot_channel) — карточки выходят за окно.
	_game.set_lot_level("lot_channel", 2)
	for i in 4:
		director.spawn_packet_now("text", "tcp")
	_main._refresh_hour()
	await process_frame
	_eq(_main.packets.size(), 8, "8 карточек пакетов")
	_ok(bar.visible, "при 8 пакетах скроллбар виден")
	_ok(bar._limit() > 0.0, "у скроллбара есть запас прокрутки (%.1f)" % bar._limit())
	if _main.packets.size() < 8:
		return

	var view_h := float(_main.receive_window.content.size.y)
	_ok(_main.packets[7].position.y + _main.packets[7].size.y <= view_h + 0.5,
		"до прокрутки последний пакет в окне")

	# Прокрутка вниз: первая карточка уходит вверх, последняя остается видимой.
	bar.value = 200.0
	await process_frame
	_ok(_main.packets[0].position.y < 0.0,
		"после прокрутки первая карточка ушла вверх (y=%.1f)" % _main.packets[0].position.y)
	_ok(_main.packets[7].position.y >= 0.0
		and _main.packets[7].position.y + _main.packets[7].size.y <= view_h + 0.5,
		"последний пакет доступен после прокрутки (y=%.1f)" % _main.packets[7].position.y)

	# Колесо мыши над content: шаг 24 px вверх.
	var before_wheel: float = _main._recv_scroll
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	_main._on_recv_gui_input(wheel)
	_ok(_main._recv_scroll < before_wheel,
		"колесо вверх прокручивает список (%.1f → %.1f)" % [before_wheel, _main._recv_scroll])


func _test_search() -> void:
	_game.upgrades["search_unlocked"] = 1
	_main._refresh_prep()
	await process_frame
	var edit: LineEdit = _main._search_edit
	_ok(edit != null, "поле поиска создано")
	if edit == null:
		return
	_ok(edit.visible, "при search_unlocked поле поиска видно")

	var folder_id := str(_main.grid.folder_id)
	_ok(not folder_id.is_empty(), "выбрана папка для файлов")
	_game.registry.create_file("отчёт_демо", "text", folder_id)
	_game.registry.create_file("прайс_демо", "text", folder_id)
	_main._refresh_prep()
	_main.grid.refresh()
	await process_frame

	var total_before: int = _main.grid.file_count()
	_ok(total_before >= 2, "в папке есть файлы (%d)" % total_before)

	edit.text = "отчёт"
	_main._on_search_changed(edit.text)
	_eq(_main._filtered_files().size(), 1, "по подстроке найден один файл")
	_ok(_main.files_window.title_hint.contains("найдено 1"),
		"заголовок показывает результат фильтра: %s" % _main.files_window.title_hint)

	edit.text = ""
	_main._on_search_changed(edit.text)
	_eq(_main._filtered_files().size(), total_before, "пустой запрос возвращает все файлы")

	# Без апгрейда поле скрыто.
	_game.upgrades["search_unlocked"] = 0
	_main._refresh_prep()
	_ok(not edit.visible, "без апгрейда поле поиска скрыто")
	_game.upgrades["search_unlocked"] = 1
	await _test_service_filter()


func _test_service_filter() -> void:
	_main.grid.refresh()
	await process_frame
	var folder_id := str(_main.grid.folder_id)
	var hidden_before: int = _main.grid.hidden_count()
	_ok(_main.grid.file_count() > 0, "в сетке есть файлы для фильтра")
	var fid := ""
	for file in _game.registry.get_folder_files(folder_id):
		if str(file.location) != "failed" and str(file.location) != "malicious":
			fid = str(file.id)
			break
	_ok(not fid.is_empty(), "найден файл для пометки опасным")
	if fid.is_empty():
		return
	_ok(_game.registry.mark_failed(fid), "файл помечен failed")
	_main.grid.refresh()
	await process_frame
	var hidden: int = _main.grid.hidden_count()
	_ok(hidden >= hidden_before + 1, "hidden_count считает опасные файлы (%d)" % hidden)
	_main._on_service_filter(true)
	_ok(bool(_main.grid.service_filter), "фильтр опасных включён")
	var items: Array = _main.toast_layer._items
	_ok(not items.is_empty(), "тост фильтра показан")
	if not items.is_empty():
		var text := str(items.back().txt)
		_ok(text.contains(str(hidden)), "тост показывает реальное число (%s)" % text)
		_ok(not text.contains("СЛУЖЕБНЫЕ"), "тост не про «служебные» (%s)" % text)
	_main._on_service_filter(false)
	_ok(not bool(_main.grid.service_filter), "фильтр опасных выключен")
	_game.registry.remove_file(fid)
	_main.grid.refresh()


func _test_delete_folder() -> void:
	# Пустая папка удаляется.
	var empty_folder = _game.registry.create_folder("C", "Удаляемая")
	_ok(empty_folder != null, "пустая папка создана")
	if empty_folder == null:
		return
	var empty_id := str(empty_folder.id)
	_main._on_tree_menu("delete", empty_id)
	_ok(not _game.registry.folders.has(empty_id), "пустая папка удалена")

	# Папка с файлом — не удаляется.
	var busy_folder = _game.registry.create_folder("C", "С_файлом")
	_ok(busy_folder != null, "папка с файлом создана")
	if busy_folder == null:
		return
	var busy_id := str(busy_folder.id)
	_ok(_game.registry.create_file("файл_в_папке", "text", busy_id) != null,
		"файл в папку добавлен")
	_main._on_tree_menu("delete", busy_id)
	_ok(_game.registry.folders.has(busy_id), "папка с файлом осталась")


func _test_calm_backdrop() -> void:
	_ok(_main._backdrop != null, "Backdrop создан")
	if _main._backdrop == null:
		return
	_main._apply_settings({"sfx": 50, "music": 50, "calm_bg": true,
		"fullscreen": false}, false)
	_ok(_main._backdrop.visible, "спокойный фон не скрывает Backdrop")
	_ok(bool(_main._backdrop.calm), "Backdrop переключён в спокойный режим")
	var clear = ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color")
	_ok(clear is Color and (clear as Color).is_equal_approx(Theme90.PAPER),
		"clear color проекта — бумага, а не серый")
	_main._apply_settings({"sfx": 50, "music": 50, "calm_bg": false,
		"fullscreen": false}, false)
	_ok(_main._backdrop.visible and not bool(_main._backdrop.calm),
		"обычный фон возвращает dither без скрытия Backdrop")


func _test_destroy_contents() -> void:
	var folder = _game.registry.create_folder("C", "Под_снос")
	_ok(folder != null, "папка для уничтожения создана")
	if folder == null:
		return
	var folder_id := str(folder.id)
	_ok(_game.registry.create_file("снос_1", "text", folder_id) != null, "файл 1 создан")
	_ok(_game.registry.create_file("снос_2", "text", folder_id) != null, "файл 2 создан")

	# Пустая папка: подтверждение не открывается, штрафа нет.
	var empty = _game.registry.create_folder("C", "Пустая_снос")
	_ok(empty != null, "пустая папка создана")
	if empty != null:
		var sla_before_empty := float(_game.sla)
		_main._on_tree_menu("destroy", str(empty.id))
		_ok(not _main.confirm_modal.visible, "пустая папка не просит подтверждения")
		_ok(is_equal_approx(float(_game.sla), sla_before_empty),
			"пустая папка не штрафует SLA")

	# Папка с файлами: подтверждение и реальное удаление.
	var sla_before := float(_game.sla)
	_main._on_tree_menu("destroy", folder_id)
	_ok(_main.confirm_modal.visible, "уничтожение просит подтверждения")
	_eq(str(_main._confirm_action), "destroy:" + folder_id, "действие подтверждения — destroy")
	_main.confirm_modal._answer(true)
	await process_frame
	_eq(_game.registry.get_folder_files(folder_id).size(), 0,
		"содержимое папки удалено")
	_ok(_game.registry.folders.has(folder_id), "сама папка осталась")
	_ok(is_equal_approx(float(_game.sla), sla_before - 5.0),
		"SLA снижен на 5 (%.1f → %.1f)" % [sla_before, float(_game.sla)])


func _test_run_result_escape() -> void:
	var modal = _main.run_result_modal
	_ok(modal != null, "RunResultModal создана")
	if modal == null:
		return

	# Пустой unlocked: подсказка про Esc.
	modal.open({"won": true, "unlocked": []})
	_eq(modal._unlocked_line(), "", "пустой unlocked не даёт строки открытий")
	_eq(modal._footer_text(), "ESC — В МЕНЮ", "пустой unlocked — подсказка Esc")
	_ok(modal.visible, "модалка итогов открыта")

	# Открытия мапятся через Data: reward -> unlock.label.
	modal.open({"won": true, "unlocked": ["survive_hour_3", "survive_hour_5"]})
	_ok(modal._unlocked_line().contains("Поиск"), "survive_hour_3 → Поиск")
	_ok(modal._unlocked_line().contains("Щит"), "survive_hour_5 → Щит")
	_ok(modal._footer_text().begins_with("ОТКРЫТО:"), "строка открытий в подвале")

	# closed эмитится ровно один раз.
	var closes := [0]
	var on_closed := func() -> void: closes[0] += 1
	modal.closed.connect(on_closed)
	modal.close()
	_eq(closes[0], 1, "closed эмитится один раз")
	modal.closed.disconnect(on_closed)

	# Esc при открытых итогах — в меню, а modal скрыта.
	var went_menu := [false]
	var on_menu := func() -> void: went_menu[0] = true
	modal.to_menu.connect(on_menu)
	modal.open({"won": true, "unlocked": []})
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	modal._unhandled_input(ev)
	_ok(went_menu[0], "Esc на итогах эмитит to_menu")
	_ok(not modal.visible, "Esc на итогах скрывает модалку")
	_ok(_main.main_menu.visible, "Esc на итогах показывает главное меню")
	modal.to_menu.disconnect(on_menu)


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


func _fail(message: String) -> void:
	_checks += 1
	_fails += 1
	print("FAIL: %s" % message)
