extends RefCounted

## Per-team planners use only normal simulation commands and observed enemies.
const FactionAdapter = preload("res://scripts/ai_faction_adapter.gd")
const VERSION := "land_skirmish_v7_transport_priority"
const SETTINGS := {
	"easy":{"reaction":4.0,"wave":4,"attack_gap":44.0,"air_weight":0.15,"anti_cycle":5,"factory_cycle":6},
	"normal":{"reaction":2.0,"wave":6,"attack_gap":32.0,"air_weight":0.25,"anti_cycle":4,"factory_cycle":5},
	"hard":{"reaction":1.0,"wave":8,"attack_gap":24.0,"air_weight":0.35,"anti_cycle":3,"factory_cycle":4}
}

static func initialize(sim) -> void:
	sim.ai_state = []
	for team in range(sim.factions.size()):
		sim.ai_state.append({"reaction_clock":0.0,"attack_clock":0.0,"scout_clock":0.0,"naval_clock":0.0,"planner_version":VERSION,"decisions":0,"build_orders":0,"production_orders":0,"attack_waves":0,"scout_orders":0,"defense_orders":0,"production_counts":{}})

static func step(sim, delta: float) -> void:
	if not sim.ai_enabled: return
	for team in range(sim.factions.size()):
		var slot: Dictionary = sim.match_options.slots[team]
		if str(slot.get("control", "ai")) != "ai": continue
		if sim.independent_ai != null and not str(slot.get("ai_module", "")).is_empty(): continue
		var config: Dictionary = SETTINGS.get(str(slot.get("difficulty", "normal")), SETTINGS.normal)
		var state: Dictionary = sim.ai_state[team]
		state.reaction_clock += delta
		state.attack_clock += delta
		state.scout_clock += delta
		state.naval_clock += delta
		if float(state.reaction_clock) < float(config.reaction): continue
		state.reaction_clock = 0.0
		_plan(sim, team, config, state)

static func _plan(sim, team: int, config: Dictionary, state: Dictionary) -> void:
	var faction: String = sim.factions[team]
	state.planner_version = VERSION
	state.decisions = int(state.get("decisions", 0)) + 1
	var land_skirmish: bool = sim.campaign_controller == null and str(sim.map.get("mode", "")) != "islands"
	if land_skirmish:
		state.observed = _observed_enemies(sim, team)
		_resume_construction(sim, team)
		_manage_miners(sim, team, state)
	for channel in ["normal", "defense"]:
		var order: Dictionary = sim.order_for_team(team, channel)
		if not order.is_empty() and bool(order.get("ready", false)):
			if str(sim.data_for(order.spec).get("role", "")) == "shipyard": _place_shipyard(sim, team)
			elif land_skirmish: _place_land(sim, team, channel)
			else: sim._ai_place(team, channel)
	if str(sim.map.get("mode", "")) == "islands" and sim._has_role(team,"shipyard") and _naval_transport_count(sim,team)>0: _shore_outpost(sim, team, faction)
	if bool(state.get("independent_shared_economy", true)):
		_build(sim, team, faction)
		_produce(sim, team, faction, config)
	if land_skirmish: _clear_producer_doors(sim, team)
	if not bool(state.get("independent_shared_tactics", true)): return
	_defend(sim, team)
	if sim.campaign_controller != null: _hold_position(sim, team, sim.campaign_controller.ai_policy())
	if str(sim.map.get("mode", "")) == "islands":
		_naval_assault(sim, team, config, state)
	else:
		_land_attack(sim, team, config, state)
	if float(state.scout_clock) >= 28.0:
		state.scout_clock = 0.0
		_scout(sim, team, faction)
	if land_skirmish: _land_air_and_support(sim, team)

static func _build(sim, team: int, faction: String) -> void:
	if sim.campaign_controller == null and str(sim.map.get("mode", "")) != "islands":
		_build_land(sim, team, faction)
		return
	sim.ai_rebuild_base(team)
	if not sim.order_for_team(team,"normal").is_empty() or not sim._has_construction_base(team): return
	if sim.campaign_controller != null:
		_build_campaign(sim, team, faction, sim.campaign_controller.ai_policy())
		return
	var power: Vector2 = sim.power(team)
	var role: String = ""
	if not sim._has_role(team,"power") or power.x < power.y + 65.0: role="advanced_power" if faction=="sky" and sim._has_role(team,"tech") and sim.money[team]>=float(sim.data_for("sky_advanced_power").cost) else "power"
	elif faction == "rivet" and sim._role_count(team,"drill") < 1:
		sim.MiningDrills.ai_build(sim, team); return
	elif faction != "rivet" and not sim._has_role(team,"refinery"): role="refinery"
	elif not sim._has_role(team,"barracks"): role="barracks"
	elif not sim._has_role(team,"factory"): role="factory"
	elif str(sim.map.get("mode", "")) == "islands" and not sim._has_role(team,"shipyard"): role="shipyard"
	elif str(sim.map.get("mode", "")) == "islands" and _naval_transport_count(sim,team)<1: role=""
	elif sim.money[team] > 2200.0 and not sim._has_role(team,"command") and sim.rules.buildings.has(faction+"_command"): role="command"
	elif sim.money[team] > 2600.0 and not sim._has_role(team,"airfield"): role="airfield"
	elif faction != "rivet" and sim.money[team] > 2900.0 and sim._role_count(team,"refinery") < 2: role="refinery"
	elif faction == "rivet" and sim.money[team] > 1500 and sim._role_count(team,"drill") < 3:
		if sim.money[team] >= float(sim.data_for("rivet_drill").cost)+_first_factory_purchase_reserve(sim,team,faction): sim.MiningDrills.ai_build(sim, team)
		return
	elif sim.money[team] > 3300.0 and not sim._has_role(team,"tech"): role="tech"
	elif sim.money[team] > 1400 and sim._has_role(team,"factory") and not sim._has_role(team,"repair") and sim.entities.values().any(func(e):return e.team==team and e.kind=="unit" and sim.data_for(e.spec).get("domain","ground")=="ground" and sim.data_for(e.spec).get("armor_class","")=="armored" and e.hp<sim.max_hp(e)*.7): role="repair"
	# Count live and queued guards together. Reserve only their normal price:
	# industrial construction must not consume the last money for mine defense.
	var guard_reserve: float = 0.0
	if faction == "iron": guard_reserve = ceili(float(maxi(0, 2-sim._unit_spec_count(team,"iron_rifle")))/sim.squad_size("iron_rifle"))*sim.production_cost("iron_rifle")
	# Once industry is online, a second tower or another facility must leave
	# enough money for the first tank (or a replacement for a lost last miner).
	var industry_reserve: float = _first_factory_purchase_reserve(sim,team,faction)
	if not role.is_empty() and not sim.building_spec(team, role).is_empty():
		var spec: String = sim.building_spec(team, role)
		var reserve: float = guard_reserve if faction == "iron" and role == "factory" else industry_reserve
		if sim.money[team] >= float(sim.data_for(spec).cost)+reserve: sim.ai_build(team,spec)
	var tower_limit: int = 1 if faction == "iron" and not sim._has_role(team,"factory") else 2
	if sim.order_for_team(team,"defense").is_empty() and sim.money[team] > 900.0 and sim._role_count(team,"tower") < tower_limit and (str(sim.map.get("mode", "")) != "islands" or sim._has_role(team,"shipyard")):
		var tower: String=faction+"_tower"
		if sim._has_role(team,"factory") and sim.money[team]>float(sim.data_for(faction+"_advanced_tower").cost)+500: tower=faction+"_advanced_tower"
		if sim.rules.buildings.has(tower) and sim.money[team] >= float(sim.data_for(tower).cost)+industry_reserve: sim.ai_build(team,tower)

static func _first_factory_purchase_reserve(sim, team: int, faction: String) -> float:
	if sim.campaign_controller != null or not sim._has_role(team,"factory"): return 0.0
	if faction != "rivet" and sim._unit_spec_count(team,faction+"_harvester") < 1:
		return float(sim.data_for(faction+"_harvester").cost)
	if sim._unit_spec_count(team,faction+"_tank") > 0: return 0.0
	return float(sim.data_for(faction+"_tank").cost)

static func _build_campaign(sim, team: int, faction: String, policy: Dictionary) -> void:
	var allowed: Array = policy.get("allowed_roles", [])
	var caps: Dictionary = policy.get("building_caps", {})
	# A single paid industrial chain supports a bounded defending army. Keep
	# the ordinary purchase, queue and placement code for every facility.
	for role: String in ["power", "refinery", "barracks", "factory"]:
		if faction == "rivet" and role == "refinery":
			if sim._role_count(team,"drill") < 1: sim.MiningDrills.ai_build(sim, team)
			continue
		if not role in allowed or sim._role_count(team, role) >= int(caps.get(role, 1)): continue
		var spec: String = sim.building_spec(team, role)
		if sim.rules.buildings.has(spec): sim.ai_build(team, spec)
		break
	if "tower" in allowed and sim.order_for_team(team,"defense").is_empty() and sim._role_count(team,"tower") < int(caps.get("tower", 1)):
		var tower: String = faction + "_tower"
		if sim.rules.buildings.has(tower): sim.ai_build(team, tower)

static func _place_shipyard(sim, team: int) -> void:
	var order: Dictionary = sim.order_for_team(team,"normal")
	if order.is_empty(): return
	var original_turns: int = sim.BuildingOrientation.quarters(order)
	var harbors: Array = sim.map.get("harbors", []).duplicate()
	harbors.sort_custom(func(a,b):return int(a.get("role")!="home")<int(b.get("role")!="home"))
	for harbor in harbors:
		if int(harbor.get("team", -1)) != team: continue
		# Start inside the owned harbor's water, rather than searching from a
		# mixed shoreline footprint. Placement still applies normal authority.
		var center: Vector2 = harbor.get("water_pos", Vector2.INF)
		if not center.is_finite(): center = harbor.get("shore_pos", harbor.get("land_pos", Vector2.INF))
		for ring in range(21):
			var radius: float=float(ring)*0.9
			var steps: int=1 if ring==0 else 24
			for index in range(steps):
				var point: Vector2=sim.snap_build_position(team,center+Vector2.from_angle(TAU*float(index)/float(steps))*radius,"normal")
				for turns: int in range(4):
					order.rotation_quarters = turns
					if sim.placement_error(team,point,"normal").is_empty() and sim.place_building(team,point,"normal").is_empty(): return
	order.rotation_quarters = original_turns
	sim._ai_place(team,"normal")

static func _has_shore_outpost(sim, team: int) -> bool:
	for harbor in sim.map.get("harbors", []):
		if int(harbor.get("team",-1))!=team or harbor.get("role")!="home":continue
		for e in sim._building_entities:
			if int(e.team)==team and sim.data_for(e.spec).get("role","")==("hq" if bool(sim.data_for(sim.factions[team]+"_hq").get("rebuildable", false)) else "barracks" if sim.rules.factions.get(sim.factions[team], {}).get("building_method", "") == "engineer" else "outpost") and float(e.construct_remaining)<=0.0 and (e.pos as Vector2).distance_to(harbor.shore_pos)<13.0:return true
	return false

