extends SceneTree
var errors:Array[String]=[]
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
	if not ok:errors.append(label)
func run():
	var game=load("res://main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_physics_process(false)
	game.start_match("handmade",73026,"rivet")
	game.sim.ai_enabled=false;game.hud.show_menu(false)
	var mine:Dictionary=game.sim.mines[1]
	var truck:int=game.sim.debug_spawn(0,"rivet_harvester",mine.pos+Vector2(3,0))
	game.selected=[truck]
	game.right_command(mine.pos,-1,false)
	check(game.sim.entities[truck].commands.size()==1 and game.sim.entities[truck].commands[0].kind=="harvest" and game.sim.entities[truck].commands[0].target==1,"right-click ore dispatches explicit mining")
	game.world.sync(0,[truck],{})
	var model:Dictionary=game.world.models[truck]
	game.sim.entities[truck].cargo=250
	for i in range(120):
		game.world.sync(1.0/60,[truck],{});game.sim.events.clear()
		check(model.volume.cargo_count==6,"cargo count remains stable between frames")
	var ruin:Dictionary=game.sim.ruins[0]
	game.focus=ruin.pos;game.distance=25;game.yaw=.3;game.camera_pitch=35;game.update_camera()
	var screen:Vector2=game.project_world_to_screen(Vector3(ruin.pos.x,MapData.height_at(game.sim.map,ruin.pos)+1.1,ruin.pos.y))
	var target:int=game.pick_entity(screen)
	check(target==game.sim.RUIN_TARGET_BASE-int(ruin.id),"ruin can be picked on visible walls")
	game.click_select(screen,false)
	check(game.inspected_ruin==target and game.selected.is_empty(),"ruin inspection is distinct from team selection")
	var tank:int=game.sim.debug_spawn(0,"rivet_tank",ruin.pos+Vector2(-5,0))
	game.selected=[tank]
	game.right_command(ruin.pos,target,false)
	check(game.sim.entities[tank].commands[0].kind=="move" and game.sim.entities[tank].commands[0].target==-1,"ordinary right-click ruin dispatches movement without destroying it")
	game.command_units("force_attack",ruin.pos,target)
	check(game.sim.entities[tank].commands[0].kind=="force_attack" and game.sim.entities[tank].commands[0].target==target,"force attack explicitly targets neutral ruin")
	game.world._spawn_effect(ruin.pos,"impact",1.2)
	game.world._spawn_effect(ruin.pos+Vector2(4,0),"death",1.2,1)
	game.world._update_effects(.7)
	var hits:=0;var deaths:=0
	for effect in game.world.effects:
		if effect.kind=="blast":hits+=1
		if effect.kind=="death_blast":deaths+=1
	check(hits==0 and deaths>0,"death bursts visibly outlast impact bursts")
	print("REFINEMENT_INPUT ","PASS" if errors.is_empty() else errors)
	for error in errors:push_error(error)
	game.queue_free();await process_frame;quit(0 if errors.is_empty() else 1)
