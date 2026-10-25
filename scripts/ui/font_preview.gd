extends Control
## Превью типографики и стиля (dev/design-артефакт, не часть игры).
##
## Проверяет кириллицу Handjet на обязательных строках интерфейса,
## показывает кегли 10/12/16/24, цифры Press Start 2P, палитру и фаски.
## Открыть: godot --path . scenes/ui/font_preview.tscn

func _ready() -> void:
	custom_minimum_size = Vector2(1280, 720)
	var frame := WindowFrame.new()
	frame.title = "ТИПОГРАФИКА · ПАЛИТРА · ФАСКИ"
	frame.title_hint = "STYLE GUIDE 1997"
	frame.icon_kind = "app"
	frame.title_size = 12
	frame.accent_line = true
	add_child(frame)
	frame.position = Vector2(16, 16)
	frame.size = Vector2(1248, 688)
	var spec := Specimen.new()
	frame.content.add_child(spec)
	spec.position = Vector2.ZERO
	spec.size = frame.content.size


func _draw() -> void:
	draw_texture_rect(Theme90.dither_texture(), Rect2(Vector2.ZERO, size), true)
	draw_rect(Rect2(0, 0, size.x, 1), Theme90.SHADE)
	draw_rect(Rect2(0, 0, 1, size.y), Theme90.SHADE)
	draw_rect(Rect2(size.x - 1, 0, 1, size.y), Theme90.FACE_HI)
	draw_rect(Rect2(0, size.y - 1, size.x, 1), Theme90.FACE_HI)


