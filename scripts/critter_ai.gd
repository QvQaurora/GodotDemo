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
var _ai_budget: float = 0.0
var _far_lod: bool = false
var _hp: float = 3.0
var _hp_max: float = 3.0
var _hit_stun: float = 0.0
var _knock_vel: Vector3 = Vector3.ZERO
var _hp_root: Node3D
var _hp_fill: MeshInstance3D
var _hp_name: Label3D
var _hp_bar_half_w: float = 0.44
var _display_name: String = ""
var _melee_cd: float = 0.0
var _attack_damage: float = 1.0
var _attack_interval: float = 1.0

const FEET_CLEARANCE := 0.03
## Beyond this, AI ticks less often (still visible; streamer despawns even farther).
const FAR_AI_DIST := 42.0
const FAR_AI_INTERVAL := 0.14
const HP_BAR_VISIBLE_DIST := 48.0


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
	add_to_group("critter")
	var species := ""
	if has_meta("spawn_name"):
		species = str(get_meta("spawn_name"))
	_hp_max = _hp_for_species(species)
	_hp = _hp_max
	var atk := _attack_for_species(species)
	_attack_damage = float(atk.get("damage", 1.0))
	_attack_interval = float(atk.get("interval", 1.0))
	_rng.randomize()
	if _flat(home).length_squared() < 0.01:
		home = global_position
	else:
		home.y = global_position.y
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_pick_wander_target()
	# Must play after entering the tree — setup runs before add_child.
	call_deferred("_kickstart_anim")
	call_deferred("_setup_health_bar")


func apply_player_hit(from_pos: Vector3, damage: float) -> void:
	## Melee hit from the player (left click).
	var away := _flat(global_position - from_pos)
	if away.length_squared() < 0.0001:
		away = -_move_dir if _move_dir.length_squared() > 0.0001 else Vector3.FORWARD
	else:
		away = away.normalized()
	_knock_vel = away * (7.5 if kind == Kind.ANIMAL else 5.5)
	_hit_stun = 0.35
	_hp = maxf(_hp - maxf(damage, 0.1), 0.0)
	_refresh_health_bar()
	if kind == Kind.ANIMAL:
		_state = State.FLEE
		_target = global_position + away * _rng.randf_range(10.0, 16.0)
		_retarget_in = 0.8
	else:
		_state = State.CHASE
		_retarget_in = 0.15
	if _hp <= 0.0:
		_die_from_player()


func _die_from_player() -> void:
	var sid := str(get_meta("spawn_id", ""))
	var streamer := get_tree().get_first_node_in_group("world_streamer")
	if streamer != null and sid != "" and streamer.has_method("notify_actor_killed"):
		streamer.call("notify_actor_killed", sid)
	else:
		queue_free()


func _kickstart_anim() -> void:
	_current_anim = ""
	if _anim != null:
		_anim.active = true
		_play_anim("walk" if _anim.has_animation("walk") else "idle", 1.0)


func _setup_health_bar() -> void:
	if _hp_root != null and is_instance_valid(_hp_root):
		return
	if _display_name == "" and has_meta("display_name"):
		_display_name = str(get_meta("display_name"))
	if _display_name == "" and has_meta("spawn_name"):
		_display_name = _pretty_critter_name(str(get_meta("spawn_name")))
	if _display_name == "":
		_display_name = "动物" if kind == Kind.ANIMAL else "怪物"

	var top_y := _body_top_y()
	_hp_root = Node3D.new()
	_hp_root.name = "HealthBar"
	# Keep the whole stack well above the head so text never covers the body.
	_hp_root.position = Vector3(0.0, top_y + 0.55, 0.0)
	# Face the camera ourselves so fill stays inside the bg from every angle.
	add_child(_hp_root)

	_hp_name = Label3D.new()
	_hp_name.name = "HpName"
	_hp_name.text = _display_name
	_hp_name.font_size = 40
	_hp_name.pixel_size = 0.011
	_hp_name.modulate = Color(1, 1, 1, 0.96)
	_hp_name.outline_modulate = Color(0, 0, 0, 0.85)
	_hp_name.outline_size = 8
	_hp_name.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	_hp_name.vertical_alignment = VerticalAlignment.VERTICAL_ALIGNMENT_BOTTOM
	_hp_name.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_hp_name.no_depth_test = true
	# Name above the bar.
	_hp_name.position = Vector3(0.0, 0.20, 0.004)
	_hp_root.add_child(_hp_name)

	var bg := MeshInstance3D.new()
	bg.name = "HpBg"
	bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bg.mesh = _make_bar_quad(0.92, 0.14)
	bg.material_override = _make_bar_mat(Color(0.05, 0.05, 0.07, 0.9), 8)
	bg.position = Vector3(0.0, 0.0, -0.002)
	_hp_root.add_child(bg)

	_hp_fill = MeshInstance3D.new()
	_hp_fill.name = "HpFill"
	_hp_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hp_fill.mesh = _make_bar_quad(0.86, 0.09)
	_hp_fill.material_override = _make_bar_mat(Color(0.92, 0.18, 0.16, 0.98), 9)
	_hp_fill.position = Vector3(0.0, 0.0, 0.002)
	_hp_root.add_child(_hp_fill)
	_hp_bar_half_w = 0.43

	_refresh_health_bar()
	_face_health_bar_to_camera()


