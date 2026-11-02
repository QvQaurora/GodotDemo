extends CharacterBody3D
## Third-person Kenney Animated Character. Uniform scale only — no axis stretching.

@export var walk_speed: float = 5.5
@export var run_speed: float = 11.0
@export var jump_velocity: float = 8.5
@export var gravity_scale: float = 2.8
@export var look_sensitivity: float = 0.0025
@export var min_pitch: float = -1.2
@export var max_pitch: float = 0.55
@export var character_path: String = "res://assets/kenney_characters/characterMedium.fbx"
@export var skin_path: String = "res://assets/kenney_characters/Skins/skaterMaleA.png"
@export var character_height: float = 1.8

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _jump_pressed: bool = false
var _air_height: float = 0.0
var _air_vel: float = 0.0
## When false (inside a house), Y is not forced to outdoor terrain height.
var stick_to_terrain: bool = true

var _anim: AnimationPlayer
var _visual: Node3D
var _skeleton: Skeleton3D
var _current_anim: String = ""
## Model yaw relative to the camera-facing body — follows move direction so backpedaling shows the face.
var _model_yaw: float = 0.0
var _skin_tex: Texture2D
var _head_bones: Array[int] = []

@onready var pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var model: Node3D = $Model

const FEET_CLEARANCE := 0.06
const MODEL_TURN_SPEED := 14.0

enum CamMode { THIRD, FIRST }
var _cam_mode: CamMode = CamMode.THIRD
var _pivot_base_x: float = 0.0


func _ready() -> void:
	add_to_group("player")
	# Collide with props/walls (layer 1), NOT terrain trimesh (layer 4 / value 8).
	collision_layer = 2
	collision_mask = 1
	motion_mode = MOTION_MODE_GROUNDED
	floor_snap_length = 0.0
	camera.current = true
	_pivot_base_x = pivot.rotation.x
	_load_kenney_character()
	_apply_camera_mode()
	if get_tree().paused:
		get_tree().paused = false
	call_deferred("_snap_to_ground")
	if DisplayServer.window_is_focused():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _terrain_y() -> float:
	var forest := get_tree().get_first_node_in_group("forest_world")
	if forest != null and forest.has_method("get_terrain_height"):
		return float(forest.call("get_terrain_height", global_position.x, global_position.z))
	return 0.0


func _snap_to_ground() -> void:
	for _i in 40:
		var forest := get_tree().get_first_node_in_group("forest_world")
		if forest != null and forest.has_method("get_terrain_height"):
			_air_height = 0.0
			_air_vel = 0.0
			velocity = Vector3.ZERO
			global_position.y = _terrain_y() + FEET_CLEARANCE
			return
		await get_tree().process_frame


func _inventory_blocks_play() -> bool:
	var inv := get_tree().get_first_node_in_group("inventory_ui")
	return inv != null and inv.has_method("is_open") and bool(inv.call("is_open"))


func _cycle_camera_mode() -> void:
	_cam_mode = CamMode.FIRST if _cam_mode == CamMode.THIRD else CamMode.THIRD
	_apply_camera_mode()


