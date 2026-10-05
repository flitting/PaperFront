extends SceneTree

const Sim=preload("res://tests/rule_test_simulation.gd")

func _initialize()->void:
	var config:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/rules.json"))
	if not config is Dictionary:push_error("rules unavailable");quit(1);return
	var sim=Sim.new()
	sim.setup_multiteam(config,"forest",19,["rivet","kestrel","iron","sky"],false,[],Callable(),{"players":4})
	for index in range(600):
		var team:int=index%4
		var spec:String=sim.factions[team]+"_rifle"
		var pos:=Vector2(14.0+float(index%30)*9.5,14.0+float(index/30)*14.0)
		sim._spawn(team,spec,pos,true)
	var before:int=Time.get_ticks_usec()
	for sample in range(5):sim.TeamVision.refresh(sim,true)
	var refresh_us:int=Time.get_ticks_usec()-before
	before=Time.get_ticks_usec()
	var visible_count:int=0
	for index in range(1000):
		if sim.position_visible_to(index%4,Vector2(10+float(index%32)*9.0,10+float(index/32)*9.0)):visible_count+=1
	var query_us:int=Time.get_ticks_usec()-before
	var report:Dictionary={"entities":sim.entities.size(),"teams":4,"refresh_mean_us":refresh_us/5.0,"queries":1000,"query_mean_us":query_us/1000.0,"visible_queries":visible_count}
	print("TEAM_VISION_PERFORMANCE ",JSON.stringify(report))
	if sim.entities.size()<600 or visible_count<=0:push_error("vision stress fixture invalid");quit(1)
	else:quit(0)
