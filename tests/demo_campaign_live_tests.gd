extends SceneTree

## Paid seven-stage campaign run with the actual asynchronous simulation.
## Retains campaign_real_commands_tests.gd's seed, sites and per-action limits.
## --no-ai is an explicit diagnostic control; the normal run keeps campaign AI.
## No funds, deployment, order readiness, stage or HQ health are injected.
const Rules = preload("res://scripts/rules_loader.gd")
const MAP = preload("res://scripts/campaign_map.gd")
const Transport = preload("res://scripts/unit_transport.gd")
const STEP := 1.0 / 30.0
const SEED := 1
const WORKER_YIELD_US := 1000

class ReceiptSim:
	extends "res://scripts/simulation.gd"
	# Transparent public-command receipts; all mechanics use the actual parent.
	var purchase_receipts: Array[Dictionary] = []
	func build(team: int, spec: String, builder: int = -1) -> String:
		var before: float = float(money[team])
		var error: String = super.build(team, spec, builder)
		if error.is_empty():
			var channel: String = construction_channel(spec)
			var order: Dictionary = order_for_team(team, channel)
			purchase_receipts.append({"kind": "building", "time": time, "team": team, "spec": spec, "builder": builder,
				"money_before": before, "money_after": money[team], "debit": before-float(money[team]),
				"rules_cost": data_for(spec).cost, "queue_cost": order.cost, "remaining": order.remaining,
				"total": order.total, "ready": order.ready, "progress": order.progress,
				"field_paid_during_work": builder >= 0})
		return error
	func produce(building_id: int, spec: String) -> String:
		var team: int = int(entities[building_id].team) if entities.has(building_id) else -1
		var before: float = float(money[team]) if team >= 0 else 0.0
		var old_queue: int = entities[building_id].queue.size() if entities.has(building_id) else 0
		var error: String = super.produce(building_id, spec)
		if error.is_empty():
			var order: Dictionary = entities[building_id].queue.back()
			purchase_receipts.append({"kind": "unit", "time": time, "team": team, "spec": spec, "producer": building_id,
				"money_before": before, "money_after": money[team], "debit": before-float(money[team]),
				"rules_cost": data_for(spec).cost, "queue_cost": order.cost, "remaining": order.remaining,
				"total": order.total, "ready": order.ready, "started": order.started, "progress": order.progress,
				"queue_before": old_queue, "queue_after": entities[building_id].queue.size()})
		return error

var sim
var rules: Dictionary
var checks := 0
var failures: Array[String] = []
var phases: Array[Dictionary] = []
var stage_history: Array[Dictionary] = []
var progress: Array[Dictionary] = []
var placed_sites: Dictionary = {}
var deliveries: Array[Dictionary] = []
var production: Array[Dictionary] = []
var transport_events: Array[Dictionary] = []
var deaths: Array[Dictionary] = []
var armor_deaths: Array[Dictionary] = []
var navigation_violations: Array[Dictionary] = []
var minimum_sampled_margin := INF
var maximum_sampled_overlap := 0.0
var previous_positions: Dictionary = {}
var previous_loaded: Dictionary = {}
var initial_money: Array[float] = []
var delivery_income: Array[float] = [0.0, 0.0]
var step_payments: Array[float] = [0.0, 0.0]
var minimum_money: Array[float] = [INF, INF]
var max_ai_armed := 0
var max_ai_armed_including_queue := 0
var max_ai_production_queue := 0
var max_ai_waves := 0
var maximum_queue := 0
var maximum_in_flight := 0
var budgets_legal := true
var tick_count := 0
var collision_unit_samples := 0
var collision_pair_samples := 0
var current_phase := "setup"
var latest_stage := -1
var wall_started_usec := 0
var setup_ms := 0.0
var source_before: Dictionary = {}
var output := "res://artifacts/demo_20261004/campaign_live/live_ai_latest.json"
var no_ai := false

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func point(value: Vector2):
	return [value.x, value.y] if value.is_finite() else null

