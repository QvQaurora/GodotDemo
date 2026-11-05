extends CharacterBody3D
## Third-person Kenney Animated Character. Uniform scale only — no axis stretching.

@export var walk_speed: float = 5.5
@export var run_speed: float = 11.0
@export var jump_velocity: float = 8.8
@export var gravity_scale: float = 2.35
@export var look_sensitivity: float = 0.0025
@export var min_pitch: float = -1.2
@export var max_pitch: float = 0.55
@export var character_path: String = "res://assets/kenney_characters/characterMedium.fbx"
@export var skin_path: String = "res://assets/kenney_characters/Skins/skaterMaleA.png"
@export var character_height: float = 1.8

const _Catalog = preload("res://scripts/character_catalog.gd")
const _Builder = preload("res://scripts/kenney_character_builder.gd")
@export var attack_range: float = 2.2
@export var attack_radius: float = 1.05
@export var attack_damage: float = 1.0
@export var attack_cooldown: float = 0.45
@export var hp_max: float = 100.0

signal health_changed(hp: float, hp_max: float)

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var hp: float = 100.0
var _jump_pressed: bool = false
var _attack_pressed: bool = false
var _attack_t: float = -1.0
var _attack_hit_done: bool = false
var _attack_cd: float = 0.0
var _hurt_cd: float = 0.0
var _air_height: float = 0.0
var _air_vel: float = 0.0
var _dead: bool = false
var _death_t: float = -1.0
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
	hp = hp_max
	_load_kenney_character()
	_apply_camera_mode()
	if get_tree().paused:
		get_tree().paused = false
	# Save restore (if any) runs from GameWorld after forest height is ready.
	if not GameSave.pending_load:
		call_deferred("_snap_to_ground")
	if DisplayServer.window_is_focused():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		DisplayServer.window_set_ime_active(false)
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	call_deferred("_emit_health")


func take_damage(amount: float) -> void:
	if amount <= 0.0 or hp <= 0.0 or _dead:
		return
	if _hurt_cd > 0.0:
		return
	hp = maxf(hp - amount, 0.0)
	_hurt_cd = 0.35
	_emit_health()
	if hp <= 0.0:
		_begin_death()


func heal(amount: float) -> void:
	if amount <= 0.0 or _dead:
		return
	hp = minf(hp + amount, hp_max)
	_emit_health()


func _emit_health() -> void:
	health_changed.emit(hp, hp_max)


func is_dead() -> bool:
	return _dead


func _begin_death() -> void:
	if _dead:
		return
	_dead = true
	_death_t = 0.0
	_jump_pressed = false
	_attack_pressed = false
	_attack_t = -1.0
	velocity = Vector3.ZERO
	_air_height = 0.0
	_air_vel = 0.0
	# Prefer third person so the fall is visible.
	if _cam_mode == CamMode.FIRST:
		_cam_mode = CamMode.THIRD
		_apply_camera_mode()
	if _anim != null and _anim.has_animation("idle"):
		_current_anim = "idle"
		_anim.speed_scale = 0.35
		_anim.play("idle", 0.05)


func _update_death(delta: float) -> void:
	_death_t += delta
	velocity = Vector3.ZERO
	if stick_to_terrain:
		move_and_slide()
		global_position.y = _terrain_y() + FEET_CLEARANCE
	else:
		move_and_slide()
	# Fall backward onto the ground (pivot at feet). Slight lift avoids clipping.
	if model != null:
		var lean := clampf(_death_t / 0.55, 0.0, 1.0)
		lean = lean * lean * (3.0 - 2.0 * lean)
		model.rotation.x = lean * deg_to_rad(82.0)
		model.rotation.z = 0.0
		model.position.y = lean * 0.34
	if _death_t >= 1.75:
		_respawn_random()


