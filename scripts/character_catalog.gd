extends RefCounted
## Kenney Animated Characters: body shapes + outfit skins.

const BODY_DIR := "res://assets/kenney_characters/"
const SKIN_DIR := "res://assets/kenney_characters/Skins/"

## id, display name, fbx filename, target height meters.
## Always use characterMedium.fbx: Kenney small/large FBX ships with a broken
## centimeter Root scale (×100 on already-meter meshes) and warps in-engine.
const BODIES: Array[Dictionary] = [
	{"id": "small", "name": "娇小", "file": "characterMedium.fbx", "height": 1.65},
	{"id": "medium", "name": "标准", "file": "characterMedium.fbx", "height": 1.8},
	{"id": "large", "name": "高大", "file": "characterMedium.fbx", "height": 1.95},
]

## Fixed preview framing reference so body-size differences stay visible on screen.
const PREVIEW_FRAME_HEIGHT := 1.95

const ACC_DIR := "res://assets/kenney_characters/Accessories/"
## Accessories are ~1m authored; skeleton bind pose is ~cm (~0.004 fits a ~1m prop to the head).
const ACC_BONE_SCALE := 0.004

## Wear slots persisted in GameSettings.player_gear.
const GEAR_SLOTS: Array[Dictionary] = [
	{"id": "hat", "name": "帽子"},
	{"id": "glasses", "name": "眼镜"},
	{"id": "hair", "name": "发型"},
	{"id": "face", "name": "面部"},
	{"id": "backpack", "name": "背包"},
	{"id": "hand_r", "name": "右手"},
]

## How to hand-calibrate ONE accessory (then tell me the numbers):
## 1. Edit the matching line in ACCESSORIES below (start with "cap").
## 2. Change only: scale / offset / rot_deg
## 3. Save, restart game, open 玩家 preview, check.
## Bone-local axes on Head / Head_end:
##   +X = 角色左(+)/右(-) 视朝向而定，先微调 offset.x
##   +Y = 头顶方向（越大越往上）
##   +Z = 脸朝前（越大越往脸外）
## Typical ranges after scale≈0.004:
##   offset components about -0.01 .. 0.01
##   scale about 0.003 .. 0.006
const SLOT_FIT: Dictionary = {
	"hat": {"bone": "Head_end", "offset": Vector3(0.0, 0.0, 0.0), "rot_deg": Vector3(0, 0, 0), "scale": 0.004},
	"glasses": {"bone": "Head", "offset": Vector3(0.0, 0.0, 0.0045), "rot_deg": Vector3(0, 0, 0), "scale": 0.004},
	"hair": {"bone": "Head_end", "offset": Vector3(0.0, -0.001, 0.0), "rot_deg": Vector3(0, 0, 0), "scale": 0.004},
	"face": {"bone": "Head", "offset": Vector3(0.0, -0.002, 0.0035), "rot_deg": Vector3(0, 0, 0), "scale": 0.004},
	"backpack": {"bone": "UpperChest", "offset": Vector3(0.0, -0.001, -0.004), "rot_deg": Vector3(0, 0, 0), "scale": 0.004},
	"hand_r": {"bone": "RightHand", "offset": Vector3(0.0, 0.0, 0.0), "rot_deg": Vector3(0, 0, -90), "scale": 0.0035},
}

