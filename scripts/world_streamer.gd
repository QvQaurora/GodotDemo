extends Node
## Chunk streaming + distance LOD + deferred actor/pickup spawn with simple pooling.
## Parent must be the forest generator (provides height / spawn helpers).


@export var chunk_size: float = 64.0
@export var visual_chunk_radius: int = 5 ## Chebyshev radius → (2r+1)^2 chunks with visuals
@export var detail_chunk_radius: int = 2 ## within this: full GLB trees; beyond: impostors
@export var collision_chunk_radius: int = 2 ## nearer ring gets trunk/rock collision
@export var grass_chunk_radius: int = 3 ## grass only near the player (lazy per-chunk)
@export var actor_distance: float = 140.0 ## animals / monsters / treasures spawn range
@export var update_interval: float = 0.25

var forest: Node = null

## Untyped arrays — survives Argument passing via Object.call() without typed-array wipe.
var _tree_meshes: Array = []
var _grass_meshes: Array = []
var _rock_meshes: Array = []
var _rock_mats: Array = []
var _bush_meshes: Array = []
var _flower_meshes: Array = []

## chunk_key(Vector2i) -> { trees:Array, grass:Array, rocks:Array, bushes:Array, flowers:Array,
##   actors:Array, treasures:Array, root:Node3D, colliders:Node3D, has_collision:bool }
var _chunks: Dictionary = {}
var _active: Dictionary = {} # Vector2i -> true
var _last_center: Vector2i = Vector2i(99999, 99999)
var _timer: float = 0.0

var _alive_actors: Dictionary = {} # spawn_id -> Node
var _killed_actors: Dictionary = {} # spawn_id -> true (stay dead this session)
var _alive_treasures: Dictionary = {} # pickup_id -> Node
var _fading: Dictionary = {} # Vector2i -> true (chunk alpha fade-in)
var _critter_ai: Script
var _pickup_script: Script
var _animals_root: Node3D
var _monsters_root: Node3D
var _treasures_root: Node3D


func setup(host: Node) -> void:
	forest = host
	add_to_group("world_streamer")
	_critter_ai = load("res://scripts/critter_ai.gd") as Script
	_pickup_script = load("res://scripts/pickup_item.gd") as Script
	_animals_root = Node3D.new()
	_animals_root.name = "AnimalsStreamed"
	forest.add_child(_animals_root)
	_monsters_root = Node3D.new()
	_monsters_root.name = "MonstersStreamed"
	forest.add_child(_monsters_root)
	_treasures_root = Node3D.new()
	_treasures_root.name = "TreasuresStreamed"
	forest.add_child(_treasures_root)
	set_process(true)


func set_meshes(
	trees: Variant,
	grass: Variant,
	rocks: Variant,
	rock_mats: Variant,
	bushes: Variant,
	flowers: Variant
) -> void:
	_tree_meshes = _copy_array(trees)
	_grass_meshes = _copy_array(grass)
	_rock_meshes = _copy_array(rocks)
	_rock_mats = _copy_array(rock_mats)
	_bush_meshes = _copy_array(bushes)
	_flower_meshes = _copy_array(flowers)


func _copy_array(src: Variant) -> Array:
	var out: Array = []
	if typeof(src) != TYPE_ARRAY:
		return out
	for item in src:
		out.append(item)
	return out


func chunk_key(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / chunk_size), floori(z / chunk_size))


func _ensure_chunk(key: Vector2i) -> Dictionary:
	if _chunks.has(key):
		return _chunks[key]
	var d := {
		"trees": [],
		"grass": [],
		"rocks": [],
		"bushes": [],
		"flowers": [],
		"actors": [],
		"treasures": [],
		"root": null,
		"colliders": null,
		"has_collision": false,
	}
	_chunks[key] = d
	return d


