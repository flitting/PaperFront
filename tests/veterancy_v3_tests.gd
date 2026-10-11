extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
const Garrison = preload("res://scripts/garrison_operations.gd")
var config: Dictionary
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	config = Rules.load_rules("res://data/rules.json",false)
	if config.is_empty(): push_error(str(Rules.errors)); quit(1); return
	_threshold_and_attribution()
	_live_combat()
	_automatic_range_and_rate()
	_regeneration_and_repairs()
	_save_and_load()
	_garrison_kills()
	print("Veterancy v3: %d checks, %d failures" % [checks,failures.size()])
	for label: String in failures: push_error(label)
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func near(a: float, b: float) -> bool: return absf(a-b)<.0001

func fixture():
	var sim = Sim.new()
	sim.setup(config,"dev",31,"kestrel",false)
	sim.vision_enabled = false
	sim.money[0] = 100000.0
	return sim

func clear_damage(sim) -> void:
	sim._damage.clear()
	sim._damage_causes.clear()

func credited_kill(sim, source: int, team: int = 1, spec: String = "kestrel_rifle") -> int:
	var victim: int = sim.debug_spawn(team,spec,Vector2(31.5,31.5))
	clear_damage(sim)
	sim._add_damage(victim,float(sim.entities[victim].hp)+1.0,true,{"source":source,"source_team":int(sim.entities[source].team),"weapon":"kestrel_rifle","explosive":false})
	sim._apply_damage()
	clear_damage(sim)
	return victim

func promote(sim, source: int) -> void:
	var cost: float = float(sim.data_for(sim.entities[source].spec).cost)
	var needed: int = floori(cost * 3.0 / float(sim.data_for("kestrel_rifle").cost)) + 1
	for i in range(needed): credited_kill(sim,source)

func _threshold_and_attribution() -> void:
	var sim = fixture()
	var id: int = sim.debug_spawn(0,"kestrel_rifle",Vector2(12.5,28.5))
	var unit: Dictionary = sim.entities[id]
	var own_cost: float = float(sim.data_for(unit.spec).cost)
	unit.hp = 51.0
	var victim: int = credited_kill(sim,id)
	check(not sim.entities.has(victim),"damage settlement destroys victim")
	check(near(float(unit.experience_value),own_cost),"first enemy cost credited to actual source")
	credited_kill(sim,id)
	credited_kill(sim,id)
	check(near(float(unit.experience_value),own_cost*3),"three equal-cost kills exactly hit threshold")
	check(not bool(unit.veteran),"equal to three times own cost does not promote")
	credited_kill(sim,id,0)
	check(near(float(unit.experience_value),own_cost*3),"friendly fire kill grants no experience")
	var neutral: Dictionary = {"id":sim.ruins.size(),"kind":"house","pos":Vector2(24,24),"half":Vector2(1.5,1.35),"yaw":0.0,"hp":900.0,"max_hp":900.0,"variant":0}
	sim.ruins.append(neutral)
	clear_damage(sim)
	sim._add_damage(Garrison.BASE-int(neutral.id),1000,true,{"source":id,"source_team":0,"weapon":"kestrel_rifle"})
	sim._apply_damage()
	check(near(float(unit.experience_value),own_cost*3),"neutral building destruction grants no experience")
	credited_kill(sim,id)
	check(bool(unit.veteran),"strictly exceeding threshold promotes")
	check(near(sim.max_hp(unit),float(config.units.kestrel_rifle.hp)*1.15),"promotion grants 15 percent maximum health")
	check(near(float(unit.hp),51+float(config.units.kestrel_rifle.hp)*.15),"promotion adds newly granted health capacity")
	check(near(float(unit.max_hp),sim.max_hp(unit)),"serialized maximum health agrees with authoritative cap")
	var events: int = 0
	for event: Dictionary in sim.events:
		if event.kind == "promotion" and int(event.id)==id: events+=1
	credited_kill(sim,id)
	var later_events: int = 0
	for event: Dictionary in sim.events:
		if event.kind == "promotion" and int(event.id)==id: later_events+=1
	check(events==1 and later_events==1,"promotion fires once and bonuses do not stack per kill")
	check(near(sim.armor_for(unit),float(config.units.kestrel_rifle.armor)*1.1),"promotion grants 10 percent armor")

