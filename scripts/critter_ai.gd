extends CharacterBody3D
## Patrol AI with Kenney GLB clips. Feet snap to terrain from live mesh bounds.

enum Kind { ANIMAL, MONSTER }
enum State { WANDER, FLEE, CHASE, RETURN }

@export var kind: Kind = Kind.ANIMAL
@export var move_speed: float = 2.8
@export var flee_speed: float = 6.0
@export var chase_speed: float = 3.8
@export var wander_radius: float = 12.0
@export var detect_radius: float = 16.0
@export var flee_radius: float = 11.0
@export var lose_radius: float = 26.0
@export var hover_height: float = 0.0
@export var turn_speed: float = 12.0

var home: Vector3 = Vector3.ZERO
var _state: State = State.WANDER
var _retarget_in: float = 0.0
var _target: Vector3 = Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _visual: Node3D
var _anim: AnimationPlayer
var _current_anim: String = ""
var _player: Node3D
var _player_refresh: float = 0.0
var _facing_yaw: float = 0.0
var _move_dir: Vector3 = Vector3.FORWARD
var _mesh_instances: Array[MeshInstance3D] = []

const FEET_CLEARANCE := 0.03


func setup_scene(scene_root: Node3D, visual_scale: float, _y_off_unused: float, yaw: float) -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	# glTF assets face +Z; CharacterBody forward is -Z.
	_visual.rotation.y = PI
	_visual.scale = Vector3(visual_scale, visual_scale, visual_scale)
	# Feet are planted each physics frame from live AABB — keep visual origin at body origin.
	_visual.position = Vector3.ZERO
	add_child(_visual)
	_visual.add_child(scene_root)
	_facing_yaw = yaw
	rotation.y = yaw
	_cache_meshes(scene_root)
	_anim = _find_animation_player(scene_root)
	if _anim != null:
		_anim.active = true
		_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
		_loop_clip("idle")
		_loop_clip("walk")
		_loop_clip("run")
		_loop_clip("sprint")


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	motion_mode = MOTION_MODE_FLOATING
	floor_snap_length = 0.0
	process_mode = Node.PROCESS_MODE_INHERIT
	set_physics_process(true)
	set_process(true)
	_rng.randomize()
	if _flat(home).length_squared() < 0.01:
		home = global_position
	else:
		home.y = global_position.y
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_pick_wander_target()
	# Must play after entering the tree — setup runs before add_child.
	call_deferred("_kickstart_anim")


func _kickstart_anim() -> void:
	_current_anim = ""
	if _anim != null:
		_anim.active = true
		_play_anim("walk" if _anim.has_animation("walk") else "idle", 1.0)


func _physics_process(delta: float) -> void:
	_player_refresh -= delta
	if _player_refresh <= 0.0:
		_player_refresh = 0.5
		_player = get_tree().get_first_node_in_group("player") as Node3D

	_retarget_in -= delta
	_update_state()
	_move(delta)
	_keep_near_home()
	_stick_to_terrain()
	_face(delta)
	_update_animation()


func _update_state() -> void:
	var to_player := _player_vec()
	var dist := to_player.length() if _player != null else 1.0e9

	if kind == Kind.ANIMAL:
		if _player != null and dist < flee_radius:
			_state = State.FLEE
			var away := -to_player.normalized()
			_target = global_position + away * _rng.randf_range(8.0, 14.0)
			if _flat(_target - home).length() > wander_radius * 1.6:
				_target = home + away * wander_radius
			_retarget_in = 0.7
			return
		if _state == State.FLEE and dist > lose_radius:
			_state = State.RETURN
			_target = home
			_retarget_in = 1.0
			return
	else:
		if _player != null and dist < detect_radius:
			_state = State.CHASE
			_target = _player.global_position
			_retarget_in = 0.25
			return
		if _state == State.CHASE and dist > lose_radius:
			_state = State.RETURN
			_target = home
			_retarget_in = 1.0
			return

	if _state == State.RETURN:
		if _flat(global_position - home).length() < wander_radius * 0.45:
			_state = State.WANDER
			_pick_wander_target()
		elif _retarget_in <= 0.0:
			_target = home
			_retarget_in = 1.0
		return

	_state = State.WANDER
	if _retarget_in <= 0.0 or _flat(global_position - _target).length() < 1.0:
		_pick_wander_target()


func _pick_wander_target() -> void:
	_state = State.WANDER
	_retarget_in = _rng.randf_range(1.2, 2.6)
	var ang := _rng.randf_range(0.0, TAU)
	var dist := _rng.randf_range(wander_radius * 0.4, wander_radius)
	var candidate := home + Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)
	var forest := get_tree().get_first_node_in_group("forest_world")
	if forest != null and forest.has_method("is_blocked_for_critter"):
		var tries := 0
		while tries < 8 and bool(forest.call("is_blocked_for_critter", candidate, 2.0)):
			ang = _rng.randf_range(0.0, TAU)
			dist = _rng.randf_range(wander_radius * 0.25, wander_radius)
			candidate = home + Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)
			tries += 1
	elif forest != null and forest.has_method("_blocked"):
		var tries2 := 0
		while tries2 < 8 and bool(forest.call("_blocked", candidate, 2.0)):
			ang = _rng.randf_range(0.0, TAU)
			dist = _rng.randf_range(wander_radius * 0.25, wander_radius)
			candidate = home + Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)
			tries2 += 1
	_target = candidate


