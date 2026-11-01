extends CanvasLayer
## Lightweight screen-space motion blur driven by camera movement.

@onready var blur_rect: ColorRect = $BlurRect

var _mat: ShaderMaterial
var _prev_cam_pos: Vector3 = Vector3.ZERO
var _has_prev: bool = false


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/motion_blur.gdshader")
	blur_rect.material = _mat
	blur_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameSettings.settings_changed.connect(_on_settings_changed)
	_on_settings_changed()


func _on_settings_changed() -> void:
	visible = GameSettings.motion_blur_strength() > 0.0
	if not visible and _mat:
		_mat.set_shader_parameter("blur_amount", 0.0)


func _process(delta: float) -> void:
	if _mat == null:
		return
	var strength := GameSettings.motion_blur_strength()
	if strength <= 0.0:
		_mat.set_shader_parameter("blur_amount", 0.0)
		return

	var cam := get_viewport().get_camera_3d()
	if cam == null:
		_mat.set_shader_parameter("blur_amount", 0.0)
		return

	var pos := cam.global_position
	if not _has_prev:
		_prev_cam_pos = pos
		_has_prev = true
		return

	var vel := (pos - _prev_cam_pos) / maxf(delta, 0.0001)
	_prev_cam_pos = pos

	# Project motion into camera local XZ for screen-ish direction
	var local := cam.global_transform.basis.inverse() * vel
	var dir := Vector2(local.x, -local.y * 0.35 - local.z * 0.15)
	if dir.length() < 0.001:
		dir = Vector2(1.0, 0.0)
	else:
		dir = dir.normalized()

	var speed := clampf(vel.length() / 28.0, 0.0, 1.0)
	_mat.set_shader_parameter("blur_direction", dir)
	_mat.set_shader_parameter("blur_amount", speed * strength)
