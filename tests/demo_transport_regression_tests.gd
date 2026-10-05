extends SceneTree

# Real island terrain, entities, simulation ticks and transport commands. Only
# ground path completion is synchronous so the fixed mechanics fixture does
# not depend on worker scheduling; no movement or boarding is mocked.
const Rules = preload("res://scripts/rules_loader.gd")
const Operations = preload("res://scripts/naval_operations.gd")
const TransportCommands = preload("res://scripts/transport_commands.gd")
const UnitTransport = preload("res://scripts/unit_transport.gd")

class ObservedSimulation:
	extends "res://tests/rule_test_simulation.gd"
	var tracing: bool = false
	var coast_queries: Array[Dictionary] = []
	var carrier_orders: Array[Dictionary] = []
	var observed_carrier: int = -1
	var _coast_seen: Dictionary = {}
	var script_entity_ticks: int = 0
	func _step_entities_script(delta: float, multipliers: Array[float]) -> void:
		script_entity_ticks += 1
		super._step_entities_script(delta, multipliers)
	func _standing(pos: Vector2, radius: float, ignore: int, dynamic: bool = true) -> bool:
		if tracing and not dynamic:
			var frames: Array = get_stack()
			for index in range(frames.size()):
				if str(frames[index].get("function", "")) != "coast_pair": continue
				var caller: String = str(frames[index + 1].get("function", "")) if index + 1 < frames.size() else ""
				var key: String = "%.6f:%d:%s" % [time, ignore, caller]
				if not _coast_seen.has(key):
					_coast_seen[key] = true
					coast_queries.append({"time": time, "passenger": ignore, "caller": caller})
				break
		return super._standing(pos, radius, ignore, dynamic)
	func issue(ids: Array, kind: String, pos: Vector2, target: int = -1, append: bool = false) -> void:
		if tracing and observed_carrier in ids:
			carrier_orders.append({"time": time, "kind": kind, "pos": [pos.x, pos.y], "target": target, "append": append})
		super.issue(ids, kind, pos, target, append)
	func reset_trace() -> void:
		coast_queries.clear()
		carrier_orders.clear()
		_coast_seen.clear()
		tracing = true

var failures: Array[String] = []
var checks: int = 0
var evidence: Dictionary = {"fixture": "islands seed 31, Rivet transport, four ground infantry, 0.05 second ticks", "phases": {}}
var rules: Dictionary
var output: String = "res://artifacts/demo_20261004/transport/current.json"
var requested_native: bool = false
var queues_only: bool = false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="): output = arg.trim_prefix("--evidence=")
		if arg == "--native": requested_native = true
		if arg == "--queues-only": queues_only = true
	OS.set_environment("PAPER_FRONT_DISABLE_NATIVE", "0" if requested_native else "1")
	evidence.execution_mode = "native kernels" if requested_native else "GDScript mechanics"
	evidence.native_kernels_available = ClassDB.class_exists("PaperFrontKernels")
	if requested_native: _check(ClassDB.class_exists("PaperFrontKernels"), "requested native simulation kernels are available")
	rules = Rules.load_rules("res://data/rules.json", false)
	_check(not rules.is_empty(), "rules validate")
	if not rules.is_empty() and queues_only:
		evidence.fixture = "saved pending pickup from the full islands seed 31 fixture"
		evidence.fixture_sha256 = FileAccess.get_sha256("/tmp/paperfront-demo-transport-pickup.save")
		_test_stop_hold_priority()
	elif not rules.is_empty():
		_test_four_passenger_crossing()
		_test_explicit_unload_priority()
		_test_released_pickup_owner()
		_test_stop_hold_priority()
	evidence.checks = checks
	evidence.failures = failures
	# Isolated projects and fresh checkouts may not have an artifacts folder.
	if not output.get_base_dir().is_empty(): DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file = FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		_check(false, "evidence file opens: " + output)
	else:
		file.store_string(JSON.stringify(evidence, "\t") + "\n")
	print("Demo transport regression: %d passed, %d failed; evidence %s" % [checks - failures.size(), failures.size(), output])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _snapshot(sim, ship: int, passengers: Array[int]) -> Dictionary:
	var carrier: Dictionary = sim.entities[ship]
	var aboard: int = 0
	var people: Array[Dictionary] = []
	for id in passengers:
		var e: Dictionary = sim.entities[id]
		if int(e.transport_id) == ship: aboard += 1
		people.append({"id": id, "transport_id": e.transport_id, "state": e.state, "pos": [e.pos.x, e.pos.y], "commands": str(e.commands)})
	return {"time": sim.time, "ship_pos": [carrier.pos.x, carrier.pos.y], "ship_state": carrier.state, "ship_commands": str(carrier.commands), "aboard": aboard, "passengers": people, "dispatch": {"native_kernels_enabled": sim.native_kernels_enabled, "native_unit_dispatch_enabled": sim.native_unit_dispatch_enabled, "native_kernels_instantiated": sim._kernels != null, "script_entity_ticks": sim.script_entity_ticks}}

