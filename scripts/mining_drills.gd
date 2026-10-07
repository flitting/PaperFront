extends RefCounted

## Drills reserve the original ore object, including while scaffolding is built.
static func mine_index(sim, pos: Vector2) -> int:
	var best: int = -1
	var distance: float = 0.76
	for i in range(sim.mines.size()):
		var current: float = pos.distance_to(sim.mines[i].pos)
		if current < distance: best = i; distance = current
	return best

static func site_error(sim, team: int, pos: Vector2, builder: int) -> String:
	if builder >= 0 and not sim._builder_valid(team, builder): return "采矿钻机需要己方武装工兵施工"
	var index: int = mine_index(sim, pos)
	if index < 0: return "钻机必须直接建立在矿脉上"
	var mine: Dictionary = sim.mines[index]
	pos = mine.pos
	var footprint: float = float(sim.data_for("rivet_drill").size) * .5
	if int(mine.get("drill", -1)) > 0 and sim.entities.has(int(mine.drill)): return "矿脉已被钻机占用"
	if bool(sim._eco("finite_ore", false)) and float(mine.amount) <= 0: return "矿脉已经耗尽"
	var level: float = sim._height(pos)
	for x in [-footprint+.01, footprint-.01]:
		for y in [-footprint+.01, footprint-.01]:
			var point: Vector2 = pos + Vector2(x,y)
			if not sim._land(point) or sim.bridge_at(point) >= 0 or sim._terrain(point) == 2 or absf(sim._height(point)-level) > .05: return "钻机需要合法平坦陆地矿脉"
	for i in range(sim.mines.size()):
		if i != index and sim._circle_rect(sim.mines[i].pos,.55,pos,Vector2.ONE*footprint): return "钻机不能同时覆盖多个矿脉"
	for other in sim.entities.values():
		if float(other.hp) <= 0 or int(other.id) == builder or sim.Transport.is_loaded(other): continue
		if other.kind == "building":
			var half: float = float(sim.data_for(other.spec).size) * .5
			if absf(other.pos.x-pos.x) < half+footprint and absf(other.pos.y-pos.y) < half+footprint: return "建筑占地与已有建筑重叠"
		elif not sim._is_air(other) and sim._circle_rect(other.pos, sim._radius(other), pos, Vector2.ONE*footprint): return "单位占据建筑位置"
	for ruin in sim._nearby_ruins(pos, footprint):
		if float(ruin.hp) > 0 and absf(ruin.pos.x-pos.x) < footprint+ruin.half.x and absf(ruin.pos.y-pos.y) < footprint+ruin.half.y: return "钻机位置有废墟障碍"
	return ""

static func claim(sim, drill: Dictionary) -> void:
	var index: int = mine_index(sim, drill.pos)
	drill.drill_mine = index
	if index < 0: return
	var mine: Dictionary = sim.mines[index]
	mine.drill = int(drill.id)
	mine.miner = -1
	for unit in sim.entities.values():
		if unit.kind == "unit" and int(unit.get("harvest_mine", -1)) == index:
			unit.harvest_mine = -1
			unit.mining_goal = Vector2.INF
			unit.path.clear()
			unit.path_goal = Vector2.INF

static func release(sim, drill: Dictionary) -> void:
	var index: int = int(drill.get("drill_mine", -1))
	if index >= 0 and index < sim.mines.size() and int(sim.mines[index].get("drill", -1)) == int(drill.id):
		sim.mines[index].drill = -1
		# Never assign amount/capacity or create an ore object here.

static func step(sim, drill: Dictionary, delta: float) -> void:
	var index: int = int(drill.get("drill_mine", -1))
	if index < 0 or index >= sim.mines.size(): drill.state = "waiting"; return
	if float(drill.construct_remaining) > 0 or sim.building_low_power(drill): drill.state = "waiting"; return
	var mine: Dictionary = sim.mines[index]
	var earned: float = float(sim._eco("drill_income_rate", 16)) * delta
	if bool(sim._eco("finite_ore", false)):
		earned = minf(earned, float(mine.amount))
		mine.amount = maxf(0, float(mine.amount) - earned)
	sim.money[int(drill.team)] += earned
	sim.statistics.add(int(drill.team), "funds_earned", earned)
	drill.drill_work = float(drill.get("drill_work", 0)) + delta
	drill.state = "harvest" if earned > 0 else "waiting"

static func ai_build(sim, team: int) -> void:
	if not sim.order_for_team(team, "normal").is_empty(): return
	var builder: int = -1
	for unit in sim.entities.values():
		if unit.team == team and unit.kind == "unit" and str(unit.spec) == "rivet_engineer" and unit.commands.is_empty(): builder = int(unit.id); break
	if builder < 0 or sim.money[team] < float(sim.data_for("rivet_drill").cost): return
	var ranked: Array = []
	for mine in sim.mines:
		if int(mine.get("drill", -1)) > 0: continue
		ranked.append(mine)
	ranked.sort_custom(func(a,b): return (a.pos as Vector2).distance_squared_to(sim.entities[builder].pos) < (b.pos as Vector2).distance_squared_to(sim.entities[builder].pos))
	for mine in ranked:
		var point: Vector2 = Vector2(floorf(mine.pos.x)+.5, floorf(mine.pos.y)+.5)
		if not site_error(sim, team, point, builder).is_empty(): continue
		if sim.build(team, "rivet_drill", builder).is_empty(): sim.place_building(team, point, "normal")
		return
