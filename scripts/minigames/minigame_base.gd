class_name MiniGame
extends Control
## Базовая мини-игра v2: без таймера, локальный сид, quality 0..1.
##
## Окно 640×360. Общая шапка, кнопка «ПРОПУСТИТЬ» с двухкликовым
## подтверждением и экран результата. Конкретные игры наследуются от этого
## класса и переопределяют _setup(), _draw_game(), обработчики ввода.
##
## Важно: здесь нет узлов-таймеров и нет поражения по времени. Игра
## завершается только действием игрока (конечная цель) или пропуском.

signal finished(quality: float)

const WINDOW_SIZE := Vector2(640.0, 360.0)
## Шапка двухстрочная: название + цель игры. Контент мини-игр начинается
## с y=44, поэтому высота 42 не перекрывает жёстко заданные координаты.
const HEADER_H := 42.0
const FOOTER_Y := 320.0
const CONTENT_RECT := Rect2(18.0, 40.0, 604.0, 270.0)
const ACTION_RECT := Rect2(466.0, 320.0, 156.0, 28.0)
const SKIP_RECT := Rect2(18.0, 320.0, 148.0, 28.0)
const CONTINUE_RECT := Rect2(245.0, 252.0, 150.0, 32.0)

const SEND_IDS: Array[String] = [
	"dots", "sound", "text", "video", "photo", "maze",
]
const ATTACK_IDS: Array[String] = [
	"junk", "ddos", "phishing", "ransomware",
]
const GAME_TITLES := {
	"dots": "ОДНА ЛИНИЯ",
	"sound": "УРОВНИ",
	"text": "ЧУЖОЕ СЛОВО",
	"video": "РАСКАДРОВКА",
	"photo": "КАДР",
	"maze": "ЛАБИРИНТ",
	"junk": "ФИЛЬТР",
	"ddos": "ЩИТ",
	"phishing": "ПАСПОРТ",
	"ransomware": "КАРАНТИН",
}
const LEGACY_TYPES := {
	"text": "text",
	"sound": "sound",
	"photo": "photo",
	"video": "video",
	# Старые id «проводов» после удаления игры ведут на ближайшую по смыслу.
	"connection": "dots",
	"connect": "dots",
}
## Короткие цели для игр атак (файлы атак не переопределяют _goal_text).
## Игры отправки возвращают свою строку сами.
const ATTACK_GOALS := {
	"junk": "СНИМИТЕ МУСОРНЫЕ ФАЙЛЫ · НОРМАЛЬНЫЕ НЕ ТРОГАЙТЕ",
	"ddos": "ДВИГАЙТЕ ЩИТ И ОТРАЖАЙТЕ ПАКЕТЫ",
	"phishing": "СВЕРЬТЕ ДАННЫЕ КЛИЕНТА С ЭТАЛОНОМ",
	"ransomware": "ИЗОЛИРУЙТЕ ФАЙЛЫ С ОПАСНЫМ РАСШИРЕНИЕМ",
}

## Общие поля контракта.
var game_id: String = ""
var tier: int = 1
var rng := RandomNumberGenerator.new()
var context: Dictionary = {}
var quality_value: float = 0.0
var running: bool = false
var difficulty: float = 1.0
var seed_value: int = 0
## true для мини-игр атак: кнопка отказа — СДАТЬСЯ, Esc взводит/подтверждает
## сдачу (§5.1/§5.5). Мини-игры отправки оставляют ПРОПУСТИТЬ и Esc — no-op.
var is_attack: bool = false

var _finished: bool = false
var _skip_armed: bool = false
var _result_detail: String = ""
## D2 (§5.5): если true, _finish() только показывает экран результата и НЕ
## эмитит finished. Сигнал уходит по клику «ПРОДОЛЖИТЬ» (Main включает режим
## для модальных мини-игр). unit-тесты без Main работают с default=false.
var defer_finish_signal: bool = false
var _pending_finish: bool = false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	size = WINDOW_SIZE
	custom_minimum_size = WINDOW_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	visible = false
	set_process(true)
	set_process_input(true)


