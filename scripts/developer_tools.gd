extends RefCounted

## These tools belong exclusively to the live developer match and its in-window
## debug panel. The switch is deliberately absent from ordinary match options.
static func enabled(sim) -> bool:
	return sim != null and str(sim.map.get("mode", "")) == "dev" and bool(sim.match_options.get("developer_debug_enabled", false))

static func instant_enabled(sim) -> bool:
	return enabled(sim) and bool(sim.match_options.get("developer_instant_build", false))

## Only removes waiting time. Existing placement, costs, engineer approach,
## production exits, aircraft capacity and railway checks still run normally.
static func finish_pending(sim, team: int = 0) -> void:
	if not instant_enabled(sim) or team < 0 or team >= sim.factions.size(): return
	for channel: String in ["normal", "defense"]:
		var order: Dictionary = sim.order_for_team(team, channel)
		if not order.is_empty() and not bool(order.get("ready", false)):
			sim.BuildingConstruction.advance(sim, team, channel, maxf(1.0,float(order.get("remaining",0.0))), 1.0)
	for building: Dictionary in sim._building_entities.duplicate():
		if int(building.team) != team or float(building.hp) <= 0.0: continue
		if building.has("construction"):
			# Scaffold completion keeps its genuine work order, proximity and
			# repair/payment requirements; an absent engineer cannot finish it.
			sim.Construction.step(sim, building, float(sim.data_for(building.spec).build_time) + 100000.0)
		elif float(building.construct_remaining) > 0.0:
			# The ordinary building step emits deployment and invalidates caches.
			building.construct_remaining = minf(float(building.construct_remaining), 0.000001)
		if not building.queue.is_empty():
			building.queue[0].remaining = 0.0
			building.queue[0].progress = 1.0
			building.queue[0].ready = true

static func _priority(info: Dictionary) -> int:
	var roles: Array = ["hq","outpost","refinery","factory","barracks","repair","tech","airfield","power","drill","shipyard","tower","wall","barricade","rail","rail_junction"]
	var index: int = roles.find(str(info.get("role", "")))
	return index if index >= 0 else 99

static func _owned(sim, team: int, spec: String) -> int:
	for building: Dictionary in sim._building_entities:
		if int(building.team) == team and str(building.spec) == spec and float(building.hp) > 0.0 and float(building.construct_remaining) <= 0.0: return int(building.id)
	return -1

static func _gap_clear(sim, info: Dictionary, pos: Vector2) -> bool:
	if sim.RailNetwork.is_rail(info): return true
	var half: float = float(info.size) * .5
	for building: Dictionary in sim._building_entities:
		var other: Dictionary = sim.data_for(building.spec)
		if float(building.hp) <= 0 or sim.RailNetwork.is_rail(other): continue
		var other_half: float = float(other.size) * .5
		if absf(building.pos.x-pos.x) < half+other_half+2.0 and absf(building.pos.y-pos.y) < half+other_half+2.0: return false
	return true

static func _candidate_points(sim, team: int, info: Dictionary) -> Array[Vector2]:
	var points: Array[Vector2] = []
	if str(info.get("role", "")) == "drill":
		for mine: Dictionary in sim.mines: points.append(mine.pos)
	elif str(info.get("role", "")) == "shipyard":
		for y: int in range(70,88,2):
			for x: int in range(34,66,2): points.append(Vector2(x,y))
	else:
		var bounds: Array = sim.map.get("developer_showcase_regions",[[3,31,38,36],[59,31,38,36]])[team % 2]
		var half: float = float(info.size) * .5
		for y: int in range(int(bounds[1]), int(bounds[1])+int(bounds[3])):
			for x: int in range(int(bounds[0]), int(bounds[0])+int(bounds[2])):
				var point := Vector2(x+half,y+half)
				if point.x+half > float(bounds[0])+float(bounds[2]) or point.y+half > float(bounds[1])+float(bounds[3]): continue
				# Keep the approach to the bridge and the naval shoreline open.
				if Rect2(point-Vector2.ONE*half,Vector2.ONE*float(info.size)).intersects(Rect2(28 if team == 0 else 56,48,16,8)): continue
				points.append(point)
	var start: Array = sim.map.starts[team]
	var target := Vector2(float(start[0]),float(start[1]))
	if str(info.get("role", "")) == "outpost": target += Vector2(13 if team == 0 else -13,-13)
	if str(info.get("role", "")) == "refinery": target = Vector2(12.5 if team == 0 else 87.5,59)
	if str(info.get("role", "")) == "shipyard": target = Vector2(36 if team == 0 else 64,72)
	points.sort_custom(func(a: Vector2,b: Vector2): return a.distance_squared_to(target) < b.distance_squared_to(target))
	return points

