extends RefCounted
## Observational telemetry. Sampling never issues commands or changes economy.
const SCHEMA_VERSION := 2
const SAMPLE_INTERVAL := 1.0
const RailNetwork = preload("res://scripts/rail_network.gd")
const LOGICAL_EVENTS := ["build", "produce", "deploy", "death", "sell", "capture", "garrison", "ungarrison", "repair", "low_power", "power_restored", "bridge_destroyed", "bridge_repaired", "result", "construction_start", "construction_cancel"]
const DEFINITIONS := {
	"time": "Authoritative simulation seconds; paused time is excluded.",
	"money_remaining": "Spendable funds at this instant.",
	"funds_earned": "Actual resource/economy income; excludes sales and refunds.",
	"funds_spent": "Initial + earned + sales - current funds, clamped at zero: net investment after refunds, including repairs/prepaid orders, not gross purchases.",
	"building_total": "All live owned structures, including construction, walls and rails.",
	"alive_buildings": "Legacy live structure count: excludes rails, includes construction.",
	"eliminated_teams": "Owners with no live victory-counting structures; walls, barricades and rails cannot sustain a side.",
	"winner_teams": "Derived from the authoritative player-relative result for two-side matches (and sole-player victory in multiteam). winner_teams_known is false when no unique winner can be inferred or a match is unfinished.",
	"infantry_total": "Live ground units classified as infantry by simulation armor rules; includes transported and garrisoned units.",
	"army_value": "Nominal rules cost of live units, including gifts/captures/transported units; not expenditure.",
	"building_value": "Nominal rules cost of live structures, including construction and rails; not expenditure.",
	"units_lost_value": "Nominal rules cost of destroyed units; excludes noncombat removals.",
	"buildings_lost_value": "Nominal rules cost of destroyed nonrail structures; excludes sales.",
	"income_per_minute": "Resource income delta since preceding sample, scaled to one minute; first sample zero.",
	"funds_spent_per_minute": "Net investment delta since preceding sample, scaled to one minute; refunds can make it negative.",
	"low_power_seconds_sampled": "Intervals whose previous sample had a power shortage; approximate to sampling resolution.",
	"zero_funds_seconds_sampled": "Intervals whose previous sample had less than one fund; approximate to sampling resolution.",
	"damage_dealt": "Existing credited simulation damage, capped against pending lethal damage; may include neutral targets.",
	"events": "Logical milestones only; movement/projectile trajectories and full replay state omitted.",
	"sampling": "Approximately one simulation-second plus initial/explicit/final observations. Oversized ticks use actual observation time; no invented backfilled states."
}
var teams: Array[Dictionary] = []
var initial_money: Array = []
var since_time := 0.0
var history: Array[Dictionary] = []
var events: Array[Dictionary] = []
var metadata: Dictionary = {}
var history_since_time := 0.0
var telemetry_history_complete := true
var _next_sample_time := 0.0
var _finished := false

func reset(factions: Array, money: Array, start_time: float = 0.0) -> void:
	teams.clear()
	initial_money = money.duplicate()
	since_time = start_time
	history.clear()
	events.clear()
	metadata.clear()
	history_since_time = start_time
	telemetry_history_complete = is_zero_approx(start_time)
	_next_sample_time = start_time
	_finished = false
	for faction: String in factions:
		teams.append({"faction": faction, "funds_earned": 0.0, "sales_income": 0.0, "units_produced": 0, "buildings_built": 0, "units_killed": 0, "units_lost": 0, "buildings_destroyed": 0, "buildings_lost": 0, "damage_dealt": 0.0, "damage_received": 0.0,
			"infantry_produced": 0, "infantry_killed": 0, "infantry_lost": 0, "units_produced_by_spec": {}, "buildings_built_by_spec": {}, "units_killed_by_spec": {}, "units_lost_by_spec": {}, "buildings_destroyed_by_spec": {}, "buildings_lost_by_spec": {},
			"units_lost_value": 0.0, "buildings_lost_value": 0.0, "enemy_units_destroyed_value": 0.0, "enemy_buildings_destroyed_value": 0.0, "buildings_captured": 0, "buildings_captured_lost": 0, "buildings_sold": 0,
			"peak_units": 0, "peak_buildings": 0, "peak_infantry": 0, "peak_army_value": 0.0, "low_power_seconds_sampled": 0.0, "zero_funds_seconds_sampled": 0.0})