func _live_combat() -> void:
	var sim = fixture()
	var source_id: int = sim.debug_spawn(0,"kestrel_rifle",Vector2(10.5,30.5))
	var source: Dictionary = sim.entities[source_id]
	var target_id: int = sim.debug_spawn(1,"rivet_rifle",Vector2(15.5,30.5))
	var target: Dictionary = sim.entities[target_id]
	var base: Dictionary = config.weapons.kestrel_rifle.duplicate(true)
	var before: float = target.hp
	sim._fire(source,target_id)
	sim._apply_damage()
	check(near(before-float(target.hp),float(base.damage)),"ordinary bullet uses ordinary damage")
	check(near(float(source.cooldown),float(base.interval)),"ordinary shot starts base interval")
	clear_damage(sim)
	source.cooldown = 0.0
	target.pos = source.pos+Vector2(float(base.range)*1.04,0)
	sim._fire(source,target_id)
	check(sim._damage.is_empty() and near(float(source.cooldown),0),"ordinary unit cannot fire outside ordinary range")
	promote(sim,source_id)
	source.cooldown = 0.0
	before = target.hp
	sim._fire(source,target_id)
	sim._apply_damage()
	check(near(before-float(target.hp),float(base.damage)*1.1),"veteran shot actually hits beyond old range with stronger damage")
	check(near(float(source.cooldown),float(base.interval)/1.1),"veteran shot actually starts shorter cooldown")
	check(near(float(sim.weapon_for(source).range),float(base.range)*1.08),"range bonus is exactly 8 percent")
	clear_damage(sim)
	source.cooldown = 0.0
	target.pos = source.pos+Vector2(float(base.range)*1.09,0)
	sim._fire(source,target_id)
	check(sim._damage.is_empty(),"veteran cannot fire beyond extended range")
	# A weapon just above ordinary armor enters the 80%-threshold partial band
	# against veteran armor; compare settled health, not only exposed numbers.
	var normal_id: int = sim.debug_spawn(0,"kestrel_rifle",Vector2(14.5,27.5))
	var normal: Dictionary = sim.entities[normal_id]
	var armor_probe: Dictionary = {"damage":40.0,"penetration":float(config.units.kestrel_rifle.armor)*1.05,"multipliers":{}}
	var ordinary_before: float = normal.hp
	var veteran_before: float = source.hp
	sim._add_damage(normal_id,sim._weapon_damage(40,normal_id,armor_probe),true,{"source":target_id,"source_team":1})
	sim._add_damage(source_id,sim._weapon_damage(40,source_id,armor_probe),true,{"source":target_id,"source_team":1})
	sim._apply_damage()
	check(near(ordinary_before-float(normal.hp),40),"boundary penetration damages ordinary armor fully")
	check(near(veteran_before-float(source.hp),20),"veteran armor applies half damage in the partial penetration band")
	check(near(float(config.weapons.kestrel_rifle.damage),float(base.damage)),"unit bonuses do not mutate shared weapon rules")