func _respawn_random() -> void:
	var pos := _pick_respawn_position()
	_dead = false
	_death_t = -1.0
	hp = hp_max
	_hurt_cd = 1.0
	_emit_health()
	stick_to_terrain = true
	_air_height = 0.0
	_air_vel = 0.0
	velocity = Vector3.ZERO
	if model != null:
		model.rotation = Vector3(0.0, _model_yaw, 0.0)
		model.position.y = 0.0
	global_position = pos
	if _anim != null:
		_anim.speed_scale = 1.0
		_play_anim("idle", 1.0)
	# Nudge streamer to rebuild around the new spot.
	var forest := get_tree().get_first_node_in_group("forest_world")
	if forest != null and forest.has_method("refresh_world_stream"):
		forest.call("refresh_world_stream")


func _pick_respawn_position() -> Vector3:
	var forest := get_tree().get_first_node_in_group("forest_world")
	var half := 420.0
	if forest != null and "terrain_size" in forest:
		half = maxf(float(forest.get("terrain_size")) * 0.5 - 50.0, 80.0)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for _i in 48:
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		var candidate := Vector3(x, 0.0, z)
		if forest != null and forest.has_method("is_blocked_for_critter"):
			if bool(forest.call("is_blocked_for_critter", candidate, 3.5)):
				continue
		elif forest != null and forest.has_method("_blocked"):
			if bool(forest.call("_blocked", candidate, 3.5)):
				continue
		var y := 0.0
		if forest != null and forest.has_method("get_terrain_height"):
			y = float(forest.call("get_terrain_height", x, z))
		return Vector3(x, y + FEET_CLEARANCE, z)
	# Fallback near origin.
	var fy := _terrain_y()
	return Vector3(0.0, fy + FEET_CLEARANCE, 0.0)


func get_facing_yaw() -> float:
	## Camera/look yaw on the map (not mesh turn — idle strafe would point the wrong way).
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		return rotation.y
	fwd = fwd.normalized()
	# Match map: yaw 0 = -Z (north / up on map).
	return atan2(fwd.x, -fwd.z)


func get_save_data() -> Dictionary:
	return {
		"x": global_position.x,
		"z": global_position.z,
		"yaw": rotation.y,
		"pivot_x": pivot.rotation.x,
		"cam_mode": int(_cam_mode),
		"model_yaw": _model_yaw,
		"hp": hp,
		"hp_max": hp_max,
	}


func apply_save_data(data: Variant) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		_snap_to_ground()
		return
	var d := data as Dictionary
	var x := float(d.get("x", global_position.x))
	var z := float(d.get("z", global_position.z))
	rotation.y = float(d.get("yaw", rotation.y))
	pivot.rotation.x = clampf(float(d.get("pivot_x", pivot.rotation.x)), min_pitch, max_pitch)
	_model_yaw = float(d.get("model_yaw", 0.0))
	if model != null:
		model.rotation.y = _model_yaw
	var mode := int(d.get("cam_mode", CamMode.THIRD))
	_cam_mode = CamMode.FIRST if mode == CamMode.FIRST else CamMode.THIRD
	_apply_camera_mode()
	# Always restore outdoors on terrain — house interior state is not persisted.
	stick_to_terrain = true
	_air_height = 0.0
	_air_vel = 0.0
	velocity = Vector3.ZERO
	global_position = Vector3(x, 0.0, z)
	global_position.y = _support_y() + FEET_CLEARANCE
	hp_max = float(d.get("hp_max", hp_max))
	hp = clampf(float(d.get("hp", hp_max)), 0.0, hp_max)
	_emit_health()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _terrain_y() -> float:
	var forest := get_tree().get_first_node_in_group("forest_world")
	if forest != null and forest.has_method("get_terrain_height"):
		return float(forest.call("get_terrain_height", global_position.x, global_position.z))
	return 0.0


