extends MiniGame
## «Чужое слово» (text). Письмо с нормальными и чужими словами.
## Клик помечает/снимает слово; «ОТПРАВИТЬ» фиксирует.
## q = clamp((found - false_positive) / aliens, 0, 1), ложное слово
## учитывается не более одного раза.

const TIERS := {
	1: {"words": 15, "aliens": 2, "lines": 2, "types": ["foreign", "deformed"]},
	2: {"words": 19, "aliens": 3, "lines": 3, "types": ["foreign", "deformed", "semantic"]},
	3: {"words": 24, "aliens": 4, "lines": 3, "types": ["foreign", "deformed", "semantic", "archaic"]},
}

const NORMAL := [
	"смета", "отчёт", "курсор", "канал", "папка", "сервер", "файл", "запрос",
	"договор", "смена", "пакет", "клиент", "письмо", "проверка", "срочно",
	"подтвердить", "согласовано", "принято", "оплата", "счёт", "архив",
	"копия", "печать", "модем", "линия", "обмен", "срок", "заявка",
	"подпись", "курьер", "терминал", "диспетчер", "доставка", "опись",
	"накладная", "пломба", "сверка", "реестр", "график", "смена", "склад",
	"погрузка", "маршрут", "квитанция", "сектор", "порт", "кабель", "узел",
	"сбой", "ремонт", "дежурный", "инструкция", "согласование", "скан",
]

const ALIEN_POOLS := {
	"foreign": [
		"deadline", "please", "update", "attachment", "urgent", "email",
		"file", "message", "report", "invoice", "delivery", "storage",
	],
	"deformed": [
		"подтверDить", "согласоваNо", "клиеNт", "проверXа", "докумеNт",
		"срочNо", "пакеD", "адреZ", "сектоR", "накладNая",
	],
	"semantic": [
		"СУХОЙ-МОДЕМ", "КВАДРАТНЫЙ-ЧАЙ", "ЖИДКИЙ-ФАКС", "ГЛУХОЙ-ЗВОНОК",
		"СОЛЁНЫЙ-КАБЕЛЬ", "ЦИФРОВОЙ-СНЕГ", "МОКРАЯ-ПОЧТА", "ХРУСТЯЩИЙ-ДИСК",
	],
	"archaic": [
		"ТЕЛЕГРАФ", "ПЕРФОЛЕНТА", "ТЕЛЕКС", "ГРАММОФОН", "АРИФМОМЕТР",
		"ПАТЕФОН", "КЕРОСИНКА", "БОБИНА", "ТАБУЛЯТОР", "ДИСКЕТА",
	],
}

const ACTION_LABEL := "ОТПРАВИТЬ"
var generated: Dictionary = {}
var _words: Array = []
var _marked: Dictionary = {}
var _layout: Array = []
var _hover: int = -1
var _found: int = 0


func _own_game_id() -> String:
	return "text"


func _setup() -> void:
	generated = generate(tier, seed_value)
	_words = []
	for w in generated.get("words", []):
		_words.append((w as Dictionary).duplicate(true))
	_marked.clear()
	_found = 0
	_hover = -1
	_build_layout()


func _goal_text() -> String:
	return "НАЙДИТЕ ЧУЖИЕ СЛОВА И НАЖМИТЕ «ОТПРАВИТЬ»"


func _progress_ratio() -> float:
	var aliens := int(generated.get("aliens", 0))
	if aliens <= 0:
		return 0.0
	return clampf(float(_found) / float(aliens), 0.0, 1.0)


func _result_stats() -> String:
	return "НАЙДЕНО %d/%d · ЛОЖНЫХ %d" % [_found,
		int(generated.get("aliens", 0)), _false_positive_count()]


# --- параметры/чистая логика ----------------------------------------------

static func tier_params(p_tier: int) -> Dictionary:
	var base: Dictionary = (TIERS.get(clampi(p_tier, 1, 3), TIERS[1]) as Dictionary).duplicate(true)
	var row := MiniGame.data_minigame_tier("text", p_tier)
	if row.is_empty():
		return base
	for key in ["words", "aliens", "lines"]:
		if row.has(key):
			base[key] = int(row[key])
	return base


