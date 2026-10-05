extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const ProfileSim=preload("res://tools/cpu_profile_simulation.gd")
const Rules=preload("res://scripts/rules_loader.gd")
const Factions=preload("res://scripts/performance_factions.gd")
const Probe=preload("res://scripts/gameplay_performance.gd")
class FakeGame:
	extends Node
	var sim
	var exit_code:int=-1
	func quit_game(code:int=0)->void:exit_code=code
func stats(values:Array[float])->Dictionary:
	var sorted:Array[float]=values.duplicate()
	sorted.sort()
	var total:float=0.0
	for value in values:total+=value
	return {"mean_ms":total/maxi(1,values.size()),"p50_ms":sorted[int(sorted.size()*.5)],"p95_ms":sorted[int(sorted.size()*.95)],"p99_ms":sorted[int(sorted.size()*.99)],"max_ms":sorted.back()}
func _initialize()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	var ticks:int=90
	var output:String="/tmp/paper_war_final_pressure_cpu.json"
	var sections:bool="--cpu-sections" in args
	var event_interval:int=1
	for i in range(args.size()-1):
		if args[i]=="--cpu-ticks":ticks=int(args[i+1])
		elif args[i]=="--cpu-output":output=args[i+1]
		elif args[i]=="--event-interval":event_interval=maxi(1,int(args[i+1]))
	var game=FakeGame.new()
	var rules:Dictionary=Rules.load_rules()
	if rules.is_empty():
		push_error("Pressure profile requires valid imported assets: "+"; ".join(Rules.errors))
		game.free()
		quit(2)
		return
	game.sim=ProfileSim.new() if sections else Sim.new()
	var hqs:Array[Vector2]=[]
	var center:=Vector2(320,352)
	for team in range(8):hqs.append(center+Vector2.from_angle(float(team)*TAU/8.0)*70.0)
	var stamp:int=Time.get_ticks_usec()
	game.sim.setup_multiteam(Factions.make_rules(rules),"mountains640",73026,Factions.ids(),false,hqs)
	var setup_ms:float=(Time.get_ticks_usec()-stamp)/1000.0
	for team in range(8):game.sim.money[team]=100000.0
	var probe=Probe.new()
	probe.game=game;probe.options={"case":"stress"};probe.center=center;probe.start_us=1
	stamp=Time.get_ticks_usec();probe._populate_eight_factions()
	var populate_ms:float=(Time.get_ticks_usec()-stamp)/1000.0
	for team in range(8):
		if game.sim.counts(team)!=Vector2i(100,20):
			push_error("Pressure profile requires 100 units and 20 buildings for every team")
			probe.free();game.sim=null;game.free()
			quit(2)
			return
	game.sim.profile_enabled=true
	if sections:game.sim.sections.clear()
	var pure:Array[float]=[]
	var reserve:Array[float]=[]
	var combined:Array[float]=[]
	var stages:Dictionary={}
	var rows:Array[Dictionary]=[]
	var events:Dictionary={}
	var min_units:int=800
	for tick in range(ticks):
		stamp=Time.get_ticks_usec();game.sim.step(1.0/30.0)
		var pure_ms:float=(Time.get_ticks_usec()-stamp)/1000.0
		stamp=Time.get_ticks_usec();probe.after_tick()
		var reserve_ms:float=(Time.get_ticks_usec()-stamp)/1000.0
		pure.append(pure_ms);reserve.append(reserve_ms);combined.append(pure_ms+reserve_ms)
		var population:int=0
		for team in range(8):population+=game.sim.counts(team).x
		min_units=mini(min_units,population)
		for key in game.sim.profile:stages[key]=float(stages.get(key,0))+float(game.sim.profile[key])
		rows.append({"tick":tick,"pure_ms":pure_ms,"reserve_ms":reserve_ms,"stages_us":game.sim.profile.duplicate(),"projectiles":game.sim.projectiles.size(),"population":population,"pending_events":game.sim.events.size()})
		if (tick+1)%event_interval==0:
			for event in game.sim.events:events[str(event.kind)]=int(events.get(str(event.kind),0))+1
			game.sim.events.clear()
		OS.delay_usec(1000)
	for key in stages:stages[key]/=maxi(1,ticks)
	var report:Dictionary={"ticks":ticks,"simulation_seconds":game.sim.time,"map_size":game.sim.map.size,"factions":game.sim.factions,"setup_ms":setup_ms,"populate_ms":populate_ms,"minimum_units":min_units,"reinforcement_spawns":probe.reinforcement_spawns,"air_reinforcements":probe.reinforcement_air_spawns,"pure_simulation":stats(pure),"reserve_after_tick":stats(reserve),"combined":stats(combined),"mean_stages_us":stages,"events":events,"rows":rows,"event_interval":event_interval,"exit_code":game.exit_code,"navigation":game.sim.navigation_stats.duplicate()}
	report.fixture_version=Factions.FIXTURE_VERSION
	report.native_unit_dispatch=game.sim.native_kernels_enabled and game.sim.native_unit_dispatch_enabled and game.sim._kernels!=null
	report.native_geometry_queries=game.sim.native_kernels_enabled and game.sim.native_geometry_enabled and game.sim._kernels!=null
	report.native_ground_movement=game.sim.native_kernels_enabled and game.sim.native_geometry_enabled and game.sim.native_movement_enabled and game.sim._kernels!=null
	report.art_templates=[]
	for team in range(8):report.art_templates.append(Factions.art_template(team))
	report.building_reinforcements=probe.reinforcement_building_spawns
	if sections:report.sections=game.sim.sections.duplicate(true)
	var file=FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()
	report.erase("rows")
	print("FINAL_PRESSURE_CPU ",JSON.stringify(report))
	probe.free();game.sim=null;game.free()
	quit()
