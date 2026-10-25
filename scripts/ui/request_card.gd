class_name RequestCard
extends Control
## Карточка запроса клиента 400×128 (v3).
##
## Сетка 2×2 обязательных файлов (конкретные REQUIRED-id из main), счётчик
## «ПРИКРЕПЛЕНО X/Y», прогноз мини-игры (Economy.send_minigame_for по типам
## обязательных файлов) и явные кнопки СОЕДИНИТЬСЯ/ОТПРАВИТЬ, ОТКРЕПИТЬ,
## ОТКЛОНИТЬ. Наведение на чип показывает полное имя файла и папку, где он
## лежит, в подсказке и строке внутри карточки. Атак/фишинга в карточке нет.

signal send_pressed(id: String)
signal protocol_toggle_requested(id: String)
signal reject_pressed(id: String)
signal file_dropped(request_id: String, slot_index: int, payload: Dictionary)
signal detach_pressed(request_id: String, slot_index: int)
## Legacy: соединение удалено. Сигнал оставлен, чтобы старые подписи не падали.
signal connect_pressed(id: String)

const CARD := Vector2(400, 128)
const ECONOMY := preload("res://scripts/core/economy.gd")
const SLOT_MAX := 4
## Сетка 2×2: шаг 90×28, чип 86×26. Правый столбец (196..392) — счётчик,
## прогноз и строка состояния.
const SLOT_X := 8.0
const SLOT_STEP_X := 90.0
const SLOT_Y := 30.0
const SLOT_STEP_Y := 28.0
const SLOT_W := 86.0
const SLOT_H := 26.0
const PROTO_RECT := Rect2(178, 6, 44, 16)
## Полоса полного имени при наведении на чип: правый верх, над счётчиком.
const HOVER_STRIP := Rect2(196, 17, 196, 13)
## Если имя и папка не влезают в одну строку — полоса выше на 9 px, папка
## идёт второй мелкой строкой. Счётчик «ПРИКРЕПЛЕНО» в этот момент не рисуем:
## на его месте оказывается вторая строка полосы.
const HOVER_STRIP_TALL := 22.0
const HOVER_FOLDER_SIZE := 7
## Пояснение к исчезновению файлов после отправки (§2.8).
const SEND_HINT := "После успешной отправки файлы списываются."

## Имена игр — только запасной вариант, если Data.minigame_def недоступен.
const FALLBACK_NAMES := {
	"dots": "ОДНА ЛИНИЯ",
	"sound": "УРОВНИ",
	"text": "ЧУЖОЕ СЛОВО",
	"video": "РАСКАДРОВКА",
	"photo": "КАДР",
	"maze": "ЛАБИРИНТ",
}

var id := ""
var client_name := ""
var client_id := ""
var protocol := "TCP"
var slots: Array = []
var required_count := 0
var time_left := 30.0
var time_total := 30.0
var progress := 0.0
var queued := false
var sending := false
var minigame_active := false
## TCP-соединение: идёт мини-игра соединения / соединение уже установлено.
var connecting := false
var connected := false
## Готовность контейнера (HourDirector.is_request_ready): файлы собраны.
var send_ready := false
var send_sum := 0
var minigame_id := ""
var minigame_tier := 0

var hovered := false:
	set(v):
		hovered = v
		queue_redraw()

var _send_btn: Button90
var _detach_btn: Button90
var _reject_btn: Button90
var _blink := 0.0
var _blink_on := true
var _hover_slot := -1
var _drop_slot := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = false
	custom_minimum_size = CARD
	if size == Vector2.ZERO:
		size = CARD
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	mouse_entered.connect(func() -> void: hovered = true)
	mouse_exited.connect(func() -> void:
		hovered = false
		_set_hover_slot(-1))

	_send_btn = _make_button("ОТПРАВИТЬ", Vector2(8, 104), Vector2(92, 18), true)
	_send_btn.pressed.connect(func() -> void:
		if can_send():
			send_pressed.emit(id))
	_detach_btn = _make_button("ОТКРЕПИТЬ", Vector2(104, 104), Vector2(86, 18), false)
	_detach_btn.pressed.connect(func() -> void:
		var index := _last_attached_index()
		if index >= 0:
			detach_pressed.emit(id, index))
	_reject_btn = _make_button("ОТКЛОНИТЬ", Vector2(194, 104), Vector2(90, 18), false)
	_reject_btn.danger = true
	_reject_btn.pressed.connect(func() -> void: reject_pressed.emit(id))
	set_process(true)
	_update_buttons()


