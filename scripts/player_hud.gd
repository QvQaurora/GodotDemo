extends CanvasLayer
## Screen-fixed player HUD (bottom-left health bar).


var _bar_bg: ColorRect
var _bar_fill: ColorRect
var _label: Label
var _player: Node


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	call_deferred("_bind_player")


func _build_ui() -> void:
	var root := Control.new()
	root.name = "HudRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var panel := PanelContainer.new()
	panel.name = "HpPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_left = 0.0
	panel.anchor_top = 1.0
	panel.anchor_right = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 24.0
	panel.offset_top = -78.0
	panel.offset_right = 280.0
	panel.offset_bottom = -24.0
	panel.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)

	_label = Label.new()
	_label.text = "生命 100 / 100"
	_label.add_theme_font_size_override("font_size", 16)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_label)

	var bar_host := Control.new()
	bar_host.custom_minimum_size = Vector2(220, 18)
	bar_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(bar_host)

	_bar_bg = ColorRect.new()
	_bar_bg.color = Color(0.08, 0.08, 0.1, 0.85)
	_bar_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_host.add_child(_bar_bg)

	_bar_fill = ColorRect.new()
	_bar_fill.color = Color(0.90, 0.20, 0.18, 0.95)
	_bar_fill.anchor_left = 0.0
	_bar_fill.anchor_top = 0.0
	_bar_fill.anchor_right = 1.0
	_bar_fill.anchor_bottom = 1.0
	_bar_fill.offset_left = 2.0
	_bar_fill.offset_top = 2.0
	_bar_fill.offset_right = -2.0
	_bar_fill.offset_bottom = -2.0
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_host.add_child(_bar_fill)


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.07, 0.55)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
	return sb


func _bind_player() -> void:
	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		await get_tree().process_frame
		_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		return
	if _player.has_signal("health_changed"):
		if not _player.health_changed.is_connected(_on_health_changed):
			_player.health_changed.connect(_on_health_changed)
	_sync_from_player()


func _sync_from_player() -> void:
	if _player == null:
		return
	var hp := float(_player.get("hp"))
	var hp_max := float(_player.get("hp_max"))
	_on_health_changed(hp, hp_max)


func _on_health_changed(hp: float, hp_max: float) -> void:
	var mx := maxf(hp_max, 0.001)
	var ratio := clampf(hp / mx, 0.0, 1.0)
	_label.text = "生命 %d / %d" % [int(round(hp)), int(round(hp_max))]
	# Ratio anchors so full HP always fills the bar host (minus 2px padding).
	_bar_fill.anchor_left = 0.0
	_bar_fill.anchor_right = ratio
	_bar_fill.offset_left = 2.0
	_bar_fill.offset_right = -2.0 if ratio > 0.001 else 2.0
