extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
const Validator = preload("res://scripts/sim_save_validator.gd")
const Construction = preload("res://scripts/outpost_construction.gd")
# A historical save owns this retired blueprint even after catalog removal.
const LEGACY_RIVET_OUTPOST: Dictionary = {
	"name": "前线压梁台", "faction": "rivet", "cost": 1100, "hp": 1700,
	"build_time": 60, "power": -20, "size": 3, "requires": ["rivet_power"],
	"role": "outpost", "expands": true, "weapon": "", "art": "outpost",
	"animations": {"idle": "res://assets/cards/rivet_outpost_portrait.png", "death": "res://assets/cards/rivet_outpost_death.svg"},
	"formal_name": "前线压梁台", "description": "工程兵选址并抵达后搭建低生命脚手架；现场施工逐步付款，受伤先维修、工兵阵亡后可接手或拆除，完工后授权前线建设。"
}
const LEGACY_RIVET_BARRACKS: Dictionary = {
	"name": "军团大兵营", "faction": "rivet", "cost": 1000, "hp": 1400,
	"build_time": 15, "power": 0, "size": 4, "requires": [],
	"role": "barracks", "expands": true, "weapon": "", "art": "hq",
	"animations": {"idle": "res://assets/cards/rivet_hq_portrait.png", "death": "res://assets/cards/rivet_hq_death.svg"},
	"formal_name": "军团大兵营", "local_power": 100, "local_power_radius": 12,
	"prerequisite_roles": ["hq"], "vision_radius": 24, "construction_radius": 20
}
var rules: Dictionary
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	rules = RulesLoader.load_rules("res://data/rules.json", false)
	if rules.is_empty():
		push_error("Rivet save rules invalid: " + str(RulesLoader.errors))
		quit(1)
		return
	_test_headquarters_queue()
	_test_unified_base_round_trip()
	_test_unified_rules()
	_test_field_buildings()
	_test_disallowed_field_buildings()
	_test_legacy_snapshots()
	print("RIVET_SAVE ", JSON.stringify({"checks": checks, "failures": failures}))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func valid(snapshot: Dictionary, label: String) -> void:
	var error: String = Validator.check(snapshot)
	check(error.is_empty(), label + ": " + error)

func fixture(faction: String = "rivet") -> Dictionary:
	var sim = Sim.new()
	sim.setup(rules, "dev", 7, faction, false)
	sim.money.assign([100000.0, 100000.0])
	var engineer: int = sim.debug_spawn(0, faction + "_engineer", Vector2(14, 43))
	var site: int = sim._spawn(0, faction + "_power", Vector2(24.5, 39.5), true)
	var headquarters: int = -1
	for e: Dictionary in sim.entities.values():
		if e.kind == "building" and e.team == 0 and sim.data_for(e.spec).get("role") == "hq": headquarters = int(e.id)
	return {"sim": sim, "engineer": engineer, "site": site, "headquarters": headquarters}

func snapshot_of(sim) -> Dictionary:
	var path: String = "user://rivet_validator_fixture.save"
	check(sim.save_game(path).is_empty(), "fixture snapshot saves")
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var snapshot: Dictionary = file.get_var(false)
	file.close()
	return snapshot

func field_order(snapshot: Dictionary, spec: String, builder: int) -> void:
	var info: Dictionary = snapshot.rules.buildings[spec]
	var order: Dictionary = {"spec": spec, "remaining": 0.0, "total": float(info.build_time), "cost": 0.0, "ready": true, "progress": 0.0, "builder": builder}
	if info.role in ["tower", "wall", "barricade"]: snapshot.defense_orders[0] = order
	else: snapshot.building_orders[0] = order

func scaffold(snapshot: Dictionary, id: int, spec: String, builder: int) -> void:
	var info: Dictionary = snapshot.rules.buildings[spec]
	var e: Dictionary = snapshot.entities[id]
	var initial_hp: float = minf(Construction.INITIAL_HEALTH_LIMIT, float(info.hp) * Construction.INITIAL_HEALTH_RATIO)
	e.spec = spec
	e.max_hp = float(info.hp)
	e.construct_remaining = float(info.build_time) * 0.75
	e.hp = initial_hp + (float(info.hp) - initial_hp) * 0.25
	e.construction = {"builder": builder, "progress": 0.25, "spent": float(info.cost) * 0.25, "initial_hp": initial_hp, "repair_spent": 0.0, "work_state": "paused", "pause_reason": "等待工程兵施工"}
	e.state = "construct"

