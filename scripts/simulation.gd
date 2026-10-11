class_name WarSimulation
extends RefCounted

# One simulation is shared by every map, the player, the AI, and rule tests.
const SAVE_VERSION := 1
const BuildingOrientation = preload("res://scripts/building_orientation.gd")
const RailNetwork = preload("res://scripts/rail_network.gd")
const ResponsiveNavigation = preload("res://scripts/responsive_navigation.gd")
var _rail_network = RailNetwork.new()
const SaveValidator = preload("res://scripts/sim_save_validator.gd")
const Transport = preload("res://scripts/unit_transport.gd")
const AircraftOperations = preload("res://scripts/aircraft_operations.gd")
const AirNavigation = preload("res://scripts/air_navigation.gd")
const Construction = preload("res://scripts/outpost_construction.gd")
const FieldConstruction = preload("res://scripts/field_construction.gd")
const MiningDrills = preload("res://scripts/mining_drills.gd")
const BeamWeapons = preload("res://scripts/beam_weapons.gd")
const ZeppelinWeapons = preload("res://scripts/zeppelin_weapons.gd")
const ProductionLifecycle = preload("res://scripts/production_lifecycle.gd")
const ProductionClearance = preload("res://scripts/production_clearance.gd")
const InfantrySquads = preload("res://scripts/infantry_squads.gd")
const RefineryDocking = preload("res://scripts/refinery_docking.gd")
const RepairDepot=preload("res://scripts/repair_depot.gd")
const BuildingConstruction = preload("res://scripts/building_construction.gd")
const TechAvailability = preload("res://scripts/tech_availability.gd")
const FactionSupport = preload("res://scripts/faction_support.gd")
const FactionTraits = preload("res://scripts/faction_traits.gd")
const LocalPower = preload("res://scripts/local_power.gd")
const TeamVision = preload("res://scripts/team_vision.gd")
const NavalOperations = preload("res://scripts/naval_operations.gd")
const AIController = preload("res://scripts/ai_controller.gd")
const HeroRules = preload("res://scripts/hero_rules.gd")
const Veterancy=preload("res://scripts/veterancy.gd")
const GarrisonOperations=preload("res://scripts/garrison_operations.gd")
const AirNavalExpansion=preload("res://scripts/air_naval_expansion.gd")
const ArmorCombat = preload("res://scripts/armor_combat.gd")
const DeveloperTools = preload("res://scripts/developer_tools.gd")
const UniqueUnitRules = preload("res://scripts/unique_unit_rules.gd")
const CampaignController = preload("res://scripts/campaign_controller.gd")
var _designation_bonuses: Dictionary = {}
const BRIDGE_TARGET_BASE := -1000
const RUIN_TARGET_BASE := -100000
const MINE_HALF := Vector2(0.55, 0.55)
var ruins: Array = []
var _ruin_spatial: Dictionary = {}
var _mine_spatial: Dictionary = {}
var _mine_spatial_count: int = -1
var _base_cache_dirty: bool = true
var _power_cache: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var _role_cache: Array = [{}, {}]
var _vision_cache: Array[float] = [0.0, 0.0]
var _max_entity_extent: float = 1.0
var _max_ground_radius: float = 1.0
const RUIN_GEOMETRY_CHUNK_SIZE: int = 256
var _ruin_geometry_chunks: Array = []
var _ruin_geometry_dirty: Dictionary = {}
var _spec_cache: Dictionary = {}
var _air_specs: Dictionary = {}
var _naval_specs: Dictionary = {}
var _naval_navigation: RefCounted
var _goal_standing_cache: Dictionary = {}
var _static_geometry_revision: int = 0
var _airfield_counts: Dictionary = {}
var _airfield_counts_dirty: bool = true
var _contact_indices: Dictionary = {}
var _contact_ids: PackedInt64Array = PackedInt64Array()
var _contact_positions: PackedVector2Array = PackedVector2Array()
var _contact_teams: PackedInt32Array = PackedInt32Array()
var _contact_domains: PackedByteArray = PackedByteArray()
var _contact_visibility: PackedByteArray = PackedByteArray()
var _contact_spatial: Dictionary = {}
var _contacts_used: int = 0
var _weapon_target_masks: Dictionary = {}
var native_kernels_enabled: bool = OS.get_environment("PAPER_FRONT_DISABLE_NATIVE") != "1"
var native_unit_dispatch_enabled: bool = OS.get_environment("PAPER_FRONT_SCRIPT_UNITS") != "1"
var native_geometry_enabled: bool = OS.get_environment("PAPER_FRONT_SCRIPT_GEOMETRY") != "1"
var native_movement_enabled: bool = OS.get_environment("PAPER_FRONT_SCRIPT_MOVEMENT") != "1"
var responsive_navigation_enabled: bool = true
var crowd_overlap_enabled: bool = true
# Explicit diagnostic instrumentation; required collision queries retain their
# original call sites and are never skipped because a local probe budget ran out.
var geometry_profiling_enabled: bool = false
var _geometry_queries: int = 0
var _geometry_us: int = 0
var _geometry_rectangles: int = 0
var _native_geometry_ready: bool = false
var _kernels: RefCounted = ClassDB.instantiate("PaperFrontKernels") if ClassDB.class_exists("PaperFrontKernels") else null
var _terrain_nav_ids: PackedInt64Array = PackedInt64Array()
var _terrain_nav_edges: PackedInt64Array = PackedInt64Array()
var _terrain_mask_candidates: Array[int] = []
var _terrain_nav_extra_positions: Dictionary = {}
var _terrain_nav_extra_cells: Dictionary = {}
var _nav_detail_rectangles: Dictionary = {}
const NAV_EDGE_DIRECTIONS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1)]
# Bounded deterministic planner work; economy/combat/time still run every tick.
const PATH_PLANS_PER_TICK := 32
const PATH_SYNC_PLANS_PER_TICK := 2 # Deterministic rule fixtures still bound synchronous AStar work.
const PATH_IN_FLIGHT := 32
const PATH_ADMIN_BUDGET_US := 750
const LOCAL_NAV_BUDGET_US := 1000
const AVOIDANCE_PROBES_PER_TICK := 96
const YIELD_REQUESTS_PER_TICK := 3
var _local_nav_us:int=0
var _avoidance_probes:int=0
var _yield_requests:int=0
var synchronous_path_tests: bool = false # Deterministic rule fixtures and the logic-only runner use this.
const PATH_WORKER=preload("res://scripts/path_worker_pool.gd")
var _path_worker
var _path_requests: Dictionary = {}
var _path_revision: int = 0
var _path_token: int = 0
var _path_in_flight: int = 0
var _path_geometry: Dictionary = {}
var _native_masks_dirty: bool = false
var navigation_stats: Dictionary = {"submitted":0,"completed":0,"discarded":0,"queued":0,"max_queued":0,"in_flight":0,"max_in_flight":0,"main_us":0,"max_main_us":0,"max_worker_us":0}

const CLEARANCE_DIRECTIONS: Array[Vector2] = [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN, Vector2(0.707, 0.707), Vector2(-0.707, 0.707), Vector2(0.707, -0.707), Vector2(-0.707, -0.707)]
var startup_profile:Dictionary={}
var map: Dictionary = {}
var map_generation_config: Dictionary = {}
var rules: Dictionary = {}
var factions: Array[String] = ["rivet", "kestrel"]
var money: Array[float] = [0.0, 0.0]
var time: float = 0.0
var result: String = ""
var campaign_controller: RefCounted = null
var entities: Dictionary = {}
var projectiles: Array = []
var mines: Array = []
var bridges: Array = []
var building_orders: Array = [{}, {}]
var defense_orders: Array = [{}, {}]
var notices: Array[String] = []
var events: Array[Dictionary] = []
var ai_enabled: bool = true
var ai_state: Array = []
var independent_ai: RefCounted = null
var match_options: Dictionary = {}
var vision_enabled: bool = false
var team_vision: Dictionary = {"last_known": []}
var visual_memory: Dictionary = {}
var _vision_observers: Array = []
var _vision_next_refresh: float = 0.0
var _next_id: int = 1
var _nav: AStar2D = AStar2D.new()
var _nav_dirty: bool = true
var _spatial: Dictionary = {}
var _neighbor_cache: Dictionary = {}
var _ground_motion_spatial: Dictionary = {}
var _team_spatial: Array = [{}, {}]
var _combat_spatial: Dictionary = {}
var _damage: Dictionary = {}
var _damage_causes: Dictionary = {}
var statistics = preload("res://scripts/match_statistics.gd").new()
var _damage_voice_next: Dictionary = {}
var _execute_buildings: Dictionary = {}
var _crush_targets: Dictionary = {}
var _building_entities: Array = []
var _wide_masks: Dictionary = {}
var _terrain_masks: Dictionary = {}
var _nav_disabled: Array[int] = []
var _nav_initialized: bool = false
var _flat_safe: PackedByteArray = PackedByteArray()
var _flat_wide_safe: PackedByteArray = PackedByteArray()
var _size: int = 0
var _building_spatial: Dictionary = {}
var profile_enabled: bool = false
var profile: Dictionary = {}
var _ai_clock: float = 0.0
var _ai_attack_clock: float = 0.0
var _low_power: Array[bool] = [false, false]
var _power_details: Array[Dictionary] = []
var _bridge_repairers: Dictionary = {}
var _field_repairers: Dictionary = {}
var _mine_tick_budget: Dictionary = {}
var _nav_regions: Array[Rect2] = []
var _in_step: bool = false
var _path_plans_remaining: int = PATH_PLANS_PER_TICK
var _planning_deferred_ids: Dictionary = {}
var _planning_queue: Array[int] = []
var _planning_requested_ids: Dictionary = {}
var _plan_was_deferred: bool = false
var _planning_max_wait: float = 0.0
var _player_navigation_ids: Dictionary = {}
var _navigation_command_until: Dictionary = {}
var navigation_priority_grants := 0
var navigation_vehicle_yields := 0
var navigation_pursuit_refreshes := 0
var _step_delta: float = 0.0

func _notification(what: int) -> void:
	if what==NOTIFICATION_PREDELETE and _path_worker!=null:_path_worker.close()

func setup(config: Dictionary, mode: String, seed_value: int, player_faction: String = "rivet", enable_ai: bool = true, options: Dictionary = {}) -> void:
	if mode == "campaign":
		setup_campaign(config, seed_value)
		return
	var ids: Array[String] = [player_faction, "kestrel" if player_faction == "rivet" else "rivet"]
	var slots: Array = options.get("slots", [])
	if not slots.is_empty():
		ids.clear()
		for slot in slots.slice(0, mini(4, slots.size())): ids.append(str(slot.get("faction", player_faction)))
		if ids.size() < 2: ids.append("kestrel" if ids[0] == "rivet" else "rivet")
	setup_multiteam(config, mode, seed_value, ids, enable_ai, [], Callable(), options)

func setup_with_progress(config: Dictionary, mode: String, seed_value: int, player_faction: String, enable_ai: bool, progress: Callable, options: Dictionary = {}) -> void:
	if mode == "campaign":
		await setup_multiteam(config, mode, seed_value, ["kestrel", "rivet"], true, [], progress, {"players":2, "modern":true, "vision_enabled":true})
		return
	var ids: Array[String] = [player_faction, "kestrel" if player_faction == "rivet" else "rivet"]
	var slots: Array = options.get("slots", [])
	if not slots.is_empty():
		ids.clear()
		for slot in slots.slice(0, mini(4, slots.size())): ids.append(str(slot.get("faction", player_faction)))
		if ids.size() < 2: ids.append("kestrel" if ids[0] == "rivet" else "rivet")
	await setup_multiteam(config, mode, seed_value, ids, enable_ai, [], progress, options)

func setup_campaign(config: Dictionary, seed_value: int = 1) -> void:
	setup_multiteam(config, "campaign", seed_value, ["kestrel", "rivet"], true, [], Callable(), {"players":2, "modern":true, "vision_enabled":true})

# Existing callers execute synchronously; only the loading path supplies a callback that yields.
func setup_multiteam(config: Dictionary, mode: String, seed_value: int, faction_ids: Array[String], enable_ai: bool = false, hq_positions: Array[Vector2] = [], progress: Callable = Callable(), options: Dictionary = {}) -> void:
	var setup_started:int=Time.get_ticks_usec()
	rules = config.duplicate(true)
	factions.assign(faction_ids)
	match_options = options.duplicate(true)
	match_options.players = factions.size()
	match_options.modern = mode in ["forest", "desert", "snow", "city", "random_city", "islands", "symmetric", "campaign"]
	vision_enabled = bool(match_options.get("vision_enabled", match_options.modern))
	match_options.vision_enabled = vision_enabled
	if not match_options.has("slots") or match_options.slots.size() != factions.size():
		match_options.slots = []
		for team in range(factions.size()): match_options.slots.append({"faction": factions[team], "control": "ai" if enable_ai and team > 0 else "human", "difficulty": "normal"})
	elif bool(match_options.modern) or bool(match_options.get("explicit_controls",false)):
		for team in range(factions.size()):
			var slot: Dictionary=match_options.slots[team]
			slot.faction=factions[team]
			if bool(match_options.get("explicit_controls",false)):
				slot.control="ai" if enable_ai and str(slot.get("control","human"))=="ai" and (team>0 or bool(match_options.get("allow_player_ai",false))) else "human"
			else:
				slot.control="human" if team==0 or not enable_ai else "ai"
			if slot.get("difficulty") not in ["easy","normal","hard"]:slot.difficulty="normal"
	_resize_team_caches()
	if progress.is_valid(): await progress.call(0.05, "生成地图")
	var map_started:int=Time.get_ticks_usec()
	var generation_options: Dictionary=map_generation_config.duplicate(true)
	generation_options.players=factions.size()
	map = MapData.generate(mode,seed_value,generation_options)
	var map_finished:int=Time.get_ticks_usec()
	if progress.is_valid(): await progress.call(0.32, "整理地形与资源")
	ruins = map.get("ruins",[]).duplicate(true)
	_refresh_ruin_spatial()
	if progress.is_valid():
		await _prepare_terrain_cache(progress)
	else:
		_prepare_terrain_cache()
	if progress.is_valid(): await progress.call(0.42, "部署基地与资源")
	money.resize(factions.size())
	money.fill(float(_eco("initial_money", 4000)))
	statistics.reset(factions,money)
	time = 0.0
	result = ""
	campaign_controller = null
	entities.clear()
	_damage_voice_next.clear()
	_ground_motion_spatial.clear()
	visual_memory = {}
	_designation_bonuses.clear()
	_max_entity_extent = 1.0
	_max_ground_radius = 1.0
	_building_entities.clear()
	_building_spatial.clear()
	_wide_masks.clear()
	_terrain_masks.clear()
	_nav_disabled.clear()
	_nav_initialized = false
	_nav_regions.clear()
	_in_step = false
	_path_plans_remaining = PATH_SYNC_PLANS_PER_TICK if synchronous_path_tests else PATH_PLANS_PER_TICK
	_planning_max_wait = 0.0
	_planning_deferred_ids.clear()
	_planning_queue.clear()
	_planning_requested_ids.clear()
	projectiles.clear()
	mines.clear()
	_mine_tick_budget.clear()
	bridges.clear()
	building_orders.resize(factions.size())
	defense_orders.resize(factions.size())
	for team in range(factions.size()):
		building_orders[team] = {}
		defense_orders[team] = {}
	notices.clear()
	events.clear()
	_next_id = 1
	_ai_clock = 0.0
	_ai_attack_clock = 0.0
	_low_power.resize(factions.size())
	_low_power.fill(false)
	ai_enabled = enable_ai
	independent_ai = null
	AIController.initialize(self)
	for raw in map.get("mines", []):
		var capacity: float = float(_eco("ore_capacity", raw.get("capacity", 3000)))
		raw.capacity = capacity
		mines.append({"pos": _vec(raw.pos), "amount": capacity, "capacity": capacity, "miner": -1})
	for raw in map.get("bridges", []):
		bridges.append({"id": int(raw.id), "bounds": raw.bounds.duplicate(), "heads": raw.heads.duplicate(), "hp": float(_eco("bridge_hp", 1200)), "repair_progress": 0.0, "alive": true, "naval_clearance":float(raw.get("naval_clearance",0.0))})
	if mode == "campaign":
		for bridge in bridges:
			if int(bridge.id) == 1:
				bridge.hp = 0.0
				bridge.alive = false
	for team in range(factions.size()):
		var pos: Vector2 = hq_positions[team] if team < hq_positions.size() else _team_start(team)
		_spawn(team, factions[team] + "_hq", pos, true)
	_nav_dirty = true
	if progress.is_valid(): await progress.call(0.52, "建立导航网格")
	var nav_started:int=Time.get_ticks_usec()
	if progress.is_valid():
		await _rebuild_nav(progress)
	else:
		_rebuild_nav()
	var nav_finished:int=Time.get_ticks_usec()
	if progress.is_valid(): await progress.call(0.96, "整理战场数据")
	_rebuild_spatial()
	TeamVision.initialize(self)
	NavalOperations.initialize(self)
	if mode == "campaign":
		_setup_campaign_scenario()
	statistics.begin(self)
	startup_profile={"rules_and_owners_ms":(map_started-setup_started)/1000.0,"map_generation_ms":(map_finished-map_started)/1000.0,"simulation_data_ms":(nav_started-map_finished)/1000.0,"navigation_ms":(nav_finished-nav_started)/1000.0,"spatial_ms":(Time.get_ticks_usec()-nav_finished)/1000.0,"total_ms":(Time.get_ticks_usec()-setup_started)/1000.0}
	if progress.is_valid(): await progress.call(1.0, "战场准备完成")

func _setup_campaign_scenario() -> void:
	# These are the sole scripted starting forces. Subsequent AI production pays
	# ordinary costs and observes the same facility and prerequisite checks.
	for deployment in [
		{"team":0, "spec":"kestrel_engineer", "pos":Vector2(66, 170)},
		{"team":0, "spec":"kestrel_scout", "pos":Vector2(66, 174)},
		{"team":0, "spec":"kestrel_harvester", "pos":Vector2(59, 175)},
		{"team":1, "spec":"rivet_rifle", "pos":Vector2(259, 170)},
		{"team":1, "spec":"rivet_scout", "pos":Vector2(259, 174)},
	]:
		debug_spawn_squad(int(deployment.team), str(deployment.spec), deployment.pos)
	campaign_controller = CampaignController.new()
	campaign_controller.setup(self)
	_rebuild_spatial()
	TeamVision.refresh(self)

func _resize_team_caches() -> void:
	_team_spatial.resize(factions.size())
	_role_cache.resize(factions.size())
	_power_cache.resize(factions.size())
	_power_cache.fill(Vector2.ZERO)
	_power_details.resize(factions.size())
	_vision_cache.resize(factions.size())
	_vision_cache.fill(0.0)
	for team in range(factions.size()):
		_team_spatial[team] = {}
		_role_cache[team] = {}
	_combat_spatial.clear()
	_airfield_counts_dirty = true
	_invalidate_base_cache()

func _team_start(team: int) -> Vector2:
	for building in _building_entities:
		if int(building.team) == team and data_for(building.spec).get("role", "") == "hq": return building.pos
	if team < map.get("starts", []).size(): return _vec(map.starts[team])
	var angle: float = TAU * float(team) / maxi(1, factions.size())
	return Vector2(float(map.size) * .5, float(map.size) * .5) + Vector2.from_angle(angle) * float(map.size) * .3

func data_for(spec: String) -> Dictionary:
	if _in_step and not _spec_cache.is_empty(): return _spec_cache.get(spec, {})
	if rules.get("units", {}).has(spec):
		return rules.units[spec]
	return rules.get("buildings", {}).get(spec, {})

func entity_visible_to(team: int, id: int) -> bool:
	if not entities.has(id) or team < 0 or team >= factions.size(): return false
	if not vision_enabled: return true
	return (int(entities[id].get("visible_to", 0)) & (1 << team)) != 0

func position_visible_to(team: int, pos: Vector2, domain: String = "ground") -> bool:
	return TeamVision.position_visible(self, team, pos, domain)

func last_known_enemy(team: int, id: int) -> Dictionary:
	if team < 0 or team >= factions.size() or not vision_enabled: return {}
	if entity_visible_to(team, id):
		var e: Dictionary = entities[id]
		return {"pos":e.pos, "seen_at":time, "spec":e.spec, "kind":e.kind, "domain":str(data_for(e.spec).get("domain", "ground"))}
	return team_vision.get("last_known", [])[team].get(id, {}).duplicate(true)

func _eco(key: String, fallback: Variant) -> Variant:
	return rules.get("economy", {}).get(key, fallback)

