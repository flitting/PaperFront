extends SceneTree
const HAND=preload("res://scripts/creator_hand_models.gd")
const PICKING=preload("res://scripts/entity_picking.gd")
func _initialize()->void:call_deferred("run")
func thumb_weight(model:Dictionary,source:Array,i:int)->float:
	var bones:PackedInt32Array=source[Mesh.ARRAY_BONES]
	var weights:PackedFloat32Array=source[Mesh.ARRAY_WEIGHTS]
	var stride:int=bones.size()/source[Mesh.ARRAY_VERTEX].size()
	var total:float=0.0
	for slot in range(stride):
		var bind:int=bones[i*stride+slot]
		var bone:int=model.skinned_mesh.skin.get_bind_bone(bind)
		if bone<0:bone=model.skeleton.find_bone(model.skinned_mesh.skin.get_bind_name(bind))
		if bone in [1,2,3]:total+=weights[i*stride+slot]
	return total
func report(model:Dictionary,label:String)->void:
	var posed:Dictionary=PICKING._skinned_surface(model.skinned_mesh,model,{})
	var ratios:Array[float]=[]
	for surface in range(model.skinned_mesh.mesh.get_surface_count()):
		var source:Array=model.skinned_mesh.mesh.surface_get_arrays(surface)
		var rest:PackedVector3Array=source[Mesh.ARRAY_VERTEX]
		var moving:PackedVector3Array=posed.surfaces[surface].vertices
		var indices:PackedInt32Array=source[Mesh.ARRAY_INDEX]
		for i in range(0,indices.size(),3):
			var a:int=indices[i];var b:int=indices[i+1];var c:int=indices[i+2]
			if maxf(thumb_weight(model,source,a),maxf(thumb_weight(model,source,b),thumb_weight(model,source,c)))<.5:continue
			var area0:float=(rest[b]-rest[a]).cross(rest[c]-rest[a]).length()
			var area1:float=(moving[b]-moving[a]).cross(moving[c]-moving[a]).length()
			if area0>.00001:ratios.append(area1/area0)
	ratios.sort()
	var small:int=0
	for ratio in ratios:
		if ratio<.5:small+=1
	print("THUMB_SKIN ",label," faces=",ratios.size()," min=",ratios.front() if not ratios.is_empty() else 0," p01=",ratios[maxi(0,ratios.size()/100)]," p05=",ratios[maxi(0,ratios.size()/20)]," under_half=",small)
func run()->void:
	var model:Dictionary=HAND.create({"faction":"sky"},0)
	root.add_child(model.root)
	report(model,"revised")
	var skeleton:Skeleton3D=model.skeleton
	var id:int=skeleton.find_bone("ThumbProximal")
	skeleton.set_bone_pose_rotation(id,model.base_bone_rotations[id]*Quaternion(Vector3.RIGHT,deg_to_rad(25.0))*Quaternion(Vector3.BACK,deg_to_rad(24.0)))
	HAND._bone(model,"ThumbMiddle",-5.0)
	skeleton.force_update_all_bone_transforms()
	model.pose_version+=1
	report(model,"previous")
	model.root.free()
	await process_frame
	quit()
