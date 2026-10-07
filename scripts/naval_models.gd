extends RefCounted

## Closed paperboard ship hulls with real decks, bulwarks and separate turret
## solids. +X is bow. The waterline is local y=0; keel lies below the water.
const INK := Color("382a22")
const PAPER := Color("e6d5af")
const WOOD := Color("987b52")
const DARK := Color("4c4a48")
const GLASS := Color("759591")
const METAL := Color("a9aea4")
const FACTION_PAINT := {"rivet": Color("817262"), "kestrel": Color("c6c0ad"), "iron": Color("789f96"), "sky": Color("ebe8df")}
const FACTION_TRIM := {"rivet": Color("c4ae8b"), "kestrel": Color("8c9290"), "iron": Color("665b48"), "sky": Color("b8b5ad")}

static func make(mesh, art: String, faction: String, team: int, kind: String) -> Dictionary:
	if art not in ["naval_transport", "naval_frigate", "naval_signature", "shipyard"]: return {}
	var owner: Color = load("res://scripts/volume_models.gd").player_color(team)
	var paint: Color = FACTION_PAINT.get(faction, FACTION_PAINT.kestrel)
	var trim: Color = owner
	mesh.capture_shell = true
	if kind == "building":
		if art != "shipyard": return {}
		_shipyard(mesh, faction, paint, trim, owner)
		return _finish(mesh, faction, art, kind)
	if kind != "unit": return {}
	var role: String = art.trim_prefix("naval_")
	var length: float = 4.2 if role == "transport" else 5.1 if role == "frigate" else 6.3
	var breadth: float = (1.38 if role == "transport" else 1.7 if role == "frigate" else 2.05) * (1.13 if faction == "rivet" else .85 if faction == "kestrel" else 1.0)
	_hull(mesh, length, breadth, paint, trim)
	_deck(mesh, length, breadth, faction, role, paint, trim, owner)
	var gun = null
	var pivot := Vector3.ZERO
	var muzzle := Vector3.ZERO
	if role != "transport":
		gun = load("res://scripts/volume_models.gd").CraftMesh.new()
		gun.capture_shell = true
		pivot = Vector3(length * (0.13 if role == "frigate" else 0.17), 0.88, 0.0)
		muzzle = _turret(gun, faction, role, trim)
	return _finish(mesh, faction, art, kind, gun, pivot, muzzle)

static func _hull(mesh, length: float, breadth: float, paint: Color, trim: Color) -> void:
	var half: float = length * 0.5
	var xs: Array[float] = [-half, -half * 0.72, -half * 0.22, half * 0.34, half * 0.78, half]
	var widths: Array[float] = [breadth * 0.31, breadth * 0.82, breadth, breadth * 0.94, breadth * 0.58, 0.08]
	var top: float = 0.69
	var chine: float = -0.08
	var keel: float = -0.41
	# Each strip has an upper sheer, a lower chine and a central keel.
	# Both bow and stern are capped, so a section never ends as a flat card.
	for side in [-1.0, 1.0]:
		for i in range(xs.size() - 1):
			var x0: float = xs[i]
			var x1: float = xs[i + 1]
			var z0: float = side * widths[i] * 0.5
			var z1: float = side * widths[i + 1] * 0.5
			var c0: float = z0 * 0.78
			var c1: float = z1 * 0.78
			var outer: Vector3 = Vector3(0, 0, side)
			mesh.face([Vector3(x0, top, z0), Vector3(x1, top, z1), Vector3(x1, chine, c1), Vector3(x0, chine, c0)], paint, outer)
			mesh.face([Vector3(x0, chine, c0), Vector3(x1, chine, c1), Vector3(x1, keel, 0), Vector3(x0, keel, 0)], DARK if side < 0 else paint.darkened(0.23), (outer + Vector3.DOWN).normalized())
			mesh.line(Vector3(x0, top - 0.09, z0), Vector3(x1, top - 0.09, z1), 0.027, trim)
			mesh.line(Vector3(x0, chine, c0), Vector3(x1, chine, c1), 0.018, INK)
		# The bow/stern close against their symmetrical opposite half.
		for end in [0, xs.size() - 1]:
			var x: float = xs[end]
			var z: float = side * widths[end] * 0.5
			var c: float = z * 0.78
			mesh.face([Vector3(x, top, 0), Vector3(x, top, z), Vector3(x, chine, c), Vector3(x, keel, 0)], paint.darkened(0.14), Vector3.LEFT if end == 0 else Vector3.RIGHT)
	# Full top surface is a closed, load-bearing paper deck, not open water.
	for i in range(xs.size() - 1):
		mesh.face([Vector3(xs[i], top, -widths[i] * 0.5), Vector3(xs[i+1], top, -widths[i+1] * 0.5), Vector3(xs[i+1], top, widths[i+1] * 0.5), Vector3(xs[i], top, widths[i] * 0.5)], WOOD, Vector3.UP)
	mesh.line(Vector3(-half, keel, 0), Vector3(half, keel, 0), 0.018, INK)

