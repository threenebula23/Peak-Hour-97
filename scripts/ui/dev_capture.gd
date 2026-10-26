extends SceneTree
## Dev-инструмент (не часть игры): снимает кадр сцены в PNG.
##
## Базовые примеры:
##   godot --path . --script scripts/ui/dev_capture.gd -- --scene=res://scenes/Main.tscn --out=/tmp/opencode/peak.png
##   godot --path . --script scripts/ui/dev_capture.gd -- --probe --out=/tmp/opencode/font_probe.png
##
## Экраны игры (флаги сами запускают новый забег, если это нужно):
##   ... -- --run --out=/tmp/opencode/prep.png
##   ... -- --hour --seconds=8 --spawn=packet,request --out=/tmp/opencode/hour.png
##   ... -- --minigame=dots --tier=2 --out=/tmp/opencode/dots.png
##   ... -- --shop --out=/tmp/opencode/shop.png
##   ... -- --tutorial --out=/tmp/opencode/tutorial.png
##
## Флаги:
##   --scene=PATH      сцена для загрузки (по умолчанию res://scenes/Main.tscn)
##   --out=PATH        куда сохранить PNG (по умолчанию /tmp/opencode/peak.png)
##   --wait=N          сколько кадров ждать перед снимком (по умолчанию 10)
##   --probe           отрисовать шрифтовой probe вместо Main
##   --run             нажать «НОВЫЙ ЗАБЕГ» (Main._start_new_run)
##   --seed-demo       в подготовку положить sound-файл (2 клетки) для проверки drag
##   --hour            после --run начать час 1 (Main._on_start_hour)
##   --seconds=N       сколько реальных секунд крутить час (по умолчанию 6) — нужен --hour
##   --spawn=A,B       через HourDirector спавнить packet и/или request (нужен --hour)
##   --folder=ID       открыть папку по id (как раньше); с --run без --folder
##                     автоматически открывается первая папка
##   --minigame=ID     dots|sound|text|video|photo|maze|junk|ddos|phishing|ransomware
##   --tier=N          сложность мини-игры, 1..4 (по умолчанию 2)
##   --seed=N          сид мини-игры (по умолчанию 12345)
##   --shop            свернуть офферы для часа 2 и открыть ShopModal
##   --tutorial        запустить забег и показать маскота-туториал
##   --sla=N           выставить SLA (dev, для скриншотов «ЖАРЫ»)
##   --stress=STATE    calm|warm|hot|critical|attack — force_heat оверлея
##   --reduce          включить «Снизить эффекты» (UiMotion.reduced)
##   --menu            контекстное меню 90-х (как раньше)
##   --filemenu        выпадающее меню «ФАЙЛ» (как раньше)
##   --toast           два демо-тоста (как раньше)
##   --hover=x,y       навести курсор
##   --press=x,y       нажать ЛКМ в точке (без отпускания)
##   --drag=x1,y1,x2,y2  настоящий drag: press → motion ×8 → release
##   --hold            с --drag: остановиться до release (кадр «в процессе»)
##   --raw-coords      координаты --hover/--press/--drag заданы в пикселях окна,
##                     а не в логических 1280×720 (аварийный режим совместимости)
##
## ПРОСТРАНСТВО КООРДИНАТ:
##   Все координаты указателя (--hover/--press/--drag) — ЛОГИЧЕСКИЕ 1280×720,
##   как в макете. Внутри они умножаются на реальный размер окна / 1280×720
##   (обычно 1920×1080 → ×1.5). Скриншот всегда сохраняется в пикселях окна
##   (обычно 1920×1080). --raw-coords отключает пересчёт.
##
## При ошибке (нет метода Main, пустая папка, мини-игра не создалась) скрипт
## печатает причину и завершается с кодом 1, а не снимает меню молча.

const LOGICAL_SIZE := Vector2(1280.0, 720.0)
const SEND_GAMES: Array[String] = [
	"dots", "sound", "text", "video", "photo", "maze",
]
const ATTACK_GAMES: Array[String] = [
	"junk", "ddos", "phishing", "ransomware",
]

var _scene_path := "res://scenes/Main.tscn"
var _out := "/tmp/opencode/peak.png"
var _wait := 10
var _probe := false
var _menu := false
var _toast := false
var _hover := Vector2(-1, -1)
var _press := Vector2(-1, -1)
var _folder := ""
var _filemenu := false
var _main: Node = null

