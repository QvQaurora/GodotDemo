@tool
extends Node3D
## Rebuild MultiMesh vegetation from baked placement (cached after first build).


const DATA_PATH := "res://baked/forest_props.tres"
const CACHE_PATH := "res://baked/props_visual.tscn"

@export var rebuild_in_editor: bool = true
@export var include_detail_in_editor: bool = false ## bushes/flowers slow editor; off by default

var _built: bool = false
var _building: bool = false


func _ready() -> void:
	if Engine.is_editor_hint() and not rebuild_in_editor:
		return
	call_deferred("_rebuild_async")


func _rebuild_async() -> void:
	if _building:
		return
	if _built and not Engine.is_editor_hint():
		return
	if RenderingServer.get_rendering_device() == null:
		print("BakedProps: skip rebuild (no rendering device)")
		return
	_building = true

	# Fast path: prebuilt Multimesh scene.
	if ResourceLoader.exists(CACHE_PATH):
		_load_cache()
		_building = false
		_built = true
		print("BakedProps: loaded cache ", CACHE_PATH)
		return

	var data: Resource = load(DATA_PATH) as Resource
	if data == null:
		push_warning("baked_props_rebuild: missing %s" % DATA_PATH)
		_building = false
		return

	for c in get_children():
		remove_child(c)
		c.free()

	var tree_items: Array = data.get("trees")
	var rock_items: Array = data.get("rocks")
	var bush_items: Array = data.get("bushes")
	var flower_items: Array = data.get("flowers")

	print("BakedProps: building trees...")
	await get_tree().process_frame
	var trees := await _load_tree_meshes_async()
	_fill_multimeshes("Trees", trees, tree_items, [])
	await get_tree().process_frame

	print("BakedProps: building rocks...")
	var rocks_m := _load_rock_meshes()
	_fill_multimeshes("Rocks", rocks_m["meshes"], rock_items, rocks_m["mats"])
	await get_tree().process_frame

	var want_detail := include_detail_in_editor or not Engine.is_editor_hint()
	if want_detail:
		print("BakedProps: building bushes/flowers...")
		var bushes := await _load_bush_meshes_async()
		_fill_multimeshes("Bushes", bushes, bush_items, [])
		await get_tree().process_frame
		var flowers := await _load_flower_meshes_async()
		_fill_multimeshes("Flowers", flowers, flower_items, [])
		await get_tree().process_frame
		# Only cache a complete build — editor tree/rock-only previews must not
		# overwrite the runtime cache and drop bushes/flowers.
		_save_cache()

	_built = true
	_building = false
	print("BakedProps rebuilt: trees=", tree_items.size(), " rocks=", rock_items.size())


func _load_cache() -> void:
	for c in get_children():
		remove_child(c)
		c.free()
	var packed := load(CACHE_PATH) as PackedScene
	if packed == null:
		return
	var root := packed.instantiate()
	for c in root.get_children():
		root.remove_child(c)
		c.owner = null
		add_child(c)
		if Engine.is_editor_hint():
			c.owner = owner if owner != null else get_parent()
	root.free()


func _save_cache() -> void:
	if RenderingServer.get_rendering_device() == null:
		return
	if get_child_count() == 0:
		return
	# Pack children into a tiny scene for next open.
	var holder := Node3D.new()
	holder.name = "PropsCache"
	var copies: Array = []
	for c in get_children():
		var d: Node = c.duplicate()
		holder.add_child(d)
		d.owner = holder
		copies.append(d)
	var packed := PackedScene.new()
	if packed.pack(holder) == OK:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://baked"))
		var err := ResourceSaver.save(packed, CACHE_PATH)
		print("BakedProps cache save: ", error_string(err) if err != OK else CACHE_PATH)
	holder.free()


func _fill_multimeshes(prefix: String, meshes: Array, items: Array, mats: Array) -> void:
	if meshes.is_empty() or items.is_empty():
		return
	var mesh_count := meshes.size()
	var counts: Array[int] = []
	counts.resize(mesh_count)
	counts.fill(0)
	for it in items:
		var t: int = int(it.get("type", 0))
		if t >= 0 and t < mesh_count:
			counts[t] += 1
	var mms: Array = []
	mms.resize(mesh_count)
	for i in mesh_count:
		if counts[i] <= 0:
			mms[i] = null
			continue
		var mesh: Mesh = meshes[i] as Mesh
		if mesh == null:
			mms[i] = null
			continue
		var mi := MultiMeshInstance3D.new()
		mi.name = "%s_%d" % [prefix, i]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = counts[i]
		mi.multimesh = mm
		if i < mats.size() and mats[i] != null:
			mi.material_override = mats[i]
		mi.custom_aabb = AABB(Vector3(-520, -30, -520), Vector3(1040, 120, 1040))
		add_child(mi)
		if Engine.is_editor_hint():
			mi.owner = owner if owner != null else get_parent()
		mms[i] = mi
	var writes: Array[int] = []
	writes.resize(mesh_count)
	writes.fill(0)
	for it in items:
		var t: int = int(it.get("type", 0))
		if t < 0 or t >= mms.size() or mms[t] == null:
			continue
		var wi: int = writes[t]
		writes[t] = wi + 1
		(mms[t] as MultiMeshInstance3D).multimesh.set_instance_transform(wi, it["xf"])