static func generate(p_tier: int, seed: int) -> Dictionary:
	var p := tier_params(p_tier)
	var total := clampi(int(p.get("words", 11)), 6, 30)
	var aliens := clampi(int(p.get("aliens", 1)), 1, mini(6, total - 2))
	var lines := clampi(int(p.get("lines", 2)), 1, 4)
	var allowed: Array = p.get("types", ["foreign"])
	if allowed.is_empty():
		allowed = ["foreign"]

	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	var normal_pool := NORMAL.duplicate()
	_shuffle(normal_pool, rng)
	var chosen: Array = []
	var used := {}
	for word in normal_pool:
		var key := str(word).to_lower()
		if used.has(key):
			continue
		used[key] = true
		chosen.append(str(word))
		if chosen.size() >= total - aliens:
			break
	while chosen.size() < total - aliens:
		var filler := "пакет%d" % (chosen.size() + 1)
		if not used.has(filler):
			used[filler] = true
			chosen.append(filler)

	var alien_words: Array = []
	var types_used: Array = []
	var type_cycle: Array = allowed.duplicate()
	_shuffle(type_cycle, rng)
	for i in range(aliens):
		var type := str(type_cycle[i % type_cycle.size()])
		var pool: Array = ALIEN_POOLS.get(type, ALIEN_POOLS["foreign"])
		var candidates := pool.duplicate()
		_shuffle(candidates, rng)
		var picked := ""
		for candidate in candidates:
			var candidate_key := str(candidate).to_lower()
			if not used.has(candidate_key):
				picked = str(candidate)
				break
		if picked.is_empty():
			# Пул исчерпан — берём любую другую разрешённую категорию.
			for alt in allowed:
				var alt_pool: Array = ALIEN_POOLS.get(str(alt), [])
				for candidate in alt_pool:
					var candidate_key := str(candidate).to_lower()
					if not used.has(candidate_key):
						picked = str(candidate)
						type = str(alt)
						break
				if not picked.is_empty():
					break
		if picked.is_empty():
			picked = "чужое%d" % (i + 1)
		used[picked.to_lower()] = true
		alien_words.append({"text": picked, "type": type})
		if not types_used.has(type):
			types_used.append(type)

	# Строки: сумма ровно total, все строки непустые.
	var rows: Array = _split_counts(total, lines, rng)
	var words: Array = []
	for word in chosen:
		words.append({"text": word, "alien": false, "type": "", "row": 0})
	for alien in alien_words:
		words.append({"text": str(alien["text"]), "alien": true,
			"type": str(alien["type"]), "row": 0})
	_shuffle(words, rng)
	var row_index := 0
	var in_row := 0
	for i in range(words.size()):
		if row_index >= rows.size():
			row_index = rows.size() - 1
		words[i]["row"] = row_index
		in_row += 1
		if in_row >= int(rows[row_index]) and row_index < rows.size() - 1:
			row_index += 1
			in_row = 0
	var alien_count := 0
	for w in words:
		if bool(w["alien"]):
			alien_count += 1
	return {
		"tier": clampi(p_tier, 1, 3),
		"words": words,
		"count": words.size(),
		"aliens": alien_count,
		"rows": rows,
		"types": allowed,
	}


