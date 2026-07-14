class_name Combat
extends Node
## Party state: HP, four ATB gauges, ability execution.
## Listens to board matches; main wires in the current enemy + board.

const MAX_HP := 100
const ATB_MAX := 100.0
# ATB gained by number of tiles cleared in one match (index = tiles, 3/4/5+)
const ATB_GAIN := [0, 0, 0, 25.0, 40.0, 60.0]
const CHIP_PER_TILE := 2

const CHARS := [
	{"name": "Knight", "ability": "Shield Bash", "hint": "Heavy damage"},
	{"name": "Mage", "ability": "Fireball", "hint": "Damage + melts Frozen"},
	{"name": "Priest", "ability": "Heal", "hint": "Restore 30 HP"},
	{"name": "Rogue", "ability": "Backstab", "hint": "Damage + interrupt"},
]

var party_hp := MAX_HP
var atb := [0.0, 0.0, 0.0, 0.0]
var active := false          # abilities usable / damage applies
var enemy: Enemy = null
var board: Board = null

func _ready() -> void:
	Events.match_made.connect(_on_match)

func reset_for_encounter(e: Enemy) -> void:
	enemy = e

func _on_match(kind: int, total: int, unlocked: int, combo: int, world_pos: Vector2) -> void:
	if not active:
		return
	# 1) chip damage: small, physical, resisted by armored enemies
	if enemy != null and enemy.active and unlocked > 0:
		enemy.take_damage(CHIP_PER_TILE * unlocked, true)
	# 2) ATB for the matched character
	var gain: float = ATB_GAIN[clampi(unlocked, 0, 5)]
	if unlocked > 5:
		gain = 60.0 + 10.0 * (unlocked - 5)
	if gain > 0.0:
		add_atb(kind, gain)
		Events.float_text.emit("+%d %s" % [int(gain), CHARS[kind].name], world_pos, Tile.KIND_COLORS[kind].lightened(0.4), 18)
	# 3) juice
	if total >= 4 or combo >= 2:
		Sfx.play("big", 1.0 + 0.07 * (combo - 1))
		Events.shake.emit(4.0)
	else:
		Sfx.play("pop", 1.0 + 0.07 * (combo - 1))

func add_atb(id: int, amount: float) -> void:
	if atb[id] >= ATB_MAX:
		return
	atb[id] = minf(ATB_MAX, atb[id] + amount)
	if atb[id] >= ATB_MAX:
		Sfx.play("ready")
		Events.atb_full.emit(id)

func is_ready(id: int) -> bool:
	return atb[id] >= ATB_MAX

func try_use_ability(id: int) -> void:
	if not active or not is_ready(id):
		return
	atb[id] = 0.0
	Events.ability_used.emit(id)
	match id:
		0: # Knight - Shield Bash
			Sfx.play("ability", 0.8)
			if enemy: enemy.take_damage(22, false)
		1: # Mage - Fireball
			Sfx.play("ability", 1.1)
			if enemy: enemy.take_damage(18, false)
			if board: board.clear_frozen()
		2: # Priest - Heal
			Sfx.play("heal")
			party_hp = mini(MAX_HP, party_hp + 30)
			Events.party_hp_changed.emit(party_hp, MAX_HP)
			Events.float_text.emit("+30 HP", Vector2(330, 560), Color(0.4, 1.0, 0.5), 26)
		3: # Rogue - Backstab
			Sfx.play("ability", 1.3)
			if enemy:
				enemy.take_damage(26, false)
				enemy.interrupt()

func damage_party(amount: int) -> void:
	if not active:
		return
	party_hp = maxi(0, party_hp - amount)
	Events.party_hp_changed.emit(party_hp, MAX_HP)
	Events.float_text.emit("-%d" % amount, Vector2(330, 470) + Vector2(randf_range(-20, 20), 0), Color(1, 0.35, 0.35), 26)
	Events.shake.emit(10.0)
	Sfx.play("hurt")
	if party_hp <= 0:
		active = false
		Events.party_defeated.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: try_use_ability(0)
			KEY_2: try_use_ability(1)
			KEY_3: try_use_ability(2)
			KEY_4: try_use_ability(3)
