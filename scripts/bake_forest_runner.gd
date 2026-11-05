extends SceneTree
## Headless: generate forest.tscn once, bake to forest_baked.tscn, quit.
## Usage: godot --headless --path . -s res://scripts/bake_forest_runner.gd


const FOREST_SCENE := "res://scenes/maps/forest.tscn"
const OUT_PATH := "res://scenes/maps/forest_baked.tscn"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("BAKE: loading ", FOREST_SCENE)
	var packed := load(FOREST_SCENE) as PackedScene
	if packed == null:
		push_error("BAKE: cannot load forest.tscn")
		quit(1)
		return
	var main := packed.instantiate() as Node3D
	if main == null:
		push_error("BAKE: instantiate failed")
		quit(1)
		return
	root.add_child(main)

	var forest: Node = null
	var frames := 0
	while frames < 3600:
		await process_frame
		frames += 1
		forest = get_first_node_in_group("forest_world")
		if forest != null and bool(forest.get("world_ready")):
			break
		if frames % 60 == 0:
			print("BAKE: waiting world_ready... frame ", frames)

	if forest == null or not bool(forest.get("world_ready")):
		push_error("BAKE: timed out waiting for forest")
		quit(1)
		return

	print("BAKE: world ready, converting...")
	# Let one more frame settle Multimeshes / houses.
	await process_frame
	var Bake := preload("res://scripts/bake_forest_scene.gd")
	var err: String = Bake.bake_live_main(main, OUT_PATH)
	if err != "":
		push_error("BAKE failed: " + err)
		quit(1)
		return
	print("BAKE OK: ", OUT_PATH)
	quit(0)
