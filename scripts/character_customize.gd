extends VBoxContainer
## Main-menu player look picker with live 3D preview.

signal back_pressed

const Catalog = preload("res://scripts/character_catalog.gd")
const Builder = preload("res://scripts/kenney_character_builder.gd")

@onready var preview_host: SubViewportContainer = $Body/PreviewPane/PreviewHost
@onready var model_root: Node3D = $Body/PreviewPane/PreviewHost/SubViewport/World/Turntable/ModelRoot
@onready var turntable: Node3D = $Body/PreviewPane/PreviewHost/SubViewport/World/Turntable
@onready var floor_mesh: MeshInstance3D = $Body/PreviewPane/PreviewHost/SubViewport/World/Floor
@onready var preview_camera: Camera3D = $Body/PreviewPane/PreviewHost/SubViewport/World/Camera3D
@onready var status_label: Label = $Body/PreviewPane/Status
@onready var calibrate_box: VBoxContainer = $Body/PreviewPane/Calibrate
@onready var cal_sliders: VBoxContainer = $Body/PreviewPane/Calibrate/CalSliders
@onready var cal_copy_btn: Button = $Body/PreviewPane/Calibrate/CalCopy
@onready var cal_code: LineEdit = $Body/PreviewPane/Calibrate/CalCode
@onready var hint_label: Label = $Hint
@onready var body_list: ItemList = $Body/Lists/BodyColumn/BodyList
@onready var outfit_title: Label = $Body/Lists/OutfitColumn/OutfitTitle
@onready var mode_tabs: TabContainer = $Body/Lists/OutfitColumn/CatTabs
@onready var back_btn: Button = $Buttons/BackButton
@onready var apply_btn: Button = $Buttons/ApplyButton

const YAW_SENS := 0.01
const PITCH_SENS := 0.008
const PITCH_MIN := -0.35
const PITCH_MAX := 0.45

var _body_id: String = "medium"
var _outfit_id: String = "skaterMaleA"
var _gear: Dictionary = {}
var _yaw: float = 0.0
var _pitch: float = 0.0
var _dragging: bool = false
var _outfit_lists: Dictionary = {} # cat -> ItemList
var _gear_lists: Dictionary = {} # slot -> ItemList
var _base_cam_pos: Vector3 = Vector3(0.0, 1.15, 4.6)
var _look_y: float = 0.9
var _skin_tabs: TabContainer
var _gear_tabs: TabContainer
var _cal_acc_id: String = ""
var _cal_scale: float = 0.004
var _cal_offset: Vector3 = Vector3.ZERO
var _cal_rot: Vector3 = Vector3.ZERO
var _cal_busy: bool = false
var _slider_scale: HSlider
var _slider_ox: HSlider
var _slider_oy: HSlider
var _slider_oz: HSlider
var _slider_rx: HSlider
var _slider_ry: HSlider
var _slider_rz: HSlider
var _label_scale: Label
var _label_ox: Label
var _label_oy: Label
var _label_oz: Label
var _label_rx: Label
var _label_ry: Label
var _label_rz: Label


func _ready() -> void:
	back_btn.pressed.connect(func() -> void: back_pressed.emit())
	apply_btn.pressed.connect(_on_apply)
	body_list.item_selected.connect(_on_body_selected)
	preview_host.mouse_filter = Control.MOUSE_FILTER_STOP
	preview_host.gui_input.connect(_on_preview_gui_input)
	cal_copy_btn.pressed.connect(_on_copy_cal)
	if hint_label:
		hint_label.text = "拖拽预览旋转 · 选中配件后可用下方滑条实时标定 · 点「保存外观」保存穿着"
	if outfit_title:
		outfit_title.text = "皮肤与配件"
	_setup_floor()
	_build_cal_sliders()
	_body_id = Catalog.resolve_existing_body_id(GameSettings.player_body_id)
	_outfit_id = Catalog.resolve_existing_outfit_id(GameSettings.player_outfit_id)
	_gear = Catalog.sanitize_gear(GameSettings.player_gear)
	_build_body_list()
	_build_mode_tabs()
	_refresh_status()
	_sync_calibrate_panel()
	call_deferred("_rebuild_preview")


func _setup_floor() -> void:
	if floor_mesh == null:
		return
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.4
	mesh.bottom_radius = 1.4
	mesh.height = 0.04
	mesh.radial_segments = 32
	floor_mesh.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.22, 0.18, 1)
	mat.roughness = 0.9
	floor_mesh.material_override = mat
	floor_mesh.position.y = -0.02