func begin(sim) -> void:
	_metadata_for(sim)
	sample(sim, true)
	if not history.is_empty(): metadata.initial_teams = history[0].teams.duplicate(true)

func add(team: int, field: String, amount: float = 1.0) -> void:
	if team >= 0 and team < teams.size() and is_finite(amount):
		teams[team][field] = float(teams[team].get(field, 0)) + amount

func destroyed(entity: Dictionary, cause: Dictionary, info: Dictionary = {}) -> void:
	var victim: int = int(entity.team)
	var building: bool = entity.kind == "building"
	add(victim, "buildings_lost" if building else "units_lost")
	var attacker: int = int(cause.get("source_team", -1))
	if attacker != victim: add(attacker, "buildings_destroyed" if building else "units_killed")
	# Detailed deaths are recorded synchronously, so presentation event draining
	# cannot erase per-spec losses between samples.
	var spec: String = str(entity.get("spec", ""))
	_by_spec(victim, "buildings_lost_by_spec" if building else "units_lost_by_spec", spec)
	var value: float = maxf(0.0, float(info.get("cost", 0)))
	add(victim, "buildings_lost_value" if building else "units_lost_value", value)
	var infantry: bool = not building and _is_infantry(info)
	if infantry: add(victim, "infantry_lost")
	if attacker != victim:
		_by_spec(attacker, "buildings_destroyed_by_spec" if building else "units_killed_by_spec", spec)
		add(attacker, "enemy_buildings_destroyed_value" if building else "enemy_units_destroyed_value", value)
		if infantry: add(attacker, "infantry_killed")

func record_event(event: Dictionary, at_time: float, sim = null) -> void:
	var kind: String = str(event.get("kind", ""))
	if kind not in LOGICAL_EVENTS or bool(event.get("_statistics_recorded", false)): return
	event._statistics_recorded = true
	var entry: Dictionary = {"time": at_time, "kind": kind}
	for field: String in ["id", "target", "team", "previous_team", "spec", "entity_kind", "construction_method", "destroyed", "result", "reason", "forced"]:
		if event.has(field): entry[field] = event[field]
	if event.get("pos") is Vector2: entry.position = [event.pos.x, event.pos.y]
	elif event.get("pos") is Array: entry.position = event.pos.duplicate()
	if event.get("cause") is Dictionary:
		entry.cause = {}
		for field: String in ["source", "source_team", "weapon", "explosive", "crush", "force"]:
			if event.cause.has(field): entry.cause[field] = event.cause[field]
	var team: int = int(event.get("team", -1))
	var spec: String = str(event.get("spec", ""))
	if spec.is_empty() and sim != null and sim.entities.has(int(event.get("id", -1))):
		spec = str(sim.entities[int(event.id)].spec)
		entry.spec = spec
	var info: Dictionary = sim.data_for(spec) if sim != null and not spec.is_empty() else {}
	if kind == "produce":
		_by_spec(team, "units_produced_by_spec", spec)
		if _is_infantry(info): add(team, "infantry_produced")
	elif kind == "deploy" and str(event.get("entity_kind", "building")) == "building" and not RailNetwork.is_rail(info):
		_by_spec(team, "buildings_built_by_spec", spec)
	elif kind == "capture":
		add(team, "buildings_captured")
		add(int(event.get("previous_team", -1)), "buildings_captured_lost")
	elif kind == "sell": add(team, "buildings_sold")
	events.append(entry)

