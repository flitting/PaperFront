extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
const PerformanceFactions = preload("res://scripts/performance_factions.gd")
var failures: Array[String]=[]
var checks: int=0

func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message)

func rules()->Dictionary:
	var raw:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/rules.json"))
	return raw if raw is Dictionary else {}

func _initialize()->void:
	var config:Dictionary=rules()
	check(not config.is_empty(),"rules JSON parses")
	var problems:Array[String]=RulesLoader.validate(config,false)
	check(problems.is_empty(),"Stage3 rules validate without asset import: "+str(problems.slice(0,3)))
	if not problems.is_empty():_finish();return
	legacy(config)
	modern(config)
	four_players(config)
	eight_owner_legacy(config)
	native_fog_equivalence(config)
	naval_sight(config)
	_finish()

func _finish()->void:
	print("STAGE3_SIM ",JSON.stringify({"checks":checks,"failures":failures}))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)

func legacy(config:Dictionary)->void:
	var sim=Sim.new()
	sim.setup(config,"dev",7,"rivet",false)
	check(not sim.vision_enabled and sim.factions.size()==2,"legacy setup keeps two-owner no-fog behavior")
	check(sim.entity_visible_to(0,int(sim.entities.values().filter(func(e):return int(e.team)==1)[0].id)),"legacy enemy stays visible")

func modern(config:Dictionary)->void:
	var sim=Sim.new()
	var ids:Array[String]=["rivet","kestrel","iron"]
	var options:Dictionary={"players":3,"slots":[{"faction":"rivet","control":"human","difficulty":"normal"},{"faction":"kestrel","control":"ai","difficulty":"easy"},{"faction":"iron","control":"ai","difficulty":"hard"}]}
	sim.setup_multiteam(config,"forest",11,ids,true,[],Callable(),options)
	check(sim.factions.size()==3 and sim.map.starts.size()==3 and sim.vision_enabled,"three-player profile initializes fog and three starts")
	var enemy_hq:int=-1
	for e in sim.entities.values():
		if int(e.team)==1 and e.kind=="building":enemy_hq=int(e.id);break
	check(enemy_hq>0 and not sim.entity_visible_to(0,enemy_hq),"distant enemy HQ is hidden")
	var observer:int=sim._spawn(0,"rivet_scout",sim.entities[enemy_hq].pos+Vector2(3,0),true)
	sim.TeamVision.refresh(sim,true)
	check(sim.entity_visible_to(0,enemy_hq),"nearby scout reveals enemy HQ")
	var known:Dictionary=sim.last_known_enemy(0,enemy_hq)
	check(known.get("pos") is Vector2 and known.pos.is_equal_approx(sim.entities[enemy_hq].pos),"sighting records last known position")
	sim.entities[observer].pos=sim._team_start(0)
	sim.TeamVision.refresh(sim,true)
	check(not sim.entity_visible_to(0,enemy_hq),"enemy disappears when scout leaves")
	check(sim.last_known_enemy(0,enemy_hq).get("pos",Vector2.ZERO).is_equal_approx(known.pos),"last known memory retains observed position")
	var gun:int=sim._spawn(0,"rivet_advanced",sim.entities[enemy_hq].pos+Vector2(12,0),true)
	sim.entities[gun].commands=[{"kind":"attack","pos":known.pos,"target":enemy_hq}]
	var actual_hq_pos:Vector2=sim.entities[enemy_hq].pos
	sim.entities[enemy_hq].pos+=Vector2(2,0)
	check(sim._lost_target_order(sim.entities[gun],enemy_hq) and sim.entities[gun].commands[0].kind=="attack_move" and sim.entities[gun].commands[0].pos.is_equal_approx(known.pos),"lost attack follows last known position rather than hidden live coordinates")
	sim.entities[enemy_hq].pos=actual_hq_pos
	sim.entities[gun].commands.clear()
	sim._in_step=true
	sim._spec_cache=sim.rules.units.duplicate()
	sim._spec_cache.merge(sim.rules.buildings)
	for spec_id in sim.rules.units:
		if sim.rules.units[spec_id].get("domain","ground")=="air":sim._air_specs[spec_id]=true
		elif sim.rules.units[spec_id].get("domain","ground")=="naval":sim._naval_specs[spec_id]=true
	for spec_id in sim._spec_cache:sim._weapon_target_masks[spec_id]=sim._target_mask_for_spec(sim._spec_cache[spec_id])
	sim._rebuild_spatial()
	sim.TeamVision.refresh(sim,true)
	check(not sim._weapon_can_target(sim.entities[gun],enemy_hq),"hidden enemy cannot be directly targeted")
	sim.native_kernels_enabled=true
	var native_hidden:int=sim._nearest_enemy(sim.entities[gun],18.0)
	sim.native_kernels_enabled=false
	var script_hidden:int=sim._nearest_enemy(sim.entities[gun],18.0)
	check(native_hidden==-1 and script_hidden==-1,"native and script acquisition reject hidden enemy")
	sim.entities[observer].pos=sim.entities[enemy_hq].pos+Vector2(3,0)
	sim.TeamVision.refresh(sim,true)
	sim.native_kernels_enabled=true
	var native_seen:int=sim._nearest_enemy(sim.entities[gun],18.0)
	sim.native_kernels_enabled=false
	var script_seen:int=sim._nearest_enemy(sim.entities[gun],18.0)
	check(native_seen==script_seen and native_seen==enemy_hq,"native and script acquisition agree when scout reveals enemy")
	sim._in_step=false
	var before:float=sim.money[1]
	sim.AIController.step(sim,4.0)
	check(not sim.building_orders[1].is_empty() or sim.money[1]<before,"AI issues a normal economy build order")
	check(is_equal_approx(float(sim.money[0]),float(config.economy.initial_money)),"AI planning does not credit human money")
	for tick in range(15):sim.step(0.1)
	check(sim.time>=1.5 and sim.ai_state[2].reaction_clock>=0.0,"multi-team native ticks advance AI clocks")
	var path:String="user://stage3_sim.save"
	check(sim.save_game(path).is_empty(),"three-player fog state saves")
	var loaded=Sim.new()
	check(loaded.load_game(path).is_empty(),"three-player fog state loads")
	if loaded.factions.size()==3:check(loaded.vision_enabled and loaded.ai_state.size()==3,"fog and per-team AI clocks survive save")

