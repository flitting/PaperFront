extends SceneTree

const LOD = preload("res://scripts/offline_mesh_lod.gd")
const SCAFFOLD = preload("res://scripts/construction_scaffold.gd")
var failures: Array[String] = []
var checks: int = 0
var reduced: Dictionary = {}
var distinct: Dictionary = {}
var visited: Dictionary = {}
var signatures: Dictionary
var tiers: Dictionary

func check(value: bool, message: String) -> void:
	checks += 1
	if not value and failures.size() < 30: failures.append(message)

func _initialize() -> void:
	var rules: Dictionary = RulesLoader.load_rules()
	var resource: Resource = VolumeModels.UNIT_LOD_RESOURCE
	signatures = resource.get_meta("source_signatures", {})
	tiers = resource.get_meta("lod_tiers", {})
	var coverage: Dictionary = resource.get_meta("catalog_coverage", {})
	check(coverage.size() == rules.units.size() + rules.buildings.size(), "baked catalog coverage matches the current unit and building catalogs without retired blueprints")
	check(int(resource.get_meta("lod_schema", 0)) == 3, "two offline tiers use schema3 provenance")
	check(int(resource.get_meta("opaque_surface_guard",0)) == 1, "opaque surface algorithm version rejects old unsafe reductions")
	check(int(resource.get_meta("component_intermediate",0))==1,"structure-aware intermediate tier is present")
	check(tiers.has("far") and tiers.has("extreme"), "both far and extreme assets are present")
	for kind in ["unit", "building"]:
		var catalog: Dictionary = rules.units if kind == "unit" else rules.buildings
		for id in catalog:
			var spec: Dictionary = catalog[id]
			check(coverage.has(id), "catalog coverage includes " + id)
			if not VolumeModels.supports(spec, kind):
				check(coverage[id].representation.begins_with("illustrated cutout"), "cutout infantry is explicitly delegated to authored card tiers " + id)
				continue
			for team in range(8):
				var variants: Array[Dictionary] = [spec]
				if kind == "building" and spec.get("role", "") in ["wall", "barricade"]:
					for mask in range(1, 16):
						var connected: Dictionary = spec.duplicate()
						connected.wall_mask = mask
						variants.append(connected)
				for variant in variants:
					var recipe: Dictionary = VolumeModels._recipe(variant, kind, team)
					var sources: Dictionary = VolumeModels.lod_recipe_meshes(recipe, variant, kind)
					for key in sources: _verify(sources[key], key, team, spec.faction, kind)
				if spec.art == "creator_hand":
					var hand: Dictionary = VolumeModels.create_model(spec, kind, team, true)
					check(hand.skinned_mesh.mesh == VolumeModels._recipe(spec, kind, team).body_mesh, "direct skin shares the provenance mesh owner " + str(team))
					check(hand.skinned_mesh.skin.get_bind_count() == 16 and hand.skeleton.get_bone_count() == 16, "hand keeps its deform bindings owner " + str(team))
					hand.root.free()
	for faction in rules.factions:
		for kind in ["unit", "building"]:
			check(int(reduced.get(str(faction) + "/" + kind, 0)) > 0, "offline reductions include " + str(faction) + " " + kind)
			check(int(distinct.get(str(faction) + "/" + kind, 0)) > 0, "distinct far/extreme topologies include " + str(faction) + " " + kind)
	for team in range(8):
		for size in range(1, 7):
			var scaffold: Dictionary = SCAFFOLD.create_model({"size": size}, team)
			for index in range(scaffold.meshes.size()): _verify(scaffold.meshes[index].mesh, "shared/scaffold/" + str(float(size)) + "/mesh:" + str(index), team, "shared", "scaffold")
			scaffold.root.free()
	var harvester: Dictionary = VolumeModels.create_model(rules.units.rivet_harvester, "unit", 0, true)
	var shared: Dictionary = {"cargo_mesh": VolumeModels.cargo_mesh, "cutter_mesh": VolumeModels.cutter_mesh}
	for field in shared: _verify(shared[field], "shared/harvester/" + field, 0, "shared", "shared")
	harvester.root.free()
	for key in signatures: check(visited.has(key), "every baked template is exercised " + key)
	_test_aggregate_tiers(rules)
	_test_major_face_coverage(rules)
	_test_stale_and_invalid(rules)
	print("ENTITY_LOD_PROVENANCE ", JSON.stringify({"checks": checks, "failures": failures, "reduced_by_faction_kind": reduced, "distinct_by_faction_kind": distinct, "templates": signatures.size()}))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _verify(source: Mesh, key: String, team: int, faction: String, kind: String) -> void:
	visited[key] = true
	check(signatures.has(key) and signatures[key] == VolumeModels.lod_source_signature(source, team), "source geometry, skin and material match " + key + " owner " + str(team))
	check(VolumeModels.quality_sources.get(source.get_instance_id(), "") == key, "runtime source registration includes " + key)
	var full_count: int = 0
	for surface in range(source.get_surface_count()): full_count += LOD.source_indices(source, surface).size()
	var counts: Array[int] = []
	for tier in ["far", "extreme"]:
		check(tiers[tier].has(key), "baked " + tier + " coverage includes " + key)
		var mesh: Mesh = VolumeModels.quality_mesh(source, team, tier)
		check(mesh.get_surface_count() == source.get_surface_count(), "surface topology retained " + key + " " + tier)
		var count: int = 0
		for surface in range(source.get_surface_count()):
			var original: Array = source.surface_get_arrays(surface)
			var result: Array = mesh.surface_get_arrays(surface)
			var attributes_equal: bool = true
			for attribute in range(Mesh.ARRAY_MAX):
				if attribute != Mesh.ARRAY_INDEX: attributes_equal = attributes_equal and _same_attribute(original[attribute], result[attribute], attribute)
			check(attributes_equal, "positions/paint/UV/skin exact and normals/tangents within GPU packing precision " + key + " " + tier)
			check(mesh.surface_get_material(surface) == source.surface_get_material(surface), "authored per-surface material retained " + key + " " + tier)
			var indices: PackedInt32Array = LOD.source_indices(mesh, surface)
			check(LOD._valid_indices(indices, source.surface_get_array_len(surface)), "valid indices " + key + " " + tier)
			count += indices.size()
			if team == 0:
				check(LOD._silhouette_safe(original[Mesh.ARRAY_VERTEX], LOD.source_indices(source, surface), indices), "exact 26-direction silhouette envelope " + key + " " + tier)
				var triangles: Dictionary = {}
				for offset in range(0, indices.size(), 3): triangles[LOD._triangle_key(indices, offset)] = true
				var protected: PackedInt32Array = LOD._protected_triangles(original, LOD.source_indices(source, surface), VolumeModels.player_color(team), VolumeModels.PAPER)
				var identity_retained: bool = true
				for offset in range(0, protected.size(), 3): identity_retained = identity_retained and triangles.has(LOD._triangle_key(protected, offset))
				check(identity_retained, "ownership plates, paper insignia and silhouette anchors retained " + key + " " + tier)
				var opaque: Dictionary = LOD.opaque_planes(original, LOD.source_indices(source,surface), VolumeModels.INK)
				var opaque_retained: bool = true
				for offset in range(0,opaque.indices.size(),3):opaque_retained=opaque_retained and triangles.has(LOD._triangle_key(opaque.indices,offset))
				check(opaque_retained,"complete major opaque walls, decks, roofs and wings retained "+key+" "+tier)
				check(mesh==source or LOD.reversed_faces(original,indices)==0,"no reversed coarse faces "+key+" "+tier)
		check(count <= full_count, "tier never increases triangle budget " + key + " " + tier)
		counts.append(count)
	check(counts[1] <= counts[0], "extreme topology is no heavier than far " + key)
	check(VolumeModels.quality_mesh(source, team) == VolumeModels.quality_mesh(source, team, "far"), "default far API remains compatible " + key)
	if counts[0] < full_count: reduced[faction + "/" + kind] = int(reduced.get(faction + "/" + kind, 0)) + 1
	if counts[1] < counts[0]: distinct[faction + "/" + kind] = int(distinct.get(faction + "/" + kind, 0)) + 1

