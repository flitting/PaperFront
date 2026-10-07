extends RefCounted

## Explicit single-bay service, paid only for health actually restored.
static func error(sim, unit_id: int, depot_id: int) -> String:
	var unit: Dictionary=sim.entities.get(unit_id,{})
	var depot: Dictionary=sim.entities.get(depot_id,{})
	if unit.is_empty() or unit.get("kind","")!="unit" or float(unit.hp)<=0 or sim.Transport.is_loaded(unit): return "请选择己方存活车辆"
	var spec: Dictionary=sim.data_for(unit.spec)
	if spec.get("domain","ground")!="ground" or spec.get("armor_class","")!="armored": return "修理厂维修地面车辆；飞机请返回机场"
	if depot.is_empty() or depot.get("kind","")!="building" or int(depot.team)!=int(unit.team) or float(depot.hp)<=0 or float(depot.construct_remaining)>0 or sim.data_for(depot.spec).get("role","")!="repair": return "需要己方已完成修理厂"
	if float(sim.data_for(depot.spec).get("service_rate",0))<=0: return "该设施没有进厂维修泊位"
	if float(unit.hp)>=sim.max_hp(unit)-.001: return "车辆无需维修"
	return ""

static func step(sim, unit: Dictionary, command: Dictionary, delta: float) -> void:
	var target: int=int(command.target)
	var problem: String=error(sim,int(unit.id),target)
	if not problem.is_empty(): sim._finish_command(unit); return
	var depot: Dictionary=sim.entities[target]
	sim.RefineryDocking.approach(sim,unit,depot,delta,"repair")
