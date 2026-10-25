extends MiniGame
## «Одна линия» (dots). Гамильтонов путь по свободным клеткам.
##
## FIX B3: сначала выбираются свободные клетки и препятствия, затем ищется
## путь только по свободным клеткам. Если случайная раскладка нерешаема —
## новый локальный RNG и ограниченное число попыток; последний рубеж — змейка.

const TIERS := {
	1: {"cols": 3, "rows": 3, "obstacles": 0, "undo_penalty": 0.05},
	2: {"cols": 4, "rows": 3, "obstacles": 2, "undo_penalty": 0.04},
	3: {"cols": 4, "rows": 4, "obstacles": 4, "undo_penalty": 0.04},
	4: {"cols": 5, "rows": 4, "obstacles": 6, "undo_penalty": 0.03},
}
const MAX_BOARD_ATTEMPTS := 16
const MAX_START_TRIES := 8
const DFS_GUARD := 120000
const RESET_RECT := Rect2(466.0, 320.0, 156.0, 28.0)

var board: Dictionary = {}
var _path: Array = []
var _undos: int = 0
var _invalid: int = 0
var _cell_rects: Array[Rect2] = []
var _cell_ids: Array = []
var _stride: float = 60.0
var _port_rect: Rect2 = Rect2()


func _own_game_id() -> String:
	return "dots"


func _setup() -> void:
	board = generate_tier(tier, seed_value)
	_path.clear()
	_undos = 0
	_invalid = 0
	_build_geometry()


# --- параметры -------------------------------------------------------------

static func tier_params(p_tier: int) -> Dictionary:
	var base: Dictionary = (TIERS.get(clampi(p_tier, 1, 4), TIERS[1]) as Dictionary).duplicate(true)
	var row := MiniGame.data_minigame_tier("dots", p_tier)
	if row.is_empty():
		return base
	var grid = row.get("grid", null)
	if grid is Array and (grid as Array).size() >= 2:
		base["cols"] = int((grid as Array)[0])
		base["rows"] = int((grid as Array)[1])
	for key in ["cols", "rows", "obstacles"]:
		if row.has(key):
			base[key] = int(row[key])
	if row.has("undo_penalty"):
		base["undo_penalty"] = float(row["undo_penalty"])
	return base


# --- генерация/валидация ---------------------------------------------------

static func generate_tier(p_tier: int, seed: int) -> Dictionary:
	var p := tier_params(p_tier)
	return generate(int(p["cols"]), int(p["rows"]), int(p["obstacles"]), seed)


## Чистая генерация. Возвращает разложение по int-id (row * cols + col).
static func generate(cols: int, rows: int, obstacles: int, seed: int) -> Dictionary:
	var c := maxi(2, cols)
	var r := maxi(2, rows)
	var cells := c * r
	var obs := clampi(obstacles, 0, cells - 4)
	var free_count := cells - obs
	var ids: Array = []
	for i in range(cells):
		ids.append(i)

	var fallback_used := false
	for attempt in range(MAX_BOARD_ATTEMPTS):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed + 7919 * (attempt + 1)
		var shuffled := ids.duplicate()
		_shuffle(shuffled, rng)
		var blocked: Array = shuffled.slice(0, obs)
		var free: Array = shuffled.slice(obs)
		if free.size() != free_count:
			continue
		if not _free_connected(free, c, r):
			continue
		if not _parity_ok(free, c):
			continue
		var starts := free.duplicate()
		_shuffle(starts, rng)
		var tries := mini(MAX_START_TRIES, starts.size())
		for si in range(tries):
			var start := int(starts[si])
			var visited := {start: true}
			var path: Array = [start]
			var guard: Array = [0]
			if _ham_dfs(start, free, c, r, visited, path, free_count, guard, rng):
				if _path_valid(path, free, c, r):
					return _make_board(c, r, free, blocked, path, attempt + 1, false)

	# Случайный, но гарантированно валидный откат: полный гамильтонов путь
	# по всей сетке, затем первые free_count клеток — свободные, хвост — стены.
	for fb_attempt in range(4):
		var rng3 := RandomNumberGenerator.new()
		rng3.seed = seed + 15485863 + fb_attempt * 101
		var all_ids: Array = []
		for i in range(cells):
			all_ids.append(i)
		var starts3 := all_ids.duplicate()
		_shuffle(starts3, rng3)
		var start3 := int(starts3[0])
		var visited3 := {start3: true}
		var full_path: Array = [start3]
		var guard3: Array = [0]
		if _ham_dfs(start3, all_ids, c, r, visited3, full_path, cells, guard3, rng3):
			var free3: Array = full_path.slice(0, free_count)
			var blocked3: Array = full_path.slice(free_count, cells)
			return _make_board(c, r, free3, blocked3, free3.duplicate(),
				MAX_BOARD_ATTEMPTS + fb_attempt + 1, true)

	# Последний рубеж: змейка по всей сетке; свободные — её префикс.
	fallback_used = true
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = seed + 104729
	var snake := _snake_ids(c, r)
	var free2: Array = snake.slice(0, free_count)
	var blocked2: Array = snake.slice(free_count, snake.size())
	_shuffle(blocked2, rng2)
	return _make_board(c, r, free2, blocked2, free2.duplicate(), MAX_BOARD_ATTEMPTS,
		fallback_used)


