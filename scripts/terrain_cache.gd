class_name TerrainCache
extends RefCounted
## Binary cache for heightmap + road distance mask (skips heavy rebuilds on reload).


const MAGIC := 0x54455252 # "TERR"
const VERSION := 2


static func cache_path(seed_value: int, terrain_size: float, height_res: int, extras: String) -> String:
	var key := "terrain_s%d_sz%d_r%d_%s.bin" % [seed_value, int(terrain_size), height_res, extras]
	return "user://cache/%s" % key


static func ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://cache"))


static func try_load(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	if f.get_32() != MAGIC:
		return {}
	if f.get_32() != VERSION:
		return {}
	var height_res := int(f.get_32())
	var count := height_res * height_res
	var heights := PackedFloat32Array()
	heights.resize(count)
	for i in count:
		heights[i] = f.get_float()
	var natural := PackedFloat32Array()
	natural.resize(count)
	for i in count:
		natural[i] = f.get_float()
	var png_size := int(f.get_64())
	if png_size <= 0 or png_size > 64 * 1024 * 1024:
		return {}
	var png := f.get_buffer(png_size)
	var img := Image.new()
	if img.load_png_from_buffer(png) != OK:
		return {}
	return {
		"height_res": height_res,
		"heights": heights,
		"natural_heights": natural,
		"road_mask": ImageTexture.create_from_image(img),
	}


static func save(
	path: String,
	height_res: int,
	heights: PackedFloat32Array,
	natural_heights: PackedFloat32Array,
	road_mask: Texture2D
) -> bool:
	ensure_dir()
	if heights.size() != height_res * height_res:
		return false
	var img: Image = null
	if road_mask is ImageTexture:
		img = (road_mask as ImageTexture).get_image()
	if img == null:
		return false
	var png := img.save_png_to_buffer()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_32(MAGIC)
	f.store_32(VERSION)
	f.store_32(height_res)
	for i in heights.size():
		f.store_float(heights[i])
	for i in natural_heights.size():
		f.store_float(natural_heights[i])
	f.store_64(png.size())
	f.store_buffer(png)
	return true