var _run := false
var _seed_demo := false
var _hour := false
var _seconds := 6.0
var _spawn: Array[String] = []
var _minigame := ""
var _tier := 2
var _seed := 12345
var _shop := false
var _tutorial := false
## [start, end] в логических координатах; пустой массив — drag не нужен.
var _drag: Array[Vector2] = []
var _hold := false
var _raw_coords := false
## «ЖАРА»: dev-флаги для скриншотов нагрева.
var _sla := -1.0
var _stress := ""
var _reduce := false

## Снимок делается только после того, как сцена и запрошенные экраны готовы.
var _setup_done := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			_scene_path = a.substr(8)
		elif a.begins_with("--out="):
			_out = a.substr(6)
		elif a == "--probe":
			_probe = true
		elif a.begins_with("--wait="):
			_wait = int(a.substr(7))
		elif a == "--menu":
			_menu = true
		elif a == "--filemenu":
			_filemenu = true
		elif a == "--toast":
			_toast = true
		elif a == "--run":
			_run = true
		elif a == "--seed-demo":
			_seed_demo = true
		elif a == "--hour":
			_hour = true
		elif a.begins_with("--seconds="):
			_seconds = maxf(0.0, float(a.substr(10)))
		elif a.begins_with("--spawn="):
			_spawn.clear()
			for raw in a.substr(8).split(",", false):
				var token := raw.strip_edges().to_lower()
				if token.is_empty():
					continue
				if token != "packet" and token != "request":
					_fail("--spawn: неизвестный тип '%s' (ожидается packet или request)" % token)
					return
				_spawn.append(token)
		elif a.begins_with("--folder="):
			_folder = a.substr(9)
		elif a.begins_with("--minigame="):
			_minigame = a.substr(11).strip_edges().to_lower()
		elif a.begins_with("--tier="):
			_tier = clampi(int(a.substr(7)), 1, 4)
		elif a.begins_with("--seed="):
			_seed = int(a.substr(7))
		elif a == "--shop":
			_shop = true
		elif a == "--tutorial":
			_tutorial = true
		elif a.begins_with("--hover="):
			_hover = _parse_pair(a.substr(8))
			if _hover.x < 0.0:
				_fail("--hover: нужен формат x,y")
				return
		elif a.begins_with("--press="):
			_press = _parse_pair(a.substr(8))
			if _press.x < 0.0:
				_fail("--press: нужен формат x,y")
				return
		elif a.begins_with("--drag="):
			var parts := a.substr(7).split(",", false)
			if parts.size() != 4:
				_fail("--drag: нужен формат x1,y1,x2,y2")
				return
			var p1 := _parse_pair("%s,%s" % [parts[0], parts[1]])
			var p2 := _parse_pair("%s,%s" % [parts[2], parts[3]])
			if p1.x < 0.0 or p2.x < 0.0:
				_fail("--drag: координаты должны быть числами x1,y1,x2,y2")
				return
			_drag = [p1, p2]
		elif a == "--hold":
			_hold = true
		elif a == "--raw-coords":
			_raw_coords = true
		elif a.begins_with("--sla="):
			_sla = float(a.substr(6))
		elif a.begins_with("--stress="):
			_stress = a.substr(9).strip_edges().to_lower()
		elif a == "--reduce":
			_reduce = true
		elif a == "--help" or a == "-h":
			_print_help()
			quit(0)
			return
	if not _minigame.is_empty() and not SEND_GAMES.has(_minigame) \
			and not ATTACK_GAMES.has(_minigame):
		_fail("--minigame: '%s' не поддерживается (см. --help)" % _minigame)
		return
	if _hold and _drag.is_empty():
		_fail("--hold имеет смысл только вместе с --drag")
		return
	if not _stress.is_empty() and not ["calm", "warm", "hot", "critical", "attack"].has(_stress):
		_fail("--stress: неизвестное состояние '%s'" % _stress)
		return
	if _probe:
		root.add_child(Probe.new())
		_setup_done = true
		return
	var ps: PackedScene = load(_scene_path)
	if ps == null:
		_fail("cannot load " + _scene_path)
		return
	_main = ps.instantiate()
	root.add_child(_main)
	call_deferred("_after_ready")


