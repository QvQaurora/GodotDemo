extends Node
## Forest BGM (Kenney Music Loops, CC0) + soft wind bed on the Music bus.


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Buses may not exist yet if this runs before GameSettings finishes.
	if GameSettings.has_method("apply_audio"):
		GameSettings.apply_audio()

	var bgm := AudioStreamPlayer.new()
	bgm.name = "BgmPlayer"
	bgm.bus = "Music"
	bgm.process_mode = Node.PROCESS_MODE_ALWAYS
	bgm.stream = _load_looping_ogg("res://assets/audio/bgm_forest.ogg")
	bgm.volume_db = -4.0
	bgm.autoplay = false
	add_child(bgm)
	if bgm.stream != null:
		bgm.play()
		print("BGM playing: ", bgm.stream.get_length(), "s")
	else:
		push_error("BGM stream failed to load")

	var wind := AudioStreamPlayer.new()
	wind.name = "AmbientPlayer"
	wind.bus = "Music"
	wind.process_mode = Node.PROCESS_MODE_ALWAYS
	wind.stream = _make_wind_stream()
	wind.volume_db = -24.0
	add_child(wind)
	wind.play()


func _load_looping_ogg(res_path: String) -> AudioStream:
	var stream := load(res_path) as AudioStream
	if stream == null:
		push_error("BGM missing: " + res_path)
		return null
	stream = stream.duplicate()
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	return stream


func _make_wind_stream() -> AudioStreamWAV:
	var sample_rate := 22050
	var seconds := 8.0
	var sample_count := int(sample_rate * seconds)
	var data := PackedByteArray()
	data.resize(sample_count * 2)

	var rng := RandomNumberGenerator.new()
	rng.seed = 2026

	var a := 0.0
	var b := 0.0
	var c := 0.0
	var gust := 0.0
	var fade := int(sample_rate * 0.35)

	for i in sample_count:
		var white := rng.randf_range(-1.0, 1.0)
		a = a * 0.997 + white * 0.003
		b = b * 0.994 + a * 0.006
		c = c * 0.990 + b * 0.010
		gust = gust * 0.9994 + white * 0.0006

		var t := float(i) / float(sample_rate)
		var tone := (
			sin(t * TAU * 48.0) * 0.018
			+ sin(t * TAU * 72.0) * 0.012
			+ sin(t * TAU * 96.0) * 0.008
		)
		var wind := c * (0.22 + gust * 0.08)
		var sample := clampf(wind + tone, -1.0, 1.0)

		var env := 1.0
		if i < fade:
			env = float(i) / float(fade)
		elif i > sample_count - fade:
			env = float(sample_count - i) / float(fade)
		env = env * env * (3.0 - 2.0 * env)
		sample *= env * 0.55

		var s16 := int(sample * 32767.0)
		data[i * 2] = s16 & 0xFF
		data[i * 2 + 1] = (s16 >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = sample_count
	return stream
