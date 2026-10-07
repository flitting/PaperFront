extends SceneTree

const Buildings = preload("res://scripts/faction_building_models.gd")
const Models = preload("res://scripts/volume_models.gd")
# Measure the actual union of triangle solids above the plinth. The XZ samples
# retain world scale: neither a large base nor a high flag can count as a house.
const SAMPLE_RESOLUTION: int = 72
const PLINTH_CUTOFF: float = .35
const USEFUL_COLUMN_HEIGHT: float = .45
const MIN_MASS_COVERAGE = {
	"hq": .46, "outpost": .40, "power": .42, "refinery": .40,
	"barracks": .45, "factory": .38, "tower": .33, "tech": .43,
	"repair": .27, "command": .40, "airfield": .23,
}
const MIN_MASS_VOLUME = {
	"hq": 9.0, "outpost": 3.0, "power": 3.7, "refinery": 7.0,
	"barracks": 4.0, "factory": 7.0, "tower": 1.2, "tech": 4.0,
	"repair": 2.6, "command": 3.8, "airfield": 5.5,
}
var failures: Array[String] = []
var checks: int = 0

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

# Integrate vertical ray intervals using winding counts, so overlapping boxes
# are counted once rather than inflating mass. Godot front winding is clockwise.
# Rasterizing triangle bounding boxes avoids a sample x triangle full scan.
static func measure_vertices(vertices: PackedVector3Array, footprint: float, resolution: int = SAMPLE_RESOLUTION) -> Dictionary:
	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	var finite: bool = true
	for point: Vector3 in vertices:
		if not point.is_finite(): finite = false; continue
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	var cells: Array = []
	cells.resize(resolution * resolution)
	for i in range(cells.size()): cells[i] = []
	var step: float = footprint / float(resolution)
	var origin: float = -footprint * .5
	var signed_mesh_volume: float = 0.0
	for i in range(0, vertices.size() - 2, 3):
		var a: Vector3 = vertices[i]
		var b: Vector3 = vertices[i + 1]
		var c: Vector3 = vertices[i + 2]
		if not a.is_finite() or not b.is_finite() or not c.is_finite(): continue
		signed_mesh_volume -= a.dot(b.cross(c)) / 6.0
		var denominator: float = (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
		if absf(denominator) < .000001: continue
		var winding: int = 1 if (b - a).cross(c - a).y > 0.0 else -1
		var x0: int = clampi(floori((minf(a.x, minf(b.x, c.x)) - origin) / step), 0, resolution - 1)
		var x1: int = clampi(floori((maxf(a.x, maxf(b.x, c.x)) - origin) / step), 0, resolution - 1)
		var z0: int = clampi(floori((minf(a.z, minf(b.z, c.z)) - origin) / step), 0, resolution - 1)
		var z1: int = clampi(floori((maxf(a.z, maxf(b.z, c.z)) - origin) / step), 0, resolution - 1)
		for z in range(z0, z1 + 1):
			# Irrational offsets avoid shared diagonal/edge double hits.
			var pz: float = origin + (float(z) + .51719) * step
			for x in range(x0, x1 + 1):
				var px: float = origin + (float(x) + .41357) * step
				var wa: float = ((b.z - c.z) * (px - c.x) + (c.x - b.x) * (pz - c.z)) / denominator
				var wb: float = ((c.z - a.z) * (px - c.x) + (a.x - c.x) * (pz - c.z)) / denominator
				var wc: float = 1.0 - wa - wb
				if minf(wa, minf(wb, wc)) < -.00001: continue
				cells[z * resolution + x].append(Vector2(wa * a.y + wb * b.y + wc * c.y, winding))
	var volume: float = 0.0
	var useful_columns: int = 0
	var slice_08: int = 0
	var slice_13: int = 0
	for events: Array in cells:
		events.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		var winding: int = 0
		var previous_y: float = 0.0
		var thickness: float = 0.0
		var present_08: bool = false
		var present_13: bool = false
		for event: Vector2 in events:
			if winding > 0:
				thickness += maxf(0.0, event.x - maxf(previous_y, PLINTH_CUTOFF))
				present_08 = present_08 or (previous_y <= .8 and event.x >= .8)
				present_13 = present_13 or (previous_y <= 1.3 and event.x >= 1.3)
			winding += roundi(event.y)
			previous_y = event.x
		volume += thickness * step * step
		if thickness >= USEFUL_COLUMN_HEIGHT: useful_columns += 1
		if present_08: slice_08 += 1
		if present_13: slice_13 += 1
	var area: float = footprint * footprint
	return {
		"finite": finite, "bounds_min": [minimum.x, minimum.y, minimum.z],
		"bounds_max": [maximum.x, maximum.y, maximum.z],
		"actual_aabb": [maximum.x-minimum.x, maximum.y-minimum.y, maximum.z-minimum.z],
		"centered_extent": [maxf(absf(minimum.x),absf(maximum.x))*2.0, maximum.y, maxf(absf(minimum.z),absf(maximum.z))*2.0],
		"mass_volume_above_plinth": volume, "mass_coverage": float(useful_columns)/float(cells.size()),
		"mass_area": float(useful_columns)*step*step, "slice_08_coverage": float(slice_08)/float(cells.size()),
		"slice_13_coverage": float(slice_13)/float(cells.size()), "signed_sum_volume": signed_mesh_volume,
		"footprint_area": area, "sample_resolution": resolution, "vertices": vertices.size(),
		"mass_to_actual_aabb_ratio": volume / maxf(.001, (maximum.x-minimum.x)*(maximum.z-minimum.z)*(maximum.y-minimum.y)),
		"mass_to_rule_envelope_ratio": volume / maxf(.001, area*maximum.y),
	}

static func recipe_vertices(recipe: Dictionary) -> PackedVector3Array:
	var vertices := PackedVector3Array()
	var meshes: Array = [[recipe.body_mesh, Vector3.ZERO]]
	if recipe.has("turret_mesh"): meshes.append([recipe.turret_mesh, recipe.turret_pos])
	for pair: Array in meshes:
		var mesh: ArrayMesh = pair[0]
		var offset: Vector3 = pair[1]
		for surface in range(mesh.get_surface_count()):
			var positions: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for position: Vector3 in positions: vertices.append(position + offset)
	return vertices

func _initialize() -> void:
	var rules: Dictionary = RulesLoader.load_rules("res://data/rules.json", false)
	var builder = Buildings
	var report_path: String = "res://artifacts/faction_validation/building_geometry.json"
	if "--before" in OS.get_cmdline_user_args():
		builder = GDScript.new()
		builder.source_code = FileAccess.get_file_as_string("res://artifacts/building_repair/before/faction_building_models.gd.txt")
		var reload_error: int = builder.reload()
		if reload_error != OK: push_error("Preserved baseline failed to compile"); quit(1); return
		report_path = "res://artifacts/building_repair/before/building_mass_geometry.json"
	var report: Dictionary = {"pairs": {}, "failures": failures, "source_sha256": builder.source_code.sha256_text(), "method": "72x72 vertical ray union of real triangles above y=.35; useful column >=.45 world units; includes turret; no per-model normalization"}
	var paper := PaperWorld.new()
	var tank_dimensions: Dictionary = {}
	var validated_buildings: int = 0
	for faction: String in ["kestrel", "rivet"]:
		tank_dimensions[faction] = Models._recipe(rules.units[faction + "_tank"], "unit", 0).dimensions
	for art: String in Buildings.ARTS:
		var pair: Dictionary = {}
		for faction: String in ["kestrel", "rivet"]:
			var id: String = faction + "_" + art
			if not rules.buildings.has(id): continue
			validated_buildings += 1
			var mesh = Models.CraftMesh.new()
			var recipe: Dictionary = builder.make(mesh, faction, art, 0)
			var spec: Dictionary = rules.buildings[id]
			var actual: Dictionary = measure_vertices(recipe_vertices(recipe), float(spec.size))
			var extent := Vector3(actual.centered_extent[0], actual.centered_extent[1], actual.centered_extent[2])
			expect(actual.finite, id + " contains nonfinite mesh vertices")
			expect(extent.x <= float(spec.size) + .005 and extent.z <= float(spec.size) + .005, id + " actual mesh exceeds centered rule footprint: " + str(extent))
			expect((recipe.dimensions as Vector3).is_equal_approx(extent), id + " declared dimensions differ from real body/turret vertices")
			expect(actual.mass_coverage >= float(MIN_MASS_COVERAGE[art]), id + " has too little useful solid footprint: %.3f < %.3f" % [actual.mass_coverage, MIN_MASS_COVERAGE[art]])
			expect(actual.mass_volume_above_plinth >= float(MIN_MASS_VOLUME[art]), id + " has too little real mass above base: %.3f < %.3f" % [actual.mass_volume_above_plinth, MIN_MASS_VOLUME[art]])
			var tank: Vector3 = tank_dimensions[faction]
			var paper_height: float = paper._dimensions(rules.units[faction + "_rifle"], "unit").y
			if art in ["hq", "factory", "refinery"]:
				expect(maxf(extent.x,extent.z) >= tank.x * 1.40, id + " major building is too narrow relative to baked tank")
				expect(actual.mass_volume_above_plinth >= tank.x * tank.y * tank.z * 1.55, id + " major building lacks bulk relative to baked tank")
			var owner_vertices: int = 0
			var faction_vertices: int = 0
			for index: int in range(mesh.vertices.size()):
				if mesh.colors[index] == Buildings.OWNER[0]: owner_vertices += 1
				if mesh.colors[index] == (Buildings.RED if faction == "rivet" else Buildings.BLUE): faction_vertices += 1
			expect(owner_vertices >= 24, id + " lacks owner plates")
			expect(faction_vertices >= 36, id + " lacks faction paint")
			actual.vertex_digest = hash(mesh.vertices)
			actual.dimensions = [extent.x, extent.y, extent.z]
			actual.owner_vertices = owner_vertices
			actual.faction_vertices = faction_vertices
			actual.turret = recipe.has("turret_mesh")
			actual.rule_footprint = float(spec.size)
			actual.tank_dimensions = [tank.x, tank.y, tank.z]
			actual.paper_card_height = paper_height
			actual.solid_parts_count = recipe.get("solid_parts", []).size()
			var verified_parts: int = 0
			for part: Dictionary in recipe.get("solid_parts", []):
				var first: int = int(part.get("vertex_start", -1))
				var end: int = int(part.get("vertex_end", -1))
				var valid_range: bool = first >= 0 and end > first and end <= mesh.vertices.size() and first % 3 == 0 and end % 3 == 0
				expect(valid_range, id + " solid part points outside real triangle vertices")
				if not valid_range: continue
				var part_vertices: PackedVector3Array = mesh.vertices.slice(first, end)
				var closed_volume: float = 0.0
				for index in range(0, part_vertices.size(), 3):
					closed_volume -= part_vertices[index].dot(part_vertices[index+1].cross(part_vertices[index+2])) / 6.0
				expect(closed_volume > .002, id + " solid part has no positive closed triangle volume")
				var center: Vector3 = part.center
				var declared: Vector3 = part.size
				for vertex: Vector3 in part_vertices:
					var local: Vector3 = (vertex-center).abs()
					if local.x > declared.x*.5+.13 or local.y > declared.y*.5+.13 or local.z > declared.z*.5+.13:
						expect(false, id + " solid part metadata differs from actual vertex range")
						break
				verified_parts += 1
			actual.verified_solid_parts = verified_parts
			pair[faction] = actual
			if art == "tower":
				expect(recipe.has("turret_mesh") and recipe.muzzle_pos.x > .5, faction + " tower lacks independent +X weapon")
				if recipe.has("turret_mesh"):
					var swept_radius: float = 0.0
					var turret_mesh: ArrayMesh = recipe.turret_mesh
					for surface in range(turret_mesh.get_surface_count()):
						var turret_vertices: PackedVector3Array = turret_mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
						for vertex: Vector3 in turret_vertices:
							for recoil: float in [0.0, -float(recipe.get("recoil_distance", 0.0))]:
								swept_radius = maxf(swept_radius, Vector2(vertex.x+recoil,vertex.z).length())
					actual.turret_swept_radius = swept_radius
					var pivot: Vector3 = recipe.turret_pos
					expect(swept_radius+maxf(absf(pivot.x),absf(pivot.z)) <= float(spec.size)*.5+.005, id + " rotating/recoiling turret exceeds rule footprint")
		if pair.has("kestrel") and pair.has("rivet"):
			expect(pair.kestrel.vertex_digest != pair.rivet.vertex_digest, art + " uses identical faction geometry")
		report.pairs[art] = pair
	paper.free()
	report.checks = checks
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/faction_validation"))
	var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t")); file.close()
	print("Faction buildings: ", validated_buildings, " real mesh/mass/footprint/scale/paint checks, checks=", checks, ", failures=", failures)
	Models.recipes.clear()
	quit(0 if failures.is_empty() else 1)
