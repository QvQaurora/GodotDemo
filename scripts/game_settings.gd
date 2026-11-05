extends Node
## Persists and applies graphics / audio settings.

const CONFIG_PATH := "user://settings.cfg"
## Shadow draw distance follows 渲染距离 (must cover the visible stream ring).
const CHUNK_METERS := 64.0
## Player-facing integer render radii (meters).
const RENDER_METERS_LOW := 100
const RENDER_METERS_MEDIUM := 300
const RENDER_METERS_HIGH := 500

const RESOLUTION_PRESETS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]

## Keep numeric IDs stable for saves.
enum Quality { LOW, MEDIUM, HIGH, ULTRA, CUSTOM }
enum VSyncMode { OFF, ON, ADAPTIVE, MAILBOX }
## Legacy single-slot AA (migrated into msaa/fxaa/taa on load).
enum AntiAliasing { OFF, FXAA, MSAA_2X, MSAA_4X, MSAA_8X, TAA }
enum MsaaMode { OFF, MSAA_2X, MSAA_4X, MSAA_8X }
enum ShadowQuality { OFF, LOW, MEDIUM, HIGH }
## Independent of graphics preset — controls chunk / grass / actor stream radii.
enum RenderDistance { LOW, MEDIUM, HIGH, ULTRA }

var quality: int = Quality.MEDIUM
var render_distance: int = RenderDistance.MEDIUM

# Detailed graphics
var windowed: bool = true
var window_resolution: Vector2i = Vector2i(1280, 720)
var vsync_mode: int = VSyncMode.OFF
var max_fps: int = 0 # 0 = unlimited (not tied to quality presets)
## Combinable AA: MSAA level + optional FXAA + optional TAA (Godot Forward+ supports all three).
var msaa_mode: int = MsaaMode.MSAA_2X
var aa_fxaa: bool = false
var aa_taa: bool = false
var shadow_quality: int = ShadowQuality.LOW
var ssao: bool = false
var glow: bool = true
var fog: bool = true

# Audio
var master_volume: float = 0.8
var music_volume: float = 0.6
var sfx_volume: float = 0.8

# Controls
var mouse_sensitivity: float = 1.0
## action_id -> Key keycode
var keybinds: Dictionary = {}

# Player appearance (Kenney Animated Characters)
var player_body_id: String = "medium"
var player_outfit_id: String = "skaterMaleA"
## slot_id -> accessory_id (empty = none)
var player_gear: Dictionary = {}

const KEYBIND_ACTIONS: Array[Dictionary] = [
	{"id": "interact", "label": "互动 / 拾取"},
	{"id": "map", "label": "打开地图"},
	{"id": "inventory", "label": "背包"},
	{"id": "jump", "label": "跳跃"},
	{"id": "sprint", "label": "奔跑"},
]

signal settings_changed
signal keybinds_changed


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	keybinds = default_keybinds()
	_ensure_audio_buses()
	load_settings()
	apply_all()
	call_deferred("_bring_window_forward")


func default_keybinds() -> Dictionary:
	return {
		"interact": KEY_E,
		"map": KEY_M,
		"inventory": KEY_TAB,
		"jump": KEY_SPACE,
		"sprint": KEY_SHIFT,
	}


func get_key(action_id: String) -> int:
	if keybinds.has(action_id):
		return int(keybinds[action_id])
	return int(default_keybinds().get(action_id, KEY_NONE))


func set_key(action_id: String, keycode: int) -> void:
	keybinds[action_id] = keycode
	keybinds_changed.emit()
	save_settings()


func matches_action(action_id: String, event: InputEvent) -> bool:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return false
	var key := event as InputEventKey
	var code := get_key(action_id)
	if code == KEY_NONE:
		return false
	if key.keycode == code or key.physical_keycode == code:
		return true
	# Some layouts only fill key_label for letters.
	if key.key_label == code:
		return true
	return false


