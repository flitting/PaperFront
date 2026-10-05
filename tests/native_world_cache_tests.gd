extends SceneTree
const Sim=preload("res://tests/rule_test_simulation.gd")
var checks:int=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok and failures.size()<12:failures.append(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var sim=Sim.new();sim.setup(RulesLoader.load_rules(),"dev",7,"rivet",false)
	var camera:=Camera3D.new();root.add_child(camera)
	camera.position=Vector3(24,30,54);camera.look_at(Vector3(24,0,29))
	var fast:=PaperWorld.new();var reference:=PaperWorld.new();reference.native_world_sync_enabled=false
	root.add_child(fast);root.add_child(reference)
	var ids:Array[int]=[]
	for i in range(16):ids.append(sim._spawn(i%2,["rivet","kestrel","iron","sky"][i%4]+"_tank",Vector2(18+i%4*2,25+i/4*2),true))
	for world in [fast,reference]:world.setup(sim,camera);world.configure_quality("performance");world.sync(.016,[])
	for frame in range(640):
		var slot:int=frame%ids.size()
		var removed:int=ids[slot]
		var replacement:Dictionary=sim.entities[removed].duplicate(true)
		replacement.id=10000+frame;replacement.alpha=wrapf(float(frame*17),-180,180);replacement.turret_alpha=wrapf(float(frame*13),-180,180)
		sim.entities.erase(removed);sim.entities[replacement.id]=replacement;ids[slot]=replacement.id
		if frame in [110,111]:
			fast.native_world_sync_enabled=false
			if frame==111:sim.entities[ids[3]].team=1-int(sim.entities[ids[3]].team)
		elif frame==112:fast.native_world_sync_enabled=true
		if frame==480:
			for world in [fast,reference]:world.setup(sim,camera);world.configure_quality("performance")
		for world in [fast,reference]:world.sync(.05,[])
		check(fast.models.size()==sim.entities.size() and not fast.models.has(removed),"retired models leave the render map")
		check(fast._submitted_transforms==reference._submitted_transforms,"replacement/compaction preserves submissions")
		for id in ids:check(fast.models[id].root.transform.is_equal_approx(reference.models[id].root.transform),"replacement/capture/setup preserves model pose")
	# Snapshot the public model order before simultaneous retirements, then
	# require the native cache to emit corpses in that exact order.
	var expected:Array=[]
	var dying:Array=ids.slice(0,5)
	for id in fast.models:
		if id in dying:expected.append(fast.models[id].render_parts[0].node.global_transform)
	for id in dying:sim.entities.erase(id)
	fast.data_corpses.clear();fast.sync(0.0,[])
	check(fast.data_corpses.size()==expected.size(),"simultaneous retirement keeps corpse count")
	for i in range(expected.size()):check(fast.data_corpses[i].transform==expected[i],"simultaneous retirement keeps insertion order")
	var externally_removed:int=ids[6]
	fast.models[externally_removed].root.queue_free();fast.models.erase(externally_removed)
	sim.entities.erase(externally_removed)
	await process_frame
	fast.sync(0.0,[])
	check(not fast.models.has(externally_removed),"external model removal does not revive a freed model as a corpse")
	var rebuilt:int=ids[7]
	var old_root=fast.models[rebuilt].root
	var old_root_id:int=old_root.get_instance_id()
	old_root.queue_free();fast.models.erase(rebuilt)
	await process_frame
	fast.sync(0.0,[])
	check(is_instance_valid(fast.models[rebuilt].root) and fast.models[rebuilt].root.get_instance_id()!=old_root_id,"external removal while the entity lives rebuilds a valid model")
	fast.free();reference.free();camera.free()
	await process_frame
	print("NATIVE_WORLD_CACHE ",JSON.stringify({"checks":checks,"failures":failures}))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