static func _deck(mesh, length: float, breadth: float, faction: String, role: String, paint: Color, trim: Color, owner: Color) -> void:
	var half: float = length * 0.5
	for side in [-1.0, 1.0]:
		var rail_z: float = side * breadth * 0.44
		for x in [-half * 0.62, -half * 0.23, half * 0.17, half * 0.55]:
			mesh.box(Vector3(x, 0.87, rail_z), Vector3(0.09, 0.38, 0.08), INK)
		mesh.line(Vector3(-half * 0.69, 1.06, rail_z), Vector3(half * 0.64, 1.06, rail_z), 0.025, trim)
	for x in [-half * 0.35, -half * 0.08, half * 0.2]:
		mesh.line(Vector3(x, 0.706, -breadth * 0.39), Vector3(x, 0.706, breadth * 0.39), 0.019, INK)
	# Identification is a small physical plate; player ownership is not the
	# faction silhouette's only difference.
	mesh.badge(Vector3(-half * 0.58, 0.731, 0),faction,owner,Vector3.UP,.19)
	if role == "transport":
		mesh.box(Vector3(-0.24, 0.98, 0), Vector3(length * 0.48, 0.58, breadth * 0.60), paint)
		mesh.box(Vector3(-0.24, 1.31, 0), Vector3(length * 0.50, 0.13, breadth * 0.64), trim)
		for side in [-1.0, 1.0]:
			mesh.box(Vector3(-0.72, 0.98, side * breadth * 0.32), Vector3(0.7, 0.37, 0.08), DARK)
			mesh.line(Vector3(-half * 0.43, 0.82, side * breadth * 0.49), Vector3(-half * 0.22, 1.28, side * breadth * 0.49), 0.045, INK)
		# Working bow ramp ends on the deck, with two continuous hinge spars.
		mesh.box(Vector3(half * 0.64, 0.78, 0), Vector3(length * 0.23, 0.10, breadth * 0.55), trim)
		for side in [-1.0, 1.0]: mesh.line(Vector3(half * 0.43, 0.86, side * breadth * 0.3), Vector3(half * 0.84, 0.73, side * breadth * 0.3), 0.035, INK)
	elif role == "frigate":
		mesh.box(Vector3(-half * 0.28, 1.22, 0), Vector3(1.2, 1.04, breadth * 0.48), paint)
		mesh.box(Vector3(-half * 0.12, 1.55, 0), Vector3(0.65, 0.27, breadth * 0.55), GLASS)
		mesh.box(Vector3(-half * 0.31, 1.79, 0), Vector3(0.93, 0.12, breadth * 0.55), trim)
		mesh.cylinder(Vector3(-half * 0.36, 2.11, 0), 0.09, 0.55, Vector3.UP, DARK, 8)
		mesh.box(Vector3(-half * 0.36, 2.38, 0), Vector3(0.6, 0.08, 0.24), trim)
	else:
		mesh.box(Vector3(-half * 0.34, 1.27, 0), Vector3(1.58, 1.13, breadth * 0.57), paint)
		mesh.box(Vector3(-half * 0.31, 1.88, 0), Vector3(1.78, 0.15, breadth * 0.65), trim)
		mesh.box(Vector3(-half * 0.18, 1.57, 0), Vector3(0.7, 0.24, breadth * 0.62), GLASS)
	match faction:
		"rivet":
			# Ram bow and paired slab armour leave a broad, low wedge.
			mesh.box(Vector3(half * 0.75, 0.78, 0), Vector3(0.94, 0.29, breadth * 0.62), DARK)
			for side in [-1.0, 1.0]: mesh.box(Vector3(-0.13, 0.78, side * breadth * 0.40), Vector3(length * 0.57, 0.34, 0.19), paint)
		"kestrel":
			# Twin raised command pods and a taut flying bridge.
			for side in [-1.0, 1.0]: mesh.box(Vector3(-half * 0.18, 1.49, side * breadth * 0.22), Vector3(0.57, 0.51, 0.37), trim)
			mesh.box(Vector3(-half * 0.18, 1.77, 0), Vector3(0.79, 0.09, breadth * 0.7), paint)
		"iron":
			# Exposed gantry and service lockers read as a mobile workshop.
			mesh.box(Vector3(-half * 0.55, 1.57, 0), Vector3(0.13, 1.37, 0.13), DARK)
			mesh.box(Vector3(-half * 0.15, 2.17, 0), Vector3(1.94, 0.13, 0.15), trim)
			for side in [-1.0, 1.0]: mesh.box(Vector3(-half * 0.05, 0.9, side * breadth * 0.3), Vector3(0.72, 0.37, 0.3), DARK)
		"sky":
			# Separate rectangular charge loops frame the pulse equipment.
			for x in [-half * 0.54, -half * 0.22]:
				for side in [-1.0, 1.0]: mesh.box(Vector3(x, 1.61, side * breadth * 0.3), Vector3(0.12, 1.21, 0.12), trim)
				mesh.box(Vector3(x, 2.25, 0), Vector3(0.13, 0.12, breadth * 0.7), trim)

	if role == "frigate":
		match faction:
			"rivet":
				for z in [-breadth*.24,breadth*.24]: mesh.cylinder(Vector3(-half*.28,1.98,z),.20,.72,Vector3.UP,paint,8,false)
			"kestrel":
				mesh.slab([Vector2(-.55,-.28),Vector2(.50,-.28),Vector2(.33,.28),Vector2(-.43,.28)],.08,Vector3(-half*.31,1.94,0),trim,false)
			"iron":
				mesh.cylinder(Vector3(-half*.44,1.82,0),.24,1.14,Vector3.UP,paint,8,false)
				mesh.cylinder(Vector3(-half*.44,2.43,0),.31,.12,Vector3.UP,trim,8,false)
				mesh.line(Vector3(-half*.40,1.20,.24),Vector3(-half*.06,1.20,.24),.09,trim)
			"sky":
				for side in [-1.0,1.0]: mesh.prism([Vector2(-.48,0),Vector2(-.12,.62),Vector2(.33,.13),Vector2(.46,0)],.12,Vector3(-half*.30,1.89,side*.38),paint,true)