## Calibrate this first — reply with final scale/offset/rot_deg when cap looks right:
## {"id": "cap", "scale": ?, "offset": Vector3(?, ?, ?), "rot_deg": Vector3(?, ?, ?)}
const ACCESSORIES: Array[Dictionary] = [
	{"id": "strawhat", "name": "草帽", "slot": "hat", "file": "strawhat.fbx"},
	{"id": "cap", "name": "棒球帽", "slot": "hat", "file": "cap.fbx", "scale": 0.004, "offset": Vector3(0.0, 0.0, 0.0), "rot_deg": Vector3(0, 0, 0)},
	{"id": "farmerCap", "name": "农夫帽", "slot": "hat", "file": "farmerCap.fbx"},
	{"id": "fantasyCap", "name": "奇幻帽", "slot": "hat", "file": "fantasyCap.fbx"},
	{"id": "militaryBeret", "name": "贝雷帽", "slot": "hat", "file": "militaryBeret.fbx"},
	{"id": "militaryHelmet", "name": "军用头盔", "slot": "hat", "file": "militaryHelmet.fbx"},
	{"id": "racingHelmet", "name": "赛车头盔", "slot": "hat", "file": "racingHelmet.fbx"},
	{"id": "astroHelmet", "name": "航天头盔", "slot": "hat", "file": "astroHelmet.fbx"},
	{"id": "glassesRound", "name": "圆框眼镜", "slot": "glasses", "file": "glassesRound.fbx"},
	{"id": "glassesRetro", "name": "复古眼镜", "slot": "glasses", "file": "glassesRetro.fbx"},
	{"id": "hairBobcut", "name": "波波头", "slot": "hair", "file": "hairBobcut.fbx"},
	{"id": "hairPigtail", "name": "双马尾", "slot": "hair", "file": "hairPigtail.fbx"},
	{"id": "hairPonytail", "name": "马尾", "slot": "hair", "file": "hairPonytail.fbx"},
	{"id": "hairTail", "name": "短尾发", "slot": "hair", "file": "hairTail.fbx"},
	{"id": "beard", "name": "胡子", "slot": "face", "file": "beard.fbx"},
	{"id": "modernBackpack", "name": "现代背包", "slot": "backpack", "file": "modernBackpack.fbx"},
	{"id": "fantasyBackpack", "name": "奇幻背包", "slot": "backpack", "file": "fantasyBackpack.fbx"},
	{"id": "militaryBackpack", "name": "军用背包", "slot": "backpack", "file": "militaryBackpack.fbx"},
	{"id": "astroBackpack", "name": "航天背包", "slot": "backpack", "file": "astroBackpack.fbx"},
	{"id": "sword", "name": "剑", "slot": "hand_r", "file": "sword.fbx", "rot_deg": Vector3(0, 0, -90)},
	{"id": "pistol", "name": "手枪", "slot": "hand_r", "file": "pistol.fbx", "rot_deg": Vector3(0, 90, -90)},
	{"id": "rifle", "name": "步枪", "slot": "hand_r", "file": "rifle.fbx", "rot_deg": Vector3(0, 90, -90)},
	{"id": "pitchfork", "name": "干草叉", "slot": "hand_r", "file": "pitchfork.fbx", "rot_deg": Vector3(0, 0, -90)},
	{"id": "shield", "name": "盾牌", "slot": "hand_r", "bone": "LeftHand", "file": "shield.fbx", "rot_deg": Vector3(0, 0, 90)},
	{"id": "astroGun", "name": "航天枪", "slot": "hand_r", "file": "astroGun.fbx", "rot_deg": Vector3(0, 90, -90)},
]

