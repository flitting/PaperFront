extends SceneTree
const Sim=preload("res://tests/rule_test_simulation.gd")
const Hero=preload("res://scripts/hero_rules.gd")
var checks:int=0
var failures:Array[String]=[]
func _initialize()->void:
	var sim=Sim.new()
	sim.setup(RulesLoader.load_rules("res://data/rules.json",false),"dev",7,"sky",false)
	var hand:int=sim.debug_spawn(0,"sky_creator_hand",Vector2(12.5,40.5))
	var building:int=sim._spawn(1,"rivet_power",Vector2(16.5,40.5),true)
	strike(sim,hand,building)
	check(not sim.entities.has(building) and death_style(sim,building)=="creator_crush","normal resolved hand strike tags destroyed building for press fragments")
	var infantry:int=sim.debug_spawn(1,"rivet_rifle",Vector2(16,40))
	strike(sim,hand,infantry)
	check(not sim.entities.has(infantry) and death_style(sim,infantry)=="creator_crush","normal hand kill tags unit press style")
	var survivor:int=sim.debug_spawn(1,"rivet_advanced",Vector2(16,40))
	var hp:float=sim.entities[survivor].hp
	strike(sim,hand,survivor)
	check(sim.entities.has(survivor) and sim.entities[survivor].hp<hp,"hand hit leaves sufficiently armored target alive with ordinary damage")
	check(sim._crush_targets.is_empty() and not sim.entities[survivor].has("death_style"),"survivor retains no persistent crush metadata")
	sim.events.clear()
	sim._add_damage(survivor,100000.0)
	sim._apply_damage()
	check(death_style(sim,survivor).is_empty(),"later ordinary lethal damage keeps ordinary death appearance")
	var sold:int=sim._spawn(1,"rivet_power",Vector2(16,40),true)
	sim._crush_targets[sold]=true
	sim.events.clear()
	sim._kill_entity(sold,false)
	check(death_style(sim,sold).is_empty(),"non-destruction removal never uses creator crush style")
	sim._crush_targets[hand]=true
	sim.step(1.0/30.0)
	check(sim._crush_targets.is_empty(),"new tick clears transient creator hit metadata")
	print("V6_CREATOR_CRUSH_METADATA ",JSON.stringify({"checks":checks,"failures":failures}))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
func strike(sim,hand:int,target:int)->void:
	Hero.step(sim,.4)
	sim.events.clear()
	sim._damage.clear()
	sim.entities[hand].cooldown=0.0
	sim._fire(sim.entities[hand],target)
	Hero.step(sim,.55)
	sim._apply_damage()
func death_style(sim,id:int)->String:
	for event:Dictionary in sim.events:
		if event.get("kind")=="death" and int(event.get("id",-1))==id:return str(event.get("death_style",""))
	return ""
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