func source_hashes() -> Dictionary:
	var hashes: Dictionary = {}
	for path in ["res://tests/demo_campaign_live_tests.gd", "res://tests/campaign_real_commands_tests.gd",
		"res://scripts/simulation.gd", "res://scripts/path_worker.gd", "res://scripts/path_graph.gd",
		"res://scripts/campaign_controller.gd", "res://scripts/campaign_map.gd", "res://scripts/ai_controller.gd",
		"res://scripts/unit_transport.gd", "res://scripts/outpost_construction.gd", "res://data/rules.json",
		"res://assets/native/libpaper_front_kernels.so"]:
		if FileAccess.file_exists(path): hashes[path] = FileAccess.get_sha256(path)
	return hashes

func run() -> void:
	var args := OS.get_cmdline_user_args()
	for index in range(args.size()-1):
		if args[index] == "--output": output = args[index+1]
	no_ai = "--no-ai" in args
	if DisplayServer.get_name() != "headless":
		push_error("Live campaign validation requires headless execution")
		quit(2)
		return
	rules = Rules.load_rules()
	if rules.is_empty():
		push_error("Live campaign rules invalid: " + str(Rules.errors))
		quit(2)
		return
	source_before = source_hashes()
	wall_started_usec = Time.get_ticks_usec()
	sim = ReceiptSim.new()
	sim.setup(rules, "campaign", SEED, "kestrel", true)
	if no_ai: sim.ai_enabled = false
	setup_ms = float(Time.get_ticks_usec()-wall_started_usec)/1000.0
	initial_money.assign(sim.money)
	minimum_money.assign(sim.money)
	check(not sim.synchronous_path_tests and sim._path_worker != null, "campaign uses the actual asynchronous worker")
	check(sim.map.mode == "campaign" and sim.map.size == 320 and sim.map.valid, "original authored 320 campaign map is valid")
	check(sim.campaign_controller.stage == 0 and sim.result.is_empty(), "campaign starts at objective zero with no result")
	check(sim.ai_enabled == not no_ai, "AI is enabled by default; no-ai requires an explicit diagnostic argument")
	check(is_equal_approx(sim.money[0], float(rules.economy.initial_money)) and is_equal_approx(sim.money[1], float(rules.economy.initial_money)), "both teams start with only normal rules funds")
	for entity in sim.entities.values():
		if entity.kind == "unit":
			previous_positions[entity.id] = entity.pos
			previous_loaded[entity.id] = Transport.is_loaded(entity)
	record_stage()
	print("DEMO_CAMPAIGN_LIVE_READY ai=", sim.ai_enabled, " setup_ms=", setup_ms, " money=", sim.money)
	write_report(false)
	await tutorial_sequence()
	check(sim.result == "win" and sim.campaign_controller.finished and sim.campaign_controller.stage == 7,
		"all seven paid objectives complete and the live campaign produces a win")
	check(sim.campaign_controller.hold_elapsed >= 60.0, "final headquarters defense retains the real 60-second requirement")
	var defense_stages: Array = stage_history.filter(func(s): return int(s.stage) == 6)
	check(not defense_stages.is_empty() and sim.time-float(defense_stages[0].time) >= 60.0-.00001, "at least sixty actual simulated seconds pass after entering the final defense stage")
	check(not navigation_violations.any(func(v): return v.get("actionable", true)), "light every-tick samples preserve actual unit/static collision")
	check(budgets_legal and maximum_in_flight <= sim.PATH_IN_FLIGHT, "actual navigation budgets stay bounded throughout the mission")
	check(minimum_money[0] >= -.000001 and minimum_money[1] >= -.000001, "normal spending never overdrafts either team")
	check(sim.navigation_stats.completed > 0, "actual worker finishes real campaign path jobs")
	validate_receipts()
	if sim.ai_enabled:
		var policy: Dictionary = sim.campaign_controller.ai_policy()
		check(max_ai_armed <= int(policy.army_cap) and max_ai_armed_including_queue <= int(policy.army_cap), "AI live and queued armed force obey the original mission cap")
		check(max_ai_waves <= int(policy.wave_limit), "AI launches at most the original two waves")
		check(sim.purchase_receipts.any(func(r): return r.team == 1 and r.kind == "building"), "enabled AI purchases its infrastructure with ordinary funds")
		check(sim.purchase_receipts.any(func(r): return r.team == 1 and r.kind == "unit"), "enabled AI purchases its production queue with ordinary funds")
	check(source_before == source_hashes(), "source/rules/native binary stay unchanged throughout this run")
	write_report(true)
	print("DEMO_CAMPAIGN_LIVE ", checks-failures.size(), "/", checks, " ai=", sim.ai_enabled, " result=", sim.result,
		" stage=", sim.campaign_controller.stage, " sim_seconds=", sim.time, " failures=", JSON.stringify(failures))
	for failure in failures: push_error(failure)
	sim = null
	await process_frame
	quit(0 if failures.is_empty() else 1)

