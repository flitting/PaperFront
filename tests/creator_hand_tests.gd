extends SceneTree

const Models=preload("res://scripts/volume_models.gd")
const Picking=preload("res://scripts/entity_picking.gd")
const Hand=preload("res://scripts/creator_hand_models.gd")
var checks:int=0
var failures:Array[String]=[]

func _initialize()->void:call_deferred("run")

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)

func edge_key(a:Vector3,b:Vector3)->String:
	var qa:=Vector3i(roundi(a.x*10000),roundi(a.y*10000),roundi(a.z*10000))
	var qb:=Vector3i(roundi(b.x*10000),roundi(b.y*10000),roundi(b.z*10000))
	var sa:String=str(qa)
	var sb:String=str(qb)
	return sa+"|"+sb if sa<sb else sb+"|"+sa

func closed_skin(mesh:Mesh)->bool:
	var edges:Dictionary={}
	for surface in range(mesh.get_surface_count()):
		var arrays:Array=mesh.surface_get_arrays(surface)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		var count:int=indices.size() if not indices.is_empty() else vertices.size()
		for i in range(0,count,3):
			var triangle:Array[Vector3]=[]
			for corner in range(3):triangle.append(vertices[indices[i+corner] if not indices.is_empty() else i+corner])
			for side in range(3):
				var key:String=edge_key(triangle[side],triangle[(side+1)%3])
				edges[key]=int(edges.get(key,0))+1
	for count in edges.values():
		if int(count)!=2:return false
	return true

func finger_min(model:Dictionary,posed:Dictionary,digits:Array[String])->float:
	var bone_ids:Dictionary={}
	for digit in digits:
		for suffix in ["Proximal","Middle","Distal"]:
			bone_ids[model.skeleton.find_bone(digit+suffix)]=true
	var minimum:float=INF
	for surface in range(model.skinned_mesh.mesh.get_surface_count()):
		var source:Array=model.skinned_mesh.mesh.surface_get_arrays(surface)
		var vertices:PackedVector3Array=posed.surfaces[surface].vertices
		var bones:PackedInt32Array=source[Mesh.ARRAY_BONES]
		var weights:PackedFloat32Array=source[Mesh.ARRAY_WEIGHTS]
		var stride:int=bones.size()/vertices.size()
		for i in range(vertices.size()):
			var influence:float=0.0
			for slot in range(stride):
				var bind:int=bones[i*stride+slot]
				var bone:int=model.skinned_mesh.skin.get_bind_bone(bind)
				if bone<0:bone=model.skeleton.find_bone(model.skinned_mesh.skin.get_bind_name(bind))
				if bone_ids.has(bone):influence+=weights[i*stride+slot]
			if influence>.65:
				minimum=minf(minimum,(model.skinned_mesh.global_transform*vertices[i]).y)
	return minimum

func pose(model:Dictionary,e:Dictionary,dt:float=.025)->Dictionary:
	Models.update_model(model,e,dt)
	return Picking._skinned_surface(model.skinned_mesh,model,{})

func digit_offset(model:Dictionary,digit:String)->Vector3:
	var root_bone:int=model.skeleton.find_bone(digit+"Proximal")
	var mcp:Vector3=model.skeleton.to_global(model.skeleton.get_bone_global_pose(root_bone).origin)
	var tip:Vector3=model.skeleton.to_global(Hand._finger_tip(model.skeleton,digit))
	return tip-mcp

