extends SceneTree
const Sim=preload("res://tests/rule_test_simulation.gd")
const Tiers=preload("res://scripts/tier_availability.gd")
var checks:=0
var failures:Array[String]=[]
var rules:Dictionary
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label)
func _initialize():call_deferred("run")
func run():
 rules=RulesLoader.load_rules()
 check(not rules.is_empty(),"strict actual rules and assets validate: "+str(RulesLoader.errors))
 if rules.is_empty():quit(1);return
 for id in rules.units:
  var d:Dictionary=rules.units[id]
  check(int(d.logical_size) in [1,2] and is_equal_approx(d.radius,d.logical_size*.5),id+" footprint and collision agree")
  if d.art in ["tank","scout","harvester","rifle","anti","engineer"]:check(d.logical_size==1,id+" ordinary unit is one grid")
  if d.art=="heavy_tank":check(d.logical_size==2,id+" heavy tank is two grids")
  check(int(d.tier) in [1,2,3],id+" defined production tier")
  for required in d.requires:check(not str(required).ends_with("_command"),id+" no deleted command prerequisite")
 for f in rules.factions:
  check(not rules.buildings.has(f+"_command"),f+" command building deleted")
  var repair:Dictionary=rules.buildings[f+"_repair"]
  check(repair.tier==2 and repair.service_rate>0 and not repair.has("repair_radius"),f+" T2 repair is explicit service without aura")
  var basic:Dictionary=rules.weapons[f+"_tower"]
  var advanced:Dictionary=rules.weapons[f+"_advanced_tower"]
  check(rules.buildings[f+"_advanced_tower"].tier==2 and advanced.range>basic.range and advanced.damage>basic.damage and advanced.damage/advanced.interval>basic.damage/basic.interval,f+" T2 turret genuinely stronger and longer-ranged")
  check(rules.buildings[f+"_tech"].tier==2 and rules.buildings[f+"_tech"].unlocks_tier==3,f+" lab is buildable before it unlocks T3")
 var p:Dictionary=rules.buildings.sky_advanced_power
 var q:Dictionary=rules.buildings.sky_power
 check(p.tier==3 and p.size>q.size and float(p.power)/p.cost>float(q.power)/q.cost,"T3 advanced power generates more per dollar with larger footprint")
 for faction in ["kestrel","iron","sky"]:
  var fs:Array[String]=[faction,"rivet"]
  var s=Sim.new();s.setup_multiteam(rules,"dev",31,fs,false);s.money.assign([100000.0,100000.0])
  check(Tiers.current(s,0)==0,faction+" starts at T0")
  var barracks:int=s._spawn(0,faction+"_barracks",Vector2(15.5,15.5),false)
  check(Tiers.current(s,0)==0,faction+" unfinished barracks grants no tier")
  s.entities[barracks].construct_remaining=0;s._invalidate_base_cache()
  check(Tiers.current(s,0)==1,faction+" completed barracks unlocks T1")
  var airport:int=s._spawn(0,faction+"_airfield",Vector2(30.5,15.5),true)
  check(not s._has_role(0,"factory") and Tiers.current(s,0)==2,faction+" airport alone unlocks T2")
  s._kill_entity(airport,false)
  var factory:int=s._spawn(0,faction+"_factory",Vector2(30,20),true)
  check(Tiers.current(s,0)==2,faction+" factory alone unlocks T2")
  check(Tiers.missing(s,0,rules.buildings[faction+"_tech"]).is_empty(),faction+" T2 lab purchasable")
  var before:float=s.money[0]
  check(not s.produce(factory,faction+"_heavy_tank").is_empty() and s.money[0]==before,faction+" T3 production blocked without research, no funds spent")
  s._spawn(0,faction+"_tech",Vector2(38.5,15.5),true)
  check(Tiers.current(s,0)==3 and s.produce(factory,faction+"_heavy_tank").is_empty(),faction+" completed research really unlocks heavy production")
 # A repair building does not heal nearby units without a service order.
 var s=Sim.new();s.setup_multiteam(rules,"dev",31,["kestrel","rivet"],false)
 var depot:int=s._spawn(0,"kestrel_repair",Vector2(22,22),true)
 var vehicle:int=s._spawn(0,"kestrel_tank",Vector2(22,26),true)
 s.entities[vehicle].hp-=100
 var hp:float=s.entities[vehicle].hp
 var money:float=s.money[0]
 for frame in range(120):s.step(1.0/30)
 check(s.entities[vehicle].hp==hp and s.money[0]==money,"nearby repair has no passive healing or idle monetary drain")
 print("LATEST_RULES_GAMEPLAY ",JSON.stringify({"checks":checks,"failures":failures}))
 for failure in failures:push_error(failure)
 quit(0 if failures.is_empty() else 1)
