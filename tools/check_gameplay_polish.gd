extends SceneTree
var failures: Array[String] = []
var game: Node
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func capture(name: String) -> void:
	for i in range(8): await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/gameplay_polish/"+name+".png")
func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.start_match("dev",7,"rivet")
	game.hud.show_menu(false)
	game.sim.ai_enabled=false
	game.focus=Vector2(15,39)
	game.distance=30
	game.yaw=.15
	game.camera_pitch=35
	game.update_camera()
	game.sim.money[0]=10000
	var hq: int = -1
	for e in game.sim.entities.values():
		if e.team==0 and e.kind=="building":hq=e.id;break
	game.selected=[hq]
	game.hud.refresh(game.sim,game.selected,game.camera,true,"",0)
	check(game.hud.entry_widgets.has("rivet_wall") and game.hud.entry_widgets.has("rivet_barricade"),"both defenses appear in headquarters cards")
	check(not game.hud.entry_widgets.rivet_power.button.tooltip_text.contains("rivet_hq"),"tooltip prerequisites use localized names")
	check(game.hud.theme_paper.get_stylebox("panel","TooltipPanel").bg_color.get_luminance()>.5,"tooltip has light background")
	for i in range(3): await process_frame
	var wheel := InputEventMouseButton.new()
	wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed=true
	game.hud.entry_widgets.rivet_power.button.gui_input.emit(wheel)
	check(game.hud.build_scroll.scroll_horizontal>0,"mouse wheel scrolls horizontal building cards")
	game.handle_action("pause",null)
	var time: float = game.sim.time
	for i in range(30):game._physics_process(1.0/30)
	check(game.sim.time==time and game.hud.pause_button.text=="继续","PVE pause stops simulation and shows resume")
	game.handle_action("pause",null)
	game._physics_process(1.0/30)
	check(game.sim.time>time,"resume advances simulation")
	var tank: int = game.sim.debug_spawn(0,"rivet_tank",Vector2(8,42))
	game.selected=[tank]
	game.handle_action("waypoint",null)
	check(game.command_mode=="waypoint","waypoint button enters route mode")
	game.handle_action("patrol",null)
	check(game.command_mode=="patrol","patrol button enters patrol mode")
	game.handle_action("hold",null)
	check(game.sim.entities[tank].get("hold_position",false),"hold button reaches simulation")
	game.handle_action("stop",null)
	check(not game.sim.entities[tank].get("hold_position",true),"stop cancels hold")
	game.sim.issue([tank],"move",Vector2(16,42))
	for i in range(60):
		game.sim.step(1.0/30)
		game.world.sync(1.0/30,[tank],{})
		game.sim.events.clear()
	check(game.world.tracks.size()>0,"moving vehicle leaves wheel/track marks")
	var truck: int = game.sim.debug_spawn(0,"rivet_harvester",Vector2(12,39))
	game.sim.entities[truck].cargo=500
	game.sim.entities[truck].state="harvest"
	game.world.sync(.1,[truck],{})
	check(game.world.models[truck].volume.cargo_count==12,"full cargo rendered by game world")
	game.sim.debug_spawn(0,"rivet_wall",Vector2(12.5,44.5))
	game.sim.debug_spawn(0,"rivet_barricade",Vector2(16.5,40.5))
	game.sim.building_orders[0]={"spec":"rivet_wall","remaining":0.0,"total":3.0,"cost":60.0,"ready":true,"progress":1.0}
	var placement: Dictionary = {"spec":"rivet_wall","pos":Vector2(18.5,44.5),"valid":game.sim.placement_error(0,Vector2(18.5,44.5)).is_empty()}
	game.world.sync(.1,[truck],placement)
	game.sim.events.clear()
	check(game.world.guide_mesh.get_surface_count()==1,"construction guides render")
	game.hud.refresh(game.sim,[hq],game.camera,true,"围墙：绿色标记预览连续六格，逐格计费",0)
	game.hud.build_scroll.scroll_horizontal=10000
	await capture("defense_preview")
	game.sim.building_orders[0].spec="rivet_tower"
	game.world.sync(0,[tank],{"spec":"rivet_tower","pos":Vector2(18,39),"valid":true})
	await capture("tower_range")
	game.sim.building_orders[0]={}
	game.sim._kill_entity(tank,true)
	var destroyed_building: int = game.sim.debug_spawn(1,"kestrel_power",Vector2(20.5,43.5))
	game.world.sync(0,[],{})
	game.sim.events.clear()
	game.sim._kill_entity(destroyed_building,true)
	game.world.sync(.16,[],{})
	game.sim.events.clear()
	var blasts := 0
	for effect in game.world.effects:
		if effect.kind=="death_blast":blasts+=1
	check(blasts>=12,"vehicle and building deaths spawn explosions")
	game.hud.refresh(game.sim,[truck],game.camera,true,"车辆与建筑爆炸、矿车采矿及载货、短暂车辙",0)
	await capture("effects")
	game.world._spawn_effect(Vector2(16,43),"impact",1.2)
	game.world._spawn_smoke(Vector2(16,43),1.2)
	game.world.sync(.12,[],{})
	await capture("shell_impact")
	game.sim.projectiles.append({"start":Vector2(10,42),"landing":Vector2(18,42),"elapsed":.25,"duration":.5,"spec":"rivet_tank","team":0,"heading":0.0,"body_heading":0.0})
	game.world._sync_projectiles()
	var source: Vector3 = Vector3(10,MapData.height_at(game.sim.map,Vector2(10,42)),42) + VolumeModels.muzzle_offset(game.sim.rules.units.rivet_tank,"unit",0,0,0)
	var destination := Vector3(18,MapData.height_at(game.sim.map,Vector2(18,42))+.15,42)
	check(is_equal_approx(game.world.shells[0].position.y,source.lerp(destination,.5).y+.36),"shell midpoint uses shallow .36m arc at 8m range")
	game.sim.projectiles.clear()
	game.sim.entities[truck].state="idle"
	game.world.sync(6.0,[],{})
	check(game.world.tracks.is_empty(),"track marks expire")
	print("Gameplay UI/render checks: ","PASS" if failures.is_empty() else failures)
	for message in failures:push_error(message)
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
