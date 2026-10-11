extends RefCounted

## Old rule snapshots without penetration retain their original damage model.
static func weapon(sim, info: Dictionary) -> Dictionary:
	var base: Dictionary=sim.rules.weapons.get(str(info.get("weapon","")),{})
	if base.is_empty(): return info
	var merged: Dictionary=base.duplicate()
	merged.merge(info,true)
	return merged

static func armor(sim,target: int) -> float:
	var entity: Dictionary=sim.entities.get(target,{})
	return sim.armor_for(entity) if not entity.is_empty() else 0.0

static func penetration_factor(info: Dictionary,protection: float,falloff: float=1.0, model: Dictionary={}) -> float:
	if not info.has("penetration"): return 1.0
	if protection<=0.0 and model.has("partial_penetration_threshold"): return 1.0
	var effective: float = float(info.penetration)*falloff
	if effective>protection: return 1.0
	# Saved matches without the optional partial band retain their two-stage
	# damage model. Native firing also resolves damage through this method.
	if model.has("partial_penetration_threshold") and effective>=protection*float(model.partial_penetration_threshold):
		return float(model.get("partial_penetration_damage_multiplier",0.5))
	return float(model.get("non_penetrating_damage_multiplier",0.25))

static func distance_to_body(sim,center: Vector2,entity: Dictionary) -> float:
	if entity.kind=="building":
		var half: Vector2=Vector2.ONE*float(sim.data_for(entity.spec).size)*.5
		return distance_to_rectangle(center,entity.pos,half)
	return maxf(0.0,center.distance_to(entity.pos)-sim._radius(entity))

static func distance_to_rectangle(center: Vector2,position: Vector2,half: Vector2) -> float:
	return ((center-position).abs()-half).max(Vector2.ZERO).length()

static func falloff(info: Dictionary,distance: float,radius: float) -> float:
	if radius<=0 or info.get("aoe_falloff","")!="linear": return 1.0
	return clampf(1.0-distance/radius,0.0,1.0)

static func damage(sim,base: float,target: int,multipliers: Dictionary,info: Dictionary,factor: float=1.0) -> float:
	return sim._scaled_damage(base,target,multipliers)*factor*penetration_factor(info,armor(sim,target),factor,sim.rules.get("combat_model",{}))