func add_tree(xform: Transform3D, type_i: int, col_r: float, col_h: float) -> void:
	var key := chunk_key(xform.origin.x, xform.origin.z)
	_ensure_chunk(key)["trees"].append({
		"xf": xform, "type": type_i, "col_r": col_r, "col_h": col_h
	})


func add_grass(xform: Transform3D, type_i: int) -> void:
	var key := chunk_key(xform.origin.x, xform.origin.z)
	_ensure_chunk(key)["grass"].append({"xf": xform, "type": type_i})


func add_rock(xform: Transform3D, type_i: int, col: Dictionary) -> void:
	var key := chunk_key(xform.origin.x, xform.origin.z)
	_ensure_chunk(key)["rocks"].append({"xf": xform, "type": type_i, "col": col})


func add_bush(xform: Transform3D, type_i: int, col_r: float) -> void:
	var key := chunk_key(xform.origin.x, xform.origin.z)
	_ensure_chunk(key)["bushes"].append({"xf": xform, "type": type_i, "col_r": col_r})


func add_flower(xform: Transform3D, type_i: int) -> void:
	var key := chunk_key(xform.origin.x, xform.origin.z)
	_ensure_chunk(key)["flowers"].append({"xf": xform, "type": type_i})


func add_actor(spawn: Dictionary) -> void:
	# spawn: id, kind(0 animal/1 monster), path, pos, yaw, height, name
	var p: Vector3 = spawn["pos"]
	var key := chunk_key(p.x, p.z)
	_ensure_chunk(key)["actors"].append(spawn)


func add_treasure(spawn: Dictionary) -> void:
	var p: Vector3 = spawn["pos"]
	var key := chunk_key(p.x, p.z)
	_ensure_chunk(key)["treasures"].append(spawn)


func force_update() -> void:
	_last_center = Vector2i(99999, 99999)
	_update_streaming(true)


func export_placement_data() -> Dictionary:
	var trees: Array = []
	var rocks: Array = []
	var bushes: Array = []
	var flowers: Array = []
	var actors: Array = []
	var treasures: Array = []
	for key in _chunks.keys():
		var ch: Dictionary = _chunks[key]
		for t in ch["trees"]:
			trees.append(t)
		for r in ch["rocks"]:
			rocks.append(r)
		for b in ch["bushes"]:
			bushes.append(b)
		for fl in ch["flowers"]:
			flowers.append(fl)
		for a in ch["actors"]:
			actors.append(a)
		for tr in ch["treasures"]:
			treasures.append(tr)
	return {
		"trees": trees,
		"rocks": rocks,
		"bushes": bushes,
		"flowers": flowers,
		"actors": actors,
		"treasures": treasures,
	}


func import_placement_data(data: Dictionary) -> void:
	_chunks.clear()
	_active.clear()
	for t in data.get("trees", []):
		add_tree(t["xf"], int(t["type"]), float(t.get("col_r", 0.2)), float(t.get("col_h", 1.0)))
	for r in data.get("rocks", []):
		add_rock(r["xf"], int(r["type"]), r.get("col", {}))
	for b in data.get("bushes", []):
		add_bush(b["xf"], int(b["type"]), float(b.get("col_r", 0.3)))
	for fl in data.get("flowers", []):
		add_flower(fl["xf"], int(fl["type"]))
	for a in data.get("actors", []):
		add_actor(a)
	for tr in data.get("treasures", []):
		add_treasure(tr)


func _process(delta: float) -> void:
	_update_chunk_fades(delta)
	_timer += delta
	if _timer < update_interval:
		return
	_timer = 0.0
	_update_streaming(false)


func _player_pos() -> Vector3:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null:
		return player.global_position
	return Vector3.ZERO


