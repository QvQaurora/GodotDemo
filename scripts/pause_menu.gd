extends CanvasLayer
## ESC opens settings; 存档 opens the five-slot save menu.

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

@onready var settings_panel: VBoxContainer = $Center/Panel/Margin/SettingsPanel
@onready var save_menu: VBoxContainer = $Center/Panel/Margin/SaveMenu

var _open: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_open = false
	settings_panel.configure_in_game(true)
	save_menu.configure(true, false)
	settings_panel.resume_pressed.connect(close_menu)
	settings_panel.save_pressed.connect(_open_save_menu)
	settings_panel.return_menu_pressed.connect(_on_return_to_menu)
	save_menu.back_pressed.connect(_close_save_menu)
	save_menu.loaded_in_game.connect(_on_loaded_in_game)
	call_deferred("_deferred_apply_graphics")


func _deferred_apply_graphics() -> void:
	GameSettings.apply_graphics()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		var inv := get_tree().get_first_node_in_group("inventory_ui")
		if inv != null and inv.has_method("is_open") and bool(inv.call("is_open")):
			return
		if not _open:
			open_menu()
		elif save_menu.visible:
			_close_save_menu()
		else:
			close_menu()
		get_viewport().set_input_as_handled()


func open_menu() -> void:
	var inv := get_tree().get_first_node_in_group("inventory_ui")
	if inv != null and inv.has_method("close_inventory"):
		inv.call("close_inventory")
	var map_ui := get_tree().get_first_node_in_group("world_map_ui")
	if map_ui != null and map_ui.has_method("close_map"):
		map_ui.call("close_map")
	_open = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_settings()


func close_menu() -> void:
	_open = false
	visible = false
	save_menu.visible = false
	settings_panel.visible = true
	get_tree().paused = false
	if DisplayServer.window_is_focused():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameSettings.save_settings()


func _show_settings() -> void:
	save_menu.visible = false
	settings_panel.visible = true
	settings_panel.sync_from_settings()
	settings_panel.focus_primary_action()


func _open_save_menu() -> void:
	settings_panel.visible = false
	save_menu.visible = true
	save_menu.configure(true, false)
	save_menu.refresh()
	save_menu.focus_primary()


func _close_save_menu() -> void:
	_show_settings()


func _on_loaded_in_game() -> void:
	# Keep menu open briefly so status is readable, then resume.
	await get_tree().create_timer(0.35).timeout
	if _open:
		close_menu()


func _on_return_to_menu() -> void:
	GameSettings.save_settings()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
