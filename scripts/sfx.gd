extends Node
## Sound effects synthesized at startup, so the game ships without audio files. The shot can instead
## be CS2's own AK sound, imported from your CS2 install (Settings → CS2-filer).

const RATE := 44100
const AK_DIR := "user://sounds/sounds/weapons/ak47"
const AK_VOLUME_DB := -9.0

var _players := {}
var _ak: Array[AudioStreamPlayer] = []
var _ak_last := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_add("shot", _shot())
	_add("hit", _tone(1750.0, 1450.0, 0.09, 0.45, 0.0))
	_add("head", _chord([2093.0, 2637.0], 0.16, 0.38))
	_add("miss", _tone(190.0, 150.0, 0.08, 0.3, 0.5))
	_add("fail", _tone(440.0, 110.0, 0.38, 0.4, 0.35))
	_add("start", _tone(880.0, 1320.0, 0.07, 0.3, 0.0))
	_add("done", _arpeggio([880.0, 1108.7, 1318.5, 1760.0], 0.075, 0.32))
	load_ak_sound()


## Reads CS2's AK recordings, if they've been imported. CS2 picks one of four per shot; the tails of
## quick shots overlap.
func load_ak_sound() -> void:
	for p in _ak:
		p.queue_free()
	_ak.clear()
	for n in range(1, 5):
		var path := ProjectSettings.globalize_path(AK_DIR.path_join("ak47_0%d.wav" % n))
		var wav := AudioStreamWAV.load_from_file(path) if FileAccess.file_exists(path) else null
		if wav:
			var p := AudioStreamPlayer.new()
			p.stream = wav
			p.max_polyphony = 3
			p.volume_db = AK_VOLUME_DB
			add_child(p)
			_ak.append(p)


func has_ak_sound() -> bool:
	return not _ak.is_empty()


func play(sound: String, pitch: float = 1.0) -> void:
	# Looked up at runtime so this script also compiles in tests, where there are no autoloads.
	var settings := get_node_or_null("/root/Settings")
	if sound == "shot" and has_ak_sound() and settings and settings.ak_sound:
		var pick := randi() % _ak.size()
		if pick == _ak_last and _ak.size() > 1:
			pick = (pick + 1) % _ak.size()
		_ak_last = pick
		_ak[pick].play()
		return
	var p: AudioStreamPlayer = _players.get(sound)
	if p:
		p.pitch_scale = pitch
		p.play()


func _add(sound: String, stream: AudioStreamWAV) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.max_polyphony = 6
	add_child(p)
	_players[sound] = p


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = bytes
	return wav


## Pitch sweep from f0 to f1 with a fast attack and exponential decay; `grit` mixes in a square wave.
func _tone(f0: float, f1: float, dur: float, vol: float, grit: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	for i in n:
		var x := float(i) / n
		phase += TAU * lerpf(f0, f1, x) / RATE
		var wave := lerpf(sin(phase), signf(sin(phase)) * 0.5, grit)
		s[i] = wave * _env(i, x, 5.0) * vol
	return _wav(s)


func _chord(freqs: Array, dur: float, vol: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var x := float(i) / n
		var v := 0.0
		for f: float in freqs:
			v += sin(TAU * f * i / RATE)
		s[i] = v / freqs.size() * _env(i, x, 4.0) * vol
	return _wav(s)


func _arpeggio(freqs: Array, step: float, vol: float) -> AudioStreamWAV:
	var per := int(step * RATE)
	var n := per * freqs.size() + int(0.15 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for k in freqs.size():
		var f: float = freqs[k]
		var span := n - k * per
		for j in span:
			s[k * per + j] += sin(TAU * f * j / RATE) * _env(j, float(j) / span, 6.0) * vol * 0.5
	return _wav(s)


## A soft gunshot: filtered noise over a low thump.
func _shot() -> AudioStreamWAV:
	var n := int(0.12 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var noise := 0.0
	for i in n:
		var x := float(i) / n
		noise = lerpf(noise, rng.randf_range(-1.0, 1.0), 0.3)
		var thump := sin(TAU * 70.0 * i / RATE) * exp(-14.0 * x)
		s[i] = (noise * exp(-10.0 * x) * 0.9 + thump * 0.7) * 0.22
	return _wav(s)


func _env(i: int, x: float, decay: float) -> float:
	return minf(1.0, i / (0.003 * RATE)) * exp(-decay * x)
