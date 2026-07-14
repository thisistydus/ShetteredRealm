class_name Hud
extends Control
## All placeholder UI, built in code: enemy telegraph + HP, party HP,
## four character panels with ATB bars, floating text, banners, end screens.

var combat: Combat = null
var enemy: Enemy = null

var _enemy_name: Label
var _enemy_hp_bar: ColorRect
var _enemy_hp_bg: ColorRect
var _enemy_hp_label: Label
var _intent_name: Label
var _intent_target: Label
var _intent_bar: ColorRect
var _intent_bar_bg: ColorRect
var _intent_time: Label
var _party_hp_bar: ColorRect
var _party_hp_label: Label
var _encounter_label: Label
var _panels: Array = []      # per char: {panel, atb_bar, ready_label, base_color}
var _banner_label: Label
var _end_screen: Control
var _end_title: Label
var _time := 0.0

const PANEL_POS := Vector2(30, 500)
const PANEL_SIZE := Vector2(305, 100)

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_enemy_ui()
	_build_party_ui()
	_build_overlays()
	Events.encounter_started.connect(_on_encounter_started)
	Events.float_text.connect(_spawn_float)
	Events.banner.connect(_show_banner)
	Events.party_hp_changed.connect(func(_hp, _mx): pass) # bars are polled

# ---------------- construction helpers ----------------

func _label(text: String, pos: Vector2, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l

func _bar(pos: Vector2, size: Vector2, fg: Color, bg := Color(0.1, 0.1, 0.12, 0.9)) -> Array:
	var back := ColorRect.new()
	back.position = pos
	back.size = size
	back.color = bg
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	var front := ColorRect.new()
	front.position = Vector2(2, 2)
	front.size = size - Vector2(4, 4)
	front.color = fg
	front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(front)
	return [back, front]

func _build_enemy_ui() -> void:
	_encounter_label = _label("", Vector2(24, 10), 24, Color(1, 0.95, 0.8))
	# telegraph panel
	var p := Panel.new()
	p.position = Vector2(130, 44)
	p.size = Vector2(400, 96)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.08, 0.08, 0.85)
	sb.set_corner_radius_all(10)
	sb.border_color = Color(0.8, 0.4, 0.3)
	sb.set_border_width_all(2)
	p.add_theme_stylebox_override("panel", sb)
	add_child(p)
	_intent_name = _label("", Vector2(150, 52), 26, Color(1, 0.8, 0.6))
	_intent_target = _label("", Vector2(150, 84), 16, Color(0.9, 0.9, 0.9))
	var bars := _bar(Vector2(150, 108), Vector2(300, 18), Color(0.95, 0.45, 0.25))
	_intent_bar_bg = bars[0]
	_intent_bar = bars[1]
	_intent_time = _label("", Vector2(458, 104), 20, Color(1, 0.8, 0.6))
	# enemy hp
	_enemy_name = _label("", Vector2(130, 356), 22)
	var hp_bars := _bar(Vector2(130, 388), Vector2(400, 24), Color(0.85, 0.2, 0.25))
	_enemy_hp_bg = hp_bars[0]
	_enemy_hp_bar = hp_bars[1]
	_enemy_hp_label = _label("", Vector2(545, 388), 18)

func _build_party_ui() -> void:
	_party_hp_label = _label("Party HP", Vector2(30, 428), 18, Color(0.6, 1.0, 0.7))
	var bars := _bar(Vector2(30, 456), Vector2(620, 26), Color(0.3, 0.85, 0.4))
	_party_hp_bar = bars[1]
	for i in 4:
		_panels.append(_build_char_panel(i))

func _build_char_panel(i: int) -> Dictionary:
	var col := Tile.KIND_COLORS[i]
	var pos := PANEL_POS + Vector2((PANEL_SIZE.x + 10) * (i % 2), (PANEL_SIZE.y + 10) * (i / 2))
	var btn := Button.new()
	btn.position = pos
	btn.size = PANEL_SIZE
	btn.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.09, 0.13, 0.95)
	sb.set_corner_radius_all(10)
	sb.border_color = col
	sb.set_border_width_all(3)
	btn.add_theme_stylebox_override("normal", sb)
	var sb2 := sb.duplicate()
	sb2.bg_color = Color(0.16, 0.16, 0.22)
	btn.add_theme_stylebox_override("hover", sb2)
	btn.add_theme_stylebox_override("pressed", sb2)
	btn.pressed.connect(func(): if combat: combat.try_use_ability(i))
	add_child(btn)
	# portrait
	var tex := AtlasTexture.new()
	tex.atlas = Tile.sheet
	var c: Vector2i = Tile.KIND_CELLS[i]
	tex.region = Rect2(c.x * 24, c.y * 24, 24, 24)
	var tr := TextureRect.new()
	tr.texture = tex
	tr.position = Vector2(10, 14)
	tr.size = Vector2(48, 48)
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(tr)
	# labels
	var name_l := Label.new()
	name_l.text = "[%d] %s" % [i + 1, Combat.CHARS[i].name]
	name_l.position = Vector2(68, 8)
	name_l.add_theme_font_size_override("font_size", 20)
	name_l.add_theme_color_override("font_color", col.lightened(0.4))
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(name_l)
	var ab_l := Label.new()
	ab_l.text = "%s — %s" % [Combat.CHARS[i].ability, Combat.CHARS[i].hint]
	ab_l.position = Vector2(68, 34)
	ab_l.add_theme_font_size_override("font_size", 13)
	ab_l.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	ab_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(ab_l)
	var ready_l := Label.new()
	ready_l.text = "READY!"
	ready_l.position = Vector2(220, 8)
	ready_l.add_theme_font_size_override("font_size", 18)
	ready_l.add_theme_color_override("font_color", Color(1, 1, 0.4))
	ready_l.visible = false
	ready_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(ready_l)
	# atb bar
	var back := ColorRect.new()
	back.position = Vector2(10, 68)
	back.size = Vector2(PANEL_SIZE.x - 20, 20)
	back.color = Color(0.05, 0.05, 0.07)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(back)
	var front := ColorRect.new()
	front.position = Vector2(2, 2)
	front.size = Vector2(back.size.x - 4, 16)
	front.color = col
	front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(front)
	return {"panel": btn, "atb_bar": front, "atb_w": back.size.x - 4, "ready": ready_l, "color": col}

