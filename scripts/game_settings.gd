extends Node
## Persists and applies graphics / audio settings.

const CONFIG_PATH := "user://settings.cfg"

enum Quality { LOW, MEDIUM, HIGH, ULTRA, CUSTOM }
enum WindowMode { WINDOWED, BORDERLESS, FULLSCREEN }
enum VSyncMode { OFF, ON, ADAPTIVE, MAILBOX }
enum MsaaMode { OFF, X2, X4, X8 }
enum ShadowQuality { OFF, LOW, MEDIUM, HIGH }
enum MotionBlurMode { OFF, LOW, MEDIUM, HIGH }

var quality: int = Quality.HIGH

# Detailed graphics
var window_mode: int = WindowMode.WINDOWED
var vsync_mode: int = VSyncMode.ON
var max_fps: int = 0 # 0 = unlimited
var render_scale: float = 1.0
var msaa: int = MsaaMode.X4
var fxaa: bool = true
var taa: bool = false
var shadow_quality: int = ShadowQuality.HIGH
var shadow_distance: float = 280.0
var ssao: bool = true
var glow: bool = true
var fog: bool = true
var dof: bool = true
var motion_blur: int = MotionBlurMode.OFF

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
	# Exclusive / borderless-fullscreen break Alt+Tab visuals on Vulkan+Windows.
	# Keep a normal or maximized window so the swapchain restores cleanly.
	if window_mode == WindowMode.FULLSCREEN:
		window_mode = WindowMode.BORDERLESS
		save_settings()
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
	# Tiny resize forces swapchain / framebuffer recreation on Windows.
	var size := DisplayServer.window_get_size()
	if size.x > 2 and size.y > 2:
		DisplayServer.window_set_size(size + Vector2i(1, 0))
		await get_tree().process_frame
		DisplayServer.window_set_size(size)
	# Kick the renderer so Alt+Tab doesn't leave a black stale frame.
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
	window_mode = int(cfg.get_value("graphics", "window_mode", WindowMode.WINDOWED))
	vsync_mode = int(cfg.get_value("graphics", "vsync", VSyncMode.ON))
	max_fps = int(cfg.get_value("graphics", "max_fps", 0))
	render_scale = float(cfg.get_value("graphics", "render_scale", 1.0))
	msaa = int(cfg.get_value("graphics", "msaa", MsaaMode.X4))
	fxaa = bool(cfg.get_value("graphics", "fxaa", true))
	taa = bool(cfg.get_value("graphics", "taa", false))
	shadow_quality = int(cfg.get_value("graphics", "shadow_quality", ShadowQuality.HIGH))
	shadow_distance = float(cfg.get_value("graphics", "shadow_distance", 280.0))
	ssao = bool(cfg.get_value("graphics", "ssao", true))
	glow = bool(cfg.get_value("graphics", "glow", true))
	fog = bool(cfg.get_value("graphics", "fog", true))
	dof = bool(cfg.get_value("graphics", "dof", true))
	motion_blur = int(cfg.get_value("graphics", "motion_blur", MotionBlurMode.OFF))
	master_volume = float(cfg.get_value("audio", "master", 0.8))
	music_volume = float(cfg.get_value("audio", "music", 0.6))
	sfx_volume = float(cfg.get_value("audio", "sfx", 0.8))
	mouse_sensitivity = float(cfg.get_value("controls", "mouse_sensitivity", 1.0))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "quality", quality)
	cfg.set_value("graphics", "window_mode", window_mode)
	cfg.set_value("graphics", "vsync", vsync_mode)
	cfg.set_value("graphics", "max_fps", max_fps)
	cfg.set_value("graphics", "render_scale", render_scale)
	cfg.set_value("graphics", "msaa", msaa)
	cfg.set_value("graphics", "fxaa", fxaa)
	cfg.set_value("graphics", "taa", taa)
	cfg.set_value("graphics", "shadow_quality", shadow_quality)
	cfg.set_value("graphics", "shadow_distance", shadow_distance)
	cfg.set_value("graphics", "ssao", ssao)
	cfg.set_value("graphics", "glow", glow)
	cfg.set_value("graphics", "fog", fog)
	cfg.set_value("graphics", "dof", dof)
	cfg.set_value("graphics", "motion_blur", motion_blur)
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
			render_scale = 0.7
			msaa = MsaaMode.OFF
			fxaa = false
			taa = false
			shadow_quality = ShadowQuality.OFF
			shadow_distance = 120.0
			ssao = false
			glow = false
			fog = true
			dof = false
			motion_blur = MotionBlurMode.OFF
			max_fps = 60
			vsync_mode = VSyncMode.ON
		Quality.MEDIUM:
			render_scale = 0.85
			msaa = MsaaMode.X2
			fxaa = true
			taa = false
			shadow_quality = ShadowQuality.LOW
			shadow_distance = 200.0
			ssao = false
			glow = true
			fog = true
			dof = false
			motion_blur = MotionBlurMode.OFF
			max_fps = 0
			vsync_mode = VSyncMode.ON
		Quality.HIGH:
			render_scale = 1.0
			msaa = MsaaMode.X4
			fxaa = true
			taa = false
			shadow_quality = ShadowQuality.HIGH
			shadow_distance = 280.0
			ssao = true
			glow = true
			fog = true
			dof = true
			motion_blur = MotionBlurMode.LOW
			max_fps = 0
			vsync_mode = VSyncMode.ON
		Quality.ULTRA:
			render_scale = 1.0
			msaa = MsaaMode.X8
			fxaa = true
			taa = true
			shadow_quality = ShadowQuality.HIGH
			shadow_distance = 400.0
			ssao = true
			glow = true
			fog = true
			dof = true
			motion_blur = MotionBlurMode.MEDIUM
			max_fps = 0
			vsync_mode = VSyncMode.ADAPTIVE


