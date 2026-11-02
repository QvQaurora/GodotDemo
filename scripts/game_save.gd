extends Node
## Five save slots: player transform + camera + inventory.

const SLOT_COUNT := 5
const SAVE_VERSION := 1
const LEGACY_PATH := "user://savegame.json"

## Set before loading main scene; consumed by GameWorld after forest is ready.
var pending_load: bool = false
var pending_slot: int = 0


func _ready() -> void:
	_migrate_legacy_save()


func slot_path(slot: int) -> String:
	return "user://save_slot_%d.json" % (slot + 1)


func has_save(slot: int = -1) -> bool:
	if slot < 0:
		return has_any_save()
	return slot >= 0 and slot < SLOT_COUNT and FileAccess.file_exists(slot_path(slot))


func has_any_save() -> bool:
	for i in SLOT_COUNT:
		if has_save(i):
			return true
	return false


func clear_slot(slot: int) -> void:
	if not has_save(slot):
		return
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove("save_slot_%d.json" % (slot + 1))


func clear_all_saves() -> void:
	for i in SLOT_COUNT:
		clear_slot(i)
	# Legacy file if still present.
	if FileAccess.file_exists(LEGACY_PATH):
		var dir := DirAccess.open("user://")
		if dir != null:
			dir.remove("savegame.json")


func get_slot_summary(slot: int) -> Dictionary:
	## { empty, title, line1, line2, saved_at, item_count, x, z }
	var title := "存档 %d" % (slot + 1)
	if not has_save(slot):
		return {
			"empty": true,
			"title": title,
			"line1": "空存档",
			"line2": "点击保存写入此槽位",
			"saved_at": "",
			"item_count": 0,
			"x": 0.0,
			"z": 0.0,
		}
	var data := load_slot_dict(slot)
	var saved_at := str(data.get("saved_at", "未知时间"))
	var player: Dictionary = data.get("player", {})
	var x := float(player.get("x", 0.0))
	var z := float(player.get("z", 0.0))
	var items := 0
	var inv: Variant = data.get("inventory", [])
	if typeof(inv) == TYPE_ARRAY:
		for entry in inv:
			if entry != null:
				items += 1
	return {
		"empty": false,
		"title": title,
		"line1": saved_at,
		"line2": "位置 (%.0f, %.0f) · 物品 %d" % [x, z, items],
		"saved_at": saved_at,
		"item_count": items,
		"x": x,
		"z": z,
	}


func save_game(slot: int, tree: SceneTree = null) -> bool:
	if slot < 0 or slot >= SLOT_COUNT:
		return false
	if tree == null:
		tree = get_tree()
	if tree == null:
		return false
	var player := tree.get_first_node_in_group("player") as Node3D
	var inv := tree.get_first_node_in_group("inventory_ui")
	if player == null:
		push_warning("Save failed: no player")
		return false

	var player_data := {}
	if player.has_method("get_save_data"):
		player_data = player.call("get_save_data")
	var inv_data: Array = []
	if inv != null and inv.has_method("get_save_data"):
		inv_data = inv.call("get_save_data")
	var pickup_data: Array = []
	var forest := tree.get_first_node_in_group("forest_world")
	if forest != null and forest.has_method("get_collected_pickups"):
		pickup_data = forest.call("get_collected_pickups")

	var data := {
		"version": SAVE_VERSION,
		"slot": slot + 1,
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"player": player_data,
		"inventory": inv_data,
		"collected_pickups": pickup_data,
	}
	var json := JSON.stringify(data, "\t")
	var f := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if f == null:
		push_error("Save failed: cannot write %s" % slot_path(slot))
		return false
	f.store_string(json)
	return true


func load_slot_dict(slot: int) -> Dictionary:
	if not has_save(slot):
		return {}
	var f := FileAccess.open(slot_path(slot), FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary


func apply_slot_to_world(slot: int, tree: SceneTree = null) -> bool:
	if tree == null:
		tree = get_tree()
	var data := load_slot_dict(slot)
	if data.is_empty():
		return false
	var player := tree.get_first_node_in_group("player")
	var inv := tree.get_first_node_in_group("inventory_ui")
	var forest := tree.get_first_node_in_group("forest_world")
	if player != null and player.has_method("apply_save_data") and data.has("player"):
		player.call("apply_save_data", data["player"])
	if inv != null and inv.has_method("apply_save_data") and data.has("inventory"):
		inv.call("apply_save_data", data["inventory"])
	if forest != null and forest.has_method("apply_collected_pickups") and data.has("collected_pickups"):
		forest.call("apply_collected_pickups", data["collected_pickups"])
	return true


func apply_to_world(tree: SceneTree = null) -> bool:
	return apply_slot_to_world(pending_slot, tree)


func newest_slot() -> int:
	var best := -1
	var best_time := ""
	for i in SLOT_COUNT:
		if not has_save(i):
			continue
		var s := get_slot_summary(i)
		var t := str(s.get("saved_at", ""))
		if best < 0 or t > best_time:
			best = i
			best_time = t
	return best


func _migrate_legacy_save() -> void:
	if not FileAccess.file_exists(LEGACY_PATH):
		return
	if has_save(0):
		return
	var src := FileAccess.open(LEGACY_PATH, FileAccess.READ)
	if src == null:
		return
	var text := src.get_as_text()
	src = null
	var dst := FileAccess.open(slot_path(0), FileAccess.WRITE)
	if dst == null:
		return
	dst.store_string(text)
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove("savegame.json")
