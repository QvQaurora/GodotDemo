extends Node
## Persists and applies graphics / audio settings.

const CONFIG_PATH := "user://settings.cfg"
const SHADOW_DISTANCE := 280.0

const RESOLUTION_PRESETS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]

enum Quality { LOW, MEDIUM, HIGH, ULTRA, CUSTOM }
enum VSyncMode { OFF, ON, ADAPTIVE, MAILBOX }
## Persist IDs stay stable; UI can show a different order.
enum AntiAliasing { OFF, FXAA, MSAA_2X, MSAA_4X, MSAA_8X, TAA }
enum ShadowQuality { OFF, LOW, MEDIUM, HIGH }

var quality: int = Quality.HIGH

# Detailed graphics
var windowed: bool = true
var window_resolution: Vector2i = Vector2i(1280, 720)
var vsync_mode: int = VSyncMode.OFF
var max_fps: int = 0 # 0 = unlimited
var anti_aliasing: int = AntiAliasing.MSAA_4X
var shadow_quality: int = ShadowQuality.HIGH
var ssao: bool = true
var glow: bool = true
var fog: bool = true

# Audio
var master_volume: float = 0.8
var music_volume: float = 0.6
var sfx_volume: float = 0.8

# Controls
var mouse_sensitivity: float = 1.0

signal settings_changed


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_audio_buses()
	load_settings()
	apply_all()
	call_deferred("_bring_window_forward")


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
		apply_quality_preset(quality)
		return
	quality = int(cfg.get_value("graphics", "quality", Quality.HIGH))
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
	if cfg.has_section_key("graphics", "anti_aliasing"):
		anti_aliasing = int(cfg.get_value("graphics", "anti_aliasing", AntiAliasing.MSAA_4X))
	else:
		anti_aliasing = _migrate_legacy_aa(cfg)
	shadow_quality = int(cfg.get_value("graphics", "shadow_quality", ShadowQuality.HIGH))
	ssao = bool(cfg.get_value("graphics", "ssao", true))
	glow = bool(cfg.get_value("graphics", "glow", true))
	fog = bool(cfg.get_value("graphics", "fog", true))
	master_volume = float(cfg.get_value("audio", "master", 0.8))
	music_volume = float(cfg.get_value("audio", "music", 0.6))
	sfx_volume = float(cfg.get_value("audio", "sfx", 0.8))
	mouse_sensitivity = float(cfg.get_value("controls", "mouse_sensitivity", 1.0))


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


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "quality", quality)
	cfg.set_value("graphics", "windowed", windowed)
	cfg.set_value("graphics", "window_width", window_resolution.x)
	cfg.set_value("graphics", "window_height", window_resolution.y)
	cfg.set_value("graphics", "vsync", vsync_mode)
	cfg.set_value("graphics", "max_fps", max_fps)
	cfg.set_value("graphics", "anti_aliasing", anti_aliasing)
	cfg.set_value("graphics", "shadow_quality", shadow_quality)
	cfg.set_value("graphics", "ssao", ssao)
	cfg.set_value("graphics", "glow", glow)
	cfg.set_value("graphics", "fog", fog)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.save(CONFIG_PATH)


func apply_all() -> void:
	apply_audio()
	apply_graphics()
	settings_changed.emit()


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
	quality = preset
	match preset:
		Quality.LOW:
			anti_aliasing = AntiAliasing.OFF
			shadow_quality = ShadowQuality.OFF
			ssao = false
			glow = false
			fog = true
			max_fps = 60
		Quality.MEDIUM:
			anti_aliasing = AntiAliasing.MSAA_2X
			shadow_quality = ShadowQuality.LOW
			ssao = false
			glow = true
			fog = true
			max_fps = 0
		Quality.HIGH:
			anti_aliasing = AntiAliasing.MSAA_4X
			shadow_quality = ShadowQuality.HIGH
			ssao = true
			glow = true
			fog = true
			max_fps = 0
		Quality.ULTRA:
			anti_aliasing = AntiAliasing.MSAA_8X
			shadow_quality = ShadowQuality.HIGH
			ssao = true
			glow = true
			fog = true
			max_fps = 0


func mark_custom() -> void:
	if quality != Quality.CUSTOM:
		quality = Quality.CUSTOM


func apply_graphics() -> void:
	_apply_window_mode()
	_apply_vsync()
	Engine.max_fps = maxi(max_fps, 0)

	var vp := get_viewport()
	if vp != null:
		vp.scaling_3d_scale = 1.0
		vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		vp.use_taa = false
		match anti_aliasing:
			AntiAliasing.FXAA:
				vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
			AntiAliasing.MSAA_2X:
				vp.msaa_3d = Viewport.MSAA_2X
			AntiAliasing.MSAA_4X:
				vp.msaa_3d = Viewport.MSAA_4X
			AntiAliasing.MSAA_8X:
				vp.msaa_3d = Viewport.MSAA_8X
			AntiAliasing.TAA:
				vp.use_taa = true
			_:
				pass

	_apply_world_effects()
	settings_changed.emit()


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
			shadow_size = 8192
			shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS

	ProjectSettings.set_setting("rendering/lights_and_shadows/directional_shadow/size", shadow_size)

	for node in tree.current_scene.find_children("*", "WorldEnvironment", true, false):
		var we := node as WorldEnvironment
		if we == null or we.environment == null:
			continue
		var env := we.environment
		env.ssao_enabled = ssao
		env.glow_enabled = glow
		env.fog_enabled = fog
		if fog:
			env.fog_density = 0.0009
		if we.camera_attributes is CameraAttributesPractical:
			var attrs := we.camera_attributes as CameraAttributesPractical
			attrs.dof_blur_far_enabled = false

	for node in tree.current_scene.find_children("*", "DirectionalLight3D", true, false):
		var light := node as DirectionalLight3D
		if light == null:
			continue
		if light.name == "FillLight":
			light.shadow_enabled = false
			continue
		light.shadow_enabled = shadows_on
		light.directional_shadow_mode = shadow_mode
		light.directional_shadow_max_distance = SHADOW_DISTANCE


func quality_label(q: int) -> String:
	match q:
		Quality.LOW:
			return "低"
		Quality.MEDIUM:
			return "中"
		Quality.HIGH:
			return "高"
		Quality.ULTRA:
			return "极高"
		Quality.CUSTOM:
			return "自定义"
		_:
			return "高"
