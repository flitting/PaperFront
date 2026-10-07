extends "res://tests/air_navigation_stall_tests.gd"

func traffic_case(native_backend: bool, crowded: bool) -> void:
	var sim = fixture(native_backend)
	var ids: Array[int] = []
	var all_air: Array[int] = []
	var center := Vector2(35,35)
	if crowded:
		# Two intersecting real idle circuits, with distinct phases and speeds.
		for index: int in range(8):
			var c: Vector2 = center + Vector2(7.0 * float(index / 4), 0)
			var id: int = loiterer(sim,c,float(index % 4)*PI*.5)
			ids.append(id)
			all_air.append(id)
	else:
		var id: int = loiterer(sim,center,0.0)
		ids.append(id);all_air.append(id)
		var radius: float = 3.4 + float(id % 3)*.6
		for angle: float in [.75,1.5,2.25]:
			all_air.append(aircraft(sim,"rivet_helicopter",center+Vector2.from_angle(angle)*radius))
	var reversals: Dictionary = {}
	var previous_velocity: Dictionary = {}
	var angles: Dictionary = {}
	var distance: Dictionary = {}
	var samples: Dictionary = {}
	for id: int in ids:
		reversals[id]=0;angles[id]=0.0;distance[id]=0.0;samples[id]=[]
	var minimum: float = INF
	for frame: int in range(600):
		var before: Dictionary = {}
		for id: int in all_air:before[id]=sim.entities[id].pos
		sim.step(STEP);sim.events.clear()
		for first: int in all_air:
			for second: int in all_air:
				if second<=first:continue
				minimum=minf(minimum,swept_distance(before[first],sim.entities[first].pos,before[second],sim.entities[second].pos))
		for id: int in ids:
			var e: Dictionary = sim.entities[id]
			var velocity: Vector2 = e.pos-before[id]
			if previous_velocity.has(id) and velocity.length()>.01 and (previous_velocity[id] as Vector2).length()>.01 and velocity.normalized().dot((previous_velocity[id] as Vector2).normalized())<-.5:
				reversals[id]+=1
			previous_velocity[id]=velocity
			angles[id]+=wrapf(((e.pos as Vector2)-(e.loiter_center as Vector2)).angle()-((before[id] as Vector2)-(e.loiter_center as Vector2)).angle(),-PI,PI)
			distance[id]+=(before[id] as Vector2).distance_to(e.pos)
			if frame%60==59:samples[id].append(e.pos)
	check(minimum>=2.0198,"all traffic has full swept airspace separation native=%s crowded=%s min=%f" % [native_backend,crowded,minimum])
	for id: int in ids:
		check(int(reversals[id])<=2,"idle traffic avoids repeated abrupt reversals native=%s crowded=%s id=%d flips=%d" % [native_backend,crowded,id,reversals[id]])
		check(float(angles[id])>TAU,"each plane progresses a real orbit through traffic native=%s crowded=%s id=%d angle=%f" % [native_backend,crowded,id,angles[id]])
		var moving_windows: int=0
		for index: int in range(1,samples[id].size()):
			if (samples[id][index] as Vector2).distance_to(samples[id][index-1])>.8:moving_windows+=1
		check(moving_windows>=8,"each plane keeps moving across later two-second windows native=%s crowded=%s id=%d windows=%d" % [native_backend,crowded,id,moving_windows])
	rows.append({"case":"intersecting_orbits" if crowded else "three_hovering_obstacles","native":native_backend,"minimum_swept_distance":minimum,"reversals":reversals,"actual_angle_progress":angles,"distance":distance})

func run() -> void:
	rules=Rules.load_rules("res://data/rules.json",false)
	check(not rules.is_empty(),"traffic repro uses real rules")
	for native_backend: bool in [false,true]:
		traffic_case(native_backend,false)
		traffic_case(native_backend,true)
	print("AIR_LOITER_TRAFFIC_V4 ",JSON.stringify({"checks":checks,"failures":failures,"cases":rows}))
	for message: String in failures:push_error(message)
	quit(0 if failures.is_empty() else 1)
