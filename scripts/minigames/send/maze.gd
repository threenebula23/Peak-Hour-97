extends MiniGame
## «Лабиринт» (maze). Recursive backtracker + BFS-валидация.
## Пакет следует за мышью с максимальной скоростью, скользит по осям.
## Качество: 1 - 0.04*collisions - 0.02*dead_ends (без нижнего порога 0.4).

const TIERS := {
	1: {"cols": 11, "rows": 4, "field_w": 440.0, "field_h": 160.0,
		"corridor": 24.0, "speed": 470.0},
	2: {"cols": 13, "rows": 4, "field_w": 494.0, "field_h": 152.0,
		"corridor": 20.0, "speed": 520.0},
	3: {"cols": 15, "rows": 5, "field_w": 520.0, "field_h": 180.0,
		"corridor": 18.0, "speed": 560.0},
}
const HITBOX := 9.0
const PACKET := 12.0
const LOOP_CHANCE := 0.12
const COLLISION_COOLDOWN := 0.25

var maze: Dictionary = {}
var params: Dictionary = {}
var _walls: Array[Rect2] = []
var _field: Rect2 = Rect2()
var _pitch: float = 20.0
var _corridor: float = 20.0
var _solution: Array = []
var _sol_index: Dictionary = {}
var _dead_ends: Dictionary = {}
var _packet: Vector2 = Vector2.ZERO
var _target: Vector2 = Vector2.ZERO
var _entrance: Vector2 = Vector2.ZERO
var _exit: Vector2 = Vector2.ZERO
var _collisions: int = 0
var _dead_end_hits: int = 0
var _visited_dead: Dictionary = {}
var _collision_cd: float = 0.0
var _max_sol: int = 0
var _exited: bool = false


func _own_game_id() -> String:
	return "maze"


func _setup() -> void:
	params = tier_params(tier)
	maze = generate_tier(tier, seed_value)
	_pitch = float(params["field_w"]) / float(maze["cols"])
	_corridor = float(params["corridor"])
	_field = Rect2((640.0 - float(params["field_w"])) * 0.5,
		70.0 + (180.0 - float(params["field_h"])) * 0.5,
		float(params["field_w"]), float(params["field_h"]))
	_walls = build_walls(maze["cells"], int(maze["cols"]), int(maze["rows"]),
		int(maze["ent_row"]), int(maze["exit_row"]), _field, _corridor)
	_solution = maze.get("solution", [])
	_sol_index.clear()
	for i in range(_solution.size()):
		_sol_index[int(_solution[i])] = i
	_entrance = Vector2(_field.position.x + _pitch * 0.5,
		_field.position.y + (float(maze["ent_row"]) + 0.5) * _pitch)
	_exit = Vector2(_field.end.x - _pitch * 0.5,
		_field.position.y + (float(maze["exit_row"]) + 0.5) * _pitch)
	_packet = _entrance
	_target = _entrance
	_collisions = 0
	_dead_end_hits = 0
	_visited_dead.clear()
	_collision_cd = 0.0
	_max_sol = 0
	_exited = false
	_dead_ends = find_dead_ends(maze["cells"], int(maze["cols"]), int(maze["rows"]),
		int(maze["ent_row"]), int(maze["exit_row"]))


func _goal_text() -> String:
	return "ПРОВЕДИТЕ ПАКЕТ ОТ ВХОДА ДО ЗЕЛЁНОГО ВЫХОДА"


func _progress_ratio() -> float:
	if _solution.is_empty():
		return 0.0
	return clampf((float(_max_sol) + 1.0) / float(_solution.size()), 0.0, 1.0)


func _result_stats() -> String:
	return "СТОЛКНОВЕНИЙ %d · ТУПИКОВ %d" % [_collisions, _dead_end_hits]


# --- параметры/генерация ---------------------------------------------------

static func tier_params(p_tier: int) -> Dictionary:
	var base: Dictionary = (TIERS.get(clampi(p_tier, 1, 3), TIERS[1]) as Dictionary).duplicate(true)
	var row := MiniGame.data_minigame_tier("maze", p_tier)
	if row.is_empty():
		return base
	for key in ["cols", "rows"]:
		if row.has(key):
			base[key] = int(row[key])
	if row.has("width"):
		base["field_w"] = float(row["width"])
	if row.has("height"):
		base["field_h"] = float(row["height"])
	for key in ["field_w", "field_h", "corridor", "speed"]:
		if row.has(key):
			base[key] = float(row[key])
	if row.has("speed"):
		base["speed"] = float(row["speed"])
	return base