func _test_headquarters_queue() -> void:
	var state: Dictionary = fixture()
	var sim = state.sim
	check(sim.produce(state.headquarters, "rivet_rifle").is_empty(), "Rivet HQ queues infantry")
	var snapshot: Dictionary = snapshot_of(sim)
	valid(snapshot, "Rivet HQ infantry queue validates through production_roles")
	var restored = Sim.new()
	var error: String = restored.load_game("user://rivet_validator_fixture.save")
	check(error.is_empty() and restored.entities[state.headquarters].queue == sim.entities[state.headquarters].queue, "Rivet HQ queue survives load: " + error)
	var invalid: Dictionary = snapshot.duplicate(true)
	invalid.rules.buildings.rivet_hq.production_roles = []
	check(not Validator.check(invalid).is_empty(), "HQ cannot produce infantry without its configured production role")
	invalid = snapshot.duplicate(true)
	var vehicle: Dictionary = invalid.rules.units.rivet_tank
	invalid.entities[state.headquarters].queue = [{"spec": "rivet_tank", "remaining": float(vehicle.build_time), "total": float(vehicle.build_time), "cost": float(vehicle.cost), "started": false, "ready": false, "progress": 0.0}]
	check(not Validator.check(invalid).is_empty(), "Rivet HQ rejects a vehicle production queue")

func _test_unified_base_round_trip() -> void:
	var state: Dictionary = fixture()
	var sim = state.sim
	var expansion: int = sim._spawn(0, "rivet_hq", Vector2(34, 39), true)
	check(sim.produce(state.headquarters, "rivet_rifle").is_empty(), "initial base barracks queues infantry")
	check(sim.produce(expansion, "rivet_engineer").is_empty(), "built base barracks queues engineers independently")
	var snapshot: Dictionary = snapshot_of(sim)
	scaffold(snapshot, state.site, "rivet_hq", state.engineer)
	snapshot.entities[state.engineer].commands = [{"kind": "resume_outpost", "pos": Vector2(24.5, 39.5), "target": state.site}]
	field_order(snapshot, "rivet_hq", state.engineer)
	valid(snapshot, "multiple base barracks queues, scaffold and next site selection share one blueprint")
	var path: String = "user://unified_rivet_base.save"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_var(snapshot, false)
	file.close()
	var restored = Sim.new()
	var error: String = restored.load_game(path)
	check(error.is_empty(), "multiple unified base barracks load: " + error)
	if not error.is_empty(): return
	check(restored.rules == snapshot.rules and not restored.rules.buildings.has("rivet_barracks"), "loaded current save retains only the unified base blueprint")
	check(restored.entities[state.headquarters].spec == restored.entities[expansion].spec and restored.entities[expansion].spec == restored.entities[state.site].spec, "initial, built and unfinished bases retain the same building ID")
	check(restored.entities[state.headquarters].queue == snapshot.entities[state.headquarters].queue and restored.entities[expansion].queue == snapshot.entities[expansion].queue, "independent base barracks production queues survive load")
	check(restored.entities[state.site].construction == snapshot.entities[state.site].construction and restored.building_orders[0] == snapshot.building_orders[0], "base barracks scaffold and next building order survive load")
	valid(snapshot_of(restored), "loaded unified base barracks save again without migration")

func _test_unified_rules() -> void:
	check(not rules.buildings.has("rivet_barracks") and bool(rules.buildings.rivet_hq.rebuildable), "current catalog has one repeatable base barracks blueprint")
	check(rules.buildings.rivet_hq.name == "基地兵营" and rules.buildings.rivet_hq.formal_name == "基地兵营", "unified base barracks has its requested name")
	check(RulesLoader.validate(rules, false).is_empty(), "HQ production alias supplies infantry without a separate barracks blueprint")
	var invalid: Dictionary = rules.duplicate(true)
	invalid.buildings.rivet_hq.rebuildable = "true"
	check(not RulesLoader.validate(invalid, false).is_empty(), "rebuildable must be a boolean")
	invalid = rules.duplicate(true)
	invalid.buildings.rivet_power.rebuildable = true
	check(not RulesLoader.validate(invalid, false).is_empty(), "only headquarters blueprints may configure rebuilding")

