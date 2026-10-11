extends SceneTree

## Short, deterministic checks of the live combat rules. Only map geometry and
## pre-deployed rosters are fixtures; HP, damage, armor and production use the
## production WarSimulation. This is not an AI win-rate experiment.
const Simulation = preload("res://scripts/simulation.gd")
const Loader = preload("res://scripts/rules_loader.gd")
const Combat = preload("res://scripts/armor_combat.gd")
const FACTIONS: Array[String] = ["kestrel", "rivet", "iron", "sky"]
const BEFORE_PATH := "res://tests/fixtures/armor_balance_revision_before.json"
const DT := 1.0 / 30.0
const BUILDING_ARMOR := {
	"hq": 40, "factory": 40, "tower": 80, "wall": 80,
	"barricade": 80, "refinery": 40, "repair": 40, "tech": 40,
	"power": 40, "barracks": 40, "outpost": 40, "airfield": 40,
	"shipyard": 40, "drill": 40, "rail": 0, "rail_junction": 0,
}

var rules: Dictionary
var before: Dictionary
var checks := 0
var failures: Array[String] = []
var details: Array[Dictionary] = []
var output := "res://artifacts/armor_balance_revision_20261009/regression.json"
var script_mode := false

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)

func fixture(left: String = "kestrel", right: String = "sky"):
	var sim = Simulation.new()
	sim.synchronous_path_tests = true
	sim.map_generation_config = {"legacy_dev48": true}
	if script_mode:
		sim.native_kernels_enabled = false
		sim.native_unit_dispatch_enabled = false
		sim.native_geometry_enabled = false
		sim.native_movement_enabled = false
	var factions: Array[String] = [left, right]
	var starts: Array[Vector2] = []
	sim.setup_multiteam(rules, "dev", 733, factions, false, starts, Callable(), {"vision_enabled": false})
	check(bool(sim.map.get("valid", false)) and sim.entities.size() == 2, "real simulation fixture initializes")
	for id in sim.entities.keys():
		sim._kill_entity(int(id), false)
	for row in sim.map.terrain:
		row.fill(0)
	for row in sim.map.heights:
		row.fill(0.0)
	sim.mines.clear()
	sim.ruins.clear()
	sim.bridges.clear()
	sim._refresh_mine_spatial()
	sim._refresh_ruin_spatial()
	sim._prepare_terrain_cache()
	sim._nav_initialized = false
	sim._rebuild_nav()
	sim._spawn(0, left + "_hq", Vector2(7, 40), true)
	sim._spawn(1, right + "_hq", Vector2(41, 40), true)
	sim.statistics.begin(sim)
	return sim

func close(sim) -> void:
	if sim._path_worker != null:
		sim._path_worker.close()

func veteran(sim, id: int, enabled: bool) -> void:
	var e: Dictionary = sim.entities[id]
	e.veteran = enabled
	e.hp = sim.max_hp(e)
	e.max_hp = sim.max_hp(e)

func shot(sim, source_spec: String, target_spec: String, source_veteran: bool = false, target_veteran: bool = false) -> Dictionary:
	# A single real discharge, fully settled without automatic follow-up fire.
	# This isolates per-hit lethality from reloads, regeneration and movement.
	var source: int = sim._spawn(0, source_spec, Vector2(12, 20), true)
	var target: int = sim._spawn(1, target_spec, Vector2(16, 20), true)
	veteran(sim, source, source_veteran)
	veteran(sim, target, target_veteran)
	var e: Dictionary = sim.entities[source]
	e.alpha = 0.0
	e.turret_alpha = 0.0
	if sim._is_air(e):
		e.airborne = true
		e.flight_state = "flying"
		e.ammo = maxi(1, int(sim.data_for(source_spec).get("ammo_capacity", 1)))
	if str(sim.weapon_for(e).get("trajectory", "")) == "gravity_bomb":
		# A stationary, pre-deployed bomber directly above the target lets the
		# real unguided bomb land at full splash strength. Its separate gun is
		# on cooldown, so this records exactly one primary attack.
		e.pos = sim.entities[target].pos
		e.zeppelin_mg_cooldown = 1000.0
	sim._rebuild_spatial()
	var initial: float = sim.entities[target].hp
	var weapon: Dictionary = sim.weapon_for(e)
	var legal: bool = sim._weapon_can_target(e, target)
	sim._fire(e, target)
	var fired: bool = float(e.cooldown) > 0.0
	sim._step_projectiles(10.0)
	sim.BeamWeapons.step(sim, 10.0)
	if bool(sim.data_for(source_spec).get("hero", false)):
		sim.HeroRules.step(sim, 10.0)
	sim._apply_damage()
	var hp: float = float(sim.entities[target].hp) if sim.entities.has(target) else 0.0
	var result := {"source": source_spec, "target": target_spec, "source_veteran": source_veteran,
		"target_veteran": target_veteran, "initial_hp": initial, "remaining_hp": hp,
		"damage": initial - hp, "legal": legal, "fired": fired,
		"nominal_damage": float(weapon.get("damage", 0)), "penetration": float(weapon.get("penetration", 0))}
	if sim.entities.has(source):
		sim._kill_entity(source, false)
	if sim.entities.has(target):
		sim._kill_entity(target, false)
	return result

