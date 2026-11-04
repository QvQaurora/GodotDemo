extends Node3D
## Minimal stub world: ground + camera + title. Esc returns to main menu.

const MAIN_MENU := "res://scenes/main_menu.tscn"

@export var map_id: String = ""
@export var map_title: String = "未命名场景"
@export var map_blurb: String = ""

var _yaw: float = 0.35
var _pitch: float = -0.55


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	_build_world()
	_build_hud()
	set_process_unhandled_input(true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
			get_tree().change_scene_to_file(MAIN_MENU)
			get_viewport().set_input_as_handled()


func _build_world() -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = _bg_color()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	environment.ambient_light_energy = 0.85
	env.environment = environment
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, 35.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = false
	add_child(sun)

	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var mesh_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80.0, 80.0)
	mesh_inst.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _ground_color()
	mat.roughness = 0.92
	mesh_inst.material_override = mat
	ground.add_child(mesh_inst)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(80.0, 0.2, 80.0)
	col.shape = shape
	col.position.y = -0.1
	ground.add_child(col)
	add_child(ground)

	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.current = true
	cam.fov = 70.0
	cam.position = Vector3(0.0, 8.0, 14.0)
	cam.rotation = Vector3(_pitch, _yaw, 0.0)
	add_child(cam)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Hud"
	add_child(layer)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	layer.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)
	var title := Label.new()
	title.text = map_title
	title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(title)
	var blurb := Label.new()
	blurb.text = map_blurb if map_blurb != "" else "占位场景 · 仅地面"
	blurb.modulate = Color(0.8, 0.85, 0.9, 1)
	vbox.add_child(blurb)
	var hint := Label.new()
	hint.text = "Esc 返回主菜单"
	hint.modulate = Color(0.65, 0.7, 0.75, 1)
	vbox.add_child(hint)


func _ground_color() -> Color:
	var h := float(map_id.hash() % 1000) / 1000.0
	return Color.from_hsv(h, 0.28, 0.42)


func _bg_color() -> Color:
	var h := float((map_id.hash() / 7) % 1000) / 1000.0
	return Color.from_hsv(h, 0.22, 0.18)
