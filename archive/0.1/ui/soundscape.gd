extends Node
## Tiny original synthesized soundscape; no external audio files.
var music: AudioStreamPlayer
var effects: AudioStreamPlayer
var clock = 0.0
var notes = [130.81,164.81,196.0,261.63,196.0,164.81,146.83,220.0]
var note_index = 0
var click_stream: AudioStreamWAV

func _ready() -> void:
	music=AudioStreamPlayer.new()
	music.volume_db=-28
	add_child(music)
	effects=AudioStreamPlayer.new()
	effects.volume_db=-17
	add_child(effects)
	click_stream=_tone(540,.055,.45)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		if Input.mouse_mode==Input.MOUSE_MODE_VISIBLE:
			effects.stream=click_stream
			effects.play()

func _process(delta: float) -> void:
	clock-=delta
	if clock<=0:
		clock=4.8
		music.stream=_tone(notes[note_index%notes.size()],3.8,.1)
		music.play()
		note_index+=1

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
