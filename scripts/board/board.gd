class_name Board
extends Node2D
## 8x8 match-3 battlefield. Drag to swap. Handles match detection,
## cascades, refills, and board modifiers (freeze / lock).

const SIZE := 8
const CELL := 68.0
const KINDS := 4
const SWAP_TIME := 0.14
const FALL_TIME := 0.24

var grid: Array = []            # grid[x][y] -> Tile or null
var input_enabled := false      # set by combat flow
var resolving := false

var _drag_cell := Vector2i(-1, -1)
var _drag_start := Vector2.ZERO
var _anim_frame := 0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	for x in SIZE:
		grid.append([])
		for y in SIZE:
			grid[x].append(null)
	_initial_fill()
	# global 2-frame idle animation for all tiles
	var t := Timer.new()
	t.wait_time = 0.45
	t.autostart = true
	t.timeout.connect(_tick_frames)
	add_child(t)

func _tick_frames() -> void:
	_anim_frame = 1 - _anim_frame
	for x in SIZE:
		for y in SIZE:
			if grid[x][y] != null:
				grid[x][y].set_frame(_anim_frame)

func _draw() -> void:
	# board backdrop
	var pad := 12.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.12, 0.9)
	sb.set_corner_radius_all(14)
	sb.border_color = Color(0.35, 0.3, 0.5)
	sb.set_border_width_all(3)
	draw_style_box(sb, Rect2(-pad, -pad, SIZE * CELL + pad * 2, SIZE * CELL + pad * 2))
	for x in SIZE:
		for y in SIZE:
			if (x + y) % 2 == 0:
				draw_rect(Rect2(x * CELL + 2, y * CELL + 2, CELL - 4, CELL - 4), Color(1, 1, 1, 0.03))

func cell_center(c: Vector2i) -> Vector2:
	return Vector2(c.x * CELL + CELL / 2, c.y * CELL + CELL / 2)

func _make_tile(c: Vector2i, kind: int) -> Tile:
	var t := Tile.new()
	t.set_kind(kind)
	t.grid_pos = c
	t.position = cell_center(c)
	add_child(t)
	grid[c.x][c.y] = t
	return t

func _initial_fill() -> void:
	for y in SIZE:
		for x in SIZE:
			var kind := _rng.randi_range(0, KINDS - 1)
			# avoid starting matches
			while _would_start_match(x, y, kind):
				kind = _rng.randi_range(0, KINDS - 1)
			_make_tile(Vector2i(x, y), kind)

func _would_start_match(x: int, y: int, kind: int) -> bool:
	if x >= 2 and grid[x - 1][y] and grid[x - 2][y] and grid[x - 1][y].kind == kind and grid[x - 2][y].kind == kind:
		return true
	if y >= 2 and grid[x][y - 1] and grid[x][y - 2] and grid[x][y - 1].kind == kind and grid[x][y - 2].kind == kind:
		return true
	return false

# ---------------- input ----------------

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or resolving:
		_drag_cell = Vector2i(-1, -1)
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var c := _cell_at(get_global_mouse_position())
			if c.x >= 0 and _is_movable(c):
				_drag_cell = c
				_drag_start = get_global_mouse_position()
		else:
			_drag_cell = Vector2i(-1, -1)
	elif event is InputEventMouseMotion and _drag_cell.x >= 0:
		var delta := get_global_mouse_position() - _drag_start
		if delta.length() >= 22.0:
			var dir := Vector2i.ZERO
			if absf(delta.x) > absf(delta.y):
				dir = Vector2i(signi(int(delta.x)), 0)
			else:
				dir = Vector2i(0, signi(int(delta.y)))
			var target := _drag_cell + dir
			var from := _drag_cell
			_drag_cell = Vector2i(-1, -1)
			if _in_bounds(target) and _is_movable(target):
				_try_swap(from, target)

func _cell_at(world: Vector2) -> Vector2i:
	var local := world - global_position
	var c := Vector2i(int(floor(local.x / CELL)), int(floor(local.y / CELL)))
	if _in_bounds(c):
		return c
	return Vector2i(-1, -1)

func _in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < SIZE and c.y >= 0 and c.y < SIZE

