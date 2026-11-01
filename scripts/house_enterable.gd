extends Node3D
## Kenney exterior + interior. Enter/leave ONLY with E at either door (no walk-through).

var exterior: MeshInstance3D
var exterior_body: StaticBody3D
var interior: Node3D
var door_areas: Array[Area3D] = []
var door_blockers: Array[StaticBody3D] = []
var door_hints: Array[Label3D] = []

var inside: bool = false
var _near_door: int = -1 # 0 = front (-Z), 1 = back (+Z)
var outside_pos: Vector3 = Vector3.ZERO
var _room_size: Vector3 = Vector3.ONE
var _ground_y: float = 0.0
const DOOR_WIDTH := 1.5


func configure(
	ext_mesh: MeshInstance3D,
	ext_body: StaticBody3D,
	room_size: Vector3,
	ground_y: float
) -> void:
	exterior = ext_mesh
	exterior_body = ext_body
	_room_size = room_size
	_ground_y = ground_y

	_make_door(0, -1.0) # front (-Z)
	_make_door(1, 1.0) # back (+Z)

	interior = _make_interior(room_size)
	interior.visible = false
	_set_interior_colliders(false)
	add_child(interior)


func _make_door(index: int, z_sign: float) -> void:
	var door_local := Vector3(0.0, 1.1, z_sign * _room_size.z * 0.5)

	var area := Area3D.new()
	area.name = "DoorArea_%d" % index
	area.monitoring = true
	area.monitorable = false
	area.collision_layer = 0
	area.collision_mask = 2
	var door_col := CollisionShape3D.new()
	var door_shape := BoxShape3D.new()
	# Tall enough / deep enough to cover both outside and just inside the doorway.
	door_shape.size = Vector3(maxf(DOOR_WIDTH + 0.6, 2.0), 2.5, 3.2)
	door_col.shape = door_shape
	area.add_child(door_col)
	area.position = door_local
	add_child(area)
	area.body_entered.connect(_on_door_entered.bind(index))
	area.body_exited.connect(_on_door_exited.bind(index))
	door_areas.append(area)

	var blocker := StaticBody3D.new()
	blocker.name = "DoorBlocker_%d" % index
	blocker.collision_layer = 1
	blocker.position = door_local
	var blocker_col := CollisionShape3D.new()
	var blocker_shape := BoxShape3D.new()
	blocker_shape.size = Vector3(DOOR_WIDTH + 0.15, 2.3, 0.28)
	blocker_col.shape = blocker_shape
	blocker.add_child(blocker_col)
	add_child(blocker)
	door_blockers.append(blocker)

	var hint := Label3D.new()
	hint.text = "按 E 进屋"
	hint.font_size = 64
	hint.pixel_size = 0.012
	hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hint.position = door_local + Vector3(0.0, 1.35, 0.0)
	hint.visible = false
	add_child(hint)
	door_hints.append(hint)


func _make_interior(room_size: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Interior"
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.82, 0.78, 0.70)
	wall_mat.roughness = 0.9
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.45, 0.32, 0.20)
	floor_mat.roughness = 0.95
	var ceil_mat := StandardMaterial3D.new()
	ceil_mat.albedo_color = Color(0.9, 0.9, 0.88)
	ceil_mat.roughness = 1.0

	var inner := room_size * 0.86
	var wall_t := 0.22
	var h := maxf(inner.y, 2.8)
	var gap := DOOR_WIDTH
	var side_w := maxf((inner.x - gap) * 0.5, 0.4)

	_add_box_mesh(root, Vector3(0.0, 0.05, 0.0), Vector3(inner.x, 0.1, inner.z), floor_mat)
	_add_static_box(root, Vector3(0.0, 0.05, 0.0), Vector3(inner.x, 0.1, inner.z))
	_add_box_mesh(root, Vector3(0.0, h - 0.05, 0.0), Vector3(inner.x, 0.1, inner.z), ceil_mat)

	# Front / back walls with a doorway gap in the middle (exit via E at the gap).
	for z_sign in [-1.0, 1.0]:
		var z := z_sign * (inner.z * 0.5 - wall_t * 0.5)
		var left_x := -gap * 0.5 - side_w * 0.5
		var right_x := gap * 0.5 + side_w * 0.5
		_add_box_mesh(root, Vector3(left_x, h * 0.5, z), Vector3(side_w, h, wall_t), wall_mat)
		_add_static_box(root, Vector3(left_x, h * 0.5, z), Vector3(side_w, h, wall_t))
		_add_box_mesh(root, Vector3(right_x, h * 0.5, z), Vector3(side_w, h, wall_t), wall_mat)
		_add_static_box(root, Vector3(right_x, h * 0.5, z), Vector3(side_w, h, wall_t))
		# Lintels above the doorway so the gap is door-shaped.
		_add_box_mesh(root, Vector3(0.0, h * 0.5 + 1.05, z), Vector3(gap, maxf(h - 2.1, 0.4), wall_t), wall_mat)
		_add_static_box(root, Vector3(0.0, h * 0.5 + 1.05, z), Vector3(gap, maxf(h - 2.1, 0.4), wall_t))

	_add_box_mesh(root, Vector3(-inner.x * 0.5 + wall_t * 0.5, h * 0.5, 0.0), Vector3(wall_t, h, inner.z), wall_mat)
	_add_static_box(root, Vector3(-inner.x * 0.5 + wall_t * 0.5, h * 0.5, 0.0), Vector3(wall_t, h, inner.z))
	_add_box_mesh(root, Vector3(inner.x * 0.5 - wall_t * 0.5, h * 0.5, 0.0), Vector3(wall_t, h, inner.z), wall_mat)
	_add_static_box(root, Vector3(inner.x * 0.5 - wall_t * 0.5, h * 0.5, 0.0), Vector3(wall_t, h, inner.z))

	var light := OmniLight3D.new()
	light.light_energy = 1.4
	light.omni_range = maxf(inner.x, inner.z) * 1.2
	light.position = Vector3(0.0, h * 0.7, 0.0)
	root.add_child(light)
	return root