static func _shore_outpost(sim, team: int, faction: String) -> void:
	if _has_shore_outpost(sim,team) or not sim.order_for_team(team,"normal").is_empty() or not sim._has_role(team,"factory"):return
	var outpost_spec:String = sim.building_spec(team, "barracks") if sim.rules.factions.get(faction, {}).get("building_method", "") == "engineer" else faction+"_outpost"
	if not sim.rules.buildings.has(outpost_spec):return
	for e in sim.entities.values():
		if int(e.team)!=team:continue
		if e.kind=="building" and e.has("construction") and str(e.spec)==outpost_spec:return
		if e.kind=="unit" and not e.commands.is_empty() and e.commands[0].kind in ["deploy_outpost","resume_outpost"]:return
	var builder:int=-1
	for e in sim.entities.values():
		if int(e.team)==team and e.kind=="unit" and sim.data_for(e.spec).get("art","")=="engineer" and e.commands.is_empty() and not sim.Transport.is_loaded(e):builder=int(e.id);break
	if builder<0 or not sim.availability(team,outpost_spec,builder).is_empty():return
	for harbor in sim.map.get("harbors", []):
		if int(harbor.get("team",-1))!=team or harbor.get("role")!="home":continue
		var base:Vector2=harbor.get("land_pos",Vector2.INF)
		for ring in range(10):
			var steps:int=1 if ring==0 else 16
			for index in range(steps):
				var candidate:Vector2=base+Vector2.from_angle(TAU*float(index)/float(steps))*float(ring)
				var half:float=float(sim.data_for(outpost_spec).size)*0.5
				candidate=Vector2(roundf(candidate.x-half)+half,roundf(candidate.y-half)+half)
				if not sim._building_site_error(team,sim.data_for(outpost_spec),candidate,builder).is_empty():continue
				if sim.build(team,outpost_spec,builder).is_empty():sim.place_building(team,candidate,"normal")
				return

static func _naval_transport_spec(info:Dictionary)->bool:
	return str(info.get("domain","ground"))=="naval" and int(info.get("transport_capacity",0))>0

static func _naval_transport_count(sim,team:int)->int:
	var count:int=0
	for spec:String in sim.rules.units:
		var info:Dictionary=sim.data_for(spec)
		if info.faction==sim.factions[team] and _naval_transport_spec(info):count+=sim._unit_spec_count(team,spec)
	return count

static func _naval_transport_price(sim,team:int)->float:
	var result:float=INF
	for info:Dictionary in sim.rules.units.values():
		if info.faction==sim.factions[team] and _naval_transport_spec(info) and not bool(info.get("roster_hidden",false)):result=minf(result,float(info.cost))
	return result if is_finite(result) else 0.0

static func _naval_choice(sim,team:int,faction:String,building:Dictionary,transport_count:int)->String:
	# All options pass the same paid production/technology gate as human orders.
	# Older saved rules naturally retain their original available ship catalog.
	if transport_count<1:
		for role:String in ["hovercraft","ship_transport"]:
			var candidate:String=faction+"_"+role
			if sim.rules.units.has(candidate) and sim.availability(team,candidate,-1,int(building.id)).is_empty():return candidate
		return ""
	var fleet:Array[String]=["ship_frigate","ship_aa","submarine","amphibious","support_ship","carrier","hovercraft","ship_signature"]
	var offset:int=int(sim.time/12.0)%fleet.size()
	for n in range(fleet.size()):
		var role:String=fleet[(offset+n)%fleet.size()]
		if role=="hovercraft" and transport_count>=2:continue
		var candidate:String=faction+"_"+role
		if sim.rules.units.has(candidate) and sim.availability(team,candidate,-1,int(building.id)).is_empty():return candidate
	return ""

static func _produce(sim, team: int, faction: String, config: Dictionary) -> void:
	if sim.campaign_controller == null and str(sim.map.get("mode", "")) != "islands":
		_produce_land(sim, team, faction)
		return
	var policy: Dictionary = sim.campaign_controller.ai_policy() if sim.campaign_controller != null else {}
	var campaign: bool = sim.campaign_controller != null
	var army_cap: int = int(policy.get("army_cap", 0))
	var army_count: int = 0
	if army_cap > 0:
		for e in sim.entities.values():
			if int(e.team) != team or float(e.hp) <= 0.0: continue
			if e.kind == "unit" and not str(sim.data_for(e.spec).get("weapon", "")).is_empty(): army_count += 1
			elif e.kind == "building":
				for order in e.queue:
					if not str(sim.data_for(str(order.spec)).get("weapon", "")).is_empty(): army_count += 1
	var harvesters: int = sim._unit_spec_count(team,faction+"_harvester")
	var transport_count: int = _naval_transport_count(sim,team)
	var reserve: float=0.0
	if not sim._has_role(team,"factory"):reserve=float(sim.data_for(faction+"_factory").cost)
	elif str(sim.map.get("mode", ""))=="islands" and not sim._has_role(team,"shipyard"):
		reserve=float(sim.data_for(faction+"_shipyard").cost)
	elif str(sim.map.get("mode", ""))=="islands" and transport_count<1:reserve=_naval_transport_price(sim,team)
	var infrastructure_reserve: float = reserve
	var tank_spec: String = faction + "_tank"
	var needs_tank: bool = not campaign and sim._has_role(team, "factory") and sim._unit_spec_count(team, tank_spec) < 1
	if needs_tank: reserve = maxf(reserve, float(sim.data_for(tank_spec).cost))
	if not campaign and faction != "rivet" and sim._has_role(team,"factory") and harvesters < 1:
		reserve = maxf(reserve,float(sim.data_for(faction+"_harvester").cost))
	var rebuilding_base: bool = not sim._has_construction_base(team) and bool(sim.data_for(faction+"_hq").get("rebuildable", false))
	if rebuilding_base:
		reserve = maxf(reserve, float(sim.data_for(faction+"_hq").cost))
	for building in sim._building_entities:
		if int(building.team) != team or float(building.hp) <= 0.0 or float(building.construct_remaining) > 0.0 or building.queue.size() >= 2: continue
		var role: String = str(sim.data_for(building.spec).get("role", ""))
		var choice: String = ""
		if sim.TechAvailability.producer_matches(sim, building, "barracks"): role = "barracks"
		match role:
			"factory":
				if faction != "rivet" and harvesters < 1: choice=faction+"_harvester"
				elif needs_tank: choice = tank_spec
				elif faction != "rivet" and harvesters < maxi(2,sim._role_count(team,"refinery")): choice=faction+"_harvester"
				elif not campaign:
					var cycle: int=int(sim.time/8.0)%int(config.factory_cycle)
					choice=faction+("_scout" if cycle==0 else ("_aa" if cycle==1 else ("_artillery" if cycle==2 and int(config.factory_cycle)==4 and sim.rules.units.has(faction+"_artillery") and sim._requirements(team,sim.data_for(faction+"_artillery")).is_empty() else "_tank")))
					if str(sim.map.get("mode",""))=="islands":
						var amphibious_choice:String=faction+("_hovercraft" if cycle==2 and transport_count<2 else "_amphibious")
						if cycle in [0,2,3] and sim.rules.units.has(amphibious_choice) and not bool(sim.data_for(amphibious_choice).get("roster_hidden",false)):choice=amphibious_choice
			"barracks":
				if faction == "iron" and not campaign and sim._unit_spec_count(team,"iron_rifle") < 2:
					choice = "iron_rifle"
				else:
					# _unit_spec_count includes production queues, so one pending
					# engineer already fulfills the startup builder requirement.
					choice=faction+("_engineer" if sim._unit_spec_count(team,faction+"_engineer")<1 else ("_rifle" if campaign else ("_anti" if int(sim.time/6.0)%int(config.anti_cycle)==0 else "_rifle")))
			"airfield":
				var strike:String=faction+("_attacker" if sim.rules.units.has(faction+"_attacker") else "_bomber")
				choice=strike if float(int(sim.time/8.0)%10)/10.0<float(config.air_weight) and sim.rules.units.has(strike) else faction+"_fighter"
			"shipyard":
				choice=_naval_choice(sim,team,faction,building,transport_count)
		if faction == "iron" and role == "factory" and not needs_tank and not choice.ends_with("_harvester") and sim._has_role(team, "tech") and int(sim.time / 8.0) % 5 == 3:
			choice = "iron_train"
		if not choice.is_empty() and sim.rules.units.has(choice):
			if army_cap > 0 and army_count >= army_cap and not str(sim.data_for(choice).get("weapon", "")).is_empty(): continue
			var startup_guard: bool = faction == "iron" and not campaign and not sim._has_role(team,"factory") and choice == "iron_rifle" and sim._unit_spec_count(team,choice) < 2
			var startup_engineer: bool = choice.ends_with("_engineer") and sim._unit_spec_count(team,choice)<1 and (campaign or not sim._has_role(team,"factory"))
			var essential: bool=startup_guard or (choice.ends_with("_harvester") and harvesters<1) or startup_engineer or (transport_count<1 and _naval_transport_spec(sim.data_for(choice)))
			var purchase_reserve: float = 0.0 if needs_tank and choice == tank_spec and not rebuilding_base else reserve
			if (not essential or rebuilding_base) and sim.money[team]<purchase_reserve+sim.production_cost(choice):continue
			# Railway connection is a real paid purchase. Never start it for an
			# unaffordable unit or let the train cycle replace the first tank.
			if not sim.availability(team,choice,-1,int(building.id)).is_empty(): continue
			if choice.ends_with("_harvester") and harvesters < 1 and sim.RailNetwork.rail_only(sim.data_for(choice)):
				# Pay for recovery before extending its route. Spending the last
				# miner's price on rails first can strand an economy at zero income.
				if sim.produce(int(building.id),choice).is_empty():
					harvesters += 1
					reserve = maxf(infrastructure_reserve,float(sim.data_for(tank_spec).cost)) if needs_tank else infrastructure_reserve
					building.ai_economy_rail_wait = true
				continue
			if sim.RailNetwork.rail_only(sim.data_for(choice)) and not sim._rail_network.ai_connect_factory(sim, building):
				choice = faction + "_tank" if role == "factory" else ""
			if choice.is_empty() or not sim.availability(team,choice,-1,int(building.id)).is_empty(): continue
			if sim.produce(int(building.id),choice).is_empty():
				if _naval_transport_spec(sim.data_for(choice)):transport_count+=1
				if choice.ends_with("_harvester"):
					harvesters += 1
					reserve = maxf(infrastructure_reserve,float(sim.data_for(tank_spec).cost)) if needs_tank else infrastructure_reserve
				if choice == tank_spec and needs_tank:
					needs_tank = false
					reserve = infrastructure_reserve
				if not str(sim.data_for(choice).get("weapon", "")).is_empty(): army_count += 1
	# The replacement miner is already paid; its remaining route may wait for
	# affordable real track. First-tank production above always gets first use
	# of this reaction's money before these recovery connections are attempted.
	for building: Dictionary in sim._building_entities:
		if int(building.team) != team or not bool(building.get("ai_economy_rail_wait",false)): continue
		if sim._unit_spec_count(team,faction+"_harvester") < 1 or sim._rail_network.ai_connect_factory(sim,building): building.erase("ai_economy_rail_wait")

