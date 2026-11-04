extends Node3D
## Builds a 1000x1000 m forest world from Kenney assets + procedural terrain/roads.

const _TerrainCache = preload("res://scripts/terrain_cache.gd")
const _PlacementCache = preload("res://scripts/placement_cache.gd")
const _BakedCacheSeed = preload("res://scripts/baked_cache_seed.gd")

@export var terrain_size: float = 1000.0
@export var tree_count: int = 2400
@export var tree_min_spacing: float = 7.5 ## min distance between tree trunks (avoids canopy clip)
@export var seed_value: int = 42
@export var pond_count: int = 14
@export var road_width: float = 10.0
@export var terrain_resolution: int = 257 ## height samples per side (odd preferred)
@export var hill_height: float = 8.5 ## max hill amplitude in meters
@export var bump_height: float = 1.8 ## soft mid-scale rolls (not sharp ridges)
@export var micro_bump_height: float = 0.2 ## fine ground ripple
@export var height_smooth_passes: int = 3 ## blur passes → arc-like slopes instead of faceted planes
@export var mountain_count: int = 8
@export var mountain_height: float = 48.0 ## peak raise above base hills
@export var mountain_radius: float = 95.0 ## footprint radius of each peak
@export var grass_count: int = 10000 ## legacy; runtime uses grass_per_chunk
@export var grass_per_chunk: int = 48 ## lazy grass density per near chunk
@export var grass_tile_meters: float = 3.5 ## ground texture repeat size in meters
@export var house_count: int = 18
@export var animal_count: int = 140
@export var monster_count: int = 55
@export var ground_normal_scale: float = 0.9
@export var treasure_count: int = 48
## Optional Blender-authored scenery (terrain/trees/roads/ponds). Gameplay heightmap + actors/treasures still run.
@export var blender_world: PackedScene
@export var use_terrain_cache: bool = true
@export var use_placement_cache: bool = true
@export var chunk_size: float = 64.0
@export var stream_visual_chunks: int = 5 ## ~5*64m Chebyshev nearby forest
@export var stream_collision_chunks: int = 2
@export var stream_grass_chunks: int = 3 ## grass only in this nearer ring
@export var actor_stream_distance: float = 140.0

## Pond centers (xz) and radii, filled in _place_pond_data.
var _ponds: Array[Vector3] = [] # (x, radius, z)
## Collected pickup ids (persisted via save).
var _collected_pickups: Dictionary = {} # id -> true
## Road polylines: each entry is a list of xz waypoints.
var _road_paths: Array = []
## House footprints (x, radius, z) so trees/rocks avoid them.
var _house_pads: Array[Vector3] = []
## Actual building plan for map: {x,z,sx,sz,yaw} in world meters.
var _house_map_footprints: Array = []
## Mountain peaks for map (x, radius, z).
var _mountain_peaks: Array[Vector3] = []
## Cached once ? building every map open freezes the game.
var _map_height_preview: Image
## Heightmap samples, row-major (z major outer, x inner).
var _heights: PackedFloat32Array = PackedFloat32Array()
## Pre-flatten noise heights so roads follow the land instead of carving to y=0.
var _natural_heights: PackedFloat32Array = PackedFloat32Array()
var _height_res: int = 129
## Hi-res road coverage mask (R asphalt, G curb, B shoulder).
var _road_mask_tex: Texture2D
var _streamer: Node = null
var _sm_trees: Array[Mesh] = []
var _sm_grass: Array[Mesh] = []
var _sm_rocks: Array[Mesh] = []
var _sm_rock_mats: Array[Material] = []
var _sm_bushes: Array[Mesh] = []
var _sm_flowers: Array[Mesh] = []
var _grass_native_h: Array[float] = []
var _map_treasure_markers: Array = []
## Animals/monsters for the world map: {x,z,kind} kind 0=animal 1=monster.
var _map_actor_markers: Array = []
var _grass_filled_chunks: Dictionary = {} # Vector2i -> true
## True after streaming data is prepared and first chunks are forced in.
var world_ready: bool = false
signal world_built


func _ready() -> void:
	add_to_group("forest_world")
	world_ready = false
	_BakedCacheSeed.seed_all()
	if not GameSettings.settings_changed.is_connected(_on_settings_changed_stream):
		GameSettings.settings_changed.connect(_on_settings_changed_stream)
	# Build across frames so the window stays responsive (avoids "not responding").
	await _build_world_async()


func _on_settings_changed_stream() -> void:
	# Single apply path (apply_graphics emits settings_changed ? avoid double force_update).
	apply_streaming_budget(GameSettings.streaming_budget())


func get_terrain_height(x: float, z: float) -> float:
	if blender_world != null and has_node("BlenderWorld"):
		var hit := _raycast_blender_ground_y(x, z)
		if not is_nan(hit):
			return hit
	return _height_at(x, z)


func _instance_blender_world() -> void:
	if blender_world == null:
		return
	if has_node("BlenderWorld"):
		return
	var root := blender_world.instantiate()
	root.name = "BlenderWorld"
	add_child(root)
	_add_blender_terrain_collision(root)
	print("Blender forest scenery instanced: ", blender_world.resource_path)


