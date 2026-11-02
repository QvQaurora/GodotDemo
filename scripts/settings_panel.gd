extends VBoxContainer
## Tabbed settings: Graphics + Audio.
## Main menu uses Back; in-game pause uses Resume / Save / Return-to-menu.

signal back_pressed
signal resume_pressed
signal save_pressed
signal return_menu_pressed

@onready var tabs: TabContainer = $Tabs
@onready var graphics_list: VBoxContainer = $Tabs/画质/GraphicsList
@onready var keybind_list: VBoxContainer = $Tabs/键位/KeybindList
@onready var master_slider: HSlider = $Tabs/声音/MasterRow/MasterSlider
@onready var music_slider: HSlider = $Tabs/声音/MusicRow/MusicSlider
@onready var sfx_slider: HSlider = $Tabs/声音/SfxRow/SfxSlider
@onready var master_value: Label = $Tabs/声音/MasterRow/MasterValue
@onready var music_value: Label = $Tabs/声音/MusicRow/MusicValue
@onready var sfx_value: Label = $Tabs/声音/SfxRow/SfxValue
@onready var resume_btn: Button = $Buttons/ResumeButton
@onready var save_btn: Button = $Buttons/SaveButton
@onready var menu_btn: Button = $Buttons/MenuButton
@onready var back_btn: Button = $Buttons/BackButton

var _preset: OptionButton
var _windowed: CheckButton
var _resolution: OptionButton
var _resolution_row: HBoxContainer
var _vsync: OptionButton
var _fps: OptionButton
var _msaa: OptionButton
var _fxaa: CheckButton
var _taa: CheckButton
var _shadows: OptionButton
var _ssao: CheckButton
var _glow: CheckButton
var _fog: CheckButton
var _render_distance: OptionButton
var _syncing: bool = false
var _in_game: bool = false
var _keybind_buttons: Dictionary = {} # action_id -> Button
var _listening_action: String = ""


func _ready() -> void:
	_build_graphics_rows()
	_build_keybind_rows()
	sync_from_settings()
	_apply_button_mode()

	master_slider.value_changed.connect(_on_master_changed)
	music_slider.value_changed.connect(_on_music_changed)
	sfx_slider.value_changed.connect(_on_sfx_changed)
	back_btn.pressed.connect(func() -> void: back_pressed.emit())
	resume_btn.pressed.connect(func() -> void: resume_pressed.emit())
	save_btn.pressed.connect(func() -> void: save_pressed.emit())
	menu_btn.pressed.connect(func() -> void: return_menu_pressed.emit())
	set_process_unhandled_input(true)


func configure_in_game(enabled: bool) -> void:
	_in_game = enabled
	if is_node_ready():
		_apply_button_mode()


func _apply_button_mode() -> void:
	resume_btn.visible = _in_game
	save_btn.visible = _in_game
	menu_btn.visible = _in_game
	back_btn.visible = not _in_game


func focus_primary_action() -> void:
	if _in_game:
		resume_btn.grab_focus()
	else:
		back_btn.grab_focus()


