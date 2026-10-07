extends RefCounted

## Per-team planners use only normal simulation commands and observed enemies.
const SETTINGS := {
	"easy":{"reaction":4.0,"wave":4,"attack_gap":44.0,"air_weight":0.15,"anti_cycle":5,"factory_cycle":6},
	"normal":{"reaction":2.0,"wave":6,"attack_gap":32.0,"air_weight":0.25,"anti_cycle":4,"factory_cycle":5},
	"hard":{"reaction":1.0,"wave":8,"attack_gap":24.0,"air_weight":0.35,"anti_cycle":3,"factory_cycle":4}
}

static func initialize(sim) -> void:
	sim.ai_state = []
	for team in range(sim.factions.size()):
		sim.ai_state.append({"reaction_clock":0.0,"attack_clock":0.0,"scout_clock":0.0,"naval_clock":0.0})

static func step(sim, delta: float) -> void:
	if not sim.ai_enabled: return
	for team in range(1, sim.factions.size()):
		var slot: Dictionary = sim.match_options.slots[team]
		if str(slot.get("control", "ai")) != "ai": continue
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
	for channel in ["normal", "defense"]:
		var order: Dictionary = sim.order_for_team(team, channel)
		if not order.is_empty() and bool(order.get("ready", false)):
			if str(sim.data_for(order.spec).get("role", "")) == "shipyard": _place_shipyard(sim, team)
			else: sim._ai_place(team, channel)
	if str(sim.map.get("mode", "")) == "islands" and sim._has_role(team,"shipyard") and _naval_transport_count(sim,team)>0: _shore_outpost(sim, team, faction)
	_build(sim, team, faction)
	_produce(sim, team, faction, config)
	_defend(sim, team)
	if sim.campaign_controller != null: _hold_position(sim, team, sim.campaign_controller.ai_policy())
	if str(sim.map.get("mode", "")) == "islands":
		_naval_assault(sim, team, config, state)
	else:
		_land_attack(sim, team, config, state)
	if float(state.scout_clock) >= 28.0:
		state.scout_clock = 0.0
		_scout(sim, team, faction)

static func _build(sim, team: int, faction: String) -> void:
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
	if faction == "iron": guard_reserve = maxi(0, 2-sim._unit_spec_count(team,"iron_rifle"))*float(sim.data_for("iron_rifle").cost)
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
			if (not essential or rebuilding_base) and sim.money[team]<purchase_reserve+float(sim.data_for(choice).cost):continue
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
		if not sim._weapon_can_target(e,threat): continue
		if (e.pos as Vector2).distance_to(home) > 26.0: continue
		if e.commands.is_empty() or str(e.commands[0].get("kind", "")) != "attack" or int(e.commands[0].get("target", -1)) != threat: sim.issue([int(e.id)],"attack",sim.entities[threat].pos,threat)

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
		if int(e.team)==team or e.kind!="building" or not sim.entity_visible_to(team,int(e.id)): continue
		var distance:float=home.distance_squared_to(e.pos)
		if distance<best:best=distance;target=e.pos
	if target.is_finite(): return target
	for record in sim.team_vision.get("last_known", [])[team].values():
		if str(record.get("kind", ""))!="building": continue
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
		if destination.is_finite(): sim.issue([int(e.id)],"move",destination)
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
