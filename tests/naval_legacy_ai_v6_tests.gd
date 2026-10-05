extends SceneTree

const Sim=preload("res://tests/rule_test_simulation.gd")
const Layout=preload("res://scripts/competitive_layout.gd")
const Ops=preload("res://scripts/naval_operations.gd")
var failures:Array[String]=[]
var checks:int=0
func _initialize()->void:
	var rules:Dictionary=RulesLoader.load_rules("res://data/rules.json",false)
	for f:String in ["rivet","kestrel","iron","sky"]:
		rules.buildings[f+"_shipyard"].erase("domain")
		rules.buildings[f+"_shipyard"].coast_split=.5
	var opts:Dictionary={"players":2,"slots":[{"faction":"rivet","control":"human","difficulty":"normal"},{"faction":"kestrel","control":"ai","difficulty":"hard"}]}
	var sim=Sim.new()
	sim.setup(rules,"islands",17,"rivet",true,opts)
	var path:String="user://v6_legacy_island_ai.pfront"
	check(sim.save_game(path).is_empty(),"real serializer creates initial snapshot fixture")
	var file:FileAccess=FileAccess.open(path,FileAccess.READ)
	var state:Dictionary=file.get_var(false)
	file.close()
	# Replace geography with the preserved V5 generator. No economy, timers,
	# completed facilities or deployed units are granted to the AI fixture.
	var old_map:Dictionary=Layout.generate_legacy("islands",17,{"players":2})
	old_map.valid=true
	old_map.validation_errors=[]
	state.map=old_map
	state.ruins=old_map.ruins.duplicate(true)
	state.mines=[]
	for mine:Dictionary in old_map.mines:
		var capacity:float=float(rules.economy.ore_capacity)
		state.mines.append({"pos":Vector2(mine.pos[0],mine.pos[1]),"amount":capacity,"capacity":capacity,"miner":-1})
	state.bridges=[]
	for bridge:Dictionary in old_map.bridges:
		state.bridges.append({"id":int(bridge.id),"bounds":bridge.bounds.duplicate(),"heads":bridge.heads.duplicate(),"hp":float(rules.economy.bridge_hp),"repair_progress":0.0,"alive":true})
	for e:Dictionary in state.entities.values():
		e.pos=Vector2(old_map.starts[e.team][0],old_map.starts[e.team][1])
		e.rally=e.pos+Vector2(0,float(rules.buildings[e.spec].size)*.5+3)
	state.nav_dirty=true
	state.nav_regions=[]
	file=FileAccess.open(path,FileAccess.WRITE)
	file.store_var(state,false)
	file.close()
	var restored=Sim.new()
	var error:String=restored.load_game(path)
	check(error.is_empty(),"V5 geography and old ground-domain shipyard snapshot loads: "+error)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if not error.is_empty():finish({});return
	var board:bool=false
	var unload:bool=false
	var yard:bool=false
	var ship:bool=false
	var minimum_funds:float=restored.money[1]
	while restored.time<600.0 and restored.result.is_empty():
		restored.step(1.0)
		minimum_funds=minf(minimum_funds,restored.money[1])
		for e in restored.entities.values():
			if e.team==1 and e.spec=="kestrel_shipyard":yard=true
			if e.team==1 and e.spec=="kestrel_ship_transport":ship=true
		for event:Dictionary in restored.events:
			if int(event.get("team",-1))!=1:continue
			if event.get("kind")=="board":board=true
			if event.get("kind")=="unload":unload=true
		restored.events.clear()
		if unload:break
	check(yard and ship and board and unload,"V5 snapshot AI pays for factory, ship, boarding and enemy-shore unloading")
	check(minimum_funds>=0.0,"old-map AI never receives negative funds")
	# A new full-water policy can also run on retained V5 geography. The known
	# edge-channel trap must fail while the owned harbor still has a safe site.
	var updated:Dictionary=state.duplicate(true)
	updated.rules=RulesLoader.load_rules("res://data/rules.json",false)
	file=FileAccess.open(path,FileAccess.WRITE)
	file.store_var(updated,false);file.close()
	var water_sim=Sim.new()
	check(water_sim.load_game(path).is_empty(),"new water-yard rules load preserved V5 geography")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var info:Dictionary=water_sim.data_for("rivet_shipyard")
	check(not Ops.shipyard_site_error(water_sim,0,info,Vector2(6,134)).is_empty(),"new construction rejects the V5 seed31 border-channel trap")
	var replacement:Vector2=Vector2.INF
	var harbor:Dictionary=water_sim.map.harbors[0]
	for ring in range(21):
		for side in range(24):
			var wanted:Vector2=harbor.water_pos+Vector2.from_angle(float(side)*TAU/24)*float(ring)*.9
			var site:=Vector2(roundf(wanted.x),roundf(wanted.y))
			if Ops.shipyard_site_error(water_sim,0,info,site).is_empty():replacement=site;break
		if replacement.is_finite():break
	check(replacement.is_finite(),"new water-yard policy finds a safe alternative on retained V5 islands")
	finish({"time":restored.time,"yard":yard,"ship":ship,"board":board,"unload":unload,"minimum_funds":minimum_funds,"design_version":restored.map.profile.get("design_version",5)})
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
func finish(details:Dictionary)->void:
	print("V6_LEGACY_NAVAL_AI ",JSON.stringify({"checks":checks,"failures":failures,"details":details}))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
