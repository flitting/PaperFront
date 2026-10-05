extends SceneTree
const COMPOSER = preload("res://scripts/contextual_props.gd")

# Explicit scenery variation. Terrain and the complete gameplay state remain
# the original serialized bytes; the manifest records only resolved new props.
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("Usage: --script tools/build_context_fixture.gd -- old.json new.json")
		quit(2)
		return
	var input: String = args[0]
	var output: String = args[1]
	if FileAccess.file_exists(output) or input == output:
		push_error("Fixture already exists; use another path and retain the prior scene")
		quit(2)
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(input))
	var state_bytes: PackedByteArray = Marshalls.base64_to_raw(manifest.state_base64)
	var snapshot: Dictionary = bytes_to_var(state_bytes)
	var old_groups: Array = manifest.prop_batches.duplicate(true)
	var new_groups: Array = COMPOSER.remap_prop_batches(snapshot.map, old_groups)
	var old_hash: String = JSON.stringify(old_groups,"",true).sha256_text()
	var new_hash: String = JSON.stringify(new_groups,"",true).sha256_text()
	if old_hash == new_hash:
		push_error("No scenery variation to evaluate")
		quit(2)
		return
	var walls: Array = []
	for group: Dictionary in new_groups:
		if str(group.mesh_key) in COMPOSER.MESH_KEYS:
			for values: Array in group.transforms:
				var cell := Vector2i(floori(values[9]),floori(values[11]))
				if int(snapshot.map.terrain[cell.y][cell.x]) != MapData.BLOCKED:
					push_error("Context wall outside a real blocked cell")
					quit(2)
					return
				walls.append({"cell":[cell.x,cell.y],"mesh":group.mesh_key,"transform":values})
	manifest.prop_batches = new_groups
	manifest["props_iteration"] = {"parent":input,"wall_cells":walls.size(),"old_prop_hash":old_hash,"new_prop_hash":new_hash,"map_and_entities":"unchanged"}
	var save_error: String = GoldenVisual.export_manifest(output,manifest)
	if not save_error.is_empty():
		push_error(save_error)
		quit(2)
		return
	var changed := FileAccess.open(output.get_basename()+"_changes.json",FileAccess.WRITE)
	changed.store_string(JSON.stringify({"input":input,"output":output,"walls":walls,"before_props_hash":old_hash,"after_props_hash":new_hash,"state_bytes_unchanged":state_bytes==Marshalls.base64_to_raw(manifest.state_base64)},"\t"));changed.close()
	print("CONTEXT_FIXTURE ",output," wall_cells=",walls.size()," fixture_hash=",manifest.fixture_hash)
	quit()
