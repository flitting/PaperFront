extends SceneTree

# Headless navigation diagnostics. Coordinate this process with other sessions
# before running it; use an external process timeout as a final shutdown guard.
#   godot --headless --path . --script tools/profile_navigation_throughput.gd -- \
#     --units=448 --ticks=900 --max-wall-seconds=30 --output=/tmp/nav-current.json
#   ... --baseline --output=/tmp/nav-baseline.json
#   ... --baseline-worker-only --output=/tmp/nav-worker-control.json
#   ... --realtime --no-route-cache --output=/tmp/nav-cache-control.json
# The frozen sources are compiled anonymously in memory. This avoids registering
# their old class_name declarations alongside the live project classes.

const Sim = preload("res://scripts/simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
const FROZEN_ROOT = "res://artifacts/free_navigation_performance_20261006/baseline/"
const STEP: float = 1.0 / 30.0

class TrackedWorker:
	extends RefCounted
	var backend
	var pending: Dictionary = {}
	var records: Array[Dictionary] = []
	var worker_us: Array[float] = []
	var queue_to_collect_ms: Array[float] = []
	var submitted: int = 0
	var collected: int = 0
	var route_cache_enabled: bool = true
	var terrain_snapshot: Dictionary = {}
	func _init(value, cache_enabled: bool = true) -> void:
		backend = value
		route_cache_enabled = cache_enabled
	func start(data: Dictionary) -> void:
		var worker_data: Dictionary = data.duplicate()
		worker_data["route_cache_enabled"] = route_cache_enabled
		terrain_snapshot = data.duplicate(true)
		backend.start(worker_data)
	func submit(job: Dictionary) -> bool:
		if not backend.submit(job): return false
		pending[int(job.token)] = {"job":job.duplicate(), "submitted_us":Time.get_ticks_usec()}
		submitted += 1
		return true
	func collect() -> Array[Dictionary]:
		var results: Array[Dictionary] = backend.collect()
		var now: int = Time.get_ticks_usec()
		for result in results:
			collected += 1
			worker_us.append(float(result.worker_us))
			var metadata: Dictionary = pending.get(int(result.token), {})
			if not metadata.is_empty():
				queue_to_collect_ms.append(float(now-int(metadata.submitted_us))/1000.0)
				# Retain all first-burst routes and a bounded number of replans for
				# safety inspection after timing, outside the measured tick.
				if records.size() < 4096:
					var record: Dictionary = result.duplicate()
					# Simulation owns and consumes result.path in place. Keep a
					# separate immutable route for later start-to-goal inspection.
					record.path = (result.path as Array).duplicate()
					record.job = metadata.job
					record.collected_us = now
					records.append(record)
			pending.erase(int(result.token))
		return results
	func invalidate(revision: int) -> void:
		if backend.has_method("invalidate"): backend.invalidate(revision)
	func close() -> void:
		backend.close()
		pending.clear()

class ProbeSim:
	extends "res://scripts/simulation.gd"
	var _throughput_worker_factory: Callable
	func _create_path_worker():
		return _throughput_worker_factory.call()

var errors: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func _options() -> Dictionary:
	var result: Dictionary = {"units":448, "ticks":900, "max-wall-seconds":30.0,
		"yield-us":1000, "command":"move", "output":"/tmp/paper_war_navigation_throughput.json",
		"baseline":false, "baseline-worker-only":false, "baseline-worker":"", "baseline-sim":"",
		"realtime":false, "no-route-cache":false, "all-route-safety":false}
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var index: int = 0
	while index < args.size():
		var argument: String = args[index]
		if argument.begins_with("--"):
			var parts: PackedStringArray = argument.substr(2).split("=", true, 1)
			var key: String = parts[0]
			if key in ["baseline", "baseline-worker-only", "realtime", "no-route-cache", "all-route-safety"]:
				result[key] = true
			elif result.has(key):
				if parts.size() > 1: result[key] = parts[1]
				elif index+1 < args.size():
					index += 1
					result[key] = args[index]
		index += 1
	result.units = maxi(2, int(result.units))
	result.ticks = maxi(1, int(result.ticks))
	result["max-wall-seconds"] = clampf(float(result["max-wall-seconds"]), .5, 120.0)
	result["yield-us"] = maxi(100, int(result["yield-us"]))
	if bool(result.baseline): result["baseline-sim"] = FROZEN_ROOT+"simulation.gd"
	if bool(result.baseline) or bool(result["baseline-worker-only"]):
		if str(result["baseline-worker"]).is_empty(): result["baseline-worker"] = FROZEN_ROOT+"path_worker.gd"
	return result

func _anonymous_script(path: String, inject_factory: bool = false) -> GDScript:
	if not FileAccess.file_exists(path):
		errors.append("Missing frozen script: "+path)
		return null
	var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
	var anonymous: PackedStringArray = []
	for line in lines:
		if not line.strip_edges().begins_with("class_name "): anonymous.append(line)
	var source: String = "\n".join(anonymous)
	if inject_factory:
		var original: String = "func _create_path_worker():\n\treturn PATH_WORKER.new()"
		if not source.contains(original):
			errors.append("Frozen simulation worker factory does not match the supported fixture injection: "+path)
			return null
		source = source.replace(original, "func _create_path_worker():\n\treturn _throughput_worker_factory.call()")
		source += "\nvar _throughput_worker_factory: Callable\n"
	var script := GDScript.new()
	script.source_code = source
	var status: int = script.reload()
	if status != OK:
		errors.append("Cannot compile frozen script %s (error %d)" % [path,status])
		return null
	return script

func _pool_script() -> GDScript:
	# A worker-only control keeps the current pool's parallelism, queue limits,
	# and distribution policy. Only its leaf search implementation is replaced.
	var source: String = FileAccess.get_file_as_string("res://scripts/path_worker_pool.gd")
	var original: String = "const Worker = preload(\"res://scripts/path_worker.gd\")"
	if not source.contains(original):
		errors.append("Live worker pool does not expose the supported leaf-worker injection")
		return null
	var lines: PackedStringArray = source.split("\n")
	var anonymous: PackedStringArray = []
	for line in lines:
		if not line.strip_edges().begins_with("class_name "): anonymous.append(line)
	source = "\n".join(anonymous).replace(original,"var _throughput_worker_script: GDScript")
	source = source.replace("Worker.new()","_throughput_worker_script.new()")
	source = source.replace("\tfor worker in _workers: worker.invalidate(revision)",
		"\tfor worker in _workers:\n\t\tif worker.has_method(\"invalidate\"): worker.invalidate(revision)")
	var script := GDScript.new()
	script.source_code = source
	if script.reload() != OK:
		errors.append("Cannot compile anonymous worker pool for the leaf-worker control")
		return null
	return script

func _make_worker(script: GDScript, cache_enabled: bool, pool_script: GDScript):
	var backend
	if script == null: backend = Sim.PATH_WORKER.new()
	elif pool_script == null: backend = script.new()
	else:
		backend = pool_script.new()
		backend._throughput_worker_script = script
	return TrackedWorker.new(backend,cache_enabled)

func _new_sim(config: Dictionary, mode: String, seed_value: int, options: Dictionary):
	var worker_script: GDScript = null
	if not str(options.get("baseline-worker", "")).is_empty():
		worker_script = _anonymous_script(str(options["baseline-worker"]))
		if worker_script == null: return null
	var pool_script: GDScript = null
	if worker_script != null and str(options.get("baseline-sim", "")).is_empty():
		pool_script = _pool_script()
		if pool_script == null: return null
	var sim
	if not str(options.get("baseline-sim", "")).is_empty():
		var script: GDScript = _anonymous_script(str(options["baseline-sim"]), true)
		if script == null: return null
		sim = script.new()
	else:
		sim = ProbeSim.new()
	sim._throughput_worker_factory = Callable(self, "_make_worker").bind(worker_script,not bool(options.get("no-route-cache",false)),pool_script)
	sim.setup(config, mode, seed_value, "rivet", false)
	sim.money.assign([100000.0,100000.0])
	return sim

func _percentiles(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {"samples":0}
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	var total: float = 0.0
	for value in values: total += value
	return {"samples":values.size(), "mean":total/values.size(),
		"p50":sorted[mini(sorted.size()-1,int(sorted.size()*.50))],
		"p95":sorted[mini(sorted.size()-1,int(sorted.size()*.95))],
		"p99":sorted[mini(sorted.size()-1,int(sorted.size()*.99))], "max":sorted.back()}

func _constant(sim, name: String, fallback: int) -> int:
	var script: Script = sim.get_script()
	while script != null:
		var constants: Dictionary = script.get_script_constant_map()
		if constants.has(name): return int(constants[name])
		script = script.get_base_script()
	return fallback

func _oracle_height(data: Dictionary, point: Vector2) -> float:
	var size: int = int(data.size)
	var x: int = clampi(floori(point.x),0,size-1)
	var z: int = clampi(floori(point.y),0,size-1)
	var height: float = float(data.heights[z*size+x])
	if int(data.terrain[z*size+x]) == 2:
		var fraction: float = point.y-(z+.5)
		var next_z: int = z+(1 if fraction>=0.0 else -1)
		if next_z>=0 and next_z<size:
			var next_height: float = float(data.heights[next_z*size+x])
			if absf(next_height-height)<=.75: height=lerpf(height,next_height,absf(fraction))
	return height

func _oracle_terrain(data: Dictionary, point: Vector2, radius: float) -> Dictionary:
	var size: int = int(data.size)
	var center_height: float = _oracle_height(data,point)
	for offset: Vector2 in [Vector2.ZERO,Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN,Vector2(.707,.707),Vector2(-.707,.707),Vector2(.707,-.707),Vector2(-.707,-.707)]:
		var edge: Vector2 = point+offset*radius
		if edge.x<0 or edge.y<0 or edge.x>=size or edge.y>=size:
			return {"kind":"terrain_bounds","point":str(point),"sample":str(edge)}
		var cell: int = floori(edge.y)*size+floori(edge.x)
		if int(data.land[cell])==0:
			return {"kind":"terrain_land","point":str(point),"sample":str(edge),"cell":[cell%size,cell/size],"terrain":int(data.terrain[cell])}
		var edge_height: float = _oracle_height(data,edge)
		if absf(edge_height-center_height)>.8:
			return {"kind":"terrain_clearance_cliff","point":str(point),"sample":str(edge),"height":center_height,"edge_height":edge_height}
	return {}

func _oracle_geometry(geometry: Dictionary) -> Dictionary:
	var buckets: Dictionary = {}
	var next_index: int = 0
	var groups: Array = [{"kind":"hard","rectangles":geometry.get("hard",[])},
		{"kind":"vehicle","rectangles":geometry.get("vehicles",[])}]
	for chunk in geometry.get("ruin_chunks",[]): groups.append({"kind":"ruin","rectangles":chunk.rectangles})
	for group in groups:
		for rectangle: Rect2 in group.rectangles:
			var item: Dictionary = {"index":next_index,"kind":group.kind,"rectangle":rectangle}
			next_index += 1
			var first := Vector2i(floori(rectangle.position.x/8.0),floori(rectangle.position.y/8.0))
			var last := Vector2i(floori(rectangle.end.x/8.0),floori(rectangle.end.y/8.0))
			for z in range(first.y,last.y+1):
				for x in range(first.x,last.x+1):
					var key := Vector2i(x,z)
					if not buckets.has(key): buckets[key]=[]
					buckets[key].append(item)
	return buckets

func _oracle_capsule_rectangle(start: Vector2, finish: Vector2, radius: float, rectangle: Rect2) -> bool:
	var low: Vector2 = start.min(finish)-Vector2.ONE*radius
	var high: Vector2 = start.max(finish)+Vector2.ONE*radius
	if high.x<rectangle.position.x or high.y<rectangle.position.y or low.x>rectangle.end.x or low.y>rectangle.end.y: return false
	var direction: Vector2 = finish-start
	var enter: float = 0.0
	var leave: float = 1.0
	var crosses: bool = true
	for axis in range(2):
		if absf(direction[axis])<.000001:
			if start[axis]<rectangle.position[axis] or start[axis]>rectangle.end[axis]: crosses=false
		else:
			var a: float = (rectangle.position[axis]-start[axis])/direction[axis]
			var b: float = (rectangle.end[axis]-start[axis])/direction[axis]
			enter=maxf(enter,minf(a,b));leave=minf(leave,maxf(a,b))
			if enter>leave: crosses=false
	if crosses: return true
	var limit: float = radius*radius+.00001
	if start.distance_squared_to(start.clamp(rectangle.position,rectangle.end))<limit: return true
	if finish.distance_squared_to(finish.clamp(rectangle.position,rectangle.end))<limit: return true
	for corner: Vector2 in [rectangle.position,rectangle.end,Vector2(rectangle.position.x,rectangle.end.y),Vector2(rectangle.end.x,rectangle.position.y)]:
		if corner.distance_squared_to(Geometry2D.get_closest_point_to_segment(corner,start,finish))<limit: return true
	return false

func _oracle_leg(data: Dictionary, buckets: Dictionary, start: Vector2, finish: Vector2, radius: float) -> Dictionary:
	var clearance: float = radius+.02
	var low: Vector2 = start.min(finish)-Vector2.ONE*clearance
	var high: Vector2 = start.max(finish)+Vector2.ONE*clearance
	var checked: Dictionary = {}
	for z in range(floori(low.y/8.0),floori(high.y/8.0)+1):
		for x in range(floori(low.x/8.0),floori(high.x/8.0)+1):
			for item in buckets.get(Vector2i(x,z),[]):
				if checked.has(item.index) or (item.kind=="vehicle" and radius<=.5): continue
				checked[item.index]=true
				if _oracle_capsule_rectangle(start,finish,clearance,item.rectangle):
					return {"kind":"rectangle","obstacle_kind":item.kind,"rectangle":str(item.rectangle),"clearance":clearance}
	var samples: int = maxi(1,ceili(start.distance_to(finish)/.25))
	var previous_height: float = _oracle_height(data,start)
	for index in range(samples+1):
		var point: Vector2 = start.lerp(finish,float(index)/samples)
		var height: float = _oracle_height(data,point)
		if absf(height-previous_height)>.8:
			return {"kind":"cliff_transition","point":str(point),"height":height,"previous_height":previous_height}
		var conflict: Dictionary = _oracle_terrain(data,point,radius)
		if not conflict.is_empty(): return conflict
		previous_height=height
	return {}

func _safety(records: Array[Dictionary], data: Dictionary, all_routes: bool = false) -> Dictionary:
	var seen: Dictionary = {}
	var empty_seen: Dictionary = {}
	var geometry_buckets: Dictionary = {}
	var checked: int = 0
	var empty: int = 0
	var detours: int = 0
	var unsafe: int = 0
	var examples: Array[Dictionary] = []
	for record in records:
		var job: Dictionary = record.job
		var key: int = int(record.token) if all_routes else int(record.id)
		if seen.has(key): continue
		if record.path.is_empty():
			if not empty_seen.has(int(record.id)):
				empty_seen[int(record.id)] = true
				empty += 1
			continue
		seen[key] = true
		checked += 1
		if record.path.size() > 1: detours += 1
		if not geometry_buckets.has(int(record.revision)):
			geometry_buckets[int(record.revision)]=_oracle_geometry(job.geometry)
		var previous: Vector2 = job.start
		var legal: bool = true
		var conflicts: Array[Dictionary] = []
		for index in range(record.path.size()):
			var point: Vector2 = record.path[index]
			var conflict: Dictionary = _oracle_leg(data,geometry_buckets[int(record.revision)],previous,point,float(job.radius))
			if not conflict.is_empty():
				legal=false
				if conflicts.size()<4: conflicts.append({"leg":index,"from":str(previous),"to":str(point),"conflict":conflict})
			previous = point
		if not legal:
			unsafe += 1
			if examples.size() < 8:
				examples.append({"id":record.id,"revision":record.revision,"radius":job.radius,"start":str(job.start),"goal":str(job.goal),"path":str(record.path),"conflicts":conflicts})
	return {"checked":checked, "detours":detours, "empty":empty, "unsafe":unsafe, "examples":examples,
		"route_scope":"all recorded nonempty routes" if all_routes else "first nonempty route per unit", "recorded_results":records.size(),
		"clearance":"independent immutable job-geometry capsule/rectangle oracle and initial worker terrain snapshot; 0.25m terrain samples; outside timed ticks"}

func _progress(sim, ids: Array, origins: Dictionary, goals: Dictionary, arrived: Dictionary) -> Dictionary:
	var displaced: int = 0
	var nearer: int = 0
	var unreachable: int = 0
	var lost: int = 0
	var distances: Array[float] = []
	for id: int in ids:
		if not sim.entities.has(id):
			lost += 1
			continue
		var entity: Dictionary = sim.entities[id]
		var distance: float = (entity.pos as Vector2).distance_to(origins[id])
		distances.append(distance)
		if distance > 1.0: displaced += 1
		if goals.has(id) and (entity.pos as Vector2).distance_to(goals[id])+1.0 < (origins[id] as Vector2).distance_to(goals[id]): nearer += 1
		if str(entity.state) == "unreachable": unreachable += 1
	return {"moved_over_1m":displaced,"nearer_goal_over_1m":nearer,"arrived":arrived.size(),
		"unreachable":unreachable,"lost":lost,"displacement_m":_percentiles(distances)}

func _missing_diagnostics(sim, ids: Array, visible: Dictionary, origins: Dictionary, goals: Dictionary, records: Array[Dictionary]) -> Array[Dictionary]:
	var first_results: Dictionary = {}
	var result_counts: Dictionary = {}
	for record in records:
		var id: int = int(record.id)
		result_counts[id]=int(result_counts.get(id,0))+1
		if not first_results.has(id):
			first_results[id]={"token":record.token,"revision":record.revision,"path_empty":record.path.is_empty(),"path":str(record.path),
				"start":str(record.job.start),"goal":str(record.job.goal)}
	var diagnostics: Array[Dictionary] = []
	for id: int in ids:
		if visible.has(id): continue
		var entity: Dictionary = sim.entities.get(id,{})
		var radius: float = .35 if entity.is_empty() else sim._radius(entity)
		var goal: Vector2 = goals.get(id,Vector2.INF)
		diagnostics.append({"id":id,"spec":entity.get("spec","lost"),"source":str(origins[id]),"goal":str(goal),
			"position":str(entity.get("pos",Vector2.INF)),"state":entity.get("state","lost"),"commands":str(entity.get("commands",[])),
			"source_standing_static_final":sim._standing(origins[id],radius,id,false),
			"goal_standing_static_final":goal.is_finite() and sim._standing(goal,radius,id,false),
			"first_worker_result":first_results.get(id,{}),"worker_result_count":int(result_counts.get(id,0)),
			"request_status":sim._path_requests.get(id,{}).get("status","none"),"planning_wait":entity.get("planning_wait",0),
			"path_wait":entity.get("path_wait",0),"stuck":entity.get("stuck",0)})
	return diagnostics

func _run_case(sim, ids: Array, command_start_us: int, options: Dictionary) -> Dictionary:
	var first_visible: Dictionary = {}
	var origins: Dictionary = {}
	var goals: Dictionary = {}
	var arrived: Dictionary = {}
	for id: int in ids:
		origins[id] = sim.entities[id].pos
		if not sim.entities[id].commands.is_empty(): goals[id] = sim.entities[id].commands[0].pos
	var samples: Array[float] = []
	var fixed_samples: Array[float] = []
	var rows: Array[Dictionary] = []
	var ticks: int = 0
	var max_in_flight: int = 0
	var max_queue: int = 0
	var wall_limit_us: int = int(float(options["max-wall-seconds"])*1000000.0)
	var target_ticks: int = int(options.ticks)
	var reason: String = "complete"
	var schedule_started: int = Time.get_ticks_usec()
	var fixed_window: Dictionary = {}
	while ticks < target_ticks or first_visible.size() < ids.size():
		if Time.get_ticks_usec()-command_start_us >= wall_limit_us:
			reason = "wall_deadline"
			break
		if not sim.result.is_empty():
			reason = "match_finished"
			break
		var before: int = Time.get_ticks_usec()
		sim.step(STEP)
		var elapsed_ms: float = float(Time.get_ticks_usec()-before)/1000.0
		samples.append(elapsed_ms)
		if ticks < target_ticks: fixed_samples.append(elapsed_ms)
		ticks += 1
		max_in_flight = maxi(max_in_flight, int(sim._path_in_flight))
		max_queue = maxi(max_queue, sim._planning_queue.size())
		var since_command_ms: float = float(Time.get_ticks_usec()-command_start_us)/1000.0
		for id: int in ids:
			if not sim.entities.has(id): continue
			var entity: Dictionary = sim.entities[id]
			if not first_visible.has(id) and not entity.path.is_empty(): first_visible[id] = since_command_ms
			if goals.has(id) and entity.commands.is_empty() and (entity.pos as Vector2).distance_to(goals[id]) < .6: arrived[id] = true
		if ticks == target_ticks:
			fixed_window={"ticks":ticks,"simulation_seconds":sim.time,"wall_ms":since_command_ms,"observed_paths":first_visible.size(),
				"navigation":sim.navigation_stats.duplicate(),"progress":_progress(sim,ids,origins,goals,arrived)}
		if ticks == 1 or ticks % 30 == 0:
			rows.append({"tick":ticks, "wall_ms":since_command_ms, "visible_paths":first_visible.size(), "in_flight":sim._path_in_flight,
				"queue":sim._planning_queue.size(), "completed":sim.navigation_stats.completed, "discarded":sim.navigation_stats.discarded})
		sim.events.clear()
		if bool(options.get("realtime",false)):
			# Use a monotonic 30 Hz cadence. Slow ticks consume their next slot;
			# fast ticks leave wall time for the real background workers.
			var remaining_us: int = schedule_started+int(float(ticks)*STEP*1000000.0)-Time.get_ticks_usec()
			if remaining_us > 0: OS.delay_usec(remaining_us)
		else:
			OS.delay_usec(int(options["yield-us"]))
	var path_latencies: Array[float] = []
	for value in first_visible.values(): path_latencies.append(float(value))
	path_latencies.sort()
	var trace = sim._path_worker
	var collected_latencies: Array[float] = []
	var collected_ids: Dictionary = {}
	for record in trace.records:
		if not record.path.is_empty() and not collected_ids.has(int(record.id)):
			collected_ids[int(record.id)] = true
			collected_latencies.append(float(int(record.collected_us)-command_start_us)/1000.0)
	collected_latencies.sort()
	var timed_wall_ms: float = float(Time.get_ticks_usec()-command_start_us)/1000.0
	var safety: Dictionary = _safety(trace.records,trace.terrain_snapshot,bool(options.get("all-route-safety",false)))
	var missing_diagnostics: Array[Dictionary] = _missing_diagnostics(sim,ids,first_visible,origins,goals,trace.records)
	return {"requested_units":ids.size(), "commanded_units":goals.size(), "ticks":ticks, "simulation_seconds":sim.time,
		"wall_ms":timed_wall_ms, "stop_reason":reason, "observed_paths":first_visible.size(), "missing_paths":ids.size()-first_visible.size(),
		"first_visible_path_ms":null if path_latencies.is_empty() else path_latencies.front(),
		"last_visible_path_ms":null if path_latencies.size()!=ids.size() else path_latencies.back(),
		"latest_observed_path_ms":null if path_latencies.is_empty() else path_latencies.back(), "visible_path_latency_ms":_percentiles(path_latencies),
		"first_collected_path_ms":null if collected_latencies.is_empty() else collected_latencies.front(),
		"last_collected_path_ms":null if collected_ids.size()!=ids.size() else collected_latencies.back(),
		"tick_ms":_percentiles(samples), "fixed_window_tick_ms":_percentiles(fixed_samples), "worker_search_us":_percentiles(trace.worker_us),
		"worker_queue_to_collect_ms":_percentiles(trace.queue_to_collect_ms), "worker_submitted":trace.submitted, "worker_collected":trace.collected,
		"navigation":sim.navigation_stats.duplicate(), "max_in_flight":max_in_flight, "in_flight_limit":_constant(sim,"PATH_IN_FLIGHT",Sim.PATH_IN_FLIGHT),
		"path_plans_per_tick":_constant(sim,"PATH_PLANS_PER_TICK",Sim.PATH_PLANS_PER_TICK),
		"max_queue":max_queue,"safety":safety,"progress":_progress(sim,ids,origins,goals,arrived),"fixed_window":fixed_window,
		"missing_unit_diagnostics":missing_diagnostics,"rows":rows}

func _standable_near(sim, pos: Vector2, radius: float = .8) -> Vector2:
	# Matches main.setup_benchmark's placement policy and spacing. Both
	# implementations therefore retain the same crowded base/bridge approaches.
	for ring in range(16):
		for index in range(maxi(1,ring*8)):
			var point: Vector2 = pos+Vector2.from_angle(float(index)/maxi(1,ring*8)*TAU)*ring*1.8
			if point.x < 2 or point.y < 2 or point.x > sim.map.size-2 or point.y > sim.map.size-2: continue
			if MapData.terrain_at(sim.map,point) in [1,4]: continue
			if not sim._standing(point,radius,-1,false): continue
			var available: bool = true
			for entity in sim.entities.values():
				var info: Dictionary = sim.data_for(entity.spec)
				var extent: float = float(info.get("size",1))*.73 if entity.kind=="building" else float(info.radius)
				if (entity.pos as Vector2).distance_to(point) < extent+radius+.1:
					available = false
					break
			if available: return point
	return pos

func _populate_debug(sim, count: int) -> Array:
	var groups: Array = [[],[]]
	for team in range(2):
		var start: Array = sim.map.starts[team]
		var base := Vector2(start[0],start[1])
		for index in range(15):
			var role: String = ["power","refinery","barracks","factory","tower"][index%5]
			var point: Vector2 = _standable_near(sim,base+Vector2((index%5-2)*7,(index/5+1)*7),3.0)
			var building: int = sim.debug_spawn(team,sim.factions[team]+"_"+role,point)
			if sim.entities.has(building):
				sim.entities[building].construct_remaining = 0.0
				sim.entities[building].gift_pending = false
		for index in range(count/2 + (count%2 if team==0 else 0)):
			var role: String = "tank" if index%7==0 else "harvester" if index%11==0 else "anti" if index%5==0 else "rifle"
			var point: Vector2 = _standable_near(sim,base+Vector2((index%12-6)*1.8,(index/12-5)*1.8))
			var unit: int = sim.debug_spawn(team,sim.factions[team]+"_"+role,point)
			if sim.entities.has(unit): groups[team].append(unit)
	# Fixed topology isolates navigation. Production/combat reserves are covered
	# by profile_final_pressure_cpu.gd; this fixture does not add reinforcements.
	sim._rebuild_nav()
	sim._rebuild_spatial()
	return groups

func _write_report(path: String, report: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null:
		errors.append("Cannot write report: "+path)
		return false
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	return true

func run() -> void:
	var options: Dictionary = _options()
	var config: Dictionary = Rules.load_rules()
	if config.is_empty():
		push_error("Navigation throughput rules invalid: "+str(Rules.errors))
		quit(2)
		return
	var before: int = Time.get_ticks_usec()
	var sim = _new_sim(config,"handmade",73026,options)
	if sim == null:
		for error in errors: push_error(error)
		quit(2)
		return
	var setup_ms: float = float(Time.get_ticks_usec()-before)/1000.0
	before = Time.get_ticks_usec()
	var groups: Array = _populate_debug(sim,int(options.units))
	var populate_ms: float = float(Time.get_ticks_usec()-before)/1000.0
	var ids: Array = groups[0]+groups[1]
	var command_started: int = Time.get_ticks_usec()
	for team in range(2):
		var enemy: Array = sim.map.starts[1-team]
		sim.issue(groups[team],str(options.command),Vector2(enemy[0],enemy[1]))
	var command_ms: float = float(Time.get_ticks_usec()-command_started)/1000.0
	sim.profile_enabled = true
	var report: Dictionary = _run_case(sim,ids,command_started,options)
	report.merge({"schema":1,"fixture":"main.setup_benchmark population and placements; all units receive a move order",
		"mode":"handmade","seed":73026,"map_size":sim.map.size,"teams":2,"units_per_team":[groups[0].size(),groups[1].size()],
		"buildings_per_team":[sim.counts(0).y,sim.counts(1).y],"setup_ms":setup_ms,"populate_ms":populate_ms,"command_issue_ms":command_ms,
		"options":options,"simulation_sha256":FileAccess.get_sha256(str(options["baseline-sim"]) if not str(options["baseline-sim"]).is_empty() else "res://scripts/simulation.gd"),
		"worker_sha256":FileAccess.get_sha256(str(options["baseline-worker"]) if not str(options["baseline-worker"]).is_empty() else "res://scripts/path_worker.gd"),
		"scope":"headless background paths and simulation; excludes rendering; wall deadlines report incomplete batches explicitly"})
	# Explicitly join the worker before the RefCounted simulator is released.
	sim._path_worker.close()
	sim = null
	var written: bool = _write_report(str(options.output),report)
	var compact: Dictionary = report.duplicate()
	compact.erase("rows")
	print("NAVIGATION_THROUGHPUT ",JSON.stringify(compact))
	quit(0 if written and int(report.safety.unsafe)==0 else 1)
