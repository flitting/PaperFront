extends SceneTree

const Sim=preload("res://tests/rule_test_simulation.gd")
var failures:Array[String]=[]

func _initialize() -> void:call_deferred("run")
func check(ok:bool,message:String) -> void:
	if not ok:failures.append(message)

func run() -> void:
	var sim=Sim.new()
	sim.setup(RulesLoader.load_rules(),"dev",7,"rivet",false)
	var camera:=Camera3D.new()
	root.add_child(camera)
	camera.position=Vector3(24,30,52)
	camera.look_at(Vector3(24,0,24))
	var world:=PaperWorld.new()
	root.add_child(world)
	world.setup(sim,camera)
	world.configure_quality("performance")
	world.profile_enabled=true
	var tank:int=sim.debug_spawn(0,"rivet_tank",Vector2(22.5,32.5))
	world.sync(0.0,[])
	var original:Node3D=world.models[tank].root
	for index in range(200):
		world._spawn_effect(Vector2(24,32),"death",1.2,.5)
		world._spawn_smoke(Vector2(24,32),1.2,.5,true)
		world._spawn_debris(Vector2(24,32),1.2,.5)
	check(world.effects.size()<=96 and world.data_effects.size()<=24,"performance burst bounds persistent fragments and data particles")
	world.sync(.05,[])
	check(world.data_effects.size()<=128,"performance particle lifetime budget remains bounded")
	sim.entities.erase(tank)
	world.sync(.05,[])
	check(world.ghosts.is_empty() and world.data_corpses.is_empty(),"performance death replaces the complete model with explosion and fragments")
	var replacement:int=sim.debug_spawn(0,"rivet_tank",Vector2(25.5,32.5))
	world.sync(.05,[])
	check(world.models[replacement].root==original and int(world.profile_last.models_reused)==1,"same-template reinforcements reuse their finished model hierarchy")
	check(world.models[replacement].last_pos==sim.entities[replacement].pos and world.models[replacement].hp_fraction==1.0,"recycled models reset position and health display")
	world.sync(21.0,[])
	check(world.data_effects.is_empty() and world.effects.is_empty(),"bounded performance smoke and fragments expire")
	print("PERFORMANCE_FX ",JSON.stringify({"failures":failures,"profile":world.profile_last}))
	world.queue_free()
	camera.queue_free()
	await process_frame
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