func _test_four_passenger_crossing() -> void:
	var sim = ObservedSimulation.new()
	sim.setup_multiteam(rules, "islands", 31, ["rivet", "kestrel"], false)
	var origin: Dictionary = {}
	var destination: Dictionary = {}
	for harbor: Dictionary in sim.map.get("harbors", []):
		if harbor.get("role", "") != "home": continue
		if int(harbor.get("team", -1)) == 0: origin = harbor
		if int(harbor.get("team", -1)) == 1: destination = harbor
	_check(not origin.is_empty() and not destination.is_empty(), "fixed islands map has both home shores")
	if origin.is_empty() or destination.is_empty(): return
	var ship: int = sim.debug_spawn(0, "rivet_ship_transport", origin.water_pos)
	var passengers: Array[int] = []
	for offset in [Vector2(-1.6, -1.2), Vector2(-0.6, 1.3), Vector2(1.1, -1.1), Vector2(1.8, 1.4)]:
		passengers.append(sim.debug_spawn(0, "rivet_rifle", origin.land_pos + offset))
	_check(ship > 0 and passengers.all(func(id): return id > 0), "carrier and four real infantry spawn legally")
	if ship <= 0 or passengers.any(func(id): return id <= 0): return
	sim.observed_carrier = ship
	sim.reset_trace()
	var load: Dictionary = TransportCommands.board(sim, passengers, ship, false)
	_check(load.passengers.size() == 4 and str(load.error).is_empty(), "four passenger requests reserve legal seats")
	var samples: Array[Dictionary] = [_snapshot(sim, ship, passengers)]
	for frame in range(600):
		sim.step(0.05)
		if frame % 100 == 0: samples.append(_snapshot(sim, ship, passengers))
		if sim.entities[ship].passengers.size() == 4: break
	var final_board: Dictionary = _snapshot(sim, ship, passengers)
	var moves_per_tick: Dictionary = {}
	for command: Dictionary in sim.carrier_orders:
		if command.kind == "move":
			var key: String = "%.6f" % float(command.time)
			moves_per_tick[key] = int(moves_per_tick.get(key, 0)) + 1
	var maximum_moves: int = 0
	for count in moves_per_tick.values(): maximum_moves = maxi(maximum_moves, int(count))
	evidence.phases.board = {"samples": samples, "final": final_board, "coast_pair_calls": sim.coast_queries.duplicate(true), "carrier_orders": sim.carrier_orders.duplicate(true), "maximum_move_orders_in_one_tick": maximum_moves}
	_check(int(final_board.aboard) == 4, "all four infantry physically board within 30 simulation seconds")
	_check(maximum_moves <= 1, "passengers share one carrier pickup command per tick")
	_check(sim.carrier_orders.size() <= 4, "four passengers do not repeatedly restart the carrier route")
	if int(final_board.aboard) < 4: return
	var click: Vector2 = destination.land_pos + Vector2(0.63, -0.42)
	var pair: Dictionary = Operations.coast_pair(sim, sim.entities[ship], null, click)
	_check(not pair.is_empty(), "non-exact destination click resolves to a physical shore")
	if pair.is_empty(): return
	evidence.destination = {"clicked": [click.x, click.y], "resolved_land": [pair.land.x, pair.land.y], "resolved_water": [pair.water.x, pair.water.y], "click_offset": (pair.land as Vector2).distance_to(click)}
	_check((pair.land as Vector2).distance_to(click) > 0.2, "destination fixture exercises a snapped coast rather than an exact endpoint")
	_check(TransportCommands.destination_error(sim, ship, click).is_empty(), "non-exact coast click is accepted by the actual input rules")
	sim.reset_trace()
	sim.issue([ship], "unload_move", click)
	for frame in range(8): sim.step(0.05)
	var cached_queries: int = sim.coast_queries.size()
	evidence.phases.unload_cache = {"coast_pair_calls": sim.coast_queries.duplicate(true), "carrier_orders": sim.carrier_orders.duplicate(true), "snapshot": _snapshot(sim, ship, passengers)}
	_check(cached_queries == 1, "unchanged unload destination resolves its coast once across eight ticks (actual %d)" % cached_queries)
	# A failed cache case is already conclusive; do not multiply its expensive
	# shoreline scan thousands of times just to produce the same failure.
	if cached_queries != 1: return
	var changed_click: Vector2 = click + Vector2(0.7, -0.5)
	sim.entities[ship].commands[0].pos = changed_click
	sim.step(0.05)
	_check(sim.coast_queries.size() == cached_queries + 1 and (sim.entities[ship].commands[0].naval_coast_target as Vector2).is_equal_approx(changed_click), "changed unload destination refreshes the cached coast once")
	sim.entities[ship].commands[0].pos = click
	sim.step(0.05)
	evidence.phases.changed_destination = {"clicked": [changed_click.x, changed_click.y], "coast_pair_calls": sim.coast_queries.duplicate(true)}
	var previous_pair: Dictionary = sim.entities[ship].commands[0].naval_coast_pair
	var blocker: int = sim.debug_spawn(0, "rivet_wall", previous_pair.land, true)
	_check(blocker > 0 and not Operations.pair_clear(sim, sim.entities[ship], null, previous_pair), "a real new shore wall invalidates the cached crossing")
	var queries_before_wall: int = sim.coast_queries.size()
	sim.step(0.05)
	var refreshed_pair: Dictionary = sim.entities[ship].commands[0].get("naval_coast_pair", {})
	_check(sim.coast_queries.size() == queries_before_wall + 1 and Operations.pair_clear(sim, sim.entities[ship], null, refreshed_pair), "blocked coast cache resolves another legal shore exactly once")
	evidence.phases.obstacle_invalidation = {"wall": blocker, "old_pair": str(previous_pair), "new_pair": str(refreshed_pair), "coast_pair_calls": sim.coast_queries.duplicate(true)}
	var save_path: String = "/tmp/paperfront-demo-transport-crossing.save"
	_check(sim.save_game(save_path).is_empty(), "partway-crossing save writes cached coast and loaded passengers")
	var restored = ObservedSimulation.new()
	var restore_error: String = restored.load_game(save_path)
	_check(restore_error.is_empty() and restored.entities == sim.entities, "partway-crossing save restores exact carrier/passenger state: " + restore_error)
	if not restore_error.is_empty(): return
	sim = restored
	sim.observed_carrier = ship
	sim.reset_trace()
	for frame in range(4400):
		sim.step(0.05)
		if sim.entities[ship].passengers.is_empty(): break
	var final_unload: Dictionary = _snapshot(sim, ship, passengers)
	var legal_landing: bool = true
	for id in passengers:
		var passenger: Dictionary = sim.entities[id]
		legal_landing = legal_landing and int(passenger.transport_id) < 0 and sim._terrain(passenger.pos) != MapData.WATER and (passenger.pos as Vector2).distance_to(click) < 20.0 and sim._standing(passenger.pos, sim._radius(passenger), id)
	evidence.phases.crossing = {"final": final_unload, "coast_pair_calls": sim.coast_queries.duplicate(true), "carrier_orders": sim.carrier_orders.duplicate(true), "legal_landing": legal_landing}
	_check(int(final_unload.aboard) == 0 and sim.entities[ship].passengers.is_empty(), "ship crosses water and unloads all four passengers within 220 seconds")
	_check(legal_landing, "all four passengers finish on legal destination-island ground")
	_check(sim.coast_queries.is_empty(), "restored valid coast cache survives the rest of the crossing")