func _vec(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	return Vector2(float(value[0]), float(value[1]))

func power(team: int) -> Vector2:
	_ensure_base_cache()
	return _power_cache[team]

func local_power_summary(team: int) -> Dictionary:
	_ensure_base_cache()
	return _power_details[team]

func building_low_power(e: Dictionary) -> bool:
	_ensure_base_cache()
	var team: int = int(e.team)
	if LocalPower.is_locally_powered(self, e, _power_details[team]): return false
	var energy: Vector2 = power(team)
	return energy.y > energy.x

func _invalidate_base_cache() -> void:
	_base_cache_dirty = true

func _ensure_base_cache() -> void:
	# Outside a tick, callers may be editing a development fixture directly.
	# During a tick, normal lifecycle hooks invalidate this derived summary.
	if not _base_cache_dirty and _in_step: return
	_power_cache.resize(factions.size())
	_power_cache.fill(Vector2.ZERO)
	_power_details.resize(factions.size())
	_role_cache.resize(factions.size())
	_vision_cache.resize(factions.size())
	_vision_cache.fill(0.0)
	for team in range(factions.size()): _role_cache[team] = {}
	for e in _building_entities:
		if float(e.hp) <= 0.0 or float(e.construct_remaining) > 0.0: continue
		var team: int = int(e.team)
		var info: Dictionary = data_for(e.spec)
		var value: float = float(info.get("power", 0))
		if float(e.get("emp_until", 0.0)) <= time:
			if value > 0.0: _power_cache[team].x += value
			else: _power_cache[team].y -= value
		_role_cache[team][str(e.spec)] = true
		_role_cache[team][str(info.get("role", ""))] = true
		for role in info.get("prerequisite_roles", []): _role_cache[team][str(role)] = true
		_vision_cache[team] = maxf(_vision_cache[team], float(info.get("vision_bonus", 0.0)))
	for team in range(factions.size()):
		_power_details[team] = LocalPower.summary(self, team)
		_power_cache[team] = _power_details[team].display
	_base_cache_dirty = false

func counts(team: int) -> Vector2i:
	var answer := Vector2i.ZERO
	for e in entities.values():
		if int(e.team) == team and float(e.hp) > 0.0:
			if e.kind == "unit":
				answer.x += 1
			else:
				answer.y += 1
	return answer

func _has_role(team: int, role: String) -> bool:
	_ensure_base_cache()
	return _role_cache[team].has(role)

func _has_construction_base(team: int) -> bool:
	return _has_role(team, "hq") or _has_role(team, "outpost")

func _is_air(e: Dictionary) -> bool:
	if _in_step and not _spec_cache.is_empty(): return e.get("kind", "unit") == "unit" and _air_specs.has(str(e.spec))
	return e.get("kind", "unit") == "unit" and data_for(str(e.spec)).get("domain", "ground") == "air"

func _is_naval(e: Dictionary) -> bool:
	if e.get("kind", "unit") != "unit": return false
	if _in_step and not _spec_cache.is_empty(): return _naval_specs.has(str(e.spec))
	return data_for(str(e.spec)).get("domain", "ground") == "naval"

func _target_domain(e: Dictionary) -> String:
	if bool(data_for(e.spec).get("amphibious",false)) and _terrain(e.pos)!=MapData.WATER:return "ground"
	if _is_air(e): return "air"
	if _is_naval(e): return "naval"
	return "ground"

func _acquisition_range(e: Dictionary, base_range: float) -> float:
	if _low_power[int(e.team)]: return base_range
	_ensure_base_cache()
	return base_range + _vision_cache[int(e.team)]

func _requirements(team: int, spec: Dictionary) -> String:
	var missing: Array[String] = TechAvailability.missing_requirements(self, team, spec)
	return "" if missing.is_empty() else "缺少前置设施与科技：" + "、".join(missing)

func availability(team: int, spec: String, builder: int = -1, producer: int = -1) -> String:
	return TechAvailability.reason(self, team, spec, builder, producer)

func squad_size(spec: String) -> int:
	return InfantrySquads.size(data_for(spec))

func production_cost(spec: String) -> float:
	return InfantrySquads.cost(data_for(spec))

func production_time(spec: String) -> float:
	return InfantrySquads.training_time(data_for(spec))

func squad_members(id: int, available_only: bool = false) -> Array:
	return InfantrySquads.members(self, id, available_only)

func squad_leader(id: int) -> int:
	var members: Array = squad_members(id)
	return int(members[0]) if not members.is_empty() else -1

func expand_squad_ids(ids: Array, available_only: bool = false) -> Array:
	return InfantrySquads.expand(self, ids, available_only)

func selection_ids(ids: Array, available_only: bool = true) -> Array:
	return InfantrySquads.representatives(self, ids, available_only)

func order_for_team(team: int, channel: String = "normal") -> Dictionary:
	return BuildingConstruction.order_for(self, team, channel)

func building_spec(team: int, role: String) -> String:
	return TechAvailability.building_id(self, team, role)

func construction_channel(spec: String) -> String:
	return BuildingConstruction.channel_for(data_for(spec))

func construction_radius(spec: String) -> float:
	return BuildingConstruction.radius_for(self, data_for(spec)) if rules.buildings.has(spec) else 0.0

func construction_zones(team: int) -> Array[Dictionary]:
	return BuildingConstruction.zones(self, team)

func in_construction_range(team: int, pos: Vector2) -> bool:
	return BuildingConstruction.covers(self, team, pos)

func _effective_construction_channel(team: int, channel: String) -> String:
	if channel != "auto": return channel
	if team >= 0 and team < factions.size() and building_orders[team].is_empty() and not defense_orders[team].is_empty(): return "defense"
	return "normal"

func _builder_valid(team: int, builder: int) -> bool:
	return entities.has(builder) and int(entities[builder].team) == team and entities[builder].kind == "unit" and float(entities[builder].hp) > 0.0 and not Transport.is_loaded(entities[builder]) and data_for(entities[builder].spec).get("art", "") == "engineer"

func build(team: int, spec: String, builder: int = -1) -> String:
	var problem: String = availability(team, spec, builder)
	if not problem.is_empty(): return problem
	var info: Dictionary = data_for(spec)
	var channel: String = BuildingConstruction.channel_for(info)
	if builder >= 0:
		_set_building_order(team, channel, {"spec": spec, "remaining": 0.0, "total": float(info.build_time), "cost": 0.0, "ready": true, "progress": 0.0, "builder": builder})
		return ""
	var cost: float = float(info.cost)
	money[team] -= cost
	_set_building_order(team, channel, {"spec": spec, "remaining": float(info.build_time), "total": float(info.build_time), "cost": cost, "ready": false, "progress": 0.0})
	return ""

func _set_building_order(team: int, channel: String, order: Dictionary) -> void:
	if channel == "defense": defense_orders[team] = order
	else: building_orders[team] = order

func snap_build_position(team: int, pos: Vector2, channel: String = "auto") -> Vector2:
	channel = _effective_construction_channel(team, channel)
	if channel not in ["normal", "defense"]: return pos
	if order_for_team(team, channel).is_empty():
		return pos
	var spec: Dictionary = data_for(order_for_team(team, channel).spec)
	if spec.get("role", "") == "drill":
		var index: int = MiningDrills.mine_index(self, pos)
		return mines[index].pos if index >= 0 else pos
	var half: float = float(spec.size) * 0.5
	return Vector2(roundf(pos.x - half) + half, roundf(pos.y - half) + half)

func defense_extension(team: int, pos: Vector2, channel: String = "auto") -> Array[Vector2]:
	channel = _effective_construction_channel(team, channel)
	if channel not in ["normal", "defense"]: return [pos]
	pos = snap_build_position(team, pos, channel)
	var points: Array[Vector2] = [pos]
	if order_for_team(team, channel).is_empty() or int(order_for_team(team, channel).get("builder", -1)) >= 0 or data_for(order_for_team(team, channel).spec).get("role", "") not in ["wall", "barricade", "rail"]:
		return points
	var rail_order: bool = str(data_for(order_for_team(team,channel).spec).get("role","")) == "rail"
	var extension_direction: Vector2 = BuildingOrientation.offset(Vector2.RIGHT,BuildingOrientation.quarters(order_for_team(team,channel)))
	var nearest: Vector2 = Vector2.INF
	var distance: float = 7.0
	for e in _building_entities:
		if int(e.team) != team or float(e.construct_remaining) > 0 or data_for(e.spec).get("role", "") not in (["rail", "rail_junction"] if RailNetwork.is_rail(data_for(order_for_team(team, channel).spec)) else ["wall", "barricade"]):
			continue
		var offset: Vector2 = pos - e.pos
		var length: float = offset.length()
		if rail_order and (offset.dot(extension_direction) <= 0 or absf(offset.cross(extension_direction)) > .01): continue
		if (absf(offset.x) < .01 or absf(offset.y) < .01) and length >= 1 and length <= 6 and length < distance:
			nearest = e.pos
			distance = length
	if nearest.is_finite():
		points.clear()
		for i in range(1, roundi(distance) + 1):
			points.append(nearest + (pos - nearest).normalized() * i)
	return points

func placement_error(team: int, pos: Vector2, channel: String = "auto") -> String:
	channel = _effective_construction_channel(team, channel)
	if channel not in ["normal", "defense"]: return "无效建筑队列通道"
	var points: Array[Vector2] = defense_extension(team, pos, channel)
	var order: Dictionary = order_for_team(team, channel)
	if not order.is_empty() and RailNetwork.is_rail(data_for(order.spec)):
		var rail_error: String = _rail_network.batch_error(self, team, data_for(order.spec), points, int(order.get("rail_rotation", 0)))
		if not rail_error.is_empty(): return rail_error
	for point in points:
		var error: String = _placement_cell_error(team, point, channel)
		if not error.is_empty(): return error
	if points.size() > 1 and money[team] < (points.size() - 1) * float(data_for(order_for_team(team, channel).spec).cost):
		return "延伸段资金不足（每格单独计费）"
	return ""

func _placement_cell_error(team: int, pos: Vector2, channel: String = "auto") -> String:
	channel = _effective_construction_channel(team, channel)
	if channel not in ["normal", "defense"]: return "无效建筑队列通道"
	if result != "":
		return "对局已经结束"
	if order_for_team(team, channel).is_empty() or not bool(order_for_team(team, channel).get("ready", false)):
		return "建筑尚未就绪"
	var builder: int = int(order_for_team(team, channel).get("builder", -1))
	if builder >= 0 and not _builder_valid(team, builder):
		return "部署工程兵已不存在"
	if builder < 0 and not _has_construction_base(team):
		return "放置需要已完成的总部或前哨基地"
	pos = snap_build_position(team, pos, channel)
	var info: Dictionary = data_for(order_for_team(team, channel).spec)
	if info.get("role", "") == "hq" and not bool(info.get("rebuildable", false)): return "总部不能建造"
	if info.get("role", "") == "outpost" and builder < 0: return "分基地需要工程兵现场部署"
	return _building_site_error(team, info, pos, builder,BuildingOrientation.quarters(order_for_team(team,channel)))

func _building_site_error(team: int, info: Dictionary, pos: Vector2, builder: int = -1, rotation_quarters: int = -1) -> String:
	var turns: int = rotation_quarters if rotation_quarters >= 0 else (posmod(roundi(NavalOperations.shipyard_heading(self,pos)/90.0),4) if info.get("role","")=="shipyard" else 0)
	var exit_error: String = ProductionClearance.site_error(self, info, pos,turns)
	if not exit_error.is_empty(): return exit_error
	if info.get("role", "") == "drill": return MiningDrills.site_error(self, team, pos, builder)
	if RailNetwork.is_rail(info):
		var order: Dictionary = order_for_team(team, BuildingConstruction.channel_for(info))
		return _rail_network.site_error(self, team, info, pos, turns)
	if info.get("role", "") == "shipyard": return NavalOperations.shipyard_site_error(self, team, info, pos, builder,turns)
	var size: float = float(info.size)
	var half: float = size * 0.5
	var origin := Vector2i(roundi(pos.x - half), roundi(pos.y - half))
	var level: float = _height(pos)
	for z in range(origin.y, origin.y + int(size)):
		for x in range(origin.x, origin.x + int(size)):
			var point := Vector2(x + 0.5, z + 0.5)
			if not _in_bounds(point):
				return "建筑超出地图边界"
			var terrain: int = _terrain(point)
			if terrain == 1 or terrain == 2 or terrain == 4 or bridge_at(point) >= 0:
				return "不能跨水面、坡道、桥面或障碍建造"
			if absf(_height(point) - level) > 0.05:
				return "建筑必须位于同一平坦高度"
	for e in entities.values():
		if float(e.hp) <= 0.0 or int(e.id) == builder or Transport.is_loaded(e):
			continue
		if e.kind == "building":
			var other_half: float = float(data_for(e.spec).size) * 0.5
			if absf(e.pos.x - pos.x) < half + other_half and absf(e.pos.y - pos.y) < half + other_half:
				return "建筑占地与已有建筑重叠"
		elif not _is_air(e) and _circle_rect(e.pos, _radius(e), pos, Vector2(half, half)):
			return "单位占据建筑位置"
	for ruin in _nearby_ruins(pos, half):
		if float(ruin.hp)>0 and absf(ruin.pos.x-pos.x)<half+ruin.half.x and absf(ruin.pos.y-pos.y)<half+ruin.half.y:
			return "需要先摧毁此处的石墙或废墟"
	for ore in mines:
		if _circle_rect(ore.pos, 1.2, pos, Vector2(half, half)):
			return "不能覆盖矿点"
	if builder >= 0:
		if rules.factions.get(factions[team], {}).get("building_method", "") == "engineer" and info.get("role", "") not in ["barracks", "outpost"] and not bool(info.get("rebuildable", false)) and not in_construction_range(team, pos): return "超出基地兵营的建设范围；请先搭建新的基地兵营"
		return ""
	var covered: bool = in_construction_range(team, pos)
	if not covered and info.get("role", "") in ["wall", "barricade"]:
		for e in _building_entities:
			var offset: Vector2 = pos - e.pos
			if int(e.team) == team and float(e.construct_remaining) <= 0 and data_for(e.spec).get("role", "") in ["wall", "barricade"] and (absf(offset.x) < .01 or absf(offset.y) < .01) and offset.length() <= 6.0:
				covered = true
				break
	if not covered:
		return "超出己方已完成建筑的扩建范围"
	return ""

func place_building(team: int, pos: Vector2, channel: String = "auto") -> String:
	channel = _effective_construction_channel(team, channel)
	var problem: String = placement_error(team, pos, channel)
	if problem != "":
		return problem
	pos = snap_build_position(team, pos, channel)
	var spec: String = str(order_for_team(team, channel).spec)
	var rail_rotation: int = BuildingOrientation.quarters(order_for_team(team, channel))
	var builder: int = int(order_for_team(team, channel).get("builder", -1))
	if builder >= 0:
		var cost: float = float(order_for_team(team, channel).cost)
		_set_building_order(team, channel, {})
		issue([builder], "deploy_outpost", pos)
		entities[builder].commands.back().spec = spec
		entities[builder].commands.back().cost = cost
		entities[builder].commands.back().rotation_quarters = rail_rotation
		return ""
	var points: Array[Vector2] = defense_extension(team, pos, channel)
	money[team] -= (points.size() - 1) * float(data_for(spec).cost)
	_set_building_order(team, channel, {})
	for point in points:
		var id: int = _spawn(team, spec, point, false,rail_rotation)
		if RailNetwork.is_rail(data_for(spec)):
			entities[id].rail_rotation = rail_rotation
			_rail_network.rebuild(self)
		events.append({"kind": "build", "pos": point, "id": id, "team": team, "spec": spec, "entity_kind": "building"})
	_nav_dirty = true
	return ""

func capture_error(engineer_id: int, target_id: int) -> String:
	if result != "": return "对局已经结束"
	if not entities.has(engineer_id) or not _builder_valid(int(entities[engineer_id].team), engineer_id): return "占领需要工程兵"
	if not entities.has(target_id) or entities[target_id].kind != "building" or float(entities[target_id].hp) <= 0.0: return "只能占领敌方建筑"
	var target: Dictionary = entities[target_id]
	if target.team == entities[engineer_id].team: return "不能占领友方建筑"
	if float(target.construct_remaining) > 0.0: return "建筑尚未完成，无法占领"
	var role: String = str(data_for(target.spec).get("role", ""))
	if role in ["wall", "barricade", "rail", "rail_junction"]: return "围墙、拒马、铁路和岔道口不能占领"
	if role == "hq" and not bool(data_for(target.spec).get("rebuildable", false)):
		for building in _building_entities:
			if building.team == entities[engineer_id].team and float(building.hp) > 0.0 and data_for(building.spec).get("role", "") == "hq" and not bool(data_for(building.spec).get("rebuildable", false)): return "每个势力只能拥有一个总部"
	return ""

func cancel_build(team: int, channel: String = "auto") -> String:
	channel = _effective_construction_channel(team, channel)
	if channel not in ["normal", "defense"]: return "无效建筑队列通道"
	var order: Dictionary = order_for_team(team, channel)
	if order.is_empty(): return "没有建筑订单"
	var refund: float = BuildingConstruction.refund(order)
	money[team] += refund
	_set_building_order(team, channel, {})
	if refund <= 0.0 and not order.has("builder"):
		_notice("就绪建筑已完成建造，取消不退款")
	return ""

func produce(building_id: int, spec: String) -> String:
	if result != "":
		return "对局已经结束"
	if not entities.has(building_id) or not rules.get("units", {}).has(spec):
		return "无效生产订单"
	var e: Dictionary = entities[building_id]
	var info: Dictionary = data_for(spec)
	if e.kind != "building" or float(e.hp) <= 0.0 or float(e.construct_remaining) > 0.0:
		return "生产建筑尚未完成或已被摧毁"
	if info.get("faction", "") != factions[int(e.team)] or not TechAvailability.producer_matches(self, e, str(info.get("producer", ""))):
		return "该设施不能生产此单位"
	var problem: String = availability(int(e.team), spec, -1, building_id)
	if not problem.is_empty(): return problem
	var cost: float = production_cost(spec)
	var duration: float = production_time(spec)
	money[int(e.team)] -= cost
	e.queue.append({"spec": spec, "remaining": duration, "total": duration, "cost": cost, "started": false, "ready": false, "progress": 0.0, "squad_size": squad_size(spec), "spawned": 0, "squad_id": -1})
	return ""

func cancel_production(building_id: int, index: int) -> String:
	if not entities.has(building_id):
		return "生产建筑不存在"
	var e: Dictionary = entities[building_id]
	if index < 0 or index >= e.queue.size():
		return "队列位置无效"
	_refund_order(int(e.team), e.queue[index])
	e.queue.remove_at(index)
	return ""

func _refund_order(team: int, order: Dictionary) -> void:
	var refund: float = float(order.cost) * float(order.remaining) / maxf(float(order.total), 0.001)
	# Deployed members can never be refunded by cancelling their order.
	var count: int = maxi(1, int(order.get("squad_size", 1)))
	var unspawned: int = maxi(0, count - int(order.get("spawned", 0)))
	money[team] += minf(refund, float(order.cost) * float(unspawned) / count)

func sell(id: int, confirmed: bool = false) -> String:
	if result != "":
		return "对局已经结束"
	if not entities.has(id) or entities[id].kind != "building" or float(entities[id].hp) <= 0.0:
		return "只能出售存活建筑"
	var e: Dictionary = entities[id]
	if e.has("construction"): return "未完工建筑请使用拆除脚手架"
	if _is_victory_building(e) and not confirmed:
		var other_base: bool = false
		for building: Dictionary in _building_entities:
			if int(building.id) != id and int(building.team) == int(e.team) and _is_victory_building(building):
				other_base = true
				break
		if not other_base: return "CONFIRM_LAST_BUILDING"
	var sales_income: float=float(data_for(e.spec).cost) * float(_eco("sell_ratio", 0.5))
	money[int(e.team)] += sales_income
	statistics.add(int(e.team),"sales_income",sales_income)
	events.append({"kind": "sell", "pos": e.pos, "id": id,"spec":e.spec,"team":int(e.team),"entity_kind":"building"})
	_kill_entity(id, false)
	_check_result()
	return ""

func toggle_repair(id: int) -> void:
	if result == "" and entities.has(id) and entities[id].kind == "building":
		entities[id].repairing = not bool(entities[id].get("repairing", false))

func set_rally(id: int, pos: Vector2) -> void:
	if entities.has(id) and entities[id].kind == "building":
		entities[id].rally = pos

func board_error(passenger_id: int, carrier_id: int) -> String:
	return Transport.board_error(self, passenger_id, carrier_id)

func unload(carrier_id: int) -> String:
	if result != "": return "对局已经结束"
	return Transport.unload(self, carrier_id)

func resume_outpost_error(engineer_id: int, target_id: int) -> String:
	return Construction.resume_error(self, engineer_id, target_id)

func dismantle_outpost(id: int) -> String:
	return Construction.dismantle(self, id)

# UI selection affects navigation service, never ownership, costs or damage.
func _human_navigation_owner(id: int) -> bool:
	if not entities.has(id) or int(entities[id].team) != 0: return false
	var slots: Array = match_options.get("slots", [])
	return slots.is_empty() or str(slots[0].get("control", "human")) == "human"

func set_player_navigation_priority(ids: Array) -> void:
	_player_navigation_ids.clear()
	for raw: Variant in expand_squad_ids(ids, true):
		var id: int = int(raw)
		if _human_navigation_owner(id): _player_navigation_ids[id] = true
	if _path_worker != null and _path_worker.has_method("prioritize"):
		_path_worker.prioritize(_player_navigation_ids)

func _navigation_priority(id: int) -> int:
	if _human_navigation_owner(id):
		if _player_navigation_ids.has(id): return 3
		if time < float(_navigation_command_until.get(id, -1.0)): return 2
	return 1 if entities.has(id) and float(entities[id].get("planning_wait", 0.0)) > 4.0 else 0

func _navigation_queue_index() -> int:
	var best := 0
	var priority := -1
	for i in range(_planning_queue.size()):
		var value: int = _navigation_priority(_planning_queue[i])
		if value > priority: best = i; priority = value
	return best

func _complete_movement_yield(e: Dictionary) -> void:
	e.yield_goal=Vector2.INF; e.erase("yield_root")
	e.avoid_until=0.0;e.reversing=false
	var saved:Array=e.get("yield_saved_path",[])
	var valid:bool=false
	if int(e.get("yield_saved_revision",-1))==_static_geometry_revision:
		# Rejoin the farthest visible suffix rather than steering back to an
		# already-passed pre-yield waypoint in the middle of the queue.
		for index in range(saved.size()-1,-1,-1):
			if _yield_route_connector(e.pos,saved[index],_radius(e),int(e.id)):
				saved=saved.slice(index);valid=true;break
	if valid:
		e.path=saved; e.path_goal=e.get("yield_saved_goal",e.path_goal); e.path_wait=0.0
	else:
		e.path.clear(); e.path_goal=Vector2.INF; e.path_wait=0.0
	for key in ["yield_saved_path","yield_saved_goal","yield_saved_revision"]:e.erase(key)

func _yield_route_connector(start:Vector2,finish:Vector2,radius:float,id:int)->bool:
	# Rejoining a saved path is optional. Near water/cliff/blocked-terrain
	# corners the worker has stricter continuous terrain validation than the
	# legacy mover, so obtain a fresh worker connector instead of shortcutting
	# that corner with the mover's sampled standing test.
	if not _fast_flat(start,radius):return false
	var checks:int=maxi(1,ceili(start.distance_to(finish)/.4))
	for n in range(1,checks+1):
		if not _fast_flat(start.lerp(finish,float(n)/checks),radius):return false
	return _segment_static(start,finish,radius,id)

func _working_miner(e: Dictionary) -> bool:
	if e.get("kind", "") != "unit" or str(data_for(str(e.spec)).get("art", "")) != "harvester": return false
	if e.commands.is_empty(): return not bool(e.get("harvest_override", false))
	return str(e.commands[0].kind) in ["harvest", "return_miner"]

func _traffic_vehicle(e: Dictionary) -> bool:
	# Rail-only vehicles deliberately cannot crush. Traffic classification
	# still treats their full vehicle body as a vehicle, independently of that.
	return _is_ground_vehicle(e) or (e.get("kind", "") == "unit" and RailNetwork.rail_only(data_for(str(e.spec))))

func _traffic_priority(e: Dictionary) -> int:
	# Active vehicles take road precedence; an idle vehicle can still yield to
	# a player-controlled pedestrian. Same-class ties retain the existing
	# bounded retreat propagation and ID arbitration.
	var working: bool = _working_miner(e)
	var active: bool = not e.commands.is_empty() or working
	var vehicle: bool = _traffic_vehicle(e)
	if not active: return 10 if vehicle else 0
	var navigation: int = _navigation_priority(int(e.id))
	# Active economy traffic takes precedence over ordinary combat traffic;
	# explicitly selected human vehicles retain their foreground priority.
	if vehicle and working: return 40 + maxi(2, navigation)
	return (40 if vehicle else 20) + navigation

func _traffic_may_yield(e: Dictionary, other: Dictionary) -> bool:
	# A yielded blocker may propagate the same request, but must never ask
	# its root requester to retreat in return: that creates an endless two-way
	# shuttle at a crowded destination even though a legal side exit exists.
	if (e.get("yield_goal", Vector2.INF) as Vector2).is_finite() and int(e.get("yield_root", -1)) == int(other.id): return false
	if int(e.team) != int(other.team) or bool(other.get("hold_position", false)): return false
	if absf(_height(e.pos) - _height(other.pos)) > .8: return false
	if other.commands.is_empty() and not _working_miner(other): return true
	var source: Dictionary = entities.get(int(e.get("yield_root", -1)), e) if (e.get("yield_goal",Vector2.INF) as Vector2).is_finite() else e
	var a: int = _traffic_priority(source)
	var b: int = _traffic_priority(other)
	# Keep the established same-class retreat propagation and ID tie break.
	# Experimental spatial headway ranking did not remain stable at narrow
	# terrain entrances. Vehicle/infantry and explicit player precedence are
	# the intended new priorities; same-class propagation retains its limits.
	if _traffic_vehicle(source)!=_traffic_vehicle(other):return _traffic_vehicle(source)
	if a!=b:return a>b
	if (e.get("yield_goal",Vector2.INF) as Vector2).is_finite():return true
	return int(source.id)<int(other.id)

func issue(ids: Array, kind: String, pos: Vector2, target: int = -1, append: bool = false, expand_members: bool = true) -> void:
	if result != "":
		return
	if kind == "harvest" and target < 0:
		target = mine_at(pos)
	if kind == "repair":
		if entities.has(target) and entities[target].kind == "building":
			kind = "repair_building"
		elif entities.has(target):
			kind = "repair_unit"
		else:
			kind = "repair_bridge"
	elif kind == "bridge":
		kind = "repair_bridge"
	if (kind == "repair_bridge" or kind == "attack") and target == -1:
		var bridge_id: int = bridge_at(pos)
		if bridge_id >= 0:
			target = BRIDGE_TARGET_BASE - bridge_id
	var selected: Array = []
	for raw_id in (expand_squad_ids(ids, true) if expand_members else ids):
		var id: int = int(raw_id)
		if entities.has(id) and entities[id].kind == "unit" and float(entities[id].hp) > 0.0 and not Transport.is_loaded(entities[id]):
			selected.append(id)
	var ground_selected: Array = selected.filter(func(id): return not _is_air(entities[id]) and not _is_naval(entities[id]))
	var reserved: Dictionary = {}
	var air_reserved: Array = []
	var formation_spacing: float = 1.0
	var maximum_radius: float=.35
	for id in ground_selected:maximum_radius=maxf(maximum_radius,_radius(entities[id]))
	# Parking rows leave a swept-body-width access lane between columns.
	# The old2.4R square grid became physically impassable once front units parked.
	var formation_lane_spacing: float=maximum_radius*4.0+.06
	for id in ground_selected: formation_spacing = maxf(formation_spacing, _radius(entities[id]) * 2.4)
	var formation_forward := Vector2.RIGHT
	if not ground_selected.is_empty():
		var center := Vector2.ZERO
		for id in ground_selected: center += entities[id].pos
		center /= float(ground_selected.size())
		formation_forward = (pos - center).normalized()
		if formation_forward.length_squared() < .5: formation_forward = Vector2.RIGHT
	var formation_side: Vector2 = formation_forward.orthogonal()
	var squad_offsets: Dictionary = InfantrySquads.formation_offsets(self, ground_selected, formation_forward, formation_side)
	ground_selected.sort_custom(func(a,b):
		var da: float=(entities[a].pos as Vector2).dot(formation_side)
		var db: float=(entities[b].pos as Vector2).dot(formation_side)
		return da < db if not is_equal_approx(da,db) else int(a)<int(b))
	var ground_indices: Dictionary={}
	var columns: int = ceili(sqrt(float(ground_selected.size()))) if not ground_selected.is_empty() else 1
	var rows: int = ceili(float(ground_selected.size())/columns)
	for column in range(columns):
		var members: Array=ground_selected.slice(column*rows,mini((column+1)*rows,ground_selected.size()))
		members.sort_custom(func(a,b):
			var da: float=(entities[a].pos as Vector2).distance_to(pos)/maxf(.1,float(data_for(entities[a].spec).speed))
			var db: float=(entities[b].pos as Vector2).distance_to(pos)/maxf(.1,float(data_for(entities[b].spec).speed))
			return da<db if not is_equal_approx(da,db) else int(a)<int(b))
		for row in range(members.size()):ground_indices[members[row]]=row*columns+column
	for index in range(selected.size()):
		var e: Dictionary = entities[selected[index]]
		var air: bool = _is_air(e)
		if kind == "garrison" and not GarrisonOperations.board_error(self,int(e.id),target).is_empty():continue
		if kind == "return_miner" and str(data_for(e.spec).get("art",""))!="harvester":continue
		if kind == "return" and not air: continue
		if kind == "land" and (not air or not AircraftOperations.land_error(self, e, pos).is_empty()): continue
		if kind == "unload_move" and (int(data_for(e.spec).get("transport_capacity", 0)) <= 0 or e.get("passengers", []).is_empty() or (air and not AircraftOperations.land_error(self, e, pos).is_empty())): continue
		if kind in ["repair_building", "repair_bridge", "capture", "deploy_outpost", "resume_outpost"] and not _builder_valid(int(e.team), int(e.id)): continue
		if kind == "repair_unit" and (not entities.has(target) or not FactionSupport.repairer(self, e, entities[target])): continue
		if kind == "service" and not service_error(int(e.id),target).is_empty(): continue
		if kind == "rescue" and not FactionSupport.rescue_error(self, int(e.id), target).is_empty(): continue
		if kind == "resume_outpost" and not resume_outpost_error(int(e.id), target).is_empty(): continue
		if kind == "capture" and not capture_error(int(e.id), target).is_empty(): continue
		if kind == "board" and not board_error(int(e.id), target).is_empty(): continue
		if kind == "attack" and not _weapon_can_target(e, target): continue
		if kind == "force_attack" and (str(data_for(e.spec).get("weapon", "")).is_empty() or (target != -1 and not _weapon_can_target(e, target, true))): continue
		if kind == "harvest" and (not str(e.spec).ends_with("_harvester") or target < 0 or target >= mines.size()): continue
		if e.has("squad_id") and kind not in ["move", "attack_move", "patrol"]: e.erase("squad_formation_goal")
		if air:
			if kind == "return": e.park_after_service = true
			elif kind not in ["stop", "hold"]:
				if bool(e.get("takeoff_pending", false)): e.takeoff_returning = false
				e.park_after_service = false
				if e.flight_state == "rearming": e.service_interrupt = true
			elif bool(e.get("takeoff_pending", false)):
				e.takeoff_pending = false
		if not append or kind in ["stop", "hold"]:
			e.erase("squad_formation_goal")
			if bool(data_for(str(e.spec)).get("hero", false)) and float(e.get("hand_strike", 0.0)) > 0.0: HeroRules.cancel(e)
			_release_mine(int(e.id))
			e.commands.clear()
			e.path.clear()
			e.path_goal = Vector2.INF
			e.path_wait = 0.0
			e.stuck = 0.0
			e.movement_retry_at=0.0
			_cancel_path_request(int(e.id))
			e.progress_anchor = e.pos
			e.progress_clock = 0.0
			e.avoid_until = 0.0
			e.yield_goal = Vector2.INF
			e.turret_target = -1
			e.mine_search = {}
			e.refinery_search = {}
			e.planning_wait = 0.0
			_planning_queue.erase(int(e.id))
		if _human_navigation_owner(int(e.id)) and kind not in ["stop","hold"]: _navigation_command_until[int(e.id)]=time+3.0
		e.erase("pursuit_goal");e.erase("pursuit_target");e.erase("yield_root")
		for key in ["yield_saved_path","yield_saved_goal","yield_saved_revision"]:e.erase(key)
		e.hold_position = kind in ["hold", "resume_outpost"]
		if kind == "return":
			_begin_return(e)
			e.auto_target = -1
			events.append({"kind": "command", "pos": e.pos, "id": e.id})
			continue
		if kind in ["stop", "hold"]:
			Transport.cancel_naval_pickup(self,e)
			e.harvest_override = true
			e.state = "idle"
			continue
		var destination: Vector2 = _air_goal(pos) if air else pos
		if air and kind in ["move", "attack_move", "patrol"]:
			destination = AirNavigation.destination(self, e, pos, air_reserved)
		var ground_index: int = int(ground_indices.get(int(e.id),-1))
		if not air and not _is_naval(e) and kind in ["move", "attack_move", "patrol"] and ground_selected.size() == 1:
			destination = _near_stand(pos, _radius(e), e.id, 5.0)
		if not air and not _is_naval(e) and kind in ["move", "attack_move", "patrol"] and ground_selected.size() > 1:
			var spacing: float = formation_spacing
			destination += squad_offsets.get(int(e.id), formation_side * (float(ground_index % columns) - float(columns - 1) * .5) * formation_lane_spacing - formation_forward * (float(ground_index / columns) - float(columns - 1) * .5) * spacing)
			destination = _near_stand(destination, _radius(e), e.id, 8.0, false)
		if not air and not _is_naval(e) and kind in ["move", "attack_move", "patrol"] and destination.is_finite():
			var ideal: Vector2 = destination
			var squad: int = int(e.get("squad_id", -1))
			var search_spacing: float = InfantrySquads.member_spacing(_radius(e)) if squad >= 0 else formation_spacing
			var reserve_reach: int = ceili((maximum_radius * 2.0 + InfantrySquads.GROUP_EDGE_GAP) / formation_spacing) if squad >= 0 else 1
			for attempt in range(33):
				var free: bool = _standing(destination, _radius(e), e.id, false)
				var bucket:=Vector2i(floori(destination.x/formation_spacing),floori(destination.y/formation_spacing))
				for dz in range(-reserve_reach, reserve_reach + 1):
					for dx in range(-reserve_reach, reserve_reach + 1):
						for slot: Dictionary in reserved.get(bucket+Vector2i(dx,dz),[]):
							var minimum: float = formation_spacing - .01
							if squad >= 0 and int(slot.squad) >= 0:
								minimum = _radius(e) + float(slot.radius) + (InfantrySquads.MEMBER_CLEARANCE if squad == int(slot.squad) else InfantrySquads.GROUP_EDGE_GAP)
							if (slot.pos as Vector2).distance_to(destination) < minimum - .001: free = false
				if free: break
				var ring: float = 1 + floorf(float(attempt) / 16)
				destination = ideal + Vector2.RIGHT.rotated(float(attempt % 16) * TAU / 16) * search_spacing * ring
				if attempt == 32: destination = ideal # Keep the order; crowding is preferable to unbounded slot searches.
			if destination.is_finite():
				var bucket:=Vector2i(floori(destination.x/formation_spacing),floori(destination.y/formation_spacing))
				if not reserved.has(bucket):reserved[bucket]=[]
				reserved[bucket].append({"pos":destination,"radius":_radius(e),"squad":squad})
		if kind in ["move", "attack_move", "patrol"] and not air and not _is_naval(e):
			if RailNetwork.rail_only(data_for(e.spec)):
				destination = RailNetwork.center(RailNetwork.key(pos)) if not _rail_network.path(int(e.team), e.pos, pos).is_empty() else _rail_network.nearest_connected(self, e, pos, 3.0)
			elif not _rail_network.at(int(e.team), pos).is_empty():
				destination = RailNetwork.center(RailNetwork.key(pos))
		if not destination.is_finite():
			_notice("铁路目的地没有连通的己方轨道" if RailNetwork.rail_only(data_for(e.spec)) else "目的地附近没有可站立位置")
			continue
		if kind == "patrol":
			var origin: Vector2 = e.pos if e.commands.is_empty() else e.commands.back().pos
			e.commands.append({"kind": "patrol", "pos": destination, "target": target})
			e.commands.append({"kind": "patrol", "pos": origin, "target": -1})
		else:
			e.commands.append({"kind": kind, "pos": destination, "target": target})
		if e.has("squad_id") and kind in ["move", "attack_move", "patrol"]: e.squad_formation_goal = destination
		if kind == "resume_outpost" and not append: Construction.assign_builder(self, int(e.id), target)
		if ground_selected.size()>1 and kind in ["move","attack_move","patrol"] and not air and not _is_naval(e):e.commands.back().navigation_lane=ground_index%3
		e.auto_target = -1
		e.harvest_override = not (kind in ["harvest", "stop", "return_miner"])
		events.append({"kind": "command", "pos": destination, "id": e.id,"team":int(e.team),"spec":str(e.spec)})

func debug_spawn(team: int, spec: String, pos: Vector2, force_spawn: bool = false) -> int:
	if data_for(spec).is_empty():
		return -1
	if team < 0 or team >= factions.size(): return -1
	if not force_spawn and rules.get("units", {}).has(spec) and not UniqueUnitRules.reason(self, team, spec).is_empty(): return -1
	var info: Dictionary = data_for(spec)
	if not pos.is_finite():return -1
	if rules.buildings.has(spec) and (not _in_bounds(pos-Vector2.ONE*float(info.size)*.5) or not _in_bounds(pos+Vector2.ONE*float(info.size)*.5)):return -1
	if rules.get("units", {}).has(spec) and info.get("domain", "ground") == "naval":
		pos = NavalOperations.debug_spawn_point(self,pos,float(info.radius))
		if not pos.is_finite(): return -1
	elif rules.get("units", {}).has(spec) and info.get("domain", "ground") == "air":
		if not _in_bounds(pos): return -1
		pos = AirNavigation.spawn_point(self, spec, pos)
		if not pos.is_finite(): return -1
	elif rules.get("units", {}).has(spec):
		pos = _near_stand(pos, float(info.radius), -1, 8.0)
		if not pos.is_finite():
			return -1
	return _spawn(team, spec, pos, true)

## Explicit whole-squad spawning for authored new battles and visual fixtures.
## debug_spawn retains its single-entity meaning for existing rule diagnostics.
func debug_spawn_squad(team: int, spec: String, pos: Vector2, force_spawn: bool = false) -> int:
	var first: int = debug_spawn(team, spec, pos, force_spawn)
	if first < 0: return first
	var count: int = squad_size(spec)
	if count <= 1: return first
	var created: Array = [first]
	var radius: float = float(data_for(spec).get("radius", .35))
	var spacing: float = InfantrySquads.member_spacing(radius)
	var origin: Vector2 = entities[first].pos
	for slot: int in range(1, count):
		var desired: Vector2 = origin + Vector2(float(slot % 2) * spacing, float(slot / 2) * spacing)
		var point: Vector2 = _near_stand(desired, radius, -1, 8.0)
		if not point.is_finite():
			for id: int in created:
				_spatial_remove(id, entities[id].pos)
				entities.erase(id)
			return -1
		created.append(_spawn(team, spec, point, true))
	for slot: int in range(created.size()): InfantrySquads.assign(entities[created[slot]], first, slot, count)
	return first

func _spawn(team: int, spec: String, pos: Vector2, completed: bool, rotation_quarters: int = -1) -> int:
	var id: int = _next_id
	_next_id += 1
	var info: Dictionary = data_for(spec)
	var is_building: bool = rules.get("buildings", {}).has(spec)
	_max_entity_extent = maxf(_max_entity_extent, float(info.size) * 0.5 if is_building else float(info.get("radius", 0.35)))
	if not is_building and str(info.get("domain", "ground")) == "ground":
		_max_ground_radius = maxf(_max_ground_radius, float(info.get("radius", 0.35)))
	if is_building:
		if info.get("role", "") == "drill":
			var mine_index: int = MiningDrills.mine_index(self, pos)
			if mine_index >= 0: pos = mines[mine_index].pos
		else:
			var half: float = float(info.size) * 0.5
			pos = Vector2(roundf(pos.x - half) + half, roundf(pos.y - half) + half)
	entities[id] = {"radius": float(info.get("radius", 0.35)), "can_crush": bool(info.get("crush", false)), "crushable": bool(info.get("crushable", false)), "id": id, "kind": "building" if is_building else "unit", "spec": spec, "team": team, "pos": pos, "hp": float(info.hp), "alpha": 0.0 if team == 0 else 180.0, "turret_alpha": 0.0 if team == 0 else 180.0, "turret_target": -1, "state": "idle", "cooldown": 0.0, "commands": [], "queue": [], "construct_remaining": 0.0 if completed or not is_building else float(_eco("construction_animation", 1.5)), "cargo": 0.0, "hit_flash": 0.0, "rally": pos + Vector2(0, float(info.get("size", 1)) * 0.5 + (4.0 if str(info.get("role", "")) in ["factory", "refinery"] else 3.0)), "path": [], "path_goal": Vector2.INF, "path_wait": 0.0, "stuck": 0.0, "auto_target": -1, "harvest_override": false, "harvest_mine": -1, "harvest_refinery": -1, "repairing": false, "gift_pending": is_building and info.get("role", "") == "refinery", "blocked_notice": false, "motion": 0.0, "attack_flash": 0.0}
	_configure_crushing(entities[id], info)
	if is_building:
		var turns: int = posmod(rotation_quarters,4) if rotation_quarters >= 0 else (posmod(roundi(NavalOperations.shipyard_heading(self,pos)/90.0),4) if info.get("role","")=="shipyard" else 0)
		entities[id].rotation_quarters = turns
		entities[id].alpha = float(turns)*90.0
		entities[id].turret_alpha = entities[id].alpha
		entities[id].rally = BuildingOrientation.point(entities[id],Vector2(float(info.size)*.5+4.0,0) if info.get("role","")=="shipyard" else Vector2(0,float(info.size)*.5+(4.0 if info.get("role","") in ["factory","refinery"] else 3.0)))
		if RailNetwork.is_rail(info): entities[id].rail_rotation = turns

	entities[id].visible_to = 1 << team if vision_enabled else (1 << factions.size()) - 1
	Transport.initialize(entities[id])
	if not is_building:
		entities[id].last_damage_time = time
		entities[id].last_attack_time = time
		if bool(info.get("hero", false)):
			entities[id].hand_strike = 0.0
			entities[id].hand_recover = 0.0
			entities[id].hand_target = -1
			entities[id].hand_landing = pos
			entities[id].hand_force = false
			entities[id].hand_resolving = false
	if info.get("domain", "ground") == "air" and not is_building:
		var aircraft: Dictionary = entities[id]
		aircraft.ammo = int(info.get("ammo_capacity", 1))
		_set_home_airfield(aircraft, _find_airfield(aircraft))
		aircraft.flight_state = "airborne"
		aircraft.rearm_remaining = 0.0
		aircraft.flight_height = float(info.get("flight_height", 4.0))
		aircraft.airborne = true
	if is_building:
		_building_entities.append(entities[id])
		_spatial_add(id, pos)
		_refresh_building_spatial()
		if info.get("role", "") == "drill": MiningDrills.claim(self, entities[id])
		_mark_nav_region(Rect2(pos - Vector2.ONE * float(info.size) * 0.5, Vector2.ONE * float(info.size)))
	else:
		_spatial_add(id, pos)
	if _is_air(entities[id]):AirNavalExpansion.initialize_air(self,entities[id])
	return id

func step(delta: float) -> void:
	if result != "" or delta <= 0.0:
		return
	var profile_start: int = Time.get_ticks_usec() if profile_enabled else 0
	_in_step = true
	_ground_motion_spatial.clear()
	_geometry_queries=0;_geometry_us=0;_geometry_rectangles=0
	if _kernels!=null:_kernels.begin_geometry_measurement(geometry_profiling_enabled)
	_spec_cache = rules.get("units", {}).duplicate()
	_spec_cache.merge(rules.get("buildings", {}))
	_air_specs.clear()
	_naval_specs.clear()
	for spec_id in rules.get("units", {}):
		if rules.units[spec_id].get("domain", "ground") == "air": _air_specs[spec_id] = true
		elif rules.units[spec_id].get("domain", "ground") == "naval": _naval_specs[spec_id] = true
	_weapon_target_masks.clear()
	for spec_id in _spec_cache:
		_weapon_target_masks[spec_id] = _target_mask_for_spec(_spec_cache[spec_id])
	_prepare_native_queries()
	_invalidate_base_cache()
	_airfield_counts_dirty = true
	navigation_stats.main_us=0
	_local_nav_us=0
	_avoidance_probes=AVOIDANCE_PROBES_PER_TICK
	_yield_requests=YIELD_REQUESTS_PER_TICK
	_collect_path_results()
	_step_delta = delta
	_path_plans_remaining = PATH_SYNC_PLANS_PER_TICK if synchronous_path_tests else PATH_PLANS_PER_TICK
	_planning_deferred_ids.clear()
	_planning_requested_ids.clear()
	time += delta
	if _nav_dirty:
		_rebuild_nav()
	_rebuild_spatial()
	_prepare_native_queries()
	_damage.clear()
	_damage_causes.clear()
	_execute_buildings.clear()
	_crush_targets.clear()
	TeamVision.refresh(self)
	_bridge_repairers.clear()
	_field_repairers.clear()
	_refresh_mine_claims()
	_mine_tick_budget.clear()
	for index in range(mines.size()): _mine_tick_budget[index] = float(_eco("harvest_rate", 25)) * delta
	FactionSupport.prepare(self, delta)
	AircraftOperations.step_idle(self, delta)
	var multipliers: Array[float] = []
	multipliers.resize(factions.size())
	multipliers.fill(1.0)
	for team in range(factions.size()):
		var energy: Vector2 = power(team)
		var low: bool = energy.y > energy.x
		multipliers[team] = float(_eco("low_power_multiplier", 0.5)) if low else 1.0
		if low != _low_power[team]:
			_low_power[team] = low
			if low:
				events.append({"kind": "low_power", "pos": _team_start(team), "team": team})
				if team == 0:
					_notice("电力不足：建造与生产减速，防御塔停机")
			else:
				events.append({"kind":"power_restored","pos":_team_start(team),"team":team})
				if team==0:_notice("电力恢复：生产与防御设施已恢复运行")
		for channel in ["normal", "defense"]:
			BuildingConstruction.advance(self, team, channel, delta, multipliers[team])
	DeveloperTools.finish_pending(self,0)
	var profile_units_start: int = Time.get_ticks_usec() if profile_enabled else 0
	if native_kernels_enabled and native_unit_dispatch_enabled and _kernels != null and not ProductionLifecycle.active(self) and not RefineryDocking.active(self) and not GarrisonOperations.active(self) and not Veterancy.active(self):
		_kernels.step_entities(self,entities,_spec_cache,rules.weapons,_air_specs,_naval_specs,_weapon_target_masks,multipliers,delta,float(_eco("fire_angle",15)))
	else:
		_step_entities_script(delta,multipliers)
	InfantrySquads.regroup(self, delta)
	Transport.sync_passengers(self)
	GarrisonOperations.step(self,delta)
	AirNavalExpansion.step_fleet(self,delta)
	var profile_units_end: int = Time.get_ticks_usec() if profile_enabled else 0
	_step_support(delta, multipliers)
	_step_projectiles(delta)
	BeamWeapons.step(self, delta)
	_apply_damage()
	TeamVision.refresh(self)
	_damage.clear()
	_execute_buildings.clear()
	_crush_targets.clear()
	HeroRules.step(self, delta)
	if not _damage.is_empty():
		_apply_damage()
		TeamVision.refresh(self)
	FactionTraits.step_regeneration(self, delta)
	Veterancy.step(self,delta)
	if campaign_controller != null: campaign_controller.step(self, delta)
	_check_result()
	if profile_enabled:
		profile = {"prepare_us": profile_units_start-profile_start, "entities_us": profile_units_end-profile_units_start, "damage_us": Time.get_ticks_usec()-profile_units_end, "total_us": Time.get_ticks_usec()-profile_start}
	if result == "" and ai_enabled and (bool(match_options.get("modern", false)) or bool(match_options.get("explicit_controls",false))):
		if independent_ai != null: independent_ai.step(self, delta)
		else: AIController.step(self, delta)
	elif result == "" and ai_enabled:
		_ai_clock -= delta
		_ai_attack_clock += delta
		if _ai_clock <= 0.0:
			_ai_clock = 2.0
			_step_ai()
	_prune_planning_queue()
	_submit_path_jobs()
	navigation_stats.local_us=_local_nav_us
	navigation_stats.max_local_us=maxi(int(navigation_stats.get("max_local_us",0)),_local_nav_us)
	navigation_stats.max_main_us=maxi(int(navigation_stats.max_main_us),int(navigation_stats.main_us))
	if geometry_profiling_enabled:
		var native_stats: Dictionary=_kernels.geometry_measurement() if _kernels!=null else {}
		navigation_stats.geometry_queries=_geometry_queries+int(native_stats.get("queries",0))
		navigation_stats.geometry_us=_geometry_us+int(native_stats.get("microseconds",0))
		navigation_stats.geometry_rectangles=_geometry_rectangles+int(native_stats.get("rectangles",0))
		navigation_stats.max_geometry_us=maxi(int(navigation_stats.get("max_geometry_us",0)),int(navigation_stats.geometry_us))
		if _kernels!=null:_kernels.begin_geometry_measurement(false)
	_in_step = false
	_native_geometry_ready = false
	statistics.sample(self)

func _step_entities_script(delta: float, multipliers: Array[float]) -> void:
	for raw_id in entities.keys():
		var id: int = int(raw_id)
		if not entities.has(id): continue
		var e: Dictionary = entities[id]
		if float(e.hp) <= 0.0:
			continue
		e.cooldown = maxf(0.0, float(e.cooldown) - delta)
		e.hit_flash = maxf(0.0, float(e.hit_flash) - delta)
		e.attack_flash = maxf(0.0, float(e.attack_flash) - delta)
		e.path_wait = maxf(0.0, float(e.path_wait) - delta)
		e.motion = 0.0
		if e.kind == "building":
			_step_building(e, delta, multipliers[int(e.team)])
		else:
			_step_unit(e, delta)

func _step_building(e: Dictionary, delta: float, multiplier: float) -> void:
	ProductionLifecycle.building_step(self, e, delta)
	if float(e.get("emp_until", 0.0)) > time:
		e.state = "emp"
		return
	if e.has("construction"):
		Construction.step(self, e, delta)
		return
	if float(e.construct_remaining) > 0.0:
		e.construct_remaining = maxf(0.0, float(e.construct_remaining) - delta)
		if float(e.construct_remaining) <= 0.0:
			_invalidate_base_cache()
			if not RailNetwork.is_rail(data_for(e.spec)): statistics.add(int(e.team),"buildings_built")
			else: _rail_network.rebuild(self)
			events.append({"kind": "deploy", "pos": e.pos, "id": e.id, "team": e.team, "spec": e.spec, "entity_kind": "building"})
		e.state = "build" if float(e.construct_remaining) > 0.0 else "idle"
		return
	if e.state == "emp": e.state = "idle"
	var info: Dictionary = data_for(e.spec)
	if info.get("role", "") == "drill": MiningDrills.step(self, e, delta)
	multiplier = float(_eco("low_power_multiplier", 0.5)) if building_low_power(e) else 1.0
	if bool(e.repairing) and float(e.hp) < max_hp(e):
		var rate: float = float(_eco("repair_rate", 0.02)) * float(info.hp)
		var cost: float = float(_eco("repair_cost", 0.2))
		var healed: float = minf(rate * delta, max_hp(e) - float(e.hp))
		if cost > 0.0:
			healed = minf(healed, money[int(e.team)] / cost)
		e.hp += healed
		money[int(e.team)] = maxf(0.0, money[int(e.team)] - healed * cost)
	if bool(e.gift_pending):
		_rail_network.auto_refinery(self, e)
		var gift: String = factions[int(e.team)] + "_harvester"
		var gift_pos: Vector2 = _spawn_point(e, gift)
		if gift_pos.is_finite():
			e.gift_pending = false
			var gift_id: int = _spawn(int(e.team), gift, gift_pos, true)
			ProductionLifecycle.begin(self, e, entities[gift_id], gift_pos)
			events.append({"kind": "produce", "pos": gift_pos, "id": gift_id, "team": int(e.team), "spec": gift})
			statistics.add(int(e.team),"units_produced")
		else:
			_blocked(e)
	if not e.queue.is_empty() and ProductionLifecycle.order_can_advance(self, e, e.queue[0]):
		var order: Dictionary = e.queue[0]
		order.started = true
		order.remaining = maxf(0.0, float(order.remaining) - delta * multiplier)
		order.progress = 1.0 - float(order.remaining) / maxf(float(order.total), 0.001)
		order.ready = float(order.remaining) <= 0.0
		if float(order.remaining) <= 0.0:
			var spawn_pos: Vector2 = ProductionLifecycle.queued_spawn_point(self, e, order)
			if spawn_pos.is_finite():
				var count: int = int(order.get("squad_size", 1))
				var slot: int = int(order.get("spawned", 0))
				var initial_pos: Vector2 = ProductionLifecycle.origin(self, e, str(order.spec), spawn_pos) if count > 1 else spawn_pos
				var unit_id: int = _spawn(int(e.team), str(order.spec), initial_pos, true)
				if int(order.get("squad_id", -1)) < 0: order.squad_id = unit_id
				InfantrySquads.assign(entities[unit_id], int(order.squad_id), slot, count)
				order.spawned = slot + 1
				ProductionLifecycle.begin(self, e, entities[unit_id], spawn_pos)
				if count > 1 and slot == 0:
					events.append({"kind":"squad_ready","pos":spawn_pos,"id":unit_id,"squad_id":int(order.squad_id),"building":int(e.id),"team":int(e.team),"spec":str(order.spec),"members":count})
				if int(order.spawned) >= count: e.queue.pop_front()
				e.blocked_notice = false
				if not str(order.spec).ends_with("_harvester") and not _is_air(entities[unit_id]):
					var rally_goal: Vector2 = _air_goal(e.rally) if _is_air(entities[unit_id]) else (e.rally if _is_naval(entities[unit_id]) else _near_stand(e.rally, _radius(entities[unit_id]), unit_id, 6.0))
					if count > 1 and rally_goal.is_finite():
						var forward: Vector2 = (rally_goal - (e.pos as Vector2)).normalized()
						if forward.length_squared() < .5: forward = Vector2.DOWN
						rally_goal += InfantrySquads.slot_offset(slot, count, _radius(entities[unit_id]), forward, forward.orthogonal())
					if rally_goal.is_finite():
						issue([unit_id], "move", rally_goal, -1, false, false)
				events.append({"kind": "produce", "pos": spawn_pos, "id": unit_id, "team": int(e.team), "spec": str(order.spec)})
				statistics.add(int(e.team),"units_produced")
			else:
				# A following member waiting for safe headway is normal cohort
				# movement, not a newly blocked production exit notification.
				if not ProductionLifecycle.pending_batch(e) or ProductionLifecycle.active_members(self, e).is_empty(): _blocked(e)
	var weapon_id: String = str(info.get("weapon", ""))
	if weapon_id != "" and not building_low_power(e):
		var weapon: Dictionary = weapon_for(e,weapon_id)
		var target: int = _nearest_enemy(e, float(weapon.range))
		if target != -1:
			e.turret_target = target
			e.turret_alpha = rad_to_deg((_target_position(target) - (e.pos as Vector2)).angle())
			_fire(e, target)

func _blocked(e: Dictionary) -> void:
	if not bool(e.blocked_notice):
		e.blocked_notice = true
		if int(e.team) == 0:
			_notice("等待铁路连接：请在工厂实际出口铺设己方铁路" if bool(e.get("rail_waiting", false)) else "生产出口堵塞：成品等待合法位置")

func _spawn_point(building: Dictionary, spec: String) -> Vector2:
	if RailNetwork.rail_only(data_for(spec)): return _rail_network.spawn_point(self, building, spec)
	if bool(data_for(spec).get("amphibious",false)) and data_for(building.spec).get("role","")!="shipyard":
		var point:Vector2=BuildingOrientation.point(building,Vector2(0,float(data_for(building.spec).size)*.5+float(data_for(spec).radius)+.15))
		return point if _standing(point,float(data_for(spec).radius),-1,true) else Vector2.INF
	if data_for(spec).get("domain", "ground") == "naval": return NavalOperations.spawn_point(self, building, spec)
	if data_for(spec).get("domain", "ground") == "air":
		if bool(data_for(spec).get("permanent_air",false)):return AirNavigation.spawn_point(self,spec,BuildingOrientation.point(building,Vector2(0,float(data_for(building.spec).size)*.5+2)))
		var capacity: int = int(data_for(building.spec).get("aircraft_capacity", 4))
		if _airfield_load(int(building.id), false) >= capacity: return Vector2.INF
		return AircraftOperations.production_slot(self, building)
	var radius: float = float(data_for(spec).get("radius", 0.35))
	var half: float = float(data_for(building.spec).size) * 0.5
	# Every ground producer uses its authored central +Z doorway. A blocked
	# door retains the ready order instead of moving the exit to a solid wall.
	var point: Vector2 = BuildingOrientation.point(building,Vector2(0, half + radius + .15))
	return point if _standing(point, radius, -1, true) else Vector2.INF

func _step_unit(e: Dictionary, delta: float) -> void:
	if Transport.is_loaded(e): return
	if float(e.get("emp_until", 0.0)) > time:
		e.state = "emp"
		return
	if ProductionLifecycle.step_unit(self, e, delta): return
	if RefineryDocking.step_unit(self,e,delta): return
	if _is_air(e) and _step_aircraft_service(e, delta): return
	_step_unit_after_service(e,delta)

func service_error(unit_id:int,depot_id:int)->String:
	return RepairDepot.error(self,unit_id,depot_id)

func _step_unit_after_service(e: Dictionary, delta: float) -> void:
	var spec: Dictionary = data_for(e.spec)
	var yielding: Vector2 = e.get("yield_goal", Vector2.INF)
	if yielding.is_finite() and time >= float(e.get("yield_until",time+3.0)):
		_complete_movement_yield(e)
		yielding=Vector2.INF
	if yielding.is_finite():
		if not e.has("yield_until"): e.yield_until=time+3.0
		if _move_to(e, yielding, delta):
			_complete_movement_yield(e)
		if _has_turret(spec):
			var yield_command: Dictionary = e.commands[0] if not e.commands.is_empty() else {}
			if _can_move_fire(spec) and yield_command.get("kind", "") in ["attack", "attack_move"]:
				if yield_command.kind == "attack" and _weapon_can_target(e, int(yield_command.target)):
					_aim_turret(e, int(yield_command.target), delta)
				else:
					_mobile_acquire_and_fire(e, delta)
			else:
				_turret_forward(e, delta)
		return
	if str(e.spec).ends_with("_harvester") and e.commands.is_empty() and not bool(e.harvest_override):
		_step_harvester(e, delta)
		return
	var command: Dictionary = e.commands[0] if not e.commands.is_empty() else {}
	if not command.is_empty():
		var kind: String = str(command.kind)
		if kind == "garrison":
			GarrisonOperations.step_board(self,e,command,delta)
			return
		if kind == "return_miner":
			if not bool(command.get("started",false)):
				_release_mine(int(e.id));e.manual_unload=true
				e.harvest_refinery=int(command.target) if entities.has(int(command.target)) else _find_refinery(e)
				command.started=true
			_step_harvester(e,delta)
			return
		if kind == "service":
			RepairDepot.step(self,e,command,delta)
			return
		if kind == "land":
			AircraftOperations.step_land(self, e, command, delta)
			return
		if kind == "unload_move":
			Transport.step_unload_move(self, e, command, delta)
			return
		if kind == "board":
			Transport.step_board(self, e, command, delta)
			return
		if kind == "capture":
			_step_capture(e, command, delta)
			return
		if kind == "deploy_outpost":
			_step_deploy_outpost(e, command, delta)
			return
		if kind == "resume_outpost":
			_step_resume_outpost(e, command, delta)
			return
		if kind == "return":
			_begin_return(e)
			_finish_command(e)
			return
		if kind in ["repair_unit", "repair_building"]:
			_step_entity_repair(e, command, delta)
			return
		if kind == "rescue":
			FactionSupport.step_rescue(self, e, command, delta)
			return
		if kind == "repair_bridge":
			_step_bridge_repair(e, command, delta)
			return
		if kind == "harvest":
			if not bool(command.get("started",false)):
				e.harvest_mine = int(command.target)
				e.preferred_mine = int(command.target)
				e.harvest_refinery = -1
				e.mine_search = {}
				e.mining_goal = Vector2.INF
				command.started = true
			e.harvest_override = false
			_step_harvester(e,delta)
			return
		if kind == "move":
			if _move_order(e, command, delta):
				_finish_command(e)
			if _has_turret(spec):
				_turret_forward(e, delta)
			return
		if kind == "force_move":
			_step_force_move(e, command, delta)
			return
		if kind == "force_attack" and int(command.target) == -1:
			_step_ground_attack(e, command, delta)
			return
		if kind in ["attack", "force_attack"]:
			var target: int = int(command.target)
			if not _target_alive(target) or not _weapon_can_target(e, target):
				if _lost_target_order(e, target): return
				_finish_command(e)
				if _has_turret(spec):
					_turret_forward(e, delta)
				return
			_engage(e, target, delta, true)
			return
		if kind in ["attack_move", "patrol"]:
			if _can_move_fire(spec):
				# The hull keeps its legal destination path while the turret fights.
				var arrived: bool = _move_order(e, command, delta)
				_mobile_acquire_and_fire(e, delta)
				if arrived:
					_finish_command(e)
				return
			var weapon_id: String = str(spec.get("weapon", ""))
			var target: int = int(e.auto_target)
			if not _target_alive(target) or not _weapon_can_target(e, target) or _target_position(target).distance_to(e.pos) > 14.0:
				target = -1
			if target == -1 and weapon_id != "":
				target = _nearest_enemy(e, float(weapon_for(e,weapon_id).range) + 2.0)
			e.auto_target = target
			if target != -1:
				_engage(e, target, delta, true)
			elif _move_order(e, command, delta):
				_finish_command(e)
			return
	var weapon_id: String = str(spec.get("weapon", ""))
	e.state = "idle"
	if weapon_id != "":
		var target: int = _nearest_enemy(e, float(weapon_for(e,weapon_id).range))
		if target != -1:
			_engage(e, target, delta, false)
		elif _has_turret(spec):
			_turret_forward(e, delta)

# Air operations use their own movement and service state, never ground navigation.
func _air_goal(pos: Vector2) -> Vector2:
	return pos.clamp(Vector2(0.05, 0.05), Vector2.ONE * (float(map.size) - 0.05)) if pos.is_finite() else Vector2.INF

func _set_airborne(e: Dictionary, value: bool) -> void:
	if bool(e.get("airborne", true)) == value: return
	_spatial_remove(int(e.id), e.pos)
	e.airborne = value
	_spatial_add(int(e.id), e.pos)
	_neighbor_cache.clear()

func _fly_to(e: Dictionary, goal: Vector2, delta: float) -> bool:
	return AirNavigation.fly_to(self, e, goal, delta)

func _airfield_load(id: int, include_queue: bool = true) -> int:
	if _airfield_counts_dirty:
		_airfield_counts.clear()
		# A roster lookup avoids resolving a full unit definition for every
		# ground unit when an aircraft dies outside the active tick.
		var prepared_air:bool=_in_step and not _spec_cache.is_empty()
		var air_ids:Dictionary=_air_specs if prepared_air else {}
		if not prepared_air:
			for spec_id in rules.get("units",{}):
				if rules.units[spec_id].get("domain","ground")=="air":air_ids[spec_id]=true
		for e in entities.values():
			if e.get("kind","unit")=="unit" and air_ids.has(e.spec) and float(e.hp)>0 and not AirNavalExpansion.permanent(self,e) and not bool(data_for(e.spec).get("carrier_plane",false)):
				var home: int = int(e.get("home_airfield", -1))
				if home >= 0: _airfield_counts[home] = int(_airfield_counts.get(home, 0)) + 1
		_airfield_counts_dirty = false
	var amount: int = int(_airfield_counts.get(id, 0))
	if include_queue and entities.has(id):
		for order in entities[id].queue:
			if not bool(data_for(order.spec).get("permanent_air",false)):amount+=1
	return amount

func _set_home_airfield(e: Dictionary, id: int) -> void:
	var old: int = int(e.get("home_airfield", -1))
	e.home_airfield = id
	if old == id or _airfield_counts_dirty: return
	if old >= 0: _airfield_counts[old] = maxi(0, int(_airfield_counts.get(old, 0)) - 1)
	if id >= 0: _airfield_counts[id] = int(_airfield_counts.get(id, 0)) + 1

func _airfield_valid(id: int, team: int) -> bool:
	if not entities.has(id):return false
	var field:Dictionary=entities[id]
	return field.kind == "building" and int(field.team) == team and float(field.hp) > 0.0 and float(field.construct_remaining) <= 0.0 and data_for(field.spec).get("role", "") == "airfield"

func _find_airfield(e: Dictionary) -> int:
	var answer: int = -1
	var nearest: float = INF
	var team:int=int(e.team)
	for building in _building_entities:
		var id: int = int(building.id)
		if not entities.has(id):continue
		var field:Dictionary=entities[id]
		if not (field.kind=="building" and int(field.team)==team and float(field.hp)>0.0 and float(field.construct_remaining)<=0.0):continue
		if data_for(field.spec).get("role","")!="airfield":continue
		var capacity: int = int(data_for(building.spec).get("aircraft_capacity", 4))
		if _airfield_load(id) >= capacity: continue
		var distance: float = (e.pos as Vector2).distance_squared_to(building.pos)
		if distance < nearest:
			nearest = distance
			answer = id
	return answer

func _begin_return(e: Dictionary) -> void:
	if AirNavalExpansion.permanent(self,e) or bool(data_for(e.spec).get("carrier_plane",false)):return
	if e.flight_state != "returning":
		if bool(e.get("airborne", true)): e.flight_state = "returning"
		else: _wait_for_takeoff(e, true)
		events.append({"kind": "return", "id": e.id, "team": e.team, "spec": e.spec, "pos": e.pos})
	e.path.clear()
	e.path_goal = Vector2.INF

func _wait_for_takeoff(e: Dictionary, returning: bool) -> void:
	e.flight_state = "landed"
	e.flight_height = .35
	e.rearm_remaining = 0.0
	e.takeoff_pending = true
	e.takeoff_returning = returning
	e.state = "waiting"
	_set_airborne(e, false)

func _step_aircraft_service(e: Dictionary, delta: float) -> bool:
	if bool(data_for(e.spec).get("carrier_plane",false)):return AirNavalExpansion.service(self,e,delta)
	if AirNavalExpansion.permanent(self,e):
		AirNavalExpansion.initialize_air(self,e)
		return false
	if bool(e.get("takeoff_pending", false)):
		if not AirNavigation.point_clear(self, e, e.pos):
			e.state = "waiting"
			return true
		e.takeoff_pending = false
		e.flight_state = "returning" if bool(e.get("takeoff_returning", false)) or int(e.ammo) <= 0 else "airborne"
		e.flight_height = float(data_for(e.spec).flight_height)
		_set_airborne(e, true)
	if AircraftOperations.step_landed(self, e): return true
	var info: Dictionary = data_for(e.spec)
	if e.flight_state == "rearming" and bool(e.get("service_interrupt", false)):
		if not AirNavigation.point_clear(self, e, e.pos):
			e.state = "waiting"
			return true
		e.service_interrupt = false
		e.flight_state = "airborne"
		e.flight_height = float(info.flight_height)
		_set_airborne(e, true)
		e.rearm_remaining = 0.0
		return false
	if not _airfield_valid(int(e.home_airfield), int(e.team)):
		_set_home_airfield(e, _find_airfield(e))
		if e.flight_state == "rearming":
			_wait_for_takeoff(e, true)
			return true
	if int(e.ammo) <= 0 and e.flight_state == "airborne": _begin_return(e)
	if e.flight_state == "stranded" and int(e.home_airfield) > 0: _begin_return(e)
	if e.flight_state == "stranded" and not e.commands.is_empty() and str(e.commands[0].get("kind", "")) in ["land", "unload_move"]: return false
	if e.flight_state not in ["returning", "rearming", "stranded"]: return false
	if int(e.home_airfield) < 0:
		if not bool(e.get("airborne", true)) and not AirNavigation.point_clear(self, e, e.pos):
			e.state = "waiting"
			return true
		e.flight_state = "stranded"
		e.flight_height = float(info.flight_height)
		_set_airborne(e, true)
		e.state = "waiting"
		return true
	var field: Dictionary = entities[int(e.home_airfield)]
	if e.flight_state == "returning":
		if not bool(e.get("airborne", true)) and not AirNavigation.point_clear(self, e, e.pos):
			e.state = "waiting"
			return true
		e.flight_height = float(info.flight_height)
		_set_airborne(e, true)
		var service_goal: Vector2 = AircraftOperations.service_position(self, e, field)
		e.service_goal = service_goal
		if not service_goal.is_finite():
			e.state = "waiting"
			return true
		if not _fly_to(e, service_goal, delta): return true
		e.flight_state = "rearming"
		e.rearm_remaining = float(info.rearm_time)
		events.append({"kind": "rearm_start", "id": e.id, "team": e.team, "pos": e.pos})
	if e.flight_state == "rearming":
		e.alpha=float(BuildingOrientation.quarters(field))*90.0
		e.turret_alpha=e.alpha
		e.flight_height = 0.35
		_set_airborne(e, false)
		e.state = "rearm"
		var maintenance: float = float(data_for(field.spec).get("aircraft_repair_rate", 0.0))
		if maintenance > 0.0 and not building_low_power(field) and float(e.hp) < max_hp(e):
			var heal: float = minf(maintenance * delta, max_hp(e) - float(e.hp))
			var price: float = float(_eco("repair_cost", 0.0))
			if price > 0.0: heal = minf(heal, money[int(e.team)] / price)
			if heal > 0.0:
				_repair_health(e, heal)
		var service_speed: float = float(_eco("low_power_multiplier", 0.5)) if building_low_power(field) else 1.0
		e.rearm_remaining = maxf(0.0, float(e.rearm_remaining) - delta * service_speed)
		if float(e.rearm_remaining) <= 0.0:
			e.ammo = int(info.ammo_capacity)
			if float(e.hp) < max_hp(e) - 0.001:
				e.state = "repair"
				return true
			if e.commands.is_empty():
				e.state = "parked"
				return true
			if not AirNavigation.point_clear(self, e, e.pos):
				e.state = "waiting"
				return true
			e.flight_state = "airborne"
			e.flight_height = float(info.flight_height)
			_set_airborne(e, true)
			events.append({"kind": "rearm", "id": e.id, "team": e.team, "spec": e.spec, "pos": e.pos})
	return true

func _target_height(target: int) -> float:
	if entities.has(target):
		var e: Dictionary = entities[target]
		if _is_naval(e): return MapData.entity_surface_y(map,e.pos,"naval") - _height(e.pos) + 0.6
		if e.kind == "building" and str(data_for(e.spec).get("domain", "ground")) == "naval": return MapData.entity_surface_y(map,e.pos,"naval") - _height(e.pos) + 1.1
		return float(e.get("flight_height", 0.0)) + (1.1 if e.kind == "building" else 0.6)
	return 0.0

func _source_height(e: Dictionary) -> float:
	if e.has("garrison_fire_height"):return float(e.garrison_fire_height)
	if _is_naval(e): return MapData.entity_surface_y(map,e.pos,"naval") - _height(e.pos)
	if e.kind == "building" and str(data_for(e.spec).get("domain", "ground")) == "naval": return MapData.entity_surface_y(map,e.pos,"naval") - _height(e.pos)
	return float(e.get("flight_height", 0.0))

func _impact_event_height(pos: Vector2, targets: Array, target: int = -1) -> float:
	if "air" in targets and (target < 1 or (entities.has(target) and _is_air(entities[target]))): return _target_height(target)
	if MapData.terrain_at(map,pos) == MapData.WATER: return MapData.water_surface_y(map,pos) - _height(pos) + 0.18
	return 0.0

func _force_attack_active(e: Dictionary, target: int) -> bool:
	return not e.commands.is_empty() and e.commands[0].kind == "force_attack" and (int(e.commands[0].target) == target or int(e.commands[0].target) == -1)

func _lost_target_order(e: Dictionary, target: int) -> bool:
	if target < 1 or not vision_enabled or entity_visible_to(int(e.team), target): return false
	var memory: Dictionary = last_known_enemy(int(e.team), target)
	if memory.is_empty() or not memory.get("pos") is Vector2: return false
	var destination: Vector2 = memory.pos
	if not destination.is_finite(): return false
	e.commands[0] = {"kind":"attack_move", "pos":destination, "target":-1}
	e.path.clear()
	e.path_goal = Vector2.INF
	e.auto_target = -1
	e.state = "search"
	return true

func _weapon_can_target(e: Dictionary, target: int, force: bool = false) -> bool:
	if not AirNavalExpansion.can_target(self,e,target):return false
	if ZeppelinWeapons.is_zeppelin(self,e) and ZeppelinWeapons.can_target(self,e,target,force): return true
	if target >= 0 and not entity_visible_to(int(e.team), target): return false
	if _in_step and _weapon_target_masks.has(e.spec):
		var mask: int = int(_weapon_target_masks[e.spec])
		if target >= 0 and native_kernels_enabled and _kernels != null:
			return _kernels.can_target(e, target, entities, mask, _air_specs, _naval_specs, force)
		if mask == 0 or Transport.is_loaded(e): return false
		force = force or _force_attack_active(e, target)
		if target >= 0:
			var other: Dictionary = entities.get(target, {})
			if other.is_empty() or float(other.hp) <= 0.0 or Transport.is_loaded(other): return false
			if other.team == e.team and not force: return false
			return (mask & (2 if _is_air(other) else (4 if _target_domain(other)=="naval" else 1))) != 0
		if target <= RUIN_TARGET_BASE and not force and not GarrisonOperations.hostile(self,int(e.team),target): return false
		return (mask & 1) != 0 and _target_alive(target)
	var weapon_id: String = str(data_for(e.spec).get("weapon", ""))
	if Transport.is_loaded(e) or weapon_id.is_empty() or not _target_alive(target): return false
	force = force or _force_attack_active(e, target)
	if target <= RUIN_TARGET_BASE and not force and not GarrisonOperations.hostile(self,int(e.team),target): return false
	if entities.has(target) and entities[target].team == e.team and not force: return false
	var domain: String = _target_domain(entities[target]) if entities.has(target) else "ground"
	return domain in rules.weapons[weapon_id].get("targets", ["ground"])

func _scaled_damage(base: float, target: int, multipliers: Dictionary) -> float:
	var armor: String = "building"
	if entities.has(target) and entities[target].kind == "unit":
		var info: Dictionary = data_for(entities[target].spec)
		armor = str(info.get("armor_class", "infantry" if info.get("crushable", false) else "armored"))
	return base * float(multipliers.get(armor, 1.0))

func max_hp(e:Dictionary)->float:return Veterancy.max_hp(self,e)
func armor_for(e:Dictionary)->float:return Veterancy.armor(self,e)
func weapon_for(e:Dictionary,id:String="")->Dictionary:return Veterancy.weapon(self,e,id if not id.is_empty() else str(data_for(e.spec).get("weapon","")))

func _weapon_damage(base: float,target: int,weapon: Dictionary,factor: float=1.0) -> float:
	var info: Dictionary=ArmorCombat.weapon(self,weapon)
	return ArmorCombat.damage(self,base,target,info.get("multipliers",{}),info,factor)

func _step_entity_repair(e: Dictionary, command: Dictionary, delta: float) -> void:
	var target: int = int(command.target)
	if not entities.has(target) or not FactionSupport.repairer(self, e, entities[target]):
		_finish_command(e)
		return
	var repaired: Dictionary = entities[target]
	if repaired.team != e.team or float(repaired.hp) <= 0.0 or _is_air(repaired) or Transport.is_loaded(repaired) or float(repaired.construct_remaining) > 0.0 or float(repaired.hp) >= max_hp(repaired) or (repaired.kind == "building" and data_for(e.spec).get("art", "") != "engineer"):
		_finish_command(e)
		return
	var info: Dictionary = data_for(e.spec)
	var reach: float = float(info.get("repair_radius", 1.8))
	var distance: float = _engineering_distance(e, repaired)
	if distance > reach:
		var goal: Vector2 = _refinery_approach(e, repaired) if repaired.kind == "building" else _near_stand(repaired.pos + (e.pos - repaired.pos).normalized() * reach * 0.8, _radius(e), int(e.id), 4.0, false)
		if goal.is_finite(): _move_to(e, goal, delta)
		else: e.state = "unreachable"
		return
	if repaired.kind == "unit" and not _segment_static(e.pos, repaired.pos, .05, int(e.id)):
		e.state = "waiting"
		return
	if repaired.kind == "building":
		var healed: float = max_hp(repaired) - float(repaired.hp)
		var cost: float = healed * float(_eco("repair_cost", 0.2))
		if money[int(e.team)] + 0.000001 < cost:
			e.state = "waiting"
			return
		money[int(e.team)] = maxf(0.0, money[int(e.team)] - cost)
		repaired.hp = max_hp(repaired)
		events.append({"kind": "repair", "id": target, "pos": repaired.pos, "team": e.team})
		_finish_command(e)
		return
	_field_repairers[target] = maxf(float(_field_repairers.get(target, 0.0)), float(info.get("repair_rate", 8.0)))
	e.state = "repair"

func _engineering_distance(e: Dictionary, target: Dictionary) -> float:
	if target.kind != "building": return (e.pos as Vector2).distance_to(target.pos)
	var half: Vector2 = Vector2.ONE * float(data_for(target.spec).size) * 0.5
	return (e.pos as Vector2).distance_to((e.pos as Vector2).clamp(target.pos - half, target.pos + half))

func _step_capture(e: Dictionary, command: Dictionary, delta: float) -> void:
	var target_id: int = int(command.target)
	var error: String = capture_error(int(e.id), target_id)
	if not error.is_empty():
		_finish_command(e)
		if int(e.team) == 0: _notice(error)
		return
	var target: Dictionary = entities[target_id]
	if _engineering_distance(e, target) > float(data_for(e.spec).get("repair_radius", 1.8)):
		var goal: Vector2 = _refinery_approach(e, target)
		if goal.is_finite(): _move_to(e, goal, delta)
		else: e.state = "unreachable"
		return
	var old_team: int = int(target.team)
	ProductionLifecycle.before_capture(self, target)
	for order in target.queue: _refund_order(old_team, order)
	target.queue.clear()
	_detach_aircraft(target_id)
	_spatial_remove(target_id, target.pos)
	target.team = int(e.team)
	_invalidate_base_cache()
	target.captured = true
	target.repairing = false
	target.gift_pending = false
	target.blocked_notice = false
	target.auto_target = -1
	target.turret_target = -1
	target.state = "idle"
	_spatial_add(target_id, target.pos)
	for unit in entities.values():
		if unit.kind != "unit" or unit.team != e.team: continue
		if not unit.commands.is_empty() and unit.commands[0].kind == "attack" and int(unit.commands[0].target) == target_id: _finish_command(unit)
		if int(unit.auto_target) == target_id: unit.auto_target = -1
		if int(unit.turret_target) == target_id: unit.turret_target = -1
	events.append({"kind": "capture", "id": target_id, "pos": target.pos, "team": e.team, "previous_team": old_team})
	_finish_command(e)
	_check_result()

func _step_deploy_outpost(e: Dictionary, command: Dictionary, delta: float) -> void:
	var spec: String = str(command.get("spec", ""))
	if not _builder_valid(int(e.team), int(e.id)) or not rules.buildings.has(spec) or not TechAvailability.engineer_building(self, int(e.team), data_for(spec)):
		_finish_command(e)
		return
	var pos: Vector2 = command.pos
	var info: Dictionary = data_for(spec)
	var half: Vector2 = Vector2.ONE * float(info.size) * 0.5
	var edge_distance: float = (e.pos as Vector2).distance_to((e.pos as Vector2).clamp(pos - half, pos + half))
	# _move_to accepts arrival within 0.25 of the perimeter approach point.
	if edge_distance > _radius(e) + 0.5 or _circle_rect(e.pos, _radius(e), pos, half):
		var goal: Vector2 = FieldConstruction.approach(self, e, {"pos": pos, "spec": spec,"rotation_quarters":BuildingOrientation.quarters(command)})
		if goal.is_finite(): _move_to(e, goal, delta)
		else: e.state = "unreachable"
		return
	var error: String = _requirements(int(e.team), info)
	if error.is_empty(): error = _building_site_error(int(e.team), info, pos, int(e.id),BuildingOrientation.quarters(command))
	if not error.is_empty():
		e.state = "waiting"
		if error == "单位占据建筑位置" and ai_enabled and int(e.team) > 0:
			_ai_clear_construction_site(e, info, pos)
		if not bool(command.get("blocked_notice", false)) and int(e.team) == 0:
			command.blocked_notice = true
			_notice("建筑等待施工：" + error)
		return
	var id: int = _spawn(int(e.team), spec, pos, false,BuildingOrientation.quarters(command))
	Construction.initialize(self, entities[id], int(e.id))
	command.kind = "resume_outpost"
	command.target = id
	command.pos = pos
	command.erase("spec")
	command.erase("cost")
	e.hold_position = true
	events.append({"kind": "build", "pos": pos, "id": id, "team": e.team, "spec": spec, "entity_kind": "building", "construction_method": "scaffold"})

func _ai_clear_construction_site(builder: Dictionary, info: Dictionary, pos: Vector2) -> void:
	var half: float = float(info.size) * 0.5
	for unit in entities.values():
		if int(unit.id) == int(builder.id) or int(unit.team) != int(builder.team) or unit.kind != "unit" or Transport.is_loaded(unit) or _is_air(unit) or _is_naval(unit): continue
		if not _circle_rect(unit.pos, _radius(unit), pos, Vector2.ONE * half): continue
		if not unit.commands.is_empty():
			if unit.commands[0].kind != "move" or not _circle_rect(unit.commands[0].pos, _radius(unit), pos, Vector2.ONE * half): continue
		var direction: Vector2 = (unit.pos as Vector2) - pos
		if direction.length_squared() < .01: direction = Vector2.from_angle(float(unit.id) * 2.4)
		var wanted: Vector2 = pos + direction.normalized() * (half * 1.42 + _radius(unit) + 2.0)
		var goal: Vector2 = _near_stand(wanted, _radius(unit), int(unit.id), 2.0)
		if goal.is_finite() and not _circle_rect(goal, _radius(unit), pos, Vector2.ONE * half): issue([int(unit.id)], "move", goal)

func _step_resume_outpost(e: Dictionary, command: Dictionary, delta: float) -> void:
	var id: int = int(command.target)
	if not resume_outpost_error(int(e.id), id).is_empty():
		_finish_command(e)
		return
	var construction: Dictionary = entities[id].construction
	if int(construction.builder) != int(e.id): Construction.assign_builder(self, int(e.id), id)
	if _engineering_distance(e, entities[id]) > _radius(e) + 0.5:
		var goal: Vector2 = FieldConstruction.approach(self, e, entities[id])
		if goal.is_finite(): _move_to(e, goal, delta)
		else: e.state = "unreachable"

func _step_support(delta: float, _multipliers: Array[float]) -> void:
	for id in _field_repairers:
		if not entities.has(id): continue
		var target: Dictionary = entities[id]
		if float(target.hp) > 0: _repair_health(target, float(_field_repairers[id]) * delta)

func _repair_health(e: Dictionary, amount: float) -> void:
	var cost: float = float(_eco("repair_cost", 0.2))
	var healed: float = minf(amount, max_hp(e) - float(e.hp))
	if cost > 0.0: healed = minf(healed, money[int(e.team)] / cost)
	e.hp += healed
	money[int(e.team)] = maxf(0.0, money[int(e.team)] - healed * cost)

func _has_turret(spec: Dictionary) -> bool:
	# Existing v1 rule snapshots predate the flags; their known vehicle art migrates.
	return bool(spec.get("has_turret", spec.get("art", "") in ["tank", "assault"]))

func _can_move_fire(spec: Dictionary) -> bool:
	return _has_turret(spec) and bool(spec.get("fire_while_moving", true))

func _mobile_acquire_and_fire(e: Dictionary, delta: float) -> void:
	var weapon_id: String = str(data_for(e.spec).get("weapon", ""))
	if weapon_id == "":
		_turret_forward(e, delta)
		return
	var range_value: float = float(weapon_for(e,weapon_id).range)
	var target: int = int(e.auto_target)
	if not _target_alive(target) or not _weapon_can_target(e, target) or _target_position(target).distance_to(e.pos) > range_value:
		target = _nearest_enemy(e, range_value)
	e.auto_target = target
	if target != -1:
		_aim_turret(e, target, delta)
	else:
		_turret_forward(e, delta)

func _turret_forward(e: Dictionary, delta: float) -> void:
	e.turret_target = -1
	_turn_turret(e, float(e.alpha), delta)

func _aim_turret(e: Dictionary, target: int, delta: float) -> void:
	if not _target_alive(target) or not _weapon_can_target(e, target):
		_turret_forward(e, delta)
		return
	e.turret_target = target
	var wanted: float = rad_to_deg((_target_position(target) - (e.pos as Vector2)).angle())
	_turn_turret(e, wanted, delta)
	if float(e.motion) > 0.0 and not _can_move_fire(data_for(e.spec)):
		return
	if absf(wrapf(wanted - float(e.turret_alpha), -180.0, 180.0)) <= float(_eco("fire_angle", 15)):
		_fire(e, target)

func _turn_turret(e: Dictionary, wanted: float, delta: float) -> void:
	var spec: Dictionary = data_for(e.spec)
	var current: float = float(e.get("turret_alpha", e.alpha))
	var angle_delta: float = wrapf(wanted - current, -180.0, 180.0)
	var speed: float = float(spec.get("turret_turn_speed", spec.get("turn_speed", 360)))
	e.turret_alpha = wrapf(current + clampf(angle_delta, -speed * delta, speed * delta), -180.0, 180.0)

func _finish_command(e: Dictionary) -> void:
	if not e.commands.is_empty():
		var finished: Dictionary = e.commands.pop_front()
		if finished.kind == "patrol": e.commands.append(finished)
		if finished.kind == "resume_outpost": e.hold_position = false
	e.path.clear()
	e.path_goal = Vector2.INF
	e.auto_target = -1
	e.turret_target = -1
	e.state = "idle"

func _configure_crushing(e: Dictionary, info: Dictionary) -> void:
	e.surface_domain="ground" if bool(info.get("amphibious",false)) and _terrain(e.pos)!=MapData.WATER else str(info.get("domain","ground"))
	e.submarine=bool(info.get("submarine",false));e.anti_submarine=bool(info.get("anti_submarine",false))
	e.veteran=bool(e.get("veteran",false));e.experience_value=float(e.get("experience_value",0))
	e.max_hp=max_hp(e)
	# Cache the rule classes with the collision radius, both on spawn and load.
	# Rail-only units and non-ground domains never take part in ground crushing.
	e.ground_infantry = e.kind == "unit" and str(info.get("domain","ground")) == "ground" and str(info.get("armor_class","infantry" if bool(info.get("crushable",false)) else "armored")) == "infantry"
	e.ground_vehicle = e.kind == "unit" and str(info.get("domain","ground")) == "ground" and not bool(e.ground_infantry) and not RailNetwork.rail_only(info)
	e.ground_crush_eligible = e.kind == "unit" and str(info.get("domain","ground")) == "ground" and not RailNetwork.rail_only(info)
	e.crush_strength = int(info.get("crush_strength",1 if bool(info.get("crush",false)) else 0))
	e.crush_resistance = int(info.get("crush_resistance",0 if bool(info.get("crushable",false)) else 99))
	e.can_crush = bool(e.ground_crush_eligible) and bool(info.get("crush",false)) and int(e.crush_strength)>0

func _is_ground_vehicle(e: Dictionary) -> bool:
	if e.has("ground_vehicle"): return bool(e.ground_vehicle)
	var info: Dictionary = data_for(str(e.spec))
	return e.kind == "unit" and str(info.get("domain","ground")) == "ground" and str(info.get("armor_class","infantry" if bool(info.get("crushable",false)) else "armored")) != "infantry" and not RailNetwork.rail_only(info)

func _query_is_infantry(ignore: int) -> bool:
	# Unidentified factory-placement queries are conservative. A real infantry
	# id is required to pass the vehicle-only barricade collider.
	if not entities.has(ignore): return false
	var e: Dictionary = entities[ignore]
	if e.has("ground_infantry"): return bool(e.ground_infantry)
	var info: Dictionary = data_for(str(e.spec))
	return e.kind == "unit" and str(info.get("domain","ground")) == "ground" and str(info.get("armor_class","infantry" if bool(info.get("crushable",false)) else "armored")) == "infantry"

func _can_crush_target(e: Dictionary, other: Dictionary) -> bool:
	return bool(e.get("can_crush",false)) and bool(e.get("ground_crush_eligible",false)) and bool(other.get("ground_crush_eligible",false)) and int(other.team) != int(e.team) and int(e.get("crush_strength",0))>int(other.get("crush_resistance",99))

func _apply_ground_crush(source: Dictionary, target: Dictionary) -> void:
	# Contact is swept by movement before arrival; no teleport or ranged damage.
	var damage: float = maxf(0,float(target.hp))
	if damage<=0: return
	target.last_damage_cause = {"source":int(source.id),"source_team":int(source.team),"weapon":"ground_crush","explosive":false}
	_damage_causes[int(target.id)] = target.last_damage_cause.duplicate()
	statistics.add(int(source.team),"damage_dealt",maxf(0,damage-float(_damage.get(int(target.id),0))))
	statistics.add(int(target.team),"damage_received",maxf(0,damage-float(_damage.get(int(target.id),0))))
	target.hp = 0.0
	events.append({"kind":"crush","id":int(source.id),"target":int(target.id),"pos":target.pos,"team":int(source.team),"damage":damage})
	_update_contact(target)

func _step_force_move(e: Dictionary, command: Dictionary, delta: float) -> void:
	var target: int = int(command.target)
	var goal: Vector2 = command.pos
	if entities.has(target) and entities[target].kind == "unit" and not Transport.is_loaded(entities[target]) and entity_visible_to(int(e.team), target):
		goal = entities[target].pos
		command.pos = goal
	if _move_order(e, command, delta):
		_settle_crushing(e, e.pos)
		_finish_command(e)
	if _has_turret(data_for(e.spec)): _turret_forward(e, delta)

func _step_ground_attack(e: Dictionary, command: Dictionary, delta: float) -> void:
	var weapon_id: String = str(data_for(e.spec).get("weapon", ""))
	if weapon_id.is_empty() or "ground" not in rules.weapons[weapon_id].get("targets", ["ground"]):
		_finish_command(e)
		return
	var landing: Vector2 = command.pos
	var reach: float = float(weapon_for(e,weapon_id).range)
	if (e.pos as Vector2).distance_to(landing) > reach:
		var goal: Vector2 = _combat_approach(e, landing, reach)
		if goal.is_finite(): _move_to(e, goal, delta)
		else: e.state = "unreachable"
		return
	var wanted: float = rad_to_deg((landing - (e.pos as Vector2)).angle())
	if _has_turret(data_for(e.spec)): _turn_turret(e, wanted, delta)
	else: _turn(e, wanted, delta)
	var actual: float = float(e.turret_alpha) if _has_turret(data_for(e.spec)) else float(e.alpha)
	if absf(wrapf(wanted - actual, -180.0, 180.0)) <= float(_eco("fire_angle", 15)):
		_launch_shot(e, landing, -1, true)

func _engage(e: Dictionary, target: int, delta: float, pursue: bool) -> void:
	if not _weapon_can_target(e, target): return
	if ZeppelinWeapons.is_zeppelin(self,e) and ZeppelinWeapons.engage_air(self,e,target,delta,pursue): return
	var spec: Dictionary = data_for(e.spec)
	var weapon_id: String = str(spec.get("weapon", ""))
	if weapon_id == "":
		e.state = "waiting"
		return
	var weapon: Dictionary = weapon_for(e,weapon_id)
	var target_pos: Vector2 = _target_position(target)
	var distance: float = e.pos.distance_to(target_pos)
	if distance > float(weapon.range):
		if pursue:
			_pursue_target(e, target, target_pos, float(weapon.range), delta)
		if _has_turret(spec):
			_aim_turret(e, target, delta)
		return
	e.state = "idle"
	if _has_turret(spec):
		_aim_turret(e, target, delta)
	else:
		var wanted: float = rad_to_deg((target_pos - e.pos).angle())
		_turn(e, wanted, delta)
		if absf(wrapf(wanted - float(e.alpha), -180.0, 180.0)) <= float(_eco("fire_angle", 15)):
			_fire(e, target)

func _pursue_target(e: Dictionary, target: int, target_pos: Vector2, reach: float, delta: float) -> void:
	var goal: Vector2 = e.get("pursuit_goal", Vector2.INF)
	if int(e.get("pursuit_target", -1)) != target or not goal.is_finite() or (time >= float(e.get("pursuit_refresh_at", 0.0)) and (target_pos as Vector2).distance_squared_to(e.get("pursuit_target_pos", Vector2.INF)) > .25):
		goal = _combat_approach(e, target_pos, reach)
		e.pursuit_goal = goal; e.pursuit_target = target; e.pursuit_target_pos = target_pos
		e.pursuit_refresh_at = time + .2
		navigation_pursuit_refreshes += 1
	if not goal.is_finite(): e.state = "unreachable"; return
	if _is_air(e) or _is_naval(e):
		_move_to(e,goal,delta);return
	var radius: float = _radius(e)
	# A continuously moving target must not make the original path_wait stop
	# the pursuer. Direct safe approaches update the last leg without AStar.
	if _segment_static(e.pos, goal, radius, int(e.id)):
		_cancel_path_request(int(e.id))
		e.path = [goal]; e.path_goal = goal
		_move_to(e, goal, delta)
		return
	if not e.path.is_empty() and (e.path_goal as Vector2).distance_to(goal) > 1.0:
		# Keep advancing the old checked corridor while its replacement is
		# queued/running; only swap a path after a usable connector is proven.
		if float(e.path_wait) <= 0.0:
			e.pursuit_request = true
			var replacement: Array = _path_between(e.pos, goal, radius, int(e.id))
			e.pursuit_request = false
			if not _plan_was_deferred and not replacement.is_empty() and _segment_static(e.pos, replacement[0], radius, int(e.id)):
				e.path = replacement; e.path_goal = goal; e.path_wait = .4
		_move_to(e, e.path_goal, delta)
	else: _move_to(e, goal, delta)

func _combat_approach(e: Dictionary, target_pos: Vector2, reach: float) -> Vector2:
	if RailNetwork.rail_only(data_for(e.spec)):
		return _rail_network.nearest_connected(self, e, target_pos, maxf(0.0, reach - .5))
	# Movement may report arrival up to a fraction of the hull radius before
	# its destination. Place the destination farther inside weapon range, and
	# reject nearby legal positions that would put that arrival band outside it.
	var radius: float = _radius(e)
	var naval: bool = _is_naval(e)
	var tolerance: float = maxf(0.26, radius * 0.35) if naval else maxf(0.25, radius * 0.4)
	var safe_reach: float = reach - tolerance - 0.1
	if safe_reach <= 0.0: return Vector2.INF
	var preferred: float = minf(safe_reach, maxf(0.35, safe_reach - 0.9))
	var direction: Vector2 = (e.pos as Vector2) - target_pos
	if direction.is_zero_approx(): direction = Vector2.RIGHT
	else: direction = direction.normalized()
	var desired: Vector2 = target_pos + direction * preferred
	if _is_air(e): return _air_goal(desired)
	var candidate: Vector2
	if naval:
		var nav = NavalOperations._nav(self)
		candidate = nav.near_water(self, desired, radius, float(data_for(str(e.spec)).get("naval_air_draft", 1.5)), int(e.id), 2.0, false)
	else:
		candidate = _near_stand(desired, radius, int(e.id), 2.0, false)
	if candidate.is_finite() and candidate.distance_to(target_pos) <= safe_reach: return candidate
	# Search inward and around the target when a building edge or shore shifts
	# the first stand point outward. Every returned point remains collision legal.
	var nav_search = NavalOperations._nav(self) if naval else null
	var draft: float = float(data_for(str(e.spec)).get("naval_air_draft", 1.5))
	for ring in range(10):
		var radial: float = preferred - float(ring) * 0.5
		if radial < 0.35: break
		for angle: float in [0.0, -PI / 8.0, PI / 8.0, -PI / 4.0, PI / 4.0, -PI / 2.0, PI / 2.0, PI]:
			var point: Vector2 = target_pos + direction.rotated(angle) * radial
			if naval:
				if nav_search.water_clear(self, point, radius, draft, int(e.id), false): return point
			elif _standing(point, radius, int(e.id), false): return point
	return Vector2.INF

func _turn(e: Dictionary, wanted: float, delta: float) -> void:
	var angle_delta: float = wrapf(wanted - float(e.alpha), -180.0, 180.0)
	var speed: float = float(data_for(e.spec).get("turn_speed", 360))
	e.alpha = wrapf(float(e.alpha) + clampf(angle_delta, -speed * delta, speed * delta), -180.0, 180.0)

func _fire(e: Dictionary, target: int) -> void:
	if float(e.get("emp_until", 0.0)) > time or float(e.cooldown) > 0.0 or not _target_alive(target) or not _weapon_can_target(e, target):
		return
	if HeroRules.begin(self, e, target, _target_position(target), _force_attack_active(e, target)): return
	_launch_shot(e, _target_position(target), target, _force_attack_active(e, target))

func _launch_shot(e: Dictionary, landing: Vector2, target: int, force: bool) -> void:
	if float(e.get("emp_until", 0.0)) > time or float(e.cooldown) > 0.0 or Transport.is_loaded(e): return
	if AirNavalExpansion.carrier_fire(self,e,target):return
	if not bool(e.get("hand_resolving", false)) and HeroRules.begin(self, e, target, landing, force): return
	var weapon_id: String = str(data_for(e.spec).get("weapon", ""))
	if weapon_id == "":
		return
	var weapon: Dictionary = weapon_for(e,weapon_id)
	weapon.weapon=weapon_id
	weapon.source=int(e.id)
	if str(weapon.get("trajectory","")) == "gravity_bomb":
		if not bool(e.get("airborne",true)): return
		if target > 0 and entities.has(target) and _target_domain(entities[target]) not in weapon.get("targets",["ground","naval"]): return
	var shot_damage: float = float(weapon.damage)
	if _is_air(e) and not AirNavalExpansion.permanent(self,e) and (int(e.ammo) <= 0 or e.flight_state in ["returning", "rearming"]): return
	if e.pos.distance_to(landing) > float(weapon.range) + 0.001:
		return
	var heading: float = float(e.turret_alpha) if e.kind == "building" or _has_turret(data_for(e.spec)) else float(e.alpha)
	if _has_turret(data_for(e.spec)):
		var wanted: float = rad_to_deg((landing - (e.pos as Vector2)).angle())
		if absf(wrapf(wanted - heading, -180.0, 180.0)) > float(_eco("fire_angle", 15)) or (float(e.motion) > 0.0 and not _can_move_fire(data_for(e.spec))):
			return
	shot_damage *= FactionSupport.damage_scale(self, e, target)
	FactionTraits.record_attack(self, e)
	if _is_air(e) and not AirNavalExpansion.permanent(self,e):
		e.ammo = maxi(0, int(e.ammo) - 1)
		if int(e.ammo) == 0: _begin_return(e)
	AirNavalExpansion.record_fire(self,e)
	e.cooldown = float(weapon.interval)
	e.attack_flash = 0.25
	e.state = "move" if float(e.motion) > 0.0 else "attack"
	if str(weapon.get("trajectory","")) == "gravity_bomb":
		ZeppelinWeapons.launch_bomb(self,e,weapon_id,shot_damage,target,force)
		return
	events.append({"kind": "fire", "pos": e.pos, "landing": landing, "target": target, "id": e.id, "team": e.team, "weapon": weapon_id, "spec": e.spec, "heading": heading, "body_heading": float(e.alpha), "height": _source_height(e), "target_height": _target_height(target), "moving": float(e.motion) > 0.0})
	if weapon.kind == "beam":
		if target != -1: BeamWeapons.begin(self, e, target, weapon_id, force)
	elif weapon.kind in ["instant", "laser"]:
		if float(weapon.get("blast", 0.0)) > 0:
			_impact_damage(landing, float(weapon.blast), shot_damage, weapon.get("multipliers", {}), weapon.get("targets", ["ground"]), force, weapon, int(e.team))
		elif target != -1:
			_add_damage(target, _weapon_damage(shot_damage,target,weapon), force, {"source":int(e.id),"source_team":int(e.team),"weapon":weapon_id,"explosive":float(weapon.get("blast",0.0))>0.0})
			_mark_creator_contact(e,target)
			if bool(weapon.get("execute_building", false)) and entities.has(target) and entities[target].kind == "building": _execute_buildings[target] = true
			FactionTraits.apply_emp(self, target, weapon, int(e.team))
		else:
			_impact_damage(landing, float(weapon.blast), shot_damage, weapon.get("multipliers", {}), weapon.get("targets", ["ground"]), force, weapon, int(e.team))
		events.append({"kind":"impact", "pos":landing, "blast":float(weapon.blast), "team":int(e.team), "source_id":int(e.id), "target":target, "weapon":weapon_id, "spec":e.spec, "projectile":false, "height":_impact_event_height(landing,weapon.get("targets",["ground"]),target)})
	else:
		var duration: float = maxf(0.2, e.pos.distance_to(landing) / maxf(float(weapon.get("speed", 18)), 0.001))
		projectiles.append({"pos": e.pos, "start": e.pos, "landing": landing, "elapsed": 0.0, "duration": duration, "damage": shot_damage, "blast": float(weapon.blast), "team": int(e.team), "source": int(e.id), "spec": str(e.spec), "weapon": weapon_id, "emp_vehicle_duration": float(weapon.get("emp_vehicle_duration", 0.0)), "emp_building_duration": float(weapon.get("emp_building_duration", 0.0)), "heading": heading, "body_heading": float(e.alpha), "targets": weapon.get("targets", ["ground"]).duplicate(), "multipliers": weapon.get("multipliers", {}).duplicate(), "target": target, "source_height": _source_height(e), "target_height": _target_height(target), "force": force})

func _mark_creator_contact(source: Dictionary, target: int) -> void:
	if target>0 and entities.has(target) and bool(source.get("hand_resolving",false)) and bool(data_for(source.spec).get("hero",false)):
		_crush_targets[target] = true

func _impact_damage(center: Vector2, blast: float, damage: float, multipliers: Dictionary, targets: Array, force: bool, weapon: Dictionary = {}, source_team: int = -1) -> void:
	var info: Dictionary=ArmorCombat.weapon(self,weapon)
	info=info.duplicate()
	info.multipliers=multipliers
	for e in _nearby_entities(center, blast + _max_entity_extent):
		if float(e.hp) <= 0.0 or Transport.is_loaded(e) or _target_domain(e) not in targets: continue
		if not bool(info.get("friendly_fire",true)) and int(e.team)==source_team and not force: continue
		if entities.has(int(info.get("source",-1))) and not AirNavalExpansion.can_target(self,entities[int(info.source)],int(e.id)):continue
		var hit: bool = _circle_rect(center, blast, e.pos, Vector2.ONE * float(data_for(e.spec).size) * 0.5) if e.kind == "building" else center.distance_to(e.pos) <= blast + _radius(e)
		if hit:
			var factor: float=ArmorCombat.falloff(info,ArmorCombat.distance_to_body(self,center,e),blast)
			_add_damage(int(e.id), _weapon_damage(damage,int(e.id),info,factor), force, {"source":int(info.get("source",-1)),"source_team":source_team,"weapon":str(info.get("weapon","")),"explosive":blast>0.0 or str(info.get("kind",""))=="shell" or info.has("duration")})
			if int(info.get("source",-1))>0 and entities.has(int(info.source)): _mark_creator_contact(entities[int(info.source)],int(e.id))
			if bool(weapon.get("execute_building", false)) and e.kind == "building": _execute_buildings[int(e.id)] = true
			FactionTraits.apply_emp(self, int(e.id), weapon, source_team)
	if "ground" in targets:
		for ruin in _nearby_ruins(center, blast):
			if (force or GarrisonOperations.hostile(self,source_team,RUIN_TARGET_BASE-int(ruin.id))) and float(ruin.hp) > 0.0 and _circle_rect(center, blast, ruin.pos, ruin.half):
				var factor: float=ArmorCombat.falloff(info,ArmorCombat.distance_to_rectangle(center,ruin.pos,ruin.half),blast)
				_add_damage(RUIN_TARGET_BASE-int(ruin.id),damage*factor*ArmorCombat.penetration_factor(info,0,factor,rules.get("combat_model",{})),force,{"source":int(info.get("source",-1)),"source_team":source_team,"weapon":str(info.get("weapon",""))})
	for bridge in bridges:
		if "ground" in targets and bool(bridge.alive) and _circle_bounds(center, blast, bridge.bounds):
			var bounds: Array=bridge.bounds
			var half: Vector2=Vector2(float(bounds[2]),float(bounds[3]))*.5
			var pos: Vector2=Vector2(float(bounds[0]),float(bounds[1]))+half
			var factor: float=ArmorCombat.falloff(info,ArmorCombat.distance_to_rectangle(center,pos,half),blast)
			_add_damage(BRIDGE_TARGET_BASE-int(bridge.id),damage*factor*ArmorCombat.penetration_factor(info,0,factor,rules.get("combat_model",{})))

func _step_projectiles(delta: float) -> void:
	ZeppelinWeapons.step_secondary(self,delta)
	for index in range(projectiles.size() - 1, -1, -1):
		var shell: Dictionary = projectiles[index]
		if str(shell.get("trajectory","")) == "gravity_bomb":
			if not ZeppelinWeapons.step_bomb(self,shell,delta): continue
		else:
			if "air" in shell.get("targets", ["ground"]) and _target_alive(int(shell.get("target", -1))):
				shell.landing = _target_position(int(shell.target))
				shell.target_height = _target_height(int(shell.target))
			shell.elapsed = float(shell.elapsed) + delta
			shell.pos = (shell.start as Vector2).lerp(shell.landing, minf(1.0, float(shell.elapsed) / float(shell.duration)))
			if float(shell.elapsed) < float(shell.duration): continue
		var center: Vector2 = shell.landing
		var blast: float = float(shell.blast)
		_impact_damage(center, blast, float(shell.damage), shell.get("multipliers", {}), shell.get("targets", ["ground"]), bool(shell.get("force", false)), shell, int(shell.get("team", -1)))
		events.append({"kind": "impact", "pos": center, "blast": blast, "team":int(shell.get("team", -1)), "source_id":int(shell.get("source",-1)), "target":int(shell.get("target",-1)), "weapon":str(shell.get("weapon", "")), "spec":str(shell.get("spec", "")), "projectile":true, "height": _impact_event_height(center,shell.get("targets",["ground"]),int(shell.get("target",-1)))})
		projectiles.remove_at(index)

func _add_damage(id: int, amount: float, force: bool = false, cause: Dictionary = {}) -> void:
	if id <= RUIN_TARGET_BASE and not force and not GarrisonOperations.hostile(self,int(cause.get("source_team",-1)),id): return
	if entities.has(id) and float(_damage.get(id,0.0))<float(entities[id].hp):
		_damage_causes[id]=cause.duplicate()
		statistics.add(int(cause.get("source_team",-1)),"damage_dealt",minf(amount,maxf(0,float(entities[id].hp)-float(_damage.get(id,0.0)))))
		statistics.add(int(entities[id].team),"damage_received",minf(amount,maxf(0,float(entities[id].hp)-float(_damage.get(id,0.0)))))
	_damage[id] = float(_damage.get(id, 0.0)) + amount

func _apply_damage() -> void:
	# All shots/impacts/crushing in a tick settle before either team is declared defeated.
	for raw_id in _damage.keys():
		var id: int = int(raw_id)
		if id <= RUIN_TARGET_BASE:
			var ruin: Dictionary = ruin_by_target(id)
			if not ruin.is_empty() and float(ruin.hp)>0:
				ruin.hp=maxf(0,float(ruin.hp)-float(_damage[id]))
				if float(ruin.hp)<float(ruin.max_hp)*.2:GarrisonOperations.unload(self,id,true)
				if float(ruin.hp)<=0:
					_ruin_geometry_dirty[int(ruin.id) / RUIN_GEOMETRY_CHUNK_SIZE] = true
					_mark_nav_region(Rect2(ruin.pos-ruin.half,ruin.half*2))
					events.append({"kind":"ruin_destroy","id":int(ruin.id),"pos":ruin.pos,"radius":ruin.half.length()})
		elif id <= BRIDGE_TARGET_BASE:
			var bridge: Dictionary = _bridge_by_id(BRIDGE_TARGET_BASE - id)
			if not bridge.is_empty() and bool(bridge.alive):
				bridge.hp = maxf(0.0, float(bridge.hp) - float(_damage[id]))
				if float(bridge.hp) <= 0.0:
					bridge.alive = false
					_rail_network.destroy_bridge(self, bridge.bounds)
					bridge.repair_progress = 0.0
					var bounds: Array = bridge.bounds
					_mark_nav_region(Rect2(float(bounds[0]), float(bounds[1]), float(bounds[2]), float(bounds[3])))
					for e in entities.values():
						if e.kind == "unit" and not _is_air(e) and not Transport.is_loaded(e) and _point_bounds(e.pos, bridge.bounds):
							e.hp = 0.0
					events.append({"kind": "impact", "pos": _bridge_center(bridge), "blast": 3.0, "team":-1, "height":_impact_event_height(_bridge_center(bridge),["ground"])})
		elif entities.has(id) and not Transport.is_loaded(entities[id]):
			var e: Dictionary = entities[id]
			var settled: float = float(_damage[id])
			e.last_damage_cause=_damage_causes.get(id,{}).duplicate()
			e.hp = 0.0 if bool(_execute_buildings.get(id, false)) else maxf(0.0, float(e.hp) - settled)
			if settled > 0.0: FactionTraits.record_damage(self, e)
			e.hit_flash = 0.18
			if settled > 0.0 and float(e.hp) > 0.0 and time >= float(_damage_voice_next.get(id, -INF)):
				_damage_voice_next[id] = time + 4.5
				events.append({"kind": "under_attack", "id": id, "spec": e.spec, "team": e.team, "pos": e.pos, "height": _source_height(e), "damage": settled})
	for raw_id in entities.keys():
		var id: int = int(raw_id)
		if entities.has(id) and float(entities[id].hp) <= 0.0:
			_kill_entity(id, true)
	_crush_targets.clear()

func _detach_aircraft(building_id: int) -> void:
	for aircraft in entities.values():
		if _is_air(aircraft) and int(aircraft.home_airfield) == building_id:
			_set_home_airfield(aircraft, -1)
			aircraft.rearm_remaining = 0.0
			if not bool(aircraft.get("airborne", true)):
				_wait_for_takeoff(aircraft, int(aircraft.ammo) == 0)
			else:
				aircraft.flight_state = "returning" if int(aircraft.ammo) == 0 else "airborne"
				aircraft.flight_height = float(data_for(aircraft.spec).flight_height)

func _kill_entity(id: int, destroyed: bool) -> void:
	if not entities.has(id):
		return
	var e: Dictionary = entities[id]
	ProductionLifecycle.remove(self, e)
	RefineryDocking.release(self,e)
	if data_for(e.spec).get("role", "") == "drill": MiningDrills.release(self, e)
	_invalidate_base_cache()
	_goal_standing_cache.erase(id)
	if _is_air(e): _airfield_counts_dirty = true
	_release_mine(id)
	for building in _building_entities:
		if building.has("construction") and int(building.construction.builder) == id:
			building.construction.builder = -1
			building.construction.work_state = "paused"
			building.construction.pause_reason = "等待工程兵接手"
	Transport.remove(self, e, destroyed)
	for team in range(factions.size()):
		for channel in ["normal", "defense"]:
			if int(order_for_team(team, channel).get("builder", -1)) == id: cancel_build(team, channel)
	if e.kind == "building":
		_spatial_remove(id, e.pos)
		_building_entities.erase(e)
		_refresh_building_spatial()
		for order in e.queue:
			_refund_order(int(e.team), order)
		_detach_aircraft(id)
		var half: Vector2 = Vector2.ONE * float(data_for(e.spec).size) * 0.5
		_mark_nav_region(Rect2(e.pos - half, half * 2.0))
	else:
		_spatial_remove(id, e.pos)
	var death_info: Dictionary = data_for(e.spec)
	var death_cause: Dictionary = e.get("last_damage_cause",_damage_causes.get(id,{}))
	var death_event: Dictionary = {"kind": "death", "pos": e.pos, "spec": e.spec, "alpha": e.alpha, "id": id, "team": e.team, "destroyed": destroyed, "height": _source_height(e), "entity_kind": e.kind, "domain": str(death_info.get("domain", "ground")), "size": float(death_info.get("size", 1.0)), "radius": float(death_info.get("radius", .35))}
	if str(death_info.get("domain","ground"))=="air":
		var flight_velocity: Vector2=Vector2.from_angle(deg_to_rad(float(e.alpha)))*maxf(0.0,float(e.get("motion",0.0)))
		if e.get("air_motion_from") is Vector2 and is_equal_approx(float(e.get("air_motion_time",-1.0)),time):
			flight_velocity=((e.pos as Vector2)-(e.air_motion_from as Vector2))/maxf(_step_delta,.001)
		death_event.merge({"velocity":flight_velocity,"heading":float(e.alpha),"flight_height":float(e.get("flight_height",death_info.get("flight_height",4.0))),"airborne":bool(e.get("airborne",true))})
	death_event.cause=death_cause.duplicate()
	if destroyed:
		Veterancy.destroyed(self,e,death_cause)
		if not RailNetwork.is_rail(death_info): statistics.destroyed(e,death_cause,death_info)
		if e.kind=="unit" and str(death_info.get("armor_class",""))=="infantry":
			death_event.death_style="infantry_shatter" if bool(death_cause.get("explosive",false)) else "infantry_fall"
	if destroyed and bool(_crush_targets.get(id,false)): death_event.death_style = "creator_crush"
	events.append(death_event)
	_planning_queue.erase(id)
	_cancel_path_request(id)
	entities.erase(id)
	_damage_causes.erase(id)
	_damage_voice_next.erase(id)

func _is_victory_building(entity: Dictionary) -> bool:
	# Physical obstacles still belong to their owner and retain their economy,
	# collision and sale behavior, but cannot keep an eliminated base alive.
	return str(entity.get("kind", "")) == "building" and float(entity.get("hp", 0.0)) > 0.0 and str(data_for(str(entity.spec)).get("role", "")) not in ["wall", "barricade", "rail", "rail_junction"]

func match_statistics() -> Dictionary:
	return statistics.snapshot(self)


func _check_result() -> void:
	if result != "":
		return
	if campaign_controller != null:
		if bool(campaign_controller.get("finished")):
			result = "win"
		else:
			var hq_alive: bool = false
			for e in _building_entities:
				if int(e.team) == 0 and float(e.hp) > 0.0 and data_for(str(e.spec)).get("role", "") == "hq": hq_alive = true
			if not hq_alive: result = "lose"
		if result != "": events.append({"kind":"result", "pos":Vector2.ZERO, "result":result})
		return
	var buildings: Array[bool] = []
	buildings.resize(factions.size())
	buildings.fill(false)
	for e in _building_entities:
		if _is_victory_building(e): buildings[int(e.team)] = true
	var player_dead: bool = not buildings[0]
	var enemy_dead: bool = true
	for team in range(1, factions.size()):
		if buildings[team]: enemy_dead = false
	if not player_dead and not enemy_dead:
		return
	result = "draw" if factions.size() == 2 and player_dead and enemy_dead else ("lose" if player_dead else "win")
	events.append({"kind": "result", "pos": Vector2.ZERO, "result": result})

func _nearest_enemy(e: Dictionary, range_value: float) -> int:
	if GarrisonOperations.active(self) or entities.values().any(func(candidate):return bool(candidate.get("submarine",false))):return _nearest_enemy_reference(e,range_value)
	if not _in_step: return _nearest_enemy_reference(e, range_value)
	if Transport.is_loaded(e): return -1
	var mask: int = int(_weapon_target_masks.get(str(e.spec), -1))
	if mask < 0: mask = _target_mask_for_spec(data_for(e.spec))
	if mask == 0: return -1
	range_value = _acquisition_range(e, range_value)
	var source: Vector2 = e.pos
	var team: int = int(e.team)
	if native_kernels_enabled and _kernels != null:
		return _kernels.nearest_enemy(source, range_value, team, mask, _contact_spatial, _contact_ids, _contact_positions, _contact_teams, _contact_domains, _contact_visibility)
	var nearest: int = -1
	var distance: float = range_value * range_value
	var first: Vector2i = _combat_bucket(source - Vector2.ONE * range_value)
	var last: Vector2i = _combat_bucket(source + Vector2.ONE * range_value)
	var center: Vector2i = _combat_bucket(source)
	var rings: int = maxi(maxi(center.x - first.x, last.x - center.x), maxi(center.y - first.y, last.y - center.y))
	var winning_bucket: int = -1
	var winning_index: int = -1
	var width: int = last.x - first.x + 1
	# Visit central cells first. A bucket whose closest point is farther than
	# the current winner cannot contain a nearer target, including large ranges.
	for ring in range(rings + 1):
		for z in range(maxi(first.y, center.y - ring), mini(last.y, center.y + ring) + 1):
			for x in range(maxi(first.x, center.x - ring), mini(last.x, center.x + ring) + 1):
				if maxi(absi(x - center.x), absi(z - center.y)) != ring: continue
				var dx: float = maxf(maxf(float(x * 8) - source.x, source.x - float((x + 1) * 8)), 0.0)
				var dz: float = maxf(maxf(float(z * 8) - source.y, source.y - float((z + 1) * 8)), 0.0)
				if dx * dx + dz * dz > distance + maxf(.00001, distance * .0000003): continue
				var slots: Array = _contact_spatial.get(Vector2i(x, z), [])
				var bucket_rank: int = (z - first.y) * width + x - first.x
				for index in range(slots.size()):
					var slot: int = int(slots[index])
					if _contact_teams[slot] == team or (_contact_domains[slot] & mask) == 0 or (_contact_visibility[slot] & (1 << team)) == 0: continue
					var candidate: float = source.distance_squared_to(_contact_positions[slot])
					if candidate > distance: continue
					# Preserve the previous min-z/min-x bucket traversal and final
					# in-bucket winner for exact-distance ties despite ring ordering.
					if candidate == distance and (bucket_rank < winning_bucket or (bucket_rank == winning_bucket and index < winning_index)): continue
					distance = candidate
					nearest = int(_contact_ids[slot])
					winning_bucket = bucket_rank
					winning_index = index
	return nearest

func _target_mask_for_spec(spec: Dictionary) -> int:
	var weapon_id: String = str(spec.get("weapon", ""))
	if weapon_id.is_empty(): return 0
	var mask: int = 0
	for domain in rules.weapons.get(weapon_id, {}).get("targets", ["ground"]):
		mask |= 2 if str(domain) == "air" else (4 if str(domain) == "naval" else 1)
	for domain in rules.weapons.get(str(spec.get("secondary_weapon","")),{}).get("targets",[]):
		mask |= 2 if str(domain) == "air" else (4 if str(domain) == "naval" else 1)
	return mask

func _nearest_enemy_reference(e: Dictionary, range_value: float) -> int:
	range_value = _acquisition_range(e, range_value)
	var nearest: int = -1
	var distance: float = range_value * range_value
	var first: Vector2i = _combat_bucket(e.pos - Vector2(range_value, range_value))
	var last: Vector2i = _combat_bucket(e.pos + Vector2(range_value, range_value))
	var targets: Dictionary = _combat_spatial
	for z in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			for raw_id in targets.get(Vector2i(x, z), []):
				var id: int = int(raw_id)
				if not entities.has(id):
					continue
				var other: Dictionary = entities[id]
				if int(other.team) == int(e.team) or float(other.hp) <= 0.0 or RailNetwork.is_rail(data_for(other.spec)):
					continue
				var candidate: float = (e.pos as Vector2).distance_squared_to(other.pos)
				if candidate <= distance and _weapon_can_target(e, id):
					distance = candidate
					nearest = id
	for ruin in _nearby_ruins(e.pos,range_value):
		var id:int=RUIN_TARGET_BASE-int(ruin.id)
		var candidate:float=(e.pos as Vector2).distance_squared_to(ruin.pos)
		if candidate<=distance and GarrisonOperations.hostile(self,int(e.team),id) and position_visible_to(int(e.team),ruin.pos) and _weapon_can_target(e,id):nearest=id;distance=candidate
	return nearest

func _target_alive(target: int) -> bool:
	if target <= RUIN_TARGET_BASE:
		var ruin: Dictionary = ruin_by_target(target)
		return not ruin.is_empty() and float(ruin.hp)>0
	if target <= BRIDGE_TARGET_BASE:
		var bridge: Dictionary = _bridge_by_id(BRIDGE_TARGET_BASE - target)
		return not bridge.is_empty() and bool(bridge.alive)
	return entities.has(target) and float(entities[target].hp) > 0.0 and not Transport.is_loaded(entities[target])

func _target_position(target: int) -> Vector2:
	if target <= RUIN_TARGET_BASE: return ruin_by_target(target).get("pos",Vector2.ZERO)
	if target <= BRIDGE_TARGET_BASE:
		return _bridge_center(_bridge_by_id(BRIDGE_TARGET_BASE - target))
	if entities.has(target):
		return entities[target].pos
	return Vector2.ZERO

func _radius(e: Dictionary) -> float:
	return float(e.radius)

func _in_bounds(pos: Vector2) -> bool:
	return pos.x >= 0.0 and pos.y >= 0.0 and pos.x < float(map.size) and pos.y < float(map.size)

func _point_bounds(point: Vector2, bounds: Array) -> bool:
	return point.x >= float(bounds[0]) and point.y >= float(bounds[1]) and point.x < float(bounds[0]) + float(bounds[2]) and point.y < float(bounds[1]) + float(bounds[3])

func _circle_rect(point: Vector2, radius: float, center: Vector2, half: Vector2) -> bool:
	var closest: Vector2 = point.clamp(center - half, center + half)
	return point.distance_squared_to(closest) < radius * radius + 0.00001

func _circle_bounds(point: Vector2, radius: float, bounds: Array) -> bool:
	var half := Vector2(float(bounds[2]), float(bounds[3])) * 0.5
	return _circle_rect(point, radius, Vector2(float(bounds[0]), float(bounds[1])) + half, half)

func bridge_at(pos: Vector2) -> int:
	for bridge in bridges:
		if _point_bounds(pos, bridge.bounds):
			return int(bridge.id)
	return -1

func _bridge_by_id(id: int) -> Dictionary:
	for bridge in bridges:
		if int(bridge.id) == id:
			return bridge
	return {}

func _bridge_center(bridge: Dictionary) -> Vector2:
	if bridge.is_empty():
		return Vector2.ZERO
	var bounds: Array = bridge.bounds
	return Vector2(float(bounds[0]) + float(bounds[2]) * 0.5, float(bounds[1]) + float(bounds[3]) * 0.5)

func _land(pos: Vector2) -> bool:
	if not _in_bounds(pos):
		return false
	var terrain: int = _terrain(pos)
	if terrain == 4:
		return false
	if terrain == 1:
		var bridge: Dictionary = _bridge_by_id(bridge_at(pos))
		return not bridge.is_empty() and bool(bridge.alive)
	return true

func _segment_terrain(a: Vector2, b: Vector2) -> bool:
	var length: float = a.distance_to(b)
	var checks: int = maxi(1, ceili(length / 0.25))
	var previous: Vector2 = a
	for n in range(1, checks + 1):
		var point: Vector2 = a.lerp(b, float(n) / float(checks))
		if not _land(point):
			return false
		var level_delta: float = absf(_height(point) - _height(previous))
		if level_delta > 0.8:
			return false
		previous = point
	return true

func _prepare_native_queries() -> void:
	_native_geometry_ready = false
	if not native_kernels_enabled or not native_geometry_enabled or _kernels == null or _spec_cache.is_empty(): return
	if mines.size() > 8 and _mine_spatial_count != mines.size(): _refresh_mine_spatial()
	_kernels.configure_geometry({"map":map,"flat":_flat_safe,"flat_wide":_flat_wide_safe,"bridges":bridges,"mines":mines,"ruins":_ruin_spatial,"buildings":_building_spatial,"mine_buckets":_mine_spatial,"spatial":_spatial,"neighbors":_neighbor_cache,"specs":_spec_cache,"max_ground_radius":_max_ground_radius,"ground_motion":_ground_motion_spatial,"entities":entities})
	_native_geometry_ready = true

func _standing(pos: Vector2, radius: float, ignore: int, dynamic: bool = true) -> bool:
	if _in_step and _native_geometry_ready and native_geometry_enabled: return _kernels.standing(pos,radius,ignore,dynamic)
	if not _land(pos):
		return false
	if not _fast_flat(pos, radius):
		if not _terrain_shape_clear(pos, pos, radius): return false
		var level: float = _height(pos)
		for direction in CLEARANCE_DIRECTIONS:
			var edge: Vector2 = pos + direction * radius
			if not _land(edge) or absf(_height(edge) - level) > 0.8:
				return false
	if not _building_clear(pos, radius, ignore):
		return false
	if dynamic:
		for e in _neighbors(pos):
			if int(e.id) == ignore or float(e.hp) <= 0.0:
				continue
			var combined: float = radius + float(e.radius) + 0.02
			if (e.pos as Vector2).distance_squared_to(pos) < combined * combined:
				return false
	return true

func _building_clear(pos: Vector2, radius: float, ignore: int) -> bool:
	if _in_step and _native_geometry_ready and native_geometry_enabled: return _kernels.building_clear(pos,radius,ignore)
	for ruin in _ruin_spatial.get(_bucket(pos),[]):
		if float(ruin.hp)>0 and _circle_rect(pos,radius+.02,ruin.pos,ruin.half): return false
	for mine in _nearby_mines(pos, radius + 0.02):
		if _circle_rect(pos, radius + 0.02, mine.pos, MINE_HALF): return false
	for e in _building_spatial.get(_bucket(pos), []):
		if int(e.id) == ignore or float(e.hp) <= 0.0:
			continue
		if _query_is_infantry(ignore) and data_for(e.spec).get("role", "") == "barricade": continue
		var half: float = float(data_for(e.spec).size) * 0.5
		if _circle_rect(pos, radius + 0.02, e.pos, Vector2(half, half)):
			return false
	return true

func _near_stand(pos: Vector2, radius: float, ignore: int, maximum: float, dynamic: bool = true) -> Vector2:
	if _in_step and _native_geometry_ready and native_geometry_enabled: return _kernels.near_stand(pos,radius,ignore,maximum,dynamic)
	if _standing(pos, radius, ignore, dynamic):
		return pos
	for ring in range(1, ceili(maximum / 0.6) + 1):
		var distance: float = ring * 0.6
		for n in range(16):
			var point: Vector2 = pos + Vector2.from_angle(float(n) * TAU / 16.0) * distance
			if _standing(point, radius, ignore, dynamic):
				return point
	return Vector2.INF

func _cell_id(cell: Vector2i) -> int:
	return cell.y * int(map.size) + cell.x

func _nav_point(pos: Vector2) -> int:
	var cell: Vector2i = MapData.cell(map, pos)
	var id: int = _cell_id(cell)
	if _nav.has_point(id) and not _nav.is_point_disabled(id):
		return id
	return -1


func _nav_point_for_radius(pos: Vector2, radius: float, ignore: int) -> int:
	var cell: Vector2i = MapData.cell(map, pos)
	var answer: int = -1
	var best: float = INF
	for z in range(-2, 3):
		for x in range(-2, 3):
			var candidate: Vector2i = cell + Vector2i(x, z)
			if candidate.x < 0 or candidate.y < 0 or candidate.x >= int(map.size) or candidate.y >= int(map.size):
				continue
			for id: int in _nav_nodes_in_cell(candidate):
				if _nav.is_point_disabled(id): continue
				var point: Vector2 = _nav.get_point_position(id)
				var distance: float = pos.distance_squared_to(point)
				if distance < best and _standing(point, radius, ignore, false) and _segment_static(pos, point, radius, ignore):
					best = distance
					answer = id
	return answer

func _nav_nodes_in_cell(cell: Vector2i) -> Array[int]:
	var answer: Array[int] = []
	var id: int = _cell_id(cell)
	if _nav.has_point(id): answer.append(id)
	answer.append_array(_terrain_nav_extra_cells.get(cell, []))
	return answer

func _nav_detail_id(point: Vector2) -> int:
	var half := Vector2i(roundi(point.x * 2.0), roundi(point.y * 2.0))
	return _size * _size + half.y * (_size * 2 + 1) + half.x

func _add_nav_detail_point(point: Vector2) -> bool:
	# Keep original cell IDs. Only terrain/obstacle boundary neighborhoods gain
	# half-cell samples; open fields retain the existing one-meter graph.
	if not _in_bounds(point): return false
	if not is_equal_approx(fposmod(point.x, 1.0), 0.5) or not is_equal_approx(fposmod(point.y, 1.0), 0.5):
		var id: int = _nav_detail_id(point)
		if _nav.has_point(id) or not _terrain_clear(point, 0.2): return false
		_nav.add_point(id, point)
		_terrain_nav_ids.append(id)
		_terrain_mask_candidates.append(id)
		_terrain_nav_extra_positions[id] = point
		var cell := Vector2i(floori(point.x), floori(point.y))
		if not _terrain_nav_extra_cells.has(cell): _terrain_nav_extra_cells[cell] = []
		_terrain_nav_extra_cells[cell].append(id)
		return true
	return false

func _add_missing_terrain_detail() -> void:
	var blocked_by_radius: Dictionary={}
	for info in rules.units.values():
		if str(info.get("domain","ground"))!="ground":continue
		var radius: float=snappedf(float(info.radius),.01)
		if blocked_by_radius.has(radius):continue
		var blocked: Dictionary={}
		for id in _terrain_masks[radius]:blocked[int(id)]=true
		blocked_by_radius[radius]=blocked
	var candidates: Dictionary={}
	for id in _terrain_mask_candidates:
		var point: Vector2=_nav.get_point_position(id)
		for offset in [Vector2(.5,0),Vector2(-.5,0),Vector2(0,.5),Vector2(0,-.5),Vector2(.5,.5),Vector2(-.5,.5),Vector2(.5,-.5),Vector2(-.5,-.5)]:
			var candidate: Vector2=point+offset
			if _in_bounds(candidate):candidates[candidate]=true
	var cores: Array[Vector2]=[]
	for point: Vector2 in candidates:
		for radius: float in blocked_by_radius:
			var blocked: Dictionary=blocked_by_radius[radius]
			var regular_available:=false
			for z in range(floori(point.y-.5),ceili(point.y-.5)+1):
				for x in range(floori(point.x-.5),ceili(point.x-.5)+1):
					if x<0 or z<0 or x>=_size or z>=_size:continue
					var id: int=z*_size+x
					if _nav.has_point(id) and not blocked.has(id):regular_available=true
				if regular_available:break
			if not regular_available and _terrain_clear(point,radius):
				cores.append(point)
				break
	# Two half-step rings join the core chain back to original anchors at
	# both ends. Every point/edge is still radius-masked and collision-checked.
	for point in cores:
		for z in range(-2,3):
			for x in range(-2,3):
				if absi(x)+absi(z)<=2:_add_nav_detail_point(point+Vector2(x,z)*.5)

func _extend_detail_terrain_masks() -> void:
	for radius: float in _terrain_masks:
		var blocked: Array=_terrain_masks[radius]
		for id: int in _terrain_nav_extra_positions:
			if not _terrain_clear(_terrain_nav_extra_positions[id],radius):blocked.append(id)


func _connect_nav_detail() -> void:
	for raw_id in _terrain_nav_extra_positions:
		var id: int = int(raw_id)
		var point: Vector2 = _terrain_nav_extra_positions[id]
		for offset in [Vector2(.5, 0), Vector2(-.5, 0), Vector2(0, .5), Vector2(0, -.5)]:
			var other_point: Vector2 = point + offset
			if not _in_bounds(other_point): continue
			var other_id: int = _cell_id(Vector2i(floori(other_point.x), floori(other_point.y))) if is_equal_approx(fposmod(other_point.x, 1.0), .5) and is_equal_approx(fposmod(other_point.y, 1.0), .5) else _nav_detail_id(other_point)
			if not _nav.has_point(other_id) or _nav.are_points_connected(id, other_id): continue
			var legal := true
			var previous: Vector2 = point
			for sample in range(1, 5):
				var current: Vector2 = point.lerp(other_point, float(sample) / 4.0)
				if not _terrain_clear(current, .2) or absf(_height(current) - _height(previous)) > .8:
					legal = false
					break
				previous = current
			if legal:
				_nav.connect_points(id, other_id)
				_terrain_nav_edges.append(id)
				_terrain_nav_edges.append(other_id)

func _add_nav_obstacle_detail(rect: Rect2) -> bool:
	if _nav_detail_rectangles.has(rect): return false
	_nav_detail_rectangles[rect] = true
	var bounds := rect.grow(1.5)
	var added := false
	for z in range(maxi(1, ceili(bounds.position.y * 2.0)), mini(_size * 2, floori(bounds.end.y * 2.0)) + 1):
		for x in range(maxi(1, ceili(bounds.position.x * 2.0)), mini(_size * 2, floori(bounds.end.x * 2.0)) + 1):
			var point := Vector2(x, z) * .5
			if rect.has_point(point): continue
			added = _add_nav_detail_point(point) or added
	return added

func _navigation_hard_rectangles() -> Array[Rect2]:
	var answer: Array[Rect2] = []
	for mine in mines: answer.append(Rect2(mine.pos - MINE_HALF, MINE_HALF * 2.0))
	for building in _building_entities:
		if float(building.hp) <= 0.0 or data_for(building.spec).get("role", "") in ["barricade", "rail", "rail_junction"]: continue
		var half := Vector2.ONE * float(data_for(building.spec).size) * .5
		answer.append(Rect2(building.pos - half, half * 2.0))
	return answer




func _segment_static(start: Vector2, end: Vector2, radius: float, ignore: int) -> bool:
	if _in_step and _native_geometry_ready and native_geometry_enabled: return _kernels.segment_static(start,end,radius,ignore)
	var started: int=Time.get_ticks_usec() if geometry_profiling_enabled and _in_step else 0
	var answer: bool=_segment_obstacles_clear(start,end,radius,ignore) and _segment_static_sampled(start,end,radius,ignore)
	if geometry_profiling_enabled and _in_step:
		_geometry_queries+=1
		_geometry_us+=Time.get_ticks_usec()-started
	return answer

func _segment_bucket_keys(start: Vector2, finish: Vector2, padding: float) -> Dictionary:
	# Existing ruin/mine buckets contain 2m padding; building buckets contain
	# 1.1m. Samples <=1m apart cover the swept circle using that padding.
	var keys: Dictionary={}
	var checks: int=maxi(1,ceili(start.distance_to(finish)))
	for n in range(checks+1):
		var point: Vector2=start.lerp(finish,float(n)/float(checks))
		var first: Vector2i=_bucket(point-Vector2.ONE*padding)
		var last: Vector2i=_bucket(point+Vector2.ONE*padding)
		for z in range(first.y,last.y+1):
			for x in range(first.x,last.x+1):keys[Vector2i(x,z)]=true
	return keys

func _segment_obstacles_clear(start: Vector2, finish: Vector2, radius: float, ignore: int) -> bool:
	var clearance: float=radius+.02
	var reach: float=sqrt(clearance*clearance+.00001)+.5
	var keys: Dictionary=_segment_bucket_keys(start,finish,maxf(0.0,reach-2.0))
	var checked: Dictionary={}
	for key: Vector2i in keys:
		for ruin in _ruin_spatial.get(key,[]):
			if checked.has(int(ruin.id)):continue
			checked[int(ruin.id)]=true
			if float(ruin.hp)<=0:continue
			if geometry_profiling_enabled and _in_step:_geometry_rectangles+=1
			if _swept_circle_rect(start,finish,clearance,Rect2(ruin.pos-ruin.half,ruin.half*2.0)):return false
	checked.clear()
	if mines.size()>8 and _mine_spatial_count!=mines.size():_refresh_mine_spatial()
	for key: Vector2i in keys:
		for mine in (mines if mines.size()<=8 else _mine_spatial.get(key,[])):
			if checked.has(mine.pos):continue
			checked[mine.pos]=true
			if geometry_profiling_enabled and _in_step:_geometry_rectangles+=1
			if _swept_circle_rect(start,finish,clearance,Rect2(mine.pos-MINE_HALF,MINE_HALF*2.0)):return false
	checked.clear()
	for key: Vector2i in _segment_bucket_keys(start,finish,maxf(0.0,reach-1.1)):
		for e in _building_spatial.get(key,[]):
			if checked.has(int(e.id)):continue
			checked[int(e.id)]=true
			if int(e.id)==ignore or float(e.hp)<=0:continue
			var info: Dictionary=data_for(e.spec)
			if _query_is_infantry(ignore) and info.get("role","")=="barricade":continue
			var half: Vector2=Vector2.ONE*float(info.size)*.5
			if geometry_profiling_enabled and _in_step:_geometry_rectangles+=1
			if _swept_circle_rect(start,finish,clearance,Rect2(e.pos-half,half*2.0)):return false
	return true

func _segment_static_sampled(start: Vector2, end: Vector2, radius: float, ignore: int) -> bool:
	var checks: int = maxi(1, ceili(start.distance_to(end) / 0.4))
	# Keep every original footprint/building sample. If every sampled cell and
	# its eight neighbors are flat land, intervening terrain samples are redundant:
	# adjacent samples are <=0.4 apart and their three-cell neighborhoods overlap.
	if _fast_flat(start, radius):
		var flat: bool = true
		for n in range(1, checks + 1):
			var point: Vector2 = start.lerp(end, float(n) / float(checks))
			if not _fast_flat(point, radius):
				flat = false
				break
			if not _building_clear(point, radius, ignore):
				return false
		if flat:
			return true
	if not _terrain_shape_clear(start, end, radius) or not _segment_terrain(start, end):
		return false
	for n in range(1, checks + 1):
		if not _standing(start.lerp(end, float(n) / float(checks)), radius, ignore, false):
			return false
	return true

func _terrain_shape_clear(start: Vector2, finish: Vector2, radius: float, original_terrain: bool = false) -> bool:
	# The worker uses continuous water rectangles and cliff boundary lines.
	# Match that exact footprint here; eight circumference samples alone can
	# accept a corner overlap and strand a unit at an impossible path origin.
	var low: Vector2 = start.min(finish) - Vector2.ONE * radius
	var high: Vector2 = start.max(finish) + Vector2.ONE * radius
	if low.x < 0 or low.y < 0 or high.x >= _size or high.y >= _size: return false
	for bucket: Vector2i in _segment_bucket_keys(start, finish, radius):
		for z in range(maxi(0, bucket.y * 2), mini(_size, bucket.y * 2 + 2)):
			for x in range(maxi(0, bucket.x * 2), mini(_size, bucket.x * 2 + 2)):
				var pos := Vector2(x + .5, z + .5)
				if not (_original_land(pos) if original_terrain else _land(pos)):
					if _swept_circle_rect(start, finish, radius, Rect2(Vector2(x, z), Vector2.ONE)): return false
					continue
				if x > 0 and (_original_land(pos - Vector2.RIGHT) if original_terrain else _land(pos - Vector2.RIGHT)) and absf(float(map.heights[z][x]) - float(map.heights[z][x - 1])) > .8:
					if _swept_circle_rect(start, finish, radius, Rect2(Vector2(x, z), Vector2(0, 1))): return false
				if z > 0 and (_original_land(pos - Vector2.DOWN) if original_terrain else _land(pos - Vector2.DOWN)) and absf(float(map.heights[z][x]) - float(map.heights[z - 1][x])) > .8:
					if _swept_circle_rect(start, finish, radius, Rect2(Vector2(x, z), Vector2(1, 0))): return false
	return true

func _prepare_terrain_cache(progress: Callable = Callable()) -> void:
	_invalidate_static_geometry()
	_size = int(map.size)
	if native_kernels_enabled and _kernels != null:
		_flat_safe=_kernels.build_flat_terrain_mask(map)
		_prepare_wide_flat_cache()
		return
	_flat_safe.resize(_size * _size)
	_flat_safe.fill(0)
	for z in range(1, _size - 1):
		for x in range(1, _size - 1):
			var level: float = float(map.heights[z][x])
			var good: bool = true
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					if int(map.terrain[z+dz][x+dx]) not in [0, 3] or absf(float(map.heights[z+dz][x+dx])-level) > 0.01:
						good = false
						break
				if not good:
					break
			if good:
				_flat_safe[z * _size + x] = 1
		if progress.is_valid() and z % 32 == 0:
			await progress.call(0.32 + 0.1 * float(z) / float(_size), "整理地形与资源")
	_prepare_wide_flat_cache()

func _prepare_wide_flat_cache() -> void:
	if native_kernels_enabled and _kernels != null and _kernels.has_method("build_wide_flat_terrain_mask"):
		_flat_wide_safe = _kernels.build_wide_flat_terrain_mask(_flat_safe, _size)
		return
	_flat_wide_safe.resize(_size * _size)
	_flat_wide_safe.fill(0)
	for z in range(2, _size - 2):
		for x in range(2, _size - 2):
			var safe: bool = true
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					if _flat_safe[(z + dz) * _size + x + dx] == 0: safe = false; break
				if not safe: break
			if safe: _flat_wide_safe[z * _size + x] = 1

func _fast_flat(pos: Vector2, radius: float) -> bool:
	if radius > 1.99 or not _in_bounds(pos):
		return false
	var index: int = floori(pos.y) * _size + floori(pos.x)
	if radius <= .99: return index < _flat_safe.size() and _flat_safe[index] == 1
	return index < _flat_wide_safe.size() and _flat_wide_safe[index] == 1

func _terrain(pos: Vector2) -> int:
	return int(map.terrain[clampi(floori(pos.y), 0, _size - 1)][clampi(floori(pos.x), 0, _size - 1)])

func _height(pos: Vector2) -> float:
	var x: int = clampi(floori(pos.x), 0, _size - 1)
	var z: int = clampi(floori(pos.y), 0, _size - 1)
	var level: float = float(map.heights[z][x])
	if int(map.terrain[z][x]) == 2:
		var fraction: float = pos.y - (z + 0.5)
		var next_z: int = z + (1 if fraction >= 0.0 else -1)
		if next_z >= 0 and next_z < _size:
			var next_level: float = float(map.heights[next_z][x])
			if absf(next_level - level) <= 0.75:
				return lerpf(level, next_level, absf(fraction))
	return level

func _refresh_building_spatial() -> void:
	_rail_network.rebuild(self)
	_invalidate_static_geometry()
	_invalidate_base_cache()
	_building_spatial.clear()
	for e in _building_entities:
		if RailNetwork.is_rail(data_for(e.spec)): continue
		var half: float = float(data_for(e.spec).size) * 0.5 + 1.1
		var first: Vector2i = _bucket(e.pos - Vector2(half, half))
		var last: Vector2i = _bucket(e.pos + Vector2(half, half))
		for z in range(first.y, last.y + 1):
			for x in range(first.x, last.x + 1):
				var key := Vector2i(x, z)
				if not _building_spatial.has(key):
					_building_spatial[key] = []
				_building_spatial[key].append(e)

func _original_land(pos: Vector2) -> bool:
	if not _in_bounds(pos):
		return false
	var terrain: int = _terrain(pos)
	return terrain != 4 and (terrain != 1 or bridge_at(pos) >= 0)

func _terrain_clear(pos: Vector2, radius: float) -> bool:
	if _fast_flat(pos, radius):
		return true
	if not _terrain_shape_clear(pos, pos, radius, true): return false
	if not _original_land(pos):
		return false
	for direction in CLEARANCE_DIRECTIONS:
		var edge: Vector2 = pos + direction * radius
		if not _original_land(edge) or absf(_height(edge) - _height(pos)) > 0.8:
			return false
	return true

func _rebuild_nav(progress: Callable = Callable()) -> void:
	_refresh_mine_spatial()
	if _in_step and _nav_initialized and not synchronous_path_tests:
		_publish_path_geometry()
		for e in entities.values():
			if e.kind=="unit" and not _is_air(e) and not _is_naval(e) and (_nav_regions.is_empty() or _path_crosses_changed_region(e)):
				e.path.clear();e.path_goal=Vector2.INF
				e.path_wait=float(int(e.id)%11)*.025
		_native_masks_dirty=true
		_nav_regions.clear();_nav_dirty=false
		return
	var initial: bool=not _nav_initialized
	_wide_masks.clear()
	if not _nav_initialized:
		_nav.clear()
		_terrain_nav_ids = PackedInt64Array()
		_terrain_nav_edges = PackedInt64Array()
		_terrain_mask_candidates.clear()
		_terrain_nav_extra_positions.clear()
		_terrain_nav_extra_cells.clear()
		_nav_detail_rectangles.clear()
		_terrain_masks.clear()
		_nav_disabled.clear()
		var size: int = int(map.size)
		_nav.reserve_space(size * size)
		for z in range(size):
			for x in range(size):
				var point := Vector2(x + 0.5, z + 0.5)
				if _terrain_clear(point, 0.2):
					var id: int = _cell_id(Vector2i(x, z))
					_nav.add_point(id, point)
					_terrain_nav_ids.append(id)
					if _flat_safe[z * _size + x] == 0: _terrain_mask_candidates.append(id)
			if progress.is_valid() and (z + 1) % 32 == 0:
				await progress.call(0.52 + 0.17 * float(z + 1) / float(size), "建立导航网格")
		for z in range(size):
			for x in range(size):
				var cell := Vector2i(x, z)
				var id: int = _cell_id(cell)
				if not _nav.has_point(id):
					continue
				# Match the background graph. Dynamic trees/buildings may disable
				# the corner node after setup, so diagonal edges can cut its footprint.
				# Open-space diagonals are recovered by the checked path smoother.
				for direction in NAV_EDGE_DIRECTIONS:
					var next: Vector2i = cell + direction
					if next.x < 0 or next.y < 0 or next.x >= size or next.y >= size:
						continue
					var next_id: int = _cell_id(next)
					if not _nav.has_point(next_id):
						continue
					var a: Vector2 = _nav.get_point_position(id)
					var b: Vector2 = _nav.get_point_position(next_id)
					if _fast_flat(a, .2) and _fast_flat(b, .2):
						_nav.connect_points(id, next_id)
						_terrain_nav_edges.append(id)
						_terrain_nav_edges.append(next_id)
						continue
					var legal: bool = true
					var previous: Vector2 = a
					for n in range(1, 7):
						var point: Vector2 = a.lerp(b, float(n) / 6.0)
						if not _original_land(point) or absf(_height(point) - _height(previous)) > 0.8:
							legal = false
							break
						previous = point
					if legal:
						_nav.connect_points(id, next_id)
						_terrain_nav_edges.append(id)
						_terrain_nav_edges.append(next_id)
			if progress.is_valid() and (z + 1) % 32 == 0:
				await progress.call(0.69 + 0.17 * float(z + 1) / float(size), "连接导航路径")
		# A two-meter corridor is physically legal for a radius-.75 tank, but
		# both ordinary centers sit only .5m from its edge. Sample the center
		# locally without changing the collision radius or densifying flat fields.
		# First cache the unchanged regular-grid masks. A terrain detail core
		# must be legal for a real ground unit radius while *all* nearest
		# regular centers are blocked for that radius. Ordinary open shores
		# already have regular routes and need no extra graph strip.
		_warm_terrain_masks()
		_add_missing_terrain_detail()
		for rect in _navigation_hard_rectangles(): _add_nav_obstacle_detail(rect)
		_connect_nav_detail()
		_extend_detail_terrain_masks()
		_nav_initialized = true
		if progress.is_valid(): await progress.call(0.88, "准备导航通行数据")
		_warm_terrain_masks()
	elif synchronous_path_tests:
		var added_detail := false
		for rect in _navigation_hard_rectangles(): added_detail = _add_nav_obstacle_detail(rect) or added_detail
		if added_detail:
			_connect_nav_detail()
			_terrain_masks.clear()
			_warm_terrain_masks()
	if progress.is_valid(): await progress.call(0.92, "准备动态导航")
	for id in _nav_disabled:
		_nav.set_point_disabled(id, false)
	_nav_disabled = _dynamic_nav_blocks(0.35, false)
	for id in _nav_disabled:
		_nav.set_point_disabled(id, true)
	_nav_dirty = false
	for e in entities.values():
		if e.kind != "unit" or e.path.is_empty():
			continue
		if _path_crosses_changed_region(e):
			e.path.clear()
			e.path_goal = Vector2.INF
			e.path_wait = 0.0
	_nav_regions.clear()

	_native_masks_dirty=false
	_publish_path_geometry()
	if initial and not synchronous_path_tests:_start_path_worker()

func _mark_nav_region(region: Rect2) -> void:
	_invalidate_static_geometry()
	_nav_regions.append(region)
	_nav_dirty = true

func _path_crosses_changed_region(e: Dictionary) -> bool:
	for region in _nav_regions:
		var clearance: Rect2 = region.grow(_radius(e) + 0.02)
		var position: Vector2 = e.pos
		for raw_point in e.path:
			var point: Vector2 = raw_point
			if _segment_crosses_rect(position, point, clearance):
				return true
			position = point
	return false

func _segment_crosses_rect(start: Vector2, end: Vector2, rectangle: Rect2) -> bool:
	var direction: Vector2 = end - start
	var first: float = 0.0
	var last: float = 1.0
	for axis in range(2):
		var low: float = rectangle.position[axis]
		var high: float = rectangle.end[axis]
		if absf(direction[axis]) < 0.000001:
			if start[axis] < low or start[axis] > high:
				return false
		else:
			var a: float = (low - start[axis]) / direction[axis]
			var b: float = (high - start[axis]) / direction[axis]
			first = maxf(first, minf(a, b))
			last = minf(last, maxf(a, b))
			if first > last:
				return false
	return true

func _warm_terrain_masks() -> void:
	var radii: Dictionary = {}
	for info in rules.units.values():
		# Every configured ground radius needs a worker terrain mask. Ships use
		# their separate water navigator; prewarming those masks is redundant.
		if str(info.get("domain", "ground")) != "ground":
			continue
		radii[snappedf(float(info.radius), 0.01)] = float(info.radius)
	for key in radii:
		_cache_terrain_mask(float(key), float(radii[key]))

func _cache_terrain_mask(key: float, radius: float) -> void:
	if _terrain_masks.has(key):
		return
	var terrain_blocked: Array[int] = []
	# Flat neighborhoods already prove clearance for every configured radius.
	# Only boundaries/ramps/shorelines can differ between these terrain masks.
	var candidates: Variant = _terrain_mask_candidates if radius <= .99 else _terrain_nav_ids
	for id in candidates:
		if not _terrain_clear(_nav.get_point_position(id), radius):
			terrain_blocked.append(int(id))
	_terrain_masks[key] = terrain_blocked

func _defer_planning(id: int) -> void:
	if not _in_step or not entities.has(id) or _planning_deferred_ids.has(id):
		return
	_planning_deferred_ids[id] = true
	var e: Dictionary = entities[id]
	e.planning_wait = float(e.get("planning_wait", 0.0)) + _step_delta
	_planning_max_wait = maxf(_planning_max_wait, float(e.planning_wait))

func _claim_path_plan(id: int) -> bool:
	if entities.has(id):
		_planning_requested_ids[id] = true
	# Equal-priority callers preserve FIFO; selected/recent player commands
	# claim a slot before background/AI work without changing search budgets.
	if _path_plans_remaining <= 0 or (not _planning_queue.is_empty() and _planning_queue[_navigation_queue_index()] != id):
		if entities.has(id) and not _planning_queue.has(id):
			_planning_queue.append(id)
		_defer_planning(id)
		return false
	if not _planning_queue.is_empty():
		_planning_queue.remove_at(_planning_queue.find(id))
	_path_plans_remaining -= 1
	if entities.has(id):
		entities[id].planning_wait = 0.0
		_planning_deferred_ids.erase(id)
	return true

func _prune_planning_queue() -> void:
	for id in _navigation_command_until.keys():
		if not entities.has(id) or time>=float(_navigation_command_until[id]):_navigation_command_until.erase(id)
	for id in _path_requests.keys():
		if not entities.has(id) or not _planning_requested_ids.has(id):_path_requests.erase(id)
	# A stopped, dead, already-arrived or newly engaged unit must not hold the queue.
	for index in range(_planning_queue.size() - 1, -1, -1):
		var id: int = _planning_queue[index]
		if not entities.has(id) or not _planning_requested_ids.has(id):
			_planning_queue.remove_at(index)

func _dynamic_nav_blocks(radius: float, vehicle: bool = true) -> Array[int]:
	var blocked: Dictionary = {}
	for mine in mines:
		var reach: Vector2 = MINE_HALF + Vector2.ONE * (radius + 0.02)
		for z in range(maxi(0, floori(mine.pos.y - reach.y)), mini(_size, ceili(mine.pos.y + reach.y))):
			for x in range(maxi(0, floori(mine.pos.x - reach.x)), mini(_size, ceili(mine.pos.x + reach.x))):
				for id in _nav_nodes_in_cell(Vector2i(x, z)):
					if _circle_rect(_nav.get_point_position(id), radius + 0.02, mine.pos, MINE_HALF): blocked[id] = true
	for ruin in ruins:
		if float(ruin.hp)<=0:continue
		var half: Vector2 = ruin.half + Vector2.ONE*radius
		for z in range(maxi(0,floori(ruin.pos.y-half.y)),mini(int(map.size),ceili(ruin.pos.y+half.y))):
			for x in range(maxi(0,floori(ruin.pos.x-half.x)),mini(int(map.size),ceili(ruin.pos.x+half.x))):
				for id in _nav_nodes_in_cell(Vector2i(x,z)):
					if _circle_rect(_nav.get_point_position(id),radius+.02,ruin.pos,ruin.half):blocked[id]=true
	for e in _building_entities:
		if RailNetwork.is_rail(data_for(e.spec)): continue
		if not vehicle and data_for(e.spec).get("role", "") == "barricade": continue
		var half: float = float(data_for(e.spec).size) * 0.5
		for z in range(maxi(0, floori(e.pos.y - half - radius)), mini(int(map.size), ceili(e.pos.y + half + radius))):
			for x in range(maxi(0, floori(e.pos.x - half - radius)), mini(int(map.size), ceili(e.pos.x + half + radius))):
				for id in _nav_nodes_in_cell(Vector2i(x, z)):
					if _circle_rect(_nav.get_point_position(id), radius + 0.02, e.pos, Vector2(half, half)):
						blocked[id] = true
	for bridge in bridges:
		if bool(bridge.alive):
			continue
		var bounds: Array = bridge.bounds
		for z in range(maxi(0, floori(float(bounds[1]) - radius)), mini(int(map.size), ceili(float(bounds[1]) + float(bounds[3]) + radius))):
			for x in range(maxi(0, floori(float(bounds[0]) - radius)), mini(int(map.size), ceili(float(bounds[0]) + float(bounds[2]) + radius))):
				for id in _nav_nodes_in_cell(Vector2i(x, z)):
					if _circle_bounds(_nav.get_point_position(id), radius, bounds):
						blocked[id] = true
	var answer: Array[int] = []
	for id in blocked:
		answer.append(int(id))
	return answer

func _path_between(start: Vector2, goal: Vector2, radius: float, ignore: int) -> Array:
	_plan_was_deferred = false
	if entities.has(ignore) and RailNetwork.rail_only(data_for(entities[ignore].spec)):
		return _rail_network.traversable_path(self, entities[ignore], start, goal)
	if _in_step and not synchronous_path_tests:return _background_path(start,goal,radius,ignore)
	if _native_masks_dirty:
		for id in _nav_disabled:_nav.set_point_disabled(id,false)
		_nav_disabled=_dynamic_nav_blocks(.35, false)
		for id in _nav_disabled:_nav.set_point_disabled(id,true)
		_wide_masks.clear();_native_masks_dirty=false
	if _in_step and not _claim_path_plan(ignore):
		_plan_was_deferred = true
		return []
	# Clear routes use their exact endpoints, independent of navigation cells.
	if _standing(start, radius, ignore, false) and _segment_static(start, goal, radius, ignore):
		return [goal]
	var start_id: int = _nav_point_for_radius(start, radius, ignore)
	var goal_id: int = _nav_point_for_radius(goal, radius, ignore)
	if start_id < 0 or goal_id < 0:
		return []
	var packed: PackedVector2Array = _nav.get_point_path(start_id, goal_id)
	if packed.is_empty():
		return []
	var answer: Array = []
	for index in range(packed.size()):
		var point: Vector2 = packed[index]
		if not _standing(point, radius, ignore, false):
			# Narrow passages need a vehicle-safe graph rather than cutting corners.
			return _wide_path(start_id, goal_id, radius, ignore, goal, start)
		answer.append(point)
	packed = _validated_graph_path(start_id, goal_id, radius, ignore, packed)
	if packed.is_empty(): return []
	answer.assign(packed)
	if answer.is_empty() or (answer.back() as Vector2).distance_to(goal) > 0.05:
		answer.append(goal)
	return _smooth_path(start, answer, radius, ignore)

func _wide_path(start_id: int, goal_id: int, radius: float, ignore: int, goal: Vector2, start: Vector2) -> Array:
	var terrain_key: float = snappedf(radius, 0.01)
	var vehicle: bool = not _query_is_infantry(ignore)
	var key := Vector2(terrain_key,1 if vehicle else 0)
	if not _wide_masks.has(key):
		_cache_terrain_mask(terrain_key, radius)
		var blocked: Array = _terrain_masks[terrain_key].duplicate()
		blocked.append_array(_dynamic_nav_blocks(radius,vehicle))
		_wide_masks[key] = blocked
	var disabled: Array = _wide_masks[key]
	for id in disabled:
		if int(id) != start_id:
			_nav.set_point_disabled(int(id), true)
	var packed: PackedVector2Array = _nav.get_point_path(start_id, goal_id)
	packed = _validated_graph_path(start_id, goal_id, radius, ignore, packed)
	for id in disabled:
		_nav.set_point_disabled(id, false)
	for id in _nav_disabled:
		_nav.set_point_disabled(id, true)
	var answer: Array = []
	for index in range(packed.size()):
		answer.append(packed[index])
	if not packed.is_empty():
		answer.append(goal)
	return _smooth_path(start, answer, radius, ignore)

func _validated_graph_path(start_id: int, goal_id: int, radius: float, ignore: int, packed: PackedVector2Array) -> PackedVector2Array:
	# A thin obstacle can block an edge while both node centers remain legal.
	# Remove such edges for this search and find the available detour.
	var rejected: Array[Vector2i] = []
	while not packed.is_empty():
		var changed: bool = false
		for index in range(1, packed.size()):
			if _segment_static(packed[index-1], packed[index], radius, ignore): continue
			var a: int = _graph_point_id(packed[index-1])
			var b: int = _graph_point_id(packed[index])
			_nav.disconnect_points(a, b)
			rejected.append(Vector2i(a, b))
			changed = true
		if not changed: break
		packed = _nav.get_point_path(start_id, goal_id)
	for edge in rejected: _nav.connect_points(edge.x, edge.y)
	return packed

func _graph_point_id(point: Vector2) -> int:
	if is_equal_approx(fposmod(point.x, 1.0), .5) and is_equal_approx(fposmod(point.y, 1.0), .5):
		return _cell_id(Vector2i(floori(point.x), floori(point.y)))
	return _nav_detail_id(point)

func _smooth_path(start: Vector2, points: Array, radius: float, ignore: int) -> Array:
	var answer: Array = []
	var position: Vector2 = start
	var index: int = 0
	while index < points.size():
		var chosen: int = -1
		for candidate in range(points.size() - 1, index - 1, -1):
			if _segment_static(position, points[candidate], radius, ignore):
				chosen = candidate
				break
		if chosen < 0: return []
		var point: Vector2 = points[chosen]
		if position != point:
			answer.append(point)
		position = point
		index = chosen + 1
	return answer


func _move_order(e: Dictionary, command: Dictionary, delta: float) -> bool:
	return _fly_to(e,command.pos,delta) if _is_air(e) else _move_to(e,command.pos,delta)

func _move_to(e: Dictionary, goal: Vector2, delta: float) -> bool:
	if _is_naval(e): return NavalOperations.move_to(self, e, goal, delta)
	if _is_air(e): return _fly_to(e, goal, delta)
	delta *= float(e.get("rescue_speed_scale", 1.0))
	var rail_move: Dictionary = _rail_network.movement(self, e, goal, delta)
	if bool(rail_move.handled): return bool(rail_move.arrived)
	if _in_step and _native_geometry_ready and native_movement_enabled and not _rail_network.usable(self, e, e.pos):
		return _kernels.move_ground(self, e, goal, delta)
	return _move_ground_reference(e, goal, delta)

func _move_pending_path(e: Dictionary, goal: Vector2, delta: float) -> bool:
	if not responsive_navigation_enabled or synchronous_path_tests:
		e.state = "waiting"
		return false
	return ResponsiveNavigation.advance(self, e, goal, delta)

func _move_ground_reference(e: Dictionary, goal: Vector2, delta: float) -> bool:
	var radius: float = _radius(e)
	if time<float(e.get("movement_retry_at",0)):
		e.state="waiting";return false
	# A new building can invalidate a previously legal formation destination.
	# Recover a legal nearby endpoint instead of retrying the blocked point forever.
	if not _goal_standing(e, goal, radius):
		var replacement: Vector2 = _near_stand(goal,radius,int(e.id),4.0,false)
		if replacement.is_finite():
			if not e.commands.is_empty() and (e.commands[0].pos as Vector2).is_equal_approx(goal):e.commands[0].pos=replacement
			goal=replacement
		else:
			e.movement_retry_at=time+1.0
			e.state="waiting"
			return false
	if e.pos.distance_to(goal) <= maxf(0.25, radius * 0.4):
		e.state = "idle"
		e.stuck = 0.0
		return true
	if _nav_dirty:
		e.state = "waiting"
		return false
	if (e.path_goal as Vector2).distance_to(goal) > 1.0 or e.path.is_empty():
		if float(e.path_wait) > 0.0:
			e.state = "waiting"
			return false
		var planned: Array = _path_between(e.pos, goal, radius, int(e.id))
		if _plan_was_deferred:
			return _move_pending_path(e, goal, delta)
		e.path = planned
		e.path_goal = goal
		e.path_wait = 2.0+float(int(e.id)%7)*.07
		if e.path.is_empty():
			e.state = "unreachable"
			if not bool(e.get("unreachable_notice", false)):
				e.unreachable_notice = true
				if int(e.team) == 0:
					_notice("暂时没有可用路线，单位稍后重试")
			return false
		e.unreachable_notice = false
	while e.path.size()>1:
		var first: Vector2=e.path[0]
		var following: Vector2=e.path[1]
		var passed: bool=(e.pos-first).dot(following-first)>0 and Geometry2D.get_closest_point_to_segment(e.pos,first,following).distance_to(e.pos)<radius+.45
		if (e.pos.distance_to(first)<maxf(.45,radius) or passed) and _segment_static(e.pos,following,radius,int(e.id)):
			e.path.pop_front()
		else:break
	while not e.path.is_empty() and e.pos.distance_to(e.path[0]) < 0.2:
		# At a tree or shoreline corner, being near the turn is not enough:
		# dropping it can aim the unit diagonally through the blocked footprint.
		if e.path.size() > 1 and not _segment_static(e.pos, e.path[1], radius, int(e.id)): break
		e.path.pop_front()
	if e.path.is_empty():
		return e.pos.distance_to(goal) < 0.4
	if not e.has("progress_anchor"): e.progress_anchor = e.pos
	var anchor: Vector2 = e.progress_anchor
	e.progress_clock = float(e.get("progress_clock", 0.0)) + delta
	if e.progress_clock > 2.5:
		e.progress_clock = 0.0
		e.progress_anchor = e.pos
		if anchor.distance_to(e.pos) < .65:
			e.path.clear()
			e.path_wait = 0.0
			e.stuck = maxf(float(e.stuck), 2.5)
			return false
	var waypoint: Vector2 = e.path[0]
	var direction: Vector2 = (waypoint - e.pos).normalized()
	var stride: float = minf(float(data_for(e.spec).speed) * delta, e.pos.distance_to(waypoint))
	if _query_is_infantry(int(e.id)):
		for building in _building_spatial.get(_bucket(e.pos), []):
			if data_for(building.spec).get("role", "") == "barricade" and _circle_rect(e.pos, radius, building.pos, Vector2(.5, .5)):
				stride *= .35
				break
	var original: Vector2 = e.pos
	var next: Vector2 = original + direction * stride
	var can_move: bool = _movement_clear(e, original, next, true)
	if can_move:
		# A former detour must not override a route that is now clear forever.
		e.avoid_until = 0.0
		if not (e.get("yield_goal",Vector2.INF) as Vector2).is_finite(): e.reversing = false
	elif time < float(e.get("avoid_until",0)):
		var candidate: Vector2=original+(e.avoid_dir as Vector2)*stride
		if _movement_clear(e,original,candidate):
			next=candidate
			can_move=true
	if not can_move:
		var candidate: Vector2 = _movement_detour(e, original, direction, stride)
		if candidate.is_finite():
			next = candidate
			can_move = true
	if can_move:
		var wanted: float = rad_to_deg((next - original).angle())
		# Vehicles may reverse out of a jam without a blocked 180-degree turn.
		if _is_ground_vehicle(e) and bool(e.get("reversing",false)) and ((e.get("yield_goal",Vector2.INF) as Vector2).is_finite() or time<float(e.get("avoid_until",0))):
			wanted=wrapf(wanted+180,-180,180)
		_turn(e, wanted, delta)
		var tolerance: float = 10.0 if _is_ground_vehicle(e) else 25.0
		if absf(wrapf(wanted - float(e.alpha), -180.0, 180.0)) > tolerance:
			# Align vehicles in place so a clear arbitrary-angle route stays straight.
			if _is_ground_vehicle(e):
				e.state = "waiting"
				return false
			var forward: Vector2=Vector2.from_angle(deg_to_rad(float(e.alpha)))
			if bool(e.get("reversing",false)) and ((e.get("yield_goal",Vector2.INF) as Vector2).is_finite() or time<float(e.get("avoid_until",0))):forward=-forward
			var turning_step: Vector2=original+forward*stride*.55
			if forward.dot((next-original).normalized())>.15 and _movement_clear(e,original,turning_step) and _turning_connector_clear(e,turning_step,waypoint):
				next=turning_step
			else:
				e.state="waiting"
				e.stuck=float(e.stuck)+delta
				if time<float(e.get("avoid_until",0)):e.avoid_until=time+.55
				return false
	if can_move:
		_settle_crushing(e, next)
		e.pos = next
		_spatial_move(e, original, next)
		e.motion = original.distance_to(next)
		e.state = "move"
		e.stuck = 0.0
	else:
		e.state = "waiting"
		e.stuck = float(e.stuck) + .2
		e.movement_retry_at=time+.18+float(int(e.id)%5)*.015
		if float(e.stuck) > 2.0 and float(e.path_wait) <= 0.0:
			e.path.clear()
			e.path_wait = 1.0
	return false

func _turning_connector_clear(e: Dictionary, candidate: Vector2, waypoint: Vector2) -> bool:
	# Turning arcs must leave the remaining static route usable. If the
	# bounded probe cannot run, rotate in place and continue on a later tick.
	var started:=Time.get_ticks_usec()
	if not _claim_yield_probe(started):
		_local_nav_us+=Time.get_ticks_usec()-started
		return false
	var clear: bool=_future_segment_static(candidate,waypoint,_radius(e),int(e.id),started)
	_local_nav_us+=Time.get_ticks_usec()-started
	return clear

func _future_segment_static(start: Vector2, finish: Vector2, radius: float, ignore: int, _started: int) -> bool:
	return _segment_static(start,finish,radius,ignore)

func _swept_circle_rect(start: Vector2, finish: Vector2, radius: float, rectangle: Rect2) -> bool:
	# Continuous distance to the real rectangle, including its rounded
	# clearance corners; a .4-sampled tangent can miss a brief intersection.
	var padded_radius: float=sqrt(radius*radius+.00001)
	var low: Vector2=start.min(finish)-Vector2.ONE*padded_radius
	var high: Vector2=start.max(finish)+Vector2.ONE*padded_radius
	if high.x<rectangle.position.x or high.y<rectangle.position.y or low.x>rectangle.end.x or low.y>rectangle.end.y:return false
	if _segment_crosses_rect(start,finish,rectangle):return true
	var half: Vector2=rectangle.size*.5
	var center: Vector2=rectangle.position+half
	if _circle_rect(start,radius,center,half) or _circle_rect(finish,radius,center,half):return true
	for corner in [rectangle.position,rectangle.end,Vector2(rectangle.position.x,rectangle.end.y),Vector2(rectangle.end.x,rectangle.position.y)]:
		var closest: Vector2=Geometry2D.get_closest_point_to_segment(corner,start,finish)
		if (corner as Vector2).distance_squared_to(closest)<radius*radius+.00001:return true
	return false

func _movement_detour(e: Dictionary, original: Vector2, direction: Vector2, stride: float) -> Vector2:
	var radius: float = _radius(e)
	var answer: Vector2 = Vector2.INF
	# Keep the same side preference until a way around the obstruction opens.
	var avoid_start:int=Time.get_ticks_usec()
	var preferred: float = 1.0 # Keep right in both directions through shared lanes.
	for angle in [preferred * 45.0, preferred * 75.0, -preferred * 45.0, -preferred * 75.0, preferred * 110.0, -preferred * 110.0]:
		if not synchronous_path_tests and (_avoidance_probes<=0 or _local_nav_us+Time.get_ticks_usec()-avoid_start>=LOCAL_NAV_BUDGET_US):break
		_avoidance_probes-=1
		var candidate: Vector2 = original + direction.rotated(deg_to_rad(angle)) * stride
		if _movement_clear(e, original, candidate):
			e.avoid_dir = (candidate-original).normalized()
			e.avoid_until = time+.55
			e.reversing = _is_ground_vehicle(e) and absf(wrapf(rad_to_deg((candidate-original).angle())-float(e.alpha),-180,180))>100
			answer = candidate
			break
	_local_nav_us+=Time.get_ticks_usec()-avoid_start
	return answer

func _invalidate_static_geometry() -> void:
	_static_geometry_revision += 1
	_goal_standing_cache.clear()

func _goal_standing(e: Dictionary, goal: Vector2, radius: float) -> bool:
	# This tests a fixed destination against terrain/mines/buildings only.
	# Movement and every intervening collision sample still execute each tick.
	if not _in_step: return _standing(goal, radius, int(e.id), false)
	var old: Dictionary = _goal_standing_cache.get(int(e.id), {})
	if not old.is_empty() and old.goal == goal and float(old.radius) == radius and int(old.revision) == _static_geometry_revision:
		return bool(old.valid)
	var valid: bool = _standing(goal, radius, int(e.id), false)
	_goal_standing_cache[int(e.id)] = {"goal": goal, "radius": radius, "revision": _static_geometry_revision, "valid": valid}
	return valid


func _movement_clear(e: Dictionary, start: Vector2, next: Vector2, request_yield: bool = false) -> bool:
	if _in_step and _native_geometry_ready and native_movement_enabled and not (_rail_network.usable(self, e, start) and _rail_network.usable(self, e, next)):
		return _kernels.movement_clear(self, e, start, next, request_yield)
	var radius: float = _radius(e)
	if not _segment_static(start, next, radius, int(e.id)):
		return false
	var on_rail: bool = _rail_network.usable(self, e, start) and _rail_network.usable(self, e, next)
	for other in _movement_neighbors(start, next, radius):
		var id: int = int(other.id)
		if id == int(e.id) or float(other.hp) <= 0.0 or Transport.is_loaded(other):
			continue
		if on_rail and _rail_network.usable(self, other, other.pos): continue
		var combined: float = _movement_pair_radius(e, other)
		var other_start: Vector2 = _ground_motion_start(other)
		if not _swept_unit_contact(start-other_start, next-other.pos, Vector2.ZERO, combined):
			continue
		if _can_crush_target(e, other):
			continue
		if request_yield: _request_movement_yield(e, other, start, next)
		return false
	return true

func _movement_pair_radius(e: Dictionary, other: Dictionary) -> float:
	var a: float = _radius(e)
	var b: float = float(other.radius)
	if crowd_overlap_enabled and int(e.team) == int(other.team) and bool(e.get("ground_crush_eligible", false)) and bool(other.get("ground_crush_eligible", false)) and not bool(e.get("hold_position", false)) and not bool(other.get("hold_position", false)):
		return a + b - minf(.12, minf(a, b) * .12)
	return a + b + .02

func _movement_neighbors(start: Vector2, finish: Vector2, radius: float) -> Array:
	var reach: float = radius + _max_ground_radius + .02
	var local: bool = start.distance_to(finish) + reach <= 2.0
	if local and _ground_motion_spatial.is_empty(): return _neighbors(finish)
	var answer: Array = []
	var checked: Dictionary = {}
	var keys: Dictionary = {}
	if local:
		for z in range(-1, 2):
			for x in range(-1, 2): keys[_bucket(finish) + Vector2i(x, z)] = true
	else: keys = _segment_bucket_keys(start, finish, reach)
	for key in keys:
		for other in _spatial.get(key, []) + _ground_motion_spatial.get(key, []):
			if checked.has(int(other.id)): continue
			checked[int(other.id)] = true
			answer.append(other)
	return answer

func _ground_motion_start(e: Dictionary) -> Vector2:
	return e.ground_motion_from if _in_step and float(e.get("ground_motion_time", -1.0)) == time and e.get("ground_motion_from") is Vector2 else e.pos

func _swept_unit_contact(start: Vector2, finish: Vector2, center: Vector2, radius: float) -> bool:
	var before: float = start.distance_squared_to(center)
	# Recover old overlapping spawns only when the entire step separates them.
	if before < radius * radius and (finish-start).dot(start-center) >= 0.0 and finish.distance_squared_to(center) > before + .00001:
		return false
	var closest: Vector2 = Geometry2D.get_closest_point_to_segment(center, start, finish)
	return closest.distance_squared_to(center) < radius * radius



func _yield_destination(other: Dictionary, requested: Vector2) -> Vector2:
	if not RailNetwork.rail_only(data_for(other.spec)): return requested
	var point: Vector2 = RailNetwork.center(RailNetwork.key(requested))
	if point.distance_to(other.pos) < .25: return Vector2.INF
	return point if not _rail_network.traversable_path(self,other,other.pos,point).is_empty() else Vector2.INF

func _request_movement_yield(e: Dictionary, other: Dictionary, start: Vector2, next: Vector2) -> void:
	if _is_air(other): return # Parked aircraft remain stationary on the ground.
	var id: int = int(other.id)
	var propagating: bool = (e.get("yield_goal",Vector2.INF) as Vector2).is_finite()
	if (synchronous_path_tests or (_yield_requests>0 and _local_nav_us<LOCAL_NAV_BUDGET_US)) and time>=float(e.get("yield_request_at",0)) and int(e.team)==int(other.team) and not bool(other.get("hold_position",false)) and _traffic_may_yield(e,other) and not (other.get("yield_goal",Vector2.INF) as Vector2).is_finite():
		var yield_start:int=Time.get_ticks_usec()
		_yield_requests-=1
		e.yield_request_at=time+1.0
		var forward: Vector2=(next-start).normalized()
		# Preserve an active front unit's route when it can already advance.
		# Stealing that path forces a needless worker replan; propagated
		# retreats can otherwise repeatedly push same-route traffic away.
		if not other.commands.is_empty() and not other.path.is_empty() and not (_is_ground_vehicle(e) and _query_is_infantry(int(other.id))) and _navigation_priority(int(e.get("yield_root",e.id)))<=_navigation_priority(id):
			var waypoint_index:=0
			var other_radius: float=_radius(other)
			# Read the same effective waypoint that both movement backends will
			# use, without mutating the front unit's route during this request.
			while waypoint_index+1<other.path.size():
				var first: Vector2=other.path[waypoint_index]
				var following: Vector2=other.path[waypoint_index+1]
				var passed: bool=((other.pos as Vector2)-first).dot(following-first)>0 and Geometry2D.get_closest_point_to_segment(other.pos,first,following).distance_to(other.pos)<other_radius+.45
				if (other.pos as Vector2).distance_to(first)>=maxf(.45,other_radius) and not passed:break
				if not _claim_yield_probe(yield_start):
					_local_nav_us+=Time.get_ticks_usec()-yield_start
					return
				if not _segment_static(other.pos,following,other_radius,id):break
				waypoint_index+=1
			while waypoint_index<other.path.size() and (other.pos as Vector2).distance_to(other.path[waypoint_index])<.2:
				if waypoint_index+1<other.path.size():
					if not _claim_yield_probe(yield_start):
						_local_nav_us+=Time.get_ticks_usec()-yield_start
						return
					if not _segment_static(other.pos,other.path[waypoint_index+1],other_radius,id):break
				waypoint_index+=1
			if waypoint_index<other.path.size():
				var waypoint: Vector2=other.path[waypoint_index]
				var other_direction: Vector2=(waypoint-(other.pos as Vector2)).normalized()
				if propagating or forward.dot(other_direction)>.5:
					if not _claim_yield_probe(yield_start):
						_local_nav_us+=Time.get_ticks_usec()-yield_start
						return
					var other_stride: float=minf(float(data_for(other.spec).speed)*maxf(_step_delta,1.0/30.0)*float(other.get("rescue_speed_scale",1.0)),(other.pos as Vector2).distance_to(waypoint))
					if _movement_clear(other,other.pos,(other.pos as Vector2)+other_direction*other_stride,false):
						_local_nav_us+=Time.get_ticks_usec()-yield_start
						return
		var side: Vector2=forward.orthogonal()
		var retreat:=Vector2.INF
		var near_retreat:=Vector2.INF
		var retreat_seconds:=4.0
		var corridor_end:Vector2=start+forward*maxf(3.0,(other.pos as Vector2).distance_to(start)+_radius(e)+_radius(other))
		var clearance:float=_radius(e)+_radius(other)+.02+maxf(.25,_radius(other)*.4)
		var distances:Array=[1.2,1.8,2.4,.6]
		var speed: float=float(data_for(other.spec).speed)*maxf(_step_delta,1.0/30.0)*float(other.get("rescue_speed_scale",1.0))
		for distance in distances:
			for offset in [side,-side,forward,-forward,(side-forward).normalized(),(-side-forward).normalized()]:
				if not synchronous_path_tests and _local_nav_us+Time.get_ticks_usec()-yield_start>=LOCAL_NAV_BUDGET_US:break
				var point: Vector2=_yield_destination(other,other.pos+offset*distance)
				if not point.is_finite(): continue
				if _standing(point,_radius(other),id) and _segment_static(other.pos,point,_radius(other),id):
					if not _claim_yield_probe(yield_start):break
					if _movement_clear(other,other.pos,(other.pos as Vector2).move_toward(point,speed),false):
						if not near_retreat.is_finite():near_retreat=point
						if not (_is_ground_vehicle(e) and _query_is_infantry(int(other.id))) or Geometry2D.get_closest_point_to_segment(point,start,corridor_end).distance_to(point)>=clearance:
							retreat=point;break
			if retreat.is_finite():break
		if not retreat.is_finite() and near_retreat.is_finite():retreat=near_retreat
		if not retreat.is_finite():
			# Prefer a legal first stride over creating another blocked retreat.
			# If every first stride is occupied, keep the original distributed
			# chain fallback; the normal mover still guards every actual step.
			var axis := Vector2(signf(forward.x),0) if absf(forward.x)>absf(forward.y) else Vector2(0,signf(forward.y))
			var occupied_fallback:=Vector2.INF
			for offset in [axis,forward,side,-side,(side+forward).normalized(),(-side+forward).normalized()]:
				if not synchronous_path_tests and _local_nav_us+Time.get_ticks_usec()-yield_start>=LOCAL_NAV_BUDGET_US:break
				var point: Vector2=_yield_destination(other,other.pos+offset*1.2)
				if not point.is_finite(): continue
				if _standing(point,_radius(other),id,false) and _segment_static(other.pos,point,_radius(other),id):
					if not occupied_fallback.is_finite():occupied_fallback=point
					if not _claim_yield_probe(yield_start):break
					if _movement_clear(other,other.pos,(other.pos as Vector2).move_toward(point,speed),false):
						retreat=point
						break
			if not retreat.is_finite():retreat=occupied_fallback
			retreat_seconds=8.0
		if retreat.is_finite():
			other.yield_saved_path=other.path.duplicate()
			other.yield_saved_goal=other.path_goal
			other.yield_saved_revision=_static_geometry_revision
			other.yield_root=int(e.get("yield_root",e.id))
			if _is_ground_vehicle(e) and _query_is_infantry(int(other.id)):navigation_vehicle_yields+=1
			other.yield_goal=retreat
			other.yield_until=time+retreat_seconds
			other.reversing=_is_ground_vehicle(other) and absf(wrapf(rad_to_deg((retreat-other.pos).angle())-float(other.alpha),-180,180))>100
			# The retreat's full static connector was already checked above.
			# Reuse it immediately instead of queueing another search for the same leg.
			_cancel_path_request(id)
			other.path=[retreat];other.path_goal=retreat;other.path_wait=0.0
			other.progress_clock=0.0
			other.progress_anchor=other.pos
		_local_nav_us+=Time.get_ticks_usec()-yield_start

func _claim_yield_probe(yield_start: int) -> bool:
	if not synchronous_path_tests and (_avoidance_probes<=0 or _local_nav_us+Time.get_ticks_usec()-yield_start>=LOCAL_NAV_BUDGET_US):return false
	_avoidance_probes-=1
	return true

func _settle_crushing(e: Dictionary, next: Vector2) -> void:
	if _rail_network.usable(self, e, e.pos): return
	if not bool(e.can_crush):
		return
	var start: Vector2 = e.pos
	for other in _movement_neighbors(start, next, float(e.radius)):
		var combined: float = float(e.radius) + float(other.radius)
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(Vector2.ZERO, start-_ground_motion_start(other), next-other.pos)
		if float(other.hp) > 0.0 and not Transport.is_loaded(other) and _can_crush_target(e, other) and closest.length_squared() < combined * combined:
			_apply_ground_crush(e, other)

func _bucket(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / 2.0), floori(pos.y / 2.0))

