extends SceneTree
const Sim = preload("res://tests/rule_test_simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
const Garrison = preload("res://scripts/garrison_operations.gd")
var failures: Array[String] = []
var checks: int = 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)
func _initialize() -> void:
	var config: Dictionary = Rules.load_rules("res://data/rules.json", false)
	var delta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/infantry_revision_v3.json"))
	config.units.merge(delta.units, true)
	config.weapons.merge(delta.weapons, true)
	for spec: String in delta.units:
		if spec in ["iron_rifle","iron_engineer"]: continue
		var info: Dictionary = delta.units[spec]
		var art_complete: bool = true
		for pose: String in ["idle","move","combat","hit","death"]:
			for tier: int in range(3):
				art_complete = art_complete and ResourceLoader.exists("res://assets/cards/paper_infantry_revision/%s_%s_%d.svg" % [spec,pose,tier])
		check(art_complete,"action/LOD art: "+spec)
		check(info.get("voice_category", "") == "infantry", "existing faction infantry voice profile: "+spec)
		check(float(config.weapons[info.weapon].get("penetration", -1)) >= 0, "armor penetration defined: "+spec)
	for faction: String in ["rivet","kestrel","iron","sky"]:
		var count: int = 0
		for spec: String in config.units:
			var info: Dictionary = config.units[spec]
			if info.faction == faction and info.get("armor_class", "") == "infantry": count += 1
		check(count >= (7 if faction == "kestrel" else 5), faction+" roster")
		var production = Sim.new()
		production.setup(config,"dev",13,faction,false)
		production.money[0] = 50000.0
		var barracks: int = -1
		if faction == "rivet":
			for e: Dictionary in production.entities.values():
				if int(e.team)==0 and e.spec=="rivet_hq": barracks=int(e.id); break
		else: barracks = production.debug_spawn(0,faction+"_barracks",Vector2(12,22))
		production.debug_spawn(0,faction+"_factory",Vector2(16,10))
		for spec: String in delta.units:
			if spec in ["iron_rifle","iron_engineer"] or delta.units[spec].faction != faction: continue
			var before: float = production.money[0]
			var error: String = production.produce(barracks,spec)
			check(error.is_empty(),"barracks produces "+spec+": "+error)
			check(production.money[0] < before and production.entities[barracks].queue.back().spec == spec,"production debits and queues "+spec)
	var sim = Sim.new()
	sim.setup(config,"dev",19,"kestrel",false)
	sim.vision_enabled = false
	var ruin: Dictionary = {}
	for r: Dictionary in sim.ruins:
		if r.kind == "house": ruin = r; break
	if ruin.is_empty():
		ruin = {"id":sim.ruins.size(),"kind":"house","pos":Vector2(24,24),"half":Vector2(1.5,1.35),"yaw":0.0,"hp":900.0,"max_hp":900.0,"variant":0}
		sim.ruins.append(ruin)
		sim._rebuild_nav()
	check(not ruin.is_empty(),"house exists")
	var target: int = Garrison.BASE-int(ruin.id)
	var a: int = sim.debug_spawn(0,"kestrel_rifle",ruin.pos+Vector2(4,0))
	var b: int = sim.debug_spawn(0,"kestrel_rifle",ruin.pos+Vector2(-4,0))
	var engineer: int = sim.debug_spawn(0,"kestrel_engineer",ruin.pos+Vector2(0,4))
	check(not Garrison.board_error(sim,engineer,target).is_empty(),"engineer rejected")
	for id: int in [a,b]:
		var e: Dictionary = sim.entities[id]
		var doorway: Vector2 = Garrison._door(sim,ruin,e)
		e.pos = doorway
		sim.issue([id],"garrison",ruin.pos,target)
		sim.step(1.0/30.0)
	check(ruin.get("garrison",[]).size()==2,"two infantry boarded")
	check(sim.Transport.is_loaded(sim.entities[a]),"loaded excludes navigation and target")
	var snapshot: Dictionary = {"entities":sim.entities.duplicate(true),"ruins":sim.ruins.duplicate(true),"map":sim.map,"rules":sim.rules,"factions":sim.factions}
	check(Garrison.validate_snapshot(snapshot).is_empty(),"valid reciprocal garrison snapshot")
	var save_path: String = "user://garrison_revision_v3.save"
	check(sim.save_game(save_path).is_empty(),"save occupied building")
	var restored = Sim.new()
	var load_error: String = restored.load_game(save_path)
	check(load_error.is_empty(),"load occupied building: "+load_error)
	if load_error.is_empty():
		check(restored.ruins[int(ruin.id)].garrison.size()==2 and Garrison.loaded(restored.entities[a]),"load preserves both occupants")
		check(Garrison.unload(restored,target,false,0).is_empty(),"saved occupants can exit")
		check(not Garrison.loaded(restored.entities[a]),"loaded unit exits to active simulation")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	var corrupt: Dictionary = snapshot.duplicate(true)
	corrupt.entities[a].garrison_id = -1
	check(not Garrison.validate_snapshot(corrupt).is_empty(),"orphaned snapshot is rejected")
	corrupt = snapshot.duplicate(true)
	corrupt.ruins[int(ruin.id)].garrison.append(a)
	check(not Garrison.validate_snapshot(corrupt).is_empty(),"duplicate occupant snapshot rejected")
	corrupt = snapshot.duplicate(true)
	corrupt.entities[a].spec = "kestrel_engineer"
	check(not Garrison.validate_snapshot(corrupt).is_empty(),"engineer garrison snapshot rejected")
	var enemy: int = sim.debug_spawn(1,"rivet_rifle",ruin.pos+Vector2(0,-4))
	check(not Garrison.board_error(sim,enemy,target).is_empty(),"enemy cannot board occupied house")
	sim._rebuild_spatial()
	Garrison.step(sim,.1)
	var shooters: Array = []
	for event: Dictionary in sim.events:
		if event.kind == "fire" and int(event.id) in [a,b]:
			shooters.append(int(event.id))
			check(float(event.height) > .9,"window firing height")
			check((event.pos as Vector2).distance_to(ruin.pos) > .9,"window firing position")
	check(shooters.size()==2,"both occupants fire independently")
	check(int(sim._damage_causes.get(enemy,{}).get("source",-1)) in [a,b],"actual infantry damage attribution")
	sim._add_damage(target,float(ruin.max_hp)*.81,true)
	sim._apply_damage()
	check(ruin.garrison.is_empty(),"low hp forces both out")
	for id: int in [a,b]:
		check(not sim.Transport.is_loaded(sim.entities[id]),"evacuee is active")
		check(sim._standing(sim.entities[id].pos,sim._radius(sim.entities[id]),id),"legal evacuation position")
	check(not Garrison.board_error(sim,a,target).is_empty(),"damaged building rejects reentry")
	ruin.hp = float(ruin.max_hp)
	for id: int in [a,b,engineer]: sim._kill_entity(id,false)
	sim._rebuild_spatial()
	var e: Dictionary = sim.entities[enemy]
	e.pos = Garrison._door(sim,ruin,e)
	e.commands = [{"kind":"garrison","target":target,"pos":ruin.pos}]
	Garrison.step_board(sim,e,e.commands[0],.1)
	check(int(ruin.garrison_team)==1,"vacant house can change owner")
	sim._kill_entity(enemy,true)
	check(ruin.garrison.is_empty() and int(ruin.garrison_team)==-1,"death removes occupant and ownership")
	finish()
func finish() -> void:
	print("Infantry/garrison v3: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
