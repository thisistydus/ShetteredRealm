extends Control
## Start screen: Shattered Realm logo over the battle backdrop,
## "press any key" prompt. Any key or click starts the game.

const GAME_SCENE := "res://scenes/main.tscn"

var _prompt: Label
var _starting := false

func _ready() -> void:
	var bg := TextureRect.new()
	bg.texture = preload("res://art/BGart.png")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(bg)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.4)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var logo := TextureRect.new()
	logo.texture = preload("res://art/SRLOGO.png")
	logo.custom_minimum_size = Vector2(760, 500)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.position = Vector2((1280 - 760) / 2.0, 40)
	logo.size = Vector2(760, 500)
	add_child(logo)
	_prompt = Label.new()
	_prompt.text = "—  PRESS ANY KEY TO START  —"
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.position = Vector2(0, 590)
	_prompt.size = Vector2(1280, 50)
	_prompt.add_theme_font_size_override("font_size", 28)
	_prompt.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_prompt.add_theme_constant_override("outline_size", 8)
	add_child(_prompt)
	# gentle pulse
	var tw := create_tween().set_loops()
	tw.tween_property(_prompt, "modulate:a", 0.35, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_prompt, "modulate:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if OS.get_environment("TITLESHOT") != "":
		await get_tree().create_timer(1.0).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TITLESHOT") + "/title.png")
		get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	if _starting:
		return
	if (event is InputEventKey or event is InputEventMouseButton) and event.pressed:
		_starting = true
		Sfx.play("ready")
		get_tree().change_scene_to_file(GAME_SCENE)