func sample(sim, force: bool = false) -> void:
	# Ingest before the one-second throttle; the UI may drain events every frame.
	for event: Dictionary in sim.events: record_event(event, float(sim.time), sim)
	var now: float = float(sim.time)
	var final_sample: bool = not str(sim.result).is_empty()
	if not force and not final_sample and now + 0.000001 < _next_sample_time: return
	_metadata_for(sim)
	var rows: Array[Dictionary] = _current_rows(sim)
	var previous: Dictionary = history.back() if not history.is_empty() else {}
	var same_time: bool = not previous.is_empty() and absf(float(previous.time) - now) <= 0.000001
	var earlier: Dictionary = history[history.size() - 2] if same_time and history.size() > 1 else ({} if same_time else previous)
	var elapsed: float = maxf(0.0, now - float(earlier.get("time", now)))
	for index: int in rows.size():
		var row: Dictionary = rows[index]
		var prior: Dictionary = earlier.teams[index] if not earlier.is_empty() and index < earlier.teams.size() else {}
		row.income_per_minute = (float(row.funds_earned) - float(prior.get("funds_earned", row.funds_earned))) * 60.0 / elapsed if elapsed > 0.0 else 0.0
		row.funds_spent_per_minute = (float(row.funds_spent) - float(prior.get("funds_spent", row.funds_spent))) * 60.0 / elapsed if elapsed > 0.0 else 0.0
		for pair: Array in [["peak_units", "alive_units"], ["peak_buildings", "building_total"], ["peak_infantry", "infantry_total"], ["peak_army_value", "army_value"]]:
			teams[index][pair[0]] = maxf(float(teams[index].get(pair[0], 0)), float(row[pair[1]]))
			row[pair[0]] = teams[index][pair[0]]
		for pair: Array in [["low_power_seconds_sampled", "low_power"], ["zero_funds_seconds_sampled", "funds_empty"]]:
			var total: float = float(prior.get(pair[0], 0)) + (elapsed if bool(prior.get(pair[1], false)) else 0.0)
			teams[index][pair[0]] = total
			row[pair[0]] = total
	var observation: Dictionary = {"time": now, "teams": rows, "ore_remaining": _ore_remaining(sim)}
	if same_time: history[history.size() - 1] = observation
	else: history.append(observation)
	if now + 0.000001 >= _next_sample_time:
		_next_sample_time = (floorf((now - history_since_time + 0.000001) / SAMPLE_INTERVAL) + 1.0) * SAMPLE_INTERVAL + history_since_time
	_finished = final_sample

func snapshot(sim) -> Dictionary:
	sample(sim, true)
	var eliminated: Array[int] = []
	for row: Dictionary in history.back().teams:
		if bool(row.get("eliminated", false)): eliminated.append(int(row.team))
	var winner_known: bool = not str(sim.result).is_empty() and (teams.size() == 2 or str(sim.result) == "win")
	var winners: Array[int] = []
	if winner_known and str(sim.result) != "draw": winners.append(0 if str(sim.result) == "win" else 1)
	return {"schema": "paper_front.match_statistics", "schema_version": SCHEMA_VERSION, "teams": history.back().teams.duplicate(true) if not history.is_empty() else [], "duration": float(sim.time), "result": str(sim.result), "map_mode": str(sim.map.get("mode", "")), "since_time": since_time, "history_complete": is_zero_approx(since_time),
		"history_since_time": history_since_time, "telemetry_history_complete": telemetry_history_complete, "sample_interval": SAMPLE_INTERVAL, "history_interval_seconds": SAMPLE_INTERVAL, "history": history.duplicate(true), "events": events.duplicate(true), "metadata": metadata.duplicate(true), "definitions": DEFINITIONS.duplicate(true), "finished": _finished, "winner_teams_known": winner_known, "winner_teams": winners, "eliminated_teams": eliminated}

func to_dict() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "teams": teams.duplicate(true), "initial_money": initial_money.duplicate(), "since_time": since_time, "history": history.duplicate(true), "events": events.duplicate(true), "metadata": metadata.duplicate(true), "history_since_time": history_since_time, "telemetry_history_complete": telemetry_history_complete, "next_sample_time": _next_sample_time, "finished": _finished}