func catalog() -> void:
	for spec: String in rules.buildings:
		var b: Dictionary = rules.buildings[spec]
		var role := str(b.role)
		check(BUILDING_ARMOR.has(role), spec + " building role has an explicit armor category")
		var expected: int = 100 if spec.ends_with("_advanced_tower") or spec.ends_with("_anti_tower") else int(BUILDING_ARMOR.get(role, -1))
		check(int(b.armor) == expected, spec + " live armor matches role category")
	for spec: String in before.infantry_armor:
		check(rules.units.has(spec) and float(rules.units[spec].armor) == float(before.infantry_armor[spec]), spec + " infantry armor unchanged")
	for weapon_id: String in before.weapon_blast:
		check(rules.weapons.has(weapon_id) and is_equal_approx(float(rules.weapons[weapon_id].get("blast", 0)), float(before.weapon_blast[weapon_id])), weapon_id + " splash radius unchanged")
	for spec: String in before.tower_cost_time:
		var b: Dictionary = rules.buildings[spec]
		var old: Dictionary = before.tower_cost_time[spec]
		check(is_equal_approx(float(b.cost), ceilf(float(old.cost) * 1.25 / 25.0) * 25.0), spec + " price rises 25% rounded up to 25")
		check(is_equal_approx(float(b.build_time), float(old.build_time) * 1.5), spec + " construction takes 50% longer")
	for faction: String in FACTIONS:
		check(float(rules.weapons[faction + "_tank"].penetration) == 85.0, faction + " ordinary tank penetration remains below heavy armor")
	for spec: String in before.aa_tower_cost_time:
		check(float(rules.buildings[spec].cost) == float(before.aa_tower_cost_time[spec].cost) and float(rules.buildings[spec].build_time) == float(before.aa_tower_cost_time[spec].build_time), spec + " AA price and construction time unchanged")

func penetration_boundaries() -> void:
	var model: Dictionary = rules.combat_model
	check(float(model.partial_penetration_threshold) == 0.8 and float(model.partial_penetration_damage_multiplier) == 0.5, "live model uses 80% threshold and half damage")
	for row: Array in [[79.999, 0.25], [80.0, 0.5], [85.0, 0.5], [100.0, 0.5], [100.001, 1.0]]:
		check(Combat.penetration_factor({"penetration": row[0]}, 100.0, 1.0, model) == row[1], "new model exact P=" + str(row[0]) + " against armor100")
	check(Combat.penetration_factor({"penetration": 100.0}, 100.0, 0.8, model) == 0.5, "splash penetration falloff reaches inclusive 80% band")
	check(Combat.penetration_factor({"penetration": 100.0}, 100.0, 0.799, model) == 0.25, "splash penetration below 80% remains quarter damage")
	for penetration: float in [0.0, 1.0, 85.0]:
		check(Combat.penetration_factor({"penetration": penetration}, 0.0, 1.0, model) == 1.0, "new model armor0 takes full damage with P=" + str(penetration))
	for penetration: float in [80.0, 85.0, 100.0]:
		check(Combat.penetration_factor({"penetration": penetration}, 100.0) == 0.25, "legacy default preserves quarter damage for P=" + str(penetration))
	check(Combat.penetration_factor({"penetration": 100.001}, 100.0) == 1.0, "legacy strictly greater penetration is full")
	check(Combat.penetration_factor({"penetration": 0.0}, 0.0) == 0.25, "legacy zero penetration versus zero armor retains old quarter damage")
	check(Combat.penetration_factor({}, 100.0, 1.0, model) == 1.0, "historical weapons without penetration retain original full damage")

