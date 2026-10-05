extends SceneTree
const Cache=preload("res://scripts/terrain_resource_cache.gd")
var failures:Array[String]=[]
var checks:int=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures.append(message)
func _initialize()->void:
	var directory:String="user://terrain_cache_test_%d"%OS.get_process_id()
	var key:String=Cache.key_for(["test",73026,[0,1,2]])
	check(key.length()==64 and key!=Cache.key_for(["test",73027,[0,1,2]]),"input and source fingerprint is deterministic and sensitive to map inputs")
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.FORWARD])
	arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP])
	arrays[Mesh.ARRAY_COLOR]=PackedColorArray([Color.RED,Color.GREEN,Color.BLUE])
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material:=StandardMaterial3D.new();material.vertex_color_use_as_albedo=true;material.roughness=.95
	mesh.surface_set_material(0,material)
	var record:Dictionary={"nodes":[{"name":"Ground_0_0","mesh":mesh,"shadow":0,"navigation_top_ranges":[Vector2i(0,3)]}],"stats":{"terrain_triangles":1}}
	check(Cache.store_entry(key,record,directory)==OK,"derived terrain saves atomically")
	var restored:Dictionary=Cache.load_entry(key,directory)
	check(not restored.is_empty() and restored.stats==record.stats and restored.nodes[0].navigation_top_ranges==record.nodes[0].navigation_top_ranges,"terrain statistics and navigation ranges round-trip")
	if not restored.is_empty():
		var recovered:Array=restored.nodes[0].mesh.surface_get_arrays(0)
		var original:Array=mesh.surface_get_arrays(0)
		check(recovered==original,"all serialized mesh arrays remain exactly equal")
		check(restored.nodes[0].mesh.surface_get_material(0).vertex_color_use_as_albedo,"material state survives serialization")
	var bad_key:String="f".repeat(64)
	var bad:=Resource.new();bad.set_meta("schema",Cache.SCHEMA);bad.set_meta("key","wrong");bad.set_meta("terrain",record)
	ResourceSaver.save(bad,directory.path_join(bad_key+".res"))
	check(Cache.load_entry(bad_key,directory).is_empty(),"mismatched cache metadata is rejected")
	Cache.store_entry("1".repeat(64),record,directory)
	Cache.store_entry("2".repeat(64),record,directory)
	check(DirAccess.get_files_at(directory).size()==2,"only two completed cache entries are retained")
	for name in DirAccess.get_files_at(directory):DirAccess.remove_absolute(directory.path_join(name))
	DirAccess.remove_absolute(directory)
	print("TERRAIN_DISK_CACHE ",JSON.stringify({"checks":checks,"failures":failures}))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
