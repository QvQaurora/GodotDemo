extends Control
## Start menu: new game / saves / settings / quit.

const LOADING_SCENE := "res://scenes/loading.tscn"
const _BakedCacheSeed = preload("res://scripts/baked_cache_seed.gd")

@onready var main_buttons: VBoxContainer = $Center/Panel/Margin/MainButtons
@onready var settings_host: MarginContainer = $Center/Panel/Margin/SettingsHost
@onready var save_host: MarginContainer = $Center/Panel/Margin/SaveHost
@onready var start_btn: Button = $Center/Panel/Margin/MainButtons/StartButton
@onready var save_btn: Button = $Center/Panel/Margin/MainButtons/SaveButton
@onready var settings_btn: Button = $Center/Panel/Margin/MainButtons/SettingsButton
@onready var quit_btn: Button = $Center/Panel/Margin/MainButtons/QuitButton
@onready var settings_panel: VBoxContainer = $Center/Panel/Margin/SettingsHost/SettingsPanel
@onready var save_menu: VBoxContainer = $Center/Panel/Margin/SaveHost/SaveMenu


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	# Seed shipped placement/terrain caches ASAP so first game launch on any PC is warm.
	_BakedCacheSeed.seed_all()

	start_btn.pressed.connect(_on_start)
	save_btn.pressed.connect(_on_open_saves)
	settings_btn.pressed.connect(_on_open_settings)
	quit_btn.pressed.connect(_on_quit)

	settings_panel.configure_in_game(false)
	settings_panel.back_pressed.connect(_on_close_settings)
	save_menu.configure(false, true)
	save_menu.back_pressed.connect(_on_close_save_menu)
	save_menu.request_load_from_title.connect(_on_load_slot_from_title)

	_show_main()
	start_btn.grab_focus()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := event as InputEventKey
	if key.keycode != KEY_ESCAPE and key.physical_keycode != KEY_ESCAPE:
		return
	if settings_host.visible:
		if settings_panel.has_method("is_listening_for_keybind") and bool(settings_panel.call("is_listening_for_keybind")):
			return
		_on_close_settings()
		get_viewport().set_input_as_handled()
	elif save_host.visible:
		_on_close_save_menu()
		get_viewport().set_input_as_handled()


func _show_main() -> void:
	main_buttons.visible = true
	settings_host.visible = false
	save_host.visible = false
	settings_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	save_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_main_buttons_enabled(true)
	start_btn.text = "新游戏"


func _show_settings() -> void:
	main_buttons.visible = false
	save_host.visible = false
	save_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	settings_host.visible = true
	settings_host.mouse_filter = Control.MOUSE_FILTER_STOP
	settings_panel.sync_from_settings()
	settings_panel.focus_primary_action()


func _show_saves() -> void:
	main_buttons.visible = false
	settings_host.visible = false
	settings_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	save_host.visible = true
	save_host.mouse_filter = Control.MOUSE_FILTER_STOP
	save_menu.configure(false, true)
	save_menu.refresh()
	save_menu.focus_primary()


func _set_main_buttons_enabled(enabled: bool) -> void:
	start_btn.disabled = not enabled
	save_btn.disabled = not enabled
	settings_btn.disabled = not enabled
	quit_btn.disabled = not enabled


func _on_start() -> void:
	_set_main_buttons_enabled(false)
	start_btn.text = "加载中..."
	GameSave.pending_load = false
	GameSettings.save_settings()
	get_tree().change_scene_to_file(LOADING_SCENE)


func _on_open_saves() -> void:
	_show_saves()


func _on_open_settings() -> void:
	_show_settings()


func _on_close_settings() -> void:
	_show_main()
	settings_btn.grab_focus()


func _on_close_save_menu() -> void:
	_show_main()
	save_btn.grab_focus()


func _on_load_slot_from_title(slot: int) -> void:
	_set_main_buttons_enabled(false)
	start_btn.text = "读取中..."
	GameSave.pending_load = true
	GameSave.pending_slot = slot
	GameSettings.save_settings()
	get_tree().change_scene_to_file(LOADING_SCENE)


func _on_quit() -> void:
	GameSettings.save_settings()
	get_tree().quit()
