extends RefCounted

const AircraftOperations = preload("res://scripts/aircraft_operations.gd")
const NavalOperations = preload("res://scripts/naval_operations.gd")

## Embarked infantry keep their entity and health, but leave navigation/combat.
## The simulation calls these helpers so transport shares its normal movement,
## terrain checks, death cleanup and authoritative save state.
static func initialize(e: Dictionary) -> void:
	if e.get("kind") != "unit": return
	e.transport_id = int(e.get("transport_id", -1))
	e.passengers = e.get("passengers", [])

static func is_loaded(e: Dictionary) -> bool:
	return int(e.get("transport_id", -1)) > 0 or int(e.get("garrison_id", -1)) >= 0

static func _water_carrier(sim, carrier: Dictionary) -> bool:
	return NavalOperations.is_naval(sim, carrier) and not (bool(sim.data_for(carrier.spec).get("amphibious", false)) and sim._terrain(carrier.pos) != MapData.WATER)

static func capacity(sim, carrier: Dictionary) -> int:
	return int(sim.data_for(str(carrier.get("spec", ""))).get("transport_capacity", 0))

static func board_error(sim, passenger_id: int, carrier_id: int) -> String:
	if not sim.entities.has(passenger_id) or not sim.entities.has(carrier_id): return "步兵或运输载具已不存在"
	var passenger: Dictionary = sim.entities[passenger_id]
	var carrier: Dictionary = sim.entities[carrier_id]
	var passenger_spec: Dictionary = sim.data_for(passenger.spec)
	if passenger.get("kind") != "unit" or passenger_spec.get("armor_class") != "infantry" or passenger_spec.get("domain", "ground") != "ground" or is_loaded(passenger): return "运输载具只能搭载未上车的地面步兵"
	if carrier.get("kind") != "unit" or capacity(sim, carrier) <= 0 or is_loaded(carrier): return "该单位没有步兵运输能力"
	if passenger.team != carrier.team: return "只能搭载友方步兵"
	if float(passenger.hp) <= 0.0 or float(carrier.hp) <= 0.0: return "步兵或运输车辆已被摧毁"
	if carrier.get("passengers", []).size() >= capacity(sim, carrier): return "运输载具已满员"
	if sim._is_air(carrier) and bool(carrier.get("airborne", true)):
		if carrier.get("flight_state", "") == "returning":
			if not sim._airfield_valid(int(carrier.get("home_airfield", -1)), int(carrier.team)): return "运输机附近没有可用机场；请先指定降落地点"
		elif carrier.get("flight_state", "") not in ["airborne", "stranded"] or not _boarding_landing(sim, carrier, passenger).is_finite():
			return "运输机附近没有合法降落地点；请先指定降落地点"
	return ""

