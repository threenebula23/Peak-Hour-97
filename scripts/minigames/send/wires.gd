extends MiniGame
## «Провода» (wires). FIX M11: порты не накладываются.
##
## Геометрия 640×360: верх стойки 56, порт 34×34, шаг 40 (34+6),
## высота стойки n*34 + (n-1)*6 + 16, низ <= 320. Левый центр x=140,
## правый x=466: 326 px между центрами, чистый коридор 292 px.
## Провода — квадратичные Безье с отдельной «полосой» на каждый провод
## (шаг 12 px), поэтому линии не сливаются.

const COLORS := {
	"accent": Color(0.184314, 0.498039, 0.560784),
	"navy": Color(0.172549, 0.360784, 0.407843),
	"warn": Color(0.772549, 0.541176, 0.180392),
	"error": Color(0.760784, 0.356863, 0.290196),
	"success": Color(0.247059, 0.560784, 0.368627),
}
const COLOR_ORDER := ["accent", "navy", "warn", "error", "success"]
const SHAPES := ["circle", "triangle", "square", "diamond", "cross"]
const TIER_SPEC := {
	1: {"wires": 3, "sockets": 3, "empty": 0},
	2: {"wires": 4, "sockets": 4, "empty": 0},
	3: {"wires": 5, "sockets": 6, "empty": 1},
	4: {"wires": 6, "sockets": 6, "empty": 0},
}
const BOX := 34.0
const PITCH := 40.0
const LEFT_X := 140.0
const RIGHT_X := 466.0
const RACK_TOP := 56.0
const LANE_STEP := 12.0

var generated: Dictionary = {}
var geo: Dictionary = {}
var _wire_sockets: Array[int] = []
var _socket_owner: Array[int] = []
var _wrong: int = 0
var _drag_wire: int = -1
var _drag_pos: Vector2 = Vector2.ZERO
var _hover_socket: int = -1
var _status: String = ""
var _status_bad: bool = false
var _key_wire: int = 0
var _key_socket: int = 0
var _keyboard_on: bool = false


func _own_game_id() -> String:
	return "wires"


func _setup() -> void:
	generated = generate(tier, seed_value)
	geo = geometry(tier)
	_wire_sockets.clear()
	_socket_owner.clear()
	for i in range(generated.get("wires", []).size()):
		_wire_sockets.append(-1)
	for i in range(generated.get("sockets", []).size()):
		_socket_owner.append(-1)
	_wrong = 0
	_drag_wire = -1
	_hover_socket = -1
	_status = ""
	_status_bad = false
	_key_wire = 0
	_key_socket = 0
	_keyboard_on = false


# --- параметры/чистая логика ----------------------------------------------

static func tier_params(p_tier: int) -> Dictionary:
	var base: Dictionary = (TIER_SPEC.get(clampi(p_tier, 1, 4), TIER_SPEC[1]) as Dictionary).duplicate(true)
	var row := MiniGame.data_minigame_tier("wires", p_tier)
	if row.is_empty():
		return base
	for key in ["wires", "sockets"]:
		if row.has(key):
			base[key] = int(row[key])
	if row.has("empty"):
		base["empty"] = int(row["empty"])
	if row.has("empty_sockets"):
		base["empty"] = int(row["empty_sockets"])
	return base