func _add_blender_terrain_collision(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var n := String(mi.name).to_lower()
		if n.find("terrain") < 0 and n.find("grid") < 0:
			continue
		if mi.get_node_or_null("TerrainBody") != null:
			continue
		var shape: Shape3D = mi.mesh.create_trimesh_shape()
		if shape == null:
			continue
		var body := StaticBody3D.new()
		body.name = "TerrainBody"
		body.collision_layer = 1
		body.collision_mask = 0
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
		mi.add_child(body)
		print("Blender terrain collision: ", mi.name)


func _raycast_blender_ground_y(x: float, z: float) -> float:
	var space := get_world_3d().direct_space_state
	if space == null:
		return NAN
	var from := Vector3(x, 500.0, z)
	var to := Vector3(x, -200.0, z)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	q.collide_with_areas = false
	q.collide_with_bodies = true
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return NAN
	return float(hit["position"].y)


func is_pickup_collected(pickup_id: String) -> bool:
	return _collected_pickups.has(pickup_id)


func _build_world_async() -> void:
	_setup_road_paths()
	_place_pond_data()
	_place_house_sites()
	# 1) Terrain cache: reuse heightmap + road mask when seed/settings match.
	if not _try_load_terrain_cache():
		_build_heightmap()
		_road_mask_tex = _bake_road_mask()
		_save_terrain_cache()
	# Peaks are deterministic from seed; rebuild list even on terrain cache hits (for map).
	_collect_mountain_peaks()
	await get_tree().process_frame
	_instance_blender_world()
	_build_ground()
	if blender_world != null:
		var ground_vis := get_node_or_null("Ground")
		if ground_vis is VisualInstance3D:
			(ground_vis as VisualInstance3D).visible = false
	_build_world_bounds()
	_place_player_on_spawn()
	await get_tree().process_frame
	if blender_world == null:
		_build_road_markings()
		_build_traffic_lights()
		await get_tree().process_frame
		_build_pond_meshes()
		await get_tree().process_frame
		_build_houses()
		await get_tree().process_frame
	# 2/3/4) Chunk streaming + collision LOD + deferred actors/pickups.
	_setup_world_streamer()
	apply_streaming_budget(GameSettings.streaming_budget())
	await _load_streamer_meshes_only()
	_finalize_streamer_meshes()
	await _prewarm_runtime_assets()
	await get_tree().process_frame
	if not _try_load_placement_cache():
		if blender_world == null:
			await _prepare_forest_chunks()
			await get_tree().process_frame
			await _prepare_rock_chunks()
			await _prepare_bush_chunks()
			await get_tree().process_frame
		await _prepare_actor_spawns()
		_prepare_treasure_spawns()
		_save_placement_cache()
	# Grass is filled lazily per near chunk (see ensure_chunk_grass).
	await get_tree().process_frame
	if _streamer != null and _streamer.has_method("force_update"):
		_streamer.call("force_update")
	world_ready = true
	world_built.emit()
	print("World stream ready")

func _terrain_cache_key() -> String:
	return "m%d_h%d_r%d" % [mountain_count, int(mountain_height), int(mountain_radius)]


func _placement_cache_key() -> String:
	# "u4f" = even tree coverage; "trv2" = Kenney treasure meshes + value.
	# "bl1" = Blender scenery mode (skip Kenney tree/rock/bush props).
	var tag := "bl1" if blender_world != null else "u4f"
	return "%s_trv2_m%d_h%d_r%d_t%d_r%d_b%d_a%d_m%d_tr%d" % [
		tag, mountain_count, int(mountain_height), int(mountain_radius),
		tree_count, 220, 420, animal_count, monster_count, treasure_count
	]


func _try_load_terrain_cache() -> bool:
	if not use_terrain_cache:
		return false
	_height_res = maxi(terrain_resolution, 33)
	if _height_res % 2 == 0:
		_height_res += 1
	var path: String = _TerrainCache.cache_path(seed_value, terrain_size, _height_res, _terrain_cache_key())
	var data: Dictionary = _TerrainCache.try_load(path)
	if data.is_empty():
		return false
	_height_res = int(data["height_res"])
	_heights = data["heights"]
	_natural_heights = data["natural_heights"]
	_road_mask_tex = data["road_mask"]
	print("Terrain cache hit: ", path)
	return true


func _save_terrain_cache() -> void:
	if not use_terrain_cache or _road_mask_tex == null:
		return
	var path: String = _TerrainCache.cache_path(seed_value, terrain_size, _height_res, _terrain_cache_key())
	if _TerrainCache.save(path, _height_res, _heights, _natural_heights, _road_mask_tex):
		print("Terrain cache saved: ", path)


func _setup_world_streamer() -> void:
	var script := load("res://scripts/world_streamer.gd") as Script
	if script == null:
		push_warning("world_streamer.gd missing")
		return
	_streamer = Node.new()
	_streamer.set_script(script)
	_streamer.name = "WorldStreamer"
	_streamer.set("chunk_size", chunk_size)
	_streamer.set("visual_chunk_radius", stream_visual_chunks)
	_streamer.set("collision_chunk_radius", stream_collision_chunks)
	_streamer.set("grass_chunk_radius", stream_grass_chunks)
	_streamer.set("actor_distance", actor_stream_distance)
	add_child(_streamer)
	_streamer.call("setup", self)


func apply_streaming_budget(budget: Dictionary) -> void:
	if budget.is_empty():
		return
	stream_visual_chunks = int(budget.get("visual_chunks", stream_visual_chunks))
	stream_collision_chunks = int(budget.get("collision_chunks", stream_collision_chunks))
	stream_grass_chunks = int(budget.get("grass_chunks", stream_grass_chunks))
	grass_per_chunk = int(budget.get("grass_per_chunk", grass_per_chunk))
	actor_stream_distance = float(budget.get("actor_distance", actor_stream_distance))
	if _streamer == null:
		return
	_streamer.set("visual_chunk_radius", stream_visual_chunks)
	_streamer.set("collision_chunk_radius", stream_collision_chunks)
	_streamer.set("grass_chunk_radius", stream_grass_chunks)
	_streamer.set("detail_chunk_radius", int(budget.get("detail_chunks", 2)))
	_streamer.set("actor_distance", actor_stream_distance)
	_streamer.set("update_interval", float(budget.get("update_interval", 0.25)))
	if world_ready and _streamer.has_method("force_update"):
		_streamer.call("force_update")


func _prewarm_runtime_assets() -> void:
	## Parse a few common GLBs during the boot overlay so first nearby spawn doesn't hitch.
	var warm := [
		"res://assets/kenney_animals/animal-deer.glb",
		"res://assets/kenney_animals/animal-fox.glb",
		"res://assets/kenney_animals/animal-bunny.glb",
		"res://assets/kenney_monsters/character-zombie.glb",
		"res://assets/kenney_monsters/character-skeleton.glb",
	]
	for i in warm.size():
		var path: String = warm[i]
		if ResourceLoader.exists(path):
			var probe := _instantiate_glb_scene(path)
			if not probe.is_empty() and probe.get("root") != null:
				(probe["root"] as Node).free()
		if i % 2 == 1:
			await get_tree().process_frame


func _finalize_streamer_meshes() -> void:
	if _streamer == null or not _streamer.has_method("set_meshes"):
		return
	_streamer.call("set_meshes", _sm_trees, _sm_grass, _sm_rocks, _sm_rock_mats, _sm_bushes, _sm_flowers)


func _try_load_placement_cache() -> bool:
	if not use_placement_cache or _streamer == null:
		return false
	var path: String = _PlacementCache.cache_path(seed_value, terrain_size, _placement_cache_key())
	var data: Dictionary = _PlacementCache.try_load(path)
	if data.is_empty():
		return false
	_streamer.call("import_placement_data", data)
	_rebuild_map_treasure_markers_from_cache(data.get("treasures", []))
	_rebuild_map_actor_markers_from_cache(data.get("actors", []))
	print("Placement cache hit: ", path)
	return true


func _save_placement_cache() -> void:
	if not use_placement_cache or _streamer == null:
		return
	if not _streamer.has_method("export_placement_data"):
		return
	var data: Dictionary = _streamer.call("export_placement_data")
	var path: String = _PlacementCache.cache_path(seed_value, terrain_size, _placement_cache_key())
	if _PlacementCache.save(path, data):
		print("Placement cache saved: ", path)


func _rebuild_map_treasure_markers_from_cache(treasures: Array) -> void:
	_map_treasure_markers.clear()
	for tr in treasures:
		if typeof(tr) != TYPE_DICTIONARY:
			continue
		var pid := str(tr.get("id", ""))
		if pid != "" and _collected_pickups.has(pid):
			continue
		var pos: Vector3 = tr.get("pos", Vector3.ZERO)
		_map_treasure_markers.append({
			"id": pid,
			"x": pos.x,
			"z": pos.z,
			"name": str(tr.get("item_name", "")),
			"value": int(tr.get("item_value", 0)),
		})


func _rebuild_map_actor_markers_from_cache(actors: Array) -> void:
	_map_actor_markers.clear()
	for a in actors:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var pos: Vector3 = a.get("pos", Vector3.ZERO)
		_map_actor_markers.append({
			"x": pos.x,
			"z": pos.z,
			"kind": int(a.get("kind", 0)),
		})


func _load_streamer_meshes_only() -> void:
	## Load GLB/primitive meshes once; placement may come from cache.
	_load_tree_meshes()
	await get_tree().process_frame
	_load_grass_meshes()
	_load_rock_meshes()
	await get_tree().process_frame
	_load_bush_and_flower_meshes()


func _load_tree_meshes() -> void:
	if not _sm_trees.is_empty():
		return
	var tree_files := [
		"tree_default.glb", "tree_default_dark.glb",
		"tree_oak.glb", "tree_oak_dark.glb",
		"tree_detailed.glb", "tree_detailed_dark.glb",
		"tree_simple.glb", "tree_simple_dark.glb",
		"tree_tall.glb", "tree_tall_dark.glb",
		"tree_thin.glb", "tree_thin_dark.glb",
		"tree_fat.glb", "tree_cone.glb", "tree_cone_dark.glb",
		"tree_plateau.glb", "tree_plateau_dark.glb",
		"tree_blocks.glb", "tree_small.glb",
		"tree_pineDefaultA.glb", "tree_pineDefaultB.glb",
		"tree_pineTallA.glb", "tree_pineTallB.glb", "tree_pineTallC.glb", "tree_pineTallD.glb",
		"tree_pineTallA_detailed.glb", "tree_pineTallB_detailed.glb",
		"tree_pineRoundA.glb", "tree_pineRoundB.glb", "tree_pineRoundC.glb", "tree_pineRoundD.glb",
		"tree_pineSmallA.glb", "tree_pineSmallB.glb",
	]
	for file_name in tree_files:
		var mesh := _load_glb_mesh("res://assets/kenney_trees/%s" % file_name)
		if mesh != null:
			_sm_trees.append(mesh)


func _load_grass_meshes() -> void:
	if not _sm_grass.is_empty():
		return
	var grass_files := [
		"grass.glb", "grass_large.glb",
		"grass_leafs.glb", "grass_leafsLarge.glb",
		"plant_flatShort.glb", "plant_flatTall.glb",
	]
	_grass_native_h.clear()
	for file_name in grass_files:
		var mesh := _load_glb_mesh("res://assets/kenney_plants/%s" % file_name)
		if mesh == null:
			continue
		_sm_grass.append(mesh)
		_grass_native_h.append(maxf(mesh.get_aabb().size.y, 0.05))


func _load_rock_meshes() -> void:
	if not _sm_rocks.is_empty():
		return
	var mat_a := _make_mat(Color(0.45, 0.43, 0.40), 0.95)
	var mat_b := _make_mat(Color(0.38, 0.37, 0.35), 0.98)
	var mat_c := _make_mat(Color(0.52, 0.50, 0.46), 0.92)
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 1.0
	sphere_mesh.height = 1.5
	sphere_mesh.radial_segments = 8
	sphere_mesh.rings = 4
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(1.8, 1.1, 1.4)
	var tall_mesh := SphereMesh.new()
	tall_mesh.radius = 0.9
	tall_mesh.height = 2.4
	tall_mesh.radial_segments = 8
	tall_mesh.rings = 5
	_sm_rocks.append(sphere_mesh)
	_sm_rocks.append(box_mesh)
	_sm_rocks.append(tall_mesh)
	_sm_rock_mats.append(mat_a)
	_sm_rock_mats.append(mat_b)
	_sm_rock_mats.append(mat_c)


func _load_bush_and_flower_meshes() -> void:
	if _sm_bushes.is_empty():
		var bush_files := [
			"plant_bush.glb", "plant_bushDetailed.glb",
			"plant_bushLarge.glb", "plant_bushSmall.glb", "plant_bushTriangle.glb",
		]
		for file_name in bush_files:
			var mesh := _load_glb_mesh("res://assets/kenney_plants/%s" % file_name)
			if mesh != null:
				_sm_bushes.append(mesh)
	if _sm_flowers.is_empty():
		var flower_files := [
			"flower_purpleA.glb", "flower_purpleB.glb",
			"flower_yellowA.glb", "flower_yellowB.glb",
			"flower_redA.glb", "flower_redB.glb",
		]
		for file_name in flower_files:
			var mesh := _load_glb_mesh("res://assets/kenney_plants/%s" % file_name)
			if mesh != null:
				_sm_flowers.append(mesh)


func ensure_chunk_grass(chunk: Vector2i, cs: float) -> void:
	## Lazily scatter grass inside one chunk the first time it enters the grass ring.
	if _grass_filled_chunks.has(chunk):
		return
	if _streamer == null or _sm_grass.is_empty() or _grass_native_h.is_empty():
		# Do not mark filled ? meshes may not be ready yet on very early calls.
		return
	var rng := RandomNumberGenerator.new()
	# Stable per-chunk seed so revisiting looks the same.
	rng.seed = seed_value + 404 + int(chunk.x) * 73856093 + int(chunk.y) * 19349663
	var x0 := float(chunk.x) * cs
	var z0 := float(chunk.y) * cs
	var margin := 1.5
	var placed := 0
	var attempts := 0
	var max_attempts := grass_per_chunk * 10
	while placed < grass_per_chunk and attempts < max_attempts:
		attempts += 1
		var p := Vector3(
			rng.randf_range(x0 + margin, x0 + cs - margin),
			0.0,
			rng.randf_range(z0 + margin, z0 + cs - margin)
		)
		if p.length() < 8.0:
			continue
		if _blocked(p, 3.0) or _too_steep_or_peak(p):
			continue
		p = _stamp_height(p)
		var t := rng.randi_range(0, _sm_grass.size() - 1)
		var target_h := rng.randf_range(0.35, 1.15)
		var s := target_h / _grass_native_h[t]
		var sxz := s * rng.randf_range(0.85, 1.25)
		var sy := s * rng.randf_range(0.8, 1.2)
		var yaw := rng.randf_range(0.0, TAU)
		var lean := Basis(Vector3.UP, yaw)
		lean = lean.rotated(lean.x, rng.randf_range(-0.12, 0.12))
		lean = lean.rotated(lean.z, rng.randf_range(-0.1, 0.1))
		var basis := lean.scaled(Vector3(sxz, sy, sxz))
		var sink := rng.randf_range(0.0, 0.04) * sy
		_streamer.call("add_grass", Transform3D(basis, p + Vector3(0.0, -sink, 0.0)), t)
		placed += 1
	# Mark after attempting so a failed early call (no meshes) can retry.
	_grass_filled_chunks[chunk] = true


func refresh_world_stream() -> void:
	if _streamer != null and _streamer.has_method("force_update"):
		_streamer.call("force_update")


func mark_pickup_collected(pickup_id: String) -> void:
	_collected_pickups[pickup_id] = true
	if _streamer != null and _streamer.has_method("_despawn_treasure"):
		_streamer.call("_despawn_treasure", pickup_id)


func get_collected_pickups() -> Array:
	return _collected_pickups.keys()


func apply_collected_pickups(ids: Variant) -> void:
	_collected_pickups.clear()
	if typeof(ids) != TYPE_ARRAY:
		return
	for id in ids:
		_collected_pickups[str(id)] = true
	for node in get_tree().get_nodes_in_group("world_pickup"):
		var pid := ""
		if "pickup_id" in node:
			pid = str(node.pickup_id)
		if pid != "" and _collected_pickups.has(pid):
			node.queue_free()


func get_map_data() -> Dictionary:
	var pickups: Array = []
	for m in _map_treasure_markers:
		var pid := str(m.get("id", ""))
		if pid != "" and _collected_pickups.has(pid):
			continue
		pickups.append(m)
	for node in get_tree().get_nodes_in_group("world_pickup"):
		if node.has_method("get_map_marker"):
			pickups.append(node.call("get_map_marker"))
	if _map_height_preview == null:
		_map_height_preview = _build_map_height_preview(40)
	return {
		"size": terrain_size,
		"road_width": road_width,
		"roads": _road_paths.duplicate(true),
		"ponds": _ponds.duplicate(),
		"houses": _house_map_footprints.duplicate(true) if not _house_map_footprints.is_empty() else _house_pads_as_map_rects(),
		"mountains": _mountain_peaks.duplicate(),
		"pickups": pickups,
		"actors": _map_actor_markers.duplicate(true),
		"height_preview": _map_height_preview,
	}


func _house_pads_as_map_rects() -> Array:
	## Fallback before houses finish building: pad radius as circular yard.
	var out: Array = []
	for pad in _house_pads:
		out.append({"x": pad.x, "z": pad.z, "sx": pad.y * 2.0, "sz": pad.y * 2.0, "yaw": 0.0, "circle": true})
	return out


func _build_map_height_preview(res: int) -> Image:
	## Coarse height tint for the world map (green low ? rock high).
	var img := Image.create(res, res, false, Image.FORMAT_RGBA8)
	if _heights.is_empty() or _height_res < 2:
		img.fill(Color(0.2, 0.35, 0.2, 1.0))
		return img
	var half := terrain_size * 0.5
	var h_min := 1.0e20
	var h_max := -1.0e20
	for i in _heights.size():
		h_min = minf(h_min, _heights[i])
		h_max = maxf(h_max, _heights[i])
	var span := maxf(h_max - h_min, 1.0)
	for y in res:
		for x in res:
			var wx := -half + terrain_size * (float(x) + 0.5) / float(res)
			# Image row 0 is top of map = world -Z (north), same as _world_to_map.
			var wz := -half + terrain_size * (float(y) + 0.5) / float(res)
			var h := _sample_height_array(_heights, wx, wz)
			var t := clampf((h - h_min) / span, 0.0, 1.0)
			var col: Color
			if t < 0.35:
				col = Color(0.18, 0.38, 0.2).lerp(Color(0.28, 0.48, 0.24), t / 0.35)
			elif t < 0.65:
				col = Color(0.28, 0.48, 0.24).lerp(Color(0.42, 0.5, 0.3), (t - 0.35) / 0.3)
			elif t < 0.85:
				col = Color(0.42, 0.5, 0.3).lerp(Color(0.55, 0.5, 0.4), (t - 0.65) / 0.2)
			else:
				col = Color(0.55, 0.5, 0.4).lerp(Color(0.78, 0.78, 0.8), (t - 0.85) / 0.15)
			img.set_pixel(x, y, col)
	return img


func _inside_pond(p: Vector3, padding: float = 2.0) -> bool:
	for pond in _ponds:
		var center := Vector3(pond.x, 0.0, pond.z)
		if Vector2(p.x - center.x, p.z - center.z).length() < pond.y + padding:
			return true
	return false


func _inside_house_pad(p: Vector3, padding: float = 2.0) -> bool:
	for pad in _house_pads:
		if Vector2(p.x - pad.x, p.z - pad.z).length() < pad.y + padding:
			return true
	return false


func _point_segment_dist_xz(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ap := Vector2(p.x - a.x, p.z - a.z)
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ab_len2 := ab.length_squared()
	if ab_len2 < 0.0001:
		return ap.length()
	var t := clampf(ap.dot(ab) / ab_len2, 0.0, 1.0)
	var closest := Vector2(a.x, a.z) + ab * t
	return closest.distance_to(Vector2(p.x, p.z))


func _inside_road(p: Vector3, padding: float = 2.0) -> bool:
	var limit := road_width * 0.5 + padding
	for path in _road_paths:
		for i in range(path.size() - 1):
			if _point_segment_dist_xz(p, path[i], path[i + 1]) < limit:
				return true
	return false


func _push_off_road(xz: Vector2, clear: float) -> Vector2:
	# Walk away from the nearest centerline until outside asphalt + clear margin.
	var need := road_width * 0.5 + clear
	for _i in 48:
		var best_d := 1.0e20
		var best_away := Vector2.ZERO
		for path in _road_paths:
			for i in range(path.size() - 1):
				var a: Vector3 = path[i]
				var b: Vector3 = path[i + 1]
				var ab := Vector2(b.x - a.x, b.z - a.z)
				var ab_len2 := ab.length_squared()
				if ab_len2 < 0.0001:
					continue
				var t := clampf(Vector2(xz.x - a.x, xz.y - a.z).dot(ab) / ab_len2, 0.0, 1.0)
				var closest := Vector2(a.x, a.z) + ab * t
				var d := closest.distance_to(xz)
				if d < best_d:
					best_d = d
					var away := xz - closest
					if away.length_squared() < 0.0001:
						away = Vector2(-ab.y, ab.x)
					best_away = away.normalized()
		if best_d >= need or best_away == Vector2.ZERO:
			break
		xz += best_away * 0.45
	return xz


func _blocked(p: Vector3, padding: float = 4.0) -> bool:
	return _inside_pond(p, padding) or _inside_road(p, padding) or _inside_house_pad(p, padding)


func is_blocked_for_critter(p: Vector3, padding: float = 2.0) -> bool:
	return _blocked(p, padding)


## Even coverage with local randomness: stratified jittered cells + min separation.
## Avoids the old "ring near spawn" bias that made creatures look clumped / non-random.
func _sample_positions_random(
	count: int,
	margin: float,
	min_clear: float,
	rng: RandomNumberGenerator,
	_near_weight: float = 0.0,
	_near_radius: float = 60.0,
	min_sep: float = 0.0
) -> Array[Vector3]:
	var half := terrain_size * 0.5 - margin
	var span := maxf(half * 2.0, 1.0)
	var positions: Array[Vector3] = []
	if count <= 0:
		return positions
	var sep := min_sep
	if sep <= 0.0:
		# Aim for roughly even spacing across the playable square.
		sep = clampf(span / sqrt(float(count) * 1.15), 8.0, 48.0)

	var cells := maxi(ceili(sqrt(float(count)) * 1.4), 4)
	var cell := span / float(cells)
	var order: Array[int] = []
	order.resize(cells * cells)
	for i in order.size():
		order[i] = i
	for i in order.size():
		var j := rng.randi_range(i, order.size() - 1)
		var tmp := order[i]
		order[i] = order[j]
		order[j] = tmp

	for idx in order:
		if positions.size() >= count:
			break
		var cx := idx % cells
		var cz := int(idx / cells)
		var p := Vector3(
			-half + (float(cx) + rng.randf()) * cell,
			0.0,
			-half + (float(cz) + rng.randf()) * cell
		)
		p.x = clampf(p.x, -half, half)
		p.z = clampf(p.z, -half, half)
		if p.length() < min_clear:
			continue
		if _blocked(p, 3.0):
			continue
		if not _sep_ok(p, positions, sep):
			continue
		positions.append(_stamp_height(p))

	# Top up leftovers with pure rejection sampling if roads/ponds ate too many cells.
	var attempts := 0
	while positions.size() < count and attempts < count * 60:
		attempts += 1
		var p2 := Vector3(rng.randf_range(-half, half), 0.0, rng.randf_range(-half, half))
		if p2.length() < min_clear:
			continue
		if _blocked(p2, 3.0):
			continue
		if not _sep_ok(p2, positions, sep * 0.85):
			continue
		positions.append(_stamp_height(p2))
	return positions


func _sep_ok(p: Vector3, existing: Array[Vector3], sep: float) -> bool:
	if sep <= 0.0 or existing.is_empty():
		return true
	var sep2 := sep * sep
	for q in existing:
		var dx := p.x - q.x
		var dz := p.z - q.z
		if dx * dx + dz * dz < sep2:
			return false
	return true


func _place_player_on_spawn() -> void:
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	if player == null:
		return
	# Drop from above so the capsule settles on trimesh instead of spawning stuck inside it.
	var y := _height_at(0.0, 0.0) + 2.5
	player.global_position = Vector3(0.0, y, 0.0)
	player.velocity = Vector3.ZERO


func _sample_height_array(data: PackedFloat32Array, x: float, z: float) -> float:
	if data.is_empty():
		return 0.0
	var half := terrain_size * 0.5
	var u := (x + half) / terrain_size * float(_height_res - 1)
	var v := (z + half) / terrain_size * float(_height_res - 1)
	var x0 := clampi(int(floor(u)), 0, _height_res - 2)
	var z0 := clampi(int(floor(v)), 0, _height_res - 2)
	var tx := clampf(u - float(x0), 0.0, 1.0)
	var tz := clampf(v - float(z0), 0.0, 1.0)
	var h00 := data[z0 * _height_res + x0]
	var h10 := data[z0 * _height_res + x0 + 1]
	var h01 := data[(z0 + 1) * _height_res + x0]
	var h11 := data[(z0 + 1) * _height_res + x0 + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func _height_at(x: float, z: float) -> float:
	return _sample_height_array(_heights, x, z)


func _natural_height_at(x: float, z: float) -> float:
	return _sample_height_array(_natural_heights, x, z)


func _stamp_height(p: Vector3) -> Vector3:
	return Vector3(p.x, _height_at(p.x, p.z), p.z)


func _build_heightmap_flat() -> void:
	# No terrain mesh — keep a flat height field so props/player share y=0.
	_height_res = maxi(terrain_resolution, 33)
	if _height_res % 2 == 0:
		_height_res += 1
	_heights.resize(_height_res * _height_res)
	_heights.fill(0.0)
	_natural_heights = _heights.duplicate()


func _build_heightmap() -> void:
	_height_res = maxi(terrain_resolution, 33)
	if _height_res % 2 == 0:
		_height_res += 1
	_heights.resize(_height_res * _height_res)

	# Low-frequency smooth noise only — high-frequency noise makes "right-angle" facets.
	var hills := FastNoiseLite.new()
	hills.seed = seed_value
	hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	hills.frequency = 0.0028
	hills.fractal_type = FastNoiseLite.FRACTAL_FBM
	hills.fractal_octaves = 3
	hills.fractal_gain = 0.45

	var bumps := FastNoiseLite.new()
	bumps.seed = seed_value + 17
	bumps.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	bumps.frequency = 0.012
	bumps.fractal_type = FastNoiseLite.FRACTAL_FBM
	bumps.fractal_octaves = 2
	bumps.fractal_gain = 0.4

	var micro := FastNoiseLite.new()
	micro.seed = seed_value + 91
	micro.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	micro.frequency = 0.035
	micro.fractal_octaves = 1

	var half := terrain_size * 0.5
	for zi in _height_res:
		for xi in _height_res:
			var x := -half + terrain_size * float(xi) / float(_height_res - 1)
			var z := -half + terrain_size * float(zi) / float(_height_res - 1)
			var h := hills.get_noise_2d(x, z) * hill_height
			h += bumps.get_noise_2d(x, z) * bump_height
			h += micro.get_noise_2d(x, z) * micro_bump_height
			_heights[zi * _height_res + xi] = h

	# Distinct mountain peaks (not just rolling hills).
	_stamp_mountains()

	# Round creases into arcs before (and after) feature stamps.
	_smooth_height_field(height_smooth_passes)
	_natural_heights = _heights.duplicate()

	# Soft spawn pad; road corridors follow natural hills (only smooth micro-bumps under asphalt).
	var spawn_h := _natural_height_at(0.0, 0.0)
	_flatten_disc(0.0, 0.0, 16.0, spawn_h, 12.0)
	for path in _road_paths:
		for i in range(path.size() - 1):
			_flatten_segment(path[i], path[i + 1], road_width * 0.5 + 2.4, 5.0)
	for hub in _road_intersection_hubs():
		var hub_h := _natural_height_at(hub.x, hub.z)
		_flatten_disc(hub.x, hub.z, road_width * 0.5 + 2.5, hub_h, 5.0)
	for pond in _ponds:
		var ph := _natural_height_at(pond.x, pond.z) - 0.4
		_flatten_disc(pond.x, pond.z, pond.y + 2.0, ph, 10.0)
	for pad in _house_pads:
		var yard_h := _natural_height_at(pad.x, pad.z)
		_flatten_disc(pad.x, pad.z, pad.y + 2.0, yard_h, 6.0)
	_smooth_height_field(maxi(height_smooth_passes - 1, 1))
	# Carve AFTER blur so painted asphalt sits in a slight road bed.
	for path in _road_paths:
		for i in range(path.size() - 1):
			_lower_segment(path[i], path[i + 1], road_width * 0.5 + 1.85, 0.25)
	for hub in _road_intersection_hubs():
		_lower_disc(hub.x, hub.z, road_width * 0.5 + 2.0, 0.25)
	_natural_heights = _heights.duplicate()


func _smooth_height_field(passes: int) -> void:
	# 3x3 box blur — turns sharp triangle folds into rounded slopes.
	if passes <= 0 or _heights.is_empty():
		return
	var n := _height_res
	for _p in passes:
		var next := PackedFloat32Array()
		next.resize(_heights.size())
		for zi in n:
			for xi in n:
				var acc := 0.0
				var wsum := 0.0
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						var xj := clampi(xi + dx, 0, n - 1)
						var zj := clampi(zi + dz, 0, n - 1)
						var w := 2.0 if dx == 0 and dz == 0 else 1.0
						acc += _heights[zj * n + xj] * w
						wsum += w
				next[zi * n + xi] = acc / wsum
		_heights = next


func _mountain_peak_layout() -> Array:
	## Deterministic peak centers + radii (must match stamp RNG order).
	var out: Array = []
	if mountain_count <= 0 or mountain_height <= 0.0:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 707
	var half := terrain_size * 0.5 - mountain_radius * 0.55
	var peaks: Array[Vector2] = [
		Vector2(280.0, -260.0),
		Vector2(-320.0, -180.0),
		Vector2(-240.0, 310.0),
		Vector2(340.0, 220.0),
		Vector2(-60.0, -380.0),
		Vector2(120.0, 360.0),
	]
	while peaks.size() < mountain_count:
		var candidate := Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half))
		if candidate.length() < 140.0:
			continue
		var ok := true
		for existing in peaks:
			if existing.distance_to(candidate) < mountain_radius * 1.15:
				ok = false
				break
		if ok:
			peaks.append(candidate)
	for i in mini(peaks.size(), mountain_count):
		var c: Vector2 = peaks[i]
		var radius := mountain_radius * rng.randf_range(0.75, 1.2)
		var peak_h := mountain_height * rng.randf_range(0.7, 1.15)
		var stretch := Vector2(rng.randf_range(0.85, 1.2), rng.randf_range(0.85, 1.2))
		out.append({"c": c, "radius": radius, "peak_h": peak_h, "stretch": stretch})
	return out


func _collect_mountain_peaks() -> void:
	_mountain_peaks.clear()
	for item in _mountain_peak_layout():
		var c: Vector2 = item["c"]
		_mountain_peaks.append(Vector3(c.x, float(item["radius"]), c.y))


func _stamp_mountains() -> void:
	for item in _mountain_peak_layout():
		var c: Vector2 = item["c"]
		_raise_mountain(c.x, c.y, float(item["radius"]), float(item["peak_h"]), item["stretch"])


func _raise_mountain(cx: float, cz: float, radius: float, peak_h: float, stretch: Vector2) -> void:
	var half := terrain_size * 0.5
	var outer := radius * 1.35
	for zi in _height_res:
		for xi in _height_res:
			var x := -half + terrain_size * float(xi) / float(_height_res - 1)
			var z := -half + terrain_size * float(zi) / float(_height_res - 1)
			var dx := (x - cx) / maxf(stretch.x, 0.2)
			var dz := (z - cz) / maxf(stretch.y, 0.2)
			var d := sqrt(dx * dx + dz * dz)
			if d >= outer:
				continue
			# Smooth dome: flat-ish summit, steep mid-slope, soft foothills.
			var t := clampf(d / maxf(radius, 0.001), 0.0, 1.0)
			var w := 1.0 - t
			w = w * w * (3.0 - 2.0 * w)
			w = pow(w, 1.35)
			if d > radius:
				var edge := 1.0 - (d - radius) / maxf(outer - radius, 0.001)
				w *= clampf(edge, 0.0, 1.0)
			var idx := zi * _height_res + xi
			_heights[idx] += peak_h * w


func _flatten_disc(cx: float, cz: float, radius: float, target: float, feather: float) -> void:
	var half := terrain_size * 0.5
	var outer := radius + feather
	for zi in _height_res:
		for xi in _height_res:
			var x := -half + terrain_size * float(xi) / float(_height_res - 1)
			var z := -half + terrain_size * float(zi) / float(_height_res - 1)
			var d := Vector2(x - cx, z - cz).length()
			if d >= outer:
				continue
			var w := 1.0 if d <= radius else 1.0 - (d - radius) / maxf(feather, 0.001)
			w = clampf(w, 0.0, 1.0)
			w = w * w * (3.0 - 2.0 * w)
			var idx := zi * _height_res + xi
			_heights[idx] = lerpf(_heights[idx], target, w)


func _flatten_segment(a: Vector3, b: Vector3, half_width: float, feather: float) -> void:
	var half := terrain_size * 0.5
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ab_len := ab.length()
	if ab_len < 0.001:
		_flatten_disc(a.x, a.z, half_width, _natural_height_at(a.x, a.z), feather)
		return
	var abn := ab / ab_len
	for zi in _height_res:
		for xi in _height_res:
			var x := -half + terrain_size * float(xi) / float(_height_res - 1)
			var z := -half + terrain_size * float(zi) / float(_height_res - 1)
			var ap := Vector2(x - a.x, z - a.z)
			var t := clampf(ap.dot(abn) / ab_len, 0.0, 1.0)
			var closest := Vector2(a.x, a.z) + ab * t
			var d := closest.distance_to(Vector2(x, z))
			var outer := half_width + feather
			if d >= outer:
				continue
			var w := 1.0 if d <= half_width else 1.0 - (d - half_width) / maxf(feather, 0.001)
			w = clampf(w, 0.0, 1.0)
			w = w * w * (3.0 - 2.0 * w)
			# Smooth the corridor onto natural elevation (keeps hills, removes micro bumps under asphalt).
			var target := _natural_height_at(closest.x, closest.y)
			var idx := zi * _height_res + xi
			_heights[idx] = lerpf(_heights[idx], target, w)


func _lower_disc(cx: float, cz: float, radius: float, amount: float) -> void:
	if amount <= 0.0 or radius <= 0.0:
		return
	var half := terrain_size * 0.5
	var feather := maxf(radius * 0.35, 1.5)
	var outer := radius + feather
	for zi in _height_res:
		for xi in _height_res:
			var x := -half + terrain_size * float(xi) / float(_height_res - 1)
			var z := -half + terrain_size * float(zi) / float(_height_res - 1)
			var d := Vector2(x - cx, z - cz).length()
			if d >= outer:
				continue
			var w := 1.0 if d <= radius else 1.0 - (d - radius) / maxf(feather, 0.001)
			w = clampf(w, 0.0, 1.0)
			w = w * w * (3.0 - 2.0 * w)
			_heights[zi * _height_res + xi] -= amount * w


func _lower_segment(a: Vector3, b: Vector3, half_width: float, amount: float) -> void:
	if amount <= 0.0:
		return
	var half := terrain_size * 0.5
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ab_len := ab.length()
	if ab_len < 0.001:
		_lower_disc(a.x, a.z, half_width, amount)
		return
	var abn := ab / ab_len
	var feather := maxf(half_width * 0.35, 1.5)
	var outer := half_width + feather
	for zi in _height_res:
		for xi in _height_res:
			var x := -half + terrain_size * float(xi) / float(_height_res - 1)
			var z := -half + terrain_size * float(zi) / float(_height_res - 1)
			var ap := Vector2(x - a.x, z - a.z)
			var t := clampf(ap.dot(abn) / ab_len, 0.0, 1.0)
			var closest := Vector2(a.x, a.z) + ab * t
			var d := closest.distance_to(Vector2(x, z))
			if d >= outer:
				continue
			var w := 1.0 if d <= half_width else 1.0 - (d - half_width) / maxf(feather, 0.001)
			w = clampf(w, 0.0, 1.0)
			w = w * w * (3.0 - 2.0 * w)
			_heights[zi * _height_res + xi] -= amount * w


func _build_ground() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := terrain_size * 0.5
	var tile := maxf(grass_tile_meters, 1.0)

	for zi in _height_res - 1:
		for xi in _height_res - 1:
			var x0 := -half + terrain_size * float(xi) / float(_height_res - 1)
			var x1 := -half + terrain_size * float(xi + 1) / float(_height_res - 1)
			var z0 := -half + terrain_size * float(zi) / float(_height_res - 1)
			var z1 := -half + terrain_size * float(zi + 1) / float(_height_res - 1)
			var v00 := Vector3(x0, _heights[zi * _height_res + xi], z0)
			var v10 := Vector3(x1, _heights[zi * _height_res + xi + 1], z0)
			var v01 := Vector3(x0, _heights[(zi + 1) * _height_res + xi], z1)
			var v11 := Vector3(x1, _heights[(zi + 1) * _height_res + xi + 1], z1)
			_add_terrain_tri(st, v00, v01, v11, tile)
			_add_terrain_tri(st, v00, v11, v10, tile)

	st.generate_normals()
	st.generate_tangents()
	var mesh := st.commit()

	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = mesh
	ground.material_override = _make_ground_material()
	# Huge heightfield: force a conservative AABB so frustum culling never drops
	# a peak that sits near the AABB edge when looked at head-on.
	var y_max := mountain_height + hill_height + bump_height + 40.0
	ground.custom_aabb = AABB(
		Vector3(-half - 20.0, -20.0, -half - 20.0),
		Vector3(terrain_size + 40.0, y_max + 40.0, terrain_size + 40.0)
	)
	ground.extra_cull_margin = 80.0
	add_child(ground)

	var body := StaticBody3D.new()
	body.name = "GroundBody"
	body.collision_layer = 8
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	col.shape = mesh.create_trimesh_shape()
	body.add_child(col)
	add_child(body)


func _add_terrain_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, tile: float) -> void:
	for v in [a, b, c]:
		st.set_uv(Vector2(v.x / tile, v.z / tile))
		st.add_vertex(v)


