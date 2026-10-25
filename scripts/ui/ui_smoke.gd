extends SceneTree
## Headless smoke-проверка UI после интеграции с GameController.
##
## godot --headless --path . --script scripts/ui/ui_smoke.gd
##
## Сценарий: меню → start_new_run() (подготовка) → _on_start_hour() (час).
## Проверяет геометрию каркаса 1280×720, наполнение дерева/сетки/панелей,
## сетку папки 5×4, стол сортировки 4×6, 5 ячеек слотов и статус-бар.

const W := 1280.0
const H := 720.0

var _main: Node = null
var _fails: Array[String] = []
var _checks := 0
var _nodes := {}


func _initialize() -> void:
	var ps: PackedScene = load("res://scenes/Main.tscn")
	if ps == null:
		printerr("SMOKE FAIL: scenes/Main.tscn не загружается")
		quit(1)
		return
	_main = ps.instantiate()
	root.add_child(_main)
	root.size = Vector2i(int(W), int(H))
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	print("=== PEAK HOUR 97 · UI SMOKE (интеграция с GameController) ===")

	_check_layout()
	_check_menu()

	# --- подготовка: новый забег
	_call_start_new_run()
	await process_frame
	_check_prep()

	# --- час: старт часа
	if _main.has_method("_on_start_hour"):
		_main.call("_on_start_hour")
		await process_frame
		await process_frame
		_check_hour()
	else:
		_check(false, "main._on_start_hour() существует")

	_check_drops()
	_check_fonts()
	_finish()


# --------------------------------------------------------------------------
# Каркас
# --------------------------------------------------------------------------

func _check_layout() -> void:
	var paths := {
		"TitleBar": "TitleBar",
		"MenuBar": "MenuBar",
		"Workspace": "Workspace",
		"TreeWindow": "Workspace/TreeWindow",
		"FilesWindow": "Workspace/FilesWindow",
		"TreePanel": "Workspace/TreeWindow/Content/TreePanel",
		"FileGrid": "Workspace/FilesWindow/Content/FileGrid",
		"ReceiveWindow": "ReceiveWindow",
		"SendWindow": "SendWindow",
		"SlotsStrip": "SlotsStrip",
		"StatusBar": "StatusBar",
		"ToastLayer": "ToastLayer",
	}
	for key in paths:
		var n := _main.get_node_or_null(paths[key])
		_check(n != null, "узел %s существует" % key)
		if n is Control:
			var c: Control = n
			var r := Rect2(c.global_position, c.size)
			_nodes[key] = r
			_check(r.position.x >= -0.01 and r.position.y >= -0.01, "%s: левый/верхний край ≥ 0" % key)
			_check(r.end.x <= W + 0.01 and r.end.y <= H + 0.01,
				"%s: правый/нижний край ≤ 1280×720 (%.0f,%.0f)" % [key, r.end.x, r.end.y])
			_check(r.size.x > 0.0 and r.size.y > 0.0, "%s: размер > 0" % key)

	if _nodes.has("TitleBar"):
		_check(int(_nodes["TitleBar"].size.y) == 24, "титлбар 24 px")
	if _nodes.has("MenuBar"):
		_check(int(_nodes["MenuBar"].size.y) == 20, "меню 20 px")
	if _nodes.has("ReceiveWindow"):
		_check(_nodes["ReceiveWindow"] == Rect2(856, 48, 416, 264), "окно ПРИЁМ 856,48,416,264")
	if _nodes.has("SendWindow"):
		_check(_nodes["SendWindow"] == Rect2(856, 320, 416, 276), "окно ОТПРАВКА 856,320,416,276")
	if _nodes.has("SlotsStrip"):
		_check(_nodes["SlotsStrip"] == Rect2(8, 604, 1264, 52), "полоса слотов 8,604,1264,52")
	if _nodes.has("StatusBar"):
		_check(_nodes["StatusBar"] == Rect2(0, 660, 1280, 60), "статус-бар 0,660,1280,60")
	if _nodes.has("Workspace"):
		_check(_nodes["Workspace"] == Rect2(8, 48, 840, 548), "рабочая область 8,48,840,548")

	var order := ["Workspace", "ReceiveWindow", "SendWindow", "SlotsStrip", "StatusBar"]
	for i in order.size():
		for j in range(i + 1, order.size()):
			if _nodes.has(order[i]) and _nodes.has(order[j]):
				_check(not (_nodes[order[i]] as Rect2).intersects(_nodes[order[j]]),
					"%s и %s не перекрываются" % [order[i], order[j]])

	var grid: FileGrid = _main.get("grid")
	var view_w: float = (_nodes["FileGrid"].size.x - 18.0) if _nodes.has("FileGrid") else 0.0
	if grid != null:
		var gm: Dictionary = grid.grid_metrics()
		var cell := float(gm.get("cell", 0.0))
		var gap := float(gm.get("gap", 6.0))
		var grid_w := 5.0 * cell + 4.0 * gap
		_check(int(gm.get("cols", 0)) == 5 and int(gm.get("rows", 0)) == 4,
			"сетка папки 5×4 (сейчас %s×%s)" % [gm.get("cols", 0), gm.get("rows", 0)])
		_check(grid_w <= view_w + 0.5,
			"5×cell+4×gap=%.0f ≤ ширины поля %.0f" % [grid_w, view_w])


