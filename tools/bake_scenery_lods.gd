extends SceneTree

## Offline only. Rebuild with godot --headless --path . --script this file.
## Runtime uses these indices, never ImporterMesh or a seed-specific proxy.
const LOD = preload("res://scripts/offline_mesh_lod.gd")
const SCENERY = preload("res://scripts/scenery_mesh_lod.gd")
const ENV = preload("res://scripts/city_environment_models.gd")
const CONTEXT = preload("res://scripts/contextual_props.gd")
const CATALOG = preload("res://scripts/battlefield_catalog.gd")
const OUTPUT: String = "res://assets/models/scenery_lod_indices.res"
var records: Dictionary = {}
var report: Array[Dictionary] = []
var signatures_by_id: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func collect(source: Mesh, label: String) -> void:
	if source == null or source.get_surface_count() == 0: return
	var id: int = source.get_instance_id()
	var signature: String = str(signatures_by_id.get(id, ""))
	if signature.is_empty(): signature = LOD.signature(source); signatures_by_id[id] = signature
	if records.has(signature): return
	var options: Dictionary = {"preserve_opaque_planes": not source.has_meta("pine_lods"), "reject_reversed_faces": not source.has_meta("pine_lods"), "decorative_color": VolumeModels.INK}
	var record: Dictionary = LOD.bake(source, Color.TRANSPARENT, Color.TRANSPARENT, options)
	records[signature] = {"far": record.far, "extreme": record.extreme}
	if source.has_meta("pine_lods"):
		for tier: String in ["far", "extreme"]:
			var arrays: Array = []
			for surface: int in source.get_surface_count(): arrays.append(SCENERY.coherent_surface(source.surface_get_arrays(surface), record[tier][surface]))
			records[signature][tier + "_arrays"] = arrays
	report.append({"label": label, "signature": signature, "triangles": record.counts})
	if report.size() % 25 == 0: print("SCENERY_LOD_PROGRESS ", report.size())

func run() -> void:
	# Collection never consumes a previous bake. This also makes rebuilding a
	# corrupt/stale resource safe without trying to upload its old mesh arrays.
	SCENERY._loaded = true
	SCENERY._resource = null
	# Regenerate the authored keys so stale asset source hashes cannot make the
	# bake accidentally validate only an old model instead of current geometry.
	var environment_keys: Dictionary = {}
	for name: String in DirAccess.get_files_at("res://assets/environment"):
		if not name.ends_with(".res"): continue
		var mesh: Mesh = load("res://assets/environment/" + name)
		var key: String = str(mesh.get_meta("environment_key", ""))
		if not key.is_empty(): environment_keys[key] = true
	for key: String in environment_keys:
		var parts: PackedStringArray = key.split(":")
		if parts[0] == "prop": collect(ENV.prop_mesh(parts[1], int(parts[2])), key)
		elif parts[0] == "house":
			var meshes: Dictionary = ENV.meshes(parts[1], float(parts[2]), int(parts[3]))
			collect(meshes.intact, key.trim_suffix(":rubble"))
			collect(meshes.rubble, key.trim_suffix(":rubble") + ":rubble")
	var builder := PaperLandscape.new()
	for key: String in ["tree_0", "tree_1", "tree_2", "trunk", "trunk_far", "trunk_distant", "rock_0", "rock_1", "rock_2", "fence", "ruin", "contact"] + CONTEXT.MESH_KEYS:
		collect(builder._prop_mesh(key), key)
	for variant: int in 3:
		collect(builder._crystal_cluster(variant), "crystal_%d" % variant)
		for kind: String in ["house", "wall"]:
			var meshes: Dictionary = BattlefieldRuins.meshes(kind, variant)
			collect(meshes.intact, "%s_%d" % [kind, variant])
			collect(meshes.rubble, "%s_%d_rubble" % [kind, variant])
	builder.free()
	# Bridge length/orientation/style and profile building heights come from all
	# six live map definitions; this collection deliberately omits heavy terrain.
	for mode: String in CATALOG.MODES + ["campaign", "dev", "handmade", "mountains", "mountains640"]:
		var sim := WarSimulation.new()
		sim.rules = RulesLoader.load_rules()
		sim.map = MapData.generate(mode, 7)
		sim.ruins = sim.map.ruins.duplicate(true)
		var scene := PaperLandscape.new()
		scene._initialize_build(sim)
		scene._build_environment()
		for ruin: Dictionary in sim.ruins: scene._build_ruin(ruin)
		for bridge: Dictionary in sim.map.bridges:
			var live: Dictionary = bridge.duplicate(true)
			live.alive = true
			scene._build_bridge(live)
		scene._flush_batches()
		for row: Dictionary in scene.lod_records: collect(row.source, mode + "/" + str(row.node.name))
		scene.free()
		print("SCENERY_LOD_MAP ", mode, " templates=", records.size())
	var resource := Resource.new()
	resource.set_meta("scenery_lod_schema", 2)
	resource.set_meta("mesh_tiers", records)
	resource.set_meta("source_note", "Safe 30-degree meshoptimizer topology tiers retaining major opaque source planes, authored attributes/materials and exact support envelope; full fallback for irreducible geometry; coherent pine normals.")
	var error: Error = ResourceSaver.save(resource, OUTPUT, ResourceSaver.FLAG_COMPRESS)
	var totals: Dictionary = {"full": 0, "far": 0, "extreme": 0}
	var irreducible: Array[String] = []
	for row: Dictionary in report:
		for tier: String in totals: totals[tier] += int(row.triangles[tier])
		if row.triangles.full == row.triangles.extreme: irreducible.append(row.label)
	var result: Dictionary = {"templates": records.size(), "triangles": totals, "irreducible": irreducible, "models": report, "error": error}
	FileAccess.open("res://assets/models/scenery_lod_meshes.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t") + "\n")
	print("SCENERY_LOD_BAKE ", JSON.stringify({"templates": records.size(), "triangles": totals, "irreducible": irreducible, "error": error}))
	quit(0 if error == OK else 1)