func _frame_camera(_character_height: float) -> void:
	if preview_camera == null:
		return
	var h := Catalog.PREVIEW_FRAME_HEIGHT
	_look_y = h * 0.48
	var dist := h * 2.45
	_base_cam_pos = Vector3(0.0, _look_y + h * 0.08, dist)
	preview_camera.fov = 32.0
	_apply_orbit()


func _reset_front_view() -> void:
	_yaw = 0.0
	_pitch = 0.0
	_dragging = false
	if turntable:
		turntable.rotation = Vector3.ZERO
	_apply_orbit()


func _apply_orbit() -> void:
	if preview_camera == null or turntable == null:
		return
	turntable.rotation.y = _yaw
	var dist := _base_cam_pos.z
	var cam_y := _base_cam_pos.y + sin(_pitch) * dist * 0.35
	var cam_z := cos(_pitch) * dist
	preview_camera.position = Vector3(0.0, cam_y, cam_z)
	preview_camera.look_at(Vector3(0.0, _look_y, 0.0), Vector3.UP)


func _on_preview_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			preview_host.accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_yaw += mm.relative.x * YAW_SENS
		_pitch = clampf(_pitch - mm.relative.y * PITCH_SENS, PITCH_MIN, PITCH_MAX)
		_apply_orbit()
		preview_host.accept_event()


func focus_primary() -> void:
	apply_btn.grab_focus()


func sync_from_settings() -> void:
	_body_id = Catalog.resolve_existing_body_id(GameSettings.player_body_id)
	_outfit_id = Catalog.resolve_existing_outfit_id(GameSettings.player_outfit_id)
	_gear = Catalog.sanitize_gear(GameSettings.player_gear)
	_select_body_in_list()
	_select_outfit_in_lists()
	_select_gear_in_lists()
	_refresh_status()
	_sync_calibrate_panel()
	_rebuild_preview()


func _build_body_list() -> void:
	body_list.clear()
	for i in Catalog.BODIES.size():
		var b: Dictionary = Catalog.BODIES[i]
		var idx := body_list.add_item(str(b.get("name", "")))
		body_list.set_item_metadata(idx, str(b.get("id", "")))
	_select_body_in_list()


func _build_mode_tabs() -> void:
	for child in mode_tabs.get_children():
		child.queue_free()
	_outfit_lists.clear()
	_gear_lists.clear()

	_skin_tabs = TabContainer.new()
	_skin_tabs.name = "皮肤"
	_skin_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mode_tabs.add_child(_skin_tabs)

	_gear_tabs = TabContainer.new()
	_gear_tabs.name = "配件"
	_gear_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mode_tabs.add_child(_gear_tabs)

	for cat in Catalog.outfit_categories():
		var list := _make_item_list()
		for o in Catalog.outfits_in_category(cat):
			var idx := list.add_item(str(o.get("name", "")))
			list.set_item_metadata(idx, str(o.get("id", "")))
		list.item_selected.connect(_on_outfit_selected.bind(list))
		var host := _wrap_list(cat, list)
		_skin_tabs.add_child(host)
		_outfit_lists[cat] = list

	for slot in Catalog.GEAR_SLOTS:
		var slot_id := str(slot.get("id", ""))
		var list := _make_item_list()
		var none_idx := list.add_item("无")
		list.set_item_metadata(none_idx, "")
		for a in Catalog.accessories_in_slot(slot_id):
			var idx := list.add_item(str(a.get("name", "")))
			list.set_item_metadata(idx, str(a.get("id", "")))
		list.item_selected.connect(_on_gear_selected.bind(list, slot_id))
		var host := _wrap_list(str(slot.get("name", slot_id)), list)
		_gear_tabs.add_child(host)
		_gear_lists[slot_id] = list

	_select_outfit_in_lists()
	_select_gear_in_lists()
	if not _gear_tabs.tab_changed.is_connected(_on_gear_tab_changed):
		_gear_tabs.tab_changed.connect(_on_gear_tab_changed)


func _on_gear_tab_changed(_idx: int) -> void:
	_sync_calibrate_panel()


func _make_item_list() -> ItemList:
	var list := ItemList.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size = Vector2(0, 200)
	list.allow_reselect = true
	return list


func _wrap_list(title: String, list: ItemList) -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	return scroll