func _check_menu() -> void:
	_check(_main.get("main_menu") != null, "main_menu создан")
	var mm = _main.get("main_menu")
	if mm != null:
		_check(bool(mm.visible), "на старте меню видимо")
	_check(_main.get("controller") != null, "controller создан")
	var ctrl = _main.get("controller")
	if ctrl != null:
		_check(str(ctrl.phase) == "menu", "стартовая фаза — menu (сейчас %s)" % str(ctrl.phase))
	_check((_main.get("packets") as Array).is_empty(), "до забега ПРИЁМ пуст")
	_check((_main.get("requests") as Array).is_empty(), "до забега ОТПРАВКА пуста")
	var menu_btn: Button90 = _main.get("_menu_btn")
	_check(menu_btn != null and menu_btn.caption == "МЕНЮ", "одна кнопка МЕНЮ")
	var menus: Dictionary = _main.get("_menus")
	_check(not menus.has("ФАЙЛ") and not menus.has("ВИД") and not menus.has("СПРАВКА"),
		"нет демо-меню ФАЙЛ/ВИД/СПРАВКА")


# --------------------------------------------------------------------------
# Подготовка
# --------------------------------------------------------------------------

func _call_start_new_run() -> void:
	if _main.has_method("start_new_run"):
		_main.call("start_new_run")
	elif _main.has_method("_start_new_run"):
		_main.call("_start_new_run")
	else:
		_check(false, "main.start_new_run() существует")


