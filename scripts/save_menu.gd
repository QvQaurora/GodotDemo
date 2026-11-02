extends VBoxContainer
## Five-slot save / load / delete panel.

signal back_pressed
signal loaded_in_game
signal request_load_from_title(slot: int)

@onready var title: Label = $Title
@onready var status: Label = $Status
@onready var slot_list: VBoxContainer = $SlotList
@onready var save_btn: Button = $Actions/SaveButton
@onready var load_btn: Button = $Actions/LoadButton
@onready var delete_btn: Button = $Actions/DeleteButton
@onready var back_btn: Button = $Actions/BackButton
@onready var confirm: ConfirmationDialog = $ConfirmDelete

var _selected: int = 0
var _slot_buttons: Array[Button] = []
var _allow_save: bool = true
var _from_title: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_unhandled_input(true)
	_build_slots()
	save_btn.pressed.connect(_on_save)
	load_btn.pressed.connect(_on_load)
	delete_btn.pressed.connect(_on_delete_pressed)
	back_btn.pressed.connect(func() -> void: back_pressed.emit())
	confirm.confirmed.connect(_on_delete_confirmed)
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := event as InputEventKey
	if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
		# Don't steal Esc from the delete confirmation dialog.
		if confirm != null and confirm.visible:
			return
		back_pressed.emit()
		get_viewport().set_input_as_handled()


func configure(allow_save: bool, from_title: bool = false) -> void:
	_allow_save = allow_save
	_from_title = from_title
	save_btn.visible = allow_save
	title.text = "存档"
	if is_node_ready():
		refresh()


func focus_primary() -> void:
	if _slot_buttons.is_empty():
		return
	_slot_buttons[clampi(_selected, 0, _slot_buttons.size() - 1)].grab_focus()


func refresh() -> void:
	if not is_node_ready() or _slot_buttons.is_empty():
		return
	for i in GameSave.SLOT_COUNT:
		_refresh_slot_button(i)
	_update_action_buttons()
	status.text = ""


func _build_slots() -> void:
	for child in slot_list.get_children():
		child.queue_free()
	_slot_buttons.clear()
	for i in GameSave.SLOT_COUNT:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 72)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.focus_mode = Control.FOCUS_ALL
		var idx := i
		btn.pressed.connect(func() -> void: _select_slot(idx))
		slot_list.add_child(btn)
		_slot_buttons.append(btn)


func _select_slot(slot: int) -> void:
	_selected = slot
	for i in _slot_buttons.size():
		_refresh_slot_button(i)
	_update_action_buttons()


func _refresh_slot_button(i: int) -> void:
	var summary: Dictionary = GameSave.get_slot_summary(i)
	var mark := "▸ " if i == _selected else "   "
	_slot_buttons[i].text = "%s%s\n   %s\n   %s" % [mark, summary["title"], summary["line1"], summary["line2"]]
	_slot_buttons[i].modulate = Color(1.15, 1.15, 1.05) if i == _selected else Color(1, 1, 1)


func _update_action_buttons() -> void:
	var empty := not GameSave.has_save(_selected)
	save_btn.disabled = not _allow_save
	load_btn.disabled = empty
	delete_btn.disabled = empty


func _on_save() -> void:
	if not _allow_save:
		return
	var ok := GameSave.save_game(_selected, get_tree())
	GameSettings.save_settings()
	refresh()
	_select_slot(_selected)
	status.text = "已保存到存档 %d" % (_selected + 1) if ok else "保存失败"
	status.modulate = Color(0.7, 0.95, 0.7) if ok else Color(1.0, 0.55, 0.45)


func _on_load() -> void:
	if not GameSave.has_save(_selected):
		status.text = "该槽位为空"
		status.modulate = Color(1.0, 0.7, 0.4)
		return
	if _from_title:
		request_load_from_title.emit(_selected)
		return
	var ok := GameSave.apply_slot_to_world(_selected, get_tree())
	var forest := get_tree().get_first_node_in_group("forest_world")
	if ok and forest != null and forest.has_method("refresh_world_stream"):
		forest.call("refresh_world_stream")
	refresh()
	_select_slot(_selected)
	if ok:
		status.text = "已加载存档 %d" % (_selected + 1)
		status.modulate = Color(0.7, 0.95, 0.7)
		loaded_in_game.emit()
	else:
		status.text = "加载失败"
		status.modulate = Color(1.0, 0.55, 0.45)


func _on_delete_pressed() -> void:
	if not GameSave.has_save(_selected):
		return
	confirm.dialog_text = "确定删除「存档 %d」？此操作无法撤销。" % (_selected + 1)
	confirm.popup_centered()


func _on_delete_confirmed() -> void:
	GameSave.clear_slot(_selected)
	refresh()
	_select_slot(_selected)
	status.text = "已删除存档 %d" % (_selected + 1)
	status.modulate = Color(1.0, 0.75, 0.45)
