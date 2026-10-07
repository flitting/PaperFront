extends SceneTree
const Sim=preload("res://tests/rule_test_simulation.gd")
const Rules=preload("res://scripts/rules_loader.gd")
var checks:=0
var failures:Array[String]=[]
var rules:Dictionary
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
func fixture():
	var sim=Sim.new()
	sim.setup_multiteam(rules,"dev",7,["iron","kestrel"],false,[Vector2(6,40),Vector2(42,6)])
	for z in range(sim.map.size):
		for x in range(sim.map.size):sim.map.terrain[z][x]=0;sim.map.heights[z][x]=0.0
	sim.mines.clear();sim.bridges.clear();sim.ruins.clear();sim._refresh_mine_spatial();sim._refresh_ruin_spatial();sim._prepare_terrain_cache()
	sim._spawn(0,"iron_power",Vector2(6.5,27.5),true)
	var refinery:int=sim._spawn(0,"iron_refinery",Vector2(17,39),true)
	sim.entities[refinery].gift_pending=false
	var barracks:int=sim._spawn(0,"iron_barracks",Vector2(17.5,29.5),true)
	return {"sim":sim,"barracks":barracks}
func plan_production(sim)->void:
	sim.AIController._produce(sim,0,"iron",sim.AIController.SETTINGS.normal)
func _initialize()->void:call_deferred("run")
func run()->void:
	rules=Rules.load_rules()
	if rules.is_empty():push_error("Invalid rules");quit(1);return
	var ctx:Dictionary=fixture()
	var sim=ctx.sim
	var barracks:Dictionary=sim.entities[ctx.barracks]
	var rifle_cost:float=float(rules.units.iron_rifle.cost)
	var initial:float=float(rules.buildings.iron_factory.cost)
	sim.money[0]=initial
	plan_production(sim);plan_production(sim)
	check(barracks.queue.size()==2 and barracks.queue.all(func(order):return order.spec=="iron_rifle"),"startup selects two actual rifle orders before unarmed engineer")
	check(is_equal_approx(sim.money[0],initial-2*rifle_cost),"both rifle orders pay their full normal costs from the factory reserve")
	check(sim._unit_spec_count(0,"iron_rifle")==2,"queued rifles count toward the two-guard minimum")
	for _i in range(8):plan_production(sim)
	check(barracks.queue.size()==2 and is_equal_approx(sim.money[0],initial-2*rifle_cost),"repeated planner ticks neither duplicate nor charge additional guards")
	for _tick in range(200):sim.step(.1)
	var guards:Array=sim.entities.values().filter(func(e):return e.spec=="iron_rifle" and float(e.hp)>0 and not bool(e.get("emerging",false)))
	check(guards.size()==2,"both queued guards really complete normal production and walk out")
	check(guards.all(func(e):return not str(sim.data_for(e.spec).get("weapon","")).is_empty()),"produced mine guards carry actual combat weapons")
	check(is_equal_approx(sim.money[0],initial-2*rifle_cost) and is_zero_approx(sim.statistics.teams[0].funds_earned),"guard delivery uses no artificial income or post-production refund")
	plan_production(sim)
	check(sim._unit_spec_count(0,"iron_engineer")==1 and barracks.queue.size()==1 and barracks.queue[0].spec=="iron_engineer","one normally paid engineer follows the armed guard minimum")
	for _i in range(8):plan_production(sim)
	check(sim._unit_spec_count(0,"iron_engineer")==1,"a pending engineer prevents duplicate startup engineer orders")
	check(is_equal_approx(sim.money[0],initial-2*rifle_cost-float(rules.units.iron_engineer.cost)),"the single engineer costs its configured price exactly once")
	var budget:Dictionary=fixture()
	budget.sim.money[0]=float(rules.buildings.iron_factory.cost)
	budget.sim._spawn(0,"iron_tower",Vector2(26.5,28.5),true)
	budget.sim.AIController._build(budget.sim,0,"iron")
	check(budget.sim.order_for_team(0,"normal").is_empty(),"first factory waits if it would consume the two-guard purchase budget")
	check(budget.sim.order_for_team(0,"defense").is_empty(),"one existing tower prevents a second pre-factory tower")
	check(is_equal_approx(budget.sim.money[0],float(rules.buildings.iron_factory.cost)),"deferred optional purchases leave funds untouched")
	var ready:Dictionary=fixture()
	ready.sim.money[0]=float(rules.buildings.iron_factory.cost)+2*rifle_cost
	ready.sim.AIController._build(ready.sim,0,"iron")
	check(ready.sim.order_for_team(0,"normal").get("spec","")=="iron_factory","factory remains purchasable when full price plus guard funding exists")
	check(is_equal_approx(ready.sim.money[0],2*rifle_cost),"factory spends only its normal price and leaves the exact guard budget")
	plan_production(ready.sim);plan_production(ready.sim)
	check(ready.sim._unit_spec_count(0,"iron_rifle")==2 and is_zero_approx(ready.sim.money[0]),"the remaining budget pays both guards while factory construction proceeds")
	var tank_reserve:Dictionary=fixture()
	tank_reserve.sim._spawn(0,"iron_factory",Vector2(31.5,38.5),true)
	tank_reserve.sim._spawn(0,"iron_harvester",Vector2(35.5,43.5),true)
	tank_reserve.sim.money[0]=float(rules.units.iron_tank.cost)
	plan_production(tank_reserve.sim)
	check(tank_reserve.sim._unit_spec_count(0,"iron_tank")==1 and tank_reserve.sim._unit_spec_count(0,"iron_rifle")==0 and is_zero_approx(tank_reserve.sim.money[0]),"after factory completion guards preserve the first tank's actual purchase budget")
	print("IRON_STARTUP_GUARD ",JSON.stringify({"checks":checks,"failures":failures,"rifle_cost":rifle_cost,"rifle_build_time":rules.units.iron_rifle.build_time}))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
