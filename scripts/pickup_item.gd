extends Area3D
## World treasure: approach and press Interact (default E) to collect.

@export var pickup_id: String = ""
@export var item_id: String = "gem"
@export var item_name: String = "闪光宝石"
@export var item_desc: String = "散落在林间的宝物。"
@export var item_color: Color = Color(0.95, 0.75, 0.2)
@export var amount: int = 1

var _player_near: bool = false
var _hint: Label3D


func _ready() -> void:
	add_to_group("world_pickup")
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 2
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if pickup_id == "":
		pickup_id = name
	_ensure_visual()
	_ensure_hint()
	set_process_unhandled_input(true)


func get_map_marker() -> Dictionary:
	return {
		"id": pickup_id,
		"x": global_position.x,
		"z": global_position.z,
		"name": item_name,
	}


func _ensure_visual() -> void:
	if has_node("Mesh"):
		return
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var mesh := SphereMesh.new()
	mesh.radius = 0.28
	mesh.height = 0.56
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = item_color
	mat.emission_enabled = true
	mat.emission = item_color
	mat.emission_energy_multiplier = 1.8
	mat.roughness = 0.25
	mi.material_override = mat
	mi.position = Vector3(0.0, 0.45, 0.0)
	add_child(mi)
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 1.4
	col.shape = shape
	col.position = Vector3(0.0, 0.5, 0.0)
	add_child(col)


func _ensure_hint() -> void:
	_hint = Label3D.new()
	_hint.name = "Hint"
	_hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hint.font_size = 48
	_hint.pixel_size = 0.012
	_hint.position = Vector3(0.0, 1.35, 0.0)
	_hint.visible = false
	add_child(_hint)
	_refresh_hint_text()
	if not GameSettings.keybinds_changed.is_connected(_refresh_hint_text):
		GameSettings.keybinds_changed.connect(_refresh_hint_text)


func _refresh_hint_text() -> void:
	if _hint == null:
		return
	_hint.text = "按 %s 拾取" % GameSettings.action_label("interact")


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_near = true
		if _hint:
			_hint.visible = true


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_near = false
		if _hint:
			_hint.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not _player_near or get_tree().paused:
		return
	if GameSettings.matches_action("interact", event):
		_try_pickup()
		get_viewport().set_input_as_handled()


func _try_pickup() -> void:
	var inv := get_tree().get_first_node_in_group("inventory_ui")
	if inv == null or not inv.has_method("add_item"):
		return
	var ok: bool = inv.call(
		"add_item",
		item_id,
		item_name,
		amount,
		item_desc,
		item_color
	)
	if not ok:
		if _hint:
			_hint.text = "背包已满"
		return
	var forest := get_tree().get_first_node_in_group("forest_world")
	if forest != null and forest.has_method("mark_pickup_collected"):
		forest.call("mark_pickup_collected", pickup_id)
	queue_free()
