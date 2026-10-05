extends SceneTree
var failures:Array[String]=[]
var checks:int=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value and failures.size()<20:failures.append(message)
func _initialize()->void:
	var rules:Dictionary=RulesLoader.load_rules()
	var resource:Resource=VolumeModels.UNIT_LOD_RESOURCE
	var records:Dictionary=resource.get_meta("lod_indices",{})
	var hashes:Dictionary=resource.get_meta("source_signatures",{})
	check(int(resource.get_meta("lod_schema",0))==2,"versioned offline LOD provenance is present")
	var reduced:Dictionary={}
	for id in rules.units:
		var spec:Dictionary=rules.units[id]
		if not VolumeModels.supports(spec,"unit"):continue
		for team in range(8):
			var recipe:Dictionary=VolumeModels._recipe(spec,"unit",team)
			for field in ["body_mesh","turret_mesh","body_border_mesh","turret_border_mesh"]:
				if not recipe.has(field):continue
				var source:Mesh=recipe[field]
				var key:String=VolumeModels.art_faction(spec)+"/"+str(spec.art)+"/"+field
				check(records.has(key) and hashes.get(key,"")==VolumeModels.lod_source_signature(source,team),"source geometry and paint match baked LOD "+key+" owner "+str(team))
				var mesh:Mesh=VolumeModels.quality_mesh(source,team)
				if records.get(key,[]).is_empty():continue
				check(mesh!=source,"valid reduced geometry loads for "+key+" owner "+str(team))
				reduced[spec.faction]=int(reduced.get(spec.faction,0))+1
				for surface in range(mesh.get_surface_count()):
					var original:Array=source.surface_get_arrays(surface)
					var result:Array=mesh.surface_get_arrays(surface)
					check(result[Mesh.ARRAY_VERTEX]==original[Mesh.ARRAY_VERTEX] and result[Mesh.ARRAY_COLOR]==original[Mesh.ARRAY_COLOR],"reduction never moves source vertices or changes owner paint")
	for faction in rules.factions:check(int(reduced.get(faction,0))>0,"offline reductions include "+str(faction))
	var original:Mesh=VolumeModels._recipe(rules.units.rivet_tank,"unit",0).body_mesh
	var changed:Array=original.surface_get_arrays(0)
	changed[Mesh.ARRAY_VERTEX][0]+=Vector3(.01,0,0)
	var stale:=ArrayMesh.new();stale.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,changed)
	VolumeModels.quality_sources[stale.get_instance_id()]="rivet/tank/body_mesh"
	check(VolumeModels.quality_mesh(stale,0)==stale,"stale geometry safely falls back to the intact source mesh")
	print("UNIT_LOD_PROVENANCE ",JSON.stringify({"checks":checks,"failures":failures,"reduced_by_faction":reduced,"templates":records.size()}))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
