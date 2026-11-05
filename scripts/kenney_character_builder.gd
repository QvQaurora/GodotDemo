extends RefCounted
## Shared Kenney character instantiate + skin + idle anim for player / preview.

const Catalog = preload("res://scripts/character_catalog.gd")


static func spawn(
	parent: Node3D,
	body_id: String,
	outfit_id: String,
	yaw_offset: float = PI,
	gear: Dictionary = {}
) -> Dictionary:
	## Returns { root, visual, anim, skeleton } or empty on failure.
	for child in parent.get_children():
		child.queue_free()

	body_id = Catalog.resolve_existing_body_id(body_id)
	outfit_id = Catalog.resolve_existing_outfit_id(outfit_id)
	gear = Catalog.sanitize_gear(gear)
	var character_path := Catalog.body_path(body_id)
	var skin := Catalog.skin_path(outfit_id)
	var character_height := Catalog.body_height(body_id)

	var packed := load(character_path) as PackedScene
	if packed == null:
		push_warning("Kenney character missing: " + character_path)
		return {}
	var root := packed.instantiate()
	if root == null:
		return {}

	_apply_skin_texture(root, skin)
	_normalize_fbx_root_scale(root)
	var aabb := _combined_aabb(root)
	# Prefer vertical extent; fall back to longest axis if the mesh lies oddly.
	var native_h := maxf(aabb.size.y, 0.01)
	if aabb.size.y < aabb.size.x * 0.35 and aabb.size.y < aabb.size.z * 0.35:
		native_h = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	var s := character_height / native_h

	var visual := Node3D.new()
	visual.name = "KenneyVisual"
	visual.rotation.y = yaw_offset
	visual.scale = Vector3(s, s, s)
	visual.position = Vector3(0.0, -aabb.position.y * s, 0.0)
	parent.add_child(visual)
	visual.add_child(root)

	var skeleton := _find_skeleton(root)
	_attach_gear(skeleton, gear)
	var anim := AnimationPlayer.new()
	anim.name = "AnimationPlayer"
	root.add_child(anim)
	var lib := AnimationLibrary.new()
	anim.add_animation_library("", lib)
	_import_anim_clip(lib, "res://assets/kenney_characters/Animations/idle.fbx", "Root|Idle", "idle", true)
	_import_anim_clip(lib, "res://assets/kenney_characters/Animations/run.fbx", "Root|Run", "run", true)
	_import_anim_clip(lib, "res://assets/kenney_characters/Animations/jump.fbx", "Root|Jump", "jump", false)
	if anim.has_animation("idle"):
		anim.play("idle")

	return {
		"root": root,
		"visual": visual,
		"anim": anim,
		"skeleton": skeleton,
		"body_id": body_id,
		"outfit_id": outfit_id,
		"gear": gear,
		"height": character_height,
	}


static func _attach_gear(skeleton: Skeleton3D, gear: Dictionary) -> void:
	if skeleton == null:
		return
	for slot_id in gear.keys():
		var acc_id := str(gear[slot_id])
		if acc_id == "":
			continue
		var acc := Catalog.find_accessory(acc_id)
		if acc.is_empty():
			continue
		var fit := Catalog.accessory_fit(acc)
		var bone_name := str(fit.get("bone", "Head"))
		var bone_idx := skeleton.find_bone(bone_name)
		if bone_idx < 0:
			# Head_end missing on some imports — fall back.
			if bone_name == "Head_end":
				bone_name = "Head"
				bone_idx = skeleton.find_bone(bone_name)
			elif bone_name == "UpperChest":
				bone_name = "Chest"
				bone_idx = skeleton.find_bone(bone_name)
		if bone_idx < 0:
			push_warning("Missing bone for accessory: " + bone_name)
			continue
		var path := Catalog.accessory_path(acc_id)
		var packed := load(path) as PackedScene
		if packed == null:
			continue
		var piece := packed.instantiate()
		if piece == null:
			continue
		_prepare_accessory_meshes(piece)
		var attach := BoneAttachment3D.new()
		attach.name = "Gear_%s" % slot_id
		attach.bone_idx = bone_idx
		attach.bone_name = bone_name
		skeleton.add_child(attach)
		var holder := Node3D.new()
		holder.name = "AccXform"
		var sc := float(fit.get("scale", Catalog.ACC_BONE_SCALE))
		holder.scale = Vector3(sc, sc, sc)
		var off: Variant = fit.get("offset", Vector3.ZERO)
		if typeof(off) == TYPE_VECTOR3:
			holder.position = off
		var rot: Variant = fit.get("rot_deg", Vector3.ZERO)
		if typeof(rot) == TYPE_VECTOR3:
			holder.rotation_degrees = rot
		attach.add_child(holder)
		holder.add_child(piece)