func _support_y() -> float:
	## Walk/jump support = terrain, or a prop roof/top under the feet (layer 1).
	## Without this, stick-to-terrain yanks Y through rocks/houses after a jump.
	var ty := _terrain_y()
	var space := get_world_3d().direct_space_state
	if space == null:
		return ty
	var x := global_position.x
	var z := global_position.z
	var from_y := maxf(global_position.y + 0.75, ty + 1.0)
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(x, from_y, z),
		Vector3(x, ty - 4.0, z)
	)
	q.collision_mask = 1
	q.collide_with_areas = false
	q.collide_with_bodies = true
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return ty
	var n: Vector3 = hit.get("normal", Vector3.UP)
	# Walls/side faces are not standable — keep terrain height.
	if n.y < 0.35:
		return ty
	return maxf(ty, float(hit["position"].y))


func _snap_to_ground() -> void:
	for _i in 40:
		var forest := get_tree().get_first_node_in_group("forest_world")
		if forest != null and forest.has_method("get_terrain_height"):
			_air_height = 0.0
			_air_vel = 0.0
			velocity = Vector3.ZERO
			global_position.y = _support_y() + FEET_CLEARANCE
			return
		await get_tree().process_frame


func _inventory_blocks_play() -> bool:
	var inv := get_tree().get_first_node_in_group("inventory_ui")
	if inv != null and inv.has_method("is_open") and bool(inv.call("is_open")):
		return true
	var map_ui := get_tree().get_first_node_in_group("world_map_ui")
	if map_ui != null and map_ui.has_method("is_open") and bool(map_ui.call("is_open")):
		return true
	return false


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
	if get_tree().paused or _inventory_blocks_play() or _dead:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := look_sensitivity * GameSettings.mouse_sensitivity
		rotate_y(-event.relative.x * sens)
		pivot.rotate_x(-event.relative.y * sens)
		pivot.rotation.x = clampf(pivot.rotation.x, min_pitch, max_pitch)
	elif event is InputEventKey and event.pressed and not event.echo:
		if GameSettings.matches_action("jump", event):
			_jump_pressed = true
		elif event.keycode == KEY_U:
			_cycle_camera_mode()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if DisplayServer.window_is_focused() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			DisplayServer.window_set_ime_active(false)
		else:
			_attack_pressed = true
			get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	_hurt_cd = maxf(_hurt_cd - delta, 0.0)
	if _dead:
		_update_death(delta)
		return
	if _inventory_blocks_play():
		_attack_pressed = false
		velocity = Vector3.ZERO
		if stick_to_terrain:
			move_and_slide()
			global_position.y = _support_y() + FEET_CLEARANCE + _air_height
		_update_animation(false)
		return

	if _attack_pressed and _attack_t < 0.0 and _attack_cd <= 0.0:
		_begin_attack()
	_attack_pressed = false
	_update_attack(delta)

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

	var running := GameSettings.action_held("sprint")
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
		# Y is scripted (terrain + prop tops). Integrate jump in world space so
		# landing on rocks/roofs is not yanked down to bare terrain through the mesh.
		velocity.y = 0.0
		var support := _support_y()
		var grounded := _air_vel <= 0.0 and global_position.y <= support + FEET_CLEARANCE + 0.08
		if _jump_pressed and grounded:
			_air_vel = jump_velocity
		_jump_pressed = false
		move_and_slide()
		support = _support_y()
		if _air_vel != 0.0 or global_position.y > support + FEET_CLEARANCE + 0.08:
			_air_vel -= gravity * gravity_scale * delta
			global_position.y += _air_vel * delta
			if global_position.y <= support + FEET_CLEARANCE and _air_vel <= 0.0:
				global_position.y = support + FEET_CLEARANCE
				_air_vel = 0.0
		else:
			global_position.y = support + FEET_CLEARANCE
			_air_vel = 0.0
		_air_height = maxf(0.0, global_position.y - support - FEET_CLEARANCE)
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
	if _attack_t >= 0.0:
		_apply_attack_arm_pose()


func _begin_attack() -> void:
	## Keep current facing — do not snap the mesh toward the camera.
	_attack_t = 0.0
	_attack_hit_done = false
	_attack_cd = attack_cooldown


func _update_attack(delta: float) -> void:
	if _attack_t < 0.0:
		return
	_attack_t += delta
	# Hit frame near the punch apex.
	if not _attack_hit_done and _attack_t >= 0.14:
		_attack_hit_done = true
		_deal_attack_hits()
	if _attack_t >= 0.36:
		_attack_t = -1.0


