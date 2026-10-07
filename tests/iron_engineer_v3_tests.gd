extends SceneTree
const Sim=preload("res://tests/rule_test_simulation.gd")
const Rules=preload("res://scripts/rules_loader.gd")
var failures:Array[String]=[]
var checks:int=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
func _initialize()->void:
	var config:Dictionary=Rules.load_rules()
	var sim=Sim.new()
	sim.setup_multiteam(config,"dev",7,["iron","iron"],false,[Vector2(6,40),Vector2(42,6)])
	sim.mines.clear();sim.ruins.clear()
	sim._refresh_ruin_spatial();sim._refresh_mine_spatial();sim._prepare_terrain_cache();sim._rebuild_nav()
	sim.money.assign([10000.0,10000.0])
	var p:=Vector2(17.5,39.5)
	var engineer:int=sim._spawn(0,"iron_engineer",p+Vector2(0,-1.35),true)
	var enemy_engineer:int=sim._spawn(1,"iron_engineer",Vector2(36,30),true)
	check(not sim.build(0,"iron_rail",enemy_engineer).is_empty(),"enemy engineer cannot build owner's railway")
	check(sim.build(0,"iron_rail",engineer).is_empty(),"engineer orders actual railway construction")
	var channel:String=sim.construction_channel("iron_rail")
	check(sim.rotate_build_order(0,2,channel).is_empty(),"engineer preview rotates by two quarters")
	check(int(sim.order_for_team(0,channel).rotation_quarters)==2,"engineer railway preview stores q2")
	var funds:float=sim.money[0]
	check(sim.place_building(0,p,channel).is_empty(),"engineer places railway site")
	check(is_equal_approx(sim.money[0],funds),"field railway has no up-front payment")
	var track:int=wait_site(sim,p)
	check(track>0,"engineer physically creates railway scaffold")
	if track<=0:finish();return
	check(sim.entities[track].has("construction") and float(sim.entities[track].construct_remaining)>0,"railway scaffold waits for paid work")
	check(int(sim.entities[track].rail_rotation)==2,"actual scaffold keeps q2")
	var path:String="user://iron_engineer_v3.save"
	check(sim.save_game(path).is_empty(),"save live railway construction")
	var restored=Sim.new()
	var error:String=restored.load_game(path)
	check(error.is_empty(),"load live railway construction: "+error)
	if not error.is_empty():finish();return
	sim=restored
	check(wait_complete(sim,track),"loaded engineer resumes and completes railway")
	check(is_equal_approx(funds-sim.money[0],float(config.buildings.iron_rail.cost)),"completed field rail pays exact cost")
	check(not sim._rail_network.at(0,p).is_empty() and sim._rail_network.at(1,p).is_empty(),"completed rail joins owner-only usable network")
	# Q2 junction accepts north and blocks south. Construction is interrupted
	# for funds, saved mid-progress, then resumed through the real work command.
	var junction_pos:Vector2=p+Vector2(2,0)
	sim.entities[engineer].pos=junction_pos+Vector2(0,-1.35)
	sim._rebuild_spatial()
	check(sim.build(0,"iron_rail_junction",engineer).is_empty(),"engineer orders actual junction")
	channel=sim.construction_channel("iron_rail_junction")
	sim.rotate_build_order(0,2,channel)
	check(sim.place_building(0,junction_pos,channel).is_empty(),"engineer places q2 junction")
	var junction:int=wait_site(sim,junction_pos)
	check(junction>0,"engineer physically creates junction scaffold")
	if junction<=0:finish();return
	sim.money[0]=10.0
	for i in range(30):sim.step(1.0/30.0)
	check(float(sim.entities[junction].construct_remaining)>0 and sim.entities[junction].has("construction"),"insufficient funds pause actual junction work")
	check(is_equal_approx(sim.money[0],0) and is_equal_approx(float(sim.entities[junction].construction.spent),10),"junction spends only available money")
	check(sim._rail_network.at(0,junction_pos).is_empty(),"unpaid scaffold is not usable railway")
	check(sim.save_game(path).is_empty(),"save partially paid rotated junction")
	restored=Sim.new();error=restored.load_game(path)
	check(error.is_empty(),"load partially paid rotated junction: "+error)
	if not error.is_empty():finish();return
	sim=restored;sim.money[0]=100.0
	check(wait_complete(sim,junction),"engineer finishes loaded junction after funds arrive")
	check(is_equal_approx(100.0-sim.money[0],float(config.buildings.iron_rail_junction.cost)-10.0),"loaded junction pays exact remaining cost without double charging")
	check(int(sim.entities[junction].rail_rotation)==2 and int(sim.entities[junction].rail_ports)==13,"completed q2 junction exposes north/east/west ports")
	var north:Vector2=junction_pos+Vector2.UP
	sim.entities[engineer].pos=north+Vector2(0,-1.35);sim._rebuild_spatial()
	check(sim.build(0,"iron_rail",engineer).is_empty(),"engineer orders connecting north branch")
	channel=sim.construction_channel("iron_rail")
	check(sim.placement_error(0,north,channel).is_empty(),"q2 junction accepts the formerly blocked north side")
	check(sim.place_building(0,north,channel).is_empty(),"north branch site accepted")
	var branch:int=wait_site(sim,north)
	check(branch>0 and wait_complete(sim,branch),"engineer constructs the north branch")
	check(not sim._rail_network.path(0,junction_pos,north).is_empty(),"completed branch is connected and traversable")
	check(not sim._rail_network.site_error(sim,0,config.buildings.iron_rail,junction_pos+Vector2.DOWN).is_empty(),"q2 blocked south side remains illegal")
	check(sim.save_game(path).is_empty(),"save completed engineer-built network")
	restored=Sim.new();error=restored.load_game(path)
	check(error.is_empty() and not restored._rail_network.path(0,junction_pos,north).is_empty(),"loaded completed network preserves q2 connectivity")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	finish()
func wait_site(sim,pos:Vector2)->int:
	for i in range(300):
		sim.step(1.0/30.0)
		for e:Dictionary in sim.entities.values():
			if e.kind=="building" and sim.RailNetwork.is_rail(sim.data_for(e.spec)) and (e.pos as Vector2).distance_to(pos)<.01:return int(e.id)
	return -1
func wait_complete(sim,id:int)->bool:
	if id<0:return false
	for i in range(300):
		sim.step(1.0/30.0)
		if sim.entities.has(id) and float(sim.entities[id].construct_remaining)<=0 and not sim.entities[id].has("construction"):return true
	return false
func finish()->void:
	print("IRON_ENGINEER_V3 ",JSON.stringify({"checks":checks,"failures":failures}))
	for message:String in failures:push_error(message)
	quit(0 if failures.is_empty() else 1)