func _build_world_bounds() -> void:
	# Invisible walls so the player cannot walk off the terrain and fall forever.
	var half := terrain_size * 0.5 - 1.0
	var thick := 8.0
	var wall_h := 80.0
	var y := wall_h * 0.5
	var body := StaticBody3D.new()
	body.name = "WorldBounds"
	var walls: Array = [
		[Vector3(half + thick * 0.5, y, 0.0), Vector3(thick, wall_h, terrain_size + thick * 2.0)],
		[Vector3(-half - thick * 0.5, y, 0.0), Vector3(thick, wall_h, terrain_size + thick * 2.0)],
		[Vector3(0.0, y, half + thick * 0.5), Vector3(terrain_size + thick * 2.0, wall_h, thick)],
		[Vector3(0.0, y, -half - thick * 0.5), Vector3(terrain_size + thick * 2.0, wall_h, thick)],
	]
	for w in walls:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = w[1]
		col.shape = shape
		col.position = w[0]
		body.add_child(col)
	# No solid catch-floor: a under-map box steals ground raycasts and spawns the player underground.
	add_child(body)


func _load_glb_mesh(res_path: String) -> Mesh:
	# Use ResourceLoader so exported builds resolve remapped .scn inside the PCK.
	var packed := load(res_path) as PackedScene
	if packed == null:
		push_warning("Kenney asset missing: " + res_path)
		return null
	var root := packed.instantiate()
	if root == null:
		return null
	var found := _find_mesh_recursive(root)
	root.free()
	return found


