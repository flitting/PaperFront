extends SceneTree
var failures:Array[String]=[]
var checks:int=0

func _check(condition:bool,label:String)->void:
	checks+=1
	if not condition:failures.append(label)

func _blank_map(sim)->void:
	sim._in_step=false
	sim.map={"size":16,"heights":[],"terrain":[]}
	for z in range(16):
		var heights:Array=[];var terrain:Array=[]
		for x in range(16):heights.append(0.0);terrain.append(0)
		sim.map.heights.append(heights);sim.map.terrain.append(terrain)

func _prepare_geometry(sim)->void:
	sim.native_kernels_enabled=true
	sim._prepare_terrain_cache()
	sim._spec_cache={"test":{}}
	sim._in_step=true
	sim.native_geometry_enabled=true
	sim._prepare_native_queries()

func _compare_detailed(sim,method:String,args:Array,expected:bool,label:String)->void:
	sim.native_geometry_enabled=true;sim._prepare_native_queries()
	var native_result:bool=sim.callv(method,args)
	sim.native_geometry_enabled=false
	var script_result:bool=sim.callv(method,args)
	# Removing only the wide shortcut exercises the former detailed checks for
	# these larger radii, independently of the new native/script fast path.
	var saved:PackedByteArray=sim._flat_wide_safe.duplicate()
	sim._flat_wide_safe.fill(0)
	var detailed_result:bool=sim.callv(method,args)
	sim._flat_wide_safe=saved
	_check(detailed_result==expected,label+" detailed fixture")
	_check(native_result==detailed_result,label+" native matches detailed")
	_check(script_result==detailed_result,label+" script matches detailed")

func _wide_geometry_cases(sim)->void:
	_blank_map(sim);_prepare_geometry(sim)
	_check(sim._fast_flat(Vector2(6.01,6.99),1.0),"vehicle radius enters wide flat shortcut")
	_check(sim._fast_flat(Vector2(6.01,6.99),1.99),"wide shortcut covers conservative two-cell radius")
	_check(not sim._fast_flat(Vector2(6.5,6.5),2.0),"radius beyond wide guarantee uses detailed checks")
	_check(not sim._fast_flat(Vector2(1.99,6.5),1.0),"two-cell map border stays outside wide shortcut")
	_compare_detailed(sim,"_standing",[Vector2(6.01,6.99),1.0,-1,false],true,"flat vehicle")
	_compare_detailed(sim,"_segment_static",[Vector2(4.01,6.99),Vector2(10.99,6.01),1.99,-1],true,"flat arbitrary-angle wide segment")
	_compare_detailed(sim,"_standing",[Vector2(.999,6.5),1.0,-1,false],false,"map edge footprint")
	_compare_detailed(sim,"_segment_static",[Vector2(3.5,6.5),Vector2(.999,6.5),1.0,-1],false,"map edge crossing")
	_blank_map(sim)
	sim.map.terrain[6][8]=1
	_prepare_geometry(sim)
	_check(not sim._fast_flat(Vector2(7.2,6.5),1.0),"nearby water disables wide shortcut")
	_compare_detailed(sim,"_standing",[Vector2(7.2,6.5),1.0,-1,false],false,"water corner footprint")
	_compare_detailed(sim,"_segment_static",[Vector2(5.5,6.5),Vector2(10.5,6.5),1.0,-1],false,"water crossing")
	_blank_map(sim)
	for z in range(16):
		for x in range(8,16):sim.map.heights[z][x]=2.0
	_prepare_geometry(sim)
	_check(not sim._fast_flat(Vector2(7.2,6.5),1.0),"nearby cliff disables wide shortcut")
	_compare_detailed(sim,"_standing",[Vector2(7.2,6.5),1.0,-1,false],false,"cliff footprint")
	_compare_detailed(sim,"_segment_static",[Vector2(5.5,6.5),Vector2(10.5,6.5),1.0,-1],false,"cliff crossing")
	_blank_map(sim)
	sim.map.terrain[6][6]=2
	_prepare_geometry(sim)
	_check(not sim._fast_flat(Vector2(6.5,6.5),1.0),"ramp terrain stays on detailed checks")
	_compare_detailed(sim,"_standing",[Vector2(6.5,6.5),1.0,-1,false],true,"level ramp footprint")
	sim._in_step=false

func _initialize()->void:
	if not ClassDB.class_exists("PaperFrontKernels"):push_error("Native kernel missing");quit(1);return
	var sim:=WarSimulation.new()
	var rng:=RandomNumberGenerator.new();rng.seed=73026
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
			var expected_wide:PackedByteArray=sim._flat_wide_safe.duplicate()
			sim.native_kernels_enabled=true;sim._prepare_terrain_cache()
			checks+=size*size
			if sim._flat_safe!=expected:failures.append("flat mask mismatch size %d variant %d"%[size,variant])
			if sim._flat_wide_safe!=expected_wide:failures.append("wide flat mask mismatch size %d variant %d"%[size,variant])
	_wide_geometry_cases(sim)
	print("NATIVE_TERRAIN_MASK ",JSON.stringify({"cells_checked":checks,"failures":failures}))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