func _test_field_buildings() -> void:
	var state: Dictionary = fixture()
	var baseline: Dictionary = snapshot_of(state.sim)
	valid(baseline, "Rivet baseline validates")
	for spec: String in baseline.rules.buildings:
		var info: Dictionary = baseline.rules.buildings[spec]
		if info.faction != "rivet": continue
		var snapshot: Dictionary = baseline.duplicate(true)
		field_order(snapshot, spec, state.engineer)
		valid(snapshot, spec + " engineer site-selection order validates")
		var invalid: Dictionary = snapshot.duplicate(true)
		var channel: String = "defense" if info.role in ["tower", "wall", "barricade"] else "normal"
		if channel == "defense": invalid.defense_orders[0].erase("builder")
		else: invalid.building_orders[0].erase("builder")
		check(not Validator.check(invalid).is_empty(), spec + " cannot bypass engineer ownership")
		snapshot = baseline.duplicate(true)
		snapshot.entities[state.engineer].commands = [{"kind": "deploy_outpost", "pos": Vector2(24.5, 39.5), "target": -1, "spec": spec, "cost": 0.0}]
		valid(snapshot, spec + " engineer deployment command validates")
		snapshot = baseline.duplicate(true)
		scaffold(snapshot, state.site, spec, state.engineer)
		snapshot.entities[state.engineer].commands = [{"kind": "resume_outpost", "pos": Vector2(24.5, 39.5), "target": state.site}]
		valid(snapshot, spec + " scaffold and takeover command validate")

func _test_disallowed_field_buildings() -> void:
	var state: Dictionary = fixture("kestrel")
	var baseline: Dictionary = snapshot_of(state.sim)
	valid(baseline, "conventional faction baseline validates")
	var invalid: Dictionary = baseline.duplicate(true)
	field_order(invalid, "kestrel_power", state.engineer)
	check(not Validator.check(invalid).is_empty(), "conventional power order rejects an engineer builder")
	invalid = baseline.duplicate(true)
	invalid.entities[state.engineer].commands = [{"kind": "deploy_outpost", "pos": Vector2(24.5, 39.5), "target": -1, "spec": "kestrel_power", "cost": 0.0}]
	check(not Validator.check(invalid).is_empty(), "conventional power rejects engineer deployment")
	invalid = baseline.duplicate(true)
	scaffold(invalid, state.site, "kestrel_power", state.engineer)
	check(not Validator.check(invalid).is_empty(), "conventional power rejects a forged scaffold")
	invalid = baseline.duplicate(true)
	invalid.entities[state.engineer].commands = [{"kind": "resume_outpost", "pos": Vector2(24.5, 39.5), "target": state.site}]
	check(not Validator.check(invalid).is_empty(), "conventional power rejects a forged takeover command")
	invalid = baseline.duplicate(true)
	scaffold(invalid, state.site, "kestrel_hq", state.engineer)
	check(Validator.check(invalid).contains("总部") or Validator.check(invalid).contains("脚手架类型"), "traditional HQ rejects an engineer scaffold")
	invalid = baseline.duplicate(true)
	field_order(invalid, "kestrel_hq", state.engineer)
	check(not Validator.check(invalid).is_empty(), "traditional HQ rejects an engineer building order")
	invalid = baseline.duplicate(true)
	invalid.entities[state.engineer].commands = [{"kind": "deploy_outpost", "pos": Vector2(24.5, 39.5), "target": -1, "spec": "kestrel_hq", "cost": 0.0}]
	check(not Validator.check(invalid).is_empty(), "traditional HQ rejects engineer deployment")
	invalid = baseline.duplicate(true)
	invalid.entities[state.engineer].commands = [{"kind": "resume_outpost", "pos": Vector2(24.5, 39.5), "target": state.headquarters}]
	check(not Validator.check(invalid).is_empty(), "traditional HQ rejects an engineer takeover command")
	invalid = baseline.duplicate(true)
	invalid.entities[state.site].spec = "kestrel_hq"
	check(Validator.check(invalid).contains("一个总部"), "traditional HQ remains unique per owner")
	state = fixture()
	baseline = snapshot_of(state.sim)
	invalid = baseline.duplicate(true)
	field_order(invalid, "kestrel_hq", state.engineer)
	check(not Validator.check(invalid).is_empty(), "repeatable base barracks rule cannot authorize another faction HQ")
	invalid = baseline.duplicate(true)
	invalid.entities[state.engineer].commands = [{"kind": "deploy_outpost", "pos": Vector2(24.5, 39.5), "target": -1, "spec": "kestrel_hq", "cost": 0.0}]
	check(not Validator.check(invalid).is_empty(), "repeatable base barracks builder cannot deploy another faction HQ")

