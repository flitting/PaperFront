extends SceneTree
var game:Node
func _initialize():call_deferred("run")
func shot(name:String):
	for i in range(8):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/group_navigation/"+name+".png")
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_physics_process(false);game.hud.show_menu(false)
	game.sim.ai_enabled=false
	for kind in ["wall","house"]:
		var first:Dictionary={}
		for ruin in game.sim.ruins:
			if ruin.kind==kind:first=ruin;break
		if first.is_empty():push_error("missing type "+kind);quit(1);return
		var members:Array=game.sim.ruins.filter(func(r):return r.group==first.group)
		var center:=Vector2.ZERO
		for ruin in members:center+=ruin.pos
		center/=members.size()
		game.focus=center;game.distance=23;game.yaw=.45+float(first.get("yaw",0));game.camera_pitch=33;game.update_camera()
		game.world.sync(0,[],{})
		game.hud.refresh(game.sim,[],game.camera,true,"低石墙：暖纸面、切口与手绘石块；按地图种子随机成簇分布" if kind=="wall" else "半毁建筑：保留窗洞、破损墙顶与木梁；独立废墟簇，不与石墙混放",0)
		await shot("paper_"+kind)
	print("ART_CAPTURE_OK")
	game.queue_free();await process_frame;quit()