static func generate_tier(p_tier: int, seed: int) -> Dictionary:
	var p := tier_params(p_tier)
	var temp := RandomNumberGenerator.new()
	temp.seed = seed
	var ent_row := temp.randi_range(0, int(p["rows"]) - 1)
	var exit_row := temp.randi_range(0, int(p["rows"]) - 1)
	return generate(int(p["cols"]), int(p["rows"]), seed, ent_row, exit_row)


static func generate(cols: int, rows: int, seed: int, ent_row: int = -1,
		exit_row: int = -1) -> Dictionary:
	var c := maxi(3, cols)
	var r := maxi(2, rows)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var ent := clampi(ent_row if ent_row >= 0 else rng.randi_range(0, r - 1), 0, r - 1)
	var ex := clampi(exit_row if exit_row >= 0 else rng.randi_range(0, r - 1), 0, r - 1)

	var cells: Array = []
	for y in range(r):
		var row: Array = []
		for x in range(c):
			row.append({"n": true, "e": true, "s": true, "w": true, "v": false})
		cells.append(row)

	var stack: Array = [Vector2i(0, ent)]
	cells[ent][0]["v"] = true
	var visited := 1
	while visited < c * r:
		var top: Vector2i = stack[stack.size() - 1]
		var near: Array = []
		if top.y > 0 and not bool(cells[top.y - 1][top.x]["v"]):
			near.append([top.x, top.y - 1, "n", "s"])
		if top.x < c - 1 and not bool(cells[top.y][top.x + 1]["v"]):
			near.append([top.x + 1, top.y, "e", "w"])
		if top.y < r - 1 and not bool(cells[top.y + 1][top.x]["v"]):
			near.append([top.x, top.y + 1, "s", "n"])
		if top.x > 0 and not bool(cells[top.y][top.x - 1]["v"]):
			near.append([top.x - 1, top.y, "w", "e"])
		if near.is_empty():
			stack.pop_back()
			continue
		var pick: Array = near[rng.randi_range(0, near.size() - 1)]
		cells[top.y][top.x][str(pick[2])] = false
		cells[int(pick[1])][int(pick[0])][str(pick[3])] = false
		cells[int(pick[1])][int(pick[0])]["v"] = true
		visited += 1
		stack.append(Vector2i(int(pick[0]), int(pick[1])))

	# Петли: аккуратно убираем часть внутренних стен (10–20%).
	for y in range(r):
		for x in range(c):
			if x < c - 1 and bool(cells[y][x]["e"]) and rng.randf() < LOOP_CHANCE:
				cells[y][x]["e"] = false
				cells[y][x + 1]["w"] = false
			if y < r - 1 and bool(cells[y][x]["s"]) and rng.randf() < LOOP_CHANCE:
				cells[y][x]["s"] = false
				cells[y + 1][x]["n"] = false

	# Вход/выход.
	cells[ent][0]["w"] = false
	cells[ex][c - 1]["e"] = false
	var solution := bfs(cells, c, r, ent * c + 0, ex * c + (c - 1))
	return {
		"cols": c,
		"rows": r,
		"seed": seed,
		"ent_row": ent,
		"exit_row": ex,
		"cells": cells,
		"solution": solution,
		"solvable": not solution.is_empty(),
	}


static func neighbors_open(cells: Array, x: int, y: int, cols: int, rows: int) -> Array:
	var out: Array = []
	if x < 0 or y < 0 or x >= cols or y >= rows:
		return out
	var cell: Dictionary = cells[y][x]
	if y > 0 and not bool(cell["n"]):
		out.append(Vector2i(x, y - 1))
	if x < cols - 1 and not bool(cell["e"]):
		out.append(Vector2i(x + 1, y))
	if y < rows - 1 and not bool(cell["s"]):
		out.append(Vector2i(x, y + 1))
	if x > 0 and not bool(cell["w"]):
		out.append(Vector2i(x - 1, y))
	return out


static func bfs(cells: Array, cols: int, rows: int, start_id: int, goal_id: int) -> Array:
	var sx := start_id % cols
	var sy := start_id / cols
	var gx := goal_id % cols
	var gy := goal_id / cols
	if sx < 0 or sy < 0 or sx >= cols or sy >= rows:
		return []
	if gx < 0 or gy < 0 or gx >= cols or gy >= rows:
		return []
	var prev := {start_id: -1}
	var queue: Array = [start_id]
	while not queue.is_empty():
		var current := int(queue.pop_front())
		if current == goal_id:
			var path: Array = []
			var node := current
			while node >= 0:
				path.append(node)
				node = int(prev.get(node, -1))
			path.reverse()
			return path
		var cx := current % cols
		var cy := current / cols
		for n in neighbors_open(cells, cx, cy, cols, rows):
			var nid: int = int(n.y) * cols + int(n.x)
			if prev.has(nid):
				continue
			prev[nid] = current
			queue.append(nid)
	return []


