extends Control
## Loading bridge into the forest scene. Keep the dark cover — game scene continues it.

const GAME_SCENE := "res://scenes/main.tscn"


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	DisplayServer.window_move_to_foreground()
	# One frame so this screen paints, then hand off (main scene shows its own overlay).
	await get_tree().process_frame
	get_tree().change_scene_to_file(GAME_SCENE)
