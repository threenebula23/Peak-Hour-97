class_name RansomwareGame
extends MiniGame
## Атака «Карантин» (ransomware). Сетка файлов, среди которых спрятаны
## исполняемые (.exe/.scr/.bat) с документными именами.
##
## Клик — «ИЗОЛИРОВАТЬ», повторный клик снимает пометку, ПРОВЕРИТЬ фиксирует.
## На T3/T4 расширение скрыто до наведения на карточку; на T4 есть ловушки,
## в имени которых есть «exe», но расширение doc/xls.
##
## Качество: q = clamp((found_exe - 0.5 * wrong_clicks) / total_exe, 0, 1).

const GAME_ID := "ransomware"
const TITLE_RU := "КАРАНТИН"
const VERIFY_RECT := Rect2(466.0, 320.0, 156.0, 28.0)

const GRID_TOP := 58.0
const GRID_BOTTOM := 306.0
const GRID_GAP := 8.0

const TIERS := {
	1: {"cards": 12, "exe": 1, "threshold": 0.50, "masking": "extension_visible"},
	2: {"cards": 16, "exe": 2, "threshold": 0.55, "masking": "extension_small"},
	3: {"cards": 20, "exe": 2, "threshold": 0.60, "masking": "document_icon"},
	4: {"cards": 24, "exe": 3, "threshold": 0.65, "masking": "similar_names"},
}

const EXEC_EXTS := ["EXE", "SCR", "BAT"]
const CLEAN_EXTS := ["DOC", "XLS", "TXT", "JPG", "BMP", "ZIP", "WAV", "AVI", "PDF"]

const BASE_NAMES := [
	"отчёт", "смета", "письмо", "фото", "схема", "архив", "звук", "клип",
	"опись", "прайс", "счёт", "курс", "факс", "лог", "план", "акт", "заявка",
	"реестр", "накладная", "договор", "таблица", "список", "карта", "резерв",
	"сводка", "ведомость", "протокол", "этикетка",
]

var _data: Dictionary = {}
var _cards: Array = []
var _marked: Dictionary = {}
var _submitted: bool = false
var _hover: int = -1


func _own_game_id() -> String:
	return GAME_ID


func title() -> String:
	return TITLE_RU


func quality() -> float:
	if _finished:
		return quality_value
	var counts := count_marks(_cards, _marked)
	return ransomware_quality(int(counts["found_exe"]), int(counts["wrong_clicks"]),
		int(_data.get("total_exe", 0)))


func _setup() -> void:
	_data = generate_cards(tier, seed_value)
	_cards = _data.get("cards", [])
	_marked.clear()
	_submitted = false
	_hover = -1


# --- параметры -------------------------------------------------------------

static func tier_params(p_tier: int) -> Dictionary:
	var t := clampi(p_tier, 1, 4)
	var base: Dictionary = (TIERS.get(t, TIERS[1]) as Dictionary).duplicate(true)
	var row := MiniGame.data_minigame_tier(GAME_ID, t)
	if row.is_empty():
		return base
	for key in ["cards", "exe"]:
		if row.has(key):
			base[key] = int(row[key])
	if row.has("threshold"):
		base["threshold"] = float(row["threshold"])
	if row.has("masking"):
		base["masking"] = str(row["masking"])
	return base


static func masking_for(p_tier: int) -> String:
	return str(tier_params(p_tier).get("masking", "extension_visible"))


# --- генерация -------------------------------------------------------------

