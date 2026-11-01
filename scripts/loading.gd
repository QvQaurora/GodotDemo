extends Control
## Brief loading screen, then loads the forest game scene.

const GAME_SCENE := "res://scenes/main.tscn"


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	DisplayServer.window_move_to_foreground()
	# Let the loading UI draw a few frames before the heavy scene builds.
	for _i in 3:
		await get_tree().process_frame
	get_tree().change_scene_to_file(GAME_SCENE)
