extends RefCounted
## Aircraft lifecycle and submerged combat are shared by native and script ticks.
const AirNavigation = preload("res://scripts/air_navigation.gd")
const CarrierLaunch=preload("res://scripts/carrier_launch.gd")

static func permanent(sim, e: Dictionary) -> bool:
	return bool(sim.data_for(str(e.get("spec", ""))).get("permanent_air", false))

static func initialize_air(sim, e: Dictionary) -> void:
	if not permanent(sim, e): return
	e.flight_state = "airborne"
	e.flight_height = float(sim.data_for(e.spec).get("flight_height", 4.0))
	e.ammo = maxi(1, int(sim.data_for(e.spec).get("ammo_capacity", 1)))
	e.rearm_remaining = 0.0
	e.takeoff_pending = false
	sim._set_home_airfield(e, -1)
	sim._set_airborne(e, true)

static func service(sim, e: Dictionary, delta: float) -> bool:
	if permanent(sim, e):
		initialize_air(sim, e)
		return false
	if not bool(sim.data_for(e.spec).get("carrier_plane", false)): return false
	if CarrierLaunch.step(sim,e,delta):return true
	var carrier: Dictionary = sim.entities.get(int(e.get("carrier_id", -1)), {})
	if carrier.is_empty() or float(carrier.hp) <= 0:
		# An orphan still flies and fights its final sortie, then leaves combat.
		if int(e.get("ammo", 0)) <= 0 or not sim._target_alive(int(e.get("sortie_target",-1))):
			_recover(sim, e)
			return true
		return false
	var target: int = int(e.get("sortie_target", -1))
	if int(e.get("ammo", 0)) > 0 and sim._target_alive(target) and not e.commands.is_empty() and sim._weapon_can_target(e,target): return false
	e.commands.clear()
	e.flight_state = "airborne"
	e.state = "returning_carrier"
	if (e.pos as Vector2).distance_to(carrier.pos) <= 2.6:
		carrier.carrier_ready = mini(2, int(carrier.get("carrier_ready", 0)) + 1)
		sim.events.append({"kind":"carrier_recover", "id":carrier.id, "aircraft":e.id, "team":e.team, "pos":carrier.pos})
		_recover(sim, e)
		return true
	AirNavigation.fly_to(sim, e, carrier.pos, delta)
	return true

static func carrier_fire(sim, carrier: Dictionary, target: int) -> bool:
	if not bool(sim.data_for(carrier.spec).get("carrier", false)): return false
	var weapon: Dictionary = sim.weapon_for(carrier,str(sim.data_for(carrier.spec).weapon))
	if not sim._target_alive(target) or (carrier.pos as Vector2).distance_to(sim._target_position(target)) > float(weapon.range): return true
	var flying: int = 0
	for plane: Dictionary in sim.entities.values():
		if int(plane.get("carrier_id", -1)) == int(carrier.id): flying += 1
	if not carrier.has("carrier_ready"): carrier.carrier_ready = 2
	if flying >= 2 or int(carrier.carrier_ready) <= 0: return true
	if int(carrier.get("carrier_pending_count",0))>0:return true
	carrier.carrier_pending_count=mini(int(carrier.carrier_ready),2-flying)
	carrier.carrier_pending_target=target
	CarrierLaunch.launch_next(sim,carrier)
	carrier.cooldown=float(weapon.interval)
	carrier.attack_flash=.25
	return true

static func step_fleet(sim, delta: float) -> void:
	for carrier: Dictionary in sim.entities.values():
		if not bool(sim.data_for(carrier.spec).get("carrier", false)): continue
		CarrierLaunch.launch_next(sim,carrier)
		var flying: int = 0
		for plane: Dictionary in sim.entities.values():
			if int(plane.get("carrier_id", -1)) == int(carrier.id): flying += 1
		var ready: int = int(carrier.get("carrier_ready", 2))
		if ready + flying >= 2:
			carrier.carrier_rebuild = 0.0
			continue
		carrier.carrier_rebuild = float(carrier.get("carrier_rebuild", 0.0)) + delta
		if float(carrier.carrier_rebuild) >= 20.0:
			carrier.carrier_ready = ready + 1
			carrier.carrier_rebuild = 0.0

static func submarine(sim, e: Dictionary) -> bool:
	return bool(sim.data_for(str(e.get("spec", ""))).get("submarine", false))

static func detected(sim, team: int, e: Dictionary) -> bool:
	if not submarine(sim, e) or int(e.team) == team: return true
	if float(e.get("surfaced_until", 0.0)) > sim.time: return true
	for detector: Dictionary in sim.entities.values():
		if int(detector.team) != team or float(detector.hp) <= 0.0 or int(detector.get("transport_id", -1)) > 0: continue
		var sonar: float = float(sim.data_for(detector.spec).get("sonar_range", 0.0))
		if sonar > 0 and (detector.pos as Vector2).distance_squared_to(e.pos) <= sonar * sonar: return true
	return false

static func can_target(sim, source: Dictionary, target: int) -> bool:
	var other: Dictionary = sim.entities.get(target, {})
	if other.is_empty() or not submarine(sim, other): return true
	if not detected(sim, int(source.team), other): return false
	return bool(sim.data_for(source.spec).get("anti_submarine", false))

static func record_fire(sim, source: Dictionary) -> void:
	if submarine(sim, source): source.surfaced_until = sim.time + 2.5

static func _recover(sim, aircraft: Dictionary) -> void:
	# Recovery is removal from the active battlefield, never a destruction event.
	var id: int = int(aircraft.id)
	sim._spatial_remove(id, aircraft.pos)
	sim._cancel_path_request(id)
	sim._planning_queue.erase(id)
	sim._goal_standing_cache.erase(id)
	sim.entities.erase(id)
	sim._damage_causes.erase(id)
	sim._damage_voice_next.erase(id)
	sim._airfield_counts_dirty = true