## id, Chinese name, category
const OUTFITS: Array[Dictionary] = [
	{"id": "skaterMaleA", "name": "滑板男", "cat": "主角"},
	{"id": "skaterFemaleA", "name": "滑板女", "cat": "主角"},
	{"id": "cyborgFemaleA", "name": "半机械女", "cat": "主角"},
	{"id": "criminalMaleA", "name": "白西装歹徒", "cat": "主角"},
	{"id": "survivorMaleA", "name": "幸存者男 A", "cat": "幸存者"},
	{"id": "survivorMaleB", "name": "幸存者男 B", "cat": "幸存者"},
	{"id": "survivorFemaleA", "name": "幸存者女 A", "cat": "幸存者"},
	{"id": "survivorFemaleB", "name": "幸存者女 B", "cat": "幸存者"},
	{"id": "humanMaleA", "name": "复古男", "cat": "幸存者"},
	{"id": "humanFemaleA", "name": "复古女", "cat": "幸存者"},
	{"id": "casualMaleA", "name": "休闲男 A", "cat": "日常"},
	{"id": "casualMaleB", "name": "休闲男 B", "cat": "日常"},
	{"id": "casualFemaleA", "name": "休闲女 A", "cat": "日常"},
	{"id": "casualFemaleB", "name": "休闲女 B", "cat": "日常"},
	{"id": "businessMaleA", "name": "商务男 A", "cat": "日常"},
	{"id": "businessMaleB", "name": "商务男 B", "cat": "日常"},
	{"id": "farmerA", "name": "农夫 A", "cat": "日常"},
	{"id": "farmerB", "name": "农夫 B", "cat": "日常"},
	{"id": "militaryMaleA", "name": "军人男 A", "cat": "职业"},
	{"id": "militaryMaleB", "name": "军人男 B", "cat": "职业"},
	{"id": "militaryFemaleA", "name": "军人女 A", "cat": "职业"},
	{"id": "militaryFemaleB", "name": "军人女 B", "cat": "职业"},
	{"id": "fantasyMaleA", "name": "奇幻男 A", "cat": "奇幻"},
	{"id": "fantasyMaleB", "name": "奇幻男 B", "cat": "奇幻"},
	{"id": "fantasyFemaleA", "name": "奇幻女 A", "cat": "奇幻"},
	{"id": "fantasyFemaleB", "name": "奇幻女 B", "cat": "奇幻"},
	{"id": "astroMaleA", "name": "航天男 A", "cat": "航天"},
	{"id": "astroMaleB", "name": "航天男 B", "cat": "航天"},
	{"id": "astroFemaleA", "name": "航天女 A", "cat": "航天"},
	{"id": "astroFemaleB", "name": "航天女 B", "cat": "航天"},
	{"id": "athleteMaleBlue", "name": "运动员男·蓝", "cat": "运动"},
	{"id": "athleteMaleGreen", "name": "运动员男·绿", "cat": "运动"},
	{"id": "athleteMaleRed", "name": "运动员男·红", "cat": "运动"},
	{"id": "athleteMaleYellow", "name": "运动员男·黄", "cat": "运动"},
	{"id": "athleteFemaleBlue", "name": "运动员女·蓝", "cat": "运动"},
	{"id": "athleteFemaleGreen", "name": "运动员女·绿", "cat": "运动"},
	{"id": "athleteFemaleRed", "name": "运动员女·红", "cat": "运动"},
	{"id": "athleteFemaleYellow", "name": "运动员女·黄", "cat": "运动"},
	{"id": "racerBlueMale", "name": "赛车男·蓝", "cat": "赛车"},
	{"id": "racerBlueFemale", "name": "赛车女·蓝", "cat": "赛车"},
	{"id": "racerGreenMale", "name": "赛车男·绿", "cat": "赛车"},
	{"id": "racerGreenFemale", "name": "赛车女·绿", "cat": "赛车"},
	{"id": "racerOrangeMale", "name": "赛车男·橙", "cat": "赛车"},
	{"id": "racerOrangeFemale", "name": "赛车女·橙", "cat": "赛车"},
	{"id": "racerPurpleMale", "name": "赛车男·紫", "cat": "赛车"},
	{"id": "racerPurpleFemale", "name": "赛车女·紫", "cat": "赛车"},
	{"id": "racerRedMale", "name": "赛车男·红", "cat": "赛车"},
	{"id": "racerRedFemale", "name": "赛车女·红", "cat": "赛车"},
	{"id": "alienA", "name": "外星人 A", "cat": "科幻"},
	{"id": "alienB", "name": "外星人 B", "cat": "科幻"},
	{"id": "cyborg", "name": "赛博格", "cat": "科幻"},
	{"id": "robot", "name": "机器人 1", "cat": "科幻"},
	{"id": "robot2", "name": "机器人 2", "cat": "科幻"},
	{"id": "robot3", "name": "机器人 3", "cat": "科幻"},
	{"id": "zombieA", "name": "僵尸 A", "cat": "僵尸"},
	{"id": "zombieB", "name": "僵尸 B", "cat": "僵尸"},
	{"id": "zombieC", "name": "僵尸 C", "cat": "僵尸"},
	{"id": "zombieMaleA", "name": "复古僵尸男", "cat": "僵尸"},
	{"id": "zombieFemaleA", "name": "复古僵尸女", "cat": "僵尸"},
]


static func body_path(body_id: String) -> String:
	var body := find_body(body_id)
	return BODY_DIR + str(body.get("file", "characterMedium.fbx"))


static func body_height(body_id: String) -> float:
	var body := find_body(body_id)
	return float(body.get("height", 1.8))


static func skin_path(outfit_id: String) -> String:
	return SKIN_DIR + outfit_id + ".png"


static func find_body(body_id: String) -> Dictionary:
	for b in BODIES:
		if str(b.get("id", "")) == body_id:
			return b
	return BODIES[0]


static func find_outfit(outfit_id: String) -> Dictionary:
	for o in OUTFITS:
		if str(o.get("id", "")) == outfit_id:
			return o
	return OUTFITS[0]


static func outfit_categories() -> Array[String]:
	var cats: Array[String] = []
	for o in OUTFITS:
		var c := str(o.get("cat", ""))
		if c != "" and not cats.has(c):
			cats.append(c)
	return cats