func _make_button(caption: String, pos: Vector2, sz: Vector2, accent: bool) -> Button90:
	var b := Button90.new()
	b.caption = caption
	b.caption_size = 10
	b.accent = accent
	b.position = pos
	b.size = sz
	b.mouse_entered.connect(func() -> void: _set_hover_slot(-1))
	add_child(b)
	return b


## Совместимые первые 16 аргументов v2 + TCP-состояние.
func setup(p_id: String, p_client: String, p_client_id: String, p_proto: String,
		p_slots: Array, p_left: float, p_total: float, p_progress: float = 0.0,
		p_required: int = 0, p_queued: bool = false, p_sending: bool = false,
		p_send_sum: int = 0, p_minigame_id: String = "", p_minigame_tier: int = 0,
		p_minigame_active: bool = false, p_ready: bool = false,
		p_connecting: bool = false, p_connected: bool = false) -> void:
	id = p_id
	client_name = p_client
	client_id = p_client_id
	protocol = str(p_proto).to_upper()
	if protocol != "UDP":
		protocol = "TCP"
	slots = p_slots.duplicate(true) if p_slots is Array else []
	var req := clampi(int(p_required), 0, SLOT_MAX)
	if req > 0:
		required_count = req
	elif not slots.is_empty():
		required_count = mini(slots.size(), SLOT_MAX)
	else:
		required_count = 0
	time_left = p_left
	time_total = p_total
	progress = clampf(p_progress, 0.0, 1.0)
	queued = p_queued
	sending = p_sending
	minigame_active = p_minigame_active
	connecting = p_connecting
	connected = p_connected
	send_ready = p_ready
	send_sum = int(p_send_sum)
	minigame_id = str(p_minigame_id)
	minigame_tier = int(p_minigame_tier)
	# Слот наведения переживает ежеминутные (покадровые) обновления карточки:
	# иначе полоса с именем/папкой успевала показаться лишь на один кадр.
	if _hover_slot >= required_count:
		_hover_slot = -1
	_refresh_tooltip()
	custom_minimum_size = CARD
	if size == Vector2.ZERO:
		size = CARD
	_update_buttons()
	queue_redraw()


func _update_buttons() -> void:
	if _send_btn != null:
		var caption := _send_caption()
		if _send_btn.caption != caption:
			_send_btn.caption = caption
		_send_btn.disabled = not can_send()
		if can_send():
			_send_btn.tooltip_text = ("Провести соединение, затем отправить" \
				if protocol == "TCP" and not connected else "Отправить контейнер") \
				+ "\n" + SEND_HINT
		else:
			_send_btn.tooltip_text = _send_disabled_reason() + "\n" + SEND_HINT
	if _detach_btn != null:
		_detach_btn.disabled = attached_count() <= 0 or sending or minigame_active \
			or queued or connecting
	if _reject_btn != null:
		_reject_btn.disabled = sending


## Текст главной кнопки: TCP без соединения сначала соединяется.
func _send_caption() -> String:
	if connecting:
		return "СОЕДИНЕНИЕ…"
	if protocol == "TCP" and not connected:
		return "СОЕДИНИТЬСЯ"
	return "ОТПРАВИТЬ"


func ratio() -> float:
	if time_total <= 0.0:
		return 0.0
	return clampf(time_left / time_total, 0.0, 1.0)


func attached_count() -> int:
	var n := 0
	for i in mini(required_count, slots.size()):
		if _slot_attached(i):
			n += 1
	return n


func _lost_count() -> int:
	var n := 0
	for i in required_count:
		if _slot_missing(i):
			n += 1
	return n