func _apply_camera_mode() -> void:
	match _cam_mode:
		CamMode.THIRD:
			pivot.position = Vector3(0.0, 1.5, 0.0)
			spring_arm.spring_length = 5.0
			spring_arm.margin = 0.2
			spring_arm.position = Vector3.ZERO
			# Restore slight downward look baked into the scene spring arm.
			spring_arm.rotation_degrees = Vector3(-15.0, 0.0, 0.0)
			if absf(pivot.rotation.x) < 0.01:
				pivot.rotation.x = _pivot_base_x
			min_pitch = -1.2
			max_pitch = 0.55
			pivot.rotation.x = clampf(pivot.rotation.x, min_pitch, max_pitch)
			camera.fov = 70.0
			camera.near = 0.05
			if model != null:
				model.visible = true
			_set_first_person_head_hidden(false)
		CamMode.FIRST:
			# Eye-height camera; keep the real body so arms/legs play true clips.
			pivot.position = Vector3(0.0, 1.58, 0.0)
			spring_arm.spring_length = 0.0
			spring_arm.margin = 0.01
			spring_arm.position = Vector3.ZERO
			spring_arm.rotation = Vector3.ZERO
			min_pitch = -1.2
			max_pitch = 1.0
			pivot.rotation.x = clampf(pivot.rotation.x, min_pitch, max_pitch)
			camera.fov = 80.0
			camera.near = 0.05
			if model != null:
				model.visible = true
				model.rotation.y = 0.0
			_model_yaw = 0.0
			_set_first_person_head_hidden(true)


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused or _inventory_blocks_play():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := look_sensitivity * GameSettings.mouse_sensitivity
		rotate_y(-event.relative.x * sens)
		pivot.rotate_x(-event.relative.y * sens)
		pivot.rotation.x = clampf(pivot.rotation.x, min_pitch, max_pitch)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_jump_pressed = true
		elif event.keycode == KEY_U:
			_cycle_camera_mode()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if DisplayServer.window_is_focused() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	if _inventory_blocks_play():
		velocity = Vector3.ZERO
		if stick_to_terrain:
			move_and_slide()
			global_position.y = _terrain_y() + FEET_CLEARANCE + _air_height
		_update_animation(false)
		return

	var input_dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		input_dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		input_dir.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		input_dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		input_dir.x += 1.0
	if input_dir.length_squared() > 1.0:
		input_dir = input_dir.normalized()

	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y))
	direction.y = 0.0
	if direction.length_squared() > 0.0001:
		direction = direction.normalized()

	var running := Input.is_physical_key_pressed(KEY_SHIFT)
	var target_speed := run_speed if running else walk_speed

	if direction != Vector3.ZERO:
		velocity.x = direction.x * target_speed
		velocity.z = direction.z * target_speed
		if _cam_mode == CamMode.FIRST:
			# Body already turns with the camera; keep mesh aligned so you see real arm swing.
			_model_yaw = 0.0
			model.rotation.y = 0.0
		else:
			_face_move_direction(direction, delta)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		if _cam_mode == CamMode.FIRST:
			_model_yaw = 0.0
			model.rotation.y = 0.0

	if stick_to_terrain:
		var on_ground := _air_height <= 0.001
		if _jump_pressed and on_ground:
			_air_vel = jump_velocity
			_air_height = 0.01
		_jump_pressed = false
		if not on_ground or _air_vel > 0.0:
			_air_vel -= gravity * gravity_scale * delta
			_air_height += _air_vel * delta
			if _air_height <= 0.0:
				_air_height = 0.0
				_air_vel = 0.0
		velocity.y = 0.0
		move_and_slide()
		global_position.y = _terrain_y() + FEET_CLEARANCE + _air_height
	else:
		_air_height = 0.0
		_air_vel = 0.0
		if not is_on_floor():
			velocity.y -= gravity * gravity_scale * delta
		elif _jump_pressed:
			velocity.y = jump_velocity
		else:
			velocity.y = 0.0
		_jump_pressed = false
		move_and_slide()

	if global_position.y < -80.0:
		global_position = Vector3(0.0, 10.0, 0.0)
		_air_height = 0.0
		_air_vel = 0.0
		velocity = Vector3.ZERO
		stick_to_terrain = true

	_update_animation(running)


func _process(_delta: float) -> void:
	# After AnimationPlayer pose update: keep head collapsed in first person.
	if _cam_mode == CamMode.FIRST:
		_set_first_person_head_hidden(true)


func _face_move_direction(world_dir: Vector3, delta: float) -> void:
	# Camera stays on the body; only the mesh turns to face movement (S → face the camera).
	var local_move := global_transform.basis.inverse() * world_dir
	local_move.y = 0.0
	if local_move.length_squared() < 0.0001:
		return
	local_move = local_move.normalized()
	# Mesh forward is body -Z when model.yaw = 0 (KenneyVisual already has yaw = PI).
	var target_yaw := atan2(-local_move.x, -local_move.z)
	_model_yaw = lerp_angle(_model_yaw, target_yaw, 1.0 - exp(-MODEL_TURN_SPEED * delta))
	model.rotation.y = _model_yaw


func _update_animation(running: bool) -> void:
	if _anim == null:
		return
	var horiz := Vector3(velocity.x, 0.0, velocity.z).length()
	var on_floor := _air_height <= 0.001
	if not on_floor and _current_anim == "jump" and _anim.is_playing():
		return
	var next := "idle"
	var speed_scale := 1.0
	if not on_floor:
		if _air_vel > 2.0 and _current_anim != "jump" and _anim.has_animation("jump"):
			next = "jump"
		elif _anim.has_animation("idle"):
			next = "idle"
	elif horiz > 0.25:
		next = "run"
		# Walk = slower run playback; sprint = full speed.
		if running and horiz > walk_speed * 0.85:
			speed_scale = 1.15
		else:
			speed_scale = 0.75
	_play_anim(next, speed_scale)


func _play_anim(anim_name: String, speed_scale: float = 1.0) -> void:
	if _anim == null or not _anim.has_animation(anim_name):
		return
	_anim.speed_scale = speed_scale
	if _current_anim == anim_name:
		return
	_current_anim = anim_name
	_anim.play(anim_name, 0.15)


