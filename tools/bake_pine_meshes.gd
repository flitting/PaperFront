extends SceneTree

# Rebuild with: godot --headless --path . --script res://tools/bake_pine_meshes.gd
# Base triangles remain the procedural reference. Godot LODs only replace
# indices at distance; the fused shadow mesh uses those exact same positions.
const PINE=preload("res://scripts/pine_model.gd")
const OUTPUT_DIR: String="res://assets/models"
const SOURCE_PATHS: Array[String]=["res://scripts/pine_model.gd","res://scripts/landscape.gd","res://tools/bake_pine_meshes.gd"]
var failures: Array[String]=[]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var error: Error=DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	if error!=OK:
		push_error("Cannot create pine resource directory: "+str(error))
		quit(1)
		return
	var source_hashes: Dictionary={}
	for path: String in SOURCE_PATHS:source_hashes[path]=FileAccess.get_sha256(path)
	var config: Dictionary={"normal_merge_angle":60.0,"normal_split_angle":25.0,"bone_transforms":[],"shadow_weld":"exact Vector3 positions; remapped LOD indices","generator":"ImporterMesh.generate_lods","godot_version":Engine.get_version_info().string}
	var report: Dictionary={"format":1,"source_hashes":source_hashes,"config":config,"variants":[]}
	var builder:=PaperLandscape.new()
	for variant: int in range(3):
		var data: Dictionary=builder._data()
		PINE.crown(builder,data,variant)
		var raw: ArrayMesh=builder._finish(data,"foliage")
		var source_arrays: Array=raw.surface_get_arrays(0)
		# Procedural data is a triangle list. ImporterMesh's simplifier needs
		# indexed connectivity; fuse only corners whose every attribute agrees.
		# Use the original floats for upload, not decoded octahedral normals
		# from the raw GPU mesh: decoding then encoding them again adds drift.
		var upload_arrays: Array=[]
		upload_arrays.resize(Mesh.ARRAY_MAX)
		upload_arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array(data.vertices)
		upload_arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array(data.normals)
		upload_arrays[Mesh.ARRAY_COLOR]=PackedColorArray(data.colors)
		upload_arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array(data.uvs)
		var indexed_arrays: Array=_index_surface(upload_arrays,source_arrays)
		var importer:=ImporterMesh.new()
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,indexed_arrays,[],{},null,"PineCrown_%d"%variant)
		importer.generate_lods(60.0,25.0,[])
		var mesh: ArrayMesh=importer.get_mesh()
		mesh.resource_name="BakedPineCrown_%d"%variant
		for surface: int in mesh.get_surface_count():mesh.surface_set_material(surface,null)
		var lods: Dictionary={}
		var lod_report: Array[Dictionary]=[]
		for lod: int in importer.get_surface_lod_count(0):
			var indices: PackedInt32Array=importer.get_surface_lod_indices(0,lod)
			var size: float=importer.get_surface_lod_size(0,lod)
			lods[size]=indices
			lod_report.append({"level":lod+1,"size":size,"triangles":indices.size()/3})
		var arrays: Array=mesh.surface_get_arrays(0)
		mesh.shadow_mesh=_fused_shadow(arrays,lods)
		mesh.set_meta("pine_source_hashes",source_hashes)
		mesh.set_meta("pine_bake_config",config)
		mesh.set_meta("pine_lods",lod_report)
		var file_path: String=OUTPUT_DIR+"/pine_%d.res"%variant
		error=ResourceSaver.save(mesh,file_path,ResourceSaver.FLAG_COMPRESS)
		if error!=OK:failures.append("Save failed "+file_path+": "+str(error))
		var saved: ArrayMesh=ResourceLoader.load(file_path,"ArrayMesh",ResourceLoader.CACHE_MODE_IGNORE) as ArrayMesh
		if saved==null:
			failures.append("Reload failed "+file_path)
			continue
		var base_triangles: int=_triangle_count(arrays)
		var saved_arrays: Array=saved.surface_get_arrays(0)
		var shadow_arrays: Array=saved.shadow_mesh.surface_get_arrays(0)
		if not _same_base_geometry(source_arrays,saved_arrays):failures.append("variant%d: changed base triangles/attributes"%variant)
		if saved.surface_get_material(0)!=null:failures.append("variant%d: material was serialized"%variant)
		if saved.shadow_mesh.get_aabb()!=saved.get_aabb():failures.append("variant%d: shadow bounds changed"%variant)
		if not _same_shadow_positions(saved_arrays,shadow_arrays):failures.append("variant%d: fused shadow changed base triangles"%variant)
		var saved_importer: ImporterMesh=ImporterMesh.from_mesh(saved)
		var saved_shadow_importer: ImporterMesh=ImporterMesh.from_mesh(saved.shadow_mesh)
		if saved_importer.get_surface_lod_count(0)!=lod_report.size() or saved_shadow_importer.get_surface_lod_count(0)!=lod_report.size():failures.append("variant%d: serialized LOD count differs"%variant)
		for level: int in saved_importer.get_surface_lod_count(0):
			if saved_importer.get_surface_lod_indices(0,level)!=importer.get_surface_lod_indices(0,level):failures.append("variant%d: serialized LOD indices differ"%variant)
			if not _same_shadow_positions(saved_arrays,shadow_arrays,saved_importer.get_surface_lod_indices(0,level),saved_shadow_importer.get_surface_lod_indices(0,level)):failures.append("variant%d: fused shadow changed LOD triangles"%variant)
		if lod_report.is_empty():failures.append("variant%d: automatic LOD generation produced no levels"%variant)
		var previous_triangles: int=base_triangles
		for lod: Dictionary in lod_report:
			if int(lod.triangles)>=previous_triangles:failures.append("variant%d: LOD does not reduce triangles"%variant)
			previous_triangles=int(lod.triangles)
		var variant_report: Dictionary={"variant":variant,"resource":file_path,"resource_sha256":FileAccess.get_sha256(file_path),"raw_triangles":_triangle_count(source_arrays),"base_triangles":base_triangles,"base_vertices":arrays[Mesh.ARRAY_VERTEX].size(),"shadow_vertices":shadow_arrays[Mesh.ARRAY_VERTEX].size(),"shadow_triangles":_triangle_count(shadow_arrays),"lods":lod_report,"base_geometry_unchanged":_same_base_geometry(source_arrays,saved_arrays),"serialized_lod_count":saved_importer.get_surface_lod_count(0),"exact_shadow_positions":_same_shadow_positions(saved_arrays,shadow_arrays),"material_cleared":saved.surface_get_material(0)==null}
		report.variants.append(variant_report)
		print("PINE_BAKE ",JSON.stringify(variant_report))
	builder.free()
	report["failures"]=failures
	var file:=FileAccess.open(OUTPUT_DIR+"/pine_meshes.json",FileAccess.WRITE)
	if file==null:failures.append("Cannot write pine metadata")
	else:file.store_string(JSON.stringify(report,"\t")+"\n")
	print("PINE_BAKE_RESULT ",JSON.stringify({"variants":report.variants.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)

func _triangle_count(arrays: Array) -> int:
	return (arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX]!=null and not arrays[Mesh.ARRAY_INDEX].is_empty() else arrays[Mesh.ARRAY_VERTEX].size())/3

func _same_shadow_positions(visible: Array, shadow: Array, visible_lod: PackedInt32Array=PackedInt32Array(), shadow_lod: PackedInt32Array=PackedInt32Array()) -> bool:
	var visible_indices: PackedInt32Array=visible_lod if not visible_lod.is_empty() else visible[Mesh.ARRAY_INDEX]
	var shadow_indices: PackedInt32Array=shadow_lod if not shadow_lod.is_empty() else shadow[Mesh.ARRAY_INDEX]
	if visible_indices.size()!=shadow_indices.size():return false
	for index: int in visible_indices.size():
		if visible[Mesh.ARRAY_VERTEX][visible_indices[index]]!=shadow[Mesh.ARRAY_VERTEX][shadow_indices[index]]:return false
	return true

func _same_base_geometry(raw: Array, baked: Array) -> bool:
	var raw_indices:=PackedInt32Array()
	var baked_indices:=PackedInt32Array()
	for index: int in _triangle_count(raw)*3:raw_indices.append(index if raw[Mesh.ARRAY_INDEX]==null or raw[Mesh.ARRAY_INDEX].is_empty() else raw[Mesh.ARRAY_INDEX][index])
	for index: int in _triangle_count(baked)*3:baked_indices.append(index if baked[Mesh.ARRAY_INDEX]==null or baked[Mesh.ARRAY_INDEX].is_empty() else baked[Mesh.ARRAY_INDEX][index])
	if raw_indices.size()!=baked_indices.size():return false
	for index: int in raw_indices.size():
		for attribute: int in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV]:
			var source=raw[attribute][raw_indices[index]]
			var output=baked[attribute][baked_indices[index]]
			if source!=output:
				print("PINE_BASE_DIFFERENCE ",index," attribute ",attribute," ",source," -> ",output)
				return false
	return true

