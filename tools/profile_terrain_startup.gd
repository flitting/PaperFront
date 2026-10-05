extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var output:String="user://terrain_startup.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	var sim:=WarSimulation.new()
	var stamp:int=Time.get_ticks_usec()
	sim.setup(RulesLoader.load_rules(),"mountains640",73026,"rivet",false)
	var simulation_ms:float=(Time.get_ticks_usec()-stamp)/1000.0
	stamp=Time.get_ticks_usec()
	var landscape=PaperLandscape.build(sim)
	root.add_child(landscape)
	var landscape_ms:float=(Time.get_ticks_usec()-stamp)/1000.0
	var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256)
	for item in PaperLandscape._terrain_cache.nodes:
		digest.update(var_to_bytes([item.name,item.shadow,item.get("navigation_top_ranges",[])]))
		var mesh:Mesh=item.mesh
		for surface in range(mesh.get_surface_count()):digest.update(var_to_bytes(mesh.surface_get_arrays(surface)))
	var report:Dictionary={"simulation_setup_ms":simulation_ms,"landscape_ms":landscape_ms,"terrain_mesh_sha256":digest.finish().hex_encode(),"stats":landscape.stats.duplicate(),"scope":"full 640 terrain construction; not gameplay FPS"}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("TERRAIN_STARTUP ",JSON.stringify(report))
	landscape.queue_free();await process_frame
	quit()