class Specimen:
	extends Control

	var _cards: Array[FileCard] = []
	var _check: Check90

	func _ready() -> void:
		var fc := FileCard.new()
		add_child(fc)
		fc.setup("demo", "отчёт_смены", "xls", 148, "text", "attached")
		fc.position = Vector2(560, 318)
		fc.size = Vector2(132, 84)
		_cards.append(fc)
		var fc2 := FileCard.new()
		add_child(fc2)
		fc2.setup("demo2", "промо_ролик", "avi", 8800, "video", "malicious")
		fc2.position = Vector2(704, 318)
		fc2.size = Vector2(132, 84)
		_cards.append(fc2)
		_check = Check90.new()
		add_child(_check)
		_check.caption = "СКРЫТЬ СЛУЖЕБНЫЕ"
		_check.position = Vector2(640, 594)
		_check.size = Vector2(160, 14)
		_check.button_pressed = true
		_check.checked = true

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Theme90.FACE)
		var f := Theme90.ui()
		var w := size.x
		_col_font(f)
		_col_numbers(f)
		_col_palette(f)
		_row_controls(f, w)


	# --- колонка 1: шрифт
	func _col_font(f: Font) -> void:
		var x := 16.0
		var y := 10.0
		_section(x, y, 520.0, "ШРИФТ · HANDJET (wght 700, ELGR 2, ELSH 2)")

		Theme90.text(self, f, Vector2(x, 40), "ПРИЁМ · ОТПРАВКА", 24, Theme90.INK)
		Theme90.text(self, f, Vector2(x, 78), "СОЕДИНИТЬСЯ", 16, Theme90.NAVY)
		Theme90.text(self, f, Vector2(x, 104), "Папка заполнена", 12, Theme90.INK)
		Theme90.text(self, f, Vector2(x, 122), "ООО «Вектор» · cl-4217 · 3/16", 12, Theme90.INK)
		Theme90.text(self, f, Vector2(x, 142), REQUIRED_STR, 10, Theme90.DARK)

		var sizes := [24, 16, 12, 10]
		var sy := 170.0
		for s in sizes:
			Theme90.num_line(self, Vector2(x, sy), str(s), 8, Theme90.SHADE)
			Theme90.text(self, f, Vector2(x + 34, sy), "Съешь ещё этих мягких булок — 0123456789", s, Theme90.INK)
			draw_rect(Rect2(x, sy + 20, 500, 1), Theme90.SHADE)
			sy += 38.0

		# кнопка-образец
		var bx := x
		var by := sy + 8
		for st in 4:
			var br := Rect2(bx, by, 118, 24)
			var pressed := st == 1
			var disabled := st == 3
			Theme90.draw_bevel(self, br, pressed, Theme90.BEVEL, Theme90.FACE)
			var fg := Theme90.INK
			if st == 2:
				Theme90.draw_bevel(self, br.grow(-2), true, 1.0, Theme90.FACE_HI)
				fg = Theme90.NAVY
			if disabled:
				fg = Theme90.SHADE
			Theme90.text_vcenter(self, f, br, "СОЕДИНИТЬСЯ", 10, fg, -1, HORIZONTAL_ALIGNMENT_CENTER)
			by += 30.0
		var cap := ["NORMAL", "PRESSED", "HOVER", "DISABLED"]
		for i in 4:
			Theme90.text(self, f, Vector2(bx + 126, sy + 16 + i * 30), cap[i], 10, Theme90.DARK)


	# --- колонка 2: цифры
	func _col_numbers(f: Font) -> void:
		var x := 560.0
		var y := 10.0
		_section(x, y, 300.0, "ЦИФРЫ · PRESS START 2P")
		Theme90.text(self, f, Vector2(x, 38), "Ноль Handjet в малых кеглях", 10, Theme90.DARK)
		Theme90.text(self, f, Vector2(x, 52), "неотличим от восьмёрки —", 10, Theme90.DARK)
		Theme90.text(self, f, Vector2(x, 66), "поэтому все числа набраны P2P.", 10, Theme90.DARK)

		Theme90.num_line(self, Vector2(x, 88), "2 / 3", 12, Theme90.INK)
		Theme90.num_line(self, Vector2(x + 120, 88), "45%", 12, Theme90.INK)
		Theme90.num_line(self, Vector2(x + 200, 88), "168 / 200", 12, Theme90.INK)
		Theme90.text(self, f, Vector2(x, 108), "12px · статус-строка", 10, Theme90.SHADE)

		var nums := ["03:42", "2 410", "168/200", "100%", "8 800", "0"]
		var ny := 132.0
		for n in nums:
			Theme90.num_line(self, Vector2(x, ny), n, 8, Theme90.DARK, " · 8px", 10)
			ny += 15.0

		# образец статус-строки
		var bar := Rect2(x, 240, 300, 46)
		Theme90.draw_bevel(self, bar, true, Theme90.BEVEL, Theme90.FACE)
		Theme90.text(self, f, Vector2(bar.position.x + 8, bar.position.y + 5), "БУФЕР ПРИЁМА", 10, Theme90.DARK)
		Theme90.num_line(self, Vector2(bar.position.x + 8, bar.position.y + 19), "3 / 4", 12, Theme90.INK)
		for i in 4:
			var br := Rect2(bar.position.x + 8 + i * 34, bar.position.y + 34, 30, 7)
			draw_rect(br, Theme90.NAVY if i < 3 else Theme90.FACE_LO)
			draw_rect(Rect2(br.position, Vector2(br.size.x, 1)), Theme90.SHADE if i >= 3 else Theme90.NAVY.lightened(0.4))

		# образец файловой карточки
		var cx := x
		var cy := 300.0
		_section(x, cy - 10, 300.0, "КАРТОЧКА ФАЙЛА")
		Theme90.text(self, f, Vector2(cx, cy + 110), "attached / malicious", 10, Theme90.DARK)


	# --- колонка 3: палитра
	func _col_palette(f: Font) -> void:
		var x := 880.0
		var y := 10.0
		_section(x, y, 340.0, "ПАЛИТРА")
		var colors := [
			["PAPER", Theme90.PAPER, "E9E6DD"],
			["PAPER_HI", Theme90.PAPER_HI, "F7F5EE"],
			["SHADE", Theme90.SHADE, "9A958A"],
			["DARK", Theme90.DARK, "2C2A26"],
			["INK", Theme90.INK, "1F1E1B"],
			["NAVY", Theme90.NAVY, "2C5C68"],
			["ERROR", Theme90.ERROR, "C25B4A"],
			["SUCCESS", Theme90.SUCCESS, "3F8F5E"],
			["WARN", Theme90.WARN, "C58A2E"],
			["ACCENT", Theme90.ACCENT, "2F7F8F"],
			["ACCENT_LIGHT", Theme90.ACCENT_LIGHT, "83C7D4"],
			["ACCENT_PALE", Theme90.ACCENT_PALE, "E6F5F7"],
		]
		var cy := 38.0
		for c in colors:
			var sw := Rect2(x, cy, 40, 20)
			draw_rect(sw, c[1])
			draw_rect(sw, Theme90.DARK, false, 1.0)
			Theme90.text(self, f, Vector2(x + 48, cy + 1), str(c[0]), 10, Theme90.INK)
			Theme90.num_line(self, Vector2(x + 150, cy + 1), "#" + str(c[2]), 8, Theme90.DARK)
			cy += 23.0


	# --- нижняя полоса: фаски и иконки
	func _row_controls(f: Font, w: float) -> void:
		var y := size.y - 168.0
		_section(16, y, w - 32, "ФАСКИ · ИКОНКИ · DROP-СОСТОЯНИЯ")

		var samples := [
			["RAISED", false], ["SUNKEN", true],
		]
		var x := 16.0
		for s in samples:
			var r := Rect2(x, y + 34, 120, 46)
			Theme90.draw_bevel(self, r, bool(s[1]), Theme90.BEVEL, Theme90.FACE)
			if s[0] == "RAISED":
				draw_rect(Rect2(r.position + Vector2(2, 2), Vector2(r.size.x - 4, 1)), Theme90.FACE_HI)
			Theme90.text_vcenter(self, f, r, str(s[0]), 10, Theme90.DARK, -1, HORIZONTAL_ALIGNMENT_CENTER)
			x += 132.0

		# типы файлов
		var kinds := [["text", "ТЕКСТ"], ["sound", "ЗВУК"], ["photo", "ФОТО"], ["video", "ВИДЕО"]]
		x = 16.0
		for k in kinds:
			var col: Color = FileCard.type_color(str(k[0]))
			Theme90.draw_doc_icon(self, Rect2(x, y + 96, 24, 24), str(k[0]), col)
			Theme90.text(self, f, Vector2(x + 28, y + 104), str(k[1]), 10, col)
			x += 92.0

		# иконки
		x = 420.0
		Theme90.draw_folder_icon(self, Vector2(x, y + 100), Theme90.WARN, true)
		Theme90.draw_drive_icon(self, Vector2(x + 26, y + 100), Theme90.NAVY)
		Theme90.draw_lock_icon(self, Vector2(x + 50, y + 96), Theme90.DARK)
		Theme90.draw_packet_icon(self, Vector2(x + 72, y + 100), Theme90.NAVY)
		Theme90.draw_arrow(self, Rect2(x + 96, y + 94, 16, 16), 0, Theme90.SUCCESS)
		Theme90.draw_arrow(self, Rect2(x + 116, y + 94, 16, 16), 1, Theme90.NAVY)
		Theme90.draw_x(self, Rect2(x + 136, y + 94, 16, 16), Theme90.ERROR)

		# чекбокс (создан в _ready)
		# drop-подсветка
		var dz := Rect2(820, y + 90, 200, 30)
		Theme90.draw_bevel(self, dz, true, Theme90.BEVEL, Theme90.FACE)
		Theme90.draw_dashed_box(self, dz.grow(-3), Theme90.NAVY, 3.0, 1.0)
		Theme90.text_vcenter(self, f, dz, "DROP: ФАЙЛ → ПАПКА", 10, Theme90.NAVY, -1, HORIZONTAL_ALIGNMENT_CENTER)


	const REQUIRED_STR := "ПРИЁМ · ОТПРАВКА · СОЕДИНИТЬСЯ · Папка заполнена · ООО «Вектор»"

	func _section(x: float, y: float, w: float, title: String) -> void:
		Theme90.text_engraved(self, Theme90.ui(), Vector2(x, y), title, 10)
		draw_rect(Rect2(x, y + 13, w, 1), Theme90.SHADE)
		draw_rect(Rect2(x, y + 14, w, 1), Theme90.LIGHT)