func _ready() -> void:
	_center_on_screen()
	# Main ставит модалку через PRESET_CENTER уже после add_child, а в Godot
	# 4.7.2 этот пресет обнуляет offsets (окно уезжает в правый нижний угол).
	# Повторяем центрирование в конце кадра, когда родитель уже modal_root.
	call_deferred("_center_on_screen")
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_center_on_screen):
		viewport.size_changed.connect(_center_on_screen)


## Совместимая сигнатура со старым main/hour_director:
## start(type_or_id, difficulty, seed, context).
func start(type_or_id: String, p_difficulty: float = 1.0, p_seed: int = 0,
		p_context: Dictionary = {}) -> void:
	var requested := str(type_or_id).to_lower()
	var resolved := resolve_game_id(requested)
	if resolved.is_empty():
		resolved = _own_game_id()
	if resolved.is_empty():
		resolved = requested if not requested.is_empty() else "dots"

	game_id = resolved
	difficulty = maxf(0.0, float(p_difficulty))
	# Старый вызов передавал 2.5 и т.п.; фабрика передаёт 1..3 (отправка)
	# или 1..4 (атаки). Атаки сохраняют четыре ступени.
	var max_tier := 4 if is_attack_id(game_id) else 3
	tier = clampi(int(round(difficulty)), 1, max_tier)
	if difficulty >= 1.0 and difficulty <= 4.0 and is_equal_approx(difficulty, roundf(difficulty)):
		tier = clampi(int(difficulty), 1, max_tier)
	context = p_context.duplicate(true)

	seed_value = p_seed
	if seed_value == 0:
		seed_value = int(Time.get_ticks_usec()) ^ int(hash("%s:%d:%d" % [game_id, tier, Time.get_ticks_msec()]))
	rng = RandomNumberGenerator.new()
	rng.seed = seed_value

	_emitent_reset()
	_setup()
	running = true
	visible = true
	_skip_armed = false
	_result_detail = ""
	set_process(true)
	set_process_input(true)
	_center_on_screen()
	queue_redraw()


## Сброс состояния при повторном start() на том же узле.
func _emitent_reset() -> void:
	_finished = false
	quality_value = 0.0
	_skip_armed = false
	_result_detail = ""
	_pending_finish = false


## Переопределяется наследником: генерация поля/состояния.
func _setup() -> void:
	pass


## База не анимируется; наследники (sound/photo/maze) переопределяют.
func _process(_delta: float) -> void:
	pass


## Идентификатор игры самого класса (нужен для прямого new().start()).
func _own_game_id() -> String:
	return ""


func title() -> String:
	return str(GAME_TITLES.get(game_id, "МИНИ-ИГРА"))


## Максимум ступеней: у отправки три (после удаления T1), у атак четыре.
func max_tier() -> int:
	return 4 if is_attack or is_attack_id(game_id) else 3


func tier_label() -> String:
	return "СЛОЖНОСТЬ %d/%d" % [clampi(tier, 1, max_tier()), max_tier()]


## Подпись кнопки отказа: атаки сдаются, отправки пропускаются.
## Текст с подсказкой «2 клика» добавляется только при отрисовке, чтобы
## контракт skip_label() оставался прежним для тестов и других систем.
func skip_label() -> String:
	return "СДАТЬСЯ" if is_attack else "ПРОПУСТИТЬ"


## Одна строка цели игры под шапкой. Переопределяется наследниками.
func _goal_text() -> String:
	return str(ATTACK_GOALS.get(game_id, ""))


## Прогресс 0..1 для тонкой полосы в шапке; -1 — не показывать.
func _progress_ratio() -> float:
	return -1.0


## Короткая статистика для экрана результата (одна строка).
func _result_stats() -> String:
	return ""


func quality() -> float:
	return quality_value


func is_finished() -> bool:
	return _finished


func verdict_for(q: float) -> String:
	if q >= 0.75:
		return "ЧИСТО"
	if q >= 0.45:
		return "НОРМАЛЬНО"
	return "СЛАБО"


