extends SceneTree

const SIM = preload("res://tests/rule_test_simulation.gd")
const RULES = preload("res://scripts/rules_loader.gd")
const VISION = preload("res://scripts/team_vision.gd")
const CONSTRUCTION = preload("res://scripts/outpost_construction.gd")
const WORLD = preload("res://scripts/paper_world.gd")
const FACTIONS: Array[String] = ["rivet", "kestrel", "iron", "sky"]
var config: Dictionary
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	config = RULES.load_rules("res://data/rules.json", false)
	if config.is_empty(): push_error("Base vision rules invalid: " + str(RULES.errors)); quit(1); return
	for faction in FACTIONS:
		_test_radius(faction, "hq", 28.0)
		if faction != "rivet": _test_radius(faction, "outpost", 24.0)
	check(not config.buildings.has("rivet_outpost") and not config.buildings.has("rivet_barracks"), "Rivet expansion uses the same base barracks sight blueprint")
	_test_terrain_and_air()
	_test_construction_capture_death()
	_test_native_mask_and_stationary_work()
	_test_save_snapshots()
	print("BASE_VISION ", JSON.stringify({"checks": checks, "failures": failures, "hq_radius": 28, "outpost_radius": 24}))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _flat_map(size: int = 96) -> Dictionary:
	var map: Dictionary = {"size": size, "mode": "dev", "seed": 7, "terrain": [], "heights": []}
	for _z in range(size):
		var heights: Array = []; heights.resize(size); heights.fill(0.0)
		var terrain: Array = []; terrain.resize(size); terrain.fill(MapData.LAND)
		map.heights.append(heights); map.terrain.append(terrain)
	return map

func _fixture():
	var sim = SIM.new()
	sim.rules = config.duplicate(true)
	sim.map = _flat_map()
	sim.factions.assign(FACTIONS)
	sim.vision_enabled = true
	sim._resize_team_caches()
	sim.money.resize(4); sim.money.fill(100000.0)
	sim.building_orders = [{}, {}, {}, {}]
	sim.defense_orders = [{}, {}, {}, {}]
	VISION.initialize(sim)
	return sim

func _test_radius(faction: String, role: String, radius: float) -> void:
	var spec: String = faction + "_" + role
	check(float(config.buildings[spec].get("vision_radius", 0.0)) == radius, "explicit balanced sight radius " + spec)
	var sim = _fixture()
	var base: int = sim._spawn(0, spec, Vector2(40, 48), true)
	var center: Vector2 = sim.entities[base].pos
	VISION.refresh(sim, true)
	for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN, Vector2(1, 1).normalized()]:
		check(sim.position_visible_to(0, center + direction * (radius - .05)), spec + " reveals inside expanded circle " + str(direction))
		check(not sim.position_visible_to(0, center + direction * (radius + .05)), spec + " does not reveal beyond expanded circle " + str(direction))
	check(sim.position_visible_to(0, center + Vector2.RIGHT * 20.0), spec + " reveals terrain beyond former twelve-cell radius")
	check(not sim.position_visible_to(1, center + Vector2.RIGHT * 20.0), spec + " vision is exclusive to its owner")
	var construction_radius: float = sim.construction_radius(spec)
	check(construction_radius == float(config.buildings[spec].get("construction_radius", config.economy.construction_radii.get(role, config.economy.construction_radii.default))), spec + " construction authorization remains independent of sight")
	var memberships: int = 0
	for bucket in sim._vision_observers[0].values(): memberships += bucket.size()
	check(memberships <= 25, spec + " observer lookup stays within five by five spatial buckets")

func _test_terrain_and_air() -> void:
	var sim = _fixture()
	var base: int = sim._spawn(0, "rivet_hq", Vector2(30, 48), true)
	var center: Vector2 = sim.entities[base].pos
	var target: Vector2 = center + Vector2(24, 0)
	for z in range(96): sim.map.heights[z][42] = 8.0
	VISION.refresh(sim, true)
	check(not sim.position_visible_to(0, target), "expanded HQ sight still respects a terrain ridge")
	check(sim.position_visible_to(0, target, "air"), "air targets retain their existing terrain occlusion bypass")
	check(not sim.position_visible_to(0, center + Vector2(29, 0), "air"), "air targets remain subject to the expanded sight radius")