func _rebuild_spatial() -> void:
	_neighbor_cache.clear()
	if _in_step and native_kernels_enabled and _kernels != null and not _spec_cache.is_empty():
		var index: Dictionary = _kernels.rebuild_spatial(entities, factions.size(), _air_specs, _naval_specs)
		_spatial = index.spatial
		_combat_spatial = index.combat
		_contact_spatial = index.contact_buckets
		_contact_indices = index.contact_indices
		_team_spatial = index.team_spatial
		_contact_ids = index.ids
		_contact_positions = index.positions
		_contact_teams = index.teams
		_contact_domains = index.domains
		_contacts_used = index.used
		# Rails remain in combat spatial buckets for AOE/forced targeting, but
		# zero acquisition masks keep the native nearest-target query fast.
		for rail: Dictionary in _rail_network.cells.values():
			var slot: int = int(_contact_indices.get(int(rail.id), -1))
			if slot >= 0: _contact_domains[slot] = 0
		return
	_spatial.clear()
	_combat_spatial.clear()
	_contact_spatial.clear()
	_contact_indices.clear()
	_contacts_used = 0
	_contact_ids.resize(entities.size())
	_contact_positions.resize(entities.size())
	_contact_teams.resize(entities.size())
	_contact_domains.resize(entities.size())
	for team in range(factions.size()): _team_spatial[team].clear()
	for e in entities.values():
		if float(e.hp) <= 0.0 or Transport.is_loaded(e): continue
		# Rebuild from the live record in one pass. Incremental insertion must
		# look records up and invalidate neighbors; neither is needed after clear.
		var id: int = int(e.id)
		var pos: Vector2 = e.pos
		var team: int = int(e.team)
		var air: bool = _is_air(e)
		var slot: int = _contacts_used
		_contacts_used += 1
		_contact_indices[id] = slot
		_contact_ids[slot] = id
		_contact_positions[slot] = pos
		_contact_teams[slot] = team
		_contact_domains[slot] = 0 if RailNetwork.is_rail(data_for(e.spec)) else (2 if air else (4 if _target_domain(e)=="naval" else 1))
		var combat_key: Vector2i = _combat_bucket(pos)
		if not _team_spatial[team].has(combat_key): _team_spatial[team][combat_key] = []
		_team_spatial[team][combat_key].append(id)
		if not _combat_spatial.has(combat_key): _combat_spatial[combat_key] = []
		_combat_spatial[combat_key].append(id)
		if not _contact_spatial.has(combat_key): _contact_spatial[combat_key] = []
		_contact_spatial[combat_key].append(slot)
		if e.kind != "unit" or (air and bool(e.get("airborne", true))) or _target_domain(e)=="naval": continue
		var key: Vector2i = _bucket(pos)
		if not _spatial.has(key): _spatial[key] = []
		_spatial[key].append(e)

