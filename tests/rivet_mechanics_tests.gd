extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
const Catalog = preload("res://scripts/contextual_production.gd")
var checks: int = 0
var failures: Array[String] = []
var config: Dictionary

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func fixture():
	var sim = Sim.new()
	sim.setup(config, "dev", 7, "rivet", false)
	sim.money.assign([100000.0, 100000.0])
	return sim

func _initialize() -> void:
	config = Rules.load_rules()
	production_and_catalog()
	field_buildings()
	local_production()
	unified_base()
	expansion_requires_base()
	base_capture_limits()
	ai_infrastructure()
	ai_base_recovery()
	print("RIVET_MECHANICS ", JSON.stringify({"checks":checks, "failures":failures}))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func production_and_catalog() -> void:
	var sim = fixture()
	var hq: int = 1
	check(Catalog.categories(sim, [hq]) == ["infantry"], "Rivet HQ offers infantry and no construction catalogs")
	check(sim._has_role(0, "barracks"), "Rivet HQ fulfills barracks technology prerequisites at match start")
	for spec in config.units:
		var info: Dictionary = config.units[spec]
		if info.faction != "rivet": continue
		if info.producer == "barracks":
			check(info.armor_class == "infantry" and sim.produce(hq, spec).is_empty(), "HQ accepts initial infantry " + spec)
		else:
			check(not sim.produce(hq, spec).is_empty(), "HQ rejects noninfantry " + spec)
	check(sim.entities[hq].queue.size() >= 3, "HQ can queue many infantry including engineer without another barracks")
	var save: String = "user://rivet_hq_production.save"
	check(sim.save_game(save).is_empty(), "HQ infantry queue saves")
	var restored = Sim.new()
	var error: String = restored.load_game(save)
	check(error.is_empty(), "HQ infantry queue loads: " + error)
	if error.is_empty(): check(restored.entities[hq].queue == sim.entities[hq].queue, "HQ independent infantry queue preserved")
	check(float(config.buildings.rivet_hq.cost) == 1000.0 and config.buildings.rivet_hq.requires.is_empty(), "base barracks is expensive and unlocked from start")
	check(config.buildings.rivet_hq.build_time == 15, "base barracks construction takes fifteen seconds")
	for faction in ["kestrel", "iron", "sky"]: check(float(config.buildings[faction + "_barracks"].cost) < 500.0, "extra Rivet barracks clearly dearer than " + faction)
	var engineer: int = sim._spawn(0, "rivet_engineer", Vector2(22.5, 43.5), true)
	check(Catalog.categories(sim, [engineer]) == ["build", "defense"], "engineer owns both construction catalogs")
	check(Catalog.visible_specs(sim, [engineer], "build").has("rivet_hq"), "engineer can build the same base barracks immediately")
	for spec in config.buildings:
		var info: Dictionary = config.buildings[spec]
		if info.faction != "rivet": continue
		check(sim.TechAvailability.engineer_building(sim, 0, info), "all Rivet structures including base barracks use field construction " + spec)
		check(not sim.build(0, spec).is_empty(), "no remote construction order for " + spec)