## Все обязательные файлы прикреплены и нет блокирующего состояния.
## TCP-соединение проверяет backend: кнопка остаётся доступной, чтобы
## игрок мог нажать её и пройти мини-игру соединения.
func can_send() -> bool:
	if required_count <= 0:
		return false
	if connecting or sending or queued or minigame_active:
		return false
	return attached_count() >= required_count


func send_disabled() -> bool:
	return _send_btn != null and _send_btn.disabled


func _send_disabled_reason() -> String:
	if connecting:
		return "Идёт соединение…"
	if sending:
		return "Отправка уже идёт"
	if queued:
		return "Ожидание свободного слота"
	if minigame_active:
		return "Сначала завершите мини-игру"
	if required_count <= 0:
		return "Нет обязательных файлов"
	if _lost_count() > 0:
		return "Обязательный файл потерян"
	if attached_count() < required_count:
		return "Прикрепите файлы: %d из %d" % [attached_count(), required_count]
	return "Отправка недоступна"


## Предсказание мини-игры: сумма коэффициентов → игра и ступень (§6).
## Считается по типам ОБЯЗАТЕЛЬНЫХ файлов, поэтому видно ещё до прикрепления.
## Если main передал send_sum/minigame_id, они приоритетнее локального расчёта.
func prediction() -> Dictionary:
	var types: Array = []
	for i in required_count:
		if _slot_missing(i):
			continue
		var data: Variant = _slot_data(i)
		if data is Dictionary:
			var t := str((data as Dictionary).get("type", ""))
			if not t.is_empty():
				types.append(t)
	var pick: Dictionary = ECONOMY.selection_for_sum(send_sum) if send_sum > 0 \
		else ECONOMY.send_minigame_for(types)
	var game := str(pick.get("id", "dots"))
	# В карточке только игры ОТПРАВКИ: у них три ступени (атаки не показываем).
	var tier := clampi(int(pick.get("tier", 1)), 1, 3)
	var sum := int(pick.get("sum", 0))
	if not minigame_id.is_empty():
		# Мини-игра уже активна: показываем выбор директора, не пересчитываем.
		game = minigame_id
		if minigame_tier > 0:
			tier = clampi(minigame_tier, 1, 3)
		if send_sum > 0:
			sum = send_sum
	return {
		"sum": sum,
		"index": int(pick.get("index", 0)),
		"id": game,
		"name": _game_name(game),
		"tier": tier,
	}


func minigame_text() -> String:
	var p := prediction()
	if int(p.get("sum", 0)) <= 0 and minigame_id.is_empty():
		return "МИНИ-ИГРА: —"
	return "МИНИ-ИГРА: %s · T%d" % [str(p.get("name", "")),
		clampi(int(p.get("tier", 1)), 1, 3)]


## Сумма коэффициентов типов обязательных файлов — «чем больше, тем сложнее».
## Не путать со ступенью T1..T3: она уже показана в строке мини-игры выше.
func difficulty_text() -> String:
	return "СУММА: %d" % int(prediction().get("sum", 0))


func _game_name(game_id: String) -> String:
	var data := get_node_or_null("/root/Data")
	if data != null and data.has_method("minigame_def"):
		var def: Dictionary = data.call("minigame_def", game_id)
		var name_ru := str(def.get("name_ru", ""))
		if not name_ru.is_empty():
			return name_ru.to_upper()
	return str(FALLBACK_NAMES.get(game_id, game_id.to_upper()))


func _process(delta: float) -> void:
	_blink += delta
	var on := int(_blink * 2.0) % 2 == 0
	if on != _blink_on:
		_blink_on = on
		queue_redraw()


# --- слоты -----------------------------------------------------------------

func _slot_data(i: int) -> Variant:
	if i < 0 or i >= slots.size():
		return null
	return slots[i]


func _slot_attached(i: int) -> bool:
	var data: Variant = _slot_data(i)
	return data is Dictionary and bool((data as Dictionary).get("attached", false))