func _after_ready() -> void:
	# Дадим Main один-два кадра на _ready/_process и ленивые модалки.
	await _frames(2)
	if _main == null:
		_fail("Main не загрузился")
		return

	if _toast and _main.has_method("_toast"):
		_main.call("_toast", "СОЕДИНЕНИЕ УСТАНОВЛЕНО · договор_11.doc", "success")
		_main.call("_toast", "КАПАЛ 45% · БУФЕР 3/4", "warn")

	# Игровые экраны невозможны без забега: --hour/--shop/--tutorial/--minigame
	# и --spawn сами включают его, чтобы команды из документации работали.
	var need_run: bool = _run or _hour or _shop or _tutorial \
		or not _minigame.is_empty() or not _spawn.is_empty()
	if need_run:
		if not _invoke_main("_start_new_run", [], "start_new_run"):
			return
		await _frames(4)

	# --folder имеет приоритет; иначе после --run открываем первую папку,
	# чтобы в кадре была сетка файлов, а не пустая панель.
	if not _folder.is_empty():
		if not _invoke_main("_on_folder_selected", [_folder]):
			return
		await _frames(2)
	elif need_run:
		if not _select_first_folder():
			return
		await _frames(2)

	# Dev-подготовка: 2-клеточный sound-файл рядом с bootstrap text-файлом,
	# чтобы проверять перенос/фантомы в сетке без запуска часа.
	if _seed_demo and not _hour:
		if not _seed_prep_demo():
			return
		await _frames(2)

	if _hour or not _spawn.is_empty():
		# Новый забег начинается с пустого склада: без файлов HourDirector
		# не сможет создать запросы. Кладём демо-файлы в первую папку.
		if not _seed_demo_files():
			return
		if not _invoke_main("_on_start_hour"):
			return
		await _frames(3)
		if not _spawn.is_empty() and not _spawn_cards():
			return
		if _seconds > 0.0:
			# Настоящее время: HourDirector тикает из Main._process, пакеты и
			# запросы успевают появиться и отрисоваться.
			await create_timer(_seconds).timeout
		await _frames(3)

	if _shop:
		if not _open_shop():
			return
		await _frames(3)

	if _tutorial:
		if not _show_tutorial():
			return
		await _frames(2)

	if not _minigame.is_empty():
		if not _show_minigame():
			return
		await _frames(6)

	# «ЖАРА»: dev-флаги нагрева/SLA/reduce — последними, чтобы кадр был стабилен.
	if _sla >= 0.0 or _reduce or not _stress.is_empty():
		if not _apply_stress_flags():
			return
		# Даём термометру довести display-ease (tau 0.25) до заданного heat.
		await create_timer(1.5).timeout

	# Прежние сценарии меню/тостов/файлового меню.
	if _filemenu and _main != null:
		await create_timer(0.1).timeout
		var menus: Dictionary = _main.get("_menus")
		if menus.has("ФАЙЛ"):
			var pm: PopupMenu = menus["ФАЙЛ"]
			pm.popup(Rect2i(Vector2i(6, 44), Vector2i.ZERO))

	if _menu:
		await create_timer(0.1).timeout
		ContextMenu90.show_items(_main, [
			{"label": "Новая папка", "id": "new"},
			{"label": "Переименовать", "id": "rename"},
			{"label": "Удалить", "id": "delete"},
			{"sep": true},
			{"label": "Уничтожить содержимое", "id": "destroy", "danger": true},
		], Vector2(120, 220), func(_id: String) -> void: pass)

	if _hover.x >= 0.0:
		await create_timer(0.15).timeout
		Input.warp_mouse(_window_point(_hover))

	if _press.x >= 0.0:
		await create_timer(0.15).timeout
		_send_button(_window_point(_press), true)

	if not _drag.is_empty():
		await _do_drag()

	_setup_done = true


func _process(_delta: float) -> bool:
	if not _setup_done:
		return false
	_wait -= 1
	if _wait > 0:
		return false
	if DisplayServer.get_name() == "headless":
		_fail("headless-режим: скриншот невозможен, нужен реальный дисплей")
		return true
	var tex := root.get_texture()
	if tex == null:
		_fail("нет текстуры окна (headless? нужен реальный дисплей)")
		return true
	var img := tex.get_image()
	if img == null:
		_fail("не удалось получить изображение кадра")
		return true
	var err := img.save_png(_out)
	if err != OK:
		_fail("не удалось сохранить %s (ошибка %d)" % [_out, err])
		return true
	print("saved ", _out, " ", img.get_size())
	quit()
	return true


