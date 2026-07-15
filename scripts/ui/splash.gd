extends Control
## Amigo Park splash: fade logo in, hold, fade out, then title screen.
## Any input skips ahead. Automated test runs bypass straight to the game.

const TITLE_SCENE := "res://scenes/title.tscn"
const GAME_SCENE := "res://scenes/main.tscn"

var _done := false

func _ready() -> void:
	# automated test hooks live in main.gd - skip the intro entirely
	for v in ["SIMTEST", "INPUTTEST", "AUTOSHOT", "BOSSTEST", "DEBUGMODS"]:
		if OS.get_environment(v) != "":
			get_tree().change_scene_to_file.call_deferred(GAME_SCENE)
			return
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var logo := TextureRect.new()
	logo.texture = preload("res://art/AmigoPark.png")
	logo.custom_minimum_size = Vector2(460, 460)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	center.add_child(logo)
	logo.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(logo, "modulate:a", 1.0, 1.0)
	tw.tween_interval(1.4)
	tw.tween_property(logo, "modulate:a", 0.0, 0.7)
	tw.finished.connect(_go_title)
	if OS.get_environment("SPLASHSHOT") != "":
		await get_tree().create_timer(1.3).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_environment("SPLASHSHOT") + "/splash.png")
		get_tree().quit()

func _go_title() -> void:
	if _done:
		return
	_done = true
	get_tree().change_scene_to_file(TITLE_SCENE)

func _unhandled_input(event: InputEvent) -> void:
	if (event is InputEventKey or event is InputEventMouseButton) and event.pressed:
		_go_title()
