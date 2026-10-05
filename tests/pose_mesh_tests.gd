extends SceneTree
var checks:int=0
var failures:Array[String]=[]
func check(value:bool,message:String)->void:
	checks+=1
	if not value and failures.size()<20:failures.append(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	var rules:Dictionary=RulesLoader.load_rules()
	for kind in ["unit","building"]:
		var catalog:Dictionary=rules.units if kind=="unit" else rules.buildings
		for id in catalog:
			var spec:Dictionary=catalog[id]
			if not VolumeModels.supports(spec,kind):continue
			var actual:Dictionary=VolumeModels.create_model(spec,kind,0,true)
			var expected:Dictionary=VolumeModels.create_model(spec,kind,0,false)
			root.add_child(actual.root);root.add_child(expected.root)
			var graphics:Array[Node]=actual.root.find_children("*","GeometryInstance3D",true,false)
			if bool(actual.get("direct_skinned",false)):
				check(graphics.size()==1 and graphics[0]==actual.skinned_mesh,id+": direct skin retains exactly one original continuous render instance")
				check(actual.skinned_mesh.skin!=null and actual.skinned_mesh.skin.get_bind_count()==16 and actual.skeleton.get_bone_count()==16,id+": direct skin retains the sixteen deform bindings")
				check(actual.skeleton!=expected.skeleton and actual.skinned_mesh.get_node_or_null(actual.skinned_mesh.skeleton)==actual.skeleton,id+": direct skin owns its private bound skeleton")
			else:
				check(graphics.is_empty(),id+": pose sources allocate no duplicate render instances")
			check(actual.meshes.size()==expected.meshes.size() and actual.cargo.size()==expected.cargo.size(),id+": model topology matches standalone preview")
			for frame in range(4):
				var entity:Dictionary={"id":37,"state":["move","attack","harvest","idle"][frame],"attack_flash":.2 if frame==1 else 0.0,"hit_flash":.15 if frame==2 else 0.0,"cargo":350.0,"airborne":frame!=3}
				for model in [actual,expected]:
					model.root.position=Vector3(13,4,-7)
					model.root.rotation.y=deg_to_rad(float(frame*77))
					if model.turret!=null:model.turret.rotation.y=deg_to_rad(float(frame*-43))
					VolumeModels.update_model(model,entity,.1)
				for part in range(actual.meshes.size()):
					check(actual.meshes[part].mesh==expected.meshes[part].mesh and actual.meshes[part].global_transform.is_equal_approx(expected.meshes[part].global_transform),id+": exact mesh and animated transform "+str(part))
				for part in range(actual.cargo.size()):
					check(actual.cargo[part].mesh==expected.cargo[part].mesh and actual.cargo[part].global_transform.is_equal_approx(expected.cargo[part].global_transform),id+": cargo mesh and transform "+str(part))
				check(VolumeModels.muzzle_world(actual).is_equal_approx(VolumeModels.muzzle_world(expected)),id+": muzzle world position matches standalone preview")
			actual.root.free();expected.root.free()
	var sim:=WarSimulation.new()
	sim.setup(rules,"dev",7,"rivet",false)
	var camera:=Camera3D.new()
	root.add_child(camera);camera.position=Vector3(24,30,52);camera.look_at(Vector3(24,0,24))
	var fast:=PaperWorld.new()
	var legacy:=PaperWorld.new()
	legacy.pose_meshes_enabled=false
	root.add_child(fast);root.add_child(legacy)
	for world in [fast,legacy]:
		world.setup(sim,camera);world.configure_quality("balanced")
		world._cache_view_planes()
		world._spawn_effect(Vector2(24,28),"death",1.3,.2)
		world._spawn_effect(Vector2(23,28),"impact",.7,.2)
		world._spawn_effect(Vector2(24,28),"fire",.4,.7)
		world._spawn_smoke(Vector2(24,28),1.3,.5,true)
		world._spawn_debris(Vector2(24,28),1.3,.5)
	for frame in range(30):
		fast.sync(.05,[]);legacy.sync(.05,[])
		check(fast.effects.size()==legacy.effects.size(),"particle lifetimes stay equal")
		for i in range(fast.effects.size()):
			var a:Dictionary=fast.effects[i]
			var b:Dictionary=legacy.effects[i]
			check(a.graphic.global_transform.is_equal_approx(b.graphic.global_transform) and a.graphic.material_override.albedo_color==b.graphic.material_override.albedo_color and a.kind==b.kind,"particle pose, tint and type match hidden-node reference")
		check(fast._submitted_transforms==legacy._submitted_transforms,"same number of particle and model submissions")
	fast.queue_free();legacy.queue_free();camera.queue_free()
	await process_frame
	print("POSE_MESH ",JSON.stringify({"checks":checks,"failures":failures}))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