func _load_glb_mesh(res_path: String) -> Mesh:
	var packed := load(res_path) as PackedScene
	if packed == null:
		return null
	var scene := packed.instantiate()
	var mesh: Mesh = null
	var stack: Array = [scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			mesh = (n as MeshInstance3D).mesh
			break
		for c in n.get_children():
			stack.append(c)
	scene.free()
	return mesh


func _load_tree_meshes_async() -> Array:
	var files := [
		"tree_default.glb", "tree_default_dark.glb", "tree_oak.glb", "tree_oak_dark.glb",
		"tree_detailed.glb", "tree_detailed_dark.glb", "tree_simple.glb", "tree_simple_dark.glb",
		"tree_tall.glb", "tree_tall_dark.glb", "tree_thin.glb", "tree_thin_dark.glb",
		"tree_fat.glb", "tree_cone.glb", "tree_cone_dark.glb", "tree_plateau.glb", "tree_plateau_dark.glb",
		"tree_blocks.glb", "tree_small.glb",
		"tree_pineDefaultA.glb", "tree_pineDefaultB.glb",
		"tree_pineTallA.glb", "tree_pineTallB.glb", "tree_pineTallC.glb", "tree_pineTallD.glb",
		"tree_pineTallA_detailed.glb", "tree_pineTallB_detailed.glb",
		"tree_pineRoundA.glb", "tree_pineRoundB.glb", "tree_pineRoundC.glb", "tree_pineRoundD.glb",
		"tree_pineSmallA.glb", "tree_pineSmallB.glb",
	]
	var out: Array = []
	var i := 0
	for f in files:
		var mesh := _load_glb_mesh("res://assets/kenney_trees/%s" % f)
		if mesh != null:
			out.append(mesh)
		i += 1
		if i % 4 == 0:
			await get_tree().process_frame
	return out


func _load_bush_meshes_async() -> Array:
	var files := [
		"plant_bush.glb", "plant_bushDetailed.glb", "plant_bushLarge.glb",
		"plant_bushSmall.glb", "plant_bushTriangle.glb",
	]
	var out: Array = []
	for f in files:
		var mesh := _load_glb_mesh("res://assets/kenney_plants/%s" % f)
		if mesh != null:
			out.append(mesh)
		await get_tree().process_frame
	return out


func _load_flower_meshes_async() -> Array:
	var files := [
		"flower_purpleA.glb", "flower_purpleB.glb", "flower_yellowA.glb",
		"flower_yellowB.glb", "flower_redA.glb", "flower_redB.glb",
	]
	var out: Array = []
	for f in files:
		var mesh := _load_glb_mesh("res://assets/kenney_plants/%s" % f)
		if mesh != null:
			out.append(mesh)
		await get_tree().process_frame
	return out


func _load_rock_meshes() -> Dictionary:
	var meshes: Array = []
	var mats: Array = []
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 1.5
	sphere.radial_segments = 8
	sphere.rings = 4
	meshes.append(sphere)
	var mat0 := StandardMaterial3D.new()
	mat0.albedo_color = Color(0.45, 0.43, 0.40)
	mat0.roughness = 0.95
	mats.append(mat0)
	var box := BoxMesh.new()
	box.size = Vector3(1.8, 1.1, 1.4)
	meshes.append(box)
	var mat1 := StandardMaterial3D.new()
	mat1.albedo_color = Color(0.38, 0.37, 0.35)
	mat1.roughness = 0.98
	mats.append(mat1)
	var tall := SphereMesh.new()
	tall.radius = 0.9
	tall.height = 2.4
	tall.radial_segments = 8
	tall.rings = 5
	meshes.append(tall)
	var mat2 := StandardMaterial3D.new()
	mat2.albedo_color = Color(0.52, 0.50, 0.46)
	mat2.roughness = 0.92
	mats.append(mat2)
	return {"meshes": meshes, "mats": mats}
