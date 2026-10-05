extends SceneTree
const Sim=preload("res://tests/rule_test_simulation.gd")
const Rules=preload("res://scripts/rules_loader.gd")
const Transport=preload("res://scripts/unit_transport.gd")
const Worker=preload("res://scripts/path_worker.gd")
var checks:int=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
func fixture():
	var sim=Sim.new()
	sim.setup(Rules.load_rules(),"dev",7,"rivet",false)
	sim.money.assign([100000.0,100000.0])
	return sim
func _initialize()->void:
	test_base_lifecycle()
	test_neighbors_and_transport()
	test_fixed_goal_invalidation()
	test_local_damage_equivalence()
	test_mine_index_equivalence()
	test_worker_overlapping_chunks()
	test_save_rebuild()
	test_nearest_contact_equivalence()
	print("Simulation cache checks: ",checks-failures.size()," passed, ",failures.size()," failed")
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
func test_base_lifecycle()->void:
	var sim=fixture()
	sim._in_step=true
	check(sim.power(0).x==100.0 and sim._has_role(0,"hq"),"base summary initially contains completed headquarters")
	var power:int=sim._spawn(0,"rivet_power",Vector2(5.5,40.5),false)
	check(sim.power(0).x==100.0 and not sim._has_role(0,"power"),"unfinished building cannot leak power or technology through a warm summary")
	sim._step_building(sim.entities[power],2.0,1.0)
	check(sim.power(0).x==400.0 and sim._has_role(0,"rivet_power"),"normal construction completion invalidates the warmed power and prerequisite summary")
	var enemy:int=sim._spawn(1,"kestrel_power",Vector2(20.5,43.5),true)
	var engineer:int=sim.debug_spawn(0,"rivet_engineer",Vector2(17.5,43.5))
	var before:Vector2=sim.power(1)
	sim._step_capture(sim.entities[engineer],{"kind":"capture","target":enemy},1.0/30)
	check(sim.power(0).x==620.0 and sim.power(1).x==before.x-220.0 and sim._has_role(0,"kestrel_power"),"capture updates both owners' cached power and technology in the same tick")
	sim._kill_entity(power,true)
	check(sim.power(0).x==320.0 and not sim._has_role(0,"rivet_power"),"building death invalidates cached power and exact prerequisite identity")
	sim._in_step=false
func test_neighbors_and_transport()->void:
	var sim=fixture()
	var rifle:int=sim.debug_spawn(0,"rivet_rifle",Vector2(6.5,43.5))
	var scout:int=sim.debug_spawn(0,"rivet_scout",Vector2(8.5,43.5))
	var near:=Vector2(6.5,43.5)
	var remote:=Vector2(30.5,43.5)
	sim._neighbors(near);sim._neighbors(remote)
	var before:Vector2=sim.entities[rifle].pos
	sim.entities[rifle].pos=Vector2(6.6,43.5)
	sim._spatial_move(sim.entities[rifle],before,sim.entities[rifle].pos)
	check(sim._neighbor_cache.has(sim._bucket(near)) and not sim._standing(sim.entities[rifle].pos,.35,scout),"same-bucket movement retains membership while collision queries observe live coordinates")
	before=sim.entities[rifle].pos
	sim.entities[rifle].pos=Vector2(12.5,43.5)
	sim._spatial_move(sim.entities[rifle],before,sim.entities[rifle].pos)
	check(not sim._neighbor_cache.has(sim._bucket(near)) and sim._neighbor_cache.has(sim._bucket(remote)),"crossing buckets invalidates affected neighborhoods without invalidating unrelated ones")
	check(not sim._neighbors(near).has(sim.entities[rifle]) and sim._neighbors(sim.entities[rifle].pos).has(sim.entities[rifle]),"cross-bucket membership is removed and inserted before subsequent queries")
	Transport._board(sim,sim.entities[rifle],sim.entities[scout])
	check(not sim._neighbors(Vector2(12.5,43.5)).has(sim.entities[rifle]),"boarding removes infantry from cached collision neighborhoods")
	check(sim.unload(scout).is_empty() and sim._neighbors(sim.entities[rifle].pos).has(sim.entities[rifle]),"unloading restores infantry to the correct collision neighborhood immediately")
