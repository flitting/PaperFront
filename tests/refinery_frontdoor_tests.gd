extends SceneTree
const Sim=preload("res://tests/rule_test_simulation.gd")
var config:Dictionary
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label)
func fixture():
 var s=Sim.new()
 s.setup_multiteam(config,"dev",7,["kestrel","rivet"],false)
 for z in range(s.map.size):
  for x in range(s.map.size):s.map.terrain[z][x]=0;s.map.heights[z][x]=0
 s.mines.clear();s.bridges.clear();s.ruins.clear();s._refresh_ruin_spatial();s._refresh_mine_spatial();s._prepare_terrain_cache()
 s.money.assign([100000.0,100000.0]);s._nav_dirty=true
 return s
func _initialize():call_deferred("run")
func run():
 config=RulesLoader.load_rules()
 for native in [false,true]:
  var s=fixture();s.native_unit_dispatch_enabled=native;s.native_movement_enabled=native;s.native_geometry_enabled=native
  var ref:int=s._spawn(0,"kestrel_refinery",Vector2(23.5,21.5),true)
  s.entities[ref].gift_pending=false
  var miner:int=s._spawn(0,"kestrel_harvester",Vector2(23.5,26.0),true)
  s.entities[miner].cargo=500.0
  var entrance:Vector2=s._refinery_approach(s.entities[miner],s.entities[ref])
  check(entrance.x==s.entities[ref].pos.x and entrance.y>s.entities[ref].pos.y,"returning miner always chooses actual central +Z front door")
  var beginning:float=s.money[0]
  var inside_seen:=false;var inside_delivery:=false;var exiting_seen:=false;var deliveries:=0
  for frame in range(300):
   s.step(1.0/30)
   var u:Dictionary=s.entities[miner]
   if u.has("refinery_docking"):
    var phase:String=u.refinery_docking.phase
    if phase=="unload":
     inside_seen=true
     check(u.pos.y<s.entities[ref].pos.y+float(config.buildings.kestrel_refinery.size)*.5,"unloading is inside building, not immediate outside deposit")
    if phase=="exit":exiting_seen=true
   for event in s.events:
    if event.kind=="delivery":
     deliveries+=1;inside_delivery=bool(event.get("inside",false))
   s.events.clear()
  check(inside_seen and inside_delivery and exiting_seen,"actual front door enter/unload/exit stages execute")
  check(deliveries==1 and s.money[0]==beginning+500,"cargo credited exactly once after timed inside unloading")
  check(not s.entities[miner].has("refinery_docking") and (s.entities[miner].pos as Vector2).distance_to(entrance)>=1.50 and s.entities[miner].pos.y>entrance.y,"miner drives outside and clears doorway before regular pathing resumes")
  check(float(s.entities[ref].production_door)==0,"front shutter closes after miner exits")
  check(is_equal_approx(s.entities[miner].radius,float(config.units.kestrel_harvester.logical_size)*.5),"front door retains the configured physical footprint")
 print("REFINERY_FRONTDOOR ",JSON.stringify({"checks":checks,"failures":failures}))
 for failure in failures:push_error(failure)
 quit(0 if failures.is_empty() else 1)