static func step_board(sim, passenger: Dictionary, command: Dictionary, delta: float) -> void:
	var carrier_id: int = int(command.target)
	var error: String = board_error(sim, int(passenger.id), carrier_id)
	if not error.is_empty():
		sim._finish_command(passenger)
		if int(passenger.team) == 0: sim._notice(error)
		return
	var carrier: Dictionary = sim.entities[carrier_id]
	if bool(sim.data_for(carrier.spec).get("amphibious", false)) and _water_carrier(sim,carrier):
		if carrier.commands.is_empty():
			var separation: float=sim._radius(carrier)+sim._radius(passenger)+.2
			var direction: Vector2=((carrier.pos as Vector2)-(passenger.pos as Vector2)).normalized()
			var pickup: Vector2=passenger.pos+direction*separation
			if not preload("res://scripts/amphibious_navigation.gd").point_clear(sim,pickup,sim._radius(carrier),int(carrier.id),false): pickup=passenger.pos
			sim.issue([int(carrier.id)],"move",pickup)
		passenger.state="waiting"
		return
	if _water_carrier(sim, carrier):
		_step_board_naval(sim, passenger, carrier, command, delta)
		return
	if sim._is_air(carrier) and bool(carrier.get("airborne", true)):
		if carrier.get("flight_state", "") == "returning":
			var home: Dictionary = sim.entities.get(int(carrier.get("home_airfield", -1)), {})
			if not home.is_empty():
				var home_approach: Vector2 = sim._refinery_approach(passenger, home)
				if home_approach.is_finite(): sim._move_to(passenger, home_approach, delta)
			return
		var landing: Vector2 = _boarding_landing(sim, carrier, passenger)
		if not landing.is_finite():
			sim._finish_command(passenger)
			return
		if carrier.get("commands", []).is_empty() or carrier.commands[0].get("kind", "") != "land":
			sim.issue([int(carrier.id)], "land", landing)
		var approach_direction: Vector2 = (passenger.pos - landing).normalized()
		if approach_direction == Vector2.ZERO: approach_direction = Vector2.RIGHT
		var approach: Vector2 = landing + approach_direction * (sim._radius(passenger) + sim._radius(carrier) + 0.16)
		sim._move_to(passenger, approach, delta)
		return
	if _at_legacy_airfield_center(sim, carrier):
		var field: Dictionary = sim.entities.get(int(carrier.get("home_airfield", -1)), {})
		if field.is_empty():
			sim._finish_command(passenger)
			return
		if sim._engineering_distance(passenger, field) <= sim._radius(passenger) + .7 and sim._segment_static(passenger.pos, carrier.pos, sim._radius(passenger), int(field.id)):
			_board(sim, passenger, carrier)
			return
		var approach: Vector2 = sim._refinery_approach(passenger, field)
		if approach.is_finite(): sim._move_to(passenger, approach, delta)
		return
	var toward: Vector2 = (passenger.pos - carrier.pos).normalized()
	if toward == Vector2.ZERO: toward = Vector2.LEFT.rotated(deg_to_rad(float(carrier.alpha)))
	var separation: float = sim._radius(passenger) + sim._radius(carrier)
	var goal: Vector2 = carrier.pos + toward * (separation + 0.12)
	var close: bool = (passenger.pos as Vector2).distance_to(carrier.pos) <= separation + 0.45
	if close and sim._segment_static(passenger.pos, carrier.pos, sim._radius(passenger), int(passenger.id)):
		_board(sim, passenger, carrier)
		return
	command.pos = goal
	sim._move_to(passenger, goal, delta)

static func _step_board_naval(sim, passenger: Dictionary, carrier: Dictionary, command: Dictionary, delta: float) -> void:
	var carrier_command: Dictionary = carrier.commands[0] if not carrier.commands.is_empty() else {}
	if not carrier.commands.is_empty():
		# A passenger may request a pickup only while the ship is idle or
		# serving that passenger. Never replace the player's sail/unload order,
		# or alternate destinations between several simultaneous passengers.
		if not bool(carrier_command.get("naval_board_pickup", false)):
			passenger.state = "waiting"
			return
	# Keep the reservation after the ship reaches water: its movement command
	# can finish before the infantry reaches land. Releasing it at that point
	# would let another passenger sail the ship away from its waiting pickup.
	var pickup_id: int = int(carrier.get("naval_board_passenger", carrier_command.get("naval_board_passenger", -1)))
	var pickup: Dictionary = sim.entities.get(pickup_id, {})
	var pending: bool = not pickup.is_empty() and not is_loaded(pickup) and float(pickup.hp) > 0.0 and not pickup.commands.is_empty() and pickup.commands[0].get("kind", "") == "board" and int(pickup.commands[0].get("target", -1)) == int(carrier.id)
	if not pending and carrier.commands.size() > 1:
		passenger.state = "waiting"
		return
	var owns_pickup: bool = not pending or pickup_id == int(passenger.id)
	if owns_pickup: carrier.naval_board_passenger = int(passenger.id)
	var pair: Dictionary = command.get("naval_coast_pair", {})
	if not pair.is_empty() and not NavalOperations.pair_clear(sim, carrier, passenger, pair):
		command.erase("naval_coast_pair")
		pair = {}
	if pair.is_empty():
		pair = NavalOperations.coast_pair(sim, carrier, passenger)
		if pair.is_empty():
			sim._finish_command(passenger)
			if int(passenger.team) == 0: sim._notice("没有可通行的岸边登船点")
			return
		command.naval_coast_pair = pair
	var land: Vector2 = pair.land
	var water: Vector2 = pair.water
	if owns_pickup and (carrier.pos as Vector2).distance_to(water) > maxf(0.45, sim._radius(carrier) * 0.45):
		if carrier.commands.is_empty() or int(carrier.commands[0].get("naval_board_passenger", -1)) != int(passenger.id) or (carrier.commands[0].pos as Vector2).distance_to(water) > 0.2:
			var queued: Array = carrier.commands.slice(1).duplicate(true) if not carrier.commands.is_empty() else []
			sim.issue([int(carrier.id)], "move", water)
			if not carrier.commands.is_empty():
				carrier.commands[0].naval_board_pickup = true
				carrier.commands[0].naval_board_passenger = int(passenger.id)
				carrier.commands.append_array(queued)
	if (passenger.pos as Vector2).distance_to(land) > 0.42:
		sim._move_to(passenger, land, delta)
		return
	if (carrier.pos as Vector2).distance_to(water) > maxf(0.5, sim._radius(carrier) * 0.55):
		passenger.state = "waiting"
		return
	if not NavalOperations.pair_clear(sim, carrier, passenger, pair):
		command.erase("naval_coast_pair")
		passenger.state = "waiting"
		return
	# The two endpoints were individually validated and share one beach edge.
	# Never board from the far side of a wall or across a deep river.
	if not sim._segment_static(passenger.pos, land, sim._radius(passenger), int(passenger.id)):
		passenger.state = "waiting"
		return
	_board(sim, passenger, carrier)

