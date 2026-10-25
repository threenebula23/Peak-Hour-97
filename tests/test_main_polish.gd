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
	_test_search()
	_test_delete_folder()

	await process_frame
	print("")
	print("Проверок: %d, провалов: %d" % [_checks, _fails])
	_finish()


## Магазин: закрыт до часа 2; позиции search/shield — только по мета-наградам.
func _test_shop_and_meta() -> void:
	_eq(int(_game.hour), 1, "подготовка первого часа")
	_ok(not _game.feature_unlocked("shop"), "магазин закрыт на часе 1")
	_main._on_shop()
	_ok(not _main.shop_modal.visible, "клик по МАГАЗИНУ на часе 1 не открывает окно")

	# Мета-награда ещё не получена — поиск закрыт и отсутствует в каталоге.
	_ok(not _game.feature_unlocked("search"), "поиск закрыт до meta survive_hour_3")
	_ok(not _shop_has("shop_search"), "shop_search отсутствует в доступном каталоге")
	_ok(not _shop_has("shop_shield"), "shop_shield отсутствует в доступном каталоге")
	_ok(_shop_has("shop_sla"), "shop_sla доступен всегда")

	# Открываем час 2 → магазин доступен, мета-награда открывает поиск.
	_game.hour = 2
	_main._update_shop_visibility()
	_ok(_main._shop_btn.visible, "на часе 2 кнопка МАГАЗИН видна")
	_main._on_shop()
	_ok(_main.shop_modal.visible, "магазин открывается в подготовке часа 2")
	_main.shop_modal.close()
	_ok(not _main.shop_modal.visible, "магазин закрывается по X")
	_ok(_game.feature_unlocked("shop"), "магазин открыт прогрессией часа 2")

	_game.meta_unlocks["survive_hour_3"] = true
	_ok(_game.feature_unlocked("search"), "meta survive_hour_3 открывает поиск")
	_ok(_shop_has("shop_search"), "shop_search появился в каталоге после meta")
	_game.hour = 1
	_main._update_shop_visibility()


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

	# 4 пакета (базовый буфер) — всё влезает, скроллбар скрыт.
	for i in 4:
		director.spawn_packet_now("text", "tcp")
	_main._refresh_hour()
	await process_frame
	_eq(_main.packets.size(), 4, "4 карточки пакетов")
	_ok(not bar.visible, "при 4 пакетах скроллбар скрыт")

	# Апгрейд буфера до 8 — карточки выходят за окно.
	_game.upgrades["buffer_level"] = 2
	for i in 4:
		director.spawn_packet_now("text", "tcp")
	_main._refresh_hour()
	await process_frame
	_eq(_main.packets.size(), 8, "8 карточек пакетов")
	_ok(bar.visible, "при 8 пакетах скроллбар виден")
	_ok(bar._limit() > 0.0, "у скроллбара есть запас прокрутки (%.1f)" % bar._limit())

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
	await process_frame

	var total_before: int = _main.grid.get_cards().size()
	_ok(total_before >= 2, "в папке есть файлы (%d)" % total_before)

	edit.text = "отчёт"
	_main._on_search_changed(edit.text)
	_ok(_main.grid.get_cards().size() < total_before,
		"фильтр уменьшает список (%d → %d)" % [total_before, _main.grid.get_cards().size()])
	_eq(_main.grid.get_cards().size(), 1, "по подстроке найден один файл")

	edit.text = ""
	_main._on_search_changed(edit.text)
	_eq(_main.grid.get_cards().size(), total_before, "пустой запрос возвращает все файлы")

	# Без апгрейда поле скрыто.
	_game.upgrades["search_unlocked"] = 0
	_main._refresh_prep()
	_ok(not edit.visible, "без апгрейда поле поиска скрыто")
	_game.upgrades["search_unlocked"] = 1


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
