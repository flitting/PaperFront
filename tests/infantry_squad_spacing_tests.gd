extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
const Squads = preload("res://scripts/infantry_squads.gd")
var checks: int = 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _initialize() -> void:
	var sim = Sim.new()
	sim.setup(RulesLoader.load_rules(), "dev", 47, "kestrel", false)
	for z: int in range(sim.map.size):
		for x: int in range(sim.map.size): sim.map.terrain[z][x] = 0; sim.map.heights[z][x] = 0
	sim.mines.clear(); sim.bridges.clear(); sim.ruins.clear()
	sim._refresh_ruin_spatial(); sim._refresh_mine_spatial(); sim._prepare_terrain_cache()
	sim._nav_dirty = true
	var leaders: Array = []
	var all: Array = []
	for p: Vector2 in [Vector2(12,12), Vector2(12,20), Vector2(21,12), Vector2(21,20)]:
		var id: int = sim.debug_spawn_squad(0, "kestrel_rifle", p)
		leaders.append(id)
		all.append_array(sim.squad_members(id))
	check(all.size() == 20, "four complete squads retain twenty independent soldiers")
	check(is_equal_approx(Squads.member_spacing(.5), 1.08), "half-metre bodies leave eight centimetres between members")
	for leader: int in leaders:
		var members: Array = sim.squad_members(leader)
		check(is_equal_approx(sim.entities[members[0]].pos.distance_to(sim.entities[members[1]].pos), 1.08), "authored members spawn in the same tight formation")
	sim.issue(leaders, "move", Vector2(29,29))
	var destinations: Dictionary = {}
	for id: int in all: destinations[id] = sim.entities[id].commands[0].pos
	var minimum_gap: float = INF
	var minimum_own: float = INF
	var clear: bool = true
	for a: int in all:
		for b: int in all:
			if b <= a: continue
			var distance: float = destinations[a].distance_to(destinations[b])
			clear = clear and distance >= sim._radius(sim.entities[a]) + sim._radius(sim.entities[b]) + .02
			if int(sim.entities[a].squad_id) == int(sim.entities[b].squad_id): minimum_own = minf(minimum_own, distance)
			else: minimum_gap = minf(minimum_gap, distance - sim._radius(sim.entities[a]) - sim._radius(sim.entities[b]))
	check(clear, "all assigned compact destinations have valid body clearance")
	check(is_equal_approx(minimum_own, 1.08), "command destination reservations preserve close squad members")
	check(minimum_gap >= 1.999, "different squad body edges retain at least 2.0 metres of open space")
	for tick: int in range(1200):
		sim.step(.05)
		if all.all(func(id): return sim.entities[id].commands.is_empty() and sim.entities[id].pos.distance_to(destinations[id]) <= .26 and not (sim.entities[id].get("yield_goal", Vector2.INF) as Vector2).is_finite()): break
	var pending: Array = all.filter(func(id): return not sim.entities[id].commands.is_empty())
	check(pending.is_empty(), "all twenty members reach separate compact parking slots")
	var max_error: float = 0.0
	var actual_gap: float = INF
	var actual_clear: bool = true
	for a: int in all:
		max_error = maxf(max_error, sim.entities[a].pos.distance_to(destinations[a]))
		for b: int in all:
			if b <= a: continue
			var distance: float = sim.entities[a].pos.distance_to(sim.entities[b].pos)
			actual_clear = actual_clear and distance >= .939
			if int(sim.entities[a].squad_id) != int(sim.entities[b].squad_id): actual_gap = minf(actual_gap, distance - 1.0)
	check(max_error <= .26, "actual movement retains each assigned squad block")
	check(actual_clear, "tight squad movement retains the existing collision clearance")
	check(actual_gap >= 1.49, "settled squads keep at least 1.5 metres after arrival tolerance")
	sim.issue(leaders, "move", Vector2(20,20))
	var return_goals: Dictionary = {}
	for id: int in all: return_goals[id] = sim.entities[id].commands[0].pos
	for tick: int in range(1200):
		sim.step(.05)
		if all.all(func(id): return sim.entities[id].commands.is_empty() and sim.entities[id].pos.distance_to(return_goals[id]) <= .26 and not (sim.entities[id].get("yield_goal", Vector2.INF) as Vector2).is_finite()): break
	check(all.all(func(id): return sim.entities[id].pos.distance_to(return_goals[id]) <= .26), "squads can reverse direction and settle without members crossing their parked formation")
	sim.issue(leaders, "stop", Vector2.ZERO)
	check(all.all(func(id): return not sim.entities[id].has("squad_formation_goal")), "explicit stop cancels regrouping for every squad member")
	print("SQUAD_SPACING ", JSON.stringify({"checks":checks,"failures":failures,"pending":pending,"max_error":max_error,"assigned_gap":minimum_gap,"actual_gap":actual_gap}))
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