func _select_body_in_list() -> void:
	for i in body_list.item_count:
		if str(body_list.get_item_metadata(i)) == _body_id:
			body_list.select(i)
			return


func _select_outfit_in_lists() -> void:
	if _skin_tabs == null:
		return
	var outfit := Catalog.find_outfit(_outfit_id)
	var cat := str(outfit.get("cat", ""))
	for i in _skin_tabs.get_child_count():
		if _skin_tabs.get_child(i).name == cat:
			_skin_tabs.current_tab = i
			break
	var list: ItemList = _outfit_lists.get(cat) as ItemList
	if list == null:
		return
	for i in list.item_count:
		if str(list.get_item_metadata(i)) == _outfit_id:
			list.select(i)
			list.ensure_current_is_visible()
			return


func _select_gear_in_lists() -> void:
	for slot_id in _gear_lists.keys():
		var list: ItemList = _gear_lists[slot_id]
		var want := str(_gear.get(slot_id, ""))
		for i in list.item_count:
			if str(list.get_item_metadata(i)) == want:
				list.select(i)
				break


func _on_body_selected(index: int) -> void:
	_body_id = str(body_list.get_item_metadata(index))
	_refresh_status()
	_rebuild_preview()


func _on_outfit_selected(index: int, list: ItemList) -> void:
	_outfit_id = str(list.get_item_metadata(index))
	_refresh_status()
	_rebuild_preview()


func _on_gear_selected(index: int, list: ItemList, slot_id: String) -> void:
	_gear[slot_id] = str(list.get_item_metadata(index))
	_gear = Catalog.sanitize_gear(_gear)
	_refresh_status()
	_sync_calibrate_panel()
	_rebuild_preview(true)


func _refresh_status() -> void:
	var body := Catalog.find_body(_body_id)
	var outfit := Catalog.find_outfit(_outfit_id)
	var worn: PackedStringArray = []
	for slot in Catalog.GEAR_SLOTS:
		var sid := str(slot.get("id", ""))
		var aid := str(_gear.get(sid, ""))
		if aid == "":
			continue
		var acc := Catalog.find_accessory(aid)
		if not acc.is_empty():
			worn.append(str(acc.get("name", aid)))
	if worn.is_empty():
		status_label.text = "%s · %s" % [body.get("name", ""), outfit.get("name", "")]
	else:
		status_label.text = "%s · %s · %s" % [body.get("name", ""), outfit.get("name", ""), " / ".join(worn)]


func _rebuild_preview(reset_view: bool = true) -> void:
	if model_root == null:
		return
	var built := Builder.spawn(model_root, _body_id, _outfit_id, 0.0, _gear)
	var h := float(built.get("height", Catalog.body_height(_body_id)))
	_frame_camera(h)
	if reset_view:
		_reset_front_view()
	else:
		_apply_orbit()


func _on_apply() -> void:
	GameSettings.player_body_id = Catalog.resolve_existing_body_id(_body_id)
	GameSettings.player_outfit_id = Catalog.resolve_existing_outfit_id(_outfit_id)
	GameSettings.player_gear = Catalog.sanitize_gear(_gear)
	GameSettings.save_settings()
	status_label.text = "已保存 · " + status_label.text
	back_pressed.emit()


func _active_cal_acc_id() -> String:
	## Prefer currently selected gear tab's worn item; else first worn accessory.
	if _gear_tabs != null and _gear_tabs.get_child_count() > 0:
		var tab := _gear_tabs.get_current_tab_control()
		if tab != null:
			var slot_name := String(tab.name)
			for slot in Catalog.GEAR_SLOTS:
				if str(slot.get("name", "")) == slot_name:
					var sid := str(slot.get("id", ""))
					var aid := str(_gear.get(sid, ""))
					if aid != "":
						return aid
	for slot in Catalog.GEAR_SLOTS:
		var sid := str(slot.get("id", ""))
		var aid := str(_gear.get(sid, ""))
		if aid != "":
			return aid
	return ""