func action_held(action_id: String) -> bool:
	var code := get_key(action_id)
	return Input.is_physical_key_pressed(code) or Input.is_key_pressed(code)


func action_label(action_id: String) -> String:
	return keycode_label(get_key(action_id))


func keycode_label(keycode: int) -> String:
	match keycode:
		KEY_ESCAPE:
			return "Esc"
		KEY_TAB:
			return "Tab"
		KEY_SPACE:
			return "空格"
		KEY_SHIFT:
			return "Shift"
		KEY_CTRL:
			return "Ctrl"
		KEY_ALT:
			return "Alt"
		_:
			var named := OS.get_keycode_string(keycode)
			return named if named != "" else str(keycode)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		call_deferred("_restore_after_alt_tab")
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _bring_window_forward() -> void:
	_apply_window_mode()
	DisplayServer.window_move_to_foreground()


func _restore_after_alt_tab() -> void:
	# Alt+Tab back often leaves a black/stale Vulkan frame until the window is nudged.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
		_apply_window_mode(false)
	DisplayServer.window_move_to_foreground()
	var size := DisplayServer.window_get_size()
	if size.x > 2 and size.y > 2:
		DisplayServer.window_set_size(size + Vector2i(1, 0))
		await get_tree().process_frame
		DisplayServer.window_set_size(size)
	RenderingServer.force_draw(true)


func _ensure_audio_buses() -> void:
	if AudioServer.get_bus_index("Music") == -1:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, "Music")
		AudioServer.set_bus_send(idx, "Master")
	if AudioServer.get_bus_index("SFX") == -1:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, "SFX")
		AudioServer.set_bus_send(idx, "Master")


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		# First launch: medium preset.
		apply_quality_preset(Quality.MEDIUM)
		return
	quality = _migrate_quality(int(cfg.get_value("graphics", "quality", Quality.MEDIUM)))
	if cfg.has_section_key("graphics", "windowed"):
		windowed = bool(cfg.get_value("graphics", "windowed", true))
	elif cfg.has_section_key("graphics", "window_mode"):
		# Legacy: 0 = windowed, anything else was borderless/fullscreen-like.
		windowed = int(cfg.get_value("graphics", "window_mode", 0)) == 0
	window_resolution = Vector2i(
		int(cfg.get_value("graphics", "window_width", 1280)),
		int(cfg.get_value("graphics", "window_height", 720))
	)
	window_resolution = _clamp_resolution(window_resolution)
	vsync_mode = int(cfg.get_value("graphics", "vsync", VSyncMode.OFF))
	max_fps = int(cfg.get_value("graphics", "max_fps", 0))
	# Combinable AA (new) or migrate from legacy single anti_aliasing slot.
	if cfg.has_section_key("graphics", "msaa_mode"):
		msaa_mode = int(cfg.get_value("graphics", "msaa_mode", MsaaMode.MSAA_2X))
		aa_fxaa = bool(cfg.get_value("graphics", "aa_fxaa", false))
		aa_taa = bool(cfg.get_value("graphics", "aa_taa", false))
	else:
		var legacy_aa := AntiAliasing.MSAA_2X
		if cfg.has_section_key("graphics", "anti_aliasing"):
			legacy_aa = int(cfg.get_value("graphics", "anti_aliasing", AntiAliasing.MSAA_2X))
		else:
			legacy_aa = _migrate_legacy_aa(cfg)
		_apply_legacy_aa_slot(legacy_aa)
	shadow_quality = int(cfg.get_value("graphics", "shadow_quality", ShadowQuality.LOW))
	ssao = bool(cfg.get_value("graphics", "ssao", false))
	glow = bool(cfg.get_value("graphics", "glow", true))
	fog = bool(cfg.get_value("graphics", "fog", true))
	render_distance = int(cfg.get_value("graphics", "render_distance", RenderDistance.MEDIUM))
	if render_distance == RenderDistance.ULTRA or render_distance < RenderDistance.LOW or render_distance > RenderDistance.HIGH:
		render_distance = RenderDistance.HIGH if render_distance == RenderDistance.ULTRA else RenderDistance.MEDIUM
	master_volume = float(cfg.get_value("audio", "master", 0.8))
	music_volume = float(cfg.get_value("audio", "music", 0.6))
	sfx_volume = float(cfg.get_value("audio", "sfx", 0.8))
	mouse_sensitivity = float(cfg.get_value("controls", "mouse_sensitivity", 1.0))
	keybinds = default_keybinds()
	for action in KEYBIND_ACTIONS:
		var id: String = action["id"]
		var code := int(cfg.get_value("controls", "key_%s" % id, keybinds[id]))
		if code == KEY_NONE or code == 0:
			code = int(default_keybinds().get(id, KEY_NONE))
		keybinds[id] = code
	player_body_id = str(cfg.get_value("player", "body_id", "medium"))
	player_outfit_id = str(cfg.get_value("player", "outfit_id", "skaterMaleA"))
	player_gear = {}
	if cfg.has_section_key("player", "gear_json"):
		var parsed: Variant = JSON.parse_string(str(cfg.get_value("player", "gear_json", "{}")))
		if typeof(parsed) == TYPE_DICTIONARY:
			player_gear = parsed
	save_settings()