func _test_construction_capture_death() -> void:
	var sim = _fixture()
	var outpost: int = sim._spawn(0, "rivet_hq", Vector2(30, 48), false)
	CONSTRUCTION.initialize(sim, sim.entities[outpost], -1)
	var center: Vector2 = sim.entities[outpost].pos
	var probe: Vector2 = center + Vector2(27, 0)
	VISION.refresh(sim, true)
	check(sim.position_visible_to(0, probe), "unfinished base barracks keeps the scaffold observer policy with the same HQ sight radius")
	CONSTRUCTION._complete(sim, sim.entities[outpost])
	sim.time += .2; VISION.refresh(sim)
	check(sim.position_visible_to(0, probe) and sim.entities[outpost].construct_remaining == 0.0, "completed base barracks retains its shared expanded sight on the scheduled refresh")
	var observer: Dictionary = sim.entities[outpost]
	var engineer: int = sim._spawn(1, "kestrel_engineer", center + Vector2(3, 0), true)
	var command: Dictionary = {"kind": "capture", "pos": center, "target": outpost}
	sim.entities[engineer].commands.append(command)
	sim._spawn(0, "rivet_power", Vector2(90, 90), true)
	sim._step_capture(sim.entities[engineer], command, .1)
	sim.time += .2; VISION.refresh(sim)
	check(int(observer.team) == 1 and sim.position_visible_to(1, probe) and not sim.position_visible_to(0, probe), "capture transfers the base barracks sight circle to its new owner")
	sim._kill_entity(outpost, true)
	sim.time += .2; VISION.refresh(sim)
	check(not sim.position_visible_to(1, probe), "destroying the base removes its expanded sight on the scheduled refresh")

func _test_native_mask_and_stationary_work() -> void:
	var sim = _fixture()
	sim._spawn(0, "rivet_hq", Vector2(30, 48), true)
	sim._spawn(0, "rivet_hq", Vector2(70, 48), true)
	var enemy: int = sim._spawn(1, "kestrel_rifle", Vector2(55, 48), true)
	VISION.refresh(sim, true)
	check(sim.entity_visible_to(0, enemy), "expanded observer radius reveals enemy contact beyond twelve cells")
	var slot: int = int(sim._contact_indices[enemy])
	check((sim._contact_visibility[slot] & 1) != 0, "native combat contact visibility matches the expanded observer result")
	var native_memory = WORLD.SightMemory.new()
	var script_memory = WORLD.SightMemory.new()
	check(sim._kernels != null and sim._kernels.has_method("refresh_sight_mask"), "native fog backend is available for actual equivalence checks")
	native_memory.initialize(96); script_memory.initialize(96)
	sim.native_kernels_enabled = true
	var native_changed: bool = native_memory.refresh(sim)
	sim.native_kernels_enabled = false
	var script_changed: bool = script_memory.refresh(sim)
	check(native_changed == script_changed and native_memory.pixels == script_memory.pixels, "native and script fog masks agree for multiple unified base barracks")
	check(not script_memory.refresh(sim) and script_memory.queries == 0, "stationary expanded bases perform zero repeated fog LOS queries")
	sim.native_kernels_enabled = true
	check(not native_memory.refresh(sim) and native_memory.queries == 0, "native stationary expanded bases also skip repeated fog LOS queries")

func _test_save_snapshots() -> void:
	for historical in [false, true]:
		var rules: Dictionary = config.duplicate(true)
		if historical:
			for info: Dictionary in rules.buildings.values():
				if info.get("role", "") in ["hq", "outpost"]: info.erase("vision_radius")
		var sim = SIM.new()
		sim.setup_multiteam(rules, "dev", 7, ["rivet", "kestrel"], false, [], Callable(), {"vision_enabled": true})
		var path: String = "/tmp/paper_front_base_vision_%s.save" % historical
		check(sim.save_game(path).is_empty(), "base sight rule snapshot writes historical=%s" % historical)
		var restored = SIM.new()
		var error: String = restored.load_game(path)
		check(error.is_empty(), "base sight rule snapshot restores historical=%s: %s" % [historical, error])
		if not error.is_empty(): continue
		check(restored.rules == sim.rules, "restoration preserves the match's complete historical sight rules historical=%s" % historical)
		var hq: Dictionary = restored.entities[1]
		check(float(restored.data_for(hq.spec).get("vision_radius", 12.0)) == (12.0 if historical else 28.0), "new matches use enlarged sight while legacy snapshots remain authoritative historical=%s" % historical)
