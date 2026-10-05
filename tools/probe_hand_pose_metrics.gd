extends SceneTree
const HAND=preload("res://scripts/creator_hand_models.gd")
const MODELS=preload("res://scripts/volume_models.gd")
func _initialize()->void:call_deferred("run")
func show(model:Dictionary,label:String)->void:
	for digit in ["Index","Middle","Ring","Little","Thumb"]:
		var base:int=model.skeleton.find_bone(digit+"Proximal")
		var mcp:Vector3=model.skeleton.to_global(model.skeleton.get_bone_global_pose(base).origin)
		var tip:Vector3=model.skeleton.to_global(HAND._finger_tip(model.skeleton,digit))
		print("METRIC ",label," ",digit," mcp=",mcp," tip=",tip," offset=",tip-mcp)
	print("METRIC ",label," heel=",model.body.to_global(Vector3(.25,.6,0))," body=",model.body.position)
func run()->void:
	var model:Dictionary=HAND.create({"faction":"sky"},0)
	root.add_child(model.root)
	show(model,"idle")
	MODELS.update_model(model,{"state":"attack","hand_strike":.05,"hand_landing":Vector2(4.5,0),"hand_contact_height":.6},.025)
	show(model,"attack")
	model.root.free()
	await process_frame
	quit()