func _find_mesh_recursive(node: Node) -> Mesh:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var mesh: Mesh = mi.mesh.duplicate()
			# Materials often live on the MeshInstance, not the Mesh resource.
			for i in mesh.get_surface_count():
				var mat := mi.get_active_material(i)
				if mat != null:
					var fixed := mat.duplicate()
					if fixed is BaseMaterial3D:
						_retint_kenney_nature_material(fixed as BaseMaterial3D)
					mesh.surface_set_material(i, fixed)
			return mesh
	for child in node.get_children():
		var m := _find_mesh_recursive(child)
		if m != null:
			return m
	return null


## Kenney Nature Kit GLBs ship mint/teal leaf factors + metallic=1. Retint to forest greens.
func _retint_kenney_nature_material(bm: BaseMaterial3D) -> void:
	bm.metallic = 0.0
	bm.roughness = 0.9
	var n := String(bm.resource_name).to_lower()
	if n.is_empty():
		# Fallback: mint/cyan albedo without a name still counts as foliage.
		var c := bm.albedo_color
		if c.g > 0.4 and c.b > c.r * 1.1:
			n = "leafs"
		elif c.r > c.g and c.r > 0.45:
			n = "wood"
	if n.find("leaf") >= 0 or n.find("grass") >= 0 or n == "plant" or n.find("hedge") >= 0:
		if n.find("dark") >= 0:
			bm.albedo_color = Color(0.13, 0.34, 0.15)
		else:
			bm.albedo_color = Color(0.23, 0.52, 0.21)
	elif n.find("wood") >= 0 or n.find("bark") >= 0:
		if n.find("dark") >= 0:
			bm.albedo_color = Color(0.30, 0.18, 0.10)
		else:
			bm.albedo_color = Color(0.50, 0.33, 0.18)
	# Flowers / rocks / other named mats keep authored colors (only demetalize above).


func _load_kenney_texture(res_path: String) -> Texture2D:
	return load(res_path) as Texture2D


func _sample_positions(
	count: int,
	margin: float,
	clear_radius: float,
	rng: RandomNumberGenerator,
	min_spacing: float = -1.0
) -> Array[Vector3]:
	## Stratified jittered cells in shuffled order ? even coverage (no edge pile-up).
	var half := terrain_size * 0.5 - margin
	var span := maxf(half * 2.0, 1.0)
	var spacing := min_spacing if min_spacing > 0.0 else maxf(tree_min_spacing, 4.0)
	var positions: Array[Vector3] = []
	if count <= 0:
		return positions
	var grid: Dictionary = {}
	# Slightly denser than spacing so blocked cells (roads/houses) don't leave blank regions.
	var cells := maxi(ceili(span / maxf(spacing * 0.92, 4.0)), 8)
	var cell := span / float(cells)
	var order: Array[int] = []
	order.resize(cells * cells)
	for i in order.size():
		order[i] = i
	for i in order.size():
		var j := rng.randi_range(i, order.size() - 1)
		var tmp := order[i]
		order[i] = order[j]
		order[j] = tmp

	for idx in order:
		if positions.size() >= count:
			break
		var cx := idx % cells
		var cz := int(idx / cells)
		var p := Vector3(
			-half + (float(cx) + rng.randf()) * cell,
			0.0,
			-half + (float(cz) + rng.randf()) * cell
		)
		p.x = clampf(p.x, -half, half)
		p.z = clampf(p.z, -half, half)
		if p.length() < clear_radius:
			continue
		if _blocked(p, 3.5) or _too_steep_or_peak(p):
			continue
		# Light thin-out only ? old 8% skip + coarse grid emptied the playable center.
		if rng.randf() < 0.03:
			continue
		if _try_accept_spaced(p, grid, spacing):
			positions.append(_stamp_height(p))

	var attempts := 0
	var max_attempts := mini(count * 20, 60000)
	while positions.size() < count and attempts < max_attempts:
		attempts += 1
		var p2 := Vector3(rng.randf_range(-half, half), 0.0, rng.randf_range(-half, half))
		if p2.length() < clear_radius or _blocked(p2, 3.5) or _too_steep_or_peak(p2):
			continue
		if _try_accept_spaced(p2, grid, spacing * 0.9):
			positions.append(_stamp_height(p2))
	return positions


func _try_accept_spaced(p: Vector3, grid: Dictionary, min_dist: float) -> bool:
	var cell := maxf(min_dist, 0.5)
	var cx := floori(p.x / cell)
	var cz := floori(p.z / cell)
	var min2 := min_dist * min_dist
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var key := Vector2i(cx + dx, cz + dz)
			if not grid.has(key):
				continue
			var bucket: Array = grid[key]
			for q in bucket:
				var dx2: float = p.x - q.x
				var dz2: float = p.z - q.y
				if dx2 * dx2 + dz2 * dz2 < min2:
					return false
	var home := Vector2i(cx, cz)
	if not grid.has(home):
		grid[home] = []
	(grid[home] as Array).append(Vector2(p.x, p.z))
	return true


func _too_steep_or_peak(p: Vector3) -> bool:
	# Keep tree line below rocky summits; only skip truly steep faces (old 4.2 wiped foothills).
	var h := _height_at(p.x, p.z)
	if h > mountain_height * 0.70:
		return true
	var step := 2.5
	var hx := absf(_height_at(p.x + step, p.z) - _height_at(p.x - step, p.z))
	var hz := absf(_height_at(p.x, p.z + step) - _height_at(p.x, p.z - step))
	return maxf(hx, hz) > 7.0


func _setup_road_paths() -> void:
	_road_paths.clear()
	var extent := terrain_size * 0.5 - 20.0
	# Fewer, stronger bends so circular fillets are obvious from a distance.
	var main: Array[Vector3] = [
		Vector3(0.0, 0.0, -extent),
		Vector3(0.0, 0.0, -280.0),
		Vector3(70.0, 0.0, -160.0),
		Vector3(0.0, 0.0, 0.0),
		Vector3(-70.0, 0.0, 160.0),
		Vector3(0.0, 0.0, 300.0),
		Vector3(0.0, 0.0, extent),
	]
	var cross: Array[Vector3] = [
		Vector3(-extent, 0.0, 0.0),
		Vector3(-300.0, 0.0, 0.0),
		Vector3(-140.0, 0.0, 55.0),
		Vector3(0.0, 0.0, 0.0),
		Vector3(140.0, 0.0, -55.0),
		Vector3(300.0, 0.0, 0.0),
		Vector3(extent, 0.0, 0.0),
	]
	var spur: Array[Vector3] = [
		Vector3(-70.0, 0.0, 160.0),
		Vector3(40.0, 0.0, 210.0),
		Vector3(140.0, 0.0, 250.0),
		Vector3(220.0, 0.0, 280.0),
	]
	# Large corner radii so bends read as highway arcs, not kinks.
	var arc_r := maxf(road_width * 8.0, 70.0)
	_road_paths.append(_fillet_polyline_arcs(main, arc_r))
	_road_paths.append(_fillet_polyline_arcs(cross, arc_r))
	_road_paths.append(_fillet_polyline_arcs(spur, arc_r * 0.75))


func _is_road_junction_node(p: Vector3) -> bool:
	# True intersections stay sharp so traffic lights can align to real arms.
	for hub in _road_intersection_hubs():
		if Vector2(p.x - hub.x, p.z - hub.z).length() < 0.75:
			return true
	return false


## Replace sharp polyline kinks with circular-arc fillets, then densify finely.
func _fillet_polyline_arcs(points: Array[Vector3], radius: float) -> Array[Vector3]:
	if points.size() < 3:
		return points.duplicate()
	var out: Array[Vector3] = []
	out.append(points[0])
	for i in range(1, points.size() - 1):
		var a: Vector3 = points[i - 1]
		var b: Vector3 = points[i]
		var c: Vector3 = points[i + 1]
		# Keep junction waypoints — filleting them floated hubs off the asphalt.
		if _is_road_junction_node(b):
			out.append(b)
			continue
		var d0 := Vector2(b.x - a.x, b.z - a.z)
		var d1 := Vector2(c.x - b.x, c.z - b.z)
		var len0 := d0.length()
		var len1 := d1.length()
		if len0 < 1.0 or len1 < 1.0:
			out.append(b)
			continue
		d0 /= len0
		d1 /= len1
		var dot := clampf(d0.dot(d1), -1.0, 1.0)
		var turn := acos(dot)
		# Nearly straight — keep the control point.
		if turn < deg_to_rad(4.0):
			out.append(b)
			continue
		# Cross sign in XZ: >0 means left turn when traveling a→b→c.
		var cross_s := d0.x * d1.y - d0.y * d1.x
		var tan_half := tan(turn * 0.5)
		if absf(tan_half) < 0.001:
			out.append(b)
			continue
		# Use most of the shorter arm so arcs stay large and obvious.
		var max_tang := mini(len0, len1) * 0.48
		var tang := radius * tan_half
		var r := radius
		if tang > max_tang:
			tang = max_tang
			r = tang / tan_half
		if r < road_width * 2.0:
			out.append(b)
			continue
		var t1 := Vector2(b.x, b.z) - d0 * tang
		var t2 := Vector2(b.x, b.z) + d1 * tang
		# Inward normal from incoming direction.
		var n0 := Vector2(-d0.y, d0.x)
		if cross_s < 0.0:
			n0 = -n0
		var center := t1 + n0 * r
		var ang0 := atan2(t1.y - center.y, t1.x - center.x)
		var ang1 := atan2(t2.y - center.y, t2.x - center.x)
		var delta := ang1 - ang0
		# Sweep the short arc matching the turn direction.
		if cross_s > 0.0:
			while delta <= 0.0:
				delta += TAU
			while delta > PI + 0.01:
				delta -= TAU
		else:
			while delta >= 0.0:
				delta -= TAU
			while delta < -(PI + 0.01):
				delta += TAU
		# Fine arc samples so ribbons stay round before densify.
		var arc_len := absf(delta) * r
		var steps := maxi(int(ceil(arc_len / 3.0)), 12)
		out.append(Vector3(t1.x, 0.0, t1.y))
		for s in range(1, steps):
			var ang := ang0 + delta * (float(s) / float(steps))
			out.append(Vector3(center.x + cos(ang) * r, 0.0, center.y + sin(ang) * r))
		out.append(Vector3(t2.x, 0.0, t2.y))
	out.append(points[points.size() - 1])
	# Medium polyline for blocking queries; road meshes densify further.
	return _densify_polyline(out, 6.0)


