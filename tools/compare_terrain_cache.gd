extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var sim:=WarSimulation.new();sim.setup(RulesLoader.load_rules(),"mountains640",73026,"rivet",false)
	var landscape:=PaperLandscape.new();landscape.terrain_disk_cache_enabled=false;landscape._build(sim)
	var key:String=preload("res://scripts/terrain_resource_cache.gd").key_for([sim.map,landscape._ground_exclusions])
	var stored:Dictionary=preload("res://scripts/terrain_resource_cache.gd").load_entry(key)
	var problems:Array=[]
	var metadata:Array=[]
	if stored.is_empty():problems.append("missing prior cache")
	else:
		for index in range(PaperLandscape._terrain_cache.nodes.size()):
			var a:Dictionary=PaperLandscape._terrain_cache.nodes[index]
			var b:Dictionary=stored.nodes[index]
			if a.name!=b.name or a.shadow!=b.shadow:problems.append("node metadata "+str(index))
			var ar:Array=a.get("navigation_top_ranges",[]);var br:Array=b.get("navigation_top_ranges",[])
			if ar!=br:problems.append("navigation ranges "+str(index))
			if metadata.is_empty() and not ar.is_empty():metadata.append({"a_typed":ar.is_typed(),"b_typed":br.is_typed(),"a_builtin":ar.get_typed_builtin(),"b_builtin":br.get_typed_builtin()})
			for surface in range(a.mesh.get_surface_count()):
				var aa:Array=a.mesh.surface_get_arrays(surface);var bb:Array=b.mesh.surface_get_arrays(surface)
				for channel in range(Mesh.ARRAY_MAX):
					if aa[channel]!=bb[channel] and problems.size()<12:
						var first:int=-1
						if aa[channel]!=null and bb[channel]!=null and aa[channel].size()==bb[channel].size():
							for item in range(aa[channel].size()):
								if aa[channel][item]!=bb[channel][item]:first=item;break
						problems.append({"node":a.name,"channel":channel,"first":first,"a":str(aa[channel][first]) if first>=0 else str(aa[channel]),"b":str(bb[channel][first]) if first>=0 else str(bb[channel])})
	var report:Dictionary={"problems":problems,"metadata":metadata}
	print("TERRAIN_CACHE_COMPARE ",JSON.stringify(report))
	FileAccess.open("res://artifacts/performance_640/phase4/terrain_comparison.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	landscape.free();quit(0 if problems.is_empty() else 1)
