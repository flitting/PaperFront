extends SceneTree
const Sim = preload("res://tests/rule_test_simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
var checks := 0
var failures: Array[String] = []
var config: Dictionary
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func fixture():
	var sim = Sim.new()
	sim.setup_multiteam(config,"dev",7,["iron","iron"],false,[Vector2(6,40),Vector2(42,6)])
	for z in range(sim.map.size):
		for x in range(sim.map.size):
			sim.map.terrain[z][x] = 0
			sim.map.heights[z][x] = 0.0
	sim.mines.clear(); sim.bridges.clear(); sim.ruins.clear()
	sim._refresh_ruin_spatial(); sim._refresh_mine_spatial(); sim._prepare_terrain_cache()
	sim.money.assign([100000.0,100000.0])
	return sim
func rail(sim, p: Vector2, role: String = "rail", rotation: int = 0, team: int = 0) -> int:
	var id: int = sim._spawn(team,"iron_"+role,p,true)
	sim.entities[id].rail_rotation = rotation
	sim._rail_network.rebuild(sim)
	return id
func err(sim,p:Vector2,role:String="rail",rotation:int=0)->String:
	return sim._rail_network.site_error(sim,0,sim.data_for("iron_"+role),p,rotation)
func _initialize()->void: call_deferred("run")
func run()->void:
	config=Rules.load_rules()
	if config.is_empty():
		push_error("Rules unavailable")
		quit(1)
		return
	topology(); movement(); production(); automatic(); combat(); bridge(); full_tick(); saved_network(); ai_economy(); full_size_mining_cycle(); rail_clearance()
	print("RAIL_NETWORK ",JSON.stringify({"checks":checks,"failures":failures}))
	for message in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)
func topology()->void:
	var sim=fixture()
	var p:=Vector2(30.5,30.5)
	var a:int=rail(sim,p)
	rail(sim,p+Vector2.RIGHT)
	check(err(sim,p+Vector2(1,1)).is_empty(),"legal orthogonal corner")
	var b:int=rail(sim,p+Vector2(1,1))
	check(int(sim.entities[b].rail_mask)==8,"endpoint mask north")
	check(not err(sim,p+Vector2.DOWN).is_empty(),"square loop rejected")
	check(not err(sim,p+Vector2(1,-1)).is_empty(),"ordinary third connection rejected")
	check(err(sim,p+Vector2(-1,-1)).is_empty(),"ordinary diagonal proximity permitted")
	var q:=Vector2(40.5,30.5)
	var j:int=rail(sim,q,"rail_junction")
	check(int(sim.entities[j].rail_ports)==7,"junction three ports exclude north")
	check(not err(sim,q+Vector2.UP).is_empty(),"blocked fourth port and nonconnected side spacing rejected")
	check(not err(sim,q+Vector2.RIGHT,"rail_junction").is_empty(),"adjacent junctions rejected")
	for direction in [Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT]: rail(sim,q+direction)
	check(int(sim.entities[j].rail_mask)==7,"three junction branches connected")
	check(sim._rail_network.path(1,p,p+Vector2.RIGHT).is_empty(),"same faction different owner cannot use network")
	check(not sim._is_victory_building(sim.entities[a]),"rail excluded from victory")
	var engineer:int=sim._spawn(1,"iron_engineer",p+Vector2(0,-2),true)
	check(not sim.capture_error(engineer,a).is_empty(),"engineer cannot capture rails")
	var loop=fixture()
	var points:Array=[]
	for point in [Vector2(25.5,25.5),Vector2(26.5,25.5),Vector2(26.5,26.5),Vector2(25.5,26.5)]: points.append(point)
	check(not loop._rail_network.batch_error(loop,0,loop.data_for("iron_rail"),points).is_empty(),"batch validates provisional graph and rejects closing loop")
