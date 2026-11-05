extends RefCounted
## Convert a live generated forest Main into a static editable PackedScene.


const OUT_PATH := "res://scenes/maps/forest_baked.tscn"
const STATIC_SCRIPT := "res://scripts/baked_forest_static.gd"
const WORLD_SCRIPT := "res://scripts/baked_forest_world.gd"


static func bake_live_main(main: Node3D, out_path: String = OUT_PATH) -> String:
	var forest := main.get_node_or_null("Forest") as Node3D
	if forest == null:
		return "Forest node missing"
	if not bool(forest.get("world_ready")):
		return "Forest not ready"

	var streamer: Node = forest.get_node_or_null("WorldStreamer")
	var placement: Dictionary = {}
	if streamer != null and streamer.has_method("export_placement_data"):
		placement = streamer.call("export_placement_data")

	# Capture height / map data before ripping generator state apart.
	var heights: PackedFloat32Array = forest.get("_heights")
	var height_res: int = int(forest.get("_height_res"))
	var terrain_size: float = float(forest.get("terrain_size"))
	var map_data: Dictionary = {}
	if forest.has_method("get_map_data"):
		map_data = forest.call("get_map_data")

	# Remove streamed chunk visuals / animals / streamer.
	_free_named_prefix(forest, "Chunk_")
	for n in ["WorldStreamer", "AnimalsStreamed", "MonstersStreamed", "TreasuresStreamed"]:
		var child := forest.get_node_or_null(n)
		if child != null:
			forest.remove_child(child)
			child.free()

	# Headless/Dummy renderer cannot write MultiMesh transforms — save placement
	# and rebuild Multimeshes in editor/game via baked_props_rebuild.gd.
	var data_script := load("res://scripts/baked_props_data.gd") as Script
	if data_script == null:
		return "missing baked_props_data.gd"
	var props_data: Resource = data_script.new()
	props_data.set("trees", _sanitize_items(placement.get("trees", [])))
	props_data.set("rocks", _sanitize_items(placement.get("rocks", [])))
	props_data.set("bushes", _sanitize_items(placement.get("bushes", [])))
	props_data.set("flowers", _sanitize_items(placement.get("flowers", [])))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://baked"))
	var props_path := "res://baked/forest_props.tres"
	var save_err := ResourceSaver.save(props_data, props_path)
	if save_err != OK:
		return "save props data failed: %s" % error_string(save_err)
	var tree_n: int = (props_data.get("trees") as Array).size()
	var rock_n: int = (props_data.get("rocks") as Array).size()
	print("BAKE props saved: trees=", tree_n, " rocks=", rock_n)
	if tree_n > 0:
		var sample_xf: Transform3D = (props_data.get("trees") as Array)[0]["xf"]
		print("BAKE sample tree origin=", sample_xf.origin)

	# Externalize heavy resources so .tscn stays openable.
	_externalize_ground(forest)
	_externalize_ground_textures(forest)
	_externalize_heights(terrain_size, height_res, heights)

	var props := Node3D.new()
	props.name = "BakedProps"
	var rebuild_script := load("res://scripts/baked_props_rebuild.gd") as Script
	if rebuild_script != null:
		props.set_script(rebuild_script)
	forest.add_child(props)
	for c in props.get_children():
		props.remove_child(c)
		c.free()

	# Prop colliders (~3k shapes) are built at runtime only — keep them out of the .tscn.
	var old_cols := forest.get_node_or_null("PropColliders")
	if old_cols != null:
		forest.remove_child(old_cols)
		old_cols.free()

	# Cloud puffs are runtime-only; packing them bloats the scene.
	var clouds := main.get_node_or_null("CloudLayer")
	if clouds != null:
		for c in clouds.get_children():
			clouds.remove_child(c)
			c.free()

	# Strip GroundBody collision shapes (rebuild from mesh at runtime).
	var gbody := forest.get_node_or_null("GroundBody")
	if gbody != null:
		for c in gbody.get_children():
			gbody.remove_child(c)
			c.free()

	# Swap Forest script to static runtime.
	var static_script := load(STATIC_SCRIPT) as Script
	if static_script == null:
		return "Missing baked_forest_static.gd"
	forest.set_script(static_script)
	forest.set("terrain_size", terrain_size)
	forest.set("height_res", height_res)
	forest.set("map_roads", map_data.get("roads", []))
	forest.set("map_ponds", map_data.get("ponds", []))
	forest.set("map_houses", map_data.get("houses", []))
	forest.set("map_mountains", map_data.get("mountains", []))
	forest.set("map_pickups", map_data.get("pickups", []))
	forest.set("map_actors", map_data.get("actors", []))
	forest.set("world_ready", true)
	# Soften editor viewport: disable glow on environment.
	var we := main.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		we.environment.glow_enabled = false

	# Root uses lightweight bootstrap (same boot overlay, instant forest ready).
	var world_script := load(WORLD_SCRIPT) as Script
	if world_script != null:
		main.set_script(world_script)

	# Re-instance Player/UI so pack() does not flatten runtime children
	# (KenneyVisual, etc.) into the .tscn — that causes editor load conflicts.
	_reinstance_packed_children(main)

	# Runtime-created nodes need owner set or PackedScene.pack drops them.
	# Do NOT recurse into PackedScene instances — only own the instance root.
	_set_owner_recursive(main, main)
	var child_names: PackedStringArray = []
	for c in forest.get_children():
		child_names.append(str(c.name))
	print("BAKE forest children: ", ", ".join(child_names))

	var packed := PackedScene.new()
	var err := packed.pack(main)
	if err != OK:
		return "pack failed: %s" % error_string(err)
	err = ResourceSaver.save(packed, out_path)
	if err != OK:
		return "save failed: %s" % error_string(err)
	return ""