func field_buildings() -> void:
	for spec in ["rivet_power", "rivet_hq", "rivet_wall", "rivet_barricade"]:
		var sim = fixture()
		var info: Dictionary = config.buildings[spec]
		var half: float = float(info.size) * .5
		var pos: Vector2 = Vector2(roundf(24.5 - half) + half, roundf(43.5 - half) + half)
		var engineer: int = sim._spawn(0, "rivet_engineer", pos + Vector2(half + .5, 0), true)
		var before: float = sim.money[0]
		check(sim.build(0, spec, engineer).is_empty(), spec + " accepts engineer selection")
		var channel: String = sim.construction_channel(spec)
		check(sim.order_for_team(0, channel).ready and is_equal_approx(sim.money[0], before), spec + " selects freely with no preparation timer")
		var error: String = sim.place_building(0, pos, channel)
		check(error.is_empty(), spec + " site placement: " + error)
		if not error.is_empty(): continue
		sim._step_deploy_outpost(sim.entities[engineer], sim.entities[engineer].commands[0], .1)
		var building: int = sim._next_id - 1
		check(sim.entities[building].has("construction") and sim.entities[building].spec == spec, spec + " becomes scaffold only on engineer arrival")
		if not sim.entities[building].has("construction"): continue
		sim.Construction.step(sim, sim.entities[building], 1.0)
		check(is_equal_approx(before - sim.money[0], float(info.cost) / float(info.build_time)), spec + " work uses unchanged configured cost/time")
		var progress: float = sim.entities[building].construction.progress
		sim.issue([engineer], "stop", sim.entities[engineer].pos)
		sim.Construction.step(sim, sim.entities[building], 2.0)
		check(is_equal_approx(progress, float(sim.entities[building].construction.progress)), spec + " pauses without working engineer")
		var replacement: int = sim._spawn(0, "rivet_engineer", pos + Vector2(-half - .5, 0), true)
		check(sim.resume_outpost_error(replacement, building).is_empty(), spec + " another engineer can resume")
		sim.issue([replacement], "resume_outpost", pos, building)
		sim._step_resume_outpost(sim.entities[replacement], sim.entities[replacement].commands[0], .1)
		var path: String = "user://rivet_scaffold.save"
		check(sim.save_game(path).is_empty(), spec + " scaffold saves")
		var restored = Sim.new()
		var load_error: String = restored.load_game(path)
		check(load_error.is_empty(), spec + " scaffold loads: " + load_error)
		if load_error.is_empty(): check(restored.entities[building].construction == sim.entities[building].construction, spec + " preserves paid progress and builder")
		sim.Construction.step(sim, sim.entities[building], float(info.build_time))
		check(not sim.entities[building].has("construction") and is_equal_approx(before - sim.money[0], float(info.cost)), spec + " finishes at exact original price")
		check(sim.entities.has(replacement), spec + " construction preserves its engineer")
		if spec == "rivet_hq":
			check(sim.entities[1].spec == sim.entities[building].spec and sim.entities[1].hp == sim.entities[building].hp and sim.data_for(sim.entities[1].spec) == sim.data_for(sim.entities[building].spec), "a field-built base uses the same blueprint and completed health as the initial base")
			check(sim.produce(building, "rivet_rifle").is_empty(), "a field-built base trains infantry immediately upon completion")

func local_production() -> void:
	var sim = fixture()
	var hq: Dictionary = sim.entities[1]
	var close: int = sim._spawn(0, "rivet_factory", hq.pos + Vector2(6, 0), true)
	var remote: int = sim._spawn(0, "rivet_factory", Vector2(54.5, 43.5), true)
	check(sim.produce(1, "rivet_rifle").is_empty() and sim.produce(close, "rivet_tank").is_empty() and sim.produce(remote, "rivet_tank").is_empty(), "local production test queues all three facilities")
	sim.step(1.0)
	var total: float = float(config.units.rivet_rifle.build_time)
	check(is_equal_approx(float(hq.queue[0].remaining), total - 1.0), "HQ infantry retains full speed during remote grid shortage")
	check(is_equal_approx(float(sim.entities[close].queue[0].remaining), float(config.units.rivet_tank.build_time) - 1.0), "locally supplied factory retains full production speed")
	check(is_equal_approx(float(sim.entities[remote].queue[0].remaining), float(config.units.rivet_tank.build_time) - .5), "remote factory cannot consume HQ local supply")

func unified_base() -> void:
	var sim = fixture()
	check(not config.buildings.has("rivet_outpost") and not config.buildings.has("rivet_barracks"), "Rivet has one base blueprint and no separate outpost or barracks")
	check(config.buildings.rivet_hq.name == "基地兵营" and config.buildings.rivet_hq.formal_name == "基地兵营", "the unified base is named 基地兵营")
	var initial: Dictionary = sim.entities[1]
	var base: int = sim._spawn(0, "rivet_hq", Vector2(24, 44), true)
	var built: Dictionary = sim.entities[base]
	check(initial.spec == built.spec and sim.data_for(initial.spec) == sim.data_for(built.spec), "initial and additional bases use the exact same blueprint")
	check(initial.hp == built.hp and initial.hp == 3500.0 and config.buildings.rivet_hq.vision_radius == 28 and config.buildings.rivet_hq.size == 4, "initial and additional bases have identical health, footprint and vision")
	check(sim.construction_radius(initial.spec) == 24.0 and sim.construction_radius(built.spec) == 24.0, "all base barracks have the same twenty-four-cell construction range")
	check(sim.produce(1, "rivet_rifle").is_empty() and sim.produce(base, "rivet_engineer").is_empty(), "both instances train infantry through independent queues")
	check(sim.entities[1].queue.size() == 1 and sim.entities[base].queue.size() == 1, "adding a base does not merge its production queue with the initial base")
	sim._kill_entity(1, false)
	sim._check_result()
	check(sim.result.is_empty() and sim._has_role(0, "hq"), "another instance preserves base authority after the initial base is lost")
	var engineer: int = sim._spawn(0, "rivet_engineer", Vector2(27, 44), true)
	check(sim.build(0, "rivet_power", engineer).is_empty(), "expansion barracks unlocks engineer construction of power plants")
	sim.cancel_build(0)
	check(sim.produce(base, "rivet_engineer").is_empty(), "expansion barracks trains replacement engineers")
	check(float(config.buildings.rivet_hq.get("local_power", 0)) == 100.0 and float(config.buildings.rivet_hq.local_power_radius) == 12.0, "every base barracks supplies one hundred local power over twelve cells")
	check(sim.build(0, "rivet_hq", engineer).is_empty(), "an engineer can order another base while an existing base survives")
	sim.cancel_build(0)
	sim._kill_entity(base, false)
	check(sim.build(0, "rivet_hq", engineer).is_empty(), "a surviving engineer can rebuild the same base after all bases are destroyed")