func _migrate_quality(q: int) -> int:
	# UI: 低/中/高/自定义. Legacy 极致 → 高.
	if q == Quality.ULTRA:
		return Quality.HIGH
	if q < Quality.LOW or q > Quality.CUSTOM:
		return Quality.MEDIUM
	return q


func _migrate_legacy_aa(cfg: ConfigFile) -> int:
	var taa := bool(cfg.get_value("graphics", "taa", false))
	var msaa := int(cfg.get_value("graphics", "msaa", 2))
	var fxaa := bool(cfg.get_value("graphics", "fxaa", true))
	if taa:
		return AntiAliasing.TAA
	match msaa:
		1:
			return AntiAliasing.MSAA_2X
		2:
			return AntiAliasing.MSAA_4X
		3:
			return AntiAliasing.MSAA_8X
		_:
			return AntiAliasing.FXAA if fxaa else AntiAliasing.OFF


func _apply_legacy_aa_slot(slot: int) -> void:
	msaa_mode = MsaaMode.OFF
	aa_fxaa = false
	aa_taa = false
	match slot:
		AntiAliasing.FXAA:
			aa_fxaa = true
		AntiAliasing.TAA:
			aa_taa = true
		AntiAliasing.MSAA_2X:
			msaa_mode = MsaaMode.MSAA_2X
		AntiAliasing.MSAA_4X:
			msaa_mode = MsaaMode.MSAA_4X
		AntiAliasing.MSAA_8X:
			msaa_mode = MsaaMode.MSAA_8X
		_:
			pass


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "quality", quality)
	cfg.set_value("graphics", "windowed", windowed)
	cfg.set_value("graphics", "window_width", window_resolution.x)
	cfg.set_value("graphics", "window_height", window_resolution.y)
	cfg.set_value("graphics", "vsync", vsync_mode)
	cfg.set_value("graphics", "max_fps", max_fps)
	cfg.set_value("graphics", "msaa_mode", msaa_mode)
	cfg.set_value("graphics", "aa_fxaa", aa_fxaa)
	cfg.set_value("graphics", "aa_taa", aa_taa)
	cfg.set_value("graphics", "shadow_quality", shadow_quality)
	cfg.set_value("graphics", "ssao", ssao)
	cfg.set_value("graphics", "glow", glow)
	cfg.set_value("graphics", "fog", fog)
	cfg.set_value("graphics", "render_distance", render_distance)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	for action in KEYBIND_ACTIONS:
		var id: String = action["id"]
		cfg.set_value("controls", "key_%s" % id, int(keybinds.get(id, KEY_NONE)))
	cfg.set_value("player", "body_id", player_body_id)
	cfg.set_value("player", "outfit_id", player_outfit_id)
	cfg.set_value("player", "gear_json", JSON.stringify(player_gear))
	cfg.save(CONFIG_PATH)


