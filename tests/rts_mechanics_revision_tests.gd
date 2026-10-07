extends SceneTree
const Sim = preload("res://tests/rule_test_simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
var checks := 0
var failures: Array[String] = []
var config: Dictionary
var evidence: Dictionary = {}
func check(ok: bool, label: String) -> void:
 checks += 1
 if not ok: failures.append(label)
func fixture(factions: Array[String] = ["rivet","sky"]):
 var sim = Sim.new()
 sim.setup_multiteam(config,"dev",7,factions,false)
 for z in range(sim.map.size):
  for x in range(sim.map.size):
   sim.map.terrain[z][x]=0; sim.map.heights[z][x]=0.0
 sim.mines.clear(); sim.bridges.clear(); sim.ruins.clear()
 sim._refresh_ruin_spatial(); sim._refresh_mine_spatial(); sim._prepare_terrain_cache()
 sim.money.assign([100000.0,100000.0]); sim._nav_dirty=true
 return sim
func tick(sim, seconds: float) -> void:
 for _frame in range(ceili(seconds*30)): sim.step(1.0/30.0)
func _initialize(): call_deferred("run")
func run():
 config=Rules.load_rules()
 check(not config.is_empty(), "strict production rules and assets validate")
 if config.is_empty(): print(Rules.errors); quit(1); return
 values(); drill(); traits(); energy(); production(); aircraft(); capture(); income(); duels(); save_drill(); mining_arrival_band()
 evidence.checks=checks; evidence.failures=failures
 var file=FileAccess.open("res://artifacts/rts_revision_latest/mechanics.json",FileAccess.WRITE)
 file.store_string(JSON.stringify(evidence,"\t")); file.close()
 print("RTS_MECHANICS ",JSON.stringify(evidence))
 for failure in failures: push_error(failure)
 quit(0 if failures.is_empty() else 1)
func values():
 for id in config.units:
  var d:Dictionary=config.units[id]
  var expected:float=float(d.get("logical_size",1))*.5
  check(is_equal_approx(d.radius,expected),id+" exact logical radius")
  if not str(d.weapon).is_empty(): check(float(d.vision_radius)>=float(config.weapons[d.weapon].range),id+" sight covers attack range")
  if d.domain=="naval": check(not d.crush and not d.rail_only,id+" no ground-only trait")
 for id in config.buildings:
  var d:Dictionary=config.buildings[id]
  if d.role!="hq": check(d.size<8,id+" smaller than main base")
  check(not d.has("overcharge_radius"),id+" has no removed overcharge aura")
  if d.role=="repair":check(float(d.get("service_rate",0))>0,id+" has the requested dedicated repair service")
 check(not config.units.has("rivet_harvester") and not config.buildings.has("rivet_refinery"),"only heavy faction replaces conventional mining")
 check(config.units.kestrel_rifle.hp>config.units.iron_rifle.hp and config.units.rivet_rifle.hp>config.units.sky_rifle.hp,"elite/heavy infantry health advantage")
 check(config.units.kestrel_tank.hp<config.units.iron_tank.hp and config.units.kestrel_tank.hp<config.units.rivet_tank.hp,"cheap canonical tank is not stronger individually")
 check(config.units.kestrel_tank.cost<config.units.iron_tank.cost and config.units.kestrel_tank.build_time<config.units.iron_tank.build_time,"canonical cheap fast armor")
 check(config.buildings.kestrel_tech.cost>config.buildings.iron_tech.cost and config.buildings.kestrel_tech.build_time>config.buildings.iron_tech.build_time,"slow costly high-tech canonical unlock")
 check(config.units.kestrel_scout.vision_radius>=config.units.kestrel_tank.vision_radius*1.7,"scout clearly superior sight")
func drill():
 var sim=fixture()
 sim.rules.economy.finite_ore=true
 sim.mines.append({"pos":Vector2(24.5,24.5),"capacity":3000.0,"amount":1700.0,"miner":-1})
 sim._spawn(0,"rivet_power",Vector2(15,15),true)
 var eng:int=sim._spawn(0,"rivet_engineer",Vector2(24.5,26.5),true)
 check(sim.build(0,"rivet_drill",eng).is_empty(),"drill uses normal engineer construction purchase")
 check(sim.place_building(0,Vector2(24.5,24.5)).is_empty(),"drill legal on ore despite ordinary ore collision")
 tick(sim,1)
 var drill_id:int=int(sim.mines[0].get("drill",-1))
 check(drill_id>0 and sim.entities.has(drill_id) and sim.entities[drill_id].has("construction"),"real scaffold claims separate original mineral")
 if drill_id<0:return
 check(not sim._mine_available(0,-1),"other harvester excluded during construction")
 tick(sim,20)
 check(not sim.entities[drill_id].has("construction") and sim.entities[drill_id].construct_remaining==0,"armed engineer finishes paid existing scaffold mechanism")
 var before:float=sim.money[0]
 var amount:float=sim.mines[0].amount
 tick(sim,2)
 check(sim.money[0]>before and sim.mines[0].amount<amount,"drill delivers authoritative income and conserves finite ore")
 var remaining:float=sim.mines[0].amount
 sim._add_damage(drill_id,100000);sim._apply_damage();sim._damage.clear()
 check(int(sim.mines[0].drill)==-1 and is_equal_approx(sim.mines[0].amount,remaining) and sim._mine_available(0,-1),"destroying drill releases exactly unchanged remaining mineral")
 check(sim.mines.size()==1,"drill destruction never duplicates ore")
 evidence.drill_remaining=remaining
func traits():
 var sim=fixture(["iron","rivet"])
 var inf:int=sim._spawn(0,"iron_rifle",Vector2(24,24),true)
 var tank:int=sim._spawn(0,"iron_tank",Vector2(26,24),true)
 var air:int=sim._spawn(0,"iron_fighter",Vector2(28,24),true)
 var eng:int=sim._spawn(1,"rivet_engineer",Vector2(34,24),true)
 for id in [inf,tank,air,eng]:sim.entities[id].hp-=30;sim.entities[id].last_damage_time=0;sim.entities[id].last_attack_time=0
 sim.time=7
 var before:float=sim.entities[inf].hp
 sim.FactionTraits.step_regeneration(sim,1)
 check(sim.entities[inf].hp==before,"iron infantry do not regenerate")
 check(sim.entities[tank].hp>config.units.iron_tank.hp-30,"iron tank regenerates")
 check(sim.entities[air].hp>config.units.iron_fighter.hp-30,"iron aircraft regenerates")
 check(sim.entities[eng].hp>config.units.rivet_engineer.hp-30 and not config.units.rivet_engineer.weapon.is_empty(),"heavy engineer has actual weapon and independent self heal")
func energy():
 var sim=fixture(["sky","iron"])
 var laser:int=sim._spawn(0,"sky_tank",Vector2(24,24),true)
 var target:int=sim._spawn(1,"iron_tank",Vector2(29,24),true)
 sim.entities[laser].alpha=0;sim.entities[laser].turret_alpha=0
 sim._fire(sim.entities[laser],target)
 check(sim.projectiles.is_empty() and sim._damage.has(target),"point laser is immediate ray damage with no traveling shell")
 sim._apply_damage();sim._damage.clear()
 var beam:int=sim._spawn(0,"sky_pulse",Vector2(24,27),true)
 sim.entities[beam].turret_alpha=rad_to_deg((sim.entities[target].pos-sim.entities[beam].pos).angle())
 sim._fire(sim.entities[beam],target)
 var health:float=sim.entities[target].hp
 check(sim.entities[beam].has("beam") and not sim._damage.has(target),"continuous beam creates timed damage channel")
 sim.BeamWeapons.step(sim,.3);sim._apply_damage();sim._damage.clear()
 var lost:float=health-sim.entities[target].hp
 check(lost>0 and lost<float(config.weapons.sky_pulse.damage),"beam settles partial continuous damage over time")
 sim.entities[target].pos=Vector2(45,45);sim.BeamWeapons.step(sim,.3)
 check(not sim.entities[beam].has("beam"),"beam cancels when target leaves effective range")
 var emp:int=sim._spawn(0,"sky_disruptor",Vector2(24,20),true)
 sim.entities[target].pos=Vector2(29,20);sim._rebuild_spatial();sim.entities[emp].turret_alpha=0
 sim._fire(sim.entities[emp],target);sim._damage.clear()
 check(float(sim.entities[target].get("emp_until",0))>sim.time,"EMP actually sets control duration")
 var old:Vector2=sim.entities[target].pos
 sim.issue([target],"move",old+Vector2(5,0));sim._step_unit(sim.entities[target],.5)
 check(sim.entities[target].pos==old and sim.entities[target].state=="emp","EMP blocks movement and weapon service")
 sim.time+=4;sim._step_unit(sim.entities[target],.5)
 check(sim.entities[target].state!="emp","EMP control restores after duration")
func production():
 var sim=fixture(["kestrel","rivet"])
 var factory:int=sim._spawn(0,"kestrel_factory",Vector2(22.5,22.5),true)
 var b:Dictionary=sim.entities[factory]
 var blocked_power:Dictionary=sim.data_for("kestrel_power")
 check(not sim._building_site_error(0,blocked_power,Vector2(22.5,28)).is_empty(),"future building cannot block an existing real producer doorway")
 sim._spawn(0,"kestrel_power",Vector2(35,32),true)
 check(not sim._building_site_error(0,sim.data_for("kestrel_factory"),Vector2(35,27)).is_empty(),"new producer placement reserves a clear central doorway")
 check(sim.produce(factory,"kestrel_tank").is_empty(),"actual production order accepted")
 b.queue[0].remaining=0
 sim._step_building(b,.1,1)
 var unit:Dictionary={}
 for e in sim.entities.values():
  if e.spec=="kestrel_tank":unit=e
 check(not unit.is_empty() and bool(unit.get("emerging",false)) and (unit.pos as Vector2).distance_to(b.pos)<float(config.buildings.kestrel_factory.size)*.5,"tank is created inside real doorway before driving out")
 if unit.is_empty():return
 var start:Vector2=unit.pos
 b.emp_until=sim.time+2
 sim._step_unit(unit,.5)
 check(unit.pos==start and unit.state=="waiting_exit","EMP suspends building door and pending physical exit")
 b.emp_until=0
 tick(sim,2)
 check(not unit.emerging and unit.pos!=start,"tank drives physically out before ordinary pathing")
 tick(sim,1)
 check(float(b.production_door)==0,"factory closes after unit exit")
func aircraft():
 var sim=fixture(["kestrel","rivet"])
 sim._spawn(0,"kestrel_power",Vector2(10,18),true)
 var field:int=sim._spawn(0,"kestrel_airfield",Vector2(24.5,24.5),true)
 var planes:Array[int]=[]
 for i in range(4):
  var err:String=sim.produce(field,"kestrel_fighter")
  check(err.is_empty(),"airport order "+str(i))
  sim.entities[field].queue[0].remaining=0
  sim._step_building(sim.entities[field],.1,1)
 for e in sim.entities.values():
  if e.spec=="kestrel_fighter":planes.append(e.id)
 tick(sim,1)
 check(planes.size()==4,"four real parking places support four aircraft")
 for i in range(planes.size()):
  check(not sim.entities[planes[i]].airborne and sim.entities[planes[i]].state=="parked","produced aircraft defaults to idle parked")
  for j in range(i):check((sim.entities[planes[i]].pos as Vector2).distance_to(sim.entities[planes[j]].pos)>=sim._radius(sim.entities[planes[i]])+sim._radius(sim.entities[planes[j]]),"parked planes never overlap")
 check(not sim.produce(field,"kestrel_fighter").is_empty(),"full airport rejects fifth reservation")
 if planes.is_empty():return
 var p:Dictionary=sim.entities[planes[0]]
 sim.issue([p.id],"move",Vector2(31,24));tick(sim,2)
 check(p.airborne and p.pos.distance_to(sim.entities[field].pos)>3,"parked aircraft takes off for a real command")
 sim.issue([p.id],"return",sim.entities[field].pos);tick(sim,10)
 check(not p.airborne and p.state=="parked","aircraft returns lands and stays parked after explicit service")
 sim.issue([p.id],"move",Vector2(31,24));tick(sim,14)
 check(not p.airborne and p.state=="parked","idle sortie automatically returns to a real parking bay")
func capture():
 var sim=fixture(["kestrel","rivet"])
 var eng:int=sim._spawn(0,"kestrel_engineer",Vector2(24,27),true)
 var tower:int=sim._spawn(1,"rivet_tower",Vector2(24.5,24.5),true)
 check(sim.capture_error(eng,tower).is_empty(),"engineer can capture defense tower")
 sim._step_capture(sim.entities[eng],{"target":tower},.1)
 check(sim.entities[tower].team==0 and sim.entities[tower].captured,"capture updates authoritative tower ownership")
 var wall:int=sim._spawn(1,"rivet_wall",Vector2(28.5,24.5),true)
 check(not sim.capture_error(eng,wall).is_empty(),"wall capture rejected")
func income():
 var sim=fixture(["kestrel","rivet"])
 var ref:int=sim._spawn(0,"kestrel_refinery",Vector2(24,18),true)
 sim.entities[ref].gift_pending=false
 sim.mines.append({"pos":Vector2(24,35),"capacity":3000.0,"amount":3000.0,"miner":-1})
 sim._refresh_mine_spatial()
 var miner:int=sim._spawn(0,"kestrel_harvester",Vector2(24,32.95),true)
 sim.issue([miner],"harvest",sim.mines[0].pos,0)
 var money:float=sim.money[0]
 tick(sim,300)
 var rate:float=(sim.money[0]-money)/300
 evidence.harvester_reference_income_per_second=rate
 evidence.drill_income_per_second=config.economy.drill_income_rate
 check(rate>0,"full long-term mining hauling unloading loop delivers actual funds")
 check(absf(rate-float(config.economy.drill_income_rate))/maxf(rate,.001)<.25,"drill income within 25 percent of actual full-cycle long-term reference")

func duels():
 evidence.duels=[]
 for specs in [["kestrel_rifle","iron_rifle","kestrel"],["rivet_rifle","sky_rifle","rivet"],["kestrel_tank","rivet_tank","rivet"],["kestrel_tank","iron_tank","iron"],["sky_fighter","rivet_fighter","sky"]]:
  var factions:Array[String]=[str(specs[0]).get_slice("_",0),str(specs[1]).get_slice("_",0)]
  var sim=fixture(factions)
  var a:int=sim._spawn(0,str(specs[0]),Vector2(21,24),true)
  var b:int=sim._spawn(1,str(specs[1]),Vector2(25.5,24),true)
  sim.entities[a].alpha=0;sim.entities[a].turret_alpha=0
  sim.entities[b].alpha=180;sim.entities[b].turret_alpha=180
  for frame in range(60*30):
   sim.step(1.0/30.0)
   if not sim.entities.has(a) or not sim.entities.has(b):break
  var winner:String=factions[0] if sim.entities.has(a) and not sim.entities.has(b) else (factions[1] if sim.entities.has(b) and not sim.entities.has(a) else "draw")
  evidence.duels.append({"a":specs[0],"b":specs[1],"winner":winner,"seconds":sim.time})
  check(winner==str(specs[2]),"actual same-tier duel respects faction role: "+str(specs))

func save_drill():
 var sim=Sim.new()
 sim.setup_multiteam(config,"dev",7,["rivet","sky"],false)
 sim.rules.economy.finite_ore=true
 sim.mines[0].amount=1532.0
 var center:Vector2=sim.mines[0].pos
 var drill_id:int=sim._spawn(0,"rivet_drill",Vector2(floorf(center.x)+.5,floorf(center.y)+.5),true)
 var path:String="/tmp/paper_rts_drill_state.save"
 check(sim.save_game(path).is_empty(),"occupied finite mineral and drill can save")
 var restored=Sim.new()
 var error:String=restored.load_game(path)
 check(error.is_empty() and restored.mines[0].drill==drill_id and restored.mines[0].amount==1532.0,"drill and original remaining ore restore without reset: "+error)

func mining_arrival_band():
 var sim=fixture(["kestrel","rivet"])
 sim.mines.append({"pos":Vector2(24.5,24.5),"capacity":3000.0,"amount":3000.0,"miner":-1})
 sim._refresh_mine_spatial()
 var miner:int=sim._spawn(0,"kestrel_harvester",Vector2(22.07,24.5),true)
 sim.issue([miner],"harvest",sim.mines[0].pos,0)
 tick(sim,3)
 check(float(sim.entities[miner].cargo)>0,"configured-footprint miner leaves previous arrival dead band and actually starts mining")
 var goal:Vector2=sim.entities[miner].get("mining_goal",Vector2.INF)
 check(goal.is_finite() and goal.distance_to(sim.mines[0].pos)+maxf(.25,sim._radius(sim.entities[miner])*.4)<sim._radius(sim.entities[miner])+float(config.economy.harvester_mining_margin),"mining approach includes actual move arrival allowance without expanding contact radius")