func test_local_damage_equivalence()->void:
	var sim=fixture()
	for i in range(24):
		sim.debug_spawn(i%2,sim.factions[i%2]+"_rifle",Vector2(3.5+float(i%12)*3.0,40.5+float(i/12)*4.0))
	for i in range(24):
		sim.ruins.append({"id":sim.ruins.size(),"kind":"tree","pos":Vector2(3.25+float(i)*1.7,37.25),"half":Vector2(.28,.28),"hp":100.0})
	sim._refresh_ruin_spatial()
	sim._rebuild_spatial()
	sim._in_step=true
	for center in [Vector2(6.5,43.5),Vector2(20.5,37.25),Vector2(39.0,31.0)]:
		for blast in [0.0,.3,2.0,6.0]:
			var expected:Dictionary={}
			for e in sim.entities.values():
				var hit:bool=sim._circle_rect(center,blast,e.pos,Vector2.ONE*float(sim.data_for(e.spec).size)*.5) if e.kind=="building" else center.distance_to(e.pos)<=blast+sim._radius(e)
				if hit and float(e.hp)>0.0 and not Transport.is_loaded(e):expected[int(e.id)]=10.0
			for ruin in sim.ruins:
				if float(ruin.hp)>0.0 and sim._circle_rect(center,blast,ruin.pos,ruin.half):expected[Sim.RUIN_TARGET_BASE-int(ruin.id)]=10.0
			for bridge in sim.bridges:
				if bool(bridge.alive) and sim._circle_bounds(center,blast,bridge.bounds):expected[Sim.BRIDGE_TARGET_BASE-int(bridge.id)]=10.0
			sim._damage.clear()
			sim._impact_damage(center,blast,10.0,{},["ground"],true)
			check(sim._damage==expected,"local AoE exactly matches the complete entity/tree/bridge scan at "+str(center)+" radius "+str(blast))
	var fresh:int=sim._spawn(0,"rivet_power",Vector2(18.5,43.5),true)
	sim._damage.clear();sim._impact_damage(sim.entities[fresh].pos,.1,10.0,{},["ground"],false)
	check(sim._damage.has(fresh),"same-tick newly spawned buildings enter local impact queries before the next rebuild")
	sim._in_step=false
func test_fixed_goal_invalidation()->void:
	var sim=fixture()
	var engineer:int=sim.debug_spawn(0,"rivet_engineer",Vector2(6.5,43.5))
	var e:Dictionary=sim.entities[engineer]
	var goal:=Vector2(12.5,43.5)
	sim._in_step=true
	check(sim._goal_standing(e,goal,.35),"a fixed clear movement destination can be cached")
	var building:int=sim._spawn(0,"rivet_power",goal,true)
	check(not sim._goal_standing(e,goal,.35),"new construction immediately invalidates an earlier clear destination")
	sim._kill_entity(building,true)
	check(sim._goal_standing(e,goal,.35),"removing a building immediately restores its formerly blocked cached destination")
	var tree:Dictionary={"id":sim.ruins.size(),"kind":"tree","pos":goal,"half":Vector2(.3,.3),"hp":100.0}
	sim.ruins.append(tree);sim._refresh_ruin_spatial()
	check(not sim._goal_standing(e,goal,.35),"rebuilding neutral geometry invalidates a previously warm fixed destination")
	sim._add_damage(Sim.RUIN_TARGET_BASE-int(tree.id),100.0,true);sim._apply_damage();sim._damage.clear()
	check(sim._goal_standing(e,goal,.35),"destroying a tree invalidates its blocked movement destination in the same tick")
	sim.mines.append({"pos":goal,"capacity":1000.0,"amount":1000.0,"miner":-1});sim._refresh_mine_spatial()
	check(not sim._goal_standing(e,goal,.35),"mine footprint reconstruction invalidates cached movement destinations")
	sim._in_step=false
func test_worker_overlapping_chunks()->void:
	var worker=Worker.new()
	var ids:=PackedInt64Array()
	var edges:=PackedInt64Array()
	var heights:=PackedFloat32Array()
	heights.resize(49);heights.fill(0.0)
	# Match the worker's immutable flat-terrain snapshot schema. This fixture
	# has no adaptive samples; the original 49 nodes and edges stay unchanged.
	var terrain:=PackedByteArray()
	terrain.resize(49);terrain.fill(0)
	var land:=PackedByteArray()
	land.resize(49);land.fill(1)
	for z in range(7):
		for x in range(7):
			var id:int=z*7+x
			ids.append(id)
			if x<6:edges.append_array([id,id+1])
			if z<6:edges.append_array([id,id+7])
	worker._data={"size":7,"ids":ids,"edges":edges,"heights":heights,"masks":{.35:[]},
		"extra_positions":{},"extra_cells":{},"terrain":terrain,"land":land}
	var tree:=Rect2(Vector2(3,3),Vector2.ONE)
	var first:Dictionary={"revision":1,"rectangles":[tree]}
	var second:Dictionary={"revision":1,"rectangles":[tree]}
	var job:Dictionary={"radius":.35,"revision":1,"start":Vector2(.5,3.5),"goal":Vector2(6.5,3.5),"start_height":0.0,"goal_height":0.0,"geometry":{"hard":[],"vehicles":[],"ruin_chunks":[first,second]}}
	worker._search(job)
	var graph:Dictionary=worker._graphs[.35]
	check(graph.nav.is_point_disabled(24),"overlapping forest chunks block their shared node")
	job.revision=2;job.geometry.ruin_chunks=[{"revision":2,"rectangles":[]},second]
	worker._search(job)
	check(graph.nav.is_point_disabled(24),"removing one chunk cannot reopen a node still covered by another chunk")
	job.revision=3;job.geometry.ruin_chunks=[{"revision":2,"rectangles":[]},{"revision":3,"rectangles":[]}]
	worker._search(job)
	check(not graph.nav.is_point_disabled(24),"removing the final overlapping obstruction restores the node")
	check(first.rectangles==[tree] and second.rectangles==[tree],"worker updates preserve earlier immutable geometry snapshots")
