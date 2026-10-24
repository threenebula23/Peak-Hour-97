extends SceneTree
## Dev-инструмент (не часть игры): снимает кадр сцены в PNG.
##
## godot --path . --script scripts/ui/dev_capture.gd -- --scene=res://scenes/Main.tscn --out=/tmp/opencode/peak.png
## godot --path . --script scripts/ui/dev_capture.gd -- --probe --out=/tmp/opencode/font_probe.png

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
		elif a.begins_with("--hover="):
			var hp := a.substr(8).split(",")
			_hover = Vector2(float(hp[0]), float(hp[1]))
		elif a.begins_with("--folder="):
			_folder = a.substr(9)
		elif a.begins_with("--press="):
			var pp := a.substr(8).split(",")
			_press = Vector2(float(pp[0]), float(pp[1]))
	if _probe:
		root.add_child(Probe.new())
	else:
		var ps: PackedScene = load(_scene_path)
		if ps == null:
			push_error("cannot load " + _scene_path)
			quit(1)
			return
		_main = ps.instantiate()
		root.add_child(_main)
		call_deferred("_after_ready")


func _after_ready() -> void:
	if _toast and _main != null and _main.has_method("_toast"):
		_main.call("_toast", "СОЕДИНЕНИЕ УСТАНОВЛЕНО · договор_11.doc", "success")
		_main.call("_toast", "КАПАЛ 45% · БУФЕР 3/4", "warn")
	if not _folder.is_empty() and _main != null:
		if _main.has_method("_on_folder_selected"):
			_main.call("_on_folder_selected", _folder)
	if _hover.x >= 0.0:
		await create_timer(0.15).timeout
		Input.warp_mouse(_hover)
	if _press.x >= 0.0:
		await create_timer(0.15).timeout
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		ev.position = _press
		ev.global_position = _press
		Input.parse_input_event(ev)
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


func _process(_delta: float) -> bool:
		_wait -= 1
		if _wait > 0:
			return false
		var img := root.get_texture().get_image()
		img.save_png(_out)
		print("saved ", _out, " ", img.get_size())
		quit()
		return true


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

