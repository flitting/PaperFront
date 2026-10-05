extends RefCounted

## Two exact, derived terrain entries. Gameplay state is never cached here.
const DIRECTORY = "user://terrain_mesh_cache_v1"
const SCHEMA = 2
const DEPENDENCIES = [
	"scripts/landscape.gd", "scripts/terrain_resource_cache.gd", "scripts/map_data.gd",
	"scripts/scenery_scale.gd", "scripts/cliff_craft.gd", "scripts/contextual_props.gd",
	"scripts/north_context.gd", "scripts/foreground_grove.gd", "scripts/pine_model.gd",
	"scripts/battlefield_catalog.gd", "scripts/competitive_layout.gd", "scripts/biome_scenery.gd",
	"scripts/city_layout.gd", "scripts/city_environment_models.gd", "assets/environment/paper_environment.gdshader",
	"assets/textures/pigment_noise.png"
]

static func key_for(inputs:Array) -> String:
	var manifest:Dictionary={}
	var path:String="res://data/performance_build_manifest.json"
	if FileAccess.file_exists(path):
		var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:manifest=parsed.get("files",{})
	var source_project:bool=FileAccess.file_exists("res://scripts/landscape.gd")
	var signatures:Array=[SCHEMA,Engine.get_version_info().string]
	for dependency in DEPENDENCIES:
		var digest:String=FileAccess.get_sha256("res://"+dependency) if source_project else str(manifest.get(dependency,""))
		if digest.is_empty():return ""
		signatures.append([dependency,digest])
	var hash:=HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(signatures));hash.update(var_to_bytes(inputs))
	return hash.finish().hex_encode()

static func load_entry(key:String,directory:String=DIRECTORY) -> Dictionary:
	if key.is_empty():return {}
	var path:String=directory.path_join(key+".res")
	var bundled:bool=false
	if not FileAccess.file_exists(path) and directory==DIRECTORY:
		path="res://assets/terrain_cache/"+key+".res"
		bundled=true
	if not FileAccess.file_exists(path):return {}
	var resource:Resource=ResourceLoader.load(path,"Resource",ResourceLoader.CACHE_MODE_IGNORE)
	if resource==null or int(resource.get_meta("schema",0))!=SCHEMA or str(resource.get_meta("key",""))!=key:return {}
	var record:Variant=resource.get_meta("terrain",{})
	if not record is Dictionary or not record.get("nodes") is Array or not record.get("stats") is Dictionary:return {}
	for node in record.nodes:
		if not node is Dictionary or not node.get("mesh") is ArrayMesh or not node.get("name") is String or not node.has("shadow"):return {}
		if node.has("navigation_top_ranges"):
			var ranges:Array[Vector2i]=[]
			ranges.assign(node.navigation_top_ranges)
			node.navigation_top_ranges=ranges
	record.cache_source="bundled" if bundled else "user"
	return record

static func store_entry(key:String,record:Dictionary,directory:String=DIRECTORY,retain:int=2) -> int:
	if key.is_empty():return ERR_INVALID_PARAMETER
	var error:int=DirAccess.make_dir_recursive_absolute(directory)
	if error!=OK:return error
	var resource:=Resource.new()
	resource.set_meta("schema",SCHEMA);resource.set_meta("key",key);resource.set_meta("terrain",record)
	var temporary:String=directory.path_join("pending_%d.res"%OS.get_process_id())
	error=ResourceSaver.save(resource,temporary,ResourceSaver.FLAG_COMPRESS)
	if error!=OK:return error
	var path:String=directory.path_join(key+".res")
	error=DirAccess.rename_absolute(temporary,path)
	if error!=OK:
		DirAccess.remove_absolute(temporary)
		return error
	# Keep this entry and the newest other completed cache; never touch saves.
	var other:Array[String]=[]
	for name in DirAccess.get_files_at(directory):
		if name.length()==68 and name.ends_with(".res") and name!=key+".res":other.append(name)
	other.sort_custom(func(a,b):return FileAccess.get_modified_time(directory.path_join(a))>FileAccess.get_modified_time(directory.path_join(b)))
	if retain>0:
		for index in range(maxi(0,retain-1),other.size()):DirAccess.remove_absolute(directory.path_join(other[index]))
	return OK