static func _defend(sim, team: int) -> void:
	if sim.campaign_controller == null and str(sim.map.get("mode", "")) != "islands":
		_defend_land_assets(sim, team)
		return
	var home: Vector2 = sim._team_start(team)
	var threat: int = -1
	var best: float = 24.0 * 24.0
	for e in sim.entities.values():
		if int(e.team) == team or e.kind != "unit" or not sim.entity_visible_to(team,int(e.id)): continue
		var distance: float = (e.pos as Vector2).distance_squared_to(home)
		if distance < best: best=distance; threat=int(e.id)
	if threat < 0: return
	for e in sim.entities.values():
		if int(e.team) != team or e.kind != "unit" or sim.Transport.is_loaded(e) or str(sim.data_for(e.spec).get("weapon", "")).is_empty(): continue
		if sim.campaign_controller == null and str(sim.map.get("mode", "")) != "islands" and str(sim.data_for(e.spec).get("art", "")) == "engineer": continue
		if not sim._weapon_can_target(e,threat): continue
		if (e.pos as Vector2).distance_to(home) > 26.0: continue
		if e.commands.is_empty() or str(e.commands[0].get("kind", "")) != "attack" or int(e.commands[0].get("target", -1)) != threat:
			sim.issue([int(e.id)],"attack",sim.entities[threat].pos,threat)
			sim.ai_state[team].defense_orders = int(sim.ai_state[team].get("defense_orders", 0)) + 1

static func _hold_position(sim, team: int, policy: Dictionary) -> void:
	if bool(policy.get("attack_enabled", false)): return
	var anchor: Variant = policy.get("hold_position", Vector2.INF)
	if not anchor is Vector2 or not (anchor as Vector2).is_finite(): return
	var rank: int = 0
	for e in sim.entities.values():
		if int(e.team) != team or e.kind != "unit" or float(e.hp) <= 0.0 or not e.commands.is_empty() or sim.Transport.is_loaded(e): continue
		var info: Dictionary = sim.data_for(str(e.spec))
		if str(info.get("weapon", "")).is_empty() or str(info.get("domain", "ground")) != "ground": continue
		var destination: Vector2 = anchor + Vector2(float(rank % 3) * 2.5, float(rank / 3) * 2.5)
		rank += 1
		if (e.pos as Vector2).distance_to(destination) > 4.0: sim.issue([int(e.id)], "move", destination)

static func _land_attack(sim, team: int, config: Dictionary, state: Dictionary) -> void:
	if sim.campaign_controller == null:
		_skirmish_attack(sim, team, config, state)
		return
	var policy: Dictionary = sim.campaign_controller.ai_policy() if sim.campaign_controller != null else {}
	if not bool(policy.get("attack_enabled", true)): return
	if policy.has("wave_limit") and int(state.get("campaign_waves", 0)) >= int(policy.wave_limit): return
	if float(state.attack_clock) < float(config.attack_gap): return
	var troops: Array=[]
	for e in sim.entities.values():
		if int(e.team) != team or e.kind != "unit" or sim.Transport.is_loaded(e): continue
		var spec: Dictionary=sim.data_for(e.spec)
		if str(spec.get("weapon", "")).is_empty() or str(spec.get("domain", "ground")) != "ground": continue
		if e.commands.is_empty() or e.commands[0].kind in ["move","attack_move","patrol"]: troops.append(int(e.id))
	var wave: int = mini(int(config.wave), int(policy.get("wave_cap", config.wave)))
	if troops.size() < wave: return
	var goal: Vector2=policy.get("attack_target", Vector2.INF)
	if not goal.is_finite(): goal = _objective(sim,team)
	if not goal.is_finite(): return
	sim.issue(troops.slice(0, wave),"attack_move",goal)
	if policy.has("wave_limit"): state.campaign_waves = int(state.get("campaign_waves", 0)) + 1
	state.attack_clock=0.0

static func _objective(sim, team: int) -> Vector2:
	var home: Vector2=sim._team_start(team)
	var best: float=INF
	var target: Vector2=Vector2.INF
	for e in sim.entities.values():
		if int(e.team)==team or not sim._is_victory_building(e) or not sim.entity_visible_to(team,int(e.id)): continue
		var distance:float=home.distance_squared_to(e.pos)
		if distance<best:best=distance;target=e.pos
	if target.is_finite(): return target
	for record in sim.team_vision.get("last_known", [])[team].values():
		if str(record.get("kind", ""))!="building": continue
		# Remembered rails and passive obstacles cannot keep a base alive and
		# do not become automatic combat targets for an attack-move order.
		if str(sim.data_for(str(record.get("spec", ""))).get("role", "")) in ["rail","rail_junction","wall","barricade"]: continue
		var distance:float=home.distance_squared_to(record.pos)
		if distance<best:best=distance;target=record.pos
	if target.is_finite(): return target
	# Spawn regions are public match geography, never a live enemy entity lookup.
	for other in range(sim.factions.size()):
		if other==team or other>=sim.map.get("starts",[]).size(): continue
		var start:Vector2=sim._vec(sim.map.starts[other])
		var distance:float=home.distance_squared_to(start)
		if distance<best:best=distance;target=start
	return target

static func _scout(sim, team: int, faction: String) -> void:
	var scout: String=faction+"_scout"
	for e in sim.entities.values():
		if int(e.team)!=team or e.spec!=scout or not e.commands.is_empty(): continue
		var destination:Vector2=_objective(sim,team)
		if destination.is_finite():
			sim.issue([int(e.id)],"move",destination)
			sim.ai_state[team].scout_orders = int(sim.ai_state[team].get("scout_orders", 0)) + 1
		return

static func _naval_assault(sim, team: int, config: Dictionary, state: Dictionary) -> void:
	var enemy_team: int=-1
	var best:float=INF
	for other in range(sim.factions.size()):
		if other==team:continue
		if other >= sim.map.get("starts", []).size(): continue
		var distance:float=sim._team_start(team).distance_squared_to(sim._vec(sim.map.starts[other]))
		if distance<best:best=distance;enemy_team=other
	if enemy_team<0:return
	var beach:Dictionary={}
	for entry in sim.map.get("landing_beaches", []):
		if int(entry.get("team",-1))==enemy_team:beach=entry;break
	if beach.is_empty():return
	var land:Vector2=beach.get("land_pos",Vector2.INF)
	var water:Vector2=beach.get("water_pos",Vector2.INF)
	if not land.is_finite() or not water.is_finite():return
	var transports:Array=[]
	var infantry:Array=[]
	var escorts:Array=[]
	var home:Vector2=sim._team_start(team)
	for e in sim.entities.values():
		if int(e.team)!=team or e.kind!="unit" or float(e.hp)<=0.0:continue
		var spec:Dictionary=sim.data_for(e.spec)
		if str(spec.get("domain","ground"))=="naval":
			if int(spec.get("transport_capacity",0))>0:transports.append(int(e.id))
			elif not str(spec.get("weapon","")).is_empty():escorts.append(int(e.id))
		elif str(spec.get("armor_class",""))=="infantry" and not sim.Transport.is_loaded(e):
			if (e.pos as Vector2).distance_to(land)<24.0 and (e.pos as Vector2).distance_to(home)>28.0:
				if e.commands.is_empty():sim.issue([int(e.id)],"attack_move",_objective(sim,team))
			elif (e.pos as Vector2).distance_to(home)<27.0:infantry.append(int(e.id))
	for ship_id in transports:
		var ship:Dictionary=sim.entities[ship_id]
		if ship.get("passengers",[]).size()<mini(int(config.wave),int(sim.data_for(ship.spec).get("transport_capacity",0))):
			for soldier_id in infantry:
				if sim.entities[soldier_id].commands.is_empty() and sim.board_error(soldier_id,ship_id).is_empty():
					sim.issue([soldier_id],"board",ship.pos,ship_id)
					if ship.get("passengers",[]).size()+1>=int(config.wave):break
		if ship.get("passengers",[]).size()>=mini(2,int(config.wave)) and (ship.commands.is_empty() or ship.commands[0].kind!="unload_move"):
			sim.issue([ship_id],"unload_move",land)
			for escort_id in escorts:
				if sim.entities[escort_id].commands.is_empty():
					var amphibious:bool=bool(sim.data_for(sim.entities[escort_id].spec).get("amphibious",false))
					sim.issue([escort_id],"attack_move",_objective(sim,team) if amphibious else water)

static func _profile(sim, team: int) -> Dictionary:
	var result: Dictionary = FactionAdapter.profile(sim.factions[team], str(sim.match_options.slots[team].get("ai_style", "balanced")))
	result.merge(sim.ai_state[team].get("independent_profile", {}), true)
	return result

static func _affordable_defender(sim, team: int, producer: Dictionary, observed: Dictionary) -> String:
	var candidates: Array = []
	for spec: String in sim.rules.units:
		var info: Dictionary = sim.data_for(spec)
		if str(info.get("faction", "")) != sim.factions[team] or str(info.get("producer", "")) != "barracks" or str(info.get("art", "")) == "engineer" or str(info.get("weapon", "")).is_empty(): continue
		if not sim.availability(team, spec, -1, int(producer.id)).is_empty(): continue
		if sim.money[team] < sim.production_cost(spec) + _construction_liability(sim, team): continue
		var targets: Array = sim.rules.weapons.get(str(info.weapon), {}).get("targets", [])
		if "ground" not in targets and int(observed.get("air", 0)) == 0: continue
		candidates.append({"spec":spec,"cost":sim.production_cost(spec)})
	candidates.sort_custom(func(a, b): return float(a.cost) < float(b.cost))
	return str(candidates[0].spec) if not candidates.is_empty() else ""

static func _air_purchase_goal(sim, team: int) -> String:
	if not sim._has_role(team, "airfield") or _roster_count(sim, team, "air") > 0 or _roster_count(sim, team, "infantry") + _roster_count(sim, team, "vehicle") < 6 or _home_under_pressure(sim, team): return ""
	for suffix: String in _profile(sim, team).air:
		var spec: String = sim.factions[team] + "_" + suffix
		if not sim.rules.units.has(spec) or not sim._requirements(team, sim.data_for(spec)).is_empty(): continue
		for field: Dictionary in sim._building_entities:
			if int(field.team) != team or sim.data_for(field.spec).get("role", "") != "airfield": continue
			var reason: String = sim.availability(team,spec,-1,int(field.id))
			if reason.is_empty() or reason == "资金不足": return spec
	return ""