func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _update_streaming(force: bool) -> void:
	var p := _player_pos()
	var center := chunk_key(p.x, p.z)
	if not force and center == _last_center:
		_update_actors_only(p)
		return
	_last_center = center

	# Load exactly the budgeted radius so 100/300/500m reads clearly in-game.
	# Keep one-ring hysteresis on unload to avoid thrash at chunk borders.
	var load_r := visual_chunk_radius
	var unload_r := visual_chunk_radius + 1
	var want_visual: Dictionary = {}
	var want_collision: Dictionary = {}
	for dz in range(-load_r, load_r + 1):
		for dx in range(-load_r, load_r + 1):
			want_visual[center + Vector2i(dx, dz)] = true
	for dz in range(-collision_chunk_radius, collision_chunk_radius + 1):
		for dx in range(-collision_chunk_radius, collision_chunk_radius + 1):
			want_collision[center + Vector2i(dx, dz)] = true

	# Unload with hysteresis (keep one ring past the load radius).
	var to_unload: Array[Vector2i] = []
	for key in _active.keys():
		if _chebyshev(key, center) > unload_r:
			to_unload.append(key)
	for key in to_unload:
		_unload_chunk(key)

	# Load / refresh needed chunks (create empty shells so lazy grass can spawn).
	for key in want_visual.keys():
		_ensure_chunk(key)
		var need_col := want_collision.has(key)
		var cheb := _chebyshev(key, center)
		var want_grass := cheb <= grass_chunk_radius
		var want_lod := 0 if cheb <= detail_chunk_radius else 1
		var was_active := _active.has(key)
		if want_grass and forest != null and forest.has_method("ensure_chunk_grass"):
			forest.call("ensure_chunk_grass", key, chunk_size)
		if not was_active:
			_load_chunk(key, need_col, want_lod, cheb > 1)
		else:
			var ch_live: Dictionary = _chunks[key]
			if int(ch_live.get("lod", -1)) != want_lod:
				_rebuild_chunk_visuals(key, need_col, want_lod)
			else:
				_set_chunk_collision(key, need_col)
				if want_grass:
					_refresh_chunk_grass(key)

	_update_actors_only(p)


func _update_actors_only(player_pos: Vector3) -> void:
	var dist2 := actor_distance * actor_distance
	# Activate nearby spawns from active chunks + neighbors.
	var center := chunk_key(player_pos.x, player_pos.z)
	var scan_r := maxi(visual_chunk_radius, 2)
	for dz in range(-scan_r, scan_r + 1):
		for dx in range(-scan_r, scan_r + 1):
			var key := center + Vector2i(dx, dz)
			if not _chunks.has(key):
				continue
			var ch: Dictionary = _chunks[key]
			for spawn in ch["actors"]:
				var sid: String = spawn["id"]
				var sp: Vector3 = spawn["pos"]
				var near := player_pos.distance_squared_to(sp) <= dist2
				if _killed_actors.has(sid):
					continue
				if near and not _alive_actors.has(sid):
					_spawn_actor(spawn)
				elif (not near) and _alive_actors.has(sid):
					_despawn_actor(sid)
			for spawn in ch["treasures"]:
				var pid: String = spawn["id"]
				if forest != null and "collected" in forest:
					pass
				if forest != null and forest.has_method("is_pickup_collected") and forest.call("is_pickup_collected", pid):
					continue
				var sp2: Vector3 = spawn["pos"]
				var near2 := player_pos.distance_squared_to(sp2) <= dist2
				if near2 and not _alive_treasures.has(pid):
					_spawn_treasure(spawn)
				elif (not near2) and _alive_treasures.has(pid):
					_despawn_treasure(pid)


func _load_chunk(key: Vector2i, with_collision: bool, lod: int = 0, fade_in: bool = false) -> void:
	var ch: Dictionary = _chunks[key]
	var root := Node3D.new()
	root.name = "Chunk_%d_%d" % [key.x, key.y]
	forest.add_child(root)
	ch["root"] = root
	ch["lod"] = lod

	_fill_chunk_props(root, ch, lod)

	var col_root := Node3D.new()
	col_root.name = "Colliders"
	root.add_child(col_root)
	ch["colliders"] = col_root
	ch["has_collision"] = false
	ch["grass_built"] = lod == 0 and not (ch["grass"] as Array).is_empty()
	_active[key] = true
	_set_chunk_collision(key, with_collision)
	if fade_in:
		_begin_chunk_fade(key)
	else:
		ch["fade"] = 0.0
		_fading.erase(key)