static func generate(p_tier: int, seed: int) -> Dictionary:
	var p := tier_params(p_tier)
	var wire_count := clampi(int(p.get("wires", 3)), 2, 6)
	var socket_count := clampi(int(p.get("sockets", wire_count)), wire_count, 6)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	var colors := COLOR_ORDER.duplicate()
	var shapes := SHAPES.duplicate()
	_shuffle(colors, rng)
	_shuffle(shapes, rng)
	var combos: Array = []

	match clampi(p_tier, 1, 4):
		1:
			for i in range(wire_count):
				combos.append({"color": colors[i % colors.size()],
					"shape": shapes[i % shapes.size()]})
		2:
			# Две пары похожих (повторяющихся) цветов, формы внутри пар разные.
			var c0: String = colors[0]
			var c1: String = colors[1]
			var s: Array = shapes.slice(0, 4)
			combos = [
				{"color": c0, "shape": s[0]},
				{"color": c0, "shape": s[1]},
				{"color": c1, "shape": s[2]},
				{"color": c1, "shape": s[3]},
			]
		3:
			# Один общий цвет и одна общая форма у разных пар.
			var s3: Array = shapes.slice(0, 5)
			combos = [
				{"color": colors[0], "shape": s3[0]},
				{"color": colors[0], "shape": s3[1]},
				{"color": colors[1], "shape": s3[0]},
				{"color": colors[2], "shape": s3[2]},
				{"color": colors[3], "shape": s3[3]},
			]
		_:
			# T4: 2 общих цвета + 2 общие формы, все пары уникальны.
			var s4: Array = shapes.slice(0, 4)
			combos = [
				{"color": colors[0], "shape": s4[0]},
				{"color": colors[0], "shape": s4[1]},
				{"color": colors[1], "shape": s4[0]},
				{"color": colors[1], "shape": s4[2]},
				{"color": colors[2], "shape": s4[2]},
				{"color": colors[3], "shape": s4[3]},
			]

	combos = combos.slice(0, wire_count)
	_shuffle(combos, rng)

	var wires: Array = []
	for i in range(combos.size()):
		wires.append({
			"id": i,
			"color": str(combos[i]["color"]),
			"shape": str(combos[i]["shape"]),
		})

	var socket_defs: Array = []
	for c in combos:
		socket_defs.append({"color": str(c["color"]), "shape": str(c["shape"]),
			"empty": false})
	while socket_defs.size() < socket_count:
		socket_defs.append({"color": "", "shape": "", "empty": true})
	_shuffle(socket_defs, rng)
	var sockets: Array = []
	for i in range(socket_defs.size()):
		sockets.append({
			"id": i,
			"color": str(socket_defs[i]["color"]),
			"shape": str(socket_defs[i]["shape"]),
			"empty": bool(socket_defs[i]["empty"]),
		})

	return {
		"tier": clampi(p_tier, 1, 4),
		"wires": wires,
		"sockets": sockets,
		"wire_count": wires.size(),
		"socket_count": sockets.size(),
	}


static func geometry(p_tier: int) -> Dictionary:
	var p := tier_params(p_tier)
	var n := clampi(int(p.get("wires", 3)), 2, 6)
	var s := clampi(int(p.get("sockets", n)), n, 6)
	var rack_h := float(n) * BOX + float(n - 1) * 6.0 + 16.0
	var right_h := float(s) * BOX + float(s - 1) * 6.0 + 16.0
	var left_ports: Array[Vector2] = []
	var right_ports: Array[Vector2] = []
	for i in range(n):
		left_ports.append(Vector2(LEFT_X, RACK_TOP + 8.0 + BOX * 0.5 + float(i) * PITCH))
	for i in range(s):
		right_ports.append(Vector2(RIGHT_X, RACK_TOP + 8.0 + BOX * 0.5 + float(i) * PITCH))
	var left_rects: Array[Rect2] = []
	var right_rects: Array[Rect2] = []
	for center in left_ports:
		left_rects.append(Rect2(center - Vector2(BOX, BOX) * 0.5, Vector2(BOX, BOX)))
	for center in right_ports:
		right_rects.append(Rect2(center - Vector2(BOX, BOX) * 0.5, Vector2(BOX, BOX)))
	var lanes: Array[float] = []
	for i in range(n):
		lanes.append((float(i) - float(n - 1) * 0.5) * LANE_STEP)
	return {
		"box": BOX,
		"pitch": PITCH,
		"left_x": LEFT_X,
		"right_x": RIGHT_X,
		"top": RACK_TOP,
		"left_rack": Rect2(LEFT_X - BOX * 0.5, RACK_TOP, BOX, rack_h),
		"right_rack": Rect2(RIGHT_X - BOX * 0.5, RACK_TOP, BOX, right_h),
		"rack_h": rack_h,
		"right_rack_h": right_h,
		"left_ports": left_ports,
		"right_ports": right_ports,
		"left_rects": left_rects,
		"right_rects": right_rects,
		"lanes": lanes,
		"gap": RIGHT_X - LEFT_X,
		"edge_gap": (RIGHT_X - BOX * 0.5) - (LEFT_X + BOX * 0.5),
	}