func _densify_polyline(points: Array[Vector3], spacing: float) -> Array[Vector3]:
	if points.size() < 2:
		return points.duplicate()
	var out: Array[Vector3] = []
	out.append(points[0])
	for i in range(points.size() - 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var dist := Vector2(b.x - a.x, b.z - a.z).length()
		var n := maxi(int(floor(dist / maxf(spacing, 1.0))), 1)
		for s in range(1, n):
			var t := float(s) / float(n)
			out.append(a.lerp(b, t))
		out.append(b)
	return out


func _path_total_length(path: Array) -> float:
	var total := 0.0
	for i in range(path.size() - 1):
		var a: Vector3 = path[i]
		var b: Vector3 = path[i + 1]
		total += Vector2(b.x - a.x, b.z - a.z).length()
	return total


## Sample a polyline by arc length. Returns { "pos": Vector2, "dir": Vector2 }.
func _sample_path_at(path: Array, dist: float) -> Dictionary:
	var remain := maxf(dist, 0.0)
	for i in range(path.size() - 1):
		var a: Vector3 = path[i]
		var b: Vector3 = path[i + 1]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var seg := ab.length()
		if seg < 0.0001:
			continue
		if remain <= seg or i == path.size() - 2:
			var t := clampf(remain / seg, 0.0, 1.0)
			return {
				"pos": Vector2(a.x, a.z) + ab * t,
				"dir": ab / seg,
			}
		remain -= seg
	var last: Vector3 = path[path.size() - 1]
	return {"pos": Vector2(last.x, last.z), "dir": Vector2(0.0, 1.0)}


func _road_intersection_hubs() -> Array[Vector3]:
	# True junctions only (not polyline kinks).
	return [
		Vector3(0.0, 0.0, 0.0), # main × cross
		Vector3(-70.0, 0.0, 160.0), # main × spur
	]


func _near_crossing(x: float, z: float, radius: float) -> bool:
	# Keep center dashes clear of the junction box.
	var clear := radius + road_width * 0.75 + 3.5
	for hub in _road_intersection_hubs():
		if Vector2(x - hub.x, z - hub.z).length() < clear:
			return true
	return false


func _path_closest_arc_s(path: Array, hub: Vector3) -> Dictionary:
	# { "s": arc length, "dist": planar distance to hub }
	var hub2 := Vector2(hub.x, hub.z)
	var best_d := 1.0e20
	var best_s := 0.0
	var walked := 0.0
	for i in range(path.size() - 1):
		var a: Vector3 = path[i]
		var b: Vector3 = path[i + 1]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var seg := ab.length()
		if seg < 0.0001:
			continue
		var t := clampf(Vector2(hub2.x - a.x, hub2.y - a.z).dot(ab) / (seg * seg), 0.0, 1.0)
		var closest := Vector2(a.x, a.z) + ab * t
		var d := closest.distance_to(hub2)
		if d < best_d:
			best_d = d
			best_s = walked + seg * t
		walked += seg
	return {"s": best_s, "dist": best_d}


func _intersection_approaches(hub: Vector3) -> Array[Dictionary]:
	# One entry per road arm: centerline stop-line + inbound tangent (toward hub).
	var hub2 := Vector2(hub.x, hub.z)
	var stop_r := road_width * 0.5 + 4.0
	var approaches: Array[Dictionary] = []
	for path in _road_paths:
		var total := _path_total_length(path)
		if total < stop_r * 2.0:
			continue
		var near: Dictionary = _path_closest_arc_s(path, hub)
		if float(near["dist"]) > road_width * 0.65:
			continue
		var hub_s: float = near["s"]
		for sign in [-1.0, 1.0]:
			var s2: float = hub_s + float(sign) * stop_r
			if s2 < 1.0 or s2 > total - 1.0:
				continue
			var info: Dictionary = _sample_path_at(path, s2)
			var pos: Vector2 = info["pos"]
			var tangent: Vector2 = info["dir"]
			# Inbound = toward the junction.
			var to_hub := hub2 - pos
			if to_hub.length_squared() < 0.01:
				continue
			if tangent.dot(to_hub) < 0.0:
				tangent = -tangent
			tangent = tangent.normalized()
			var duplicate := false
			for existing in approaches:
				var ep: Vector2 = existing["pos"]
				if ep.distance_to(pos) < road_width * 0.75:
					duplicate = true
					break
				var ed: Vector2 = existing["along"]
				if ed.dot(tangent) > 0.92 and ep.distance_to(pos) < stop_r * 0.85:
					duplicate = true
					break
			if duplicate:
				continue
			# Right shoulder relative to inbound traffic.
			var right := Vector2(tangent.y, -tangent.x)
			approaches.append({
				"pos": pos,
				"along": tangent,
				"right": right,
			})
	return approaches


func _build_road_markings() -> void:
	# Thin height-sampled decals: yellow dashed center line.
	var root := Node3D.new()
	root.name = "RoadMarkings"
	add_child(root)

	var dash_mat := _make_mat(Color(0.95, 0.90, 0.35), 0.72)
	dash_mat.grow = true
	dash_mat.grow_amount = 0.012

	const DASH_LEN := 3.2
	const DASH_GAP := 4.2
	const DASH_W := 0.28
	# Sit just above the painted terrain asphalt (no overlay ribbon to clear).
	const LIFT := 0.04
	const SKIP_NEAR_CROSSING := 10.0

	# Walk each whole path by arc length — never restart per short densified segment
	# (that was stacking angled dashes into yellow diamonds at bends).
	for path in _road_paths:
		var total := _path_total_length(path)
		if total < DASH_LEN * 2.0:
			continue
		var traveled := DASH_GAP * 0.5
		while traveled + DASH_LEN < total:
			var mid_s := traveled + DASH_LEN * 0.5
			var mid_info: Dictionary = _sample_path_at(path, mid_s)
			var mid_xz: Vector2 = mid_info["pos"]
			var abn: Vector2 = mid_info["dir"]
			traveled += DASH_LEN + DASH_GAP
			if _near_crossing(mid_xz.x, mid_xz.y, SKIP_NEAR_CROSSING):
				continue
			var p0_info: Dictionary = _sample_path_at(path, mid_s - DASH_LEN * 0.5)
			var p1_info: Dictionary = _sample_path_at(path, mid_s + DASH_LEN * 0.5)
			var p0: Vector2 = p0_info["pos"]
			var p1: Vector2 = p1_info["pos"]
			var h0 := _height_at(p0.x, p0.y)
			var h1 := _height_at(p1.x, p1.y)
			var hm := _height_at(mid_xz.x, mid_xz.y)
			var pitch := -atan2(h1 - h0, DASH_LEN)
			var yaw := atan2(abn.x, abn.y)

			var dash := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(DASH_W, 0.01, DASH_LEN)
			dash.mesh = box
			dash.material_override = dash_mat
			dash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			dash.position = Vector3(mid_xz.x, hm + LIFT, mid_xz.y)
			dash.rotation = Vector3(pitch, yaw, 0.0)
			root.add_child(dash)


func _build_traffic_lights() -> void:
	var mesh := _load_glb_mesh("res://assets/kenney_roads/traffic-light.glb")
	if mesh == null:
		push_warning("Traffic light model missing")
		return
	var tex := _load_kenney_texture("res://assets/kenney_roads/Textures/colormap.png")
	if tex != null:
		for si in mesh.get_surface_count():
			var base := mesh.surface_get_material(si)
			var mat: StandardMaterial3D
			if base is StandardMaterial3D:
				mat = (base as StandardMaterial3D).duplicate() as StandardMaterial3D
			else:
				mat = StandardMaterial3D.new()
			mat.albedo_texture = tex
			mat.albedo_color = Color(1, 1, 1)
			mat.roughness = 0.85
			mesh.surface_set_material(si, mat)

	var aabb := mesh.get_aabb()
	var native_h := maxf(aabb.size.y, 0.5)
	var target_h := 4.2
	var s := target_h / native_h
	var y_off := -aabb.position.y * s

	var root := Node3D.new()
	root.name = "TrafficLights"
	add_child(root)

	# One light per approach, on the right shoulder at the stop line, facing traffic.
	var half := road_width * 0.5
	var idx := 0
	for hub in _road_intersection_hubs():
		for approach in _intersection_approaches(hub):
			var pos: Vector2 = approach["pos"]
			var along: Vector2 = approach["along"] # inbound
			var right: Vector2 = approach["right"]
			# Right of the stop line, then push off any overlapping arm's asphalt.
			var xz := _push_off_road(pos + right * (half + 0.6), 1.7)
			# Face oncoming cars (look outbound).
			var face := -along
			var yaw := atan2(face.x, face.y)
			var h := _height_at(xz.x, xz.y)

			var light := Node3D.new()
			light.name = "TrafficLight_%d" % idx
			light.position = Vector3(xz.x, h + 0.02, xz.y)
			light.rotation.y = yaw
			root.add_child(light)

			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.position = Vector3(0.0, y_off, 0.0)
			mi.scale = Vector3(s, s, s)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			light.add_child(mi)

			_add_traffic_bulb(light, Vector3(0.0, target_h * 0.72, 0.35), Color(1.0, 0.2, 0.08))
			_add_traffic_bulb(light, Vector3(0.0, target_h * 0.58, 0.35), Color(1.0, 0.78, 0.12))
			_add_traffic_bulb(light, Vector3(0.0, target_h * 0.44, 0.35), Color(0.2, 1.0, 0.28))
			idx += 1


func _add_traffic_bulb(parent: Node3D, local_pos: Vector3, color: Color) -> void:
	var bulb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	bulb.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.4
	bulb.material_override = mat
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bulb.position = local_pos
	parent.add_child(bulb)


func _place_pond_data() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 3
	_ponds.clear()

	var preset: Array[Vector3] = [
		Vector3(55.0, 18.0, -70.0),
		Vector3(-65.0, 16.0, 90.0),
		Vector3(200.0, 22.0, 300.0),
		Vector3(-180.0, 15.0, -220.0),
	]
	for preset_pond in preset:
		if not _inside_road(Vector3(preset_pond.x, 0.0, preset_pond.z), preset_pond.y + 6.0):
			_ponds.append(preset_pond)

	var half := terrain_size * 0.5 - 40.0
	var attempts := 0
	while _ponds.size() < pond_count and attempts < pond_count * 80:
		attempts += 1
		var center := Vector3(rng.randf_range(-half, half), 0.0, rng.randf_range(-half, half))
		if center.length() < 30.0:
			continue
		var radius := rng.randf_range(12.0, 28.0)
		if _inside_road(center, radius + 8.0):
			continue
		var ok := true
		for existing in _ponds:
			var dist := Vector2(center.x - existing.x, center.z - existing.z).length()
			if dist < radius + existing.y + 18.0:
				ok = false
				break
		if not ok:
			continue
		_ponds.append(Vector3(center.x, radius, center.z))


func _build_pond_meshes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 3

	var water_mat := _make_mat(Color(0.18, 0.42, 0.55, 0.78), 0.12)
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_mat.metallic = 0.35
	water_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var depth_mat := _make_mat(Color(0.10, 0.28, 0.38, 1.0), 0.95)
	var shore_mat := _make_mat(Color(0.42, 0.38, 0.28), 0.98)

	for pond_i in _ponds.size():
		var pond: Vector3 = _ponds[pond_i]
		var center := _stamp_height(Vector3(pond.x, 0.0, pond.z))
		var radius: float = pond.y

		var pond_root := Node3D.new()
		pond_root.name = "Pond_%d" % (pond_i + 1)
		pond_root.position = center
		add_child(pond_root)

		var bed := MeshInstance3D.new()
		var bed_mesh := CylinderMesh.new()
		bed_mesh.top_radius = radius * 1.05
		bed_mesh.bottom_radius = radius * 1.05
		bed_mesh.height = 0.08
		bed_mesh.radial_segments = 24
		bed.mesh = bed_mesh
		bed.position.y = 0.02
		bed.material_override = depth_mat
		pond_root.add_child(bed)

		var water := MeshInstance3D.new()
		var water_mesh := CylinderMesh.new()
		water_mesh.top_radius = radius
		water_mesh.bottom_radius = radius
		water_mesh.height = 0.12
		water_mesh.radial_segments = 28
		water.mesh = water_mesh
		water.position.y = 0.08
		water.scale = Vector3(rng.randf_range(0.92, 1.08), 1.0, rng.randf_range(0.85, 1.12))
		water.material_override = water_mat
		pond_root.add_child(water)

		var shore := MeshInstance3D.new()
		var shore_mesh := CylinderMesh.new()
		shore_mesh.top_radius = radius * 1.22
		shore_mesh.bottom_radius = radius * 1.22
		shore_mesh.height = 0.06
		shore_mesh.radial_segments = 24
		shore.mesh = shore_mesh
		shore.position.y = 0.01
		shore.material_override = shore_mat
		pond_root.add_child(shore)

		# Tall solid volume: player sticks to terrain Y, so only XZ blockers keep them off water.
		var body := StaticBody3D.new()
		body.name = "WaterBlocker"
		body.collision_layer = 1
		body.collision_mask = 0
		var col := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = radius * 0.98
		shape.height = 4.0
		col.shape = shape
		col.position.y = 1.6
		body.add_child(col)
		pond_root.add_child(body)

		_scatter_shore_rocks(pond_root, radius, rng)


func _make_mat(color: Color, roughness: float = 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m


func _bake_road_mask() -> ImageTexture:
	# Distance field to road centerlines. Shader thresholds with fwidth → crisp curb, no mask pixel毛边.
	var res := 4096
	var dist_scale := 14.0
	var buf := PackedFloat32Array()
	buf.resize(res * res)
	buf.fill(1.0)
	var reach := road_width * 0.5 + 2.8
	for path in _road_paths:
		var dense: Array[Vector3] = _densify_polyline(path, 1.5)
		for i in range(dense.size() - 1):
			_stamp_road_segment_distance(buf, res, dense[i], dense[i + 1], reach, dist_scale)
	var img := Image.create_from_data(res, res, false, Image.FORMAT_RF, buf.to_byte_array())
	return ImageTexture.create_from_image(img)


func _stamp_road_segment_distance(
	buf: PackedFloat32Array, res: int, a: Vector3, b: Vector3, reach: float, dist_scale: float
) -> void:
	var half := terrain_size * 0.5
	var min_x := minf(a.x, b.x) - reach
	var max_x := maxf(a.x, b.x) + reach
	var min_z := minf(a.z, b.z) - reach
	var max_z := maxf(a.z, b.z) + reach
	var x0 := clampi(int(floor((min_x + half) / terrain_size * float(res))), 0, res - 1)
	var x1 := clampi(int(ceil((max_x + half) / terrain_size * float(res))), 0, res - 1)
	var z0 := clampi(int(floor((min_z + half) / terrain_size * float(res))), 0, res - 1)
	var z1 := clampi(int(ceil((max_z + half) / terrain_size * float(res))), 0, res - 1)
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ab_len2 := ab.length_squared()
	for zi in range(z0, z1 + 1):
		for xi in range(x0, x1 + 1):
			var sx := -half + (float(xi) + 0.5) / float(res) * terrain_size
			var sz := -half + (float(zi) + 0.5) / float(res) * terrain_size
			var d: float
			if ab_len2 < 0.0001:
				d = Vector2(sx - a.x, sz - a.z).length()
			else:
				var t := clampf(Vector2(sx - a.x, sz - a.z).dot(ab) / ab_len2, 0.0, 1.0)
				var closest := Vector2(a.x, a.z) + ab * t
				d = closest.distance_to(Vector2(sx, sz))
			if d > reach:
				continue
			var enc := clampf(d / dist_scale, 0.0, 1.0)
			var idx := zi * res + xi
			if enc < buf[idx]:
				buf[idx] = enc


func _make_ground_material() -> ShaderMaterial:
	# Grass/dirt + road SDF (world XZ). Edges use screen-space AA so the curb stays sharp.
	var pack := _make_ground_texture_pack()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D ground_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D ground_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D road_sdf : hint_default_white, filter_linear, repeat_disable;
uniform float normal_scale = 1.15;
uniform float world_size = 1000.0;
uniform float dist_scale = 14.0;
uniform float half_width = 5.0;
uniform float curb_extra = 0.18;
uniform float shoulder_extra = 0.5;
uniform vec3 asphalt_color : source_color = vec3(0.12, 0.12, 0.14);
uniform vec3 curb_color : source_color = vec3(0.08, 0.08, 0.09);
uniform vec3 shoulder_color : source_color = vec3(0.48, 0.43, 0.32);
uniform float detail_scale = 4.0;

varying vec2 road_uv;

void vertex() {
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	road_uv = vec2(wpos.x / world_size + 0.5, wpos.z / world_size + 0.5);
}

void fragment() {
	vec3 near_c = texture(ground_tex, UV).rgb;
	vec3 far_c = texture(ground_tex, UV * detail_scale).rgb;
	vec3 ground = mix(near_c, far_c, 0.35);

	vec3 n_near = texture(ground_normal, UV).rgb;
	vec3 n_far = texture(ground_normal, UV * detail_scale).rgb;
	NORMAL_MAP = mix(n_near, n_far, 0.4);
	NORMAL_MAP_DEPTH = normal_scale;

	vec2 ru = clamp(road_uv, vec2(0.0), vec2(1.0));
	float d = texture(road_sdf, ru).r * dist_scale;
	// Screen-space AA: edge width tracks pixel size → no low-res mask stair-steps.
	float aa = max(fwidth(d) * 1.1, 0.015);
	float shoulder_r = half_width + shoulder_extra;
	float curb_r = half_width + curb_extra;
	float shoulder = 1.0 - smoothstep(shoulder_r - aa, shoulder_r + aa, d);
	float curb = 1.0 - smoothstep(curb_r - aa, curb_r + aa, d);
	float road = 1.0 - smoothstep(half_width - aa, half_width + aa, d);

	vec3 albedo = ground;
	albedo = mix(albedo, shoulder_color, clamp(shoulder, 0.0, 1.0));
	albedo = mix(albedo, curb_color, clamp(curb, 0.0, 1.0));
	albedo = mix(albedo, asphalt_color, clamp(road, 0.0, 1.0));
	ALBEDO = albedo;
	ROUGHNESS = mix(0.94, 0.72, max(road, max(curb, shoulder * 0.5)));
	METALLIC = 0.0;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("ground_tex", pack["albedo"])
	mat.set_shader_parameter("ground_normal", pack["normal"])
	mat.set_shader_parameter("road_sdf", _road_mask_tex)
	mat.set_shader_parameter("normal_scale", 1.2)
	mat.set_shader_parameter("detail_scale", 3.5)
	mat.set_shader_parameter("world_size", terrain_size)
	mat.set_shader_parameter("dist_scale", 14.0)
	mat.set_shader_parameter("half_width", road_width * 0.5)
	mat.set_shader_parameter("curb_extra", 0.18)
	mat.set_shader_parameter("shoulder_extra", 0.5)
	mat.set_shader_parameter("asphalt_color", Color(0.12, 0.12, 0.14))
	mat.set_shader_parameter("curb_color", Color(0.08, 0.08, 0.09))
	mat.set_shader_parameter("shoulder_color", Color(0.48, 0.43, 0.32))
	return mat


func _make_ground_texture_pack() -> Dictionary:
	# Procedural soil + grass clumps (seamless) — looks like ground, not flat green plastic.
	var size := 512
	var albedo := Image.create(size, size, false, Image.FORMAT_RGB8)
	var height := Image.create(size, size, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 501

	var n_soil := FastNoiseLite.new()
	n_soil.seed = seed_value + 11
	n_soil.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_soil.frequency = 0.035
	n_soil.fractal_type = FastNoiseLite.FRACTAL_FBM
	n_soil.fractal_octaves = 5

	var n_clump := FastNoiseLite.new()
	n_clump.seed = seed_value + 29
	n_clump.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_clump.frequency = 0.09
	n_clump.fractal_octaves = 3

	var n_blade := FastNoiseLite.new()
	n_blade.seed = seed_value + 47
	n_blade.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n_blade.frequency = 0.45
	n_blade.fractal_octaves = 2

	var n_dry := FastNoiseLite.new()
	n_dry.seed = seed_value + 73
	n_dry.frequency = 0.02
	n_dry.fractal_octaves = 3

	var soil_dark := Color(0.22, 0.16, 0.10)
	var soil_mid := Color(0.34, 0.26, 0.16)
	var grass_dark := Color(0.16, 0.34, 0.14)
	var grass_mid := Color(0.28, 0.52, 0.22)
	var grass_lit := Color(0.40, 0.62, 0.28)
	var grass_dry := Color(0.48, 0.50, 0.24)

	for y in size:
		for x in size:
			var fx := float(x)
			var fy := float(y)
			var soil_n := n_soil.get_noise_2d(fx, fy) * 0.5 + 0.5
			var clump := n_clump.get_noise_2d(fx, fy) * 0.5 + 0.5
			var blade := n_blade.get_noise_2d(fx, fy * 0.35) * 0.5 + 0.5
			var dry := n_dry.get_noise_2d(fx, fy) * 0.5 + 0.5

			var soil: Color = soil_dark.lerp(soil_mid, soil_n)
			var grass: Color = grass_dark.lerp(grass_mid, clump)
			grass = grass.lerp(grass_lit, blade * 0.55)
			grass = grass.lerp(grass_dry, dry * 0.35)

			# More grass where clumps are high; soil shows in worn/dry patches.
			var cover := clampf(0.35 + clump * 0.55 - dry * 0.25, 0.15, 0.95)
			var col: Color = soil.lerp(grass, cover)

			# Tiny pebble / debris speckles.
			if rng.randf() > 0.985:
				col = col.lerp(Color(0.45, 0.42, 0.38), 0.55)
			elif rng.randf() > 0.992:
				col = col.darkened(0.12)

			albedo.set_pixel(x, y, col)

			# Height for normals: soil pits + grass loft.
			var h := soil_n * 0.25 + clump * 0.45 + blade * 0.35 - dry * 0.15
			height.set_pixel(x, y, Color(h, h, h))

	var normal := _height_to_normal_map(height, 5.5)
	albedo.generate_mipmaps()
	normal.generate_mipmaps()
	return {
		"albedo": ImageTexture.create_from_image(albedo),
		"normal": ImageTexture.create_from_image(normal),
	}


func _height_to_normal_map(height_img: Image, strength: float) -> Image:
	var w := height_img.get_width()
	var h := height_img.get_height()
	var out := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var xl := (x - 1 + w) % w
			var xr := (x + 1) % w
			var yd := (y - 1 + h) % h
			var yu := (y + 1) % h
			var dx := (height_img.get_pixel(xl, y).r - height_img.get_pixel(xr, y).r) * strength
			var dy := (height_img.get_pixel(x, yd).r - height_img.get_pixel(x, yu).r) * strength
			var n := Vector3(dx, dy, 1.0).normalized()
			out.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	return out


func _prepare_grass_chunks() -> void:
	## Deprecated: grass is generated lazily in ensure_chunk_grass().
	pass


func _make_multimesh(name: String, mesh: Mesh, count: int, mat: Material) -> MultiMeshInstance3D:
	var mi := MultiMeshInstance3D.new()
	mi.name = name
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = maxi(count, 0)
	mi.multimesh = mm
	mi.material_override = mat
	add_child(mi)
	return mi


func _add_cylinder_body(parent: Node, origin: Vector3, radius: float, height: float) -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = maxf(radius, 0.08)
	shape.height = maxf(height, 0.3)
	col.shape = shape
	col.position = origin + Vector3(0.0, shape.height * 0.5, 0.0)
	body.add_child(col)
	parent.add_child(body)


func _add_box_body(parent: Node, origin: Vector3, size: Vector3, yaw: float = 0.0) -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = origin
	col.rotation.y = yaw
	body.add_child(col)
	parent.add_child(body)


func _add_sphere_body(parent: Node, origin: Vector3, radius: float) -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = maxf(radius, 0.2)
	col.shape = shape
	col.position = origin
	body.add_child(col)
	parent.add_child(body)


func _place_house_sites() -> void:
	_house_pads.clear()
	# Guaranteed houses near spawn / crossroads so you can see them immediately.
	var near_spawn: Array[Vector3] = [
		Vector3(42.0, 0.0, 30.0),
		Vector3(-46.0, 0.0, 34.0),
		Vector3(40.0, 0.0, -50.0),
		Vector3(-44.0, 0.0, -46.0),
		Vector3(62.0, 0.0, -6.0),
		Vector3(-64.0, 0.0, 8.0),
	]
	for p in near_spawn:
		if _inside_pond(p, 20.0) or _inside_road(p, 8.0):
			continue
		_house_pads.append(Vector3(p.x, 18.0, p.z))

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 77
	var attempts := 0
	while _house_pads.size() < house_count and attempts < house_count * 200:
		attempts += 1
		var p := _sample_roadside_point(rng)
		if p.x > 1.0e20:
			continue
		if p.length() < 70.0:
			continue
		if _inside_pond(p, 22.0) or _inside_road(p, 7.0):
			continue
		var ok := true
		for pad in _house_pads:
			if Vector2(p.x - pad.x, p.z - pad.z).length() < 36.0:
				ok = false
				break
		if not ok:
			continue
		_house_pads.append(Vector3(p.x, 16.0, p.z))


func _sample_roadside_point(rng: RandomNumberGenerator) -> Vector3:
	if _road_paths.is_empty():
		return Vector3(1.0e30, 0.0, 1.0e30)
	var path: Array = _road_paths[rng.randi_range(0, _road_paths.size() - 1)]
	if path.size() < 2:
		return Vector3(1.0e30, 0.0, 1.0e30)
	var i := rng.randi_range(0, path.size() - 2)
	var a: Vector3 = path[i]
	var b: Vector3 = path[i + 1]
	var along: Vector3 = a.lerp(b, rng.randf())
	var ab := Vector2(b.x - a.x, b.z - a.z)
	if ab.length_squared() < 0.01:
		return Vector3(1.0e30, 0.0, 1.0e30)
	var side := Vector2(-ab.y, ab.x).normalized()
	if rng.randf() < 0.5:
		side = -side
	var dist := road_width * 0.5 + rng.randf_range(9.0, 20.0)
	return Vector3(along.x + side.x * dist, 0.0, along.z + side.y * dist)


func _nearest_road_direction(p: Vector3) -> float:
	# Yaw so the house faces toward the nearest road segment.
	var best_d := 1.0e20
	var face := Vector2(0.0, -1.0)
	for path in _road_paths:
		for i in range(path.size() - 1):
			var a: Vector3 = path[i]
			var b: Vector3 = path[i + 1]
			var ab := Vector2(b.x - a.x, b.z - a.z)
			var ap := Vector2(p.x - a.x, p.z - a.z)
			var ab_len2 := ab.length_squared()
			if ab_len2 < 0.0001:
				continue
			var t := clampf(ap.dot(ab) / ab_len2, 0.0, 1.0)
			var closest := Vector2(a.x, a.z) + ab * t
			var d := closest.distance_to(Vector2(p.x, p.z))
			if d < best_d:
				best_d = d
				face = (closest - Vector2(p.x, p.z)).normalized()
	return atan2(face.x, face.y)


func _build_houses() -> void:
	_house_map_footprints.clear()
	if _house_pads.is_empty():
		return
	var meshes: Array[Mesh] = []
	var letters := "abcdefghijklmnopqrstu"
	for i in mini(house_count, letters.length()):
		var path := "res://assets/kenney_houses/building-type-%s.glb" % letters[i]
		var mesh := _load_glb_mesh(path)
		if mesh != null:
			meshes.append(mesh)
	if meshes.is_empty():
		push_warning("No Kenney house models loaded")
		return

	var root := Node3D.new()
	root.name = "Houses"
	add_child(root)

	var house_script := load("res://scripts/house_enterable.gd") as Script
	var house_tex := _load_kenney_texture("res://assets/kenney_houses/Textures/colormap.png")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 91
	for i in _house_pads.size():
		var pad: Vector3 = _house_pads[i]
		var mesh: Mesh = meshes[i % meshes.size()].duplicate()
		if house_tex != null:
			for si in mesh.get_surface_count():
				var base := mesh.surface_get_material(si)
				var mat: StandardMaterial3D
				if base is StandardMaterial3D:
					mat = (base as StandardMaterial3D).duplicate() as StandardMaterial3D
				else:
					mat = StandardMaterial3D.new()
				mat.albedo_texture = house_tex
				mat.albedo_color = Color(1, 1, 1)
				mat.cull_mode = BaseMaterial3D.CULL_BACK
				mat.metallic = 0.0
				mat.roughness = 0.9
				mesh.surface_set_material(si, mat)
		var aabb := mesh.get_aabb()
		var native_h := maxf(aabb.size.y, 0.3)
		var target_h := rng.randf_range(8.5, 12.0)
		var s := target_h / native_h
		var yaw := _nearest_road_direction(Vector3(pad.x, 0.0, pad.z))
		var y := _height_at(pad.x, pad.z) + 0.04
		var y_off := -aabb.position.y * s
		var size := Vector3(aabb.size.x * s, aabb.size.y * s, aabb.size.z * s)
		_house_map_footprints.append({
			"x": pad.x,
			"z": pad.z,
			"sx": size.x,
			"sz": size.z,
			"yaw": yaw,
			"circle": false,
		})

		var house := Node3D.new()
		house.name = "House_%d" % i
		house.set_script(house_script)
		house.position = Vector3(pad.x, y, pad.z)
		house.rotation.y = yaw
		root.add_child(house)

		var mi := MeshInstance3D.new()
		mi.name = "Exterior"
		mi.mesh = mesh
		mi.position = Vector3(0.0, y_off, 0.0)
		mi.scale = Vector3(s, s, s)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.visibility_range_end = 0.0
		house.add_child(mi)

		# Collision in unscaled space via shape scale — matches mesh without oversized AABB boxes.
		var body := StaticBody3D.new()
		body.name = "ExteriorBody"
		body.collision_layer = 1
		body.position = Vector3(0.0, y_off, 0.0)
		var col := CollisionShape3D.new()
		var tri := mesh.create_trimesh_shape()
		if tri != null:
			col.shape = tri
			col.scale = Vector3(s, s, s)
		else:
			var fallback := BoxShape3D.new()
			fallback.size = Vector3(aabb.size.x * s * 0.9, aabb.size.y * s, aabb.size.z * s * 0.9)
			col.shape = fallback
			col.position = Vector3(0.0, aabb.size.y * s * 0.5, 0.0)
		body.add_child(col)
		house.add_child(body)

		house.call("configure", mi, body, size, y)


func _prepare_forest_chunks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# Small spawn clearing only ? forest should start just outside the pad.
	var positions := _sample_positions(tree_count, 8.0, 14.0, rng, tree_min_spacing)
	# Guarantee a visible grove around the player (old caches left the center nearly empty).
	_append_near_spawn_trees(positions, rng, 110, 18.0, 150.0, tree_min_spacing * 0.85)
	if positions.is_empty() or _streamer == null:
		return
	print("Forest trees prepared: ", positions.size(), " / ", tree_count)
	await get_tree().process_frame
	_load_tree_meshes()
	if _sm_trees.is_empty():
		push_warning("No Kenney tree models loaded from res://assets/kenney_trees/")
		return
	var native_heights: Array[float] = []
	for mesh in _sm_trees:
		native_heights.append(maxf(mesh.get_aabb().size.y, 0.4))
	for i in positions.size():
		var p: Vector3 = positions[i]
		var t := rng.randi_range(0, _sm_trees.size() - 1)
		var target_h := rng.randf_range(6.5, 14.0)
		var s := target_h / native_heights[t]
		var sxz := s * rng.randf_range(0.82, 1.02)
		var sy := s * rng.randf_range(0.9, 1.2)
		var yaw := rng.randf_range(0.0, TAU)
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3(sxz, sy, sxz))
		var col_h := clampf(target_h * 0.32, 1.2, 4.0)
		var col_r := clampf(0.045 * sxz, 0.1, 0.32)
		_streamer.call("add_tree", Transform3D(basis, p), t, col_r, col_h)
		if i > 0 and i % 400 == 0:
			await get_tree().process_frame


func _append_near_spawn_trees(
	positions: Array[Vector3],
	rng: RandomNumberGenerator,
	extra: int,
	inner_r: float,
	outer_r: float,
	spacing: float
) -> void:
	var grid: Dictionary = {}
	for existing in positions:
		_try_accept_spaced(existing, grid, spacing)
	var attempts := 0
	var added := 0
	while added < extra and attempts < extra * 40:
		attempts += 1
		var ang := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(inner_r, outer_r)
		var p := Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)
		if _blocked(p, 3.0) or _too_steep_or_peak(p):
			continue
		if not _try_accept_spaced(p, grid, spacing):
			continue
		positions.append(_stamp_height(p))
		added += 1


func _scatter_shore_rocks(pond_root: Node3D, radius: float, rng: RandomNumberGenerator) -> void:
	var rock_mat := _make_mat(Color(0.48, 0.46, 0.42), 0.96)
	var count := rng.randi_range(14, 22)
	for i in count:
		var ang := rng.randf_range(0.0, TAU)
		var dist := radius * rng.randf_range(0.95, 1.28)
		var local := Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)
		var s := Vector3(
			rng.randf_range(0.7, 2.4),
			rng.randf_range(0.35, 1.3),
			rng.randf_range(0.7, 2.4)
		)
		var mi := MeshInstance3D.new()
		if rng.randf() < 0.55:
			var sm := SphereMesh.new()
			sm.radius = 1.0
			sm.height = 1.5
			sm.radial_segments = 8
			sm.rings = 4
			mi.mesh = sm
		else:
			var bm := BoxMesh.new()
			bm.size = Vector3(1.6, 1.0, 1.3)
			mi.mesh = bm
		mi.material_override = rock_mat
		mi.position = local + Vector3(0.0, s.y * 0.35, 0.0)
		mi.rotation.y = rng.randf_range(0.0, TAU)
		mi.rotation.x = rng.randf_range(-0.25, 0.25)
		mi.scale = s
		pond_root.add_child(mi)

		var body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(s.x * 0.95, s.y * 0.75, s.z * 0.95)
		col.shape = shape
		col.position = mi.position
		col.rotation = mi.rotation
		body.add_child(col)
		pond_root.add_child(body)


func _prepare_rock_chunks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 7
	if _streamer == null:
		return
	await get_tree().process_frame
	_load_rock_meshes()
	var count := 220
	var positions := _sample_positions(count, 10.0, 12.0, rng, 10.0)
	for i in positions.size():
		var p: Vector3 = positions[i]
		var roll := rng.randf()
		var k := 0
		if roll < 0.45:
			k = 0
		elif roll < 0.78:
			k = 1
		else:
			k = 2
		var s: Vector3
		match k:
			0:
				s = Vector3(rng.randf_range(0.7, 2.6), rng.randf_range(0.4, 1.4), rng.randf_range(0.7, 2.6))
			1:
				s = Vector3(rng.randf_range(0.8, 2.8), rng.randf_range(0.45, 1.6), rng.randf_range(0.8, 2.4))
			_:
				s = Vector3(rng.randf_range(0.8, 2.0), rng.randf_range(1.0, 2.8), rng.randf_range(0.8, 2.0))
		var yaw := rng.randf_range(0.0, TAU)
		var basis := Basis(Vector3.UP, yaw)
		basis = basis.rotated(basis.x, rng.randf_range(-0.3, 0.3))
		basis = basis.scaled(s)
		var origin := p + Vector3(0.0, s.y * 0.35, 0.0)
		var col: Dictionary
		match k:
			0:
				col = {"shape": 0, "radius": maxf(s.x, s.z) * 0.5}
			1:
				col = {
					"shape": 1,
					"size": Vector3(1.8 * s.x * 0.85, 1.1 * s.y * 0.8, 1.4 * s.z * 0.85),
					"yaw": yaw,
				}
			_:
				col = {"shape": 0, "radius": maxf(s.x, s.z) * 0.55}
		_streamer.call("add_rock", Transform3D(basis, origin), k, col)


func _prepare_bush_chunks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 99
	if _streamer == null:
		return
	await get_tree().process_frame
	_load_bush_and_flower_meshes()
	var bush_h: Array[float] = []
	for mesh in _sm_bushes:
		bush_h.append(maxf(mesh.get_aabb().size.y, 0.08))
	if _sm_bushes.is_empty():
		push_warning("No Kenney bush models loaded")
		return
	var positions := _sample_positions(420, 5.0, 12.0, rng, 5.0)
	for i in positions.size():
		var p: Vector3 = positions[i]
		var t := rng.randi_range(0, _sm_bushes.size() - 1)
		var target_h := rng.randf_range(0.7, 1.9)
		var s := target_h / bush_h[t]
		var sxz := s * rng.randf_range(0.9, 1.2)
		var yaw := rng.randf_range(0.0, TAU)
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3(sxz, s, sxz))
		_streamer.call("add_bush", Transform3D(basis, p), t, target_h * 0.28)
	await get_tree().process_frame
	var flower_h: Array[float] = []
	for mesh in _sm_flowers:
		flower_h.append(maxf(mesh.get_aabb().size.y, 0.05))
	if _sm_flowers.is_empty():
		return
	var flower_pos := _sample_positions(280, 4.0, 8.0, rng, 4.0)
	for i in flower_pos.size():
		var p: Vector3 = flower_pos[i]
		var t := rng.randi_range(0, _sm_flowers.size() - 1)
		var target_h := rng.randf_range(0.25, 0.55)
		var s := target_h / flower_h[t]
		var yaw := rng.randf_range(0.0, TAU)
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s))
		_streamer.call("add_flower", Transform3D(basis, p), t)


