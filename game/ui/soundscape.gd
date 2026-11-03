extends Node
## Slopwoofer Lullaby, supplied by the game creator. UI effects are synthesized.
const TRACK_TITLE = "Slopwoofer Lullaby"
const TRACK = preload("res://assets/music/slopwoofer_lullaby.ogg")
var music: AudioStreamPlayer
var effects: AudioStreamPlayer
var clock = 5.0
var frequency = 50.0
var music_volume = 0.65
var click_stream: AudioStreamWAV
var _shutting_down = false
var _retiring_playbacks: Array[WeakRef] = []

func _ready() -> void:
	music=AudioStreamPlayer.new()
	music.stream=TRACK
	music.volume_db=-10.0
	add_child(music)
	music.finished.connect(func(): clock=silence_seconds(frequency))
	effects=AudioStreamPlayer.new()
	effects.volume_db=-17
	add_child(effects)
	click_stream=_tone(540,.055,.45)
	set_music_volume(music_volume)

func _input(event: InputEvent) -> void:
	if _shutting_down: return
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		if Input.mouse_mode==Input.MOUSE_MODE_VISIBLE:
			effects.stream=click_stream
			effects.play()

func _process(delta: float) -> void:
	_prune_playbacks()
	if _shutting_down or frequency<=0.0 or music.playing: return
	clock-=delta
	if clock<=0:
		music.play()

static func silence_seconds(value: float) -> float:
	return pow(1.0-clampf(value,0,100)/100.0,2.0)*600.0

func set_music_volume(value: float) -> void:
	music_volume=clampf(value,0,1)
	if is_instance_valid(music):
		music.volume_db=linear_to_db(maxf(.00001,music_volume))-10.0
		# Gain-only mute preserves the track position when volume returns.

func set_music_frequency(value: float) -> void:
	frequency=clampf(value,0,100)
	if frequency<=0:
		_stop_player(music)
		clock=5.0
	elif not music.playing:
		clock=minf(clock,silence_seconds(frequency))

func _exit_tree() -> void:
	_stop_player(music,true)
	_stop_player(effects,true)

func _stop_player(audio_player: AudioStreamPlayer,release_stream: bool = false) -> void:
	if not is_instance_valid(audio_player): return
	if audio_player.has_stream_playback():
		_retiring_playbacks.append(weakref(audio_player.get_stream_playback()))
	# stop() already handles paused streams; do not briefly resume them.
	audio_player.stop()
	if release_stream: audio_player.stream=null

static func _playback_released(playback: WeakRef) -> bool:
	# Keep get_ref() in this synchronous scope: a temporary strong reference
	# must not survive an await and prevent the audio server's final release.
	return playback.get_ref()==null

func _prune_playbacks() -> void:
	for playback in _retiring_playbacks.duplicate():
		if _playback_released(playback): _retiring_playbacks.erase(playback)

func shutdown(timeout_seconds: float = 1.0) -> bool:
	_shutting_down=true
	frequency=0
	set_process(false)
	set_process_input(false)
	_stop_player(music,true)
	_stop_player(effects,true)
	var deadline: int=Time.get_ticks_msec()+int(maxf(timeout_seconds,0.0)*1000)
	_prune_playbacks()
	# AudioStreamPlayer.stop() schedules a fade and asynchronous disposal.
	# Wait for disposal itself rather than guessing a driver-specific delay.
	while not _retiring_playbacks.is_empty() and Time.get_ticks_msec()<deadline:
		await get_tree().create_timer(.01).timeout
		_prune_playbacks()
	return _retiring_playbacks.is_empty()

func _tone(freq: float,duration: float,brightness: float) -> AudioStreamWAV:
	var rate=16000
	var count=int(rate*duration)
	var bytes=PackedByteArray()
	bytes.resize(count*2)
	for i in count:
		var t=float(i)/rate
		var envelope=minf(t/.04,1.0)*pow(maxf(0,1-t/duration),2)
		var wave=sin(t*freq*TAU)+brightness*sin(t*freq*2*TAU)+.13*sin(t*freq*.501*TAU)
		var sample=int(clampf(wave*envelope*.4,-1,1)*32767)
		bytes.encode_s16(i*2,sample)
	var stream=AudioStreamWAV.new()
	stream.format=AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate=rate
	stream.data=bytes
	return stream