func movement()->void:
	var sim=fixture()
	for x in range(20,36): rail(sim,Vector2(x+.5,30.5))
	var id:int=sim._spawn(0,"iron_train",Vector2(21.5,30.5),true)
	var e:Dictionary=sim.entities[id]
	var speed:float=float(sim.data_for(e.spec).speed)
	sim._move_to(e,Vector2(33.5,30.5),.5)
	check(is_equal_approx(e.pos.x,21.5+speed),"train actual movement is exactly double speed")
	var other:int=sim._spawn(0,"iron_train",e.pos,true)
	check(sim._movement_clear(e,e.pos,e.pos+Vector2(.1,0)),"applicable overlapping trains ignore collisions")
	sim._kill_entity(other,false)
	var old:Vector2=e.pos
	sim._move_to(e,Vector2(28.5,34.5),1)
	check(e.pos==old,"rail-only cannot move onto plain ground")
	var cut:Dictionary=sim._rail_network.cells[Vector2i(27,30)]
	sim._kill_entity(int(cut.id),true)
	sim._move_to(e,Vector2(33.5,30.5),1)
	check(e.pos==old,"track destruction invalidates cached route immediately")
	var infantry:int=sim._spawn(0,"iron_rifle",Vector2(29.5,30.5),true)
	var soldier:Dictionary=sim.entities[infantry]
	sim._move_to(soldier,Vector2(34.5,30.5),.25)
	check(is_equal_approx(soldier.pos.x,29.5+float(sim.data_for(soldier.spec).speed)*.5),"ordinary infantry receive exactly double rail speed")
	var before_short: Vector2 = soldier.pos
	sim._move_to(soldier, before_short + Vector2(.2, 0), .01)
	check(is_equal_approx(soldier.pos.x - before_short.x, float(sim.data_for(soldier.spec).speed) * .02),"short within-cell rail motion retains double speed without a fictitious boarding charge")
	var enemy:int=sim._spawn(1,"iron_train",Vector2(29.5,30.5),true)
	var enemy_old:Vector2=sim.entities[enemy].pos
	sim._move_to(sim.entities[enemy],Vector2(34.5,30.5),1)
	check(sim.entities[enemy].pos==enemy_old,"rail-only enemy cannot borrow same-faction rail")
func production()->void:
	var sim=fixture()
	var id:int=sim._spawn(0,"iron_factory",Vector2(26.5,38.5),true)
	var factory:Dictionary=sim.entities[id]
	check(not sim._spawn_point(factory,"iron_train").is_finite() and bool(factory.rail_waiting),"factory waits for rail at physical exit")
	var point:Vector2=sim._rail_network.exit_cell(sim,factory)
	check(point.y>=factory.pos.y+float(sim.data_for(factory.spec).size)*.5+float(sim.data_for("iron_train").radius)+.02,"rail outlet rounds outward with actual train hull clearance")
	rail(sim,point)
	check(sim._spawn_point(factory,"iron_train")==point,"factory resumes at connected actual exit")
	check(not factory.has("rail_waiting"),"waiting state clears after connection")
func automatic()->void:
	var sim=fixture()
	var id:int=sim._spawn(0,"iron_refinery",Vector2(35,40),true)
	var factory:Dictionary=sim.entities[id]
	sim._rail_network.auto_refinery(sim,factory)
	check(sim._rail_network.cells.size()==1,"no nearby ore creates one exit rail")
	var mining=fixture()
	var refinery:int=mining._spawn(0,"iron_refinery",Vector2(35,40),true)
	mining.mines.append({"pos":Vector2(40.5,47.5),"capacity":10000.0,"amount":10000.0,"miner":-1})
	mining._refresh_mine_spatial()
	mining._rail_network.auto_refinery(mining,mining.entities[refinery])
	var point:Vector2=mining._rail_network.spawn_point(mining,mining.entities[refinery],"iron_harvester")
	check(point.is_finite(),"auto track attaches refinery exit")
	if not point.is_finite(): return
	var harvester:int=mining._spawn(0,"iron_harvester",point,true)
	var goal:Vector2=mining._mining_approach(mining.entities[harvester],0)
	check(goal.is_finite() and goal.distance_to(mining.mines[0].pos)<=mining._radius(mining.entities[harvester])+1.4,"auto route reaches mine approach")
	if goal.is_finite():
		check(not mining._path_between(point,goal,mining._radius(mining.entities[harvester]),harvester).is_empty(),"harvester feasibility uses connected track graph")
		for _tick in range(60): mining._step_harvester(mining.entities[harvester],.1)
		check(float(mining.entities[harvester].cargo)>0,"rail-only harvester physically reaches and gathers ore")
func combat()->void:
	var sim=fixture()
	var id:int=rail(sim,Vector2(30.5,30.5),"rail",0,1)
	var tank:int=sim._spawn(0,"iron_tank",Vector2(28.5,30.5),true)
	check(sim._nearest_enemy(sim.entities[tank],10)==-1,"rail excluded from automatic acquisition")
	sim.step(.1)
	sim._in_step=true
	check(sim._nearest_enemy(sim.entities[tank],10)==-1,"native combat acquisition masks exclude rail after actual spatial rebuild")
	sim._in_step=false
	sim._add_damage(id,100000)
	sim._apply_damage()
	check(not sim.entities.has(id),"forced damage destroys rail")