static func generate_cards(p_tier: int, seed: int) -> Dictionary:
	var t := clampi(p_tier, 1, 4)
	var p := tier_params(t)
	var total := clampi(int(p.get("cards", 12)), 8, 30)
	var exe_count := clampi(int(p.get("exe", 1)), 1, total - 2)
	var trap_count := 2 if t == 4 else 0
	if total - exe_count - trap_count < 2:
		trap_count = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	var names: Array = BASE_NAMES.duplicate()
	_shuffle(names, rng)
	var cursor := 0

	var execs: Array = []
	for i in range(exe_count):
		var ext := str(EXEC_EXTS[rng.randi_range(0, EXEC_EXTS.size() - 1)])
		execs.append({
			"name": str(names[cursor % names.size()]),
			"ext": ext,
			"size_kb": rng.randi_range(18, 46),
			"date": _random_date(rng),
			"executable": true,
			"target": false,
			"trap": false,
		})
		cursor += 1

	var traps: Array = []
	for i in range(trap_count):
		var base_name := str(names[cursor % names.size()])
		cursor += 1
		var trap_name := ("exe_" + base_name) if i % 2 == 0 else (base_name + "_exe")
		traps.append({
			"name": trap_name,
			"ext": "DOC" if i % 2 == 0 else "XLS",
			"size_kb": rng.randi_range(2, 480),
			"date": _random_date(rng),
			"executable": false,
			"target": false,
			"trap": true,
		})

	var clean_count := total - execs.size() - traps.size()
	var cleans: Array = []
	for i in range(clean_count):
		var ext := str(CLEAN_EXTS[rng.randi_range(0, CLEAN_EXTS.size() - 1)])
		cleans.append({
			"name": str(names[cursor % names.size()]),
			"ext": ext,
			"size_kb": rng.randi_range(2, 480),
			"date": _random_date(rng),
			"executable": false,
			"target": false,
			"trap": false,
		})
		cursor += 1

	# Ровно одна «настоящая» цель; остальные исполняемые — тоже угрозы,
	# но флаг target не дублируется. Ловушки целью не бывают никогда.
	var target_index := rng.randi_range(0, execs.size() - 1)
	(execs[target_index] as Dictionary)["target"] = true

	# Хотя бы один чистый файл совпадает по размеру с исполняемым, чтобы
	# размер сам по себе не выдавал цель.
	if not cleans.is_empty():
		(cleans[0] as Dictionary)["size_kb"] = int((execs[0] as Dictionary)["size_kb"])

	var descriptors: Array = []
	descriptors.append_array(execs)
	descriptors.append_array(traps)
	descriptors.append_array(cleans)
	_shuffle(descriptors, rng)

	var cards: Array = []
	for i in range(descriptors.size()):
		var d: Dictionary = descriptors[i]
		var size_kb := int(d.get("size_kb", 2))
		cards.append({
			"id": i,
			"name": str(d.get("name", "")),
			"ext": str(d.get("ext", "")),
			"size_kb": size_kb,
			"size_text": "%d КБ" % size_kb,
			"date": str(d.get("date", "01.01.97")),
			"executable": bool(d.get("executable", false)),
			"target": bool(d.get("target", false)),
			"trap": bool(d.get("trap", false)),
		})

	return {
		"tier": t,
		"cards": cards,
		"total_cards": total,
		"total_exe": exe_count,
		"trap_count": trap_count,
		"threshold": float(p.get("threshold", 0.5)),
		"masking": str(p.get("masking", "extension_visible")),
	}


static func _random_date(rng: RandomNumberGenerator) -> String:
	var day := rng.randi_range(1, 28)
	var month := rng.randi_range(1, 12)
	var year := 96 + rng.randi_range(0, 1)
	return "%02d.%02d.%02d" % [day, month, year]


# --- проверка --------------------------------------------------------------

static func validate_cards(data: Dictionary) -> bool:
	var t := clampi(int(data.get("tier", 1)), 1, 4)
	var p := tier_params(t)
	var cards: Array = data.get("cards", [])
	var total := int(data.get("total_cards", -1))
	if cards.size() != total or total != int(p.get("cards", -1)):
		return false
	if int(data.get("total_exe", -1)) != int(p.get("exe", -1)):
		return false

	var exec_count := 0
	var target_count := 0
	var trap_count := 0
	var names: Dictionary = {}
	for card in cards:
		var c: Dictionary = card
		var name_key := str(c.get("name", ""))
		if names.has(name_key):
			return false
		names[name_key] = true

		var ext := str(c.get("ext", "")).to_upper()
		if bool(c.get("trap", false)):
			trap_count += 1
			if bool(c.get("executable", false)) or bool(c.get("target", false)):
				return false
			if t != 4:
				return false
			if not name_key.to_lower().contains("exe"):
				return false
			if ext != "DOC" and ext != "XLS":
				return false
		if bool(c.get("executable", false)):
			exec_count += 1
			if not EXEC_EXTS.has(ext):
				return false
			if bool(c.get("trap", false)):
				return false
		else:
			if EXEC_EXTS.has(ext):
				return false
			if not bool(c.get("trap", false)) and name_key.to_lower().contains("exe"):
				return false
		if bool(c.get("target", false)):
			target_count += 1
			if not bool(c.get("executable", false)):
				return false

	if exec_count < 1 or exec_count != int(p.get("exe", 0)):
		return false
	if target_count > 1:
		return false
	if t <= 2 and target_count != 1:
		return false
	if trap_count != int(data.get("trap_count", 0)):
		return false
	if t != 4 and trap_count != 0:
		return false
	return true


static func ransomware_quality(found_exe: int, wrong_clicks: int, total_exe: int) -> float:
	if total_exe <= 0:
		return 0.0
	return clampf((float(found_exe) - 0.5 * float(wrong_clicks)) / float(total_exe),
		0.0, 1.0)


