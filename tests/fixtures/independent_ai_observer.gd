extends RefCounted
var local_calls := 0
func decide(observation: Dictionary,memory: Dictionary) -> Dictionary:
	local_calls+=1
	memory.calls=int(memory.get("calls",0))+1
	memory.team=observation.team
	memory.faction=observation.faction
	memory.money_seen=observation.money
	memory.enemy_count=observation.visible_enemies.size()
	memory.own_ids=[]
	for entity: Dictionary in observation.own:memory.own_ids.append(entity.id)
	# A module can filter/mutate its private input without changing the game
	# or the other module's same-time observation and official receipt.
	observation.money=-123456.0
	observation.rules.economy.initial_money=-123456.0
	if not observation.own.is_empty():
		observation.own[0].hp=-123456.0
		observation.own[0].queue.append({"spec":"forged"})
	return {"shared_economy":false,"shared_tactics":false,"commands":[],"reason":"observer"}