static func matching_sockets(wire: Dictionary, sockets: Array) -> Array:
	var out: Array = []
	for socket in sockets:
		if bool(socket.get("empty", false)):
			continue
		if str(socket.get("color", "")) == str(wire.get("color", "")) \
				and str(socket.get("shape", "")) == str(wire.get("shape", "")):
			out.append(int(socket.get("id", out.size())))
	return out


static func validate_pairs(data: Dictionary) -> bool:
	var wires: Array = data.get("wires", [])
	var sockets: Array = data.get("sockets", [])
	if wires.is_empty() or sockets.size() < wires.size():
		return false
	var seen_pairs := {}
	for wire in wires:
		var key := "%s|%s" % [str(wire.get("color", "")), str(wire.get("shape", ""))]
		if seen_pairs.has(key):
			return false
		seen_pairs[key] = true
		var matches := matching_sockets(wire, sockets)
		if matches.size() != 1:
			return false
	return true


static func quality_for(connected: int, wrong: int, total: int) -> float:
	if total <= 0:
		return 0.0
	return clampf((float(connected) - 0.25 * float(maxi(0, wrong))) / float(total),
		0.0, 1.0)


static func _shuffle(list: Array, p_rng: RandomNumberGenerator) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := p_rng.randi_range(0, i)
		var tmp = list[i]
		list[i] = list[j]
		list[j] = tmp


# --- игра ------------------------------------------------------------------


func _left_center(i: int) -> Vector2:
	var ports: Array = geo.get("left_ports", [])
	return ports[i] if i >= 0 and i < ports.size() else Vector2(LEFT_X, RACK_TOP)


func _right_center(i: int) -> Vector2:
	var ports: Array = geo.get("right_ports", [])
	return ports[i] if i >= 0 and i < ports.size() else Vector2(RIGHT_X, RACK_TOP)


func _wire_at(local: Vector2) -> int:
	var rects: Array = geo.get("left_rects", [])
	for i in range(rects.size()):
		if (rects[i] as Rect2).grow(6.0).has_point(local):
			return i
	return -1


func _socket_at(local: Vector2) -> int:
	var rects: Array = geo.get("right_rects", [])
	for i in range(rects.size()):
		if (rects[i] as Rect2).grow(6.0).has_point(local):
			return i
	return -1


func _connected_count() -> int:
	var n := 0
	for s in _wire_sockets:
		if s >= 0:
			n += 1
	return n


func _matches(wi: int, si: int) -> bool:
	var wires: Array = generated.get("wires", [])
	var sockets: Array = generated.get("sockets", [])
	if wi < 0 or wi >= wires.size() or si < 0 or si >= sockets.size():
		return false
	var wire: Dictionary = wires[wi]
	var socket: Dictionary = sockets[si]
	if bool(socket.get("empty", false)):
		return false
	if _socket_owner[si] >= 0:
		return false
	return str(wire["color"]) == str(socket["color"]) \
		and str(wire["shape"]) == str(socket["shape"])


func _connect(wi: int, si: int) -> bool:
	if _matches(wi, si):
		if _wire_sockets[wi] >= 0:
			_socket_owner[_wire_sockets[wi]] = -1
		_wire_sockets[wi] = si
		_socket_owner[si] = wi
		_status = "ПОДКЛЮЧЕНО: %d ИЗ %d" % [_connected_count(), _wire_sockets.size()]
		_status_bad = false
		_play_sfx(&"minigame_win")
		queue_redraw()
		if _connected_count() == _wire_sockets.size():
			_finish(quality_for(_connected_count(), _wrong, _wire_sockets.size()))
		return true
	_wrong += 1
	_status_bad = true
	var sockets: Array = generated.get("sockets", [])
	if si >= 0 and si < sockets.size() and bool((sockets[si] as Dictionary).get("empty", false)):
		_status = "ГНЕЗДО ПУСТОЕ · +1 ОШИБКА"
	elif si >= 0 and si < _socket_owner.size() and _socket_owner[si] >= 0:
		_status = "ГНЕЗДО ЗАНЯТО · +1 ОШИБКА"
	else:
		_status = "НЕ СОВПАЛО: НУЖНЫ ТОТ ЖЕ ЦВЕТ И ФОРМА · +1 ОШИБКА"
	_play_sfx(&"minigame_fail")
	queue_redraw()
	return false