static func count_marks(cards: Array, marked: Dictionary) -> Dictionary:
	var found := 0
	var wrong := 0
	var missed := 0
	for card in cards:
		var c: Dictionary = card
		var is_marked := bool(marked.get(int(c.get("id", -1)), false))
		if bool(c.get("executable", false)):
			if is_marked:
				found += 1
			else:
				missed += 1
		elif is_marked:
			wrong += 1
	return {"found_exe": found, "wrong_clicks": wrong, "missed_exe": missed,
		"marked": int(marked.size())}


# --- игра ------------------------------------------------------------------

func _card_rects() -> Array:
	var n := _cards.size()
	if n <= 0:
		return []
	var cols := 4
	if n > 20:
		cols = 6
	elif n > 16:
		cols = 5
	var rows := int(ceil(float(n) / float(cols)))
	var card_w := (604.0 - GRID_GAP * float(cols - 1)) / float(cols)
	var avail_h := GRID_BOTTOM - GRID_TOP
	var card_h := minf(64.0, (avail_h - GRID_GAP * float(rows - 1)) / float(rows))
	var rects: Array = []
	for i in range(n):
		var col := i % cols
		var row := i / cols
		rects.append(Rect2(18.0 + float(col) * (card_w + GRID_GAP),
			GRID_TOP + float(row) * (card_h + GRID_GAP), card_w, card_h))
	return rects


func _card_index_at(local: Vector2) -> int:
	var rects := _card_rects()
	for i in range(rects.size()):
		if (rects[i] as Rect2).has_point(local):
			return i
	return -1


func _ext_visible(card: Dictionary, index: int) -> bool:
	var masking := str(_data.get("masking", "extension_visible"))
	if masking == "extension_visible" or masking == "extension_small":
		return true
	return index == _hover


func _toggle(index: int) -> void:
	if index < 0 or index >= _cards.size():
		return
	var id := int((_cards[index] as Dictionary).get("id", index))
	if _marked.has(id):
		_marked.erase(id)
	else:
		_marked[id] = true
	_play_sfx(&"tick")
	queue_redraw()


func _submit() -> void:
	if _submitted or _finished:
		return
	var counts := count_marks(_cards, _marked)
	var q := ransomware_quality(int(counts["found_exe"]), int(counts["wrong_clicks"]),
		int(_data.get("total_exe", 0)))
	_submitted = true
	_result_detail = _with_context("НАЙДЕНО %d ИЗ %d · ЛОЖНЫХ %d · ПРОПУЩЕНО %d" % [
		int(counts["found_exe"]), int(_data.get("total_exe", 0)),
		int(counts["wrong_clicks"]), int(counts["missed_exe"])])
	_finish(q)


func _with_context(text: String) -> String:
	var parts: Array = []
	var reward := str(context.get("reward_text", ""))
	var penalty := str(context.get("penalty_text", ""))
	if not reward.is_empty():
		parts.append(reward)
	if not penalty.is_empty():
		parts.append(penalty)
	parts.append(text)
	return " · ".join(parts)


func _on_pointer_pressed(local: Vector2, _event: InputEvent) -> bool:
	if _submitted or _finished:
		return false
	if VERIFY_RECT.has_point(local):
		_submit()
		return true
	var index := _card_index_at(local)
	if index >= 0:
		_toggle(index)
		return true
	return false


func _on_pointer_moved(local: Vector2, _event: InputEvent) -> void:
	if _submitted or _finished:
		return
	var next := _card_index_at(local)
	if next != _hover:
		_hover = next
		queue_redraw()


func _on_key_pressed(keycode: int, _event: InputEvent) -> bool:
	if _submitted or _finished:
		return false
	if keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		_submit()
		return true
	return false


# --- отрисовка -------------------------------------------------------------

func _draw_game() -> void:
	_draw_label("ОТМЕЧЕНО: %d" % _marked.size(), Vector2(24.0, 44.0), 12,
		Theme90.INK, 220.0)
	var masking := str(_data.get("masking", "extension_visible"))
	var mode_text := "РАСШИРЕНИЕ ВИДНО"
	if masking == "document_icon":
		mode_text = "НАВЕДИТЕ НА ФАЙЛ: РАСШИРЕНИЕ В ТУЛТИПЕ"
	elif masking == "similar_names":
		mode_text = "ОСТОРОЖНО: ИМЕНА С «EXE» МОГУТ БЫТЬ ЛОВУШКОЙ"
	elif masking == "extension_small":
		mode_text = "РАСШИРЕНИЕ МЕЛКИМ ШРИФТОМ"
	_draw_label(mode_text, Vector2(230.0, 44.0), 10, Theme90.SHADE, 382.0,
		HORIZONTAL_ALIGNMENT_RIGHT)

	var rects := _card_rects()
	for i in range(_cards.size()):
		_draw_card(i, rects[i] if i < rects.size() else Rect2())
	_draw_action_button(VERIFY_RECT, "ПРОВЕРИТЬ", not _submitted, true)


