extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Rules=preload("res://scripts/rules_loader.gd")
var report:Dictionary={}
func _initialize()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	var mode:String="handmade"
	var count:int=256
	var ticks:int=120
	var tree_count:int=24000
	var output:String="/tmp/paper_war_cpu_profile_before.json"
	var sections:bool="--cpu-sections" in args
	for i:int in range(args.size()-1):
		match args[i]:
			"--cpu-mode":mode=args[i+1]
			"--cpu-units":count=int(args[i+1])
			"--cpu-ticks":ticks=int(args[i+1])
			"--cpu-tree-count":tree_count=int(args[i+1])
			"--cpu-output":output=args[i+1]
	var sim=preload("res://tools/cpu_profile_simulation.gd").new() if sections else Sim.new()
	var stamp:int=Time.get_ticks_usec()
	sim.setup(Rules.load_rules(),mode,73026,"rivet",false)
	report.setup_ms=(Time.get_ticks_usec()-stamp)/1000.0
	sim.money.assign([1000000.0,1000000.0])
	var ids:Array=[]
	var southern:float=float(sim.map.size)-maxf(15.0,ceili(float(count)/32.0)*1.2+4.0)
	for i:int in range(count):
		var team:int=i%2
		var p:=Vector2(10.5+float(i%32)*2.7,southern+float(i/32)*1.2)
		var id:int=sim.debug_spawn(team,sim.factions[team]+"_tank",p)
		if id>=0:ids.append(id)
	# Extra trees expose forest-scale broad-phase cost without allocating render
	# nodes. They leave the southern test lane clear; actual map trees remain.
	for i:int in range(maxi(0,tree_count-sim.ruins.size())):
		var id:int=sim.ruins.size()
		var width:int=maxi(1,int(sim.map.size)-20)
		var p:=Vector2(5.25+float(i%width),5.25+float((i/width)%maxi(1,int(southern)-15)))
		sim.ruins.append({"id":id,"kind":"tree","pos":p,"half":Vector2(.12,.12),"hp":100.0,"max_hp":100.0})
	stamp=Time.get_ticks_usec();sim._refresh_ruin_spatial()
	report.ruin_index_ms=(Time.get_ticks_usec()-stamp)/1000.0
	stamp=Time.get_ticks_usec();sim._publish_path_geometry()
	report.geometry_publish_ms=(Time.get_ticks_usec()-stamp)/1000.0
	sim._in_step = true
	stamp=Time.get_ticks_usec()
	for i:int in range(100):sim._impact_damage(Vector2(50.25,50.25),1.2,10.0,{},["ground"],true)
	report.force_aoe_100_ms=(Time.get_ticks_usec()-stamp)/1000.0
	sim._in_step = false
	sim._damage.clear()
	if not sim.ruins.is_empty():
		sim._add_damage(Sim.RUIN_TARGET_BASE - int(sim.ruins[0].id), float(sim.ruins[0].hp) + 1.0, true)
		sim._apply_damage()
		sim._damage.clear()
		stamp=Time.get_ticks_usec();sim._publish_path_geometry()
		report.geometry_single_change_publish_ms=(Time.get_ticks_usec()-stamp)/1000.0
	for id:int in ids:
		var e:Dictionary=sim.entities[id]
		sim.issue([id],"attack_move",e.pos+Vector2(12 if e.team==0 else -12,0))
	sim.profile_enabled=true
	if sections: sim.sections.clear()
	var samples:Array[float]=[]
	var totals:Dictionary={}
	var slow_ticks:Array[Dictionary]=[]
	for i:int in range(ticks):
		stamp=Time.get_ticks_usec();sim.step(1.0/30.0)
		var elapsed_ms:float=(Time.get_ticks_usec()-stamp)/1000.0
		samples.append(elapsed_ms)
		if elapsed_ms>16.667:
			slow_ticks.append({"tick":i,"ms":elapsed_ms,"stages_us":sim.profile.duplicate(),"entities":sim.entities.size(),"projectiles":sim.projectiles.size(),"navigation":sim.navigation_stats.duplicate()})
		for key:Variant in sim.profile:totals[key]=float(totals.get(key,0.0))+float(sim.profile[key])
		sim.events.clear()
		OS.delay_usec(1000)
	samples.sort()
	for key:Variant in totals:totals[key]/=maxi(1,ticks)
	if sections: report.section_diagnostics = sim.sections.duplicate(true)
	report.merge({"mode":mode,"size":sim.map.size,"trees_and_ruins":sim.ruins.size(),"requested_units":count,"spawned_units":ids.size(),"ticks":ticks,"tick_p50_ms":samples[int(samples.size()*.5)],"tick_p95_ms":samples[int(samples.size()*.95)],"tick_p99_ms":samples[int(samples.size()*.99)],"tick_max_ms":samples.back(),"slow_ticks":slow_ticks,"mean_stages_us":totals,"navigation":sim.navigation_stats,"physical_time":sim.time,"final_entities":sim.entities.size()})
	var file=FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("CPU_PROFILE ",JSON.stringify(report))
	sim=null
	quit()
