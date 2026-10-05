extends RefCounted

# Solid paperboard architecture follows the illustrated faction sheets.
# Each installation has a complete room/industrial shell and attached equipment. CraftMesh is passed in to preserve cached materials and avoid a
# static dependency cycle with VolumeModels. Wall/barricade stay in that file.
const INK = Color("382a22")
const ARMOR = Color("57453a")
const RED_DARK = Color("88342d")
const PAPER = Color("e6d5af")
const KRAFT = Color("c9ad7f")
const WOOD = Color("987b52")
const STEEL = Color("a9aea4")
const GLASS = Color("759591")
const BLUE = Color("2865a5")
const RED = Color("bb4034")
const OWNER = [Color("e7ad42"), Color("41c7c6"), Color("af80d1"), Color("9bb85a")]
const ARTS = ["hq", "outpost", "power", "refinery", "barracks", "factory", "tower", "tech", "repair", "command", "airfield"]

static var _solid_parts: Array[Dictionary] = []
static var _smoke_ports: Array[Vector3] = []

static func make(mesh, faction: String, art: String, team: int) -> Dictionary:
	if art not in ARTS: return {}
	_solid_parts = []
	_smoke_ports = []
	var hammer: bool = faction == "rivet"
	var paint: Color = RED if hammer else BLUE
	var owner: Color = OWNER[posmod(team, OWNER.size())]
	var turret = null
	var pivot: Vector3 = Vector3.ZERO
	var muzzle: Vector3 = Vector3.ZERO
	match art:
		"hq": _hq(mesh, hammer, paint, faction, owner)
		"outpost": _outpost(mesh, hammer, paint, faction, owner)
		"power": _power(mesh, hammer, paint, faction, owner)
		"refinery": _refinery(mesh, hammer, paint, faction, owner)
		"barracks": _barracks(mesh, hammer, paint, faction, owner)
		"factory": _factory(mesh, hammer, paint, faction, owner)
		"tech": _tech(mesh, hammer, paint, faction, owner)
		"repair": _repair(mesh, hammer, paint, faction, owner)
		"command": _command(mesh, hammer, paint, faction, owner)
		"airfield": _airfield(mesh, hammer, paint, faction, owner)
		"tower":
			# The renderer already rotates/recoils this independent mesh.
			var volume = load("res://scripts/volume_models.gd")
			turret = volume.CraftMesh.new()
			var gun: Dictionary = _tower(mesh, turret, hammer, paint, faction, owner)
			pivot = gun.pivot
			muzzle = gun.muzzle
	return _finish(mesh, ("hammer_" if hammer else "canon_") + art, turret, pivot, muzzle)

static func _finish(mesh, signature: String, turret, pivot: Vector3, muzzle: Vector3) -> Dictionary:
	var extent: Vector3 = Vector3.ZERO
	for point: Vector3 in mesh.vertices:
		extent.x = maxf(extent.x, absf(point.x))
		extent.y = maxf(extent.y, point.y)
		extent.z = maxf(extent.z, absf(point.z))
	var result: Dictionary = {"body_mesh": mesh.mesh(), "design_signature": signature, "faction_geometry": true, "solid_parts": _solid_parts.duplicate(true), "smoke_ports": _smoke_ports.duplicate()}
	if turret != null:
		for point: Vector3 in turret.vertices:
			var positioned: Vector3 = point + pivot
			extent.x = maxf(extent.x, absf(positioned.x))
			extent.y = maxf(extent.y, positioned.y)
			extent.z = maxf(extent.z, absf(positioned.z))
		result.turret_mesh = turret.mesh()
		result.turret_pos = pivot
		result.muzzle_pos = muzzle
		result.recoil_distance = 0.045
	result.dimensions = Vector3(extent.x * 2.0, extent.y, extent.z * 2.0)
	return result

static func _base(mesh, width: float, depth: float, hammer: bool) -> void:
	if hammer:
		mesh.box(Vector3(0, .12, 0), Vector3(width, .20, depth), KRAFT)
		for z: float in [-depth * .34, depth * .34]:
			mesh.box(Vector3(0, .24, z), Vector3(width * .93, .10, .20), WOOD)
	else:
		var x: float = width * .5
		var z: float = depth * .5
		var cut: float = .25
		mesh.slab([Vector2(-x + cut, -z), Vector2(x - cut, -z), Vector2(x, -z + cut), Vector2(x, z - cut), Vector2(x - cut, z), Vector2(-x + cut, z), Vector2(-x, z - cut), Vector2(-x, -z + cut)], .17, Vector3(0, .13, 0), KRAFT)

static func _marks(mesh, faction: String, owner: Color, side: Vector3, top: Vector3, size: float = .27) -> void:
	mesh.badge(side, faction, owner, Vector3.BACK, size)
	mesh.badge(top, faction, owner, Vector3.UP, size * 1.03)

# Major closed forms are tracked by their actual vertex ranges so validation can
# measure architecture independently of flags, base plates and thin ink strokes.
static func _solid_box(mesh, center: Vector3, size: Vector3, color: Color, role: String = "room") -> void:
	var begin: int = mesh.vertices.size()
	mesh.box(center, size, color)
	_solid_parts.append({"center": center, "size": size, "role": role, "vertex_start": begin, "vertex_end": mesh.vertices.size()})

static func _solid_cylinder(mesh, center: Vector3, radius: float, length: float, axis: Vector3, color: Color, role: String = "equipment", segments: int = 12) -> void:
	var begin: int = mesh.vertices.size()
	mesh.cylinder(center, radius, length, axis, color, segments)
	_solid_parts.append({"center": center, "size": Vector3.ONE * radius * 2.0 + axis.abs() * (length - radius * 2.0), "role": role, "vertex_start": begin, "vertex_end": mesh.vertices.size()})

static func _dome(mesh, center: Vector3, radius: float, rise: float, paint: Color) -> void:
	# Closed faceted cupola sits on a solid room. Each latitude is a filled cap.
	var begin: int = mesh.vertices.size()
	var segments: int = 16
	var rings: int = 5
	for ring: int in range(rings):
		var a: float = float(ring) / float(rings) * PI * .5
		var b: float = float(ring + 1) / float(rings) * PI * .5
		for i: int in range(segments):
			var aa: float = float(i) / float(segments) * TAU
			var ab: float = float(i + 1) / float(segments) * TAU
			var p0: Vector3 = center + Vector3(cos(aa) * cos(a) * radius, sin(a) * rise, sin(aa) * cos(a) * radius)
			var p1: Vector3 = center + Vector3(cos(ab) * cos(a) * radius, sin(a) * rise, sin(ab) * cos(a) * radius)
			var p2: Vector3 = center + Vector3(cos(ab) * cos(b) * radius, sin(b) * rise, sin(ab) * cos(b) * radius)
			var p3: Vector3 = center + Vector3(cos(aa) * cos(b) * radius, sin(b) * rise, sin(aa) * cos(b) * radius)
			var normal: Vector3 = Vector3(cos((aa + ab) * .5) * cos((a + b) * .5), sin((a + b) * .5) * radius / rise, sin((aa + ab) * .5) * cos((a + b) * .5)).normalized()
			mesh.face([p0, p1, p2, p3], paint, normal)
			if ring == 0: mesh.triangle(center, p1, p0, paint, Vector3.DOWN)
	for i: int in range(segments):
		var aa: float = float(i) / float(segments) * TAU
		var ab: float = float(i + 1) / float(segments) * TAU
		mesh.line(center + Vector3(cos(aa) * radius, 0, sin(aa) * radius), center + Vector3(cos(ab) * radius, 0, sin(ab) * radius), .022, INK)
	_solid_parts.append({"center": center + Vector3(0, rise * .5, 0), "size": Vector3(radius * 2.0, rise, radius * 2.0), "role": "roof", "vertex_start": begin, "vertex_end": mesh.vertices.size()})