func result_text() -> String:
	return "КАЧЕСТВО %d%% · %s" % [roundi(quality_value * 100.0),
		verdict_for(quality_value)]


## Завершение игры. Эмитит ровно один раз, клампит q в 0..1.
func _finish(q: float) -> void:
	if _finished:
		return
	quality_value = clampf(float(q), 0.0, 1.0)
	_finished = true
	running = false
	set_process(false)
	_skip_armed = false
	if _result_detail.is_empty():
		_result_detail = _default_result_detail()
	_play_sfx(&"minigame_win" if quality_value >= 0.45 else &"minigame_fail")
	if defer_finish_signal:
		# Экран результата уже нарисован; сигнал ждёт «ПРОДОЛЖИТЬ».
		_pending_finish = true
	else:
		finished.emit(quality_value)
	queue_redraw()


## Эмитит отложенный finished ровно один раз (если _finish уже случился).
func _emit_finished_once() -> void:
	if not _pending_finish:
		return
	_pending_finish = false
	finished.emit(quality_value)


func _default_result_detail() -> String:
	var parts: Array[String] = []
	var stats := _result_stats()
	if not stats.is_empty():
		parts.append(stats)
	var reward := str(context.get("reward_text", ""))
	if not reward.is_empty():
		parts.append(reward)
	var penalty := str(context.get("penalty_text", ""))
	if not penalty.is_empty():
		parts.append(penalty)
	return " · ".join(parts)


# --- ввод ------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		if not event.pressed or event.echo:
			return
		if _finished:
			if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE]:
				_mark_input_handled()
				_continue_clicked()
			return
		if event.keycode == KEY_ESCAPE:
			# В мини-играх отправки Esc — no-op (D10), но пауза часа его не ловит.
			# В мини-играх атак Esc — двухшаговое подтверждение сдачи.
			_mark_input_handled()
			if is_attack:
				_on_skip_clicked()
			return
		if _on_key_pressed(event.keycode, event):
			_mark_input_handled()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var local: Vector2 = event.position - global_position
		if _finished:
			if event.pressed and _result_continue_rect().has_point(local):
				_mark_input_handled()
				_continue_clicked()
			return
		if event.pressed:
			if SKIP_RECT.has_point(local):
				_mark_input_handled()
				_on_skip_clicked()
				return
			if _on_pointer_pressed(local, event):
				_mark_input_handled()
		else:
			_on_pointer_released(local, event)
		return

	if event is InputEventMouseMotion:
		if _finished:
			return
		var local: Vector2 = event.position - global_position
		_on_pointer_moved(local, event)


func _on_pointer_pressed(_local: Vector2, _event: InputEvent) -> bool:
	return false


func _on_pointer_released(_local: Vector2, _event: InputEvent) -> void:
	pass


func _on_pointer_moved(_local: Vector2, _event: InputEvent) -> void:
	pass


func _on_key_pressed(_keycode: int, _event: InputEvent) -> bool:
	return false


func _on_skip_clicked() -> void:
	if not _skip_armed:
		_skip_armed = true
		_play_sfx(&"tick")
		queue_redraw()
		return
	_finish(0.0)


func _continue_clicked() -> void:
	# Модальный режим: сначала отдаём результат директору, затем освобождаем ноду.
	_emit_finished_once()
	queue_free()


func _mark_input_handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


# --- отрисовка -------------------------------------------------------------