func _test_explicit_unload_priority() -> void:
	var sim = ObservedSimulation.new()
	sim.setup_multiteam(rules, "islands", 31, ["rivet", "kestrel"], false)
	var origin: Dictionary = {}
	var destination: Dictionary = {}
	for harbor: Dictionary in sim.map.get("harbors", []):
		if harbor.get("role", "") != "home": continue
		if int(harbor.get("team", -1)) == 0: origin = harbor
		if int(harbor.get("team", -1)) == 1: destination = harbor
	if origin.is_empty() or destination.is_empty(): return
	var ship: int = sim.debug_spawn(0, "rivet_ship_transport", origin.water_pos)
	var passengers: Array[int] = []
	for offset in [Vector2(-1.6, -1.2), Vector2(-0.6, 1.3), Vector2(1.1, -1.1), Vector2(1.8, 1.4)]:
		passengers.append(sim.debug_spawn(0, "rivet_rifle", origin.land_pos + offset))
	if ship <= 0 or passengers.any(func(id): return id <= 0):
		_check(false, "partial-load priority fixture spawns")
		return
	TransportCommands.board(sim, passengers, ship, false)
	sim.step(0.05)
	var initial_pickup: int = int(sim.entities[ship].get("naval_board_passenger", -1))
	_check(initial_pickup in passengers, "first pending passenger reserves the naval pickup")
	if initial_pickup not in passengers: return
	var save_path: String = "/tmp/paperfront-demo-transport-pickup.save"
	_check(sim.save_game(save_path).is_empty(), "pending naval pickup reservation saves")
	var restored = ObservedSimulation.new()
	var load_error: String = restored.load_game(save_path)
	_check(load_error.is_empty() and restored.entities == sim.entities, "pending naval pickup reservation restores exactly: " + load_error)
	if initial_pickup in passengers:
		var blocked_pair: Dictionary = sim.entities[initial_pickup].commands[0].get("naval_coast_pair", {})
		var wall: int = sim.debug_spawn(0, "rivet_wall", blocked_pair.land, true)
		_check(wall > 0 and not Operations.pair_clear(sim, sim.entities[ship], sim.entities[initial_pickup], blocked_pair), "real new wall blocks the reserved boarding coast")
		sim.step(0.05)
		var refreshed_pair: Dictionary = sim.entities[initial_pickup].commands[0].get("naval_coast_pair", {})
		_check(not refreshed_pair.is_empty() and Operations.pair_clear(sim, sim.entities[ship], sim.entities[initial_pickup], refreshed_pair), "blocked boarding cache refreshes before infantry must reach the obstructed endpoint")
		evidence.phases.boarding_obstacle = {"wall": wall, "old_pair": str(blocked_pair), "new_pair": str(refreshed_pair)}
	# Preserve this exact post-wall state for the explicit-order branch. Other
	# infantry may board before the reserved owner reaches the alternate shore;
	# waiting for that owner can miss the genuine partially loaded interval.
	var priority_path: String = "/tmp/paperfront-demo-transport-priority.save"
	var priority = ObservedSimulation.new()
	var priority_error: String = sim.save_game(priority_path)
	if priority_error.is_empty(): priority_error = priority.load_game(priority_path)
	var priority_exact: bool = priority_error.is_empty() and priority.entities == sim.entities
	evidence.phases.explicit_priority_fixture = {"error": priority_error, "same_entities": priority_exact, "snapshot": _snapshot(sim, ship, passengers)}
	for frame in range(600):
		sim.step(0.05)
		if int(sim.entities[initial_pickup].transport_id) == ship: break
	_check(int(sim.entities[initial_pickup].transport_id) == ship, "reserved passenger physically boards after its original shore is blocked by a wall")
	evidence.phases.boarding_obstacle.final = _snapshot(sim, ship, passengers)
	if priority_exact:
		sim = priority
		for frame in range(600):
			sim.step(0.05)
			if not sim.entities[ship].passengers.is_empty(): break
	var loaded: Array = sim.entities[ship].passengers.duplicate()
	_check(priority_exact and not loaded.is_empty() and loaded.size() < passengers.size(), "explicit-order fixture has embarked and still-pending infantry at its first real boarding tick")
	if loaded.is_empty(): return
	sim.observed_carrier = ship
	sim.reset_trace()
	var click: Vector2 = destination.land_pos + Vector2(0.63, -0.42)
	sim.issue([ship], "unload_move", click)
	for frame in range(8): sim.step(0.05)
	var still_ordered: bool = not sim.entities[ship].commands.is_empty() and sim.entities[ship].commands[0].kind == "unload_move" and (sim.entities[ship].commands[0].pos as Vector2).is_equal_approx(click)
	_check(still_ordered and sim.carrier_orders.size() == 1, "pending boarding requests preserve the player's explicit unload destination")
	evidence.phases.explicit_unload_priority = {"loaded_before_order": loaded, "snapshot": _snapshot(sim, ship, passengers), "carrier_orders": sim.carrier_orders.duplicate(true), "coast_pair_calls": sim.coast_queries.duplicate(true)}
	if not still_ordered: return
	for frame in range(4400):
		sim.step(0.05)
		if sim.entities[ship].passengers.is_empty(): break
	var delivered: bool = true
	for id in loaded:
		var passenger: Dictionary = sim.entities[id]
		delivered = delivered and int(passenger.transport_id) < 0 and (passenger.pos as Vector2).distance_to(click) < 20.0 and sim._terrain(passenger.pos) != MapData.WATER
	_check(delivered, "explicit unload physically delivers its embarked infantry despite pending boarding requests")
	evidence.phases.explicit_unload_priority.final = _snapshot(sim, ship, passengers)

