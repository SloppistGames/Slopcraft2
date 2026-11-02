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
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		if Input.mouse_mode==Input.MOUSE_MODE_VISIBLE:
			effects.stream=click_stream
			effects.play()

func _process(delta: float) -> void:
	if frequency<=0.0 or music.playing: return
	clock-=delta
	if clock<=0:
		music.play()

static func silence_seconds(value: float) -> float:
	return pow(1.0-clampf(value,0,100)/100.0,2.0)*600.0

func set_music_volume(value: float) -> void:
	music_volume=clampf(value,0,1)
	if is_instance_valid(music):
		music.volume_db=linear_to_db(maxf(.00001,music_volume))-10.0
		# Muting is gain-only. Rapid pause/unpause/stop can retain an Ogg
		# playback in the audio server; frequency controls track scheduling.

func set_music_frequency(value: float) -> void:
	frequency=clampf(value,0,100)
	if frequency<=0:
		music.stream_paused=false
		music.stop()
		clock=5.0
	elif not music.playing:
		clock=minf(clock,silence_seconds(frequency))

func _exit_tree() -> void:
	if is_instance_valid(music):
		music.stream_paused=false
		music.stop()
		music.stream=null
	if is_instance_valid(effects):
		effects.stop()
		effects.stream=null

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
