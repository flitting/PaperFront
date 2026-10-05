extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
var failures: Array[String] = []
var checks: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func fixture(faction: String):
	var sim = Sim.new()
	var config: Dictionary = RulesLoader.load_rules()
	config.factions.iron.traits = {"damage_reduction":0.10,"regen_delay":6.0,"regen_fraction_per_second":0.012}
	config.factions.kestrel.traits = {"cohesion_radius":5.0,"cohesion_min_allies":2,"cohesion_damage_bonus":0.08}
	config.factions.rivet.traits = {"breakthrough_distance":5.0,"breakthrough_window":4.0,"breakthrough_damage_bonus":0.20}
	config.weapons.sky_disruptor.emp_vehicle_duration = 2.0
	config.weapons.sky_disruptor.emp_building_duration = 1.0
	sim.setup(config,"dev",7,faction,false)
	sim.money.assign([100000.0,100000.0])
	return sim

func _initialize() -> void:
	defense_and_regeneration()
	cohesion_and_breakthrough()
	emp_and_save()
	native_emp_equivalence()
	print("FACTION_TRAITS ",JSON.stringify({"checks":checks,"failures":failures}))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func defense_and_regeneration() -> void:
	var sim = fixture("iron")
	var infantry: int = sim._spawn(0,"iron_rifle",Vector2(14,39),true)
	var fighter: int = sim._spawn(0,"iron_fighter",Vector2(14,31),true)
	var building: int = sim._spawn(0,"iron_power",Vector2(12.5,25.5),true)
	sim._add_damage(infantry,10.0)
	sim._add_damage(building,10.0)
	sim._apply_damage()
	var funds_before_healing: float = sim.money[0]
	check(is_equal_approx(float(sim.entities[infantry].hp),float(sim.data_for("iron_rifle").hp)-9.0),"iron infantry receives 10% less damage")
	check(is_equal_approx(float(sim.entities[building].hp),float(sim.data_for("iron_power").hp)-10.0),"iron building does not receive damage reduction")
	sim.time=5.9
	var before: float = sim.entities[infantry].hp
	sim.FactionTraits.step_regeneration(sim,1.0)
	check(is_equal_approx(float(sim.entities[infantry].hp),before),"regeneration waits six seconds")
	sim.time=6.0
	sim.entities[fighter].hp=float(sim.data_for("iron_fighter").hp)-10.0
	sim.FactionTraits.step_regeneration(sim,1.0)
	check(is_equal_approx(float(sim.entities[infantry].hp),before),"healing does not advance for the tick ending at six seconds")
	sim.time=7.0
	sim.FactionTraits.step_regeneration(sim,1.0)
	check(is_equal_approx(float(sim.entities[infantry].hp),before+float(sim.data_for("iron_rifle").hp)*0.012),"infantry heals at 1.2% max HP per second")
	check(is_equal_approx(float(sim.entities[fighter].hp),float(sim.data_for("iron_fighter").hp)-10.0+float(sim.data_for("iron_fighter").hp)*0.012),"aircraft receives passive regeneration")
	var loaded: Dictionary = sim.entities[infantry]
	loaded.transport_id=100
	sim.time=8.0
	before=loaded.hp
	sim.FactionTraits.step_regeneration(sim,1.0)
	check(is_equal_approx(float(loaded.hp),before) and is_equal_approx(float(loaded.last_damage_time),8.0),"loaded infantry pauses healing and resets delay")
	loaded.transport_id=-1
	sim.time=8.1
	sim.FactionTraits.step_regeneration(sim,1.0)
	check(is_equal_approx(float(loaded.hp),before),"unloaded infantry does not heal immediately")
	check(is_equal_approx(float(sim.money[0]),funds_before_healing),"passive healing charges no money")
	var combat=fixture("iron")
	var shooter: int=combat._spawn(0,"iron_rifle",Vector2(14,39),true)
	var dummy: int=combat._spawn(1,"rivet_power",Vector2(17.5,39.5),true)
	var rifle: Dictionary=combat.entities[shooter]
	rifle.hp=float(combat.data_for("iron_rifle").hp)-20.0
	for attack_time in [6.0,12.0]:
		combat.time=attack_time
		rifle.cooldown=0.0
		combat._launch_shot(rifle,combat.entities[dummy].pos,dummy,false)
		combat.FactionTraits.step_regeneration(combat,1.0)
		check(is_equal_approx(float(rifle.hp),float(combat.data_for("iron_rifle").hp)-20.0),"active firing prevents regeneration at "+str(attack_time))
	check(is_equal_approx(float(rifle.last_attack_time),12.0),"successful shots record the last attack time")
	combat.time=17.9
	combat.FactionTraits.step_regeneration(combat,1.0)
	check(is_equal_approx(float(rifle.hp),float(combat.data_for("iron_rifle").hp)-20.0),"regeneration remains paused until six seconds after firing")
	combat.time=18.0
	combat.FactionTraits.step_regeneration(combat,1.0)
	check(is_equal_approx(float(rifle.hp),float(combat.data_for("iron_rifle").hp)-20.0),"healing starts only after the six-second boundary")
	combat.time=19.0
	combat.FactionTraits.step_regeneration(combat,1.0)
	check(float(rifle.hp)>float(combat.data_for("iron_rifle").hp)-20.0,"regeneration resumes six seconds after firing stops")