func four_players(config:Dictionary)->void:
	var sim=Sim.new()
	var options:Dictionary={"players":4,"slots":[{"faction":"rivet","control":"human","difficulty":"normal"},{"faction":"kestrel","control":"ai","difficulty":"easy"},{"faction":"iron","control":"ai","difficulty":"normal"},{"faction":"sky","control":"ai","difficulty":"hard"}]}
	sim.setup(config,"desert",5,"rivet",true,options)
	check(sim.factions.size()==4 and sim.map.starts.size()==4 and sim.vision_enabled,"public setup accepts four local slots")
	check(sim.match_options.slots[0].control=="human" and sim.match_options.slots[3].difficulty=="hard","player and AI difficulty slots are preserved")
	for tick in range(12):sim.step(0.1)
	check(sim.ai_state.size()==4 and sim.time>=1.2,"four-owner AI clocks advance in real simulation")

func eight_owner_legacy(config:Dictionary)->void:
	var sim=Sim.new()
	var ids:Array[String]=PerformanceFactions.ids()
	var hqs:Array[Vector2]=[]
	for team in range(8):hqs.append(Vector2(4+team*5,43))
	sim.setup_multiteam(PerformanceFactions.make_rules(config),"dev",7,ids,false,hqs)
	check(sim.factions.size()==8 and sim.map.starts.size()==2 and not sim.vision_enabled,"eight-owner benchmark keeps old map and no-fog behavior")
	var path:String="user://stage3_eight_legacy.save"
	check(sim.save_game(path).is_empty() and Sim.new().load_game(path).is_empty(),"eight-owner legacy fixture still saves and loads")