func _check_prep() -> void:
	var ctrl = _main.get("controller")
	_check(ctrl != null and str(ctrl.phase) == "prep",
		"после start_new_run фаза prep (сейчас %s)" % (str(ctrl.phase) if ctrl else "нет"))
	var mm = _main.get("main_menu")
	_check(mm != null and not bool(mm.visible), "после start_new_run меню скрыто")

	# дерево получило данные
	var rows := _find_all(_main.get("tree"), "FolderRow")
	var sections := 0
	var folders := 0
	for r in rows:
		if (r as FolderRow).is_section:
			sections += 1
		else:
			folders += 1
	print("дерево: %d секций, %d папок" % [sections, folders])
	_check(sections >= 1, "в дереве ≥1 секция (сейчас %d)" % sections)
	_check(folders >= 1, "в дереве ≥1 папка (сейчас %d)" % folders)
	var first_folder: FolderRow = null
	for r in rows:
		if not (r as FolderRow).is_section:
			first_folder = r
			break
	if first_folder != null:
		_check(first_folder.selected, "первая папка выбрана в дереве")

	# сетка пуста на старте подготовки
	var cards: Array = (_main.get("grid") as FileGrid).get_cards()
	print("сетка: %d файлов" % cards.size())
	_check(cards.is_empty(), "в сетке 0 файлов на старте подготовки (сейчас %d)" % cards.size())
	_check((_main.get("grid") as FileGrid).folder_name.length() > 0, "в сетке выбрана папка")
	var grid_stats: Dictionary = (_main.get("grid") as FileGrid).stats()
	_check(int(grid_stats.get("total", 0)) == 20, "сетка 5×4 = 20 клеток")
	var table = _main.get("sorting_table")
	_check(table != null and bool(table.visible), "в подготовке виден стол сортировки")
	if table != null:
		_check(int(table.total_cells()) == 24, "стол сортировки 4×6 = 24 клетки")
		var tm: Dictionary = table.grid_metrics()
		_check(int(tm.get("cols", 0)) == 4 and int(tm.get("rows", 0)) == 6,
			"стол 4×6 (сейчас %s×%s)" % [tm.get("cols", 0), tm.get("rows", 0)])
	var recv_hidden: WindowFrame = _main.get_node("ReceiveWindow")
	var send_hidden: WindowFrame = _main.get_node("SendWindow")
	_check(not recv_hidden.visible and not send_hidden.visible,
		"ПРИЁМ/ОТПРАВКА скрыты в подготовке")
	var files_win: WindowFrame = _main.get("files_window")
	_check(files_win.title.contains((_main.get("grid") as FileGrid).folder_name),
		"заголовок ФАЙЛЫ содержит имя папки (%s)" % files_win.title)

	# ПРИЁМ/ОТПРАВКА пусты
	_check((_main.get("packets") as Array).is_empty(), "ПРИЁМ пуст в подготовке")
	_check((_main.get("requests") as Array).is_empty(), "ОТПРАВКА пуста в подготовке")
	_check((_main.get("slot_cells") as Array).is_empty(), "TCP-слоты очищены в подготовке")
	var recv: WindowFrame = _main.get_node("ReceiveWindow")
	var send: WindowFrame = _main.get_node("SendWindow")
	_check(_find_all(recv.content, "PacketCard").is_empty(), "в контенте ПРИЁМ нет карточек")
	_check(_find_all(send.content, "RequestCard").is_empty(), "в контенте ОТПРАВКА нет карточек")
	_check(recv.title_hint.contains("0 ПАКЕТОВ"), "ПРИЁМ: «%s»" % recv.title_hint)
	_check(send.title_hint.contains("0 ЗАПРОСОВ"), "ОТПРАВКА: «%s»" % send.title_hint)

	# статус-бар
	var sb: StatusBar = _main.get_node("StatusBar")
	var money := str(sb.get_metric("money").get("value", ""))
	var sla := str(sb.get_metric("sla").get("value", ""))
	print("статус[подготовка]: money=%s sla=%s tcp=%s buffer=%s channel=%s hour=%s" % [
		money, sla, str(sb.get_metric("tcp").get("value", "")),
		str(sb.get_metric("buffer").get("value", "")),
		str(sb.get_metric("channel").get("value", "")),
		str(sb.get_metric("hour").get("value", ""))])
	_check(money.contains("$ 50"), "статус: счёт «$ 50» (сейчас «%s»)" % money)
	_check(sla.contains("60 / 60"), "статус: SLA «60 / 60» (сейчас «%s»)" % sla)
	var shop_btn = _main.get("_shop_btn")
	_check(shop_btn != null and not bool(shop_btn.visible),
		"в первом приготовлении кнопка МАГАЗИН скрыта")
	_check(str(sb.get_metric("tcp").get("value", "")).begins_with("0 /"),
		"статус: TCP «0 / N»")
	_check(str(sb.get_metric("buffer").get("value", "")).begins_with("0 /"),
		"статус: буфер «0 / N»")
	_check(str(sb.get_metric("channel").get("value", "")).contains("/"),
		"статус: канал вида load/capacity")


# --------------------------------------------------------------------------
# Час
# --------------------------------------------------------------------------

func _check_hour() -> void:
	var ctrl = _main.get("controller")
	_check(ctrl != null and str(ctrl.phase) == "hour",
		"после _on_start_hour фаза hour (сейчас %s)" % (str(ctrl.phase) if ctrl else "нет"))

	var cells: Array = _main.get("slot_cells")
	print("слоты: %d" % cells.size())
	_check(cells.size() == 5, "slot_cells = 5 (сейчас %d)" % cells.size())
	var strip: Panel90 = _main.get_node("SlotsStrip")
	var nodes := _find_all(strip, "SlotCell")
	_check(nodes.size() == 5, "в полосе 5 SlotCell (сейчас %d)" % nodes.size())
	var strip_rect := Rect2(strip.global_position, strip.size)
	for i in mini(cells.size(), 5):
		var cell: SlotCell = cells[i]
		var r := Rect2(cell.global_position, cell.size)
		_check(r.size == Vector2(236, 44), "слот %d: 236×44 (сейчас %.0f×%.0f)" % [i, r.size.x, r.size.y])
		_check(cell.position == Vector2(58 + i * 240, 5), "слот %d: позиция 58+240i" % i)
		_check(strip_rect.encloses(r), "слот %d внутри полосы" % i)

	var sb: StatusBar = _main.get_node("StatusBar")
	var keys := ["tcp", "channel", "sla", "buffer", "money", "hour"]
	for k in keys:
		_check(not str(sb.get_metric(k).get("value", "")).is_empty(), "статус[час]: сегмент %s заполнен" % k)
	var tcp := str(sb.get_metric("tcp").get("value", ""))
	var hour := str(sb.get_metric("hour").get("value", ""))
	var money := str(sb.get_metric("money").get("value", ""))
	var sla := str(sb.get_metric("sla").get("value", ""))
	print("статус[час]: money=%s sla=%s tcp=%s channel=%s hour=%s" % [
		money, sla, tcp, str(sb.get_metric("channel").get("value", "")), hour])
	_check(tcp.begins_with("0 /"), "статус[час]: TCP вида «0 / N» (сейчас «%s»)" % tcp)
	_check(hour.contains("ЧАС"), "статус[час]: подпись «ЧАС N» (сейчас «%s»)" % hour)
	_check(money.contains("$"), "статус[час]: счёт в долларах")
	_check(sla.contains("/ 60"), "статус[час]: SLA из 60")
	var shop_btn = _main.get("_shop_btn")
	_check(shop_btn != null and not bool(shop_btn.visible),
		"во время часа кнопка МАГАЗИН скрыта")

	var recv: WindowFrame = _main.get_node("ReceiveWindow")
	var send: WindowFrame = _main.get_node("SendWindow")
	var packet_hint: String = str(_main.call("_plural_ru",
		(_main.get("packets") as Array).size(), "ПАКЕТ", "ПАКЕТА", "ПАКЕТОВ"))
	var request_hint: String = str(_main.call("_plural_ru",
		(_main.get("requests") as Array).size(), "ЗАПРОС", "ЗАПРОСА", "ЗАПРОСОВ"))
	_check(recv.title_hint == packet_hint,
		"ПРИЁМ переключён на час: «%s» (ожидалось «%s»)" % [recv.title_hint, packet_hint])
	_check(send.title_hint == request_hint,
		"ОТПРАВКА переключена на час: «%s» (ожидалось «%s»)" % [send.title_hint, request_hint])
	var toast: ToastLayer = _main.get_node("ToastLayer")
	_check(toast.get_child_count() >= 1, "тост «ЧАС N НАЧАЛСЯ» показан")