func _automatic_range_and_rate() -> void:
	var sim = fixture()
	var source_id: int = sim.debug_spawn(0,"kestrel_rifle",Vector2(10.5,30.5))
	var source: Dictionary = sim.entities[source_id]
	var original_position: Vector2 = source.pos
	var target_id: int = sim.debug_spawn(1,"rivet_rifle",source.pos+Vector2(float(config.weapons.kestrel_rifle.range)*1.04,0))
	sim.issue([source_id],"hold",source.pos)
	sim.issue([target_id],"hold",sim.entities[target_id].pos)
	var ordinary_shots: int = 0
	for i in range(12):
		sim.events.clear()
		sim.step(1.0/30.0)
		for event: Dictionary in sim.events:
			if event.kind=="fire" and int(event.id)==source_id: ordinary_shots+=1
	check(ordinary_shots==0,"ordinary idle acquisition cannot engage outside base range")
	promote(sim,source_id)
	var shot_times: Array[float] = []
	for i in range(39):
		sim.events.clear()
		sim.step(1.0/30.0)
		for event: Dictionary in sim.events:
			if event.kind=="fire" and int(event.id)==source_id: shot_times.append(float(sim.time))
	check(shot_times.size()==3,"veteran idle acquisition and repeated combat use expanded range")
	if shot_times.size()>=2:
		var interval: float = float(config.weapons.kestrel_rifle.interval)/1.1
		check(shot_times[1]-shot_times[0]>=interval-.0001 and shot_times[1]-shot_times[0]<interval+1.0/30.0+.0001,"real repeated fire follows upgraded attack speed within one tick")
	check((source.pos as Vector2).distance_to(original_position)<.01,"range test does not pass by moving closer")

func _regeneration_and_repairs() -> void:
	var sim = fixture()
	var veteran_id: int = sim.debug_spawn(0,"kestrel_rifle",Vector2(12.5,28.5))
	var ordinary_id: int = sim.debug_spawn(0,"kestrel_rifle",Vector2(15.5,28.5))
	var veteran: Dictionary = sim.entities[veteran_id]
	var ordinary: Dictionary = sim.entities[ordinary_id]
	promote(sim,veteran_id)
	veteran.hp = 40.0
	ordinary.hp = 40.0
	# The real step runs immediately after combat: veteran recovery has no delay.
	veteran.last_damage_time = sim.time
	for i in range(30): sim.step(1.0/30.0)
	check(near(float(veteran.hp),40+sim.max_hp(veteran)*.005),"real simulation regenerates 0.5 percent maximum hp each second")
	check(near(float(ordinary.hp),40),"ordinary unit gains no veteran regeneration")
	veteran.hp = sim.max_hp(veteran)-.01
	sim.step(1.0/30.0)
	check(near(float(veteran.hp),sim.max_hp(veteran)),"regeneration caps at enlarged maximum")
	for unit: Dictionary in [ordinary,veteran]:
		unit.hp = sim.max_hp(unit)-20.0
		var before_money: float = sim.money[0]
		sim._repair_health(unit,1000.0)
		check(near(float(unit.hp),sim.max_hp(unit)),"repair caps correctly for veteran="+str(unit.veteran))
		check(near(before_money-float(sim.money[0]),20*float(config.economy.get("repair_cost",.2))),"repair charges only actual health restored")
	check(float(veteran.hp)>float(config.units.kestrel_rifle.hp),"repair restores veteran health above original maximum")
	var tank_id: int = sim.debug_spawn(0,"kestrel_tank",Vector2(16.5,32.5))
	var tank: Dictionary = sim.entities[tank_id]
	promote(sim,tank_id)
	tank.hp = float(config.units.kestrel_tank.hp)+1.0
	var rescuer: int = sim.debug_spawn(0,"iron_recycler",Vector2(17.5,32.5))
	check(sim.FactionSupport.rescue_error(sim,rescuer,tank_id).is_empty(),"wounded veteran vehicle above ordinary health cap remains rescuable")
	sim._repair_health(tank,10000)
	check(near(float(tank.hp),sim.max_hp(tank)),"vehicle repair reaches veteran maximum health")

