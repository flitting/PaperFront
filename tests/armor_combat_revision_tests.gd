extends SceneTree
const Sim=preload("res://tests/rule_test_simulation.gd")
const Combat=preload("res://scripts/armor_combat.gd")
var checks:=0
var failures:Array[String]=[]
var rules:Dictionary
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
func fixture():
	var sim=Sim.new();sim.setup_multiteam(rules,"dev",7007,["sky","kestrel"],false)
	for id in sim.entities.keys():sim._kill_entity(id,false)
	for row in sim.map.terrain:row.fill(0)
	for row in sim.map.heights:row.fill(0.0)
	sim.mines.clear();sim.ruins.clear();sim.bridges.clear();sim._refresh_mine_spatial();sim._refresh_ruin_spatial()
	sim._prepare_terrain_cache();sim._nav_initialized=false;sim._rebuild_nav()
	sim._spawn(0,"sky_hq",Vector2(5,43),true);sim._spawn(1,"kestrel_hq",Vector2(43,43),true)
	return sim
func close(sim)->void:
	if sim._path_worker!=null:sim._path_worker.close()
func catalog()->void:
	for id in rules.units:
		var u:Dictionary=rules.units[id]
		var infantry:bool=u.armor_class=="infantry"
		check(int(u.logical_size)==(1 if infantry else 2) and is_equal_approx(float(u.radius),.5 if infantry else 1.0),id+" latest exact footprint")
		check(float(u.armor)>=0 and float(u.armor)==floorf(float(u.armor)),id+" explicit integer armor")
	for id in rules.buildings:check(rules.buildings[id].has("armor"),id+" explicit building armor")
	for id in rules.weapons:
		var w:Dictionary=rules.weapons[id]
		check(w.has("penetration") and float(w.penetration)>=0,id+" explicit penetration")
		if w.get("damage_type","")=="electric" or id=="sky_creator_hand":check(int(w.penetration)==9999,id+" electrical/hand penetration exactly9999")
		if float(w.blast)>0:check(w.get("aoe_falloff","")=="linear",id+" radial damage and penetration falloff")
	for faction in rules.factions:
		var families:Dictionary={}
		for id in rules.units:
			var u:Dictionary=rules.units[id]
			if u.faction!=faction:continue
			if families.has(u.armor_family):check(families[u.armor_family]==u.armor,faction+" same armor family consistent: "+u.armor_family)
			else:families[u.armor_family]=u.armor
	check(rules.units.sky_creator_hand.cost==5000 and rules.units.sky_creator_hand.hp==6667,"hand cost/HP reduced to one third")
	check(rules.weapons.sky_creator_hand.damage==300 and rules.weapons.sky_creator_hand.blast==3 and not rules.weapons.sky_creator_hand.get("execute_building",false),"hand damage one third and real area strike without building execution")
func boundaries()->void:
	for protection in [49,50,51]:
		check(Combat.penetration_factor({"penetration":50},protection)==(1.0 if protection<50 else .25),"strict greater/equal/lower penetration "+str(protection))
	check(Combat.penetration_factor({},9999)==1,"historical snapshots without penetration retain original behavior")
	check(Combat.falloff({},3,4)==1,"historical splash remains its saved original behavior")
	for kind in ["instant","laser","shell","beam"]:
		for protection in [49,50]:
			var sim=fixture();sim.rules.units.kestrel_tank.armor=protection
			var w:Dictionary=sim.rules.weapons.sky_tank
			w.kind=kind;w.damage=80;w.range=20;w.blast=0;w.penetration=50;w.multipliers={};w.speed=20;w.beam_duration=1.0
			var source:int=sim._spawn(0,"sky_tank",Vector2(10,20),true)
			var target:int=sim._spawn(1,"kestrel_tank",Vector2(15,20),true)
			sim.entities[target].hp=1000.0;sim._rebuild_spatial()
			sim._fire(sim.entities[source],target)
			if kind=="shell":sim._step_projectiles(1)
			if kind=="beam":sim.BeamWeapons.step(sim,1)
			sim._apply_damage()
			var expected:float=80.0 if protection<50 else 40.0
			check(is_equal_approx(float(sim.entities[target].hp),1000.0-expected),kind+" actual attack settles armor boundary "+str(protection))
			close(sim)
func splash()->void:
	var sim=fixture();sim.rules.units.kestrel_tank.armor=60
	var ids:Array[int]=[]
	for p in [Vector2(20,20),Vector2(23,20),Vector2(25,20)]:
		var id:int=sim._spawn(1,"kestrel_tank",p,true);sim.entities[id].hp=1000.0;ids.append(id)
	sim._rebuild_spatial()
	var weapon:Dictionary={"penetration":100,"aoe_falloff":"linear","kind":"shell"}
	sim._impact_damage(Vector2(20,20),4,100,{},["ground"],false,weapon,0);sim._apply_damage()
	check(is_equal_approx(float(sim.entities[ids[0]].hp),900),"blast center full damage and full penetration")
	check(is_equal_approx(float(sim.entities[ids[1]].hp),975),"half-radius damage halves and penetration50 partially penetrates armor60, yielding25")
	check(is_equal_approx(float(sim.entities[ids[2]].hp),1000),"outer wave edge reaches zero damage")
	close(sim)