func _load_kenney_character() -> void:
	for child in model.get_children():
		child.queue_free()
	_anim = null
	_visual = null
	_skeleton = null
	_head_bones.clear()

	# load() follows import remaps — required for exported PCK builds.
	var packed := load(character_path) as PackedScene
	if packed == null:
		push_warning("Kenney character missing: " + character_path)
		return
	var root := packed.instantiate()
	if root == null:
		return

	_apply_skin_texture(root)
	# FBX often comes in as Root.scale = 100; keep that and only scale the outer wrapper uniformly.
	var aabb := _combined_aabb(root)
	var native_h := maxf(aabb.size.y, 0.01)
	var s := character_height / native_h
	# Guard: scale must be uniform (same on X/Y/Z).
	var uniform := Vector3(s, s, s)

	_visual = Node3D.new()
	_visual.name = "KenneyVisual"
	_visual.rotation.y = PI
	_visual.scale = uniform
	_visual.position = Vector3(0.0, -aabb.position.y * s, 0.0)
	model.add_child(_visual)
	_visual.add_child(root)

	_skeleton = _find_skeleton(root)
	if _skeleton != null:
		for bone_name in ["Head", "Head_end", "Neck"]:
			var bi := _skeleton.find_bone(bone_name)
			if bi >= 0:
				_head_bones.append(bi)

	_anim = AnimationPlayer.new()
	_anim.name = "AnimationPlayer"
	root.add_child(_anim)
	var lib := AnimationLibrary.new()
	_anim.add_animation_library("", lib)

	_import_anim_clip(lib, "res://assets/kenney_characters/Animations/idle.fbx", "Root|Idle", "idle", true)
	_import_anim_clip(lib, "res://assets/kenney_characters/Animations/run.fbx", "Root|Run", "run", true)
	_import_anim_clip(lib, "res://assets/kenney_characters/Animations/jump.fbx", "Root|Jump", "jump", false)

	_play_anim("idle")


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _set_first_person_head_hidden(hidden: bool) -> void:
	if _skeleton == null:
		return
	for bi in _head_bones:
		var bone_name := String(_skeleton.get_bone_name(bi))
		if hidden:
			# Collapse head so the camera sits in the neck without seeing the face mesh.
			var s := Vector3(0.01, 0.01, 0.01) if bone_name != "Neck" else Vector3(0.2, 0.2, 0.2)
			_skeleton.set_bone_pose_scale(bi, s)
		else:
			_skeleton.set_bone_pose_scale(bi, Vector3.ONE)


func _import_anim_clip(lib: AnimationLibrary, res_path: String, src_name: String, dest_name: String, loop: bool) -> void:
	var packed := load(res_path) as PackedScene
	if packed == null:
		push_warning("Animation missing: " + res_path)
		return
	var scene := packed.instantiate()
	if scene == null:
		return
	var src_ap := _find_animation_player(scene)
	if src_ap == null or not src_ap.has_animation(src_name):
		# Some imports drop the Root| prefix.
		var fallback := ""
		if src_ap != null:
			for n in src_ap.get_animation_list():
				if String(n).ends_with("Idle") and dest_name == "idle":
					fallback = n
				elif String(n).ends_with("Run") and dest_name == "run":
					fallback = n
				elif String(n).ends_with("Jump") and dest_name == "jump":
					fallback = n
		if fallback == "":
			push_warning("Clip %s not found in %s" % [src_name, res_path])
			scene.free()
			return
		src_name = fallback
	var anim: Animation = src_ap.get_animation(src_name).duplicate(true)
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	lib.add_animation(dest_name, anim)
	scene.free()


func _apply_skin_texture(node: Node) -> void:
	_skin_tex = load(skin_path) as Texture2D
	if _skin_tex == null:
		return
	_apply_tex_recursive(node, _skin_tex)


func _apply_tex_recursive(node: Node, tex: Texture2D) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var base := mi.get_active_material(i)
				var mat: StandardMaterial3D
				if base is StandardMaterial3D:
					mat = (base as StandardMaterial3D).duplicate() as StandardMaterial3D
				else:
					mat = StandardMaterial3D.new()
				mat.albedo_texture = tex
				mat.albedo_color = Color(1, 1, 1)
				mat.roughness = 0.85
				mi.set_surface_override_material(i, mat)
	for child in node.get_children():
		_apply_tex_recursive(child, tex)


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _combined_aabb(node: Node) -> AABB:
	var boxes: Array[AABB] = []
	_collect_mesh_aabbs(node, Transform3D.IDENTITY, boxes)
	if boxes.is_empty():
		return AABB(Vector3(-0.4, 0.0, -0.2), Vector3(0.8, 1.8, 0.4))
	var result: AABB = boxes[0]
	for i in range(1, boxes.size()):
		result = result.merge(boxes[i])
	return result


func _collect_mesh_aabbs(node: Node, parent_xf: Transform3D, out: Array[AABB]) -> void:
	var xf := parent_xf
	if node is Node3D:
		xf = parent_xf * (node as Node3D).transform
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			out.append(xf * mi.mesh.get_aabb())
	for child in node.get_children():
		_collect_mesh_aabbs(child, xf, out)
