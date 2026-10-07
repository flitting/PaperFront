extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
const Validator = preload("res://scripts/sim_save_validator.gd")
var rules: Dictionary
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	rules = RulesLoader.load_rules()
	_test_mining()
	_test_mine_obstacle()
	_test_forced_fire()
	_test_forced_movement()
	_test_snapshots()
	print("Mining / force rule checks: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _sim():
	var sim = Sim.new()
	sim.setup(rules, "dev", 7, "rivet", false)
	return sim

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _tick(sim, seconds: float) -> void:
	for i in range(ceili(seconds * 30.0)): sim.step(1.0 / 30.0)

func _miner(sim, team: int, offset: Vector2) -> int:
	var id: int = sim.debug_spawn(team, sim.factions[team] + "_harvester", sim.mines[1].pos + offset)
	sim.issue([id], "harvest", sim.mines[1].pos, 1)
	return id

func _test_mining() -> void:
	var sim = _sim()
	var first: int = _miner(sim, 0, Vector2(-1.55, 0))
	var enemy: int = _miner(sim, 1, Vector2(1.55, 0))
	var friend: int = _miner(sim, 0, Vector2(0, 1.55))
	var reserve: float = sim.mines[1].amount
	sim.step(1.0)
	_check(sim.entities[first].cargo == rules.economy.harvest_rate and sim.entities[enemy].cargo == 0.0 and sim.entities[friend].cargo == 0.0, "one crystal has a single mining slot shared by both armies")
	_check(sim.mines[1].miner == first and sim.mines[1].amount == reserve, "active mining retains ownership without reducing the infinite crystal")
	sim.issue([first], "stop", Vector2.ZERO)
	sim.step(1.0)
	_check(sim.mines[1].miner == enemy and sim.entities[enemy].cargo == rules.economy.harvest_rate and sim.entities[friend].cargo == 0.0, "an enemy occupying the crystal excludes friendly mining until it leaves")
	sim.entities[enemy].cargo = rules.economy.harvester_capacity - 1.0
	sim.step(0.1)
	_check(sim.mines[1].miner == friend and sim.entities[friend].cargo > 0.0, "a full miner releases the crystal immediately for the next miner")
	_check(absf((float(sim.entities[enemy].cargo) - float(rules.economy.harvester_capacity) + 1.0) + float(sim.entities[friend].cargo) - float(rules.economy.harvest_rate) * 0.1) < 0.000001, "handover shares the remaining tick time without multiplying a crystal's yield")
	sim._kill_entity(friend, true)
	_check(sim.mines[1].miner == -1, "destroying the current miner releases its crystal")
	sim.issue([first], "harvest", sim.mines[1].pos, 1)
	_tick(sim, 5.0)
	_check(sim.entities[first].cargo > rules.economy.harvest_rate and sim.mines[1].amount == reserve, "longer mining keeps the original yield and infinite resource reserve")
	sim.issue([first], "move", Vector2(10.5, 43.5))
	_check(sim.mines[1].miner == -1, "an explicit movement order releases mining ownership")

func _test_mine_obstacle() -> void:
	var sim = _sim()
	var pos: Vector2 = sim.mines[1].pos
	_check(not sim._standing(pos, 0.35, -1, false) and not sim._standing(pos, 0.75, -1, false), "crystal pillars block both infantry and vehicles")
	_check(not sim._segment_static(pos + Vector2(-3, 0), pos + Vector2(3, 0), 0.35, -1), "a movement segment cannot cross the crystal pillar")
	var path: Array = sim._path_between(pos + Vector2(-3, 0), pos + Vector2(3, 0), 0.35, -1)
	_check(not path.is_empty() and path.all(func(point): return sim._standing(point, 0.35, -1, false)), "ground navigation finds a legal route around the crystal")
	var before: Dictionary = sim.mines[1].duplicate(true)
	sim._impact_damage(pos, 2.0, 100000.0, {}, ["ground"], true)
	sim._apply_damage()
	_check(sim.mines[1] == before, "even forced artillery impacts cannot damage a crystal pillar")

func _test_forced_fire() -> void:
	var sim = _sim()
	var gun: int = sim.debug_spawn(0, "rivet_rifle", Vector2(10.5, 43.5))
	var friend: int = sim.debug_spawn(0, "rivet_engineer", Vector2(13.5, 43.5))
	var initial: float = sim.entities[friend].hp
	sim.issue([gun], "attack", sim.entities[friend].pos, friend)
	_check(sim.entities[gun].commands.is_empty(), "ordinary attack rejects a friendly target")
	sim.issue([gun], "force_attack", sim.entities[friend].pos, friend)
	_tick(sim, 0.2)
	_check(sim.entities[friend].hp < initial, "forced attack deliberately damages a friendly unit")
	sim = _sim()
	var neutral: Dictionary = sim.ruins[0]
	var target: int = sim.RUIN_TARGET_BASE - int(neutral.id)
	initial = neutral.hp
	sim._impact_damage(neutral.pos, 2.0, 10000.0, {}, ["ground"], false)
	sim._apply_damage()
	_check(neutral.hp == initial, "ordinary combat splash cannot destroy neutral scenery")
	sim._damage.clear()
	gun = sim.debug_spawn(0, "rivet_rifle", neutral.pos + Vector2(-3, 0))
	sim.issue([gun], "attack", neutral.pos, target)
	_check(sim.entities[gun].commands.is_empty(), "ordinary attack rejects trees and neutral stone structures")
	sim.issue([gun], "force_attack", neutral.pos, target)
	_tick(sim, 1.0)
	_check(neutral.hp < initial, "forced fire can damage a selected neutral object")
	sim.issue([gun], "force_attack", neutral.pos, -1)
	_tick(sim, 1.0)
	_check(sim.entities[gun].commands[0].kind == "force_attack", "forced attack on a ground position continues firing until cancelled")

func _test_forced_movement() -> void:
	var sim = _sim()
	var tank: int = sim.debug_spawn(0, "rivet_tank", Vector2(5.5, 43.5))
	var friend: int = sim.debug_spawn(0, "rivet_rifle", Vector2(8.5, 43.5))
	sim.issue([friend], "hold", sim.entities[friend].pos)
	sim.issue([tank], "move", Vector2(12.5, 43.5))
	_tick(sim, 0.5)
	_check(sim.entities.has(friend), "ordinary movement preserves friendly infantry")
	sim.issue([tank], "force_move", sim.entities[friend].pos, friend)
	_tick(sim, 4.0)
	_check(sim.entities.has(friend) and sim.entities[tank].pos.distance_to(sim.entities[friend].pos) >= float(sim.entities[tank].radius) + float(sim.entities[friend].radius) - 0.001, "forced movement preserves selected friendly infantry and its collision clearance")
	var crystal: Vector2 = sim.mines[1].pos
	sim.issue([tank], "force_move", crystal)
	_tick(sim, 8.0)
	_check(sim.entities[tank].pos.distance_to(crystal) > 0.75 and sim._standing(sim.entities[tank].pos, sim._radius(sim.entities[tank]), tank, false), "forced movement still obeys the impassable crystal footprint")

func _test_snapshots() -> void:
	var sim = _sim()
	var miner: int = _miner(sim, 0, Vector2(-1.55, 0))
	sim.step(0.1)
	var path: String = "/tmp/paperfront-mining-force.save"
	_check(sim.save_game(path).is_empty(), "a mining claim can be saved")
	var restored = Sim.new()
	_check(restored.load_game(path).is_empty() and restored.mines[1].miner == miner, "loading preserves the shared mining claim")
	_tick(sim, 0.3)
	_tick(restored, 0.3)
	_check(sim.mines == restored.mines and sim.entities == restored.entities, "restored mining advances deterministically")
	var tree: Dictionary = sim.ruins.filter(func(item): return item.kind == "tree")[0]
	sim._add_damage(sim.RUIN_TARGET_BASE - int(tree.id), 10000.0, true)
	sim._apply_damage()
	_check(sim.save_game(path).is_empty() and restored.load_game(path).is_empty() and sim.map == restored.map and sim.ruins == restored.ruins, "destroyed tree saves retain both cleared simulation state and the original map layout")
	DirAccess.remove_absolute(path)