static func _roof(mesh, center: Vector3, width: float, depth: float, rise: float, paint: Color) -> void:
	var begin: int = mesh.vertices.size()
	mesh.gable(center, width, depth, rise, paint)
	_solid_parts.append({"center": center + Vector3(0, (rise - .105) * .5, 0), "size": Vector3(width, rise + .105, depth), "role": "roof", "vertex_start": begin, "vertex_end": mesh.vertices.size()})

static func _armor_vault(mesh, center: Vector3, width: float, depth: float, rise: float, paint: Color, thickness: float = .20) -> void:
	# Closed folded armor roof: its crown and deep eaves are substantial solids.
	var begin: int = mesh.vertices.size()
	var half: float = width * .5
	mesh.prism([Vector2(-half, -thickness), Vector2(-half, 0), Vector2(-half * .67, rise * .75), Vector2(-half * .23, rise), Vector2(half * .23, rise), Vector2(half * .67, rise * .75), Vector2(half, 0), Vector2(half, -thickness)], depth, center, paint)
	mesh.box(center + Vector3(0, rise + .055, 0), Vector3(width * .40, .10, depth * .90), RED_DARK)
	for z: float in [-depth * .39, depth * .39]:
		mesh.line(center + Vector3(-half * .86, rise * .32 + .027, z), center + Vector3(-half * .54, rise * .85 + .027, z), .022, KRAFT)
		mesh.line(center + Vector3(half * .54, rise * .85 + .027, z), center + Vector3(half * .86, rise * .32 + .027, z), .022, KRAFT)
	_solid_parts.append({"center": center + Vector3(0, (rise + .105 - thickness) * .5, 0), "size": Vector3(width, rise + thickness + .105, depth), "role": "roof", "vertex_start": begin, "vertex_end": mesh.vertices.size()})

static func _room(mesh, center: Vector3, size: Vector3, hammer: bool, paint: Color) -> void:
	_solid_box(mesh, center, size, ARMOR if hammer else PAPER)
	var front: float = center.z + size.z * .5
	var back: float = center.z - size.z * .5
	var floor_y: float = center.y - size.y * .5
	var roof_y: float = center.y + size.y * .5
	mesh.box(Vector3(center.x, floor_y + .13, center.z), Vector3(size.x + .06, .23, size.z + .06), RED_DARK if hammer else paint)
	mesh.box(Vector3(center.x, roof_y - .15, front + .035), Vector3(size.x, .20, .10), paint)
	if hammer:
		# Thick red outer armor surrounds the dark structural room.
		for side: float in [-1.0, 1.0]:
			mesh.box(Vector3(center.x + side * (size.x * .5 - .08), center.y, center.z), Vector3(.17, size.y * .76, size.z * .80), paint)
			for seam_z: float in [-.32, .32]:
				mesh.box(Vector3(center.x + side * (size.x * .5 + .025), center.y, center.z + size.z * seam_z), Vector3(.075, size.y * .86, .11), KRAFT)
		for x: float in [-.35, .35]:
			mesh.box(Vector3(center.x + size.x * x, center.y, front + .065), Vector3(size.x * .23, size.y * .85, .17), paint)
		mesh.box(Vector3(center.x, center.y, back - .04), Vector3(size.x * .86, size.y * .81, .12), paint)
		mesh.box(Vector3(center.x, roof_y + .10, center.z), Vector3(size.x + .12, .22, size.z + .14), paint)
		mesh.box(Vector3(center.x, roof_y + .26, center.z), Vector3(size.x * .88, .12, size.z * .86), RED_DARK)
	else:
		for side: float in [-1.0, 1.0]:
			mesh.box(Vector3(center.x + side * (size.x * .5 - .09), center.y, front + .045), Vector3(.16, size.y, .12), KRAFT)
		mesh.box(Vector3(center.x, roof_y + .025, center.z), Vector3(size.x + .08, .10, size.z + .08), paint)

static func _door(mesh, center: Vector3, width: float, height: float, hammer: bool, paint: Color) -> void:
	mesh.box(center, Vector3(width, height, .065), INK)
	mesh.box(center + Vector3(0, 0, .044), Vector3(width * .77, height * .86, .045), RED_DARK if hammer else paint)
	for side: float in [-1.0, 1.0]:
		mesh.box(center + Vector3(side * width * .56, .03, .06), Vector3(width * .13, height + .17, .17), KRAFT)
	mesh.box(center + Vector3(0, height * .54, .08), Vector3(width * 1.26, .13, .20), KRAFT)
	mesh.line(center + Vector3(0, -height * .37, .073), center + Vector3(0, height * .39, .073), .012, INK)

static func _windows(mesh, center: Vector3, width: float, height: float, count: int = 3) -> void:
	for i: int in range(count):
		var x: float = (float(i) - float(count - 1) * .5) * width / float(count)
		mesh.box(center + Vector3(x, 0, 0), Vector3(width / float(count) * .71, height, .065), INK)
		mesh.box(center + Vector3(x, .012, .047), Vector3(width / float(count) * .55, height * .69, .04), GLASS, false)

static func _crate(mesh, center: Vector3, size: Vector3, hammer: bool = false) -> void:
	_solid_box(mesh, center, size, ARMOR if hammer else KRAFT, "equipment")
	mesh.box(center + Vector3(0, 0, size.z * .5 + .025), Vector3(size.x * .72, size.y * .70, .05), KRAFT)
	mesh.line(center + Vector3(-size.x * .29, -size.y * .28, size.z * .5 + .06), center + Vector3(size.x * .29, size.y * .28, size.z * .5 + .06), .016, INK)

static func _service_chassis(mesh, center: Vector3, hammer: bool, paint: Color) -> void:
	# A stationary stripped hull makes the assembly/maintenance function visible.
	# This is workshop equipment; the independent combat vehicle recipes stay intact.
	for side: float in [-1.0, 1.0]:
		_solid_box(mesh, center + Vector3(side * .48, .19, 0), Vector3(.25, .34, 1.59), INK, "equipment")
		for z: float in [-.57, -.19, .19, .57]:
			mesh.cylinder(center + Vector3(side * .61, .19, z), .125, .075, Vector3.RIGHT, KRAFT, 8)
	_solid_box(mesh, center + Vector3(0, .39, 0), Vector3(.93, .31, 1.37), RED_DARK if hammer else KRAFT, "equipment")
	mesh.prism([Vector2(-.47, 0), Vector2(-.34, .24), Vector2(.34, .24), Vector2(.47, 0)], 1.25, center + Vector3(0, .55, 0), paint)
	mesh.box(center + Vector3(0, .81, -.29), Vector3(.55, .16, .60), KRAFT)
	mesh.box(center + Vector3(0, .71, .47), Vector3(.67, .06, .25), STEEL)
	for x: float in [-.18, 0.0, .18]:
		mesh.box(center + Vector3(x, .90, -.29), Vector3(.038, .035, .43), INK, false)