func _combat_bucket(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / 8.0), floori(pos.y / 8.0))

func _spatial_add(id: int, pos: Vector2) -> void:
	if Transport.is_loaded(entities[id]): return
	var slot: int = _update_contact(entities[id])
	var combat_key: Vector2i = _combat_bucket(pos)
	var team: int = int(entities[id].team)
	if not _team_spatial[team].has(combat_key):
		_team_spatial[team][combat_key] = []
	_team_spatial[team][combat_key].append(id)
	if not _combat_spatial.has(combat_key): _combat_spatial[combat_key] = []
	_combat_spatial[combat_key].append(id)
	if not _contact_spatial.has(combat_key): _contact_spatial[combat_key] = []
	_contact_spatial[combat_key].append(slot)
	if entities[id].kind != "unit" or (_is_air(entities[id]) and bool(entities[id].get("airborne", true))) or _target_domain(entities[id])=="naval":
		return
	var key: Vector2i = _bucket(pos)
	_invalidate_neighbors(key)
	if not _spatial.has(key):
		_spatial[key] = []
	_spatial[key].append(entities[id])

func _spatial_remove(id: int, pos: Vector2) -> void:
	var combat_key: Vector2i = _combat_bucket(pos)
	var team: int = int(entities[id].team)
	if _team_spatial[team].has(combat_key):
		_team_spatial[team][combat_key].erase(id)
	if _combat_spatial.has(combat_key): _combat_spatial[combat_key].erase(id)
	var slot: int = int(_contact_indices.get(id, -1))
	if slot >= 0:
		_contact_domains[slot] = 0
		if _contact_spatial.has(combat_key): _contact_spatial[combat_key].erase(slot)
	var key: Vector2i = _bucket(pos)
	if _spatial.has(key):
		_invalidate_neighbors(key)
		_spatial[key].erase(entities[id])