func _rebuild_chunk_visuals(key: Vector2i, with_collision: bool, lod: int) -> void:
	## Swap near/far undergrowth LOD without despawning actors/treasures.
	## Trees stay fully populated in both LODs so density never "pops".
	if not _chunks.has(key) or not _active.has(key):
		_load_chunk(key, with_collision, lod, false)
		return
	var ch: Dictionary = _chunks[key]
	var root: Node3D = ch.get("root") as Node3D
	if root == null or not is_instance_valid(root):
		_load_chunk(key, with_collision, lod, false)
		return
	var kids := root.get_children()
	for c in kids:
		if str(c.name) == "Colliders":
			continue
		root.remove_child(c)
		c.free()
	ch["lod"] = lod
	ch["grass_built"] = false
	_fill_chunk_props(root, ch, lod)
	if lod == 0 and not (ch["grass"] as Array).is_empty():
		ch["grass_built"] = true
	_set_chunk_collision(key, with_collision)
	# Keep current fade state on geometry (usually already opaque near player).
	_apply_chunk_fade_amount(ch, float(ch.get("fade", 0.0)))


func _fill_chunk_props(root: Node3D, ch: Dictionary, lod: int) -> void:
	# Always full trees/rocks — far LOD only drops grass/bush/flower (cheap + no tree pop).
	_fill_multimeshes(root, "Trees", _tree_meshes, ch["trees"])
	_fill_rock_multimeshes(root, ch["rocks"])
	if lod == 0:
		_fill_multimeshes(root, "Grass", _grass_meshes, ch["grass"])
		_fill_multimeshes(root, "Bushes", _bush_meshes, ch["bushes"])
		_fill_multimeshes(root, "Flowers", _flower_meshes, ch["flowers"])


func _begin_chunk_fade(key: Vector2i) -> void:
	if not _chunks.has(key):
		return
	var ch: Dictionary = _chunks[key]
	ch["fade"] = 1.0
	_apply_chunk_fade_amount(ch, 1.0)
	_fading[key] = true


func _apply_chunk_fade_amount(ch: Dictionary, amount: float) -> void:
	var root: Node3D = ch.get("root") as Node3D
	if root == null or not is_instance_valid(root):
		return
	var t := clampf(amount, 0.0, 1.0)
	for c in root.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).transparency = t


func _update_chunk_fades(delta: float) -> void:
	if _fading.is_empty():
		return
	var done: Array[Vector2i] = []
	var step := delta / 0.9 # ~0.9s soft appear
	for key in _fading.keys():
		if not _chunks.has(key) or not _active.has(key):
			done.append(key)
			continue
		var ch: Dictionary = _chunks[key]
		var fade := maxf(float(ch.get("fade", 0.0)) - step, 0.0)
		ch["fade"] = fade
		_apply_chunk_fade_amount(ch, fade)
		if fade <= 0.001:
			done.append(key)
	for key in done:
		_fading.erase(key)


func _refresh_chunk_grass(key: Vector2i) -> void:
	## Rebuild grass MultiMeshes if lazy fill happened after the chunk root existed.
	if not _active.has(key) or not _chunks.has(key):
		return
	var ch: Dictionary = _chunks[key]
	# Far LOD skips grass entirely.
	if int(ch.get("lod", 0)) != 0:
		return
	if bool(ch.get("grass_built", false)):
		return
	if (ch["grass"] as Array).is_empty():
		return
	var root: Node3D = ch["root"]
	if root == null or not is_instance_valid(root):
		return
	_free_named_children(root, "Grass_")
	_fill_multimeshes(root, "Grass", _grass_meshes, ch["grass"])
	ch["grass_built"] = true
	_apply_chunk_fade_amount(ch, float(ch.get("fade", 0.0)))


