extends SceneTree

# Optional long integration probe. AI begins with shipping HQ + 4000 funds.
# ONLY the passive player's HQ HP is raised to prevent an early match end.
# There are no free AI spawns, resource grants, shortened production times, or
# forced AI building/production orders. Each success requires a produce event
# whose ID references an actual domain=air unit created by the simulation.
const Sim = preload("res://scripts/simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
const OUTPUT = "res://artifacts/faction_validation/ai_aviation_growth.json"

func _initialize() -> void:
	var config: Dictionary = Rules.load_rules("res://data/rules.json", false)
	if config.is_empty():
		push_error(str(Rules.errors)); quit(1); return
	var results: Array = []
	for ai_faction: String in ["kestrel", "rivet"]:
		results.append(_probe(config, ai_faction))
	var report: Dictionary = {"probe": "natural_paid_ai_aviation_growth", "map_mode": "dev", "seed": 24, "delta": 0.5, "limit_seconds": 1800.0, "initial_money": config.economy.initial_money, "intervention": "Only passive player HQ HP = 1000000, to prevent early defeat; AI receives no extra funds or units.", "spawn_proof": "produce event with an ID present in entities and domain=air", "matches": results}
	var file: FileAccess = FileAccess.open(OUTPUT, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write aviation probe report"); quit(1); return
	file.store_string(JSON.stringify(report, "\t")); file.close()
	var passed: bool = results.all(func(item): return bool(item.actual_aircraft_spawned))
	print("Natural paid AI aviation growth: ", results)
	quit(0 if passed else 1)

func _probe(config: Dictionary, ai_faction: String) -> Dictionary:
	var player_faction: String = "rivet" if ai_faction == "kestrel" else "kestrel"
	var fixture: Dictionary = config.duplicate(true)
	fixture.buildings[player_faction + "_hq"].hp = 1000000.0
	var sim = Sim.new()
	sim.setup(fixture, "dev", 24, player_faction, true)
	var airport_completed: float = -1.0
	while sim.time < 1800.0 and sim.result == "":
		sim.step(0.5)
		if airport_completed < 0.0 and sim._has_role(1, "airfield"): airport_completed = sim.time
		for event in sim.events:
			if event.kind == "produce" and sim.entities.has(event.id) and sim._is_air(sim.entities[event.id]):
				var plane: Dictionary = sim.entities[event.id]
				if int(plane.team) == 1:
					return {"ai_faction": ai_faction, "actual_aircraft_spawned": true, "airfield_completed_seconds": airport_completed, "first_aircraft_seconds": sim.time, "aircraft_id": plane.id, "aircraft_spec": plane.spec, "remaining_funds": sim.money[1]}
		sim.events.clear()
	return {"ai_faction": ai_faction, "actual_aircraft_spawned": false, "airfield_completed_seconds": airport_completed, "elapsed_seconds": sim.time, "remaining_funds": sim.money[1], "result": sim.result}
