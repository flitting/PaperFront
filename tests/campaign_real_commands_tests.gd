extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
const MAP = preload("res://scripts/campaign_map.gd")
var failures: Array[String] = []
var checks: int = 0
var sim
var placed_sites: Dictionary = {}
var armor_deaths: Array = []
var max_ai_armed: int = 0
var min_ai_money: float = INF

func _initialize() -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/rules.json"))
	sim = Sim.new()
	sim.setup(config, "campaign", 1, "kestrel", true)
	sim.ai_enabled = "--campaign-ai" in OS.get_cmdline_user_args()
	var power: int = build_and_place("kestrel_power", Vector2(57,165), -1)
	check(power > 0 and sim.campaign_controller.stage == 1, "paid power construction advances stage 1")
	var refinery: int = build_and_place("kestrel_refinery", Vector2(72,157), -1)
	check(refinery > 0, "paid refinery can be placed near headquarters")
	var harvester: int = find_entity("kestrel_harvester")
	if harvester > 0:
		sim.issue([harvester], "harvest", Vector2(81.5,142.5))
	advance_until(func(): return sim.campaign_controller.stage >= 2, 200.0)
	check(sim.campaign_controller.stage >= 2, "real harvester delivers to refinery")
	if sim.campaign_controller.stage >= 2:
		var barracks: int = build_and_place("kestrel_barracks", Vector2(69,184), -1)
		check(barracks > 0, "paid barracks can be constructed")
		if barracks > 0:
			check(sim.produce(barracks, "kestrel_rifle").is_empty(), "paid rifle enters barracks queue")
			check(sim.produce(barracks, "kestrel_engineer").is_empty(), "paid engineer enters same barracks queue")
			advance_until(func(): return sim.campaign_controller.flags.trained_rifle and sim.campaign_controller.flags.trained_engineer, 100.0)
			check(sim.campaign_controller.flags.trained_rifle and sim.campaign_controller.flags.trained_engineer, "both units emerge through normal production")
			var rifle: int = find_entity("kestrel_rifle")
			if rifle > 0:
				sim.issue([rifle], "move", MAP.WEST_BRIDGE + Vector2(-2,0))
				advance_until(func(): return sim.campaign_controller.stage >= 3, 200.0)
				check(sim.campaign_controller.stage >= 3, "rifle pathfinds to western bridgehead")
	if sim.campaign_controller.stage >= 3:
		var repairer: int = find_entity("kestrel_engineer")
		if repairer > 0:
			sim.issue([repairer], "bridge", Vector2(160,160))
			advance_until(func(): return sim.campaign_controller.stage >= 4, 240.0)
			check(sim.campaign_controller.stage >= 4 and bool(sim.bridges[0].alive), "engineer repairs bridge through normal order")
	if sim.campaign_controller.stage >= 4:
		var expander: int = find_entity("kestrel_engineer")
		var outpost: int = build_and_place("kestrel_outpost", MAP.EXPANSION + Vector2(8,0), expander)
		check(outpost > 0 and sim.campaign_controller.stage >= 5, "engineer constructs funded eastern outpost")
	if sim.campaign_controller.stage >= 5:
		var factory: int = build_and_place("kestrel_factory", Vector2(69,184), -1)
		check(factory > 0, "factory is buildable after eastern expansion")
		var carrier: int = find_entity("kestrel_scout")
		var passenger: int = find_entity("kestrel_rifle")
		if carrier > 0 and passenger > 0:
			sim.issue([passenger], "board", sim.entities[carrier].pos, carrier)
			advance_until(func(): return sim.entities.has(passenger) and int(sim.entities[passenger].get("transport_id",-1)) == carrier, 220.0)
			check(sim.entities.has(passenger) and int(sim.entities[passenger].get("transport_id",-1)) == carrier, "rifle boards scout using normal order")
			if sim.entities.has(passenger) and int(sim.entities[passenger].get("transport_id",-1)) == carrier:
				sim.issue([carrier], "unload_move", MAP.EAST_ASSEMBLY)
				advance_until(func(): return sim.campaign_controller.stage >= 6, 250.0)
				check(sim.campaign_controller.stage >= 6, "scout drives to and unloads at designated eastern assembly")
	if sim.campaign_controller.stage >= 6:
		var tower: int = build_and_place("kestrel_tower", Vector2(72, 169), -1)
		check(tower > 0, "paid tower protects the headquarters during final defense")
		var armor_factory: int = find_entity("kestrel_factory")
		if armor_factory > 0:
			for wave: int in 2:
				if sim.result == "win": break
				for order: int in 4:
					check(sim.produce(armor_factory, "kestrel_tank").is_empty(), "paid armored counterattack order %d/%d" % [wave,order])
				advance_until(func(): return count_entities("kestrel_tank") >= 4, 110.0)
				check(count_entities("kestrel_tank") >= 4, "counterattack force emerges from factory")
				advance_until(func(): return sim.campaign_controller.hold_elapsed >= 60.0, 65.0)
				check(sim.campaign_controller.hold_elapsed >= 60.0, "headquarters survives timed defense phase")
				var armor: Array = []
				for entity: Dictionary in sim.entities.values():
					if entity.spec == "kestrel_tank" and int(entity.team) == 0: armor.append(int(entity.id))
				if not armor.is_empty():
					sim.issue(armor, "attack_move", MAP.ENEMY_START)
					advance_until(func(): return sim.result == "win" or count_entities("kestrel_tank") == 0, 230.0)
			check(sim.result == "win" and sim.campaign_controller.finished, "funded armor destroys enemy HQ and wins mission")
	if sim.ai_enabled:
		check(max_ai_armed <= int(sim.campaign_controller.ai_policy().army_cap), "enemy mobile army stays within mission cap")
		check(int(sim.ai_state[1].get("campaign_waves", 0)) <= 2, "enemy launches at most two attack waves")
		check(min_ai_money >= 0.0, "enemy production spends normal nonnegative funds")
	var force: Dictionary = {}
	for entity: Dictionary in sim.entities.values():
		var key: String = str(entity.spec)
		force[key] = int(force.get(key,0)) + 1
	var enemy_hq_hp: float = -1.0
	for entity: Dictionary in sim.entities.values():
		if entity.spec == "rivet_hq": enemy_hq_hp = float(entity.hp)
	print("CAMPAIGN_REAL_COMMANDS ",JSON.stringify({"checks":checks,"ai":sim.ai_enabled,"result":sim.result,"stage":sim.campaign_controller.stage,"time":sim.time,"money":sim.money[0],"max_ai_armed":max_ai_armed,"ai_waves":sim.ai_state[1].get("campaign_waves",0),"min_ai_money":min_ai_money,"enemy_hq_hp":enemy_hq_hp,"armor_deaths":armor_deaths,"force":force,"placed_sites":placed_sites,"failures":failures}))
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func build_and_place(spec: String, preferred: Vector2, builder: int) -> int:
	var original: Dictionary = sim.entities.duplicate()
	var channel: String = sim.construction_channel(spec)
	var error: String = sim.build(0, spec, builder)
	if not error.is_empty():
		failures.append("Cannot buy " + spec + ": " + error)
		return -1
	advance_until(func(): return bool(sim.order_for_team(0, channel).get("ready", false)), 90.0)
	if not bool(sim.order_for_team(0, channel).get("ready", false)):
		failures.append("Building queue never readied: " + spec)
		return -1
	var site: Vector2 = find_site(preferred, channel)
	if not site.is_finite():
		failures.append("No legal site for " + spec + " near " + str(preferred))
		return -1
	error = sim.place_building(0, site, channel)
	placed_sites[spec] = site
	if not error.is_empty():
		failures.append("Cannot place " + spec + ": " + error)
		return -1
	advance_until(func(): return _completed_new_building(spec, original) > 0, 120.0)
	return _completed_new_building(spec, original)