func _unload_chunk(key: Vector2i) -> void:
	if not _chunks.has(key):
		_active.erase(key)
		_fading.erase(key)
		return
	var ch: Dictionary = _chunks[key]
	var root: Node = ch["root"]
	if root != null and is_instance_valid(root):
		root.queue_free()
	ch["root"] = null
	ch["colliders"] = null
	ch["has_collision"] = false
	# Visual Multimeshes are gone; allow rebuild when the chunk streams back in.
	ch["grass_built"] = false
	ch["fade"] = 0.0
	_active.erase(key)
	_fading.erase(key)
	# Despawn actors/treasures belonging to this chunk if still alive.
	for spawn in ch["actors"]:
		var sid: String = spawn["id"]
		if _alive_actors.has(sid):
			_despawn_actor(sid)
	for spawn in ch["treasures"]:
		var pid: String = spawn["id"]
		if _alive_treasures.has(pid):
			_despawn_treasure(pid)


func _set_chunk_collision(key: Vector2i, enabled: bool) -> void:
	var ch: Dictionary = _chunks[key]
	if ch.get("has_collision", false) == enabled:
		return
	var col_root: Node3D = ch["colliders"]
	if col_root == null or not is_instance_valid(col_root):
		return
	# Free immediately — queue_free() would leave old shapes for a frame beside new ones.
	_free_all_children(col_root)
	ch["has_collision"] = enabled
	if not enabled:
		return
	for t in ch["trees"]:
		_add_cyl(col_root, t["xf"].origin, float(t["col_r"]), float(t["col_h"]))
	for b in ch["bushes"]:
		_add_sphere(col_root, b["xf"].origin + Vector3(0, 0.35, 0), float(b["col_r"]))
	for r in ch["rocks"]:
		var col: Dictionary = r["col"]
		match int(col.get("shape", 0)):
			1:
				_add_box(col_root, r["xf"].origin, col["size"], float(col.get("yaw", 0.0)))
			_:
				_add_sphere(col_root, r["xf"].origin, float(col.get("radius", 0.5)))


func _free_all_children(parent: Node) -> void:
	var kids := parent.get_children()
	for c in kids:
		parent.remove_child(c)
		c.free()


func _free_named_children(parent: Node, prefix: String) -> void:
	var kids := parent.get_children()
	for c in kids:
		if str(c.name).begins_with(prefix):
			parent.remove_child(c)
			c.free()


func _fill_multimeshes(parent: Node, prefix: String, meshes: Array, items: Array) -> void:
	if meshes.is_empty() or items.is_empty():
		return
	var mesh_count := meshes.size()
	var counts: Array[int] = []
	counts.resize(mesh_count)
	counts.fill(0)
	for it in items:
		var t: int = int(it["type"])
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
		parent.add_child(mi)
		mms[i] = mi
	var writes: Array[int] = []
	writes.resize(mesh_count)
	writes.fill(0)
	for it in items:
		var t: int = int(it["type"])
		if t < 0 or t >= mms.size() or mms[t] == null:
			continue
		var wi: int = writes[t]
		writes[t] = wi + 1
		var xf: Transform3D = it["xf"]
		(mms[t] as MultiMeshInstance3D).multimesh.set_instance_transform(wi, xf)