static func _defend_land_assets(sim, team: int) -> void:
	var home: Vector2 = sim._team_start(team)
	var threat: Dictionary = {}
	var best: float = INF
	for enemy: Dictionary in sim.entities.values():
		if int(enemy.team) == team or enemy.kind != "unit" or float(enemy.hp) <= 0.0 or not sim.entity_visible_to(team, int(enemy.id)) or str(sim.data_for(enemy.spec).get("weapon", "")).is_empty(): continue
		var distance: float = (enemy.pos as Vector2).distance_to(home)
		var near_asset: bool = distance < 38.0
		var priority: float = distance
		var enemy_weapon: Dictionary = sim.weapon_for(enemy,str(sim.data_for(enemy.spec).get("weapon","")))
		if "ground" in enemy_weapon.get("targets",[]):
			for miner: Dictionary in sim.entities.values():
				if int(miner.team) != team or str(sim.data_for(miner.spec).get("art","")) != "harvester": continue
				if (miner.pos as Vector2).distance_to(enemy.pos) < float(enemy_weapon.get("range",0.0)) + 6.0:
					near_asset = true
					priority -= 70.0 + 20.0 * (1.0-float(miner.hp)/maxf(1.0,sim.max_hp(miner)))
		for building: Dictionary in sim._building_entities:
			if int(building.team) == team and sim.data_for(building.spec).get("role", "") in ["refinery","drill","factory","hq"] and (building.pos as Vector2).distance_to(enemy.pos) < 19.0: near_asset = true
		if near_asset and priority < best: best = priority; threat = enemy
	if threat.is_empty(): return
	for e: Dictionary in sim.entities.values():
		if int(e.team) != team or e.kind != "unit" or sim.Transport.is_loaded(e) or bool(e.get("emerging", false)) or str(sim.data_for(e.spec).get("art", "")) == "engineer": continue
		if (e.pos as Vector2).distance_to(threat.pos) > 36.0 or not sim._weapon_can_target(e, int(threat.id)): continue
		if sim.time < float(e.get("ai_traffic_until",0.0)) and not _engaged_in_range(sim,e): continue
		if not e.commands.is_empty() and str(e.commands[0].kind) == "attack" and int(e.commands[0].target) == int(threat.id): continue
		sim.issue([int(e.id)], "attack", threat.pos, int(threat.id))
		sim.ai_state[team].defense_orders = int(sim.ai_state[team].get("defense_orders", 0)) + 1

static func _miner_goal(sim, miner: Dictionary) -> Vector2:
	var job: Dictionary = miner.get("refinery_docking", {})
	if not job.is_empty():
		var clearance: Vector2 = job.get("clearance", Vector2.INF)
		return clearance if clearance.is_finite() else job.get("outside", miner.pos)
	if bool(miner.get("emerging", false)): return miner.get("production_exit", miner.pos)
	var path: Array = miner.get("path", [])
	return path[0] if not path.is_empty() else miner.get("path_goal", miner.pos)

static func _unblock_unit(sim, mover: Dictionary, state: Dictionary) -> int:
	var goal: Vector2 = _miner_goal(sim, mover)
	if not goal.is_finite() or goal.distance_to(mover.pos) < .1: goal = mover.pos + Vector2.DOWN * 3.0
	var forward: Vector2 = (goal - mover.pos).normalized()
	var count: int = 0
	for other: Dictionary in sim.entities.values():
		if int(other.team) != int(mover.team) or int(other.id) == int(mover.id) or other.kind != "unit" or sim.Transport.is_loaded(other) or sim._is_air(other) or sim._is_naval(other) or bool(other.get("emerging", false)) or not other.get("refinery_docking", {}).is_empty(): continue
		if sim.RailNetwork.rail_only(sim.data_for(other.spec)): continue
		if sim.time < float(other.get("ai_traffic_until",0.0)): continue
		if not other.commands.is_empty() and str(other.commands[0].kind) not in ["move","attack_move","patrol"]: continue
		if _engaged_in_range(sim,other): continue
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(other.pos, mover.pos, goal)
		if closest.distance_to(other.pos) > sim._radius(mover) + sim._radius(other) + .8 or (other.pos as Vector2).distance_to(mover.pos) > 8.0: continue
		if str(sim.data_for(other.spec).get("art", "")) == "harvester" and str(other.state) not in ["waiting","waiting_rail","idle","unreachable"]: continue
		var side: float = -1.0 if ((other.pos as Vector2) - mover.pos).dot(forward.orthogonal()) < 0.0 else 1.0
		var destination: Vector2 = sim._near_stand(mover.pos + forward.orthogonal() * side * 5.0 + forward * 2.0, sim._radius(other), int(other.id), 3.0, false)
		if not destination.is_finite() or Geometry2D.get_closest_point_to_segment(destination,mover.pos,goal).distance_to(destination) < 3.0: continue
		sim.issue([int(other.id)], "move", destination)
		other.ai_traffic_until = float(sim.time) + 12.0
		if str(sim.data_for(other.spec).get("art", "")) == "harvester":
			var mine: int = _safe_mine(sim, other, -1)
			if mine >= 0: sim.issue([int(other.id)], "harvest", sim.mines[mine].pos, mine, true)
		count += 1
		if count >= 3: break
	if count > 0: state.traffic_yield_orders = int(state.get("traffic_yield_orders", 0)) + count
	return count

static func _engaged_in_range(sim, unit: Dictionary) -> bool:
	var target: int = int(unit.get("auto_target",-1))
	if target < 0 or not sim._weapon_can_target(unit,target): return false
	var weapon: Dictionary = sim.weapon_for(unit,str(sim.data_for(unit.spec).get("weapon","")))
	return (unit.pos as Vector2).distance_to(sim._target_position(target)) <= float(weapon.get("range",0.0)) + 4.0

static func _miner_visible_threats(sim, team: int) -> Array:
	var threats: Array = []
	for enemy: Dictionary in sim.entities.values():
		if int(enemy.team) == team or float(enemy.hp) <= 0.0 or not sim.entity_visible_to(team,int(enemy.id)): continue
		var weapon: Dictionary = sim.weapon_for(enemy,str(sim.data_for(enemy.spec).get("weapon","")))
		if "ground" in weapon.get("targets",[]): threats.append({"pos":enemy.pos,"range":float(weapon.get("range",0.0))})
	return threats

static func _threat_clearance(point: Vector2, threats: Array) -> float:
	var result: float = 100.0
	for threat: Dictionary in threats: result = minf(result,point.distance_to(threat.pos)-float(threat.range)-6.0)
	return result

static func _safe_retreat_path(sim, miner: Dictionary, goal: Vector2, threats: Array) -> Array:
	var path: Array = sim._rail_network.traversable_path(sim,miner,miner.pos,goal) if sim.RailNetwork.rail_only(sim.data_for(miner.spec)) else sim._path_between(miner.pos,goal,sim._radius(miner),int(miner.id))
	if path.is_empty(): return []
	var floor: float = minf(_threat_clearance(miner.pos,threats)-1.0,-1.0)
	for point: Vector2 in path:
		if _threat_clearance(point,threats) < floor: return []
	return path

static func _miner_retreat_goal(sim, miner: Dictionary, threats: Array) -> Dictionary:
	var team: int = int(miner.team)
	var candidates: Array = []
	for refinery: Dictionary in sim._building_entities:
		if int(refinery.team) == team and sim.data_for(refinery.spec).get("role","") == "refinery" and float(refinery.construct_remaining) <= 0.0:
			var entrance: Vector2 = sim.RefineryDocking.entrance(sim,miner,refinery)
			if entrance.is_finite(): candidates.append({"pos":entrance,"refinery":int(refinery.id)})
	if sim.RailNetwork.rail_only(sim.data_for(miner.spec)):
		for cell: Vector2i in _rail_component(sim,miner,miner.pos):
			var point: Vector2 = sim.RailNetwork.center(cell)
			if point.distance_to(miner.pos) <= 18.0: candidates.append({"pos":point,"refinery":-1})
	else:
		var home: Vector2 = sim._team_start(team)
		for offset: Vector2 in [Vector2(0,10),Vector2(0,-10),Vector2(10,0),Vector2(-10,0)]:
			var point: Vector2 = sim._near_stand(home+offset,sim._radius(miner),int(miner.id),4.0,false)
			if point.is_finite(): candidates.append({"pos":point,"refinery":-1})
	var best: float = -INF
	var answer: Dictionary = {}
	var current_clearance: float = _threat_clearance(miner.pos,threats)
	for candidate: Dictionary in candidates:
		var clearance: float = _threat_clearance(candidate.pos,threats)
		if not threats.is_empty() and clearance < current_clearance+2.0: continue
		var path: Array = _safe_retreat_path(sim,miner,candidate.pos,threats)
		if path.is_empty(): continue
		var score: float = minf(25.0,clearance) - float(path.size())*.2
		if int(candidate.refinery) >= 0 and float(miner.cargo) > 0.0: score += 12.0
		if score > best: best = score; answer = candidate
	return answer

static func _manage_miner_safety(sim, miner: Dictionary, state: Dictionary) -> bool:
	if bool(miner.get("emerging",false)) or not miner.get("refinery_docking",{}).is_empty(): return false
	var records: Dictionary = state.get("miner_safety",{})
	state.miner_safety = records
	var id: int = int(miner.id)
	var safety: Dictionary = records.get(id,{})
	var threats: Array = _miner_visible_threats(sim,int(miner.team))
	var mine: int = int(safety.get("resume_mine",miner.get("harvest_mine",-1)))
	var danger: bool = _threat_clearance(miner.pos,threats) < 0.0
	if mine >= 0 and mine < sim.mines.size(): danger = danger or _threat_clearance(sim.mines[mine].pos,threats) < 0.0
	var recent_injury: bool = float(miner.hp) < sim.max_hp(miner)*.45 and float(miner.get("last_damage_time",-100.0)) > float(sim.time)-10.0
	if safety.is_empty() and not danger and not recent_injury: return false
	if safety.is_empty(): safety = {"resume_mine":mine,"last_danger":float(sim.time),"retry_at":0.0,"goal":Vector2.INF}
	records[id] = safety
	if danger or recent_injury: safety.last_danger = float(sim.time)
	var parked_goal: Vector2 = safety.get("goal",Vector2.INF)
	if parked_goal.is_finite() and (miner.pos as Vector2).distance_to(parked_goal) < 3.0 and _threat_clearance(miner.pos,threats) > 0.0:
		if miner.commands.is_empty() and not bool(miner.get("harvest_override",false)):
			# A zero-distance ordinary move parks an unloaded returner until the
			# danger hold expires; it cannot auto-drive back into the threatened ore.
			sim.issue([id],"move",miner.pos)
		if not recent_injury and sim.time >= float(safety.retry_at):
			var alternative: int = _safe_mine(sim,miner,mine)
			if alternative >= 0 and _threat_clearance(sim.mines[alternative].pos,threats) > 0.0:
				sim.issue([id],"harvest",sim.mines[alternative].pos,alternative)
				records.erase(id)
				state.miner_safety_switches = int(state.get("miner_safety_switches",0)) + 1
				return true
	if not danger and not recent_injury and sim.time-float(safety.last_danger) >= 10.0:
		var target: int = _safe_mine(sim,miner,-1)
		if target >= 0 and _threat_clearance(sim.mines[target].pos,threats) > 0.0:
			sim.issue([id],"harvest",sim.mines[target].pos,target)
			records.erase(id)
			state.miner_safety_resumes = int(state.get("miner_safety_resumes",0)) + 1
			return true
	if sim.time < float(safety.retry_at): return true
	var old_goal: Vector2 = safety.get("goal",Vector2.INF)
	if old_goal.is_finite() and _threat_clearance(old_goal,threats) > 0.0 and not miner.commands.is_empty(): return true
	var retreat: Dictionary = _miner_retreat_goal(sim,miner,threats)
	safety.retry_at = float(sim.time) + 8.0
	if retreat.is_empty(): return true
	if int(retreat.refinery) >= 0 and float(miner.cargo) > 0.0: sim.issue([id],"return_miner",retreat.pos,int(retreat.refinery))
	else: sim.issue([id],"move",retreat.pos)
	safety.goal = retreat.pos
	state.miner_safety_retreats = int(state.get("miner_safety_retreats",0)) + 1
	return true