func apply_all() -> void:
	apply_audio()
	apply_graphics() # already emits settings_changed


func apply_audio() -> void:
	_set_bus_linear("Master", master_volume)
	_set_bus_linear("Music", music_volume)
	_set_bus_linear("SFX", sfx_volume)


func _set_bus_linear(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var v := clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_mute(idx, v <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))


func apply_quality_preset(preset: int) -> void:
	## 低 = 全最低；高 = 全最高；中 = 中间档。自定义不改写当前选项。
	quality = preset
	match preset:
		Quality.LOW:
			msaa_mode = MsaaMode.OFF
			aa_fxaa = false
			aa_taa = false
			shadow_quality = ShadowQuality.OFF
			ssao = false
			glow = false
			fog = false
			render_distance = RenderDistance.LOW
		Quality.MEDIUM:
			msaa_mode = MsaaMode.MSAA_2X
			aa_fxaa = true
			aa_taa = false
			shadow_quality = ShadowQuality.MEDIUM
			ssao = false
			glow = true
			fog = true
			render_distance = RenderDistance.MEDIUM
		Quality.HIGH, Quality.ULTRA:
			# MSAA 8x + TAA; skip FXAA so High stays sharp instead of soft/muddy.
			msaa_mode = MsaaMode.MSAA_8X
			aa_fxaa = false
			aa_taa = true
			shadow_quality = ShadowQuality.HIGH
			ssao = true
			glow = true
			fog = true
			render_distance = RenderDistance.HIGH
		_:
			pass


func is_quality_detail_property(property: String) -> bool:
	## Tweaking these re-resolves 画质预设 (匹配低/中/高则切回，否则自定义).
	return property in [
		"msaa_mode", "aa_fxaa", "aa_taa", "shadow_quality",
		"ssao", "glow", "fog", "render_distance",
	]


func matches_quality_preset(preset: int) -> bool:
	match preset:
		Quality.LOW:
			return (
				msaa_mode == MsaaMode.OFF
				and not aa_fxaa and not aa_taa
				and shadow_quality == ShadowQuality.OFF
				and not ssao and not glow and not fog
				and render_distance == RenderDistance.LOW
			)
		Quality.MEDIUM:
			return (
				msaa_mode == MsaaMode.MSAA_2X
				and aa_fxaa and not aa_taa
				and shadow_quality == ShadowQuality.MEDIUM
				and not ssao and glow and fog
				and render_distance == RenderDistance.MEDIUM
			)
		Quality.HIGH:
			return (
				msaa_mode == MsaaMode.MSAA_8X
				and not aa_fxaa and aa_taa
				and shadow_quality == ShadowQuality.HIGH
				and ssao and glow and fog
				and render_distance == RenderDistance.HIGH
			)
		_:
			return false


func resolve_quality_from_settings() -> int:
	## If current options exactly match 低/中/高, use that preset; else 自定义.
	for preset in [Quality.LOW, Quality.MEDIUM, Quality.HIGH]:
		if matches_quality_preset(preset):
			quality = preset
			return quality
	quality = Quality.CUSTOM
	return quality


func apply_graphics() -> void:
	_apply_window_mode()
	_apply_vsync()
	Engine.max_fps = maxi(max_fps, 0)

	var vp := get_viewport()
	if vp != null:
		# Always native scale — internal downscale made Low look soft/wrong.
		vp.scaling_3d_scale = 1.0
		# Stacked AA — Godot Forward+ allows MSAA + TAA + FXAA together.
		match msaa_mode:
			MsaaMode.MSAA_2X:
				vp.msaa_3d = Viewport.MSAA_2X
			MsaaMode.MSAA_4X:
				vp.msaa_3d = Viewport.MSAA_4X
			MsaaMode.MSAA_8X:
				vp.msaa_3d = Viewport.MSAA_8X
			_:
				vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.use_taa = aa_taa
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa_fxaa else Viewport.SCREEN_SPACE_AA_DISABLED

	_apply_world_effects()
	settings_changed.emit()