func _build_overlays() -> void:
	_banner_label = _label("", Vector2(0, 290), 52, Color(1, 1, 0.85))
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.size = Vector2(1280, 80)
	_banner_label.visible = false
	# end screen (win / lose)
	_end_screen = Control.new()
	_end_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_screen.visible = false
	add_child(_end_screen)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.72)
	_end_screen.add_child(dim)
	_end_title = Label.new()
	_end_title.position = Vector2(0, 260)
	_end_title.size = Vector2(1280, 100)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_title.add_theme_font_size_override("font_size", 64)
	_end_screen.add_child(_end_title)
	var btn := Button.new()
	btn.text = "  Restart  "
	btn.position = Vector2(560, 400)
	btn.add_theme_font_size_override("font_size", 28)
	btn.pressed.connect(func(): get_tree().reload_current_scene())
	_end_screen.add_child(btn)

# ---------------- events ----------------

func _on_encounter_started(index: int, e: Node) -> void:
	enemy = e
	_encounter_label.text = "Encounter %d / 3" % (index + 1)
	_enemy_name.text = e.data.name

func _spawn_float(text: String, world_pos: Vector2, color: Color, size: int) -> void:
	var l := _label(text, world_pos + Vector2(-40, -10), size, color)
	l.z_index = 100
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 46, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(l.queue_free)

func _show_banner(text: String, color: Color) -> void:
	_banner_label.text = text
	_banner_label.add_theme_color_override("font_color", color)
	_banner_label.visible = true
	_banner_label.scale = Vector2(0.6, 0.6)
	_banner_label.pivot_offset = Vector2(640, 40)
	_banner_label.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_banner_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_banner_label, "modulate:a", 1.0, 0.2)
	tw.chain().tween_interval(1.0)
	tw.chain().tween_property(_banner_label, "modulate:a", 0.0, 0.3)
	tw.chain().tween_callback(func(): _banner_label.visible = false)

func show_end(title: String, color: Color) -> void:
	_end_title.text = title
	_end_title.add_theme_color_override("font_color", color)
	_end_screen.visible = true

# ---------------- per-frame polling ----------------

func _process(delta: float) -> void:
	_time += delta
	# enemy hp + telegraph
	var e_ok := enemy != null and is_instance_valid(enemy)
	if e_ok:
		_enemy_hp_bar.size.x = 396.0 * float(enemy.hp) / float(enemy.max_hp)
		_enemy_hp_label.text = "%d / %d" % [enemy.hp, enemy.max_hp]
		if enemy.active and not enemy.current_attack.is_empty():
			var a: Dictionary = enemy.current_attack
			_intent_name.text = a.name
			_intent_target.text = _target_line(a)
			_intent_time.text = "%.1f" % maxf(0.0, enemy.time_left)
			_intent_bar.size.x = 296.0 * clampf(enemy.time_left / a.time, 0.0, 1.0)
			# urgency tint
			_intent_bar.color = Color(0.95, 0.45, 0.25) if enemy.time_left > 1.2 else Color(1.0, 0.15, 0.1)
		else:
			_intent_name.text = "—"
			_intent_target.text = ""
			_intent_time.text = ""
			_intent_bar.size.x = 0
	# party
	if combat:
		_party_hp_bar.size.x = 616.0 * float(combat.party_hp) / float(Combat.MAX_HP)
		_party_hp_label.text = "Party HP  %d / %d" % [combat.party_hp, Combat.MAX_HP]
		for i in 4:
			var p: Dictionary = _panels[i]
			p.atb_bar.size.x = p.atb_w * combat.atb[i] / Combat.ATB_MAX
			var ready: bool = combat.is_ready(i)
			p.ready.visible = ready
			if ready:
				var pulse := 0.75 + 0.25 * sin(_time * 8.0)
				p.panel.modulate = Color(1, 1, 1).lerp(Color(1.5, 1.5, 1.2), pulse - 0.75)
				p.atb_bar.color = p.color.lightened(0.3 * pulse)
			else:
				p.panel.modulate = Color.WHITE
				p.atb_bar.color = p.color

func _target_line(a: Dictionary) -> String:
	match a.kind:
		"damage": return "→ targets the party  (%d dmg)" % a.power
		"freeze": return "→ targets the board  (freezes %d tiles)" % a.power
		"lock": return "→ targets the board  (locks %d tiles)" % a.power
	return ""
