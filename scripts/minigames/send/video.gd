extends MiniGame
## «Раскадровка» (video). Разложить кадры по слотам.
##
## T1 4/4 (таймкод), T2 5 карточек/4 слота (1 скрытый брак),
## T3 6 карточек/5 слотов (1 брак + 1 зеркальный кадр).
## Таймкоды случайны для каждой раздачи, брак дублирует ровно один реальный
## таймкод и отличается силуэтом.

const TIERS := {
	1: {"cards": 4, "slots": 4, "decoy": false, "mirror": false, "hint": "timecode"},
	2: {"cards": 5, "slots": 4, "decoy": true, "mirror": false, "hint": "ghost"},
	3: {"cards": 6, "slots": 5, "decoy": true, "mirror": true, "hint": "timecode"},
}
const SHAPES := ["circle", "triangle", "square", "diamond", "cross"]
const COLORS := ["accent", "warn", "success", "error", "navy"]
const COLOR_HEX := {
	"accent": Color(0.184314, 0.498039, 0.560784),
	"warn": Color(0.772549, 0.541176, 0.180392),
	"success": Color(0.247059, 0.560784, 0.368627),
	"error": Color(0.760784, 0.356863, 0.290196),
	"navy": Color(0.172549, 0.360784, 0.407843),
}

var generated: Dictionary = {}
var _cards: Array = []
var _selected: int = -1
var _card_slot: Array[int] = []
var _slot_rects: Array[Rect2] = []
var _tray_rects: Array = []


func _own_game_id() -> String:
	return "video"


func _setup() -> void:
	generated = generate(tier, seed_value)
	_cards = []
	for card in generated.get("cards", []):
		_cards.append((card as Dictionary).duplicate(true))
	_card_slot.clear()
	for i in range(_cards.size()):
		_card_slot.append(-1)
	_selected = -1
	_build_slot_rects()


func _goal_text() -> String:
	return "РАЗЛОЖИТЕ КАДРЫ ПО СЛОТАМ · КАДР → СЛОТ · ОТПРАВИТЬ"


func _progress_ratio() -> float:
	var slots := int(generated.get("slots", 0))
	if slots <= 0:
		return 0.0
	return clampf(float(_occupied_slots()) / float(slots), 0.0, 1.0)


func _result_stats() -> String:
	var c := _counts()
	return "ВЕРНО %d ИЗ %d · ОШИБОК %d · БРАК %d" % [int(c["correct"]),
		int(generated.get("slots", 0)), int(c["wrong"]), int(c["decoys"])]


# --- параметры/чистая логика ----------------------------------------------

static func tier_params(p_tier: int) -> Dictionary:
	var base: Dictionary = (TIERS.get(clampi(p_tier, 1, 3), TIERS[1]) as Dictionary).duplicate(true)
	var row := MiniGame.data_minigame_tier("video", p_tier)
	if row.is_empty():
		return base
	if row.has("frames"):
		base["cards"] = int(row["frames"])
	if row.has("cards"):
		base["cards"] = int(row["cards"])
	if row.has("slots"):
		base["slots"] = int(row["slots"])
	if row.has("decoy"):
		base["decoy"] = bool(row["decoy"])
	if row.has("decoys"):
		base["decoy"] = int(row["decoys"]) > 0
	if row.has("mirror"):
		base["mirror"] = bool(row["mirror"])
	return base