func _fill_rock_multimeshes(parent: Node, items: Array) -> void:
	if _rock_meshes.is_empty() or items.is_empty():
		return
	var counts: Array[int] = []
	counts.resize(_rock_meshes.size())
	counts.fill(0)
	for it in items:
		var t: int = int(it["type"])
		if t >= 0 and t < counts.size():
			counts[t] += 1
	var mms: Array = []
	mms.resize(_rock_meshes.size())
	for i in _rock_meshes.size():
		if counts[i] <= 0:
			mms[i] = null
			continue
		var mi := MultiMeshInstance3D.new()
		mi.name = "Rocks_%d" % i
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _rock_meshes[i]
		mm.instance_count = counts[i]
		mi.multimesh = mm
		if i < _rock_mats.size():
			mi.material_override = _rock_mats[i]
		parent.add_child(mi)
		mms[i] = mi
	var writes: Array[int] = []
	writes.resize(_rock_meshes.size())
	writes.fill(0)
	for it in items:
		var t: int = int(it["type"])
		if t < 0 or t >= mms.size() or mms[t] == null:
			continue
		var wi: int = writes[t]
		writes[t] = wi + 1
		(mms[t] as MultiMeshInstance3D).multimesh.set_instance_transform(wi, it["xf"])


func _spawn_actor(spawn: Dictionary) -> void:
	if _critter_ai == null or forest == null:
		return
	if not forest.has_method("stream_spawn_critter"):
		return
	var sid := str(spawn.get("id", ""))
	if sid != "" and _killed_actors.has(sid):
		return
	var node: Node = forest.call("stream_spawn_critter", spawn, _critter_ai)
	if node == null:
		return
	if sid != "":
		node.set_meta("spawn_id", sid)
	var spawn_name := str(spawn.get("name", ""))
	if spawn_name != "":
		node.set_meta("spawn_name", spawn_name)
	var kind := int(spawn.get("kind", 0))
	if kind == 0:
		_animals_root.add_child(node)
	else:
		_monsters_root.add_child(node)
	_alive_actors[sid] = node


func notify_actor_killed(sid: String) -> void:
	## Player finished a critter — do not stream-respawn it this session.
	if sid == "":
		return
	_killed_actors[sid] = true
	_despawn_actor(sid)


func _despawn_actor(sid: String) -> void:
	if not _alive_actors.has(sid):
		return
	var node: Node = _alive_actors[sid]
	_alive_actors.erase(sid)
	if node != null and is_instance_valid(node):
		# Pool unused CharacterBody3D trees is brittle with AI state — free and respawn.
		node.queue_free()


func _spawn_treasure(spawn: Dictionary) -> void:
	if _pickup_script == null:
		return
	var node := Area3D.new()
	node.set_script(_pickup_script)
	node.name = str(spawn["id"])
	node.set("pickup_id", str(spawn["id"]))
	node.set("item_id", str(spawn["item_id"]))
	node.set("item_name", str(spawn["item_name"]))
	node.set("item_desc", str(spawn["item_desc"]))
	node.set("item_color", spawn["item_color"])
	node.set("amount", int(spawn.get("amount", 1)))
	node.set("item_value", int(spawn.get("item_value", 10)))
	node.set("mesh_path", str(spawn.get("mesh_path", "")))
	node.set("target_height", float(spawn.get("target_height", 0.45)))
	node.set("yaw", float(spawn.get("yaw", 0.0)))
	var p: Vector3 = spawn["pos"]
	node.position = p
	_treasures_root.add_child(node)
	_alive_treasures[str(spawn["id"])] = node


func _despawn_treasure(pid: String) -> void:
	if not _alive_treasures.has(pid):
		return
	var node: Node = _alive_treasures[pid]
	_alive_treasures.erase(pid)
	if node != null and is_instance_valid(node):
		node.queue_free()


func _add_cyl(parent: Node, origin: Vector3, radius: float, height: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = maxf(radius, 0.08)
	shape.height = maxf(height, 0.3)
	col.shape = shape
	col.position = origin + Vector3(0.0, shape.height * 0.5, 0.0)
	body.add_child(col)
	parent.add_child(body)


func _add_sphere(parent: Node, origin: Vector3, radius: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = maxf(radius, 0.1)
	col.shape = shape
	col.position = origin
	body.add_child(col)
	parent.add_child(body)


func _add_box(parent: Node, origin: Vector3, size: Vector3, yaw: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = origin
	body.rotation.y = yaw
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)
