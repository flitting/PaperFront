extends RefCounted
const MAP = preload("res://scripts/map_data.gd")

# The native unit dispatcher calls the simulation's common _fire callback.
# A hero reserves its normal cooldown when the strike begins; the impact is
# resolved later through the same shot and damage path as ordinary weapons.
static func begin(sim, e: Dictionary, target: int, landing: Vector2, force: bool) -> bool:
	var info: Dictionary = sim.data_for(str(e.spec))
	if not bool(info.get("hero", false)): return false
	if float(e.get("hand_strike", 0.0)) > 0.0 or float(e.get("hand_recover", 0.0)) > 0.0 or float(e.cooldown) > 0.0: return true
	var weapon: Dictionary = sim.rules.weapons.get(str(info.get("weapon", "")), {})
	if weapon.is_empty(): return true
	e.cooldown = float(weapon.interval)
	e.hand_strike = float(info.get("attack_windup", 0.5))
	e.hand_recover = 0.0
	e.hand_target = target
	e.hand_landing = landing
	e.hand_ground_height = _ground_height(sim,e,landing,target)
	e.hand_contact_height = _contact_height(sim,e,landing,target)
	e.hand_force = force
	e.state = "attack"
	return true

static func cancel(e: Dictionary) -> void:
	e.hand_strike = 0.0
	e.hand_target = -1
	e.hand_recover = 0.0
	e.hand_contact_height = 0.0
	e.hand_ground_height = 0.0

static func _contact_height(sim,e:Dictionary,landing:Vector2,target:int) -> float:
	# The model's root is placed at the attacker's ground level. The target
	# surface may sit on a different tile height or above water/air.
	return sim._height(landing)-sim._height(e.pos)+sim._target_height(target)

static func _ground_height(sim,e:Dictionary,landing:Vector2,target:int) -> float:
	# Debris rests on the local ground or water surface after the target dies.
	# Naval units and shipyards float below the height of the underlying tile.
	var naval:bool=false
	if target>0 and sim.entities.has(target):
		var victim:Dictionary=sim.entities[target]
		naval=sim._is_naval(victim) or str(sim.data_for(str(victim.spec)).get("domain","ground"))=="naval"
	if naval or (target<0 and MAP.terrain_at(sim.map,landing)==MAP.WATER):
		return MAP.water_surface_y(sim.map,landing)-sim._height(e.pos)
	return sim._height(landing)-sim._height(e.pos)

static func step(sim, delta: float) -> void:
	for e in sim.entities.values():
		if e.kind != "unit" or not bool(sim.data_for(str(e.spec)).get("hero", false)): continue
		var old_strike: float = float(e.get("hand_strike", 0.0))
		if old_strike > 0.0:
			if float(e.hp) <= 0.0 or float(e.get("emp_until", 0.0)) > sim.time or sim.Transport.is_loaded(e):
				cancel(e)
				continue
			var target: int = int(e.get("hand_target", -1))
			var landing: Vector2 = e.get("hand_landing", e.pos)
			if target != -1:
				if not sim._target_alive(target) or not sim._weapon_can_target(e, target, bool(e.get("hand_force", false))):
					cancel(e)
					continue
				landing = sim._target_position(target)
			e.hand_landing = landing
			e.hand_ground_height = _ground_height(sim,e,landing,target)
			e.hand_contact_height = _contact_height(sim,e,landing,target)
			var weapon: Dictionary = sim.rules.weapons.get(str(sim.data_for(str(e.spec)).get("weapon", "")), {})
			if weapon.is_empty() or (e.pos as Vector2).distance_to(landing) > float(weapon.get("range", 0.0)) + 0.001:
				cancel(e)
				continue
			e.hand_strike = maxf(0.0, old_strike - delta)
			if float(e.hand_strike) <= 0.0:
				var saved_cooldown: float = float(e.cooldown)
				e.cooldown = 0.0
				e.hand_resolving = true
				sim._launch_shot(e, landing, target, bool(e.get("hand_force", false)))
				e.hand_resolving = false
				e.cooldown = maxf(saved_cooldown, float(e.cooldown))
				e.hand_recover = float(sim.data_for(str(e.spec)).get("attack_recovery", 0.35))
				e.hand_target = -1
			continue
		if float(e.get("hand_recover", 0.0)) > 0.0:
			e.hand_recover = maxf(0.0, float(e.hand_recover) - delta)