func _is_movable(c: Vector2i) -> bool:
	var t = grid[c.x][c.y]
	return t != null and not t.frozen and not t.locked and not t.dying

# ---------------- swapping ----------------

func _try_swap(a: Vector2i, b: Vector2i) -> void:
	resolving = true
	var ta = grid[a.x][a.y]
	var tb = grid[b.x][b.y]
	_swap_cells(a, b)
	await _animate_swap(ta, tb)
	if _find_groups().is_empty():
		# no match: swap back
		_swap_cells(a, b)
		await _animate_swap(ta, tb)
		resolving = false
	else:
		resolving = false
		_resolve()

func _swap_cells(a: Vector2i, b: Vector2i) -> void:
	var ta = grid[a.x][a.y]
	var tb = grid[b.x][b.y]
	grid[a.x][a.y] = tb
	grid[b.x][b.y] = ta
	if ta: ta.grid_pos = b
	if tb: tb.grid_pos = a

func _animate_swap(ta: Tile, tb: Tile) -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(ta, "position", cell_center(ta.grid_pos), SWAP_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(tb, "position", cell_center(tb.grid_pos), SWAP_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished

# ---------------- matching ----------------

func _kind_at(x: int, y: int) -> int:
	# -1 means "does not match anything" (empty or frozen)
	var t = grid[x][y]
	if t == null or t.frozen or t.dying:
		return -1
	return t.kind

func _find_groups() -> Array:
	# returns array of {kind, cells: Array[Vector2i]} for connected match groups
	var matched := {}
	for y in SIZE:
		var run := 1
		for x in range(1, SIZE + 1):
			var same := x < SIZE and _kind_at(x, y) != -1 and _kind_at(x, y) == _kind_at(x - 1, y)
			if same:
				run += 1
			else:
				if run >= 3:
					for i in range(x - run, x):
						matched[Vector2i(i, y)] = true
				run = 1
	for x in SIZE:
		var run := 1
		for y in range(1, SIZE + 1):
			var same := y < SIZE and _kind_at(x, y) != -1 and _kind_at(x, y) == _kind_at(x, y - 1)
			if same:
				run += 1
			else:
				if run >= 3:
					for i in range(y - run, y):
						matched[Vector2i(x, i)] = true
				run = 1
	# group matched cells into connected components of the same kind
	var groups: Array = []
	var seen := {}
	for cell in matched.keys():
		if seen.has(cell):
			continue
		var kind := _kind_at(cell.x, cell.y)
		var stack: Array = [cell]
		var cells: Array = []
		seen[cell] = true
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			cells.append(c)
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n: Vector2i = c + d
				if matched.has(n) and not seen.has(n) and _kind_at(n.x, n.y) == kind:
					seen[n] = true
					stack.append(n)
		groups.append({"kind": kind, "cells": cells})
	return groups

# ---------------- resolution loop ----------------

func _resolve(start_with_collapse := false) -> void:
	if resolving:
		return
	resolving = true
	var combo := 0
	if start_with_collapse:
		_collapse_and_refill()
		await get_tree().create_timer(FALL_TIME + 0.05).timeout
	while true:
		var groups := _find_groups()
		if groups.is_empty():
			break
		combo += 1
		for g in groups:
			_process_group(g, combo)
		await get_tree().create_timer(0.20).timeout
		_collapse_and_refill()
		await get_tree().create_timer(FALL_TIME + 0.05).timeout
	resolving = false
	_ensure_moves()
	Events.board_settled.emit()

func _process_group(g: Dictionary, combo: int) -> void:
	var unlocked_cells: Array = []
	var center := Vector2.ZERO
	for c in g.cells:
		center += cell_center(c)
	center = global_position + center / g.cells.size()
	for c in g.cells:
		var t = grid[c.x][c.y]
		if t == null:
			continue
		if t.locked:
			# first match removes the lock; tile stays, gives no ATB
			t.unlock_flash()
		else:
			unlocked_cells.append(c)
			grid[c.x][c.y] = null
			t.pop()
	Events.match_made.emit(g.kind, g.cells.size(), unlocked_cells.size(), combo, center)

func _collapse_and_refill() -> void:
	for x in SIZE:
		# compact surviving tiles to the bottom
		var write := SIZE - 1
		for y in range(SIZE - 1, -1, -1):
			var t = grid[x][y]
			if t != null:
				if write != y:
					grid[x][write] = t
					grid[x][y] = null
					t.grid_pos = Vector2i(x, write)
					_fall_to(t)
				write -= 1
		# spawn new tiles above the board and drop them in
		var empties := write + 1
		for y in range(write, -1, -1):
			var kind := _rng.randi_range(0, KINDS - 1)
			var t := _make_tile(Vector2i(x, y), kind)
			t.position = cell_center(Vector2i(x, y - empties)) - Vector2(0, CELL * 0.3)
			_fall_to(t)

func _fall_to(t: Tile) -> void:
	var tw := create_tween()
	tw.tween_property(t, "position", cell_center(t.grid_pos), FALL_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(t, "position", cell_center(t.grid_pos) - Vector2(0, 4), 0.05)
	tw.tween_property(t, "position", cell_center(t.grid_pos), 0.05)

# ---------------- modifiers (freeze / lock) ----------------

func freeze_random(n: int) -> void:
	var candidates := _plain_tiles()
	candidates.shuffle()
	for i in mini(n, candidates.size()):
		candidates[i].frozen = true
	Sfx.play("freeze")

func lock_random(n: int) -> void:
	var candidates := _plain_tiles()
	candidates.shuffle()
	for i in mini(n, candidates.size()):
		candidates[i].locked = true
	Sfx.play("lock")

func _plain_tiles() -> Array:
	var out: Array = []
	for x in SIZE:
		for y in SIZE:
			var t = grid[x][y]
			if t != null and not t.frozen and not t.locked and not t.dying:
				out.append(t)
	return out

func clear_modifiers() -> void:
	# fresh battlefield between encounters
	for x in SIZE:
		for y in SIZE:
			var t = grid[x][y]
			if t != null:
				t.frozen = false
				t.locked = false

func count_frozen() -> int:
	var n := 0
	for x in SIZE:
		for y in SIZE:
			if grid[x][y] != null and grid[x][y].frozen:
				n += 1
	return n

func clear_frozen() -> void:
	# Mage's Fireball: destroy every frozen tile, then let the board cascade.
	var any := false
	for x in SIZE:
		for y in SIZE:
			var t = grid[x][y]
			if t != null and t.frozen and not t.dying:
				grid[x][y] = null
				t.pop()
				Events.float_text.emit("melt!", t.global_position, Color(0.7, 0.9, 1.0), 18)
				any = true
	if any and not resolving:
		_resolve(true)

# ---------------- deadlock protection ----------------

func _ensure_moves() -> void:
	if _has_possible_move():
		return
	# reshuffle plain tiles until a move exists
	for attempt in 30:
		var tiles := _plain_tiles()
		var kinds: Array = []
		for t in tiles:
			kinds.append(t.kind)
		kinds.shuffle()
		for i in tiles.size():
			tiles[i].set_kind(kinds[i])
		if _find_groups().is_empty() and _has_possible_move():
			Events.float_text.emit("Board reshuffled", global_position + Vector2(SIZE * CELL / 2, SIZE * CELL / 2), Color.WHITE, 22)
			return
	# give up quietly; next cascade will likely fix things

func _has_possible_move() -> bool:
	return not find_move().is_empty()

func find_move() -> Array:
	# returns [a, b] cells of the first valid swap, or [] if none
	for x in SIZE:
		for y in SIZE:
			var a := Vector2i(x, y)
			if not _is_movable(a):
				continue
			for d in [Vector2i.RIGHT, Vector2i.DOWN]:
				var b: Vector2i = a + d
				if not _in_bounds(b) or not _is_movable(b):
					continue
				_swap_cells(a, b)
				var found := not _find_groups().is_empty()
				_swap_cells(a, b)
				if found:
					return [a, b]
	return []

func sim_swap(a: Vector2i, b: Vector2i) -> void:
	# debug/autoplay hook
	if not resolving and input_enabled:
		_try_swap(a, b)