func test_mine_index_equivalence()->void:
	var sim=fixture()
	sim.mines.clear()
	sim.ruins.clear();sim._refresh_ruin_spatial()
	for i in range(40):sim.mines.append({"pos":Vector2(3.5+float(i%10)*4.0,3.5+float(i/10)*7.0),"capacity":1000.0,"amount":1000.0,"miner":-1})
	sim._refresh_mine_spatial()
	for p in [Vector2(3.5,3.5),Vector2(4.4,3.5),Vector2(10.5,11.1),Vector2(20.5,21.5),Vector2(35.5,43.5)]:
		for radius in [.35,.95,1.99,2.2]:
			var expected:bool=true
			for mine in sim.mines:
				if sim._circle_rect(p,radius+.02,mine.pos,Sim.MINE_HALF):expected=false
			for e in sim._building_entities:
				if sim._circle_rect(p,radius+.02,e.pos,Vector2.ONE*float(sim.data_for(e.spec).size)*.5):expected=false
			check(sim._building_clear(p,radius,-1)==expected,"local mine collision matches the complete footprint scan for radius "+str(radius)+" at "+str(p))
	sim.mines.append({"pos":Vector2(35.5,43.5),"capacity":1000.0,"amount":1000.0,"miner":-1})
	check(not sim._building_clear(Vector2(35.5,43.5),.35,-1),"changing the mine list rebuilds the local footprint index before subsequent collision queries")
func test_save_rebuild()->void:
	var sim=fixture()
	sim.debug_spawn(0,"rivet_power",Vector2(5.5,40.5))
	var scout:int=sim.debug_spawn(0,"rivet_scout",Vector2(9.5,43.5))
	var rifle:int=sim.debug_spawn(0,"rivet_rifle",Vector2(7.5,43.5))
	Transport._board(sim,sim.entities[rifle],sim.entities[scout])
	var path:String="/tmp/paper_war_simulation_cache.save"
	check(sim.save_game(path).is_empty(),"simulation containing warm derived caches saves")
	var restored=Sim.new()
	check(restored.load_game(path).is_empty() and restored.power(0)==sim.power(0) and restored._has_role(0,"power"),"load reconstructs derived power, prerequisites and transportation membership")
	check(restored._neighbors(restored.entities[scout].pos).all(func(e):return e.id!=rifle),"restored cached neighbors exclude embarked infantry")
	for i in range(30):sim.step(1.0/30);restored.step(1.0/30)
	check(restored.entities==sim.entities and restored.money==sim.money,"rebuilt caches preserve authoritative save roundtrip evolution")
	DirAccess.remove_absolute(path)
func test_nearest_contact_equivalence()->void:
	var sim=fixture()
	var fighters:Array[int]=[]
	for i in range(40):
		var team:int=i%2
		var role:String=["rifle","engineer","aa","fighter"][i%4]
		var id:int=sim.debug_spawn(team,sim.factions[team]+"_"+role,Vector2(3.5+float(i%14)*2.5,40.5+float(i/14)*2.0))
		if id>0:fighters.append(id)
	sim._rebuild_spatial();sim._in_step=true
	for id in fighters:
		for radius in [0.0,1.0,5.0,7.0,15.0]:
			check(sim._nearest_enemy(sim.entities[id],radius)==sim._nearest_enemy_reference(sim.entities[id],radius),"packed nearest matches exact full bucket reference for unit "+str(id)+" radius "+str(radius))
	var moved:int=fighters[0]
	var origin:Vector2=sim.entities[moved].pos
	sim.entities[moved].pos=Vector2(41.5,45.5);sim._spatial_move(sim.entities[moved],origin,sim.entities[moved].pos)
	check(sim._nearest_enemy(sim.entities[moved],15.0)==sim._nearest_enemy_reference(sim.entities[moved],15.0),"same-tick movement updates packed positions and bucket membership before nearest queries")
	sim._in_step=false
	var tie=fixture()
	var source:int=tie.debug_spawn(0,"rivet_rifle",Vector2(16.0,43.5))
	var later_bucket:int=tie.debug_spawn(1,"kestrel_engineer",Vector2(20.0,43.5))
	tie.debug_spawn(1,"kestrel_engineer",Vector2(12.0,43.5))
	tie._rebuild_spatial();tie._in_step=true
	check(tie._nearest_enemy(tie.entities[source],5.0)==later_bucket and tie._nearest_enemy(tie.entities[source],5.0)==tie._nearest_enemy_reference(tie.entities[source],5.0),"center-first search retains the original later-bucket winner for an exact-distance tie")
	tie._in_step=false