static func _prepare_accessory_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		# Slight push so thin glasses/hair don't z-fight the face.
		mi.sorting_offset = 0.02
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var base := mi.get_active_material(i)
				var mat: StandardMaterial3D
				if base is StandardMaterial3D:
					mat = (base as StandardMaterial3D).duplicate() as StandardMaterial3D
				else:
					mat = StandardMaterial3D.new()
					if base != null:
						mat.albedo_color = Color(0.85, 0.85, 0.85)
				# Avoid depth fighting / vanishing inside head.
				mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
				mi.set_surface_override_material(i, mat)
	for child in node.get_children():
		_prepare_accessory_meshes(child)


static func _normalize_fbx_root_scale(node: Node) -> void:
	## Kenney medium mesh is ~0.04m locally with Root×100. Small/large meshes are
	## already ~meter sized but still carry Root×100, which inflates them ~100×.
	var root_n := node.get_node_or_null("Root") as Node3D
	if root_n == null:
		return
	var mi := _find_first_mesh(node)
	if mi == null or mi.mesh == null:
		return
	var longest := _vec3_max_abs(mi.mesh.get_aabb().size)
	if longest > 0.5 and root_n.scale.x >= 50.0:
		root_n.scale = Vector3.ONE


static func _find_first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_first_mesh(child)
		if found != null:
			return found
	return null


static func _vec3_max_abs(v: Vector3) -> float:
	return maxf(absf(v.x), maxf(absf(v.y), absf(v.z)))


static func _apply_skin_texture(node: Node, skin_path: String) -> void:
	var tex := load(skin_path) as Texture2D
	if tex == null:
		return
	_apply_tex_recursive(node, tex)


static func _apply_tex_recursive(node: Node, tex: Texture2D) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var base := mi.get_active_material(i)
				var mat: StandardMaterial3D
				if base is StandardMaterial3D:
					mat = (base as StandardMaterial3D).duplicate() as StandardMaterial3D
				else:
					mat = StandardMaterial3D.new()
				mat.albedo_texture = tex
				mat.albedo_color = Color(1, 1, 1)
				mat.roughness = 0.85
				mi.set_surface_override_material(i, mat)
	for child in node.get_children():
		_apply_tex_recursive(child, tex)


static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


static func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


static func _import_anim_clip(lib: AnimationLibrary, res_path: String, src_name: String, dest_name: String, loop: bool) -> void:
	var packed := load(res_path) as PackedScene
	if packed == null:
		return
	var scene := packed.instantiate()
	if scene == null:
		return
	var src_ap := _find_animation_player(scene)
	if src_ap == null:
		scene.free()
		return
	if not src_ap.has_animation(src_name):
		var fallback := ""
		for n in src_ap.get_animation_list():
			var sn := String(n)
			if sn.ends_with("Idle") and dest_name == "idle":
				fallback = sn
			elif sn.ends_with("Run") and dest_name == "run":
				fallback = sn
			elif sn.ends_with("Jump") and dest_name == "jump":
				fallback = sn
		if fallback == "":
			scene.free()
			return
		src_name = fallback
	var anim: Animation = src_ap.get_animation(src_name).duplicate(true)
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	lib.add_animation(dest_name, anim)
	scene.free()


static func _combined_aabb(node: Node) -> AABB:
	var boxes: Array[AABB] = []
	_collect_mesh_aabbs(node, Transform3D.IDENTITY, boxes)
	if boxes.is_empty():
		return AABB(Vector3(-0.4, 0.0, -0.2), Vector3(0.8, 1.8, 0.4))
	var result: AABB = boxes[0]
	for i in range(1, boxes.size()):
		result = result.merge(boxes[i])
	return result


static func _collect_mesh_aabbs(node: Node, parent_xf: Transform3D, out: Array[AABB]) -> void:
	var xf := parent_xf
	if node is Node3D:
		xf = parent_xf * (node as Node3D).transform
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			out.append(xf * mi.mesh.get_aabb())
	for child in node.get_children():
		_collect_mesh_aabbs(child, xf, out)
