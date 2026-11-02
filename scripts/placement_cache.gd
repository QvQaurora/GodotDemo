extends RefCounted
## Binary cache for streamed prop placements (trees/rocks/bushes/flowers/actors/treasures).
## Grass is intentionally excluded — it is generated per-chunk on demand.


const MAGIC := 0x504C4331 # "PLC1"
const VERSION := 1


static func cache_path(seed_value: int, terrain_size: float, extras: String) -> String:
	var key := "place_s%d_sz%d_%s.bin" % [seed_value, int(terrain_size), extras]
	return "user://cache/%s" % key


static func ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://cache"))


static func try_load(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	if f.get_32() != MAGIC or f.get_32() != VERSION:
		return {}
	var trees := _read_xf_items(f, true)
	var rocks := _read_rocks(f)
	var bushes := _read_xf_items(f, false)
	var flowers := _read_flowers(f)
	var actors := _read_actors(f)
	var treasures := _read_treasures(f)
	return {
		"trees": trees,
		"rocks": rocks,
		"bushes": bushes,
		"flowers": flowers,
		"actors": actors,
		"treasures": treasures,
	}


static func save(path: String, data: Dictionary) -> bool:
	ensure_dir()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_32(MAGIC)
	f.store_32(VERSION)
	_write_xf_items(f, data.get("trees", []), true)
	_write_rocks(f, data.get("rocks", []))
	_write_xf_items(f, data.get("bushes", []), false)
	_write_flowers(f, data.get("flowers", []))
	_write_actors(f, data.get("actors", []))
	_write_treasures(f, data.get("treasures", []))
	return true


static func _store_xform(f: FileAccess, xf: Transform3D) -> void:
	var b := xf.basis
	f.store_float(b.x.x); f.store_float(b.x.y); f.store_float(b.x.z)
	f.store_float(b.y.x); f.store_float(b.y.y); f.store_float(b.y.z)
	f.store_float(b.z.x); f.store_float(b.z.y); f.store_float(b.z.z)
	f.store_float(xf.origin.x); f.store_float(xf.origin.y); f.store_float(xf.origin.z)


static func _read_xform(f: FileAccess) -> Transform3D:
	var basis := Basis(
		Vector3(f.get_float(), f.get_float(), f.get_float()),
		Vector3(f.get_float(), f.get_float(), f.get_float()),
		Vector3(f.get_float(), f.get_float(), f.get_float())
	)
	var origin := Vector3(f.get_float(), f.get_float(), f.get_float())
	return Transform3D(basis, origin)


static func _store_string(f: FileAccess, s: String) -> void:
	var buf := s.to_utf8_buffer()
	f.store_32(buf.size())
	f.store_buffer(buf)


static func _read_string(f: FileAccess) -> String:
	var n := int(f.get_32())
	if n <= 0 or n > 1_000_000:
		return ""
	return f.get_buffer(n).get_string_from_utf8()


static func _write_xf_items(f: FileAccess, items: Array, with_col: bool) -> void:
	f.store_32(items.size())
	for it in items:
		_store_xform(f, it["xf"])
		f.store_32(int(it["type"]))
		if with_col:
			f.store_float(float(it.get("col_r", 0.2)))
			f.store_float(float(it.get("col_h", 1.0)))
		else:
			f.store_float(float(it.get("col_r", 0.3)))


static func _read_xf_items(f: FileAccess, with_col: bool) -> Array:
	var n := int(f.get_32())
	var out: Array = []
	out.resize(n)
	for i in n:
		var xf := _read_xform(f)
		var t := int(f.get_32())
		if with_col:
			out[i] = {"xf": xf, "type": t, "col_r": f.get_float(), "col_h": f.get_float()}
		else:
			out[i] = {"xf": xf, "type": t, "col_r": f.get_float()}
	return out


static func _write_flowers(f: FileAccess, items: Array) -> void:
	f.store_32(items.size())
	for it in items:
		_store_xform(f, it["xf"])
		f.store_32(int(it["type"]))


static func _read_flowers(f: FileAccess) -> Array:
	var n := int(f.get_32())
	var out: Array = []
	out.resize(n)
	for i in n:
		out[i] = {"xf": _read_xform(f), "type": int(f.get_32())}
	return out


static func _write_rocks(f: FileAccess, items: Array) -> void:
	f.store_32(items.size())
	for it in items:
		_store_xform(f, it["xf"])
		f.store_32(int(it["type"]))
		var col: Dictionary = it.get("col", {})
		var shape := int(col.get("shape", 0))
		f.store_32(shape)
		if shape == 1:
			var size: Vector3 = col.get("size", Vector3.ONE)
			f.store_float(size.x); f.store_float(size.y); f.store_float(size.z)
			f.store_float(float(col.get("yaw", 0.0)))
		else:
			f.store_float(float(col.get("radius", 0.5)))


static func _read_rocks(f: FileAccess) -> Array:
	var n := int(f.get_32())
	var out: Array = []
	out.resize(n)
	for i in n:
		var xf := _read_xform(f)
		var t := int(f.get_32())
		var shape := int(f.get_32())
		var col: Dictionary
		if shape == 1:
			col = {
				"shape": 1,
				"size": Vector3(f.get_float(), f.get_float(), f.get_float()),
				"yaw": f.get_float(),
			}
		else:
			col = {"shape": 0, "radius": f.get_float()}
		out[i] = {"xf": xf, "type": t, "col": col}
	return out


static func _write_actors(f: FileAccess, items: Array) -> void:
	f.store_32(items.size())
	for it in items:
		_store_string(f, str(it.get("id", "")))
		f.store_32(int(it.get("kind", 0)))
		_store_string(f, str(it.get("path", "")))
		var p: Vector3 = it.get("pos", Vector3.ZERO)
		f.store_float(p.x); f.store_float(p.y); f.store_float(p.z)
		f.store_float(float(it.get("yaw", 0.0)))
		f.store_float(float(it.get("height", 1.2)))
		_store_string(f, str(it.get("name", "")))


static func _read_actors(f: FileAccess) -> Array:
	var n := int(f.get_32())
	var out: Array = []
	out.resize(n)
	for i in n:
		out[i] = {
			"id": _read_string(f),
			"kind": int(f.get_32()),
			"path": _read_string(f),
			"pos": Vector3(f.get_float(), f.get_float(), f.get_float()),
			"yaw": f.get_float(),
			"height": f.get_float(),
			"name": _read_string(f),
		}
	return out


static func _write_treasures(f: FileAccess, items: Array) -> void:
	f.store_32(items.size())
	for it in items:
		_store_string(f, str(it.get("id", "")))
		_store_string(f, str(it.get("item_id", "")))
		_store_string(f, str(it.get("item_name", "")))
		_store_string(f, str(it.get("item_desc", "")))
		var c: Color = it.get("item_color", Color.WHITE)
		f.store_float(c.r); f.store_float(c.g); f.store_float(c.b); f.store_float(c.a)
		f.store_32(int(it.get("amount", 1)))
		var p: Vector3 = it.get("pos", Vector3.ZERO)
		f.store_float(p.x); f.store_float(p.y); f.store_float(p.z)


static func _read_treasures(f: FileAccess) -> Array:
	var n := int(f.get_32())
	var out: Array = []
	out.resize(n)
	for i in n:
		out[i] = {
			"id": _read_string(f),
			"item_id": _read_string(f),
			"item_name": _read_string(f),
			"item_desc": _read_string(f),
			"item_color": Color(f.get_float(), f.get_float(), f.get_float(), f.get_float()),
			"amount": int(f.get_32()),
			"pos": Vector3(f.get_float(), f.get_float(), f.get_float()),
		}
	return out
