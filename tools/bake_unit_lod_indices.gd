extends SceneTree

## Offline authoring only. All rigid entity parts, buildings, connected walls,
## construction stages and the continuous skinned hand share the tier contract.
const LOD = preload("res://scripts/offline_mesh_lod.gd")
const SCAFFOLD = preload("res://scripts/construction_scaffold.gd")
var bake_cache: Dictionary = {}
var records: Dictionary = {"far": {}, "extreme": {}}
var signatures: Dictionary = {}
var statistics: Dictionary = {}
var coverage: Dictionary = {}

func _initialize() -> void:
	var rules: Dictionary = RulesLoader.load_rules()
	if rules.is_empty(): push_error("LOD bake requires valid imported rules"); quit(2); return
	for kind in ["unit", "building"]:
		var catalog: Dictionary = rules.units if kind == "unit" else rules.buildings
		for id in catalog:
			var spec: Dictionary = catalog[id]
			if not VolumeModels.supports(spec, kind):
				coverage[id] = {"kind": kind, "faction": spec.faction, "representation": "illustrated cutout; authored card tiers", "templates": []}
				continue
			var variants: Array[Dictionary] = [spec]
			if kind == "building" and spec.get("role", "") in ["wall", "barricade"]:
				for mask in range(1, 16):
					var connected: Dictionary = spec.duplicate()
					connected.wall_mask = mask
					variants.append(connected)
			var templates: Array = []
			for variant in variants:
				var recipe: Dictionary = VolumeModels._recipe(variant, kind, 0)
				var sources: Dictionary = VolumeModels.lod_recipe_meshes(recipe, variant, kind)
				for template in sources:
					_record(template, sources[template], {"kind": kind, "faction": spec.faction, "art": spec.art})
					templates.append(template)
			coverage[id] = {"kind": kind, "faction": spec.faction, "representation": "direct skin" if spec.art == "creator_hand" else "solid model", "templates": templates}
			if spec.art == "harvester":
				var model: Dictionary = VolumeModels.create_model(spec, kind, 0, true)
				_record("shared/harvester/cargo_mesh", VolumeModels.cargo_mesh, {"kind": "shared", "faction": "shared", "art": "cargo"})
				_record("shared/harvester/cutter_mesh", VolumeModels.cutter_mesh, {"kind": "shared", "faction": "shared", "art": "drill"})
				model.root.free()
	var sizes: Dictionary = {}
	for spec in rules.buildings.values(): sizes[float(spec.get("size", 3.0))] = true
	for size in sizes:
		var scaffold: Dictionary = SCAFFOLD.create_model({"size": size}, 0)
		for index in range(scaffold.meshes.size()):
			var template: String = "shared/scaffold/" + str(size) + "/mesh:" + str(index)
			_record(template, scaffold.meshes[index].mesh, {"kind": "scaffold", "faction": "shared", "art": str(size)})
		scaffold.root.free()
	var resource := Resource.new()
	resource.set_meta("lod_tiers", records)
	resource.set_meta("lod_indices", records.far)
	resource.set_meta("source_signatures", signatures)
	resource.set_meta("lod_schema", 3)
	resource.set_meta("source_note", "Offline 30-degree meshoptimizer hierarchy; complete source major opaque wall/roof/deck/wing planes restored, reversed coarse faces rejected, original attributes/skin/materials, protected ownership/paper insignia and exact 26-direction support. No runtime simplifier.")
	resource.set_meta("opaque_surface_guard", 1)
	resource.set_meta("component_intermediate", 1)
	resource.set_meta("template_statistics", statistics)
	resource.set_meta("catalog_coverage", coverage)
	var error: int = ResourceSaver.save(resource, "res://assets/models/unit_lod_indices.res")
	var totals: Dictionary = {"full": 0, "far": 0, "extreme": 0, "reduced_far": 0, "reduced_extreme": 0, "distinct_tiers": 0}
	for row in statistics.values():
		for tier in ["full", "far", "extreme"]: totals[tier] += int(row[tier])
		if row.far < row.full: totals.reduced_far += 1
		if row.extreme < row.full: totals.reduced_extreme += 1
		if row.extreme < row.far: totals.distinct_tiers += 1
	print("BAKED_ENTITY_LOD ", JSON.stringify({"schema": 3, "templates": signatures.size(), "catalog_specs": coverage.size(), "triangles": totals, "error": error}))
	quit(error)

func _record(template: String, source: Mesh, description: Dictionary) -> void:
	if signatures.has(template): return
	var key: int = source.get_instance_id()
	if not bake_cache.has(key): bake_cache[key] = LOD.bake(source, VolumeModels.player_color(0), VolumeModels.PAPER, {"preserve_opaque_planes": true, "decorative_color": VolumeModels.INK, "reject_reversed_faces": true, "distinct_component_intermediate": true})
	var baked: Dictionary = bake_cache[key]
	for tier in ["far", "extreme"]: records[tier][template] = baked[tier]
	signatures[template] = VolumeModels.lod_source_signature(source, 0)
	statistics[template] = description.duplicate()
	statistics[template].merge(baked.counts)
