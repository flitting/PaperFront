extends SceneTree

const SCALE = preload("res://scripts/scenery_scale.gd")
const DEFAULT_INPUT: String = "res://data/golden_visual_northforest_v7.json"
const DEFAULT_OUTPUT: String = "res://data/golden_visual_paintedforest_v9.json"
var failures: Array[String] = []

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 0 and args.size() != 2:
		push_error("Usage: --script tools/build_painted_forest_fixture.gd -- [old.json new.json]")
		quit(2)
		return
	var input: String = args[0] if args.size() == 2 else DEFAULT_INPUT
	var output: String = args[1] if args.size() == 2 else DEFAULT_OUTPUT
	if input == output or FileAccess.file_exists(output):
		push_error("Retain the prior fixture; choose a fresh output path")
		quit(2)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(input))
	if not parsed is Dictionary:
		push_error("Input fixture is not a valid manifest")
		quit(2)
		return
	var before: Dictionary = parsed
	_check(GoldenVisual._manifest_hash(before) == str(before.fixture_hash), "Input official manifest hash is valid")
	var manifest: Dictionary = before.duplicate(true)
	var original_state: PackedByteArray = Marshalls.base64_to_raw(before.state_base64)
	var snapshot: Dictionary = bytes_to_var(original_state)
	var tree_positions: Dictionary = {}
	var trunk_positions: Dictionary = {}
	var corrected_count: int = 0
	var tree_count: int = 0
	var non_tree_count: int = 0
	for group_index: int in range(manifest.prop_batches.size()):
		var group: Dictionary = manifest.prop_batches[group_index]
		var old_group: Dictionary = before.prop_batches[group_index]
		var key: String = str(group.mesh_key)
		var is_tree: bool = key.begins_with("tree_") or key == "trunk"
		for index: int in range(group.transforms.size()):
			var values: Array = group.transforms[index]
			var old_values: Array = old_group.transforms[index]
			var original: Transform3D = GoldenVisual._array_transform(old_values)
			var corrected: Transform3D = SCALE.corrected(key, original)
			if not is_tree:
				_check(corrected == original and values == old_values, "Non-tree transform remains exactly unchanged")
				non_tree_count += 1
				continue
			tree_count += 1
			_check(corrected.origin == original.origin, "Tree position remains exactly unchanged")
			_check(corrected.basis.x == original.basis.x and corrected.basis.z == original.basis.z, "Tree horizontal basis axes remain exactly unchanged")
			_check(corrected.basis.y.length() <= maxf(corrected.basis.x.length(), corrected.basis.z.length()) * 1.08 + 0.000001, "Tree vertical stretch obeys the 1.08 cap")
			_check(original.basis.y.normalized().is_equal_approx(corrected.basis.y.normalized()), "Tree vertical rotation direction is preserved")
			_check(SCALE.corrected(key, corrected).is_equal_approx(corrected), "Aspect correction is idempotent")
			if corrected != original:
				corrected_count += 1
				# Preserve original JSON numbers for every untouched component;
				# converting the full basis would introduce float32 round trips.
				values[3] = corrected.basis.y.x
				values[4] = corrected.basis.y.y
				values[5] = corrected.basis.y.z
			for component: int in [0, 1, 2, 6, 7, 8, 9, 10, 11]:
				_check(values[component] == old_values[component], "Fixture horizontal axes and positions preserve exact JSON values")
			var position_key: String = JSON.stringify(old_values.slice(9, 12))
			var ratio: Vector3 = Vector3(corrected.basis.x.length(), corrected.basis.y.length(), corrected.basis.z.length())
			if key == "trunk":
				trunk_positions[position_key] = ratio
			else:
				tree_positions[position_key] = ratio
		var unchanged_group: Dictionary = group.duplicate(true)
		unchanged_group.transforms = old_group.transforms
		_check(unchanged_group == old_group, "Prop group metadata remains unchanged")
	_check(tree_positions.size() == trunk_positions.size(), "Tree and trunk position counts match")
	for position_key: String in tree_positions:
		_check(trunk_positions.has(position_key), "Every canopy has a trunk at the same position")
		if trunk_positions.has(position_key):
			_check((tree_positions[position_key] as Vector3).is_equal_approx(trunk_positions[position_key]), "Tree and trunk corrected proportions agree")
	# Only the resolved prop transforms and resulting manifest hash may change.
	for field: String in before:
		if field in ["prop_batches", "fixture_hash"]:
			continue
		_check(manifest[field] == before[field], "Manifest field %s remains unchanged" % field)
	_check(Marshalls.base64_to_raw(manifest.state_base64) == original_state, "Serialized simulation snapshot is byte-identical")
	var result_snapshot: Dictionary = bytes_to_var(Marshalls.base64_to_raw(manifest.state_base64))
	_check(result_snapshot.map == snapshot.map and result_snapshot.entities == snapshot.entities, "Map and entities remain unchanged")
	_check(corrected_count > 0, "The fixture includes corrected trees")
	if not failures.is_empty():
		_finish_failures()
		return
	var save_error: String = GoldenVisual.export_manifest(output, manifest)
	_check(save_error.is_empty(), "Official manifest export succeeds: " + save_error)
	if failures.is_empty():
		var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output))
		_check(GoldenVisual._manifest_hash(saved) == str(saved.fixture_hash), "Saved official manifest hash validates")
		_check(saved.state_base64 == before.state_base64 and saved.entities == before.entities and saved.map_hash == before.map_hash, "Saved snapshot, entity metadata and map identity remain unchanged")
		for group_index: int in range(saved.prop_batches.size()):
			var group: Dictionary = saved.prop_batches[group_index]
			var old_group: Dictionary = before.prop_batches[group_index]
			if not str(group.mesh_key).begins_with("tree_") and str(group.mesh_key) != "trunk":
				_check(group == old_group, "Saved non-tree group remains exactly unchanged")
	if not failures.is_empty():
		_finish_failures()
		return
	print("PAINTED_FOREST_FIXTURE ", output, " trees_and_trunks=", tree_count, " corrected=", corrected_count, " paired_positions=", tree_positions.size(), " unchanged_non_trees=", non_tree_count, " fixture_hash=", manifest.fixture_hash)
	print("Validated exact horizontal axes, positions, non-tree transforms, tree/trunk proportions, byte-identical simulation snapshot, map/entities and official saved hash.")
	quit()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish_failures() -> void:
	for message: String in failures:
		push_error(message)
	quit(1)