static func _safe_mine(sim, miner: Dictionary, excluded: int) -> int:
	var home: Vector2 = sim._team_start(int(miner.team))
	var enemy_start: Vector2 = _public_enemy_start(sim, int(miner.team))
	var best: float = INF
	var answer: int = -1
	for index: int in range(sim.mines.size()):
		if index == excluded: continue
		var mine: Dictionary = sim.mines[index]
		if bool(sim._eco("finite_ore", false)) and float(mine.amount) <= 0.0: continue
		if (mine.pos as Vector2).distance_to(home) > (mine.pos as Vector2).distance_to(enemy_start) + .1: continue
		var drill: Dictionary = sim.entities.get(int(mine.get("drill", -1)), {})
		if not drill.is_empty() and (int(drill.team) == int(miner.team) or sim.entity_visible_to(int(miner.team),int(drill.id))): continue
		if sim.RailNetwork.rail_only(sim.data_for(miner.spec)) and not sim._rail_network.nearest_connected(sim,miner,mine.pos,sim._radius(miner)+float(sim._eco("harvester_mining_margin",1.4))).is_finite(): continue
		var score: float = (mine.pos as Vector2).distance_to(miner.pos) + (mine.pos as Vector2).distance_to(home) * .3
		for other: Dictionary in sim.entities.values():
			if other.kind != "unit" or int(other.id) == int(miner.id): continue
			if int(other.team) == int(miner.team) and str(sim.data_for(other.spec).get("art", "")) == "harvester" and int(other.get("harvest_mine", -1)) == index: score += 45.0
			elif int(other.team) != int(miner.team) and sim.entity_visible_to(int(miner.team), int(other.id)) and str(sim.data_for(other.spec).get("weapon", "")).length() > 0 and (other.pos as Vector2).distance_to(mine.pos) < 18.0: score += 500.0
		if score < best: best = score; answer = index
	return answer

static func _try_rail_repair(sim, miner: Dictionary, state: Dictionary) -> bool:
	var team: int = int(miner.team)
	if not sim.order_for_team(team, "defense").is_empty() or sim.money[team] < float(sim.data_for("iron_rail").cost) + _construction_liability(sim, team): return false
	# A validated branch upgrade reserves its one connecting segment until it
	# is actually purchased. New track/junction construction can finish normally.
	if state.has("rail_bridge_target"):
		var target: Vector2 = state.rail_bridge_target
		if sim._rail_network.cells.has(sim.RailNetwork.key(target)):
			if not sim._rail_network.at(team,target).is_empty(): state.erase("rail_bridge_target"); state.erase("rail_bridge_reserved")
			return false
		if sim._rail_network.site_error(sim,team,sim.data_for("iron_rail"),target).is_empty() and sim.build(team,"iron_rail").is_empty():
			state.rail_repair_site = target
			state.erase("rail_bridge_reserved")
			state.rail_repair_orders = int(state.get("rail_repair_orders",0)) + 1
			return true
		return false
	var candidates: Array = []
	var center: Vector2i = sim.RailNetwork.key(miner.pos)
	for y: int in range(-4,5):
		for x: int in range(-4,5):
			var point: Vector2 = sim.RailNetwork.center(center + Vector2i(x,y))
			if not sim._rail_network.at(team,point).is_empty(): continue
			var neighbors: int = 0
			for offset: Vector2i in sim.RailNetwork.DIRECTIONS:
				if not sim._rail_network.at(team,point+Vector2(offset)).is_empty(): neighbors += 1
			var facility_exit: bool = false
			if neighbors > 0:
				for facility: Dictionary in sim._building_entities:
					if int(facility.team) == team and sim.data_for(facility.spec).get("role", "") in ["refinery","factory"] and sim.RailNetwork.key(sim._rail_network.exit_cell(sim,facility)) == sim.RailNetwork.key(point): facility_exit = true; break
			if neighbors < 2 and not (neighbors > 0 and sim.RailNetwork.key(point) == center) and not facility_exit: continue
			if sim._rail_network.site_error(sim,team,sim.data_for("iron_rail"),point).is_empty(): candidates.append({"pos":point,"distance":point.distance_squared_to(miner.pos)})
	candidates.sort_custom(func(a,b): return float(a.distance) < float(b.distance))
	if candidates.is_empty(): return _try_rail_branch_bridge(sim,miner,state)
	if not sim.build(team,"iron_rail").is_empty(): return false
	state.rail_repair_site = candidates[0].pos
	state.rail_repair_orders = int(state.get("rail_repair_orders", 0)) + 1
	return true

static func _rail_component(sim, miner: Dictionary, start: Vector2) -> Dictionary:
	var first: Dictionary = sim._rail_network.at(int(miner.team),start)
	if first.is_empty(): return {}
	var seen: Dictionary = {}
	var pending: Array = [sim.RailNetwork.key(start)]
	while not pending.is_empty():
		var cell: Vector2i = pending.pop_back()
		if seen.has(cell): continue
		seen[cell] = true
		var track: Dictionary = sim._rail_network.cells.get(cell,{})
		for direction: int in range(4):
			var next: Vector2i = cell + sim.RailNetwork.DIRECTIONS[direction]
			var other: Dictionary = sim._rail_network.at(int(miner.team),sim.RailNetwork.center(next))
			if seen.has(next) or other.is_empty() or not sim._rail_network.linked(track,other,direction): continue
			if sim._standing(other.pos,sim._radius(miner),int(miner.id),false) and sim._segment_static(track.pos,other.pos,sim._radius(miner),int(miner.id)): pending.append(next)
	return seen

static func _try_rail_branch_bridge(sim, miner: Dictionary, state: Dictionary) -> bool:
	var team: int = int(miner.team)
	var own_component: Dictionary = _rail_component(sim,miner,miner.pos)
	if own_component.is_empty(): return false
	var target_component: Dictionary = {}
	for refinery: Dictionary in sim._building_entities:
		if int(refinery.team) != team or sim.data_for(refinery.spec).get("role", "") != "refinery" or float(refinery.construct_remaining) > 0.0: continue
		var entrance: Vector2 = sim._rail_network.exit_cell(sim,refinery)
		var component: Dictionary = _rail_component(sim,miner,entrance)
		if component.has(sim.RailNetwork.key(miner.pos)): return false
		target_component.merge(component)
	if target_component.is_empty(): return false
	var rail_info: Dictionary = sim.data_for("iron_rail")
	var junction_info: Dictionary = sim.data_for("iron_rail_junction")
	var refund: float = float(rail_info.cost) * float(sim._eco("sell_ratio",.5))
	if sim.money[team] + refund < float(junction_info.cost) + float(rail_info.cost) + _construction_liability(sim,team): return false
	if not sim.availability(team,"iron_rail_junction").is_empty(): return false
	for cell: Vector2i in own_component:
		for offset: Vector2i in sim.RailNetwork.DIRECTIONS:
			var gap_cell: Vector2i = cell + offset
			if sim._rail_network.cells.has(gap_cell): continue
			var gap: Vector2 = sim.RailNetwork.center(gap_cell)
			if not sim._standing(gap,sim._radius(miner),int(miner.id),false) or not sim._segment_static(sim.RailNetwork.center(cell),gap,sim._radius(miner),int(miner.id)): continue
			for target_offset: Vector2i in sim.RailNetwork.DIRECTIONS:
				var upgrade_cell: Vector2i = gap_cell + target_offset
				if not target_component.has(upgrade_cell): continue
				var old: Dictionary = sim._rail_network.cells[upgrade_cell]
				if str(sim.data_for(old.spec).get("role", "")) != "rail" or not sim._segment_static(gap,old.pos,sim._radius(miner),int(miner.id)): continue
				# Validate in a private planning graph. Only sell/build/place below
				# mutate the real world, at their normal prices and topology rules.
				for turns: int in range(4):
					var planning = sim.RailNetwork.new()
					planning.cells = sim._rail_network.cells.duplicate()
					planning.cells.erase(upgrade_cell)
					if not planning.site_error(sim,team,junction_info,old.pos,turns).is_empty(): continue
					planning.cells[upgrade_cell] = {"team":team,"pos":old.pos,"role":"rail_junction","spec":"iron_rail_junction","rail_ports":sim.RailNetwork.ports("rail_junction",turns)}
					if not planning.site_error(sim,team,rail_info,gap).is_empty(): continue
					if not sim.sell(int(old.id)).is_empty(): return false
					if not sim.build(team,"iron_rail_junction").is_empty(): return false
					sim.order_for_team(team,"defense").rail_rotation = turns
					state.rail_repair_site = old.pos
					state.rail_bridge_target = gap
					state.rail_bridge_reserved = float(rail_info.cost)
					state.rail_junction_upgrades = int(state.get("rail_junction_upgrades",0)) + 1
					return true
	return false

