extends CanvasLayer
## Toggleable top-down forest map (default key: M).
## Hotkey uses the same GameSettings.matches_action + _input pattern as inventory (Tab).


@onready var dim: ColorRect = $Dim
@onready var title: Label = $Center/Panel/Margin/VBox/Title
@onready var hint: Label = $Center/Panel/Margin/VBox/Hint
@onready var map_view: ColorRect = $Center/Panel/Margin/VBox/MapView
@onready var legend: Label = $Center/Panel/Margin/VBox/Legend
@onready var close_btn: Button = $Center/Panel/Margin/VBox/CloseButton

var _open: bool = false
var _height_tex: ImageTexture
var _cached_data: Dictionary = {}
var _redraw_accum: float = 0.0
var _building_cache: bool = false


func _enter_tree() -> void:
	visible = false
	_open = false


func _ready() -> void:
	add_to_group("world_map_ui")
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)
	visible = false
	_open = false
	set_process(false)
	if dim != null:
		dim.mouse_filter = Control.MOUSE_FILTER_STOP
		if not dim.gui_input.is_connected(_on_dim_gui_input):
			dim.gui_input.connect(_on_dim_gui_input)
	var center := get_node_or_null("Center") as Control
	if center != null:
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := get_node_or_null("Center/Panel") as Control
	if panel != null:
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
	if map_view != null:
		map_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not map_view.draw.is_connected(_on_map_draw):
			map_view.draw.connect(_on_map_draw)
		if not map_view.resized.is_connected(_on_map_resized):
			map_view.resized.connect(_on_map_resized)
	if close_btn != null:
		close_btn.focus_mode = Control.FOCUS_NONE
		if not close_btn.pressed.is_connected(close_map):
			close_btn.pressed.connect(close_map)
	if legend != null:
		legend.text = "蓝池塘　灰道路　褐房屋　灰褐山体　绿动物　红怪物　黄宝物　▲朝向 · 上北下南"
	_refresh_hint()
	if not GameSettings.keybinds_changed.is_connected(_refresh_hint):
		GameSettings.keybinds_changed.connect(_refresh_hint)


func is_open() -> bool:
	return _open


func _refresh_hint() -> void:
	if hint == null:
		return
	hint.text = "按 %s / Esc / 关闭 退出地图 · 上方为北 (N)" % GameSettings.action_label("map")


func open_map() -> void:
	if _open:
		return
	var inv := get_tree().get_first_node_in_group("inventory_ui")
	if inv != null and inv.has_method("close_inventory"):
		inv.call("close_inventory")
	_open = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_hint()
	set_process(true)
	_building_cache = true
	_refresh_map_cache()
	_building_cache = false
	if map_view != null:
		map_view.queue_redraw()
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner != null:
		focus_owner.release_focus()


func close_map() -> void:
	if not _open:
		return
	_open = false
	visible = false
	set_process(false)
	_building_cache = false
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner != null:
		focus_owner.release_focus()
	if get_tree().paused:
		return
	if DisplayServer.window_is_focused():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func toggle() -> void:
	if _open:
		close_map()
	else:
		open_map()


func _process(delta: float) -> void:
	if not _open:
		return
	_redraw_accum += delta
	if _redraw_accum >= 0.2:
		_redraw_accum = 0.0
		if map_view != null:
			map_view.queue_redraw()


func _on_map_resized() -> void:
	if _open and map_view != null:
		map_view.queue_redraw()


func _on_dim_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close_map()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	# Same pattern as inventory.gd (Tab) / house interact (E).
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := event as InputEventKey
	if GameSettings.matches_action("map", event):
		if get_tree().paused and not _open:
			return
		toggle()
		get_viewport().set_input_as_handled()
		return
	if _open and (key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE):
		close_map()
		get_viewport().set_input_as_handled()


func _refresh_map_cache() -> void:
	var forest := get_tree().get_first_node_in_group("forest_world")
	if forest == null or not forest.has_method("get_map_data"):
		return
	var data: Dictionary = forest.call("get_map_data")
	if data.is_empty():
		return
	_cached_data = data
	var preview: Variant = data.get("height_preview", null)
	if preview is Image:
		_height_tex = ImageTexture.create_from_image(preview)
	else:
		_height_tex = null


func _world_to_map(wx: float, wz: float, origin: Vector2, side: float, world_size: float) -> Vector2:
	# World +X → East (right). World -Z → North (up on screen).
	var u := (wx / world_size) + 0.5
	var v := (wz / world_size) + 0.5
	return origin + Vector2(u * side, v * side)


