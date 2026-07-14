extends Node2D
## Debug-only: renders labeled cells of the creature sheet so we can pick
## sprite coordinates. Run with env ROWS="0,2,4" AUTOSHOT=/path.

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.12, 0.15)
	bg.size = Vector2(1280, 720)
	add_child(bg)
	var rows_env := OS.get_environment("ROWS")
	var rows := []
	for r in rows_env.split(","):
		rows.append(int(r))
	var sheet: Texture2D = load("res://art/creatures.png")
	var y_off := 30.0
	for r in rows:
		for c in 18:
			var at := AtlasTexture.new()
			at.atlas = sheet
			at.region = Rect2(c * 24, r * 24, 24, 24)
			var s := Sprite2D.new()
			s.texture = at
			s.scale = Vector2(2.5, 2.5)
			s.position = Vector2(40 + c * 70, y_off + 30)
			add_child(s)
			var l := Label.new()
			l.text = "%d,%d" % [c, r]
			l.position = Vector2(12 + c * 70, y_off + 62)
			l.add_theme_font_size_override("font_size", 12)
			add_child(l)
		var rl := Label.new()
		rl.text = "row %d" % r
		rl.position = Vector2(2, y_off + 20)
		rl.add_theme_font_size_override("font_size", 11)
		rl.add_theme_color_override("font_color", Color(1, 1, 0.5))
		add_child(rl)
		y_off += 95
	_shot()

func _shot() -> void:
	await get_tree().create_timer(1.0).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("AUTOSHOT") + "/sheet.png")
	get_tree().quit()
