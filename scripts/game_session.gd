extends Node
## Cross-menu session: which map to load after the loading screen.

var selected_map_id: String = "forest"
var selected_scene_path: String = "res://scenes/maps/forest.tscn"


func select_map(map_id: String, scene_path: String) -> void:
	selected_map_id = map_id
	selected_scene_path = scene_path


func reset_to_forest() -> void:
	select_map("forest", "res://scenes/maps/forest.tscn")
