extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
const Loader = preload("res://scripts/rules_loader.gd")
var checks := 0
var failures: Array[String] = []
var rules: Dictionary
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func near(a: float,b: float) -> bool: return absf(a-b)<.0001
func fixture():
	var sim=Simulation.new();sim.synchronous_path_tests=true
	var factions: Array[String]=["kestrel","rivet"]
	var starts: Array[Vector2]=[]
	sim.setup_multiteam(rules,"symmetric",733,factions,false,starts,Callable(),{"vision_enabled":false})
	return sim
func kill(sim,source: int,team: int,starred: bool,spec: String="rivet_rifle") -> int:
	var victim: int=sim._spawn(team,spec,Vector2(100,96),true)
	sim.entities[victim].veteran=starred
	sim.entities[victim].hp=sim.max_hp(sim.entities[victim])
	var cause: Dictionary={"source":source,"source_team":int(sim.entities[source].team),"weapon":"kestrel_rifle","explosive":false}
	sim._add_damage(victim,float(sim.entities[victim].hp)+1.0,true,cause)
	sim._apply_damage();sim._damage.clear();sim._damage_causes.clear()
	return victim
func close(sim) -> void:
	if sim._path_worker!=null:sim._path_worker.close()
func run() -> void:
	rules=Loader.load_rules("res://data/rules.json",false)
	check(not rules.is_empty(),"current rules load")
	if rules.is_empty():finish();return
	check(near(float(rules.experience.veteran_kill_experience_multiplier),2.0),"current star-kill reward is 2x")
	var sim=fixture()
	var source: int=sim._spawn(0,"kestrel_rifle",Vector2(90,96),true)
	var money: Array=sim.money.duplicate()
	kill(sim,source,1,false)
	check(near(float(sim.entities[source].experience_value),120.0),"ordinary enemy grants its original 120 value")
	kill(sim,source,1,true)
	check(near(float(sim.entities[source].experience_value),360.0),"starred enemy adds exactly 240 experience")
	check(bool(sim.entities[source].veteran),"bonus experience participates in normal promotion threshold")
	check(sim.money==money,"bonus experience grants no extra money")
	check(near(float(sim.statistics.teams[0].enemy_units_destroyed_value),240.0),"kill value remains two actual 120-value units, not 360 XP")
	check(near(float(sim.statistics.teams[1].units_lost_value),240.0),"loss telemetry is not doubled by starred reward")
	var before: float=float(sim.entities[source].experience_value)
	kill(sim,source,0,true,"kestrel_rifle")
	check(near(float(sim.entities[source].experience_value),before),"friendly starred kill grants no experience")
	var building: int=sim._spawn(1,"rivet_power",Vector2(110,96),true)
	sim.entities[building].veteran=true
	sim._add_damage(building,10000,true,{"source":source,"source_team":0,"weapon":"kestrel_rifle"});sim._apply_damage();sim._damage.clear();sim._damage_causes.clear()
	check(near(float(sim.entities[source].experience_value)-before,float(rules.buildings.rivet_power.cost)),"unit-star bonus does not multiply structure rewards")
	var ordinary: int=sim._spawn(0,"kestrel_tank",Vector2(90,104),true)
	sim.rules.experience.veteran_kill_experience_multiplier=3.0
	kill(sim,ordinary,1,true)
	check(near(float(sim.entities[ordinary].experience_value),360.0),"reward multiplier reads the match snapshot, not a global constant")
	close(sim)
	var legacy=fixture();legacy.rules.experience.erase("veteran_kill_experience_multiplier")
	var old_source: int=legacy._spawn(0,"kestrel_tank",Vector2(90,96),true)
	kill(legacy,old_source,1,true)
	check(near(float(legacy.entities[old_source].experience_value),120.0),"legacy snapshot without the field retains 1x starred reward")
	close(legacy)
	var persisted=fixture()
	var saved_source: int=persisted._spawn(0,"kestrel_tank",Vector2(70,96),true)
	kill(persisted,saved_source,1,true)
	var path: String="user://veteran_kill_experience_test.pfront"
	check(persisted.save_game(path).is_empty(),"new XP rule and accumulated reward save")
	var restored=Simulation.new();restored.synchronous_path_tests=true
	check(restored.load_game(path).is_empty(),"new XP snapshot restores")
	check(near(float(restored.rules.experience.veteran_kill_experience_multiplier),2.0),"save preserves 2x reward setting")
	kill(restored,saved_source,1,true)
	check(near(float(restored.entities[saved_source].experience_value),480.0),"resumed starred kill adds another 240 exactly")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path));close(persisted);close(restored)
	finish()
func finish() -> void:
	print("VETERAN_KILL_EXPERIENCE "+JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
