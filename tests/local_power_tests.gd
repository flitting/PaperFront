extends SceneTree

const LocalPower = preload("res://scripts/local_power.gd")

class PowerFixture extends RefCounted:
	var _building_entities: Array[Dictionary] = []
	var rules: Dictionary
	var time: float = 0.0
	func _init(config: Dictionary) -> void: rules = config.duplicate(true)
	func data_for(spec: String) -> Dictionary: return rules.buildings[spec]
	func add(id: int, spec: String, pos: Vector2, team: int = 0) -> Dictionary:
		var entity: Dictionary = {"id":id, "kind":"building", "spec":spec, "pos":pos, "team":team, "hp":100.0, "construct_remaining":0.0}
		_building_entities.append(entity)
		return entity

var checks: int = 0
var failures: Array[String] = []
var config: Dictionary

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _initialize() -> void:
	config = RulesLoader.load_rules()
	check(not config.is_empty(), "Rules load with local headquarters power: " + str(RulesLoader.errors))
	if config.is_empty(): quit(1); return
	all_headquarters()
	capacity_and_distance()
	multiple_base_sources()
	source_lifecycle()
	consumer_lifecycle()
	configuration_validation()
	print("LOCAL_POWER ", JSON.stringify({"checks":checks, "failures":failures}))
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func all_headquarters() -> void:
	for faction: String in ["kestrel", "rivet", "iron", "sky"]:
		var sim = PowerFixture.new(config)
		# Isolate the same range check from each faction factory's actual load.
		sim.rules.buildings[faction + "_factory"].power = -20
		var hq: Dictionary = sim.add(1, faction + "_hq", Vector2(20,20))
		var nearby: Dictionary = sim.add(2, faction + "_factory", Vector2(25,20))
		var remote: Dictionary = sim.add(3, faction + "_factory", Vector2(33,20))
		var result: Dictionary = LocalPower.summary(sim, 0)
		check(is_equal_approx(float(result.local_supply), 100.0) and is_zero_approx(float(result.global_supply)), faction + " HQ has 100 local power and no global supply")
		check(LocalPower.is_locally_powered(sim, hq, result), faction + " HQ can run its own production")
		check(LocalPower.is_locally_powered(sim, nearby, result) and not LocalPower.is_locally_powered(sim, remote, result), faction + " local power has a 12-cell radius")
		check(result.display.x < result.display.y and result.global_demand > 0.0, faction + " unused local capacity cannot conceal remote shortage")
		check(is_equal_approx(LocalPower.generation(sim,hq),100.0), faction + " HQ counts as a power source")
		var plant: Dictionary = sim.add(4,faction + "_power",Vector2(40,20))
		result = LocalPower.summary(sim,0)
		check(result.global_supply >= result.global_demand and is_equal_approx(LocalPower.generation(sim,plant),float(sim.data_for(plant.spec).power)), faction + " distant plant feeds the global grid")

func capacity_and_distance() -> void:
	var sim = PowerFixture.new(config)
	sim.rules.buildings.rivet_factory.power = -60
	sim.rules.buildings.rivet_tower.power = -40
	sim.add(1,"rivet_hq",Vector2(20,20))
	var first: Dictionary = sim.add(4,"rivet_factory",Vector2(21,20))
	var skipped: Dictionary = sim.add(3,"rivet_factory",Vector2(22,20))
	var final: Dictionary = sim.add(2,"rivet_tower",Vector2(23,20))
	var snapshot: Dictionary = LocalPower.summary(sim,0)
	check(LocalPower.is_locally_powered(sim,first,snapshot) and not LocalPower.is_locally_powered(sim,skipped,snapshot) and LocalPower.is_locally_powered(sim,final,snapshot),"Nearest consumers reserve complete capacity; oversized remaining consumers are skipped")
	check(is_equal_approx(float(snapshot.local_used),100.0) and is_equal_approx(float(snapshot.global_demand),60.0),"Capacity is finite and unmet load remains global demand")
	first.pos=Vector2(23,20)
	skipped.pos=Vector2(23,20)
	final.pos=Vector2(23,20)
	snapshot=LocalPower.summary(sim,0)
	check(LocalPower.is_locally_powered(sim,final,snapshot) and LocalPower.is_locally_powered(sim,skipped,snapshot) and not LocalPower.is_locally_powered(sim,first,snapshot),"Equal-distance allocation is stable by entity ID")
	var other: Dictionary = sim.add(5,"rivet_factory",Vector2(20,21),1)
	check(not LocalPower.is_locally_powered(sim,other),"Local power never crosses team ownership")

