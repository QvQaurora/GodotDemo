extends Node3D
## Static baked forest: light scene file + runtime/editor helpers.


const HEIGHTS_PATH := "res://baked/forest_heights.res"
const PROPS_PATH := "res://baked/forest_props.tres"
const GROUND_MESH_PATH := "res://baked/ground_mesh.res"

@export var terrain_size: float = 1000.0
@export var height_res: int = 257
@export var map_roads: Array = []
@export var map_ponds: Array = []
@export var map_houses: Array = []
@export var map_mountains: Array = []
@export var map_pickups: Array = []
@export var map_actors: Array = []

var heights: PackedFloat32Array = PackedFloat32Array()
var world_ready: bool = false
var _collected_pickups: Dictionary = {}
signal world_built


func _ready() -> void:
	add_to_group("forest_world")
	_load_heights()
	_ensure_ground_mesh()
	if not Engine.is_editor_hint():
		_ensure_ground_collision()
		_ensure_prop_colliders()
	world_ready = true
	world_built.emit()


func get_terrain_height(x: float, z: float) -> float:
	return _height_at(x, z)


func refresh_world_stream() -> void:
	pass


func mark_pickup_collected(pickup_id: String) -> void:
	_collected_pickups[pickup_id] = true


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


func is_pickup_collected(pickup_id: String) -> bool:
	return _collected_pickups.has(pickup_id)


func get_map_data() -> Dictionary:
	var pickups: Array = []
	for m in map_pickups:
		var pid := str(m.get("id", ""))
		if pid != "" and _collected_pickups.has(pid):
			continue
		pickups.append(m)
	for node in get_tree().get_nodes_in_group("world_pickup"):
		if node.has_method("get_map_marker"):
			pickups.append(node.call("get_map_marker"))
	return {
		"size": terrain_size,
		"road_width": 10.0,
		"roads": map_roads.duplicate(true),
		"ponds": map_ponds.duplicate(),
		"houses": map_houses.duplicate(true),
		"mountains": map_mountains.duplicate(),
		"pickups": pickups,
		"actors": map_actors.duplicate(true),
		"height_preview": null,
	}


func _load_heights() -> void:
	if ResourceLoader.exists(HEIGHTS_PATH):
		var res: Resource = load(HEIGHTS_PATH)
		if res != null:
			terrain_size = float(res.get("terrain_size"))
			height_res = int(res.get("height_res"))
			heights = res.get("heights")


func _ensure_ground_mesh() -> void:
	var ground := get_node_or_null("Ground") as MeshInstance3D
	if ground == null:
		return
	if ground.mesh == null and ResourceLoader.exists(GROUND_MESH_PATH):
		ground.mesh = load(GROUND_MESH_PATH)


func _ensure_ground_collision() -> void:
	var ground := get_node_or_null("Ground") as MeshInstance3D
	if ground == null or ground.mesh == null:
		return
	var body := get_node_or_null("GroundBody") as StaticBody3D
	if body == null:
		body = StaticBody3D.new()
		body.name = "GroundBody"
		body.collision_layer = 8
		body.collision_mask = 0
		add_child(body)
	# Replace heavy packed shapes with one trimesh from mesh.
	for c in body.get_children():
		body.remove_child(c)
		c.free()
	var col := CollisionShape3D.new()
	col.shape = ground.mesh.create_trimesh_shape()
	body.add_child(col)


func _ensure_prop_colliders() -> void:
	if get_node_or_null("PropColliders") != null:
		return
	if not ResourceLoader.exists(PROPS_PATH):
		return
	var data: Resource = load(PROPS_PATH)
	if data == null:
		return
	var body := StaticBody3D.new()
	body.name = "PropColliders"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	for t in data.get("trees"):
		_add_cyl(body, t["xf"].origin, float(t.get("col_r", 0.2)), float(t.get("col_h", 1.0)))
	for b in data.get("bushes"):
		_add_sphere(body, b["xf"].origin + Vector3(0, 0.35, 0), float(b.get("col_r", 0.3)))
	for r in data.get("rocks"):
		var col: Dictionary = r.get("col", {})
		match int(col.get("shape", 0)):
			1:
				_add_box(body, r["xf"].origin, col.get("size", Vector3.ONE), float(col.get("yaw", 0.0)))
			_:
				_add_sphere(body, r["xf"].origin, float(col.get("radius", 0.5)))


func _add_cyl(parent: Node, origin: Vector3, radius: float, height: float) -> void:
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = maxf(radius, 0.08)
	shape.height = maxf(height, 0.3)
	col.shape = shape
	col.position = origin + Vector3(0.0, shape.height * 0.5, 0.0)
	parent.add_child(col)


func _add_sphere(parent: Node, origin: Vector3, radius: float) -> void:
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = maxf(radius, 0.2)
	col.shape = shape
	col.position = origin
	parent.add_child(col)


func _add_box(parent: Node, origin: Vector3, size: Vector3, yaw: float) -> void:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = origin
	col.rotation.y = yaw
	parent.add_child(col)


func _height_at(x: float, z: float) -> float:
	if heights.is_empty() or height_res < 2:
		return 0.0
	var half := terrain_size * 0.5
	var u := clampf((x + half) / terrain_size, 0.0, 1.0)
	var v := clampf((z + half) / terrain_size, 0.0, 1.0)
	var fx := u * float(height_res - 1)
	var fz := v * float(height_res - 1)
	var x0 := mini(int(fx), height_res - 2)
	var z0 := mini(int(fz), height_res - 2)
	var tx := fx - float(x0)
	var tz := fz - float(z0)
	var i00 := z0 * height_res + x0
	var h00 := heights[i00]
	var h10 := heights[i00 + 1]
	var h01 := heights[i00 + height_res]
	var h11 := heights[i00 + height_res + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)
