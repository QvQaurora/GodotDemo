extends Node3D
## Loads a Kenney/Blender GLB map: bake scales, trimesh collision, player spawn.

const MAIN_MENU := "res://scenes/main_menu.tscn"

@export var map_id: String = ""
@export var map_title: String = "未命名场景"
@export var map_blurb: String = ""
@export var world_glb: PackedScene
@export var player_scene: PackedScene
@export var pause_menu_scene: PackedScene

var world_ready: bool = false
var _spawn: Vector3 = Vector3(0.0, 2.0, 8.0)


func _ready() -> void:
	add_to_group("forest_world")
	world_ready = false
	call_deferred("_boot")


func get_terrain_height(x: float, z: float) -> float:
	var hit := _raycast_ground_y(x, z)
	if not is_nan(hit):
		return hit
	return 0.0


func _boot() -> void:
	_ensure_environment()
	_instance_world()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_place_player()
	_ensure_pause_menu()
	_build_title_hud()
	world_ready = true
	print("Kenney map ready: ", map_id)


func _ensure_environment() -> void:
	if has_node("WorldEnvironment"):
		return
	var sky := _theme_sky()
	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = sky["bg"]
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = sky["ambient"]
	environment.ambient_light_energy = float(sky["ambient_e"])
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = bool(sky.get("fog", false))
	if environment.fog_enabled:
		environment.fog_light_color = sky["bg"]
		environment.fog_density = float(sky.get("fog_d", 0.0015))
	env.environment = environment
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-42.0, 35.0, 0.0)
	sun.light_color = sky["sun"]
	sun.light_energy = float(sky["sun_e"])
	sun.shadow_enabled = true
	add_child(sun)


