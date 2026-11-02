extends RefCounted
## Copies shipped baked caches from res:// into user:// so first launch on other PCs skips heavy baking.


const BAKED_DIR := "res://baked_cache"
const USER_DIR := "user://cache"


static func seed_all() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(USER_DIR))
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(BAKED_DIR)):
		# Editor may not have imported folder yet — try listing via DirAccess.
		pass
	var dir := DirAccess.open(BAKED_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".bin"):
			var src := "%s/%s" % [BAKED_DIR, name]
			var dst := "%s/%s" % [USER_DIR, name]
			if not FileAccess.file_exists(dst):
				_copy_file(src, dst)
		name = dir.get_next()
	dir.list_dir_end()


static func _copy_file(src: String, dst: String) -> void:
	var in_f := FileAccess.open(src, FileAccess.READ)
	if in_f == null:
		return
	var bytes := in_f.get_buffer(in_f.get_length())
	in_f = null
	var out_f := FileAccess.open(dst, FileAccess.WRITE)
	if out_f == null:
		return
	out_f.store_buffer(bytes)
	print("Seeded cache: ", dst)