func native_fog_equivalence(config:Dictionary)->void:
	if not ClassDB.class_exists("PaperFrontKernels"):
		failures.append("native kernel unavailable")
		return
	var fast=Sim.new()
	var reference=Sim.new()
	for sim in [fast,reference]:
		sim.setup(config,"dev",7,"rivet",false,{"vision_enabled":true})
		var gun:int=sim._spawn(0,"rivet_advanced",Vector2(14,39),true)
		var enemy:int=sim._spawn(1,"kestrel_tank",Vector2(27,39),true)
		sim._spawn(0,"rivet_scout",Vector2(22,39),true)
		sim.TeamVision.refresh(sim,true)
		sim.issue([gun],"attack",sim.entities[enemy].pos,enemy)
		sim.native_geometry_enabled=false
	fast.native_unit_dispatch_enabled=true
	reference.native_unit_dispatch_enabled=false
	for tick in range(60):
		fast.step(1.0/30.0)
		reference.step(1.0/30.0)
		if fast.entities!=reference.entities or fast.projectiles!=reference.projectiles or fast.events!=reference.events:
			failures.append("native/script fog combat diverged at tick "+str(tick))
			break
		fast.events.clear()
		reference.events.clear()
	checks+=1

func naval_sight(config:Dictionary)->void:
	var sim=Sim.new()
	sim.setup_multiteam(config,"islands",17,["rivet","kestrel"],false,[],Callable(),{"players":2})
	var first:Vector2=Vector2.INF
	for z in range(24,296,3):
		if first.is_finite():break
		for x in range(24,287,3):
			var open:bool=true
			for offset in range(9):
				if int(sim.map.terrain[z][x+offset])!=MapData.WATER:open=false;break
			if not open:continue
			var candidate:=Vector2(x+0.5,z+0.5)
			if candidate.distance_to(sim._team_start(0))<30.0 or candidate.distance_to(sim._team_start(1))<30.0:continue
			first=candidate
			break
	check(first.is_finite(),"island fixture contains open sea sight lane")
	if not first.is_finite():return
	var second:Vector2=first+Vector2(8,0)
	var a:int=sim._spawn(0,"rivet_ship_frigate",first,true)
	var b:int=sim._spawn(1,"kestrel_ship_frigate",second,true)
	sim.TeamVision.refresh(sim,true)
	check(sim.entity_visible_to(0,b),"two ships see each other across open water")
	var water_offset:float=MapData.water_surface_y(sim.map,first)-sim._height(first)
	sim.entities[a].turret_alpha=0.0
	sim._launch_shot(sim.entities[a],second,b,false)
	check(not sim.projectiles.is_empty() and is_equal_approx(float(sim.projectiles.back().source_height),water_offset),"naval projectile starts at water surface offset")
	sim._step_projectiles(1.0)
	var impact:Dictionary={}
	for event in sim.events:
		if event.kind=="impact":impact=event
	check(not impact.is_empty() and int(impact.get("team",-1))==0 and is_equal_approx(float(impact.get("height",0.0)),MapData.water_surface_y(sim.map,second)-sim._height(second)+0.18),"water impact records owning team and real water height")
	var own_harbor:Dictionary={}
	for harbor in sim.map.harbors:
		if int(harbor.team)==0 and harbor.role=="home":own_harbor=harbor;break
	if not own_harbor.is_empty():
		var dock:int=sim._spawn(0,"rivet_shipyard",own_harbor.shore_pos,true)
		check(is_equal_approx(float(sim.entities[dock].alpha),sim.NavalOperations.shipyard_heading(sim,sim.entities[dock].pos)),"shipyard model faces its actual water exit")
	var cell:Vector2i=MapData.cell(sim.map,first+Vector2(4,0))
	sim.map.terrain[cell.y][cell.x]=MapData.LAND
	sim.map.heights[cell.y][cell.x]=8.0
	sim.TeamVision.refresh(sim,true)
	check(not sim.entity_visible_to(0,b),"actual high land blocks naval mast sight")
	sim._kill_entity(a,true)
	var death:Dictionary=sim.events.back()
	check(death.kind=="death" and is_equal_approx(float(death.height),water_offset),"naval death FX uses actual water surface")