func _build_cal_sliders() -> void:
	for child in cal_sliders.get_children():
		child.queue_free()
	_slider_scale = _add_cal_slider("缩放 scale", 0.001, 0.02, 0.0001, 0.004)
	_label_scale = _slider_scale.get_meta("value_label") as Label
	_slider_ox = _add_cal_slider("偏移 X", -0.02, 0.02, 0.0001, 0.0)
	_label_ox = _slider_ox.get_meta("value_label") as Label
	_slider_oy = _add_cal_slider("偏移 Y 上下", -0.02, 0.02, 0.0001, 0.0)
	_label_oy = _slider_oy.get_meta("value_label") as Label
	_slider_oz = _add_cal_slider("偏移 Z 前后", -0.02, 0.02, 0.0001, 0.0)
	_label_oz = _slider_oz.get_meta("value_label") as Label
	_slider_rx = _add_cal_slider("旋转 X°", -180.0, 180.0, 1.0, 0.0)
	_label_rx = _slider_rx.get_meta("value_label") as Label
	_slider_ry = _add_cal_slider("旋转 Y°", -180.0, 180.0, 1.0, 0.0)
	_label_ry = _slider_ry.get_meta("value_label") as Label
	_slider_rz = _add_cal_slider("旋转 Z°", -180.0, 180.0, 1.0, 0.0)
	_label_rz = _slider_rz.get_meta("value_label") as Label
	_slider_scale.value_changed.connect(_on_cal_changed)
	_slider_ox.value_changed.connect(_on_cal_changed)
	_slider_oy.value_changed.connect(_on_cal_changed)
	_slider_oz.value_changed.connect(_on_cal_changed)
	_slider_rx.value_changed.connect(_on_cal_changed)
	_slider_ry.value_changed.connect(_on_cal_changed)
	_slider_rz.value_changed.connect(_on_cal_changed)


func _add_cal_slider(title: String, min_v: float, max_v: float, step: float, value: float) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var name_l := Label.new()
	name_l.text = title
	name_l.custom_minimum_size = Vector2(96, 0)
	name_l.add_theme_font_size_override("font_size", 12)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(0, 18)
	var val_l := Label.new()
	val_l.custom_minimum_size = Vector2(56, 0)
	val_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_l.add_theme_font_size_override("font_size", 12)
	val_l.text = "%.4f" % value
	row.add_child(name_l)
	row.add_child(slider)
	row.add_child(val_l)
	cal_sliders.add_child(row)
	slider.set_meta("value_label", val_l)
	return slider


func _sync_calibrate_panel() -> void:
	_cal_acc_id = _active_cal_acc_id()
	if _cal_acc_id == "":
		calibrate_box.visible = false
		return
	calibrate_box.visible = true
	var acc := Catalog.find_accessory(_cal_acc_id)
	var fit := Catalog.accessory_fit(acc)
	_cal_busy = true
	_cal_scale = float(fit.get("scale", Catalog.ACC_BONE_SCALE))
	_cal_offset = fit.get("offset", Vector3.ZERO) as Vector3
	_cal_rot = fit.get("rot_deg", Vector3.ZERO) as Vector3
	_slider_scale.value = _cal_scale
	_slider_ox.value = _cal_offset.x
	_slider_oy.value = _cal_offset.y
	_slider_oz.value = _cal_offset.z
	_slider_rx.value = _cal_rot.x
	_slider_ry.value = _cal_rot.y
	_slider_rz.value = _cal_rot.z
	_update_cal_labels()
	_update_cal_code()
	_cal_busy = false


func _on_cal_changed(_v: float = 0.0) -> void:
	if _cal_busy or _cal_acc_id == "":
		return
	_cal_scale = _slider_scale.value
	_cal_offset = Vector3(_slider_ox.value, _slider_oy.value, _slider_oz.value)
	_cal_rot = Vector3(_slider_rx.value, _slider_ry.value, _slider_rz.value)
	Catalog.set_fit_override(_cal_acc_id, _cal_scale, _cal_offset, _cal_rot)
	_update_cal_labels()
	_update_cal_code()
	_rebuild_preview(false)


func _update_cal_labels() -> void:
	_label_scale.text = "%.4f" % _cal_scale
	_label_ox.text = "%.4f" % _cal_offset.x
	_label_oy.text = "%.4f" % _cal_offset.y
	_label_oz.text = "%.4f" % _cal_offset.z
	_label_rx.text = "%.0f" % _cal_rot.x
	_label_ry.text = "%.0f" % _cal_rot.y
	_label_rz.text = "%.0f" % _cal_rot.z


func _update_cal_code() -> void:
	cal_code.text = Catalog.format_accessory_line(_cal_acc_id, _cal_scale, _cal_offset, _cal_rot)


func _on_copy_cal() -> void:
	_update_cal_code()
	DisplayServer.clipboard_set(cal_code.text)
	status_label.text = "已复制标定代码 · 粘贴替换 character_catalog.gd 里对应行"
