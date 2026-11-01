extends CanvasLayer
## ESC pause menu with settings and return-to-title.

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

@onready var title: Label = $Center/Panel/Margin/VBox/Title
@onready var hint: Label = $Center/Panel/Margin/VBox/Hint
@onready var main_actions: VBoxContainer = $Center/Panel/Margin/VBox/MainActions
@onready var settings_host: MarginContainer = $Center/Panel/Margin/VBox/SettingsHost
@onready var settings_panel: VBoxContainer = $Center/Panel/Margin/VBox/SettingsHost/SettingsPanel
@onready var resume_btn: Button = $Center/Panel/Margin/VBox/MainActions/ResumeButton
@onready var settings_btn: Button = $Center/Panel/Margin/VBox/MainActions/SettingsButton
@onready var menu_btn: Button = $Center/Panel/Margin/VBox/MainActions/MenuButton

var _open: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_open = false
	_show_root()

	resume_btn.pressed.connect(close_menu)
	settings_btn.pressed.connect(_on_open_settings)
	menu_btn.pressed.connect(_on_return_to_menu)
	settings_panel.back_pressed.connect(_on_close_settings)
	call_deferred("_deferred_apply_graphics")


func _deferred_apply_graphics() -> void:
	GameSettings.apply_graphics()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		# Inventory handles its own Esc close first (higher priority while open).
		var inv := get_tree().get_first_node_in_group("inventory_ui")
		if inv != null and inv.has_method("is_open") and bool(inv.call("is_open")):
			return
		if not _open:
			open_menu()
		elif settings_host.visible:
			_on_close_settings()
		else:
			close_menu()
		get_viewport().set_input_as_handled()


func open_menu() -> void:
	var inv := get_tree().get_first_node_in_group("inventory_ui")
	if inv != null and inv.has_method("close_inventory"):
		inv.call("close_inventory")
	_open = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_root()
	resume_btn.grab_focus()


func close_menu() -> void:
	_open = false
	visible = false
	get_tree().paused = false
	if DisplayServer.window_is_focused():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameSettings.save_settings()


func _show_root() -> void:
	title.text = "暂停菜单"
	hint.visible = true
	main_actions.visible = true
	settings_host.visible = false


func _on_open_settings() -> void:
	title.text = "设置"
	hint.visible = false
	main_actions.visible = false
	settings_host.visible = true
	settings_panel.sync_from_settings()
	settings_panel.back_btn.grab_focus()


func _on_close_settings() -> void:
	_show_root()
	settings_btn.grab_focus()


func _on_return_to_menu() -> void:
	GameSettings.save_settings()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