## Слот обязателен, но файла в реестре нет. null внутри required-диапазона —
## тоже потерянный файл (main может отдать null либо name = "ПОТЕРЯН").
func _slot_missing(i: int) -> bool:
	if i < 0 or i >= required_count:
		return false
	var data: Variant = _slot_data(i)
	if data == null:
		return true
	if data is Dictionary:
		var d: Dictionary = data
		if bool(d.get("missing", false)):
			return true
		return str(d.get("name", "")) == "ПОТЕРЯН"
	return true


func _slot_status(i: int) -> String:
	if _slot_missing(i):
		return "ПОТЕРЯН"
	if _slot_attached(i):
		return "ПРИКРЕПЛЁН"
	return "ОБЯЗАТЕЛЕН"


func _display_name(data: Dictionary) -> String:
	var nm := str(data.get("name", ""))
	var e := str(data.get("ext", ""))
	if e.is_empty():
		return nm
	return "%s.%s" % [nm, e]


func _slot_full_label(i: int) -> String:
	if _slot_missing(i):
		return "ПОТЕРЯН · ФАЙЛ · ПОТЕРЯН · папка: —"
	var data: Variant = _slot_data(i)
	if not (data is Dictionary):
		return ""
	var d: Dictionary = data
	var line := "%s · %s · %s" % [_display_name(d),
		FileCard.type_title(str(d.get("type", "text"))), _slot_status(i)]
	var folder := _slot_folder(i)
	if not folder.is_empty():
		line += " · папка: " + folder
	return line


## Папка, где сейчас лежит обязательный файл ("" — неизвестна или файла нет).
func _slot_folder(i: int) -> String:
	if _slot_missing(i):
		return ""
	var data: Variant = _slot_data(i)
	if not (data is Dictionary):
		return ""
	return str((data as Dictionary).get("folder", "")).strip_edges()


## Только имя файла — для полосы внутри карточки (тип/статус остаются в tooltip).
func _slot_name_only(i: int) -> String:
	if _slot_missing(i):
		return "ПОТЕРЯН"
	var data: Variant = _slot_data(i)
	if not (data is Dictionary):
		return ""
	return _display_name(data)


func _slot_rect(i: int) -> Rect2:
	return Rect2(SLOT_X + float(i % 2) * SLOT_STEP_X,
		SLOT_Y + floorf(float(i) / 2.0) * SLOT_STEP_Y, SLOT_W, SLOT_H)


## Кегль имени в чипе: 10 px; 9 — только если это позволяет показать имя
## целиком. Длинное имя остаётся 10 px одной строкой с многоточием (полное
## имя показывает полоса наведения).
func _chip_name_size(f: Font, name_text: String, width: float) -> int:
	if f.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x <= width:
		return 10
	if f.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x <= width:
		return 9
	return 10


## Кегль подписи типа/статуса: 8 px, если влезает, иначе прежние 7.
func _chip_sub_size(f: Font, text: String, width: float) -> int:
	if f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x <= width:
		return 8
	return 7


func _slot_at(pos: Vector2) -> int:
	for i in required_count:
		if _slot_rect(i).has_point(pos):
			return i
	return -1


## Первый слот, в который реально можно прикрепить файл: обязательный, ещё
## не занятый и не потерянный. -1 — свободных нет (подсветку не рисуем).
func _first_empty() -> int:
	for i in required_count:
		if _slot_data(i) != null and not _slot_attached(i) and not _slot_missing(i):
			return i
	return -1


func _last_attached_index() -> int:
	for i in range(mini(required_count, slots.size()) - 1, -1, -1):
		if _slot_attached(i):
			return i
	return -1