static func _ring(mesh, center: Vector3, radius: float, normal: Vector3, paint: Color, stroke: float = .07, start: float = 0.0, sweep: float = TAU) -> void:
	var tangent: Vector3 = normal.normalized().cross(Vector3.UP)
	if tangent.length_squared() < .1: tangent = Vector3.RIGHT
	tangent = tangent.normalized()
	var bitangent: Vector3 = normal.normalized().cross(tangent)
	for i: int in range(20):
		var a: float = start + sweep * float(i) / 20.0
		var b: float = start + sweep * float(i + 1) / 20.0
		mesh.line(center + radius * (tangent * cos(a) + bitangent * sin(a)), center + radius * (tangent * cos(b) + bitangent * sin(b)), stroke, paint)

static func _flag(mesh, position: Vector3, faction: String, owner: Color, height: float, width: float = .62) -> void:
	mesh.cylinder(position + Vector3(0, height * .5, 0), .042, height, Vector3.UP, INK, 8, false)
	mesh.box(position + Vector3(width * .35, height - .22, 0), Vector3(width, .48, .045), owner)
	mesh.badge(position + Vector3(width * .35, height - .22, .05), faction, owner, Vector3.BACK, .13)

static func _hq(mesh, hammer: bool, paint: Color, faction: String, owner: Color) -> void:
	_base(mesh, 3.82, 3.80, hammer)
	if hammer:
		# Stepped fortress: the tall central command block is filled, not a press.
		_room(mesh, Vector3(0, 1.65, -.28), Vector3(1.51, 2.82, 2.38), true, paint)
		for side: float in [-1.0, 1.0]:
			_room(mesh, Vector3(side * 1.25, .98, -.20), Vector3(.93, 1.48, 2.62), true, paint)
			_room(mesh, Vector3(side * 1.38, .65, 1.12), Vector3(.75, .82, .84), true, paint)
			_door(mesh, Vector3(side * 1.38, .60, 1.57), .33, .55, true, paint)
			mesh.cylinder(Vector3(side * 1.33, 2.24, -.82), .11, .91, Vector3.UP, INK, 8)
			mesh.cylinder(Vector3(side * 1.33, 2.67, -.82), .13, .13, Vector3.UP, paint, 8)
		_room(mesh, Vector3(0, 1.10, 1.04), Vector3(1.40, 1.70, 1.10), true, paint)
		_door(mesh, Vector3(0, 1.04, 1.64), .88, 1.48, true, paint)
		_windows(mesh, Vector3(0, 2.74, .99), 1.12, .22, 2)
		_solid_box(mesh, Vector3(0, 3.37, -.48), Vector3(1.04, .38, 1.05), ARMOR, "equipment")
		mesh.box(Vector3(0, 3.59, -.48), Vector3(1.16, .13, 1.17), paint)
		_marks(mesh, faction, owner, Vector3(0, 2.16, .99), Vector3(0, 3.69, -.48), .40)
		_flag(mesh, Vector3(-.44, 3.62, -.79), faction, owner, .92, .48)
	else:
		# Broad cream headquarters with blue roofing and complete low side wings.
		_room(mesh, Vector3(0, 1.06, -.14), Vector3(2.80, 1.63, 2.78), false, paint)
		_roof(mesh, Vector3(0, 1.96, -.14), 3.03, 2.93, .42, paint)
		for side: float in [-1.0, 1.0]:
			_room(mesh, Vector3(side * 1.42, .75, .67), Vector3(.58, 1.00, 1.83), false, paint)
			mesh.box(Vector3(side * 1.42, 1.33, .67), Vector3(.70, .16, 1.95), paint)
			_door(mesh, Vector3(side * 1.42, .66, 1.64), .30, .60, false, paint)
			_crate(mesh, Vector3(side * 1.49, .52, -1.40), Vector3(.51, .54, .56))
		_room(mesh, Vector3(0, 2.60, -.39), Vector3(1.04, .67, .99), false, paint)
		mesh.box(Vector3(0, 3.01, -.39), Vector3(1.21, .15, 1.16), paint)
		_windows(mesh, Vector3(0, 2.62, .14), .79, .29, 2)
		_door(mesh, Vector3(0, 1.02, 1.29), .89, 1.46, false, paint)
		_windows(mesh, Vector3(-.89, 1.31, 1.31), .57, .39, 2)
		_windows(mesh, Vector3(.89, 1.31, 1.31), .57, .39, 2)
		mesh.box(Vector3(0, .28, 1.64), Vector3(1.38, .13, .36), KRAFT)
		_marks(mesh, faction, owner, Vector3(.75, 1.59, 1.34), Vector3(.65, 2.29, .55), .29)
		_flag(mesh, Vector3(0, 3.10, -.38), faction, owner, 1.07, .65)

static func _outpost(mesh, hammer: bool, paint: Color, faction: String, owner: Color) -> void:
	_base(mesh, 2.84, 2.82, hammer)
	if hammer:
		_room(mesh, Vector3(0, 1.10, -.14), Vector3(2.34, 1.70, 2.06), true, paint)
		_room(mesh, Vector3(0, 1.08, .87), Vector3(1.30, 1.66, .56), true, paint)
		_door(mesh, Vector3(0, 1.02, 1.19), .68, 1.39, true, paint)
		_solid_box(mesh, Vector3(0, 2.22, -.30), Vector3(1.48, .38, 1.05), ARMOR, "room")
		mesh.box(Vector3(0, 2.45, -.30), Vector3(1.60, .13, 1.17), paint)
		_windows(mesh, Vector3(0, 2.26, .27), 1.07, .23, 2)
		for side: float in [-1.0, 1.0]:
			_crate(mesh, Vector3(side * 1.04, .57, 1.03), Vector3(.48, .65, .51), true)
			mesh.cylinder(Vector3(side * .98, 2.49, -.74), .067, .75, Vector3.UP, INK, 8)
		_marks(mesh, faction, owner, Vector3(-.79, 1.40, .99), Vector3(.52, 2.54, -.27), .24)
		_flag(mesh, Vector3(-.48, 2.50, -.54), faction, owner, .86, .45)
	else:
		_room(mesh, Vector3(0, .99, -.15), Vector3(2.24, 1.48, 2.13), false, paint)
		_roof(mesh, Vector3(0, 1.82, -.15), 2.43, 2.32, .38, paint)
		_room(mesh, Vector3(0, 2.27, -.43), Vector3(.78, .52, .72), false, paint)
		mesh.box(Vector3(0, 2.61, -.43), Vector3(.93, .14, .87), paint)
		_door(mesh, Vector3(0, .99, .96), .76, 1.31, false, paint)
		for side: float in [-1.0, 1.0]:
			_windows(mesh, Vector3(side * .77, 1.23, .97), .40, .34, 1)
			_crate(mesh, Vector3(side * 1.04, .51, 1.05), Vector3(.47, .51, .46))
		_marks(mesh, faction, owner, Vector3(0, 1.48, 1.03), Vector3(.53, 2.07, .36), .23)
		_flag(mesh, Vector3(0, 2.68, -.43), faction, owner, .91, .49)