static func _turret(gun, faction: String, role: String, trim: Color) -> Vector3:
	var heavy: bool = role == "signature"
	var body: Color = FACTION_PAINT.get(faction, FACTION_PAINT.kestrel)
	var width: float = 0.84 if not heavy else 1.28
	var height: float = 0.48 if not heavy else 0.68
	gun.cylinder(Vector3(0, 0.02, 0), 0.52 if not heavy else 0.71, 0.18, Vector3.UP, DARK, 12)
	gun.box(Vector3(0.03, height * 0.5 + 0.12, 0), Vector3(width, height, width * 0.82), body)
	gun.box(Vector3(-0.12, height + 0.14, 0), Vector3(width * 0.74, 0.10, width * 0.70), trim)
	if faction == "sky" and heavy:
		for side in [-1.0, 1.0]:
			gun.cylinder(Vector3(0.16, 0.51, side * 0.42), 0.20, 0.48, Vector3.RIGHT, trim, 10)
			gun.cylinder(Vector3(0.42, 0.51, side * 0.42), 0.13, 0.09, Vector3.RIGHT, GLASS, 10)
		return Vector3(0.48, 0.51, 0)
	var barrel_length: float = 1.17 if heavy else 0.8
	for side in ([-1.0, 1.0] if heavy and faction in ["rivet", "iron"] else [0.0]):
		var z: float = side * 0.27
		gun.cylinder(Vector3(width * 0.42 + barrel_length * 0.5, 0.39, z), 0.12 if heavy else 0.09, barrel_length, Vector3.RIGHT, DARK, 10)
		gun.cylinder(Vector3(width * 0.42 + barrel_length - 0.05, 0.39, z), 0.145, 0.14, Vector3.RIGHT, trim, 10)
	return Vector3(width * 0.42 + barrel_length + 0.03, 0.39, 0)

