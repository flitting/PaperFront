extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
const Squads = preload("res://scripts/infantry_squads.gd")
const Garrison = preload("res://scripts/garrison_operations.gd")
const TransportCommands = preload("res://scripts/transport_commands.gd")
var failures: Array[String] = []
var checks: int = 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func _initialize() -> void:
	var config: Dictionary = Rules.load_rules("res://data/rules.json", false)
	check(not config.is_empty(), "squad rules validate")
	var sim = Sim.new()
	sim.setup(config, "dev", 41, "kestrel", false)
	var authored_map: Dictionary = sim.map.duplicate(true)
	for z: int in range(sim.map.size):
		for x: int in range(sim.map.size): sim.map.terrain[z][x] = 0; sim.map.heights[z][x] = 0
	sim.mines.clear(); sim.bridges.clear(); sim.ruins.clear()
	sim._refresh_ruin_spatial(); sim._refresh_mine_spatial(); sim._prepare_terrain_cache()
	sim._nav_dirty = true
	sim.money[0] = 20000.0
	var barracks: int = sim.debug_spawn(0, "kestrel_barracks", Vector2(14, 22))
	check(barracks > 0, "barracks fixture")
	check(sim.squad_size("kestrel_rifle") == 5, "five rifle soldiers per squad")
	check(sim.squad_size("kestrel_marksman") == 2, "dedicated sniper pair")
	check(sim.squad_size("kestrel_demolition") == 3, "advanced squad has fewer soldiers")
	check(sim.squad_size("kestrel_engineer") == 1, "engineers remain independent")
	var cost: float = sim.production_cost("kestrel_rifle")
	check(is_equal_approx(cost, float(config.units.kestrel_rifle.cost) * 5.0), "group cost sums individual soldiers")
	check(is_equal_approx(sim.production_time("kestrel_rifle"), float(config.units.kestrel_rifle.build_time) * 5.0), "training time sums individual soldiers")
	sim.money[0] = cost - 1.0
	check(not sim.produce(barracks, "kestrel_rifle").is_empty(), "cannot buy a squad with only one soldier's funds")
	check(sim.entities[barracks].queue.is_empty(), "failed purchase creates no order")
	sim.money[0] = 20000.0
	var before: float = sim.money[0]
	check(sim.produce(barracks, "kestrel_rifle").is_empty(), "purchase one squad")
	check(is_equal_approx(before - sim.money[0], cost), "entire squad paid once")
	check(sim.entities[barracks].queue.size() == 1 and int(sim.entities[barracks].queue[0].squad_size) == 5, "one queue entry stores the whole squad")
	check(sim.cancel_production(barracks, 0).is_empty() and is_equal_approx(sim.money[0], before), "unstarted group cancellation refunds its full price")
	check(sim.produce(barracks, "kestrel_rifle").is_empty(), "queue replacement squad")
	sim.entities[barracks].queue[0].remaining = 0.0
	sim.step(.05)
	check(int(sim.entities[barracks].queue[0].spawned) == 1, "group exits sequentially without spawning overlapping people")
	var assembly_path: String = "user://infantry_squad_assembly_tests.save"
	var flat_map: Dictionary = sim.map
	sim.map = authored_map
	check(sim.save_game(assembly_path).is_empty(), "save squad while members are still exiting")
	sim.map = flat_map
	var assembly_restore = Sim.new()
	var assembly_error: String = assembly_restore.load_game(assembly_path)
	check(assembly_error.is_empty(), "load partially deployed squad: " + assembly_error)
	if assembly_error.is_empty():
		var restored_order: Dictionary = assembly_restore.entities[barracks].queue[0]
		check(int(restored_order.spawned) == 1 and int(restored_order.squad_size) == 5 and assembly_restore.squad_members(int(restored_order.squad_id)).size() == 1, "saved queue resumes with its exact deployed count and group identity")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(assembly_path))
	for tick: int in range(500):
		sim.step(.05)
		if sim.entities[barracks].queue.is_empty() and not sim.ProductionLifecycle.active(sim): break
	var soldiers: Array = []
	for e: Dictionary in sim.entities.values():
		if e.spec == "kestrel_rifle" and int(e.team) == 0: soldiers.append(int(e.id))
	check(soldiers.size() == 5, "one completed order spawns exactly five real soldiers")
	check(sim.entities[barracks].queue.is_empty(), "order completes after the final member exits")
	check(int(sim.statistics.to_dict().teams[0].units_produced) == 5, "production statistics count actual people")
	if soldiers.size() == 5:
		var leader: int = int(soldiers[0])
		check(sim.squad_members(leader).size() == 5 and sim.selection_ids(soldiers).size() == 1, "five members form one command object")
		check(sim.expand_squad_ids([soldiers[3]], true).size() == 5, "selecting any member expands the squad")
		sim.issue([soldiers[3]], "move", Vector2(29, 28))
		var goals: Array = []
		for id: int in soldiers:
			check(sim.entities[id].commands.size() == 1 and sim.entities[id].commands[0].kind == "move", "group move reaches member %d" % id)
			goals.append(sim.entities[id].commands[0].pos)
		check(goals[0] != goals[1], "member movement preserves separate formation slots")
		var other_hp: float = float(sim.entities[soldiers[1]].hp)
		sim._add_damage(leader, 7.0, true)
		sim._apply_damage()
		check(is_equal_approx(float(sim.entities[soldiers[1]].hp), other_hp), "damage applies to one soldier independently")
		var group_id: int = int(sim.entities[leader].squad_id)
		sim._kill_entity(leader, true)
		check(sim.squad_members(soldiers[1]).size() == 4 and sim.squad_leader(soldiers[1]) == soldiers[1], "a surviving member succeeds the dead leader")
		check(int(sim.entities[soldiers[1]].squad_id) == group_id and int(sim.entities[soldiers[1]].squad_capacity) == 5, "losses preserve stable group identity and original capacity")
		var save_path: String = "user://infantry_squad_tests.save"
		var flat_fixture: Dictionary = sim.map
		sim.map = authored_map
		check(sim.save_game(save_path).is_empty(), "save depleted squad")
		sim.map = flat_fixture
		var restored = Sim.new()
		var error: String = restored.load_game(save_path)
		check(error.is_empty(), "load depleted squad: " + error)
		if error.is_empty():
			check(restored.squad_members(soldiers[1]).size() == 4 and int(restored.entities[soldiers[1]].squad_id) == group_id, "save/load retains members and identity without replacements")
			check(restored.selection_ids(soldiers).size() == 1, "dead saved representative resolves to survivor")
		var file: FileAccess = FileAccess.open(save_path, FileAccess.READ)
		var old_snapshot: Dictionary = file.get_var(false)
		file.close()
		var malformed: Dictionary = old_snapshot.duplicate(true)
		malformed.entities[soldiers[1]].squad_slot = int(malformed.entities[soldiers[2]].squad_slot)
		check(not Squads.validate_snapshot(malformed).is_empty(), "duplicate squad slots are rejected before loading")
		for e: Dictionary in old_snapshot.entities.values():
			for field: String in ["squad_id", "squad_slot", "squad_capacity", "squad_formation_goal"]: e.erase(field)
			for order: Dictionary in e.queue:
				for field: String in ["squad_size", "spawned", "squad_id"]: order.erase(field)
		file = FileAccess.open(save_path, FileAccess.WRITE)
		file.store_var(old_snapshot, false)
		file.close()
		var legacy_restore = Sim.new()
		var legacy_error: String = legacy_restore.load_game(save_path)
		check(legacy_error.is_empty(), "legacy save with no group metadata still loads: " + legacy_error)
		if legacy_error.is_empty(): check(legacy_restore.squad_members(soldiers[1]).size() == 1 and legacy_restore.selection_ids(soldiers).size() == 4, "legacy save preserves its original individual command objects")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	check(sim.produce(barracks, "kestrel_rifle").is_empty(), "prepare partially deployed cancellation")
	sim.entities[barracks].queue[0].remaining = 0.0
	for tick: int in range(500):
		sim.step(.05)
		if int(sim.entities[barracks].queue[0].spawned) > 0: break
	var partial: Dictionary = sim.entities[barracks].queue[0]
	var partial_id: int = int(partial.squad_id)
	var paid_balance: float = sim.money[0]
	check(int(partial.spawned) == 1 and sim.cancel_production(barracks, 0).is_empty(), "partially deployed order can be cancelled")
	check(is_equal_approx(sim.money[0], paid_balance) and sim.entities.has(partial_id), "cancelling trained squad never refunds a deployed soldier")
	if sim.entities.has(partial_id): sim._kill_entity(partial_id, false)
	var squad: int = sim.debug_spawn_squad(0, "kestrel_rifle", Vector2(30, 14))
	var engineer: int = sim.debug_spawn_squad(0, "kestrel_engineer", Vector2(33, 14))
	check(squad > 0 and sim.squad_members(squad).size() == 5, "authored spawn creates complete group")
	check(engineer > 0 and sim.squad_members(engineer).size() == 1 and not sim.entities[engineer].has("squad_id"), "authored engineer is a singleton")
	var legacy: int = sim.debug_spawn(0, "kestrel_rifle", Vector2(35, 14))
	check(sim.squad_members(legacy).size() == 1, "unrelated legacy infantry never auto-merge")
	var carrier: int = sim.debug_spawn(0, "iron_transport", Vector2(31, 17))
	check(not sim.board_error(squad, carrier).is_empty(), "four-seat carrier rejects five-person group")
	sim.rules.units.iron_transport.transport_capacity = 5
	check(sim.board_error(squad, carrier).is_empty(), "five seats permit five people")
	sim.issue([squad], "board", sim.entities[carrier].pos, carrier)
	var boarding: int = 0
	for id: int in sim.squad_members(squad):
		if sim.entities[id].commands.size() == 1 and sim.entities[id].commands[0].kind == "board": boarding += 1
	check(boarding == 5, "one transport order sends all five members")
	check(not sim.board_error(engineer, carrier).is_empty(), "walking squad reserves five real seats")
	sim.issue([squad], "stop", Vector2.ZERO)
	check(sim.board_error(engineer, carrier).is_empty(), "cancelled boarding releases reservations")
	var boarding_order: Dictionary = TransportCommands.board(sim, [squad, engineer], carrier, false)
	check(boarding_order.passengers.size() == 5 and engineer not in boarding_order.passengers, "transport batching accepts complete squads without reporting a partial group")
	for tick: int in range(500):
		sim.step(.05)
		if sim.entities[carrier].passengers.size() == 5: break
	check(sim.entities[carrier].passengers.size() == 5, "every squad member boards into its own transport seat")
	check(sim.squad_members(squad, true).is_empty() and sim.squad_members(squad).size() == 5, "embarking retains squad identity and hides deployed members")
	check(sim.unload(carrier).is_empty(), "whole group unloads through valid separate positions")
	check(sim.entities[carrier].passengers.is_empty() and sim.squad_members(squad, true).size() == 5, "unloading restores all members and the same command group")
	var house: Dictionary = {"id":sim.ruins.size(),"kind":"house","pos":Vector2(40, 28),"half":Vector2(1.5, 1.35),"hp":900.0,"max_hp":900.0,"garrison":[],"garrison_team":-1}
	sim.ruins.append(house)
	var house_target: int = Garrison.BASE - int(house.id)
	check(Garrison.board_error(sim, squad, house_target).is_empty(), "six-seat house accepts a five-person squad")
	sim.issue([squad], "garrison", house.pos, house_target)
	check(Garrison.board_error(sim, legacy, house_target).is_empty(), "one final house seat remains available")
	var second: int = sim.debug_spawn_squad(0, "kestrel_marksman", Vector2(35, 25))
	check(not Garrison.board_error(sim, second, house_target).is_empty(), "reserved house seats cannot overbook a second group")
	for id: int in sim.squad_members(squad):
		var e: Dictionary = sim.entities[id]
		var original: Vector2 = e.pos
		e.pos = Garrison._door(sim, house, e)
		sim._spatial_move(e, original, e.pos)
		Garrison.step_board(sim, e, e.commands[0], .05)
	check(house.garrison.size() == 5 and sim.squad_members(squad, true).is_empty(), "garrison uses five separate occupants and preserves their group")
	check(Garrison.unload(sim, house_target, false, 0).is_empty() and sim.squad_members(squad, true).size() == 5, "evacuating squad restores all five independent soldiers")
	var legacy_info: Dictionary = config.units.kestrel_rifle.duplicate(true)
	legacy_info.erase("squad_size")
	check(Squads.size(legacy_info) == 1 and is_equal_approx(Squads.cost(legacy_info), float(legacy_info.cost)), "old rules retain individual recruitment")
	finish()

func finish() -> void:
	print("Infantry squads: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