# --------------------------------------------------------------------------
# Шаги сценария
# --------------------------------------------------------------------------

## Вызвать метод Main; при отсутствии — внятная ошибка и код 1.
func _invoke_main(method: String, args: Array = [], fallback: String = "") -> bool:
	if _main == null:
		_fail("Main не загружен")
		return false
	var target := method
	if not _main.has_method(target):
		if fallback.is_empty() or not _main.has_method(fallback):
			_fail("Main не имеет метода %s()" % method)
			return false
		target = fallback
	_main.callv(target, args)
	return true


func _select_first_folder() -> bool:
	var folder_id := _first_folder_id()
	if folder_id.is_empty():
		_fail("в подготовке нет ни одной папки для --run")
		return false
	return _invoke_main("_on_folder_selected", [folder_id])


func _first_folder_id() -> String:
	var ctrl = _main.get("controller")
	if ctrl == null or not ctrl.has_method("prep_data"):
		return ""
	var d: Dictionary = ctrl.call("prep_data")
	for sec in d.get("sections", []):
		var folders: Array = sec.get("folders", [])
		if folders.is_empty():
			continue
		var folder_id := str(folders[0].get("id", ""))
		if not folder_id.is_empty():
			return folder_id
	return ""


func _folder_exists(folder_id: String) -> bool:
	var ctrl = _main.get("controller")
	if ctrl == null or not ctrl.has_method("prep_data"):
		return false
	var d: Dictionary = ctrl.call("prep_data")
	for sec in d.get("sections", []):
		for fol in sec.get("folders", []):
			if str(fol.get("id", "")) == folder_id:
				return true
	return false


## Dev: sound-файл на 2 клетки в первую папку подготовки (без запуска часа).
func _seed_prep_demo() -> bool:
	var game_node := root.get_node_or_null("Game")
	if game_node == null:
		_fail("--seed-demo: автолоад Game недоступен")
		return false
	var registry = game_node.get("registry")
	var folder_id := _first_folder_id()
	if registry == null or folder_id.is_empty():
		_fail("--seed-demo: нет реестра или папки")
		return false
	if registry.has_method("find_by_name") \
			and registry.call("find_by_name", "звонок_демо") != null:
		return true
	var file = registry.call("create_file", "звонок_демо", "sound", folder_id)
	if file == null:
		_fail("--seed-demo: не удалось создать sound-файл")
		return false
	# Детерминированно: 2 клетки горизонтально в (1,0).
	file.shape_id = "I2H"
	file.shape_cells = registry.call("shape_cells", "I2H", 0)
	if not bool(registry.call("move_file", str(file.id), folder_id,
			Vector2i(1, 0), 0)):
		_fail("--seed-demo: не удалось разместить sound-файл в (1,0)")
		return false
	if _main.has_method("_refresh_prep"):
		_main.call("_refresh_prep")
	return true


## Демо-файлы для часа: без них запросы не спавнятся (реестр пуст).
func _seed_demo_files() -> bool:
	var game_node := root.get_node_or_null("Game")
	if game_node == null:
		_fail("автолоад Game недоступен")
		return false
	var registry = game_node.get("registry")
	if registry == null or not registry.has_method("create_file"):
		_fail("Game.registry.create_file() недоступен")
		return false
	var folder_id := _folder
	if folder_id.is_empty() or not _folder_exists(folder_id):
		folder_id = _first_folder_id()
	if folder_id.is_empty():
		_fail("некуда положить демо-файлы: нет папок")
		return false
	var demo := [["договор_97", "text"], ["смета_демо", "photo"],
		["отчёт_демо", "video"]]
	for pair in demo:
		var file_name := str(pair[0])
		if registry.has_method("find_by_name") \
				and registry.call("find_by_name", file_name) != null:
			continue
		registry.call("create_file", file_name, str(pair[1]), folder_id)
	if _main.has_method("_refresh_prep"):
		_main.call("_refresh_prep")
	return true