# --------------------------------------------------------------------------
# Контракты drag&drop (на живых узлах подготовки)
# --------------------------------------------------------------------------

func _check_drops() -> void:
	var rows := _find_all(_main.get("tree"), "FolderRow")
	var target: FolderRow = null
	for r in rows:
		if not (r as FolderRow).is_section:
			target = r
			break
	if target != null:
		var payload := {"kind": "file", "id": "smoke"}
		var ok: bool = target._can_drop_data(Vector2.ZERO, payload)
		_check(ok and target.drop_active, "строка папки принимает {kind:file}")
		target._drop_data(Vector2.ZERO, payload)
		_check(not target.drop_active, "подсветка папки снимается после drop")
	var fg: FileGrid = _main.get("grid")
	_check(fg._can_drop_data(Vector2.ZERO, {"kind": "packet", "id": "p"}), "сетка принимает пакет")
	_check(not fg._can_drop_data(Vector2.ZERO, {"kind": "nope"}), "сетка отвергает чужие данные")


# --------------------------------------------------------------------------
# Шрифты и тема
# --------------------------------------------------------------------------

func _check_fonts() -> void:
	var word_font := Theme90.ui()
	_check(word_font is FontVariation, "основной шрифт — FontVariation")
	var cyr := "ПРИЁМОТПРАВКАСОЕДИНИТЬСЯПапка заполненаООО «Вектор»"
	var missing := ""
	for i in cyr.length():
		if not word_font.has_char(cyr.unicode_at(i)):
			missing += cyr[i]
	_check(missing.is_empty(), "Handjet содержит кириллицу (%s)" % ("нет: " + missing if not missing.is_empty() else "ок"))
	_check(Theme90.logo().has_char(48), "Press Start 2P содержит цифру 0")
	_check([Theme90.FS_MICRO, Theme90.FS_BODY, Theme90.FS_HEAD, Theme90.FS_LOGO] == [11, 13, 17, 26],
		"кегли 11/13/17/26")
	var th: Theme = load("res://art/fonts/ui_theme.tres")
	_check(th != null, "art/fonts/ui_theme.tres загружается")
	if th != null:
		_check(th.default_font is FontVariation, "тема: default_font = FontVariation")
		_check(th.default_font_size == 13, "тема: базовый кегль 13")


# --------------------------------------------------------------------------
# Итог
# --------------------------------------------------------------------------

func _finish() -> void:
	print("--- проверок: %d, провалов: %d ---" % [_checks, _fails.size()])
	for f in _fails:
		printerr("FAIL: " + f)
	if _fails.is_empty():
		print("SMOKE OK")
	else:
		printerr("SMOKE FAILED")
	quit(0 if _fails.is_empty() else 1)


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails.append(label)


func _find_all(node: Node, cls: String) -> Array:
	var out: Array = []
	if node == null:
		return out
	for c in node.get_children():
		var sc = c.get_script()
		if sc != null and sc.get_global_name() == cls:
			out.append(c)
		out.append_array(_find_all(c, cls))
	return out
