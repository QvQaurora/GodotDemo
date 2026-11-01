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
var _window: OptionButton
var _vsync: OptionButton
var _fps: OptionButton
var _scale: HSlider
var _scale_value: Label
var _msaa: OptionButton
var _fxaa: CheckButton
var _taa: CheckButton
var _shadows: OptionButton
var _shadow_dist: HSlider
var _shadow_dist_value: Label
var _ssao: CheckButton
var _glow: CheckButton
var _fog: CheckButton
var _dof: CheckButton
var _motion_blur: OptionButton
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

	_window = _add_option_row("窗口模式", ["窗口", "无边框最大化", "无边框最大化"], [0, 1, 2])
	_window.item_selected.connect(func(i: int) -> void:
		_set_graphic("window_mode", _window.get_item_id(i))
	)

	_vsync = _add_option_row("垂直同步", ["关闭", "开启", "自适应", "Mailbox"], [0, 1, 2, 3])
	_vsync.item_selected.connect(func(i: int) -> void:
		_set_graphic("vsync_mode", _vsync.get_item_id(i))
	)

	_fps = _add_option_row("帧率上限", ["无限制", "30", "60", "120", "144"], [0, 30, 60, 120, 144])
	_fps.item_selected.connect(func(i: int) -> void:
		_set_graphic("max_fps", _fps.get_item_id(i))
	)

	var scale_row := _add_slider_row("渲染比例", 50.0, 100.0, 5.0)
	_scale = scale_row[0]
	_scale_value = scale_row[1]
	_scale.value_changed.connect(func(v: float) -> void:
		_scale_value.text = "%d%%" % int(v)
		_set_graphic("render_scale", v / 100.0)
	)

	_msaa = _add_option_row("MSAA 抗锯齿", ["关闭", "2x", "4x", "8x"], [0, 1, 2, 3])
	_msaa.item_selected.connect(func(i: int) -> void:
		_set_graphic("msaa", _msaa.get_item_id(i))
	)

	_fxaa = _add_check_row("FXAA")
	_fxaa.toggled.connect(func(on: bool) -> void: _set_graphic("fxaa", on))

	_taa = _add_check_row("TAA 时间抗锯齿")
	_taa.toggled.connect(func(on: bool) -> void: _set_graphic("taa", on))

	_shadows = _add_option_row("阴影质量", ["关闭", "低", "中", "高"], [0, 1, 2, 3])
	_shadows.item_selected.connect(func(i: int) -> void:
		_set_graphic("shadow_quality", _shadows.get_item_id(i))
	)

	var dist_row := _add_slider_row("阴影距离", 80.0, 500.0, 10.0)
	_shadow_dist = dist_row[0]
	_shadow_dist_value = dist_row[1]
	_shadow_dist.value_changed.connect(func(v: float) -> void:
		_shadow_dist_value.text = "%dm" % int(v)
		_set_graphic("shadow_distance", v)
	)

	_ssao = _add_check_row("环境光遮蔽 (SSAO)")
	_ssao.toggled.connect(func(on: bool) -> void: _set_graphic("ssao", on))

	_glow = _add_check_row("辉光 / 泛光")
	_glow.toggled.connect(func(on: bool) -> void: _set_graphic("glow", on))

	_fog = _add_check_row("雾效")
	_fog.toggled.connect(func(on: bool) -> void: _set_graphic("fog", on))

	_dof = _add_check_row("景深")
	_dof.toggled.connect(func(on: bool) -> void: _set_graphic("dof", on))

	_motion_blur = _add_option_row("动态模糊", ["关闭", "低", "中", "高"], [0, 1, 2, 3])
	_motion_blur.item_selected.connect(func(i: int) -> void:
		_set_graphic("motion_blur", _motion_blur.get_item_id(i))
	)


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


func _add_slider_row(label_text: String, min_v: float, max_v: float, step: float) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.custom_minimum_size = Vector2(140, 0)
	label.text = label_text
	row.add_child(label)
	var slider := HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_FILL
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	row.add_child(slider)
	var value := Label.new()
	value.custom_minimum_size = Vector2(56, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	graphics_list.add_child(row)
	return [slider, value]


func sync_from_settings() -> void:
	_syncing = true
	_select_by_id(_preset, GameSettings.quality)
	_select_by_id(_window, GameSettings.window_mode)
	_select_by_id(_vsync, GameSettings.vsync_mode)
	_select_by_id(_fps, GameSettings.max_fps)
	_scale.set_value_no_signal(GameSettings.render_scale * 100.0)
	_scale_value.text = "%d%%" % int(_scale.value)
	_select_by_id(_msaa, GameSettings.msaa)
	_fxaa.set_pressed_no_signal(GameSettings.fxaa)
	_taa.set_pressed_no_signal(GameSettings.taa)
	_select_by_id(_shadows, GameSettings.shadow_quality)
	_shadow_dist.set_value_no_signal(GameSettings.shadow_distance)
	_shadow_dist_value.text = "%dm" % int(_shadow_dist.value)
	_ssao.set_pressed_no_signal(GameSettings.ssao)
	_glow.set_pressed_no_signal(GameSettings.glow)
	_fog.set_pressed_no_signal(GameSettings.fog)
	_dof.set_pressed_no_signal(GameSettings.dof)
	_select_by_id(_motion_blur, GameSettings.motion_blur)

	master_slider.set_value_no_signal(GameSettings.master_volume * 100.0)
	music_slider.set_value_no_signal(GameSettings.music_volume * 100.0)
	sfx_slider.set_value_no_signal(GameSettings.sfx_volume * 100.0)
	_update_audio_labels()
	_syncing = false


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