## «ЖАРА»: --sla=N, --stress=..., --reduce — только для dev-скриншотов.
func _apply_stress_flags() -> bool:
	var game_node := root.get_node_or_null("Game")
	if _sla >= 0.0:
		if game_node == null:
			_fail("--sla: автолоад Game недоступен")
			return false
		var cap := 60.0
		if game_node.has_method("sla_cap"):
			cap = float(game_node.call("sla_cap"))
		game_node.set("sla", clampf(_sla, 0.0, maxf(1.0, cap)))
		if _main != null and _main.has_method("_refresh_hour"):
			_main.call("_refresh_hour")
	if _reduce:
		if _main == null or not _main.has_method("_apply_settings"):
			_fail("--reduce: Main._apply_settings() недоступен")
			return false
		_main.call("_apply_settings", {"reduce_motion": true}, false)
	if _stress.is_empty():
		return true
	var overlay = _main.get("stress_overlay") if _main != null else null
	if overlay == null or not overlay.has_method("force_heat"):
		_fail("Main.stress_overlay.force_heat() недоступен")
		return false
	var heat := 0.0
	match _stress:
		"calm":
			heat = 0.08
		"warm":
			heat = 0.46
		"hot":
			heat = 0.70
		"critical":
			heat = 0.92
		"attack":
			heat = 0.88
		_:
			_fail("--stress: неизвестное состояние '%s'" % _stress)
			return false
	overlay.call("force_heat", heat)
	if _stress == "attack" and overlay.has_method("notify"):
		overlay.call("notify", "attack_start")
	if _main != null and _main.has_method("_sync_stress_ui"):
		_main.call("_sync_stress_ui")
	return true


func _spawn_cards() -> bool:
	var ctrl = _main.get("controller")
	if ctrl == null:
		_fail("Main.controller недоступен")
		return false
	var director = ctrl.get("hour_director")
	if director == null:
		_fail("HourDirector недоступен")
		return false
	for token in _spawn:
		if token == "packet":
			if not director.has_method("spawn_packet_now"):
				_fail("HourDirector.spawn_packet_now() отсутствует")
				return false
			var spawned := 0
			for i in 3:
				if not str(director.call("spawn_packet_now")).is_empty():
					spawned += 1
			if spawned == 0:
				_fail("HourDirector не смог создать ни одного пакета")
				return false
		elif token == "request":
			if not director.has_method("spawn_request_now"):
				_fail("HourDirector.spawn_request_now() отсутствует")
				return false
			var spawned_req := 0
			for i in 2:
				var req_id := str(director.call("spawn_request_now"))
				if req_id.is_empty():
					# Страховка: один файл на запрос, если обычный ролл не прошёл.
					req_id = str(director.call("spawn_request_now", 1))
				if not req_id.is_empty():
					spawned_req += 1
			if spawned_req == 0:
				_fail("HourDirector не смог создать ни одного запроса")
				return false
	if _main.has_method("_refresh_hour"):
		_main.call("_refresh_hour")
	return true


func _open_shop() -> bool:
	var ctrl = _main.get("controller")
	if ctrl == null:
		_fail("Main.controller недоступен")
		return false
	var shop = ctrl.get("shop")
	if shop == null:
		_fail("GameController.shop недоступен")
		return false
	var modal = _main.get("shop_modal")
	if modal == null:
		_fail("Main.shop_modal недоступен")
		return false
	if not modal.has_method("open_prep"):
		_fail("ShopModal.open_prep() отсутствует")
		return false
	# Магазин в игре открывается в подготовке ПОСЛЕ часа 1. Main._on_shop()
	# на часе 1 отказывает, поэтому крутим офферы для часа 2 и открываем
	# модалку напрямую тем же API, что и игра.
	if shop.has_method("refresh"):
		shop.call("refresh", 2, _game_money())
	var offers: Array = []
	if shop.has_method("offers"):
		offers = shop.call("offers")
	if offers.is_empty():
		_fail("магазин не выдал офферы для часа 2")
		return false
	modal.call("open_prep", shop, _game_money(), 2)
	if not bool(modal.get("visible")):
		_fail("ShopModal не открылся")
		return false
	return true