func _species_key(raw: String) -> String:
	return raw.get_file().get_basename().to_lower()


func _hp_for_species(raw: String) -> float:
	## Per-species hit points (player melee deals ~1 per punch).
	var key := _species_key(raw)
	const HP := {
		# Fragile / tiny
		"animal-bee": 1.0,
		"animal-chick": 1.0,
		"animal-bunny": 2.0,
		"animal-crab": 2.0,
		# Common medium
		"animal-fox": 3.0,
		"animal-cat": 3.0,
		"animal-dog": 3.0,
		"animal-parrot": 2.0,
		"animal-penguin": 3.0,
		"animal-koala": 3.0,
		"animal-monkey": 3.0,
		# Tough herbivores
		"animal-deer": 4.0,
		"animal-pig": 4.0,
		"animal-beaver": 4.0,
		"animal-cow": 5.0,
		"animal-hog": 5.0,
		"animal-panda": 5.0,
		# Predators
		"animal-tiger": 6.0,
		"animal-lion": 6.0,
		"animal-polar": 7.0,
		# Monsters
		"character-ghost": 3.0,
		"character-skeleton": 4.0,
		"character-vampire": 5.0,
		"character-zombie": 6.0,
	}
	if HP.has(key):
		return float(HP[key])
	return 3.0 if kind == Kind.ANIMAL else 4.0


func _pretty_critter_name(raw: String) -> String:
	var key := _species_key(raw)
	const CN := {
		"animal-deer": "鹿",
		"animal-fox": "狐狸",
		"animal-bunny": "兔子",
		"animal-hog": "野猪",
		"animal-bee": "蜜蜂",
		"animal-chick": "小鸡",
		"animal-cat": "猫",
		"animal-dog": "狗",
		"animal-cow": "牛",
		"animal-pig": "猪",
		"animal-parrot": "鹦鹉",
		"animal-beaver": "海狸",
		"animal-penguin": "企鹅",
		"animal-polar": "北极熊",
		"animal-tiger": "老虎",
		"animal-lion": "狮子",
		"animal-monkey": "猴子",
		"animal-panda": "熊猫",
		"animal-koala": "考拉",
		"animal-crab": "螃蟹",
		"character-zombie": "僵尸",
		"character-skeleton": "骷髅",
		"character-vampire": "吸血鬼",
		"character-ghost": "幽灵",
	}
	if CN.has(key):
		return str(CN[key])
	if key.begins_with("animal-"):
		return "动物"
	if key.begins_with("character-"):
		return "怪物"
	return "生物"


