extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func matching(sim, kind: String) -> Array:
	return sim.events.filter(func(event): return event.kind == kind)

func run() -> void:
	var sim = Sim.new()
	sim.setup(RulesLoader.load_rules(), "dev", 7, "rivet", false)
	var victim: int = sim.debug_spawn(0, "rivet_tank", Vector2(20, 20))
	var shooter: int = sim.debug_spawn(1, "kestrel_tank", Vector2(16, 20))
	sim.events.clear()
	sim._add_damage(victim, 10)
	sim._apply_damage()
	sim._damage.clear()
	var hits: Array = matching(sim, "under_attack")
	check(hits.size() == 1 and hits[0].spec == "rivet_tank" and hits[0].team == 0 and hits[0].pos == sim.entities[victim].pos, "surviving victim emits exact friendly radio metadata")
	sim.events.clear()
	for index in range(90):
		sim._add_damage(victim, .01)
		sim._apply_damage()
		sim._damage.clear()
	check(matching(sim, "under_attack").is_empty(), "sustained incoming shots cannot spam victim speech events")
	sim.time += 4.6
	sim._add_damage(victim, 10)
	sim._apply_damage()
	sim._damage.clear()
	check(matching(sim, "under_attack").size() == 1, "new attack report becomes available after its interval")
	sim.events.clear()
	sim.entities[shooter].alpha = 0.0
	sim.entities[shooter].turret_alpha = 0.0
	sim._launch_shot(sim.entities[shooter], sim.entities[victim].pos, victim, false)
	check(sim.projectiles.size() == 1, "real cannon launch creates a shell")
	sim._step_projectiles(5.0)
	var impacts: Array = matching(sim, "impact")
	check(impacts.size() == 1 and impacts[0].projectile and impacts[0].weapon == sim.data_for("kestrel_tank").weapon, "real shell landing identifies projectile and weapon for crater and SFX routing")
	sim._damage.clear()
	sim.events.clear()
	var rifle: int = sim.debug_spawn(1, "kestrel_rifle", Vector2(18, 20))
	sim._launch_shot(sim.entities[rifle], sim.entities[victim].pos, victim, false)
	impacts = matching(sim, "impact")
	check(impacts.size() == 1 and not impacts[0].projectile and impacts[0].weapon == "kestrel_rifle", "instant bullet landing stays distinct from shell craters")
	sim._damage.clear()
	sim.events.clear()
	sim._add_damage(victim, 100000)
	sim._apply_damage()
	sim._damage.clear()
	var deaths: Array = matching(sim, "death")
	check(not sim.entities.has(victim) and deaths.size() == 1 and deaths[0].destroyed and deaths[0].entity_kind == "unit" and deaths[0].radius > 0.0, "tank death carries dimensions after its entity is removed")
	check(matching(sim, "under_attack").is_empty() and not sim._damage_voice_next.has(victim), "lethal damage emits death only and removes victim throttle state")
	sim.events.clear()
	var building: int = sim.debug_spawn(0, "rivet_factory", Vector2(26, 20))
	sim._kill_entity(building, false)
	deaths = matching(sim, "death")
	check(deaths.size() == 1 and not deaths[0].destroyed and deaths[0].entity_kind == "building", "sold or removed building explicitly suppresses destruction feedback")
	sim.events.clear()
	building = sim._spawn(0, "kestrel_factory", Vector2(26, 26), false)
	sim._step_building(sim.entities[building], 2.0, 1.0)
	var deployed: Array = matching(sim, "deploy")
	check(deployed.size() == 1 and deployed[0].spec == "kestrel_factory" and deployed[0].team == 0, "normal building unfold completion dispatches spatial audio metadata")
	sim._step_building(sim.entities[building], .1, 1.0)
	check(matching(sim, "deploy").size() == 1, "completed building does not repeat deploy sound every tick")
	sim = null
	await process_frame
	print("COMBAT_FEEDBACK_EVENTS ", JSON.stringify({"checks": checks, "failures": failures}))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