func marksman_cross_faction_hits() -> void:
	for source: String in ["kestrel_marksman", "iron_marksman"]:
		for target: String in ["kestrel_marksman", "iron_marksman"]:
			var sim = fixture(str(rules.units[source].faction), str(rules.units[target].faction))
			for source_veteran: bool in [false, true]:
				for target_veteran: bool in [false, true]:
					var hit := shot(sim, source, target, source_veteran, target_veteran)
					check(bool(hit.fired) and float(hit.damage) > 0.0 and float(hit.remaining_hp) > 0.0, "%s -> %s single full-health hit survives, veteran=%s/%s" % [source, target, source_veteran, target_veteran])
					details.append(hit)
			close(sim)

func legacy_snapshot() -> void:
	var old: Dictionary = Loader.load_rules("res://tests/fixtures/historical_rules/before_armor_balance_20261009.json", false)
	check(not old.is_empty() and not old.combat_model.has("partial_penetration_threshold"), "actual pre-revision rule snapshot retains two-stage armor model")
	if old.is_empty():
		return
	# Use a real generated map for save validation, rather than the flat arena.
	var sim = Simulation.new()
	sim.synchronous_path_tests = true
	sim.map_generation_config = {"legacy_dev48": true}
	var factions: Array[String] = ["kestrel", "kestrel"]
	var starts: Array[Vector2] = []
	sim.setup_multiteam(old, "dev", 734, factions, false, starts, Callable(), {"vision_enabled": false})
	var source: int = sim._spawn(0, "kestrel_tank", Vector2(14.5, 38.5), true)
	var target: int = sim._spawn(1, "kestrel_advanced_tower", Vector2(18.5, 38.5), true)
	sim._rebuild_spatial()
	sim.entities[source].alpha = 0.0
	sim.entities[source].turret_alpha = 0.0
	sim._fire(sim.entities[source], target)
	check(sim.projectiles.size() == 1, "old rules produce a real in-flight tank shell before save")
	var path := "user://armor_balance_legacy_%d.save" % OS.get_process_id()
	var problem: String = sim.save_game(path)
	check(problem.is_empty(), "old-rule in-flight match saves: " + problem)
	var restored = Simulation.new()
	if problem.is_empty():
		problem = restored.load_game(path)
		check(problem.is_empty(), "old-rule in-flight match restores: " + problem)
		if problem.is_empty():
			check(not restored.rules.combat_model.has("partial_penetration_threshold"), "loading old match does not inject new partial armor fields")
			for state in [sim, restored]:
				state._step_projectiles(1.0)
				state._apply_damage()
			var expected := float(old.buildings.kestrel_advanced_tower.hp) - float(old.weapons.kestrel_tank.damage) * 0.25
			check(is_equal_approx(float(restored.entities[target].hp), expected) and is_equal_approx(float(sim.entities[target].hp), expected), "saved old tank85 versus tower90 still applies exact quarter damage")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	close(sim)
	close(restored)

func tank_armor_hits() -> void:
	for faction: String in FACTIONS:
		for target_faction: String in FACTIONS:
			var sim = fixture(faction, target_faction)
			for role: String in ["tank", "heavy_tank"]:
				var source := faction + "_" + role
				for building_role: String in ["hq", "tower", "advanced_tower", "factory", "refinery"]:
					var target := target_faction + "_" + building_role
					if not rules.buildings.has(target):
						target = target_faction + "_drill"
					check(rules.buildings.has(target), "actual faction target building exists: " + target)
					if not rules.buildings.has(target):
						continue
					var hit := shot(sim, source, target)
					var weapon: Dictionary = rules.weapons[rules.units[source].weapon]
					var factor := 0.5 if role == "tank" and building_role == "advanced_tower" else 1.0
					var expected := float(weapon.damage) * float(weapon.get("multipliers", {}).get("building", 1.0)) * factor
					check(bool(hit.fired) and is_equal_approx(float(hit.damage), expected), source + " actual building hit has factor " + str(factor) + " versus " + target + ": " + str(hit.damage))
					check(Combat.penetration_factor(weapon, float(rules.buildings[target].armor), 1.0, rules.combat_model) == factor, source + " armor band matches " + target)
			close(sim)

