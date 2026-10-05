extends SceneTree
func _initialize()->void:
	if not ClassDB.class_exists("PaperFrontKernels"):push_error("Native kernel missing");quit(1);return
	var kernel=ClassDB.instantiate("PaperFrontKernels")
	var result:Dictionary=kernel.verify_container_lifetimes()
	var valid:bool=result.after_move==1 and result.after_self==2 and result.after_scope==1
	print("NATIVE_LIFETIME ",JSON.stringify({"passed":valid,"counts":result}))
	if not valid:push_error("Container assignment retained or lost owned references")
	quit(0 if valid else 1)