func thumb_min_area_ratio(model:Dictionary,posed:Dictionary)->float:
	var minimum:float=INF
	for surface in range(model.skinned_mesh.mesh.get_surface_count()):
		var source:Array=model.skinned_mesh.mesh.surface_get_arrays(surface)
		var rest:PackedVector3Array=source[Mesh.ARRAY_VERTEX]
		var moved:PackedVector3Array=posed.surfaces[surface].vertices
		var indices:PackedInt32Array=source[Mesh.ARRAY_INDEX]
		var bones:PackedInt32Array=source[Mesh.ARRAY_BONES]
		var weights:PackedFloat32Array=source[Mesh.ARRAY_WEIGHTS]
		var stride:int=bones.size()/rest.size()
		for i in range(0,indices.size(),3):
			var vertices:Array[int]=[indices[i],indices[i+1],indices[i+2]]
			var influenced:bool=false
			for vertex in vertices:
				for slot in range(stride):
					var bind:int=bones[vertex*stride+slot]
					var bone:int=model.skinned_mesh.skin.get_bind_bone(bind)
					if bone<0:bone=model.skeleton.find_bone(model.skinned_mesh.skin.get_bind_name(bind))
					if bone in [1,2,3] and weights[vertex*stride+slot]>.5:influenced=true
			if not influenced:continue
			var area0:float=(rest[vertices[1]]-rest[vertices[0]]).cross(rest[vertices[2]]-rest[vertices[0]]).length()
			var area1:float=(moved[vertices[1]]-moved[vertices[0]]).cross(moved[vertices[2]]-moved[vertices[0]]).length()
			if area0>.00001:minimum=minf(minimum,area1/area0)
	return minimum

