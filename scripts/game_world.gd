extends Node3D
## Game scene bootstrap (boot overlay + save apply).


var _boot_layer: CanvasLayer
var _boot_dim: ColorRect
var _boot_title: Label
var _boot_hint: Label


func _ready() -> void:
	_show_boot_overlay()
	call_deferred("_bootstrap")


func _show_boot_overlay() -> void:
	_boot_layer = CanvasLayer.new()
	_boot_layer.name = "BootOverlay"
	_boot_layer.layer = 128
	_boot_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_boot_layer.add_to_group("boot_overlay")
	add_child(_boot_layer)

	_boot_dim = ColorRect.new()
	_boot_dim.color = Color(0.08, 0.12, 0.09, 1.0)
	_boot_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_boot_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_boot_layer.add_child(_boot_dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boot_layer.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	center.add_child(vbox)

	_boot_title = Label.new()
	_boot_title.text = "正在加载森林..."
	_boot_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boot_title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(_boot_title)

	_boot_hint = Label.new()
	_boot_hint.text = "准备地形与附近场景"
	_boot_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boot_hint.modulate = Color(0.7, 0.78, 0.7, 1.0)
	vbox.add_child(_boot_hint)


func _set_boot_hint(text: String) -> void:
	if _boot_hint != null:
		_boot_hint.text = text


func _hide_boot_overlay() -> void:
	var layer := _boot_layer
	_boot_layer = null
	_boot_dim = null
	_boot_title = null
	_boot_hint = null
	if layer != null and is_instance_valid(layer):
		layer.queue_free()
	for n in get_tree().get_nodes_in_group("boot_overlay"):
		if is_instance_valid(n):
			n.queue_free()
	await get_tree().process_frame


func _bootstrap() -> void:
	GameSettings.apply_audio()
	GameSettings.apply_graphics()
	_set_boot_hint("生成世界中...")

	var forest: Node = null
	for _i in 1800:
		forest = get_tree().get_first_node_in_group("forest_world")
		if forest != null and bool(forest.get("world_ready")):
			break
		await get_tree().process_frame

	if GameSave.pending_load:
		GameSave.pending_load = false
		_set_boot_hint("读取存档...")
		if forest != null and bool(forest.get("world_ready")):
			GameSave.apply_to_world(get_tree())
			if forest.has_method("refresh_world_stream"):
				forest.call("refresh_world_stream")
			await get_tree().process_frame
		else:
			push_warning("Save load: forest not ready in time")

	GameSettings.apply_graphics()
	_set_boot_hint("即将开始")
	await get_tree().process_frame
	var map_ui := get_tree().get_first_node_in_group("world_map_ui")
	if map_ui != null and map_ui.has_method("close_map"):
		map_ui.call("close_map")
	await _hide_boot_overlay()
	DisplayServer.window_set_ime_active(false)
