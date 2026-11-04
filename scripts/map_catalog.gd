extends RefCounted
## All playable maps: default forest + map.txt placeholders.


static func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		{
			"id": "forest",
			"name": "默认森林",
			"category": "已有",
			"blurb": "1000×1000 米完整可玩场景",
			"scene": "res://scenes/maps/forest.tscn",
			"ready": true,
		},
	]
	for m in _map_txt_entries():
		out.append(m)
	return out


static func find(map_id: String) -> Dictionary:
	for e in entries():
		if str(e.get("id", "")) == map_id:
			return e
	return {}


static func _map_txt_entries() -> Array[Dictionary]:
	## id / name / category / blurb — scenes under res://scenes/maps/
	var rows: Array[Dictionary] = [
		{"id": "abandoned_supermarket", "name": "废弃超市", "category": "工业", "blurb": "货架倒塌、冷柜闪烁"},
		{"id": "underground_parking", "name": "地下停车场", "category": "工业", "blurb": "昏暗车位、滴水声"},
		{"id": "abandoned_cruise", "name": "废弃游轮", "category": "工业", "blurb": "倾斜甲板、赌场大厅"},
		{"id": "nuclear_plant", "name": "核电站", "category": "工业", "blurb": "辐射警告、冷却塔"},
		{"id": "museum", "name": "博物馆", "category": "文化", "blurb": "展厅、玻璃柜、安保"},
		{"id": "casino_ruins", "name": "赌场废墟", "category": "文化", "blurb": "霓虹残破、老虎机成排"},
		{"id": "egypt_pyramid", "name": "古埃及金字塔", "category": "文化", "blurb": "甬道、壁画、石棺"},
		{"id": "japanese_shrine", "name": "日式神社", "category": "文化", "blurb": "鸟居、樱花、灯笼"},
		{"id": "pirate_island", "name": "海盗岛", "category": "文化", "blurb": "沙滩、洞穴、沉船"},
		{"id": "space_station", "name": "太空站", "category": "科幻", "blurb": "失重舱、舷窗、控制台"},
		{"id": "cyberpunk_district", "name": "赛博朋克街区", "category": "科幻", "blurb": "霓虹、雨水、全息广告"},
		{"id": "bio_lab", "name": "生化实验室", "category": "科幻", "blurb": "培养舱、警报、绿液"},
		{"id": "time_rift", "name": "时间裂隙", "category": "科幻", "blurb": "破碎空间、时间残影"},
		{"id": "abandoned_hospital", "name": "废弃医院", "category": "恐怖", "blurb": "走廊、病床、手术室"},
		{"id": "haunted_amusement", "name": "鬼屋游乐园", "category": "恐怖", "blurb": "旋转木马、鬼屋"},
		{"id": "deep_sea_wreck", "name": "深海沉船", "category": "恐怖", "blurb": "黑暗、水压、发光鱼"},
		{"id": "jungle_ruins", "name": "丛林遗迹", "category": "自然", "blurb": "藤蔓、石像、瀑布"},
		{"id": "snow_camp", "name": "雪山营地", "category": "自然", "blurb": "暴风雪、木屋、缆车"},
		{"id": "volcano_mine", "name": "火山矿洞", "category": "自然", "blurb": "岩浆、矿车、熔炉"},
		{"id": "spirit_forest", "name": "精灵森林", "category": "自然", "blurb": "发光蘑菇、树屋"},
		{"id": "inverted_world", "name": "倒置世界", "category": "特殊", "blurb": "上下颠倒、头顶深渊"},
		{"id": "mirror_level", "name": "镜像关卡", "category": "特殊", "blurb": "左右完全对称"},
		{"id": "maze_casino", "name": "迷宫赌城", "category": "特殊", "blurb": "每面墙都是老虎机"},
		{"id": "ghost_train", "name": "幽灵列车", "category": "特殊", "blurb": "行驶中的列车"},
		{"id": "gamble_arena", "name": "赌命竞技场", "category": "特殊", "blurb": "斗兽场、聚光灯"},
	]
	for r in rows:
		r["scene"] = "res://scenes/maps/%s.tscn" % str(r["id"])
		r["ready"] = false
	return rows
