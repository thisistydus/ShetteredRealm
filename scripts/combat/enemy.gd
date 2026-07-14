class_name Enemy
extends Node2D
## Data-driven enemy. Always telegraphs its next attack with a countdown.
## data = {name, hp, chip_resist, cell: Vector2i, scale, attacks: [{name, time, kind, power}]}

var data: Dictionary
var hp := 1
var max_hp := 1
var active := false
var current_attack := {}
var time_left := 0.0

var _attack_i := -1
var _sprite: Sprite2D
var _atlas: AtlasTexture
var _anim_t := 0.0
var _frame := 0
var _home := Vector2.ZERO

func setup(d: Dictionary) -> void:
	data = d
	max_hp = d.hp
	hp = d.hp
	_atlas = AtlasTexture.new()
	_atlas.atlas = Tile.sheet
	_sprite = Sprite2D.new()
	_sprite.texture = _atlas
	_sprite.scale = Vector2.ONE * d.get("scale", 7.0)
	add_child(_sprite)
	_set_frame(0)
	_home = position
	# entrance
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.4)

func begin() -> void:
	active = true
	_next_intent()

func _set_frame(f: int) -> void:
	var c: Vector2i = data.cell
	_atlas.region = Rect2(c.x * 24, (c.y + f) * 24, 24, 24)

func _process(delta: float) -> void:
	_anim_t += delta
	if _anim_t >= 0.45:
		_anim_t = 0.0
		_frame = 1 - _frame
		_set_frame(_frame)
	if active and not current_attack.is_empty():
		time_left -= delta
		if time_left <= 0.0:
			_fire()

func _next_intent() -> void:
	_attack_i = (_attack_i + 1) % data.attacks.size()
	current_attack = data.attacks[_attack_i]
	time_left = current_attack.time

func _fire() -> void:
	var attack := current_attack
	current_attack = {}
	# little lunge
	var tw := create_tween()
	tw.tween_property(self, "position", _home + Vector2(60, 10), 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "position", _home, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	Events.enemy_attack.emit(attack)
	_next_intent()

func take_damage(amount: int, is_chip: bool) -> void:
	if not active:
		return
	var final := amount
	if is_chip:
		final = maxi(1, int(round(amount * (1.0 - data.get("chip_resist", 0.0)))))
	hp = maxi(0, hp - final)
	var resisted: bool = is_chip and final < amount
	var col := Color(1, 1, 1) if is_chip else Color(1, 0.85, 0.3)
	var txt := str(final) + (" (resisted)" if resisted else "")
	Events.float_text.emit(txt, global_position + Vector2(randf_range(-30, 30), -70), col, 20 if is_chip else 30)
	Events.enemy_damaged.emit(final, global_position, is_chip)
	# hit flash + wobble
	_sprite.modulate = Color(3, 3, 3)
	var tw := create_tween()
	tw.tween_property(_sprite, "modulate", Color.WHITE, 0.15)
	if not is_chip:
		Events.shake.emit(8.0)
	if hp <= 0:
		_die()

func interrupt() -> void:
	if not active:
		return
	Events.float_text.emit("INTERRUPTED!", global_position + Vector2(0, -110), Color(1, 0.4, 0.2), 26)
	Sfx.play("interrupt")
	_next_intent()

func _die() -> void:
	active = false
	current_attack = {}
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 0.0, 0.5)
	tw.tween_property(self, "position", _home + Vector2(0, 30), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(queue_free)
	Events.enemy_died.emit()