func legacy_headquarters(snapshot: Dictionary) -> void:
	var hq: Dictionary = snapshot.rules.buildings.rivet_hq
	hq.name = "军团大兵营"
	hq.formal_name = "军团大兵营"
	hq.cost = 2800
	hq.build_time = 60
	hq.erase("rebuildable")
	hq.erase("construction_radius")
	snapshot.rules.buildings.rivet_barracks = LEGACY_RIVET_BARRACKS.duplicate(true)

func _test_legacy_snapshots() -> void:
	var state: Dictionary = fixture()
	var baseline: Dictionary = snapshot_of(state.sim)
	legacy_headquarters(baseline)
	var split_snapshot: Dictionary = baseline.duplicate(true)
	split_snapshot.entities[state.site].spec = "rivet_barracks"
	split_snapshot.entities[state.site].hp = float(LEGACY_RIVET_BARRACKS.hp)
	split_snapshot.entities[state.site].max_hp = float(LEGACY_RIVET_BARRACKS.hp)
	var infantry: Dictionary = split_snapshot.rules.units.rivet_rifle
	split_snapshot.entities[state.site].queue = [{"spec": "rivet_rifle", "remaining": float(infantry.build_time), "total": float(infantry.build_time), "cost": float(infantry.cost), "started": false, "ready": false, "progress": 0.0}]
	valid(split_snapshot, "historical split HQ and expansion barracks snapshot remains readable")
	var split_path: String = "user://legacy_split_rivet_base.save"
	var split_file: FileAccess = FileAccess.open(split_path, FileAccess.WRITE)
	split_file.store_var(split_snapshot, false)
	split_file.close()
	var split_restored = Sim.new()
	var split_error: String = split_restored.load_game(split_path)
	check(split_error.is_empty() and split_restored.rules == split_snapshot.rules and split_restored.entities[state.site] == split_snapshot.entities[state.site], "historical split base IDs and properties load without remapping: " + split_error)
	baseline.rules.factions.rivet.erase("building_method")
	baseline.rules.buildings.rivet_hq.erase("production_roles")
	baseline.rules.buildings.rivet_hq.erase("prerequisite_roles")
	baseline.rules.buildings.rivet_outpost = LEGACY_RIVET_OUTPOST.duplicate(true)
	valid(baseline, "legacy conventional Rivet snapshot validates")
	var snapshot: Dictionary = baseline.duplicate(true)
	var power: Dictionary = snapshot.rules.buildings.rivet_power
	snapshot.building_orders[0] = {"spec": "rivet_power", "remaining": float(power.build_time), "total": float(power.build_time), "cost": float(power.cost), "ready": false, "progress": 0.0}
	valid(snapshot, "legacy HQ power-building queue remains readable")
	snapshot = baseline.duplicate(true)
	field_order(snapshot, "rivet_outpost", state.engineer)
	valid(snapshot, "legacy engineer outpost selection remains readable")
	snapshot = baseline.duplicate(true)
	snapshot.entities[state.engineer].commands = [{"kind": "deploy_outpost", "pos": Vector2(24.5, 39.5), "target": -1, "spec": "rivet_outpost", "cost": float(snapshot.rules.buildings.rivet_outpost.cost)}]
	valid(snapshot, "legacy prepaid outpost deployment remains readable")
	snapshot = baseline.duplicate(true)
	scaffold(snapshot, state.site, "rivet_outpost", state.engineer)
	snapshot.entities[state.engineer].commands = [{"kind": "resume_outpost", "pos": Vector2(24.5, 39.5), "target": state.site}]
	valid(snapshot, "legacy outpost scaffold and takeover remain readable")
	var path: String = "user://retired_rivet_outpost.save"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_var(snapshot, false)
	file.close()
	var restored = Sim.new()
	var error: String = restored.load_game(path)
	check(error.is_empty() and restored.entities[state.site] == snapshot.entities[state.site] and restored.rules.buildings.get("rivet_outpost", {}) == LEGACY_RIVET_OUTPOST, "retired Rivet outpost loads with its own historical blueprint: " + error)