func tutorial_sequence() -> void:
	var power: int = await build_and_place("kestrel_power", Vector2(57,165), -1)
	check(power > 0 and sim.campaign_controller.stage == 1, "paid power construction advances stage one")
	if power < 0 or sim.campaign_controller.stage < 1: return
	var refinery: int = await build_and_place("kestrel_refinery", Vector2(72,157), -1)
	check(refinery > 0, "paid refinery is legally placed near headquarters")
	if refinery < 0: return
	var harvester: int = find_entity("kestrel_harvester")
	check(harvester > 0, "normal campaign starting harvester exists")
	if harvester < 0: return
	sim.issue([harvester], "harvest", Vector2(81.5,142.5))
	await advance_until("first paid ore delivery", func(): return sim.campaign_controller.stage >= 2, 200.0)
	check(sim.campaign_controller.stage >= 2 and not deliveries.filter(func(d): return d.team == 0).is_empty(), "real mining and refinery delivery advance economy stage")
	if sim.campaign_controller.stage < 2: return
	var barracks: int = await build_and_place("kestrel_barracks", Vector2(69,184), -1)
	check(barracks > 0, "paid barracks completes normally")
	if barracks < 0: return
	check(sim.produce(barracks, "kestrel_rifle").is_empty(), "paid rifle enters barracks queue")
	check(sim.produce(barracks, "kestrel_engineer").is_empty(), "paid engineer enters the same normal queue")
	await advance_until("paid rifle and engineer emerge", func(): return sim.campaign_controller.flags.trained_rifle and sim.campaign_controller.flags.trained_engineer, 100.0)
	check(sim.campaign_controller.flags.trained_rifle and sim.campaign_controller.flags.trained_engineer, "both paid units emerge through actual production events")
	var rifle: int = find_entity("kestrel_rifle")
	check(rifle > 0, "trained rifle survives for bridge reconnaissance")
	if rifle < 0: return
	sim.issue([rifle], "move", MAP.WEST_BRIDGE+Vector2(-2,0))
	await advance_until("rifle walks to west bridge", func(): return sim.campaign_controller.stage >= 3, 200.0)
	check(sim.campaign_controller.stage >= 3, "real worker guides rifle to the western bridgehead")
	if sim.campaign_controller.stage < 3: return
	var repairer: int = find_entity("kestrel_engineer")
	check(repairer > 0, "normal engineer survives for bridge repair")
	if repairer < 0: return
	sim.issue([repairer], "bridge", Vector2(160,160))
	await advance_until("engineer walks and pays for bridge repair", func(): return sim.campaign_controller.stage >= 4, 240.0)
	check(sim.campaign_controller.stage >= 4 and bool(sim.bridges[0].alive), "engineer repairs bridge through its ordinary paid order")
	if sim.campaign_controller.stage < 4: return
	var expander: int = find_entity("kestrel_engineer")
	var outpost: int = await build_and_place("kestrel_outpost", MAP.EXPANSION+Vector2(8,0), expander)
	check(outpost > 0 and sim.campaign_controller.stage >= 5, "engineer crosses and constructs the funded eastern outpost")
	if outpost < 0 or sim.campaign_controller.stage < 5: return
	var factory: int = await build_and_place("kestrel_factory", Vector2(69,184), -1)
	check(factory > 0, "paid factory is legally built after expansion")
	if factory < 0: return
	var carrier: int = find_entity("kestrel_scout")
	var passenger: int = find_entity("kestrel_rifle")
	check(carrier > 0 and passenger > 0, "starting scout and trained passenger are alive for transport")
	if carrier < 0 or passenger < 0: return
	sim.issue([passenger], "board", sim.entities[carrier].pos, carrier)
	await advance_until("rifle returns and boards scout", func(): return sim.entities.has(passenger) and int(sim.entities[passenger].get("transport_id",-1)) == carrier, 220.0)
	var boarded: bool = sim.entities.has(passenger) and int(sim.entities[passenger].get("transport_id",-1)) == carrier
	check(boarded, "rifle boards the scout using the normal approach order")
	if not boarded: return
	sim.issue([carrier], "unload_move", MAP.EAST_ASSEMBLY)
	await advance_until("scout crosses and unloads east", func(): return sim.campaign_controller.stage >= 6, 250.0)
	check(sim.campaign_controller.stage >= 6, "scout drives through the actual bridge and unloads at the eastern assembly")
	if sim.campaign_controller.stage < 6: return
	var tower: int = await build_and_place("kestrel_tower", Vector2(72,169), -1)
	check(tower > 0, "paid defense tower protects headquarters during final phase")
	var armor_factory: int = find_entity("kestrel_factory")
	check(armor_factory > 0, "paid armor factory remains alive")
	if armor_factory < 0: return
	for wave in range(2):
		if sim.result == "win": break
		for order in range(4):
			check(sim.produce(armor_factory, "kestrel_tank").is_empty(), "paid armored counterattack order %d/%d" % [wave,order])
		await advance_until("armor wave " + str(wave) + " emerges", func(): return count_entities("kestrel_tank") >= 4, 110.0)
		check(count_entities("kestrel_tank") >= 4, "counterattack force emerges through the real queue")
		await advance_until("headquarters defends for sixty seconds", func(): return sim.campaign_controller.hold_elapsed >= 60.0, 65.0)
		check(sim.campaign_controller.hold_elapsed >= 60.0, "headquarters survives the unmodified timed defense")
		var armor: Array[int] = []
		for entity in sim.entities.values():
			if entity.spec == "kestrel_tank" and int(entity.team) == 0: armor.append(int(entity.id))
		if not armor.is_empty():
			sim.issue(armor, "attack_move", MAP.ENEMY_START)
			await advance_until("armor wave " + str(wave) + " attacks enemy headquarters", func(): return sim.result == "win" or count_entities("kestrel_tank") == 0, 230.0)
	check(sim.result == "win" and sim.campaign_controller.finished, "funded armor actually destroys enemy HQ and wins the mission")