static func outfits_in_category(cat: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for o in OUTFITS:
		if str(o.get("cat", "")) == cat:
			out.append(o)
	return out


static func resolve_existing_body_id(body_id: String) -> String:
	# Legacy ids from the earlier 4-body picker.
	if body_id == "large_male" or body_id == "large_female":
		body_id = "large"
	for b in BODIES:
		if str(b.get("id", "")) == body_id:
			var path := body_path(body_id)
			if ResourceLoader.exists(path):
				return body_id
			break
	return "medium"


static func resolve_existing_outfit_id(outfit_id: String) -> String:
	var path := skin_path(outfit_id)
	if ResourceLoader.exists(path):
		return outfit_id
	return "skaterMaleA"


static func accessory_path(acc_id: String) -> String:
	var acc := find_accessory(acc_id)
	if acc.is_empty():
		return ""
	return ACC_DIR + str(acc.get("file", ""))


static func find_accessory(acc_id: String) -> Dictionary:
	if acc_id == "" or acc_id == "none":
		return {}
	for a in ACCESSORIES:
		if str(a.get("id", "")) == acc_id:
			return a
	return {}


## Runtime calibration overrides: acc_id -> {scale, offset, rot_deg}. Not persisted.
static var fit_overrides: Dictionary = {}


static func set_fit_override(acc_id: String, scale: float, offset: Vector3, rot_deg: Vector3) -> void:
	if acc_id == "":
		return
	fit_overrides[acc_id] = {
		"scale": scale,
		"offset": offset,
		"rot_deg": rot_deg,
	}


static func clear_fit_override(acc_id: String) -> void:
	fit_overrides.erase(acc_id)


static func accessory_fit(acc: Dictionary) -> Dictionary:
	## Merge slot defaults with per-item overrides into {bone, offset, rot_deg, scale}.
	var slot := str(acc.get("slot", ""))
	var fit: Dictionary = SLOT_FIT.get(slot, {
		"bone": "Head",
		"offset": Vector3.ZERO,
		"rot_deg": Vector3.ZERO,
		"scale": ACC_BONE_SCALE,
	}).duplicate(true)
	if acc.has("bone"):
		fit["bone"] = str(acc["bone"])
	if acc.has("offset"):
		fit["offset"] = acc["offset"]
	if acc.has("rot_deg"):
		fit["rot_deg"] = acc["rot_deg"]
	if acc.has("scale"):
		fit["scale"] = float(acc["scale"])
	var acc_id := str(acc.get("id", ""))
	if acc_id != "" and fit_overrides.has(acc_id):
		var ov: Dictionary = fit_overrides[acc_id]
		if ov.has("scale"):
			fit["scale"] = float(ov["scale"])
		if ov.has("offset"):
			fit["offset"] = ov["offset"]
		if ov.has("rot_deg"):
			fit["rot_deg"] = ov["rot_deg"]
	return fit


static func format_accessory_line(acc_id: String, scale: float, offset: Vector3, rot_deg: Vector3) -> String:
	var acc := find_accessory(acc_id)
	if acc.is_empty():
		return ""
	return (
		'{"id": "%s", "name": "%s", "slot": "%s", "file": "%s", "scale": %.4f, "offset": Vector3(%.4f, %.4f, %.4f), "rot_deg": Vector3(%.1f, %.1f, %.1f)},'
		% [
			acc_id,
			str(acc.get("name", acc_id)),
			str(acc.get("slot", "")),
			str(acc.get("file", "")),
			scale,
			offset.x, offset.y, offset.z,
			rot_deg.x, rot_deg.y, rot_deg.z,
		]
	)


static func accessories_in_slot(slot_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a in ACCESSORIES:
		if str(a.get("slot", "")) == slot_id:
			out.append(a)
	return out


static func default_gear() -> Dictionary:
	var g := {}
	for s in GEAR_SLOTS:
		g[str(s.get("id", ""))] = ""
	return g


static func sanitize_gear(gear: Dictionary) -> Dictionary:
	var out := default_gear()
	for s in GEAR_SLOTS:
		var sid := str(s.get("id", ""))
		var aid := str(gear.get(sid, ""))
		if aid == "" or aid == "none":
			out[sid] = ""
			continue
		var acc := find_accessory(aid)
		if acc.is_empty():
			out[sid] = ""
			continue
		if str(acc.get("slot", "")) != sid:
			out[sid] = ""
			continue
		if not ResourceLoader.exists(accessory_path(aid)):
			out[sid] = ""
			continue
		out[sid] = aid
	return out
