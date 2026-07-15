extends SceneTree
func _init():
	var s1: AudioStream = load("res://audio/music/byteblade_clash.mp3")
	var s2: AudioStream = load("res://audio/music/byteblade_clash_2.mp3")
	print("TRACK1 ok=%s len=%.1fs  TRACK2 ok=%s len=%.1fs" % [s1 != null, s1.get_length() if s1 else -1.0, s2 != null, s2.get_length() if s2 else -1.0])
	quit()