func build_and_place(spec: String, preferred: Vector2, builder: int) -> int:
	var original: Dictionary = sim.entities.duplicate()
	var channel: String = sim.construction_channel(spec)
	var error: String = sim.build(0, spec, builder)
	check(error.is_empty(), "normal purchase accepts " + spec + ": " + error)
	if not error.is_empty(): return -1
	await advance_until("building queue readies " + spec, func(): return bool(sim.order_for_team(0,channel).get("ready",false)), 90.0)
	if not bool(sim.order_for_team(0,channel).get("ready",false)):
		failures.append("Building queue never readied within original 90s: " + spec)
		return -1
	var site: Vector2 = find_site(preferred, channel)
	check(site.is_finite(), "a legal placement site exists for " + spec)
	if not site.is_finite(): return -1
	error = sim.place_building(0, site, channel)
	placed_sites[spec] = point(site)
	check(error.is_empty(), "normal placement accepts " + spec + ": " + error)
	if not error.is_empty(): return -1
	await advance_until("actual construction completes " + spec, func(): return completed_new_building(spec,original) > 0, 120.0)
	return completed_new_building(spec, original)

func find_site(preferred: Vector2, channel: String) -> Vector2:
	# Exactly the old paid fixture's legal-site search, with no new map edits.
	for radius in range(32):
		for z in range(floori(preferred.y)-radius, floori(preferred.y)+radius+1):
			for x in range(floori(preferred.x)-radius, floori(preferred.x)+radius+1):
				var pos := Vector2(x,z)
				if sim.placement_error(0,pos,channel).is_empty(): return pos
	return Vector2.INF

