extends Node2D
## Prototype orchestrator: builds the scene, runs the 3-encounter flow,
## routes enemy attacks to party damage / board modifiers.

const ENCOUNTERS := [
	{
		"name": "Goblin Scout", "hp": 55, "chip_resist": 0.0,
		"cell": Vector2i(1, 14), "scale": 7.0,
		"attacks": [
			{"name": "Slash", "time": 4.0, "kind": "damage", "power": 8},
		],
	},
	{
		"name": "Frost Mage", "hp": 100, "chip_resist": 0.0,
		"cell": Vector2i(8, 16), "scale": 7.0,
		"attacks": [
			{"name": "Ice Bolt", "time": 4.5, "kind": "damage", "power": 9},
			{"name": "Freeze", "time": 6.0, "kind": "freeze", "power": 4},
		],
	},
	{
		"name": "Crypt Warden", "hp": 150, "chip_resist": 0.88,
		"cell": Vector2i(13, 14), "scale": 8.0,
		"attacks": [
			{"name": "Seal Tiles", "time": 4.0, "kind": "lock", "power": 4},
			{"name": "Crushing Blow", "time": 8.0, "kind": "damage", "power": 16},
		],
	},
]

var shaker: Node2D
var board: Board
var combat: Combat
var hud: Hud
var enemy: Enemy = null

var _shake_amt := 0.0
var _encounter_i := 0
var _over := false

func _ready() -> void:
	# background
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.09, 0.14)
	bg.size = Vector2(1280, 720)
	bg.z_index = -10
	add_child(bg)

	shaker = Node2D.new()
	add_child(shaker)
	board = Board.new()
	board.position = Vector2(700, 88)
	shaker.add_child(board)
	combat = Combat.new()
	combat.board = board
	add_child(combat)
	hud = Hud.new()
	add_child(hud)
	hud.combat = combat

	Events.enemy_attack.connect(_on_enemy_attack)
	Events.enemy_died.connect(_on_enemy_died)
	Events.party_defeated.connect(_on_defeat)
	Events.shake.connect(func(a): _shake_amt = maxf(_shake_amt, a))

	_start_encounter(0)

	var shot_dir := OS.get_environment("AUTOSHOT")
	if shot_dir != "":
		_autoshot(shot_dir)
	var sim_dir := OS.get_environment("SIMTEST")
	if sim_dir != "":
		_simtest(sim_dir)
	if OS.get_environment("DEBUGMODS") != "":
		await get_tree().create_timer(1.0).timeout
		board.freeze_random(5)
		board.lock_random(5)

func _start_encounter(i: int) -> void:
	_encounter_i = i
	var d: Dictionary = ENCOUNTERS[i]
	board.clear_modifiers()
	enemy = Enemy.new()
	enemy.position = Vector2(330, 240)
	shaker.add_child(enemy)
	enemy.setup(d)
	combat.reset_for_encounter(enemy)
	Events.encounter_started.emit(i, enemy)
	var title: String = d.name + (" — Mini Boss" if i == 2 else "")
	Events.banner.emit(title, Color(1, 0.92, 0.7))
	await get_tree().create_timer(1.5).timeout
	if _over:
		return
	enemy.begin()
	combat.active = true
	board.input_enabled = true

func _on_enemy_attack(a: Dictionary) -> void:
	if enemy != null and is_instance_valid(enemy):
		Events.float_text.emit(a.name + "!", enemy.global_position + Vector2(-20, -100), Color(1, 0.6, 0.4), 26)
	match a.kind:
		"damage":
			combat.damage_party(a.power)
		"freeze":
			board.freeze_random(a.power)
		"lock":
			board.lock_random(a.power)

func _on_enemy_died() -> void:
	combat.active = false
	board.input_enabled = false
	Sfx.play("victory")
	Events.banner.emit("VICTORY!", Color(1, 1, 0.5))
	await get_tree().create_timer(1.9).timeout
	if _over:
		return
	if _encounter_i < ENCOUNTERS.size() - 1:
		_start_encounter(_encounter_i + 1)
	else:
		_over = true
		hud.show_end("YOU WIN!", Color(1, 0.9, 0.4))

func _on_defeat() -> void:
	_over = true
	board.input_enabled = false
	Sfx.play("defeat")
	hud.show_end("DEFEAT", Color(1, 0.35, 0.3))

func _process(delta: float) -> void:
	# screen shake, applied to the world (HUD stays still)
	if _shake_amt > 0.0:
		_shake_amt = maxf(0.0, _shake_amt - 45.0 * delta)
		shaker.position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake_amt * 0.6
	else:
		shaker.position = Vector2.ZERO

func _unhandled_key_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_K: # debug: kill current enemy
				if enemy != null and is_instance_valid(enemy):
					enemy.take_damage(9999, false)
			KEY_F: # debug: test freeze
				board.freeze_random(4)
			KEY_L: # debug: test lock
				board.lock_random(4)

func _simtest(dir: String) -> void:
	# debug autoplayer: random valid swaps + abilities, screenshots, then quit.
	# exercises matching, cascades, ATB, abilities, modifiers, encounter flow.
	Engine.time_scale = 2.0
	var start := Time.get_ticks_msec()
	var enc_start := start
	var last_enc := 0
	var shots := {8: false, 26: false, 45: false}
	while not _over:
		await get_tree().create_timer(0.4).timeout
		var elapsed := (Time.get_ticks_msec() - start) / 1000.0
		if _encounter_i != last_enc:
			last_enc = _encounter_i
			enc_start = Time.get_ticks_msec()
		for s in shots:
			if not shots[s] and elapsed >= s:
				shots[s] = true
				get_viewport().get_texture().get_image().save_png(dir + "/sim%d.png" % s)
		for i in 4:
			if combat.is_ready(i) and randf() < 0.5:
				combat.try_use_ability(i)
		if board.input_enabled and not board.resolving:
			var mv: Array = board.find_move()
			if mv.size() == 2:
				board.sim_swap(mv[0], mv[1])
		# force encounter progress so we cover all three fights
		if enemy != null and is_instance_valid(enemy) and enemy.active \
				and (Time.get_ticks_msec() - enc_start) / 1000.0 > 18.0:
			enemy.take_damage(9999, false)
			enc_start = Time.get_ticks_msec()
		if elapsed > 75.0:
			break
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(dir + "/sim_end.png")
	print("SIMTEST COMPLETE over=%s encounter=%d party_hp=%d" % [_over, _encounter_i, combat.party_hp])
	get_tree().quit()

func _autoshot(dir: String) -> void:
	# debug helper: save screenshots then quit (used for automated visual checks)
	for i in [1, 2]:
		await get_tree().create_timer(1.6).timeout
		var img := get_viewport().get_texture().get_image()
		img.save_png(dir + "/shot%d.png" % i)
	get_tree().quit()
