extends Node2D
## Prototype orchestrator: builds the scene, runs the 3-encounter flow,
## routes enemy attacks to party damage / board modifiers.

# Endless mode roster. Waves = 2-3 low-tier enemies, then a mini boss.
# After each boss falls the loop counter rises and everything scales up.
const LOW_TIER := [
	{
		"name": "Goblin Scout", "hp": 55, "chip_resist": 0.0,
		"cell": Vector2i(1, 14), "scale": 7.0,
		"attacks": [
			{"name": "Slash", "time": 4.0, "kind": "damage", "power": 8},
		],
	},
	{
		"name": "Goblin", "hp": 65, "chip_resist": 0.0,
		"cell": Vector2i(0, 14), "scale": 7.0,
		"attacks": [
			{"name": "Stab", "time": 3.5, "kind": "damage", "power": 7},
		],
	},
	{
		"name": "Frost Mage", "hp": 100, "chip_resist": 0.0,
		"cell": Vector2i(16, 16), "scale": 7.0,
		"attacks": [
			{"name": "Ice Bolt", "time": 4.5, "kind": "damage", "power": 9},
			{"name": "Freeze", "time": 6.0, "kind": "freeze", "power": 4},
		],
	},
]
const BOSSES := [
	{
		"name": "Crypt Warden", "hp": 150, "chip_resist": 0.88,
		"cell": Vector2i(13, 14), "scale": 8.0, "boss": true,
		"attacks": [
			{"name": "Seal Tiles", "time": 4.0, "kind": "lock", "power": 4},
			{"name": "Crushing Blow", "time": 8.0, "kind": "damage", "power": 16},
		],
	},
	{
		"name": "Medusa", "hp": 140, "chip_resist": 0.35,
		"cell": Vector2i(17, 16), "scale": 8.0, "boss": true,
		"attacks": [
			{"name": "Petrify", "time": 5.0, "kind": "stone", "power": 5},
			{"name": "Stone Gaze", "time": 6.5, "kind": "damage", "power": 14},
		],
	},
]

# per-loop scaling
const HP_SCALE := 1.08
const DMG_SCALE := 1.05
const SPEED_SCALE := 1.02

var shaker: Node2D
var board: Board
var combat: Combat
var hud: Hud
var enemy: Enemy = null

var _shake_amt := 0.0
var _loop := 0            # completed boss cycles (drives scaling)
var _encounter_num := 0   # total encounters started this run
var _cleared := 0         # enemies defeated this run
var _wave: Array = []     # upcoming encounters (base data refs)
var _boss_i := 0          # alternates Warden / Medusa
var _current_is_boss := false
var _over := false

func _ready() -> void:
	# background art + slight dim so gameplay reads on top
	var bg := TextureRect.new()
	bg.texture = preload("res://art/BGart.png")
	bg.size = Vector2(1280, 720)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.z_index = -10
	# never intercept mouse events meant for the board
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.22)
	dim.size = Vector2(1280, 720)
	dim.z_index = -9
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

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

	if OS.get_environment("MUTE") != "":
		AudioServer.set_bus_mute(0, true)  # silent automated test runs
	if OS.get_environment("BOSSTEST") != "":
		# debug: jump straight to a boss (0 = Warden, 1 = Medusa)
		_wave = [BOSSES[int(OS.get_environment("BOSSTEST")) % BOSSES.size()]]
	Sfx.play_music()
	_next_encounter()

	var shot_dir := OS.get_environment("AUTOSHOT")
	if shot_dir != "":
		_autoshot(shot_dir)
	var sim_dir := OS.get_environment("SIMTEST")
	if sim_dir != "":
		_simtest(sim_dir)
	if OS.get_environment("INPUTTEST") != "":
		_inputtest()
	if OS.get_environment("HINTTEST") != "":
		_hinttest()
	if OS.get_environment("DEBUGMODS") != "":
		await get_tree().create_timer(1.0).timeout
		board.freeze_random(5)
		board.lock_random(5)
		board.stone_random(5)
	if OS.get_environment("HINTSHOT") != "":
		# let the board sit idle so a hint appears, then screenshot at its peak glow
		await get_tree().create_timer(4.9).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_environment("HINTSHOT") + "/hint.png")
		get_tree().quit()

func _next_encounter() -> void:
	if _wave.is_empty():
		_build_wave()
	_start_encounter(_scaled(_wave.pop_front()))

func _build_wave() -> void:
	var lows := LOW_TIER.duplicate()
	lows.shuffle()
	for i in randi_range(2, 3):
		_wave.append(lows[i % lows.size()])
	_wave.append(BOSSES[_boss_i % BOSSES.size()])
	_boss_i += 1

func _scaled(base: Dictionary) -> Dictionary:
	# apply endless-mode loop scaling to a copy of the base enemy data
	var d := base.duplicate(true)
	d.hp = int(round(d.hp * pow(HP_SCALE, _loop)))
	for a in d.attacks:
		if a.kind == "damage":
			a.power = int(round(a.power * pow(DMG_SCALE, _loop)))
		a.time = a.time / pow(SPEED_SCALE, _loop)
	return d