func run()->void:
	var spec:Dictionary={"art":"creator_hand","faction":"sky","domain":"ground"}
	var hand:Dictionary=Models.create_model(spec,"unit",0,false)
	var twin:Dictionary=Models.create_model(spec,"unit",0,false)
	var pose_only:Dictionary=Models.create_model(spec,"unit",0,true)
	root.add_child(hand.root)
	root.add_child(twin.root)
	root.add_child(pose_only.root)
	check(bool(hand.get("direct_skinned",false)),"runtime hand uses direct skinned rendering")
	check(hand.meshes.size()==1 and hand.meshes[0]==hand.skinned_mesh,"one continuous anatomical skin replaces rigid segments")
	check(hand.parts.is_empty(),"no rigid per-phalanx skin parts")
	check(hand.skinned_mesh is MeshInstance3D and hand.skinned_mesh.skin!=null,"mesh has a bound skin")
	check(hand.skinned_mesh.get_node_or_null(hand.skinned_mesh.skeleton)==hand.skeleton,"skin resolves its skeleton path")
	check(hand.skinned_mesh.mesh==twin.skinned_mesh.mesh and hand.skinned_mesh.skin==twin.skinned_mesh.skin,"immutable source mesh and skin are shared")
	check(hand.skeleton!=twin.skeleton and hand.skeleton!=pose_only.skeleton,"each hand has an independent skeleton")
	check(hand.skeleton.get_bone_count()==16 and hand.skinned_mesh.skin.get_bind_count()==16,"palm and five three-bone digits are rigged")
	for digit in ["Thumb","Index","Middle","Ring","Little"]:
		for suffix in ["Proximal","Middle","Distal"]:
			check(hand.skeleton.find_bone(digit+suffix)>=0,digit+" "+suffix+" bone")
	var mesh:Mesh=hand.skinned_mesh.mesh
	var vertex_count:int=0
	for surface in range(mesh.get_surface_count()):vertex_count+=mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX].size()
	check(vertex_count>=6500,"subdivided anatomical hand retains curved skin detail")
	check(closed_skin(mesh),"wrist cap closes the continuous five-finger skin")
	check(hand.height>4.0 and hand.height<6.5,"whole hand remains giant beside tabletop vehicles")
	var recipe:Dictionary=Models._recipe(spec,"unit",0)
	check(recipe.body_mesh!=null and recipe.dimensions.y==hand.height,"static recipe callers receive safe imported mesh metadata")
	var rest_skin:Dictionary=pose(hand,{"state":"idle"})
	check(not rest_skin.is_empty() and rest_skin.surfaces.size()==mesh.get_surface_count(),"CPU posed mesh supplies every surface to picking")
	check(int(hand.pose_version)>0,"pose revision advances for picking cache")
	var idle_index:float=finger_min(hand,rest_skin,["Index"])
	var idle_middle:float=finger_min(hand,rest_skin,["Middle"])
	check(minf(idle_index,idle_middle)>-.16 and minf(idle_index,idle_middle)<.22,"a walking fingertip supports the resting hand near the ground")
	check(absf((hand.support_tips[0].x+hand.support_tips[1].x)*.5)<.30,"support footprint is centered on simulation position")
	var walk_index_projection:float=digit_offset(hand,"Index").x
	var walk_middle_projection:float=digit_offset(hand,"Middle").x
	check(walk_index_projection>1.0 and walk_middle_projection>1.25,"walking proximal bones extend visibly ahead of the palm in top view")
	for digit in ["Ring","Little"]:
		var curl:Vector3=digit_offset(hand,digit)
		check(curl.y>.10 and curl.z>.25,digit+" curls up and inward beneath the palm")
	check(thumb_min_area_ratio(hand,rest_skin)>.45,"abducted thumb skin keeps area without a collapsed triangular fold")
	var resting_heel_y:float=hand.body.to_global(Vector3(.25,.6,0)).y
	var high_step:float=0.0
	pose_only.clock=hand.clock
	for frame in range(40):
		var moving:Dictionary=pose(hand,{"state":"move","id":7})
		var twin_pose:Dictionary=pose(pose_only,{"state":"move","id":7})
		var bottoms:Array[float]=[finger_min(hand,moving,["Index"]),finger_min(hand,moving,["Middle"])]
		check(minf(bottoms[0],bottoms[1])>-.16,"walking skin does not sink far below the ground "+str(frame))
		check(minf(bottoms[0],bottoms[1])<.22,"one digit supports the palm "+str(frame))
		high_step=maxf(high_step,absf(bottoms[0]-bottoms[1]))
		for digit in ["Index","Middle"]:
			for suffix in ["Proximal","Middle","Distal"]:
				var index:int=hand.skeleton.find_bone(digit+suffix)
				check(hand.skeleton.get_bone_pose_rotation(index).is_equal_approx(pose_only.skeleton.get_bone_pose_rotation(index)),"normal and pose-only bone parity "+str(frame)+digit+suffix)
	check(high_step>.08,"walking lifts alternating index and middle fingertips")
	var strike:Dictionary=pose(hand,{"state":"attack","hand_strike":.05,"hand_recover":0.0,"pos":Vector2.ZERO,"alpha":0.0,"hand_landing":Vector2(4.5,0),"hand_contact_height":.6})
	var strike_y:float=minf(finger_min(hand,strike,["Index"]),finger_min(hand,strike,["Middle"]))
	check(strike_y>.38 and strike_y<.82,"pressing skin touches a tank roof")
	check(absf((hand.support_tips[0].x+hand.support_tips[1].x)*.5-4.5)<.18,"both pads reach the actual target position")
	check(digit_offset(hand,"Index").x>walk_index_projection+.8 and digit_offset(hand,"Middle").x>walk_middle_projection+.8,"attack lays both finger pads forward across the target")
	check(hand.body.to_global(Vector3(.25,.6,0)).y<resting_heel_y-1.0,"attack lowers the palm while spreading the two fingers")
	var crush:Dictionary=pose(hand,{"state":"attack","hand_strike":0.0,"hand_recover":.20,"pos":Vector2.ZERO,"alpha":0.0,"hand_landing":Vector2(4.5,0),"hand_contact_height":.6,"hand_ground_height":0.0})
	var rubble_y:float=minf(finger_min(hand,crush,["Index"]),finger_min(hand,crush,["Middle"]))
	check(rubble_y>-.12 and rubble_y<.22,"post-hit hand presses near-ground wreckage")
	pose(hand,{"state":"idle","hand_strike":0.0,"hand_recover":0.0})
	check(hand.body.position.x<0.0,"pooled hand returns to the two-finger support anchor")
	print("CREATOR_HAND ",JSON.stringify({"checks":checks,"failures":failures,"vertices":vertex_count,"idle_min_y":[idle_index,idle_middle],"raised_step":high_step,"strike_min_y":strike_y,"rubble_min_y":rubble_y}))
	for failure in failures:push_error(failure)
	hand.root.free();twin.root.free();pose_only.root.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
