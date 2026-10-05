extends SceneTree

const Sim=preload("res://tests/rule_test_simulation.gd")
var failures:Array[String]=[]

func _initialize()->void:
	var config:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/rules.json"))
	if not config is Dictionary:push_error("rules unavailable");quit(1);return
	var sim=Sim.new()
	var opts:Dictionary={"players":2,"slots":[{"faction":"rivet","control":"human","difficulty":"normal"},{"faction":"kestrel","control":"ai","difficulty":"hard"}]}
	sim.setup_multiteam(config,"islands",17,["rivet","kestrel"],true,[],Callable(),opts)
	var shipyard_seen:bool=false
	var transport_seen:bool=false
	var board_seen:bool=false
	var unload_seen:bool=false
	var full_water_yard:bool=true
	var max_time:float=450.0
	while sim.time<max_time and sim.result.is_empty():
		sim.step(1.0)
		for e in sim.entities.values():
			if int(e.team)!=1:continue
			if str(e.spec)=="kestrel_shipyard":
				shipyard_seen=true
				var size:int=int(sim.data_for(e.spec).size)
				var origin:=Vector2i(roundi(e.pos.x-size*.5),roundi(e.pos.y-size*.5))
				for z in range(origin.y,origin.y+size):
					for x in range(origin.x,origin.x+size):
						full_water_yard=full_water_yard and int(sim.map.terrain[z][x])==MapData.WATER
			if str(e.spec)=="kestrel_ship_transport":transport_seen=true
		for event in sim.events:
			if int(event.get("team",-1))!=1:continue
			if event.get("kind")=="board":board_seen=true
			if event.get("kind")=="unload":unload_seen=true
		sim.events.clear()
		if unload_seen:break
	if not shipyard_seen:failures.append("AI never legally built a shipyard")
	if not full_water_yard:failures.append("AI shipyard is not wholly on water")
	if not transport_seen:failures.append("AI never legally produced a transport ship")
	if not board_seen:failures.append("AI never boarded infantry onto the ship")
	if not unload_seen:failures.append("AI never unloaded infantry on an enemy island")
	if sim.money[1]<0.0:failures.append("AI spent beyond its funds")
	print("STAGE3_ISLAND_AI ",JSON.stringify({"time":sim.time,"shipyard":shipyard_seen,"full_water_shipyard":full_water_yard,"transport":transport_seen,"board":board_seen,"unload":unload_seen,"funds":sim.money[1],"failures":failures}))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