func _on_pointer_pressed(local: Vector2, _event: InputEvent) -> bool:
	var wi := _wire_at(local)
	if wi < 0:
		return false
	_keyboard_on = false
	if _wire_sockets[wi] >= 0:
		_socket_owner[_wire_sockets[wi]] = -1
		_wire_sockets[wi] = -1
	_drag_wire = wi
	_drag_pos = local
	_hover_socket = -1
	_play_sfx(&"tick")
	queue_redraw()
	return true


func _on_pointer_moved(local: Vector2, _event: InputEvent) -> void:
	if _drag_wire < 0:
		return
	_drag_pos = local
	_hover_socket = _socket_at(local)
	queue_redraw()


func _on_pointer_released(local: Vector2, _event: InputEvent) -> void:
	if _drag_wire < 0:
		return
	var wi := _drag_wire
	_drag_wire = -1
	_hover_socket = -1
	var si := _socket_at(local)
	if si < 0:
		# Отпускание в пустоту — бесплатно.
		queue_redraw()
		return
	_connect(wi, si)


func _on_key_pressed(keycode: int, _event: InputEvent) -> bool:
	if keycode == KEY_E or keycode == KEY_ENTER:
		if _keyboard_on:
			_connect(_key_wire, _key_socket)
		else:
			var wi := _wire_at(get_local_mouse_position())
			var si := _socket_at(get_local_mouse_position())
			if wi >= 0 and si >= 0:
				_connect(wi, si)
		return true
	if keycode == KEY_UP or keycode == KEY_W or keycode == KEY_TAB:
		_keyboard_on = true
		_key_wire = posmod(_key_wire - 1, maxi(1, _wire_sockets.size()))
		queue_redraw()
		return true
	if keycode == KEY_DOWN or keycode == KEY_S:
		_keyboard_on = true
		_key_wire = (_key_wire + 1) % maxi(1, _wire_sockets.size())
		queue_redraw()
		return true
	if keycode == KEY_LEFT or keycode == KEY_A:
		_keyboard_on = true
		_key_socket = posmod(_key_socket - 1, maxi(1, _socket_owner.size()))
		queue_redraw()
		return true
	if keycode == KEY_RIGHT or keycode == KEY_D:
		_keyboard_on = true
		_key_socket = (_key_socket + 1) % maxi(1, _socket_owner.size())
		queue_redraw()
		return true
	return false


# --- отрисовка -------------------------------------------------------------

