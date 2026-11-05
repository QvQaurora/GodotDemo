extends RefCounted
## Playable maps catalog.


static func entries() -> Array[Dictionary]:
	return [
		{
			"id": "forest",
			"name": "默认森林",
			"category": "已有",
			"blurb": "1000×1000 米完整可玩场景",
			"scene": "res://scenes/maps/forest.tscn",
			"ready": true,
		},
	]


static func find(map_id: String) -> Dictionary:
	for e in entries():
		if str(e.get("id", "")) == map_id:
			return e
	return {}