static func generate(p_tier: int, seed: int) -> Dictionary:
	var p := tier_params(p_tier)
	var slots := clampi(int(p.get("slots", 3)), 2, 5)
	var cards_total := clampi(int(p.get("cards", slots)), slots, 7)
	var want_decoy := bool(p.get("decoy", false)) and cards_total > slots
	var want_mirror := bool(p.get("mirror", false))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	var shape_pool := SHAPES.duplicate()
	var color_pool := COLORS.duplicate()
	_shuffle(shape_pool, rng)
	_shuffle(color_pool, rng)

	# Таймкоды: случайная стартовая секунда и случайные интервалы; слот i
	# получает i-й по возрастанию таймкод, поэтому порядок не фиксирован.
	var seconds := rng.randi_range(0, 18)
	var timecodes: Array[String] = []
	for i in range(slots):
		timecodes.append("00:%02d" % seconds)
		seconds += rng.randi_range(2, 7)
	var slot_shapes: Array = []
	var cards: Array = []
	var mirror_index := -1
	if want_mirror:
		mirror_index = rng.randi_range(0, slots - 1)
	for i in range(slots):
		var shape := str(shape_pool[i % shape_pool.size()])
		var color := str(color_pool[i % color_pool.size()])
		var mirrored := i == mirror_index
		if mirrored and shape == "circle":
			# Зеркало заметно только на несимметричной фигуре.
			shape = "triangle"
		slot_shapes.append({"shape": shape, "color": color, "timecode": timecodes[i]})
		cards.append({
			"id": cards.size(),
			"timecode": timecodes[i],
			"shape": shape,
			"color": color,
			"correct_slot": i,
			"decoy": false,
			"mirrored": mirrored,
		})

	if want_decoy:
		var source_slot := rng.randi_range(0, slots - 1)
		var source: Dictionary = cards[source_slot]
		var decoy_shape := str(source["shape"])
		var candidates: Array = []
		for s in SHAPES:
			if str(s) != decoy_shape:
				candidates.append(str(s))
		decoy_shape = str(candidates[rng.randi_range(0, candidates.size() - 1)])
		cards.append({
			"id": cards.size(),
			"timecode": str(source["timecode"]),
			"shape": decoy_shape,
			"color": str(source["color"]),
			"correct_slot": -1,
			"decoy": true,
			"mirrored": false,
		})

	# В лотке карточки перемешаны; брак не первый и не последний.
	var tray := cards.duplicate(true)
	_shuffle(tray, rng)
	if want_decoy and tray.size() > 2:
		var decoy_idx := -1
		for i in range(tray.size()):
			if bool((tray[i] as Dictionary).get("decoy", false)):
				decoy_idx = i
				break
		if decoy_idx == 0 or decoy_idx == tray.size() - 1:
			var safe_idx := rng.randi_range(1, tray.size() - 2)
			var tmp = tray[decoy_idx]
			tray[decoy_idx] = tray[safe_idx]
			tray[safe_idx] = tmp

	return {
		"tier": clampi(p_tier, 1, 3),
		"slots": slots,
		"cards": tray,
		"card_count": tray.size(),
		"slot_timecodes": timecodes,
		"slot_shapes": slot_shapes,
		"hint": str(p.get("hint", "timecode")),
		"has_decoy": want_decoy,
		"has_mirror": want_mirror,
	}


static func quality_from(slots: int, correct: int, wrong: int, decoys_in_slot: int) -> float:
	if slots <= 0:
		return 0.0
	return clampf((float(correct) - 0.5 * float(maxi(0, wrong))
		- float(maxi(0, decoys_in_slot))) / float(slots), 0.0, 1.0)


static func _shuffle(list: Array, p_rng: RandomNumberGenerator) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := p_rng.randi_range(0, i)
		var tmp = list[i]
		list[i] = list[j]
		list[j] = tmp


static func decoy_info(data: Dictionary) -> Dictionary:
	var cards: Array = data.get("cards", [])
	var counts := {}
	for card in cards:
		var tc := str(card.get("timecode", ""))
		counts[tc] = int(counts.get(tc, 0)) + 1
	for card in cards:
		if not bool(card.get("decoy", false)):
			continue
		var tc := str(card.get("timecode", ""))
		var duplicate_real := -1
		for other in cards:
			if other == card or bool(other.get("decoy", false)):
				continue
			if str(other.get("timecode", "")) == tc:
				duplicate_real = int(other.get("id", -1))
				break
		return {
			"decoy_timecode": tc,
			"duplicate_real": duplicate_real,
			"decoy_shape": str(card.get("shape", "")),
			"duplicate_count": int(counts.get(tc, 0)),
		}
	return {"decoy_timecode": "", "duplicate_real": -1, "decoy_shape": "",
		"duplicate_count": 0}


# --- раскладка/игра --------------------------------------------------------

func _build_slot_rects() -> void:
	_slot_rects.clear()
	var slots := int(generated.get("slots", 3))
	var area := Rect2(40.0, 62.0, 560.0, 128.0)
	var gap := 10.0
	var w := (area.size.x - gap * float(maxi(0, slots - 1))) / float(maxi(1, slots))
	for i in range(slots):
		_slot_rects.append(Rect2(area.position.x + float(i) * (w + gap),
			area.position.y, w, area.size.y))


