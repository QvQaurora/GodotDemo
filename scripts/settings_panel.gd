extends VBoxContainer
## Tabbed settings: Graphics + Audio.

signal back_pressed

@onready var tabs: TabContainer = $Tabs
@onready var graphics_list: VBoxContainer = $Tabs/画质/GraphicsList
@onready var master_slider: HSlider = $Tabs/声音/MasterRow/MasterSlider
@onready var music_slider: HSlider = $Tabs/声音/MusicRow/MusicSlider
@onready var sfx_slider: HSlider = $Tabs/声音/SfxRow/SfxSlider
@onready var master_value: Label = $Tabs/声音/MasterRow/MasterValue
@onready var music_value: Label = $Tabs/声音/MusicRow/MusicValue
@onready var sfx_value: Label = $Tabs/声音/SfxRow/SfxValue
@onready var back_btn: Button = $Buttons/BackButton

var _preset: OptionButton
var _windowed: CheckButton
var _resolution: OptionButton
var _resolution_row: HBoxContainer
var _vsync: OptionButton
var _fps: OptionButton
var _aa: OptionButton
var _shadows: OptionButton
var _ssao: CheckButton
var _glow: CheckButton
var _fog: CheckButton
var _syncing: bool = false


func _ready() -> void:
	_build_graphics_rows()
	sync_from_settings()

	master_slider.value_changed.connect(_on_master_changed)
	music_slider.value_changed.connect(_on_music_changed)
	sfx_slider.value_changed.connect(_on_sfx_changed)
	back_btn.pressed.connect(func() -> void: back_pressed.emit())


func _build_graphics_rows() -> void:
	for child in graphics_list.get_children():
		child.queue_free()

	_preset = _add_option_row(
		"画质预设",
		["低", "中", "高", "极高", "自定义"],
		[
			GameSettings.Quality.LOW,
			GameSettings.Quality.MEDIUM,
			GameSettings.Quality.HIGH,
			GameSettings.Quality.ULTRA,
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

	# Display order: non-MSAA first, MSAA last (IDs stay stable for saves).
	_aa = _add_option_row(
		"抗锯齿",
		["关闭", "FXAA", "TAA", "MSAA 2x", "MSAA 4x", "MSAA 8x"],
		[
			GameSettings.AntiAliasing.OFF,
			GameSettings.AntiAliasing.FXAA,
			GameSettings.AntiAliasing.TAA,
			GameSettings.AntiAliasing.MSAA_2X,
			GameSettings.AntiAliasing.MSAA_4X,
			GameSettings.AntiAliasing.MSAA_8X,
		]
	)
	_aa.item_selected.connect(func(i: int) -> void:
		_set_graphic("anti_aliasing", _aa.get_item_id(i))
	)

	_shadows = _add_option_row("阴影质量", ["关闭", "低", "中", "高"], [0, 1, 2, 3])
	_shadows.item_selected.connect(func(i: int) -> void:
		_set_graphic("shadow_quality", _shadows.get_item_id(i))
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
	_select_by_id(_preset, GameSettings.quality)
	_windowed.set_pressed_no_signal(GameSettings.windowed)
	_rebuild_resolution_options()
	_select_by_id(_vsync, GameSettings.vsync_mode)
	_select_by_id(_fps, GameSettings.max_fps)
	_select_by_id(_aa, GameSettings.anti_aliasing)
	_select_by_id(_shadows, GameSettings.shadow_quality)
	_ssao.set_pressed_no_signal(GameSettings.ssao)
	_glow.set_pressed_no_signal(GameSettings.glow)
	_fog.set_pressed_no_signal(GameSettings.fog)
	_update_resolution_enabled()

	master_slider.set_value_no_signal(GameSettings.master_volume * 100.0)
	music_slider.set_value_no_signal(GameSettings.music_volume * 100.0)
	sfx_slider.set_value_no_signal(GameSettings.sfx_volume * 100.0)
	_update_audio_labels()
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
	if property != "quality":
		GameSettings.mark_custom()
		_select_by_id(_preset, GameSettings.Quality.CUSTOM)
	GameSettings.apply_graphics()
	GameSettings.save_settings()


func _on_windowed_toggled(on: bool) -> void:
	if _syncing:
		return
	GameSettings.windowed = on
	GameSettings.mark_custom()
	_select_by_id(_preset, GameSettings.Quality.CUSTOM)
	_update_resolution_enabled()
	GameSettings.apply_graphics()
	GameSettings.save_settings()


func _on_resolution_selected(index: int) -> void:
	if _syncing or not GameSettings.windowed:
		return
	var res: Vector2i = _resolution.get_item_metadata(index)
	GameSettings.window_resolution = res
	GameSettings.mark_custom()
	_select_by_id(_preset, GameSettings.Quality.CUSTOM)
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
