extends SceneTree
const Sim=preload("res://tests/rule_test_simulation.gd")
var failures:Array[String]=[]
var checks:int=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value and failures.size()<20:failures.append(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	if not ClassDB.class_exists("PaperFrontKernels"):
		push_error("Native world kernel missing");quit(1);return
	var sim=Sim.new();sim.setup(RulesLoader.load_rules(),"dev",7,"rivet",false)
	var camera:=Camera3D.new();root.add_child(camera)
	camera.position=Vector3(24,30,54);camera.look_at(Vector3(24,0,29))
	var fast:=PaperWorld.new();var reference:=PaperWorld.new()
	reference.native_kernels_enabled=false;reference.native_world_sync_enabled=false
	root.add_child(fast);root.add_child(reference)
	for world in [fast,reference]:world.setup(sim,camera);world.configure_quality("performance")
	var ids:Array=[]
	for faction in ["rivet","kestrel","iron","sky"]:
		for role in ["rifle","anti","engineer","tank","harvester","fighter","power"]:
			var id:int=sim._spawn(0,faction+"_"+role,Vector2(16.5+float(ids.size()%7)*2.2,25.5+float(ids.size()/7)*2.5),true)
			ids.append(id)
	for frame in range(90):
		if frame in [30,60]:
			camera.position=Vector3(24 if frame==60 else 4,30,54);camera.look_at(Vector3(24 if frame==60 else 4,0,29))
		for id in ids:
			var e:Dictionary=sim.entities[id]
			e.alpha=wrapf(float(id*13+frame*17),-180,180);e.turret_alpha=wrapf(float(frame*11),-180,180)
			e.pos+=Vector2(.008,.002);e.state=["move","attack","hit","idle"][frame%4]
			e.hp=float(sim.data_for(e.spec).hp)*(.2+.1*(frame%8));e.cargo=float(frame*17%500)
			e.attack_flash=.2 if frame%3==0 else 0.0;e.hit_flash=.1 if frame%5==0 else 0.0
			if sim._is_air(e):e.flight_height=.35 if frame%7==0 else 5.0
			if frame==45:e.team=1
			if str(e.spec).ends_with("_rifle"):e.transport_id=999 if frame%9==0 else -1
		var selection:Array=ids if frame%2==0 else []
		fast.sync(.016,selection);reference.sync(.016,selection)
		for id in ids:
			var a:Dictionary=fast.models[id];var b:Dictionary=reference.models[id]
			check(a.view_culled==b.view_culled and a.get("embarked",false)==b.get("embarked",false),"culling/transport "+str(frame)+" "+str(id))
			var same:bool=true
			for field in ["root","art_root","hp_root","hp_fill","hp_fill_back","shadow"]:
				if not a[field].transform.is_equal_approx(b[field].transform):same=false
			check(same,"pose "+str(frame)+" "+str(id))
			check(a.state==b.state and a.hp_fraction==b.hp_fraction and a.graphic.mesh.get_aabb()==b.graphic.mesh.get_aabb(),"state/card/health "+str(frame)+" "+str(id))
		check(fast._submitted_transforms==reference._submitted_transforms,"submission count "+str(frame))
	for world in [fast,reference]:world.configure_quality("balanced");world.sync(.05,ids);world.configure_quality("performance");world.sync(.05,ids)
	check(fast._submitted_transforms==reference._submitted_transforms,"quality switching preserves submissions")
	for frame in range(6):
		fast.sync(.05,ids);reference.sync(.05,ids)
		check(fast._submitted_transforms==reference._submitted_transforms,"stationary cache replay count")
	for world in [fast,reference]:world.configure_quality("balanced")
	for id in ids:
		if not fast.models[id].volumetric:
			sim.entities[id].state="attack";sim.entities[id].attack_flash=.2;sim.entities[id].hit_flash=0.0;sim.entities[id].transport_id=-1
	for world in [fast,reference]:world.sync(.02,ids);world.configure_quality("performance");world.sync(.02,ids)
	for script_frame in [true,false]:
		fast.native_world_sync_enabled=not script_frame
		for id in ids:
			if not fast.models[id].volumetric:sim.entities[id].hit_flash=.1
		fast.sync(.02,ids)
		for id in ids:
			var model:Dictionary=fast.models[id]
			if model.volumetric or model.view_culled:continue
			check(fast._batch_transforms(model.paper_batch).has(model.root.global_transform*model.art_root.transform),"paper card submission follows quality/script transitions")
	print("NATIVE_WORLD_SYNC ",JSON.stringify({"checks":checks,"failures":failures}))
	fast.queue_free();reference.queue_free();camera.queue_free();await process_frame
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