func completed_new_building(spec: String, original: Dictionary) -> int:
	for id in sim.entities:
		var entity: Dictionary = sim.entities[id]
		if not original.has(id) and entity.spec == spec and float(entity.construct_remaining) <= 0.0: return int(id)
	return -1

func find_entity(spec: String) -> int:
	for entity in sim.entities.values():
		if entity.spec == spec and int(entity.team) == 0 and float(entity.hp) > 0.0: return int(entity.id)
	return -1

func count_entities(spec: String) -> int:
	var count := 0
	for entity in sim.entities.values():
		if entity.spec == spec and int(entity.team) == 0 and float(entity.hp) > 0.0: count += 1
	return count

func advance_until(label: String, done: Callable, max_seconds: float) -> bool:
	current_phase = label
	var start: float = sim.time
	var money_start: Array = sim.money.duplicate()
	var income_start: Array[float] = delivery_income.duplicate()
	var start_deaths := deaths.size()
	print("DEMO_CAMPAIGN_LIVE_PHASE ", label, " stage=", sim.campaign_controller.stage, " limit=", max_seconds)
	while sim.time-start < max_seconds-STEP*.5 and not done.call() and sim.result.is_empty():
		var money_before_step: Array = sim.money.duplicate()
		sim.step(STEP)
		tick_count += 1
		observe_events(money_before_step)
		observe_ai()
		observe_navigation()
		record_stage()
		sim.events.clear()
		sim.notices.clear()
		OS.delay_usec(WORKER_YIELD_US)
		await process_frame
		if tick_count % 900 == 0:
			var snapshot: Dictionary = compact_snapshot()
			progress.append(snapshot)
			print("DEMO_CAMPAIGN_LIVE_PROGRESS ", JSON.stringify(snapshot))
			write_report(false)
	var passed: bool = bool(done.call())
	var phase_income: Array[float] = []
	var phase_payment: Array[float] = []
	for team in range(2):
		phase_income.append(delivery_income[team]-income_start[team])
		phase_payment.append(float(money_start[team])+phase_income[team]-float(sim.money[team]))
	phases.append({"phase": label, "start_sim_seconds": start, "end_sim_seconds": sim.time, "elapsed_sim_seconds": sim.time-start,
		"original_limit_seconds": max_seconds, "completed": passed, "stage": sim.campaign_controller.stage, "result": sim.result,
		"money_start": money_start, "money_end": sim.money.duplicate(), "delivery_income": phase_income, "ordinary_step_payments": phase_payment,
		"deaths": deaths.size()-start_deaths, "units": unit_diagnostics()})
	write_report(false)
	return passed

