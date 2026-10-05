extends SceneTree
var checks:int=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func run()->void:
	if not ClassDB.class_exists("PaperFrontKernels"):
		push_error("Native pose kernel missing");quit(1);return
	var sim:=WarSimulation.new()
	sim.setup(RulesLoader.load_rules(),"dev",7,"rivet",false)
	var camera:=Camera3D.new()
	root.add_child(camera)
	camera.position=Vector3(24,35,63);camera.look_at(Vector3(24,0,30))
	var fast:=PaperWorld.new()
	var reference:=PaperWorld.new()
	root.add_child(fast);root.add_child(reference)
	for world in [fast,reference]:world.setup(sim,camera);world.configure_quality("performance")
	reference.native_kernels_enabled=false
	var ids:Array[int]=[]
	for faction in ["rivet","kestrel","iron","sky"]:
		for role in ["tank","harvester","fighter","tower","power"]:
			ids.append(sim._spawn(0,faction+"_"+role,Vector2(20+ids.size()%6,30+ids.size()/6),true))
	for frame in range(60):
		for id in ids:
			var e:Dictionary=sim.entities[id]
			e.alpha=wrapf(float(id*37+frame*11),-180,180)
			e.turret_alpha=wrapf(float(id*23-frame*7),-180,180)
			e.pos+=Vector2(.005,.002)
			e.hp=float(sim.data_for(e.spec).hp)*(.2+.1*(frame%9))
			e.cargo=float(frame*17%500)
			e.state=["move","attack","idle"][frame%3]
			e.attack_flash=.12 if frame%4==0 else 0.0
			e.hit_flash=.10 if frame%5==0 else 0.0
			if sim._is_air(e):e.flight_height=.35 if frame%6==0 else float(sim.data_for(e.spec).flight_height)
			if e.kind=="building":e.construct_remaining=maxf(0,1.5-frame*.2)
			if frame in [20,40]:e.team=1-int(e.team)
		var selected:Array=ids if frame%2==0 else []
		fast.sync(1.0/60,selected);reference.sync(1.0/60,selected)
		for id in ids:
			var actual:Dictionary=fast.models[id]
			var expected:Dictionary=reference.models[id]
			var same:bool=true
			for field in ["state","last_pos","last_alpha","last_turret_angle","last_hp_yaw","hp_fraction","flight_height"]:
				if actual[field]!=expected[field]:
					same=false
					if failures.size()<2:print("POSE_DIFFERENCE ",frame," ",id," ",field," ",actual[field]," ",expected[field])
			for field in ["root","art_root","hp_root","shadow","hp_fill","hp_fill_back"]:
				if not actual[field].transform.is_equal_approx(expected[field].transform):same=false
			for i in range(actual.render_parts.size()):
				if not actual.render_parts[i].node.global_transform.is_equal_approx(expected.render_parts[i].node.global_transform):same=false
			if actual.volume.get("cargo_count",0)!=expected.volume.get("cargo_count",0):same=false
			checks+=1
			if not same and failures.size()<10:failures.append("pose mismatch frame %d entity %d"%[frame,id])
		# Same number and order of model submissions, including health bars.
		checks+=1
		if fast._submitted_transforms!=reference._submitted_transforms:failures.append("different submitted instance count in frame "+str(frame))
	for frame in range(20):
		fast.sync(1.0/60,ids);reference.sync(1.0/60,ids)
		checks+=1
		if fast._submitted_transforms!=reference._submitted_transforms:failures.append("cached pose dropped submissions")
		for id in ids:
			checks+=1
			if not fast.models[id].root.transform.is_equal_approx(reference.models[id].root.transform):failures.append("cached pose changed model anchor")
	print("NATIVE_VOLUME ",JSON.stringify({"checks":checks,"failures":failures}))
	fast.queue_free();reference.queue_free();camera.queue_free()
	await process_frame
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