func _show_tutorial() -> bool:
	var mascot = _main.get("mascot")
	if mascot == null or not mascot.has_method("show_message"):
		_fail("Main.mascot/TutorialMascot.show_message() недоступен")
		return false
	var phase := ""
	var ctrl = _main.get("controller")
	if ctrl != null:
		phase = str(ctrl.get("phase"))
	if phase == "hour" and _main.has_method("_show_tutorial_step"):
		_main.call("_show_tutorial_step", 0)
	elif _main.has_method("_maybe_show_prep_tutorial"):
		_main.call("_maybe_show_prep_tutorial")
	if not bool(mascot.get("visible")):
		# В headless авто-туториал выключен; для инструмента показываем явно.
		mascot.call("show_message",
			"Привет, я БАЙТ. Час пик начинается с приёма пакетов.", -1.0)
	if not bool(mascot.get("visible")):
		_fail("маскот-туториал не стал видимым")
		return false
	return true


func _show_minigame() -> bool:
	var game = null
	if SEND_GAMES.has(_minigame):
		game = MiniGameFactory.create_send(_minigame, _tier, _seed)
	elif ATTACK_GAMES.has(_minigame):
		game = MiniGameFactory.create_attack(_minigame, _tier, _seed)
	if game == null:
		_fail("MiniGameFactory не создал '%s' (tier %d)" % [_minigame, _tier])
		return false
	var host: Node = _main
	var mr = _main.get("modal_root")
	if mr != null:
		host = mr
	host.add_child(game)
	if game is Control:
		# См. Main._show_modal_game: фиксируем min-size, затем центрируем KEEP_SIZE.
		var ctl := game as Control
		ctl.size = ctl.get_combined_minimum_size()
		ctl.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	if game.has_method("start"):
		game.call("start", _minigame, _tier, _seed)
	if game is CanvasItem and not (game as CanvasItem).visible:
		_fail("мини-игра '%s' создана, но не видима" % _minigame)
		return false
	return true


# --------------------------------------------------------------------------
# Ввод: логические 1280×720 → пиксели окна
# --------------------------------------------------------------------------

func _window_point(logical: Vector2) -> Vector2:
	if _raw_coords:
		return logical
	var win := Vector2(DisplayServer.window_get_size())
	if win.x <= 0.0 or win.y <= 0.0:
		return logical
	return Vector2(logical.x * win.x / LOGICAL_SIZE.x,
		logical.y * win.y / LOGICAL_SIZE.y)