## Explicit stop/hold cancels consecutive same-ship boarding requests at each
## passenger's queue head; Shift duplicates belong to the same pickup. Keep
## embarked infantry, later movement and future boarding requests intact.
static func cancel_naval_pickup(sim, carrier: Dictionary) -> void:
	if not _water_carrier(sim, carrier): return
	carrier.erase("naval_board_passenger")
	for passenger: Dictionary in sim.entities.values():
		if passenger.get("kind", "") != "unit" or is_loaded(passenger) or passenger.get("commands", []).is_empty(): continue
		var command: Dictionary = passenger.commands[0]
		if command.get("kind", "") != "board" or int(command.get("target", -1)) != int(carrier.id): continue
		while not passenger.commands.is_empty() and passenger.commands[0].get("kind", "") == "board" and int(passenger.commands[0].get("target", -1)) == int(carrier.id):
			sim._finish_command(passenger)
		passenger.path_wait = 0.0
		passenger.planning_wait = 0.0
		passenger.stuck = 0.0
		passenger.yield_goal = Vector2.INF
		sim._planning_deferred_ids.erase(int(passenger.id))
		sim._planning_requested_ids.erase(int(passenger.id))
		sim._cancel_path_request(int(passenger.id))

static func _boarding_landing(sim, carrier: Dictionary, passenger: Dictionary) -> Vector2:
	if not carrier.get("commands", []).is_empty() and carrier.commands[0].get("kind", "") == "land":
		var ordered: Vector2 = carrier.commands[0].pos
		if AircraftOperations.land_error(sim, carrier, ordered).is_empty(): return ordered
	var toward: Vector2 = (passenger.pos - carrier.pos).normalized()
	if toward == Vector2.ZERO: toward = Vector2.RIGHT
	for ring in range(17):
		var radius: float = float(ring) * 0.75
		var choices: int = 1 if ring == 0 else 16
		for step in range(choices):
			var goal: Vector2 = carrier.pos + toward.rotated(float(step) * TAU / 16.0) * radius
			if AircraftOperations.land_error(sim, carrier, goal).is_empty(): return goal
	return Vector2.INF

static func _board(sim, passenger: Dictionary, carrier: Dictionary) -> void:
	sim._spatial_remove(int(passenger.id), passenger.pos)
	_clear_navigation(sim, passenger)
	passenger.transport_id = int(carrier.id)
	passenger.pos = carrier.pos
	passenger.state = "transported"
	passenger.motion = 0.0
	carrier.passengers.append(int(passenger.id))
	if int(carrier.get("naval_board_passenger", -1)) == int(passenger.id): carrier.erase("naval_board_passenger")
	sim.events.append({"kind": "board", "id": passenger.id, "carrier": carrier.id, "pos": carrier.pos, "team": passenger.team})