func _recompute_tray() -> void:
	_tray_rects.clear()
	var visible: Array = []
	for i in range(_cards.size()):
		if _card_slot[i] < 0:
			visible.append(i)
	var card_w := 84.0
	var card_h := 96.0
	var gap := 8.0
	var total := float(visible.size()) * card_w + float(maxi(0, visible.size() - 1)) * gap
	var x := 320.0 - total * 0.5
	for idx in visible:
		_tray_rects.append({"card": int(idx), "rect": Rect2(x, 224.0, card_w, card_h)})
		x += card_w + gap


func _slot_at(local: Vector2) -> int:
	for i in range(_slot_rects.size()):
		if _slot_rects[i].has_point(local):
			return i
	return -1


func _card_at(local: Vector2) -> int:
	_recompute_tray()
	for entry in _tray_rects:
		if (entry["rect"] as Rect2).has_point(local):
			return int(entry["card"])
	return -1


func _counts() -> Dictionary:
	var correct := 0
	var wrong := 0
	var decoys := 0
	for i in range(_cards.size()):
		var slot := _card_slot[i]
		if slot < 0:
			continue
		var card: Dictionary = _cards[i]
		if bool(card.get("decoy", false)):
			decoys += 1
		elif slot == int(card.get("correct_slot", -2)):
			correct += 1
		else:
			wrong += 1
	return {"correct": correct, "wrong": wrong, "decoys": decoys}


func _quality_now() -> float:
	var c := _counts()
	return quality_from(int(generated.get("slots", 3)), int(c["correct"]),
		int(c["wrong"]), int(c["decoys"]))


func _on_pointer_pressed(local: Vector2, _event: InputEvent) -> bool:
	if ACTION_RECT.has_point(local):
		_finish(_quality_now())
		return true
	var si := _slot_at(local)
	if si >= 0:
		# Клик по занятому слоту возвращает кадр в лоток.
		for i in range(_cards.size()):
			if _card_slot[i] == si:
				_card_slot[i] = -1
				_selected = -1
				_play_sfx(&"tick")
				queue_redraw()
				return true
		if _selected >= 0:
			_card_slot[_selected] = si
			_selected = -1
			_play_sfx(&"tick")
			queue_redraw()
		return true
	var ci := _card_at(local)
	if ci >= 0:
		_selected = -1 if _selected == ci else ci
		_play_sfx(&"tick")
		queue_redraw()
		return true
	return false


func _on_key_pressed(keycode: int, _event: InputEvent) -> bool:
	if keycode == KEY_ENTER or keycode == KEY_KP_ENTER:
		_finish(_quality_now())
		return true
	return false