func restore(value: Variant, sim) -> void:
	reset(sim.factions, sim.money, float(sim.time))
	if not value is Dictionary or not value.get("teams") is Array or not value.get("initial_money") is Array: return
	if value.teams.size() != sim.factions.size() or value.initial_money.size() != sim.factions.size(): return
	for index: int in teams.size():
		if not value.teams[index] is Dictionary: return
		teams[index].merge(value.teams[index].duplicate(true), true)
	initial_money = value.initial_money.duplicate()
	since_time = float(value.get("since_time", 0.0))
	# Legacy cumulative totals cannot reconstruct missing curves.
	if int(value.get("schema_version", 0)) < SCHEMA_VERSION: return
	if not value.get("history") is Array or not value.get("events") is Array: return
	if not _valid_history(value.history, teams.size(), float(sim.time)): return
	if not _valid_events(value.events, float(sim.time)): return
	var scope: Variant = value.get("history_since_time", sim.time)
	if not (scope is float or scope is int) or not is_finite(float(scope)) or float(scope) < 0 or float(scope) > float(sim.time): return
	history.assign(value.history.duplicate(true))
	events.assign(value.events.duplicate(true))
	metadata = value.get("metadata", {}).duplicate(true) if value.get("metadata", {}) is Dictionary else {}
	history_since_time = float(value.get("history_since_time", sim.time))
	telemetry_history_complete = bool(value.get("telemetry_history_complete", false)) and not history.is_empty() and is_zero_approx(float(history[0].time))
	_next_sample_time = float(value.get("next_sample_time", sim.time))
	_finished = bool(value.get("finished", false))

func _current_rows(sim) -> Array[Dictionary]:
	var rows: Array[Dictionary] = teams.duplicate(true)
	for index: int in rows.size():
		var row: Dictionary = rows[index]
		row.merge({"team": index, "money_remaining": float(sim.money[index]), "alive_units": 0, "alive_buildings": 0, "building_total": 0, "victory_building_total": 0, "infantry_total": 0, "structures_complete": 0, "structures_under_construction": 0, "army_value": 0.0, "building_value": 0.0, "units_by_spec": {}, "buildings_by_spec": {}, "unit_categories": {"infantry": 0, "vehicle": 0, "air": 0, "naval": 0}, "harvesters": 0, "idle_harvesters": 0, "unit_queue_total": 0, "wounded_units": 0}, true)
		row.funds_spent = maxf(0, float(initial_money[index]) + float(row.funds_earned) + float(row.sales_income) - float(sim.money[index]))
		row.funds_spent_kind = "net investment after refunds"
		row.funds_empty = float(sim.money[index]) < 1.0
		var power: Vector2 = sim.power(index)
		row.power_generated = power.x
		row.power_consumed = power.y
		row.low_power = power.x + 0.000001 < power.y
	for entity: Dictionary in sim.entities.values():
		var owner: int = int(entity.get("team", -1))
		if owner < 0 or owner >= rows.size() or float(entity.get("hp", 0)) <= 0: continue
		var row: Dictionary = rows[owner]
		var spec: String = str(entity.spec)
		var info: Dictionary = sim.data_for(spec)
		var cost: float = maxf(0, float(info.get("cost", 0)))
		if entity.kind == "building":
			row.building_total += 1
			if sim._is_victory_building(entity): row.victory_building_total += 1
			row.building_value += cost
			if not RailNetwork.is_rail(info): row.alive_buildings += 1
			_increment(row.buildings_by_spec, spec)
			var incomplete: bool = entity.has("construction") or float(entity.get("construct_remaining", 0)) > 0.0
			row["structures_under_construction" if incomplete else "structures_complete"] += 1
			row.unit_queue_total += entity.get("queue", []).size()
			if not incomplete and sim.building_low_power(entity): row.low_power = true
		else:
			row.alive_units += 1
			row.army_value += cost
			_increment(row.units_by_spec, spec)
			var domain: String = str(info.get("domain", "ground"))
			var category: String = "air" if domain == "air" else ("naval" if domain == "naval" else ("infantry" if _is_infantry(info) else "vehicle"))
			row.unit_categories[category] += 1
			if category == "infantry": row.infantry_total += 1
			if float(entity.hp) < float(sim.max_hp(entity)): row.wounded_units += 1
			if str(info.get("role", "")) == "harvester" or spec.ends_with("_harvester"):
				row.harvesters += 1
				if entity.get("commands", []).is_empty(): row.idle_harvesters += 1
	for row: Dictionary in rows: row.eliminated = int(row.victory_building_total) == 0
	return rows