func same_type_hits() -> void:
	for faction: String in FACTIONS:
		var sim = fixture(faction, faction)
		for spec: String in rules.units:
			var u: Dictionary = rules.units[spec]
			if str(u.faction) != faction or bool(u.get("roster_hidden", false)) or str(u.get("weapon", "")).is_empty():
				continue
			var w: Dictionary = rules.weapons[u.weapon]
			var domain := str(u.get("domain", "ground"))
			if domain not in w.get("targets", ["ground"]):
				continue
			for source_veteran: bool in [false, true]:
				for target_veteran: bool in [false, true]:
					var hit := shot(sim, spec, spec, source_veteran, target_veteran)
					var label := "%s same-type one discharge (attacker veteran=%s target veteran=%s)" % [spec, source_veteran, target_veteran]
					check(bool(hit.legal) and bool(hit.fired), label + " is a real legal shot")
					check(float(hit.remaining_hp) > 0.0, label + " does not kill full-health peer: " + str(hit.damage))
					details.append(hit)
		close(sim)

func rail_unarmored_hits() -> void:
	for faction: String in FACTIONS:
		var sim = fixture(faction, "iron")
		for target: String in ["iron_rail", "iron_rail_junction"]:
			var source := faction + "_rifle"
			var hit := shot(sim, source, target)
			var weapon: Dictionary = rules.weapons[rules.units[source].weapon]
			var expected := float(weapon.damage) * float(weapon.get("multipliers", {}).get("building", 1.0))
			check(bool(hit.fired) and is_equal_approx(float(hit.damage), expected), source + " actual hit on unarmored " + target + " is not quartered")
		close(sim)

func ordinary_infantry_hits() -> void:
	# Explicit anti-infantry and unique superweapons are checked as same-type
	# above; this list covers important weapons without that specialist role.
	var roles: Array[String] = ["rifle", "anti", "tank", "heavy_tank", "artillery", "advanced", "pulse", "attacker", "bomber", "zeppelin", "helicopter", "advanced_tower", "anti_tower", "ship_frigate", "ship_signature", "support_ship", "train", "carrier_plane", "assault", "amphibious"]
	var weakest := ""
	var minimum_hp := INF
	for spec: String in rules.units:
		var u: Dictionary = rules.units[spec]
		if bool(u.get("roster_hidden", false)) or str(u.get("armor_class", "")) != "infantry":
			continue
		if float(u.hp) < minimum_hp:
			minimum_hp = float(u.hp)
			weakest = spec
	check(not weakest.is_empty(), "minimum-HP ordinary infantry target exists")
	for faction: String in FACTIONS:
		var sim = fixture(faction, str(rules.units[weakest].faction))
		for role: String in roles:
			var source := faction + "_" + role
			if source == "iron_assault":
				continue # The actual dedicated anti-infantry cannon is exempt.
			if not rules.units.has(source) and not rules.buildings.has(source):
				continue
			for source_veteran: bool in [false, true]:
				if rules.buildings.has(source) and source_veteran:
					continue
				var hit := shot(sim, source, weakest, source_veteran, false)
				check(bool(hit.legal) and bool(hit.fired), source + " actually fires at weakest infantry")
				check(float(hit.remaining_hp) > 0.0, source + " does not one-shot " + weakest + " (veteran=" + str(source_veteran) + "): " + str(hit.damage))
				details.append(hit)
		close(sim)

func paid_tank_production() -> void:
	for faction: String in FACTIONS:
		var sim = fixture(faction, faction)
		sim.money.assign([10000.0, 10000.0])
		for p: Vector2 in [Vector2(7.5, 8.5), Vector2(7.5, 16.5)]:
			sim._spawn(0, faction + "_power", p, true)
		if rules.buildings.has(faction + "_barracks"):
			sim._spawn(0, faction + "_barracks", Vector2(20.5, 8.5), true)
		var factory: int = sim._spawn(0, faction + "_factory", Vector2(20, 20), true)
		var prior: float = sim.money[0]
		var problem: String = sim.produce(factory, faction + "_tank")
		check(problem.is_empty(), faction + " normal tank production accepted: " + problem)
		check(is_equal_approx(prior - float(sim.money[0]), float(rules.units[faction + "_tank"].cost)), faction + " tank production charges exact live price")
		var produced := -1
		for frame in range(60 * 30):
			sim.step(DT)
			for e: Dictionary in sim.entities.values():
				if e.spec == faction + "_tank" and not bool(e.get("emerging", false)):
					produced = int(e.id)
			if produced >= 0:
				break
		check(produced >= 0, faction + " normal paid tank completes and physically exits in 60 seconds")
		if produced >= 0:
			check(is_equal_approx(float(sim.entities[produced].hp), sim.max_hp(sim.entities[produced])), faction + " normal produced tank has unmodified full HP")
		close(sim)