func expansion_requires_base() -> void:
	var sim = fixture()
	var engineer: int = sim._spawn(0, "rivet_engineer", Vector2(42, 44), true)
	var site: Vector2 = Vector2.INF
	for z in range(8, 60, 2):
		for x in range(36, 80, 2):
			var wanted := Vector2(x, z)
			if not sim.in_construction_range(0, wanted) and sim._building_site_error(0, config.buildings.rivet_hq, wanted, engineer).is_empty(): site = wanted; break
		if site.is_finite(): break
	check(site.is_finite(), "remote expansion barracks has legal dry site")
	if not site.is_finite(): return
	var ordinary: Vector2 = Vector2.INF
	var geometry_only: Dictionary = config.buildings.rivet_power.duplicate()
	geometry_only.role = "hq" # Validate dry geometry separately from base authority.
	geometry_only.rebuildable = true
	for offset in [Vector2(6.5,.5),Vector2(-6.5,.5),Vector2(.5,6.5),Vector2(.5,-6.5)]:
		var candidate: Vector2 = site + offset
		if not sim.in_construction_range(0, candidate) and sim._building_site_error(0, geometry_only, candidate, engineer).is_empty(): ordinary = candidate; break
	check(ordinary.is_finite(), "ordinary remote site has independently valid geometry")
	if not ordinary.is_finite(): return
	check(sim._building_site_error(0, config.buildings.rivet_power, ordinary, engineer).contains("兵营"), "engineering cannot expand by placing a remote ordinary structure")
	var base: int = sim._spawn(0, "rivet_hq", site, false)
	sim.Construction.initialize(sim, sim.entities[base], engineer)
	check(not sim.in_construction_range(0, ordinary), "unfinished expansion barracks provides no construction authority")
	sim.Construction._complete(sim, sim.entities[base])
	check(sim.in_construction_range(0, ordinary), "completed expansion barracks authorizes nearby construction")
	check(sim.construction_radius("rivet_hq") == 24.0 and sim.construction_radius("rivet_factory") == 0.0, "only completed base barracks expands Rivet base")

func base_capture_limits() -> void:
	var sim = fixture()
	var enemy: int = sim._spawn(1, "rivet_hq", Vector2(30, 44), true)
	var engineer: int = sim._spawn(0, "rivet_engineer", Vector2(27, 44), true)
	check(sim.capture_error(engineer, enemy).is_empty(), "a repeatable base can be captured while the capturer already owns a base")
	sim.issue([engineer], "capture", sim.entities[enemy].pos, enemy)
	sim._step_capture(sim.entities[engineer], sim.entities[engineer].commands[0], .1)
	check(sim.entities[1].team == 0 and sim.entities[enemy].team == 0 and sim.entities[enemy].spec == "rivet_hq", "capture adds a second identical base without replacing the initial base")
	check(sim.produce(enemy, "rivet_engineer").is_empty(), "a captured base keeps its infantry producer alias")
	var path: String = "user://rivet_multiple_bases.save"
	var restored = Sim.new()
	var save_error: String = sim.save_game(path)
	var load_error: String = restored.load_game(path)
	check(save_error.is_empty() and load_error.is_empty(), "multiple identical bases round-trip through save/load: " + load_error)
	if load_error.is_empty():
		check(restored.entities[1].spec == "rivet_hq" and restored.entities[enemy].spec == "rivet_hq" and restored.entities[1].team == restored.entities[enemy].team, "save/load preserves both instances of the same base blueprint")
		check(restored.entities[enemy].queue == sim.entities[enemy].queue, "save/load preserves the captured base's independent production queue")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var classic = Sim.new()
	classic.setup_multiteam(config, "dev", 7, ["kestrel", "kestrel"], false)
	var classic_engineer: int = classic._spawn(0, "kestrel_engineer", classic.entities[2].pos + Vector2(-3, 0), true)
	check(not classic.build(0, "kestrel_hq", classic_engineer).is_empty(), "conventional headquarters remain unavailable for reconstruction")
	check(not classic.capture_error(classic_engineer, 2).is_empty(), "a conventional headquarters still occupies the single headquarters slot")

