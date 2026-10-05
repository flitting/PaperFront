extends SceneTree
const Sim=preload("res://tests/rule_test_simulation.gd")
const Rules=preload("res://scripts/rules_loader.gd")
var checks:int=0
var failures:Array[String]=[]
var config:Dictionary
var ids:Array[String]=["rivet","kestrel"]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
func _initialize()->void:
	config=Rules.load_rules()
	for team in range(2,8):
		var source:String="rivet" if team%2==0 else "kestrel"
		var faction:String="cpu_"+str(team)
		ids.append(faction)
		config.factions[faction]=config.factions[source].duplicate(true)
		config.factions[faction].name="临时测试势力 "+str(team)
		for category in ["units","buildings","weapons"]:
			for raw in config[category].keys():
				var key:String=str(raw)
				if not key.begins_with(source+"_"):continue
				var spec:Dictionary=config[category][raw].duplicate(true)
				if spec.has("faction"):spec.faction=faction
				if category!="weapons":
					spec.art_faction=source
					if not str(spec.get("weapon","")).is_empty():spec.weapon=faction+str(spec.weapon).trim_prefix(source)
					var required:Array=[]
					for value in spec.get("requires",[]):required.append(faction+str(value).trim_prefix(source) if str(value).begins_with(source+"_") else value)
					spec.requires=required
				config[category][faction+key.trim_prefix(source)]=spec
	check(Rules.validate(config,false).is_empty(),"eight temporary faction templates retain valid production and combat rules")
	test_ownership_and_arrays()
	test_hostile_teams_and_damage()
	test_airfield_occupancy()
	test_results_and_roundtrip()
	print("Multiteam checks: ",checks-failures.size()," passed, ",failures.size()," failed")
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
func fixture():
	var sim=Sim.new()
	var positions:Array[Vector2]=[]
	for team in range(8):positions.append(Vector2(4.0+5.0*team,43.0))
	sim.setup_multiteam(config,"dev",7,ids,false,positions)
	return sim
func test_ownership_and_arrays()->void:
	var sim=fixture()
	check(sim.factions==ids and sim.money.size()==8 and sim.building_orders.size()==8 and sim._low_power.size()==8 and sim._team_spatial.size()==8,"all authoritative and spatial team arrays contain eight independent owners")
	for team in range(8):
		check(sim.counts(team).y==1 and sim._has_role(team,"hq") and sim.power(team).x==float(config.buildings[ids[team]+"_hq"].power),"each team has exactly its own headquarters, technology and power: "+str(team))
	check(sim.build(7,ids[7]+"_power").is_empty() and sim.building_orders[0].is_empty(),"team 7 can purchase an independent construction order without changing team 0")
	var original:float=sim.money[0]
	sim.step(1.0/30)
	check(sim.entities.size()==8 and sim.money[0]==original and sim.building_orders[7].remaining<float(config.buildings[ids[7]+"_power"].build_time),"all eight teams update while preserving unrelated funds and orders")
	check(sim.cancel_build(7).is_empty() and not sim.build(8,ids[7]+"_power").is_empty(),"construction cancellation uses dynamic team bounds")
func test_hostile_teams_and_damage()->void:
	var sim=fixture()
	var attacker:int=sim.debug_spawn(7,ids[7]+"_rifle",Vector2(6.5,37.5))
	var friendly:int=sim.debug_spawn(7,ids[7]+"_rifle",sim.entities[attacker].pos+Vector2(1,0))
	var enemy:int=sim.debug_spawn(4,ids[4]+"_rifle",sim.entities[attacker].pos+Vector2(0,-3))
	sim._rebuild_spatial()
	check(sim._nearest_enemy(sim.entities[attacker],5.0)==enemy,"team 7 recognizes nearby team 4 as hostile while excluding closer same-owner infantry")
	var hp:float=sim.entities[enemy].hp
	sim.entities[attacker].alpha=rad_to_deg((sim.entities[enemy].pos-sim.entities[attacker].pos).angle())
	sim._fire(sim.entities[attacker],enemy);sim._apply_damage();sim._damage.clear()
	check(float(sim.entities[enemy].hp)<hp and float(sim.entities[friendly].hp)==float(config.units[ids[7]+"_rifle"].hp),"independent foreign ownership receives real weapon damage without changing friendly infantry")
	sim._in_step=true
	sim._impact_damage(sim.entities[attacker].pos,10.0,5.0,{},["ground"],true)
	check(sim._damage.has(attacker) and sim._damage.has(enemy) and sim._damage.has(friendly),"localized forced AoE retains friendly fire across all owner buckets")
	sim._in_step=false
func test_airfield_occupancy()->void:
	var sim=fixture()
	sim.debug_spawn(7,ids[7]+"_power",Vector2(7.5,14.5))
	sim.debug_spawn(7,ids[7]+"_command",Vector2(18.5,14.5))
	var field:int=sim.debug_spawn(7,ids[7]+"_airfield",Vector2(12.5,23.5))
	var first:int=sim.debug_spawn(7,ids[7]+"_fighter",sim.entities[field].pos)
	var second:int=sim.debug_spawn(7,ids[7]+"_fighter",sim.entities[field].pos)
	sim._in_step=true
	check(sim._airfield_load(field,false)==2 and sim.entities[first].home_airfield==field and sim.entities[second].home_airfield==field,"team 7 aircraft reserve only their actual friendly airport")
	check(sim.produce(field,ids[7]+"_fighter").is_empty() and sim._airfield_load(field)==3,"warm airport occupancy includes new production queue reservations")
	sim._kill_entity(first,true)
	check(sim._airfield_load(field)==2,"aircraft death releases its warm airport reservation in the same tick")
	var engineer:int=sim._spawn(4,ids[4]+"_engineer",sim.entities[field].pos+Vector2(-3.0,0),true)
	sim._step_capture(sim.entities[engineer],{"kind":"capture","target":field},1.0/30)
	check(sim.entities[field].team==4 and sim.entities[second].home_airfield==-1 and sim._airfield_load(field)==0,"airport capture by a third-party owner detaches old aircraft and cancels old queue reservations")
	sim._in_step=false
func test_results_and_roundtrip()->void:
	var sim=fixture()
	var path:String="/tmp/paper_war_multiteam.save"
	check(sim.save_game(path).is_empty(),"eight independent team state writes a snapshot")
	var restored=Sim.new()
	var error:String=restored.load_game(path)
	check(error.is_empty() and restored.factions==sim.factions and restored.money==sim.money and restored.entities==sim.entities and restored._team_spatial.size()==8,"eight owner arrays and reconstructed indices survive save/load: "+error)
	if error.is_empty():
		for i in range(10):sim.step(1.0/30);restored.step(1.0/30)
		check(restored.entities==sim.entities and restored.money==sim.money and restored.building_orders==sim.building_orders,"multiteam snapshots retain deterministic authoritative progression")
	DirAccess.remove_absolute(path)
	for id in sim.entities.keys():
		if int(sim.entities[id].team)>0:sim._kill_entity(id,true)
	sim._check_result()
	check(sim.result=="win","the player wins only after all seven independent enemy building owners are eliminated")
	sim=fixture();sim._kill_entity(1,true);sim._check_result()
	check(sim.result=="lose" and sim.counts(7).y==1,"player building elimination loses while independent foreign factions remain")
