extends Control
## Loading bridge into the selected map (forest or placeholder).

const FALLBACK_SCENE := "res://scenes/maps/forest.tscn"


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	DisplayServer.window_move_to_foreground()
	await get_tree().process_frame
	var path := FALLBACK_SCENE
	var session := get_node_or_null("/root/GameSession")
	if session != null:
		var candidate := str(session.selected_scene_path)
		if candidate != "" and ResourceLoader.exists(candidate):
			path = candidate
	get_tree().change_scene_to_file(path)