func _animal_target_height(file_name: String, rng: RandomNumberGenerator) -> float:
	match file_name:
		"animal-deer.glb", "animal-cow.glb", "animal-polar.glb", "animal-tiger.glb", "animal-lion.glb":
			return rng.randf_range(1.15, 1.55)
		"animal-hog.glb", "animal-pig.glb", "animal-dog.glb", "animal-fox.glb", "animal-monkey.glb", "animal-panda.glb":
			return rng.randf_range(0.75, 1.15)
		"animal-bunny.glb", "animal-cat.glb", "animal-chick.glb", "animal-beaver.glb", "animal-koala.glb", "animal-penguin.glb":
			return rng.randf_range(0.4, 0.7)
		"animal-bee.glb", "animal-parrot.glb", "animal-crab.glb":
			return rng.randf_range(0.25, 0.45)
		_:
			return rng.randf_range(0.7, 1.2)


## Cache GLB scene templates so each type is parsed once, then duplicated with animations intact.
## feet_y_min includes the lowest animated pose so walk cycles do not sink into the ground.
var _glb_scene_templates: Dictionary = {} # path -> bounds dict + root


func _instantiate_glb_scene(res_path: String) -> Dictionary:
	# Returns { root, native_h, feet_y_min, size_x, size_z } or empty on failure.
	if not _glb_scene_templates.has(res_path):
		var packed := load(res_path) as PackedScene
		if packed == null:
			push_warning("Kenney asset missing: " + res_path)
			return {}
		var loaded := packed.instantiate() as Node3D
		if loaded == null:
			return {}
		_fix_critter_materials(loaded)
		var bounds := _measure_critter_bounds(loaded)
		_glb_scene_templates[res_path] = {
			"root": loaded,
			"native_h": float(bounds["native_h"]),
			"feet_y_min": float(bounds["feet_y_min"]),
			"size_x": float(bounds["size_x"]),
			"size_z": float(bounds["size_z"]),
		}
	var tmpl: Dictionary = _glb_scene_templates[res_path]
	var dup := (tmpl["root"] as Node).duplicate() as Node3D
	return {
		"root": dup,
		"native_h": float(tmpl["native_h"]),
		"feet_y_min": float(tmpl["feet_y_min"]),
		"size_x": float(tmpl["size_x"]),
		"size_z": float(tmpl["size_z"]),
	}