func observe_events(money_before_step: Array) -> void:
	var this_income: Array[float] = [0.0, 0.0]
	for event in sim.events:
		var kind: String = str(event.get("kind", ""))
		var record := {"time": sim.time, "kind": kind, "team": event.get("team", -1), "spec": event.get("spec", ""),
			"id": event.get("id", -1), "pos": point(event.get("pos", Vector2.INF)), "amount": event.get("amount", 0.0), "carrier": event.get("carrier", -1)}
		if kind == "delivery":
			deliveries.append(record)
			var team: int = int(record.team)
			if team >= 0 and team < 2:
				delivery_income[team] += float(record.amount)
				this_income[team] += float(record.amount)
		elif kind == "produce": production.append(record)
		elif kind in ["board", "unload"]: transport_events.append(record)
		elif kind == "death":
			deaths.append(record)
			if record.spec == "kestrel_tank": armor_deaths.append(record)
	for team in range(2):
		minimum_money[team] = minf(minimum_money[team], float(sim.money[team]))
		step_payments[team] += float(money_before_step[team])+this_income[team]-float(sim.money[team])

func observe_ai() -> void:
	var armed := 0
	var queued_armed := 0
	for entity in sim.entities.values():
		if int(entity.team) != 1 or float(entity.hp) <= 0.0: continue
		if entity.kind == "unit" and not str(sim.data_for(entity.spec).get("weapon", "")).is_empty(): armed += 1
		elif entity.kind == "building":
			max_ai_production_queue = maxi(max_ai_production_queue, entity.queue.size())
			for order in entity.queue:
				if not str(sim.data_for(order.spec).get("weapon", "")).is_empty(): queued_armed += 1
	max_ai_armed = maxi(max_ai_armed, armed)
	max_ai_armed_including_queue = maxi(max_ai_armed_including_queue, armed+queued_armed)
	max_ai_waves = maxi(max_ai_waves, int(sim.ai_state[1].get("campaign_waves", 0)))

func navigation_violation(record: Dictionary) -> void:
	if navigation_violations.size() < 64: navigation_violations.append(record)

# The movement contract permits a crushing unit to enter its target's ordinary
# 0.02 avoidance margin. Actual live-body penetration remains independently illegal.
static func pair_clearance(simulation: WarSimulation, entity: Dictionary, other: Dictionary) -> Dictionary:
	var body: float = float(entity.radius) + float(other.radius)
	var separation: float = (entity.pos as Vector2).distance_to(other.pos)
	var crush_allowed: bool = simulation._can_crush_target(entity, other) or simulation._can_crush_target(other, entity)
	var required: float = body if crush_allowed else body + .02
	return {"body": body, "separation": separation, "required": required, "crush_allowed": crush_allowed,
		"body_overlap": separation < body - .000001, "margin_violation": separation < required - .0001}

func observe_navigation() -> void:
	maximum_queue = maxi(maximum_queue, sim._planning_queue.size())
	maximum_in_flight = maxi(maximum_in_flight, sim._path_in_flight)
	budgets_legal = budgets_legal and sim._yield_requests >= 0 and sim._yield_requests <= sim.YIELD_REQUESTS_PER_TICK and sim._avoidance_probes >= 0 and sim._path_in_flight <= sim.PATH_IN_FLIGHT
	var ground: Array[int] = []
	for entity in sim.entities.values():
		if entity.kind == "unit" and float(entity.hp) > 0.0 and not Transport.is_loaded(entity) and not sim._is_air(entity) and not sim._is_naval(entity): ground.append(int(entity.id))
	# Rotate six actual units per tick: light enough for a paid long tutorial,
	# while still sampling collision each tick instead of only at phase ends.
	for index in range(mini(6,ground.size())):
		var id: int = ground[(tick_count+index)%ground.size()]
		var entity: Dictionary = sim.entities[id]
		var radius: float = float(entity.radius)
		collision_unit_samples += 1
		if not sim._standing(entity.pos, radius, id, false):
			navigation_violation({"kind": "static_position", "time": sim.time, "id": id, "spec": entity.spec, "pos": point(entity.pos)})
		if previous_positions.has(id) and not bool(previous_loaded.get(id, true)):
			if not sim._segment_static(previous_positions[id], entity.pos, radius, id):
				navigation_violation({"kind": "static_segment", "time": sim.time, "id": id, "from": point(previous_positions[id]), "to": point(entity.pos)})
		for other in sim._neighbors(entity.pos):
			if int(other.id) == id or float(other.hp) <= 0.0 or Transport.is_loaded(other): continue
			collision_pair_samples += 1
			var body: float = radius+float(other.radius)
			var separation: float = (entity.pos as Vector2).distance_to(other.pos)
			minimum_sampled_margin = minf(minimum_sampled_margin, separation-body)
			maximum_sampled_overlap = maxf(maximum_sampled_overlap, body-separation)
			var clearance: Dictionary = pair_clearance(sim, entity, other)
			if bool(clearance.body_overlap) or bool(clearance.margin_violation):
				navigation_violation({"kind": "unit_body_overlap" if bool(clearance.body_overlap) else "unit_margin",
					"time": sim.time, "id": id, "other": other.id, "pos": point(entity.pos), "other_pos": point(other.pos),
					"separation": separation, "body": body, "required": clearance.required, "crush_allowed": clearance.crush_allowed})
	for entity in sim.entities.values():
		if entity.kind == "unit":
			previous_positions[entity.id] = entity.pos
			previous_loaded[entity.id] = Transport.is_loaded(entity)

