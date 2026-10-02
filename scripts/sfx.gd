extends Node
## Sfx: synthesized engine loop, drift screech, and one-shot beeps. No audio files needed.

var _engine: AudioStreamPlayer
var _screech: AudioStreamPlayer
var _oneshots: Array[AudioStreamPlayer] = []
var _oi := 0

const RATE := 22050

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_engine = AudioStreamPlayer.new()
	_engine.stream = _make_engine()
	_engine.volume_db = -14.0
	add_child(_engine)
	_screech = AudioStreamPlayer.new()
	_screech.stream = _make_screech()
	_screech.volume_db = -28.0
	add_child(_screech)
	for i in range(6):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_oneshots.append(p)

func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w

func _make_engine() -> AudioStreamWAV:
	# buzzy 4-cylinder-ish loop: fundamental + harmonics, loop-safe length
	var n := RATE / 2  # 0.5s
	var s := PackedFloat32Array()
	s.resize(n)
	var f := 55.0  # base; pitch_scale moves it with speed
	for i in range(n):
		var t := float(i) / RATE
		var v := sin(TAU * f * t) * 0.5 + sin(TAU * f * 2.0 * t) * 0.28 \
			+ sin(TAU * f * 3.0 * t) * 0.14 + sin(TAU * f * 0.5 * t) * 0.3
		# crossfade the loop seam
		var edge := minf(1.0, minf(float(i), float(n - i)) / float(RATE / 40))
		s[i] = v * 0.5 * edge
	return _wav(s, true)

func _make_screech() -> AudioStreamWAV:
	# bandy tire noise: filtered noise with a whistle partial
	var n := RATE / 2
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var lp := 0.0
	for i in range(n):
		var t := float(i) / RATE
		var nz := rng.randf_range(-1.0, 1.0)
		lp = lp * 0.82 + nz * 0.18
		var v := lp * 1.6 + sin(TAU * 1900.0 * t) * 0.12 + sin(TAU * 2600.0 * t) * 0.07
		var edge := minf(1.0, minf(float(i), float(n - i)) / float(RATE / 40))
		s[i] = v * 0.45 * edge
	return _wav(s, true)

func _tone(freq: float, dur: float, vol := 0.5, slide := 0.0) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t := float(i) / RATE
		var f := freq * (1.0 + slide * t / dur)
		var env := sin(PI * float(i) / float(n))  # smooth in/out
		s[i] = sin(TAU * f * t) * vol * env
	return _wav(s, false)

func engine_on() -> void:
	if not _engine.playing:
		_engine.play()

func engine_off() -> void:
	_engine.stop()
	_screech.stop()

func set_engine(ratio: float) -> void:
	# ratio 0..1 (speed / max). Called every frame while racing.
	_engine.pitch_scale = 0.7 + ratio * 1.6
	_engine.volume_db = -16.0 + ratio * 7.0

func set_drift(intensity: float) -> void:
	# intensity 0..1
	if intensity > 0.03:
		if not _screech.playing:
			_screech.play()
		_screech.volume_db = -30.0 + intensity * 16.0
		_screech.pitch_scale = 0.85 + intensity * 0.4
	elif _screech.playing:
		_screech.stop()

func _play_tone(freq: float, dur: float, vol := 0.5, slide := 0.0) -> void:
	var p := _oneshots[_oi]
	_oi = (_oi + 1) % _oneshots.size()
	p.stream = _tone(freq, dur, vol, slide)
	p.play()

func count_beep() -> void:
	_play_tone(440.0, 0.18)

func go_beep() -> void:
	_play_tone(880.0, 0.4, 0.55, 0.25)

func finish_jingle() -> void:
	_play_tone(523.0, 0.16, 0.5)
	_play_tone(659.0, 0.16, 0.5)
	_play_tone(784.0, 0.34, 0.55)

func scrape() -> void:
	_play_tone(170.0, 0.22, 0.4, -0.5)
