extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():printerr("Expected saved match path");quit(1);return
	var sim:=Simulation.new();sim.synchronous_path_tests=true
	var error:String=sim.load_game(args[0])
	if not error.is_empty():printerr(error);quit(1);return
	print("CHECKPOINT ",sim.time," funds=",sim.money," AI=",JSON.stringify(sim.ai_state))
	for e:Dictionary in sim.entities.values():
		var row:Dictionary={"id":e.id,"team":e.team,"spec":e.spec,"pos":str(e.pos),"state":e.state,"commands":str(e.commands),"path":str(e.path)}
		for field:String in ["queue","emerging","emerge_elapsed","construct_remaining","construction","harvest_mine","harvest_refinery","preferred_mine","harvest_load","cargo","harvest_override","refinery_docking","refinery_waiting","dock_unit","dock_phase","refinery_target","dock_refinery","path_goal","planning_wait","path_wait","stuck","yield_goal","yield_root","yield_until","rail_route","rail_goal","rail_revision","auto_target","last_attack_time","production_unit","gift_pending"]:
			if e.has(field):row[field]=str(e[field])
		print("ENTITY ",JSON.stringify(row))
	quit()
