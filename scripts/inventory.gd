extends CanvasLayer
## Tab backpack: empty grid inventory (filled via gameplay / save).

const COLS := 5
const ROWS := 4
const SLOT_COUNT := COLS * ROWS

@onready var dim: ColorRect = $Dim
@onready var title: Label = $Center/Panel/Margin/VBox/Title
@onready var hint: Label = $Center/Panel/Margin/VBox/Hint
@onready var grid: GridContainer = $Center/Panel/Margin/VBox/Grid
@onready var detail: Label = $Center/Panel/Margin/VBox/Detail
@onready var close_btn: Button = $Center/Panel/Margin/VBox/CloseButton

var _open: bool = false
## Each entry: null or { "id": String, "name": String, "count": int, "desc": String, "color": Color }
var _slots: Array = []
var _slot_buttons: Array[Button] = []
var _selected: int = -1


func _ready() -> void:
	add_to_group("inventory_ui")
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)
	visible = false
	_open = false
	_init_slots()
	_build_grid()
	_refresh_grid()
	_set_detail(-1)
	if close_btn != null:
		close_btn.focus_mode = Control.FOCUS_NONE
		close_btn.pressed.connect(close_inventory)


func is_open() -> bool:
	return _open


func open_inventory() -> void:
	if _open:
		return
	_open = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_grid()
	# Avoid keyboard focus so Tab isn't eaten by Control focus cycling.
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner != null:
		focus_owner.release_focus()


func close_inventory() -> void:
	if not _open:
		return
	_open = false
	visible = false
	_selected = -1
	_set_detail(-1)
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
		close_inventory()
	else:
		open_inventory()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := event as InputEventKey
	if GameSettings.matches_action("inventory", event):
		if get_tree().paused and not _open:
			return
		var map_ui := get_tree().get_first_node_in_group("world_map_ui")
		if map_ui != null and map_ui.has_method("is_open") and bool(map_ui.call("is_open")):
			map_ui.call("close_map")
		toggle()
		get_viewport().set_input_as_handled()
		return
	if _open and (key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE):
		close_inventory()
		get_viewport().set_input_as_handled()


func _init_slots() -> void:
	_slots.clear()
	_slots.resize(SLOT_COUNT)
	_slots.fill(null)


func clear_all() -> void:
	_init_slots()
	_selected = -1
	_set_detail(-1)
	if not _slot_buttons.is_empty():
		_refresh_grid()


func get_save_data() -> Array:
	var out: Array = []
	out.resize(SLOT_COUNT)
	for i in SLOT_COUNT:
		var item = _slots[i]
		if item == null:
			out[i] = null
			continue
		var c: Color = item["color"]
		out[i] = {
			"id": str(item["id"]),
			"name": str(item["name"]),
			"count": int(item["count"]),
			"desc": str(item["desc"]),
			"color": [c.r, c.g, c.b, c.a],
		}
	return out


func add_item(id: String, item_name: String, count: int, desc: String, color: Color) -> bool:
	# Stack into existing slot with same id, else first empty slot.
	for i in SLOT_COUNT:
		var item = _slots[i]
		if item != null and str(item["id"]) == id:
			item["count"] = int(item["count"]) + count
			_slots[i] = item
			_refresh_grid()
			return true
	for i in SLOT_COUNT:
		if _slots[i] == null:
			_slots[i] = {
				"id": id,
				"name": item_name,
				"count": count,
				"desc": desc,
				"color": color,
			}
			_refresh_grid()
			return true
	return false


func apply_save_data(data: Variant) -> void:
	_init_slots()
	if typeof(data) != TYPE_ARRAY:
		_refresh_grid()
		return
	var arr := data as Array
	for i in mini(SLOT_COUNT, arr.size()):
		var item = arr[i]
		if item == null or typeof(item) != TYPE_DICTIONARY:
			continue
		var d := item as Dictionary
		var col := Color(0.7, 0.7, 0.7)
		if d.has("color") and typeof(d["color"]) == TYPE_ARRAY:
			var ca: Array = d["color"]
			if ca.size() >= 3:
				col = Color(float(ca[0]), float(ca[1]), float(ca[2]), float(ca[3]) if ca.size() > 3 else 1.0)
		_slots[i] = {
			"id": str(d.get("id", "")),
			"name": str(d.get("name", "")),
			"count": int(d.get("count", 1)),
			"desc": str(d.get("desc", "")),
			"color": col,
		}
	_selected = -1
	_set_detail(-1)
	if not _slot_buttons.is_empty():
		_refresh_grid()


func _build_grid() -> void:
	for child in grid.get_children():
		child.queue_free()
	_slot_buttons.clear()
	grid.columns = COLS
	for i in SLOT_COUNT:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(92, 92)
		# Mouse only — keyboard Tab must remain free to close the backpack.
		btn.focus_mode = Control.FOCUS_NONE
		btn.clip_text = true
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		var idx := i
		btn.pressed.connect(func() -> void: _on_slot_pressed(idx))
		grid.add_child(btn)
		_slot_buttons.append(btn)


func _refresh_grid() -> void:
	for i in SLOT_COUNT:
		var btn := _slot_buttons[i]
		var item = _slots[i]
		if item == null:
			btn.text = ""
			btn.modulate = Color(1, 1, 1, 0.85)
			btn.tooltip_text = "空栏位"
		else:
			btn.text = "%s\nx%d" % [str(item["name"]), int(item["count"])]
			var c: Color = item["color"]
			btn.modulate = Color(lerpf(c.r, 1.0, 0.35), lerpf(c.g, 1.0, 0.35), lerpf(c.b, 1.0, 0.35), 1.0)
			btn.tooltip_text = "%s × %d" % [str(item["name"]), int(item["count"])]
		btn.button_pressed = i == _selected


func _on_slot_pressed(index: int) -> void:
	_selected = index
	_set_detail(index)
	_refresh_grid()


func _set_detail(index: int) -> void:
	if index < 0 or index >= SLOT_COUNT or _slots[index] == null:
		detail.text = "选择一个物品查看说明"
		return
	var item = _slots[index]
	detail.text = "%s × %d\n%s" % [str(item["name"]), int(item["count"]), str(item["desc"])]