func _measure_critter_bounds(root: Node3D) -> Dictionary:
	var rest := _scene_aabb(root)
	var feet_y := rest.position.y
	var top_y := rest.position.y + rest.size.y
	var size_x := rest.size.x
	var size_z := rest.size.z
	var ap := _find_animation_player_node(root)
	if ap != null:
		var was := ap.current_animation
		for clip_name in ["idle", "walk", "run", "sprint"]:
			if not ap.has_animation(clip_name):
				continue
			var anim := ap.get_animation(clip_name)
			if anim == null or anim.length <= 0.0:
				continue
			ap.play(clip_name)
			var steps := 6
			for step in steps:
				ap.seek(anim.length * float(step) / float(maxi(steps - 1, 1)), true)
				ap.advance(0.0)
				var pose := _scene_aabb(root)
				feet_y = minf(feet_y, pose.position.y)
				top_y = maxf(top_y, pose.position.y + pose.size.y)
				size_x = maxf(size_x, pose.size.x)
				size_z = maxf(size_z, pose.size.z)
		# Restore idle (NOT static/T-pose) so duplicates don't spawn frozen with arms out.
		if ap.has_animation("idle"):
			ap.play("idle")
			ap.seek(0.0, true)
			ap.advance(0.0)
			ap.stop()
		elif was != "" and was != "static":
			ap.play(was)
			ap.seek(0.0, true)
			ap.advance(0.0)
			ap.stop()
		else:
			ap.stop()
	return {
		"native_h": maxf(rest.size.y, 0.15),
		# Prefer rest soles for spawn offset; live snap corrects anim dips.
		"feet_y_min": rest.position.y,
		"size_x": maxf(size_x, 0.2),
		"size_z": maxf(size_z, 0.2),
	}


