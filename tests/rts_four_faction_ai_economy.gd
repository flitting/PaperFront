extends SceneTree

## Normal forest economy from four starting HQs and 4000 funds. Team 0 is
## passed through the same normal planner explicitly because live UI reserves
## slot 0 for the human. No bonus resources, seeded miners, instant queues,
## extra buildings, terrain changes or income injections are used.
const Sim = preload("res://tests/rule_test_simulation.gd")
const AI = preload("res://scripts/ai_controller.gd")
var checkpoints: Array = []
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var sim = Sim.new()
	var factions: Array[String] = ["kestrel","rivet","iron","sky"]
	sim.setup_multiteam(RulesLoader.load_rules(),"forest",117,factions,true)
	var human_clock: float = 0
	var next_checkpoint: float = 60
	for frame in range(6000):
		if not sim.result.is_empty(): break
		human_clock+=.1
		if human_clock>=2:
			human_clock=0
			sim.ai_state[0].attack_clock+=2
			sim.ai_state[0].scout_clock+=2
			sim.ai_state[0].naval_clock+=2
			AI._plan(sim,0,AI.SETTINGS.normal,sim.ai_state[0])
		sim.step(.1)
		sim.events.clear();sim.notices.clear()
		if sim.time>=next_checkpoint:
			var snapshot: Dictionary = sim.statistics.snapshot(sim)
			checkpoints.append(snapshot)
			print("RTS_AI_CHECKPOINT ",JSON.stringify(snapshot))
			next_checkpoint+=60
			await process_frame
	var failures: Array[String] = []
	var rows: Array = sim.statistics.snapshot(sim).teams
	for row: Dictionary in rows:
		if float(row.funds_earned)<=0:failures.append(str(row.faction)+" never earned mining income")
		if float(row.units_produced)<=0:failures.append(str(row.faction)+" never produced a paid unit")
	var result: Dictionary = {"scenario":"normal forest four starting HQs, initial 4000 funds, all four normal AI planners; no seeded infrastructure","seed":117,"seconds":sim.time,"ended_early":sim.time<599.9,"result":sim.result,"statistics":sim.statistics.snapshot(sim),"checkpoints":checkpoints,"failures":failures}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/rts_revision"))
	var file := FileAccess.open("res://artifacts/rts_revision/four_faction_ai_economy.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	print("RTS_AI_ECONOMY ",JSON.stringify(result))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
