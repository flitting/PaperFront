extends SceneTree

## Economy/traffic stress fixture, never included in faction win rates.
## The passive enemy HQ has extra HP solely to keep a long observation window.
## Our HQ, money, costs, production, mining and collision use normal rules.
const MatchRunner = preload("res://scripts/headless_match.gd")
const Exporter = preload("res://scripts/match_statistics_exporter.gd")
var options: Dictionary = {"faction":"sky", "side":0, "duration":900.0, "dt":1.0/30.0, "fault":"none", "output":"/tmp/ai_reliability"}
var observations: Array = []
var failures: Array[String] = []
var progress: Dictionary = {}
var longest_stalls: Dictionary = {}
var stall_observations: Array = []

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var n: int = 0
	while n < args.size():
		var key: String = args[n].trim_prefix("--")
		if not options.has(key) or n + 1 >= args.size(): printerr("Unknown/missing option: " + args[n]); quit(2); return
		options[key] = args[n+1]
		n += 2
	var faction: String = str(options.faction)
	var side: int = int(options.side)
	var duration: float = float(options.duration)
	var delta: float = float(options.dt)
	if faction not in MatchRunner.FACTIONS or side not in [0,1] or duration < 300 or delta < .001 or delta > .1 or str(options.fault) not in ["none","miner_loss","refinery_loss","rail_break"]:
		printerr("Expected faction, side 0/1, duration >=300, dt .001..0.1, fault none/miner_loss/refinery_loss/rail_break"); quit(2); return
	var match_runner = MatchRunner.new()
	var problem: String = match_runner.start({"map":"symmetric","factions":[faction,faction],"ai":"left" if side==0 else "right","difficulty":"normal","ai-styles":["balanced"],"seed":1})
	if not problem.is_empty(): printerr(problem); quit(2); return
	var sim = match_runner.sim
	for entity: Dictionary in sim.entities.values():
		if int(entity.team) != side: entity.hp = 10000000.0
	var next_sample: float = 30.0
	var fault_at: float = 300.0
	var fault_record: Dictionary = {}
	var deliveries: Array = []
	while float(sim.time) < duration - .00001 and sim.result.is_empty():
		sim.step(minf(delta,duration-float(sim.time)))
		for event: Dictionary in sim.events:
			if str(event.kind)=="delivery" and int(event.get("team",-1))==side: deliveries.append({"time":sim.time,"amount":event.get("amount",0),"id":event.get("id",-1)})
		sim.events.clear(); sim.notices.clear()
		for unit: Dictionary in sim.entities.values():
			if int(unit.team)!=side or not str(unit.spec).ends_with("_harvester") or bool(unit.get("emerging",false)): continue
			var id: int = int(unit.id)
			var prior: Dictionary = progress.get(id,{"pos":unit.pos,"cargo":unit.cargo,"at":sim.time})
			if (unit.pos as Vector2).distance_to(prior.pos)>.2 or absf(float(unit.cargo)-float(prior.cargo))>1.0:
				prior={"pos":unit.pos,"cargo":unit.cargo,"at":sim.time}
			progress[id]=prior
			longest_stalls[str(id)]=maxf(float(longest_stalls.get(str(id),0)),float(sim.time)-float(prior.at))
		if fault_record.is_empty() and str(options.fault)!="none" and float(sim.time)>=fault_at:
			var candidates: Array = []
			for entity: Dictionary in sim.entities.values():
				if int(entity.team)!=side: continue
				var role: String = str(sim.data_for(entity.spec).get("role",""))
				if (str(options.fault)=="miner_loss" and str(entity.spec).ends_with("_harvester")) or (str(options.fault)=="refinery_loss" and role in ["refinery","drill"]) or (str(options.fault)=="rail_break" and role=="rail"):
					candidates.append(entity)
			if not candidates.is_empty():
				var victim: Dictionary = candidates[0]
				fault_record={"time":sim.time,"id":victim.id,"spec":victim.spec,"pos":[victim.pos.x,victim.pos.y]}
				sim._kill_entity(int(victim.id),false)
			else: fault_record={"time":sim.time,"not_applicable":true}
		if float(sim.time)>=next_sample:
			var row: Dictionary = sim.statistics.snapshot(sim).teams[side]
			observations.append({"time":sim.time,"income":row.funds_earned,"money":sim.money[side],"harvesters":row.harvesters,"waiting_harvesters":row.waiting_harvesters,"units_produced":row.units_produced,"army_value":row.army_value})
			for id: int in progress:
				if not sim.entities.has(id) or float(sim.time)-float(progress[id].at)<30.0: continue
				var unit: Dictionary = sim.entities[id]
				stall_observations.append({"time":sim.time,"id":id,"seconds":float(sim.time)-float(progress[id].at),"pos":[unit.pos.x,unit.pos.y],"cargo":unit.cargo,"state":unit.state,"mine":unit.harvest_mine,"refinery":unit.harvest_refinery,"docking":unit.get("refinery_docking",{}).duplicate(true),"commands":str(unit.commands)})
			next_sample+=30
			await process_frame
	sim.statistics.sample(sim,true)
	var snapshot: Dictionary = sim.statistics.snapshot(sim)
	var own: Dictionary = snapshot.teams[side]
	if float(own.funds_earned)<3000: failures.append("insufficient normal mining income")
	if float(own.units_produced)<5: failures.append("fewer than five units completed normal production")
	var late_production: int = 0
	for event: Dictionary in snapshot.events:
		if str(event.kind)=="produce" and int(event.get("team",-1))==side and float(event.time)>=duration-180.0: late_production+=1
	var cutoff_income: float = 0.0
	for row: Dictionary in observations:
		if float(row.time)<=duration-180.0: cutoff_income=float(row.income)
	if float(own.funds_earned)-cutoff_income<500: failures.append("no completed income cycle in final 180 seconds")
	if not sim.result.is_empty(): failures.append("long passive-HQ observation ended unexpectedly")
	for id: String in longest_stalls:
		if float(longest_stalls[id])>120.0: failures.append("miner " + id + " made no movement/cargo progress for more than 120 seconds")
	var output: String = str(options.output)
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	problem=sim.save_game(output+".save")
	if not problem.is_empty(): failures.append("Checkpoint save failed: " + problem)
	var exported: Dictionary = Exporter.export_snapshot(snapshot,output)
	if not bool(exported.get("ok",false)): failures.append("telemetry export failed")
	var result: Dictionary = {"schema":"paper_front.ai_reliability_soak","options":options,"fixture":"Standard HQ and 4000 funds; passive opponent HQ HP extended to retain the observation window. Optional loss removes one entity, measuring single-loss tolerance. Excluded from win-rate experiments.","duration":sim.time,"checks_passed":failures.is_empty(),"failures":failures,"fault":fault_record,"observations":observations,"deliveries":deliveries,"max_no_movement_or_cargo_progress_seconds_by_miner":longest_stalls,"stall_observations":stall_observations,"completed_unit_production_final_180_seconds":late_production,"production_note":"Recent completions are observational; an intact army may legitimately stop production at its roster cap.","ai_state":sim.ai_state[side],"income":own.funds_earned,"export":exported}
	var file = FileAccess.open(output+"_reliability.json",FileAccess.WRITE)
	if file==null: printerr("Could not save reliability report"); quit(2); return
	file.store_string(JSON.stringify(result,"  "));file.close()
	print("AI_RELIABILITY ",JSON.stringify({"faction":faction,"side":side,"duration":sim.time,"income":own.funds_earned,"deliveries":deliveries.size(),"failures":failures,"max_stalls":longest_stalls}))
	quit(0 if failures.is_empty() else 1)