func _theme_sky() -> Dictionary:
	## Distinct mood per map — not the same blue sky everywhere.
	var table := {
		"abandoned_supermarket": {"bg": Color(0.55, 0.58, 0.62), "ambient": Color(0.7, 0.7, 0.72), "ambient_e": 0.85, "sun": Color(1, 0.98, 0.92), "sun_e": 1.1},
		"underground_parking": {"bg": Color(0.08, 0.08, 0.1), "ambient": Color(0.35, 0.38, 0.4), "ambient_e": 0.55, "sun": Color(0.7, 0.75, 0.85), "sun_e": 0.55, "fog": true, "fog_d": 0.004},
		"abandoned_cruise": {"bg": Color(0.45, 0.7, 0.88), "ambient": Color(0.65, 0.75, 0.85), "ambient_e": 0.8, "sun": Color(1, 0.95, 0.8), "sun_e": 1.35},
		"nuclear_plant": {"bg": Color(0.4, 0.48, 0.32), "ambient": Color(0.5, 0.55, 0.4), "ambient_e": 0.7, "sun": Color(0.95, 1.0, 0.75), "sun_e": 1.1, "fog": true, "fog_d": 0.0012},
		"museum": {"bg": Color(0.62, 0.6, 0.58), "ambient": Color(0.75, 0.72, 0.68), "ambient_e": 0.9, "sun": Color(1, 0.98, 0.95), "sun_e": 1.0},
		"casino_ruins": {"bg": Color(0.12, 0.05, 0.18), "ambient": Color(0.45, 0.2, 0.4), "ambient_e": 0.65, "sun": Color(1.0, 0.45, 0.7), "sun_e": 0.85},
		"egypt_pyramid": {"bg": Color(0.78, 0.62, 0.35), "ambient": Color(0.85, 0.7, 0.45), "ambient_e": 0.85, "sun": Color(1.0, 0.9, 0.55), "sun_e": 1.5},
		"japanese_shrine": {"bg": Color(0.55, 0.72, 0.82), "ambient": Color(0.65, 0.75, 0.7), "ambient_e": 0.8, "sun": Color(1, 0.95, 0.9), "sun_e": 1.2},
		"pirate_island": {"bg": Color(0.4, 0.72, 0.9), "ambient": Color(0.7, 0.8, 0.85), "ambient_e": 0.85, "sun": Color(1, 0.95, 0.75), "sun_e": 1.45},
		"space_station": {"bg": Color(0.02, 0.02, 0.05), "ambient": Color(0.25, 0.3, 0.45), "ambient_e": 0.5, "sun": Color(0.7, 0.85, 1.0), "sun_e": 0.9},
		"cyberpunk_district": {"bg": Color(0.08, 0.1, 0.2), "ambient": Color(0.25, 0.35, 0.55), "ambient_e": 0.6, "sun": Color(0.6, 0.9, 1.0), "sun_e": 0.8, "fog": true, "fog_d": 0.002},
		"bio_lab": {"bg": Color(0.18, 0.32, 0.24), "ambient": Color(0.35, 0.55, 0.4), "ambient_e": 0.7, "sun": Color(0.7, 1.0, 0.75), "sun_e": 1.0},
		"time_rift": {"bg": Color(0.28, 0.12, 0.4), "ambient": Color(0.45, 0.25, 0.55), "ambient_e": 0.7, "sun": Color(0.9, 0.5, 1.0), "sun_e": 1.1},
		"abandoned_hospital": {"bg": Color(0.45, 0.48, 0.5), "ambient": Color(0.6, 0.62, 0.65), "ambient_e": 0.7, "sun": Color(0.9, 0.92, 1.0), "sun_e": 0.85, "fog": true, "fog_d": 0.0025},
		"haunted_amusement": {"bg": Color(0.08, 0.06, 0.1), "ambient": Color(0.3, 0.22, 0.35), "ambient_e": 0.55, "sun": Color(0.7, 0.5, 0.85), "sun_e": 0.7, "fog": true, "fog_d": 0.003},
		"deep_sea_wreck": {"bg": Color(0.02, 0.08, 0.14), "ambient": Color(0.1, 0.3, 0.4), "ambient_e": 0.55, "sun": Color(0.3, 0.7, 0.9), "sun_e": 0.6, "fog": true, "fog_d": 0.005},
		"jungle_ruins": {"bg": Color(0.3, 0.5, 0.55), "ambient": Color(0.4, 0.55, 0.4), "ambient_e": 0.75, "sun": Color(1.0, 0.95, 0.7), "sun_e": 1.25, "fog": true, "fog_d": 0.0015},
		"snow_camp": {"bg": Color(0.72, 0.82, 0.92), "ambient": Color(0.85, 0.9, 0.95), "ambient_e": 0.95, "sun": Color(1, 1, 1), "sun_e": 1.35},
		"volcano_mine": {"bg": Color(0.28, 0.1, 0.06), "ambient": Color(0.5, 0.25, 0.15), "ambient_e": 0.65, "sun": Color(1.0, 0.55, 0.25), "sun_e": 1.2, "fog": true, "fog_d": 0.002},
		"spirit_forest": {"bg": Color(0.12, 0.2, 0.28), "ambient": Color(0.25, 0.45, 0.4), "ambient_e": 0.7, "sun": Color(0.55, 1.0, 0.85), "sun_e": 1.0, "fog": true, "fog_d": 0.0018},
		"inverted_world": {"bg": Color(0.45, 0.25, 0.6), "ambient": Color(0.55, 0.35, 0.65), "ambient_e": 0.75, "sun": Color(0.85, 0.6, 1.0), "sun_e": 1.1},
		"mirror_level": {"bg": Color(0.55, 0.6, 0.68), "ambient": Color(0.7, 0.75, 0.8), "ambient_e": 0.85, "sun": Color(1, 1, 1), "sun_e": 1.15},
		"maze_casino": {"bg": Color(0.1, 0.04, 0.12), "ambient": Color(0.4, 0.15, 0.3), "ambient_e": 0.6, "sun": Color(1.0, 0.4, 0.65), "sun_e": 0.8},
		"ghost_train": {"bg": Color(0.15, 0.15, 0.18), "ambient": Color(0.35, 0.35, 0.4), "ambient_e": 0.55, "sun": Color(0.75, 0.8, 0.95), "sun_e": 0.75, "fog": true, "fog_d": 0.003},
		"gamble_arena": {"bg": Color(0.5, 0.38, 0.25), "ambient": Color(0.65, 0.5, 0.35), "ambient_e": 0.8, "sun": Color(1.0, 0.85, 0.55), "sun_e": 1.35},
	}
	if table.has(map_id):
		return table[map_id]
	return {"bg": Color(0.45, 0.62, 0.82), "ambient": Color(0.55, 0.58, 0.62), "ambient_e": 0.75, "sun": Color(1, 0.97, 0.9), "sun_e": 1.25}


func _world_path() -> String:
	if world_glb != null and world_glb.resource_path != "":
		return world_glb.resource_path
	return "res://assets/blender_maps/%s/world.glb" % map_id


func _instance_world() -> void:
	if has_node("BlenderWorld"):
		return
	var path := _world_path()
	var packed: PackedScene = world_glb
	if packed == null and ResourceLoader.exists(path):
		packed = load(path) as PackedScene
	if packed == null:
		push_warning("Kenney map GLB missing: " + path)
		_make_fallback_ground()
		return
	var root := packed.instantiate()
	root.name = "BlenderWorld"
	add_child(root)
	_bake_mesh_scales(root)
	_retint_materials(root)
	_add_collision(root)
	_find_spawn(root)
	print("Kenney map instanced: ", path, " children=", root.get_child_count())


func _make_fallback_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "FallbackGround"
	body.collision_layer = 8
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	mi.mesh = plane
	body.add_child(mi)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 0.2, 80)
	col.shape = box
	col.position.y = -0.1
	body.add_child(col)
	add_child(body)


