extends RefCounted

## Eight independent benchmark owners cover all four playable faction templates.
## They keep separate rule IDs, requirements, ownership, economy and production.
const ART_TEMPLATES = ["rivet", "kestrel", "iron", "sky"]
const FIXTURE_VERSION = "eight_owners_four_factions_v2"

static func ids() -> Array[String]:
	return ["rivet", "kestrel", "iron", "sky", "bench_4", "bench_5", "bench_6", "bench_7"]

static func art_template(team: int) -> String:
	return ART_TEMPLATES[team % ART_TEMPLATES.size()]

static func make_rules(source: Dictionary) -> Dictionary:
	var config: Dictionary = source.duplicate(true)
	var factions: Array[String] = ids()
	for team in range(4, factions.size()):
		var template: String = art_template(team)
		var faction: String = factions[team]
		config.factions[faction] = source.factions[template].duplicate(true)
		config.factions[faction].name = "压力势力 %d" % (team + 1)
		config.factions[faction].description = "性能测试用独立势力，使用" + str(source.factions[template].name) + "的完整规则与美术。"
		for category in ["units", "buildings"]:
			for spec_id in source[category]:
				var spec: Dictionary = source[category][spec_id]
				if spec.faction != template: continue
				var clone: Dictionary = spec.duplicate(true)
				clone.faction = faction
				clone.art_faction = template
				clone.requires = []
				for required in spec.get("requires", []): clone.requires.append(str(required).replace(template + "_", faction + "_"))
				config[category][str(spec_id).replace(template + "_", faction + "_")] = clone
	return config
