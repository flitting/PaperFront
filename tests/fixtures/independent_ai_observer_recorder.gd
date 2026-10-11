extends RefCounted
var local_calls := 0
func record(observation: Dictionary,memory: Dictionary) -> Dictionary:
	local_calls+=1
	memory.calls=int(memory.get("calls",0))+1
	memory.recorder_only=true
	memory.team=observation.team
	memory.last_home=observation.home
	var result: Dictionary={"team":observation.team,"time":observation.time,"money":observation.money,"home":observation.home,"nested":{"positions":[observation.own[0].pos,Vector2(1.25,-2.5)]},"own_state":observation.own[0].get("state","")}
	# Recorder edits are local analysis, never game actions or policy memory.
	observation.money=-987654.0
	observation.rules.economy.initial_money=-987654.0
	observation.own[0].hp=-987654.0
	observation.own[0].queue.append({"spec":"recorder-forged"})
	return result