static func _make_board(c: int, r: int, free: Array, blocked: Array, path: Array,
		attempts: int, fallback_used: bool) -> Dictionary:
	var path_cells: Array = []
	for id in path:
		path_cells.append(Vector2i(int(id) % c, int(id) / c))
	var sorted_blocked := blocked.duplicate()
	sorted_blocked.sort()
	var sorted_free := free.duplicate()
	sorted_free.sort()
	return {
		"cols": c,
		"rows": r,
		"obstacles": sorted_blocked.size(),
		"free_count": sorted_free.size(),
		"blocked": sorted_blocked,
		"free": sorted_free,
		"path": path.duplicate(),
		"path_cells": path_cells,
		"start": int(path[0]),
		"finish": int(path[path.size() - 1]),
		"attempts": attempts,
		"fallback": fallback_used,
	}


static func _free_connected(free: Array, c: int, r: int) -> bool:
	if free.is_empty():
		return false
	var free_map := {}
	for id in free:
		free_map[int(id)] = true
	var seen := {int(free[0]): true}
	var queue: Array = [int(free[0])]
	while not queue.is_empty():
		var id := int(queue.pop_front())
		for n in _neighbors(id, c, r):
			if free_map.has(n) and not seen.has(n):
				seen[n] = true
				queue.append(n)
	return seen.size() == free.size()


static func _parity_ok(free: Array, c: int) -> bool:
	var even := 0
	var odd := 0
	for id in free:
		var x := int(id) % c
		var y := int(id) / c
		if (x + y) % 2 == 0:
			even += 1
		else:
			odd += 1
	return absi(even - odd) <= 1


static func _ham_dfs(current: int, free: Array, c: int, r: int, visited: Dictionary,
		path: Array, total: int, guard: Array, rng: RandomNumberGenerator) -> bool:
	guard[0] = int(guard[0]) + 1
	if int(guard[0]) > DFS_GUARD:
		return false
	if path.size() == total:
		return true
	var free_map := {}
	for id in free:
		free_map[int(id)] = true
	var near: Array = []
	for n in _neighbors(current, c, r):
		if free_map.has(n) and not visited.has(n):
			near.append(n)
	_shuffle(near, rng)
	for n in near:
		visited[n] = true
		path.append(n)
		if _ham_dfs(int(n), free, c, r, visited, path, total, guard, rng):
			return true
		path.pop_back()
		visited.erase(n)
	return false


static func _path_valid(path: Array, free: Array, c: int, r: int) -> bool:
	if path.size() != free.size() or path.is_empty():
		return false
	var free_map := {}
	for id in free:
		free_map[int(id)] = true
	var seen := {}
	for i in range(path.size()):
		var id := int(path[i])
		if not free_map.has(id) or seen.has(id):
			return false
		seen[id] = true
		if i > 0 and not _adjacent(int(path[i - 1]), id, c):
			return false
	return true