# --- отрисовка -------------------------------------------------------------

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var f := Theme90.ui()
	var bg := Theme90.WHITE if hovered else Theme90.PAPER_HI
	var border := Theme90.ACCENT_LIGHT if hovered else Theme90.BORDER
	draw_style_box(Theme90.box(bg, border, 4, 1,
		Color(0, 0, 0, 0.11) if hovered else Theme90.SHADOW), r)

	_draw_avatar(Rect2(8, 6, 20, 20))

	Theme90.text(self, f, Vector2(32, 4), Theme90.fit(f, client_name, 12, 140), 12,
		Theme90.INK, 140)
	Theme90.text(self, f, Vector2(32, 18), Theme90.fit(f, client_id, 9, 140), 9,
		Theme90.SHADE, 140)

	_draw_protocol_chip(f)
	_draw_timer(f)

	var count := required_count if required_count > 0 else 1
	for i in count:
		_draw_slot(i, f)

	# Полное имя файла и папка — поверх правой части шапки, только при наведении на чип.
	var tall_strip := _hover_slot >= 0 and _hover_strip_tall(f)
	if not tall_strip:
		_draw_counter(f)
	_draw_prediction(f)
	if _hover_slot >= 0:
		_draw_hover_strip(f, tall_strip)

	if hovered and _drop_slot < 0:
		draw_style_box(Theme90.box(Color(0, 0, 0, 0), Theme90.ACCENT_LIGHT, 4, 1),
			r.grow(-1.0))
	if _drop_slot >= 0:
		Theme90.draw_dashed_box(self, Rect2(2, 2, size.x - 4, size.y - 4),
			Theme90.ACCENT, 4.0, 1.2)


func _draw_protocol_chip(f: Font) -> void:
	var locked := connected
	var pcol := Theme90.SHADE if locked else (Theme90.NAVY if protocol == "TCP" else Theme90.WARN)
	draw_style_box(Theme90.box(Color(pcol.r, pcol.g, pcol.b, 0.13),
		Color(pcol.r, pcol.g, pcol.b, 0.45), 3, 1), PROTO_RECT)
	Theme90.text_vcenter(self, f, PROTO_RECT, protocol, 10, pcol, -1,
		HORIZONTAL_ALIGNMENT_CENTER)
	if locked:
		_draw_lock(Vector2(PROTO_RECT.end.x - 5, PROTO_RECT.get_center().y), pcol)
	else:
		Theme90.draw_chevron(self, Vector2(PROTO_RECT.end.x - 5, PROTO_RECT.get_center().y),
			2, pcol, 2.0, 1.0)


func _draw_lock(center: Vector2, col: Color) -> void:
	draw_rect(Rect2(center.x - 2.5, center.y, 5.0, 4.0), col, true)
	draw_arc(Vector2(center.x, center.y), 2.0, PI, TAU, 6, col, 1.0, true)


func _draw_timer(f: Font) -> void:
	var label := "ОСТАЛОСЬ"
	var value := "%d с" % int(ceilf(time_left))
	var col := _time_color()
	if connecting:
		label = "СОСТОЯНИЕ"
		value = "СВЯЗЬ…"
		col = Theme90.WARN
	elif sending:
		label = "ОТПРАВКА"
		value = "%d%%" % int(roundf(progress * 100.0))
		col = Theme90.ACCENT
	elif queued:
		label = "СЛОТ"
		value = "ОЖИДАНИЕ"
		col = Theme90.WARN
	elif minigame_active:
		label = "СОСТОЯНИЕ"
		value = "МИНИ-ИГРА"
		col = Theme90.ACCENT
	Theme90.text(self, f, Vector2(232, 4), label, 9, Theme90.SHADE)
	var vw := f.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	Theme90.text(self, f, Vector2(392 - vw, 3), value, 10, col)
	var fill := progress if sending else ratio()
	Theme90.draw_meter(self, Rect2(232, 19, 152, 4), fill,
		Theme90.ACCENT if sending else col)


func _draw_counter(f: Font) -> void:
	var have := attached_count()
	var cap := maxi(required_count, 0)
	var col := Theme90.SUCCESS if cap > 0 and have >= cap else Theme90.DARK
	if _lost_count() > 0:
		col = Theme90.ERROR
	Theme90.text(self, f, Vector2(196, 32), "ПРИКРЕПЛЕНО %d/%d" % [have, cap], 11,
		col, 196)


