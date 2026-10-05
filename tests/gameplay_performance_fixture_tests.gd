extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Rules=preload("res://scripts/rules_loader.gd")
const Factions=preload("res://scripts/performance_factions.gd")
const Probe=preload("res://scripts/gameplay_performance.gd")

class FakeGame:
	extends Node
	var sim
	var exit_code:int=-1
	func quit_game(code:int=0)->void:exit_code=code

var checks:int=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
func _initialize()->void:
	var config:Dictionary=Factions.make_rules(Rules.load_rules())
	var ids:Array[String]=Factions.ids()
	var unique:Dictionary={}
	for id in ids:unique[id]=true
	check(ids.size()==8 and unique.size()==8 and Rules.validate(config,false).is_empty(),"the final pressure configuration contains eight independently identified valid factions")
	var templates:Dictionary={}
	for team in range(8):
		var template:String=Factions.art_template(team)
		templates[template]=int(templates.get(template,0))+1
		for role in ["tank","fighter","harvester"]:
			var spec:Dictionary=config.units[ids[team]+"_"+role]
			check(VolumeModels.art_faction(spec)==template and spec.weapon==config.units[template+"_"+role].weapon,"pressure owner %d uses the real %s model and weapon for %s"%[team,template,role])
	check(templates=={"rivet":2,"kestrel":2,"iron":2,"sky":2},"the pressure fixture includes all four playable factions twice")
	var center:=Vector2(320,352)
	var hqs:Array[Vector2]=[]
	for team in range(8):hqs.append(center+Vector2.from_angle(float(team)*TAU/8.0)*70.0)
	var sim=Sim.new()
	sim.setup_multiteam(config,"mountains640",73026,ids,false,hqs)
	for team in range(8):sim.money[team]=100000.0
	var fake=FakeGame.new()
	fake.sim=sim
	var probe=Probe.new()
	probe.game=fake
	probe.options={"case":"stress"}
	probe.center=center
	probe.start_us=1
	probe._populate_eight_factions()
	check(sim.map.size==640 and sim.factions==ids,"the real pressure fixture uses the 640 map and preserves all eight independent owners")
	_check_population(sim,"initial pressure population")
	_check_airfields(sim,"initial pressure air support")
	var killed:Dictionary={}
	for team in [0,3,7]:
		for air in [false,true]:
			var victim:int=_first_unit(sim,team,air)
			check(victim>0,"a real "+("air" if air else "ground")+" victim exists for team "+str(team))
			if victim<0:continue
			var e:Dictionary=sim.entities[victim]
			killed[victim]={"team":team,"air":air,"spec":e.spec,"pos":e.pos}
			sim._add_damage(victim,float(e.hp)+1.0)
	var hurt:int=_first_unit(sim,2,false)
	var hurt_hp:float=sim.entities[hurt].hp
	sim._add_damage(hurt,7.0)
	sim._apply_damage();sim._damage.clear()
	# Faction mitigation changes the amount of real damage. Replenishment must
	# preserve the resulting health rather than assuming the raw damage is final.
	var injured_hp:float=sim.entities[hurt].hp
	check(injured_hp<hurt_hp,"the surviving pressure unit receives actual simulation damage")
	check(killed.keys().all(func(id):return not sim.entities.has(id)),"real damage and death remove every selected ground and aircraft victim")
	var original_events:Array=sim.events.duplicate(true)
	var old_ids:Dictionary={}
	for id in sim.entities:old_ids[id]=true
	probe.after_tick()
	check(fake.exit_code==-1,"reserve replenishment accepts the actual eight-faction fixture without aborting")
	_check_population(sim,"population after six real casualties")
	check(probe.reinforcement_spawns==6 and probe.reinforcement_air_spawns==3,"the fixed pressure workload restores exactly the lost three ground and three aircraft units")
	var replacements:Array[int]=[]
	for id in sim.entities:
		if not old_ids.has(id):replacements.append(int(id))
	check(replacements.size()==6 and replacements.all(func(id):return not killed.has(id)),"reinforcements have newly generated IDs rather than resurrecting dead entities")
	check(killed.keys().all(func(id):return sim.events.any(func(event):return event.get("kind")=="death" and int(event.get("id",-1))==id)),"normal death events remain available for world effects after replenishment")
	check(original_events.all(func(event):return sim.events.has(event)),"the reserve workload preserves existing simulation events")
	check(absf(float(sim.entities[hurt].hp)-injured_hp)<.001,"fixed population does not heal or replace an injured surviving unit")
	var counter:int=sim._next_id
	probe.after_tick()
	check(sim._next_id==counter and probe.reinforcement_spawns==6 and probe.reinforced_death_ids.size()==6,"calling after_tick twice on the same death events cannot replenish them twice")
	_check_airfields(sim,"reserve aircraft air support")
	var before:float=sim.time
	for tick in range(5):
		sim.step(1.0/30.0)
		probe.after_tick()
		sim.events.clear()
	check(absf(sim.time-before-5.0/30.0)<.00001 and fake.exit_code==-1,"subsequent real simulation ticks advance without health or clock shortcuts")
	_check_population(sim,"population after subsequent actual simulation ticks")
	_check_airfields(sim,"air support after subsequent actual simulation ticks")
	# Test building reserves without resurrecting the old airport or its queue.
	var lost_airfield:int=-1
	for building in sim._building_entities:
		if int(building.team)==2 and sim.data_for(building.spec).get("role","")=="airfield":
			lost_airfield=int(building.id)
			break
	var footprint:Vector2=sim.entities[lost_airfield].pos
	sim._add_damage(lost_airfield,float(sim.entities[lost_airfield].hp)+1.0)
	sim._apply_damage();sim._damage.clear()
	probe.after_tick()
	check(not sim.entities.has(lost_airfield) and probe.reinforcement_building_spawns==1,"airport reserves preserve real destruction and create one new building ID")
	check(sim._building_entities.any(func(e):return int(e.team)==2 and e.pos==footprint and e.spec=="iron_airfield" and int(e.id)!=lost_airfield),"the real iron airfield is rebuilt at its original footprint")
	_check_population(sim,"population after airport destruction and reserve reconstruction")
	sim.events.clear();sim.step(1.0/30.0);probe.after_tick();sim.events.clear()
	_check_airfields(sim,"airport ownership and capacity after reconstruction")
	var path:String="/tmp/paper_war_final_pressure_fixture.save"
	check(sim.save_game(path).is_empty(),"the final fixed-population pressure state writes a normal game snapshot")
	var restored=Sim.new()
	var error:String=restored.load_game(path)
	check(error.is_empty() and restored.factions==ids and restored.entities==sim.entities and restored.money==sim.money,"the pressure state restores real faction, aircraft and unit state: "+error)
	if error.is_empty():
		_check_population(restored,"restored pressure population")
		_check_airfields(restored,"restored pressure air support")
		var loaded_time:float=restored.time
		restored.step(1.0/30.0)
		check(absf(restored.time-loaded_time-1.0/30.0)<.00001,"restored pressure units can resume a real simulation step")
	DirAccess.remove_absolute(path)
	probe.free();fake.sim=null;fake.free();sim=null;restored=null
	print("Gameplay performance fixture checks: ",checks-failures.size()," passed, ",failures.size()," failed")
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
func _first_unit(sim,team:int,air:bool)->int:
	for e in sim.entities.values():
		if e.kind=="unit" and int(e.team)==team and sim._is_air(e)==air:return int(e.id)
	return -1