func source_lifecycle() -> void:
	for spec: String in ["rivet_hq"]:
		var sim = PowerFixture.new(config)
		var source: Dictionary = sim.add(1,spec,Vector2(20,20))
		var consumer: Dictionary = sim.add(2,"rivet_factory",Vector2(25,20))
		source.emp_until=1.0
		check(not LocalPower.is_locally_powered(sim,consumer) and is_zero_approx(LocalPower.generation(sim,source)),"EMP removes HQ supply")
		sim.time=1.0
		check(LocalPower.is_locally_powered(sim,consumer),"Supply resumes when EMP expires")
		source.hp=0.0
		check(not LocalPower.is_locally_powered(sim,consumer),"Destroyed HQ stops supplying local buildings")
		source.hp=100.0
		source.construct_remaining=1.0
		check(not LocalPower.is_locally_powered(sim,consumer),"Unfinished HQ cannot supply buildings")
		source.construct_remaining=0.0
		source.team=1
		check(not LocalPower.is_locally_powered(sim,consumer) and is_equal_approx(float(LocalPower.summary(sim,1).local_supply),100.0),"Captured HQ supply follows its new team")

func multiple_base_sources() -> void:
	var sim = PowerFixture.new(config)
	var initial: Dictionary = sim.add(1,"rivet_hq",Vector2(20,20))
	var additional: Dictionary = sim.add(2,"rivet_hq",Vector2(50,20))
	var nearby: Dictionary = sim.add(3,"rivet_factory",Vector2(25,20))
	var expansion: Dictionary = sim.add(4,"rivet_factory",Vector2(55,20))
	var snapshot: Dictionary = LocalPower.summary(sim,0)
	check(is_equal_approx(float(snapshot.local_supply),200.0) and LocalPower.is_locally_powered(sim,nearby,snapshot) and LocalPower.is_locally_powered(sim,expansion,snapshot),"two instances of base barracks each supply their own local industrial area")
	initial.hp=0.0
	snapshot=LocalPower.summary(sim,0)
	check(not LocalPower.is_locally_powered(sim,nearby,snapshot) and LocalPower.is_locally_powered(sim,expansion,snapshot) and is_equal_approx(LocalPower.generation(sim,additional),100.0),"losing the starting instance preserves identical supply from an additional base")

func consumer_lifecycle() -> void:
	var sim = PowerFixture.new(config)
	sim.add(1,"rivet_hq",Vector2(20,20))
	var consumer: Dictionary = sim.add(2,"rivet_factory",Vector2(25,20))
	consumer.construct_remaining=1.0
	check(is_zero_approx(float(LocalPower.summary(sim,0).total_demand)),"Scaffolds reserve no power before completion")
	consumer.construct_remaining=0.0
	consumer.emp_until=1.0
	check(not LocalPower.is_locally_powered(sim,consumer) and is_zero_approx(float(LocalPower.summary(sim,0).local_used)),"EMP consumer releases its reservation")
	sim.time=1.0
	check(LocalPower.is_locally_powered(sim,consumer),"Consumer resumes its reservation after EMP")
	consumer.hp=0.0
	check(is_zero_approx(float(LocalPower.summary(sim,0).total_demand)),"Destroyed consumer releases its demand")

func configuration_validation() -> void:
	var invalid: Dictionary = config.duplicate(true)
	invalid.buildings.rivet_hq.erase("local_power_radius")
	check(not RulesLoader.validate(invalid,false).is_empty(),"Local supply requires an explicit positive radius")
	invalid=config.duplicate(true)
	invalid.buildings.rivet_hq.local_power=-10
	check(not RulesLoader.validate(invalid,false).is_empty(),"Local capacity cannot be negative")
	invalid=config.duplicate(true)
	invalid.buildings.rivet_hq.production_roles=["barracks","barracks"]
	check(not RulesLoader.validate(invalid,false).is_empty(),"Headquarters producer aliases cannot be duplicated")
	invalid=config.duplicate(true)
	invalid.buildings.rivet_hq.prerequisite_roles=["unknown"]
	check(not RulesLoader.validate(invalid,false).is_empty(),"Headquarters prerequisite aliases must name supported roles")
	invalid=config.duplicate(true)
	invalid.factions.rivet.building_method="unknown"
	check(not RulesLoader.validate(invalid,false).is_empty(),"Faction construction method must be supported")
	invalid=config.duplicate(true)
	invalid.buildings.rivet_hq.construction_radius=-1
	check(not RulesLoader.validate(invalid,false).is_empty(),"Expansion construction radius must be positive")
