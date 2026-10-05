extends SceneTree
var failures: Array[String] = []
var checks: int = 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game.audio.muted = true
	game.start_match("dev",7,"sky",true)
	game.sim.ai_enabled = false
	game.sim.synchronous_path_tests = true
	var sim: WarSimulation = game.sim
	sim._spawn(0,"sky_power",Vector2(28,39),true)
	var field: int = sim._spawn(0,"sky_airfield",Vector2(20,36),true)
	var plane: int = sim._spawn(0,"sky_air_transport",Vector2(20,36),true)
	sim._set_home_airfield(sim.entities[plane],field)
	sim.entities[plane].flight_state="rearming"
	sim.entities[plane].airborne=false
	sim.entities[plane].flight_height=.35
	sim.entities[plane].rearm_remaining=0.0
	var infantry: Array = []
	for i in range(4): infantry.append(sim._spawn(0,"sky_rifle",Vector2(18+i*2,40),true))
	game.selected=infantry
	game.right_command(sim.entities[plane].pos,plane,false)
	check(infantry.all(func(id): return not sim.entities[id].commands.is_empty() and sim.entities[id].commands[0].kind=="board"),"One right click dispatches all four selected infantry to aircraft")
	for tick in range(240):
		sim.step(1.0/30.0)
		if sim.entities[plane].passengers.size()==4: break
	check(sim.entities[plane].passengers.size()==4,"Four infantry actually board parked aircraft")
	game.hud.refresh(sim,[plane],game.camera,true,"",0)
	check(game.hud.unload_button.visible and game.hud.info_label.text.contains("搭载 4/4"),"Aircraft selection exposes passengers and unload action")
	game.selected=[plane]
	game.handle_action("unload",null)
	check(sim.entities[plane].passengers.is_empty(),"Aircraft HUD unload action restores infantry")
	var repairer: int = sim._spawn(0,"sky_inspection",Vector2(27,39),true)
	var tank: int = sim._spawn(0,"sky_tank",Vector2(31,39),true)
	sim.entities[tank].hp=100.0
	game.selected=[repairer]
	game.right_command(sim.entities[tank].pos,tank,false)
	check(not sim.entities[repairer].commands.is_empty() and sim.entities[repairer].commands[0].kind=="repair_unit","Inspection vehicle right click issues field repair")
	game.start_match("dev",7,"iron",true)
	game.sim.ai_enabled=false
	sim=game.sim
	var rescue: int = sim._spawn(0,"iron_recycler",Vector2(14,39),true)
	tank=sim._spawn(0,"iron_tank",Vector2(17,39),true)
	sim.entities[tank].hp=100.0
	game.selected=[rescue]
	game.right_command(sim.entities[tank].pos,tank,false)
	check(not sim.entities[rescue].commands.is_empty() and sim.entities[rescue].commands[0].kind=="rescue","Rescue vehicle right click issues escort instead of ground move")
	print("FACTION_SUPPORT_INPUT ",JSON.stringify({"checks":checks,"failures":failures}))
	for failure in failures: push_error(failure)
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