func _save_and_load() -> void:
	var sim = fixture()
	var veteran_id: int = sim.debug_spawn(0,"kestrel_rifle",Vector2(12.5,28.5))
	var ordinary_id: int = sim.debug_spawn(0,"kestrel_rifle",Vector2(15.5,28.5))
	promote(sim,veteran_id)
	credited_kill(sim,ordinary_id)
	var path: String = "user://veterancy_v3_test.save"
	check(sim.save_game(path).is_empty(),"save mixed veteran and unpromoted units")
	var restored = Sim.new()
	var error: String = restored.load_game(path)
	check(error.is_empty(),"load mixed veterancy snapshot: "+error)
	if error.is_empty():
		var veteran: Dictionary = restored.entities[veteran_id]
		var ordinary: Dictionary = restored.entities[ordinary_id]
		check(bool(veteran.veteran) and not bool(ordinary.veteran),"save preserves promotion flags independently")
		check(near(float(veteran.experience_value),float(sim.entities[veteran_id].experience_value)),"save preserves veteran accumulated kill value")
		check(near(float(ordinary.experience_value),float(config.units.kestrel_rifle.cost)),"save preserves pre-promotion experience")
		check(near(float(veteran.hp),restored.max_hp(veteran)),"save preserves enlarged health without clamping")
		check(near(float(restored.weapon_for(veteran).damage),float(config.weapons.kestrel_rifle.damage)*1.1),"loaded veteran retains effective weapon bonus")
		veteran.hp = restored.max_hp(veteran)-10
		restored._repair_health(veteran,100)
		check(near(float(veteran.hp),restored.max_hp(veteran)),"loaded veteran can repair to enlarged maximum")
	var input := FileAccess.open(path,FileAccess.READ)
	var snapshot: Dictionary = input.get_var(false)
	input.close()
	var corruptions: Array = [
		["experience_value",-1.0,"negative experience"],
		["experience_value",INF,"nonfinite experience"],
		["veteran","yes","nonboolean veteran flag"],
		["hp",sim.max_hp(sim.entities[veteran_id])+1.0,"health above veteran cap"],
	]
	for corruption: Array in corruptions:
		var invalid: Dictionary = snapshot.duplicate(true)
		invalid.entities[veteran_id][corruption[0]] = corruption[1]
		var output := FileAccess.open(path,FileAccess.WRITE)
		output.store_var(invalid,false)
		output.close()
		var destination = fixture()
		var prior_entities: int = destination.entities.size()
		check(not destination.load_game(path).is_empty(),"reject "+str(corruption[2])+" in saved state")
		check(destination.entities.size()==prior_entities,"invalid load leaves live match unchanged: "+str(corruption[2]))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _garrison_kills() -> void:
	var sim = fixture()
	var ruin: Dictionary = {"id":sim.ruins.size(),"kind":"house","pos":Vector2(24,24),"half":Vector2(1.5,1.35),"yaw":0.0,"hp":900.0,"max_hp":900.0,"variant":0}
	sim.ruins.append(ruin)
	sim._rebuild_nav()
	var shooter_id: int = sim.debug_spawn(0,"kestrel_rifle",Vector2(28,24))
	var spectator_id: int = sim.debug_spawn(0,"kestrel_rifle",Vector2(20,24))
	for id: int in [shooter_id,spectator_id]:
		var e: Dictionary = sim.entities[id]
		e.pos = Garrison._door(sim,ruin,e)
		e.commands = [{"kind":"garrison","target":Garrison.BASE-int(ruin.id),"pos":ruin.pos}]
		Garrison.step_board(sim,e,e.commands[0],.1)
	sim.entities[spectator_id].cooldown = 100.0
	for i in range(4):
		var victim: int = sim.debug_spawn(1,"kestrel_rifle",Vector2(24,20))
		sim.entities[victim].hp = 1.0
		sim.entities[shooter_id].cooldown = 0.0
		sim._rebuild_spatial()
		clear_damage(sim)
		Garrison.step(sim,.1)
		check(int(sim._damage_causes.get(victim,{}).get("source",-1))==shooter_id,"window shot attributes kill to actual occupant")
		sim._apply_damage()
		check(not sim.entities.has(victim),"window shot actually kills enemy")
		if i==2: check(not bool(sim.entities[shooter_id].veteran),"garrison shooter also requires strictly greater threshold")
	check(bool(sim.entities[shooter_id].veteran),"garrison shooter promotes from actual window kills")
	check(near(float(sim.entities[spectator_id].experience_value),0),"other occupants do not receive shooter's experience")
	check(int(ruin.garrison_team)==0 and ruin.garrison.size()==2,"promotion does not detach occupants from building")