func bridge()->void:
	var sim=fixture()
	var bounds:Array=[22.0,20.0,5.0,3.0]
	sim.bridges.append({"id":0,"bounds":bounds,"heads":[[21,21],[27,21]],"hp":100.0,"repair_progress":0.0,"alive":true})
	for x in range(22,27):
		for z in range(20,23): sim.map.terrain[z][x]=1
	sim._prepare_terrain_cache()
	check(err(sim,Vector2(24.5,21.5)).is_empty(),"live bridge deck accepts track")
	var track:int=rail(sim,Vector2(24.5,21.5))
	sim._add_damage(sim.BRIDGE_TARGET_BASE,1000,true)
	sim._apply_damage()
	check(not sim.entities.has(track) and sim._rail_network.at(0,Vector2(24.5,21.5)).is_empty(),"bridge destruction destroys track and graph immediately")
	check(not err(sim,Vector2(24.5,21.5)).is_empty(),"destroyed bridge refuses track")
	check(not err(sim,Vector2(22.5,20.5)).is_empty(),"track cannot directly cross sea")
func full_tick()->void:
	var sim=fixture()
	for x in range(15,34): rail(sim,Vector2(x+.5,20.5))
	var a:int=sim._spawn(0,"iron_train",Vector2(16.5,20.5),true)
	var b:int=sim._spawn(0,"iron_train",Vector2(16.5,20.5),true)
	sim.issue([a,b],"move",Vector2(30.5,20.5))
	check(sim.entities[a].commands[0].pos==Vector2(30.5,20.5) and sim.entities[b].commands[0].pos==Vector2(30.5,20.5),"rail group destination permits overlapping trains without off-rail formation offsets")
	for _tick in range(10): sim.step(.1)
	check(sim.entities[a].pos.x>21 and sim.entities[b].pos.x>21,"default native-enabled simulation ticks run overlapping trains on rails")
	var hp_a:float=sim.entities[a].hp
	var hp_b:float=sim.entities[b].hp
	sim._impact_damage(sim.entities[a].pos,2,100,{},["ground"],true)
	sim._apply_damage()
	check(is_equal_approx(hp_a-sim.entities[a].hp,100) and is_equal_approx(hp_b-sim.entities[b].hp,100),"AOE independently damages both overlapping rail units")
	var factory:int=sim._spawn(0,"iron_factory",Vector2(26.5,38.5),true)
	sim._spawn(0,"iron_tech",Vector2(15,40),true)
	check(sim.produce(factory,"iron_train").is_empty(),"train uses actual factory production queue")
	sim.entities[factory].queue[0].remaining=.01
	sim._step_building(sim.entities[factory],1,1)
	check(sim.entities[factory].queue.size()==1 and bool(sim.entities[factory].get("rail_waiting",false)),"finished queue stalls until actual outlet track is connected")
	var exit:Vector2=sim._rail_network.exit_cell(sim,sim.entities[factory])
	rail(sim,exit)
	sim._step_building(sim.entities[factory],1,1)
	check(sim.entities[factory].queue.is_empty(),"waiting factory automatically releases train after track connection")
	var produced:Dictionary=sim.entities[sim._next_id-1]
	for _tick in range(40): sim.ProductionLifecycle.step_unit(sim,produced,.1)
	check(produced.pos.distance_to(exit)<.05 and not bool(produced.get("emerging",false)),"train opens door and physically exits onto connected rail")