func mark_custom() -> void:
	if quality != Quality.CUSTOM:
		quality = Quality.CUSTOM


func apply_graphics() -> void:
	_apply_window_mode()
	_apply_vsync()
	Engine.max_fps = maxi(max_fps, 0)

	var vp := get_viewport()
	if vp != null:
		vp.scaling_3d_scale = clampf(render_scale, 0.5, 1.0)
		match msaa:
			MsaaMode.OFF:
				vp.msaa_3d = Viewport.MSAA_DISABLED
			MsaaMode.X2:
				vp.msaa_3d = Viewport.MSAA_2X
			MsaaMode.X4:
				vp.msaa_3d = Viewport.MSAA_4X
			MsaaMode.X8:
				vp.msaa_3d = Viewport.MSAA_8X
		vp.screen_space_aa = (
			Viewport.SCREEN_SPACE_AA_FXAA if fxaa else Viewport.SCREEN_SPACE_AA_DISABLED
		)
		vp.use_taa = taa

	_apply_world_effects()
	settings_changed.emit()


func _apply_window_mode(recenter: bool = true) -> void:
	match window_mode:
		WindowMode.WINDOWED:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			if recenter:
				var screen := DisplayServer.window_get_current_screen()
				var usable := DisplayServer.screen_get_usable_rect(screen)
				var target := Vector2i(1280, 720)
				if usable.size.x > 0 and usable.size.y > 0:
					target = Vector2i(
						mini(1280, usable.size.x - 40),
						mini(720, usable.size.y - 60)
					)
				DisplayServer.window_set_size(target)
				DisplayServer.window_set_position(usable.position + (usable.size - target) / 2)
		WindowMode.BORDERLESS, WindowMode.FULLSCREEN:
			# Maximized borderless window — NOT exclusive/fullscreen present mode.
			# Real fullscreen often returns black after Alt+Tab on Vulkan Windows.
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)


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
			attrs.dof_blur_far_enabled = dof

	for node in tree.current_scene.find_children("*", "DirectionalLight3D", true, false):
		var light := node as DirectionalLight3D
		if light == null:
			continue
		if light.name == "FillLight":
			light.shadow_enabled = false
			continue
		light.shadow_enabled = shadows_on
		light.directional_shadow_mode = shadow_mode
		light.directional_shadow_max_distance = shadow_distance


func motion_blur_strength() -> float:
	match motion_blur:
		MotionBlurMode.LOW:
			return 0.35
		MotionBlurMode.MEDIUM:
			return 0.65
		MotionBlurMode.HIGH:
			return 1.0
		_:
			return 0.0


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