static func _power(mesh, hammer: bool, paint: Color, faction: String, owner: Color) -> void:
	_base(mesh, 2.84, 2.82, hammer)
	if hammer:
		_room(mesh, Vector3(0, 1.09, -.07), Vector3(2.44, 1.67, 2.22), true, paint)
		for side: float in [-1.0, 1.0]:
			_room(mesh, Vector3(side * .87, .72, .88), Vector3(.65, .90, .57), true, paint)
			_door(mesh, Vector3(side * .87, .69, 1.19), .38, .69, true, paint)
		_door(mesh, Vector3(0, 1.01, 1.10), .64, 1.40, true, paint)
		for x: float in [.26, .93]:
			_solid_cylinder(mesh, Vector3(x, 2.82, -.73), .23, 1.61, Vector3.UP, ARMOR)
			for y: float in [2.14, 2.59, 3.17]: mesh.cylinder(Vector3(x, y, -.73), .252, .14, Vector3.UP, paint, 10)
			mesh.cylinder(Vector3(x, 3.65, -.73), .27, .12, Vector3.UP, INK, 10)
			_smoke_ports.append(Vector3(x, 3.72, -.73))
		_solid_box(mesh, Vector3(-.80, 2.47, -.75), Vector3(.55, 1.03, .58), ARMOR, "equipment")
		for y: float in [2.13, 2.47, 2.80]: mesh.box(Vector3(-.80, y, -.42), Vector3(.61, .13, .14), KRAFT)
		mesh.box(Vector3(-.80, 3.05, -.75), Vector3(.70, .16, .71), INK)
		_marks(mesh, faction, owner, Vector3(0, 1.65, 1.19), Vector3(-.11, 2.34, .35), .26)
	else:
		_room(mesh, Vector3(0, 1.03, .01), Vector3(2.33, 1.56, 2.26), false, paint)
		_roof(mesh, Vector3(0, 1.90, .01), 2.53, 2.43, .35, paint)
		_door(mesh, Vector3(0, 1.00, 1.20), .71, 1.35, false, paint)
		_windows(mesh, Vector3(-.82, 1.27, 1.20), .41, .38, 1)
		_windows(mesh, Vector3(.82, 1.27, 1.20), .41, .38, 1)
		for i: int in range(2):
			var x: float = -.66 if i == 0 else .65
			var top: float = 3.10 if i == 0 else 3.78
			_solid_box(mesh, Vector3(x, 1.99, -.56), Vector3(.58, .52, .58), KRAFT, "equipment")
			_solid_cylinder(mesh, Vector3(x, (2.17 + top) * .5, -.56), .205, top - 2.17, Vector3.UP, paint)
			mesh.cylinder(Vector3(x, top - .10, -.56), .235, .15, Vector3.UP, KRAFT, 12)
			mesh.cylinder(Vector3(x, top + .02, -.56), .233, .10, Vector3.UP, INK, 12)
			_smoke_ports.append(Vector3(x, top + .08, -.56))
		_marks(mesh, faction, owner, Vector3(0, 1.51, 1.22), Vector3(.57, 2.17, .52), .25)

static func _refinery(mesh, hammer: bool, paint: Color, faction: String, owner: Color) -> void:
	_base(mesh, 3.82, 3.80, hammer)
	if hammer:
		# Thick rear processing house, low front mill and attached storage plant.
		_room(mesh, Vector3(.30, 1.63, -.74), Vector3(2.42, 2.75, 1.90), true, paint)
		_room(mesh, Vector3(-.42, 1.08, .61), Vector3(1.49, 1.63, 1.33), true, paint)
		_door(mesh, Vector3(-.44, 1.04, 1.35), .79, 1.38, true, paint)
		_solid_cylinder(mesh, Vector3(-1.39, 1.02, .20), .36, 1.54, Vector3.UP, RED_DARK)
		mesh.cylinder(Vector3(-1.39, 1.85, .20), .40, .14, Vector3.UP, KRAFT, 12)
		mesh.line(Vector3(-1.39, 1.85, .20), Vector3(-1.39, 2.84, .20), .10, INK)
		mesh.line(Vector3(-1.39, 2.84, .20), Vector3(-.32, 2.84, -.74), .10, INK)
		_solid_box(mesh, Vector3(1.07, .63, 1.12), Vector3(1.11, .74, .95), ARMOR, "equipment")
		for x: float in [.72, 1.07, 1.42]:
			mesh.prism([Vector2(-.14, 0), Vector2(-.20, .37), Vector2(0, .76), Vector2(.18, .39), Vector2(.13, 0)], .29, Vector3(x, 1.03, 1.15), paint)
		_solid_cylinder(mesh, Vector3(-.43, 2.10, .56), .27, 1.18, Vector3.RIGHT, RED_DARK)
		for x: float in [-.84, -.43, -.02]: mesh.cylinder(Vector3(x, 2.10, .56), .30, .10, Vector3.RIGHT, KRAFT, 10)
		for x: float in [-.27, .77]:
			_solid_cylinder(mesh, Vector3(x, 3.28, -.85), .23, .58, Vector3.UP, ARMOR)
			mesh.cylinder(Vector3(x, 3.61, -.85), .28, .14, Vector3.UP, paint, 10)
			_smoke_ports.append(Vector3(x, 3.69, -.85))
		_marks(mesh, faction, owner, Vector3(.48, 2.40, .27), Vector3(.32, 3.45, -.22), .32)
	else:
		# A full sorting house supports the high processor and crystal reception bay.
		_room(mesh, Vector3(-.67, 1.06, -.31), Vector3(1.79, 1.61, 2.35), false, paint)
		_roof(mesh, Vector3(-.67, 1.97, -.31), 1.99, 2.53, .45, paint)
		_room(mesh, Vector3(.88, 1.28, -.55), Vector3(1.09, 2.04, 1.83), false, paint)
		_solid_cylinder(mesh, Vector3(.87, 2.81, -.52), .49, .94, Vector3.UP, paint)
		mesh.cylinder(Vector3(.87, 3.34, -.52), .55, .13, Vector3.UP, KRAFT, 12)
		_solid_box(mesh, Vector3(.87, 3.49, -.52), Vector3(.48, .22, .50), KRAFT, "equipment")
		_door(mesh, Vector3(-.62, 1.02, .94), .88, 1.42, false, paint)
		_solid_box(mesh, Vector3(.59, .60, 1.26), Vector3(1.48, .64, .78), KRAFT, "equipment")
		for x: float in [.10, .57, 1.04]:
			mesh.prism([Vector2(-.17, 0), Vector2(-.20, .36), Vector2(0, .88), Vector2(.22, .39), Vector2(.14, 0)], .31, Vector3(x, .94, 1.29), BLUE.lightened(.23))
		mesh.prism([Vector2(-.95, .38), Vector2(-.29, 1.32), Vector2(-.09, 1.22), Vector2(-.71, .33)], .47, Vector3(-.53, .32, 1.13), paint)
		mesh.line(Vector3(.91, 2.05, -.63), Vector3(1.64, 2.05, -.63), .09, STEEL)
		_solid_cylinder(mesh, Vector3(1.52, 1.27, -.67), .23, 1.60, Vector3.UP, KRAFT)
		_marks(mesh, faction, owner, Vector3(-.55, 1.50, .99), Vector3(-.68, 2.30, .25), .27)