func _draw_game() -> void:
	var left_rack: Rect2 = geo.get("left_rack", Rect2())
	var right_rack: Rect2 = geo.get("right_rack", Rect2())
	_draw_label("ПОДКЛЮЧЕНО %d / %d" % [_connected_count(), _wire_sockets.size()],
		Vector2(24.0, 46.0), 10, Theme90.NAVY, 240.0)
	_draw_label("ОШИБОК %d · ПРОВОДОВ %d · ГНЁЗД %d" % [_wrong,
		_wire_sockets.size(), _socket_owner.size()],
		Vector2(320.0, 46.0), 10, Theme90.SHADE, 280.0,
		HORIZONTAL_ALIGNMENT_RIGHT)

	draw_style_box(Theme90.box(Theme90.PAPER_LO, Theme90.BORDER_SOFT, 4, 1),
		left_rack.grow(6.0))
	draw_style_box(Theme90.box(Theme90.PAPER_LO, Theme90.BORDER_SOFT, 4, 1),
		right_rack.grow(6.0))

	# Сначала уже подключённые кабели.
	var wires: Array = generated.get("wires", [])
	var sockets: Array = generated.get("sockets", [])
	var lanes: Array = geo.get("lanes", [])
	for wi in range(_wire_sockets.size()):
		var si := _wire_sockets[wi]
		if si < 0:
			continue
		var wire: Dictionary = wires[wi]
		var lane := float(lanes[wi]) if wi < lanes.size() else 0.0
		_draw_cable(_left_center(wi) + Vector2(BOX * 0.5, 0.0),
			_right_center(si) - Vector2(BOX * 0.5, 0.0),
			_color_of(str(wire["color"])), lane)

	if _drag_wire >= 0 and _drag_wire < wires.size():
		var wire: Dictionary = wires[_drag_wire]
		var lane := float(lanes[_drag_wire]) if _drag_wire < lanes.size() else 0.0
		_draw_cable(_left_center(_drag_wire) + Vector2(BOX * 0.5, 0.0),
			_drag_pos, _color_of(str(wire["color"])), lane * 0.8)

	for wi in range(wires.size()):
		var wire: Dictionary = wires[wi]
		var center := _left_center(wi)
		var rect := Rect2(center - Vector2(BOX, BOX) * 0.5, Vector2(BOX, BOX))
		var col := _color_of(str(wire["color"]))
		var connected := _wire_sockets[wi] >= 0
		draw_style_box(Theme90.box(col.lightened(0.70), col, 4, 1,
			Theme90.SHADOW), rect)
		_draw_shape(center, 18.0, str(wire["shape"]), col)
		if connected:
			draw_circle(Vector2(rect.end.x - 5.0, rect.position.y + 5.0), 3.0,
				Theme90.SUCCESS)
		if wi == _drag_wire:
			draw_rect(rect.grow(3.0), Theme90.NAVY_DEEP, false, 2.0)
		if _keyboard_on and wi == _key_wire:
			Theme90.draw_dashed_box(self, rect.grow(4.0), Theme90.NAVY, 3.0, 1.0)

	for si in range(sockets.size()):
		var socket: Dictionary = sockets[si]
		var center := _right_center(si)
		var rect := Rect2(center - Vector2(BOX, BOX) * 0.5, Vector2(BOX, BOX))
		if bool(socket.get("empty", false)):
			Theme90.draw_dashed_box(self, rect, Theme90.SHADE, 3.0, 1.0)
			_draw_label("—", Vector2(center.x - 5.0, center.y - 7.0), 16,
				Theme90.SHADE)
			continue
		var col := _color_of(str(socket["color"]))
		var hover := si == _hover_socket and _drag_wire >= 0
		draw_style_box(Theme90.box(Theme90.PAPER_HI if not hover else Theme90.ACCENT_PALE,
			col if not hover else Theme90.ACCENT, 4, 2 if hover else 1), rect)
		_draw_shape(center, 18.0, str(socket["shape"]), col.darkened(0.05))
		if _socket_owner[si] >= 0:
			draw_circle(Vector2(rect.end.x - 5.0, rect.position.y + 5.0), 3.0,
				Theme90.SUCCESS)
		if _keyboard_on and si == _key_socket:
			Theme90.draw_dashed_box(self, rect.grow(4.0), Theme90.NAVY, 3.0, 1.0)

	if _status.is_empty():
		_status = "ТЯНИТЕ ПРОВОД СЛЕВА В ПРАВОЕ ГНЕЗДО: ЦВЕТ + ФОРМА"
	_draw_label(_status, Vector2(24.0, 344.0), 10,
		Theme90.ERROR if _status_bad else Theme90.SHADE, 430.0)
	if _status_bad:
		_draw_label("+0.25 ШТРАФА", Vector2(466.0, 344.0), 10, Theme90.ERROR,
			156.0, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_cable(from: Vector2, to: Vector2, color: Color, lane: float) -> void:
	var mid := (from + to) * 0.5
	var control := Vector2(mid.x, mid.y + lane)
	var points := PackedVector2Array()
	for i in range(25):
		var t := float(i) / 24.0
		var p := from.lerp(control, t).lerp(control.lerp(to, t), t)
		points.append(p)
	draw_polyline(points, color, 3.0, true)


func _draw_shape(center: Vector2, size: float, shape: String, color: Color) -> void:
	match shape:
		"circle":
			draw_circle(center, size * 0.55, color)
		"triangle":
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(0, -size * 0.62),
				center + Vector2(size * 0.60, size * 0.42),
				center + Vector2(-size * 0.60, size * 0.42)]), color)
		"square":
			draw_rect(Rect2(center - Vector2(size, size) * 0.48,
				Vector2(size, size) * 0.96), color)
		"diamond":
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(0, -size * 0.66),
				center + Vector2(size * 0.66, 0),
				center + Vector2(0, size * 0.66),
				center + Vector2(-size * 0.66, 0)]), color)
		_:
			draw_rect(Rect2(center - Vector2(size * 0.16, size * 0.62),
				Vector2(size * 0.32, size * 1.24)), color)
			draw_rect(Rect2(center - Vector2(size * 0.62, size * 0.16),
				Vector2(size * 1.24, size * 0.32)), color)


func _color_of(id: String) -> Color:
	return COLORS.get(id, Theme90.ACCENT)
