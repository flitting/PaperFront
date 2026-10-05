extends SceneTree
const GROVE = preload("res://scripts/foreground_grove.gd")

# One explicit scenery candidate, copied from a frozen match. No entities,
# old resolved prop transforms, heights, camera or clock are regenerated.
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("Usage: --script tools/build_foreground_fixture.gd -- old.json new.json")
		quit(2)
		return
	var input: String = args[0]
	var output: String = args[1]
	if FileAccess.file_exists(output) or input == output:
		push_error("Retain the old fixture; use a fresh output path")
		quit(2)
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(input))
	var snapshot: Dictionary = bytes_to_var(Marshalls.base64_to_raw(manifest.state_base64))
	var before: Dictionary = snapshot.map.duplicate(true)
	var immutable: Dictionary = snapshot.duplicate(true)
	immutable.erase("map")
	var non_map_bytes: PackedByteArray = var_to_bytes(immutable)
	var protected_points: Array = []
	var rules: Dictionary = RulesLoader.load_rules()
	for entity: Dictionary in snapshot.entities.values():
		var data: Dictionary = rules.buildings[entity.spec] if entity.kind == "building" else rules.units[entity.spec]
		protected_points.append({"pos": entity.pos, "radius": float(data.size) * 0.74 if entity.kind == "building" else float(data.radius)})
	var report: Dictionary = GROVE.apply_foreground(snapshot.map, protected_points)
	var errors: Array[String] = MapData.validate(snapshot.map)
	var changes: Array = []
	for z: int in range(int(before.size)):
		for x: int in range(int(before.size)):
			if before.heights[z][x] != snapshot.map.heights[z][x]:
				errors.append("Height changed at " + str(Vector2i(x,z)))
			if before.terrain[z][x] == snapshot.map.terrain[z][x]:continue
			if int(before.terrain[z][x]) != MapData.LAND or int(snapshot.map.terrain[z][x]) != MapData.BLOCKED:
				errors.append("Non-land obstruction changed at " + str(Vector2i(x,z)))
			changes.append({"cell":[x,z],"height":before.heights[z][x]})
	for key: String in before:
		if key not in ["terrain","foreground_grove"] and var_to_bytes(before[key]) != var_to_bytes(snapshot.map[key]):
			errors.append("Unrelated map field changed: " + key)
	var after_immutable: Dictionary = snapshot.duplicate(true)
	after_immutable.erase("map")
	if var_to_bytes(after_immutable) != non_map_bytes:errors.append("Non-map state changed")
	var old_groups: Array = manifest.prop_batches.duplicate(true)
	var new_groups: Array = GROVE.append_prop_batches(snapshot.map,old_groups)
	if new_groups.size() <= old_groups.size():errors.append("No new prop groups")
	for index: int in old_groups.size():
		if var_to_bytes(old_groups[index]) != var_to_bytes(new_groups[index]):errors.append("Old prop transform changed")
	if changes.is_empty():errors.append("No foreground change to evaluate")
	if not errors.is_empty():
		push_error(JSON.stringify(errors))
		quit(2)
		return
	var bytes: PackedByteArray = var_to_bytes(snapshot)
	manifest.state_base64 = Marshalls.raw_to_base64(bytes)
	manifest.state_hash = GoldenVisual._hash_bytes(bytes)
	manifest.map_hash = JSON.stringify(snapshot.map,"",true).sha256_text()
	manifest.prop_batches = new_groups
	manifest["foreground_iteration"] = {"parent":input,"blocked_cells":changes.size(),"non_map_state_hash":GoldenVisual._hash_bytes(non_map_bytes),"old_prop_groups_unchanged":true,"heights_unchanged":true}
	var save_error: String = GoldenVisual.export_manifest(output,manifest)
	if not save_error.is_empty():
		push_error(save_error)
		quit(2)
		return
	var change_file := FileAccess.open(output.get_basename()+"_changes.json",FileAccess.WRITE)
	change_file.store_string(JSON.stringify({"source":input,"output":output,"report":report,"changes":changes,"validation_errors":errors},"\t"));change_file.close()
	print("FOREGROUND_FIXTURE ",output," added_cells=",changes.size()," fixture_hash=",manifest.fixture_hash)
	quit()