static func _barracks(mesh, hammer: bool, paint: Color, faction: String, owner: Color) -> void:
	_base(mesh, 2.84, 2.82, hammer)
	if hammer:
		_solid_box(mesh, Vector3(0, .44, -.15), Vector3(2.56, .37, 2.33), ARMOR, "room")
		# Three connected muster compartments, with lower central entry and side forts.
		for side: float in [-1.0, 1.0]:
			_solid_box(mesh, Vector3(side * .88, 1.05, -.19), Vector3(.72, 1.57, 2.17), ARMOR, "room")
			mesh.box(Vector3(side * .88, 1.10, .94), Vector3(.66, 1.42, .15), paint)
			mesh.box(Vector3(side * 1.24, 1.07, -.19), Vector3(.13, 1.45, 2.25), paint)
			_armor_vault(mesh, Vector3(side * .88, 1.90, -.19), .94, 2.34, .39, paint)
			_door(mesh, Vector3(side * .88, 1.04, 1.04), .46, 1.42, true, paint)
		_solid_box(mesh, Vector3(0, .99, -.37), Vector3(.91, 1.46, 1.82), RED_DARK, "room")
		_armor_vault(mesh, Vector3(0, 1.77, -.37), 1.09, 1.98, .24, paint)
		_solid_box(mesh, Vector3(0, .94, .79), Vector3(.89, 1.37, .62), ARMOR, "room")
		mesh.box(Vector3(0, 1.67, .79), Vector3(1.00, .17, .76), paint)
		_door(mesh, Vector3(0, .99, 1.16), .60, 1.32, true, paint)
		_crate(mesh, Vector3(-1.08, .47, 1.16), Vector3(.37, .42, .38), true)
		_marks(mesh, faction, owner, Vector3(0, 1.86, 1.19), Vector3(.88, 2.36, -.17), .22)
		_flag(mesh, Vector3(0, 2.07, -.76), faction, owner, .74, .42)
	else:
		_room(mesh, Vector3(0, 1.02, -.16), Vector3(2.40, 1.53, 2.16), false, paint)
		_roof(mesh, Vector3(0, 1.88, -.16), 2.59, 2.35, .58, paint)
		_door(mesh, Vector3(-.53, 1.01, .97), .61, 1.39, false, paint)
		_windows(mesh, Vector3(.53, 1.20, .99), .94, .37, 2)
		mesh.box(Vector3(-.52, .30, 1.21), Vector3(.90, .13, .36), KRAFT)
		for x: float in [.49, .90]:
			mesh.box(Vector3(x, .29, 1.18), Vector3(.045, .035, .28), PAPER, false)
			mesh.cylinder(Vector3(x, .64, 1.27), .10, .035, Vector3.BACK, paint, 8)
		_marks(mesh, faction, owner, Vector3(-.53, 1.52, 1.02), Vector3(.56, 2.25, .39), .23)
		_flag(mesh, Vector3(-.81, 2.39, -.68), faction, owner, .71, .43)

static func _factory(mesh, hammer: bool, paint: Color, faction: String, owner: Color) -> void:
	_base(mesh, 3.82, 3.80, hammer)
	# Closed rear and thick side walls form a full-depth manufacturing building.
	# The single front assembly door exposes the work bed, not the whole building.
	_solid_box(mesh, Vector3(0, .36, -.17), Vector3(3.38, .23, 2.99), ARMOR if hammer else KRAFT, "floor")
	_solid_box(mesh, Vector3(0, 1.37, -1.49), Vector3(3.32, 2.08, .29), ARMOR if hammer else PAPER, "wall")
	for side: float in [-1.0, 1.0]:
		_solid_box(mesh, Vector3(side * 1.53, 1.37, -.15), Vector3(.31, 2.08, 2.95), ARMOR if hammer else PAPER, "wall")
		_solid_box(mesh, Vector3(side * 1.15, 1.32, 1.33), Vector3(1.05, 1.98, .30), paint if hammer else PAPER, "wall")
		mesh.box(Vector3(side * 1.59, 1.22, .05), Vector3(.13, 1.58, 2.52), RED_DARK if hammer else paint)
		_crate(mesh, Vector3(side * 1.47, .54, 1.61), Vector3(.53, .53, .42), hammer)
		_solid_box(mesh, Vector3(side * 1.16, .96, -.18), Vector3(.59, 1.24, 2.26), ARMOR if hammer else KRAFT, "equipment")
	_solid_box(mesh, Vector3(0, 2.22, 1.32), Vector3(3.32, .36, .34), paint, "wall")
	mesh.box(Vector3(0, .32, 1.62), Vector3(1.37, .16, .55), KRAFT)
	for x: float in [-.42, .42]: mesh.box(Vector3(x, .52, -.13), Vector3(.19, .14, 2.96), STEEL)
	_service_chassis(mesh, Vector3(0, .56, .48), hammer, paint)
	if hammer:
		# Wide low armored production hull with stacked roof plates and flank pods.
		_solid_box(mesh, Vector3(0, 2.42, -.16), Vector3(3.46, .32, 3.10), paint, "roof")
		_solid_box(mesh, Vector3(0, 2.69, -.30), Vector3(2.87, .22, 2.53), RED_DARK, "roof")
		for side: float in [-1.0, 1.0]:
			_solid_box(mesh, Vector3(side * 1.20, 2.92, -.60), Vector3(.52, .40, .84), ARMOR, "equipment")
			mesh.box(Vector3(side * 1.20, 3.17, -.60), Vector3(.61, .14, .93), paint)
			mesh.cylinder(Vector3(side * 1.47, 2.35, -1.22), .12, 1.16, Vector3.UP, INK, 8)
		mesh.box(Vector3(0, 1.83, .72), Vector3(.91, .29, .63), paint)
		mesh.cylinder(Vector3(0, 1.49, .72), .16, .44, Vector3.UP, STEEL, 8)
		_marks(mesh, faction, owner, Vector3(0, 2.22, 1.52), Vector3(0, 2.84, -.27), .31)
	else:
		# Complete blue pitched roof; the large cream end wall surrounds the door.
		_roof(mesh, Vector3(0, 2.48, -.17), 3.56, 3.13, .71, paint)
		mesh.prism([Vector2(-1.65, 0), Vector2(0, .66), Vector2(1.65, 0)], .23, Vector3(0, 2.38, 1.29), PAPER)
		for side: float in [-1.0, 1.0]:
			mesh.box(Vector3(side * .69, 1.29, 1.52), Vector3(.18, 1.72, .19), paint)
		mesh.box(Vector3(0, 2.14, 1.53), Vector3(1.49, .18, .19), paint)
		_solid_box(mesh, Vector3(-.97, 2.91, -1.01), Vector3(.47, .55, .57), KRAFT, "equipment")
		mesh.box(Vector3(-.97, 3.23, -1.01), Vector3(.55, .13, .66), paint)
		_marks(mesh, faction, owner, Vector3(0, 2.65, 1.43), Vector3(.73, 2.91, .57), .29)
		_flag(mesh, Vector3(-.92, 3.31, -1.02), faction, owner, .68, .43)