func _index_surface(source: Array, encoded_identity: Array) -> Array:
	var vertices:=PackedVector3Array()
	var normals:=PackedVector3Array()
	var colors:=PackedColorArray()
	var uvs:=PackedVector2Array()
	var indices:=PackedInt32Array()
	var corners: Dictionary={}
	for index: int in source[Mesh.ARRAY_VERTEX].size():
		# Match exactly the attributes the original GPU mesh can represent.
		# Several original normal floats encode to the same octahedral value;
		# merging those already-identical rendered corners opens connectivity.
		var key: Array=[encoded_identity[Mesh.ARRAY_VERTEX][index],encoded_identity[Mesh.ARRAY_NORMAL][index],encoded_identity[Mesh.ARRAY_COLOR][index],encoded_identity[Mesh.ARRAY_TEX_UV][index]]
		if not corners.has(key):
			corners[key]=vertices.size()
			vertices.append(source[Mesh.ARRAY_VERTEX][index])
			normals.append(source[Mesh.ARRAY_NORMAL][index])
			colors.append(source[Mesh.ARRAY_COLOR][index])
			uvs.append(source[Mesh.ARRAY_TEX_UV][index])
		indices.append(corners[key])
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_COLOR]=colors
	arrays[Mesh.ARRAY_TEX_UV]=uvs
	arrays[Mesh.ARRAY_INDEX]=indices
	return arrays

