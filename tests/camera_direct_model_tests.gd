extends SceneTree
const Sim=preload("res://tests/rule_test_simulation.gd")
const CUT=preload("res://scripts/camera_occlusion.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var sim=Sim.new();sim.setup(RulesLoader.load_rules(),"dev",7,"sky",false);sim.vision_enabled=false
	for id in sim.entities.keys():sim._kill_entity(id,false)
	var hand_id:int=sim._spawn(0,"sky_creator_hand",Vector2(24,24),true)
	var camera:=Camera3D.new();root.add_child(camera);camera.position=Vector3(24,7,35);camera.look_at(Vector3(24,1,24))
	var world:=PaperWorld.new();root.add_child(world);world.setup(sim,camera);world.sync(0,[])
	var model:Dictionary=world.models[hand_id];var node:MeshInstance3D=model.volume.skinned_mesh
	var original_mesh:Mesh=model.skinned_lods[0].source;var original_skin:Skin=node.skin;var original_skeleton:Skeleton3D=model.volume.skeleton
	var source:ShaderMaterial=model.volume.owner_materials[0];var wrapped:ShaderMaterial=node.get_surface_override_material(0)
	check(bool(model.direct_skinned) and node.visible,"actualPaperWorld hand uses direct visibleSkeleton3D geometry")
	check(wrapped!=source and wrapped.shader.code.contains("paper_camera_occlusion"),"directhand has peripheral/nearby occlusion shader through production hook")
	check(not source.shader.code.contains("paper_camera_occlusion"),"authoredskin material remains unchanged")
	for name in ["owner_color","paint_cutoff","skin_tint"]:check(wrapped.get_shader_parameter(name)==source.get_shader_parameter(name),"original hand uniform preserved: "+name)
	for surface in node.mesh.get_surface_count():check(node.get_active_material(surface) is ShaderMaterial and node.get_active_material(surface).shader.code.contains("paper_camera_occlusion"),"skin and nails both support peripheral/nearby fading surface"+str(surface))
	for tier in range(3):
		world.lod_override=tier;world.sync(0,[])
		check(node.get_surface_override_material(0)==wrapped and node.skin==original_skin and model.volume.skeleton==original_skeleton,"LOD retains wrapped private material and skin binding tier"+str(tier))
	world.lod_override=0
	for state in ["idle","move","attack"]:
		sim.entities[hand_id].state=state;sim.entities[hand_id].hand_strike=.18 if state=="attack" else 0
		world.sync(.15,[])
		check(node.mesh==original_mesh and node.skin==original_skin and original_skeleton.get_bone_count()==16,"real animation retains continuous mesh and16bone rig: "+state)
		check(node.get_surface_override_material(0)==wrapped,"animation retains cutaway shader: "+state)
	CUT.wrap_instance(node)
	check(node.get_surface_override_material(0)==wrapped,"repeated directhook is idempotent")
	world.free();camera.free();if sim._path_worker!=null:sim._path_worker.close()
	await process_frame
	print("CAMERA_DIRECT_MODEL ",JSON.stringify({"checks":checks,"failures":failures}))
	for label in failures:push_error(label)
	quit(0 if failures.is_empty() else 1)