func ai_infrastructure() -> void:
	var sim = Sim.new()
	sim.setup(config, "dev", 7, "kestrel", true)
	sim.money.assign([100000.0, 100000.0])
	for _tick in range(150): sim.step(1.0)
	check(sim._has_role(1, "power") and sim._has_role(1, "refinery"), "legacy Rivet AI trains engineer and builds its industrial chain")
	check(sim._unit_spec_count(1, "rivet_engineer") > 0, "legacy Rivet AI obtains builders from initial HQ")
	var modern = Sim.new()
	var opts: Dictionary = {"players":2,"slots":[{"faction":"kestrel","control":"human","difficulty":"normal"},{"faction":"rivet","control":"ai","difficulty":"hard"}]}
	modern.setup_multiteam(config, "dev", 7, ["kestrel", "rivet"], true, [], Callable(), opts)
	modern.money.assign([100000.0,100000.0])
	modern.entities[1].hp = 1000000.0 # Isolate industrial planning from victory termination.
	modern.match_options.modern = true
	modern.AIController.initialize(modern)
	for _tick in range(210): modern.step(1.0)
	check(modern._has_role(1, "power") and modern._has_role(1, "refinery") and modern._has_role(1, "factory"), "modern Rivet AI builds ordinary industrial chain through engineers")

func ai_base_recovery() -> void:
	var sim = Sim.new()
	var opts: Dictionary = {"players":2,"modern":true,"slots":[{"faction":"kestrel","control":"human","difficulty":"normal"},{"faction":"rivet","control":"ai","difficulty":"hard"}]}
	sim.setup_multiteam(config, "dev", 7, ["kestrel", "rivet"], true, [Vector2(8, 8), Vector2(38, 36)], Callable(), opts)
	# A flat, resource-free battlefield isolates ordinary AI purchases and work.
	for z in range(sim.map.size):
		for x in range(sim.map.size):
			sim.map.terrain[z][x] = 0
			sim.map.heights[z][x] = 0.0
	sim.mines.clear()
	sim.bridges.clear()
	sim.ruins.clear()
	sim.map.ruins = []
	sim._refresh_ruin_spatial()
	sim._prepare_terrain_cache()
	sim._nav_dirty = true
	sim.entities[1].hp = 1000000.0
	var factory: int = sim._spawn(1, "rivet_factory", Vector2(30, 36), true)
	var engineer: int = sim._spawn(1, "rivet_engineer", Vector2(38, 36), true)
	sim._kill_entity(2, false)
	sim.money.assign([0.0, 1200.0])
	check(not sim._has_construction_base(1) and sim.entities[engineer].commands.is_empty(), "AI recovery begins with no base, one idle engineer and a surviving factory")
	var rebuilt: int = -1
	var factory_spent_first: bool = false
	var negative_funds: bool = false
	for _tick in range(900):
		sim.step(.1)
		negative_funds = negative_funds or float(sim.money[1]) < 0.0
		if rebuilt < 0 and not sim.entities[factory].queue.is_empty(): factory_spent_first = true
		for entity: Dictionary in sim._building_entities:
			if entity.team == 1 and entity.spec == "rivet_hq" and not entity.has("construction") and float(entity.construct_remaining) <= 0.0: rebuilt = int(entity.id); break
		if rebuilt > 0: break
	check(rebuilt > 0, "modern AI rebuilds the canonical base barracks using ordinary ticks and its surviving engineer")
	if rebuilt < 0:
		print("AI_BASE_RECOVERY_STATE ", JSON.stringify({"money":sim.money[1], "result":sim.result, "time":sim.time, "orders":sim.building_orders[1], "engineer":sim.entities.get(engineer, {}), "factory":sim.entities.get(factory, {})}))
	check(not factory_spent_first, "base rebuilding funds are reserved before surviving factory production spends them")
	var queued_cost: float = 0.0
	for entity: Dictionary in sim._building_entities:
		if entity.team != 1: continue
		for order: Dictionary in entity.queue: queued_cost += float(order.cost)
	check(not negative_funds and is_equal_approx(float(sim.money[1]) + queued_cost, 200.0), "AI recovery pays the full one-thousand base cost from twelve-hundred funds before any subsequent unit orders, without income or gifts")
	if rebuilt > 0: check(sim.entities[rebuilt].spec == "rivet_hq" and sim.entities.has(engineer) and sim._has_role(1, "barracks"), "AI rebuilt base restores the same infantry technology and preserves the builder")