static func _shipyard(mesh, faction: String, paint: Color, trim: Color, owner: Color) -> void:
	# Split dry land workshop and recessed slipway; no floating block fills the
	# water opening. The two pier rails extend from the gate toward open water.
	mesh.box(Vector3(-0.86, 0.17, 0), Vector3(2.0, 0.34, 3.4), WOOD)
	mesh.box(Vector3(-1.25, 1.01, 0), Vector3(1.26, 1.48, 2.56), paint)
	mesh.box(Vector3(-1.25, 1.79, 0), Vector3(1.55, 0.16, 2.8), trim)
	mesh.badge(Vector3(-0.55, 1.22, 1.33),faction,owner,Vector3.BACK,.22)
	for side in [-1.0, 1.0]:
		mesh.box(Vector3(0.95, 0.12, side * 1.53), Vector3(2.05, 0.22, 0.34), WOOD)
		mesh.box(Vector3(0.13, 1.66, side * 1.52), Vector3(0.15, 2.55, 0.16), DARK)
		mesh.line(Vector3(0.14, 2.88, side * 1.52), Vector3(1.45, 2.88, side * 1.20), 0.065, trim)
		mesh.line(Vector3(1.45, 2.88, side * 1.20), Vector3(1.45, 0.58, side * 1.20), 0.025, INK)
	for z in [-0.7, 0.0, 0.7]: mesh.line(Vector3(-0.25, 0.36, z), Vector3(1.88, 0.36, z), 0.055, METAL)
	match faction:
		"rivet":
			for z in [-0.65, 0.65]: mesh.box(Vector3(-1.47, 1.35, z), Vector3(0.23, 1.26, 0.49), DARK)
		"kestrel":
			mesh.box(Vector3(-0.13, 2.25, 0), Vector3(1.44, 0.18, 2.95), trim)
		"iron":
			mesh.box(Vector3(-1.24, 2.31, 0), Vector3(1.3, 0.71, 0.89), DARK)
			mesh.box(Vector3(-1.24, 2.71, 0), Vector3(1.41, 0.11, 1.02), trim)
		"sky":
			for z in [-0.91, 0.91]: mesh.box(Vector3(-1.25, 2.53, z), Vector3(0.13, 1.12, 0.13), trim)
			mesh.box(Vector3(-1.25, 3.13, 0), Vector3(0.17, 0.13, 2.0), trim)

static func _finish(mesh, faction: String, art: String, kind: String, gun = null, pivot: Vector3 = Vector3.ZERO, muzzle: Vector3 = Vector3.ZERO) -> Dictionary:
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for vertex: Vector3 in mesh.vertices:
		low = low.min(vertex)
		high = high.max(vertex)
	var result: Dictionary = {"body_mesh": mesh.mesh(), "body_border_mesh": mesh.shell_mesh(), "design_signature": faction + "_" + art,
		"faction_geometry": true, "faction_color": FACTION_PAINT.get(faction, FACTION_PAINT.kestrel), "emblem": faction,
		"dimensions": high - low, "visual_bounds": AABB(low, high - low)}
	if gun != null:
		for vertex: Vector3 in gun.vertices:
			low = low.min(vertex + pivot)
			high = high.max(vertex + pivot)
		result.turret_mesh = gun.mesh()
		result.turret_border_mesh = gun.shell_mesh()
		result.turret_pos = pivot
		result.muzzle_pos = muzzle
		result.dimensions = high - low
		result.visual_bounds = AABB(low, high - low)
	return result