static func validate_board(board_data: Dictionary) -> bool:
	if not board_data.has("cols") or not board_data.has("rows"):
		return false
	var c := int(board_data["cols"])
	var r := int(board_data["rows"])
	var free: Array = board_data.get("free", [])
	var blocked: Array = board_data.get("blocked", [])
	var path: Array = board_data.get("path", [])
	if free.size() + blocked.size() != c * r:
		return false
	if int(board_data.get("obstacles", blocked.size())) != blocked.size():
		return false
	if int(board_data.get("free_count", free.size())) != free.size():
		return false
	if not _path_valid(path, free, c, r):
		return false
	if int(board_data.get("start", -1)) != int(path[0]):
		return false
	if int(board_data.get("finish", -1)) != int(path[path.size() - 1]):
		return false
	return true


static func _neighbors(id: int, c: int, r: int) -> Array:
	var x := id % c
	var y := id / c
	var out: Array = []
	if y > 0:
		out.append(id - c)
	if x < c - 1:
		out.append(id + 1)
	if y < r - 1:
		out.append(id + c)
	if x > 0:
		out.append(id - 1)
	return out


static func _adjacent(a: int, b: int, c: int) -> bool:
	var ax := a % c
	var ay := a / c
	var bx := b % c
	var by := b / c
	return absi(ax - bx) + absi(ay - by) == 1


static func _shuffle(list: Array, p_rng: RandomNumberGenerator) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := p_rng.randi_range(0, i)
		var tmp = list[i]
		list[i] = list[j]
		list[j] = tmp


static func _snake_ids(c: int, r: int) -> Array:
	var out: Array = []
	for y in range(r):
		for i in range(c):
			var x := i if y % 2 == 0 else c - 1 - i
			out.append(y * c + x)
	return out


static func quality_for(p_undos: int, p_invalid: int, p_tier: int) -> float:
	var p := tier_params(p_tier)
	var penalty := float(p.get("undo_penalty", 0.04))
	return clampf(1.0 - penalty * float(maxi(0, p_undos))
		- 0.1 * float(maxi(0, p_invalid)), 0.0, 1.0)


# --- геометрия/игра --------------------------------------------------------

func _build_geometry() -> void:
	var cols := int(board.get("cols", 3))
	var rows := int(board.get("rows", 3))
	var area := Rect2(20.0, 54.0, 600.0, 256.0)
	_stride = minf(area.size.x / float(cols), area.size.y / float(rows))
	_stride = clampf(floorf(_stride), 46.0, 78.0)
	var total_w := _stride * float(cols)
	var total_h := _stride * float(rows)
	_port_rect = Rect2(area.position.x + (area.size.x - total_w) * 0.5,
		area.position.y + (area.size.y - total_h) * 0.5, total_w, total_h)
	_cell_rects.clear()
	_cell_ids.clear()
	for y in range(rows):
		for x in range(cols):
			var pad := 5.0
			_cell_rects.append(Rect2(
				Vector2(_port_rect.position.x + x * _stride,
					_port_rect.position.y + y * _stride) + Vector2(pad, pad),
				Vector2(_stride - pad * 2.0, _stride - pad * 2.0)))
			_cell_ids.append(y * cols + x)


func _cell_at(local: Vector2) -> int:
	for i in range(_cell_rects.size()):
		if _cell_rects[i].grow(4.0).has_point(local):
			return int(_cell_ids[i])
	return -1


func _blocked_map() -> Dictionary:
	var out := {}
	for id in board.get("blocked", []):
		out[int(id)] = true
	return out


func _free_map() -> Dictionary:
	var out := {}
	for id in board.get("free", []):
		out[int(id)] = true
	return out


func _on_pointer_pressed(local: Vector2, _event: InputEvent) -> bool:
	if RESET_RECT.has_point(local):
		_reset_line()
		return true
	var id := _cell_at(local)
	if id < 0:
		return false
	if _path.is_empty():
		if id == int(board.get("start", -1)):
			_path = [id]
			_play_sfx(&"tick")
		else:
			_invalid += 1
		queue_redraw()
		return true

	var free := _free_map()
	var last := int(_path[_path.size() - 1])
	if _path.size() >= 2 and id == int(_path[_path.size() - 2]):
		_path.pop_back()
		_undos += 1
		_play_sfx(&"tick")
		queue_redraw()
		return true
	if id == last:
		return true
	if not free.has(id) or _path.has(id):
		_invalid += 1
		queue_redraw()
		return true
	var cols := int(board.get("cols", 3))
	if not _adjacent(last, id, cols):
		_invalid += 1
		queue_redraw()
		return true
	if id == int(board.get("finish", -1)) and _path.size() < int(board.get("free_count", 0)) - 1:
		# Финиш можно только последним: иначе линия не покроет все порты.
		_invalid += 1
		queue_redraw()
		return true
	_path.append(id)
	_play_sfx(&"tick")
	if _path.size() == int(board.get("free_count", 0)) and id == int(board.get("finish", -1)):
		_finish(quality_for(_undos, _invalid, tier))
	queue_redraw()
	return true


