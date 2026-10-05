extends SceneTree
const HAND=preload("res://scripts/creator_hand_models.gd")
func _initialize()->void:call_deferred("run")
func set_bone(model:Dictionary,name:String,z:float,x:float=0.0)->void:
	var skeleton:Skeleton3D=model.skeleton
	var id:int=skeleton.find_bone(name)
	skeleton.set_bone_pose_rotation(id,model.base_bone_rotations[id]*Quaternion(Vector3.RIGHT,deg_to_rad(x))*Quaternion(Vector3.BACK,deg_to_rad(z)))
func sample(model:Dictionary,digit:String,prox_z:float,prox_x:float,middle_z:float,distal_z:float)->Vector3:
	set_bone(model,digit+"Proximal",prox_z,prox_x)
	set_bone(model,digit+"Middle",middle_z)
	set_bone(model,digit+"Distal",distal_z)
	model.skeleton.force_update_all_bone_transforms()
	return HAND._finger_tip(model.skeleton,digit)
func run()->void:
	var model:Dictionary=HAND.create({"faction":"sky"},0)
	root.add_child(model.root)
	for digit in ["Ring","Little"]:
		print("SEARCH_DIGIT ",digit," rest=",sample(model,digit,0,0,0,0)," current=",sample(model,digit,-55 if digit=="Ring" else -50,0,-105,-50))
		for px in [-35.0,-20.0,0.0,20.0,35.0]:
			print("SEARCH_X ",digit," ",px," tip=",sample(model,digit,-55 if digit=="Ring" else -50,px,-105,-50))
		for pz in [-85.0,-70.0,-55.0,-40.0]:
			print("SEARCH_Z ",digit," ",pz," tip=",sample(model,digit,pz,0,-105,-50))
	for digit in ["Index","Middle"]:
		for angles in [[-35.0,-30.0,-15.0],[-15.0,-20.0,-25.0],[-5.0,-20.0,-25.0],[5.0,-10.0,-15.0]]:
			print("SEARCH_WALK ",digit," ",angles," tip=",sample(model,digit,angles[0],0,angles[1],angles[2]))
	model.root.free()
	await process_frame
	quit()