static func _manage_miners(sim, team: int, state: Dictionary) -> void:
	var watches: Dictionary = state.get("miner_watch", {})
	state.miner_watch = watches
	# Once a branch plan is validated and its junction purchased, advancing
	# the next paid construction stage is distinct from scanning a new fault.
	# Do not strand it behind the originating miner's 12-second retry clock.
	if state.has("rail_bridge_target"):
		for miner: Dictionary in sim.entities.values():
			if int(miner.team) == team and miner.kind == "unit" and sim.RailNetwork.rail_only(sim.data_for(miner.spec)):
				if _try_rail_repair(sim,miner,state): state.rail_phase_advances = int(state.get("rail_phase_advances",0)) + 1
				break
	var alive: Dictionary = {}
	var maximum_wait: float = 0.0
	for miner: Dictionary in sim.entities.values():
		if int(miner.team) != team or miner.kind != "unit" or str(sim.data_for(miner.spec).get("art", "")) != "harvester" or sim.Transport.is_loaded(miner): continue
		var id: int = int(miner.id)
		alive[id] = true
		var phase: String = str(miner.get("refinery_docking", {}).get("phase", ""))
		var watch: Dictionary = watches.get(id, {"pos":miner.pos,"cargo":float(miner.cargo),"phase":phase,"last_progress":float(sim.time),"last_seen":float(sim.time),"retry_at":0.0,"attempts":0})
		if (miner.pos as Vector2).distance_to(watch.pos) > .25 or absf(float(miner.cargo)-float(watch.cargo)) > .1 or phase != str(watch.phase):
			watch.pos = miner.pos; watch.cargo = float(miner.cargo); watch.phase = phase; watch.last_progress = float(sim.time)
		var waiting: float = maxf(0.0,float(sim.time)-float(watch.last_progress))
		watch.wait_seconds = waiting
		maximum_wait = maxf(maximum_wait,waiting)
		if waiting >= 12.0: state.miner_wait_seconds = float(state.get("miner_wait_seconds",0.0)) + maxf(0.0,float(sim.time)-float(watch.last_seen))
		watch.last_seen = float(sim.time)
		watches[id] = watch
		if _manage_miner_safety(sim,miner,state): continue
		if waiting < 12.0 or sim.time < float(watch.retry_at): continue
		watch.retry_at = float(sim.time) + 12.0
		watch.attempts = int(watch.attempts) + 1
		state.miner_recovery_checks = int(state.get("miner_recovery_checks",0)) + 1
		_unblock_unit(sim,miner,state)
		# Reservation, door traversal and cargo credit belong to the ordinary
		# docking/production code. Never cancel or teleport a vehicle inside.
		if not miner.get("refinery_docking", {}).is_empty() or bool(miner.get("emerging",false)):
			if sim.RailNetwork.rail_only(sim.data_for(miner.spec)): _try_rail_repair(sim,miner,state)
			continue
		var queue: Dictionary = miner.get("refinery_waiting", {})
		if not queue.is_empty() and waiting < 45.0:
			var source: Dictionary = sim.entities.get(int(queue.get("source",-1)),{})
			if not source.is_empty() and int(source.get("dock_unit",-1)) >= 0: continue
		if sim.RailNetwork.rail_only(sim.data_for(miner.spec)):
			_try_rail_repair(sim,miner,state)
			for factory: Dictionary in sim._building_entities:
				if int(factory.team) == team and sim.data_for(factory.spec).get("role", "") == "factory" and sim.money[team] >= _construction_liability(sim,team):
					if sim._rail_network.ai_connect_factory(sim,factory): break
		var command: String = ""
		if float(miner.cargo) > 0.0:
			var nearest: Dictionary = {}
			var distance: float = INF
			for refinery: Dictionary in sim._building_entities:
				if int(refinery.team) != team or float(refinery.construct_remaining) > 0.0 or sim.data_for(refinery.spec).get("role", "") != "refinery": continue
				var entrance: Vector2 = sim.RefineryDocking.entrance(sim,miner,refinery)
				if not entrance.is_finite(): continue
				if sim.RailNetwork.rail_only(sim.data_for(miner.spec)) and sim._rail_network.traversable_path(sim,miner,miner.pos,entrance).is_empty(): continue
				if (miner.pos as Vector2).distance_to(refinery.pos) < distance: distance = (miner.pos as Vector2).distance_to(refinery.pos); nearest = refinery
			if not nearest.is_empty(): sim.issue([id],"return_miner",nearest.pos,int(nearest.id)); command = "return"
		else:
			var target: int = _safe_mine(sim,miner,int(miner.get("harvest_mine",-1)))
			if target < 0: target = _safe_mine(sim,miner,-1)
			if target >= 0: sim.issue([id],"harvest",sim.mines[target].pos,target); command = "harvest"
		if not command.is_empty(): state.miner_recovery_orders = int(state.get("miner_recovery_orders",0)) + 1
	for id: Variant in watches.keys():
		if not alive.has(id): watches.erase(id)
	var safety: Dictionary = state.get("miner_safety",{})
	for id: Variant in safety.keys():
		if not alive.has(id): safety.erase(id)
	state.miner_wait_current_max = maximum_wait
	state.miner_wait_peak = maxf(float(state.get("miner_wait_peak",0.0)),maximum_wait)

static func _clear_producer_doors(sim, team: int) -> void:
	var state: Dictionary = sim.ai_state[team]
	for building: Dictionary in sim._building_entities:
		if int(building.team) != team: continue
		var unit: Dictionary = sim.entities.get(int(building.get("production_unit",-1)), {})
		if not unit.is_empty() and bool(unit.get("emerging",false)) and str(unit.state) in ["waiting_exit","waiting_rail"]: _unblock_unit(sim,unit,state)
	for e: Dictionary in sim.entities.values():
		if int(e.team) != team or e.kind != "unit" or str(sim.data_for(e.spec).get("art", "")) != "engineer" or not e.commands.is_empty() or bool(e.get("emerging",false)): continue
		for building: Dictionary in sim._building_entities:
			if int(building.team) != team or not sim.ProductionClearance.ground_producer(sim.data_for(building.spec)): continue
			var corridor: Rect2 = sim.ProductionClearance.corridor(sim,sim.data_for(building.spec),building.pos,sim.BuildingOrientation.quarters(building)).grow(1.0)
			if not corridor.has_point(e.pos): continue
			var home: Vector2 = sim._team_start(team)
			var forward: Vector2 = (_public_enemy_start(sim,team)-home).normalized()
			var destination: Vector2 = sim._near_stand(e.pos + forward.orthogonal() * 5.0,sim._radius(e),int(e.id),3.0,false)
			if destination.is_finite(): sim.issue([int(e.id)],"move",destination); state.traffic_yield_orders = int(state.get("traffic_yield_orders",0)) + 1
			break

static func _observed_enemies(sim, team: int) -> Dictionary:
	var observed: Dictionary = {"air":0,"armored":0,"infantry":0,"buildings":0}
	for e: Dictionary in sim.entities.values():
		if int(e.team) == team or float(e.hp) <= 0.0 or not sim.entity_visible_to(team, int(e.id)): continue
		var info: Dictionary = sim.data_for(e.spec)
		if e.kind == "building": observed.buildings += 1
		elif str(info.get("domain", "ground")) == "air": observed.air += 1
		elif str(info.get("armor_class", "")) == "infantry": observed.infantry += 1
		else: observed.armored += 1
	return observed

static func _construction_liability(sim, team: int) -> float:
	var reserve: float = 0.0
	for e: Dictionary in sim._building_entities:
		if int(e.team) == team and e.has("construction"):
			reserve += maxf(0.0, float(sim.data_for(e.spec).cost) - float(e.construction.get("spent", 0.0)))
	return reserve

static func _home_under_pressure(sim, team: int) -> bool:
	var home: Vector2 = sim._team_start(team)
	for e: Dictionary in sim.entities.values():
		if int(e.team) == team or e.kind != "unit" or float(e.hp) <= 0.0 or not sim.entity_visible_to(team, int(e.id)): continue
		if str(sim.data_for(e.spec).get("weapon", "")).is_empty(): continue
		if (e.pos as Vector2).distance_squared_to(home) <= 38.0 * 38.0: return true
	return false

static func _resume_construction(sim, team: int) -> void:
	for building: Dictionary in sim._building_entities:
		if int(building.team) != team or not building.has("construction"): continue
		var old_id: int = int(building.construction.get("builder", -1))
		if sim.entities.has(old_id) and not sim.entities[old_id].commands.is_empty() and sim.entities[old_id].commands[0].kind == "resume_outpost" and int(sim.entities[old_id].commands[0].target) == int(building.id): continue
		for e: Dictionary in sim.entities.values():
			if sim._builder_valid(team, int(e.id)) and e.commands.is_empty():
				sim.issue([int(e.id)], "resume_outpost", building.pos, int(building.id))
				break

static func _land_goal(sim, team: int, profile_data: Dictionary) -> String:
	var faction: String = sim.factions[team]
	var power: Vector2 = sim.power(team)
	if sim._role_count(team, "power") == 0 or power.x < power.y + 35.0:
		# One unfinished generator already addresses this shortage.
		for building: Dictionary in sim._building_entities:
			if int(building.team) == team and sim.data_for(building.spec).get("role", "") == "power" and float(building.construct_remaining) > 0.0: return ""
		if faction == "sky" and sim._has_role(team, "tech") and sim._role_count(team, "power") >= 2: return "advanced_power"
		return "power"
	if faction == "rivet" and sim._role_count(team, "drill") < 1: return "drill"
	if faction != "rivet" and sim._role_count(team, "refinery") < 1: return "refinery"
	if sim._role_count(team, "barracks") < 1: return "barracks"
	if sim._role_count(team, "factory") < 1: return "factory"
	if not sim._has_role(team, "factory"): return ""
	# Fund the first fighting vehicle before optional expansion or technology.
	if sim._unit_spec_count(team, faction + "_tank") < 1: return ""
	# All factions suspend optional growth while a small defending army faces
	# a visible armed raid. Essential power and the first income facility above
	# still take priority; hidden enemy forces cannot trigger this response.
	if _home_under_pressure(sim, team) and _roster_count(sim, team, "infantry") + _roster_count(sim, team, "vehicle") < 6: return ""
	if _roster_count(sim, team, "infantry") + _roster_count(sim, team, "vehicle") < 4: return ""
	if faction == "rivet" and sim._role_count(team, "drill") < (3 if sim.time >= 90.0 else 2): return "drill"
	if faction != "rivet" and sim.time >= float(profile_data.get("expansion_after",90.0)) and sim._role_count(team, "refinery") < 2: return "refinery"
	# A functioning economy needs an actual fighting force before optional
	# research/air budgets can reserve several minutes of early income.
	if _roster_count(sim, team, "infantry") + _roster_count(sim, team, "vehicle") < 6: return ""
	if sim.time >= float(profile_data.tech_after) and sim._role_count(team, "tech") < 1: return "tech"
	if sim.time >= float(profile_data.air_after) and sim._role_count(team, "airfield") < 1: return "airfield"
	if not _air_purchase_goal(sim, team).is_empty(): return ""
	if sim.time >= float(profile_data.get("factory_after",300.0)) and sim._role_count(team, "factory") < 2: return "factory"
	if sim.time >= 360.0 and faction == "rivet" and sim._role_count(team, "drill") < 4: return "drill"
	if sim.time >= 420.0 and sim._role_count(team, "airfield") < 2: return "airfield"
	return ""