func _move(_delta: float) -> void:
	var speed := move_speed
	var desire := _flat(_target - global_position)
	match _state:
		State.FLEE:
			speed = flee_speed
		State.CHASE:
			speed = chase_speed
			if _player != null:
				desire = _flat(_player.global_position - global_position)
				if desire.length() < 1.5:
					desire = Vector3.ZERO
					speed = 0.0
		State.RETURN:
			speed = move_speed * 1.15
			desire = _flat(home - global_position)
		State.WANDER:
			speed = move_speed
			if desire.length_squared() < 0.25:
				_pick_wander_target()
				desire = _flat(_target - global_position)

	if desire.length_squared() > 0.0001:
		_move_dir = desire.normalized()
		velocity.x = _move_dir.x * speed
		velocity.z = _move_dir.z * speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	velocity.y = 0.0
	move_and_slide()


func _keep_near_home() -> void:
	var offset := _flat(global_position - home)
	var max_r := wander_radius * 1.75
	if offset.length() > max_r:
		var pulled := home + offset.normalized() * wander_radius
		global_position.x = pulled.x
		global_position.z = pulled.z
		_state = State.RETURN
		_target = home
		_retarget_in = 0.8


func _stick_to_terrain() -> void:
	var forest := get_tree().get_first_node_in_group("forest_world")
	var terrain_y := 0.0
	if forest != null and forest.has_method("get_terrain_height"):
		terrain_y = float(forest.call("get_terrain_height", global_position.x, global_position.z))
	# Feet offset in body space (stable — does not feedback on current body Y).
	var feet_local := _lowest_mesh_body_y()
	global_position.y = terrain_y + FEET_CLEARANCE + hover_height - feet_local


func _lowest_mesh_body_y() -> float:
	var lowest := 0.0
	var has := false
	var inv := global_transform.affine_inverse()
	for mi in _mesh_instances:
		if mi == null or mi.mesh == null:
			continue
		var local_xf := inv * mi.global_transform
		var aabb := local_xf * mi.mesh.get_aabb()
		if has:
			lowest = minf(lowest, aabb.position.y)
		else:
			lowest = aabb.position.y
			has = true
	return lowest if has else 0.0


func _face(delta: float) -> void:
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if horiz.length_squared() < 0.04:
		return
	var target_yaw := atan2(-horiz.x, -horiz.z)
	_facing_yaw = lerp_angle(_facing_yaw, target_yaw, 1.0 - exp(-turn_speed * delta))
	rotation.y = _facing_yaw


func _update_animation() -> void:
	if _anim == null:
		return
	if not _anim.is_playing() and _current_anim != "":
		# Recover if the player was stopped somehow (e.g. duplicated while stopped).
		_anim.play(_current_anim)
	var speed := Vector3(velocity.x, 0.0, velocity.z).length()
	var next := "idle"
	var scale := 1.0
	if speed > 0.2:
		if _state == State.FLEE or speed > move_speed * 1.35:
			if _anim.has_animation("run"):
				next = "run"
				scale = 1.15
			elif _anim.has_animation("sprint"):
				next = "sprint"
				scale = 1.1
			elif _anim.has_animation("walk"):
				next = "walk"
				scale = 1.55
		else:
			if _anim.has_animation("walk"):
				next = "walk"
				scale = clampf(speed / maxf(move_speed, 0.1), 0.9, 1.4)
			elif _anim.has_animation("run"):
				next = "run"
				scale = 0.85
	_play_anim(next, scale)


func _play_anim(anim_name: String, speed_scale: float = 1.0) -> void:
	if _anim == null or not _anim.has_animation(anim_name):
		return
	_anim.speed_scale = speed_scale
	if _current_anim == anim_name and _anim.is_playing():
		return
	_current_anim = anim_name
	_anim.play(anim_name, 0.1)


func _loop_clip(anim_name: String) -> void:
	if _anim == null or not _anim.has_animation(anim_name):
		return
	var clip := _anim.get_animation(anim_name)
	if clip != null:
		clip.loop_mode = Animation.LOOP_LINEAR


func _cache_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		_mesh_instances.append(node as MeshInstance3D)
	for child in node.get_children():
		_cache_meshes(child)


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _player_vec() -> Vector3:
	if _player == null:
		return Vector3.ZERO
	var v := _player.global_position - global_position
	v.y = 0.0
	return v


func _flat(v: Vector3) -> Vector3:
	v.y = 0.0
	return v
