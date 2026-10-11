extends SceneTree

## Controlled real-simulation combat experiments. The terrain-only fixture is
## flattened to isolate unit value; it is deliberately separate from AI matches.
## No unit, weapon, trait, veterancy, targeting or movement rule is changed.
const Simulation = preload("res://scripts/simulation.gd")
const Loader = preload("res://scripts/rules_loader.gd")
const Combat = preload("res://scripts/armor_combat.gd")
const FACTIONS: Array[String] = ["kestrel", "rivet", "iron", "sky"]
var rules: Dictionary
var rules_path := "res://data/rules.json"
var output := "res://artifacts/balance_micro/current"
var suite := "full"
var settle_projectiles := false
var scenario_filter := ""
var faction_filter := ""
var cases: Array[Dictionary] = []
var failures: Array[String] = []
const DT := 0.05

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	for index in range(args.size()):
		if args[index] == "--rules" and index + 1 < args.size(): rules_path = args[index + 1]
		if args[index] == "--output" and index + 1 < args.size(): output = args[index + 1]
		if args[index] == "--suite" and index + 1 < args.size(): suite = args[index + 1]
		if args[index] == "--scenario" and index + 1 < args.size(): scenario_filter = args[index + 1]
		if args[index] == "--faction" and index + 1 < args.size(): faction_filter = args[index + 1]
		if args[index] == "--settle": settle_projectiles = true
	if suite not in ["quick","full","matched","core","mixed"]:
		push_error("--suite must be quick, full, matched, core or mixed");quit(1);return
	if not faction_filter.is_empty() and faction_filter not in FACTIONS:
		push_error("Unknown --faction");quit(1);return
	rules = Loader.load_rules(rules_path, false)
	if rules.is_empty():
		push_error("Invalid rules: " + str(Loader.errors)); quit(1); return
	var budgets := {"rifle":1500.0,"anti":1500.0,"scout":1800.0,"tank":4000.0}
	for role: String in budgets:
		if suite in ["matched","mixed"]: continue
		if suite in ["quick","core"] and role not in ["rifle","tank"]: continue
		for a in range(FACTIONS.size()):
			for b in range(a + 1, FACTIONS.size()):
				for swap in range(2):
					var left: String = FACTIONS[a] if swap == 0 else FACTIONS[b]
					var right: String = FACTIONS[b] if swap == 0 else FACTIONS[a]
					combat(role + "_mirror", left, right, roster(left,role,budgets[role]), roster(right,role,budgets[role]), swap)
	if suite == "full":
		for faction in FACTIONS:
			for swap in range(2):
				combat("anti_vs_rifle",faction,faction,roster(faction,"anti" if swap==0 else "rifle",1500),roster(faction,"rifle" if swap==0 else "anti",1500),swap)
				combat("anti_vs_tank",faction,faction,roster(faction,"anti" if swap==0 else "tank",4000),roster(faction,"tank" if swap==0 else "anti",4000),swap)
				combat("scout_vs_rifle",faction,faction,roster(faction,"scout" if swap==0 else "rifle",1800),roster(faction,"rifle" if swap==0 else "scout",1800),swap)
	if suite in ["full","matched","core","mixed"]:
		for a in range(FACTIONS.size()):
			for b in range(a+1,FACTIONS.size()):
				for swap in range(2):
					var left: String = FACTIONS[a] if swap==0 else FACTIONS[b]
					var right: String = FACTIONS[b] if swap==0 else FACTIONS[a]
					combat("mixed",left,right,mixed(left),mixed(right),swap)
	if suite == "matched":
		for other: String in ["rivet","iron"]:
			for swap in range(2):
				var k := {"kestrel_tank":5}
				var opponent := {other+"_tank":3 if other=="rivet" else 4}
				combat("tank_matched_spend","kestrel" if swap==0 else other,other if swap==0 else "kestrel",k if swap==0 else opponent,opponent if swap==0 else k,swap)
		for other: String in ["rivet","iron"]:
			for swap in range(2):
				var k := {"kestrel_anti":5 if other=="rivet" else 7}
				var opponent := {other+"_anti":4 if other=="rivet" else 6}
				combat("anti_matched_spend","kestrel" if swap==0 else other,other if swap==0 else "kestrel",k if swap==0 else opponent,opponent if swap==0 else k,swap)
	if cases.is_empty() and failures.is_empty(): failures.append("No experiment case matched the requested filters")
	var report := {
		"schema_version":2,"suite":suite,"filters":{"scenario":scenario_filter,"faction":faction_filter},"rules_path":rules_path,"rules_sha256":FileAccess.get_sha256(rules_path),
		"method":{"simulation":"scripts/simulation.gd","fixture":"48x48 flat unobstructed diagnostic arena; headquarters isolated at southern corners","dt":DT,"limit_seconds":90,"seed":733,"vision_enabled":false,"placement":"mirrored 7-row formation, 2.4 spacing; rows filled before adding rear columns","orders":"ordinary attack_move to enemy combat roster centroid, refreshed every two seconds to avoid disengagement after passing fixed starting targets","sampling":"First roster elimination sampled immediately, including projectile counts. With --settle, continue ordinary simulation without new commands until projectiles clear (maximum 5 additional seconds) and report both outcomes.","settle_projectiles":settle_projectiles,"budget":"single-role: floor(budget/unit cost); mixed: 1200 rifles/1500 anti/3300 tanks, then spend remaining 6000 budget on extra rifles; matched-spend: specified counts, actual spend and percentage gap reported. No reinforcements or production/tech cost.","caveats":["Controlled unit comparison; does not estimate faction win rates or account for economic and technology asymmetry.","Mirror swaps measure side sensitivity; two mirrored runs are not independent random samples.","All targeting, penetration, splash, crushing, regeneration and veterancy use current production simulation.","Without --settle, winner means first roster elimination, and in-flight projectiles may still change a close outcome.","The matched suite reuses troop counts selected for the baseline prices; changed prices may not remain closely matched. Inspect spend_gap_fraction rather than assuming equal deployment."]},
		"catalog":catalog(),"cases":cases,"failures":failures
	}
	var absolute := ProjectSettings.globalize_path(output + ".json")
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var file := FileAccess.open(absolute,FileAccess.WRITE)
	if file == null: push_error("Could not write " + absolute);quit(1);return
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("BALANCE_MICRO " + JSON.stringify({"output":absolute,"cases":cases.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)

func roster(faction: String, role: String, budget: float) -> Dictionary:
	var spec := faction + "_" + role
	return {spec:floori(budget / float(rules.units[spec].cost))}

func mixed(faction: String) -> Dictionary:
	var result := roster(faction,"rifle",1200)
	result.merge(roster(faction,"anti",1500))
	result.merge(roster(faction,"tank",3300))
	var rifle := faction+"_rifle"
	result[rifle]=int(result[rifle])+floori((6000-composition_cost(result))/float(rules.units[rifle].cost))
	return result

func fixture(left: String,right: String):
	var sim = Simulation.new()
	sim.synchronous_path_tests = true
	sim.map_generation_config = {"legacy_dev48":true}
	var ids: Array[String] = [left,right]
	var starts: Array[Vector2] = []
	sim.setup_multiteam(rules,"dev",733,ids,false,starts,Callable(),{"vision_enabled":false})
	if sim.entities.size()!=2 or not bool(sim.map.get("valid",false)):
		failures.append("Simulation setup incomplete for " + left + " / " + right)
		if sim._path_worker != null: sim._path_worker.close()
		return null
	for id in sim.entities.keys(): sim._kill_entity(id,false)
	for row in sim.map.terrain: row.fill(0)
	for row in sim.map.heights: row.fill(0.0)
	sim.mines.clear();sim.ruins.clear();sim.bridges.clear()
	sim._refresh_mine_spatial();sim._refresh_ruin_spatial()
	sim._prepare_terrain_cache();sim._nav_initialized=false;sim._rebuild_nav()
	sim._spawn(0,left+"_hq",Vector2(5,43),true)
	sim._spawn(1,right+"_hq",Vector2(43,43),true)
	sim.statistics.begin(sim)
	return sim

func deploy(sim,team: int,composition: Dictionary) -> Array[int]:
	var ids: Array[int] = []
	for spec: String in composition:
		for unused in range(int(composition[spec])):
			var slot := ids.size()
			var sign_side := 1.0 if team==0 else -1.0
			var pos := Vector2(14 if team==0 else 34,21)+Vector2(-sign_side*floori(slot/7.0)*2.4,(slot%7-3)*2.4)
			var id: int = sim.debug_spawn(team,spec,pos)
			if id<0: failures.append("Spawn failed: " + spec);continue
			ids.append(id)
	return ids

func assets(sim,ids: Array[int]) -> Dictionary:
	var count := 0
	var hp := 0.0
	var value := 0.0
	for id in ids:
		if not sim.entities.has(id): continue
		var e: Dictionary = sim.entities[id]
		count+=1;hp+=float(e.hp)
		value+=float(sim.data_for(e.spec).cost)*float(e.hp)/sim.max_hp(e)
	return {"alive":count,"hp":hp,"remaining_value":value}

func composition_cost(composition: Dictionary) -> float:
	var total := 0.0
	for spec: String in composition: total+=float(rules.units[spec].cost)*int(composition[spec])
	return total

func centroid(sim,ids: Array[int]) -> Vector2:
	var sum := Vector2.ZERO
	var count := 0
	for id in ids:
		if sim.entities.has(id): sum+=sim.entities[id].pos;count+=1
	return sum/maxi(1,count)

func roster_outcome(left: Dictionary,right: Dictionary) -> String:
	if left.alive==0 and right.alive==0: return "mutual_elimination"
	if right.alive==0: return "left"
	if left.alive==0: return "right"
	return "unfinished"

func projectiles_by_team(sim) -> Array[int]:
	var counts: Array[int] = [0,0]
	for shot: Dictionary in sim.projectiles:
		var team := int(shot.get("team",-1))
		if team in [0,1]: counts[team]+=1
	return counts

func combat(name: String,left: String,right: String,left_roster: Dictionary,right_roster: Dictionary,swap: int) -> void:
	if not failures.is_empty(): return
	if not scenario_filter.is_empty() and name != scenario_filter: return
	if not faction_filter.is_empty() and left != faction_filter and right != faction_filter: return
	var sim = fixture(left,right)
	if sim == null: return
	var lhs := deploy(sim,0,left_roster)
	var rhs := deploy(sim,1,right_roster)
	sim._rebuild_spatial()
	sim.issue(lhs,"attack_move",Vector2(34,21));sim.issue(rhs,"attack_move",Vector2(14,21))
	var remaining_left := assets(sim,lhs)
	var remaining_right := assets(sim,rhs)
	var next_orders := 2.0
	while float(sim.time)<90-.000001 and remaining_left.alive>0 and remaining_right.alive>0:
		if float(sim.time)>=next_orders-.000001:
			sim.issue(lhs,"attack_move",centroid(sim,rhs));sim.issue(rhs,"attack_move",centroid(sim,lhs))
			next_orders+=2.0
		sim.step(minf(DT,90-float(sim.time)));sim.events.clear();sim.notices.clear()
		remaining_left=assets(sim,lhs);remaining_right=assets(sim,rhs)
	var first_outcome := roster_outcome(remaining_left,remaining_right)
	var first_time: float = float(sim.time)
	var first_left := remaining_left.duplicate(true)
	var first_right := remaining_right.duplicate(true)
	var pending_initial := projectiles_by_team(sim)
	if settle_projectiles and first_outcome != "unfinished":
		while not sim.projectiles.is_empty() and float(sim.time)<first_time+5.0-.000001 and sim.result.is_empty():
			sim.step(minf(DT,first_time+5.0-float(sim.time)));sim.events.clear();sim.notices.clear()
		remaining_left=assets(sim,lhs);remaining_right=assets(sim,rhs)
	var winner := roster_outcome(remaining_left,remaining_right)
	var left_spent := composition_cost(left_roster)
	var right_spent := composition_cost(right_roster)
	var gap: float = absf(left_spent-right_spent)/maxf(.001,(left_spent+right_spent)*.5)
	var row := {"scenario":name,"swap":swap,"left":left,"right":right,"left_roster":left_roster,"right_roster":right_roster,"left_spent":left_spent,"right_spent":right_spent,"spend_gap_fraction":gap,"winner":winner,"seconds":float(sim.time),"remaining_left":remaining_left,"remaining_right":remaining_right,"first_elimination":{"winner":first_outcome,"seconds":first_time,"remaining_left":first_left,"remaining_right":first_right,"pending_projectiles_by_team":pending_initial},"settlement":{"requested":settle_projectiles,"elapsed_seconds":float(sim.time)-first_time,"pending_projectiles_by_team":projectiles_by_team(sim),"projectiles_cleared":sim.projectiles.is_empty(),"outcome_changed":winner!=first_outcome}}
	cases.append(row)
	print("MICRO_CASE " + JSON.stringify(row))
	if sim._path_worker != null: sim._path_worker.close()

func catalog() -> Dictionary:
	var result := {}
	for faction in FACTIONS:
		var units := {}
		for spec: String in rules.units:
			var u: Dictionary=rules.units[spec]
			if str(u.faction)!=faction or bool(u.get("roster_hidden",false)): continue
			var w: Dictionary=rules.weapons.get(str(u.get("weapon","")),{})
			var dps := {}
			var effective_dps := {}
			for target_class: String in ["infantry","armored","building"]:
				var base: float=float(w.get("damage",0))/maxf(.001,float(w.get("interval",1)))
				dps[target_class]=base*float(w.get("multipliers",{}).get(target_class,1))
			for target_faction in FACTIONS:
				for target_role: String in ["rifle","tank","hq"]:
					var target_spec: String=target_faction+"_"+target_role
					var target_info: Dictionary=rules.buildings[target_spec] if target_role=="hq" else rules.units[target_spec]
					var target_class: String="building" if target_role=="hq" else str(target_info.get("armor_class","armored"))
					effective_dps[target_spec]=float(dps[target_class])*Combat.penetration_factor(w,float(target_info.get("armor",0))) if "ground" in w.get("targets",["ground"]) else 0.0
			units[spec]={"cost":u.cost,"hp":u.hp,"armor":u.get("armor",0),"build_time":u.build_time,"speed":u.get("speed",0),"tier":u.get("tier",0),"range":w.get("range",0),"penetration":w.get("penetration",0),"dps_before_armor":dps,"nominal_dps_after_armor_by_target":effective_dps,"weapon":str(u.get("weapon","")),"weapon_targets":w.get("targets",[]),"weapon_kind":w.get("kind","none"),"weapon_blast":w.get("blast",0),"ammo_capacity":u.get("ammo_capacity",0)}
		var buildings := {}
		for spec: String in rules.buildings:
			var b: Dictionary=rules.buildings[spec]
			if str(b.faction)==faction: buildings[spec]={"cost":b.cost,"hp":b.hp,"armor":b.get("armor",0),"build_time":b.build_time,"power":b.get("power",0),"tier":b.get("tier",0),"role":b.get("role","")}
		result[faction]={"units":units,"buildings":buildings}
	return result
