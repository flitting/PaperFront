extends SceneTree

const MAP = preload("res://scripts/map_data.gd")
const LAYOUT = preload("res://scripts/competitive_layout.gd")
const NAVAL = preload("res://scripts/naval_navigation.gd")
var failed: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok: failed.append(label)

func run() -> void:
	for mode in ["city", "random_city", "forest", "desert", "snow", "islands"]:
		for players in [2, 3, 4]:
			var map: Dictionary = MAP.generate(mode, 7, {"players":players})
			check(bool(map.get("valid", false)), "%s/%d validates: %s" % [mode, players, str(map.get("validation_errors", []))])
			check(int(map.profile.get("design_version", 0)) == 6, "%s/%d uses authored topology" % [mode, players])
			check((map.bridges.size() >= 3 or mode == "islands") and map.ruins.size() >= 40, "%s/%d bridges and physical scenery" % [mode, players])
			check(map.profile.water_fraction > (.60 if mode == "islands" else .15) and map.profile.water_fraction < (.70 if mode == "islands" else .50), "%s/%d connected water fraction" % [mode, players])
			var wet: PackedByteArray = LAYOUT.flood(map, Vector2i.ZERO, true)
			var naval = NAVAL.new()
			naval.configure(map, map.bridges)
			for bridge: Dictionary in map.bridges:
				var center: Vector2i = Vector2i(int(bridge.bounds[0] + bridge.bounds[2] / 2), int(bridge.bounds[1] + bridge.bounds[3] / 2))
				check(wet[center.y * 320 + center.x] == 1, "%s/%d water connected below bridge %d" % [mode, players, bridge.id])
				check(naval.static_clear(Vector2(center) + Vector2.ONE * .5, 3.25, 2.25), "%s/%d wide ship clears bridge %d" % [mode, players, bridge.id])
			print("V6_%s players=%d valid=%s ruins=%d props=%d people=%d water=%.3f" % [mode, players, str(map.valid), map.ruins.size(), map.environment_props.size(), map.civilians.size(), map.profile.water_fraction])
	var legacy: Dictionary = LAYOUT.generate_legacy("city", 7, {"players":3})
	check(legacy.profile.schema == 3 and not legacy.profile.has("design_version") and MAP.validate(legacy).is_empty(), "legacy schema-3 city layout still validates")
	print("V6 map checks: %d failed" % failed.size())
	for item in failed: push_error(item)
	quit(1 if not failed.is_empty() else 0)