static func find_dead_ends(cells: Array, cols: int, rows: int, ent_row: int,
		exit_row: int) -> Dictionary:
	var out := {}
	for y in range(rows):
		for x in range(cols):
			var degree := neighbors_open(cells, x, y, cols, rows).size()
			if degree == 1 and not (x == 0 and y == ent_row) \
					and not (x == cols - 1 and y == exit_row):
				out[y * cols + x] = true
	return out


## Все рёбра лабиринта: closed=true/false. Ключи:
## v:bx:by — вертикальная стена слева от клетки (bx,by), 0<=bx<=cols;
## h:bx:by — горизонтальная стена над клеткой (bx,by), 0<=by<=rows.
static func wall_edges(cells: Array, cols: int, rows: int, ent_row: int,
		exit_row: int) -> Dictionary:
	var out := {}
	for by in range(rows):
		for bx in range(cols + 1):
			var closed := true
			if bx == 0:
				closed = by != ent_row
			elif bx == cols:
				closed = by != exit_row
			else:
				closed = bool(cells[by][bx - 1]["e"])
			out["v:%d:%d" % [bx, by]] = closed
	for by in range(rows + 1):
		for bx in range(cols):
			var closed := true
			if by == 0:
				closed = true
			elif by == rows:
				closed = true
			else:
				closed = bool(cells[by - 1][bx]["s"])
			out["h:%d:%d" % [bx, by]] = closed
	return out


static func build_walls(cells: Array, cols: int, rows: int, ent_row: int,
		exit_row: int, field: Rect2, corridor: float) -> Array[Rect2]:
	var pitch := field.size.x / float(cols)
	var wall := pitch - corridor
	var out: Array[Rect2] = []
	var edges := wall_edges(cells, cols, rows, ent_row, exit_row)
	for by in range(rows):
		for bx in range(cols + 1):
			if not bool(edges["v:%d:%d" % [bx, by]]):
				continue
			out.append(Rect2(field.position.x + float(bx) * pitch - wall * 0.5,
				field.position.y + float(by) * pitch - wall * 0.5,
				wall, pitch + wall))
	for by in range(rows + 1):
		for bx in range(cols):
			if not bool(edges["h:%d:%d" % [bx, by]]):
				continue
			out.append(Rect2(field.position.x + float(bx) * pitch - wall * 0.5,
				field.position.y + float(by) * pitch - wall * 0.5,
				pitch + wall, wall))
	return out


static func hit_wall(center: Vector2, walls: Array, half: float) -> bool:
	var box := Rect2(center - Vector2(half, half), Vector2(half, half) * 2.0)
	for wall in walls:
		if box.intersects(wall as Rect2):
			return true
	return false


## Движение с раздельным скольжением по осям. Возвращает новую позицию и
## флаг столкновения. Чистая функция — удобна для headless-теста.
static func move_packet(pos: Vector2, target: Vector2, speed: float, dt: float,
		walls: Array, field: Rect2, half: float) -> Dictionary:
	var delta := target - pos
	var dist := delta.length()
	var max_move := maxf(0.0, speed) * maxf(0.0, dt)
	if dist > max_move and dist > 0.001:
		delta = delta / dist * max_move
	var blocked := false
	if delta.length_squared() <= 0.000001:
		return {"pos": pos, "blocked": false}
	var steps := maxi(1, int(ceil(maxf(absf(delta.x), absf(delta.y)) / 3.0)))
	var sx := delta.x / float(steps)
	var sy := delta.y / float(steps)
	for i in range(steps):
		var nx := pos.x + sx
		if absf(sx) > 0.0001:
			if not hit_wall(Vector2(nx, pos.y), walls, half):
				pos.x = nx
			else:
				blocked = true
		var ny := pos.y + sy
		if absf(sy) > 0.0001:
			if not hit_wall(Vector2(pos.x, ny), walls, half):
				pos.y = ny
			else:
				blocked = true
	pos.x = clampf(pos.x, field.position.x + half, field.end.x - half)
	pos.y = clampf(pos.y, field.position.y + half, field.end.y - half)
	return {"pos": pos, "blocked": blocked}


static func quality_for(collisions: int, dead_ends: int) -> float:
	return clampf(1.0 - 0.04 * float(maxi(0, collisions))
		- 0.02 * float(maxi(0, dead_ends)), 0.0, 1.0)


# --- игра ------------------------------------------------------------------

