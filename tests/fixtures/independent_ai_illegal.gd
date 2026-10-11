extends RefCounted
func decide(observation: Dictionary,memory: Dictionary) -> Dictionary:
	var enemy_hq: int=2 if int(observation.team)==0 else 1
	return {"shared_economy":false,"shared_tactics":false,"reason":"illegal ownership probe","commands":[
		{"action":"sell","id":enemy_hq,"confirmed":true},
		{"action":"produce","id":enemy_hq,"spec":str(observation.faction)+"_rifle"},
		{"action":"rally","id":enemy_hq,"pos":[80,96]},
		{"action":"cancel_production","id":enemy_hq,"index":0},
		{"action":"issue","id":enemy_hq,"kind":"move","pos":[80,96]},
		{"action":"build","team":1-int(observation.team),"spec":str(observation.faction)+"_power"}
	]}
