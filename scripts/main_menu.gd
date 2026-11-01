extends Control
## Start menu: play, settings, quit. Game world loads only after Start.

const LOADING_SCENE := "res://scenes/loading.tscn"

@onready var main_buttons: VBoxContainer = $Center/Panel/Margin/MainButtons
@onready var settings_host: MarginContainer = $Center/Panel/Margin/SettingsHost
@onready var start_btn: Button = $Center/Panel/Margin/MainButtons/StartButton
@onready var settings_btn: Button = $Center/Panel/Margin/MainButtons/SettingsButton
@onready var quit_btn: Button = $Center/Panel/Margin/MainButtons/QuitButton
@onready var settings_panel: VBoxContainer = $Center/Panel/Margin/SettingsHost/SettingsPanel


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	main_buttons.visible = true
	settings_host.visible = false

	start_btn.pressed.connect(_on_start)
	settings_btn.pressed.connect(_on_open_settings)
	quit_btn.pressed.connect(_on_quit)
	settings_panel.back_pressed.connect(_on_close_settings)
	start_btn.grab_focus()


func _on_start() -> void:
	start_btn.disabled = true
	settings_btn.disabled = true
	quit_btn.disabled = true
	start_btn.text = "加载中..."
	GameSettings.save_settings()
	get_tree().change_scene_to_file(LOADING_SCENE)


func _on_open_settings() -> void:
	main_buttons.visible = false
	settings_host.visible = true
	settings_panel.sync_from_settings()
	settings_panel.back_btn.grab_focus()


func _on_close_settings() -> void:
	settings_host.visible = false
	main_buttons.visible = true
	settings_btn.grab_focus()


func _on_quit() -> void:
	GameSettings.save_settings()
	get_tree().quit()
