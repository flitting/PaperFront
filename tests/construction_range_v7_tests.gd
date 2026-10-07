extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
const Construction = preload("res://scripts/building_construction.gd")
const Outpost = preload("res://scripts/outpost_construction.gd")
const Naval = preload("res://scripts/naval_operations.gd")
const Wiki = preload("res://scripts/wiki_catalog.gd")
var config: Dictionary
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	config = Rules.load_rules("res://data/rules.json", false)
	check(not config.is_empty(), "the active role-based range rules validate")
	if not config.is_empty():
		rules_contract()
		all_completed_building_sources()
		large_continuous_area()
		completed_building_extension()
		engineer_remote_deployment()
		outpost_and_owner_lifecycle()
		site_constraints()
		defense_and_naval_authority()
		defense_micro_building_sites()
		ai_placement()
		ai_defense_micro_zone()
		snapshot_compatibility()
		visual_memory_snapshot()
	print("Construction range v7: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	for message: String in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func fresh(rules: Dictionary = {}, flatten: bool = true):
	var sim = Sim.new()
	# Two conventional Kestrel players isolate construction and ownership rules.
	sim.setup_multiteam(config if rules.is_empty() else rules, "dev", 7, ["kestrel", "kestrel"], false, [Vector2(7, 7), Vector2(42, 42)])
	sim.money.assign([100000.0, 100000.0])
	if not flatten: return sim
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
	return sim

func ready(sim, team: int = 0, spec: String = "kestrel_power") -> void:
	var before: float = sim.money[team]
	check(sim.build(team, spec).is_empty(), "a real paid construction order is accepted: " + spec)
	check(is_equal_approx(before - sim.money[team], float(sim.data_for(spec).cost)), "configured construction cost is charged once: " + spec)
	sim.step(float(sim.data_for(spec).build_time) * 2.0 + 0.1)
	check(bool(sim.order_for_team(team, sim.construction_channel(spec)).get("ready", false)), "a real timed construction order becomes ready: " + spec)

func rules_contract() -> void:
	for faction: String in config.factions:
		check(Construction.radius_in_rules(config, config.buildings[faction + "_hq"]) == 24.0, faction + " headquarters has the same large range")
		if faction == "rivet":
			check(not config.buildings.has("rivet_outpost") and not config.buildings.has("rivet_barracks"), "Rivet expands through its one base barracks blueprint")
			check(Construction.radius_in_rules(config, config.buildings.rivet_hq) == 24.0, "every Rivet base barracks has the same range")
		else:
			check(Construction.radius_in_rules(config, config.buildings[faction + "_outpost"]) == 20.0, faction + " outpost has the same large range")
		for spec: Dictionary in config.buildings.values():
			if spec.faction != faction: continue
			if str(spec.role) not in ["hq", "outpost"]:
				var expected: float = 3.0 if str(spec.role) in ["wall", "barricade"] else 6.0
				if faction == "rivet": expected = 0.0
				check(Construction.radius_in_rules(config, spec) == expected, faction + " completed " + str(spec.role) + " provides the configured small extension")
	for value: Variant in [-1, "wide", INF]:
		var invalid: Dictionary = config.duplicate(true)
		invalid.economy.construction_radii.hq = value
		check(not Rules.validate(invalid, false).is_empty(), "invalid range values are rejected: " + str(value))
	var missing: Dictionary = config.duplicate(true)
	missing.economy.construction_radii.erase("default")
	check(not Rules.validate(missing, false).is_empty(), "range tables need a validated default")
	missing = config.duplicate(true)
	missing.economy.construction_radii["unknown"] = 8
	check(not Rules.validate(missing, false).is_empty(), "unknown construction roles are rejected")
	for spec: String in ["kestrel_hq", "kestrel_outpost", "kestrel_power", "kestrel_tower", "kestrel_wall"]:
		var displayed: String = ""
		for section: Dictionary in Wiki.sections(config, spec):
			for row: Dictionary in section.rows:
				if row.label == "扩建半径": displayed = str(row.value)
		check(displayed == "%d 格" % int(Construction.radius_in_rules(config, config.buildings[spec])), "wiki range matches simulation rules: " + spec)

func all_completed_building_sources() -> void:
	var sim = fresh()
	for spec: String in config.buildings:
		var id: int = sim.debug_spawn(0, spec, Vector2(34.5, 7.5))
		var point: Vector2 = sim.entities[id].pos + Vector2(1, 0)
		var provides_range: bool = sim.construction_radius(spec) > 0.0
		check(sim.in_construction_range(0, point) == provides_range, "completed buildings grant only their configured construction range: " + spec)
		check(sim.construction_zones(0).any(func(zone): return int(zone.id) == id and float(zone.radius) > 0.0) == provides_range, "visible construction zones match each building's rules: " + spec)
		sim.entities[id].construct_remaining = 1.0
		check(not sim.in_construction_range(0, point), "every unfinished building is excluded from authority: " + spec)
		sim.entities[id].construct_remaining = 0.0
		sim.entities[id].team = 1
		check(not sim.in_construction_range(0, point), "every hostile building is excluded from owned authority: " + spec)
		sim.entities[id].team = 0
		sim.entities[id].hp = 0.0
		check(not sim.in_construction_range(0, point), "every destroyed building is excluded from authority: " + spec)
		sim._kill_entity(id, false)

func large_continuous_area() -> void:
	var sim = fresh()
	ready(sim)
	for y in range(8, 18):
		for x in range(14, 28):
			check(sim.placement_error(0, Vector2(x + 0.5, y + 0.5)).is_empty(), "continuous headquarters build area includes %d,%d" % [x, y])
	check(sim.in_construction_range(0, Vector2(31, 7)), "the headquarters circle includes its exact 24-cell boundary")
	check(not sim.in_construction_range(0, Vector2(31.01, 7)), "the headquarters circle rejects points beyond its boundary")
	check(sim.placement_error(0, Vector2(31.5, 7.5)).contains("扩建范围"), "real placement rejects a clear site outside all owned zones")
	check(not sim.in_construction_range(0, Vector2(38.5, 38.5)) and sim.in_construction_range(1, Vector2(38.5, 38.5)), "enemy headquarters never authorizes player construction")
	check(sim.construction_zones(0).size() == 1 and sim.construction_zones(0)[0].radius == 24.0, "the visible zone API exposes exactly the owned completed headquarters")
	check(sim.construction_radius("kestrel_rifle") == 0.0, "units never provide building zones")

func completed_building_extension() -> void:
	var sim = fresh()
	ready(sim)
	var first := Vector2(30.5, 7.5)
	var extension := Vector2(35.5, 7.5)
	var funds: float = sim.money[0]
	check(sim.place_building(0, first).is_empty() and sim.money[0] == funds, "headquarters-edge placement preserves the normal prepaid building price")
	var id: int = sim._next_id - 1
	check(sim.entities[id].construct_remaining > 0.0 and not sim.in_construction_range(0, extension), "a newly placed ordinary building occupies land without extending before completion")
	sim.step(float(config.economy.construction_animation) + 0.1)
	check(sim.entities[id].construct_remaining == 0.0 and sim.in_construction_range(0, extension), "finishing an ordinary power station extends the real range beyond the headquarters")
	ready(sim)
	check(sim.placement_error(0, extension).is_empty() and sim.place_building(0, extension).is_empty(), "a second paid building can actually be placed in the completed facility's extension")
	check(not sim.in_construction_range(0, first + Vector2(6.01, 0)), "the six-cell extension remains bounded while the second building is unfinished")

func outpost_and_owner_lifecycle() -> void:
	var sim = fresh()
	var outpost: int = sim._spawn(0, "kestrel_outpost", Vector2(29.5, 35.5), false)
	Outpost.initialize(sim, sim.entities[outpost], -1)
	var site := Vector2(11.5, 35.5)
	check(not sim.in_construction_range(0, site), "an engineer scaffold does not authorize remote ordinary construction")
	sim.entities[outpost].construct_remaining = 0.0
	check(not sim.in_construction_range(0, site), "an unpaid scaffold never authorizes construction even when its animation timer is zero")
	Outpost._complete(sim, sim.entities[outpost])
	check(sim.in_construction_range(0, site), "only completed field construction grants the full outpost range")
	ready(sim)
	check(sim.placement_error(0, site).is_empty(), "ordinary buildings can really be placed around the completed outpost")
	sim._kill_entity(outpost, false)
	check(not sim.in_construction_range(0, site), "destroying the outpost immediately removes its range")
	var hostile: int = sim.debug_spawn(1, "kestrel_power", Vector2(35.5, 7.5))
	var target := Vector2(39.5, 7.5)
	check(not sim.in_construction_range(0, target), "a hostile ordinary facility grants no owned range")
	var engineer: int = sim.debug_spawn(0, "kestrel_engineer", Vector2(33.3, 7.5))
	sim.issue([engineer], "capture", sim.entities[hostile].pos, hostile)
	sim.step(0.1)
	check(sim.entities[hostile].team == 0 and sim.in_construction_range(0, target), "real engineer capture transfers the completed facility's construction zone to its new owner")
	sim.entities[hostile].hp = 0.0
	check(not sim.in_construction_range(0, target), "a destroyed facility provides no residual range")

func engineer_remote_deployment() -> void:
	var sim = fresh()
	sim.debug_spawn(0, "kestrel_power", Vector2(11.5, 7.5))
	var site := Vector2(29.5, 35.5)
	var nearby := Vector2(11.5, 35.5)
	var builder: int = sim.debug_spawn(0, "kestrel_engineer", Vector2(25.2, 35.5))
	var before: float = sim.money[0]
	check(not sim.in_construction_range(0, site), "real engineer deployment fixture lies beyond every current headquarters and ordinary zone")
	check(sim.build(0, "kestrel_outpost", builder).is_empty() and sim.money[0] == before, "remote outpost site selection keeps the existing engineer-only, no-prepayment rule")
	check(sim.placement_error(0, site).is_empty() and sim.place_building(0, site).is_empty(), "a real engineer can still select legal land beyond the enlarged headquarters range")
	var entity_count: int = sim.entities.size()
	sim.step(0.1)
	check(sim.entities.size() == entity_count and sim.money[0] == before, "remote site selection sends the engineer to travel without remotely creating or paying a scaffold")
	var outpost: int = -1
	for tick in range(180):
		sim.step(1.0 / 30.0)
		for entity: Dictionary in sim.entities.values():
			if entity.kind == "building" and entity.spec == "kestrel_outpost": outpost = int(entity.id)
		if outpost > 0: break
	check(outpost > 0, "the engineer physically arrives and creates its scaffold")
	if outpost < 0: return
	check(sim.entities[outpost].has("construction") and not sim.in_construction_range(0, nearby), "a real engineer-created scaffold has no remote build authority")
	sim.step(float(config.buildings.kestrel_outpost.build_time) + 0.1)
	check(not sim.entities[outpost].has("construction") and sim.in_construction_range(0, nearby), "the engineer's completed work grants a large continuous remote outpost zone")
	check(is_equal_approx(before - sim.money[0], float(config.buildings.kestrel_outpost.cost)) and sim.entities.has(builder), "real remote field construction charges exactly the configured cost and preserves its engineer")

func site_constraints() -> void:
	var sim = fresh()
	check(not sim.build(0, "kestrel_factory").is_empty(), "large headquarters ranges do not bypass facility prerequisites")
	ready(sim)
	var site := Vector2(17.5, 8.5)
	check(sim.placement_error(0, site).is_empty(), "constraint fixture has a clear authorized land site")
	sim.map.terrain[8][16] = MapData.WATER
	check(sim.placement_error(0, site).contains("水面"), "the whole land footprint still rejects one water cell")
	sim.map.terrain[8][16] = 0
	sim.map.heights[8][17] = 2.0
	check(sim.placement_error(0, site).contains("平坦"), "the footprint still rejects mixed elevations")
	sim.map.heights[8][17] = 0.0
	check(sim.placement_error(0, Vector2(0.5, 8.5)).contains("边界"), "buildable range does not bypass map boundaries")
	check(sim.placement_error(0, Vector2(7.5, 7.5)).contains("重叠"), "headquarters footprint remains solid occupancy")
	sim.mines.append({"pos": site})
	check(sim.placement_error(0, site).contains("矿点"), "range does not authorize covering a mine")
	sim.mines.clear()
	var unit: int = sim.debug_spawn(0, "kestrel_engineer", site)
	check(unit > 0 and sim.placement_error(0, site).contains("单位"), "ground unit occupancy still blocks placement")

func defense_and_naval_authority() -> void:
	var sim = fresh()
	var wall: int = sim.debug_spawn(0, "kestrel_wall", Vector2(34.5, 7.5))
	check(sim.construction_radius("kestrel_wall") == 3.0 and sim.construction_radius("kestrel_barricade") == 3.0, "completed wall and barricade lines provide a bounded three-cell ordinary construction micro zone")
	check(sim.in_construction_range(0, Vector2(36.5, 7.5)), "a completed remote wall provides a small ordinary build zone")
	ready(sim, 0, "kestrel_wall")
	var funds: float = sim.money[0]
	check(sim.defense_extension(0, Vector2(40.5, 7.5)).size() == 6, "existing straight six-cell wall extension is preserved")
	check(sim.place_building(0, Vector2(40.5, 7.5)).is_empty(), "a legal paid remote defensive extension still places")
	check(is_equal_approx(funds - sim.money[0], float(config.buildings.kestrel_wall.cost) * 5.0), "the extra five defense cells are charged individually")
	sim.step(float(config.economy.construction_animation) + 0.1)
	check(sim.in_construction_range(0, Vector2(40.5, 9.5)), "finished extended walls provide their configured ordinary construction micro zones")
	check(not sim.in_construction_range(0, Vector2(40.5, 11.0)), "finished paid defense segments do not authorize sites beyond the three-cell micro zone")
	check(sim.entities.has(wall), "defensive extension preserves its existing source wall")
	var naval = fresh()
	var point := Vector2(35.5, 7.5)
	check(not Naval._yard_authorized(naval, 0, point, 2.0, true, -1), "open water outside owned zones has no shipyard authority")
	var facility: int = naval.debug_spawn(0, "kestrel_power", Vector2(30.5, 7.5))
	check(Naval._yard_authorized(naval, 0, point, 2.0, true, -1), "shipyard authority uses the same completed ordinary facility zones")
	naval.entities[facility].construct_remaining = 1.0
	check(not Naval._yard_authorized(naval, 0, point, 2.0, true, -1), "unfinished facilities cannot authorize naval placement")
	naval.map.harbors = [{"team": 0, "role": "home", "protected": true, "shore_pos": point, "radius": 10.0}]
	check(Naval._yard_authorized(naval, 0, point, 2.0, true, -1), "the protected owned home harbor retains its historical authorization")
	naval.map.harbors[0].team = 1
	check(not Naval._yard_authorized(naval, 0, point, 2.0, true, -1), "an enemy protected harbor never authorizes player construction")

func defense_micro_building_sites() -> void:
	for role: String in ["wall", "barricade"]:
		var sim = fresh()
		var center := Vector2(34.5, 7.5)
		var point := center + Vector2(2, 0)
		var source: int = sim.debug_spawn(0, "kestrel_" + role, center)
		ready(sim)
		check(sim.entities[1].pos.distance_to(point) > sim.construction_radius("kestrel_hq"), "the actual " + role + " micro-zone site is outside headquarters authority")
		check(sim.placement_error(0, point).is_empty(), "a completed owned " + role + " really authorizes normal building placement nearby")
		check(sim.placement_error(0, center + Vector2(3.5, 0)).contains("扩建范围"), "ordinary building placement stays inside the " + role + " micro zone")
		sim.entities[source].construct_remaining = 1.0
		check(sim.placement_error(0, point).contains("扩建范围"), "an unfinished " + role + " cannot authorize the same normal site")
		sim.entities[source].construct_remaining = 0.0
		sim.entities[source].team = 1
		check(sim.placement_error(0, point).contains("扩建范围"), "an enemy " + role + " cannot authorize the same normal site")
		sim.entities[source].team = 0
		var funds: float = sim.money[0]
		check(sim.place_building(0, point).is_empty() and sim.entities[sim._next_id - 1].spec == "kestrel_power", "a real paid ordinary power station can be placed using only an owned " + role + " micro zone")
		check(sim.money[0] == funds, "ordinary placement near a " + role + " retains its configured prepaid cost")

func ai_placement() -> void:
	var sim = fresh()
	var facility: int = sim.debug_spawn(1, "kestrel_power", Vector2(32.5, 8.5))
	ready(sim, 1, "kestrel_power")
	for z in range(sim.map.size):
		for x in range(sim.map.size): sim.map.terrain[z][x] = 4
	for z in range(7, 10):
		for x in range(31, 34): sim.map.terrain[z][x] = 0
	for z in range(9, 12):
		for x in range(36, 39): sim.map.terrain[z][x] = 0
	var before: int = sim.entities.size()
	var funds: float = sim.money[1]
	sim._ai_place(1)
	check(sim.entities.size() == before + 1 and sim.building_orders[1].is_empty(), "AI can really place using an ordinary completed facility outside all headquarters zones")
	if sim.entities.size() == before + 1:
		var placed: Dictionary = sim.entities[sim._next_id - 1]
		check((placed.pos as Vector2).distance_to(sim.entities[2].pos) > sim.construction_radius("kestrel_hq") and (placed.pos as Vector2).distance_to(sim.entities[facility].pos) <= sim.construction_radius("kestrel_power"), "AI's actual site obeys the same six-cell construction authority as the player")
	check(sim.money[1] == funds, "AI placement retains the same normal prepaid cost")

func ai_defense_micro_zone() -> void:
	for role: String in ["wall", "barricade"]:
		var sim = fresh()
		var source: int = sim.debug_spawn(1, "kestrel_" + role, Vector2(32.5, 8.5))
		ready(sim, 1, "kestrel_power")
		for z in range(sim.map.size):
			for x in range(sim.map.size): sim.map.terrain[z][x] = 4
		sim.map.terrain[8][32] = 0
		for z in range(8, 11):
			for x in range(33, 36): sim.map.terrain[z][x] = 0
		var before: int = sim.entities.size()
		var funds: float = sim.money[1]
		sim._ai_place(1)
		check(sim.entities.size() == before + 1 and sim.building_orders[1].is_empty(), "AI can really place a normal facility using only an owned " + role + " micro zone")
		if sim.entities.size() == before + 1:
			var placed: Dictionary = sim.entities[sim._next_id - 1]
			check((placed.pos as Vector2).distance_to(sim.entities[2].pos) > sim.construction_radius("kestrel_hq") and (placed.pos as Vector2).distance_to(sim.entities[source].pos) <= 3.0, "AI's actual " + role + " micro-zone placement obeys the same three-cell authority")
		check(sim.money[1] == funds, "AI ordinary placement through a " + role + " micro zone retains normal cost")

func snapshot_compatibility() -> void:
	for legacy: bool in [false, true]:
		var rules: Dictionary = config.duplicate(true)
		if legacy: rules.economy.erase("construction_radii")
		else: rules.economy.construction_radii.hq = 26.0
		check(Rules.validate(rules, false).is_empty(), "custom new and historical range rules both validate: legacy=" + str(legacy))
		var sim = fresh(rules, false)
		sim.debug_spawn(0, "kestrel_power", Vector2(30.5, 7.5))
		var path: String = "/tmp/paper_front_v7_range_" + str(legacy) + ".save"
		check(sim.save_game(path).is_empty(), "a real range snapshot writes: legacy=" + str(legacy))
		var restored = Sim.new()
		var error: String = restored.load_game(path)
		check(error.is_empty(), "a real range snapshot loads: legacy=" + str(legacy) + " " + error)
		if error.is_empty():
			check(restored.rules == rules and restored.construction_zones(0) == sim.construction_zones(0), "saved rule snapshots and derived zones survive load exactly: legacy=" + str(legacy))
			check(restored.construction_radius("kestrel_hq") == (12.0 if legacy else 26.0) and restored.construction_radius("kestrel_power") == (0.0 if legacy else 6.0), "loading never silently replaces old or customized range rules with installed defaults")
			check(restored.construction_radius("kestrel_wall") == (0.0 if legacy else 3.0) and restored.construction_radius("kestrel_barricade") == (0.0 if legacy else 3.0), "new defensive micro zones round-trip while old snapshots retain their historical defense authority")
			check(restored.in_construction_range(0, Vector2(35.5, 7.5)) == (not legacy), "historical expands=false power stations retain their original placement authority")
		DirAccess.remove_absolute(path)

func visual_memory_snapshot() -> void:
	var sim = fresh({}, false)
	var memory: Dictionary = {"schema": 1, "explored_terrain": {"cells": PackedByteArray([0, 1, 1, 0])}}
	var before: Dictionary = memory.duplicate(true)
	var path: String = "/tmp/paper_front_v7_visual_memory.save"
	check(sim.save_game(path, memory).is_empty(), "a save may carry optional terrain exploration metadata")
	memory.explored_terrain.cells[0] = 1
	var restored = Sim.new()
	check(restored.load_game(path).is_empty() and restored.visual_memory == before, "optional visual metadata survives save/load without caller aliasing")
	check(restored.rules == sim.rules and restored.team_vision == sim.team_vision and restored.construction_zones(0) == sim.construction_zones(0), "visual metadata has no authority over rules, gameplay visibility or construction")
	check(sim.save_game(path).is_empty() and restored.load_game(path).is_empty() and restored.visual_memory.is_empty(), "old calls and snapshots without visual metadata load with empty exploration")
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var malformed: Dictionary = file.get_var(false)
	file.close()
	malformed.visual_memory = "invalid optional metadata"
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_var(malformed, false)
	file.close()
	check(restored.load_game(path).is_empty() and restored.visual_memory.is_empty(), "unrecognized optional visual metadata is ignored without invalidating an otherwise valid historical save")
	restored.visual_memory = before
	restored.setup(config, "dev", 7, "kestrel", false)
	check(restored.visual_memory.is_empty(), "a new match resets restored exploration metadata")
	DirAccess.remove_absolute(path)
