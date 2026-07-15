extends Node
## Fire-and-forget sound player. Sfx.play("pop", 1.1)

var _streams := {}

func _ready() -> void:
	for n in ["pop", "big", "ability", "heal", "hurt", "ready", "freeze", "lock", "stone", "interrupt", "victory", "defeat"]:
		var path := "res://audio/%s.wav" % n
		if ResourceLoader.exists(path):
			_streams[n] = load(path)

var _music: AudioStreamPlayer = null

func play_music(path := "res://audio/music/byteblade_clash.mp3", volume_db := -11.0) -> void:
	if _music == null:
		_music = AudioStreamPlayer.new()
		add_child(_music)
	var s: AudioStream = load(path)
	if s is AudioStreamMP3:
		s.loop = true
	_music.stream = s
	_music.volume_db = volume_db
	_music.play()

func fade_out_music(dur := 1.2) -> void:
	if _music == null or not _music.playing:
		return
	var tw := create_tween()
	tw.tween_property(_music, "volume_db", -60.0, dur)
	tw.tween_callback(_music.stop)

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
