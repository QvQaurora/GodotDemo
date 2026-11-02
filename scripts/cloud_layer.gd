extends Node3D
## Soft volumetric-looking clouds: clustered FIXED_Y billboards (standard stylized approach).
## Each cloud is several overlapping soft puffs so you never read a single paper card edge.


@export var cloud_count: int = 26
@export var puffs_per_cloud: int = 7
@export var height_min: float = 145.0
@export var height_max: float = 255.0
@export var spread: float = 1150.0
@export var drift_speed: float = 2.8
@export var seed_value: int = 11
@export var sun_distance: float = 780.0

var _mm: MultiMeshInstance3D
## Per puff: parent cloud index, local offset, size, speed/phase inherit from cloud.
var _cloud_origins: PackedVector3Array = PackedVector3Array()
var _cloud_speeds: PackedFloat32Array = PackedFloat32Array()
var _cloud_phases: PackedFloat32Array = PackedFloat32Array()
var _puff_cloud: PackedInt32Array = PackedInt32Array()
var _puff_offset: PackedVector3Array = PackedVector3Array()
var _puff_size: PackedVector2Array = PackedVector2Array()
var _instance_count: int = 0
var _time: float = 0.0
var _cloud_accum: float = 0.0
var _sun_core: MeshInstance3D
var _sun_glow: MeshInstance3D
var _sun_light: DirectionalLight3D


func _ready() -> void:
	_build_clouds()
	_build_sun()
	set_process(true)


func _soft_blob(p: Vector2, c: Vector2, rx: float, ry: float) -> float:
	var d := Vector2((p.x - c.x) / maxf(rx, 0.001), (p.y - c.y) / maxf(ry, 0.001))
	return exp(-d.length_squared() * 1.7)


func _build_cloud_texture(variant: int) -> ImageTexture:
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 100 + variant * 97
	var lobes: Array[Dictionary] = []
	# Cotton-ball stack: wide soft body + many overlapping lobes.
	lobes.append({
		"c": Vector2(0.50, 0.48),
		"rx": rng.randf_range(0.34, 0.42),
		"ry": rng.randf_range(0.24, 0.32),
	})
	lobes.append({
		"c": Vector2(0.38, 0.55),
		"rx": rng.randf_range(0.20, 0.28),
		"ry": rng.randf_range(0.18, 0.26),
	})
	lobes.append({
		"c": Vector2(0.64, 0.54),
		"rx": rng.randf_range(0.20, 0.28),
		"ry": rng.randf_range(0.18, 0.26),
	})
	for _i in rng.randi_range(10, 16):
		lobes.append({
			"c": Vector2(rng.randf_range(0.18, 0.82), rng.randf_range(0.30, 0.70)),
			"rx": rng.randf_range(0.08, 0.20),
			"ry": rng.randf_range(0.08, 0.18),
		})
	for y in size:
		for x in size:
			var p := Vector2(float(x) / float(size), float(y) / float(size))
			var dens := 0.0
			for lobe in lobes:
				dens += _soft_blob(p, lobe["c"], lobe["rx"], lobe["ry"])
			var radial := Vector2(p.x - 0.5, (p.y - 0.48) * 1.15).length()
			var edge := 1.0 - smoothstep(0.42, 0.78, radial)
			dens *= edge
			# Softer alpha ramp → feathered cotton edges instead of hard cards.
			var a := clampf(smoothstep(0.10, 0.95, dens), 0.0, 1.0)
			a = pow(a, 0.62) * 0.92
			# Gentle vertical lighting for volume without chalky contrast.
			var shade := lerpf(0.86, 1.0, smoothstep(0.70, 0.30, p.y))
			var lit := lerpf(0.95, 1.0, smoothstep(0.60, 0.25, p.y))
			var col := Color(0.97 * shade * lit, 0.98 * shade * lit, 1.0 * lit, a)
			img.set_pixel(x, y, col)
	img.resize(512, 512, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)


func _cloud_material(tex: Texture2D) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = tex
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.78)
	mat.vertex_color_use_as_albedo = true
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat.disable_receive_shadows = true
	# FIXED_Y: faces camera on yaw only — upright soft sprites, no paper edge when looking up.
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	mat.render_priority = -2
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.disable_fog = true
	return mat


func _puff_xform(pos: Vector3, size: Vector2) -> Transform3D:
	# Rotation is driven by FIXED_Y billboard; only position + scale matter.
	return Transform3D(Basis.from_scale(Vector3(size.x, size.y, 1.0)), pos)


func _build_clouds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var tex := _build_cloud_texture(0)
	var mat := _cloud_material(tex)
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1, 1)
	mesh.material = mat

	_instance_count = cloud_count * puffs_per_cloud
	_mm = MultiMeshInstance3D.new()
	_mm.name = "CloudPuffs"
	_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mm.extra_cull_margin = 180.0
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = _instance_count
	_mm.multimesh = mm
	add_child(_mm)

	_cloud_origins.resize(cloud_count)
	_cloud_speeds.resize(cloud_count)
	_cloud_phases.resize(cloud_count)
	_puff_cloud.resize(_instance_count)
	_puff_offset.resize(_instance_count)
	_puff_size.resize(_instance_count)

	var pi := 0
	for i in cloud_count:
		var ang := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(spread * 0.14, spread * 0.52)
		var y := rng.randf_range(height_min, height_max)
		_cloud_origins[i] = Vector3(cos(ang) * dist, y, sin(ang) * dist)
		_cloud_speeds[i] = rng.randf_range(0.45, 1.15)
		_cloud_phases[i] = rng.randf_range(0.0, TAU)
		var base_w := rng.randf_range(85.0, 155.0)
		for j in puffs_per_cloud:
			# Denser cluster with more vertical stack → fluffier white volumes.
			var ox := rng.randf_range(-0.62, 0.62) * base_w
			var oy := rng.randf_range(-0.18, 0.38) * base_w * 0.55
			var oz := rng.randf_range(-0.50, 0.50) * base_w
			var scale_mul := 1.15 if j == 0 else rng.randf_range(0.50, 0.98)
			var w := base_w * scale_mul * rng.randf_range(0.88, 1.18)
			var h := w * rng.randf_range(0.48, 0.72)
			_puff_cloud[pi] = i
			_puff_offset[pi] = Vector3(ox, oy, oz)
			_puff_size[pi] = Vector2(w, h)
			# Outer puffs slightly more transparent so the cluster softens.
			var a := 1.0 if j == 0 else rng.randf_range(0.55, 0.88)
			var tint := rng.randf_range(0.96, 1.0)
			mm.set_instance_color(pi, Color(tint, tint, 1.0, a))
			pi += 1
	_write_clouds()