func _draw() -> void:
	var font := Theme90.ui()
	var full := Rect2(Vector2.ZERO, size)
	Theme90.draw_bevel(self, full, false, Theme90.BEVEL, Theme90.PAPER)

	var tr := Rect2(1.0, 1.0, size.x - 2.0, HEADER_H - 2.0)
	draw_style_box(Theme90.top_box(Theme90.PAPER_HI, 4), tr)
	draw_rect(Rect2(tr.position.x + 1.0, tr.end.y, tr.size.x - 2.0, 1.0),
		Theme90.HAIRLINE)
	draw_circle(Vector2(tr.position.x + 14.0, tr.position.y + 14.0), 3.0,
		Theme90.ACCENT)
	Theme90.text(self, font, Vector2(tr.position.x + 24.0, tr.position.y + 3.0),
		title(), 18, Theme90.NAVY_DEEP, tr.size.x - 400.0)

	var badge := Rect2(tr.end.x - 124.0, tr.position.y + 6.0, 116.0, 17.0)
	draw_style_box(Theme90.box(Theme90.ACCENT_PALE, Theme90.BORDER_SOFT, 2, 1), badge)
	Theme90.text_vcenter(self, font, badge, tier_label(), 11, Theme90.NAVY,
		-1, HORIZONTAL_ALIGNMENT_CENTER)

	var ratio := _progress_ratio()
	if ratio >= 0.0:
		var bar := Rect2(tr.end.x - 252.0, tr.position.y + 16.0, 104.0, 6.0)
		Theme90.text(self, font, Vector2(bar.position.x - 38.0, bar.position.y - 2.0),
			"%d%%" % roundi(clampf(ratio, 0.0, 1.0) * 100.0), 10, Theme90.DARK,
			34.0, HORIZONTAL_ALIGNMENT_RIGHT)
		_draw_bar(bar, ratio, Theme90.SUCCESS if ratio >= 0.999 else Theme90.ACCENT)

	var goal := _goal_text()
	if not goal.is_empty():
		draw_rect(Rect2(tr.position.x + 14.0, tr.position.y + 26.0, 2.0, 12.0),
			Theme90.ACCENT_LIGHT)
		Theme90.text(self, font, Vector2(tr.position.x + 24.0, tr.position.y + 25.0),
			Theme90.fit(font, goal, 11, tr.size.x - 48.0), 11, Theme90.DARK,
			tr.size.x - 48.0)

	_draw_game()
	_draw_skip_button()
	_draw_footer_hint()
	if _finished:
		_draw_result_overlay()


## Переопределяется наследником. Рисовать в CONTENT_RECT.
func _draw_game() -> void:
	pass


## Необязательная подпись над футером/в футере.
func _draw_footer_hint() -> void:
	pass