static func _tower(mesh, turret, hammer: bool, paint: Color, faction: String, owner: Color) -> Dictionary:
	_base(mesh, 1.88, 1.86, hammer)
	if hammer:
		# Broad armored bunker and independent low gun cupola.
		_solid_box(mesh, Vector3(0, .70, 0), Vector3(1.63, .92, 1.61), ARMOR)
		mesh.prism([Vector2(-.84, 0), Vector2(-.71, .87), Vector2(-.48, 1.10), Vector2(.48, 1.10), Vector2(.71, .87), Vector2(.84, 0)], 1.63, Vector3(0, .24, 0), paint)
		for z: float in [-.64, .64]: mesh.box(Vector3(0, .82, z), Vector3(1.29, .24, .18), KRAFT)
		mesh.cylinder(Vector3(0, 1.40, 0), .67, .19, Vector3.UP, INK, 12)
		turret.cylinder(Vector3(0, .16, 0), .56, .35, Vector3.UP, paint, 10)
		turret.box(Vector3(.33, .18, 0), Vector3(.47, .30, .41), KRAFT)
		turret.cylinder(Vector3(.67, .20, 0), .115, .43, Vector3.RIGHT, STEEL, 8)
		turret.cylinder(Vector3(.88, .20, 0), .145, .08, Vector3.RIGHT, INK, 8)
		turret.badge(Vector3(-.14, .37, 0), faction, owner, Vector3.UP, .19)
		_marks(mesh, faction, owner, Vector3(0, .68, .86), Vector3(-.48, 1.29, -.48), .20)
		return {"pivot": Vector3(0, 1.49, 0), "muzzle": Vector3(.93, .20, 0)}
	# Substantial watchhouse on thick timber legs and a broad service pedestal.
	_solid_box(mesh, Vector3(0, .65, 0), Vector3(1.30, .80, 1.30), KRAFT, "room")
	for x: float in [-.59, .59]:
		for z: float in [-.59, .59]:
			_solid_box(mesh, Vector3(x, 1.71, z), Vector3(.20, 2.14, .20), WOOD, "support")
		for z: float in [-.59, .59]:
			mesh.line(Vector3(x, 1.05, z), Vector3(-x, 2.54, z), .047, KRAFT)
	_solid_box(mesh, Vector3(0, 2.81, 0), Vector3(1.42, .68, 1.36), PAPER, "room")
	mesh.box(Vector3(0, 2.43, 0), Vector3(1.63, .16, 1.58), paint)
	mesh.box(Vector3(0, 3.20, 0), Vector3(1.57, .13, 1.51), paint)
	_windows(mesh, Vector3(0, 2.83, .72), 1.13, .30, 3)
	mesh.cylinder(Vector3(0, 3.32, 0), .44, .12, Vector3.UP, INK, 10)
	for z: float in [-.15, .15]:
		turret.box(Vector3(.14, .17, z), Vector3(.35, .20, .15), paint)
		turret.cylinder(Vector3(.59, .18, z), .049, .63, Vector3.RIGHT, STEEL, 8)
		turret.cylinder(Vector3(.89, .18, z), .064, .09, Vector3.RIGHT, INK, 8)
	turret.box(Vector3(-.18, .14, 0), Vector3(.18, .29, .51), KRAFT)
	turret.badge(Vector3(-.18, .33, 0), faction, owner, Vector3.UP, .17)
	_marks(mesh, faction, owner, Vector3(0, .76, .72), Vector3(-.48, 3.30, -.43), .19)
	return {"pivot": Vector3(0, 3.40, 0), "muzzle": Vector3(.97, .18, 0)}

static func _tech(mesh, hammer: bool, paint: Color, faction: String, owner: Color) -> void:
	_base(mesh, 2.84, 2.82, hammer)
	if hammer:
		_room(mesh, Vector3(0, 1.04, -.17), Vector3(2.40, 1.58, 2.10), true, paint)
		_dome(mesh, Vector3(-.35, 1.96, -.33), .77, .68, paint)
		mesh.cylinder(Vector3(-.35, 2.04, -.33), .80, .13, Vector3.UP, KRAFT, 16)
		mesh.cylinder(Vector3(-.35, 2.68, -.33), .20, .12, Vector3.UP, INK, 10)
		_room(mesh, Vector3(.92, .86, .89), Vector3(.65, 1.18, .59), true, paint)
		_door(mesh, Vector3(-.45, 1.00, .94), .75, 1.36, true, paint)
		_solid_cylinder(mesh, Vector3(.85, 2.22, -.54), .30, .84, Vector3.UP, ARMOR)
		for y: float in [1.91, 2.25, 2.58]: mesh.cylinder(Vector3(.85, y, -.54), .37, .13, Vector3.UP, KRAFT, 12)
		_solid_cylinder(mesh, Vector3(.85, 2.89, -.54), .19, .42, Vector3.UP, STEEL)
		_dome(mesh, Vector3(.85, 3.10, -.54), .22, .21, STEEL)
		_ring(mesh, Vector3(.85, 3.04, -.54), .44, Vector3.BACK, KRAFT, .047)
		_ring(mesh, Vector3(.85, 3.04, -.54), .44, Vector3.RIGHT, KRAFT, .047)
		_ring(mesh, Vector3(.85, 3.04, -.54), .42, Vector3.UP, paint, .041)
		_marks(mesh, faction, owner, Vector3(.91, 1.06, 1.28), Vector3(-.33, 2.77, -.32), .23)
	else:
		_room(mesh, Vector3(-.25, 1.05, -.17), Vector3(1.86, 1.60, 2.15), false, paint)
		_dome(mesh, Vector3(-.30, 1.95, -.22), .88, .79, paint)
		mesh.cylinder(Vector3(-.30, 1.97, -.22), .90, .12, Vector3.UP, KRAFT, 16)
		mesh.cylinder(Vector3(-.30, 2.79, -.22), .20, .10, Vector3.UP, KRAFT, 10)
		_room(mesh, Vector3(.99, .88, -.02), Vector3(.57, 1.24, 1.81), false, paint)
		mesh.box(Vector3(.99, 1.59, -.02), Vector3(.68, .14, 1.92), paint)
		_door(mesh, Vector3(-.29, 1.01, .96), .72, 1.38, false, paint)
		_windows(mesh, Vector3(-.91, 1.18, .96), .33, .35, 1)
		_solid_box(mesh, Vector3(.99, 1.78, -.56), Vector3(.60, .35, .64), KRAFT, "equipment")
		_solid_cylinder(mesh, Vector3(.99, 2.67, -.56), .17, 1.46, Vector3.UP, paint)
		for y: float in [2.12, 2.55, 2.96, 3.33]: mesh.cylinder(Vector3(.99, y, -.56), .26, .13, Vector3.UP, KRAFT, 10)
		mesh.cylinder(Vector3(.99, 3.60, -.56), .069, .48, Vector3.UP, INK, 8)
		mesh.cylinder(Vector3(.99, 3.86, -.56), .10, .075, Vector3.UP, paint, 8)
		_marks(mesh, faction, owner, Vector3(.99, 1.08, .94), Vector3(-.30, 2.88, -.22), .24)

