extends SceneTree
func _initialize():call_deferred("run")
func run():
	var game=load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false);game.set_physics_process(false)
	game.start_match("dev",7,"rivet")
	game.benchmark_count=256
	game.setup_benchmark()
	var sim=game.sim
	var starts: Dictionary={}
	var uncommanded: Array=[]
	for e in sim.entities.values():
		if e.kind=="unit":
			starts[e.id]=e.pos
			if not str(e.spec).ends_with("harvester") and e.commands.is_empty():uncommanded.append(e.id)
	print("PRESSURE_INITIAL_UNITS ",starts.size())
	print("UNCOMMANDED_AT_START ",uncommanded)
	for t in range(3600):
		sim.step(1.0/30);sim.events.clear()
	var stuck: Array=[]
	for e in sim.entities.values():
		if e.kind!="unit" or not starts.has(e.id):continue
		if e.pos.distance_to(starts[e.id])<3 or e.state=="unreachable":
			stuck.append({"id":e.id,"spec":e.spec,"pos":e.pos,"start":starts[e.id],"state":e.state,"stuck":e.stuck,"yield":e.get("yield_goal"),"commands":e.commands,"path":e.path})
	print("PRESSURE_STALLED ",stuck.size()," live ",sim.entities.size()," time ",sim.time," result ",sim.result)
	for e in stuck:print(e)
	sim.save_game("/tmp/paperfront-pressure-v2.pfront")
	game.queue_free();await process_frame
	quit()