func _invalidate_neighbors(key: Vector2i) -> void:
	if _neighbor_cache.is_empty(): return
	for z in range(-1, 2):
		for x in range(-1, 2): _neighbor_cache.erase(key + Vector2i(x, z))

func _spatial_move(e: Dictionary, original: Vector2, next: Vector2) -> void:
	# Buckets hold live entity dictionaries, so positions update without changing
	# membership. Only crossing a bucket boundary invalidates nearby membership.
	var old_combat: Vector2i = _combat_bucket(original)
	var new_combat: Vector2i = _combat_bucket(next)
	var slot: int = int(_contact_indices.get(int(e.id), -1))
	if slot >= 0: _contact_positions[slot] = next
	if old_combat != new_combat:
		var team: int = int(e.team)
		if _team_spatial[team].has(old_combat): _team_spatial[team][old_combat].erase(int(e.id))
		if not _team_spatial[team].has(new_combat): _team_spatial[team][new_combat] = []
		_team_spatial[team][new_combat].append(int(e.id))
		if _combat_spatial.has(old_combat): _combat_spatial[old_combat].erase(int(e.id))
		if not _combat_spatial.has(new_combat): _combat_spatial[new_combat] = []
		_combat_spatial[new_combat].append(int(e.id))
		if slot >= 0:
			if _contact_spatial.has(old_combat): _contact_spatial[old_combat].erase(slot)
			if not _contact_spatial.has(new_combat): _contact_spatial[new_combat] = []
			_contact_spatial[new_combat].append(slot)
	if (_is_air(e) and bool(e.get("airborne", true))) or _target_domain(e)=="naval" or Transport.is_loaded(e): return
	if _in_step:
		e.ground_motion_from = original
		e.ground_motion_time = time
		for key in _segment_bucket_keys(original, next, .5):
			if not _ground_motion_spatial.has(key): _ground_motion_spatial[key] = []
			_ground_motion_spatial[key].append(e)
	var old_key: Vector2i = _bucket(original)
	var new_key: Vector2i = _bucket(next)
	if old_key == new_key: return
	_invalidate_neighbors(old_key)
	_invalidate_neighbors(new_key)
	if _spatial.has(old_key): _spatial[old_key].erase(e)
	if not _spatial.has(new_key): _spatial[new_key] = []
	_spatial[new_key].append(e)

