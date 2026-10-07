extends RefCounted

## A channel tracks its target and settles damage over simulation time.
static func begin(sim, source: Dictionary, target: int, weapon_id: String, force: bool) -> void:
	var weapon: Dictionary = sim.rules.weapons[weapon_id]
	source.beam = {"target":target, "weapon":weapon_id, "remaining":float(weapon.get("beam_duration", 1.8)), "force":force}

static func step(sim, delta: float) -> void:
	for source in sim.entities.values():
		var channel: Dictionary = source.get("beam", {})
		if channel.is_empty(): continue
		var target: int = int(channel.target)
		var weapon: Dictionary = sim.weapon_for(source,str(channel.weapon))
		if weapon.is_empty() or not sim._target_alive(target) or float(source.hp) <= 0 or float(source.get("emp_until", 0)) > sim.time or sim.Transport.is_loaded(source) or (sim._is_air(source) and not bool(source.get("airborne", true))) or not sim._weapon_can_target(source, target, bool(channel.force)) or (source.pos as Vector2).distance_to(sim._target_position(target)) > float(weapon.range):
			source.erase("beam"); continue
		var applied: float = minf(delta, float(channel.remaining))
		var amount: float = float(weapon.damage) * applied / float(weapon.get("beam_duration", 1.8))
		amount *= sim.FactionSupport.damage_scale(sim, source, target)
		sim._add_damage(target, sim._weapon_damage(amount,target,weapon), bool(channel.force), {"source":int(source.id), "source_team":int(source.team), "weapon":str(channel.weapon), "explosive":false})
		sim.FactionTraits.record_attack(sim, source)
		channel.remaining = maxf(0, float(channel.remaining)-applied)
		if float(channel.remaining) <= 0: source.erase("beam")
