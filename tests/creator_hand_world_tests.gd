extends SceneTree

const PICKING=preload("res://scripts/entity_picking.gd")
var checks:int=0
var failures:Array[String]=[]

func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)

func visible_skin_ray(sim,world,model:Dictionary,camera:Camera3D,id:int)->bool:
	var graphic:MeshInstance3D=model.volume.skinned_mesh
	var posed:Dictionary=PICKING._skinned_surface(graphic,model.volume,{})
	if posed.is_empty():return false
	var cache:Dictionary={}
	for surface in posed.surfaces:
		var vertices:PackedVector3Array=surface.vertices
		var indices:PackedInt32Array=surface.indices
		var count:int=indices.size() if not indices.is_empty() else vertices.size()
		for i in range(0,count-2,maxi(3,(count/90)/3*3)):
			var center:=Vector3.ZERO
			for corner in range(3):center+=vertices[indices[i+corner] if not indices.is_empty() else i+corner]/3.0
			var point:Vector3=graphic.global_transform*center
			var direction:Vector3=(point-camera.global_position).normalized()
			var hit:Dictionary=PICKING.ray_hit(sim,world,camera.global_position,direction,cache,func(entity):return int(entity.id)==id)
			if int(hit.id)==id and is_finite(float(hit.depth)):return true
	return false

func run()->void:
	var rules:Dictionary=RulesLoader.load_rules()
	check(rules.units.has("sky_creator_hand"),"real unit catalog contains Creator hand")
	if not rules.units.has("sky_creator_hand"):
		print("CREATOR_HAND_WORLD ",JSON.stringify({"checks":checks,"failures":failures}))
		quit(1);return
	var sim:=WarSimulation.new()
	sim.setup(rules,"dev",7,"sky",false)
	var camera:=Camera3D.new()
	root.add_child(camera)
	camera.position=Vector3(20,22,45)
	camera.look_at(Vector3(24,0,24))
	var world:=PaperWorld.new()
	root.add_child(world)
	world.setup(sim,camera)
	world.configure_quality("native")
	var id:int=sim._spawn(0,"sky_creator_hand",Vector2(24,24),true)
	check(id>0,"real simulation spawns hand")
	if id>0:
		var e:Dictionary=sim.entities[id]
		e.state="attack"
		e.hand_strike=.05
		e.hand_landing=e.pos+Vector2(4.5,0)
		e.hand_contact_height=.6
		e.hand_ground_height=0.0
		world.sync(.08,[id])
		var model:Dictionary=world.models[id]
		var volume:Dictionary=model.volume
		check(model.volumetric and bool(model.get("direct_skinned",false)),"world uses direct anatomical Skin rendering")
		check(model.render_parts.is_empty() and volume.meshes.size()==1,"skinned hand bypasses rigid MultiMesh parts")
		check(volume.skinned_mesh.visible and model.root.visible,"animated skin is directly visible in native world")
		check(volume.skeleton.get_bone_count()==16 and volume.skinned_mesh.skin.get_bind_count()==16,"world retains all independent deform bones")
		check(volume.skinned_mesh.mesh.get_surface_count()==2 and volume.skinned_mesh.mesh.get_aabb().size.x>5.0,"closed skin and nails use imported anatomical mesh")
		check(visible_skin_ray(sim,world,model,camera,id),"posed skin triangle is ray-pickable in the actual world")
		var original_root:Node3D=model.root
		var original_skeleton:Skeleton3D=volume.skeleton
		var original_mesh:Mesh=volume.skinned_mesh.mesh
		var pressed_x:float=volume.body.position.x
		sim._kill_entity(id,true)
		sim.events.clear()
		world.sync(.1,[])
		world.sync(2.6,[])
		var replacement:int=sim._spawn(0,"sky_creator_hand",Vector2(24.2,24.1),true)
		check(replacement>0,"hand can respawn after death")
		if replacement>0:
			world.sync(.05,[replacement])
			var reused:Dictionary=world.models[replacement]
			check(reused.root==original_root and reused.volume.skeleton==original_skeleton,"model pool reuses private Skeleton3D")
			check(reused.volume.skinned_mesh.mesh==original_mesh and reused.volume.skinned_mesh.visible,"pooled hand restores original visible Skin")
			check(absf(reused.volume.body.position.x-pressed_x)>1.0,"pooled hand clears its prior target press")
			check(absf((reused.volume.support_tips[0].x+reused.volume.support_tips[1].x)*.5)<.35,"pooled hand replants two support fingers at rule centre")
			var second:int=sim._spawn(0,"sky_creator_hand",Vector2(26,24),true)
			world.sync(.05,[replacement,second])
			var second_model:Dictionary=world.models[second]
			check(second_model.volume.skeleton!=reused.volume.skeleton,"simultaneous hands do not share mutable pose")
			check(second_model.volume.skinned_mesh.mesh==original_mesh,"simultaneous hands reuse immutable GLB geometry")
	world.free();camera.free()
	await process_frame
	print("CREATOR_HAND_WORLD ",JSON.stringify({"checks":checks,"failures":failures}))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