func _update_contact(e: Dictionary) -> int:
	var id: int = int(e.id)
	var slot: int = int(_contact_indices.get(id, -1))
	if slot < 0:
		slot = _contacts_used
		_contacts_used += 1
		_contact_indices[id] = slot
		if slot >= _contact_ids.size():
			_contact_ids.resize(slot + 1)
			_contact_positions.resize(slot + 1)
			_contact_teams.resize(slot + 1)
			_contact_domains.resize(slot + 1)
			_contact_visibility.resize(slot + 1)
	_contact_ids[slot] = id
	_contact_positions[slot] = e.pos
	_contact_teams[slot] = int(e.team)
	_contact_domains[slot] = 0 if float(e.hp) <= 0.0 or Transport.is_loaded(e) or RailNetwork.is_rail(data_for(e.spec)) else (2 if _is_air(e) else (4 if _target_domain(e)=="naval" else 1))
	_contact_visibility[slot] = int(e.get("visible_to", (1 << factions.size()) - 1 if not vision_enabled else 1 << int(e.team)))
	return slot

func _nearby_entities(pos: Vector2, reach: float) -> Array:
	if not _in_step: return entities.values()
	var ids: Array[int] = []
	var first: Vector2i = _combat_bucket(pos - Vector2.ONE * reach)
	var last: Vector2i = _combat_bucket(pos + Vector2.ONE * reach)
	for z in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			for id in _combat_spatial.get(Vector2i(x, z), []):
				if entities.has(id): ids.append(int(id))
	# Preserve the authoritative insertion order for simultaneous impact/death.
	ids.sort()
	var answer: Array = []
	for id in ids: answer.append(entities[id])
	return answer

