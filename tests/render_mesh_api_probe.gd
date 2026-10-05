extends SceneTree

func _initialize() -> void:
	var rules:Dictionary=RulesLoader.load_rules()
	for spec_id in ["rivet_tank","kestrel_tank","rivet_fighter"]:
		var recipe:Dictionary=VolumeModels._recipe(rules.units[spec_id],"unit",0)
		var source:ArrayMesh=recipe.body_mesh
		var importer:=ImporterMesh.new()
		for surface in range(source.get_surface_count()):
			var arrays:Array=source.surface_get_arrays(surface)
			if arrays[Mesh.ARRAY_INDEX]==null or (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty():
				var indices:=PackedInt32Array()
				indices.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
				for index in range(indices.size()):indices[index]=index
				arrays[Mesh.ARRAY_INDEX]=indices
			importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},source.surface_get_material(surface))
		importer.generate_lods(60.0,25.0,[])
		var counts:Array=[]
		var generated:Array=importer.get_surface_arrays(0)
		var vertices:PackedVector3Array=generated[Mesh.ARRAY_VERTEX]
		var colors:PackedColorArray=generated[Mesh.ARRAY_COLOR]
		for index in range(importer.get_surface_lod_count(0)):
			var ids:PackedInt32Array=importer.get_surface_lod_indices(0,index)
			var bounds:=AABB(vertices[ids[0]],Vector3.ZERO)
			var owner_vertices:int=0
			for id in ids:
				bounds=bounds.expand(vertices[id])
				if colors[id].is_equal_approx(VolumeModels.player_color(0)):owner_vertices+=1
			counts.append({"distance":importer.get_surface_lod_size(0,index),"indices":ids.size(),"size":bounds.size,"owner_vertices":owner_vertices})
		print("LOD_BASE ",vertices.size()," / ",(generated[Mesh.ARRAY_INDEX] as PackedInt32Array).size()," / ",source.get_aabb().size)
		print("MESH_LOD ",JSON.stringify({"spec":spec_id,"base_vertices":source.surface_get_array_len(0),"lods":counts}))
	quit()
