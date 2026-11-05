extends RefCounted
## Playable maps catalog.


static func entries() -> Array[Dictionary]:
	return [
		{
			"id": "forest",
			"name": "默认森林",
			"category": "已有",
			"blurb": "1000×1000 米静态可视场景（可在编辑器中打开）",
			"scene": "res://scenes/maps/forest_baked.tscn",
			"ready": true,
		},
		{
			"id": "forest_gen",
			"name": "森林（程序化源）",
			"category": "工具",
			"blurb": "用于重新烘焙的流式生成源场景",
			"scene": "res://scenes/maps/forest.tscn",
			"ready": true,
		},
	]


static func find(map_id: String) -> Dictionary:
	for e in entries():
		if str(e.get("id", "")) == map_id:
			return e
	return {}