func _on_key_pressed(keycode: int, _event: InputEvent) -> bool:
	if keycode == KEY_R:
		_reset_line()
		return true
	return false


func _reset_line() -> void:
	if not _path.is_empty():
		_undos += 1
	_path.clear()
	_play_sfx(&"tick")
	queue_redraw()


func _draw_game() -> void:
	var font := Theme90.ui()
	var cols := int(board.get("cols", 3))
	var blocked := _blocked_map()
	var free := _free_map()
	var path_set := {}
	for id in _path:
		path_set[int(id)] = true

	_draw_label("ЛИНИЯ %d / %d" % [_path.size(), int(board.get("free_count", 0))],
		Vector2(24.0, 46.0), 10, Theme90.NAVY, 220.0)
	_draw_label("ПРЕПЯТСТВИЙ %d · ОТКАТОВ %d · ОШИБОК %d" % [
		int(board.get("obstacles", 0)), _undos, _invalid],
		Vector2(300.0, 46.0), 10, Theme90.SHADE, 300.0, HORIZONTAL_ALIGNMENT_RIGHT)

	draw_style_box(Theme90.box(Theme90.PAPER_LO, Theme90.BORDER_SOFT, 4, 1),
		Rect2(_port_rect.position - Vector2(8, 8), _port_rect.size + Vector2(16, 16)))

	for i in range(_cell_ids.size()):
		var id := int(_cell_ids[i])
		var rect := _cell_rects[i]
		if blocked.has(id):
			draw_style_box(Theme90.fill_box(Theme90.DARK.darkened(0.08), 3), rect)
			Theme90.draw_hatch(self, rect.grow(-2.0), Color(1, 1, 1, 0.10), 5.0)
			continue
		var fill := Theme90.PAPER_HI
		if path_set.has(id):
			fill = Theme90.ACCENT_PALE
		draw_style_box(Theme90.box(fill, Theme90.BORDER, 3, 1), rect)
		var center := rect.get_center()
		draw_circle(center, minf(rect.size.x, rect.size.y) * 0.22, Theme90.ACCENT_LIGHT)
		draw_circle(center, minf(rect.size.x, rect.size.y) * 0.13, Theme90.ACCENT)
		if id == int(board.get("start", -1)):
			Theme90.text_vcenter(self, font, rect, "С", 16, Theme90.WHITE,
				-1, HORIZONTAL_ALIGNMENT_CENTER)
		elif id == int(board.get("finish", -1)):
			draw_circle(center, minf(rect.size.x, rect.size.y) * 0.30, Theme90.SUCCESS)
			Theme90.text_vcenter(self, font, rect, "Ф", 16, Theme90.WHITE,
				-1, HORIZONTAL_ALIGNMENT_CENTER)

	for i in range(1, _path.size()):
		var a := _cell_center(int(_path[i - 1]))
		var b := _cell_center(int(_path[i]))
		draw_line(a, b, Theme90.ACCENT, 4.0, true)
		if i == _path.size() - 1:
			draw_circle(b, 4.0, Theme90.NAVY_DEEP)

	if _path.is_empty():
		_draw_label("НАЧНИТЕ С «С» · КЛИК ПО ПРЕДЫДУЩЕМУ УЗЛУ — ОТКАТ · R — СБРОС",
			Vector2(24.0, 344.0), 10, Theme90.SHADE, 430.0)
	_draw_secondary_button(RESET_RECT, "СБРОС (R)")


func _cell_center(id: int) -> Vector2:
	for i in range(_cell_ids.size()):
		if int(_cell_ids[i]) == id:
			return _cell_rects[i].get_center()
	return _port_rect.get_center()
