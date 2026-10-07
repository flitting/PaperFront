extends RefCounted

## Ground production owns a short checked doorway traversal before normal AI.
static func begin(sim, building: Dictionary, unit: Dictionary, exit: Vector2) -> void:
	if sim._is_air(unit) or sim._is_naval(unit):
		unit.alpha=float(sim.BuildingOrientation.quarters(building))*90.0
		unit.turret_alpha=unit.alpha
	if sim._is_air(unit) and bool(sim.data_for(unit.spec).get("permanent_air", false)):
		preload("res://scripts/air_naval_expansion.gd").initialize_air(sim,unit)
		return
	if sim._is_air(unit):
		sim._set_home_airfield(unit, int(building.id))
		unit.service_goal = exit
		unit.flight_state = "rearming"
		unit.rearm_remaining = 0.0
		unit.park_after_service = true
		unit.flight_height = .35
		sim._set_airborne(unit, false)
		return
	if sim._is_naval(unit) and not (bool(sim.data_for(unit.spec).get("amphibious",false)) and sim.data_for(building.spec).get("role","")=="factory"): return
	var direction: Vector2 = (exit - (building.pos as Vector2)).normalized()
	var half: float = float(sim.data_for(building.spec).size)*.5
	var inside: Vector2 = building.pos + direction*(half-sim._radius(unit)-float(sim._eco("production_inside_margin",.75)))
	var original: Vector2 = unit.pos
	unit.pos = inside
	unit.alpha = rad_to_deg(direction.angle())
	unit.turret_alpha = unit.alpha
	unit.emerging = true
	unit.production_source = int(building.id)
	unit.production_exit = exit
	unit.production_origin = inside
	unit.production_elapsed = 0.0
	unit.state = "emerging"
	building.state = "emerging"
	building.production_door = 0.0
	building.production_unit = int(unit.id)
	sim._spatial_move(unit, original, inside)

static func active(sim) -> bool:
	for unit in sim.entities.values():
		if bool(unit.get("emerging", false)): return true
	return false

static func building_step(sim, building: Dictionary, delta: float) -> void:
	var docked: Dictionary=sim.entities.get(int(building.get("dock_unit",-1)),{})
	if not docked.get("refinery_docking",{}).is_empty(): return
	var unit: Dictionary = sim.entities.get(int(building.get("production_unit", -1)), {})
	if unit.is_empty() or not bool(unit.get("emerging", false)):
		building.production_door = maxf(0, float(building.get("production_door",0))-delta/float(sim._eco("production_door_time",.6)))

static func step_unit(sim, unit: Dictionary, delta: float) -> bool:
	if not bool(unit.get("emerging", false)): return false
	var building: Dictionary = sim.entities.get(int(unit.production_source), {})
	if building.is_empty():
		unit.emerging = false
		return false
	if float(building.get("emp_until", 0)) > sim.time:
		unit.state = "waiting_exit"; return true
	var restricted: bool = sim.RailNetwork.rail_only(sim.data_for(unit.spec))
	if restricted and sim._rail_network.at(int(unit.team), unit.production_exit).is_empty():
		unit.state = "waiting_rail"; building.state = "waiting_rail"; return true
	building.state = "emerging"
	var door_time: float = float(sim._eco("production_door_time", .6))
	building.production_door = minf(1, float(building.get("production_door",0))+delta/door_time)
	if float(building.production_door) < 1: unit.state = "waiting_exit"; return true
	var exit: Vector2 = unit.production_exit
	var travel: float = float(sim.data_for(unit.spec).speed)*delta
	var next: Vector2 = (unit.pos as Vector2).move_toward(exit, travel)
	# Ignore only this producer. All other scenery and buildings retain collision.
	if not sim._segment_static(unit.pos, next, sim._radius(unit), int(building.id)):
		unit.state = "waiting_exit"; return true
	for other in sim._neighbors(next):
		if int(other.id) == int(unit.id): continue
		if restricted and int(other.team) == int(unit.team) and sim._rail_network.usable(sim, other, other.pos): continue
		if (other.pos as Vector2).distance_to(next) < sim._radius(unit)+sim._radius(other)+.02:
			unit.state = "waiting_exit"; return true
	var original: Vector2 = unit.pos
	unit.pos = next
	unit.motion = travel/maxf(delta,.001)
	unit.state = "emerging"
	sim._spatial_move(unit, original, next)
	if next.distance_to(exit) <= .01:
		unit.emerging = false
		unit.state = "idle"
		building.production_unit = -1
		building.state = "idle"
	return true
