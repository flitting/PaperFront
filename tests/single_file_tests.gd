extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Rules=preload("res://scripts/rules_loader.gd")
func _initialize():
	var sim=Sim.new();sim.setup(Rules.load_rules(),"dev",7,"rivet",false)
	for z in range(48):
		for x in range(48):
			sim.map.terrain[z][x]=0;sim.map.heights[z][x]=0.0
	sim.mines.clear();sim.bridges.clear();sim.ruins.clear();sim._refresh_ruin_spatial()
	for id in sim.entities.keys():sim._kill_entity(id,false)
	sim.debug_spawn(0,"rivet_hq",Vector2(4,44));sim.debug_spawn(1,"kestrel_hq",Vector2(44,44))
	for z in range(48):
		if z in ([23] if "--infantry" in OS.get_cmdline_user_args() else [23,24]):continue
		for x in range(21,27):sim.map.terrain[z][x]=4
	sim._prepare_terrain_cache();sim._nav_initialized=false;sim._rebuild_nav()
	var groups:Array=[[],[]]
	var both:bool="--both" in OS.get_cmdline_user_args()
	var count:int=96 if "--large" in OS.get_cmdline_user_args() else 24
	for side in range(2 if both else 1):
		for i in range(count):
			var p:=Vector2(4+(i%8)*1.9,8+(i/8)*1.9) if count>24 else (Vector2(5+(i%4)*2,18+(i/4)*2) if side==0 else Vector2(35+(i%4)*2,18+(i/4)*2))
			var id:int=sim.debug_spawn(0,"rivet_engineer" if "--infantry" in OS.get_cmdline_user_args() else "rivet_assault" if "--heavy" in OS.get_cmdline_user_args() else "rivet_tank",p)
			groups[side].append(id)
		sim.issue(groups[side],"move",Vector2(29 if "--near" in OS.get_cmdline_user_args() else 38,24) if side==0 else Vector2(10,24))
	var cleared: Dictionary={}
	var unreachable:=0
	var overlaps:=0
	for t in range(18000 if count>24 else 10800):
		sim.step(1.0/30);sim.events.clear()
		for side in range(2):
			for id in groups[side]:
				if (sim.entities[id].pos.x>27.95 if side==0 else sim.entities[id].pos.x<20.05):cleared[id]=true
		for e in sim.entities.values():
			if e.kind=="unit" and e.state=="unreachable":unreachable+=1
		if t%300==0:
			var reached:=0
			for side in range(2):
				for id in groups[side]:
					if (sim.entities[id].pos.x>29 if side==0 else sim.entities[id].pos.x<19):reached+=1
			print("T=",t/30," passed=",reached," gates=",sim.group_navigation.gates.size()," grants=",sim.group_navigation.grants)
	var passed:Array=[0,0]
	var remaining:Array=[]
	for side in range(2):
		for id in groups[side]:
			var e:Dictionary=sim.entities[id]
			if cleared.has(id) and e.commands.is_empty():passed[side]+=1
			else:remaining.append([id,e.pos,e.state,e.path,e.get("traffic_strict"),e.get("yield_goal")])
	for gate in sim.group_navigation.gates:print("GATE ",gate)
	for e in sim.entities.values():
		if e.kind=="unit" and e.pos.x>27 and e.pos.x<33:print("MOUTH ",e.id," ",e.pos," ",e.state," ",e.commands," rank ",e.get("traffic_rank")," strict ",e.get("traffic_strict")," path ",e.path," alpha ",e.alpha)
	print("SINGLE_FILE ",passed," remaining=",remaining," unreachable_frames=",unreachable," plans=",sim.group_navigation.plans)
	quit(0 if passed[0]==count and passed[1]==(count if both else 0) and unreachable==0 else 1)