func _same_attribute(first: Variant, second: Variant, attribute: int) -> bool:
	if first == second: return true
	# Godot's octahedral normal/tangent storage is encoded again when adding
	# an index buffer. This bound is below one stored normal quantization step;
	# position, owner colour, UVs and deform weights still compare exactly.
	if attribute not in [Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT] or first == null or second == null or first.size() != second.size(): return false
	for index in range(first.size()):
		if attribute == Mesh.ARRAY_NORMAL and (first[index] as Vector3).distance_to(second[index]) > 0.0002: return false
		if attribute == Mesh.ARRAY_TANGENT and absf(float(first[index]) - float(second[index])) > 0.0002: return false
	return true

func _clone(source: ArrayMesh, arrays: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(source.surface_get_primitive_type(0), arrays, [], {}, source.surface_get_format(0))
	mesh.surface_set_material(0, source.surface_get_material(0))
	return mesh

func _test_aggregate_tiers(rules:Dictionary)->void:
	for kind in ["unit","building"]:
		var catalog:Dictionary=rules.units if kind=="unit" else rules.buildings
		for id in catalog:
			var spec:Dictionary=catalog[id]
			if not VolumeModels.supports(spec,kind):continue
			var recipe:Dictionary=VolumeModels._recipe(spec,kind,0)
			var sources:Dictionary=VolumeModels.lod_recipe_meshes(recipe,spec,kind)
			var counts:Array[int]=[0,0,0]
			for key in sources:
				var full:Mesh=sources[key]
				var meshes:Array[Mesh]=[full,VolumeModels.quality_mesh(full,0,"far"),VolumeModels.quality_mesh(full,0,"extreme")]
				var weight:int=2 if "border_mesh" in key else 1
				for tier in range(3):
					for surface in range(meshes[tier].get_surface_count()):counts[tier]+=LOD.source_indices(meshes[tier],surface).size()/3*weight
			# The two thin crossed-beam barricades already contain 144/180 faces
			# and have no safe native reduction; all larger solid models do.
			if counts[0]>180:check(counts[0]>counts[1] and counts[1]>counts[2],"every complex whole model has genuinely distinct full/far/extreme geometry "+id+" "+str(counts))

func _test_major_face_coverage(rules: Dictionary) -> void:
	# Independent filled-face regression for the factory/aircraft failures.
	# Bounds and index validity can pass while a wall or wing becomes a line.
	for id in ["rivet_factory","rivet_hq","kestrel_factory","iron_factory","sky_factory","rivet_fighter","kestrel_fighter","iron_fighter","sky_fighter"]:
		var kind: String = "unit" if rules.units.has(id) else "building"
		var source: Mesh = VolumeModels._recipe(rules.units.get(id,rules.buildings.get(id,{})),kind,0).body_mesh
		var arrays: Array = source.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var full: PackedInt32Array = LOD.source_indices(source,0)
		var largest: float = 0.0
		for offset in range(0,full.size(),3):largest=maxf(largest,(vertices[full[offset+1]]-vertices[full[offset]]).cross(vertices[full[offset+2]]-vertices[full[offset]]).length()*.5)
		# Verify the importer index-space assumption against all attributes.
		var importer:=ImporterMesh.new()
		var supplied:Array=arrays.duplicate();supplied[Mesh.ARRAY_INDEX]=full
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,supplied,[],{},source.surface_get_material(0),"",source.surface_get_format(0))
		importer.generate_lods(30.0,25.0,[])
		check(importer.get_surface_arrays(0)==supplied,"offline importer retains canonical source attribute/index space "+id)
		for tier in ["far","extreme"]:
			var mesh:Mesh=VolumeModels.quality_mesh(source,0,tier)
			var indices:PackedInt32Array=LOD.source_indices(mesh,0)
			var faces:Array=[]
			for offset in range(0,indices.size(),3):
				var a:Vector3=vertices[indices[offset]]
				var first:Vector3=vertices[indices[offset+1]]-a
				var second:Vector3=vertices[indices[offset+2]]-a
				var cross:Vector3=first.cross(second)
				if cross.length_squared()<.0000000001:continue
				var d00:float=first.dot(first)
				var d01:float=first.dot(second)
				var d11:float=second.dot(second)
				faces.append({"a":a,"first":first,"second":second,"normal":cross.normalized(),"d00":d00,"d01":d01,"d11":d11,"inverse":1.0/(d00*d11-d01*d01)})
			var missing:int=0
			var points:int=0
			for offset in range(0,full.size(),3):
				var a:Vector3=vertices[full[offset]]
				var b:Vector3=vertices[full[offset+1]]
				var c:Vector3=vertices[full[offset+2]]
				var cross:Vector3=(b-a).cross(c-a)
				if cross.length()*.5<largest*.05:continue
				var normal:Vector3=cross.normalized()
				for weights in [Vector3.ONE/3.0,Vector3(.6,.2,.2),Vector3(.2,.6,.2),Vector3(.2,.2,.6)]:
					var point:Vector3=a*weights.x+b*weights.y+c*weights.z
					var covered:bool=false
					points+=1
					for face in faces:
						if normal.dot(face.normal)<.999:continue
						var local:Vector3=point-face.a
						if absf(local.dot(face.normal))>.0002:continue
						var d20:float=local.dot(face.first)
						var d21:float=local.dot(face.second)
						var u:float=(face.d11*d20-face.d01*d21)*face.inverse
						var v:float=(face.d00*d21-face.d01*d20)*face.inverse
						if u>=-.0001 and v>=-.0001 and u+v<=1.0001:covered=true;break
					if not covered:missing+=1
			check(missing==0,"major original opaque faces remain filled with correct winding "+id+" "+tier+" missing %d/%d interior points"%[missing,points])