static func sync_passengers(sim) -> void:
	for carrier in sim.entities.values():
		for id in carrier.get("passengers", []):
			if not sim.entities.has(id): continue
			var passenger: Dictionary = sim.entities[id]
			passenger.pos = carrier.pos
			passenger.alpha = carrier.alpha
			passenger.state = "transported"
			passenger.motion = 0.0

static func unload(sim, carrier_id: int, preferred_pair: Dictionary = {}) -> String:
	if not sim.entities.has(carrier_id): return "运输载具已不存在"
	var carrier: Dictionary = sim.entities[carrier_id]
	if capacity(sim, carrier) <= 0: return "该单位没有步兵运输能力"
	if sim._is_air(carrier) and bool(carrier.get("airborne", true)): return "运输机需要先降落才能卸载步兵"
	if carrier.get("passengers", []).is_empty(): return "运输载具没有搭载步兵"
	var naval_pair: Dictionary = {}
	if _water_carrier(sim, carrier):
		naval_pair = preferred_pair if NavalOperations.pair_clear(sim, carrier, null, preferred_pair) else NavalOperations.coast_pair(sim, carrier)
		if naval_pair.is_empty() or (carrier.pos as Vector2).distance_to(naval_pair.water) > maxf(0.5, sim._radius(carrier) * 0.55): return "舰船需驶近可通行海岸才能卸载"
	var blocked: bool = false
	for id in carrier.passengers.duplicate():
		if not sim.entities.has(id):
			carrier.passengers.erase(id)
			continue
		var passenger: Dictionary = sim.entities[id]
		var pos: Vector2 = _naval_unload_position(sim, carrier, passenger, naval_pair) if _water_carrier(sim, carrier) else _unload_position(sim, carrier, passenger)
		if not pos.is_finite():
			blocked = true
			continue
		carrier.passengers.erase(id)
		passenger.transport_id = -1
		passenger.pos = pos
		_clear_navigation(sim, passenger)
		passenger.state = "idle"
		sim._spatial_add(int(passenger.id), pos)
		sim.events.append({"kind": "unload", "id": passenger.id, "carrier": carrier.id, "pos": pos, "team": passenger.team})
	return "载具附近没有可供步兵下车的空地" if blocked else ""

## A carrier can travel to a chosen destination and disembark there. Aircraft
## land first and stay on the ground until a later flight order takes them off.
static func step_unload_move(sim, carrier: Dictionary, command: Dictionary, delta: float) -> void:
	if carrier.get("passengers", []).is_empty():
		sim._finish_command(carrier)
		return
	if sim._is_air(carrier):
		if not AircraftOperations.step_land(sim, carrier, command, delta, false): return
	elif bool(sim.data_for(carrier.spec).get("amphibious", false)):
		if not NavalOperations.move_to(sim, carrier, command.pos, delta): return
	elif _water_carrier(sim, carrier):
		var pair: Dictionary = command.get("naval_coast_pair", {})
		var coast_target: Vector2 = command.get("naval_coast_target", Vector2.INF)
		# The resolved beach is usually several metres from the clicked point.
		# Cache against the requested target, and revalidate the short crossing
		# so new shore obstacles still force a fresh coast lookup.
		if pair.is_empty() or not coast_target.is_equal_approx(command.pos) or not NavalOperations.pair_clear(sim, carrier, null, pair):
			pair = NavalOperations.coast_pair(sim, carrier, null, command.pos)
			if pair.is_empty():
				carrier.state = "unreachable"
				if not bool(command.get("blocked_notice", false)) and int(carrier.team) == 0:
					sim._notice("目标附近没有可通行的卸载海岸")
					command.blocked_notice = true
				return
			command.naval_coast_pair = pair
			command.naval_coast_target = command.pos
		if not NavalOperations.move_to(sim, carrier, pair.water, delta): return
	elif not sim._move_order(carrier, command, delta):
		return
	var error: String = unload(sim, int(carrier.id), command.get("naval_coast_pair", {}) if _water_carrier(sim, carrier) else {})
	if carrier.get("passengers", []).is_empty():
		sim._finish_command(carrier)
	elif not error.is_empty():
		carrier.state = "waiting"
		if not bool(command.get("blocked_notice", false)) and int(carrier.team) == 0:
			sim._notice(error)
			command.blocked_notice = true

