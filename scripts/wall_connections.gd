extends RefCounted

## Visual connectivity only. The simulation retains its original one-cell
## footprint, collision and construction cost for every individual segment.
const EAST := 1
const SOUTH := 2
const WEST := 4
const NORTH := 8
const DIRECTIONS := [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]

static func is_wall(entity: Dictionary, rules: Dictionary) -> bool:
	return str(entity.get("kind", "")) == "building" and str(rules.buildings.get(entity.get("spec", ""), {}).get("role", "")) in ["wall", "barricade"]

static func _key(position: Vector2) -> Vector2i:
	# Keep half-cell placement and reject merely nearby, off-grid structures.
	return Vector2i(roundi(position.x * 1000.0), roundi(position.y * 1000.0))

static func masks(entities: Dictionary, rules: Dictionary) -> Dictionary:
	var cells: Dictionary = {}
	var walls: Array[Dictionary] = []
	for entity: Dictionary in entities.values():
		if not is_wall(entity, rules) or float(entity.get("hp", 1.0)) <= 0.0: continue
		walls.append(entity)
		cells[_key(entity.pos)] = entity
	var result: Dictionary = {}
	for entity in walls:
		var info: Dictionary = rules.buildings[entity.spec]
		var spacing: float = float(info.get("size", 1.0))
		var mask: int = 0
		for index in range(DIRECTIONS.size()):
			var neighbor: Dictionary = cells.get(_key(entity.pos + DIRECTIONS[index] * spacing), {})
			if neighbor.is_empty() or int(neighbor.team) != int(entity.team): continue
			var other: Dictionary = rules.buildings[neighbor.spec]
			if str(other.role) != str(info.role) or not is_equal_approx(float(other.get("size", 1.0)), spacing): continue
			mask |= 1 << index
		result[int(entity.id)] = mask
	return result

static func shape(mask: int) -> String:
	var count: int = 0
	for index in range(4):
		if mask & (1 << index): count += 1
	if count == 0: return "isolated"
	if count == 1: return "endpoint"
	if count == 2: return "straight" if mask in [EAST | WEST, SOUTH | NORTH] else "corner"
	return "tee" if count == 3 else "cross"

static func connected_recipe(base: Dictionary, mask: int, faction: String, team: int) -> Dictionary:
	if mask == 0: return base
	var volume = load("res://scripts/volume_models.gd")
	var mesh = volume.CraftMesh.new()
	var source: ArrayMesh = base.body_mesh
	var bounds: AABB = source.get_aabb()
	var height: float = bounds.end.y
	var thickness: float = minf(bounds.size.z, .95)
	var paint: Color = Color("51463a") if faction == "iron" else Color("e9e5dc") if faction == "sky" else volume.KRAFT
	var cap: Color = Color("bb963e") if faction == "iron" else Color("74569d") if faction == "sky" else volume.RED if faction == "rivet" else volume.BLUE
	mesh.capture_shell = false
	# Each arm is a clipped half of the complete authored model. Preserve its
	# panels, bolts, bracing, cut edges and pigments instead of a proxy board.
	for index in range(4):
		if not mask & (1 << index): continue
		_append_half(mesh, source, index, maxf(bounds.end.x, .01))
		if base.has("body_border_mesh"):
			_append_half(mesh, base.body_border_mesh, index, maxf(bounds.end.x, .01), true)
		mesh.capture_shell = base.has("body_border_mesh")
		var direction: Vector2 = DIRECTIONS[index]
		var center := Vector3(direction.x * .475, height * .5, direction.y * .475)
		var size := Vector3(.05, height, thickness * .60) if index % 2 == 0 else Vector3(thickness * .60, height, .05)
		mesh.box(center, size, paint)
		mesh.capture_shell = false
	# A closed solid junction covers every cut face, including an exposed end.
	# Small caps retain the faction's construction vocabulary at corners/Ts.
	var hub: float = maxf(.18, thickness * .62)
	mesh.capture_shell = base.has("body_border_mesh")
	mesh.box(Vector3(0, height * .49, 0), Vector3(hub, height * .98, hub), paint)
	mesh.box(Vector3(0, height - .035, 0), Vector3(hub + .04, .07, hub + .04), cap)
	mesh.capture_shell = false
	var mark_position := Vector3(0, height + .015, 0)
	var mark_size: float = minf(hub * .28, .13)
	if faction == "iron": load("res://scripts/iron_models.gd")._mark(mesh, mark_position, Vector3.UP, volume.player_color(team), mark_size)
	elif faction == "sky": load("res://scripts/sky_models.gd")._mark(mesh, mark_position, volume.player_color(team), Vector3.UP, mark_size)
	else: mesh.badge(mark_position, faction, volume.player_color(team), Vector3.UP, mark_size)
	var result: Dictionary = base.duplicate()
	result.body_mesh = mesh.mesh()
	if base.has("body_border_mesh"): result.body_border_mesh = mesh.shell_mesh()
	result.dimensions = result.body_mesh.get_aabb().size
	result.wall_mask = mask
	result.wall_shape = shape(mask)
	return result

static func _append_half(target, source: ArrayMesh, direction: int, extent: float, shell: bool = false) -> void:
	var basis := Basis(Vector3.UP, -float(direction) * PI * .5)
	for surface in range(source.get_surface_count()):
		var arrays: Array = source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count: int = indices.size() if not indices.is_empty() else vertices.size()
		for first in range(0, count, 3):
			var polygon: Array[Dictionary] = []
			for offset in range(3):
				var index: int = indices[first + offset] if not indices.is_empty() else first + offset
				polygon.append({"pos": vertices[index], "normal": normals[index], "color": colors[index] if not colors.is_empty() else Color.WHITE})
			var clipped: Array[Dictionary] = []
			for index in range(polygon.size()):
				var a: Dictionary = polygon[index]
				var b: Dictionary = polygon[(index + 1) % polygon.size()]
				if a.pos.x >= 0.0: clipped.append(a)
				if (a.pos.x >= 0.0) != (b.pos.x >= 0.0):
					var fraction: float = -a.pos.x / (b.pos.x - a.pos.x)
					clipped.append({"pos": a.pos.lerp(b.pos, fraction), "normal": a.normal.lerp(b.normal, fraction).normalized(), "color": a.color.lerp(b.color, fraction)})
			for index in range(1, clipped.size() - 1):
				var positions: Array[Vector3] = []
				for vertex in [clipped[0], clipped[index], clipped[index + 1]]:
					var point: Vector3 = vertex.pos
					point.x *= .5 / extent
					positions.append(basis * point)
				if (positions[1] - positions[0]).cross(positions[2] - positions[0]).length_squared() > 0.0000000001:
					var corners: Array = [clipped[0], clipped[index], clipped[index + 1]]
					for corner in range(3):
						var normal: Vector3 = corners[corner].normal
						normal.x *= extent / .5
						normal = (basis * normal).normalized()
						if shell:
							target.shell_vertices.append(positions[corner])
							target.shell_normals.append(normal)
						else:
							target.vertices.append(positions[corner])
							target.normals.append(normal)
							target.colors.append(corners[corner].color)