func _add_box_mesh(parent: Node, pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)


func _add_static_box(parent: Node, pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = pos
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)


func _set_interior_colliders(enabled: bool) -> void:
	if interior == null:
		return
	for child in interior.get_children():
		if child is StaticBody3D:
			(child as StaticBody3D).collision_layer = 1 if enabled else 0


func _set_door_blockers(enabled: bool) -> void:
	for blocker in door_blockers:
		if blocker == null:
			continue
		blocker.collision_layer = 1 if enabled else 0
		for child in blocker.get_children():
			if child is CollisionShape3D:
				(child as CollisionShape3D).disabled = not enabled


func _update_hints() -> void:
	for i in door_hints.size():
		var hint := door_hints[i]
		if hint == null:
			continue
		if _near_door != i:
			hint.visible = false
			continue
		hint.visible = true
		hint.text = "按 E 出门" if inside else "按 E 进屋"


func _on_door_entered(body: Node3D, index: int) -> void:
	if body is CharacterBody3D:
		_near_door = index
		_update_hints()


func _on_door_exited(body: Node3D, index: int) -> void:
	if body is CharacterBody3D and _near_door == index:
		_near_door = -1
		# Still overlapping the other door?
		for i in door_areas.size():
			if door_areas[i] == null:
				continue
			for b in door_areas[i].get_overlapping_bodies():
				if b is CharacterBody3D:
					_near_door = i
					break
			if _near_door >= 0:
				break
		_update_hints()


func _unhandled_input(event: InputEvent) -> void:
	if _near_door < 0:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		_toggle_enter()
		get_viewport().set_input_as_handled()


func _get_player() -> CharacterBody3D:
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	if player != null:
		return player
	if _near_door >= 0 and _near_door < door_areas.size() and door_areas[_near_door]:
		for body in door_areas[_near_door].get_overlapping_bodies():
			if body is CharacterBody3D:
				return body
	return null


func _door_z_sign(index: int) -> float:
	return -1.0 if index == 0 else 1.0


func _inside_spawn_for_door(index: int) -> Vector3:
	var z := _door_z_sign(index) * (_room_size.z * 0.5 - 1.35)
	var g := to_global(Vector3(0.0, 0.2, z))
	g.y = _ground_y + 0.2
	return g


func _outside_spawn_for_door(index: int) -> Vector3:
	var z := _door_z_sign(index) * (_room_size.z * 0.5 + 1.9)
	var g := to_global(Vector3(0.0, 0.2, z))
	g.y = _ground_y + 0.2
	return g


func _toggle_enter() -> void:
	var player := _get_player()
	if player == null:
		return
	if inside:
		_leave_house(player)
	else:
		_enter_house(player)


func _enter_house(player: CharacterBody3D) -> void:
	inside = true
	outside_pos = player.global_position
	var door_i := maxi(_near_door, 0)
	_apply_exterior_visible(false)
	_set_door_blockers(true)
	if interior:
		interior.visible = true
	_set_interior_colliders(true)
	if "stick_to_terrain" in player:
		player.stick_to_terrain = false
	player.global_position = _inside_spawn_for_door(door_i)
	player.velocity = Vector3.ZERO
	_near_door = door_i
	_update_hints()


func _leave_house(player: CharacterBody3D) -> void:
	inside = false
	_apply_exterior_visible(true)
	_set_door_blockers(true)
	if interior:
		interior.visible = false
	_set_interior_colliders(false)
	var door_i := maxi(_near_door, 0)
	if "stick_to_terrain" in player:
		player.stick_to_terrain = true
	player.global_position = _outside_spawn_for_door(door_i)
	player.velocity = Vector3.ZERO
	_near_door = door_i
	_update_hints()


func _apply_exterior_visible(show_ext: bool) -> void:
	if exterior:
		exterior.visible = show_ext
	if exterior_body:
		exterior_body.collision_layer = 1 if show_ext else 0
		for child in exterior_body.get_children():
			if child is CollisionShape3D:
				(child as CollisionShape3D).disabled = not show_ext
