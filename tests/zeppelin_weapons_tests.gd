extends SceneTree
const Sim = preload("res://tests/rule_test_simulation.gd")
const Z = preload("res://scripts/zeppelin_weapons.gd")
const V = preload("res://scripts/volume_models.gd")
var failures: Array[String] = []
var checks: int = 0
var rules: Dictionary
func _initialize() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures.append(message)
func fixture(native_mode: bool = false):
	var sim = Sim.new()
	sim.native_kernels_enabled=native_mode; sim.native_unit_dispatch_enabled=native_mode; sim.native_geometry_enabled=native_mode; sim.native_movement_enabled=native_mode
	sim.setup(rules.duplicate(true),"dev",7,"rivet",false)
	sim.vision_enabled=false
	for row in sim.map.terrain: row.fill(0)
	for row in sim.map.heights: row.fill(0.0)
	sim.mines.clear(); sim.bridges.clear(); sim.ruins.clear(); sim._refresh_mine_spatial(); sim._refresh_ruin_spatial()
	for id in sim.entities.keys(): sim._kill_entity(id,false)
	sim._spawn(0,"rivet_hq",Vector2(5,43),true); sim._spawn(1,"kestrel_hq",Vector2(43,43),true)
	sim._prepare_terrain_cache(); sim._nav_initialized=false; sim._rebuild_nav(); sim._rebuild_spatial(); sim.events.clear()
	return sim
func quiet(sim,spec: String,pos: Vector2) -> int:
	var id: int=sim._spawn(1,spec,pos,true)
	sim.entities[id].cooldown=10000.0
	sim.entities[id].hold_position=true
	return id
func close(sim) -> void:
	if sim._path_worker != null: sim._path_worker.close()
