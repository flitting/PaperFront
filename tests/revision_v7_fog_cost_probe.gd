extends SceneTree
const SIM=preload("res://scripts/simulation.gd")
const WORLD=preload("res://scripts/paper_world.gd")
var rows:Array=[]
func _initialize()->void:
	for count:int in [38,80,150]:
		var sim=SIM.new();sim.factions.assign(["rivet","kestrel"]);sim.vision_enabled=true
		sim.rules={"units":{"rivet_rifle":{"domain":"ground","vision_radius":16}},"buildings":{}}
		sim.map={"size":320,"seed":7,"mode":"forest","terrain":[],"heights":[]}
		for z:int in 320:
			var heights:Array=[];var terrain:Array=[]
			for x:int in 320:heights.append(0.0);terrain.append(0)
			sim.map.heights.append(heights);sim.map.terrain.append(terrain)
		for id:int in count:
			sim.entities[id]={"id":id,"team":0,"hp":100,"kind":"unit","spec":"rivet_rifle","pos":Vector2(10+(id%12)*25,10+(id/12)*23)}
		sim.TeamVision.initialize(sim)
		var memory=WORLD.SightMemory.new();memory.initialize(320)
		var times:Array[int]=[];var queries:Array[int]=[]
		for tick:int in 8:
			for id:int in sim.entities:sim.entities[id].pos+=Vector2(.75,0)
			sim.TeamVision.refresh(sim,true)
			var start:int=Time.get_ticks_usec();memory.refresh(sim)
			times.append(Time.get_ticks_usec()-start);queries.append(memory.queries)
		var stationary_start:int=Time.get_ticks_usec();memory.refresh(sim)
		rows.append({"observers":count,"mask_pixels":memory.width*memory.width,"refresh_microseconds":times,"queries":queries,"stationary_microseconds":Time.get_ticks_usec()-stationary_start,"stationary_queries":memory.queries})
	var out:=FileAccess.open("res://artifacts/revision_v7_integration/fog_cpu.json",FileAccess.WRITE)
	out.store_string(JSON.stringify({"scope":"pure CPU fog query cost only; no landscape/GPU/mainloop/performance improvement claim","cell_size":2,"cadence_seconds":.2,"rows":rows},"  "));out.close()
	print("V7_FOG_CPU ",JSON.stringify(rows));quit()
