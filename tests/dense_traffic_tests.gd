extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Rules=preload("res://scripts/rules_loader.gd")
func _initialize() -> void:
	var sim=Sim.new()
	sim.setup(Rules.load_rules(),"handmade",7,"rivet",false)
	for z in range(160):
		for x in range(160):
			sim.map.terrain[z][x]=0
			sim.map.heights[z][x]=0.0
	sim.mines.clear();sim.bridges.clear()
	if "ruins" in sim:sim.ruins.clear();sim._refresh_ruin_spatial()
	for id in sim.entities.keys():sim._kill_entity(id,false)
	sim.debug_spawn(0,"rivet_hq",Vector2(4,154))
	sim.debug_spawn(1,"kestrel_hq",Vector2(154,154))
	for z in range(160):
		if z>=76 and z<=85:continue
		for x in [79,80]:sim.map.terrain[z][x]=4
	sim._prepare_terrain_cache();sim._nav_initialized=false;sim._rebuild_nav()
	var groups: Array=[[],[]]
	for side in range(2):
		for i in range(128):
			var p:=Vector2(32+(i%16)*1.9,52+(i/16)*1.9) if side==0 else Vector2(104+(i%16)*1.9,94+(i/16)*1.9)
			var id: int=sim.debug_spawn(0,"rivet_tank" if i%3==0 else "rivet_engineer",p)
			if id>=0:groups[side].append(id)
		sim.issue(groups[side],"move",Vector2(120,58) if side==0 else Vector2(44,100))
	for t in range(9000):
		sim.step(1.0/30);sim.events.clear()
	var passed: Array=[0,0]
	var remaining: Array=[]
	for side in range(2):
		for id in groups[side]:
			var e: Dictionary=sim.entities[id]
			if (e.pos.x>86 if side==0 else e.pos.x<74):passed[side]+=1
			else:remaining.append([id,e.pos,e.state,e.get("stuck",0),e.get("yield_goal"),e.path.size()])
	sim.save_game("/tmp/dense-traffic-v2.pfront")
	print("BIDIRECTIONAL_256 ",passed," remaining ",remaining)
	quit(0 if passed[0]==128 and passed[1]==128 else 1)