func _bake_mesh_scales(root: Node) -> void:
	var baked_n := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if mi.scale.is_equal_approx(Vector3.ONE):
			continue
		var scl := mi.scale
		var src := mi.mesh
		var out := ArrayMesh.new()
		for si in src.get_surface_count():
			var mdt := MeshDataTool.new()
			if mdt.create_from_surface(src, si) != OK:
				continue
			for vi in mdt.get_vertex_count():
				var v := mdt.get_vertex(vi)
				mdt.set_vertex(vi, Vector3(v.x * scl.x, v.y * scl.y, v.z * scl.z))
				if mdt.get_format() & Mesh.ARRAY_FORMAT_NORMAL:
					var nrm := mdt.get_vertex_normal(vi)
					if not is_equal_approx(scl.x, scl.y) or not is_equal_approx(scl.y, scl.z):
						nrm = Vector3(nrm.x / scl.x, nrm.y / scl.y, nrm.z / scl.z).normalized()
						mdt.set_vertex_normal(vi, nrm)
			mdt.commit_to_surface(out)
			var mat := src.surface_get_material(si)
			if mat == null:
				mat = mi.get_active_material(si)
			if mat != null:
				out.surface_set_material(out.get_surface_count() - 1, mat)
		mi.mesh = out
		mi.scale = Vector3.ONE
		baked_n += 1
	if baked_n > 0:
		print("Kenney map scales baked: ", baked_n)


func _retint_materials(root: Node) -> void:
	var seen: Dictionary = {}
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(si)
			if mat == null or not (mat is BaseMaterial3D):
				continue
			var id := mat.get_instance_id()
			if seen.has(id):
				continue
			seen[id] = true
			var bm := mat as BaseMaterial3D
			bm.metallic = 0.0
			if bm.roughness < 0.2:
				bm.roughness = 0.85
			var n := String(bm.resource_name).to_lower()
			if n.find("leaf") >= 0 or n.find("grass") >= 0 or n.find("hedge") >= 0:
				bm.albedo_color = Color(0.20, 0.48, 0.20) if n.find("dark") < 0 else Color(0.13, 0.34, 0.15)
			elif n.find("wood") >= 0 or n.find("bark") >= 0:
				bm.albedo_color = Color(0.48, 0.32, 0.18) if n.find("dark") < 0 else Color(0.30, 0.18, 0.10)


func _add_collision(root: Node) -> void:
	var added := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var n := String(mi.name).to_lower()
		if n.find("water") >= 0 or n.find("pond") >= 0 or n.find("river") >= 0:
			continue
		if mi.get_node_or_null("ColBody") != null:
			continue
		var tri := mi.mesh.create_trimesh_shape()
		if tri == null:
			continue
		if tri is ConcavePolygonShape3D:
			(tri as ConcavePolygonShape3D).backface_collision = true
		var is_terrain := n.find("terrain") >= 0 or n.find("ground") >= 0
		var body := StaticBody3D.new()
		body.name = "ColBody"
		body.collision_layer = 8 if is_terrain else 1
		body.collision_mask = 0
		var col := CollisionShape3D.new()
		col.shape = tri
		body.add_child(col)
		mi.add_child(body)
		added += 1
	print("Kenney map collision bodies: ", added)


func _find_spawn(root: Node) -> void:
	var marker := root.find_child("SpawnMarker", true, false)
	if marker is Node3D:
		var p: Vector3 = (marker as Node3D).global_position
		_spawn = Vector3(p.x, p.y + 1.5, p.z)
		return
	var gy := _raycast_ground_y(0.0, 8.0)
	if is_nan(gy):
		gy = 0.0
	_spawn = Vector3(0.0, gy + 1.2, 8.0)


func _raycast_ground_y(x: float, z: float) -> float:
	var space := get_world_3d().direct_space_state
	if space == null:
		return NAN
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 400.0, z), Vector3(x, -200.0, z))
	q.collision_mask = 8
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		# Fallback: any static
		q.collision_mask = 0xFFFFFFFF
		hit = space.intersect_ray(q)
		if hit.is_empty():
			return NAN
	return float(hit["position"].y)


func _place_player() -> void:
	if has_node("Player"):
		return
	var ps: PackedScene = player_scene
	if ps == null:
		ps = load("res://scenes/player.tscn") as PackedScene
	if ps == null:
		return
	var player := ps.instantiate()
	player.name = "Player"
	add_child(player)
	await get_tree().physics_frame
	var gy := get_terrain_height(_spawn.x, _spawn.z)
	player.global_position = Vector3(_spawn.x, gy + 0.08, _spawn.z)
	if player.get("stick_to_terrain") != null:
		player.set("stick_to_terrain", true)


func _ensure_pause_menu() -> void:
	if get_tree().get_first_node_in_group("pause_menu") != null:
		return
	var ps: PackedScene = pause_menu_scene
	if ps == null and ResourceLoader.exists("res://scenes/pause_menu.tscn"):
		ps = load("res://scenes/pause_menu.tscn") as PackedScene
	if ps != null:
		add_child(ps.instantiate())


func _build_title_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "MapTitleHud"
	add_child(layer)
	var label := Label.new()
	label.text = "%s\n%s" % [map_title, map_blurb]
	label.position = Vector2(28, 24)
	label.add_theme_font_size_override("font_size", 22)
	label.modulate = Color(0.92, 0.95, 0.98, 0.9)
	layer.add_child(label)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			# Pause menu handles Esc when present.
			pass
