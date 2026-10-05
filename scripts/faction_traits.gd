extends RefCounted

## Shared faction combat rules. All clocks use the authoritative simulation time.
static func traits(sim, e: Dictionary) -> Dictionary:
	if e.get("kind") != "unit": return {}
	var faction: String = str(sim.factions[int(e.team)])
	return sim.rules.factions.get(faction, {}).get("traits", {})

static func incoming_damage(sim, e: Dictionary, amount: float) -> float:
	if e.get("kind") != "unit": return amount
	return amount * (1.0 - float(traits(sim, e).get("damage_reduction", 0.0)))

static func record_damage(sim, e: Dictionary) -> void:
	if e.get("kind") == "unit": e.last_damage_time = sim.time

static func record_attack(sim, e: Dictionary) -> void:
	if e.get("kind") == "unit": e.last_attack_time = sim.time

static func step_regeneration(sim, delta: float) -> void:
	for e in sim.entities.values():
		if e.kind != "unit" or float(e.hp) <= 0.0: continue
		var config: Dictionary = traits(sim, e)
		var rate: float = float(config.get("regen_fraction_per_second", 0.0))
		if rate <= 0.0: continue
		if sim.Transport.is_loaded(e):
			e.last_damage_time = sim.time
			continue
		var last_combat: float = maxf(float(e.get("last_damage_time", sim.time)), float(e.get("last_attack_time", sim.time)))
		var eligible_delta: float = clampf(sim.time - last_combat - float(config.get("regen_delay", 0.0)), 0.0, delta)
		if eligible_delta <= 0.0: continue
		var max_hp: float = float(sim.data_for(e.spec).hp)
		e.hp = minf(max_hp, float(e.hp) + max_hp * rate * eligible_delta)

static func step_breakthrough(sim) -> void:
	for e in sim.entities.values():
		if e.kind != "unit" or float(e.hp) <= 0.0: continue
		var config: Dictionary = traits(sim, e)
		var required: float = float(config.get("breakthrough_distance", 0.0))
		if required <= 0.0: continue
		var previous: Vector2 = e.get("breakthrough_last_pos", e.pos)
		e.breakthrough_last_pos = e.pos
		var spec: Dictionary = sim.data_for(e.spec)
		if str(spec.get("armor_class", "")) != "armored" or str(spec.get("weapon", "")).is_empty() or str(spec.get("domain", "ground")) not in ["ground", "naval"] or sim.Transport.is_loaded(e):
			e.breakthrough_progress = 0.0
			e.breakthrough_ready_until = 0.0
			continue
		if float(e.get("breakthrough_ready_until", 0.0)) > sim.time: continue
		if e.commands.is_empty() or e.commands[0].kind != "attack_move":
			e.breakthrough_progress = 0.0
			continue
		var traveled: float = minf(previous.distance_to(e.pos), required)
		e.breakthrough_progress = minf(required, float(e.get("breakthrough_progress", 0.0)) + traveled)
		if float(e.breakthrough_progress) >= required:
			e.breakthrough_ready_until = sim.time + float(config.get("breakthrough_window", 0.0))
			e.breakthrough_progress = 0.0

static func outgoing_scale(sim, source: Dictionary) -> float:
	if source.get("kind") != "unit": return 1.0
	if str(sim.data_for(source.spec).get("weapon", "")).is_empty() or sim.Transport.is_loaded(source): return 1.0
	var config: Dictionary = traits(sim, source)
	var bonus: float = float(config.get("cohesion_damage_bonus", 0.0))
	if bonus <= 0.0: return 1.0
	var reach: float = float(config.get("cohesion_radius", 0.0))
	var count: int = 0
	var domain: String = str(sim.data_for(source.spec).get("domain", "ground"))
	for other in sim._nearby_entities(source.pos, reach):
		if int(other.id) == int(source.id) or other.kind != "unit" or other.team != source.team or float(other.hp) <= 0.0 or sim.Transport.is_loaded(other): continue
		var spec: Dictionary = sim.data_for(other.spec)
		if str(spec.get("domain", "ground")) != domain or str(spec.get("weapon", "")).is_empty(): continue
		if (source.pos as Vector2).distance_to(other.pos) > reach: continue
		count += 1
		if count >= int(config.get("cohesion_min_allies", 2)): return 1.0 + bonus
	return 1.0

static func cohesion_bonus(sim, source: Dictionary) -> float:
	return outgoing_scale(sim, source) - 1.0

static func breakthrough_scale(sim, source: Dictionary) -> float:
	if source.get("kind") != "unit": return 1.0
	if float(source.get("breakthrough_ready_until", 0.0)) <= sim.time: return 1.0
	var config: Dictionary = traits(sim, source)
	source.breakthrough_ready_until = 0.0
	return 1.0 + float(config.get("breakthrough_damage_bonus", 0.0))

static func apply_emp(sim, target_id: int, weapon: Dictionary, source_team: int) -> void:
	if not sim.entities.has(target_id): return
	var target: Dictionary = sim.entities[target_id]
	if float(target.hp) <= 0.0 or int(target.team) == source_team or sim.Transport.is_loaded(target): return
	var duration: float = 0.0
	if target.kind == "building":
		duration = float(weapon.get("emp_building_duration", 0.0))
	elif str(sim.data_for(target.spec).get("armor_class", "")) == "armored":
		duration = float(weapon.get("emp_vehicle_duration", 0.0))
	if duration > 0.0:
		target.emp_until = maxf(float(target.get("emp_until", 0.0)), sim.time + duration)
		sim.events.append({"kind":"emp", "id":target_id, "pos":target.pos, "team":target.team})
