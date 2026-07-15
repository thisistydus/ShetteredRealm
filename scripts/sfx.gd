extends Node
## Fire-and-forget sound player. Sfx.play("pop", 1.1)

var _streams := {}

func _ready() -> void:
	for n in ["pop", "big", "ability", "heal", "hurt", "ready", "freeze", "lock", "stone", "interrupt", "victory", "defeat"]:
		var path := "res://audio/%s.wav" % n
		if ResourceLoader.exists(path):
			_streams[n] = load(path)

# Battle music playlist: track 1 -> track 2 -> back to track 1 -> ...
const PLAYLIST := [
	"res://audio/music/byteblade_clash.mp3",
	"res://audio/music/byteblade_clash_2.mp3",
]

var _music: AudioStreamPlayer = null
var _track_i := 0
var _music_stopping := false

func play_music(volume_db := -11.0) -> void:
	if _music == null:
		_music = AudioStreamPlayer.new()
		add_child(_music)
		_music.finished.connect(_on_track_finished)
	_music_stopping = false
	_track_i = 0
	_music.volume_db = volume_db
	_start_track()

func _start_track() -> void:
	var s: AudioStream = load(PLAYLIST[_track_i])
	if s is AudioStreamMP3:
		s.loop = false  # tracks alternate instead of looping individually
	_music.stream = s
	_music.play()

func _on_track_finished() -> void:
	if _music_stopping:
		return
	_track_i = (_track_i + 1) % PLAYLIST.size()
	_start_track()

func fade_out_music(dur := 1.2) -> void:
	if _music == null or not _music.playing:
		return
	_music_stopping = true
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