func streaming_budget() -> Dictionary:
	## Driven by the player-facing 渲染距离 setting (not locked to quality preset).
	var meters := render_distance_meters()
	var visual := maxi(ceili(float(meters) / CHUNK_METERS), 1)
	match render_distance:
		RenderDistance.LOW:
			return {
				"visual_chunks": visual,
				"detail_chunks": visual,
				"collision_chunks": 1,
				"grass_chunks": 1,
				"grass_per_chunk": 18,
				"actor_distance": 70.0,
				"update_interval": 0.50,
			}
		RenderDistance.MEDIUM:
			return {
				"visual_chunks": visual,
				"detail_chunks": maxi(visual - 1, 1),
				"collision_chunks": 2,
				"grass_chunks": 2,
				"grass_per_chunk": 36,
				"actor_distance": 120.0,
				"update_interval": 0.32,
			}
		_:
			return {
				"visual_chunks": visual,
				"detail_chunks": maxi(visual - 1, 2),
				"collision_chunks": 3,
				"grass_chunks": 3,
				"grass_per_chunk": 48,
				"actor_distance": 160.0,
				"update_interval": 0.25,
			}


func shadow_distance_for_render() -> float:
	## Shadows cover the labeled render radius (meters), not a loose chunk guess.
	return float(render_distance_meters()) + 30.0


func camera_far_for_render() -> float:
	## Keep the full terrain / mountains in frustum always.
	## Render-distance feel comes from fog + chunk streaming — not camera far-clip
	## (short far-clip made distant peaks vanish when looked at head-on, then
	## reappear at the screen edge after a slight yaw).
	return 2000.0


func render_distance_meters(d: int = -1) -> int:
	var rd := render_distance if d < 0 else d
	match rd:
		RenderDistance.LOW:
			return RENDER_METERS_LOW
		RenderDistance.MEDIUM:
			return RENDER_METERS_MEDIUM
		_:
			return RENDER_METERS_HIGH


func available_resolutions() -> Array[Vector2i]:
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen).size
	var out: Array[Vector2i] = []
	for res in RESOLUTION_PRESETS:
		if usable.x <= 0 or usable.y <= 0 or (res.x <= usable.x and res.y <= usable.y):
			out.append(res)
	if out.is_empty():
		out.append(Vector2i(1280, 720))
	if not out.has(window_resolution):
		out.insert(0, window_resolution)
	return out


func _clamp_resolution(res: Vector2i) -> Vector2i:
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen).size
	if usable.x > 0 and usable.y > 0:
		res.x = clampi(res.x, 640, usable.x)
		res.y = clampi(res.y, 360, usable.y)
	else:
		res.x = maxi(res.x, 640)
		res.y = maxi(res.y, 360)
	return res


func _apply_window_mode(recenter: bool = true) -> void:
	if windowed:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var target := _clamp_resolution(window_resolution)
		window_resolution = target
		DisplayServer.window_set_size(target)
		if recenter:
			var screen := DisplayServer.window_get_current_screen()
			var usable := DisplayServer.screen_get_usable_rect(screen)
			if usable.size.x > 0 and usable.size.y > 0:
				DisplayServer.window_set_position(usable.position + (usable.size - target) / 2)
	else:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _apply_vsync() -> void:
	match vsync_mode:
		VSyncMode.OFF:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		VSyncMode.ON:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		VSyncMode.ADAPTIVE:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ADAPTIVE)
		VSyncMode.MAILBOX:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_MAILBOX)