func _neighbors(pos: Vector2) -> Array:
	var cell: Vector2i = _bucket(pos)
	if _neighbor_cache.has(cell):
		return _neighbor_cache[cell]
	var answer: Array = []
	for z in range(-1, 2):
		for x in range(-1, 2):
			answer.append_array(_spatial.get(cell + Vector2i(x, z), []))
	_neighbor_cache[cell] = answer
	return answer

func _step_harvester(e: Dictionary, delta: float) -> void:
	var capacity: float = float(_eco("harvester_capacity", 500))
	if bool(e.get("manual_unload",false)) or float(e.cargo) >= capacity - 0.001 or (float(e.cargo) > 0.0 and _available_ore() == 0):
		_release_mine(int(e.id))
		var refinery_id: int = int(e.harvest_refinery)
		if not entities.has(refinery_id) or int(entities[refinery_id].team) != int(e.team) or float(entities[refinery_id].construct_remaining) > 0.0:
			refinery_id = _find_refinery(e)
			e.harvest_refinery = refinery_id
		if refinery_id < 0:
			e.state = "waiting"
			return
		var refinery: Dictionary = entities[refinery_id]
		RefineryDocking.approach(self,e,refinery,delta)
		return
	var mine_index: int = int(e.harvest_mine)
	if mine_index < 0 or mine_index >= mines.size():
		mine_index = _find_mine(e)
		e.harvest_mine = mine_index
	if mine_index < 0:
		e.state = "waiting"
		return
	var mine: Dictionary = mines[mine_index]
	if not _mine_available(mine_index, int(e.id)):
		e.state = "waiting"
		if not e.has("preferred_mine"):
			e.harvest_mine = -1
			e.mining_goal = Vector2.INF
		return
	if e.pos.distance_to(mine.pos) <= _radius(e) + float(_eco("harvester_mining_margin", 1.4)):
		mine.miner = int(e.id)
		var budget: float = float(_mine_tick_budget.get(mine_index, float(_eco("harvest_rate", 25)) * delta))
		var ore: float = minf(budget, capacity - float(e.cargo))
		if bool(_eco("finite_ore", false)):
			ore = minf(ore, float(mine.amount))
			mine.amount = maxf(0, float(mine.amount) - ore)
		_mine_tick_budget[mine_index] = maxf(0.0, budget - ore)
		e.cargo += ore
		e.state = "harvest"
		if float(e.cargo) >= capacity - 0.001: _release_mine(int(e.id))
	else:
		var approach: Vector2 = _mining_approach(e,mine_index)
		if approach.is_finite():
			_move_to(e, approach, delta)
		else:
			e.state = "waiting"

func _refresh_ruin_spatial() -> void:
	_invalidate_static_geometry()
	_ruin_spatial.clear()
	_ruin_geometry_chunks.clear()
	_ruin_geometry_dirty.clear()
	_ruin_geometry_chunks.resize(ceili(float(ruins.size()) / RUIN_GEOMETRY_CHUNK_SIZE))
	for index in range(_ruin_geometry_chunks.size()): _ruin_geometry_dirty[index] = true
	for ruin in ruins:
		var first: Vector2i = _bucket(ruin.pos-ruin.half-Vector2.ONE*2)
		var last: Vector2i = _bucket(ruin.pos+ruin.half+Vector2.ONE*2)
		for z in range(first.y,last.y+1):
			for x in range(first.x,last.x+1):
				var key:=Vector2i(x,z)
				if not _ruin_spatial.has(key):_ruin_spatial[key]=[]
				_ruin_spatial[key].append(ruin)

func _nearby_ruins(pos: Vector2, reach: float) -> Array:
	return neutral_in_rect(Rect2(pos - Vector2.ONE * reach, Vector2.ONE * reach * 2.0))

func neutral_in_rect(region: Rect2) -> Array[Dictionary]:
	# Broad-phase candidates from padded footprint buckets. Picking/collision
	# callers retain their exact mesh or shape tests; this array is independent.
	region = region.abs()
	var found: Dictionary = {}
	var first: Vector2i = _bucket(region.position)
	var last: Vector2i = _bucket(region.end)
	for z in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			for ruin in _ruin_spatial.get(Vector2i(x, z), []):
				if float(ruin.hp) > 0.0: found[int(ruin.id)] = ruin
	var ids: Array = found.keys()
	ids.sort()
	var answer: Array[Dictionary] = []
	for id in ids: answer.append(found[id])
	return answer

func _refresh_mine_spatial() -> void:
	_invalidate_static_geometry()
	_mine_spatial.clear()
	_mine_spatial_count = mines.size()
	if mines.size() <= 8: return
	for mine in mines:
		var first: Vector2i = _bucket(mine.pos - MINE_HALF - Vector2.ONE * 2.0)
		var last: Vector2i = _bucket(mine.pos + MINE_HALF + Vector2.ONE * 2.0)
		for z in range(first.y, last.y + 1):
			for x in range(first.x, last.x + 1):
				var key := Vector2i(x, z)
				if not _mine_spatial.has(key): _mine_spatial[key] = []
				_mine_spatial[key].append(mine)

func _nearby_mines(pos: Vector2, radius: float) -> Array:
	if mines.size() <= 8 or radius > 2.0: return mines
	if _mine_spatial_count != mines.size(): _refresh_mine_spatial()
	return _mine_spatial.get(_bucket(pos), [])

func ruin_at(pos: Vector2) -> int:
	for ruin in _ruin_spatial.get(_bucket(pos),[]):
		if float(ruin.hp)>0 and _circle_rect(pos,.25,ruin.pos,ruin.half):return RUIN_TARGET_BASE-int(ruin.id)
	return -1

func ruin_by_target(target: int) -> Dictionary:
	var index: int = RUIN_TARGET_BASE-target
	return ruins[index] if index>=0 and index<ruins.size() else {}

func mine_at(pos: Vector2) -> int:
	var nearest: int = -1
	var distance: float = 2.5
	for i in range(mines.size()):
		var d: float = pos.distance_to(mines[i].pos)
		if d < distance:
			distance = d
			nearest = i
	return nearest

func _release_mine(unit_id: int) -> void:
	if entities.has(unit_id) and not str(entities[unit_id].spec).ends_with("_harvester"): return
	for mine in mines:
		if int(mine.get("miner", -1)) == unit_id: mine.miner = -1

func _refresh_mine_claims() -> void:
	for index in range(mines.size()):
		var mine: Dictionary = mines[index]
		var drill_id: int = int(mine.get("drill", -1))
		if drill_id > 0 and not entities.has(drill_id): mine.drill = -1
		var id: int = int(mine.get("miner", -1))
		mine.miner = id
		if id < 0: continue
		if not entities.has(id):
			mine.miner = -1
			continue
		var e: Dictionary = entities[id]
		var harvesting: bool = e.commands.is_empty() and not bool(e.harvest_override)
		if not e.commands.is_empty(): harvesting = e.commands[0].kind == "harvest"
		if float(e.hp) <= 0.0 or not str(e.spec).ends_with("_harvester") or not harvesting or int(e.harvest_mine) != index or float(e.cargo) >= float(_eco("harvester_capacity", 500)) - 0.001 or (e.pos as Vector2).distance_to(mine.pos) > _radius(e) + float(_eco("harvester_mining_margin", 1.4)):
			mine.miner = -1

func _mine_available(index: int, unit_id: int) -> bool:
	return int(mines[index].get("drill", -1)) < 0 and int(mines[index].get("miner", -1)) in [-1, unit_id] and (not bool(_eco("finite_ore", false)) or float(mines[index].amount) > 0)

func _mining_approach(e: Dictionary, index: int) -> Vector2:
	if RailNetwork.rail_only(data_for(e.spec)): return _rail_network.nearest_connected(self, e, mines[index].pos, _radius(e) + float(_eco("harvester_mining_margin", 1.4)))
	var center: Vector2 = mines[index].pos
	var radius: float = _radius(e)
	var arrival: float = maxf(.25, radius*.4)
	var contact: float = radius + float(_eco("harvester_mining_margin",1.4))
	var approach_distance: float = contact-arrival-.1
	var previous: Vector2 = e.get("mining_goal",Vector2.INF)
	if previous.is_finite() and previous.distance_to(center) <= approach_distance+.0001 and _standing(previous,radius,int(e.id)):
		return previous
	var candidates: Array[Vector2]=[]
	for offset in range(6):
		var angle: float = ((int(e.id)+offset)%6) * TAU/6.0
		var point: Vector2 = center + Vector2.from_angle(angle)*approach_distance
		if not _standing(point,_radius(e),int(e.id)): continue
		var reserved: bool = false
		for other in _neighbors(center):
			if other.id == e.id: continue
			var goal: Vector2 = other.get("mining_goal",Vector2.INF)
			if goal.is_finite() and goal.distance_to(point)<_radius(e)+_radius(other)+.05:
				reserved=true;break
		if not reserved:candidates.append(point)
	if not candidates.is_empty():
		candidates.sort_custom(func(a:Vector2,b:Vector2):return e.pos.distance_squared_to(a)<e.pos.distance_squared_to(b))
		e.mining_goal=candidates[0]
		return candidates[0]
	return Vector2.INF

func _available_ore() -> int:
	var count: int = 0
	for index in range(mines.size()):
		if int(mines[index].get("drill", -1)) < 0 and (not bool(_eco("finite_ore", false)) or float(mines[index].amount) > 0): count += 1
	return count

func _find_mine(e: Dictionary) -> int:
	return _find_resource_target(e, false)

func _resource_candidates(e: Dictionary, refinery_search: bool) -> Array[int]:
	var ranked: Array[Dictionary] = []
	if refinery_search:
		for refinery in _building_entities:
			if _eligible_refinery(e, refinery):
				ranked.append({"id": int(refinery.id), "distance": (e.pos as Vector2).distance_squared_to(refinery.pos)})
	else:
		for index in range(mines.size()):
			if _mine_available(index, int(e.id)):
				ranked.append({"id": index, "distance": (e.pos as Vector2).distance_squared_to(mines[index].pos)})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.distance) < float(b.distance) if a.distance != b.distance else int(a.id) < int(b.id))
	var answer: Array[int] = []
	for entry in ranked:
		answer.append(int(entry.id))
	return answer

func _eligible_refinery(e: Dictionary, refinery: Dictionary) -> bool:
	return refinery.kind == "building" and int(refinery.team) == int(e.team) and float(refinery.hp) > 0.0 and float(refinery.construct_remaining) <= 0.0 and data_for(refinery.spec).get("role", "") == "refinery"

func _find_resource_target(e: Dictionary, refinery_search: bool) -> int:
	var field: String = "refinery_search" if refinery_search else "mine_search"
	var search: Dictionary = e.get(field, {})
	if search.is_empty() or int(search.next) >= search.candidates.size():
		if not search.is_empty() and float(search.retry_at) > time:
			return -1
		search = {"candidates": _resource_candidates(e, refinery_search), "next": 0, "retry_at": 0.0}
		e[field] = search
	while int(search.next) < search.candidates.size():
		var candidate: int = int(search.candidates[int(search.next)])
		var goal := Vector2.INF
		if refinery_search:
			if entities.has(candidate) and _eligible_refinery(e, entities[candidate]):
				goal = _refinery_approach(e, entities[candidate])
		elif candidate < mines.size() and _mine_available(candidate, int(e.id)):
			goal = _mining_approach(e,candidate)
		if goal.is_finite():
			var path: Array = _path_between(e.pos, goal, _radius(e), int(e.id))
			if _plan_was_deferred:
				return -1
			search.next = int(search.next) + 1
			if not path.is_empty():
				# Reuse the feasibility path rather than charge a second plan to depart.
				e.path = path
				e.path_goal = goal
				e.path_wait = 1.0
				e[field] = {}
				return candidate
		else:
			search.next = int(search.next) + 1
	search.retry_at = time + 1.0
	return -1

func _refinery_approach(e: Dictionary, refinery: Dictionary) -> Vector2:
	if str(e.spec).ends_with("_harvester") and data_for(refinery.spec).get("role", "") == "refinery": return RefineryDocking.entrance(self,e,refinery)
	if RailNetwork.rail_only(data_for(e.spec)):
		var exit: Vector2 = _rail_network.exit_cell(self, refinery)
		return exit if not _rail_network.traversable_path(self, e, e.pos, exit).is_empty() else Vector2.INF
	var half: float = float(data_for(refinery.spec).size) * 0.5 + _radius(e) + 0.25
	var best := Vector2.INF
	var distance: float = INF
	for direction in [Vector2.DOWN, Vector2.RIGHT, Vector2.LEFT, Vector2.UP]:
		var goal: Vector2 = refinery.pos + direction * half
		if _standing(goal, _radius(e), int(e.id), false):
			var candidate: float = e.pos.distance_to(goal)
			if candidate < distance:
				best = goal
				distance = candidate
	return best

