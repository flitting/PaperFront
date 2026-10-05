extends SceneTree
var game:Node
var out:String="res://artifacts/refinement_v2/"
func _initialize():call_deferred("run")
func shot(name:String):
	for i in range(8):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out+name+".png")
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_physics_process(false)
	game.start_match("handmade",73026,"rivet")
	game.sim.ai_enabled=false;game.hud.show_menu(false)
	game.camera_pitch=34;game.yaw=.45;game.distance=23
	var ruin:Dictionary=game.sim.ruins[0]
	game.focus=ruin.pos+Vector2(0,1)
	game.update_camera()
	var truck:int=game.sim.debug_spawn(0,"rivet_harvester",ruin.pos+Vector2(-4,1))
	game.sim.entities[truck].cargo=250
	var person:int=game.sim.debug_spawn(0,"rivet_rifle",ruin.pos+Vector2(-2,4))
	game.world.sync(.1,[truck],{})
	game.sim.events.clear()
	game.hud.refresh(game.sim,[truck],game.camera,true,"参考重建：低石墙、开窗厚墙、破损墙顶、木梁及碎砖组成完整废墟簇",0)
	await shot("ruin_cluster")
	game.sim._add_damage(game.sim.RUIN_TARGET_BASE-int(ruin.id),10000)
	game.sim._apply_damage();game.sim._damage.clear()
	game.world.sync(.45,[],{});game.sim.events.clear()
	await shot("ruin_destroyed")
	game.focus=ruin.pos+Vector2(-4,4);game.distance=17;game.yaw=0;game.update_camera()
	game.world.sync(4,[],{})
	game.sim.entities[truck].cargo=0
	game.world.sync(0,[truck],{})
	await shot("truck_empty")
	game.sim.entities[truck].cargo=500
	game.sim.entities[truck].state="harvest"
	game.world.sync(.15,[truck],{})
	await shot("truck_full")
	# Same-view and same-size impact versus vehicle destruction over time.
	game.world._spawn_effect(ruin.pos+Vector2(-2,4),"impact",1.2)
	game.world._spawn_smoke(ruin.pos+Vector2(-2,4),1.2)
	game.sim._kill_entity(truck,true)
	game.world.sync(.14,[],{});game.sim.events.clear()
	game.hud.refresh(game.sim,[],game.camera,true,"左侧车辆死亡：二次燃爆 / 飞散碎片 / 黑烟；右侧普通落点：短促火团",0)
	await shot("death_vs_hit_014")
	game.world.sync(.55,[],{})
	await shot("death_vs_hit_069")
	game.world.sync(1.0,[],{})
	await shot("death_vs_hit_169")
	print("REFINEMENT_RENDER_OK")
	game.queue_free();await process_frame;quit()