func _draw_card(index: int, rect: Rect2) -> void:
	if rect.size.x <= 0.0:
		return
	var card: Dictionary = _cards[index]
	var marked := _marked.has(int(card.get("id", -1)))
	var executable := bool(card.get("executable", false))
	var trap := bool(card.get("trap", false))

	var fill := Theme90.PAPER_HI
	var border := Theme90.BORDER
	var border_w := 1
	var status := ""

	if _submitted:
		if executable and marked:
			fill = Theme90.SUCCESS.lightened(0.78)
			border = Theme90.SUCCESS
			border_w = 2
			status = "ИЗОЛИРОВАН"
		elif executable and not marked:
			fill = Theme90.WARN.lightened(0.78)
			border = Theme90.WARN
			border_w = 2
			status = "ПРОПУЩЕН"
		elif not executable and marked:
			fill = Theme90.ERROR.lightened(0.80)
			border = Theme90.ERROR
			border_w = 2
			status = "ЛОЖНО"
		elif trap:
			border = Theme90.BORDER_SOFT
	elif marked:
		fill = Theme90.ERROR.lightened(0.90)
		border = Theme90.ERROR
		border_w = 2
		status = "ИЗОЛИРОВАТЬ"
	elif index == _hover:
		border = Theme90.ACCENT
		border_w = 2

	draw_style_box(Theme90.box(fill, border, 3, border_w), rect)

	var ext := str(card.get("ext", ""))
	var show_ext := _ext_visible(card, index)
	var icon_ext := ext if show_ext else ""
	var icon_kind := "text"
	if show_ext:
		icon_kind = _kind_for_ext(ext)
	var icon_col := Theme90.ext_color(Theme90.ext_category(ext))
	if not show_ext:
		icon_col = Theme90.NAVY
	var icon_size := 24.0 if rect.size.x >= 120.0 else 20.0
	Theme90.draw_doc_icon(self, Rect2(rect.position + Vector2(6.0, 7.0),
		Vector2(icon_size, icon_size)), icon_kind, icon_col, icon_ext)

	var name_size := 12 if rect.size.x >= 130.0 else 10
	var text_x := rect.position.x + icon_size + 12.0
	var text_w := rect.size.x - icon_size - 18.0
	Theme90.text(self, Theme90.ui(), Vector2(text_x, rect.position.y + 6.0),
		Theme90.fit(Theme90.ui(), str(card.get("name", "")), name_size, text_w),
		name_size, Theme90.INK, text_w)

	var meta := str(card.get("size_text", ""))
	if show_ext:
		meta = "%s · %s" % [ext, meta]
	Theme90.text(self, Theme90.ui(), Vector2(text_x, rect.position.y + 23.0),
		Theme90.fit(Theme90.ui(), meta, 10, text_w), 10, Theme90.DARK, text_w)

	var bottom_text := str(card.get("date", ""))
	var bottom_col := Theme90.SHADE
	if not status.is_empty():
		bottom_text = status
		bottom_col = Theme90.ERROR
		if _submitted and status == "ИЗОЛИРОВАН":
			bottom_col = Theme90.SUCCESS
		elif status == "ПРОПУЩЕН":
			bottom_col = Theme90.WARN
	Theme90.text(self, Theme90.ui(), Vector2(rect.position.x + 6.0,
		rect.position.y + rect.size.y - 14.0),
		Theme90.fit(Theme90.ui(), bottom_text, 10, rect.size.x - 12.0), 10,
		bottom_col, rect.size.x - 12.0)


func _kind_for_ext(ext: String) -> String:
	match Theme90.ext_category(ext):
		"audio":
			return "sound"
		"image":
			return "photo"
		"video":
			return "video"
	return "text"


func _draw_footer_hint() -> void:
	var masking := str(_data.get("masking", "extension_visible"))
	var text := "ИЩИТЕ ИСПОЛНЯЕМЫЕ ФАЙЛЫ · КЛИК — ИЗОЛИРОВАТЬ"
	if masking == "document_icon":
		text = "ИКОНКА ДОКУМЕНТА НИЧЕГО НЕ ЗНАЧИТ · НАВЕДИТЕ НА ФАЙЛ"
	elif masking == "similar_names":
		text = "«EXE» В ИМЕНИ — ЕЩЁ НЕ ПРИГОВОР · ПРОВЕРЬТЕ РАСШИРЕНИЕ"
	_draw_label(text, Vector2(18.0, 350.0), 10, Theme90.SHADE, 604.0)


# --- служебное -------------------------------------------------------------

static func _shuffle(list: Array, rng: RandomNumberGenerator) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = list[i]
		list[i] = list[j]
		list[j] = tmp