func _test_released_pickup_owner() -> void:
	for action in ["cancel", "destroy"]:
		var sim = ObservedSimulation.new()
		var load_error: String = sim.load_game("/tmp/paperfront-demo-transport-pickup.save")
		_check(load_error.is_empty(), action + " owner fixture restores: " + load_error)
		if not load_error.is_empty(): continue
		var ship: int = -1
		for e: Dictionary in sim.entities.values():
			if e.spec == "rivet_ship_transport": ship = int(e.id)
		if ship <= 0: continue
		var pickup: int = int(sim.entities[ship].get("naval_board_passenger", -1))
		if action == "cancel": sim.issue([pickup], "stop", Vector2.ZERO)
		else: sim._kill_entity(pickup, true)
		sim.step(0.05)
		var next_pickup: int = int(sim.entities[ship].get("naval_board_passenger", -1))
		_check(next_pickup > 0 and next_pickup != pickup and sim.entities.has(next_pickup), action + " releases the owner so another pending passenger can request pickup")
		evidence.phases[action + "_owner"] = {"old_owner": pickup, "new_owner": next_pickup, "ship_commands": str(sim.entities[ship].commands)}

func _test_stop_hold_priority() -> void:
	for kind in ["stop", "hold"]:
		var sim = ObservedSimulation.new()
		var load_error: String = sim.load_game("/tmp/paperfront-demo-transport-pickup.save")
		_check(load_error.is_empty(), kind + " fixture restores a real pending-pickup snapshot: " + load_error)
		if not load_error.is_empty(): continue
		var ship: int = -1
		var passengers: Array[int] = []
		for e: Dictionary in sim.entities.values():
			if e.spec == "rivet_ship_transport": ship = int(e.id)
			elif e.spec == "rivet_rifle": passengers.append(int(e.id))
		if ship <= 0 or passengers.is_empty():
			_check(false, kind + " fixture has its carrier and pending passengers")
			continue
		var queued_passenger: int = passengers[0]
		var followup: Vector2 = sim.entities[queued_passenger].pos + Vector2(1, 1)
		sim.issue([queued_passenger], "board", sim.entities[ship].pos, ship, true)
		sim.issue([queued_passenger], "move", followup, -1, true)
		var future_passenger: int = passengers[1]
		sim.issue([future_passenger], "move", sim.entities[future_passenger].pos + Vector2(-10, -10), -1, true)
		sim.issue([future_passenger], "board", sim.entities[ship].pos, ship, true)
		var other_passenger: int = passengers[2]
		var other_carrier: int = sim.debug_spawn(0, "rivet_scout", sim.entities[other_passenger].pos + Vector2(-8, -8))
		_check(other_carrier > 0, kind + " queue-boundary fixture has another legal carrier")
		if other_carrier <= 0: continue
		sim.issue([other_passenger], "board", sim.entities[other_carrier].pos, other_carrier, true)
		var position_before: Vector2 = sim.entities[ship].pos
		sim.observed_carrier = ship
		sim.reset_trace()
		sim.issue([ship], kind, Vector2.ZERO)
		var no_pending_pickup: bool = not sim.entities[ship].has("naval_board_passenger")
		for id in passengers:
			no_pending_pickup = no_pending_pickup and (sim.entities[id].commands.is_empty() or sim.entities[id].commands[0].kind != "board" or int(sim.entities[id].commands[0].target) != ship)
		_check(no_pending_pickup, kind + " cancels associated current boarding requests and releases the pickup owner")
		_check(sim.entities[queued_passenger].commands.size() == 1 and sim.entities[queued_passenger].commands[0].kind == "move", kind + " removes repeated board/board requests while preserving the later move")
		_check(sim.entities[future_passenger].commands.size() == 2 and sim.entities[future_passenger].commands[0].kind == "move" and sim.entities[future_passenger].commands[1].kind == "board" and int(sim.entities[future_passenger].commands[1].target) == ship, kind + " cancels only the leading board in a board/move/board queue")
		_check(sim.entities[other_passenger].commands.size() == 1 and int(sim.entities[other_passenger].commands[0].target) == other_carrier, kind + " preserves a subsequent board request for another carrier")
		var queues_before_repeat: Array = passengers.map(func(id): return sim.entities[id].commands.duplicate(true))
		UnitTransport.cancel_naval_pickup(sim, sim.entities[ship])
		_check(queues_before_repeat == passengers.map(func(id): return sim.entities[id].commands), kind + " pickup cancellation is idempotent")
		for frame in range(12): sim.step(0.05)
		_check(not sim.entities[future_passenger].commands.is_empty() and sim.entities[future_passenger].commands[0].kind == "move", kind + " future boarding remains behind the real ongoing movement during priority observation")
		_check(sim.carrier_orders.size() == 1 and sim.entities[ship].commands.is_empty() and (sim.entities[ship].pos as Vector2).is_equal_approx(position_before), kind + " remains authoritative across twelve ticks without a new automatic pickup move")
		_check(bool(sim.entities[ship].hold_position) == (kind == "hold"), kind + " preserves the requested hold state")
		var save_path: String = "/tmp/paperfront-demo-transport-" + kind + ".save"
		_check(sim.save_game(save_path).is_empty(), kind + " released pickup state saves")
		var restored = ObservedSimulation.new()
		var restore_error: String = restored.load_game(save_path)
		_check(restore_error.is_empty() and restored.entities == sim.entities and not restored.entities[ship].has("naval_board_passenger"), kind + " released pickup state restores exactly: " + restore_error)
		evidence.phases[kind + "_priority"] = {"snapshot": _snapshot(sim, ship, passengers), "carrier_orders": sim.carrier_orders.duplicate(true)}
		for frame in range(900):
			sim.step(0.05)
			if int(sim.entities[future_passenger].transport_id) == ship: break
		_check(int(sim.entities[future_passenger].transport_id) == ship, kind + " future board after movement still executes the queued transport intent")
		evidence.phases[kind + "_priority"].future_request_final = _snapshot(sim, ship, passengers)
