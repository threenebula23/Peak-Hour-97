class_name JunkGame
extends MiniGame
## Атака «Фильтр» (junk). Статическая сетка карточек: игрок помечает мусор
## в карантин, повторный клик снимает пометку, ПРОВЕРИТЬ фиксирует выбор.
##
## Мусор выглядит почти как обычный файл: аномалия спрятана в метаданных
## (размер, расширение/тип, дубль имени, дата, CRC, непечатаемый символ).
## Нормальные карточки полностью согласованы. Точное число мусора не
## показывается — только «ОТМЕЧЕНО: N».
##
## Здесь нет таймера и нет поражения по времени. Качество:
## q = clamp((removed_junk - false_positive) / total_junk, 0, 1).

const GAME_ID := "junk"
const TITLE_RU := "ФИЛЬТР"
const BAD_CHAR := "▯"
const COLS := 3
const CARD_W := 190.0
const CARD_GAP := 8.0
const GRID_TOP := 58.0
const GRID_BOTTOM := 294.0
const VERIFY_RECT := Rect2(466.0, 320.0, 156.0, 28.0)

const TIERS := {
	1: {"cards": 9, "junk": 2, "hints": 1, "threshold": 0.60},
	2: {"cards": 10, "junk": 3, "hints": 2, "threshold": 0.65},
	3: {"cards": 11, "junk": 4, "hints": 2, "threshold": 0.70},
	4: {"cards": 12, "junk": 5, "hints": 3, "threshold": 0.75},
}

const TYPE_DEFS := [
	{"kind": "text", "label": "ТЕКСТ", "exts": ["TXT", "DOC", "RTF"]},
	{"kind": "sound", "label": "ЗВУК", "exts": ["WAV", "MP3"]},
	{"kind": "photo", "label": "ФОТО", "exts": ["JPG", "PNG", "BMP"]},
	{"kind": "video", "label": "ВИДЕО", "exts": ["AVI", "MP4"]},
]

const NAMES := [
	"отчёт", "смета", "письмо", "схема", "прайс", "акт", "реестр", "план",
	"курс", "заявка", "договор", "опись", "факс", "сводка", "накладная",
	"ведомость", "протокол", "фото", "звук", "клип",
]

const ANOMALY_DEFS := [
	{"id": "zero_size", "family": "size"},
	{"id": "absurd_size", "family": "size"},
	{"id": "wrong_ext", "family": "ext"},
	{"id": "duplicate_name", "family": "name"},
	{"id": "bad_date", "family": "date"},
	{"id": "missing_crc", "family": "crc"},
	{"id": "bad_char", "family": "name"},
]

const ANOMALY_HINTS := {
	"zero_size": "размер 0 Б — это мусор",
	"absurd_size": "абсурдный размер файла",
	"wrong_ext": "расширение не сходится с типом",
	"duplicate_name": "два файла с одинаковым именем",
	"invalid_date": "несуществующая дата",
	"future_date": "дата из будущего",
	"missing_crc": "нет контрольной суммы",
	"bad_char": "в имени непечатаемый символ",
}

const WRONG_EXTS := {
	"text": ["WAV", "JPG", "AVI", "EXE"],
	"sound": ["TXT", "JPG", "AVI", "EXE"],
	"photo": ["TXT", "WAV", "AVI", "EXE"],
	"video": ["TXT", "WAV", "JPG", "EXE"],
}

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
	return junk_quality(int(counts["removed_junk"]), int(counts["false_positive"]),
		int(_data.get("total_junk", 0)))


func _setup() -> void:
	_data = generate_junk(tier, seed_value)
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
	for key in ["cards", "junk", "hints"]:
		if row.has(key):
			base[key] = int(row[key])
	if row.has("threshold"):
		base["threshold"] = float(row["threshold"])
	return base


# --- генерация -------------------------------------------------------------