func _fused_shadow(arrays: Array, lods: Dictionary) -> ArrayMesh:
	var positions: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var welded:=PackedVector3Array()
	var vertex_to_shadow:=PackedInt32Array()
	var by_position: Dictionary={}
	for point: Vector3 in positions:
		if not by_position.has(point):
			by_position[point]=welded.size()
			welded.append(point)
		vertex_to_shadow.append(int(by_position[point]))
	var source_indices:=PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX]!=null and not arrays[Mesh.ARRAY_INDEX].is_empty():source_indices=arrays[Mesh.ARRAY_INDEX]
	else:
		for index: int in positions.size():source_indices.append(index)
	var shadow_indices:=PackedInt32Array()
	for index: int in source_indices:shadow_indices.append(vertex_to_shadow[index])
	var shadow_lods: Dictionary={}
	for size: float in lods:
		var indices:=PackedInt32Array()
		for index: int in lods[size]:indices.append(vertex_to_shadow[index])
		shadow_lods[size]=indices
	var shadow_arrays: Array=[]
	shadow_arrays.resize(Mesh.ARRAY_MAX)
	shadow_arrays[Mesh.ARRAY_VERTEX]=welded
	shadow_arrays[Mesh.ARRAY_INDEX]=shadow_indices
	var shadow:=ArrayMesh.new()
	shadow.resource_name="ExactFusedPineShadow"
	shadow.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,shadow_arrays,[],shadow_lods)
	return shadow