func _process(delta: float) -> void:
	if not running or _exited:
		return
	var half := HITBOX * 0.5
	var result := move_packet(_packet, _target, float(params.get("speed", 420.0)),
		minf(maxf(delta, 0.0), 0.1), _walls, _field, half)
	_packet = result["pos"]
	_collision_cd = maxf(0.0, _collision_cd - delta)
	if bool(result["blocked"]) and _collision_cd <= 0.0:
		_collisions += 1
		_collision_cd = COLLISION_COOLDOWN
	var id := _cell_under(_packet)
	if id >= 0:
		if _sol_index.has(id) and int(_sol_index[id]) > _max_sol:
			_max_sol = int(_sol_index[id])
		if _dead_ends.has(id) and not _visited_dead.has(id):
			_visited_dead[id] = true
			_dead_end_hits += 1
	# Выход справа, в строке выхода.
	if _packet.x >= _field.end.x - half - 1.5 \
			and absf(_packet.y - _exit.y) <= _corridor * 0.5:
		_exited = true
		_play_sfx(&"minigame_win")
		_finish(quality_for(_collisions, _dead_end_hits))
		return
	queue_redraw()


func _cell_under(pos: Vector2) -> int:
	var gx := int(floor((pos.x - _field.position.x) / _pitch))
	var gy := int(floor((pos.y - _field.position.y) / _pitch))
	var cols := int(maze.get("cols", 1))
	var rows := int(maze.get("rows", 1))
	if gx < 0 or gy < 0 or gx >= cols or gy >= rows:
		return -1
	return gy * cols + gx


func _clamp_target(local: Vector2) -> Vector2:
	var half := HITBOX * 0.5
	return Vector2(
		clampf(local.x, _field.position.x + half, _field.end.x - half),
		clampf(local.y, _field.position.y + half, _field.end.y - half))


func _on_pointer_pressed(local: Vector2, _event: InputEvent) -> bool:
	if local.y < FOOTER_Y and _field.grow(20.0).has_point(local):
		_target = _clamp_target(local)
		return true
	return false


func _on_pointer_moved(local: Vector2, _event: InputEvent) -> void:
	if local.y >= FOOTER_Y:
		return
	if _field.grow(20.0).has_point(local):
		_target = _clamp_target(local)


func _on_key_pressed(keycode: int, _event: InputEvent) -> bool:
	var step := 12.0
	match keycode:
		KEY_LEFT:
			_target.x -= step
		KEY_RIGHT:
			_target.x += step
		KEY_UP:
			_target.y -= step
		KEY_DOWN:
			_target.y += step
		KEY_HOME:
			_target = _entrance
		_:
			return false
	_target = _clamp_target(_target)
	return true


func _draw_game() -> void:
	var font := Theme90.ui()
	_draw_label("МАРШРУТ · ВЫХОД СПРАВА", Vector2(24.0, 46.0), 10,
		Theme90.DARK, 280.0)
	_draw_label("СТОЛКНОВЕНИЙ %d · ТУПИКОВ %d" % [_collisions, _dead_end_hits],
		Vector2(320.0, 46.0), 10, Theme90.DARK, 280.0,
		HORIZONTAL_ALIGNMENT_RIGHT)

	draw_style_box(Theme90.box(Theme90.PAPER_HI, Theme90.BORDER, 4, 1),
		_field.grow(10.0))
	# Лёгкая шахматная подложка.
	var pitch := _pitch
	for y in range(int(maze.get("rows", 1))):
		for x in range(int(maze.get("cols", 1))):
			if (x + y) % 2 == 0:
				draw_rect(Rect2(_field.position + Vector2(float(x) * pitch,
					float(y) * pitch), Vector2(pitch, pitch)),
					Color(0.18, 0.30, 0.32, 0.035))
	for wall in _walls:
		draw_rect(wall, Theme90.NAVY_DEEP)
	# Вход/выход.
	draw_rect(Rect2(_entrance - Vector2(3, 4), Vector2(6, 8)), Theme90.ACCENT)
	draw_circle(_exit, maxf(5.0, _corridor * 0.32), Theme90.SUCCESS)
	# Пакет и цель.
	draw_circle(_target, 2.0, Theme90.ACCENT.lightened(0.25))
	draw_style_box(Theme90.box(Theme90.ACCENT, Theme90.NAVY_DEEP, 3, 1,
		Theme90.SHADOW), Rect2(_packet - Vector2(PACKET, PACKET) * 0.5,
		Vector2(PACKET, PACKET)))
	draw_circle(_packet + Vector2(0, -2), 2.0, Theme90.WHITE)
	var progress := 0.0
	if not _solution.is_empty():
		progress = clampf((float(_max_sol) + 1.0) / float(_solution.size()), 0.0, 1.0)
	_draw_label("ПРОГРЕСС %d%%" % roundi(progress * 100.0),
		Vector2(_field.position.x, _field.end.y + 12.0), 10, Theme90.DARK,
		_field.size.x)