func _build_sun_textures() -> Dictionary:
	var core_size := 160
	var core_img := Image.create(core_size, core_size, false, Image.FORMAT_RGBA8)
	var mid := core_size * 0.5
	for y in core_size:
		for x in core_size:
			var d := Vector2(x - mid, y - mid).length() / mid
			var disc := 1.0 - smoothstep(0.42, 0.52, d)
			var rim := (1.0 - smoothstep(0.48, 0.72, d)) * 0.55
			var a := maxf(disc, rim)
			var hot := 1.0 - smoothstep(0.0, 0.35, d)
			var col := Color(1.0, 0.82, 0.25, a).lerp(Color(1.0, 0.98, 0.88, a), hot)
			if disc > 0.85:
				col = Color(1.0, 1.0, 0.95, a)
			core_img.set_pixel(x, y, col)

	var glow_size := 256
	var glow_img := Image.create(glow_size, glow_size, false, Image.FORMAT_RGBA8)
	var gmid := glow_size * 0.5
	for y in glow_size:
		for x in glow_size:
			var d := Vector2(x - gmid, y - gmid).length() / gmid
			var a := pow(1.0 - smoothstep(0.08, 1.0, d), 2.4) * 0.55
			glow_img.set_pixel(x, y, Color(1.0, 0.72, 0.2, a))

	return {
		"core": ImageTexture.create_from_image(core_img),
		"glow": ImageTexture.create_from_image(glow_img),
	}


func _sun_material(tex: Texture2D, priority: int, additive: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = tex
	mat.albedo_color = Color(1, 1, 1, 1)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat.disable_receive_shadows = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.render_priority = priority
	mat.no_depth_test = true
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.disable_fog = true
	return mat


func _build_sun() -> void:
	_sun_light = get_parent().get_node_or_null("Sun") as DirectionalLight3D
	var texs := _build_sun_textures()

	_sun_glow = MeshInstance3D.new()
	_sun_glow.name = "SunGlow"
	_sun_glow.extra_cull_margin = 200.0
	var glow_mesh := QuadMesh.new()
	glow_mesh.size = Vector2(220, 220)
	glow_mesh.material = _sun_material(texs["glow"], 4, true)
	_sun_glow.mesh = glow_mesh
	_sun_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sun_glow)

	_sun_core = MeshInstance3D.new()
	_sun_core.name = "SunCore"
	_sun_core.extra_cull_margin = 200.0
	var core_mesh := QuadMesh.new()
	core_mesh.size = Vector2(88, 88)
	var core_mat := _sun_material(texs["core"], 5)
	core_mat.emission_enabled = true
	core_mat.emission = Color(1.0, 0.95, 0.7)
	core_mat.emission_energy_multiplier = 3.5
	core_mesh.material = core_mat
	_sun_core.mesh = core_mesh
	_sun_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sun_core)

	if _sun_light != null:
		_sun_light.light_energy = 1.45


func _wrap(v: float, half: float) -> float:
	return fposmod(v + half, half * 2.0) - half


func _write_clouds() -> void:
	if _mm == null:
		return
	var half := spread * 0.55
	for pi in _instance_count:
		var ci := _puff_cloud[pi]
		var drift := Vector3(1.0, 0.0, 0.2) * (drift_speed * _cloud_speeds[ci] * _time)
		var bob := sin(_time * 0.08 + _cloud_phases[ci]) * 2.5
		var base := _cloud_origins[ci] + drift
		base.x = _wrap(base.x, half)
		base.z = _wrap(base.z, half)
		base.y = _cloud_origins[ci].y + bob
		var pos := base + _puff_offset[pi]
		_mm.multimesh.set_instance_transform(pi, _puff_xform(pos, _puff_size[pi]))


func _update_sun() -> void:
	var dir := Vector3(0.32, 0.78, 0.54).normalized()
	if _sun_light != null:
		var light_dir := _sun_light.global_transform.basis.z.normalized()
		if light_dir.y > 0.2:
			dir = light_dir
	if dir.y < 0.62:
		var horiz := Vector3(dir.x, 0.0, dir.z)
		if horiz.length_squared() < 0.0001:
			horiz = Vector3(0.32, 0.0, 0.54)
		horiz = horiz.normalized()
		dir = (horiz * 0.58 + Vector3.UP * 0.81).normalized()
	var pos := dir * sun_distance
	if _sun_glow != null:
		_sun_glow.position = pos
	if _sun_core != null:
		_sun_core.position = pos


func _process(delta: float) -> void:
	_time += delta
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null:
		global_position.x = player.global_position.x
		global_position.z = player.global_position.z
		global_position.y = 0.0
	# Clouds drift slowly — no need to rewrite every frame.
	_cloud_accum += delta
	if _cloud_accum >= 0.12:
		_cloud_accum = 0.0
		_write_clouds()
	_update_sun()