func _find_animation_player_node(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player_node(child)
		if found != null:
			return found
	return null


func _fix_critter_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(i)
				if mat == null:
					continue
				var fixed := mat.duplicate()
				if fixed is BaseMaterial3D:
					var bm := fixed as BaseMaterial3D
					bm.metallic = 0.0
					bm.roughness = 0.88
				mi.set_surface_override_material(i, fixed)
	for child in node.get_children():
		_fix_critter_materials(child)


func _scene_aabb(node: Node) -> AABB:
	var boxes: Array[AABB] = []
	_collect_mesh_aabbs_local(node, Transform3D.IDENTITY, boxes)
	if boxes.is_empty():
		return AABB(Vector3(-0.4, 0.0, -0.4), Vector3(0.8, 1.0, 0.8))
	var result: AABB = boxes[0]
	for i in range(1, boxes.size()):
		result = result.merge(boxes[i])
	return result


func _collect_mesh_aabbs_local(node: Node, parent_xf: Transform3D, out: Array[AABB]) -> void:
	var xf := parent_xf
	if node is Node3D:
		xf = parent_xf * (node as Node3D).transform
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			out.append(xf * mi.mesh.get_aabb())
	for child in node.get_children():
		_collect_mesh_aabbs_local(child, xf, out)


func stream_spawn_critter(spawn: Dictionary, ai_script: Script) -> Node:
	var res_path := str(spawn.get("path", ""))
	var pos: Vector3 = spawn.get("pos", Vector3.ZERO)
	var target_h := float(spawn.get("height", 1.2))
	var yaw := float(spawn.get("yaw", 0.0))
	var kind := int(spawn.get("kind", 0))
	var file_name := str(spawn.get("name", ""))
	var inst := _instantiate_glb_scene(res_path)
	if inst.is_empty() or inst.get("root") == null:
		return null
	var scene_root: Node3D = inst["root"]
	var native_h: float = float(inst["native_h"])
	var feet_y_min: float = float(inst["feet_y_min"])
	var size_x: float = float(inst["size_x"])
	var size_z: float = float(inst["size_z"])
	var s := target_h / maxf(native_h, 0.05)
	var y_off := -feet_y_min * s
	var body := CharacterBody3D.new()
	body.set_script(ai_script)
	body.position = pos
	body.kind = kind
	body.move_speed = 2.8 if kind == 0 else 2.6
	body.flee_speed = 6.2
	body.chase_speed = 3.8
	body.wander_radius = 14.0 if kind == 0 else 16.0
	body.detect_radius = 18.0
	body.flee_radius = 11.0
	body.lose_radius = 28.0
	if file_name.find("bee") >= 0 or file_name.find("parrot") >= 0:
		body.hover_height = 1.1
		body.move_speed = 3.4
		body.wander_radius = 18.0
	elif file_name.find("ghost") >= 0:
		body.hover_height = 0.55
		body.chase_speed = 2.9
	var col := CollisionShape3D.new()
	var world_x := size_x * s
	var world_z := size_z * s
	var world_h := target_h
	var wide := maxf(world_x, world_z) > world_h * 0.95
	if wide:
		var box := BoxShape3D.new()
		box.size = Vector3(
			clampf(world_x * 0.72, 0.22, 2.8),
			clampf(world_h * 0.72, 0.18, 2.6),
			clampf(world_z * 0.72, 0.22, 2.8)
		)
		col.shape = box
		col.position = Vector3(0.0, box.size.y * 0.5 + 0.02, 0.0)
	else:
		var capsule := CapsuleShape3D.new()
		capsule.radius = clampf(maxf(world_x, world_z) * 0.28, 0.14, 0.85)
		capsule.height = maxf(world_h * 0.92, capsule.radius * 2.05)
		col.shape = capsule
		col.position = Vector3(0.0, capsule.height * 0.5 + 0.02, 0.0)
	body.add_child(col)
	body.home = pos
	body.setup_scene(scene_root, s, y_off, yaw)
	return body


func _prepare_actor_spawns() -> void:
	if _streamer == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 707
	var animal_files := [
		"animal-deer.glb", "animal-fox.glb", "animal-bunny.glb", "animal-hog.glb",
		"animal-bee.glb", "animal-chick.glb", "animal-cat.glb", "animal-dog.glb",
		"animal-cow.glb", "animal-pig.glb", "animal-parrot.glb", "animal-beaver.glb",
		"animal-penguin.glb", "animal-polar.glb", "animal-tiger.glb", "animal-lion.glb",
		"animal-monkey.glb", "animal-panda.glb", "animal-koala.glb", "animal-crab.glb",
	]
	var paths: Array[String] = []
	var names: Array[String] = []
	for file_name in animal_files:
		var res_path := "res://assets/kenney_animals/%s" % file_name
		# Existence check only ? instantiating every model here used to stall load.
		if not ResourceLoader.exists(res_path):
			continue
		paths.append(res_path)
		names.append(file_name)
	_map_actor_markers.clear()
	if not paths.is_empty():
		var positions := _sample_positions_random(animal_count, 6.0, 12.0, rng, 0.0, 0.0, 18.0)
		for i in positions.size():
			var t := rng.randi_range(0, paths.size() - 1)
			var pos: Vector3 = positions[i]
			_streamer.call("add_actor", {
				"id": "animal_%d" % i,
				"kind": 0,
				"path": paths[t],
				"pos": pos,
				"yaw": rng.randf_range(0.0, TAU),
				"height": _animal_target_height(names[t], rng),
				"name": names[t],
			})
			_map_actor_markers.append({"x": pos.x, "z": pos.z, "kind": 0})
	await get_tree().process_frame
	rng.seed = seed_value + 909
	var monster_files := [
		"character-zombie.glb",
		"character-skeleton.glb",
		"character-vampire.glb",
		"character-ghost.glb",
	]
	paths.clear()
	names.clear()
	for file_name in monster_files:
		var res_path := "res://assets/kenney_monsters/%s" % file_name
		if not ResourceLoader.exists(res_path):
			continue
		paths.append(res_path)
		names.append(file_name)
	if paths.is_empty():
		return
	var mpos := _sample_positions_random(monster_count, 8.0, 20.0, rng, 0.0, 0.0, 28.0)
	for i in mpos.size():
		var t := rng.randi_range(0, paths.size() - 1)
		var pos2: Vector3 = mpos[i]
		_streamer.call("add_actor", {
			"id": "monster_%d" % i,
			"kind": 1,
			"path": paths[t],
			"pos": pos2,
			"yaw": rng.randf_range(0.0, TAU),
			"height": rng.randf_range(1.55, 1.95),
			"name": names[t],
		})
		_map_actor_markers.append({"x": pos2.x, "z": pos2.z, "kind": 1})


func _prepare_treasure_spawns() -> void:
	if _streamer == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 515
	# Kenney kits differ in native size; target_height normalizes each to world meters.
	# weight: common food high, rare chests/keys low (mind: high-value is uncommon).
	const BASE := "res://assets/kenney_treasures/"
	var defs: Array[Dictionary] = [
		{"id": "apple", "name": "红苹果", "desc": "新鲜却略显异样的果实", "color": Color(0.85, 0.25, 0.2),
			"mesh": BASE + "food/apple.glb", "h": 0.22, "value": 8, "weight": 14},
		{"id": "banana", "name": "香蕉", "desc": "弯弯的黄色水果", "color": Color(0.92, 0.82, 0.2),
			"mesh": BASE + "food/banana.glb", "h": 0.28, "value": 10, "weight": 12},
		{"id": "avocado", "name": "牛油果", "desc": "软乎乎的绿色果实", "color": Color(0.35, 0.55, 0.22),
			"mesh": BASE + "food/avocado.glb", "h": 0.24, "value": 12, "weight": 10},
		{"id": "bread", "name": "面包", "desc": "还能吃的硬面包", "color": Color(0.78, 0.58, 0.32),
			"mesh": BASE + "food/bread.glb", "h": 0.18, "value": 9, "weight": 12},
		{"id": "cheese", "name": "奶酪", "desc": "带着孔洞的香气奶酪", "color": Color(0.95, 0.82, 0.35),
			"mesh": BASE + "food/cheese.glb", "h": 0.2, "value": 14, "weight": 10},
		{"id": "burger", "name": "汉堡", "desc": "谁把这个丢在林子里了", "color": Color(0.7, 0.45, 0.22),
			"mesh": BASE + "food/burger.glb", "h": 0.22, "value": 18, "weight": 8},
		{"id": "cake", "name": "蛋糕", "desc": "意外完整的甜品", "color": Color(0.95, 0.7, 0.75),
			"mesh": BASE + "food/cake.glb", "h": 0.32, "value": 28, "weight": 5},
		{"id": "fish", "name": "鲜鱼", "desc": "刚上岸的鱼，或许值钱", "color": Color(0.45, 0.65, 0.85),
			"mesh": BASE + "food/fish.glb", "h": 0.26, "value": 35, "weight": 6},
		{"id": "pot", "name": "陶罐", "desc": "空空的陶罐，可是好看", "color": Color(0.55, 0.4, 0.28),
			"mesh": BASE + "food/pot.glb", "h": 0.4, "value": 22, "weight": 7},
		{"id": "barrel", "name": "木桶", "desc": "沉重的木桶，里面或许有货", "color": Color(0.5, 0.35, 0.22),
			"mesh": BASE + "food/barrel.glb", "h": 0.85, "value": 45, "weight": 4},
		{"id": "bottle", "name": "旧酒瓶", "desc": "海盗留下的空瓶", "color": Color(0.3, 0.55, 0.35),
			"mesh": BASE + "pirate/bottle.glb", "h": 0.34, "value": 30, "weight": 6},
		{"id": "cannon_ball", "name": "炮弹", "desc": "沉甸甸的铁球", "color": Color(0.25, 0.25, 0.28),
			"mesh": BASE + "pirate/cannon-ball.glb", "h": 0.28, "value": 40, "weight": 4},
		{"id": "crate", "name": "货箱", "desc": "钉死的木箱", "color": Color(0.55, 0.4, 0.25),
			"mesh": BASE + "pirate/crate.glb", "h": 0.7, "value": 55, "weight": 3},
		{"id": "pirate_chest", "name": "木宝箱", "desc": "锈锁的海盗宝箱", "color": Color(0.55, 0.38, 0.2),
			"mesh": BASE + "pirate/chest.glb", "h": 0.55, "value": 90, "weight": 2},
		{"id": "coin", "name": "古币", "desc": "生锈现一角的金币", "color": Color(0.9, 0.75, 0.25),
			"mesh": BASE + "dungeon/coin.glb", "h": 0.1, "value": 25, "weight": 8},
		{"id": "potion", "name": "药瓶", "desc": "神秘的彩色药剂", "color": Color(0.55, 0.3, 0.75),
			"mesh": BASE + "dungeon/potion.glb", "h": 0.3, "value": 60, "weight": 3},
		{"id": "key", "name": "旧钥匙", "desc": "或许能打开某处的门", "color": Color(0.75, 0.65, 0.3),
			"mesh": BASE + "dungeon/key.glb", "h": 0.22, "value": 80, "weight": 2},
		{"id": "shield", "name": "圆盾", "desc": "磨损的圆形盾牌", "color": Color(0.45, 0.5, 0.6),
			"mesh": BASE + "dungeon/shield-round.glb", "h": 0.72, "value": 110, "weight": 2},
		{"id": "dungeon_chest", "name": "宝箱", "desc": "沉重的宝藏箱", "color": Color(0.7, 0.55, 0.25),
			"mesh": BASE + "dungeon/chest.glb", "h": 0.5, "value": 150, "weight": 1},
	]
	var total_w := 0
	for d in defs:
		total_w += int(d["weight"])
	var positions := _sample_positions_random(treasure_count, 12.0, 22.0, rng, 0.0, 0.0, 36.0)
	_map_treasure_markers.clear()
	var placed := 0
	for i in positions.size():
		var pid := "treasure_%d" % i
		if _collected_pickups.has(pid):
			continue
		var def: Dictionary = _pick_weighted_treasure(defs, total_w, rng)
		var p: Vector3 = positions[i]
		var pos := Vector3(p.x, p.y + 0.02, p.z)
		var yaw := rng.randf_range(0.0, TAU)
		_streamer.call("add_treasure", {
			"id": pid,
			"item_id": str(def["id"]),
			"item_name": str(def["name"]),
			"item_desc": str(def["desc"]),
			"item_color": def["color"],
			"amount": 1,
			"item_value": int(def["value"]),
			"mesh_path": str(def["mesh"]),
			"target_height": float(def["h"]),
			"yaw": yaw,
			"pos": pos,
		})
		_map_treasure_markers.append({
			"id": pid,
			"x": pos.x,
			"z": pos.z,
			"name": str(def["name"]),
			"value": int(def["value"]),
		})
		placed += 1
	print("Treasures prepared: ", placed)


func _pick_weighted_treasure(defs: Array[Dictionary], total_w: int, rng: RandomNumberGenerator) -> Dictionary:
	var roll := rng.randi_range(1, maxi(total_w, 1))
	var acc := 0
	for d in defs:
		acc += int(d["weight"])
		if roll <= acc:
			return d
	return defs[defs.size() - 1]
