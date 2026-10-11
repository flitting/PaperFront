extends RefCounted
static func multiplier(sim,key:String,default:float)->float:return float(sim.rules.get("experience",{}).get(key,default))
static func max_hp(sim,e:Dictionary)->float:
	return float(sim.data_for(e.spec).hp)*(multiplier(sim,"max_hp_multiplier",1.15) if bool(e.get("veteran",false)) and e.kind=="unit" else 1.0)
static func armor(sim,e:Dictionary)->float:
	return float(sim.data_for(e.spec).get("armor",0))*(multiplier(sim,"armor_multiplier",1.1) if bool(e.get("veteran",false)) and e.kind=="unit" else 1.0)
static func weapon(sim,e:Dictionary,id:String)->Dictionary:
	var w:Dictionary=sim.rules.weapons.get(id,{}).duplicate()
	if w.is_empty():return w
	var carrier:Dictionary=sim.entities.get(int(e.get("carrier_id",-1)),{})
	if bool(sim.data_for(e.spec).get("carrier_plane",false)) and bool(carrier.get("veteran",false)):
		w.damage=float(w.damage)*multiplier(sim,"damage_multiplier",1.1)
	if not bool(e.get("veteran",false)):return w
	w.damage=float(w.damage)*multiplier(sim,"damage_multiplier",1.1)
	w.interval=float(w.interval)/multiplier(sim,"attack_speed_multiplier",1.1)
	w.range=float(w.range)*multiplier(sim,"range_multiplier",1.08)
	return w
static func active(sim)->bool:
	for e in sim.entities.values():
		if bool(e.get("veteran",false)):return true
	return false
static func destroyed(sim,victim:Dictionary,cause:Dictionary)->void:
	var killer:Dictionary=sim.entities.get(int(cause.get("source",-1)),{})
	if not killer.is_empty() and sim.entities.has(int(killer.get("carrier_id",-1))):killer=sim.entities[int(killer.carrier_id)]
	if killer.is_empty() or killer.kind!="unit" or float(killer.hp)<=0 or int(killer.team)==int(victim.team):return
	var info:Dictionary=sim.data_for(victim.spec)
	var value:float=float(info.get("cost",0))
	if victim.has("construction"):value=float(victim.construction.get("spent",0))
	# This reward affects experience only. Economic kill/loss telemetry keeps
	# the target's original value, and legacy rule snapshots default to 1x.
	if victim.get("kind", "") == "unit" and bool(victim.get("veteran", false)):
		value *= multiplier(sim,"veteran_kill_experience_multiplier",1.0)
	killer.experience_value=float(killer.get("experience_value",0))+value
	var own_cost:float=float(sim.data_for(killer.spec).get("experience_cost",sim.data_for(killer.spec).cost))
	if bool(killer.get("veteran",false)) or own_cost<=0 or float(killer.experience_value)<=own_cost*multiplier(sim,"threshold_cost_multiplier",3):return
	var before:float=max_hp(sim,killer)
	killer.veteran=true
	killer.max_hp=max_hp(sim,killer)
	killer.hp=minf(max_hp(sim,killer),float(killer.hp)+max_hp(sim,killer)-before)
	sim.events.append({"kind":"promotion","id":killer.id,"team":killer.team,"pos":killer.pos})
static func step(sim,delta:float)->void:
	for e in sim.entities.values():
		if e.kind=="unit" and bool(e.get("veteran",false)) and float(e.hp)>0:
			e.hp=minf(max_hp(sim,e),float(e.hp)+max_hp(sim,e)*multiplier(sim,"regen_fraction_per_second",.005)*delta)
