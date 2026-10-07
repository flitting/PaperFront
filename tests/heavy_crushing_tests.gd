extends SceneTree
const Sim = preload("res://tests/rule_test_simulation.gd")
const V = preload("res://scripts/volume_models.gd")
const FACTIONS := ["kestrel","rivet","iron","sky"]
const ADVANCED := ["kestrel_advanced","rivet_assault","rivet_advanced","iron_assault","iron_advanced","sky_pulse"]
var checks: int=0
var failures: Array[String]=[]
var rules: Dictionary
var evidence: Array=[]
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures.append(message)
func _initialize() -> void: call_deferred("run")
func fixture(native_mode: bool, faction: String="rivet"):
	var sim=Sim.new()
	sim.native_kernels_enabled=native_mode; sim.native_unit_dispatch_enabled=native_mode; sim.native_geometry_enabled=native_mode; sim.native_movement_enabled=native_mode
	sim.setup(rules.duplicate(true),"dev",7,faction,false)
	for row in sim.map.terrain: row.fill(0)
	for row in sim.map.heights: row.fill(0.0)
	sim.mines.clear(); sim.bridges.clear(); sim.ruins.clear(); sim._refresh_mine_spatial(); sim._refresh_ruin_spatial()
	for id in sim.entities.keys(): sim._kill_entity(id,false)
	sim._spawn(0,faction+"_hq",Vector2(5,43),true); sim._spawn(1,"kestrel_hq",Vector2(43,43),true)
	sim._prepare_terrain_cache(); sim._nav_initialized=false; sim._rebuild_nav(); sim._rebuild_spatial(); sim.events.clear()
	return sim
func prepare(sim) -> void:
	sim._in_step=true; sim._spec_cache=sim.rules.units.duplicate(); sim._spec_cache.merge(sim.rules.buildings)
	sim._rebuild_spatial(); sim._prepare_native_queries()
func quiet(sim, team: int, spec: String, pos: Vector2) -> int:
	var id: int=sim._spawn(team,spec,pos,true)
	sim.entities[id].cooldown=10000.0
	return id
func close(sim) -> void:
	sim._in_step=false
	if sim._path_worker!=null: sim._path_worker.close()
func live_crush(native_mode: bool, faction: String) -> void:
	var sim=fixture(native_mode,faction)
	var attacker: int=quiet(sim,0,faction+"_heavy_tank",Vector2(12,22))
	var target: int=quiet(sim,1,"kestrel_tank",Vector2(18,22))
	var target_record: Dictionary=sim.entities[target]
	var hp: float=target_record.hp
	sim.issue([target],"hold",target_record.pos)
	sim.issue([attacker],"move",Vector2(28,22))
	var max_stride: float=0
	var crush_event: bool=false
	var death_event: bool=false
	var frames: int=0
	for frame in range(260):
		var before: Vector2=sim.entities[attacker].pos
		sim.step(.05); frames+=1
		max_stride=maxf(max_stride,before.distance_to(sim.entities[attacker].pos))
		for event in sim.events:
			if event.kind=="crush" and int(event.target)==target: crush_event=true
			if event.kind=="death" and int(event.id)==target:
				death_event=true
				check(int(event.cause.get("source",-1))==attacker,"crushing death retains attacker attribution")
		sim.events.clear()
		if not sim.entities.has(target): break
	var label: String=faction+" "+("native" if native_mode else "script")
	check(not sim.entities.has(target) and is_zero_approx(target_record.hp),label+" heavy crushes enemy ordinary tank during actual movement")
	check(crush_event and death_event,label+" emits contact and actual death feedback")
	check(max_stride<=float(sim.data_for(faction+"_heavy_tank").speed)*.05+.0001,label+" keeps configured movement stride without teleport")
	check(float(sim.statistics.teams[0].units_killed)==1 and is_equal_approx(float(sim.statistics.teams[0].damage_dealt),hp),label+" credits one kill and target HP damage")
	evidence.append({"faction":faction,"native":native_mode,"frames":frames,"position":str(sim.entities[attacker].pos),"maximum_stride":max_stride,"victim_hp_before":hp,"victim_hp_after":target_record.hp,"removed":not sim.entities.has(target)})
	close(sim)
