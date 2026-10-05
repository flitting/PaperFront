extends RefCounted

## Authoritative per-team sight and last observed enemy positions.
## Terrain and ore are shared map knowledge; units and buildings require sight.
static func initialize(sim) -> void:
	sim.team_vision = {"last_known": []}
	for team in range(sim.factions.size()): sim.team_vision.last_known.append({})
	sim._vision_observers = []
	sim._vision_next_refresh = 0.0
	refresh(sim, true)

static func position_visible(sim, team: int, pos: Vector2, domain: String = "ground") -> bool:
	if not sim.vision_enabled: return true
	if team < 0 or team >= sim.factions.size() or not pos.is_finite(): return false
	if team >= sim._vision_observers.size(): return false
	var bucket: Vector2i = Vector2i(floori(pos.x / 16.0), floori(pos.y / 16.0))
	for observer in sim._vision_observers[team].get(bucket, []):
		if (observer.pos as Vector2).distance_squared_to(pos) > float(observer.radius_sq): continue
		if bool(observer.air) or domain == "air" or _terrain_line(sim, observer.pos, pos, float(observer.eye_height), domain): return true
	return false

static func refresh(sim, force: bool = false) -> void:
	if not force and sim.time + 0.000001 < sim._vision_next_refresh:
		_sync_contacts(sim)
		return
	sim._vision_next_refresh = sim.time + 0.2
	_build_observers(sim)
	var all_bits: int = (1 << sim.factions.size()) - 1
	var known: Array = sim.team_vision.get("last_known", [])
	while known.size() < sim.factions.size(): known.append({})
	sim.team_vision.last_known = known
	for e in sim.entities.values():
		var bits: int = all_bits if not sim.vision_enabled else 1 << int(e.team)
		if sim.vision_enabled and float(e.hp) > 0.0 and not sim.Transport.is_loaded(e):
			var domain: String = str(sim.data_for(e.spec).get("domain", "ground"))
			for team in range(sim.factions.size()):
				if team == int(e.team): continue
				if position_visible(sim, team, e.pos, domain):
					bits |= 1 << team
					known[team][int(e.id)] = {"pos": e.pos, "seen_at": sim.time, "spec": e.spec, "kind": e.kind, "domain": domain}
		e.visible_to = bits
	if sim.vision_enabled:
		for team in range(sim.factions.size()):
			for id in known[team].keys():
				var record: Dictionary = known[team][id]
				if not sim.entities.has(id) or not bool(int(sim.entities[id].get("visible_to", 0)) & (1 << team)):
					if position_visible(sim, team, record.pos, str(record.get("domain", "ground"))): known[team].erase(id)
	_sync_contacts(sim)

static func _build_observers(sim) -> void:
	sim._vision_observers = []
	for team in range(sim.factions.size()): sim._vision_observers.append({})
	if not sim.vision_enabled: return
	for e in sim.entities.values():
		if float(e.hp) <= 0.0 or sim.Transport.is_loaded(e): continue
		var team: int = int(e.team)
		var spec: Dictionary = sim.data_for(e.spec)
		var domain: String = str(spec.get("domain", "ground"))
		var radius: float = float(spec.get("vision_radius", 14.0 if domain == "air" else (12.0 if e.kind == "building" else (11.0 if domain == "naval" else 9.0))))
		var surface: float=MapData.entity_surface_y(sim.map,e.pos,domain)
		var record: Dictionary = {"pos":e.pos, "radius_sq":radius*radius, "air":domain=="air", "eye_height":surface+(2.5 if e.kind=="building" or domain=="naval" else 1.6)}
		var first: Vector2i = Vector2i(floori((e.pos.x-radius)/16.0),floori((e.pos.y-radius)/16.0))
		var last: Vector2i = Vector2i(floori((e.pos.x+radius)/16.0),floori((e.pos.y+radius)/16.0))
		var buckets: Dictionary=sim._vision_observers[team]
		for z in range(first.y,last.y+1):
			for x in range(first.x,last.x+1):
				var key:=Vector2i(x,z)
				if not buckets.has(key):buckets[key]=[]
				buckets[key].append(record)

static func _sync_contacts(sim) -> void:
	var all_bits: int=(1<<sim.factions.size())-1
	sim._contact_visibility.resize(sim._contact_ids.size())
	for slot in range(sim._contacts_used):
		var id: int = int(sim._contact_ids[slot])
		sim._contact_visibility[slot] = int(sim.entities[id].get("visible_to", all_bits)) if sim.entities.has(id) else 0

static func _terrain_line(sim, origin: Vector2, target: Vector2, start_height: float, target_domain: String) -> bool:
	var length: float = origin.distance_to(target)
	var steps: int = maxi(1, ceili(length / 1.5))
	var end_height: float = MapData.entity_surface_y(sim.map,target,target_domain) + (2.5 if target_domain=="naval" else 1.0)
	for index in range(1, steps):
		var t: float = float(index) / float(steps)
		var point: Vector2=origin.lerp(target,t)
		var terrain_height: float=MapData.water_surface_y(sim.map,point) if MapData.terrain_at(sim.map,point)==1 else MapData.height_at(sim.map,point)
		if terrain_height > lerpf(start_height, end_height, t) + 0.2: return false
	return true