func _metadata_for(sim) -> void:
	if not metadata.is_empty():
		if not metadata.has("rules_snapshot"): metadata.rules_snapshot = sim.rules.duplicate(true)
		return
	metadata = {"map_mode": str(sim.map.get("mode", "")), "map_seed": sim.map.get("seed", 0), "map_width": sim.map.get("width", sim.map.get("size", 0)), "map_height": sim.map.get("height", sim.map.get("size", 0)), "map_starts": sim.map.get("starts", []).duplicate(true), "factions": sim.factions.duplicate(), "match_options": sim.match_options.duplicate(true), "initial_money": initial_money.duplicate(), "rules_sha256": JSON.stringify(sim.rules).sha256_text(), "rules_snapshot": sim.rules.duplicate(true), "godot_version": Engine.get_version_info().get("string", ""), "simulation_only_compatible": true, "replay_included": false}
	for field: String in ["symmetry", "symmetric", "symmetry_mode", "profile_id", "profile", "layout", "design_version", "symmetric_layout", "developer_layout"]:
		if sim.map.has(field):
			var value: Variant = sim.map[field]
			metadata[field] = value.duplicate(true) if value is Array or value is Dictionary else value

func _by_spec(team: int, field: String, spec: String) -> void:
	if team < 0 or team >= teams.size() or spec.is_empty(): return
	if not teams[team].get(field) is Dictionary: teams[team][field] = {}
	_increment(teams[team][field], spec)

static func _increment(counts: Dictionary, spec: String) -> void:
	counts[spec] = int(counts.get(spec, 0)) + 1

static func _is_infantry(info: Dictionary) -> bool:
	return str(info.get("domain", "ground")) == "ground" and str(info.get("armor_class", "infantry" if bool(info.get("crushable", false)) else "armored")) == "infantry"

static func _ore_remaining(sim) -> float:
	var remaining := 0.0
	for mine: Dictionary in sim.mines: remaining += maxf(0.0, float(mine.get("amount", 0)))
	return remaining

static func _valid_history(value: Array, owner_count: int, end_time: float) -> bool:
	var prior := -1.0
	for item: Variant in value:
		if not item is Dictionary or not (item.get("time") is float or item.get("time") is int) or not item.get("teams") is Array: return false
		var at_time: float = float(item.time)
		if not is_finite(at_time) or at_time < 0 or at_time < prior or at_time > end_time + 0.000001 or item.teams.size() != owner_count: return false
		for row: Variant in item.teams:
			if not row is Dictionary: return false
			for field: String in ["money_remaining", "funds_earned", "funds_spent", "building_total", "infantry_total", "alive_units", "alive_buildings"]:
				var amount: Variant = row.get(field)
				if not (amount is float or amount is int) or not is_finite(float(amount)) or float(amount) < 0: return false
		prior = at_time
	return true

static func _valid_events(value: Array, end_time: float) -> bool:
	var prior := -1.0
	for entry: Variant in value:
		if not entry is Dictionary or not entry.get("kind") is String: return false
		var time: Variant = entry.get("time")
		if not (time is float or time is int) or not is_finite(float(time)) or float(time) < 0 or float(time) < prior or float(time) > end_time + 0.000001: return false
		prior = float(time)
	return true