static func _naval_unload_position(sim, carrier: Dictionary, passenger: Dictionary, pair: Dictionary) -> Vector2:
	if pair.is_empty(): return Vector2.INF
	var land: Vector2 = pair.land
	var radius: float = sim._radius(passenger)
	for ring in range(4):
		var distance: float = float(ring) * 0.38
		for step in range(16):
			var point: Vector2 = land + Vector2.from_angle(float(step) * TAU / 16.0) * distance
			if point.distance_to(pair.water) > radius + sim._radius(carrier) + 1.55: continue
			if sim._standing(point, radius, int(passenger.id)) and sim._segment_static(land, point, radius, int(passenger.id)):
				return point
	return Vector2.INF

static func _unload_position(sim, carrier: Dictionary, passenger: Dictionary) -> Vector2:
	var radius: float = sim._radius(passenger)
	var distance: float = radius + sim._radius(carrier) + 0.18
	var passage_ignore: int = int(passenger.id)
	if _at_legacy_airfield_center(sim, carrier):
		var field: Dictionary = sim.entities.get(int(carrier.get("home_airfield", -1)), {})
		if field.is_empty(): return Vector2.INF
		distance = float(sim.data_for(field.spec).size) * .5 + radius + .2
		passage_ignore = int(field.id)
	# Check a small local ring; never unload across an impassable wall or river.
	for ring in range(3):
		for step in range(16):
			var angle: float = deg_to_rad(float(carrier.alpha)) + PI + float(step) * TAU / 16.0
			var pos: Vector2 = carrier.pos + Vector2.from_angle(angle) * (distance + float(ring) * 0.4)
			if sim._standing(pos, radius, int(passenger.id)) and sim._segment_static(carrier.pos, pos, radius, passage_ignore):
				return pos
	return Vector2.INF

static func _at_legacy_airfield_center(sim, carrier: Dictionary) -> bool:
	if not sim._is_air(carrier) or carrier.get("flight_state", "") != "rearming": return false
	var field: Dictionary = sim.entities.get(int(carrier.get("home_airfield", -1)), {})
	return not field.is_empty() and (carrier.pos as Vector2).distance_to(field.pos) < 0.5

static func remove(sim, e: Dictionary, destroyed: bool) -> void:
	if int(e.get("garrison_id", -1)) >= 0:
		var ruin: Dictionary = sim.ruin_by_target(-100000-int(e.garrison_id))
		if not ruin.is_empty():
			ruin.get("garrison", []).erase(int(e.id))
			if ruin.get("garrison", []).is_empty(): ruin.garrison_team = -1
		e.garrison_id = -1
	if is_loaded(e):
		var carrier_id: int = int(e.transport_id)
		if sim.entities.has(carrier_id): sim.entities[carrier_id].passengers.erase(int(e.id))
	for id in e.get("passengers", []).duplicate():
		if sim.entities.has(id):
			if destroyed:sim.entities[id].last_damage_cause=e.get("last_damage_cause",{}).duplicate()
			sim._kill_entity(int(id), destroyed)
	e.passengers = []

static func _clear_navigation(sim, passenger: Dictionary) -> void:
	passenger.commands.clear()
	passenger.path.clear()
	passenger.path_goal = Vector2.INF
	passenger.path_wait = 0.0
	passenger.stuck = 0.0
	passenger.auto_target = -1
	passenger.turret_target = -1
	passenger.yield_goal = Vector2.INF
	passenger.hold_position = false
	passenger.planning_wait = 0.0
	passenger.movement_retry_at = 0.0
	passenger.progress_clock = 0.0
	passenger.progress_anchor = passenger.pos
	passenger.avoid_until = 0.0
	sim._planning_queue.erase(int(passenger.id))
	sim._planning_deferred_ids.erase(int(passenger.id))
	sim._planning_requested_ids.erase(int(passenger.id))
	sim._cancel_path_request(int(passenger.id))