func _check_population(sim,label:String)->void:
	var total:=Vector2i.ZERO
	for team in range(8):
		var count:Vector2i=sim.counts(team)
		var aircraft:int=0
		for e in sim.entities.values():
			if e.kind=="unit" and int(e.team)==team and sim._is_air(e):aircraft+=1
		check(count==Vector2i(100,20) and aircraft==20 and count.x-aircraft==80,label+" retains exactly 20 buildings, 80 ground and 20 air units for team "+str(team))
		total+=count
	check(total==Vector2i(800,160),label+" contains exactly 800 live units and 160 live buildings")
func _check_airfields(sim,label:String)->void:
	var fields:Array[int]=[]
	fields.resize(8);fields.fill(0)
	var guaranteed:bool=true
	for e in sim.entities.values():
		if e.kind=="building" and sim.data_for(e.spec).get("role","")=="airfield":
			fields[int(e.team)]+=1
			guaranteed=guaranteed and sim._airfield_load(int(e.id))<=int(sim.data_for(e.spec).aircraft_capacity)
		elif sim._is_air(e):guaranteed=guaranteed and sim._airfield_valid(int(e.home_airfield),int(e.team))
	check(fields.all(func(count):return count==5) and guaranteed,label+" provides five friendly capacity-limited airfields for each of the eight factions")
