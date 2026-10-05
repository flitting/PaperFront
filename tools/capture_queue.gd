extends SceneTree
var game:Node
func _initialize():call_deferred("run")
func shot(name:String):
	for i in range(8):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/group_navigation/"+name+".png")
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_physics_process(false)
	game.start_match("dev",7,"rivet");game.sim.ai_enabled=false;game.hud.show_menu(false)
	for z in range(30,47):
		if z in [40,41]:continue
		for x in range(21,27):game.sim.debug_spawn(0,"rivet_wall",Vector2(x+.5,z+.5))
	var ids:Array=[]
	for i in range(24):ids.append(game.sim.debug_spawn(0,"rivet_tank",Vector2(12+(i%4)*1.9,35+(i/4)*1.9)))
	game.sim.issue(ids,"move",Vector2(34,41))
	game.focus=Vector2(23,40);game.distance=34;game.yaw=.3;game.camera_pitch=42;game.update_camera()
	game.world.sync(0,ids,{});game.sim.events.clear()
	for t in range(750):
		game.sim.step(1.0/30)
		if t%10==0:game.world.sync(1.0/3,ids,{})
		game.sim.events.clear()
		if t in [239,599]:
			game.hud.refresh(game.sim,ids,game.camera,true,"两格窄口：共享路线，入口外排队，前车通行后逐辆跟进",0)
			await shot("queue_%d"%(t+1))
	print("QUEUE_CAPTURE gates=",game.sim.group_navigation.gates.size()," shared plans=",game.sim.group_navigation.plans," grants=",game.sim.group_navigation.grants)
	game.queue_free();await process_frame;quit()
