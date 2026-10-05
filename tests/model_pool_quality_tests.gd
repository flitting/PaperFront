extends SceneTree
var failures:Array[String]=[]
var checks:int=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures.append(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	for policy in ["balanced","native"]:
		var sim:=WarSimulation.new()
		sim.setup(RulesLoader.load_rules(),"dev",7,"rivet",false)
		var camera:=Camera3D.new()
		root.add_child(camera)
		camera.position=Vector3(24,40,62);camera.look_at(Vector3(24,0,28))
		var world:=PaperWorld.new()
		root.add_child(world);world.setup(sim,camera);world.configure_quality(policy)
		var originals:Array[Dictionary]=[]
		var ids:Array=[]
		for faction in ["rivet","kestrel","iron","sky"]:
			for role in ["rifle","tank","harvester","fighter","power"]:
				var spec:String=faction+"_"+role
				var position:=Vector2(17.5+float(ids.size()%5)*3.0,25.5+float(ids.size()/5)*3.0)
				var id:int=sim._spawn(0,spec,position,true)
				ids.append(id)
				var e:Dictionary=sim.entities[id]
				e.alpha=170.0;e.turret_alpha=-75.0;e.cargo=450.0;e.attack_flash=.2
				e.hp*=.35
				if sim._is_air(e):e.flight_height=.35
				originals.append({"spec":spec,"pos":position})
		world.sync(.1,ids)
		for i in range(ids.size()):
			originals[i].root=world.models[ids[i]].root
			sim._kill_entity(ids[i],true)
		sim.events.clear()
		world.sync(.1,[])
		check(world.ghosts.size()==ids.size(),policy+": full corpse animation is retained for every original model")
		world.sync(1.4,[])
		check(world.ghosts.size()==ids.size(),policy+": corpses are not shortened by pooling")
		world.sync(1.1,[])
		check(world.ghosts.is_empty() and originals.all(func(item):return is_instance_valid(item.root) and not item.root.visible),policy+": only expired corpses enter the hidden pool")
		ids.clear()
		for item in originals:
			var id:int=sim._spawn(0,item.spec,item.pos+Vector2(.2,.1),true)
			sim.entities[id].alpha=-35.0;sim.entities[id].turret_alpha=82.0
			ids.append(id)
		world.sync(.05,ids)
		for i in range(ids.size()):
			var e:Dictionary=sim.entities[ids[i]]
			var reused:Dictionary=world.models[ids[i]]
			check(reused.root==originals[i].root,policy+": reuses the existing "+str(e.spec)+" hierarchy")
			var fresh:Dictionary=world._create_entity(e)
			world._update_entity(fresh,e,true)
			var same:bool=true
			for field in ["root","art_root","hp_root","hp_fill","hp_fill_back","shadow"]:
				if not reused[field].transform.is_equal_approx(fresh[field].transform):same=false
			check(same and reused.graphic.mesh==fresh.graphic.mesh and reused.hp_fraction==fresh.hp_fraction,policy+": recycled pose, health and paper state match a fresh "+str(e.spec))
			if reused.volumetric:
				var parts_match:bool=reused.render_parts.size()==fresh.render_parts.size()
				for part in range(reused.render_parts.size()):
					if not reused.render_parts[part].node.global_transform.is_equal_approx(fresh.render_parts[part].node.global_transform):parts_match=false
				check(parts_match,policy+": reset all articulated parts for "+str(e.spec))
			fresh.root.free()
		world.queue_free();camera.queue_free()
		await process_frame
	print("MODEL_POOL_QUALITY ",JSON.stringify({"checks":checks,"failures":failures}))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