func _draw_prediction(f: Font) -> void:
	var p := prediction()
	Theme90.text(self, f, Vector2(196, 50), Theme90.fit(f, minigame_text(), 10, 196), 10,
		Theme90.NAVY, 196)
	Theme90.text(self, f, Vector2(196, 64), "СУММА: %d" % int(p.get("sum", 0)), 9,
		Theme90.DARK, 196)

	var hint := ""
	var hcol := Theme90.WARN
	if connecting:
		hint = "УСТАНОВКА СОЕДИНЕНИЯ"
		hcol = Theme90.WARN
	elif queued:
		hint = "ОЖИДАНИЕ СЛОТА"
	elif sending:
		hint = "ПЕРЕДАЧА ИДЁТ"
		hcol = Theme90.ACCENT
	elif minigame_active:
		hint = "ИДЁТ МИНИ-ИГРА"
		hcol = Theme90.ACCENT
	elif _lost_count() > 0:
		hint = "ПОТЕРЯН ФАЙЛ"
		hcol = Theme90.ERROR
	elif _blink_on and attached_count() < required_count:
		hint = "НУЖНО ФАЙЛОВ: %d" % maxi(0, required_count - attached_count())
	elif protocol == "TCP" and not connected:
		hint = "СНАЧАЛА СОЕДИНЕНИЕ"
		hcol = Theme90.SHADE
	if not hint.is_empty():
		Theme90.text(self, f, Vector2(196, 76), Theme90.fit(f, hint, 9, 196), 9, hcol, 196)


## Кегль имени в полосе: длинные имена уменьшаем на 1 px, чтобы показать целиком.
func _hover_text_size(f: Font, name_text: String) -> int:
	var inner := HOVER_STRIP.size.x - 10.0
	if f.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x > inner:
		return 8
	return 9


## Влезают ли имя и папка в одну строку полосы при текущем кегле.
func _hover_strip_tall(f: Font) -> bool:
	var folder := _slot_folder(_hover_slot)
	if folder.is_empty():
		return false
	var name_text := _slot_name_only(_hover_slot)
	if name_text.is_empty():
		return false
	var inner := HOVER_STRIP.size.x - 10.0
	var line := "%s · %s" % [name_text, folder]
	return f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1,
		_hover_text_size(f, name_text)).x > inner


func _draw_hover_strip(f: Font, tall: bool) -> void:
	var name_text := _slot_name_only(_hover_slot)
	if name_text.is_empty():
		return
	var border := Theme90.ACCENT_LIGHT
	if _slot_missing(_hover_slot):
		border = Theme90.ERROR
	elif _slot_attached(_hover_slot):
		border = Theme90.SUCCESS
	var text_size := _hover_text_size(f, name_text)
	var inner := HOVER_STRIP.size.x - 10.0
	var folder := _slot_folder(_hover_slot)
	if not tall:
		# Всё влезло в одну строку: имя и папка через « · ».
		var line := name_text if folder.is_empty() \
			else "%s · %s" % [name_text, folder]
		draw_style_box(Theme90.box(Theme90.WHITE, border, 3, 1), HOVER_STRIP)
		Theme90.text_vcenter(self, f, HOVER_STRIP,
			Theme90.fit(f, line, text_size, inner), text_size, Theme90.INK,
			inner, HORIZONTAL_ALIGNMENT_LEFT, 5.0)
		return
	# Полоса на строку выше: имя сверху, папка — мелкой второй строкой. Счётчик
	# «ПРИКРЕПЛЕНО» на это время не рисуется (_draw), иначе строки наложатся.
	var strip := Rect2(HOVER_STRIP.position,
		Vector2(HOVER_STRIP.size.x, HOVER_STRIP_TALL))
	draw_style_box(Theme90.box(Theme90.WHITE, border, 3, 1), strip)
	var name_rect := Rect2(strip.position, Vector2(strip.size.x, HOVER_STRIP.size.y))
	Theme90.text_vcenter(self, f, name_rect,
		Theme90.fit(f, name_text, text_size, inner), text_size, Theme90.INK,
		inner, HORIZONTAL_ALIGNMENT_LEFT, 5.0)
	var folder_rect := Rect2(strip.position + Vector2(0, 12),
		Vector2(strip.size.x, HOVER_STRIP_TALL - 12.0))
	Theme90.text_vcenter(self, f, folder_rect,
		Theme90.fit(f, "папка: " + folder, HOVER_FOLDER_SIZE, inner),
		HOVER_FOLDER_SIZE, Theme90.SHADE, inner, HORIZONTAL_ALIGNMENT_LEFT, 5.0)