func _apply_world_effects() -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return

	var shadows_on := shadow_quality != ShadowQuality.OFF
	var shadow_size := 2048
	var shadow_mode := DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	match shadow_quality:
		ShadowQuality.LOW:
			shadow_size = 2048
			shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		ShadowQuality.MEDIUM:
			shadow_size = 4096
			shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		ShadowQuality.HIGH:
			shadow_size = 4096
			shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS

	ProjectSettings.set_setting("rendering/lights_and_shadows/directional_shadow/size", shadow_size)

	for node in tree.current_scene.find_children("*", "WorldEnvironment", true, false):
		var we := node as WorldEnvironment
		if we == null or we.environment == null:
			continue
		var env := we.environment
		env.ssao_enabled = ssao
		if ssao:
			# Defaults are too subtle under forest fill light — push contact darkening.
			env.ssao_radius = 1.35
			env.ssao_intensity = 3.2
			env.ssao_power = 2.0
			env.ssao_detail = 0.65
			env.ssao_horizon = 0.06
			env.ssao_sharpness = 0.85
			env.ssao_light_affect = 0.55
		env.glow_enabled = glow
		if glow:
			# Stronger bloom so sun/sky/bright leaves visibly flare when toggled.
			env.glow_normalized = false
			env.glow_intensity = 1.15
			env.glow_strength = 1.05
			env.glow_bloom = 0.45
			env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
			env.glow_hdr_threshold = 0.75
			env.glow_hdr_scale = 2.2
			env.glow_hdr_luminance_cap = 12.0
			env.set_glow_level(1, 1.0)
			env.set_glow_level(2, 1.0)
			env.set_glow_level(3, 0.85)
			env.set_glow_level(4, 0.55)
			env.set_glow_level(5, 0.3)
		env.fog_enabled = fog
		if fog:
			# Fog horizon tracks the labeled meter distance so 100/300/500 look different.
			var fog_end := float(render_distance_meters()) * 0.98
			env.fog_mode = Environment.FOG_MODE_DEPTH
			env.fog_density = 0.0012
			env.fog_depth_begin = fog_end * 0.55
			env.fog_depth_end = maxf(fog_end, 90.0)
			env.fog_aerial_perspective = 0.35
		else:
			env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		# Slightly less flat ambient when SSAO is on so creases actually darken.
		if ssao:
			env.ambient_light_energy = 0.38
		else:
			env.ambient_light_energy = 0.55
		if we.camera_attributes is CameraAttributesPractical:
			var attrs := we.camera_attributes as CameraAttributesPractical
			attrs.dof_blur_far_enabled = false

	var cam_far := camera_far_for_render()
	for node in tree.current_scene.find_children("*", "Camera3D", true, false):
		var cam := node as Camera3D
		if cam != null:
			cam.far = cam_far

	for node in tree.current_scene.find_children("*", "DirectionalLight3D", true, false):
		var light := node as DirectionalLight3D
		if light == null:
			continue
		if light.name == "FillLight":
			light.shadow_enabled = false
			# Slightly cheaper fill on Low; High keeps original energy.
			light.light_energy = 0.18 if quality == Quality.LOW else 0.25
			continue
		light.shadow_enabled = shadows_on
		light.directional_shadow_mode = shadow_mode
		light.directional_shadow_max_distance = shadow_distance_for_render()
		light.directional_shadow_blend_splits = true
		# Slightly softer contact to reduce acne inside the stream radius.
		light.shadow_bias = 0.03
		light.shadow_normal_bias = 1.5
		if shadow_quality == ShadowQuality.LOW or quality == Quality.LOW:
			light.shadow_blur = 1.0
		else:
			light.shadow_blur = 1.25


func quality_label(q: int) -> String:
	match q:
		Quality.LOW:
			return "低"
		Quality.MEDIUM:
			return "中"
		Quality.HIGH:
			return "高"
		Quality.CUSTOM:
			return "自定义"
		_:
			return "中"


func render_distance_label(d: int) -> String:
	return "%d 米" % render_distance_meters(d)
