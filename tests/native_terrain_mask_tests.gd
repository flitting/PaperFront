extends SceneTree
var failures:Array[String]=[]
func _initialize()->void:
	if not ClassDB.class_exists("PaperFrontKernels"):push_error("Native kernel missing");quit(1);return
	var sim:=WarSimulation.new()
	var rng:=RandomNumberGenerator.new();rng.seed=73026
	var checks:int=0
	for size in [16,48,128]:
		for variant in range(4):
			sim.map={"size":size,"heights":[],"terrain":[]}
			for z in range(size):
				var heights:Array=[];var terrain:Array=[]
				for x in range(size):
					heights.append(float(int(x/9)+int(z/7))*.5 if variant%2 else 0.0)
					terrain.append(0 if variant<2 else rng.randi_range(0,4))
				sim.map.heights.append(heights);sim.map.terrain.append(terrain)
			sim.native_kernels_enabled=false;sim._prepare_terrain_cache()
			var expected:PackedByteArray=sim._flat_safe.duplicate()
			sim.native_kernels_enabled=true;sim._prepare_terrain_cache()
			checks+=size*size
			if sim._flat_safe!=expected:failures.append("flat mask mismatch size %d variant %d"%[size,variant])
	print("NATIVE_TERRAIN_MASK ",JSON.stringify({"cells_checked":checks,"failures":failures}))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