func record_stage() -> void:
	if latest_stage == int(sim.campaign_controller.stage): return
	latest_stage = int(sim.campaign_controller.stage)
	stage_history.append({"stage": latest_stage, "time": sim.time, "flags": sim.campaign_controller.flags.duplicate(),
		"hold_elapsed": sim.campaign_controller.hold_elapsed, "money": sim.money.duplicate()})

func validate_receipts() -> void:
	var ordinary_paid := true
	var queues_normal := true
	var player_paid_buildings := 0
	var player_paid_units := 0
	for receipt in sim.purchase_receipts:
		if receipt.get("field_paid_during_work", false):
			ordinary_paid = ordinary_paid and is_zero_approx(float(receipt.debit))
			continue
		ordinary_paid = ordinary_paid and absf(float(receipt.debit)-float(receipt.rules_cost)) < .00001 and absf(float(receipt.queue_cost)-float(receipt.rules_cost)) < .00001
		queues_normal = queues_normal and not bool(receipt.ready) and absf(float(receipt.remaining)-float(receipt.total)) < .00001 and is_zero_approx(float(receipt.progress))
		if receipt.team == 0:
			if receipt.kind == "building": player_paid_buildings += 1
			elif receipt.kind == "unit": player_paid_units += 1
	check(ordinary_paid and player_paid_buildings >= 5 and player_paid_units >= 6, "ordinary buildings/units debit actual configured costs; field outpost is charged during work")
	check(queues_normal, "successful paid purchases begin with full remaining time and are not forced ready")
	var outpost_phase: Array = phases.filter(func(p): return p.phase == "actual construction completes kestrel_outpost")
	check(not outpost_phase.is_empty() and float(outpost_phase[0].ordinary_step_payments[0])+0.001 >= float(rules.buildings.kestrel_outpost.cost), "engineer outpost construction actually pays its configured cost during normal work")
	var repair_phase: Array = phases.filter(func(p): return p.phase == "engineer walks and pays for bridge repair")
	check(not repair_phase.is_empty() and float(repair_phase[0].ordinary_step_payments[0])+0.001 >= float(rules.economy.bridge_cost), "bridge repair actually spends normal configured repair funds")

func unit_diagnostics() -> Array[Dictionary]:
	var units: Array[Dictionary] = []
	for entity in sim.entities.values():
		if entity.kind != "unit": continue
		var commands: Array[Dictionary] = []
		for command in entity.commands:
			commands.append({"kind": command.kind, "pos": point(command.pos), "target": command.get("target", -1)})
		var path: Array = []
		for node: Vector2 in entity.path: path.append(point(node))
		units.append({"id": entity.id, "team": entity.team, "spec": entity.spec, "pos": point(entity.pos), "hp": entity.hp,
			"state": entity.state, "commands": commands, "path": path, "path_wait": entity.path_wait,
			"planning_wait": entity.get("planning_wait",0.0), "stuck": entity.stuck, "yield_goal": point(entity.get("yield_goal",Vector2.INF)),
			"transport_id": entity.get("transport_id",-1), "cargo": entity.cargo})
	return units

