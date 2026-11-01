extends CanvasLayer
## Tab backpack: grid inventory with starter forest supplies.

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
	# Before GUI — Tab must close backpack even if a Control would steal focus.
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := event as InputEventKey
	var is_tab := (
		key.keycode == KEY_TAB
		or key.physical_keycode == KEY_TAB
		or key.is_action_pressed("ui_focus_next")
		or key.is_action_pressed("ui_focus_prev")
	)
	if is_tab:
		if get_tree().paused and not _open:
			return
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
	_put(0, "wood", "木柴", 5, "干燥的树枝，可生火或搭建。", Color(0.55, 0.35, 0.18))
	_put(1, "berry", "浆果", 8, "森林里摘到的浆果，能稍微恢复体力。", Color(0.72, 0.18, 0.32))
	_put(2, "water", "水瓶", 2, "干净的饮水，走远路时很重要。", Color(0.25, 0.55, 0.85))
	_put(3, "rope", "绳子", 1, "结实的麻绳，捆东西或攀爬用。", Color(0.72, 0.62, 0.38))
	_put(4, "herb", "草药", 3, "带清香的草叶，据说能止血。", Color(0.28, 0.62, 0.32))
	_put(5, "stone", "石块", 4, "趁手的石头，敲打或砸开硬壳。", Color(0.55, 0.55, 0.52))
	_put(6, "map", "手绘地图", 1, "标注了小路与池塘的粗糙地图。", Color(0.85, 0.78, 0.55))


func _put(index: int, id: String, item_name: String, count: int, desc: String, color: Color) -> void:
	if index < 0 or index >= SLOT_COUNT:
		return
	_slots[index] = {
		"id": id,
		"name": item_name,
		"count": count,
		"desc": desc,
		"color": color,
	}


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