func cohesion_and_breakthrough() -> void:
	var kestrel = fixture("kestrel")
	var gun: int=kestrel._spawn(0,"kestrel_rifle",Vector2(14,39),true)
	var ally_a: int=kestrel._spawn(0,"kestrel_tank",Vector2(16,39),true)
	check(is_equal_approx(kestrel.FactionTraits.cohesion_bonus(kestrel,kestrel.entities[gun]),0.0),"one ally does not activate cohesion")
	var ally_b: int=kestrel._spawn(0,"kestrel_rifle",Vector2(14,41),true)
	check(is_equal_approx(kestrel.FactionTraits.cohesion_bonus(kestrel,kestrel.entities[gun]),0.08),"two same-domain allies activate cohesion")
	kestrel.entities[ally_b].pos=Vector2(30,30)
	check(is_equal_approx(kestrel.FactionTraits.cohesion_bonus(kestrel,kestrel.entities[gun]),0.0),"cohesion respects radius")
	var rivet=fixture("rivet")
	var tank: int=rivet._spawn(0,"rivet_tank",Vector2(14,39),true)
	var e: Dictionary=rivet.entities[tank]
	e.commands=[{"kind":"attack_move","pos":Vector2(30,39),"target":-1}]
	e.pos+=Vector2(5,0)
	rivet.time=1.0
	rivet.FactionTraits.step_breakthrough(rivet)
	check(is_equal_approx(float(e.breakthrough_ready_until),5.0),"five metres of actual attack movement arms breakthrough")
	check(is_equal_approx(rivet.FactionTraits.breakthrough_scale(rivet,e),1.2),"first shot gains 20% breakthrough damage")
	check(is_equal_approx(rivet.FactionTraits.breakthrough_scale(rivet,e),1.0),"breakthrough is consumed once")
	for spec in ["rivet_harvester","rivet_fighter"]:
		var id: int=rivet._spawn(0,spec,Vector2(14,31) if spec=="rivet_fighter" else Vector2(14,35),true)
		var candidate: Dictionary=rivet.entities[id]
		candidate.commands=[{"kind":"attack_move","pos":Vector2(30,35),"target":-1}]
		candidate.pos+=Vector2(5,0)
		rivet.time=2.0
		rivet.FactionTraits.step_breakthrough(rivet)
		check(is_zero_approx(float(candidate.get("breakthrough_ready_until",0.0))),"unarmed or airborne armored unit cannot arm breakthrough: "+spec)

func emp_and_save() -> void:
	var sim=fixture("sky")
	var source: int=sim._spawn(0,"sky_disruptor",Vector2(12,39),true)
	var vehicle: int=sim._spawn(1,"rivet_tank",Vector2(17,39),true)
	var infantry: int=sim._spawn(1,"rivet_rifle",Vector2(18,39),true)
	var building: int=sim._spawn(1,"rivet_power",Vector2(19.5,25.5),true)
	var weapon: Dictionary=sim.rules.weapons.sky_disruptor
	var initial_power: float=sim.power(1).x
	sim._launch_shot(sim.entities[source],sim.entities[vehicle].pos,vehicle,false)
	check(sim.projectiles.size()==1 and is_equal_approx(float(sim.projectiles[0].emp_vehicle_duration),2.0),"disruptor shell snapshots EMP duration")
	sim._step_projectiles(1.0)
	sim._apply_damage()
	sim.FactionTraits.apply_emp(sim,infantry,weapon,0)
	sim.FactionTraits.apply_emp(sim,building,weapon,0)
	check(is_equal_approx(float(sim.entities[vehicle].emp_until),2.0),"EMP disables enemy vehicle for two seconds")
	check(not sim.entities[infantry].has("emp_until"),"EMP does not disable infantry")
	check(is_equal_approx(float(sim.entities[building].emp_until),1.0),"EMP disables enemy building for one second")
	check(is_equal_approx(sim.power(1).x,initial_power-float(sim.data_for("rivet_power").power)),"EMP cuts power output from disabled plant")
	var path: String="user://faction_trait_state.save"
	check(sim.save_game(path).is_empty(),"faction states save")
	var restored=Sim.new()
	check(restored.load_game(path).is_empty(),"faction states load")
	if restored.entities.has(vehicle): check(is_equal_approx(float(restored.entities[vehicle].emp_until),2.0),"EMP duration survives save")

func native_emp_equivalence() -> void:
	if not ClassDB.class_exists("PaperFrontKernels"):
		failures.append("native unit kernel unavailable")
		return
	var fast=fixture("sky")
	var reference=fixture("sky")
	var fast_id: int=fast._spawn(0,"sky_tank",Vector2(14,39),true)
	var reference_id: int=reference._spawn(0,"sky_tank",Vector2(14,39),true)
	fast.issue([fast_id],"move",Vector2(20,39))
	reference.issue([reference_id],"move",Vector2(20,39))
	fast.entities[fast_id].emp_until=1.0
	reference.entities[reference_id].emp_until=1.0
	fast.native_kernels_enabled=true
	fast.native_unit_dispatch_enabled=true
	fast.native_geometry_enabled=false
	reference.native_kernels_enabled=true
	reference.native_unit_dispatch_enabled=false
	reference.native_geometry_enabled=false
	var start: Vector2=fast.entities[fast_id].pos
	for tick in range(45):
		fast.step(1.0/30.0)
		reference.step(1.0/30.0)
		if tick==15:
			check(fast.entities[fast_id].pos.is_equal_approx(start) and fast.entities[fast_id].state=="emp","native EMP freezes vehicle during active window")
		check(fast.entities[fast_id].pos.is_equal_approx(reference.entities[reference_id].pos) and fast.entities[fast_id].state==reference.entities[reference_id].state,"native and script EMP state match at tick "+str(tick))
	check(fast.entities[fast_id].pos.distance_to(start)>0.1,"vehicle resumes movement after EMP expires")