func _make_bar_quad(w: float, h: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	return q


func _make_bar_mat(color: Color, priority: int = 8) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	mat.no_depth_test = true
	mat.render_priority = priority
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _face_health_bar_to_camera() -> void:
	if _hp_root == null or not is_instance_valid(_hp_root):
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var from := _hp_root.global_position
	var to := cam.global_position
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	if flat.length_squared() < 0.0001:
		return
	# Quad faces +Z; point +Z toward camera on the XZ plane.
	var yaw := atan2(flat.x, flat.z)
	# Cancel parent body yaw so the bar stays screen-aligned.
	_hp_root.rotation = Vector3(0.0, yaw - global_rotation.y, 0.0)


func _body_top_y() -> float:
	var top := 1.2
	var has := false
	var inv := global_transform.affine_inverse()
	for mi in _mesh_instances:
		if mi == null or mi.mesh == null:
			continue
		var local_xf := inv * mi.global_transform
		var aabb := local_xf * mi.mesh.get_aabb()
		var y := aabb.position.y + aabb.size.y
		if has:
			top = maxf(top, y)
		else:
			top = y
			has = true
	return top if has else 1.2


func _refresh_health_bar() -> void:
	if _hp_fill == null or not is_instance_valid(_hp_fill):
		return
	var ratio := clampf(_hp / maxf(_hp_max, 0.001), 0.0, 1.0)
	_hp_fill.scale = Vector3(maxf(ratio, 0.001), 1.0, 1.0)
	# Left-anchored inside the dark tube (same local space as bg — no per-mesh billboard).
	_hp_fill.position = Vector3(-_hp_bar_half_w * (1.0 - ratio), 0.0, 0.002)
	var mat := _hp_fill.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = Color(0.92, 0.18, 0.16, 0.98)


func _update_health_bar_visibility() -> void:
	if _hp_root == null or not is_instance_valid(_hp_root):
		return
	var show := true
	if _player != null:
		show = _player.global_position.distance_to(global_position) <= HP_BAR_VISIBLE_DIST
	_hp_root.visible = show and _hp > 0.0
	if _hp_root.visible:
		_face_health_bar_to_camera()


func _process(_delta: float) -> void:
	if _hp_root != null and _hp_root.visible:
		_face_health_bar_to_camera()


func _physics_process(delta: float) -> void:
	_player_refresh -= delta
	_melee_cd = maxf(_melee_cd - delta, 0.0)
	if _player_refresh <= 0.0:
		_player_refresh = 0.65
		_player = get_tree().get_first_node_in_group("player") as Node3D
		_update_health_bar_visibility()

	if _hit_stun > 0.0:
		_hit_stun -= delta
		velocity.x = _knock_vel.x
		velocity.z = _knock_vel.z
		velocity.y = 0.0
		_knock_vel = _knock_vel.lerp(Vector3.ZERO, 1.0 - exp(-10.0 * delta))
		move_and_slide()
		_stick_to_terrain()
		_face(delta)
		_update_animation()
		return

	# No player yet → keep full tick (don't treat as "very close" with dist 0).
	var dist_player := _player.global_position.distance_to(global_position) if _player != null else FAR_AI_DIST + 1.0
	_far_lod = _player != null and dist_player > FAR_AI_DIST
	if _far_lod:
		# Keep feet planted every frame so they don't float; stagger decision/move.
		_stick_to_terrain()
		_ai_budget += delta
		if _ai_budget < FAR_AI_INTERVAL:
			return
		_ai_budget = 0.0
		_retarget_in -= FAR_AI_INTERVAL
		_update_state()
		_move(FAR_AI_INTERVAL)
		_keep_near_home()
		_face(FAR_AI_INTERVAL)
		_update_animation()
		return

	_retarget_in -= delta
	_update_state()
	_move(delta)
	_try_melee_player(dist_player)
	_keep_near_home()
	_stick_to_terrain()
	_face(delta)
	_update_animation()


func _attack_for_species(raw: String) -> Dictionary:
	## Monster contact damage + seconds between hits.
	var key := _species_key(raw)
	match key:
		"character-ghost":
			return {"damage": 6.0, "interval": 0.55} # 快、伤害低
		"character-skeleton":
			return {"damage": 10.0, "interval": 0.85}
		"character-vampire":
			return {"damage": 14.0, "interval": 0.70}
		"character-zombie":
			return {"damage": 18.0, "interval": 1.25} # 慢、伤害高
		_:
			return {"damage": 8.0, "interval": 1.0}


func _try_melee_player(dist_player: float) -> void:
	if kind != Kind.MONSTER or _state != State.CHASE:
		return
	if _player == null or dist_player > 1.7 or _melee_cd > 0.0:
		return
	if _player.has_method("take_damage"):
		_player.call("take_damage", _attack_damage)
		_melee_cd = _attack_interval


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
