extends SceneTree
const Sim=preload("res://tests/rule_test_simulation.gd")
const Factions=preload("res://scripts/performance_factions.gd")
var threaded:bool=false
var worker=preload("res://scripts/simulation_render_overlap.gd").new()
var checks:int=0
var failures:Array[String]=[]
func fixture(all_types:bool=false):
	var sim=Sim.new()
	var hqs:Array[Vector2]=[]
	for team in range(8):hqs.append(Vector2(4+team*5,43))
	sim.setup_multiteam(Factions.make_rules(RulesLoader.load_rules()),"dev",7,Factions.ids(),false,hqs)
	for team in range(8):
		sim.money[team]=100000.0
		var faction:String=sim.factions[team]
		for role in ["power","airfield","repair","barracks"]:
			var building_id:String=sim.building_spec(team,role)
			if building_id.is_empty(): continue # Removed support buildings have no current blueprint.
			var id:int=sim._spawn(team,building_id,Vector2(3.5+5*team,18.5+3*["power","airfield","repair","barracks"].find(role)),true)
			sim.entities[id].gift_pending=false
		var roles:Array=[]
		if all_types:
			for id in sim.rules.units:
				if sim.rules.units[id].faction==faction:roles.append(str(id).trim_prefix(faction+"_"))
		else:roles=["tank","rifle","aa","artillery","scout","engineer","harvester","fighter","attacker","anti"]
		for i in range(roles.size()):
			var role:String=roles[i]
			if role=="attacker" and sim.rules.units.has(faction+"_bomber"):role="bomber"
			if role=="artillery" and not sim.rules.units.has(faction+"_artillery"):role="advanced"
			if not sim.rules.units.has(faction+"_"+role): continue # Rivet economy has no harvester.
			var id:int=sim._spawn(team,faction+"_"+role,Vector2(3.5+5*team,33.5+float(i%6)*1.4),true)
			sim.entities[id].alpha=wrapf(float(id*31),-180,180)
			sim.entities[id].turret_alpha=wrapf(float(id*17),-180,180)
			if role=="engineer":sim.entities[id].yield_goal=Vector2(3.5+5*team,37.5);sim.entities[id].yield_until=.3
	return sim
func stimulus(sim,tick:int)->void:
	if tick%47==0:
		# Cached native definition views must observe edits between ticks,
		# including after a save/load restores its historical rule snapshot.
		for info in sim.rules.units.values():
			if info.get("art","") in ["tank","assault"]:
				info.fire_while_moving=tick%94==0
				info.turn_speed=120.0 if tick%94==0 else 240.0
				info.turret_turn_speed=180.0 if tick%94==0 else 300.0
		for weapon in sim.rules.weapons.values():weapon.range=8.0 if tick%94==0 else 14.0
	if tick%40==0:
		for team in range(8):
			var units:Array=[]
			for e in sim.entities.values():
				if int(e.team)==team and e.kind=="unit" and not str(e.spec).ends_with("_harvester"):units.append(e.id)
			var kind:String=["attack_move","move","patrol","stop","attack_move"][int(tick/40)%5]
			sim.issue(units,kind,Vector2(3.5+5*((team+1)%8),38.5))
	if tick%53==0:
		for e in sim.entities.values():
			if e.kind=="unit" and str(e.spec).ends_with("_fighter"):e.ammo=0
	if tick%67==0:
		for e in sim.entities.values():
			if e.kind=="unit" and str(e.spec).ends_with("_tank"):
				var target:int=-1
				for other in sim.entities.values():
					if other.kind=="unit" and other.team!=e.team:target=int(other.id);break
				if target>0:sim.issue([e.id],"force_attack" if tick%2 else "attack",sim.entities[target].pos,target)
	if tick==75:
		for e in sim._building_entities:
			if int(e.team)==2 and sim.data_for(e.spec).get("role","")=="airfield":sim._kill_entity(int(e.id),true);break
	if tick==120:
		sim._spawn(2,"iron_airfield",Vector2(13.5,21.5),true)
func difference(a:Variant,b:Variant,path:String)->String:
	if a==b:return ""
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return path+" dictionary size"
		for key in a:
			if not b.has(key):return path+" missing "+str(key)
			var nested:String=difference(a[key],b[key],path+"."+str(key))
			if not nested.is_empty():return nested
	elif a is Array and b is Array:
		if a.size()!=b.size():return path+" array size"
		for i in range(a.size()):
			var nested:String=difference(a[i],b[i],path+"["+str(i)+"]")
			if not nested.is_empty():return nested
	return path+": "+str(a)+" != "+str(b)
func _initialize()->void:
	threaded="--threaded-tick-equivalence" in OS.get_cmdline_user_args()
	if threaded and worker.start()!=OK:push_error("Cannot start equivalence worker");quit(1);return
	if not ClassDB.class_exists("PaperFrontKernels"):
		push_error("Native unit kernel missing");quit(1);return
	for all_types in [false,true]:
		var fast=fixture(all_types)
		var reference=fixture(all_types)
		fast.native_unit_dispatch_enabled=true
		reference.native_unit_dispatch_enabled=false
		reference.native_geometry_enabled=false
		for tick in range(300):
			stimulus(fast,tick);stimulus(reference,tick)
			if threaded:worker.dispatch(fast,1.0/30.0);worker.collect()
			else:fast.step(1.0/30.0)
			reference.step(1.0/30.0)
			for field in ["entities","projectiles","events","money","mines","bridges","ruins","building_orders","time","result"]:
				checks+=1
				var mismatch:String=difference(fast.get(field),reference.get(field),field)
				if not mismatch.is_empty():failures.append("all_types %s tick %d: %s"%[all_types,tick,mismatch]);break
			if not failures.is_empty():break
			fast.events.clear();reference.events.clear()
			if tick==160:
				var path:String="/tmp/paper_native_tick_equivalence.pfront"
				var error:String=fast.save_game(path)
				if not error.is_empty():failures.append(error);break
				fast=Sim.new();reference=Sim.new()
				var fast_error:String=fast.load_game(path)
				var reference_error:String=reference.load_game(path)
				checks+=1
				if not fast_error.is_empty() or not reference_error.is_empty():failures.append("cannot reload comparison checkpoint");break
				fast.native_unit_dispatch_enabled=true;reference.native_unit_dispatch_enabled=false;reference.native_geometry_enabled=false
				DirAccess.remove_absolute(path)
		if not failures.is_empty():break

	if threaded and worker.worker_thread_id==OS.get_thread_caller_id():failures.append("comparison did not execute on a worker")
	worker.close()
	print("NATIVE_UNIT_TICK ",JSON.stringify({"checks":checks,"threaded":threaded,"failures":failures}))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
