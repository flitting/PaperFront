extends SceneTree
const Sim=preload("res://tests/rule_test_simulation.gd")
var checks:=0
var failures:Array[String]=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var sim=Sim.new()
	sim.setup(RulesLoader.load_rules(),"dev",7,"iron",false)
	for z in range(48):
		for x in range(48):sim.map.terrain[z][x]=0;sim.map.heights[z][x]=0.0
	sim.mines.clear();sim.bridges.clear();sim.ruins.clear();sim._refresh_ruin_spatial();sim._refresh_mine_spatial()
	for z in range(48):
		if z in [22,23,24]:continue
		for x in range(21,27):sim.map.terrain[z][x]=4
	sim._prepare_terrain_cache()
	sim._spec_cache=sim.rules.units.duplicate();sim._spec_cache.merge(sim.rules.buildings)
	sim._in_step=true;sim.native_geometry_enabled=true;sim._prepare_native_queries()
	for native in [false,true]:
		sim.native_geometry_enabled=native
		check(not sim._standing(Vector2(20.2,24.6),1.0,-1,false),"vehicle corner overlap rejected native=%s"%native)
		check(not sim._standing(Vector2(20.6,24.8),.5,-1,false),"infantry corner overlap rejected native=%s"%native)
		check(sim._standing(Vector2(19.95,24.6),1.0,-1,false),"legal vehicle corner clearance retained native=%s"%native)
		check(not sim._segment_static(Vector2(19.95,24.6),Vector2(20.4,24.8),1.0,-1),"continuous swept vehicle collision native=%s"%native)
		check(sim._segment_static(Vector2(19,23.5),Vector2(29,23.5),1.0,-1),"three-cell passage remains traversable native=%s"%native)
	var rng=RandomNumberGenerator.new();rng.seed=3107
	for i in range(600):
		var p=Vector2(rng.randf_range(19,28),rng.randf_range(22,26))
		var q=p+Vector2.from_angle(rng.randf_range(0,TAU))*rng.randf_range(0,2)
		var radius:float=.5 if i%2==0 else 1.0
		sim.native_geometry_enabled=false
		var standing:bool=sim._standing(p,radius,-1,false)
		var swept:bool=sim._segment_static(p,q,radius,-1)
		sim.native_geometry_enabled=true
		check(sim._standing(p,radius,-1,false)==standing,"native/script exact standing sample %d"%i)
		check(sim._segment_static(p,q,radius,-1)==swept,"native/script exact sweep sample %d"%i)
	sim._in_step=false
	var barricade:int=sim._spawn(0,"rivet_barricade",Vector2(16.5,24.5),true)
	var crossing_infantry:int=sim._spawn(0,"iron_rifle",Vector2(12,16),true)
	var crossing_tank:int=sim._spawn(0,"iron_tank",Vector2(10,16),true)
	check(sim._building_clear(sim.entities[barricade].pos,.5,crossing_infantry),"identified one-cell infantry can pass barricades")
	check(not sim._building_clear(sim.entities[barricade].pos,.5,crossing_tank),"same-radius ordinary vehicle cannot pass barricades")
	check(not sim._building_clear(sim.entities[barricade].pos,.5,-1),"unidentified exit placement conservatively blocks barricades")
	check(not sim._building_clear(sim.entities[barricade].pos,1.0,-1),"two-cell vehicles cannot pass infantry-only barricades")
	var infantry:int=sim._spawn(0,"iron_rifle",Vector2(12,12),true)
	var tank:int=sim._spawn(0,"iron_tank",Vector2(10,12),true)
	sim.issue([infantry],"move",Vector2(20,12));sim.issue([tank],"move",Vector2(20,12))
	check(sim._traffic_priority(sim.entities[tank])>sim._traffic_priority(sim.entities[infantry]),"one-cell vehicles retain vehicle traffic precedence")
	sim.entities[infantry].yield_goal=Vector2(13,13)
	sim.entities[infantry].yield_root=tank
	check(not sim._traffic_may_yield(sim.entities[infantry],sim.entities[tank]),"a propagated yield cannot request its own root to retreat")
	print("RTS_NAVIGATION_GEOMETRY ",JSON.stringify({"checks":checks,"failures":failures}))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
