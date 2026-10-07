extends "res://tools/capture_rts_model_revision.gd"
const Sim = preload("res://tests/rule_test_simulation.gd")
const OUT = "res://artifacts/zeppelin_revision_20261007"
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size=Vector2i(1440,1000); root.content_scale_size=root.size
	V.configure_player_colors(["#397ac4","#b6504d"])
	prepare("LIVE DIRIGIBLE / GRAVITY BOMB + INDEPENDENT DORSAL GUN",12.0,Vector3(21,2.6,20))
	var sim=Sim.new()
	var rules: Dictionary=RulesLoader.load_rules()
	sim.setup(rules,"dev",7,"rivet",false); sim.vision_enabled=false
	for row in sim.map.terrain: row.fill(0)
	for row in sim.map.heights: row.fill(0.0)
	sim.mines.clear(); sim.bridges.clear(); sim.ruins.clear(); sim._refresh_mine_spatial(); sim._refresh_ruin_spatial()
	for id in sim.entities.keys(): sim._kill_entity(id,false)
	sim._spawn(0,"rivet_hq",Vector2(5,43),true); sim._spawn(1,"kestrel_hq",Vector2(43,43),true)
	var zeppelin: int=sim._spawn(0,"rivet_zeppelin",Vector2(20,20),true)
	var ground: int=sim._spawn(1,"kestrel_tank",Vector2(20.8,20),true)
	var aircraft: int=sim._spawn(1,"kestrel_fighter",Vector2(23.4,20),true)
	for id in [ground,aircraft]: sim.entities[id].cooldown=1000; sim.entities[id].hold_position=true
	sim._prepare_terrain_cache(); sim._nav_initialized=false; sim._rebuild_nav(); sim._rebuild_spatial(); sim.events.clear()
	sim.issue([zeppelin],"attack",sim.entities[ground].pos,ground)
	var world:=PaperWorld.new(); scene.add_child(world); world.setup(sim,camera)
	camera.position=Vector3(25,8,34); camera.look_at(Vector3(21,2.7,20)); camera.size=10.8
	var evidence: Array=[]
	for i in range(24):
		sim.events.clear(); sim.step(.05); world.sync(.05,[])
		await process_frame
		if i in [0,6,14,21]:
			RenderingServer.force_draw()
			var name: String="drop_"+str(i).pad_zeros(2)
			root.get_texture().get_image().save_png(OUT+"/"+name+".png")
			var bomb: Dictionary=sim.projectiles[0] if not sim.projectiles.is_empty() else {}
			evidence.append({"frame":i,"bomb_y":bomb.get("gravity_y",0),"bomb_pos":str(bomb.get("pos",Vector2.ZERO)),"ammo":sim.entities[zeppelin].ammo,"mg_target":sim.entities[zeppelin].get("zeppelin_mg_target",-1),"enemy_aircraft_hp":sim.entities[aircraft].hp})
			print("ZEPPELIN_LIVE_CAPTURE ",name)
	if sim._path_worker!=null: sim._path_worker.close()
	world.free()
	root.size=Vector2i(1440,720); root.content_scale_size=root.size
	prepare("DIRIGIBLE / NEAR · MEDIUM · FAR / DORSAL GUN",4.8,Vector3(0,.6,0))
	for tier in range(3): add_model(rules.units.rivet_zeppelin,"unit",Vector3(-2.8+float(tier)*2.8,0,0),tier,{"id":tier,"zeppelin_mg_alpha":50,"zeppelin_mg_pitch":.15})
	for i in range(5): await process_frame
	RenderingServer.force_draw(); root.get_texture().get_image().save_png(OUT+"/three_lods.png")
	root.size=Vector2i(512,512); root.content_scale_size=root.size
	prepare("",2.70,Vector3(0,.68,0)); labels.hide()
	add_model(rules.units.rivet_zeppelin,"unit",Vector3.ZERO,0,{"id":1,"zeppelin_mg_alpha":25})
	for i in range(5): await process_frame
	RenderingServer.force_draw(); root.get_texture().get_image().save_png("res://assets/cards/rts_revision/zeppelin.png")
	var file:=FileAccess.open(OUT+"/live_manifest.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"frames":evidence,"renderer":RenderingServer.get_current_rendering_method(),"device":RenderingServer.get_video_adapter_name()},"  "))
	file.close()
	scene.free(); labels.free(); await process_frame
	print("ZEPPELIN_LIVE_RESULT ",JSON.stringify(evidence))
	quit()
