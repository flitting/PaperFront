extends SceneTree

# Opt-in deterministic terrain experiment. It copies the existing fixed state,
# never respawns entities, rerolls props or overwrites the original manifest.
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("Usage: --script tools/build_landscape_fixture.gd -- old.json new.json")
		quit(2)
		return
	var input: String = args[0]
	var output: String = args[1]
	if FileAccess.file_exists(output) or input == output:
		push_error("New fixture path already exists; retain the original and use a new path")
		quit(2)
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(input))
	var snapshot: Dictionary = bytes_to_var(Marshalls.base64_to_raw(manifest.state_base64))
	var before: Dictionary = snapshot.map.duplicate(true)
	var immutable: Dictionary = snapshot.duplicate(true)
	immutable.erase("map")
	var non_map_before: PackedByteArray = var_to_bytes(immutable)
	var protected_points: Array = []
	var rules: Dictionary = RulesLoader.load_rules()
	for entity: Dictionary in snapshot.entities.values():
		var data: Dictionary = rules.buildings[entity.spec] if entity.kind == "building" else rules.units[entity.spec]
		var radius: float = float(data.size) * 0.74 if entity.kind == "building" else float(data.radius)
		protected_points.append({"pos":entity.pos,"radius":radius})
	var report: Dictionary = MapData.sculpt_battlefield(snapshot.map, protected_points)
	var errors: Array[String] = MapData.validate(snapshot.map)
	for point: Dictionary in protected_points:
		if not is_equal_approx(MapData.height_at(before,point.pos),MapData.height_at(snapshot.map,point.pos)):
			errors.append("Entity anchor changed: "+str(point.pos))
	var changes: Array = []
	for z: int in range(int(before.size)):
		for x: int in range(int(before.size)):
			if before.heights[z][x] == snapshot.map.heights[z][x] and before.terrain[z][x] == snapshot.map.terrain[z][x]:continue
			changes.append({"cell":[x,z],"before":[before.terrain[z][x],before.heights[z][x]],"after":[snapshot.map.terrain[z][x],snapshot.map.heights[z][x]]})
			if int(before.terrain[z][x]) != MapData.LAND or float(before.heights[z][x]) != 0.0:
				errors.append("Unauthorized terrain changed: "+str(Vector2i(x,z)))
	var after_immutable: Dictionary = snapshot.duplicate(true)
	after_immutable.erase("map")
	if var_to_bytes(after_immutable) != non_map_before:errors.append("Non-map state changed")
	if changes.is_empty():errors.append("No terrain change to evaluate")
	if not errors.is_empty():
		push_error(JSON.stringify(errors))
		quit(2)
		return
	var bytes: PackedByteArray = var_to_bytes(snapshot)
	manifest.state_base64 = Marshalls.raw_to_base64(bytes)
	manifest.state_hash = GoldenVisual._hash_bytes(bytes)
	manifest.map_hash = JSON.stringify(snapshot.map,"",true).sha256_text()
	manifest["terrain_iteration"] = {"parent":input,"change_count":changes.size(),"non_map_state_hash":GoldenVisual._hash_bytes(non_map_before),"entities_and_props":"unchanged"}
	# Entity records, camera, UI and prop transform arrays are retained verbatim.
	var save_error: String = GoldenVisual.export_manifest(output, manifest)
	if not save_error.is_empty():
		push_error(save_error)
		quit(2)
		return
	var change_file := FileAccess.open(output.get_basename()+"_changes.json",FileAccess.WRITE)
	change_file.store_string(JSON.stringify({"source":input,"output":output,"report":report,"changes":changes,"validation_errors":errors},"\t"));change_file.close()
	print("LANDSCAPE_FIXTURE ",output," changed_cells=",changes.size()," fixture_hash=",manifest.fixture_hash)
	quit()