static func _place_one(sim, team: int, spec: String) -> Dictionary:
	var info: Dictionary = sim.data_for(spec)
	var last_error: String = "没有足够的平地与两格通道"
	var turns_count: int = 4 if str(info.get("role","")) in ["shipyard","airfield"] or sim.ProductionClearance.ground_producer(info) else 1
	for point: Vector2 in _candidate_points(sim,team,info):
		if not _gap_clear(sim,info,point): continue
		for turns: int in range(turns_count):
			var problem: String = sim._building_site_error(team,info,point,-1,turns)
			if not problem.is_empty():
				last_error = problem
				continue
			var id: int = sim._spawn(team,spec,point,true,turns)
			if id < 0: continue
			sim.entities[id].gift_pending = false
			sim._invalidate_base_cache()
			return {"id":id,"spec":spec,"pos":point,"rotation_quarters":turns}
	return {"spec":spec,"error":last_error}

## Spawn catalog models without charging the player, but validate every actual
## footprint, mine claim, dock channel and production doorway before spawning.
static func generate_all_buildings(sim, team: int = 0) -> Dictionary:
	var report: Dictionary = {"created":[],"existing":[],"failed":[],"support":[]}
	if not enabled(sim) or team < 0 or team >= sim.factions.size():
		report.failed.append({"spec":"debug","error":"此工具仅在启用调试的开发试验场可用"})
		return report
	var specs: Array[String] = []
	for spec: String in sim.rules.buildings:
		if str(sim.rules.buildings[spec].get("faction", "")) == str(sim.factions[team]): specs.append(spec)
	specs.sort_custom(func(a: String,b: String):
		var pa: int = _priority(sim.data_for(a))
		var pb: int = _priority(sim.data_for(b))
		return pa < pb if pa != pb else float(sim.data_for(a).size) > float(sim.data_for(b).size))
	for spec: String in specs:
		var existing: int = _owned(sim,team,spec)
		if existing >= 0:
			report.existing.append({"spec":spec,"id":existing})
			continue
		var placed: Dictionary = _place_one(sim,team,spec)
		if placed.has("error"): report.failed.append(placed)
		else: report.created.append(placed)
	# Supply the real consumer load so every catalog facility can be exercised.
	for index: int in range(12):
		var power: Vector2 = sim.power(team)
		if power.x >= power.y: break
		var placed: Dictionary = _place_one(sim,team,sim.building_spec(team,"power"))
		if placed.has("error"):
			report.failed.append({"spec":"power_support","error":placed.error})
			break
		report.support.append(placed)
	# Iron factories need their actual exit track. Refinery auto-routing uses
	# the same legal railway graph; no force-spawn or fake production is used.
	if str(sim.factions[team]) == "iron":
		for building: Dictionary in sim._building_entities.duplicate():
			if int(building.team) != team or str(sim.data_for(building.spec).get("role", "")) not in ["factory","refinery","repair"]: continue
			sim._rail_network.auto_refinery(sim,building)
		sim._rail_network.rebuild(sim)
	sim._nav_dirty = true
	sim._rebuild_nav()
	sim._rebuild_spatial()
	return report

static func report_text(sim, report: Dictionary) -> String:
	var message: String = "建筑目录：新增 %d，已有 %d，供电补充 %d，失败 %d。" % [report.created.size(),report.existing.size(),report.support.size(),report.failed.size()]
	for failure: Dictionary in report.failed:
		message += "\n%s：%s" % [str(sim.data_for(str(failure.spec)).get("name",failure.spec)),str(failure.error)]
	return message
