extends Control
## Start menu: new game (map pick) / saves / settings / quit.

const LOADING_SCENE := "res://scenes/loading.tscn"
const _BakedCacheSeed = preload("res://scripts/baked_cache_seed.gd")
const _MapCatalog = preload("res://scripts/map_catalog.gd")

@onready var main_buttons: VBoxContainer = $Center/Panel/Margin/MainButtons
@onready var settings_host: MarginContainer = $Center/Panel/Margin/SettingsHost
@onready var save_host: MarginContainer = $Center/Panel/Margin/SaveHost
@onready var map_host: MarginContainer = $Center/Panel/Margin/MapHost
@onready var start_btn: Button = $Center/Panel/Margin/MainButtons/StartButton
@onready var save_btn: Button = $Center/Panel/Margin/MainButtons/SaveButton
@onready var settings_btn: Button = $Center/Panel/Margin/MainButtons/SettingsButton
@onready var quit_btn: Button = $Center/Panel/Margin/MainButtons/QuitButton
@onready var settings_panel: VBoxContainer = $Center/Panel/Margin/SettingsHost/SettingsPanel
@onready var save_menu: VBoxContainer = $Center/Panel/Margin/SaveHost/SaveMenu
@onready var map_list: VBoxContainer = $Center/Panel/Margin/MapHost/MapSelect/Scroll/List
@onready var map_back_btn: Button = $Center/Panel/Margin/MapHost/MapSelect/BackButton
@onready var panel: PanelContainer = $Center/Panel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	_BakedCacheSeed.seed_all()

	start_btn.pressed.connect(_on_start)
	save_btn.pressed.connect(_on_open_saves)
	settings_btn.pressed.connect(_on_open_settings)
	quit_btn.pressed.connect(_on_quit)
	map_back_btn.pressed.connect(_on_close_map_select)

	settings_panel.configure_in_game(false)
	settings_panel.back_pressed.connect(_on_close_settings)
	save_menu.configure(false, true)
	save_menu.back_pressed.connect(_on_close_save_menu)
	save_menu.request_load_from_title.connect(_on_load_slot_from_title)

	_build_map_list()
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
	elif map_host.visible:
		_on_close_map_select()
		get_viewport().set_input_as_handled()


func _show_main() -> void:
	main_buttons.visible = true
	settings_host.visible = false
	save_host.visible = false
	map_host.visible = false
	settings_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	save_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(520, 0)
	_set_main_buttons_enabled(true)
	start_btn.text = "开始游戏"


func _show_settings() -> void:
	main_buttons.visible = false
	save_host.visible = false
	map_host.visible = false
	save_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	settings_host.visible = true
	settings_host.mouse_filter = Control.MOUSE_FILTER_STOP
	settings_panel.sync_from_settings()
	settings_panel.focus_primary_action()


func _show_saves() -> void:
	main_buttons.visible = false
	settings_host.visible = false
	map_host.visible = false
	settings_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	save_host.visible = true
	save_host.mouse_filter = Control.MOUSE_FILTER_STOP
	save_menu.configure(false, true)
	save_menu.refresh()
	save_menu.focus_primary()


func _show_map_select() -> void:
	main_buttons.visible = false
	settings_host.visible = false
	save_host.visible = false
	settings_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	save_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_host.visible = true
	map_host.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.custom_minimum_size = Vector2(640, 0)
	map_back_btn.grab_focus()


func _set_main_buttons_enabled(enabled: bool) -> void:
	start_btn.disabled = not enabled
	save_btn.disabled = not enabled
	settings_btn.disabled = not enabled
	quit_btn.disabled = not enabled


func _build_map_list() -> void:
	for child in map_list.get_children():
		child.queue_free()
	var last_cat := ""
	for entry in _MapCatalog.entries():
		var cat := str(entry.get("category", ""))
		if cat != last_cat:
			last_cat = cat
			var head := Label.new()
			head.text = cat
			head.modulate = Color(0.7, 0.85, 0.72, 1)
			head.add_theme_font_size_override("font_size", 16)
			map_list.add_child(head)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 44)
		btn.focus_mode = Control.FOCUS_ALL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var tag := "" if bool(entry.get("ready", false)) else "  · 占位"
		btn.text = "%s%s" % [str(entry.get("name", "")), tag]
		btn.tooltip_text = str(entry.get("blurb", ""))
		var map_id := str(entry.get("id", ""))
		var scene_path := str(entry.get("scene", ""))
		btn.pressed.connect(_on_map_chosen.bind(map_id, scene_path, btn))
		map_list.add_child(btn)


func _on_start() -> void:
	_show_map_select()


func _on_map_chosen(map_id: String, scene_path: String, btn: Button) -> void:
	if not ResourceLoader.exists(scene_path):
		btn.text = "场景缺失"
		return
	GameSession.select_map(map_id, scene_path)
	GameSave.pending_load = false
	GameSettings.save_settings()
	btn.disabled = true
	btn.text = "加载中..."
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


func _on_close_map_select() -> void:
	_show_main()
	start_btn.grab_focus()


func _on_load_slot_from_title(slot: int) -> void:
	_set_main_buttons_enabled(false)
	start_btn.text = "读取中..."
	GameSession.reset_to_forest()
	GameSave.pending_load = true
	GameSave.pending_slot = slot
	GameSettings.save_settings()
	get_tree().change_scene_to_file(LOADING_SCENE)


func _on_quit() -> void:
	GameSettings.save_settings()
	get_tree().quit()