static func _split_counts(total: int, lines: int, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var base := total / lines
	var rest := total % lines
	for i in range(lines):
		out.append(base + (1 if i < rest else 0))
	if lines > 1 and rng.randf() < 0.5 and int(out[0]) > 1 and int(out[lines - 1]) > 1:
		out[0] = int(out[0]) + 1
		out[lines - 1] = int(out[lines - 1]) - 1
	return out


static func validate_generation(data: Dictionary, p_tier: int) -> bool:
	var p := tier_params(p_tier)
	var words: Array = data.get("words", [])
	var rows: Array = data.get("rows", [])
	if words.size() != int(p.get("words", words.size())):
		return false
	var expected_aliens := int(p.get("aliens", 1))
	var aliens := 0
	var seen := {}
	var row_sum := 0
	for r in rows:
		row_sum += int(r)
	if row_sum != words.size() or rows.size() != int(p.get("lines", rows.size())):
		return false
	for w in words:
		var text := str(w.get("text", "")).strip_edges()
		if text.is_empty():
			return false
		var key := text.to_lower()
		if seen.has(key):
			return false
		seen[key] = true
		if bool(w.get("alien", false)):
			aliens += 1
			if not _is_known_alien(text):
				return false
		else:
			if _is_known_alien(text):
				return false
	return aliens == expected_aliens


static func _is_known_alien(word: String) -> bool:
	var key := word.strip_edges().to_lower()
	for pool in ALIEN_POOLS.values():
		for candidate in (pool as Array):
			if str(candidate).strip_edges().to_lower() == key:
				return true
	return false


static func quality_for(found: int, false_positive: int, aliens: int) -> float:
	if aliens <= 0:
		return 1.0
	return clampf((float(found) - float(false_positive)) / float(aliens), 0.0, 1.0)


static func _shuffle(list: Array, p_rng: RandomNumberGenerator) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := p_rng.randi_range(0, i)
		var tmp = list[i]
		list[i] = list[j]
		list[j] = tmp


# --- раскладка/игра --------------------------------------------------------

func _build_layout() -> void:
	_layout.clear()
	var font := Theme90.ui()
	if _words.is_empty():
		return
	var panel := Rect2(28.0, 62.0, 584.0, 232.0)
	var inner_w := panel.size.x - 40.0
	var rows_count := int(generated.get("rows", []).size())
	if rows_count <= 0:
		rows_count = 2
	var counts: Array = generated.get("rows", [])
	var size_px := 10
	for candidate in [16, 12, 10]:
		var fits := true
		for r in range(counts.size()):
			var width := 0.0
			for w in _row_words(r, counts):
				width += font.get_string_size(str(w["text"]), HORIZONTAL_ALIGNMENT_LEFT,
					-1, int(candidate)).x + 10.0
			width += 7.0 * float(maxi(0, _row_words(r, counts).size() - 1))
			if width > inner_w:
				fits = false
				break
		if fits:
			size_px = int(candidate)
			break

	var line_h := float(size_px) + 13.0
	# Первая строка ниже заголовка записки, а не поверх него.
	var header_h := 24.0
	var top := panel.position.y + header_h + 2.0
	var avail := panel.size.y - header_h - 10.0
	var gap := 10.0
	if rows_count > 1:
		gap = clampf((avail - line_h * float(rows_count)) / float(rows_count - 1),
			10.0, 46.0)
	var block_h := line_h * float(rows_count) + gap * float(maxi(0, rows_count - 1))
	var y := top + maxf(0.0, (avail - block_h) * 0.5)
	for r in range(counts.size()):
		var row_list := _row_words(r, counts)
		var widths: Array = []
		var total_w := 0.0
		for w in row_list:
			var ww := font.get_string_size(str(w["text"]), HORIZONTAL_ALIGNMENT_LEFT,
				-1, size_px).x + 10.0
			widths.append(ww)
			total_w += ww
		total_w += 7.0 * float(maxi(0, row_list.size() - 1))
		var x := panel.position.x + 20.0 + maxf(0.0, (inner_w - total_w) * 0.5)
		var row_layout: Array = []
		for i in range(row_list.size()):
			var ww := float(widths[i])
			row_layout.append({
				"idx": int(row_list[i]["idx"]),
				"rect": Rect2(x, y, ww, line_h),
			})
			x += ww + 7.0
		_layout.append(row_layout)
		y += line_h + gap
	_layout.append(size_px)


func _row_words(r: int, counts: Array) -> Array:
	var out: Array = []
	for i in range(_words.size()):
		if int(_words[i].get("row", 0)) == r:
			var copy: Dictionary = (_words[i] as Dictionary).duplicate(true)
			copy["idx"] = i
			out.append(copy)
	return out


func _word_index_at(local: Vector2) -> int:
	for row in _layout:
		if not (row is Array):
			continue
		for item in (row as Array):
			var hit: Rect2 = (item as Dictionary)["rect"]
			if hit.grow(3.0).has_point(local):
				return int((item as Dictionary)["idx"])
	return -1


func _false_positive_count() -> int:
	var n := 0
	for idx in _marked.keys():
		var i := int(idx)
		if i >= 0 and i < _words.size() and not bool(_words[i].get("alien", false)):
			n += 1
	return n


func _recount() -> void:
	_found = 0
	for idx in _marked.keys():
		var i := int(idx)
		if i >= 0 and i < _words.size() and bool(_words[i].get("alien", false)):
			_found += 1


func _on_pointer_pressed(local: Vector2, _event: InputEvent) -> bool:
	if ACTION_RECT.has_point(local):
		var fp := _false_positive_count()
		_finish(quality_for(_found, fp, int(generated.get("aliens", 1))))
		return true
	var idx := _word_index_at(local)
	if idx < 0:
		return false
	if _marked.has(idx):
		_marked.erase(idx)
	else:
		_marked[idx] = true
	_recount()
	_play_sfx(&"tick")
	queue_redraw()
	return true


func _on_pointer_moved(local: Vector2, _event: InputEvent) -> void:
	var idx := _word_index_at(local)
	if idx != _hover:
		_hover = idx
		queue_redraw()


func _on_key_pressed(keycode: int, _event: InputEvent) -> bool:
	if keycode == KEY_ENTER or keycode == KEY_KP_ENTER:
		var fp := _false_positive_count()
		_finish(quality_for(_found, fp, int(generated.get("aliens", 1))))
		return true
	return false


func _draw_game() -> void:
	var font := Theme90.ui()
	var fp := _false_positive_count()
	_draw_label("ПИСЬМО КЛИЕНТА · ЗАДАНИЕ 97", Vector2(24.0, 46.0), 10,
		Theme90.NAVY, 260.0)
	_draw_label("НАЙДЕНО %d / %d · ЛОЖНЫХ %d" % [_found,
		int(generated.get("aliens", 1)), fp], Vector2(300.0, 46.0), 10,
		Theme90.SUCCESS if _found >= int(generated.get("aliens", 1)) else Theme90.DARK,
		300.0, HORIZONTAL_ALIGNMENT_RIGHT)

	var panel := Rect2(28.0, 62.0, 584.0, 232.0)
	draw_style_box(Theme90.box(Theme90.PAPER_HI, Theme90.BORDER, 4, 1,
		Theme90.SHADOW), panel)
	draw_rect(Rect2(panel.position.x + 18.0, panel.position.y + 23.0,
		panel.size.x - 36.0, 1.0), Theme90.HAIRLINE)
	_draw_label("СЛУЖЕБНАЯ ЗАПИСКА · НАЙДИТЕ ЧУЖИЕ СЛОВА", Vector2(panel.position.x + 20.0,
		panel.position.y + 7.0), 10, Theme90.DARK, panel.size.x - 40.0)

	var size_px := 12
	if not _layout.is_empty() and typeof(_layout[_layout.size() - 1]) == TYPE_INT:
		size_px = int(_layout[_layout.size() - 1])
	for row in _layout:
		if not (row is Array):
			continue
		for item in (row as Array):
			var d: Dictionary = item
			var idx := int(d["idx"])
			var rect: Rect2 = d["rect"]
			var word: String = str(_words[idx].get("text", ""))
			var marked := _marked.has(idx)
			if marked and _hover == idx:
				draw_style_box(Theme90.box(Theme90.ACCENT_PALE, Theme90.ACCENT, 2, 1),
					rect)
			elif marked:
				var fcol := Theme90.ERROR if not bool(_words[idx].get("alien", false)) \
					else Theme90.SUCCESS
				draw_style_box(Theme90.box(Color(fcol.r, fcol.g, fcol.b, 0.13),
					fcol, 2, 1), rect)
			elif _hover == idx:
				draw_style_box(Theme90.box(Theme90.PAPER_LO, Theme90.BORDER_SOFT, 2, 1),
					rect)
			var color := Theme90.INK
			if marked:
				color = Theme90.ERROR if not bool(_words[idx].get("alien", false)) else Theme90.SUCCESS
			Theme90.text_vcenter(self, font, rect, word, size_px, color,
				rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)
			if marked and bool(_words[idx].get("alien", false)):
				draw_line(Vector2(rect.position.x + 2.0, rect.get_center().y + 5.0),
					Vector2(rect.end.x - 2.0, rect.get_center().y + 5.0),
					Theme90.SUCCESS, 1.5)
	_draw_label("КЛИК ПО СЛОВУ — ПОМЕТИТЬ · ПОВТОРНЫЙ КЛИК — СНЯТЬ",
		Vector2(24.0, 300.0), 10, Theme90.DARK, 400.0)
	_draw_action_button(ACTION_RECT, ACTION_LABEL, true, true)