func _test_stale_and_invalid(rules: Dictionary) -> void:
	var original: ArrayMesh = VolumeModels._recipe(rules.units.rivet_tank, "unit", 0).body_mesh
	var changed: Array = original.surface_get_arrays(0)
	changed[Mesh.ARRAY_VERTEX][0] += Vector3(.01, 0, 0)
	var stale: ArrayMesh = _clone(original, changed)
	VolumeModels.register_lod_source(stale, "rivet/tank/body_mesh")
	for tier in ["far", "extreme"]: check(VolumeModels.quality_mesh(stale, 0, tier) == stale, "stale geometry falls back intact " + tier)
	var repainted: ArrayMesh = _clone(original, original.surface_get_arrays(0))
	repainted.surface_set_material(0, StandardMaterial3D.new())
	VolumeModels.register_lod_source(repainted, "rivet/tank/body_mesh")
	check(VolumeModels.quality_mesh(repainted, 0) == repainted, "changed material invalidates provenance")
	var hand: ArrayMesh = VolumeModels._recipe(rules.units.sky_creator_hand, "unit", 0).body_mesh
	var skin_arrays: Array = hand.surface_get_arrays(0)
	skin_arrays[Mesh.ARRAY_WEIGHTS][0] += 0.1
	var changed_skin: ArrayMesh = _clone(hand, skin_arrays)
	VolumeModels.register_lod_source(changed_skin, "sky/creator_hand/body_mesh")
	check(VolumeModels.quality_mesh(changed_skin, 0, "extreme") == changed_skin, "changed skin weights invalidate provenance")
	var bad: ArrayMesh = _clone(original, original.surface_get_arrays(0))
	VolumeModels.register_lod_source(bad, "rivet/tank/body_mesh")
	var old: Array = tiers.far["rivet/tank/body_mesh"]
	tiers.far["rivet/tank/body_mesh"] = [PackedInt32Array([-1, 0, 1])]
	check(VolumeModels.quality_mesh(bad, 0) == bad, "invalid offline indices safely preserve full mesh")
	tiers.far["rivet/tank/body_mesh"] = old
