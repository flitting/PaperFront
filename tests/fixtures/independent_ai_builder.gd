extends RefCounted
func decide(observation: Dictionary,memory: Dictionary) -> Dictionary:
	memory.calls=int(memory.get("calls",0))+1
	memory.team=observation.team
	memory.faction=observation.faction
	memory.money_seen=observation.money
	var commands: Array=[]
	if not bool(memory.get("sent",false)):
		commands.append({"action":"build","spec":str(observation.faction)+"_power"})
		memory.sent=true
	return {"shared_economy":false,"shared_tactics":false,"commands":commands,"settings":{"wave":3,"attack_gap":12},"profile":{"infantry_limit":4},"reason":"builder"}