func paid_tower_construction() -> void:
	for faction: String in FACTIONS:
		var sim = fixture(faction, faction)
		sim.money.assign([10000.0, 10000.0])
		for p: Vector2 in [Vector2(7.5, 8.5), Vector2(7.5, 16.5)]:
			sim._spawn(0, faction + "_power", p, true)
		sim._spawn(0, faction + "_factory", Vector2(20, 20), true)
		var spec := faction + "_advanced_tower"
		var info: Dictionary = rules.buildings[spec]
		var builder := -1
		if str(rules.factions[faction].get("building_method", "")) == "engineer":
			builder = sim._spawn(0, faction + "_engineer", Vector2(14.5, 31.5), true)
		var money_before: float = sim.money[0]
		var problem: String = sim.build(0, spec, builder)
		check(problem.is_empty(), faction + " normal advanced tower construction accepted: " + problem)
		if not problem.is_empty():
			close(sim)
			continue
		var order: Dictionary = sim.order_for_team(0, "defense")
		check(is_equal_approx(float(order.total), float(info.build_time)), faction + " live tower construction timer uses increased build time")
		var tower := -1
		if builder >= 0:
			check(is_equal_approx(float(sim.money[0]), money_before), faction + " field construction charges during actual work")
			problem = sim.place_building(0, Vector2(14.5, 35.5), "defense")
			check(problem.is_empty(), faction + " field tower scaffold placement accepted: " + problem)
		else:
			check(is_equal_approx(money_before - float(sim.money[0]), float(info.cost)), faction + " preparation charges increased tower cost")
		for frame in range(100 * 30):
			sim.step(DT)
			if builder < 0 and tower < 0 and bool(sim.order_for_team(0, "defense").get("ready", false)):
				problem = sim.place_building(0, Vector2(14.5, 35.5), "defense")
				check(problem.is_empty(), faction + " ready tower normal placement accepted: " + problem)
			for e: Dictionary in sim.entities.values():
				if e.spec == spec and float(e.construct_remaining) <= 0.0:
					tower = int(e.id)
			if tower >= 0:
				break
		check(tower >= 0, faction + " normally paid advanced tower physically completes in bounded construction test")
		check(is_equal_approx(money_before - float(sim.money[0]), float(info.cost)), faction + " actual completed tower charges exact increased price")
		details.append({"scenario": "paid_tower_construction", "faction": faction, "seconds": float(sim.time), "completed": tower >= 0, "spent": money_before - float(sim.money[0]), "cost": float(info.cost), "build_time": float(info.build_time), "engineer": builder >= 0})
		close(sim)