func _attack_forward() -> Vector3:
	## Prefer the mesh facing (third person can strafe while looking elsewhere).
	var forward := Vector3.FORWARD
	if model != null:
		forward = -model.global_transform.basis.z
	else:
		forward = -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return Vector3.FORWARD
	return forward.normalized()


func _deal_attack_hits() -> void:
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var sphere := SphereShape3D.new()
	sphere.radius = attack_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.collision_mask = 4 # critter layer
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var forward := _attack_forward()
	var origin := global_position + Vector3(0.0, 1.05, 0.0) + forward * (attack_range * 0.55)
	query.transform = Transform3D(Basis(), origin)
	var hits := space.intersect_shape(query, 12)
	var struck: Dictionary = {}
	for hit in hits:
		var col: Object = hit.get("collider")
		if col == null or not is_instance_valid(col):
			continue
		var id := col.get_instance_id()
		if struck.has(id):
			continue
		struck[id] = true
		if col.has_method("apply_player_hit"):
			col.call("apply_player_hit", global_position, attack_damage)


func _apply_attack_arm_pose() -> void:
	## Additive offsets on top of idle/run — only the right arm, no torso overwrite.
	if _skeleton == null or _attack_t < 0.0:
		return
	var u := clampf(_attack_t / 0.36, 0.0, 1.0)
	# Envelope: pull back → extend → recover.
	var pull := 0.0
	var extend := 0.0
	if u < 0.28:
		pull = u / 0.28
	elif u < 0.55:
		pull = 1.0 - ((u - 0.28) / 0.27)
		extend = (u - 0.28) / 0.27
	else:
		extend = 1.0 - ((u - 0.55) / 0.45)
	pull = clampf(pull, 0.0, 1.0)
	extend = clampf(extend, 0.0, 1.0)
	# Local bone deltas (Kenney Mixamo-style right arm).
	_add_bone_euler("RightArm", Vector3(
		deg_to_rad(-55.0 * extend + 25.0 * pull),
		deg_to_rad(-20.0 * extend),
		deg_to_rad(12.0 * pull - 8.0 * extend)
	))
	_add_bone_euler("RightForeArm", Vector3(
		deg_to_rad(-70.0 * pull + 35.0 * extend),
		0.0,
		deg_to_rad(8.0 * extend)
	))
	_add_bone_euler("RightHand", Vector3(deg_to_rad(-15.0 * extend), 0.0, 0.0))


func _add_bone_euler(bone_name: String, euler: Vector3) -> void:
	if _skeleton == null:
		return
	var bi := _skeleton.find_bone(bone_name)
	if bi < 0:
		return
	var cur := _skeleton.get_bone_pose_rotation(bi)
	_skeleton.set_bone_pose_rotation(bi, cur * Quaternion.from_euler(euler))


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
	_anim = null
	_visual = null
	_skeleton = null
	_head_bones.clear()
	_current_anim = ""

	# Prefer appearance chosen in the main-menu 玩家 panel.
	var body_id := _Catalog.resolve_existing_body_id(GameSettings.player_body_id)
	var outfit_id := _Catalog.resolve_existing_outfit_id(GameSettings.player_outfit_id)
	var gear := _Catalog.sanitize_gear(GameSettings.player_gear)
	character_path = _Catalog.body_path(body_id)
	skin_path = _Catalog.skin_path(outfit_id)
	character_height = _Catalog.body_height(body_id)

	var built := _Builder.spawn(model, body_id, outfit_id, PI, gear)
	if built.is_empty():
		return
	_visual = built.get("visual") as Node3D
	_anim = built.get("anim") as AnimationPlayer
	_skeleton = built.get("skeleton") as Skeleton3D
	if _skeleton != null:
		for bone_name in ["Head", "Head_end", "Neck"]:
			var bi := _skeleton.find_bone(bone_name)
			if bi >= 0:
				_head_bones.append(bi)
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
