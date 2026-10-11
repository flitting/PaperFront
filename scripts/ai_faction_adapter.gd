extends RefCounted

## Strategy preferences only. Prices, technology, placement, fog and weapon
## rules remain authoritative in Simulation for every faction and style.
const PROFILES := {
	"kestrel":{"infantry":["rifle","rifle","anti","gunner","rifle","marksman"], "vehicles":["tank","tank","scout","tank","artillery","heavy_tank"], "air":["attacker","helicopter"], "tech_after":170.0, "air_after":230.0, "builders":1},
	"rivet":{"infantry":["rifle","grenadier","anti","rifle","gunner"], "vehicles":["tank","tank","scout","assault","tank","heavy_tank"], "air":["zeppelin","bomber","helicopter"], "tech_after":145.0, "air_after":205.0, "builders":2},
	"iron":{"infantry":["rifle","rifle","anti","marksman","mortar"], "vehicles":["tank","tank","scout","artillery","tank","assault"], "air":["attacker","helicopter"], "tech_after":155.0, "air_after":245.0, "builders":1},
	"sky":{"infantry":["rifle","storm","anti","rifle"], "vehicles":["tank","tank","scout","disruptor","artillery","tank"], "air":["attacker","helicopter"], "tech_after":135.0, "air_after":180.0, "builders":1}
}

static func profile(faction: String, style: String = "balanced") -> Dictionary:
	var result: Dictionary = PROFILES.get(faction, PROFILES.kestrel).duplicate(true)
	result.style = style if style in ["balanced","pressure","armor"] else "balanced"
	result.infantry_limit = 12
	result.wave_scale = 1.0
	result.attack_scale = 1.0
	result.factory_share = .55
	match str(result.style):
		"pressure":
			result.infantry_limit = 22
			result.wave_scale = .75
			result.attack_scale = .75
			result.tech_after = float(result.tech_after) + 65.0
			result.air_after = float(result.air_after) + 75.0
			result.factory_share = .35
		"armor":
			result.infantry_limit = 6
			result.wave_scale = .75
			result.attack_scale = 1.25
			result.factory_share = .8
	return result

static func infantry(faction: String, profile_data: Dictionary, index: int, observed: Dictionary) -> String:
	if int(observed.get("air", 0)) > 0 and index % 3 == 0 and faction in ["kestrel","sky"]: return faction + "_aa_infantry"
	if int(observed.get("armored", 0)) > int(observed.get("infantry", 0)) and index % 2 == 0: return faction + "_anti"
	var choices: Array = profile_data.infantry
	return faction + "_" + str(choices[index % choices.size()])

static func vehicle(faction: String, profile_data: Dictionary, index: int, observed: Dictionary) -> String:
	if int(observed.get("air", 0)) > 0 and index % 3 == 1: return faction + "_aa"
	if str(profile_data.style) == "armor" and index % 4 != 3: return faction + ("_heavy_tank" if index % 4 == 2 else "_tank")
	var choices: Array = profile_data.vehicles
	return faction + "_" + str(choices[index % choices.size()])
