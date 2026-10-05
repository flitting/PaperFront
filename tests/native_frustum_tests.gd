extends SceneTree
var failures:Array[String]=[]
var checks:int=0
func _initialize()->void:call_deferred("run")
func run()->void:
	if not ClassDB.class_exists("PaperFrontKernels"):
		push_error("Native frustum kernel missing");quit(1);return
	var camera:=Camera3D.new()
	root.add_child(camera)
	var world:=PaperWorld.new()
	root.add_child(world);world.camera=camera
	var rng:=RandomNumberGenerator.new();rng.seed=73026
	for pose in range(16):
		camera.position=Vector3(rng.randf_range(0,640),rng.randf_range(20,80),rng.randf_range(0,640))
		camera.rotation=Vector3(-rng.randf_range(.3,.8),rng.randf_range(-PI,PI),0)
		camera.fov=42;camera.h_offset=float(pose%3);camera.v_offset=float(pose%2)
		world._cache_view_planes()
		for i in range(1000):
			var position:=Vector3(rng.randf_range(0,640),rng.randf_range(-5,12),rng.randf_range(0,640))
			var radius:float=rng.randf_range(0,15)
			world.native_kernels_enabled=true
			var fast:bool=world._point_in_view(position,radius)
			world.native_kernels_enabled=false
			var expected:bool=world._point_in_view(position,radius)
			checks+=1
			if fast!=expected:failures.append("frustum differs in camera pose "+str(pose))
		for plane in world._view_planes:
			for gap in [-.00001,0.0,.00001]:
				var position:Vector3=plane.normal*(plane.d+gap)
				world.native_kernels_enabled=true
				var fast:bool=world._point_in_view(position,0.0)
				world.native_kernels_enabled=false
				checks+=1
				if fast!=world._point_in_view(position,0.0):failures.append("plane boundary differs")
	print("NATIVE_FRUSTUM ",JSON.stringify({"checks":checks,"failures":failures}))
	world.queue_free();camera.queue_free();await process_frame
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