func _find_refinery(e: Dictionary) -> int:
	return _find_resource_target(e, true)

func _step_bridge_repair(e: Dictionary, command: Dictionary, delta: float) -> void:
	if not str(e.spec).ends_with("_engineer"):
		e.state = "waiting"
		return
	var bridge: Dictionary = _bridge_by_id(BRIDGE_TARGET_BASE - int(command.target))
	if bridge.is_empty():
		_finish_command(e)
		return
	var maximum_hp: float = float(_eco("bridge_hp", 1200))
	if bool(bridge.alive) and float(bridge.hp) >= maximum_hp:
		_finish_command(e)
		return
	var head := Vector2.INF
	var distance: float = INF
	for raw_head in bridge.heads:
		var candidate: Vector2 = _vec(raw_head)
		var d: float = e.pos.distance_to(candidate)
		if d < distance and _land(candidate):
			head = candidate
			distance = d
	if not head.is_finite():
		e.state = "unreachable"
		return
	if distance > 1.2:
		_move_to(e, head, delta)
		return
	var bridge_id: int = int(bridge.id)
	if _bridge_repairers.has(bridge_id):
		e.state = "waiting"
		return
	_bridge_repairers[bridge_id] = int(e.id)
	if bool(bridge.alive):
		bridge.repair_progress = float(bridge.hp) / maximum_hp
	var full_time: float = float(_eco("bridge_time", 10))
	var full_cost: float = float(_eco("bridge_cost", 400))
	var increase: float = minf(delta / maxf(full_time, 0.001), 1.0 - float(bridge.repair_progress))
	if full_cost > 0.0:
		increase = minf(increase, money[int(e.team)] / full_cost)
	money[int(e.team)] = maxf(0.0, money[int(e.team)] - increase * full_cost)
	bridge.repair_progress = float(bridge.repair_progress) + increase
	e.state = "repair" if increase > 0.0 else "waiting"
	if bool(bridge.alive):
		bridge.hp = float(bridge.repair_progress) * maximum_hp
	if float(bridge.repair_progress) >= 1.0 - 0.000000001:
		bridge.repair_progress = 1.0
		bridge.hp = float(_eco("bridge_hp", 1200))
		bridge.alive = true
		var changed_bounds: Array = bridge.bounds
		_mark_nav_region(Rect2(float(changed_bounds[0]), float(changed_bounds[1]), float(changed_bounds[2]), float(changed_bounds[3])))
		events.append({"kind": "build", "pos": _bridge_center(bridge), "bridge": bridge.id})
		_finish_command(e)

func _step_ai() -> void:
	if factions.size() != 2: return
	var team: int = 1
	var faction: String = factions[team]
	ai_rebuild_base(team)
	var order: Dictionary = building_orders[team]
	for channel in ["normal", "defense"]:
		if not order_for_team(team, channel).is_empty() and bool(order_for_team(team, channel).ready): _ai_place(team, channel)
	if order.is_empty() and _has_construction_base(team):
		var next: String = ""
		var energy: Vector2 = power(team)
		if not _has_role(team, "power") or energy.x < energy.y + 70.0:
			next = "power"
		elif faction == "rivet" and not _has_role(team, "drill"):
			MiningDrills.ai_build(self, team)
		elif faction != "rivet" and not _has_role(team, "refinery"):
			next = "refinery"
		elif not _has_role(team, "barracks"):
			next = "barracks"
		elif not _has_role(team, "factory"):
			next = "factory"
		elif not _has_role(team, "command") and rules.buildings.has(faction + "_command") and money[team] > 1300.0:
			next = "command"
		elif _has_role(team, "command") and not _has_role(team, "airfield") and rules.buildings.has(faction + "_airfield") and money[team] > 2000.0:
			next = "airfield"
		elif not _has_role(team, "tech") and money[team] > 1400.0:
			next = "tech"
		elif money[team] > 3300.0 and _role_count(team, "factory") < 3:
			next = "factory"
		elif faction != "rivet" and money[team] > 2500.0 and _role_count(team, "refinery") < 2:
			next = "refinery"
		if next != "":
			ai_build(team, building_spec(team, next))
	if defense_orders[team].is_empty() and _has_construction_base(team) and not _has_role(team, "tower") and money[team] > 1000.0:
		ai_build(team, faction + "_tower")
	var reserve: float = 0.0
	if building_orders[team].is_empty():
		for role in ["power", "refinery", "barracks", "factory", "command", "airfield", "tech"]:
			if rules.buildings.has(faction + "_" + role) and not _has_role(team, role):
				reserve = float(data_for(faction + "_" + role).cost)
				break
	var rebuilding_base: bool = not _has_construction_base(team) and bool(data_for(faction+"_hq").get("rebuildable", false))
	if rebuilding_base:
		reserve = maxf(reserve, float(data_for(faction+"_hq").cost))
	var infrastructure_reserve: float = reserve
	# Reserve one aviation order before ground queues consume each ore delivery.
	for building in _building_entities:
		if int(building.team) == team and _airfield_valid(int(building.id), team) and _airfield_load(int(building.id)) < int(data_for(building.spec).get("aircraft_capacity", 4)):
			var aircraft_choice: String = _ai_aircraft_choice(team)
			if rules.units.has(aircraft_choice): reserve = maxf(reserve, float(data_for(aircraft_choice).cost))
	var harvesters: int = 0
	for e in entities.values():
		if int(e.team) == team and str(e.spec).ends_with("_harvester"):
			harvesters += 1
	var combat_ids: Array = []
	var ground_attack_ids: Array = []
	for e in entities.values():
		if int(e.team) != team or Transport.is_loaded(e):
			continue
		if e.kind == "building" and float(e.construct_remaining) <= 0.0:
			var role: String = str(data_for(e.spec).get("role", ""))
			if e.queue.size() < 2:
				if role == "factory":
					if faction != "rivet" and harvesters < maxi(2, _role_count(team, "refinery")) and (faction != "iron" or _rail_network.ai_connect_factory(self, e)):
						if (not rebuilding_base or money[team] >= reserve + float(data_for(faction + "_harvester").cost)) and produce(int(e.id), faction + "_harvester") == "":
							harvesters += 1
					elif money[team] > reserve + 1050.0:
						var choice: String = faction + "_tank"
						var artillery: String = faction + ("_artillery" if faction == "kestrel" else "_assault")
						var aa: String = faction + "_aa"
						if rules.units.has(aa) and (_enemy_air_count(team) > _unit_spec_count(team, aa) or int(time / 2.0) % 4 == 0): choice = aa
						elif rules.units.has(artillery) and _requirements(team, data_for(artillery)) == "" and int(time / 2.0) % 3 == 0: choice = artillery
						elif rules.units.has(faction + "_advanced") and _requirements(team, data_for(faction + "_advanced")) == "" and int(time / 2.0) % 7 == 0: choice = faction + "_advanced"
						if money[team] >= reserve + production_cost(choice): produce(int(e.id), choice)
				elif role == "airfield":
					var aircraft: String = _ai_aircraft_choice(team)
					if rules.units.has(aircraft) and money[team] >= infrastructure_reserve + float(data_for(aircraft).cost): produce(int(e.id), aircraft)
				elif TechAvailability.producer_matches(self, e, "barracks") and money[team] > reserve + 350.0:
					var unit_spec: String = faction + ("_anti" if int(time) % 3 == 0 else "_rifle")
					if faction == "kestrel" and _has_role(team, "tech") and int(time) % 5 == 0:
						unit_spec = faction + "_demolition"
					produce(int(e.id), unit_spec)
			if float(e.hp) < max_hp(e) * 0.65 and money[team] > 250.0:
				e.repairing = true
		elif e.kind == "unit" and str(data_for(e.spec).get("weapon", "")) != "":
			combat_ids.append(int(e.id))
			if "ground" in rules.weapons[str(data_for(e.spec).weapon)].get("targets", ["ground"]): ground_attack_ids.append(int(e.id))
	var base: Vector2 = _vec(map.starts[team])
	var threat: int = -1
	var nearest: float = 24.0
	for enemy in entities.values():
		if int(enemy.team) != team and enemy.kind == "unit" and not Transport.is_loaded(enemy):
			var distance: float = enemy.pos.distance_to(base)
			if distance < nearest and _force_can_target(combat_ids, int(enemy.id)):
				nearest = distance
				threat = int(enemy.id)
	if threat >= 0:
		for id in combat_ids:
			if _weapon_can_target(entities[id], threat) and (entities[id].commands.is_empty() or str(entities[id].commands[0].kind) != "attack"):
				issue([id], "attack", entities[threat].pos, threat)
	elif not ground_attack_ids.is_empty() and (ground_attack_ids.size() >= 5 or time >= 420.0) and _ai_attack_clock >= 28.0:
		_ai_attack_clock = 0.0
		var target: int = _ai_enemy_building(base)
		if target >= 0:
			var idle: Array = []
			for id in combat_ids:
				if entities[id].commands.is_empty() or str(entities[id].commands[0].kind) == "move" or entities[id].state == "unreachable" or (str(entities[id].commands[0].kind) == "attack_move" and (entities[id].commands[0].pos as Vector2).distance_to(entities[target].pos) > 7.0):
					idle.append(id)
			issue(idle, "attack_move", entities[target].pos)

func _force_can_target(ids: Array, target: int) -> bool:
	for id in ids:
		if _weapon_can_target(entities[int(id)], target): return true
	return false

func _unit_spec_count(team: int, spec: String) -> int:
	var count: int = 0
	for e in entities.values():
		if int(e.team) != team: continue
		if e.spec == spec: count += 1
		for order in e.queue:
			if order.spec == spec: count += 1
	return count

func _ai_aircraft_choice(team: int) -> String:
	var faction: String = factions[team]
	var fighter: String = faction + "_fighter"
	var strike: String = faction + ("_attacker" if faction == "kestrel" else "_bomber")
	var fighters: int = 0
	var strikes: int = 0
	for e in entities.values():
		if int(e.team) != team: continue
		if e.spec == fighter: fighters += 1
		elif e.spec == strike: strikes += 1
		for order in e.queue:
			if order.spec == fighter: fighters += 1
			elif order.spec == strike: strikes += 1
	if fighters > strikes and rules.units.has(strike) and _requirements(team, data_for(strike)) == "": return strike
	return fighter

func _enemy_air_count(team: int) -> int:
	var amount: int = 0
	for e in entities.values():
		if int(e.team) != team and _is_air(e): amount += 1
	return amount

func _role_count(team: int, role: String) -> int:
	var amount: int = 0
	for e in entities.values():
		if int(e.team) == team and e.kind == "building" and (data_for(e.spec).get("role", "") == role or role in data_for(e.spec).get("production_roles", [])):
			amount += 1
	return amount

func ai_rebuild_base(team: int) -> void:
	var base_spec: String = building_spec(team, "hq")
	if not base_spec.is_empty() and bool(data_for(base_spec).get("rebuildable", false)) and not _has_construction_base(team) and order_for_team(team).is_empty(): ai_build(team, base_spec)

func ai_build(team: int, spec: String) -> String:
	if not TechAvailability.engineer_building(self, team, data_for(spec)): return build(team, spec)
	for e in entities.values():
		if _builder_valid(team, int(e.id)) and e.commands.is_empty() and not [order_for_team(team, "normal"), order_for_team(team, "defense")].any(func(order): return int(order.get("builder", -1)) == int(e.id)): return build(team, spec, int(e.id))
	var engineer_spec: String = factions[team] + "_engineer"
	if _unit_spec_count(team, engineer_spec) < 1:
		for e in _building_entities:
			if int(e.team) == team and TechAvailability.producer_matches(self, e, "barracks") and availability(team, engineer_spec, -1, int(e.id)).is_empty():
				return produce(int(e.id), engineer_spec)
	return "等待空闲工程兵"

func _ai_enemy_building(origin: Vector2) -> int:
	var answer: int = -1
	var best: float = INF
	for e in entities.values():
		if int(e.team) == 0 and e.kind == "building":
			var distance: float = origin.distance_to(e.pos)
			if distance < best:
				best = distance
				answer = int(e.id)
	return answer

func _ai_place(team: int, channel: String = "normal") -> void:
	var pending_rail_order: Dictionary = order_for_team(team, channel)
	if factions[team] == "iron" and not pending_rail_order.is_empty() and data_for(pending_rail_order.spec).get("role", "") == "refinery":
		_rail_network.ai_place_refinery(self, team, channel)
		return
	var zones: Array[Dictionary] = construction_zones(team)
	var order: Dictionary = order_for_team(team, channel)
	if zones.is_empty() and not order.is_empty() and bool(data_for(order.spec).get("rebuildable", false)):
		var builder: int = int(order.get("builder", -1))
		zones.append({"pos":entities[builder].pos if _builder_valid(team, builder) else _team_start(team), "radius":24.0})
	for zone: Dictionary in zones:
		var origin: Vector2 = zone.pos
		# Keep the established search for large zones, and also sample tiny
		# completed wall/barricade zones instead of skipping them entirely.
		var first_ring: int = mini(5, maxi(1, ceili(float(zone.radius)) - 1))
		for ring in range(first_ring, ceili(float(zone.radius)) + 1):
			for n in range(24):
				var point: Vector2 = origin + Vector2.from_angle(float(n) * TAU / 24.0 + 0.31) * float(ring)
				if placement_error(team, point, channel) == "":
					place_building(team, point, channel)
					return

func _notice(message: String) -> void:
	notices.append(message)
	if notices.size() > 8:
		notices.pop_front()

func save_game(path: String, visual_memory_snapshot: Dictionary = {}) -> String:
	statistics.sample(self,true)
	var snapshot: Dictionary = {"format": "paper_war", "version": SAVE_VERSION, "rules": rules.duplicate(true), "map": map.duplicate(true), "factions": factions.duplicate(), "money": money.duplicate(), "time": time, "result": result, "entities": entities.duplicate(true), "projectiles": projectiles.duplicate(true), "mines": mines.duplicate(true), "bridges": bridges.duplicate(true), "ruins": ruins.duplicate(true), "building_orders": building_orders.duplicate(true), "defense_orders": defense_orders.duplicate(true), "next_id": _next_id, "ai_enabled": ai_enabled, "ai_clock": _ai_clock, "ai_attack_clock": _ai_attack_clock, "ai_state":ai_state.duplicate(true), "low_power": _low_power.duplicate(), "nav_dirty": _nav_dirty, "nav_regions": _nav_regions.duplicate(), "planning_max_wait": _planning_max_wait, "planning_queue": _planning_queue.duplicate(), "navigation_command_until":_navigation_command_until.duplicate(), "static_geometry_revision":_static_geometry_revision, "match_options":match_options.duplicate(true), "team_vision":team_vision.duplicate(true)}
	snapshot.match_statistics=statistics.to_dict()
	if not visual_memory_snapshot.is_empty(): snapshot.visual_memory = visual_memory_snapshot.duplicate(true)
	if campaign_controller != null: snapshot.campaign = campaign_controller.to_dict()
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "无法写入存档：" + error_string(FileAccess.get_open_error())
	file.store_var(snapshot, false)
	file.close()
	return ""

func load_game(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "无法读取存档：" + error_string(FileAccess.get_open_error())
	var raw: Variant = file.get_var(false)
	file.close()
	if not raw is Dictionary:
		return "存档损坏或格式不兼容"
	var snapshot: Dictionary = raw
	if snapshot.get("format", "") != "paper_war" or not snapshot.get("version") is int or snapshot.version != SAVE_VERSION:
		return "不兼容的存档版本"
	for field in ["rules", "map", "factions", "money", "time", "entities", "projectiles", "mines", "bridges", "building_orders", "next_id"]:
		if not snapshot.has(field):
			return "存档缺少字段：" + field
	# Version 1 saves used one order slot. Move an old wall or tower to the
	# new defense channel before validating the normalized authoritative state.
	if not snapshot.has("defense_orders") and snapshot.get("factions") is Array and snapshot.get("building_orders") is Array and snapshot.get("rules") is Dictionary:
		var old_defense: Array = []
		for team in range(snapshot.factions.size()):
			var legacy_order: Dictionary = snapshot.building_orders[team] if team < snapshot.building_orders.size() and snapshot.building_orders[team] is Dictionary else {}
			if not legacy_order.is_empty() and snapshot.rules.get("buildings", {}).has(str(legacy_order.get("spec", ""))) and BuildingConstruction.channel_for(snapshot.rules.buildings[legacy_order.spec]) == "defense":
				old_defense.append(legacy_order)
				snapshot.building_orders[team] = {}
			else: old_defense.append({})
		snapshot.defense_orders = old_defense
	ProductionLifecycle.normalize_legacy(snapshot)
	var validation_error: String = SaveValidator.check(snapshot)
	if validation_error != "":
		return validation_error
	visual_memory = snapshot.get("visual_memory", {}).duplicate(true) if snapshot.get("visual_memory", {}) is Dictionary else {}
	rules = snapshot.rules
	map = snapshot.map
	ruins = snapshot.get("ruins",map.get("ruins",[])).duplicate(true)
	preload("res://scripts/battlefield_ruins.gd").register_trees(map)
	for index in range(ruins.size(), map.ruins.size()): ruins.append(map.ruins[index].duplicate(true))
	_refresh_ruin_spatial()
	_prepare_terrain_cache()
	_nav_initialized = false
	factions.assign(snapshot.factions)
	_resize_team_caches()
	match_options = snapshot.get("match_options", {"players":factions.size(), "vision_enabled":false}).duplicate(true)
	vision_enabled = bool(match_options.get("vision_enabled", false))
	team_vision = snapshot.get("team_vision", {"last_known":[]}).duplicate(true)
	money.assign(snapshot.money)
	time = float(snapshot.time)
	result = str(snapshot.get("result", ""))
	campaign_controller = null
	if str(map.get("mode", "")) == "campaign":
		campaign_controller = CampaignController.new()
		campaign_controller.from_dict(snapshot.campaign)
	entities = snapshot.entities
	statistics.restore(snapshot.get("match_statistics",{}),self)
	_ground_motion_spatial.clear()
	_designation_bonuses.clear()
	_building_entities.clear()
	_max_ground_radius = 1.0
	for e in entities.values():
		var info: Dictionary = data_for(e.spec)
		if e.kind == "unit" and str(info.get("domain", "ground")) == "ground":
			_max_ground_radius = maxf(_max_ground_radius, float(info.get("radius", 0.35)))
		_max_entity_extent = maxf(_max_entity_extent, float(info.get("size", 1)) * 0.5 if e.kind == "building" else float(info.get("radius", 0.35)))
		Transport.initialize(e)
		if e.kind == "unit":
			e.last_damage_time = float(e.get("last_damage_time", time))
			e.last_attack_time = float(e.get("last_attack_time", time))
			if bool(info.get("hero", false)):
				e.hand_strike = float(e.get("hand_strike", 0.0))
				e.hand_recover = float(e.get("hand_recover", 0.0))
				e.hand_target = int(e.get("hand_target", -1))
				e.hand_landing = e.get("hand_landing", e.pos)
				e.hand_force = bool(e.get("hand_force", false))
				e.hand_resolving = false
		e.radius = float(info.get("radius", 0.35))
		e.turret_alpha = float(e.get("turret_alpha", e.alpha))
		e.turret_target = int(e.get("turret_target", -1))
		e.can_crush = bool(info.get("crush", false))
		e.crushable = bool(info.get("crushable", false))
		_configure_crushing(e, info)
		if _is_air(e):
			e.ammo = int(e.get("ammo", info.ammo_capacity))
			e.home_airfield = int(e.get("home_airfield", -1))
			e.flight_state = str(e.get("flight_state", "airborne"))
			e.rearm_remaining = float(e.get("rearm_remaining", 0.0))
			e.flight_height = float(e.get("flight_height", info.flight_height))
			e.airborne = bool(e.get("airborne", true))
		if e.kind == "building":
			_building_entities.append(e)
	projectiles = snapshot.projectiles
	mines = snapshot.mines
	for mine in mines:
		mine.miner = int(mine.get("miner", -1))
		mine.amount = float(mine.get("amount", mine.capacity))
		mine.drill = int(mine.get("drill", -1))
	bridges = snapshot.bridges
	building_orders = snapshot.building_orders
	defense_orders = snapshot.get("defense_orders", [])
	if defense_orders.is_empty():
		defense_orders.resize(factions.size())
		for team in range(factions.size()): defense_orders[team] = {}
	# Prior saves prepaid the engineer's deployment before selecting its site.
	# Refund that reservation once when migrating to payment during field work.
	for team in range(factions.size()):
		var order: Dictionary = building_orders[team]
		if order.has("builder"):
			money[team] += float(order.cost)
			order.cost = 0.0
			order.remaining = 0.0
			order.progress = 0.0
			order.ready = true
	for e in entities.values():
		for command in e.commands:
			if command.kind == "deploy_outpost" and float(command.get("cost", 0.0)) > 0.0:
				money[int(e.team)] += float(command.cost)
				command.cost = 0.0
	_refresh_building_spatial()
	_next_id = int(snapshot.next_id)
	ai_enabled = bool(snapshot.get("ai_enabled", true))
	if snapshot.has("ai_state"): ai_state = snapshot.ai_state.duplicate(true)
	else: AIController.initialize(self)
	_ai_clock = float(snapshot.get("ai_clock", 0.0))
	_ai_attack_clock = float(snapshot.get("ai_attack_clock", 0.0))
	_low_power.resize(factions.size())
	_low_power.fill(false)
	if snapshot.has("low_power"): _low_power.assign(snapshot.low_power)
	notices.clear()
	events.clear()
	_damage.clear()
	_damage_voice_next.clear()
	_execute_buildings.clear()
	_crush_targets.clear()
	# Navigation is derived, but saved commands/cooldowns/projectiles are authoritative.
	var saved_paths: Dictionary = {}
	for e in entities.values():
		saved_paths[int(e.id)] = {"path": e.path.duplicate(), "goal": e.path_goal}
	_nav_dirty = true
	_nav_regions.clear()
	_in_step = false
	_rebuild_nav()
	for e in entities.values():
		e.path = saved_paths[int(e.id)].path
		e.path_goal = saved_paths[int(e.id)].goal
	_nav_regions.assign(snapshot.get("nav_regions", []))
	_nav_dirty = bool(snapshot.get("nav_dirty", false))
	# Saved yield corridors refer to this geometry epoch. The loaded world is
	# identical, so retain its epoch while rebuilding all physical query caches.
	_static_geometry_revision=int(snapshot.get("static_geometry_revision",_static_geometry_revision))
	_goal_standing_cache.clear()
	_planning_max_wait = float(snapshot.get("planning_max_wait", 0.0))
	_path_plans_remaining = PATH_SYNC_PLANS_PER_TICK if synchronous_path_tests else PATH_PLANS_PER_TICK
	_planning_deferred_ids.clear()
	_planning_queue.assign(snapshot.get("planning_queue", []))
	_navigation_command_until=snapshot.get("navigation_command_until",{}).duplicate()
	_player_navigation_ids.clear()
	_planning_requested_ids.clear()
	NavalOperations.initialize(self)
	_rebuild_spatial()
	TeamVision.refresh(self)
	# Legacy reservations are deliberately discarded; unit orders stay intact.
	for entity in entities.values():
		var legacy: bool=snapshot.has("group_navigation") or entity.has("traffic_active") or entity.commands.any(func(command):return command.has("formation"))
		if not legacy:continue
		for key in ["traffic_active","traffic_strict","traffic_precision","traffic_gate","traffic_rank","yield_step","yield_parked"]:entity.erase(key)
		entity.yield_goal=Vector2.INF
		entity.movement_retry_at=0.0
		entity.path.clear();entity.path_goal=Vector2.INF;entity.path_wait=0.0
		for command in entity.commands:
			command.erase("formation");command.erase("formation_goal")
	statistics.sample(self,true)
	return ""

func _publish_path_geometry() -> void:
	var before: int=Time.get_ticks_usec()
	var hard: Array=[]
	var vehicles: Array=[]
	for mine in mines:
		hard.append(Rect2(mine.pos - MINE_HALF, MINE_HALF * 2.0))
	for e in _building_entities:
		if float(e.hp)<=0 or RailNetwork.is_rail(data_for(e.spec)):continue
		var half:=Vector2.ONE*float(data_for(e.spec).size)*.5
		var rect:=Rect2(e.pos-half,half*2)
		if data_for(e.spec).get("role","")=="barricade":vehicles.append(rect)
		else:hard.append(rect)
	for raw_chunk in _ruin_geometry_dirty:
		var chunk: int = int(raw_chunk)
		var rectangles: Array[Rect2] = []
		var end: int = mini(ruins.size(), (chunk + 1) * RUIN_GEOMETRY_CHUNK_SIZE)
		for index in range(chunk * RUIN_GEOMETRY_CHUNK_SIZE, end):
			var ruin: Dictionary = ruins[index]
			if float(ruin.hp) > 0.0: rectangles.append(Rect2(ruin.pos - ruin.half, ruin.half * 2.0))
		_ruin_geometry_chunks[chunk] = {"revision": _path_revision + 1, "rectangles": rectangles}
	_ruin_geometry_dirty.clear()
	for bridge in bridges:
		if not bool(bridge.alive):hard.append(Rect2(bridge.bounds[0],bridge.bounds[1],bridge.bounds[2],bridge.bounds[3]))
	_path_revision+=1
	# Published chunk objects are immutable. Replacing a changed chunk preserves
	# every in-flight worker snapshot without copying the entire forest again.
	_path_geometry={"hard":hard,"vehicles":vehicles,"ruin_chunks":_ruin_geometry_chunks.duplicate()}
	_path_requests.clear();_planning_queue.clear()
	if _path_worker!=null and _path_worker.has_method("invalidate"):_path_worker.invalidate(_path_revision)
	navigation_stats.main_us+=Time.get_ticks_usec()-before

func _start_path_worker() -> void:
	if _path_worker!=null:_path_worker.close()
	_path_in_flight=0
	var ids: PackedInt64Array = _terrain_nav_ids
	var edges: PackedInt64Array = _terrain_nav_edges
	var heights:=PackedFloat32Array()
	var terrain := PackedByteArray()
	var original_land := PackedByteArray()
	heights.resize(_size*_size)
	terrain.resize(_size*_size)
	original_land.resize(_size*_size)
	for z in range(_size):
		for x in range(_size):
			heights[z*_size+x]=float(map.heights[z][x])
			terrain[z*_size+x]=int(map.terrain[z][x])
			original_land[z*_size+x]=1 if _original_land(Vector2(x+.5,z+.5)) else 0
	_path_worker=_create_path_worker()
	_path_worker.start({"size":_size,"ids":ids,"edges":edges,"heights":heights,"terrain":terrain,"land":original_land,"flat":_flat_safe,"flat_wide":_flat_wide_safe,"masks":_terrain_masks.duplicate(true),"extra_positions":_terrain_nav_extra_positions.duplicate(),"extra_cells":_terrain_nav_extra_cells.duplicate(true)})

func _cancel_path_request(id: int) -> void:
	_path_requests.erase(id)
	_planning_queue.erase(id)

func _background_path(start: Vector2, goal: Vector2, radius: float, id: int) -> Array:
	_planning_requested_ids[id]=true
	var job: Dictionary=_path_requests.get(id,{})
	var key: float=snappedf(radius,.01)
	var vehicle: bool=not _query_is_infantry(id)
	var pursuit: bool=entities.has(id) and bool(entities[id].get("pursuit_request",false))
	if not job.is_empty() and ((not pursuit and (job.goal.distance_to(goal)>.6 or (not responsive_navigation_enabled and job.start.distance_to(start)>1.2))) or job.radius!=key or bool(job.get("vehicle",true))!=vehicle or job.revision!=_path_revision):
		_cancel_path_request(id);job={}
	if not job.is_empty() and job.status=="ready":
		var path: Array=job.path
		_cancel_path_request(id)
		if entities.has(id):entities[id].planning_wait=0.0
		if responsive_navigation_enabled and not path.is_empty() and job.start.distance_squared_to(start) > .0225:
			path = ResponsiveNavigation.join_route(self, start, path, radius, id)
			if path.is_empty():
				# The moving start may have crossed into another corridor. Queue a
				# fresh snapshot without reporting this stale connector as no route.
				return _background_path(start, goal, radius, id)
		if not path.is_empty() and (path.back() as Vector2).distance_to(goal)>.05 and _segment_static(path.back(),goal,radius,id):path.append(goal)
		return path
	if job.is_empty():
		_path_token+=1
		_path_requests[id]={"id":id,"token":_path_token,"revision":_path_revision,"start":start,"goal":goal,"radius":key,"vehicle":vehicle,"start_height":_height(start),"goal_height":_height(goal),"status":"queued"}
		if not _planning_queue.has(id):_planning_queue.append(id)
	_plan_was_deferred=true
	_defer_planning(id)
	return []

func _collect_path_results() -> void:
	if _path_worker==null:return
	var before: int=Time.get_ticks_usec()
	for result in _path_worker.collect():
		_path_in_flight=maxi(0,_path_in_flight-1)
		navigation_stats.max_worker_us=maxi(int(navigation_stats.max_worker_us),int(result.worker_us))
		for key in result.get("worker_stats",{}):navigation_stats[key]=int(navigation_stats.get(key,0))+int(result.worker_stats[key])
		var job: Dictionary=_path_requests.get(int(result.id),{})
		if job.is_empty() or job.token!=result.token or result.revision!=_path_revision:
			navigation_stats.discarded+=1
			continue
		job.status="ready";job.path=result.path
		navigation_stats.completed+=1
	navigation_stats.main_us+=Time.get_ticks_usec()-before

func _submit_path_jobs() -> void:
	if _path_worker==null:return
	var before: int=Time.get_ticks_usec()
	navigation_stats.max_queued=maxi(int(navigation_stats.max_queued),_planning_queue.size())
	while _path_plans_remaining>0 and _path_in_flight<PATH_IN_FLIGHT and not _planning_queue.is_empty():
		if Time.get_ticks_usec()-before>=PATH_ADMIN_BUDGET_US:break
		var queue_index:int=_navigation_queue_index()
		var id: int=_planning_queue[queue_index]
		var priority:int=_navigation_priority(id)
		if priority<2 and _path_in_flight>=PATH_IN_FLIGHT-4:break
		var job: Dictionary=_path_requests.get(id,{})
		if job.is_empty() or not _planning_requested_ids.has(id):_planning_queue.remove_at(queue_index);continue
		var work: Dictionary=job.duplicate()
		work.geometry=_path_geometry
		work.priority=priority
		work.base_priority=2 if _human_navigation_owner(id) and float(_navigation_command_until.get(id,0.0))>time else 0
		if entities.has(id) and not entities[id].commands.is_empty():work.navigation_lane=int(entities[id].commands[0].get("navigation_lane",-1))
		if not _path_worker.submit(work):break
		job.status="running"
		_planning_queue.remove_at(queue_index);_path_in_flight+=1;_path_plans_remaining-=1
		if priority>=2:navigation_priority_grants+=1
		navigation_stats.submitted+=1
	navigation_stats.queued=_planning_queue.size()
	navigation_stats.in_flight=_path_in_flight
	navigation_stats.max_in_flight=maxi(int(navigation_stats.max_in_flight),_path_in_flight)
	navigation_stats.main_us+=Time.get_ticks_usec()-before

func _create_path_worker():
	return PATH_WORKER.new()

func rotate_build_order(team: int, quarter_turns: int = 1, channel: String = "auto") -> String:
	channel = _effective_construction_channel(team, channel)
	var order: Dictionary = order_for_team(team, channel)
	if order.is_empty(): return "当前没有待放置的建筑"
	order.rotation_quarters = posmod(BuildingOrientation.quarters(order)+quarter_turns,4)
	if RailNetwork.is_rail(data_for(str(order.spec))): order.rail_rotation = order.rotation_quarters
	return ""

func rotate_rail_order(team: int, quarter_turns: int = 1, channel: String = "auto") -> String:
	# Compatibility for the previous V shortcut and older tools.
	return rotate_build_order(team,quarter_turns,channel)