func _draw_game() -> void:
	var font := Theme90.ui()
	var slots := int(generated.get("slots", 3))
	var hint := str(generated.get("hint", "timecode"))
	var c := _counts()
	_draw_label("РАСКАДРОВКА · СЛОЙ 97", Vector2(24.0, 46.0), 10,
		Theme90.ACCENT, 260.0)
	_draw_label("РАЗМЕЩЕНО %d / %d · ОШИБОК %d · БРАК %d" % [
		_occupied_slots(), slots, int(c["wrong"]), int(c["decoys"])],
		Vector2(300.0, 46.0), 10, Theme90.DARK, 300.0,
		HORIZONTAL_ALIGNMENT_RIGHT)

	var slot_shapes: Array = generated.get("slot_shapes", [])
	for i in range(slots):
		var rect := _slot_rects[i]
		draw_style_box(Theme90.box(Theme90.PAPER_HI, Theme90.BORDER, 3, 1), rect)
		draw_rect(Rect2(rect.position.x + 1.0, rect.position.y + 20.0,
			rect.size.x - 2.0, 1.0), Theme90.HAIRLINE)
		_draw_label("СЛОТ %02d" % (i + 1), Vector2(rect.position.x + 8.0,
			rect.position.y + 5.0), 10, Theme90.ACCENT, rect.size.x - 16.0)
		var occupant := -1
		for ci in range(_cards.size()):
			if _card_slot[ci] == i:
				occupant = ci
				break
		if occupant >= 0:
			_draw_card(_cards[occupant], Rect2(rect.position + Vector2(8, 28),
				rect.size - Vector2(16, 36)), true, hint)
			_draw_label("КЛИК — ВЕРНУТЬ", Vector2(rect.position.x, rect.end.y - 14.0),
				10, Theme90.DARK, rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)
			continue
		Theme90.draw_dashed_box(self, Rect2(rect.position + Vector2(8, 28),
			rect.size - Vector2(16, 36)), Theme90.BORDER_SOFT, 3.0, 1.0)
		if i < slot_shapes.size():
			var ghost: Dictionary = slot_shapes[i]
			var gshape := str(ghost.get("shape", "circle"))
			var gcol: Color = COLOR_HEX.get(str(ghost.get("color", "accent")),
				Theme90.NAVY)
			if hint == "shape" or hint == "ghost":
				_draw_frame_shape(Vector2(rect.get_center().x, rect.position.y + 72.0),
					34.0, gshape, Color(gcol.r, gcol.g, gcol.b, 0.50), false)
			if hint != "shape":
				_draw_centered(str(ghost.get("timecode", "")),
					Rect2(rect.position.x, rect.end.y - 34.0, rect.size.x, 24.0),
					16 if hint == "ghost" else 24, Theme90.NAVY)
			else:
				_draw_centered(str(ghost.get("timecode", "")),
					Rect2(rect.position.x, rect.end.y - 30.0, rect.size.x, 20.0),
					10, Theme90.DARK)

	_recompute_tray()
	for entry in _tray_rects:
		var card: Dictionary = _cards[int(entry["card"])]
		var rect: Rect2 = entry["rect"]
		if int(entry["card"]) == _selected:
			rect.position.y -= 4.0
		_draw_card(card, rect, false, hint)
		if int(entry["card"]) == _selected:
			draw_rect(rect.grow(3.0), Theme90.NAVY_DEEP, false, 2.0)

	_draw_action_button(ACTION_RECT, "ОТПРАВИТЬ", true, true)


func _empty_slots() -> int:
	var n := 0
	for i in range(_cards.size()):
		if _card_slot[i] < 0:
			n += 1
	return n


func _occupied_slots() -> int:
	var n := 0
	for i in range(_cards.size()):
		if _card_slot[i] >= 0:
			n += 1
	return mini(n, int(generated.get("slots", 3)))


func _draw_card(card: Dictionary, rect: Rect2, in_slot: bool, hint: String) -> void:
	var col: Color = COLOR_HEX.get(str(card.get("color", "accent")), Theme90.ACCENT)
	draw_style_box(Theme90.box(col, Theme90.BORDER, 3, 1), rect)
	var center := Vector2(rect.get_center().x, rect.position.y + rect.size.y * 0.46)
	_draw_frame_shape(center, minf(rect.size.y * 0.34, 38.0),
		str(card.get("shape", "circle")), Color(1, 1, 1, 0.90),
		bool(card.get("mirrored", false)))
	var label := str(card.get("timecode", ""))
	if hint == "shape" and not in_slot:
		label = "КАДР"
	_draw_centered(label, Rect2(rect.position.x, rect.end.y - 25.0, rect.size.x, 20.0),
		12 if rect.size.x >= 90.0 else 10, Theme90.WHITE)


func _draw_frame_shape(center: Vector2, s: float, shape: String, color: Color,
		mirrored: bool) -> void:
	var flip := -1.0 if mirrored else 1.0
	match shape:
		"circle":
			draw_circle(center, s * 0.52, color)
		"triangle":
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(0, -s * 0.62) * Vector2(flip, 1),
				center + Vector2(s * 0.58, s * 0.40) * Vector2(flip, 1),
				center + Vector2(-s * 0.58, s * 0.40) * Vector2(flip, 1)]), color)
		"square":
			draw_rect(Rect2(center - Vector2(s, s) * 0.46, Vector2(s, s) * 0.92), color)
		"diamond":
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(0, -s * 0.64) * Vector2(flip, 1),
				center + Vector2(s * 0.64, 0) * Vector2(flip, 1),
				center + Vector2(0, s * 0.64) * Vector2(flip, 1),
				center + Vector2(-s * 0.64, 0) * Vector2(flip, 1)]), color)
		_:
			draw_rect(Rect2(center - Vector2(s * 0.15, s * 0.60),
				Vector2(s * 0.30, s * 1.20)), color)
			draw_rect(Rect2(center - Vector2(s * 0.60, s * 0.15),
				Vector2(s * 1.20, s * 0.30)), color)