static func _build_land(sim, team: int, faction: String) -> void:
	sim.ai_rebuild_base(team)
	if not sim._has_construction_base(team) or not sim.order_for_team(team, "normal").is_empty(): return
	var profile_data: Dictionary = _profile(sim, team)
	var liability: float = _construction_liability(sim, team) + float(sim.ai_state[team].get("rail_bridge_reserved",0.0))
	var role: String = _land_goal(sim, team, profile_data)
	var first_reserve: float = _first_factory_purchase_reserve(sim, team, faction)
	if not role.is_empty():
		var spec: String = sim.building_spec(team, role)
		var guard_reserve: float = ceili(float(maxi(0, 2 - sim._unit_spec_count(team, "iron_rifle")))/sim.squad_size("iron_rifle")) * sim.production_cost("iron_rifle") if faction == "iron" and role == "factory" else 0.0
		if not spec.is_empty() and sim.money[team] >= float(sim.data_for(spec).cost) + liability + maxf(first_reserve, guard_reserve):
			if role == "drill":
				var before: int = sim._role_count(team, "drill")
				sim.MiningDrills.ai_build(sim, team)
				if sim._role_count(team, "drill") > before: sim.ai_state[team].build_orders = int(sim.ai_state[team].get("build_orders", 0)) + 1
			elif sim.ai_build(team, spec).is_empty(): sim.ai_state[team].build_orders = int(sim.ai_state[team].get("build_orders", 0)) + 1
	# A bounded defensive purchase cannot eat an economic, first-tank or
	# scaffold budget. It uses the independent, normal paid defense queue.
	if not sim._has_role(team, "factory") or not sim.order_for_team(team, "defense").is_empty(): return
	var desired: int = int(profile_data.get("tower_limit",1 if sim.time < 240.0 else 2))
	if sim._role_count(team, "tower") >= desired: return
	var tower: String = faction + "_tower"
	var observed: Dictionary = sim.ai_state[team].get("observed", {})
	if int(observed.get("air", 0)) > 0 and sim.rules.buildings.has(faction + "_aa_tower"): tower = faction + "_aa_tower"
	var economic_reserve: float = float(sim.data_for(sim.building_spec(team, role)).get("cost", 0.0)) if not role.is_empty() else 0.0
	var air_goal: String = _air_purchase_goal(sim, team)
	if not air_goal.is_empty(): economic_reserve += float(sim.data_for(air_goal).cost)
	if sim.money[team] >= float(sim.data_for(tower).cost) + _construction_liability(sim, team) + first_reserve + economic_reserve + 400.0:
		if sim.ai_build(team, tower).is_empty(): sim.ai_state[team].build_orders = int(sim.ai_state[team].get("build_orders", 0)) + 1

static func _roster_count(sim, team: int, category: String) -> int:
	var amount: int = 0
	for e: Dictionary in sim.entities.values():
		if int(e.team) != team: continue
		var specs: Array = [str(e.spec)] if e.kind == "unit" else []
		for queued: Dictionary in e.queue: specs.append(str(queued.spec))
		for spec: String in specs:
			var info: Dictionary = sim.data_for(spec)
			if str(info.get("weapon", "")).is_empty() or str(info.get("art", "")) == "engineer": continue
			var domain: String = str(info.get("domain", "ground"))
			if category == "air" and domain == "air": amount += 1
			elif category == "infantry" and domain == "ground" and str(info.get("armor_class", "")) == "infantry": amount += 1
			elif category == "vehicle" and domain == "ground" and str(info.get("armor_class", "")) != "infantry": amount += 1
	return amount

static func _produce_land(sim, team: int, faction: String) -> void:
	var state: Dictionary = sim.ai_state[team]
	var counts: Dictionary = state.get("production_counts", {})
	state.production_counts = counts
	var profile_data: Dictionary = _profile(sim, team)
	var observed: Dictionary = state.get("observed", _observed_enemies(sim, team))
	var goal: String = _land_goal(sim, team, profile_data)
	var reserve: float = _construction_liability(sim, team)
	reserve += float(state.get("rail_bridge_reserved",0.0))
	if not goal.is_empty() and sim.order_for_team(team, "normal").is_empty(): reserve += float(sim.data_for(sim.building_spec(team, goal)).get("cost", 0.0))
	var air_goal: String = _air_purchase_goal(sim, team)
	if not air_goal.is_empty(): reserve += float(sim.data_for(air_goal).cost)
	var rebuilding: bool = not sim._has_construction_base(team) and bool(sim.data_for(faction + "_hq").get("rebuildable", false))
	if rebuilding: reserve += float(sim.data_for(faction + "_hq").cost)
	var first_tank: bool = sim._has_role(team, "factory") and sim._unit_spec_count(team, faction + "_tank") < 1
	if first_tank: reserve = maxf(reserve, _construction_liability(sim, team) + float(sim.data_for(faction + "_tank").cost))
	var harvesters: int = sim._unit_spec_count(team, faction + "_harvester")
	var infantry_count: int = _roster_count(sim, team, "infantry")
	var vehicle_count: int = _roster_count(sim, team, "vehicle")
	var under_pressure: bool = _home_under_pressure(sim, team)
	state.pressure_active = under_pressure
	# Iterate expensive producers first, so ready factories do not lose their
	# exact purchase budget to an unrelated infantry order in this reaction.
	var producers: Array = sim._building_entities.duplicate()
	producers.sort_custom(func(a, b): return int(sim.data_for(a.spec).get("role", "") != "factory") < int(sim.data_for(b.spec).get("role", "") != "factory"))
	for building: Dictionary in producers:
		if int(building.team) != team or float(building.hp) <= 0.0 or float(building.construct_remaining) > 0.0: continue
		var role: String = "barracks" if sim.TechAvailability.producer_matches(sim, building, "barracks") else str(sim.data_for(building.spec).get("role", ""))
		if not building.queue.is_empty() and not (role == "factory" and first_tank and building.queue.size() == 1 and str(building.queue[0].spec).ends_with("_harvester")): continue
		var index: int = int(counts.get(role, 0))
		var choice: String = ""
		var essential: bool = false
		match role:
			"factory":
				if faction != "rivet" and harvesters < 1:
					choice = faction + "_harvester"; essential = true
				elif first_tank:
					choice = faction + "_tank"; essential = true
				elif faction != "rivet" and infantry_count + vehicle_count >= 4 and not under_pressure and harvesters < (4 if sim._role_count(team, "refinery") >= 2 and infantry_count + vehicle_count >= 10 else 2):
					choice = faction + "_harvester"
				elif faction == "sky" and vehicle_count >= 4 and sim._unit_spec_count(team, "sky_designation") < 1:
					choice = "sky_designation"
				elif faction == "iron" and vehicle_count >= 5 and sim._unit_spec_count(team, "iron_repair_vehicle") < 1:
					choice = "iron_repair_vehicle"
				else: choice = FactionAdapter.vehicle(faction, profile_data, index, observed)
			"barracks":
				var builders: int = sim._unit_spec_count(team, faction + "_engineer")
				if not sim._has_role(team, "factory") and infantry_count < 2 and (builders > 0 or faction != "rivet"):
					choice = faction + "_rifle"; essential = true
				elif under_pressure and infantry_count + vehicle_count < 6 and (builders > 0 or faction != "rivet"):
					choice = FactionAdapter.infantry(faction, profile_data, index, observed)
				elif builders < (int(profile_data.builders) if not first_tank and sim._has_role(team, "factory") else 1) and (faction == "rivet" or infantry_count + vehicle_count >= 4):
					choice = faction + "_engineer"; essential = builders < 1 and not first_tank
				elif infantry_count < int(profile_data.infantry_limit): choice = FactionAdapter.infantry(faction, profile_data, index, observed)
			"airfield":
				if _roster_count(sim, team, "air") >= 6: continue
				if int(observed.get("air", 0)) > 0 and sim._unit_spec_count(team, faction + "_fighter") < maxi(1, int(observed.air) / 2): choice = faction + "_fighter"
				else:
					for suffix: String in profile_data.air:
						var candidate: String = faction + "_" + suffix
						if sim.rules.units.has(candidate) and sim.availability(team, candidate, -1, int(building.id)).is_empty(): choice = candidate; break
		if choice.is_empty(): continue
		if role == "barracks" and under_pressure and infantry_count + vehicle_count < 6 and str(sim.data_for(choice).get("art", "")) != "engineer" and (not sim.availability(team, choice, -1, int(building.id)).is_empty() or sim.money[team] < sim.production_cost(choice) + _construction_liability(sim,team)):
			choice = _affordable_defender(sim, team, building, observed)
			if choice.is_empty(): continue
		if not sim.rules.units.has(choice) or not sim.availability(team, choice, -1, int(building.id)).is_empty():
			if role != "factory": continue
			choice = faction + "_tank"
			if not sim.availability(team, choice, -1, int(building.id)).is_empty(): continue
		var cost: float = sim.production_cost(choice)
		var purchase_reserve: float = 0.0 if essential and not rebuilding else reserve
		purchase_reserve = maxf(purchase_reserve,_construction_liability(sim,team) + float(state.get("rail_bridge_reserved",0.0)))
		if role == "airfield" and not air_goal.is_empty(): purchase_reserve = maxf(_construction_liability(sim, team), reserve - float(sim.data_for(air_goal).cost))
		# Beyond the opening, preserve part of one factory purchase when the
		# armor style would otherwise spend every income tick on rifle squads.
		if role == "barracks" and not essential and not first_tank and sim._has_role(team, "factory"):
			purchase_reserve = maxf(purchase_reserve, float(sim.data_for(faction + "_tank").cost) * float(profile_data.factory_share))
		var urgent_defender: bool = role == "barracks" and under_pressure and infantry_count + vehicle_count < 6 and str(sim.data_for(choice).get("art", "")) != "engineer"
		if urgent_defender: purchase_reserve = _construction_liability(sim, team) + float(state.get("rail_bridge_reserved",0.0))
		if sim.money[team] < cost + purchase_reserve: continue
		if sim.produce(int(building.id), choice).is_empty():
			counts[role] = index + 1
			state.production_orders = int(state.get("production_orders", 0)) + 1
			if urgent_defender: state.emergency_defenders = int(state.get("emergency_defenders", 0)) + 1
			if choice.ends_with("_harvester"):
				harvesters += 1
				if sim.RailNetwork.rail_only(sim.data_for(choice)): building.ai_economy_rail_wait = true
			if choice == faction + "_tank" and first_tank:
				first_tank = false
				reserve = maxf(0.0, reserve - cost)
			if role == "factory" and not str(sim.data_for(choice).get("weapon", "")).is_empty(): vehicle_count += 1
			if role == "barracks" and not choice.ends_with("_engineer"): infantry_count += sim.squad_size(choice)
	# Tracks cost their actual rules price. Reserve the next miner/first tank
	# before asking the existing railway adapter to connect the real factory.
	if faction == "iron":
		for building: Dictionary in sim._building_entities:
			if int(building.team) != team or not bool(building.get("ai_economy_rail_wait", false)): continue
			if first_tank or sim.money[team] < _construction_liability(sim, team): continue
			if sim._rail_network.ai_connect_factory(sim, building): building.erase("ai_economy_rail_wait")

