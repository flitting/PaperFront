extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _initialize() -> void:
	var rules: Dictionary = Rules.load_rules()
	# Conventional headquarters retain the shared normal/defense build queues.
	var sim = Sim.new()
	sim.setup(rules, "dev", 7, "kestrel", false)
	var funds: float = sim.money[0]
	check(sim.build(0, "kestrel_power").is_empty(), "normal construction accepts an initial order")
	check(sim.build(0, "kestrel_wall").is_empty(), "defense construction starts while normal construction is active")
	check(sim.building_orders[0].spec == "kestrel_power" and sim.defense_orders[0].spec == "kestrel_wall", "legacy order remains normal and defense has its own slot")
	check(sim.money[0] == funds - float(rules.buildings.kestrel_power.cost) - float(rules.buildings.kestrel_wall.cost), "both queues use shared funds")
	var protected_funds: float = sim.money[0]
	var normal_order: Dictionary = sim.building_orders[0].duplicate(true)
	var defense_order: Dictionary = sim.defense_orders[0].duplicate(true)
	check(not sim.cancel_build(0, "bogus").is_empty() and not sim.place_building(0, Vector2(15.5, 30.5), "bogus").is_empty(), "unknown channel rejects mutations")
	check(sim.money[0] == protected_funds and sim.building_orders[0] == normal_order and sim.defense_orders[0] == defense_order, "unknown channel preserves funds and both orders")
	var normal_before: float = float(sim.building_orders[0].remaining)
	var defense_before: float = float(sim.defense_orders[0].remaining)
	sim.step(1.0)
	check(float(sim.building_orders[0].remaining) < normal_before and float(sim.defense_orders[0].remaining) < defense_before, "both queues progress in the same tick")
	var refund: float = float(sim.defense_orders[0].cost) * float(sim.defense_orders[0].remaining) / float(sim.defense_orders[0].total)
	var before_cancel: float = sim.money[0]
	check(sim.cancel_build(0, "defense").is_empty() and sim.money[0] == before_cancel + refund, "defense cancellation refunds only its unfinished work")
	check(not sim.building_orders[0].is_empty() and sim.defense_orders[0].is_empty(), "canceling defense preserves the normal order")
	check(sim.build(0, "kestrel_wall").is_empty(), "defense channel accepts a replacement order")
	sim.step(40.0)
	check(bool(sim.building_orders[0].ready) and bool(sim.defense_orders[0].ready), "both queues can retain ready buildings together")
	var path: String = "/tmp/paper_war_construction_channels.save"
	check(sim.save_game(path).is_empty(), "dual-channel save writes")
	var restored = Sim.new()
	check(restored.load_game(path).is_empty() and restored.building_orders == sim.building_orders and restored.defense_orders == sim.defense_orders, "both ready orders survive load")
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var old: Dictionary = file.get_var(false)
	file.close()
	var normal_legacy: Dictionary = old.duplicate(true)
	normal_legacy.erase("defense_orders")
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_var(normal_legacy, false)
	file.close()
	check(restored.load_game(path).is_empty() and restored.defense_orders.size() == 2 and restored.defense_orders[0].is_empty() and restored.building_orders[0] == sim.building_orders[0], "old normal-order snapshots load with empty defense slots")
	for ready_state in [true, false]:
		var legacy: Dictionary = old.duplicate(true)
		legacy.building_orders[0] = legacy.defense_orders[0]
		legacy.erase("defense_orders")
		if not ready_state:
			legacy.building_orders[0].ready = false
			legacy.building_orders[0].remaining = float(legacy.building_orders[0].total) * 0.5
			legacy.building_orders[0].progress = 0.5
		file = FileAccess.open(path, FileAccess.WRITE)
		file.store_var(legacy, false)
		file.close()
		check(restored.load_game(path).is_empty() and restored.building_orders[0].is_empty() and restored.defense_orders[0] == legacy.building_orders[0], "old wall order migrates to defense channel: ready=" + str(ready_state))
	DirAccess.remove_absolute(path)
	print("Construction channel checks: %d failed" % failures.size())
	for failure in failures: push_error(failure)
	quit(1 if not failures.is_empty() else 0)