func run() -> void:
	rules=RulesLoader.load_rules()
	check(not rules.is_empty(),"strict rules validation accepts secondary weapon and gravity trajectory")
	if rules.is_empty(): print(RulesLoader.errors); quit(1); return
	check(int(rules.units.rivet_zeppelin.hp)==2200,"zeppelin durability doubled from 1100")
	check(float(rules.weapons.rivet_zeppelin.range)==2.5,"bombs require close range")
	check(str(rules.units.rivet_zeppelin.secondary_weapon)=="rivet_zeppelin_mg","independent gun is configured")
	for native_mode in [false,true]:
		var sim=fixture(native_mode)
		var id: int=sim._spawn(0,"rivet_zeppelin",Vector2(20,20),true)
		var e: Dictionary=sim.entities[id]
		var ground: int=quiet(sim,"kestrel_tank",Vector2(20.6,20))
		var plane: int=quiet(sim,"kestrel_fighter",Vector2(24.5,20))
		sim._rebuild_spatial()
		e.commands=[{"kind":"attack","target":ground,"pos":sim.entities[ground].pos}]
		sim._launch_shot(e,sim.entities[ground].pos,ground,false)
		check(sim.projectiles.size()==1,"close bombardment creates one falling bomb")
		if sim.projectiles.is_empty(): close(sim); continue
		var bomb: Dictionary=sim.projectiles[0]
		check(bomb.start==e.pos and bomb.landing==e.pos,"stationary bomb is released under gondola, not at target")
		check(int(e.ammo)==5,"one bomb uses one magazine slot")
		var bomb_cooldown: float=e.cooldown
		Z.step_secondary(sim,.01)
		check(int(e.zeppelin_mg_target)==plane,"defensive gun chooses aircraft while bombing surface order remains")
		check(float(sim._damage.get(plane,0))>0,"independent gun applies real anti-air damage")
		check(int(e.ammo)==5 and float(e.cooldown)==bomb_cooldown,"machine gun neither consumes bomb magazine nor changes bomb cooldown")
		check(sim.events.any(func(event): return event.get("weapon_slot","")=="bomb") and sim.events.any(func(event): return event.get("weapon_slot","")=="secondary"),"both weapons produce actual fire events together")
		check(int(e.commands[0].target)==ground,"independent gun keeps bombing command")
		e.ammo=0; e.zeppelin_mg_cooldown=0.0; sim._damage.clear()
		Z.step_secondary(sim,.01)
		check(float(sim._damage.get(plane,0))>0,"empty bomb magazine does not disable defensive gun")
		e.emp_until=sim.time+1; e.zeppelin_mg_cooldown=0.0; sim._damage.clear()
		Z.step_secondary(sim,.01)
		check(sim._damage.is_empty(),"EMP disables secondary gun")
		e.emp_until=0.0
		sim.entities[ground].pos=Vector2(30,30)
		var release: Vector2=bomb.start
		check(not Z.step_bomb(sim,bomb,.25),"bomb remains airborne after quarter second")
		check(is_equal_approx(float(bomb.gravity_y),float(bomb.gravity_origin_y)-.5*9.8*.25*.25),"fall follows y=y0-0.5gt^2")
		check(bomb.pos==release and bomb.landing==release,"moving target never drags falling bomb")
		var current_y: float=bomb.gravity_y
		Z.step_bomb(sim,bomb,.25)
		check(float(bomb.gravity_y)<current_y and float(bomb.gravity_velocity)<-4.8,"downward velocity increases with gravity")
		var hit: bool=Z.step_bomb(sim,bomb,2.0)
		check(hit and is_equal_approx(float(bomb.gravity_y),0.0),"bomb resolves at real ground contact")
		check((Z.bomb_transform(bomb).origin as Vector3).y==float(bomb.gravity_y),"rendered bomb uses authoritative world altitude")
		close(sim)
		# Run the real unit dispatcher, not just the standalone secondary helper.
		sim=fixture(native_mode)
		id=sim._spawn(0,"rivet_zeppelin",Vector2(12,20),true); e=sim.entities[id]
		plane=quiet(sim,"kestrel_fighter",Vector2(25,20)); sim._rebuild_spatial()
		sim.issue([id],"attack",sim.entities[plane].pos,plane)
		for frame in range(80): sim.step(.05)
		check((e.pos as Vector2).distance_to(sim.entities[plane].pos)>3.0 and (e.pos as Vector2).distance_to(sim.entities[plane].pos)<=6.05,"air attack approaches gun range, not bomb range: "+str(native_mode))
		check(float(sim.entities[plane].hp)<float(rules.units.kestrel_fighter.hp),"live air attack uses independent gun: "+str(native_mode))
		check(int(e.ammo)==6 and sim.projectiles.is_empty(),"air target never consumes or launches gravity bombs")
		close(sim)
	# Inertial horizontal velocity and real impact area are independent of aim.
	var sim=fixture()
	var id: int=sim._spawn(0,"rivet_zeppelin",Vector2(20,20),true)
	var e: Dictionary=sim.entities[id]
	e.motion=3.4; e.alpha=0.0
	var victim: int=quiet(sim,"kestrel_tank",Vector2(20.6,20))
	sim._rebuild_spatial(); sim._launch_shot(e,sim.entities[victim].pos,victim,false)
	var bomb: Dictionary=sim.projectiles[0]
	check(is_equal_approx(bomb.horizontal_velocity.x,.68) and is_zero_approx(bomb.horizontal_velocity.y),"bomb inherits only 20 percent aircraft horizontal speed")
	e.zeppelin_mg_cooldown=1000
	for i in range(30): sim._step_projectiles(.05)
	check(sim.projectiles.is_empty() and float(sim._damage.get(victim,0))>0,"gravity impact inflicts area damage at actual contact")
	close(sim)
	# Saving mid-fall retains independent timers and the ballistic state.
	sim=Sim.new()
	sim.setup(rules.duplicate(true),"dev",7,"rivet",false)
	sim.vision_enabled=false
	id=sim._spawn(0,"rivet_zeppelin",Vector2(20,20),true); e=sim.entities[id]
	victim=quiet(sim,"kestrel_tank",Vector2(21,20)); sim._rebuild_spatial()
	sim._launch_shot(e,sim.entities[victim].pos,victim,false)
	e.zeppelin_mg_cooldown=.14
	Z.step_bomb(sim,sim.projectiles[0],.25)
	var saved_y: float=sim.projectiles[0].gravity_y
	check(sim.save_game("user://zeppelin_ballistics_test.save").is_empty(),"mid-fall save writes")
	var restored=fixture()
	var restore_error: String=restored.load_game("user://zeppelin_ballistics_test.save")
	check(restore_error.is_empty(),"mid-fall save restores: "+restore_error)
	if restore_error.is_empty():
		check(is_equal_approx(restored.projectiles[0].gravity_y,saved_y) and is_equal_approx(restored.entities[id].zeppelin_mg_cooldown,.14),"save retains bomb altitude and independent gun cooldown")
		Z.step_bomb(sim,sim.projectiles[0],.2); Z.step_bomb(restored,restored.projectiles[0],.2)
		check(is_equal_approx(restored.projectiles[0].gravity_y,sim.projectiles[0].gravity_y),"restored falling bomb follows the same next trajectory")
	close(restored); close(sim)
	var model: Dictionary=V.create_model(rules.units.rivet_zeppelin,"unit",0)
	root.add_child(model.root)
	var guns: Array=model.parts.filter(func(p): return p.role=="zeppelin_mg")
	check(guns.size()==1,"visible independent dorsal machine gun exists")
	V.update_model(model,{"id":1,"alpha":0.0,"zeppelin_mg_alpha":90.0,"zeppelin_mg_pitch":.2,"zeppelin_mg_flash":.1},.05)
	check(is_equal_approx(guns[0].node.rotation.y,-PI*.5) and is_equal_approx(guns[0].node.rotation.z,.2),"dorsal gun yaw and elevation follow its own target")
	model.root.free()
	print("ZEPPELIN_WEAPONS ",JSON.stringify({"checks":checks,"failures":failures}))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