func _draw_skip_button() -> void:
	var face := Theme90.WARN if _skip_armed else Theme90.PAPER_HI
	var fg := Theme90.WHITE if _skip_armed else Theme90.DARK
	var border := Theme90.WARN.darkened(0.18) if _skip_armed else Theme90.BORDER
	draw_style_box(Theme90.box(face, border, 3, 1,
		Theme90.SHADOW if not _skip_armed else Color(0, 0, 0, 0)), SKIP_RECT)
	var label := skip_label()
	if _skip_armed:
		label = "ЕЩЁ КЛИК — СДАЧА" if is_attack else "ЕЩЁ КЛИК — ПРОПУСК"
	else:
		label = "%s · 2 КЛИКА" % label
	Theme90.text_vcenter(self, Theme90.ui(), SKIP_RECT, label, 11, fg,
		-1, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_action_button(rect: Rect2, label: String, enabled: bool = true,
		primary: bool = true, size_px: int = 12) -> void:
	var face := Theme90.PAPER_HI
	var fg := Theme90.INK
	var border := Theme90.BORDER
	if primary and enabled:
		face = Theme90.ACCENT
		fg = Theme90.WHITE
		border = Theme90.ACCENT.darkened(0.18)
	elif not enabled:
		face = Theme90.PAPER
		fg = Theme90.DARK
		border = Theme90.BORDER_SOFT
	draw_style_box(Theme90.box(face, border, 3, 1,
		Theme90.SHADOW if enabled else Color(0, 0, 0, 0)), rect)
	Theme90.text_vcenter(self, Theme90.ui(), rect, label, size_px, fg,
		-1, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_secondary_button(rect: Rect2, label: String) -> void:
	draw_style_box(Theme90.box(Theme90.PAPER_HI, Theme90.BORDER, 3, 1), rect)
	Theme90.text_vcenter(self, Theme90.ui(), rect, label, 11, Theme90.DARK,
		-1, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_modal_panel(rect: Rect2, fill: Color = Theme90.PAPER_HI) -> void:
	draw_style_box(Theme90.box(fill, Theme90.BORDER, 4, 1, Theme90.SHADOW), rect)


func _draw_label(text: String, pos: Vector2, size_px: int = 12,
		color: Color = Theme90.INK, width: float = -1.0,
		align: int = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	Theme90.text(self, Theme90.ui(), pos, text, size_px, color, width, align)


func _draw_centered(text: String, rect: Rect2, size_px: int = 12,
		color: Color = Theme90.INK) -> void:
	Theme90.text_vcenter(self, Theme90.ui(), rect, text, size_px, color,
		-1, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_bar(rect: Rect2, ratio: float, color: Color) -> void:
	Theme90.draw_sunken(self, rect)
	Theme90.draw_meter(self, rect.grow(-1.0), clampf(ratio, 0.0, 1.0), color,
		Theme90.PAPER_LO)


func _result_continue_rect() -> Rect2:
	var panel := _result_panel_rect()
	return Rect2(panel.position.x + (panel.size.x - CONTINUE_RECT.size.x) * 0.5,
		panel.position.y + panel.size.y - CONTINUE_RECT.size.y - 16.0,
		CONTINUE_RECT.size.x, CONTINUE_RECT.size.y)


func _result_panel_rect() -> Rect2:
	return Rect2((size.x - 400.0) * 0.5, (size.y - 232.0) * 0.5, 400.0, 232.0)


func _draw_result_overlay() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.10, 0.10, 0.58))
	var panel := _result_panel_rect()
	_draw_modal_panel(panel)
	Theme90.text(self, Theme90.display(), Vector2(panel.position.x, panel.position.y + 10.0),
		"РЕЗУЛЬТАТ", 18, Theme90.NAVY_DEEP, panel.size.x,
		HORIZONTAL_ALIGNMENT_CENTER)
	Theme90.text(self, Theme90.ui(), Vector2(panel.position.x, panel.position.y + 30.0),
		Theme90.fit(Theme90.ui(), title(), 12, panel.size.x - 36.0), 12, Theme90.NAVY,
		panel.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	var q_text := "%d%%" % roundi(quality_value * 100.0)
	Theme90.text(self, Theme90.logo(), Vector2(panel.position.x, panel.position.y + 46.0),
		q_text, 30, Theme90.INK, panel.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	var qcol := Theme90.SUCCESS if quality_value >= 0.75 else (
		Theme90.WARN if quality_value >= 0.45 else Theme90.ERROR)
	_draw_bar(Rect2(panel.position.x + 26.0, panel.position.y + 86.0,
		panel.size.x - 52.0, 8.0), quality_value, qcol)
	var verdict := verdict_for(quality_value)
	Theme90.text(self, Theme90.ui(), Vector2(panel.position.x, panel.position.y + 102.0),
		verdict, 22, qcol, panel.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	if not _result_detail.is_empty():
		Theme90.text(self, Theme90.ui(), Vector2(panel.position.x + 18.0,
			panel.position.y + 134.0), Theme90.fit(Theme90.ui(), _result_detail, 11,
			panel.size.x - 36.0), 11, Theme90.DARK, panel.size.x - 36.0,
			HORIZONTAL_ALIGNMENT_CENTER)
	Theme90.text(self, Theme90.ui(), Vector2(panel.position.x,
		panel.position.y + 154.0), "Esc — продолжить", 10, Theme90.DARK,
		panel.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	var cont := _result_continue_rect()
	_draw_action_button(cont, "ПРОДОЛЖИТЬ", true, true, 13)


# --- служебное -------------------------------------------------------------

static func resolve_game_id(value: String) -> String:
	var v := value.strip_edges().to_lower()
	if SEND_IDS.has(v):
		return v
	if ATTACK_IDS.has(v):
		return v
	return str(LEGACY_TYPES.get(v, ""))


static func is_attack_id(value: String) -> bool:
	var v := str(value).strip_edges().to_lower()
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var data = (loop as SceneTree).root.get_node_or_null("Data")
		if data != null and data.has_method("minigame_def"):
			var def = data.call("minigame_def", v)
			if def is Dictionary and not (def as Dictionary).is_empty():
				return str((def as Dictionary).get("kind", "")).to_lower() == "attack"
	return ATTACK_IDS.has(v)


## Безопасное чтение data/minigame_def(id) с fallback на balance.json.
## Возвращает копию словаря; при отсутствии данных — пустой словарь.
static func data_minigame_def(id: String) -> Dictionary:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return {}
	var root := (loop as SceneTree).root
	var data = root.get_node_or_null("Data")
	if data == null:
		return {}
	if data.has_method("minigame_def"):
		var value = data.call("minigame_def", id)
		if value is Dictionary:
			return (value as Dictionary).duplicate(true)
	var balance = data.get("balance")
	if balance is Dictionary:
		var minigames = (balance as Dictionary).get("minigames", null)
		if minigames is Dictionary:
			var games = (minigames as Dictionary).get("games", null)
			if games is Dictionary and (games as Dictionary).get(id) is Dictionary:
				return ((games as Dictionary).get(id) as Dictionary).duplicate(true)
	return {}


## Строка tier из Data.minigame_def(id). Поддерживает tiers как Array
## (текущий формат balance.json) и как Dictionary (старый/альтернативный).
##
## Отправка теперь имеет 3 ступени, атаки — 4. Если balance.json ещё хранит
## старые 4 строки для отправки, tier 1 читает вторую строку (старый T2):
## так игра работает и до, и после синхронного сдвига таблиц.
static func data_minigame_tier(id: String, p_tier: int) -> Dictionary:
	var def := data_minigame_def(id)
	if def.is_empty():
		return {}
	var attack_def := is_attack_id(id) \
		or str(def.get("kind", "")).to_lower() == "attack"
	var t := clampi(p_tier, 1, 4 if attack_def else 3)
	var tiers = def.get("tiers", null)
	var row: Dictionary = {}
	if tiers is Array:
		var arr := tiers as Array
		var index := t - 1
		if not attack_def and arr.size() >= 4:
			index = clampi(t, 0, arr.size() - 1)
		if index >= 0 and index < arr.size() and arr[index] is Dictionary:
			row = (arr[index] as Dictionary).duplicate(true)
	elif tiers is Dictionary:
		var map := tiers as Dictionary
		var key := t
		if not attack_def and map.size() >= 4:
			key = clampi(t + 1, 1, 4)
		var value = map.get(str(key), map.get(key, null))
		if value is Dictionary:
			row = (value as Dictionary).duplicate(true)
	if row.is_empty():
		# Плоская схема: параметры прямо в def (без tiers).
		for key in def.keys():
			if str(key) != "tiers":
				row[key] = def[key]
	return row


func _center_on_screen() -> void:
	# get_viewport_rect() отдаёт ФИЗИЧЕСКИЙ размер окна (1920×1080), а UI-канва
	# логическая 1280×720. Центрируем по фактическому родителю (modal_root),
	# иначе окно уезжает в правый нижний квадрант. Fallback — вьюпорт.
	var area := Vector2.ZERO
	if is_inside_tree() and get_parent() is Control:
		area = (get_parent() as Control).size
	if area.x <= 0.0 or area.y <= 0.0:
		# Вне дерева (нода создана фабрикой до add_child) вьюпорта ещё нет —
		# центрируем позже в _ready()/повторном start().
		if not is_inside_tree():
			return
		area = get_viewport_rect().size
	position = ((area - size) * 0.5).floor()
	position.x = maxf(0.0, position.x)
	position.y = maxf(0.0, position.y)


func _play_sfx(id: StringName) -> void:
	var audio = _autoload("Audio")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(str(id))


func _autoload(name: String):
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null(name)
	return null


## Удобный static-хелпер для игр, которым нужен общий вердикт.
static func verdict(q: float) -> String:
	if q >= 0.75:
		return "ЧИСТО"
	if q >= 0.45:
		return "НОРМАЛЬНО"
	return "СЛАБО"