func _build_keybind_rows() -> void:
	for child in keybind_list.get_children():
		child.queue_free()
	_keybind_buttons.clear()
	var tip := Label.new()
	tip.modulate = Color(0.7, 0.78, 0.7, 1)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.text = "点击按键按钮后，按下想要绑定的键。"
	keybind_list.add_child(tip)
	for action in GameSettings.KEYBIND_ACTIONS:
		var id: String = action["id"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var label := Label.new()
		label.custom_minimum_size = Vector2(160, 0)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = str(action["label"])
		row.add_child(label)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(120, 36)
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		var aid := id
		btn.pressed.connect(func() -> void: _begin_rebind(aid))
		row.add_child(btn)
		keybind_list.add_child(row)
		_keybind_buttons[id] = btn
	var reset := Button.new()
	reset.text = "恢复默认键位"
	reset.pressed.connect(_reset_keybinds)
	keybind_list.add_child(reset)
	_refresh_keybind_labels()


func _begin_rebind(action_id: String) -> void:
	_listening_action = action_id
	for id in _keybind_buttons.keys():
		var btn: Button = _keybind_buttons[id]
		if id == action_id:
			btn.text = "按下新按键…"
			btn.button_pressed = true
		else:
			btn.button_pressed = false
			btn.text = GameSettings.action_label(id)


func _reset_keybinds() -> void:
	_listening_action = ""
	GameSettings.keybinds = GameSettings.default_keybinds()
	GameSettings.keybinds_changed.emit()
	GameSettings.save_settings()
	_refresh_keybind_labels()


func _refresh_keybind_labels() -> void:
	for id in _keybind_buttons.keys():
		var btn: Button = _keybind_buttons[id]
		btn.button_pressed = false
		btn.text = GameSettings.action_label(id)


func is_listening_for_keybind() -> bool:
	return _listening_action != ""


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := event as InputEventKey
	var is_esc := key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE
	if _listening_action != "":
		if is_esc:
			_listening_action = ""
			_refresh_keybind_labels()
			get_viewport().set_input_as_handled()
			return
		var code := key.keycode if key.keycode != KEY_NONE else key.physical_keycode
		if code == KEY_NONE:
			return
		GameSettings.set_key(_listening_action, code)
		_listening_action = ""
		_refresh_keybind_labels()
		get_viewport().set_input_as_handled()
		return
	# Title-menu settings: Esc returns to main buttons.
	if is_esc and not _in_game and is_visible_in_tree():
		back_pressed.emit()
		get_viewport().set_input_as_handled()


func _build_graphics_rows() -> void:
	# Free immediately so no leftover「自定义」rows from older builds linger a frame.
	var old := graphics_list.get_children()
	for child in old:
		graphics_list.remove_child(child)
		child.free()

	_preset = _add_option_row(
		"画质预设",
		["低", "中", "高", "自定义"],
		[
			GameSettings.Quality.LOW,
			GameSettings.Quality.MEDIUM,
			GameSettings.Quality.HIGH,
			GameSettings.Quality.CUSTOM,
		]
	)
	_preset.item_selected.connect(_on_preset_selected)

	_windowed = _add_check_row("窗口模式")
	_windowed.toggled.connect(_on_windowed_toggled)

	_resolution_row = HBoxContainer.new()
	_resolution_row.add_theme_constant_override("separation", 12)
	var res_label := Label.new()
	res_label.custom_minimum_size = Vector2(140, 0)
	res_label.text = "分辨率"
	_resolution_row.add_child(res_label)
	_resolution = OptionButton.new()
	_resolution.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resolution_row.add_child(_resolution)
	graphics_list.add_child(_resolution_row)
	_resolution.item_selected.connect(_on_resolution_selected)

	_vsync = _add_option_row("垂直同步", ["关闭", "开启", "自适应", "Mailbox"], [0, 1, 2, 3])
	_vsync.item_selected.connect(func(i: int) -> void:
		_set_graphic("vsync_mode", _vsync.get_item_id(i))
	)

	_fps = _add_option_row("帧率上限", ["无限制", "30", "60", "120", "144"], [0, 30, 60, 120, 144])
	_fps.item_selected.connect(func(i: int) -> void:
		_set_graphic("max_fps", _fps.get_item_id(i))
	)

	# MSAA / FXAA / TAA can be enabled together (Godot Forward+).
	_msaa = _add_option_row(
		"MSAA",
		["关闭", "2x", "4x", "8x"],
		[
			GameSettings.MsaaMode.OFF,
			GameSettings.MsaaMode.MSAA_2X,
			GameSettings.MsaaMode.MSAA_4X,
			GameSettings.MsaaMode.MSAA_8X,
		]
	)
	_msaa.item_selected.connect(func(i: int) -> void:
		_set_graphic("msaa_mode", _msaa.get_item_id(i))
	)
	_fxaa = _add_check_row("FXAA")
	_fxaa.toggled.connect(func(on: bool) -> void: _set_graphic("aa_fxaa", on))
	_taa = _add_check_row("TAA")
	_taa.toggled.connect(func(on: bool) -> void: _set_graphic("aa_taa", on))

	_shadows = _add_option_row("阴影质量", ["关闭", "低", "中", "高"], [0, 1, 2, 3])
	_shadows.item_selected.connect(func(i: int) -> void:
		_set_graphic("shadow_quality", _shadows.get_item_id(i))
	)

	_render_distance = _add_option_row(
		"渲染距离",
		[
			GameSettings.render_distance_label(GameSettings.RenderDistance.LOW),
			GameSettings.render_distance_label(GameSettings.RenderDistance.MEDIUM),
			GameSettings.render_distance_label(GameSettings.RenderDistance.HIGH),
		],
		[
			GameSettings.RenderDistance.LOW,
			GameSettings.RenderDistance.MEDIUM,
			GameSettings.RenderDistance.HIGH,
		]
	)
	_render_distance.item_selected.connect(func(i: int) -> void:
		_set_graphic("render_distance", _render_distance.get_item_id(i))
	)

	_ssao = _add_check_row("环境光遮蔽 (SSAO)")
	_ssao.toggled.connect(func(on: bool) -> void: _set_graphic("ssao", on))

	_glow = _add_check_row("辉光 / 泛光")
	_glow.toggled.connect(func(on: bool) -> void: _set_graphic("glow", on))

	_fog = _add_check_row("雾效")
	_fog.toggled.connect(func(on: bool) -> void: _set_graphic("fog", on))


func _add_option_row(label_text: String, items: Array, ids: Array) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.custom_minimum_size = Vector2(140, 0)
	label.text = label_text
	row.add_child(label)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in items.size():
		opt.add_item(str(items[i]), int(ids[i]))
	row.add_child(opt)
	graphics_list.add_child(row)
	return opt


func _add_check_row(label_text: String) -> CheckButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.custom_minimum_size = Vector2(140, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = label_text
	row.add_child(label)
	var check := CheckButton.new()
	row.add_child(check)
	graphics_list.add_child(row)
	return check


func sync_from_settings() -> void:
	_syncing = true
	var q := GameSettings.quality
	# Keep 低/中/高/自定义; fold legacy 极致 into 高.
	if q == GameSettings.Quality.ULTRA:
		q = GameSettings.Quality.HIGH
		GameSettings.quality = q
	elif q < GameSettings.Quality.LOW or q > GameSettings.Quality.CUSTOM:
		q = GameSettings.Quality.MEDIUM
		GameSettings.quality = q
	_select_by_id(_preset, q)
	_windowed.set_pressed_no_signal(GameSettings.windowed)
	_rebuild_resolution_options()
	_select_by_id(_vsync, GameSettings.vsync_mode)
	_select_by_id(_fps, GameSettings.max_fps)
	_select_by_id(_msaa, GameSettings.msaa_mode)
	_fxaa.set_pressed_no_signal(GameSettings.aa_fxaa)
	_taa.set_pressed_no_signal(GameSettings.aa_taa)
	_select_by_id(_shadows, GameSettings.shadow_quality)
	var rd := GameSettings.render_distance
	if rd < GameSettings.RenderDistance.LOW or rd > GameSettings.RenderDistance.HIGH:
		rd = GameSettings.RenderDistance.MEDIUM
		GameSettings.render_distance = rd
	_select_by_id(_render_distance, rd)
	_ssao.set_pressed_no_signal(GameSettings.ssao)
	_glow.set_pressed_no_signal(GameSettings.glow)
	_fog.set_pressed_no_signal(GameSettings.fog)
	_update_resolution_enabled()

	master_slider.set_value_no_signal(GameSettings.master_volume * 100.0)
	music_slider.set_value_no_signal(GameSettings.music_volume * 100.0)
	sfx_slider.set_value_no_signal(GameSettings.sfx_volume * 100.0)
	_update_audio_labels()
	_refresh_keybind_labels()
	_syncing = false


func _rebuild_resolution_options() -> void:
	if _resolution == null:
		return
	_resolution.clear()
	var resolutions := GameSettings.available_resolutions()
	for i in resolutions.size():
		var res: Vector2i = resolutions[i]
		_resolution.add_item("%d × %d" % [res.x, res.y], i)
		_resolution.set_item_metadata(i, res)
	for i in _resolution.item_count:
		var res: Vector2i = _resolution.get_item_metadata(i)
		if res == GameSettings.window_resolution:
			_resolution.select(i)
			return
	if _resolution.item_count > 0:
		_resolution.select(0)


func _update_resolution_enabled() -> void:
	var on := GameSettings.windowed
	if _resolution_row != null:
		_resolution_row.visible = on
	if _resolution != null:
		_resolution.disabled = not on


func _select_by_id(opt: OptionButton, id: int) -> void:
	if opt == null:
		return
	for i in opt.item_count:
		if opt.get_item_id(i) == id:
			opt.select(i)
			return
	opt.select(0)


func _set_graphic(property: String, value: Variant) -> void:
	if _syncing:
		return
	GameSettings.set(property, value)
	if GameSettings.is_quality_detail_property(property):
		var resolved := GameSettings.resolve_quality_from_settings()
		_select_by_id(_preset, resolved)
	GameSettings.apply_graphics()
	GameSettings.save_settings()


func _on_windowed_toggled(on: bool) -> void:
	if _syncing:
		return
	GameSettings.windowed = on
	_update_resolution_enabled()
	GameSettings.apply_graphics()
	GameSettings.save_settings()


func _on_resolution_selected(index: int) -> void:
	if _syncing or not GameSettings.windowed:
		return
	var res: Vector2i = _resolution.get_item_metadata(index)
	GameSettings.window_resolution = res
	GameSettings.apply_graphics()
	GameSettings.save_settings()


func _on_preset_selected(index: int) -> void:
	if _syncing:
		return
	var id := _preset.get_item_id(index)
	if id == GameSettings.Quality.CUSTOM:
		GameSettings.quality = GameSettings.Quality.CUSTOM
		GameSettings.save_settings()
		return
	GameSettings.apply_quality_preset(id)
	GameSettings.apply_graphics()
	GameSettings.save_settings()
	sync_from_settings()


func _update_audio_labels() -> void:
	master_value.text = "%d%%" % int(master_slider.value)
	music_value.text = "%d%%" % int(music_slider.value)
	sfx_value.text = "%d%%" % int(sfx_slider.value)


func _on_master_changed(value: float) -> void:
	GameSettings.master_volume = value / 100.0
	GameSettings.apply_audio()
	GameSettings.save_settings()
	_update_audio_labels()


func _on_music_changed(value: float) -> void:
	GameSettings.music_volume = value / 100.0
	GameSettings.apply_audio()
	GameSettings.save_settings()
	_update_audio_labels()


func _on_sfx_changed(value: float) -> void:
	GameSettings.sfx_volume = value / 100.0
	GameSettings.apply_audio()
	GameSettings.save_settings()
	_update_audio_labels()