static func _repair(mesh, hammer: bool, paint: Color, faction: String, owner: Color) -> void:
	_base(mesh, 2.84, 2.82, hammer)
	_solid_box(mesh, Vector3(0, .39, .10), Vector3(1.54, .29, 2.35), ARMOR if hammer else KRAFT, "equipment")
	mesh.box(Vector3(0, .57, .10), Vector3(1.10, .10, 2.17), INK)
	for x: float in [-.47, .47]: mesh.box(Vector3(x, .67, .10), Vector3(.20, .12, 2.13), STEEL)
	for side: float in [-1.0, 1.0]:
		_room(mesh, Vector3(side * 1.09, .71, -.54), Vector3(.53, .92, 1.42), hammer, paint)
		mesh.box(Vector3(side * 1.09, 1.25, -.54), Vector3(.62, .16, 1.53), paint)
		_crate(mesh, Vector3(side * 1.10, .63, .67), Vector3(.54, .70, .65), hammer)
		_door(mesh, Vector3(side * 1.10, .68, 1.04), .33, .52, hammer, paint)
	_crate(mesh, Vector3(0, .86, -1.11), Vector3(1.45, 1.20, .36), hammer)
	_service_chassis(mesh, Vector3(0, .72, .25), hammer, paint)
	if hammer:
		# Four thick columns and a red overhead crane enclose an armored work bed.
		for x: float in [-1.03, 1.03]:
			for z: float in [-.80, .69]:
				_solid_box(mesh, Vector3(x, 1.63, z), Vector3(.27, 2.55, .33), ARMOR, "gantry")
				mesh.box(Vector3(x, 1.70, z + .18), Vector3(.15, 2.11, .08), KRAFT)
		for z: float in [-.80, .69]:
			_solid_box(mesh, Vector3(0, 2.94, z), Vector3(2.61, .32, .39), paint, "gantry")
		_solid_box(mesh, Vector3(0, 3.03, -.10), Vector3(.49, .37, 1.79), paint, "gantry")
		mesh.box(Vector3(0, 2.58, -.06), Vector3(.50, .48, .50), KRAFT)
		mesh.line(Vector3(0, 2.35, -.06), Vector3(0, 1.31, -.06), .040, INK)
		mesh.box(Vector3(0, 1.29, -.06), Vector3(.32, .18, .32), STEEL)
		mesh.cylinder(Vector3(1.07, 1.61, -1.04), .21, .94, Vector3.UP, paint, 8)
		_marks(mesh, faction, owner, Vector3(0, 2.95, .92), Vector3(0, 3.28, -.13), .27)
	else:
		# Broad blue bridge crane, complete tool cabins and service tanks.
		for side: float in [-1.0, 1.0]:
			_solid_box(mesh, Vector3(side * 1.05, 1.76, -.45), Vector3(.28, 2.87, .43), paint, "gantry")
			mesh.box(Vector3(side * 1.05, .45, -.45), Vector3(.55, .35, .70), KRAFT)
		_solid_box(mesh, Vector3(0, 3.21, -.45), Vector3(2.61, .34, .61), paint, "gantry")
		mesh.box(Vector3(0, 3.41, -.45), Vector3(2.32, .11, .51), KRAFT)
		mesh.box(Vector3(.22, 2.91, -.45), Vector3(.45, .28, .55), KRAFT)
		mesh.cylinder(Vector3(.22, 2.69, -.45), .14, .25, Vector3.UP, INK, 8)
		mesh.line(Vector3(.22, 2.55, -.45), Vector3(.22, 1.35, -.45), .037, INK)
		mesh.line(Vector3(.22, 1.35, -.45), Vector3(.38, 1.22, -.45), .056, STEEL)
		mesh.line(Vector3(.38, 1.22, -.45), Vector3(.53, 1.41, -.45), .056, STEEL)
		mesh.cylinder(Vector3(-1.11, 1.56, -1.02), .22, .89, Vector3.UP, paint, 10)
		_marks(mesh, faction, owner, Vector3(0, 3.21, -.10), Vector3(0, 3.52, -.45), .28)

static func _dish(mesh, center: Vector3, radius: float, hammer: bool, facing: Vector3 = Vector3(0, .66, .75)) -> void:
	var normal: Vector3 = facing.normalized()
	var right: Vector3 = Vector3.UP.cross(normal).normalized()
	var up: Vector3 = normal.cross(right).normalized()
	var segments: int = 16
	var depth: float = radius * .25
	for i: int in range(segments):
		var a: float = float(i) / float(segments) * TAU
		var b: float = float(i + 1) / float(segments) * TAU
		var rim_a: Vector3 = center + right * cos(a) * radius + up * sin(a) * radius + normal * depth
		var rim_b: Vector3 = center + right * cos(b) * radius + up * sin(b) * radius + normal * depth
		var middle_a: Vector3 = center + right * cos(a) * radius * .50 + up * sin(a) * radius * .50 + normal * depth * .18
		var middle_b: Vector3 = center + right * cos(b) * radius * .50 + up * sin(b) * radius * .50 + normal * depth * .18
		mesh.triangle(center, middle_a, middle_b, STEEL if hammer else PAPER, normal)
		mesh.face([middle_a, rim_a, rim_b, middle_b], STEEL if hammer else PAPER, normal)
		mesh.triangle(center - normal * .075, rim_b - normal * .075, rim_a - normal * .075, ARMOR if hammer else KRAFT, -normal)
		mesh.face([rim_a, rim_b, rim_b - normal * .075, rim_a - normal * .075], INK, (rim_a + rim_b - center * 2.0).normalized())
		mesh.line(rim_a, rim_b, .027, INK)
		if i % 4 == 0: mesh.line(center + normal * .016, rim_a, .021, ARMOR if hammer else STEEL)
	mesh.line(center, center + normal * radius * .82, .052, INK)
	mesh.cylinder(center + normal * radius * .83, .10, .19, normal, RED if hammer else BLUE, 8)

static func _command(mesh, hammer: bool, paint: Color, faction: String, owner: Color) -> void:
	_base(mesh, 2.84, 2.82, hammer)
	if hammer:
		# Elevated central armored control room, lower side vaults and front vestibule.
		_solid_box(mesh, Vector3(0, 1.28, -.27), Vector3(1.02, 2.05, 1.96), ARMOR, "room")
		mesh.box(Vector3(0, 1.39, .78), Vector3(.88, 1.63, .15), paint)
		_armor_vault(mesh, Vector3(0, 2.38, -.27), 1.23, 2.15, .33, paint)
		for side: float in [-1.0, 1.0]:
			_room(mesh, Vector3(side * .91, .94, -.16), Vector3(.61, 1.38, 2.06), true, paint)
			mesh.box(Vector3(side * .91, 1.68, -.16), Vector3(.69, .18, 2.18), paint)
		_room(mesh, Vector3(0, 1.02, .91), Vector3(.88, 1.53, .64), true, paint)
		_door(mesh, Vector3(0, 1.04, 1.28), .58, 1.42, true, paint)
		_windows(mesh, Vector3(-.91, 1.25, .94), .43, .35, 1)
		_solid_box(mesh, Vector3(0, 2.83, -.56), Vector3(.57, .32, .58), ARMOR, "equipment")
		mesh.cylinder(Vector3(0, 3.10, -.56), .17, .28, Vector3.UP, INK, 10)
		_dish(mesh, Vector3(0, 3.69, -.38), .79, true, Vector3(-.57, .67, .47))
		_solid_box(mesh, Vector3(.93, 2.15, -.74), Vector3(.33, .54, .41), ARMOR, "equipment")
		mesh.cylinder(Vector3(.93, 2.87, -.74), .068, .91, Vector3.UP, INK, 8)
		for y: float in [2.60, 2.94, 3.26]:
			mesh.cylinder(Vector3(.93, y, -.74), .14, .11, Vector3.UP, paint, 8)
			mesh.line(Vector3(.75, y, -.74), Vector3(1.11, y, -.74), .028, STEEL)
		_marks(mesh, faction, owner, Vector3(-.91, .72, .99), Vector3(.90, 2.06, .37), .23)
	else:
		# Wide low control hall and a separate, visibly tall glazed observation tower.
		_room(mesh, Vector3(-.29, .97, -.10), Vector3(1.91, 1.44, 2.18), false, paint)
		mesh.box(Vector3(-.29, 1.78, -.10), Vector3(2.04, .17, 2.31), paint)
		_door(mesh, Vector3(-.34, .99, 1.05), .68, 1.35, false, paint)
		_windows(mesh, Vector3(-.98, 1.13, 1.07), .35, .31, 1)
		_room(mesh, Vector3(.98, 1.41, -.33), Vector3(.60, 2.31, 1.57), false, paint)
		_solid_box(mesh, Vector3(.98, 2.93, -.33), Vector3(.75, .63, .93), PAPER, "room")
		_windows(mesh, Vector3(.98, 2.95, .18), .57, .33, 2)
		mesh.box(Vector3(.98, 3.31, -.33), Vector3(.88, .13, 1.06), paint)
		mesh.cylinder(Vector3(.98, 3.66, -.61), .060, .55, Vector3.UP, INK, 8)
		_solid_box(mesh, Vector3(-.58, 2.02, -.44), Vector3(.62, .28, .61), KRAFT, "equipment")
		mesh.cylinder(Vector3(-.58, 2.27, -.44), .16, .29, Vector3.UP, INK, 10)
		_dish(mesh, Vector3(-.58, 2.84, -.29), .82, false)
		_marks(mesh, faction, owner, Vector3(.34, 1.15, 1.10), Vector3(.45, 1.90, .57), .23)

