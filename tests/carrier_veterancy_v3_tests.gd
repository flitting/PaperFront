extends SceneTree
const Sim=preload("res://tests/rule_test_simulation.gd")
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
func fixture():
	var sim=Sim.new();sim.setup_multiteam(RulesLoader.load_rules(),"dev",17,["kestrel","rivet"],false)
	for id in sim.entities.keys():sim._kill_entity(id,false)
	for row in sim.map.terrain:row.fill(0)
	for row in sim.map.heights:row.fill(0)
	sim.mines.clear();sim.ruins.clear();sim.bridges.clear();sim._refresh_mine_spatial();sim._refresh_ruin_spatial();sim._prepare_terrain_cache()
	return sim
func close(sim)->void:
	if sim._path_worker!=null:sim._path_worker.close()
func sortie(star:bool)->float:
	var sim=fixture()
	var carrier:int=sim._spawn(0,"kestrel_carrier",Vector2(18,20),true)
	var enemy:int=sim._spawn(1,"rivet_ship_frigate",Vector2(23,20),true)
	sim.entities[carrier].veteran=star
	sim.entities[carrier].experience_value=100000.0 if star else 0.0
	sim._spawn(0,"kestrel_hq",Vector2(4,8),true);sim._spawn(1,"rivet_hq",Vector2(40,8),true)
	sim.entities[carrier].alpha=0
	preload("res://scripts/air_naval_expansion.gd").carrier_fire(sim,sim.entities[carrier],enemy)
	var plane:int=-1
	for entity:Dictionary in sim.entities.values():
		if int(entity.get("carrier_id",-1))==carrier:plane=int(entity.id);break
	check(plane>0,"real carrier creates a launch aircraft")
	if plane<0:close(sim);return 0.0
	for frame in range(80):
		sim.step(.05)
		if not sim.entities[plane].has("carrier_launch"):break
	check(not sim.entities[plane].has("carrier_launch"),"actual deck roll and climb complete before damage test")
	sim.entities[plane].alpha=rad_to_deg((sim.entities[enemy].pos-sim.entities[plane].pos).angle());sim.entities[plane].turret_alpha=sim.entities[plane].alpha
	sim._rebuild_spatial()
	var before:float=sim.entities[enemy].hp
	sim._fire(sim.entities[plane],enemy);sim._step_projectiles(2);sim._apply_damage()
	var damage:float=before-float(sim.entities[enemy].hp)
	check(not bool(sim.entities[plane].veteran),"carrier damage inheritance does not fake individual aircraft rank")
	close(sim)
	return damage
func run()->void:
	var ordinary:float=sortie(false)
	var veteran:float=sortie(true)
	check(ordinary>0 and veteran>ordinary,"both real sorties damage enemy and veteran carrier is stronger")
	check(is_equal_approx(veteran,ordinary*1.1),"actual carrier aircraft damage inherits exactly10percent")
	var sim=fixture()
	var shooter:int=sim._spawn(0,"kestrel_tank",Vector2(10,20),true)
	var transport:int=sim._spawn(1,"rivet_ship_transport",Vector2(14,20),true)
	var first:int=sim._spawn(1,"rivet_rifle",Vector2(14,22),true)
	var second:int=sim._spawn(1,"rivet_anti",Vector2(14,24),true)
	var value:float=float(sim.data_for("rivet_ship_transport").cost)+float(sim.data_for("rivet_rifle").cost)+float(sim.data_for("rivet_anti").cost)
	sim.Transport._board(sim,sim.entities[first],sim.entities[transport]);sim.Transport._board(sim,sim.entities[second],sim.entities[transport])
	sim._add_damage(transport,10000,false,{"source":shooter,"source_team":0,"weapon":"kestrel_tank"});sim._apply_damage()
	check(not sim.entities.has(transport) and not sim.entities.has(first) and not sim.entities.has(second),"destroyed transport loses its actual embarked units")
	check(is_equal_approx(float(sim.entities[shooter].experience_value),value),"transport and passenger kill values credit their real attacker once")
	close(sim)
	print("CARRIER_VETERANCY_V3 ",JSON.stringify({"checks":checks,"failures":failures,"ordinary_damage":ordinary,"carrier_veteran_damage":veteran}))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