func run() -> void:
	rules=RulesLoader.load_rules()
	check(not rules.is_empty(),"real gameplay rules validate")
	check(ClassDB.class_exists("PaperFrontKernels"),"native backend is present")
	if rules.is_empty(): finish(); return
	for faction in FACTIONS:
		var info: Dictionary=rules.units[faction+"_heavy_tank"]
		check(info.logical_size==2 and is_equal_approx(info.radius,1.0),faction+" heavy physical footprint is two cells")
		check(info.art=="heavy_tank" and info.requires.has(faction+"_tech"),faction+" heavy has independent art and advanced tech unlock")
		check(str(info.animations.idle).ends_with(faction+"_heavy_tank_portrait.png") and ResourceLoader.exists(info.animations.idle),faction+" uses its real newly rendered heavy portrait")
		var recipe: Dictionary=V._recipe(info,"unit",0)
		check(str(recipe.design).begins_with("heavy_"+faction),faction+" uses its independently authored heavy model")
		check(is_equal_approx(maxf(recipe.dimensions.x,recipe.dimensions.z),float(info.logical_size)*.96),faction+" heavy visual scale follows two-cell logical footprint with paper margin")
		for field in ["body_mesh","turret_mesh"]:
			var near: Mesh=recipe[field]
			var middle: Mesh=V.quality_mesh(near,0,"far")
			var far: Mesh=V.quality_mesh(near,0,"extreme")
			check(near.get_instance_id()!=middle.get_instance_id() and middle.get_instance_id()!=far.get_instance_id(),faction+" independent heavy mesh LODs "+field)
			check(near.surface_get_array_len(0)>middle.surface_get_array_len(0) and middle.surface_get_array_len(0)>far.surface_get_array_len(0),faction+" simplifies authored geometry in each tier "+field)
		var sim=fixture(false,faction)
		sim.money[0]=10000
		var factory_id: int=sim._spawn(0,faction+"_factory",Vector2(12,8),true)
		check(not sim.produce(factory_id,faction+"_heavy_tank").is_empty(),faction+" heavy cannot queue before tech unlock")
		sim._spawn(0,faction+"_tech",Vector2(28,8),true)
		check(sim.produce(factory_id,faction+"_heavy_tank").is_empty(),faction+" real factory accepts heavy after tech unlock")
		close(sim)
	# Cost-efficient ordinary armor remains ordinary: it must not beat a newly
	# unlocked heavy in a stationary one-on-one just because of its low cost.
	for faction in FACTIONS:
		var battle=fixture(true,"kestrel")
		var cheap: int=battle._spawn(0,"kestrel_tank",Vector2(12,22),true)
		var heavy: int=battle._spawn(1,faction+"_heavy_tank",Vector2(20,22),true)
		battle.issue([cheap],"hold",Vector2(12,22)); battle.issue([heavy],"hold",Vector2(20,22))
		for frame in range(1200):
			battle.step(.05); battle.events.clear()
			if not battle.entities.has(cheap) or not battle.entities.has(heavy): break
		check(not battle.entities.has(cheap) and battle.entities.has(heavy),"ordinary cheap kestrel tank loses live equal-count duel to "+faction+" heavy")
		close(battle)
	for native_mode in [false,true]:
		for faction in FACTIONS: live_crush(native_mode,faction)
		var sim=fixture(native_mode)
		var a: int=quiet(sim,0,"rivet_heavy_tank",Vector2(12,20))
		for entry in [["kestrel_tank",1,true],["kestrel_rifle",1,true],["rivet_tank",0,false],["kestrel_heavy_tank",1,false],["kestrel_advanced",1,false],["sky_fighter",1,false],["iron_train",1,false],["iron_harvester",1,false],["sky_ship_frigate",1,false]]:
			var target: int=quiet(sim,int(entry[1]),str(entry[0]),Vector2(18,20))
			prepare(sim)
			check(sim._can_crush_target(sim.entities[a],sim.entities[target])==bool(entry[2]),"ground crush eligibility "+str(entry)+" native="+str(native_mode))
			if sim.data_for(str(entry[0])).get("domain","ground")=="ground":
				check(sim._movement_clear(sim.entities[a],Vector2(12,20),Vector2(24,20))==bool(entry[2]),"actual collision clearance respects crush class "+str(entry[0])+" native="+str(native_mode))
			var hp: float=sim.entities[target].hp
			sim._settle_crushing(sim.entities[a],Vector2(24,20))
			check(is_zero_approx(sim.entities[target].hp) if bool(entry[2]) else is_equal_approx(sim.entities[target].hp,hp),"swept crush preserves exempt targets "+str(entry[0]))
			sim._kill_entity(target,false)
		for source_spec in ["sky_fighter","sky_ship_frigate","iron_train"]:
			var source: int=quiet(sim,0,source_spec,Vector2(12,18))
			var victim: int=quiet(sim,1,"kestrel_rifle",Vector2(18,18))
			sim.entities[source].can_crush=true; sim.entities[source].crush_strength=99
			check(not sim._can_crush_target(sim.entities[source],sim.entities[victim]),"domain/rail exemption prevents non-ground source crushing "+source_spec)
			sim._kill_entity(source,false);sim._kill_entity(victim,false)
		for selected in ADVANCED:
			var source: int=quiet(sim,0,selected,Vector2(12,18))
			var victim: int=quiet(sim,1,"kestrel_tank",Vector2(18,18))
			check(sim._can_crush_target(sim.entities[source],sim.entities[victim]),selected+" selected heavy can crush ordinary tank")
			check(not sim._can_crush_target(sim.entities[a],sim.entities[source]),selected+" is protected against equal tier")
			sim._kill_entity(source,false);sim._kill_entity(victim,false)
		var ordinary: int=quiet(sim,0,"rivet_tank",Vector2(12,18))
		var enemy_tank: int=quiet(sim,1,"kestrel_tank",Vector2(18,18))
		var enemy_infantry: int=quiet(sim,1,"kestrel_rifle",Vector2(20,18))
		check(not sim._can_crush_target(sim.entities[ordinary],sim.entities[enemy_tank]) and sim._can_crush_target(sim.entities[ordinary],sim.entities[enemy_infantry]),"ordinary tank retains infantry-only crushing")
		var wall: int=sim._spawn(1,"kestrel_wall",Vector2(18,20),true)
		prepare(sim)
		check(not sim._movement_clear(sim.entities[a],Vector2(12,20),Vector2(24,20)),"heavy crushing never bypasses a solid wall")
		sim._kill_entity(wall,false)
		sim.map.terrain[20][18]=1;sim._prepare_terrain_cache();sim._rebuild_nav();prepare(sim)
		check(not sim._movement_clear(sim.entities[a],Vector2(12,20),Vector2(24,20)),"heavy crushing never bypasses impassable water")
		close(sim)
		var saved_sim=Sim.new()
		saved_sim.native_kernels_enabled=native_mode
		saved_sim.setup(rules.duplicate(true),"dev",7,"rivet",false)
		var saved_heavy: int=quiet(saved_sim,0,"rivet_heavy_tank",Vector2(12,20))
		var save_path: String="user://heavy_crushing_test.save"
		saved_sim.entities[saved_heavy].crush_strength=99
		check(saved_sim.save_game(save_path).is_empty(),"heavy matches can save")
		var load_error: String=saved_sim.load_game(save_path)
		check(load_error.is_empty(),"heavy matches can load: "+load_error)
		check(int(saved_sim.entities[saved_heavy].crush_strength)==2 and int(saved_sim.entities[saved_heavy].crush_resistance)==2,"load reconstructs authoritative crush classes from rules")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
		var blast_target: int=quiet(saved_sim,1,"kestrel_heavy_tank",Vector2(20,20))
		var blast_hp: float=saved_sim.entities[blast_target].hp
		saved_sim._impact_damage(Vector2(20,20),1.0,25,{},["ground"],false,{"kind":"shell"},0)
		saved_sim._apply_damage()
		check(is_equal_approx(saved_sim.entities[blast_target].hp,blast_hp-25),"heavy crush resistance does not suppress ordinary area damage")
		close(saved_sim)
	finish()
func finish() -> void:
	print("HEAVY_CRUSHING ",JSON.stringify({"checks":checks,"failures":failures,"movement":evidence}))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