static func _place_land(sim, team: int, channel: String) -> void:
	var order: Dictionary = sim.order_for_team(team, channel)
	if order.is_empty(): return
	var role: String = str(sim.data_for(order.spec).get("role", ""))
	if role in ["rail","rail_junction"] and sim.ai_state[team].has("rail_repair_site"):
		var target: Vector2 = sim.ai_state[team].rail_repair_site
		if sim.placement_error(team,target,channel).is_empty():
			sim.place_building(team,target,channel)
			sim.ai_state[team].erase("rail_repair_site")
		return
	if sim.factions[team] == "iron" and role == "refinery":
		sim._ai_place(team, channel)
		return
	var home: Vector2 = sim._team_start(team)
	var forward: Vector2 = (_public_enemy_start(sim, team) - home).normalized()
	if forward.is_zero_approx(): forward = Vector2.RIGHT
	# Reflect x without rotating z on the authored mirror battlefield.
	var tangent: Vector2 = Vector2.DOWN if absf(forward.x) > .9 else forward.orthogonal()
	var zones: Array = sim.construction_zones(team)
	if zones.is_empty():
		sim._ai_place(team, channel)
		return
	var preferred: Vector2 = home + forward * (17.0 if role == "tower" else 8.0)
	# Reserve the two forward ore sectors for the economy. Support facilities
	# start behind headquarters instead of filling miners' shortest access paths.
	if role in ["power","factory"]: preferred = home - forward * 12.0 - tangent * 12.0
	elif role == "barracks": preferred = home - forward * 10.0 + tangent * 10.0
	elif role == "tech": preferred = home - forward * 17.0
	elif role == "airfield": preferred = home + tangent * 18.0
	if role == "refinery":
		var ranked: Array = []
		for mine: Dictionary in sim.mines:
			if (mine.pos as Vector2).distance_to(home) > 56.0 or (mine.pos as Vector2).distance_to(home) > (mine.pos as Vector2).distance_to(_public_enemy_start(sim, team)): continue
			var nearest: float = 40.0
			for e: Dictionary in sim._building_entities:
				if int(e.team) == team and sim.data_for(e.spec).get("role", "") == "refinery": nearest = minf(nearest, (e.pos as Vector2).distance_to(mine.pos))
			ranked.append({"pos":mine.pos,"score":(mine.pos as Vector2).distance_to(home) - nearest * .8})
		ranked.sort_custom(func(a, b): return float(a.score) < float(b.score))
		if not ranked.is_empty(): preferred = ranked[0].pos + (home - ranked[0].pos).normalized() * 6.0
	# Try a role-appropriate site first, then a bounded reflected search in the
	# normal owned construction zones. All candidates use normal authority.
	var origins: Array = [{"pos":preferred,"radius":9.0}]
	origins.append_array(zones)
	for zone: Dictionary in origins:
		for ring: int in range(0 if zone == origins[0] else 5, ceili(float(zone.radius)) + 1):
			for n: int in range(1 if ring == 0 else 24):
				var angle: float = float(n) * TAU / 24.0 + .31
				var point: Vector2 = sim.snap_build_position(team, zone.pos + (forward * cos(angle) + tangent * sin(angle)) * float(ring), channel)
				if not _land_apron_clear(sim, team, str(order.spec), point): continue
				if sim.placement_error(team, point, channel).is_empty() and sim.place_building(team, point, channel).is_empty(): return

static func _land_apron_clear(sim, team: int, spec: String, point: Vector2) -> bool:
	# The human placement rules permit compact layouts. This planner reserves
	# four metres of traffic space on every facility edge: a legal door can
	# otherwise open into a pocket that a miner cannot leave after unloading.
	var half: float = float(sim.data_for(spec).size) * .5
	for mine: Dictionary in sim.mines:
		if absf(point.x-mine.pos.x) < half + 2.8 and absf(point.y-mine.pos.y) < half + 2.8: return false
	for building: Dictionary in sim._building_entities:
		if float(building.hp) <= 0.0: continue
		if int(building.team) != team and not sim.entity_visible_to(team, int(building.id)): continue
		if sim.RailNetwork.is_rail(sim.data_for(building.spec)):
			if absf(point.x-building.pos.x) < half + 1.2 and absf(point.y-building.pos.y) < half + 1.2: return false
			continue
		var margin: float = 4.0
		var other_half: float = float(sim.data_for(building.spec).size) * .5
		if absf(point.x - building.pos.x) < half + other_half + margin and absf(point.y - building.pos.y) < half + other_half + margin: return false
	return true

static func _public_enemy_start(sim, team: int) -> Vector2:
	var home: Vector2 = sim._team_start(team)
	var target: Vector2 = home
	var distance: float = INF
	for other: int in range(sim.factions.size()):
		if other == team or other >= sim.map.get("starts", []).size(): continue
		var point: Vector2 = sim._vec(sim.map.starts[other])
		if home.distance_squared_to(point) < distance: target = point; distance = home.distance_squared_to(point)
	return target

static func _skirmish_attack(sim, team: int, config: Dictionary, state: Dictionary) -> void:
	var profile_data: Dictionary = _profile(sim, team)
	var goal: Vector2 = _objective(sim, team)
	if not goal.is_finite(): return
	var home: Vector2 = sim._team_start(team)
	var rally: Vector2 = home + (_public_enemy_start(sim, team) - home).normalized() * 30.0
	if int(state.get("attack_waves",0)) == 0 and _roster_count(sim,team,"infantry") + _roster_count(sim,team,"vehicle") < 4:
		rally = home + (_public_enemy_start(sim,team)-home).normalized() * 12.0
	var troops: Array = []
	var committed: int = 0
	for e: Dictionary in sim.entities.values():
		if int(e.team) != team or e.kind != "unit" or sim.Transport.is_loaded(e) or bool(e.get("emerging", false)): continue
		var info: Dictionary = sim.data_for(e.spec)
		if str(info.get("weapon", "")).is_empty() or str(info.get("domain", "ground")) != "ground" or str(info.get("art", "")) == "engineer": continue
		if sim.time < float(e.get("ai_traffic_until",0.0)): continue
		# Surviving assault units keep clearing the observed base. Sending every
		# temporarily idle veteran back to the assembly point otherwise turns
		# a successful first wave into an endless march home and back.
		if bool(e.get("ai_attacking", false)):
			committed += 1
			if _recover_attack(sim,e,goal,state): continue
			if e.commands.is_empty(): sim.issue([int(e.id)], "attack_move", goal)
			elif str(e.commands[0].kind) == "attack_move" and (e.commands[0].pos as Vector2).distance_to(goal) > 8.0 and (e.pos as Vector2).distance_to(e.commands[0].pos) < 12.0: sim.issue([int(e.id)], "attack_move", goal)
			continue
		# A visible attack target assigned by defense retains priority.
		if not e.commands.is_empty() and str(e.commands[0].kind) not in ["move","attack_move","patrol"]: continue
		if not e.commands.is_empty() and str(e.commands[0].kind) == "attack_move" and (e.pos as Vector2).distance_to(home) > 30.0 and (e.commands[0].pos as Vector2).distance_to(rally) > 8.0: continue
		troops.append(int(e.id))
		if e.commands.is_empty() and (e.pos as Vector2).distance_to(rally) > 5.0: sim.issue([int(e.id)], "attack_move", rally)
	var wave: int = maxi(3, roundi(float(config.wave) * float(profile_data.wave_scale)))
	if int(state.get("attack_waves", 0)) == 0: wave = mini(wave, 4)
	elif committed > 0 and float(state.attack_clock) >= float(config.attack_gap) * float(profile_data.attack_scale) * 2.0: wave = 1
	if troops.size() < wave or float(state.attack_clock) < float(config.attack_gap) * float(profile_data.attack_scale): return
	# Send the assembled combined force together; expensive tanks no longer
	# remain forever behind a slice of the earliest six infantry IDs.
	sim.issue(troops, "attack_move", goal)
	for id: int in troops: sim.entities[id].ai_attacking = true
	state.attack_clock = 0.0
	state.attack_waves = int(state.get("attack_waves", 0)) + 1
	var watches: Dictionary = state.get("attack_watch",{})
	for id: Variant in watches.keys():
		if not sim.entities.has(id): watches.erase(id)

static func _recover_attack(sim, unit: Dictionary, goal: Vector2, state: Dictionary) -> bool:
	var watches: Dictionary = state.get("attack_watch",{})
	state.attack_watch = watches
	var id: int = int(unit.id)
	var watch: Dictionary = watches.get(id,{"pos":unit.pos,"last_progress":float(sim.time),"last_attack":float(unit.get("last_attack_time",-1.0)),"retry_at":0.0})
	if (unit.pos as Vector2).distance_to(watch.pos) > .5 or float(unit.get("last_attack_time",-1.0)) > float(watch.last_attack):
		watch.pos = unit.pos; watch.last_progress = float(sim.time); watch.last_attack = float(unit.get("last_attack_time",-1.0))
	watches[id] = watch
	if sim.time - float(watch.last_progress) < 18.0 or sim.time < float(watch.retry_at) or unit.commands.is_empty(): return false
	if str(unit.commands[0].kind) not in ["attack_move","move"]: return false
	if _engaged_in_range(sim,unit): return false
	watch.retry_at = float(sim.time) + 20.0
	var direction: Vector2 = (goal-unit.pos).normalized()
	var side: float = -1.0 if id % 2 == 0 else 1.0
	var detour: Vector2 = sim._near_stand(unit.pos + direction.orthogonal() * side * 6.0 + direction * 4.0,sim._radius(unit),id,3.0,false)
	if not detour.is_finite(): return false
	sim.issue([id],"attack_move",detour)
	sim.issue([id],"attack_move",goal,-1,true)
	state.attack_recovery_orders = int(state.get("attack_recovery_orders",0)) + 1
	return true

static func _land_air_and_support(sim, team: int) -> void:
	var goal: Vector2 = _objective(sim, team)
	var forward_units: Array = []
	for e: Dictionary in sim.entities.values():
		if int(e.team) != team or e.kind != "unit" or bool(e.get("emerging", false)): continue
		var info: Dictionary = sim.data_for(e.spec)
		if str(info.get("domain", "ground")) == "ground" and str(info.get("weapon", "")).length() > 0 and str(info.get("art", "")) != "engineer": forward_units.append(e)
		if str(info.get("domain", "ground")) != "air" or not e.commands.is_empty() or str(e.get("flight_state", "")) in ["returning","rearming"]: continue
		var weapon: Dictionary = sim.rules.weapons.get(str(info.get("weapon", "")), {})
		if "ground" in weapon.get("targets", []) and goal.is_finite(): sim.issue([int(e.id)], "attack_move", goal)
		else:
			# Air superiority responds only to enemies currently visible.
			for enemy: Dictionary in sim.entities.values():
				if int(enemy.team) != team and sim.entity_visible_to(team, int(enemy.id)) and sim._weapon_can_target(e, int(enemy.id)):
					sim.issue([int(e.id)], "attack", enemy.pos, int(enemy.id)); break
	if forward_units.is_empty(): return
	var home: Vector2 = sim._team_start(team)
	forward_units.sort_custom(func(a, b): return (a.pos as Vector2).distance_squared_to(home) > (b.pos as Vector2).distance_squared_to(home))
	var anchor: Dictionary = forward_units[mini(2, forward_units.size() - 1)]
	for e: Dictionary in sim.entities.values():
		if int(e.team) != team or e.kind != "unit" or not e.commands.is_empty() or str(sim.data_for(e.spec).get("art", "")) not in ["designation","repair_vehicle"]: continue
		var destination: Vector2 = anchor.pos + (home - anchor.pos).normalized() * 4.0
		if (e.pos as Vector2).distance_to(destination) > 6.0: sim.issue([int(e.id)], "move", destination)
