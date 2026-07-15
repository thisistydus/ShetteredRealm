class_name Tile
extends Node2D
## One gem on the battlefield. Each kind maps to a party member.
## Modifier states:
##  frozen - can't move or match (Mage's Fireball melts them)
##  locked - can't move; matches give no ATB, first match removes the lock
##  stoned - can't move; matching works normally and clears the tile

const SIZE := 60.0

const KIND_COLORS: Array[Color] = [
	Color("c0392b"), # 0 Knight - red
	Color("2e86c1"), # 1 Mage   - blue
	Color("d4ac0d"), # 2 Priest - gold
	Color("8e44ad"), # 3 Rogue  - purple
]

# Cell (col,row) on the Oryx creature sheet; frame B is row+1.
const KIND_CELLS: Array[Vector2i] = [
	Vector2i(17, 2), # Knight - full plate + shield
	Vector2i(12, 0), # Mage   - purple pointy-hat wizard
	Vector2i(8, 2),  # Priest - white/gold robe + staff
	Vector2i(0, 2),  # Rogue  - red-bandana bandit
]

static var sheet: Texture2D = preload("res://art/creatures.png")
static var _boxes := {}

var kind := 0
var frozen := false:
	set(v):
		frozen = v
		_refresh()
var locked := false:
	set(v):
		locked = v
		_refresh()
var stoned := false:
	set(v):
		stoned = v
		_refresh()
var selected := false:
	set(v):
		selected = v
		_refresh()
var grid_pos := Vector2i.ZERO
var dying := false

var _sprite: Sprite2D
var _atlas: AtlasTexture
var _overlay: Node2D
var _hint_tween: Tween

func _ready() -> void:
	_atlas = AtlasTexture.new()
	_atlas.atlas = sheet
	_sprite = Sprite2D.new()
	_sprite.texture = _atlas
	_sprite.scale = Vector2(2.1, 2.1)
	add_child(_sprite)
	# modifier overlays render above the character sprite
	_overlay = Node2D.new()
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_refresh()

func set_kind(k: int) -> void:
	kind = k
	if is_inside_tree():
		_refresh()

func set_frame(f: int) -> void:
	# 2-frame idle animation straight off the sheet
	if _atlas == null or dying:
		return
	var c := KIND_CELLS[kind]
	_atlas.region = Rect2((c.x) * 24, (c.y + f) * 24, 24, 24)

func _refresh() -> void:
	if _atlas == null:
		return
	set_frame(0)
	if frozen:
		_sprite.modulate = Color(0.75, 0.9, 1.4, 0.8)
	elif stoned:
		_sprite.modulate = Color(0.55, 0.55, 0.58)
	else:
		_sprite.modulate = Color.WHITE
	queue_redraw()
	_overlay.queue_redraw()

func _box_for(k: int) -> StyleBoxFlat:
	if not _boxes.has(k):
		var sb := StyleBoxFlat.new()
		sb.bg_color = KIND_COLORS[k].darkened(0.25)
		sb.set_corner_radius_all(10)
		sb.border_color = KIND_COLORS[k].lightened(0.15)
		sb.set_border_width_all(3)
		_boxes[k] = sb
	return _boxes[k]

func _draw() -> void:
	var r := Rect2(-SIZE / 2, -SIZE / 2, SIZE, SIZE)
	draw_style_box(_box_for(kind), r)

func _draw_overlay() -> void:
	var r := Rect2(-SIZE / 2, -SIZE / 2, SIZE, SIZE)
	if selected:
		# click-click selection ring
		_overlay.draw_rect(r.grow(2), Color(1, 1, 1, 0.95), false, 4.0)
		_overlay.draw_rect(r.grow(6), Color(1, 1, 0.5, 0.5), false, 3.0)
	if frozen:
		# icy overlay
		_overlay.draw_rect(r.grow(-2), Color(0.75, 0.9, 1.0, 0.45))
		_overlay.draw_rect(r.grow(-2), Color(0.85, 0.95, 1.0, 0.9), false, 4.0)
		_overlay.draw_line(Vector2(-16, -16), Vector2(16, 16), Color(1, 1, 1, 0.7), 2.0)
		_overlay.draw_line(Vector2(-16, 16), Vector2(16, -16), Color(1, 1, 1, 0.7), 2.0)
	elif locked:
		# gray chain bars + padlock
		var g := Color(0.7, 0.7, 0.74, 0.9)
		_overlay.draw_rect(Rect2(-SIZE / 2, -5, SIZE, 10), g)
		_overlay.draw_rect(Rect2(-5, -SIZE / 2, 10, SIZE), g)
		_overlay.draw_rect(r.grow(-1), g, false, 5.0)
		_overlay.draw_rect(Rect2(-8, -8, 16, 14), Color(0.35, 0.35, 0.4))
		_overlay.draw_arc(Vector2(0, -8), 5, PI, TAU, 10, Color(0.35, 0.35, 0.4), 3.0)
	elif stoned:
		# stone slab: gray wash + cracks (tile still matches normally)
		_overlay.draw_rect(r.grow(-2), Color(0.5, 0.5, 0.52, 0.5))
		_overlay.draw_rect(r.grow(-1), Color(0.42, 0.42, 0.45), false, 5.0)
		_overlay.draw_polyline(PackedVector2Array([
			Vector2(-22, -26), Vector2(-12, -12), Vector2(-18, 2), Vector2(-8, 16)
		]), Color(0.3, 0.3, 0.33, 0.9), 2.0)
		_overlay.draw_polyline(PackedVector2Array([
			Vector2(24, -14), Vector2(12, -4), Vector2(16, 10)
		]), Color(0.3, 0.3, 0.33, 0.9), 2.0)

func pop() -> void:
	# clear animation, then free
	dying = true
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2(1.45, 1.45), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 0.0, 0.16)
	tw.chain().tween_callback(queue_free)

func unlock_flash() -> void:
	locked = false
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(1.6, 1.6, 1.6), 0.08)
	tw.tween_property(self, "modulate", Color.WHITE, 0.15)

func hint() -> void:
	# subtle looping glow to nudge an idle player toward a valid move
	if _hint_tween != null and _hint_tween.is_valid():
		return
	_hint_tween = create_tween().set_loops()
	_hint_tween.tween_property(_sprite, "modulate", Color(1.4, 1.35, 1.05), 0.55) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_hint_tween.tween_property(_sprite, "modulate", Color.WHITE, 0.55) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func clear_hint() -> void:
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
	_hint_tween = null
	# restore whatever the tile's normal tint should be
	if not dying:
		_refresh()