func saved_network()->void:
	var sim=Sim.new()
	sim.setup_multiteam(config,"dev",7,["iron","iron"],false,[Vector2(6,40),Vector2(42,6)])
	sim.money.assign([100000.0,100000.0])
	check(sim.build(0,"iron_rail_junction").is_empty(),"junction available from headquarters at match start")
	check(sim.rotate_rail_order(0,1).is_empty(),"junction pending order rotates")
	var path:String="user://rail_network_revision.save"
	check(sim.save_game(path).is_empty(),"rail order saves")
	var restored=Sim.new()
	var error:String=restored.load_game(path)
	check(error.is_empty(),"rail defense order loads: "+error)
	if error.is_empty(): check(int(restored.order_for_team(0,"defense").get("rail_rotation",-1))==1,"junction rotation survives save/load")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func ai_economy()->void:
	var sim=fixture()
	sim._spawn(0,"iron_power",Vector2(10.5,20.5),true)
	sim.mines.append({"pos":Vector2(20.5,36.5),"capacity":10000.0,"amount":10000.0,"miner":-1})
	sim._refresh_mine_spatial()
	check(sim.build(0,"iron_refinery").is_empty(),"AI refinery construction order accepted")
	sim.building_orders[0].ready=true
	sim._ai_place(0)
	var refinery:Dictionary={}
	for e in sim._building_entities:
		if e.spec=="iron_refinery":refinery=e
	check(not refinery.is_empty() and refinery.pos.distance_to(sim.mines[0].pos)<=10,"AI places refinery within ten cells of a harvestable mine")
	var connected=fixture()
	var depot:int=connected._spawn(0,"iron_refinery",Vector2(30,35),true)
	connected.mines.append({"pos":Vector2(35.5,42.5),"capacity":10000.0,"amount":10000.0,"miner":-1})
	connected._refresh_mine_spatial()
	connected._rail_network.auto_refinery(connected,connected.entities[depot])
	var factory:int=connected._spawn(0,"iron_factory",Vector2(19.5,37.5),true)
	var before:float=connected.money[0]
	check(connected._rail_network.ai_connect_factory(connected,connected.entities[factory]),"AI factory legally connects its exit to the mining rail network")
	check(connected.money[0]<before,"AI factory extension pays the configured rail price")
	var exit:Vector2=connected._rail_network.exit_cell(connected,connected.entities[factory])
	var harvester:int=connected._spawn(0,"iron_harvester",exit,true)
	check(connected._mining_approach(connected.entities[harvester],0).is_finite(),"factory rail-only harvester can reach mine after AI extension")

func full_size_mining_cycle()->void:
	var sim=fixture()
	var refinery:int=sim._spawn(0,"iron_refinery",Vector2(26,34),false)
	sim.mines.append({"pos":Vector2(32.5,40.5),"capacity":10000.0,"amount":10000.0,"miner":-1})
	sim._refresh_mine_spatial()
	var harvester:int=-1
	var unsafe:int=0
	for _tick in range(950):
		sim.step(.1)
		for e:Dictionary in sim.entities.values():
			if e.spec=="iron_harvester":harvester=int(e.id)
		if harvester>0 and not bool(sim.entities[harvester].get("emerging",false)):
			var carrier: Dictionary=sim.entities[harvester]
			# The reserved unloading trip deliberately enters its own refinery.
			# Keep all other building/terrain clearance active during that trip.
			var ignore: int=int(carrier.get("refinery_docking",{}).get("source",harvester))
			if not sim._standing(carrier.pos,sim._radius(carrier),ignore,false):unsafe+=1
		if float(sim.statistics.teams[0].funds_earned)>=1000:break
	check(harvester>0 and not bool(sim.entities[refinery].gift_pending),"current-footprint miner physically leaves a normally completing refinery")
	check(float(sim.statistics.teams[0].funds_earned)>=1000,"railway miner completes two real harvest-return-unload cycles")
	check(unsafe==0,"full-size railway miner never violates static clearance during either journey")
func rail_clearance()->void:
	var sim=fixture()
	for x in range(20,31):rail(sim,Vector2(x+.5,20.5))
	var wall:int=sim._spawn(0,"iron_wall",Vector2(26.5,21.5),true)
	var id:int=sim._spawn(0,"iron_train",Vector2(22.5,20.5),true)
	check(not sim._rail_network.path(0,sim.entities[id].pos,Vector2(30.5,20.5)).is_empty(),"one-cell rail graph remains topologically connected beside a wall")
	check(sim._rail_network.traversable_path(sim,sim.entities[id],sim.entities[id].pos,Vector2(30.5,20.5)).is_empty(),"two-cell locomotive rejects rail route with insufficient physical hull clearance")
	var original:Vector2=sim.entities[id].pos
	sim._move_to(sim.entities[id],Vector2(30.5,20.5),1.0)
	check(sim.entities[id].pos==original,"full-size train does not squeeze or travel through the adjacent wall")
	# Destroyed scenery invalidates physical clearance even when rail topology
	# itself is unchanged; the original command must resume without reissuing.
	sim._kill_entity(wall,false)
	sim.ruins.append({"id":0,"kind":"tree","pos":Vector2(26.5,21.5),"half":Vector2(.5,.5),"hp":100.0,"max_hp":100.0})
	sim._refresh_ruin_spatial()
	sim._move_to(sim.entities[id],Vector2(30.5,20.5),1.0)
	check(sim.entities[id].pos==original,"full-size rail clearance also accounts for nearby destructible scenery")
	sim.ruins[0].hp=0.0
	sim._mark_nav_region(Rect2(26,21,1,1))
	sim._move_to(sim.entities[id],Vector2(30.5,20.5),1.0)
	check(sim.entities[id].pos.x>original.x,"clearing scenery automatically refreshes a stationary rail unit's physical route")
