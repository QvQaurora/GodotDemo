extends Node3D
## Game scene bootstrap: apply saved graphics after the world exists.


func _ready() -> void:
	call_deferred("_apply")


func _apply() -> void:
	GameSettings.apply_audio()
	GameSettings.apply_graphics()
