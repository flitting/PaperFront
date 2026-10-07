extends RefCounted

## Iron recovery and weapon-specific EMP use authoritative simulation time.
static func traits(sim, e: Dictionary) -> Dictionary:
	if e.get("kind") != "unit": return {}
	var faction: String = str(sim.factions[int(e.team)])
	if faction != "iron" or str(sim.data_for(e.spec).get("armor_class", "")) != "armored": return {}
	return sim.rules.factions.get(faction, {}).get("traits", {})

static func record_damage(sim, e: Dictionary) -> void:
	if e.get("kind") == "unit": e.last_damage_time = sim.time

static func record_attack(sim, e: Dictionary) -> void:
	if e.get("kind") == "unit": e.last_attack_time = sim.time

static func step_regeneration(sim, delta: float) -> void:
	for e in sim.entities.values():
		if e.kind != "unit" or float(e.hp) <= 0.0: continue
		var config: Dictionary = traits(sim, e)
		var spec: Dictionary = sim.data_for(e.spec)
		var rate: float = float(config.get("regen_fraction_per_second", 0.0))
		var flat_rate: float = float(spec.get("self_heal_rate", 0.0))
		if rate <= 0.0 and flat_rate <= 0.0: continue
		if sim.Transport.is_loaded(e):
			e.last_damage_time = sim.time
			continue
		var last_combat: float = maxf(float(e.get("last_damage_time", sim.time)), float(e.get("last_attack_time", sim.time)))
		var eligible_delta: float = clampf(sim.time - last_combat - float(spec.get("self_heal_delay", config.get("regen_delay", 0.0))), 0.0, delta)
		if eligible_delta <= 0.0: continue
		var max_hp: float = sim.max_hp(e)
		e.hp = minf(max_hp, float(e.hp) + (max_hp * rate + flat_rate) * eligible_delta)

static func apply_emp(sim, target_id: int, weapon: Dictionary, source_team: int) -> void:
	if not sim.entities.has(target_id): return
	var target: Dictionary = sim.entities[target_id]
	if float(target.hp) <= 0.0 or int(target.team) == source_team or sim.Transport.is_loaded(target): return
	var duration: float = 0.0
	if target.kind == "building":
		duration = float(weapon.get("emp_building_duration", 0.0))
	elif sim._is_air(target):
		duration = float(weapon.get("emp_air_duration", weapon.get("emp_vehicle_duration", 0.0)))
	elif str(sim.data_for(target.spec).get("armor_class", "")) == "armored":
		duration = float(weapon.get("emp_vehicle_duration", 0.0))
	if duration > 0.0:
		target.emp_until = maxf(float(target.get("emp_until", 0.0)), sim.time + duration)
		sim.events.append({"kind":"emp", "id":target_id, "pos":target.pos, "team":target.team})