func find_site(preferred: Vector2, channel: String = "normal") -> Vector2:
	for radius: int in range(0, 32):
		for z: int in range(floori(preferred.y) - radius, floori(preferred.y) + radius + 1):
			for x: int in range(floori(preferred.x) - radius, floori(preferred.x) + radius + 1):
				var pos := Vector2(x,z)
				if sim.placement_error(0,pos,channel).is_empty(): return pos
	return Vector2.INF

func _completed_new_building(spec: String, original: Dictionary) -> int:
	for id: int in sim.entities:
		var e: Dictionary = sim.entities[id]
		if not original.has(id) and e.spec == spec and float(e.construct_remaining) <= 0.0: return id
	return -1

func find_entity(spec: String) -> int:
	for e: Dictionary in sim.entities.values():
		if e.spec == spec and int(e.team) == 0 and float(e.hp) > 0.0: return int(e.id)
	return -1

func count_entities(spec: String) -> int:
	var count: int = 0
	for e: Dictionary in sim.entities.values():
		if e.spec == spec and int(e.team) == 0 and float(e.hp) > 0.0: count += 1
	return count

func advance_until(done: Callable, max_seconds: float) -> void:
	var elapsed: float = 0.0
	while elapsed < max_seconds and not done.call() and sim.result.is_empty():
		sim.step(0.5)
		if sim.ai_enabled:
			min_ai_money = minf(min_ai_money, float(sim.money[1]))
			var armed: int = 0
			for entity: Dictionary in sim.entities.values():
				if int(entity.team) == 1 and entity.kind == "unit" and not str(sim.data_for(entity.spec).get("weapon", "")).is_empty(): armed += 1
			max_ai_armed = maxi(max_ai_armed, armed)
		for event: Dictionary in sim.events:
			if event.get("kind", "") == "death" and event.get("spec", "") == "kestrel_tank": armor_deaths.append({"time":sim.time,"pos":event.get("pos",Vector2.ZERO)})
		sim.events.clear()
		sim.notices.clear()
		elapsed += 0.5

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