func breakthrough_case(attacker: String, defender: String, strong: bool, siege: bool) -> void:
	var sim = fixture(attacker, defender)
	for id in sim.entities.keys():
		if int(sim.entities[id].team) == 1:
			sim._kill_entity(int(id), false)
	var hq: int = sim._spawn(1, defender + "_hq", Vector2(37, 24), true)
	for p: Vector2 in [Vector2(40.5, 8.5), Vector2(40.5, 40.5)]:
		sim._spawn(1, defender + "_power", p, true)
	var targets: Array[int] = [sim._spawn(1, defender + "_tower", Vector2(26, 24), true)]
	if strong:
		for p: Vector2 in [Vector2(29.5, 19.5), Vector2(29.5, 28.5)]:
			targets.append(sim._spawn(1, defender + "_advanced_tower", p, true))
	targets.append(hq)
	check(not sim.building_low_power(sim.entities[targets[0]]), defender + " diagnostic defensive line begins fully powered")
	var roster: Array[int] = []
	var initial_hp := 0.0
	var army_cost := 0.0
	for i in range(8):
		var id: int = sim._spawn(0, attacker + "_tank", Vector2(12, 14 + 2.8 * i), true)
		roster.append(id)
		initial_hp += float(sim.entities[id].hp)
		army_cost += float(rules.units[attacker + "_tank"].cost)
	if siege:
		var spec := attacker + ("_advanced" if attacker == "rivet" else "_artillery")
		check(rules.units.has(spec) and not bool(rules.units[spec].get("roster_hidden", false)), attacker + " uses an actual current siege support unit")
		for i in range(3):
			var id: int = sim._spawn(0, spec, Vector2(8, 19 + 5 * i), true)
			roster.append(id)
			initial_hp += float(sim.entities[id].hp)
			army_cost += float(rules.units[spec].cost)
	sim._rebuild_spatial()
	var stage := 0
	var damaged := false
	for frame in range(120 * 30):
		while stage < targets.size() and not sim.entities.has(targets[stage]):
			stage += 1
		if stage >= targets.size():
			break
		if frame % 60 == 0:
			sim.issue(roster, "attack", sim.entities[targets[stage]].pos, targets[stage])
		sim.step(DT)
		for id: int in roster:
			if not sim.entities.has(id) or float(sim.entities[id].hp) < sim.max_hp(sim.entities[id]) - 0.001:
				damaged = true
		sim.events.clear()
		sim.notices.clear()
	var alive := 0
	var hp := 0.0
	for id: int in roster:
		if sim.entities.has(id):
			alive += 1
			hp += float(sim.entities[id].hp)
	var success: bool = not sim.entities.has(hq) and stage >= targets.size() - 1
	var label := "%s attacking %s (%s)" % [attacker, defender, "tank plus siege against dual high towers" if siege else ("tank-only dual high towers diagnostic" if strong else "tank basic breakthrough")]
	if not strong or siege:
		check(success, label + " destroys defensive line and HQ within 120 seconds")
		check(damaged and alive > 0, label + " has real defensive damage and surviving attackers")
	details.append({"scenario": "mixed_siege_breakthrough" if siege else ("strong_tank_diagnostic" if strong else "tank_basic_breakthrough"), "attacker": attacker, "defender": defender, "seconds": float(sim.time), "tanks": 8, "siege_units": 3 if siege else 0, "alive": alive, "remaining_hp": hp, "initial_hp": initial_hp, "army_cost": army_cost, "hq_destroyed": not sim.entities.has(hq), "defense_stage": stage, "success": success, "defensive_damage": damaged})
	close(sim)

func tank_breakthrough() -> void:
	for attacker: String in FACTIONS:
		for defender: String in FACTIONS:
			breakthrough_case(attacker, defender, false, false)
			breakthrough_case(attacker, defender, true, true)
		# A strong static line is a legitimate anti-tank counter; its raw-tank
		# result is descriptive rather than an assertion that tanks must win.
		breakthrough_case(attacker, attacker, true, false)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	for index in range(args.size()):
		if args[index] == "--output" and index + 1 < args.size():
			output = args[index + 1]
		if args[index] == "--script":
			script_mode = true
	rules = Loader.load_rules("res://data/rules.json", false)
	before = JSON.parse_string(FileAccess.get_file_as_string(BEFORE_PATH))
	check(not rules.is_empty(), "production rules validate: " + str(Loader.errors))
	check(not before.is_empty(), "pre-revision constraints fixture loads")
	if not rules.is_empty() and not before.is_empty():
		catalog()
		penetration_boundaries()
		legacy_snapshot()
		tank_armor_hits()
		rail_unarmored_hits()
		same_type_hits()
		marksman_cross_faction_hits()
		ordinary_infantry_hits()
		paid_tank_production()
		paid_tower_construction()
		tank_breakthrough()
	var report := {"checks": checks, "passed": checks - failures.size(), "failures": failures,
		"rules_sha256": FileAccess.get_sha256("res://data/rules.json"), "before_sha256": before.get("rules_sha256", ""),
		"simulation_sha256": FileAccess.get_sha256("res://scripts/simulation.gd"), "mode": "script" if script_mode else "native",
		"method": "Real WarSimulation; flat 48m diagnostic arena and pre-deployed full-HP rosters; actual fire/projectile/beam damage; veteran rule multipliers; normal paid tank production; 120s bounded ordinary attack commands. No AI league or win-rate claims.", "details": details}
	var absolute := ProjectSettings.globalize_path(output)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write armor revision report: " + absolute)
		quit(1)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("ARMOR_BALANCE_REVISION ", JSON.stringify({"checks": checks, "passed": checks - failures.size(), "failures": failures, "output": absolute}))
	for failure: String in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