static func _hangar_aircraft(mesh, center: Vector3, hammer: bool, paint: Color) -> void:
	var length: float = 1.55 if hammer else 1.48
	_solid_box(mesh, center + Vector3(0, .25, 0), Vector3(.29, .26, length), paint, "equipment")
	mesh.prism([Vector2(-.15, 0), Vector2(0, .18), Vector2(.15, 0)], length * .87, center + Vector3(0, .37, -.03), paint)
	mesh.slab([Vector2(-.15, -.45), Vector2(-.69, .04), Vector2(-.73, .28), Vector2(-.13, .16), Vector2(.13, .16), Vector2(.73, .28), Vector2(.69, .04), Vector2(.15, -.45)], .09, center + Vector3(0, .31, .02), paint)
	mesh.slab([Vector2(-.09, -.66), Vector2(-.41, -.48), Vector2(-.42, -.32), Vector2(.42, -.32), Vector2(.41, -.48), Vector2(.09, -.66)], .065, center + Vector3(0, .36, -.12), paint)
	_solid_box(mesh, center + Vector3(0, .53, -.07), Vector3(.19, .18, .43), INK, "equipment")
	mesh.box(center + Vector3(0, .63, -.07), Vector3(.14, .045, .32), GLASS, false)
	mesh.box(center + Vector3(0, .64, -.66), Vector3(.08, .40, .24), paint)
	for x: float in [-.20, .20]:
		mesh.cylinder(center + Vector3(x, .06, .19), .08, .07, Vector3.RIGHT, INK, 8)
	mesh.cylinder(center + Vector3(0, .06, -.53), .075, .09, Vector3.RIGHT, INK, 8)
	mesh.cylinder(center + Vector3(0, .24, -length * .51), .107, .12, Vector3.BACK, ARMOR, 8)

static func _airfield(mesh, hammer: bool, paint: Color, faction: String, owner: Color) -> void:
	_base(mesh, 4.76, 4.74, hammer)
	if hammer:
		# A wide armored hangar fills the rear building strip above the front apron.
		mesh.box(Vector3(0, .28, .88), Vector3(4.39, .10, 2.50), INK, false)
		for x: float in [-1.36, 0.0, 1.36]:
			mesh.box(Vector3(x, .35, .92), Vector3(.065, .026, 1.98), PAPER, false)
			mesh.box(Vector3(x, .35, 1.90), Vector3(.58, .026, .09), PAPER, false)
		_solid_box(mesh, Vector3(-.31, .51, -1.03), Vector3(3.58, .40, 1.83), ARMOR, "floor")
		_solid_box(mesh, Vector3(-.31, 1.20, -1.88), Vector3(3.58, 1.46, .27), ARMOR, "wall")
		for x: float in [-1.95, 1.34]:
			_solid_box(mesh, Vector3(x, 1.19, -1.03), Vector3(.30, 1.47, 1.84), paint, "wall")
		for x: float in [-1.17, .31]:
			_solid_box(mesh, Vector3(x, 1.18, -.23), Vector3(.25, 1.45, .34), paint, "wall")
		_armor_vault(mesh, Vector3(-1.63, 1.87, -1.03), 1.06, 2.05, .32, paint, .24)
		_armor_vault(mesh, Vector3(-.43, 1.88, -1.03), 1.54, 2.05, .43, paint, .24)
		_armor_vault(mesh, Vector3(.91, 1.87, -1.03), 1.21, 2.05, .32, paint, .24)
		for x: float in [-1.05, .37]:
			_solid_box(mesh, Vector3(x, .98, -1.21), Vector3(.62, .57, .79), ARMOR, "equipment")
			mesh.box(Vector3(x, 1.32, -1.21), Vector3(.67, .14, .88), KRAFT)
		_hangar_aircraft(mesh, Vector3(-.40, .75, -.04), true, paint)
		_hangar_aircraft(mesh, Vector3(-1.27, .39, 1.02), true, paint)
		_room(mesh, Vector3(1.79, 1.00, -1.05), Vector3(.81, 1.48, 1.88), true, paint)
		_solid_box(mesh, Vector3(1.79, 2.23, -1.07), Vector3(1.04, .54, 1.02), KRAFT, "room")
		_windows(mesh, Vector3(1.79, 2.24, -.51), .83, .29, 3)
		mesh.box(Vector3(1.79, 2.58, -1.07), Vector3(1.12, .13, 1.13), paint)
		mesh.cylinder(Vector3(1.79, 2.96, -1.07), .064, .62, Vector3.UP, INK, 8)
		_marks(mesh, faction, owner, Vector3(-.43, 2.02, .04), Vector3(-.43, 2.43, -1.02), .29)
	else:
		# Long runway beside a complete pitched-roof aircraft hangar and control tower.
		mesh.box(Vector3(.78, .27, 0), Vector3(1.78, .08, 4.32), INK, false)
		for z: float in [-1.71, -.85, 0.0, .85, 1.71]: mesh.box(Vector3(.78, .33, z), Vector3(.11, .026, .36), PAPER, false)
		for x: float in [.10, 1.46]: mesh.box(Vector3(x, .33, 0), Vector3(.056, .026, 4.04), PAPER, false)
		_solid_box(mesh, Vector3(-1.11, .50, -.90), Vector3(1.97, .37, 2.50), KRAFT, "floor")
		_solid_box(mesh, Vector3(-1.11, 1.33, -2.03), Vector3(1.97, 1.49, .25), PAPER, "wall")
		for x: float in [-1.97, -.25]:
			_solid_box(mesh, Vector3(x, 1.30, -.90), Vector3(.25, 1.56, 2.50), PAPER, "wall")
		_solid_box(mesh, Vector3(-1.11, 2.09, .37), Vector3(1.97, .29, .28), paint, "wall")
		_solid_box(mesh, Vector3(-1.11, 2.10, -.90), Vector3(1.97, .23, 2.50), KRAFT, "roof")
		_roof(mesh, Vector3(-1.11, 2.22, -.90), 2.17, 2.70, .44, paint)
		for x: float in [-1.96, -.26]: mesh.box(Vector3(x, 1.33, .52), Vector3(.16, 1.48, .18), paint)
		_solid_box(mesh, Vector3(-1.11, 1.00, -1.33), Vector3(.84, .65, .71), KRAFT, "equipment")
		_hangar_aircraft(mesh, Vector3(-1.11, .74, .19), false, paint)
		_room(mesh, Vector3(1.88, 1.29, -1.31), Vector3(.91, 2.07, 1.14), false, paint)
		_room(mesh, Vector3(1.88, .71, -.27), Vector3(.71, .90, .72), false, paint)
		_solid_box(mesh, Vector3(1.88, 2.64, -1.31), Vector3(1.05, .67, 1.11), PAPER, "room")
		_windows(mesh, Vector3(1.88, 2.66, -.71), .84, .32, 3)
		mesh.box(Vector3(1.88, 3.05, -1.31), Vector3(1.14, .15, 1.21), paint)
		mesh.cylinder(Vector3(1.88, 3.42, -1.31), .049, .60, Vector3.UP, INK, 8)
		_marks(mesh, faction, owner, Vector3(-1.11, 2.11, .56), Vector3(-1.10, 2.69, -.90), .25)