func _time_color() -> Color:
	if queued or connecting:
		return Theme90.WARN
	if ratio() < 0.2:
		return Theme90.ERROR
	if ratio() < 0.5:
		return Theme90.WARN
	return Theme90.SUCCESS


func _draw_avatar(r: Rect2) -> void:
	var bg := Theme90.ACCENT
	draw_style_box(Theme90.box(bg, Color(0, 0, 0, 0), 5, 0), r)
	var f := Theme90.ui()
	Theme90.text(self, f, Vector2(r.position.x, r.position.y + 3), _monogram(), 12,
		Theme90.WHITE, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	draw_circle(Vector2(r.end.x - 3, r.end.y - 3), 2.5, Theme90.PAPER_HI)
	draw_circle(Vector2(r.end.x - 3, r.end.y - 3), 1.6, Theme90.SUCCESS)


func _monogram() -> String:
	var parts := client_name.replace("«", " ").replace("»", " ").split(" ", false)
	if parts.is_empty():
		return "?"
	var last := str(parts[parts.size() - 1])
	if last.length() == 0:
		return "?"
	return last.substr(0, 1).to_upper()


func _draw_slot(i: int, f: Font) -> void:
	var cell := _slot_rect(i)
	if required_count <= 0:
		_draw_empty_slot(cell, i)
		return
	if _slot_missing(i):
		_draw_missing_slot(cell, i, f)
		return
	var data: Dictionary = _slot_data(i)
	var t := str(data.get("type", "text"))
	var col := FileCard.type_color(t)
	var attached := _slot_attached(i)
	var hov := _hover_slot == i
	var border: Color
	var fill: Color
	if attached:
		fill = Theme90.WHITE
		border = Theme90.ACCENT.lightened(0.16) if hov else Theme90.ACCENT
		draw_style_box(Theme90.box(fill, border, 3, 1), cell)
	else:
		# Ждём файл: приглушённая заливка и пунктир в цвете типа.
		fill = Theme90.PAPER
		border = Theme90.ACCENT_LIGHT if hov else Color(col.r, col.g, col.b, 0.62)
		draw_style_box(Theme90.box(fill, Color(0, 0, 0, 0), 3, 0), cell)
		Theme90.draw_dashed_box(self, cell, border, 3.0, 1.0)
	# Иконка файла слева; если текстуры нет — прежняя цветная полоса типа.
	var icon_drawn := false
	if not t.is_empty():
		icon_drawn = Theme90.draw_file_icon(self, Rect2(
			cell.position + Vector2(4, 4), Vector2(12, 12)), t)
	if not icon_drawn:
		draw_rect(Rect2(cell.position.x + 1, cell.position.y + 4, 3, cell.size.y - 8), col)

	var text_x := 8.0 + (16.0 if icon_drawn else 0.0)
	var name_w := SLOT_W - text_x - 6.0
	if attached:
		name_w -= 8.0
	var full_name := _display_name(data)
	var name_size := _chip_name_size(f, full_name, name_w)
	var nm := Theme90.fit(f, full_name, name_size, name_w)
	Theme90.text(self, f, Vector2(cell.position.x + text_x, cell.position.y + 2), nm,
		name_size, Theme90.INK, name_w)
	var sub := FileCard.type_title(t)
	var sub_col := Theme90.SHADE
	if not attached:
		sub = "ЖДЁМ"
		sub_col = Theme90.WARN
	var sub_w := SLOT_W - text_x - 4.0
	Theme90.text(self, f, Vector2(cell.position.x + text_x, cell.position.y + 15), sub,
		_chip_sub_size(f, sub, sub_w), sub_col, sub_w)
	if attached:
		Theme90.draw_check_badge(self, Vector2(cell.end.x - 7, cell.position.y + 7), 4.5)
	if _drop_slot == i:
		Theme90.draw_dashed_box(self, cell.grow(1), Theme90.ACCENT, 2.5, 1.4)


func _draw_missing_slot(cell: Rect2, i: int, f: Font) -> void:
	var hov := _hover_slot == i
	var border := Theme90.ERROR.lightened(0.2) if hov else Theme90.ERROR
	draw_style_box(Theme90.box(Color(Theme90.ERROR.r, Theme90.ERROR.g, Theme90.ERROR.b, 0.06),
		border, 3, 1), cell)
	draw_rect(Rect2(cell.position.x + 1, cell.position.y + 4, 3, cell.size.y - 8),
		Theme90.ERROR)
	Theme90.text(self, f, Vector2(cell.position.x + 8, cell.position.y + 2), "ПОТЕРЯН",
		_chip_name_size(f, "ПОТЕРЯН", SLOT_W - 14.0), Theme90.ERROR, SLOT_W - 14.0)
	Theme90.text(self, f, Vector2(cell.position.x + 8, cell.position.y + 15), "НЕТ ФАЙЛА",
		_chip_sub_size(f, "НЕТ ФАЙЛА", SLOT_W - 14.0),
		Color(Theme90.ERROR.r, Theme90.ERROR.g, Theme90.ERROR.b, 0.8), SLOT_W - 14.0)
	if _drop_slot == i:
		Theme90.draw_dashed_box(self, cell.grow(1), Theme90.ACCENT, 2.5, 1.4)


func _draw_empty_slot(cell: Rect2, i: int) -> void:
	var f := Theme90.ui()
	Theme90.draw_dashed_box(self, cell, Color(Theme90.SHADE.r, Theme90.SHADE.g,
		Theme90.SHADE.b, 0.55), 2.5, 1.0)
	Theme90.text(self, f, Vector2(cell.position.x + 5, cell.position.y + 5), "+",
		12, Theme90.SHADE)
	if _blink_on:
		Theme90.text(self, f, Vector2(cell.position.x + 16, cell.position.y + 7),
			"ожидается", 9, Theme90.WARN, SLOT_W - 18.0)
	if _drop_slot == i:
		Theme90.draw_dashed_box(self, cell.grow(1), Theme90.ACCENT, 2.5, 1.4)


# --- подсказки и ввод ------------------------------------------------------

func _default_tooltip() -> String:
	return "%s · %s\n%s" % [client_name, client_id, SEND_HINT]


func _refresh_tooltip() -> void:
	if _hover_slot >= 0 and _hover_slot < required_count:
		var line := _slot_full_label(_hover_slot)
		if not line.is_empty():
			tooltip_text = line
			return
	tooltip_text = _default_tooltip() + \
		"\nСумма коэффициентов файлов: чем выше, тем сложнее мини-игра"


func _set_hover_slot(index: int) -> void:
	if index == _hover_slot:
		return
	_hover_slot = index
	_refresh_tooltip()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_set_hover_slot(_slot_at(event.position))
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if PROTO_RECT.has_point(event.position):
			if not connected and not connecting:
				protocol_toggle_requested.emit(id)
			accept_event()
			return
		var i := _slot_at(event.position)
		if i >= 0:
			if event.double_click and _slot_attached(i):
				detach_pressed.emit(id, i)
			accept_event()
			return
		accept_event()


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	if str(data.get("kind", "")) != "file":
		return false
	# Файл со стола сортировки в запрос прикреплять нельзя (§4.7).
	if str(data.get("from", "")) == "table":
		return false
	var i := _slot_at(at_position)
	if i < 0:
		i = _first_empty()
	# Свободного слота может не быть (-1): подсветку не рисуем, но дроп
	# разрешаем — соответствие обязательному файлу проверит backend.
	_drop_slot = i if i >= 0 else -1
	var dc := _drag_controller()
	if dc != null:
		dc.set_mode("square")
	queue_redraw()
	return true


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var i := _slot_at(at_position)
	if i < 0:
		i = _first_empty()
	_drop_slot = -1
	queue_redraw()
	file_dropped.emit(id, i, data)


func _drag_controller() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group("drag_controller")


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_drop_slot = -1
		queue_redraw()