static func _set_owner_recursive(node: Node, owner: Node) -> void:
	for c in node.get_children():
		c.owner = owner
		# Instanced scene root: keep reference, don't flatten internals.
		if str(c.scene_file_path) != "":
			continue
		_set_owner_recursive(c, owner)


static func _reinstance_packed_children(main: Node) -> void:
	var specs := {
		"Player": "res://scenes/player.tscn",
		"Inventory": "res://scenes/inventory.tscn",
		"WorldMap": "res://scenes/world_map.tscn",
		"PauseMenu": "res://scenes/pause_menu.tscn",
	}
	for node_name in specs.keys():
		var path := str(specs[node_name])
		var old := main.get_node_or_null(node_name)
		var xform := Transform3D.IDENTITY
		var idx := -1
		if old != null:
			idx = old.get_index()
			if old is Node3D:
				xform = (old as Node3D).transform
			main.remove_child(old)
			old.free()
		var packed := load(path) as PackedScene
		if packed == null:
			push_warning("bake: missing " + path)
			continue
		var inst := packed.instantiate()
		inst.name = node_name
		if inst is Node3D:
			(inst as Node3D).transform = xform
		main.add_child(inst)
		if idx >= 0:
			main.move_child(inst, mini(idx, main.get_child_count() - 1))


static func _externalize_ground(forest: Node3D) -> void:
	var ground := forest.get_node_or_null("Ground") as MeshInstance3D
	if ground == null or ground.mesh == null:
		return
	var path := "res://baked/ground_mesh.res"
	var err := ResourceSaver.save(ground.mesh, path)
	if err != OK:
		push_warning("bake: ground mesh save failed " + error_string(err))
		return
	ground.mesh = load(path)
	print("BAKE ground mesh -> ", path)


static func _externalize_ground_textures(forest: Node3D) -> void:
	## Road SDF alone is a 4096² RF image (~64MB). Keep it out of the .tscn text.
	var ground := forest.get_node_or_null("Ground") as MeshInstance3D
	if ground == null:
		return
	var mat := ground.material_override as ShaderMaterial
	if mat == null and ground.get_surface_override_material_count() > 0:
		mat = ground.get_surface_override_material(0) as ShaderMaterial
	if mat == null:
		return
	var keys := ["ground_tex", "ground_normal", "road_sdf"]
	for key in keys:
		var tex: Variant = mat.get_shader_parameter(key)
		if not (tex is Texture2D):
			continue
		var path := "res://baked/%s.res" % key
		var err := ResourceSaver.save(tex, path)
		if err != OK:
			push_warning("bake: save %s failed %s" % [path, error_string(err)])
			continue
		var loaded := load(path)
		if loaded != null:
			mat.set_shader_parameter(key, loaded)
			print("BAKE texture -> ", path)
	ground.material_override = mat


static func _externalize_heights(terrain_size: float, height_res: int, heights: PackedFloat32Array) -> void:
	var script := load("res://scripts/baked_heightmap.gd") as Script
	if script == null:
		return
	var res: Resource = script.new()
	res.set("terrain_size", terrain_size)
	res.set("height_res", height_res)
	res.set("heights", heights)
	var path := "res://baked/forest_heights.res"
	var err := ResourceSaver.save(res, path)
	print("BAKE heights -> ", path, " ", error_string(err) if err != OK else "ok")


static func _sanitize_items(items: Array) -> Array:
	## Ensure dictionaries only contain serializable fields for .tres.
	var out: Array = []
	for it in items:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = {
			"xf": it["xf"],
			"type": int(it.get("type", 0)),
		}
		if it.has("col_r"):
			d["col_r"] = float(it["col_r"])
		if it.has("col_h"):
			d["col_h"] = float(it["col_h"])
		if it.has("col"):
			d["col"] = it["col"]
		out.append(d)
	return out


static func _free_named_prefix(parent: Node, prefix: String) -> void:
	for child in parent.get_children():
		if str(child.name).begins_with(prefix):
			parent.remove_child(child)
			child.free()