func _send_button(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(ev)


func _do_drag() -> void:
	var start := _window_point(_drag[0])
	var finish := _window_point(_drag[1])
	_send_button(start, true)
	await _frames(2)
	var steps := 8
	var prev := start
	for i in range(1, steps + 1):
		var p := start.lerp(finish, float(i) / float(steps))
		if DisplayServer.get_name() != "headless":
			# Держим и системный курсор рядом: hover-open папок смотрит на него.
			Input.warp_mouse(p)
		var motion := InputEventMouseMotion.new()
		motion.position = p
		motion.global_position = p
		motion.relative = p - prev
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(motion)
		prev = p
		await process_frame
	if not _hold:
		# --hold оставляет кнопку зажатой: снимок ловит середину drag'а.
		_send_button(finish, false)
		await _frames(2)


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _parse_pair(text: String) -> Vector2:
	var parts := text.split(",", false)
	if parts.size() != 2:
		return Vector2(-1, -1)
	if not parts[0].strip_edges().is_valid_float() \
			or not parts[1].strip_edges().is_valid_float():
		return Vector2(-1, -1)
	return Vector2(float(parts[0]), float(parts[1]))


func _game_money() -> int:
	var node := root.get_node_or_null("Game")
	if node == null:
		return 0
	return int(node.get("money"))


func _fail(message: String) -> void:
	printerr("dev_capture: ERROR: ", message)
	push_error("dev_capture: " + message)
	quit(1)


func _print_help() -> void:
	print("dev_capture.gd — снимок экрана PEAK HOUR 97")
	print("  --run --hour --seconds=N --spawn=packet,request")
	print("  --minigame=ID --tier=N --seed=N --shop --tutorial")
	print("  --folder=ID --hover=x,y --press=x,y --drag=x1,y1,x2,y2 --hold")
	print("  --sla=N --stress=calm|warm|hot|critical|attack --reduce")
	print("  --menu --filemenu --toast --probe --out=PATH --wait=N")
	print("  Координаты указателя — логические 1280x720; --raw-coords для пикселей окна.")
	print("  Мини-игры: ", ", ".join(SEND_GAMES + ATTACK_GAMES))


# --------------------------------------------------------------------------
# Font probe
# --------------------------------------------------------------------------

class Probe:
	extends Control

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Theme90.FACE)
		Theme90.draw_bevel(self, Rect2(8, 8, 1264, 704))
		var f := Theme90.ui()
		Theme90.draw_sunken(self, Rect2(20, 20, 1240, 300))
		Theme90.text(self, f, Vector2(32, 30), "ПРИЁМ  ОТПРАВКА  СОЕДИНИТЬСЯ", 24, Theme90.INK)
		print("ascent10=", f.get_ascent(10), " descent10=", f.get_descent(10), " height10=", f.get_height(10))
		print("ascent12=", f.get_ascent(12), " height12=", f.get_height(12))
		print("ascent16=", f.get_ascent(16), " height16=", f.get_height(16))
		print("ascent24=", f.get_ascent(24), " height24=", f.get_height(24))
		print("width ПРИЁМ@12=", f.get_string_size("ПРИЁМ", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x)
		print("width 12ch@10=", f.get_string_size("отчёт_07.xls", HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x)
		print("logo width=", Theme90.logo().get_string_size("PEAK HOUR 97", HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x)
		var y := 70.0
		for s in [10, 12, 16, 24]:
			Theme90.text(self, f, Vector2(32, y), "Папка заполнена · ООО «Вектор» · $ 1240 · 03:42 (%d)" % s, s, Theme90.INK)
			draw_line(Vector2(32, y + f.get_height(s)), Vector2(700, y + f.get_height(s)), Theme90.SHADE, 1.0)
			y += 46
		Theme90.text_engraved(self, f, Vector2(32, 270), "ЗАГОЛОВОК ГРУППЫ — ГРАВИРОВКА", 12)
		# кнопки
		var bx := 760.0
		Theme90.draw_bevel(self, Rect2(bx, 40, 120, 24))
		Theme90.text_vcenter(self, f, Rect2(bx, 40, 120, 24), "СОЕДИНИТЬСЯ", 12, Theme90.INK,
			-1, HORIZONTAL_ALIGNMENT_CENTER)
		Theme90.draw_bevel(self, Rect2(bx, 72, 120, 24), true)
		Theme90.text_vcenter(self, f, Rect2(bx, 72, 120, 24), "НАЖАТА", 12, Theme90.INK,
			-1, HORIZONTAL_ALIGNMENT_CENTER)
		var logo := Theme90.logo()
		Theme90.text(self, logo, Vector2(bx, 120), "PEAK HOUR 97", 24, Theme90.NAVY)
		# иконки
		var ic := ["text", "sound", "photo", "video"]
		for i in 4:
			var col: Color = [Theme90.NAVY, Theme90.WARN, Theme90.SUCCESS, Theme90.ERROR][i]
			Theme90.draw_doc_icon(self, Rect2(bx + i * 36, 170, 24, 24), ic[i], col)
			Theme90.draw_folder_icon(self, Vector2(bx + i * 36, 210), Theme90.WARN, i % 2 == 0)
			Theme90.draw_lock_icon(self, Vector2(bx + i * 36, 230), Theme90.DARK)
			Theme90.draw_drive_icon(self, Vector2(bx + i * 36, 250), Theme90.NAVY)
			Theme90.draw_packet_icon(self, Vector2(bx + i * 36, 268), Theme90.NAVY)
		Theme90.draw_dashed_box(self, Rect2(20, 320, 1240, 380), Theme90.SHADE)
		Theme90.text(self, f, Vector2(32, 330), "пусто · ожидается · locked · malicious · attached", 12, Theme90.DARK)
		# проверка вариативных осей
		var yy := 360.0
		for w in [100.0, 400.0, 700.0, 900.0]:
			var fw := Theme90.ui(w)
			Theme90.text(self, fw, Vector2(40, yy), "wght %d — ПРИЁМ ОТПРАВКА 0123" % int(w), 16, Theme90.INK)
			yy += 26
		for eg in [1.0, 2.0]:
			for esh in [0.0, 2.0, 8.0]:
				var fe := Theme90.ui(700.0, eg, esh)
				Theme90.text(self, fe, Vector2(560, yy2(eg, esh) + 0), "ELGR %d ELSH %d — Папка заполнена 1240" % [int(eg), int(esh)], 16, Theme90.INK)

	func yy2(eg: float, esh: float) -> float:
		var i := 0 if eg == 1.0 else 1
		var j := [0, 2, 8].find(esh)
		return 360.0 + (i * 3 + j) * 26.0
