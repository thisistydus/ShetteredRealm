extends Node
## Fire-and-forget sound player. Sfx.play("pop", 1.1)

var _streams := {}

func _ready() -> void:
	for n in ["pop", "big", "ability", "heal", "hurt", "ready", "freeze", "lock", "interrupt", "victory", "defeat"]:
		var path := "res://audio/%s.wav" % n
		if ResourceLoader.exists(path):
			_streams[n] = load(path)

func play(name: String, pitch := 1.0, volume_db := -6.0) -> void:
	if not _streams.has(name):
		return
	var p := AudioStreamPlayer.new()
	p.stream = _streams[name]
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.finished.connect(p.queue_free)
	add_child(p)
	p.play()
