extends "res://scripts/simulation.gd"
## Optional diagnostic adapter; production simulation has no section timers.
var sections: Dictionary = {}
func record(name: String, stamp: int) -> void:
	var value: Dictionary = sections.get(name, {"calls": 0, "us": 0})
	value.calls += 1
	value.us += Time.get_ticks_usec() - stamp
	sections[name] = value
func _nearest_enemy(e: Dictionary, reach: float) -> int:
	var stamp: int = Time.get_ticks_usec()
	var value: int = super._nearest_enemy(e, reach)
	record("nearest_enemy", stamp)
	return value
func _weapon_can_target(e: Dictionary, target: int, force: bool = false) -> bool:
	var stamp: int = Time.get_ticks_usec()
	var value: bool = super._weapon_can_target(e, target, force)
	record("weapon_can_target", stamp)
	return value
func _step_aircraft_service(e: Dictionary, delta: float) -> bool:
	var stamp: int = Time.get_ticks_usec()
	var value: bool = super._step_aircraft_service(e, delta)
	record("aircraft_service", stamp)
	return value
func _find_airfield(e: Dictionary) -> int:
	var stamp: int = Time.get_ticks_usec()
	var value: int = super._find_airfield(e)
	record("find_airfield", stamp)
	return value
func _neighbors(pos: Vector2) -> Array:
	var stamp: int = Time.get_ticks_usec()
	var value: Array = super._neighbors(pos)
	record("neighbors", stamp)
	return value
func _movement_clear(e: Dictionary, start: Vector2, next: Vector2, request_yield: bool = false) -> bool:
	var stamp: int = Time.get_ticks_usec()
	var value: bool = super._movement_clear(e, start, next, request_yield)
	record("movement_clear", stamp)
	return value
func _segment_static(start: Vector2, end: Vector2, radius: float, ignore: int) -> bool:
	var stamp: int = Time.get_ticks_usec()
	var value: bool = super._segment_static(start, end, radius, ignore)
	record("segment_static", stamp)
	return value
func _building_clear(pos: Vector2, radius: float, ignore: int) -> bool:
	var stamp: int = Time.get_ticks_usec()
	var value: bool = super._building_clear(pos, radius, ignore)
	record("building_clear", stamp)
	return value
func _standing(pos: Vector2, radius: float, ignore: int, dynamic: bool = true) -> bool:
	var stamp: int = Time.get_ticks_usec()
	var value: bool = super._standing(pos, radius, ignore, dynamic)
	record("standing", stamp)
	return value
func _move_to(e: Dictionary, goal: Vector2, delta: float) -> bool:
	var stamp: int = Time.get_ticks_usec()
	var value: bool = super._move_to(e, goal, delta)
	record("move_to", stamp)
	return value
func _mobile_acquire_and_fire(e: Dictionary, delta: float) -> void:
	var stamp: int = Time.get_ticks_usec()
	super._mobile_acquire_and_fire(e, delta)
	record("mobile_acquire", stamp)
func _step_support(delta: float, multipliers: Array[float]) -> void:
	var stamp: int = Time.get_ticks_usec()
	super._step_support(delta, multipliers)
	record("support", stamp)
func _step_projectiles(delta: float) -> void:
	var stamp: int = Time.get_ticks_usec()
	super._step_projectiles(delta)
	record("projectiles", stamp)
func _impact_damage(center: Vector2, blast: float, damage: float, multipliers: Dictionary, targets: Array, force: bool) -> void:
	var stamp: int = Time.get_ticks_usec()
	super._impact_damage(center, blast, damage, multipliers, targets, force)
	record("impact_damage", stamp)
func _apply_damage() -> void:
	var stamp: int = Time.get_ticks_usec()
	super._apply_damage()
	record("apply_damage", stamp)
func _rebuild_spatial() -> void:
	var stamp: int = Time.get_ticks_usec()
	super._rebuild_spatial()
	record("rebuild_spatial", stamp)
