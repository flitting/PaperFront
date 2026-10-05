extends SceneTree

var bake_cache:Dictionary={}

func _initialize() -> void:
	var rules:Dictionary=RulesLoader.load_rules()
	if rules.is_empty():push_error("LOD bake requires valid imported rules");quit(2);return
	var records:Dictionary={}
	var signatures:Dictionary={}
	var reduced:int=0
	for id in rules.units:
		var spec:Dictionary=rules.units[id]
		if not VolumeModels.supports(spec,"unit"):continue
		var recipe:Dictionary=VolumeModels._recipe(spec,"unit",0)
		for field in ["body_mesh","turret_mesh","body_border_mesh","turret_border_mesh"]:
			if not recipe.has(field):continue
			var source:Mesh=recipe[field]
			var mesh:Mesh=bake_mesh(source,0)
			var surfaces:Array=[]
			if mesh!=source:
				for surface in range(mesh.get_surface_count()):surfaces.append(mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX])
				reduced+=1
			var template:String=VolumeModels.art_faction(spec)+"/"+str(spec.art)+"/"+field
			records[template]=surfaces
			signatures[template]=VolumeModels.lod_source_signature(source,0)
	var resource:=Resource.new()
	resource.set_meta("lod_indices",records)
	resource.set_meta("source_signatures",signatures)
	resource.set_meta("lod_schema",2)
	resource.set_meta("source_note","Native meshoptimizer first LOD with protected owner/PAPER triangles and 6% silhouette bound guard; runtime uses original owner vertices.")
	var error:int=ResourceSaver.save(resource,"res://assets/models/unit_lod_indices.res")
	print("BAKED_UNIT_LOD ",JSON.stringify({"templates":records.size(),"reduced":reduced,"error":error}))
	quit(error)

func bake_mesh(source:Mesh,team:int) -> Mesh:
	if not source is ArrayMesh:return source
	var key:int=source.get_instance_id()
	if bake_cache.has(key):return bake_cache[key]
	var importer:=ImporterMesh.new()
	for surface in range(source.get_surface_count()):
		var arrays:Array=source.surface_get_arrays(surface)
		if arrays[Mesh.ARRAY_INDEX]==null or (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty():
			var indices:=PackedInt32Array()
			indices.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
			for index in range(indices.size()):indices[index]=index
			arrays[Mesh.ARRAY_INDEX]=indices
		importer.add_surface(source.surface_get_primitive_type(surface),arrays,[],{},source.surface_get_material(surface))
	importer.generate_lods(60.0,25.0,[])
	var result:=ArrayMesh.new()
	var simplified:bool=false
	for surface in range(source.get_surface_count()):
		var arrays:Array=importer.get_surface_arrays(surface)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var full:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		var indices:PackedInt32Array=full
		if importer.get_surface_lod_count(surface)>0:
			indices=importer.get_surface_lod_indices(surface,0)
			var colors:PackedColorArray=arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR]!=null else PackedColorArray()
			# Native simplification drops small detached badges. Keep the complete
			# owner-colored plate and paper insignia/text triangles at every tier.
			if not colors.is_empty():
				var owner:Color=VolumeModels.player_color(team)
				for offset in range(0,full.size(),3):
					var protect:bool=false
					for corner in range(3):
						var color:Color=colors[full[offset+corner]]
						if color.is_equal_approx(owner) or color.is_equal_approx(VolumeModels.PAPER):protect=true;break
					if protect:
						for corner in range(3):indices.append(full[offset+corner])
			var original_bounds:=AABB(vertices[full[0]],Vector3.ZERO)
			for id in full:original_bounds=original_bounds.expand(vertices[id])
			var bounds:=AABB(vertices[indices[0]],Vector3.ZERO)
			for id in indices:bounds=bounds.expand(vertices[id])
			var margin:Vector3=original_bounds.size*.06+Vector3.ONE*.02
			if not AABB(bounds.position-margin,bounds.size+margin*2.0).encloses(original_bounds):indices=full
		if indices.size()<full.size():simplified=true
		else:indices=full
		arrays[Mesh.ARRAY_INDEX]=indices
		result.add_surface_from_arrays(source.surface_get_primitive_type(surface),arrays)
		result.surface_set_material(surface,source.surface_get_material(surface))
	bake_cache[key]=result if simplified else source
	return bake_cache[key]