func _start_encounter(d: Dictionary) -> void:
	_encounter_num += 1
	_current_is_boss = d.get("boss", false)
	board.clear_modifiers()
	enemy = Enemy.new()
	enemy.position = Vector2(330, 240)
	shaker.add_child(enemy)
	enemy.setup(d)
	combat.reset_for_encounter(enemy)
	Events.encounter_started.emit("Loop %d · Encounter %d" % [_loop + 1, _encounter_num], enemy)
	var title: String = d.name + (" — Mini Boss" if _current_is_boss else "")
	Events.banner.emit(title, Color(1, 0.6, 0.55) if _current_is_boss else Color(1, 0.92, 0.7))
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
		"stone":
			board.stone_random(a.power)

func _on_enemy_died() -> void:
	combat.active = false
	board.input_enabled = false
	_cleared += 1
	if _current_is_boss:
		_loop += 1
		Sfx.play("victory")
		Events.banner.emit("BOSS DOWN! Loop %d begins..." % (_loop + 1), Color(1, 0.8, 0.3))
	else:
		Sfx.play("victory")
		Events.banner.emit("VICTORY!", Color(1, 1, 0.5))
	await get_tree().create_timer(1.9).timeout
	if _over:
		return
	_next_encounter()

func _on_defeat() -> void:
	_over = true
	board.input_enabled = false
	Sfx.fade_out_music()
	Sfx.play("defeat")
	hud.show_end("DEFEAT", Color(1, 0.35, 0.3),
		"Reached Loop %d  ·  %d enemies defeated" % [_loop + 1, _cleared])

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
			KEY_S: # debug: test stone
				board.stone_random(4)

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
		if _encounter_num != last_enc:
			last_enc = _encounter_num
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
	print("SIMTEST COMPLETE over=%s loop=%d cleared=%d party_hp=%d" % [_over, _loop, _cleared, combat.party_hp])
	get_tree().quit()

func _inputtest() -> void:
	# debug: drive a drag-swap through the REAL input pipeline (synthesized
	# mouse events), so anything that eats mouse input makes this fail.
	await get_tree().create_timer(2.5).timeout
	var mv: Array = board.find_move()
	if mv.is_empty():
		print("INPUTTEST FAIL - no move available")
		get_tree().quit()
		return
	var matches := [0]
	Events.match_made.connect(func(_k, _t, _u, _c, _p): matches[0] += 1)
	# --- test 1: drag swap ---
	var a_pos: Vector2 = board.global_position + board.cell_center(mv[0])
	var b_pos: Vector2 = board.global_position + board.cell_center(mv[1])
	_send_motion(a_pos, Vector2.ZERO)
	await get_tree().create_timer(0.05).timeout
	_send_button(a_pos, true)
	await get_tree().create_timer(0.05).timeout
	_send_motion(b_pos, b_pos - a_pos)
	await get_tree().create_timer(0.05).timeout
	_send_button(b_pos, false)
	await get_tree().create_timer(1.5).timeout
	var drag_ok: bool = matches[0] > 0
	print("INPUTTEST drag: %s" % ("PASS" if drag_ok else "FAIL"))
	# --- test 2: click-click swap ---
	while board.resolving:
		await get_tree().create_timer(0.2).timeout
	var before: int = matches[0]
	mv = board.find_move()
	if mv.is_empty():
		print("INPUTTEST click: SKIP - no move available")
		get_tree().quit()
		return
	for cell in mv:
		var pos: Vector2 = board.global_position + board.cell_center(cell)
		_send_motion(pos, Vector2.ZERO)
		await get_tree().create_timer(0.05).timeout
		_send_button(pos, true)
		await get_tree().create_timer(0.05).timeout
		_send_button(pos, false)
		await get_tree().create_timer(0.2).timeout
	await get_tree().create_timer(1.5).timeout
	var click_ok: bool = matches[0] > before
	print("INPUTTEST click: %s" % ("PASS" if click_ok else "FAIL"))
	print("INPUTTEST %s" % ("PASS" if drag_ok and click_ok else "FAIL"))
	get_tree().quit()

func _hinttest() -> void:
	# debug: verify a hint appears only after the idle delay and clears on input.
	while not board.input_enabled or board.resolving:
		await get_tree().create_timer(0.2).timeout
	await get_tree().create_timer(2.0).timeout  # before the 4s delay
	var early_clear: bool = board._hint_cells.is_empty()
	await get_tree().create_timer(2.6).timeout  # now past 4s of no input
	var appeared: bool = board._hint_cells.size() == 2
	# a deliberate click should drop the hint
	var pos: Vector2 = board.global_position + board.cell_center(Vector2i(0, 0))
	_send_button(pos, true)
	_send_button(pos, false)
	await get_tree().create_timer(0.2).timeout
	var cleared: bool = board._hint_cells.is_empty()
	print("HINTTEST early_clear=%s appeared=%s cleared_on_input=%s -> %s" % [
		early_clear, appeared, cleared,
		"PASS" if early_clear and appeared and cleared else "FAIL"])
	get_tree().quit()

func _send_button(pos: Vector2, pressed: bool) -> void:
	var b := InputEventMouseButton.new()
	b.button_index = MOUSE_BUTTON_LEFT
	b.pressed = pressed
	b.position = pos
	Input.parse_input_event(b)

func _send_motion(pos: Vector2, rel: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = pos
	m.relative = rel
	Input.parse_input_event(m)

func _autoshot(dir: String) -> void:
	# debug helper: save screenshots then quit (used for automated visual checks)
	for i in [1, 2]:
		await get_tree().create_timer(1.6).timeout
		var img := get_viewport().get_texture().get_image()
		img.save_png(dir + "/shot%d.png" % i)
	get_tree().quit()