func _draw_label(pos: Vector2, text: String, font_size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var text_sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	map_view.draw_string(font, pos - Vector2(text_sz.x * 0.5, -text_sz.y * 0.25), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_compass(origin: Vector2, side: float) -> void:
	var font := ThemeDB.fallback_font
	var n_col := Color(0.95, 0.35, 0.3, 1.0)
	var dim_col := Color(0.85, 0.9, 0.85, 0.95)
	_draw_label(Vector2(origin.x + side * 0.5, origin.y - 2.0), "N", 18, n_col)
	_draw_label(Vector2(origin.x + side * 0.5, origin.y + side + 16.0), "S", 16, dim_col)
	_draw_label(Vector2(origin.x - 12.0, origin.y + side * 0.5), "W", 16, dim_col)
	_draw_label(Vector2(origin.x + side + 12.0, origin.y + side * 0.5), "E", 16, dim_col)

	var c := origin + Vector2(side - 36.0, 36.0)
	map_view.draw_circle(c, 22.0, Color(0.08, 0.12, 0.1, 0.75))
	map_view.draw_circle(c, 22.0, Color(0.7, 0.8, 0.7, 0.85), false, 1.5)
	var arms := [
		{"d": Vector2(0, -1), "t": "N", "col": n_col},
		{"d": Vector2(0, 1), "t": "S", "col": dim_col},
		{"d": Vector2(-1, 0), "t": "W", "col": dim_col},
		{"d": Vector2(1, 0), "t": "E", "col": dim_col},
	]
	for arm in arms:
		var d: Vector2 = arm["d"]
		map_view.draw_line(c, c + d * 14.0, arm["col"], 2.0, true)
		var lp := c + d * 28.0
		var t: String = arm["t"]
		var ts := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		map_view.draw_string(font, lp - Vector2(ts.x * 0.5, -4.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, arm["col"])


func _draw_oriented_rect(center: Vector2, sx_px: float, sz_px: float, yaw: float, color: Color) -> void:
	var hx := sx_px * 0.5
	var hz := sz_px * 0.5
	var cos_y := cos(yaw)
	var sin_y := sin(yaw)
	var local := [
		Vector2(-hx, -hz),
		Vector2(hx, -hz),
		Vector2(hx, hz),
		Vector2(-hx, hz),
	]
	var pts := PackedVector2Array()
	for p in local:
		var wx: float = p.x * cos_y + p.y * sin_y
		var wz: float = -p.x * sin_y + p.y * cos_y
		pts.append(center + Vector2(wx, wz))
	map_view.draw_colored_polygon(pts, color)


func _draw_player_marker(pc: Vector2, look_xz: Vector2) -> void:
	var fwd := look_xz
	if fwd.length_squared() < 0.0001:
		fwd = Vector2(0.0, -1.0)
	else:
		fwd = fwd.normalized()
	var right := Vector2(fwd.y, -fwd.x)
	var tip := pc + fwd * 16.0
	var back := pc - fwd * 8.0
	var left := back + right * 9.0
	var right_pt := back - right * 9.0
	var pts := PackedVector2Array([tip, left, right_pt])
	map_view.draw_colored_polygon(pts, Color(1.0, 0.95, 0.35, 1.0))
	map_view.draw_polyline(PackedVector2Array([tip, left, right_pt, tip]), Color(0.15, 0.12, 0.05, 1.0), 2.0, true)
	map_view.draw_circle(pc, 3.0, Color(1, 1, 1, 1))


func _on_map_draw() -> void:
	if not _open:
		return
	var view_sz: Vector2 = map_view.size
	if view_sz.x < 8.0 or view_sz.y < 8.0:
		return
	var rect := Rect2(Vector2.ZERO, view_sz)
	map_view.draw_rect(rect, Color(0.08, 0.12, 0.1, 1.0))

	if _cached_data.is_empty() and not _building_cache:
		_refresh_map_cache()
	if _cached_data.is_empty():
		map_view.draw_string(ThemeDB.fallback_font, Vector2(16, 28), "地图数据不可用", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.7))
		return

	var data := _cached_data
	var world_size: float = maxf(float(data.get("size", 1000.0)), 1.0)
	var pad := 28.0
	var side := mini(rect.size.x, rect.size.y) - pad * 2.0
	if side < 8.0:
		return
	var origin := Vector2((rect.size.x - side) * 0.5, (rect.size.y - side) * 0.5)
	var map_rect := Rect2(origin, Vector2(side, side))

	if _height_tex != null:
		map_view.draw_texture_rect(_height_tex, map_rect, false)
	else:
		map_view.draw_rect(map_rect, Color(0.2, 0.36, 0.2, 1.0))

	map_view.draw_rect(map_rect, Color(0.05, 0.08, 0.05, 0.15), false, 8.0)
	map_view.draw_rect(map_rect, Color(0.55, 0.7, 0.55, 0.95), false, 2.0)

	var grid_step := 100.0
	var half := world_size * 0.5
	var gx := -half
	while gx <= half + 0.1:
		var a := _world_to_map(gx, -half, origin, side, world_size)
		var b := _world_to_map(gx, half, origin, side, world_size)
		var major := absf(gx) < 0.1 or absf(absf(gx) - half) < 0.1
		map_view.draw_line(a, b, Color(1, 1, 1, 0.12 if not major else 0.22), 1.0 if not major else 1.5, true)
		gx += grid_step
	var gz := -half
	while gz <= half + 0.1:
		var a2 := _world_to_map(-half, gz, origin, side, world_size)
		var b2 := _world_to_map(half, gz, origin, side, world_size)
		var major2 := absf(gz) < 0.1 or absf(absf(gz) - half) < 0.1
		map_view.draw_line(a2, b2, Color(1, 1, 1, 0.12 if not major2 else 0.22), 1.0 if not major2 else 1.5, true)
		gz += grid_step

	var meters_to_px := side / world_size

	for mtn in data.get("mountains", []):
		if typeof(mtn) != TYPE_VECTOR3:
			continue
		var m: Vector3 = mtn
		var mc := _world_to_map(m.x, m.z, origin, side, world_size)
		map_view.draw_circle(mc, m.y * meters_to_px, Color(0.48, 0.44, 0.38, 0.72))

	var road_w_px: float = maxf(float(data.get("road_width", 10.0)) * meters_to_px, 1.0)
	for path in data.get("roads", []):
		if typeof(path) != TYPE_ARRAY or path.size() < 2:
			continue
		for i in range(path.size() - 1):
			var a_v: Variant = path[i]
			var b_v: Variant = path[i + 1]
			if typeof(a_v) != TYPE_VECTOR3 or typeof(b_v) != TYPE_VECTOR3:
				continue
			var a: Vector3 = a_v
			var b: Vector3 = b_v
			map_view.draw_line(
				_world_to_map(a.x, a.z, origin, side, world_size),
				_world_to_map(b.x, b.z, origin, side, world_size),
				Color(0.55, 0.55, 0.52, 1.0),
				road_w_px,
				true
			)

	for pond in data.get("ponds", []):
		if typeof(pond) != TYPE_VECTOR3:
			continue
		var p: Vector3 = pond
		map_view.draw_circle(_world_to_map(p.x, p.z, origin, side, world_size), p.y * meters_to_px, Color(0.28, 0.52, 0.75, 0.92))

	for house_item in data.get("houses", []):
		if typeof(house_item) == TYPE_DICTIONARY:
			var hd: Dictionary = house_item
			var hc: Vector2 = _world_to_map(float(hd.get("x", 0.0)), float(hd.get("z", 0.0)), origin, side, world_size)
			var house_sx := float(hd.get("sx", 8.0)) * meters_to_px
			var house_sz := float(hd.get("sz", 8.0)) * meters_to_px
			if bool(hd.get("circle", false)):
				map_view.draw_circle(hc, maxf(house_sx, house_sz) * 0.5, Color(0.78, 0.58, 0.36, 0.95))
			else:
				_draw_oriented_rect(hc, house_sx, house_sz, float(hd.get("yaw", 0.0)), Color(0.78, 0.58, 0.36, 0.95))
		elif typeof(house_item) == TYPE_VECTOR3:
			var h: Vector3 = house_item
			map_view.draw_circle(_world_to_map(h.x, h.z, origin, side, world_size), h.y * meters_to_px, Color(0.78, 0.58, 0.36, 0.95))

	for actor in data.get("actors", []):
		if typeof(actor) != TYPE_DICTIONARY:
			continue
		var ad: Dictionary = actor
		var ac: Vector2 = _world_to_map(float(ad.get("x", 0.0)), float(ad.get("z", 0.0)), origin, side, world_size)
		var kind := int(ad.get("kind", 0))
		var col := Color(0.35, 0.85, 0.4, 0.95) if kind == 0 else Color(0.9, 0.28, 0.28, 0.95)
		map_view.draw_circle(ac, maxf(2.2, 1.0 * meters_to_px), col)

	for gem in data.get("pickups", []):
		if typeof(gem) != TYPE_DICTIONARY:
			continue
		var g: Dictionary = gem
		var gc: Vector2 = _world_to_map(float(g.get("x", 0.0)), float(g.get("z", 0.0)), origin, side, world_size)
		map_view.draw_circle(gc, maxf(2.5, 1.2 * meters_to_px), Color(1.0, 0.88, 0.2, 1.0))

	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null:
		var pc: Vector2 = _world_to_map(player.global_position.x, player.global_position.z, origin, side, world_size)
		var look3 := -player.global_transform.basis.z
		_draw_player_marker(pc, Vector2(look3.x, look3.z))

	_draw_compass(origin, side)

	var bar_m := 200.0
	var bar_px := (bar_m / world_size) * side
	var bar_pos := Vector2(origin.x + 10.0, origin.y + side - 18.0)
	map_view.draw_line(bar_pos, bar_pos + Vector2(bar_px, 0), Color(1, 1, 1, 0.85), 3.0, true)
	map_view.draw_line(bar_pos + Vector2(0, -4), bar_pos + Vector2(0, 4), Color(1, 1, 1, 0.85), 2.0, true)
	map_view.draw_line(bar_pos + Vector2(bar_px, -4), bar_pos + Vector2(bar_px, 4), Color(1, 1, 1, 0.85), 2.0, true)
	map_view.draw_string(ThemeDB.fallback_font, bar_pos + Vector2(0, -8), "200 m", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.85))