func compact_snapshot() -> Dictionary:
	return {"phase": current_phase, "stage": sim.campaign_controller.stage, "sim_seconds": sim.time, "result": sim.result,
		"money": sim.money.duplicate(), "armed_ai": max_ai_armed, "waves": max_ai_waves,
		"units": sim.entities.size(), "armor": count_entities("kestrel_tank"), "in_flight": sim._path_in_flight,
		"queue": sim._planning_queue.size(), "navigation": sim.navigation_stats.duplicate(),
		"violations": navigation_violations.size(), "wall_seconds": float(Time.get_ticks_usec()-wall_started_usec)/1000000.0}

func write_report(complete: bool) -> void:
	var enemy_hq_hp := -1.0
	var player_hq_hp := -1.0
	var force: Dictionary = {}
	for entity in sim.entities.values():
		force[entity.spec] = int(force.get(entity.spec,0))+1
		if entity.spec == "rivet_hq": enemy_hq_hp = entity.hp
		elif entity.spec == "kestrel_hq": player_hq_hp = entity.hp
	var report := {"schema": 1, "complete": complete, "checks": checks, "passed": checks-failures.size(), "failures": failures,
		"scope": "paid full campaign functional headless run with real asynchronous worker, fixed original limits; no GPU or FPS claim",
		"default_ai_enabled": not no_ai, "ai_enabled": sim.ai_enabled, "seed": SEED, "step_seconds": STEP,
		"worker_yield_us_per_tick": WORKER_YIELD_US, "process_frame_each_tick": true, "tick_count": tick_count,
		"map_size": sim.map.size, "setup_ms": setup_ms, "startup_profile": sim.startup_profile,
		"wall_seconds": float(Time.get_ticks_usec()-wall_started_usec)/1000000.0, "sim_seconds": sim.time,
		"result": sim.result, "campaign": sim.campaign_controller.to_dict(), "stage_history": stage_history,
		"phases": phases, "progress": progress, "placed_sites": placed_sites, "initial_money": initial_money,
		"final_money": sim.money.duplicate(), "minimum_money": minimum_money, "delivery_income": delivery_income,
		"ordinary_step_payments": step_payments, "purchase_receipts": sim.purchase_receipts,
		"deliveries": deliveries, "production": production, "transport_events": transport_events, "deaths": deaths, "armor_deaths": armor_deaths,
		"max_ai_armed": max_ai_armed, "max_ai_armed_including_queue": max_ai_armed_including_queue,
		"max_ai_production_queue": max_ai_production_queue, "max_ai_waves": max_ai_waves, "ai_state": sim.ai_state,
		"enemy_hq_hp": enemy_hq_hp, "player_hq_hp": player_hq_hp, "force": force, "remaining_units": unit_diagnostics(),
		"navigation": sim.navigation_stats.duplicate(), "maximum_queue": maximum_queue, "maximum_in_flight": maximum_in_flight,
		"maximum_planning_wait_seconds": sim._planning_max_wait, "budgets_legal": budgets_legal,
		"collision_unit_samples": collision_unit_samples, "collision_pair_samples": collision_pair_samples,
		"minimum_sampled_margin": minimum_sampled_margin if is_finite(minimum_sampled_margin) else null,
		"maximum_sampled_overlap": maximum_sampled_overlap, "navigation_violations": navigation_violations,
		"native_available": sim._kernels != null, "native_dispatch": sim.native_kernels_enabled and sim.native_unit_dispatch_enabled and sim._kernels != null,
		"native_movement": sim.native_movement_enabled, "synchronous_test_adapter": sim.synchronous_path_tests,
		"source_before": source_before, "source_after": source_hashes(), "godot": Engine.get_version_info().string}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write campaign live report: " + output)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