static func generate_junk(p_tier: int, seed: int) -> Dictionary:
	var t := clampi(p_tier, 1, 4)
	var p := tier_params(t)
	var total := clampi(int(p.get("cards", 9)), 4, 24)
	var junk_count := clampi(int(p.get("junk", 2)), 1, total - 1)
	var hint_count := clampi(int(p.get("hints", 1)), 0, 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	var names: Array = NAMES.duplicate()
	_shuffle(names, rng)

	var cards: Array = []
	for i in range(total):
		var td: Dictionary = TYPE_DEFS[rng.randi_range(0, TYPE_DEFS.size() - 1)]
		var exts: Array = td["exts"]
		var ext := str(exts[rng.randi_range(0, exts.size() - 1)])
		var raw_name := str(names[i % names.size()])
		if i >= names.size():
			raw_name = "%s_%d" % [raw_name, i]
		var size_kb := rng.randi_range(2, 480)
		cards.append({
			"id": i,
			"name": raw_name,
			"kind": str(td["kind"]),
			"type_label": str(td["label"]),
			"ext": ext,
			"size_kb": size_kb,
			"size_text": "%d КБ" % size_kb,
			"date": _random_date(rng),
			"crc": "%04X" % rng.randi_range(0, 65535),
			"junk": false,
			"anomalies": [],
		})

	var order: Array = []
	for i in range(total):
		order.append(i)
	_shuffle(order, rng)
	var junk_indices: Array = order.slice(0, junk_count)

	var normal_indices: Array = []
	for i in range(total):
		if not junk_indices.has(i):
			normal_indices.append(i)

	for pos in range(junk_indices.size()):
		var card: Dictionary = cards[int(junk_indices[pos])]
		card["junk"] = true
		var anomaly_ids := _pick_anomalies(t, pos, rng)
		var applied: Array = []
		for anomaly_id in anomaly_ids:
			var result := _apply_anomaly(card, str(anomaly_id), rng, cards, normal_indices)
			if not str(result).is_empty():
				applied.append(str(result))
		if applied.is_empty():
			card["size_kb"] = 0
			card["size_text"] = "0 Б"
			applied.append("zero_size")
		card["anomalies"] = applied

	var hints := _collect_hints(cards, hint_count)

	return {
		"tier": t,
		"cards": cards,
		"total_cards": total,
		"total_junk": junk_count,
		"hint_count": hint_count,
		"hints": hints,
		"threshold": float(p.get("threshold", 0.6)),
	}


static func _pick_anomalies(p_tier: int, junk_pos: int, rng: RandomNumberGenerator) -> Array:
	var pool: Array = ANOMALY_DEFS.duplicate(true)
	_shuffle(pool, rng)
	var picked: Array = []
	var families: Dictionary = {}

	if p_tier == 1 and junk_pos == 0:
		picked.append("zero_size")
		families["size"] = true
	elif p_tier <= 2 and junk_pos == 0 and rng.randf() < 0.5:
		picked.append("zero_size")
		families["size"] = true

	for entry in pool:
		if picked.size() >= 2:
			break
		var family := str((entry as Dictionary)["family"])
		var anomaly_id := str((entry as Dictionary)["id"])
		if families.has(family):
			continue
		picked.append(anomaly_id)
		families[family] = true

	if picked.is_empty():
		picked.append("zero_size")
	return picked


static func _apply_anomaly(card: Dictionary, anomaly_id: String, rng: RandomNumberGenerator,
		cards: Array, normal_indices: Array) -> String:
	match anomaly_id:
		"zero_size":
			card["size_kb"] = 0
			card["size_text"] = "0 Б"
			return "zero_size"
		"absurd_size":
			card["size_kb"] = 999999
			card["size_text"] = "999 999 КБ"
			return "absurd_size"
		"wrong_ext":
			var kind_name := str(card.get("kind", "text"))
			var options: Array = WRONG_EXTS.get(kind_name, ["EXE"])
			var alt := str(options[rng.randi_range(0, options.size() - 1)])
			if _ext_matches_kind(kind_name, alt):
				alt = "EXE"
			card["ext"] = alt
			return "wrong_ext"
		"duplicate_name":
			if normal_indices.is_empty() or str(card.get("name", "")).contains(BAD_CHAR):
				return ""
			var victim: Dictionary = cards[int(normal_indices[rng.randi_range(0,
				normal_indices.size() - 1)])]
			card["name"] = str(victim.get("name", ""))
			return "duplicate_name"
		"bad_date":
			if rng.randf() < 0.5:
				card["date"] = "31.02.97"
				return "invalid_date"
			card["date"] = "12.06.31"
			return "future_date"
		"missing_crc":
			card["crc"] = "—"
			return "missing_crc"
		"bad_char":
			var name := str(card.get("name", ""))
			if name.length() >= 2:
				card["name"] = name.substr(0, 1) + BAD_CHAR + name.substr(2)
			else:
				card["name"] = BAD_CHAR + name
			return "bad_char"
	return ""


static func _collect_hints(cards: Array, limit: int) -> Array:
	if limit <= 0:
		return []
	var order := ["zero_size", "absurd_size", "wrong_ext", "duplicate_name",
		"invalid_date", "future_date", "missing_crc", "bad_char"]
	var seen: Dictionary = {}
	for key in order:
		for card in cards:
			if not bool((card as Dictionary).get("junk", false)):
				continue
			var anomalies: Array = (card as Dictionary).get("anomalies", [])
			if anomalies.has(key):
				seen[key] = true
	var hints: Array = []
	for key in order:
		if seen.has(key) and hints.size() < limit:
			hints.append(str(ANOMALY_HINTS.get(key, "")))
	return hints


# --- проверка --------------------------------------------------------------

static func _ext_matches_kind(kind: String, ext: String) -> bool:
	var e := ext.strip_edges().to_upper()
	for td in TYPE_DEFS:
		if str((td as Dictionary)["kind"]) != kind:
			continue
		var exts: Array = (td as Dictionary)["exts"]
		for allowed in exts:
			if e == str(allowed):
				return true
	return false


static func _valid_date(value: String) -> bool:
	var parts := value.split(".")
	if parts.size() != 3:
		return false
	if not parts[0].is_valid_int() or not parts[1].is_valid_int() \
			or not parts[2].is_valid_int():
		return false
	var day := int(parts[0])
	var month := int(parts[1])
	var year := int(parts[2])
	if month < 1 or month > 12:
		return false
	if day < 1 or day > _days_in_month(month):
		return false
	return year >= 0 and year <= 99


static func _future_date(value: String) -> bool:
	var parts := value.split(".")
	if parts.size() != 3 or not parts[2].is_valid_int():
		return false
	# Игра идёт в 1996–1997; двухзначные 00–89 читаются как 2000-е.
	var year := int(parts[2])
	return year > 97 or year < 90


static func _days_in_month(month: int) -> int:
	match month:
		2:
			return 28
		4, 6, 9, 11:
			return 30
	return 31


static func _random_date(rng: RandomNumberGenerator) -> String:
	var day := rng.randi_range(1, 28)
	var month := rng.randi_range(1, 12)
	var year := 96 + rng.randi_range(0, 1)
	return "%02d.%02d.%02d" % [day, month, year]


## Все видимые аномалии карточки. Дубль имени — отношение между карточками,
## поэтому передаётся counts имён.
static func detected_anomalies(card: Dictionary, name_counts: Dictionary) -> Array:
	var out: Array = []
	var size_kb := int(card.get("size_kb", 0))
	if size_kb == 0:
		out.append("zero_size")
	elif size_kb >= 999999:
		out.append("absurd_size")
	if not _ext_matches_kind(str(card.get("kind", "")), str(card.get("ext", ""))):
		out.append("wrong_ext")
	if str(card.get("crc", "")) == "—":
		out.append("missing_crc")
	var date := str(card.get("date", ""))
	if not _valid_date(date):
		out.append("invalid_date")
	elif _future_date(date):
		out.append("future_date")
	if str(card.get("name", "")).contains(BAD_CHAR):
		out.append("bad_char")
	if int(name_counts.get(str(card.get("name", "")), 0)) > 1:
		out.append("duplicate_name")
	return out


static func validate_junk(data: Dictionary) -> bool:
	var cards: Array = data.get("cards", [])
	var p := tier_params(int(data.get("tier", 1)))
	if cards.size() != int(data.get("total_cards", -1)) or cards.is_empty():
		return false
	if int(data.get("total_junk", -1)) != int(p.get("junk", -1)):
		return false

	var name_counts: Dictionary = {}
	for card in cards:
		var name := str((card as Dictionary).get("name", ""))
		name_counts[name] = int(name_counts.get(name, 0)) + 1

	var junk_seen := 0
	for card in cards:
		var c: Dictionary = card
		var detected := detected_anomalies(c, name_counts)
		if bool(c.get("junk", false)):
			junk_seen += 1
			if detected.is_empty():
				return false
			# Дубль имени сам по себе неоднозначен: у мусорной карточки должен
			# быть ещё хотя бы один независимый признак.
			var independent := 0
			for anomaly in detected:
				if str(anomaly) != "duplicate_name":
					independent += 1
			if independent == 0:
				return false
		else:
			if int(c.get("size_kb", 0)) <= 0 or int(c.get("size_kb", 0)) > 999998:
				return false
			if not _ext_matches_kind(str(c.get("kind", "")), str(c.get("ext", ""))):
				return false
			if str(c.get("crc", "")) == "—" or str(c.get("crc", "")).length() != 4:
				return false
			if not _valid_date(str(c.get("date", ""))) or _future_date(str(c.get("date", ""))):
				return false
			if str(c.get("name", "")).contains(BAD_CHAR):
				return false
	if junk_seen != int(data.get("total_junk", -1)):
		return false
	return true


static func junk_quality(removed_junk: int, false_positive: int, total_junk: int) -> float:
	if total_junk <= 0:
		return 0.0
	return clampf((float(removed_junk) - float(false_positive)) / float(total_junk),
		0.0, 1.0)


static func count_marks(cards: Array, marked: Dictionary) -> Dictionary:
	var removed := 0
	var false_positive := 0
	var missed := 0
	for card in cards:
		var c: Dictionary = card
		var is_marked := bool(marked.get(int(c.get("id", -1)), false))
		if bool(c.get("junk", false)):
			if is_marked:
				removed += 1
			else:
				missed += 1
		elif is_marked:
			false_positive += 1
	return {
		"removed_junk": removed,
		"false_positive": false_positive,
		"missed_junk": missed,
		"marked": int(marked.size()),
	}


# --- ввод ------------------------------------------------------------------

func _card_index_at(local: Vector2) -> int:
	for i in range(_cards.size()):
		if _card_rect(i).has_point(local):
			return i
	return -1


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
	var q := junk_quality(int(counts["removed_junk"]), int(counts["false_positive"]),
		int(_data.get("total_junk", 0)))
	_submitted = true
	_result_detail = _with_context("СНЯТО %d ИЗ %d · ЛОЖНЫХ %d · ПРОПУЩЕНО %d" % [
		int(counts["removed_junk"]), int(_data.get("total_junk", 0)),
		int(counts["false_positive"]), int(counts["missed_junk"])])
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

func _card_rect(index: int) -> Rect2:
	var rows := maxi(1, int(ceil(float(_cards.size()) / float(COLS))))
	var gap := CARD_GAP
	var avail_h := GRID_BOTTOM - GRID_TOP
	var card_h := minf(70.0, (avail_h - gap * float(rows - 1)) / float(rows))
	var total_w := CARD_W * float(COLS) + gap * float(COLS - 1)
	var x0 := 18.0 + (604.0 - total_w) * 0.5
	var col := index % COLS
	var row := index / COLS
	return Rect2(x0 + float(col) * (CARD_W + gap), GRID_TOP + float(row) * (card_h + gap),
		CARD_W, card_h)


func _draw_game() -> void:
	var marked_count := _marked.size()
	_draw_label("ОТМЕЧЕНО: %d" % marked_count, Vector2(24.0, 44.0), 12,
		Theme90.INK, 180.0)

	for i in range(_cards.size()):
		_draw_card(i)
	_draw_action_button(VERIFY_RECT, "ПРОВЕРИТЬ", not _submitted, true)


func _draw_card(index: int) -> void:
	var card: Dictionary = _cards[index]
	var rect := _card_rect(index)
	var marked := _marked.has(int(card.get("id", -1)))
	var junk := bool(card.get("junk", false))

	var fill := Theme90.PAPER_HI
	var border := Theme90.BORDER
	var border_w := 1
	var status := ""

	if _submitted:
		if junk and marked:
			fill = Theme90.SUCCESS.lightened(0.78)
			border = Theme90.SUCCESS
			border_w = 2
			status = "СНЯТ"
		elif junk and not marked:
			fill = Theme90.WARN.lightened(0.78)
			border = Theme90.WARN
			border_w = 2
			status = "ПРОПУЩЕН"
		elif not junk and marked:
			fill = Theme90.ERROR.lightened(0.80)
			border = Theme90.ERROR
			border_w = 2
			status = "ЛОЖНО"
		elif not junk:
			border = Theme90.BORDER_SOFT
	elif marked:
		fill = Theme90.ERROR.lightened(0.90)
		border = Theme90.ERROR
		border_w = 2
		status = "В КАРАНТИН"
	elif index == _hover:
		border = Theme90.ACCENT
		border_w = 2

	draw_style_box(Theme90.box(fill, border, 3, border_w), rect)

	var kind := str(card.get("kind", "text"))
	var ext := str(card.get("ext", ""))
	var cat := Theme90.ext_category(ext)
	var icon_col := Theme90.ext_color(cat)
	if cat.is_empty():
		match kind:
			"sound":
				icon_col = Theme90.WARN
			"photo":
				icon_col = Theme90.SUCCESS
			"video":
				icon_col = Theme90.ERROR
			_:
				icon_col = Theme90.ACCENT
	Theme90.draw_doc_icon(self, Rect2(rect.position + Vector2(7.0, 7.0), Vector2(28.0, 28.0)),
		kind, icon_col, ext)

	var tall := rect.size.y >= 64.0
	var name_y := rect.position.y + (8.0 if tall else 5.0)
	var meta_y := rect.position.y + (27.0 if tall else 21.0)
	var sub_y := rect.position.y + (44.0 if tall else 36.0)
	var text_x := rect.position.x + 42.0
	var text_w := rect.size.x - 50.0
	var name := Theme90.fit(Theme90.ui(), str(card.get("name", "")), 12, text_w)
	Theme90.text(self, Theme90.ui(), Vector2(text_x, name_y), name, 12, Theme90.INK, text_w)
	Theme90.text(self, Theme90.ui(), Vector2(text_x, meta_y),
		"%s · %s" % [ext, str(card.get("size_text", ""))], 10, Theme90.DARK, text_w)
	Theme90.text(self, Theme90.ui(), Vector2(text_x, sub_y),
		"%s · CRC %s" % [str(card.get("date", "")), str(card.get("crc", ""))],
		10, Theme90.SHADE, text_w)

	var badge := status
	if badge.is_empty():
		badge = str(card.get("type_label", ""))
	var badge_col := Theme90.SHADE
	if _submitted and status == "СНЯТ":
		badge_col = Theme90.SUCCESS
	elif _submitted and status == "ЛОЖНО":
		badge_col = Theme90.ERROR
	elif status == "ПРОПУЩЕН":
		badge_col = Theme90.WARN
	elif status == "В КАРАНТИН":
		badge_col = Theme90.ERROR
	Theme90.text(self, Theme90.ui(), Vector2(rect.position.x + 112.0, name_y),
		Theme90.fit(Theme90.ui(), badge, 10, rect.size.x - 118.0), 10, badge_col,
		rect.size.x - 118.0, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_footer_hint() -> void:
	var hints: Array = _data.get("hints", [])
	var text := "ПОДСКАЗКИ: " + " · ".join(hints) if not hints.is_empty() \
		else "СНИМАЙТЕ ТОЛЬКО МУСОР"
	# Полная подсказка — в полосе между сеткой (y=294) и футером (y=320).
	_draw_label(Theme90.fit(Theme90.ui(), text, 10, 604.0),
		Vector2(18.0, 298.0), 10, Theme90.SHADE, 604.0)


# --- служебное -------------------------------------------------------------

static func _shuffle(list: Array, rng: RandomNumberGenerator) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = list[i]
		list[i] = list[j]
		list[j] = tmp
