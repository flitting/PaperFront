extends RefCounted
const Orientation=preload("res://scripts/building_orientation.gd")

## Placement preserves the same doorway used by production, for human and AI.
static func ground_producer(info: Dictionary) -> bool:
	return str(info.get("role", "")) in ["factory", "refinery", "barracks", "repair"] or "barracks" in info.get("production_roles", [])

static func corridor(sim, info: Dictionary, pos: Vector2, turns: int = 0) -> Rect2:
	var half: float = float(info.size) * .5
	var radius: float = 1.0 if str(info.get("role", "")) in ["factory", "refinery", "repair"] else .5
	var distance: float = radius*2+.25
	if str(info.get("faction", "")) == "iron" and str(info.get("role", "")) in ["factory", "refinery", "repair"]: distance = maxf(distance,2.6)
	return Orientation.rectangle(pos,Rect2(Vector2(-radius-.1,half),Vector2(radius*2+.2,distance)),turns)

static func site_error(sim, info: Dictionary, pos: Vector2, turns: int = 0) -> String:
	if sim.RailNetwork.is_rail(info): return ""
	var half: float = float(info.size) * .5
	var footprint: Rect2 = Rect2(pos-Vector2.ONE*half,Vector2.ONE*float(info.size))
	for existing in sim._building_entities:
		if float(existing.hp) <= 0: continue
		var other: Dictionary = sim.data_for(existing.spec)
		if ground_producer(other) and footprint.intersects(corridor(sim, other, existing.pos,Orientation.quarters(existing))):
			return "建筑占用已有生产设施的中央出厂通道"
	if ground_producer(info):
		var radius: float = 1.0 if str(info.get("role", "")) in ["factory", "refinery", "repair"] else .5
		var exit: Vector2 = pos + Orientation.offset(Vector2(0,half+radius+.15),turns)
		if not sim._standing(exit, radius, -1, false): return "生产设施中央门外没有合法出厂空间"
		var reserved: Rect2 = corridor(sim, info, pos,turns)
		for existing in sim._building_entities:
			if float(existing.hp) <= 0 or sim.RailNetwork.is_rail(sim.data_for(existing.spec)): continue
			var size: float = float(sim.data_for(existing.spec).size)
			if reserved.intersects(Rect2(existing.pos-Vector2.ONE*size*.5,Vector2.ONE*size)):
				return "生产设施中央出厂通道被建筑占用"
	return ""
