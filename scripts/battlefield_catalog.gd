extends RefCounted
class_name BattlefieldCatalog

const SCHEMA: int = 3
const MODES: Array[String] = ["forest", "desert", "snow", "city", "random_city", "islands"]
const FIXED_MODES: Array[String] = ["symmetric"]
const REMOVED_MENU_MODES: Array[String] = ["handmade", "random", "mountains", "mountains640"]
const PROFILES = {
	"forest": {"title": "翠林溪谷", "biome": "forest", "size": 320, "routes": "land", "ground": "879865", "road": "b29d7b", "water": "437f8f"},
	"desert": {"title": "金砂峡谷", "biome": "desert", "size": 320, "routes": "land", "ground": "d6bc83", "road": "bca175", "water": "419796"},
	"snow": {"title": "白雪冻河", "biome": "snow", "size": 320, "routes": "land", "ground": "dedfd6", "road": "a3a99b", "water": "719cad"},
	"city": {"title": "纸城河港", "biome": "city", "size": 320, "routes": "land", "ground": "b9b19d", "road": "777e78", "water": "517f88"},
	"random_city": {"title": "种子城市", "biome": "city", "size": 320, "routes": "land", "ground": "b9b19d", "road": "777e78", "water": "517f88"},
	"islands": {"title": "远海群岛", "biome": "islands", "size": 320, "routes": "naval", "ground": "baa77c", "road": "a59779", "water": "3e91a1"}
}

static func has_profile(mode: String) -> bool:
	return PROFILES.has(mode)

static func profile(mode: String, players: int) -> Dictionary:
	var result: Dictionary = PROFILES[mode].duplicate(true)
	result.schema = SCHEMA
	result.id = mode
	result.players = clampi(players, 2, 4)
	result.layout = "triangle" if result.players == 3 else "opposed" if result.players == 2 else "quadrilateral"
	return result

static func entries(include_legacy: bool = true) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for mode: String in MODES:
		result.append({"id": mode, "name": PROFILES[mode].title, "size": 320, "players": [2, 3, 4]})
	result.append({"id": "symmetric", "name": display_name("symmetric"), "size": 192, "players": [2]})
	if include_legacy:
		# Historical generators remain available for old saves and validation,
		# while these four maps no longer appear in the new-match catalogue.
		for mode: String in ["dev"]:
			result.append({"id": mode, "name": display_name(mode), "size": 48 if mode == "dev" else 640 if mode == "mountains640" else 320 if mode == "mountains" else 160, "players": [2]})
	return result

static func selectable_mode(mode: String, debug_enabled: bool = false) -> String:
	if mode in MODES or mode in FIXED_MODES or (mode == "dev" and debug_enabled): return mode
	return "forest"

static func display_name(mode: String) -> String:
	if PROFILES.has(mode): return str(PROFILES[mode].title)
	return str({"symmetric": "明原对称场（2人）", "handmade": "经典河谷（2人）", "random": "经典随机（2人）", "mountains": "山地盆地（2人）", "mountains640": "巨型山地（2人）", "dev": "开发测试（2人）"}.get(mode, mode))
