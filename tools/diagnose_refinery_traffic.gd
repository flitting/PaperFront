extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty(): printerr("Expected saved match path");quit(1);return
	var sim := Simulation.new()
	sim.synchronous_path_tests = true
	var error: String = sim.load_game(args[0])
	if not error.is_empty(): printerr(error);quit(1);return
	for e: Dictionary in sim.entities.values():
		if not str(e.spec).ends_with("_harvester") and not str(e.spec).ends_with("_refinery"): continue
		var row := {"id":e.id,"spec":e.spec,"pos":str(e.pos),"state":e.state,"cargo":e.cargo}
		for field: String in ["refinery_docking","refinery_waiting","harvest_refinery","harvest_mine","production_door","production_unit","dock_unit","gift_pending","emerging","commands","yield_goal"]:
			row[field] = str(e.get(field,"absent"))
		print("REFINERY_ENTITY " + JSON.stringify(row))
	if sim._path_worker != null: sim._path_worker.close()
	quit()