func hand_and_emp()->void:
	var sim=fixture()
	var hand:int=sim._spawn(0,"sky_creator_hand",Vector2(16,20),true)
	var center:int=sim._spawn(1,"kestrel_tank",Vector2(21,20),true)
	var nearby:int=sim._spawn(1,"kestrel_tank",Vector2(23,20),true)
	var outside:int=sim._spawn(1,"kestrel_tank",Vector2(25.2,20),true)
	var friend:int=sim._spawn(0,"sky_tank",Vector2(20,20),true)
	var building:int=sim._spawn(1,"kestrel_power",Vector2(21,23),true)
	for id in [center,nearby,outside,friend,building]:sim.entities[id].hp=1000.0
	sim._rebuild_spatial();sim._fire(sim.entities[hand],center)
	sim.HeroRules.step(sim,.49);check(sim._damage.is_empty(),"hand respects pre-impact windup")
	sim.HeroRules.step(sim,.02);sim._apply_damage()
	check(is_equal_approx(float(sim.entities[center].hp),700),"hand center receives300 area damage")
	check(float(sim.entities[nearby].hp)<1000 and float(sim.entities[nearby].hp)>700,"hand hits nearby enemy with radial falloff")
	check(float(sim.entities[outside].hp)==1000 and float(sim.entities[friend].hp)==1000,"hand preserves out-of-radius enemy and friendly units")
	check(sim.entities.has(building) and float(sim.entities[building].hp)>0,"hand applies damage to buildings without old instant kill")
	close(sim)
	sim=fixture();sim.rules.units.kestrel_tank.armor=9999
	var source:int=sim._spawn(0,"sky_disruptor",Vector2(10,20),true)
	var target:int=sim._spawn(1,"kestrel_tank",Vector2(13,20),true)
	sim._rebuild_spatial();sim._fire(sim.entities[source],target)
	check(float(sim.entities[target].get("emp_until",0))>sim.time,"EMP status unaffected by armor reduction")
	close(sim)
func snapshots()->void:
	# Keep the actual generated four-height map: flattened diagnostic arenas
	# are intentionally rejected by the production save validator.
	var sim=Sim.new();sim.setup_multiteam(rules,"dev",7007,["sky","kestrel"],false)
	sim.rules.units.kestrel_tank.armor=100
	var w:Dictionary=sim.rules.weapons.sky_tank
	w.kind="shell";w.damage=80;w.range=20;w.blast=0;w.penetration=100;w.multipliers={};w.speed=10
	var source:int=sim._spawn(0,"sky_tank",Vector2(8.5,42.5),true)
	var target:int=sim._spawn(1,"kestrel_tank",Vector2(13.5,42.5),true)
	sim._rebuild_spatial();sim._fire(sim.entities[source],target);sim._step_projectiles(.1)
	check(sim.projectiles.size()==1,"real shell is still in flight before save")
	var path:String="user://armor_combat_inflight.save"
	check(sim.save_game(path).is_empty(),"armor/AP rules and in-flight shell save")
	var restored=Sim.new();var problem:String=restored.load_game(path)
	check(problem.is_empty(),"armor/AP save restores: "+problem)
	if problem.is_empty():
		for state in [sim,restored]:state._step_projectiles(1);state._apply_damage()
		check(is_equal_approx(float(sim.entities[target].hp),float(restored.entities[target].hp)) and is_equal_approx(float(restored.entities[target].hp),440),"restored equal armor shell still deals exactly half damage")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path));close(sim);close(restored)
	var legacy:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/historical_rules/before_armor_20261007.json"))
	check(RulesLoader.validate(legacy,false).is_empty(),"previous unarmored rule snapshot remains valid")
	var invalid:Dictionary=rules.duplicate(true);invalid.weapons.sky_tank.penetration=-1
	check(not RulesLoader.validate(invalid,false).is_empty(),"negative penetration is rejected")
	invalid=rules.duplicate(true);invalid.units.sky_tank.armor=2.5
	check(not RulesLoader.validate(invalid,false).is_empty(),"fractional armor is rejected")
func run()->void:
	rules=RulesLoader.load_rules();check(not rules.is_empty(),"production rules validate")
	if not rules.is_empty():catalog();boundaries();splash();hand_and_emp();snapshots()
	var result:Dictionary={"checks":checks,"failures":failures}
	var f=FileAccess.open("res://artifacts/rts_revision_v2_20261007/armor_combat.json",FileAccess.WRITE);f.store_string(JSON.stringify(result,"  "));f.close()
	print("ARMOR_COMBAT_REVISION ",JSON.stringify(result))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
