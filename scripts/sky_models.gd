extends RefCounted

## Sky Wing Order: hurried, convincing cardboard craft with genuinely advanced
## functions. Thick boxes, paper tubes and folded boards carry each clear role.
## All recipes are authored at game scale; ground/air units face +X.
## Only construction primitives are shared: every role owns its silhouette/layout.
const WHITE = Color("e9e5dc")
const PEARL = Color("c9c7cf")
const PURPLE = Color("74569d")
const VIOLET = Color("4b376e")
const INK = Color("342d40")
const METAL = Color("a5a6b0")
const GLASS = Color("89b8a3")
const RUBBER = Color("4d4958")
const GOLD = Color("d8c17d")
const CUT = Color("c6b99d")
const TAPE = Color("d8ccb2")
const BUILDINGS = ["hq", "power", "refinery", "barracks", "factory", "repair", "command", "tech", "airfield", "accumulator", "outpost", "tower", "aa_tower", "anti_tower", "wall"]
const UNITS = ["harvester", "scout", "tank", "artillery", "aa", "inspection", "designation", "disruptor", "pulse", "fighter", "attacker", "air_transport", "recon"]

static func make(mesh, art: String, team: int, kind: String) -> Dictionary:
	if art not in (BUILDINGS if kind == "building" else UNITS): return {}
	var volume = load("res://scripts/volume_models.gd")
	var owner: Color = volume.player_color(team)
	var weapon: Dictionary = {}
	mesh.capture_shell = true
	if kind == "building":
		match art:
			"hq": _hq(mesh, owner)
			"power": _power(mesh, owner)
			"refinery": _refinery(mesh, owner)
			"barracks": _barracks(mesh, owner)
			"factory": _factory(mesh, owner)
			"repair": _repair(mesh, owner)
			"command": _command(mesh, owner)
			"tech": _tech(mesh, owner)
			"airfield": _airfield(mesh, owner)
			"accumulator": _accumulator(mesh, owner)
			"outpost": _outpost(mesh, owner)
			"tower", "aa_tower", "anti_tower": weapon = _defense(mesh, art, owner)
			"wall": _wall(mesh, owner)
	else:
		match art:
			"harvester": _harvester(mesh, owner)
			"scout": weapon = _scout(mesh, owner)
			"tank": weapon = _tank(mesh, owner)
			"artillery": weapon = _artillery(mesh, owner)
			"aa": weapon = _aa(mesh, owner)
			"inspection": _inspection(mesh, owner)
			"designation": _designation(mesh, owner)
			"disruptor": weapon = _disruptor(mesh, owner)
			"pulse": weapon = _pulse(mesh, owner)
			"fighter": _fighter(mesh, owner)
			"attacker": _attacker(mesh, owner)
			"air_transport": _air_transport(mesh, owner)
			"recon": _recon(mesh, owner)
	mesh.capture_shell = false
	var extent: Vector3 = Vector3.ZERO
	for point: Vector3 in mesh.vertices:
		extent = extent.max(Vector3(absf(point.x), point.y, absf(point.z)))
	var recipe: Dictionary = {"body_mesh": mesh.mesh(), "body_border_mesh": mesh.shell_mesh(), "faction_geometry": true, "design_signature": "sky_" + art, "design": "sky_" + art}
	if weapon.has("mesh"):
		var gun = weapon.mesh
		var pivot: Vector3 = weapon.pivot
		gun.capture_shell = false
		for point: Vector3 in gun.vertices:
			var positioned: Vector3 = point + pivot
			extent = extent.max(Vector3(absf(positioned.x), positioned.y, absf(positioned.z)))
		recipe.turret_mesh = gun.mesh()
		recipe.turret_border_mesh = gun.shell_mesh()
		recipe.turret_pos = pivot
		recipe.muzzle_pos = weapon.muzzle
		recipe.recoil_distance = .045
	elif kind != "building":
		recipe.muzzle_pos = Vector3(extent.x, minf(extent.y * .55, .65), 0)
	recipe.dimensions = Vector3(extent.x * 2.0, extent.y, extent.z * 2.0)
	if art == "harvester":
		recipe.cargo_origin = Vector3(-1.03, .93, -.29)
		recipe.cargo_step = Vector3(.23, .11, .30)
		recipe.drill_pos = Vector3(1.19, .33, 0)
	return recipe

static func _part():
	var volume = load("res://scripts/volume_models.gd")
	return volume.CraftMesh.new()

static func _append(mesh, part, center: Vector3, right: Vector3, up: Vector3, forward: Vector3) -> void:
	for i: int in range(part.vertices.size()):
		var p: Vector3 = part.vertices[i]
		var n: Vector3 = part.normals[i]
		mesh.vertices.append(center + right * p.x + up * p.y + forward * p.z)
		mesh.normals.append((right * n.x + up * n.y + forward * n.z).normalized())
		mesh.colors.append(part.colors[i])
	for i: int in range(part.shell_vertices.size()):
		var p: Vector3 = part.shell_vertices[i]
		var n: Vector3 = part.shell_normals[i]
		mesh.shell_vertices.append(center + right * p.x + up * p.y + forward * p.z)
		mesh.shell_normals.append((right * n.x + up * n.y + forward * n.z).normalized())

static func _box(mesh, center: Vector3, size: Vector3, color: Color = WHITE) -> void:
	mesh.box(center, size, color, false)

static func _panel(mesh, center: Vector3, width: float, height: float, normal: Vector3, color: Color) -> void:
	var part = _part()
	part.box(Vector3.ZERO, Vector3(width, height, .055), color, false)
	var outward: Vector3 = normal.normalized()
	var right: Vector3 = Vector3.RIGHT if absf(outward.y) > .9 else Vector3.UP.cross(outward).normalized()
	_append(mesh, part, center, right, outward.cross(right).normalized(), outward)

static func _mark(mesh, center: Vector3, owner: Color, normal: Vector3 = Vector3.UP, size: float = .22) -> void:
	# A distinct four-point star with swept paired wings, never the canon bird badge.
	var part = _part()
	part.box(Vector3.ZERO, Vector3(size * 2.65, size * 2.28, .060), VIOLET, false)
	part.box(Vector3(0, 0, .042), Vector3(size * 2.39, size * 2.05, .038), owner, false)
	part.prism([Vector2(0, size * .85), Vector2(size * .15, size * .16), Vector2(size * .51, 0), Vector2(size * .13, -size * .13), Vector2(0, -size * .87), Vector2(-size * .13, -size * .13), Vector2(-size * .51, 0), Vector2(-size * .15, size * .16)], .045, Vector3(0, 0, .085), WHITE, false)
	for side: float in [-1.0, 1.0]:
		part.prism([Vector2(side * size * .18, size * .09), Vector2(side * size * 1.06, size * .61), Vector2(side * size * .70, -size * .10), Vector2(side * size * .20, -size * .31)], .045, Vector3(0, 0, .083), WHITE, false)
	var outward: Vector3 = normal.normalized()
	var right: Vector3 = Vector3.RIGHT if absf(outward.y) > .9 else Vector3.UP.cross(outward).normalized()
	_append(mesh, part, center, right, outward.cross(right).normalized(), outward)

# The slight shifts belong to cut paper and pasted seams, never to the main
# weapon direction. Paint and tape add material information without new shells.
static func _carton(mesh, center: Vector3, size: Vector3, color: Color = WHITE, skew: float = .025, taped: bool = true) -> void:
	var w: float = size.x * .5
	var h: float = size.y * .5
	mesh.prism([Vector2(-w, -h), Vector2(-w + skew, h), Vector2(w + skew, h - .018), Vector2(w, -h)], size.z, center, color, false, {0:color.darkened(.035), 1:color.lightened(.035), 2:color.darkened(.025), 3:CUT})
	if not taped: return
	var top: float = center.y + h + .012
	_box(mesh, Vector3(center.x + skew * .5, top, center.z), Vector3(size.x * .87, .016, .085), TAPE)
	mesh.line(Vector3(center.x - w * .78, top + .012, center.z + .050), Vector3(center.x + w * .48, top + .006, center.z + .039), .007, INK)
	var side_z: float = center.z + size.z * .5 + .012
	mesh.line(Vector3(center.x - w * .68, center.y - h * .50, side_z), Vector3(center.x - w * .67, center.y + h * .45, side_z), .009, INK)
	mesh.line(Vector3(center.x - w * .67, center.y + h * .45, side_z), Vector3(center.x - w * .19, center.y + h * .40, side_z), .009, INK)
	_box(mesh, Vector3(center.x + w * .58, center.y + h * .47, side_z), Vector3(.085, size.y * .44, .018), TAPE)

static func _board(mesh, profile: Array, depth: float, center: Vector3, color: Color = WHITE) -> void:
	var cut_edges: Dictionary = {}
	# Thin boards show pale cut thickness. A broad extrusion is a folded roof
	# or launch trough: its long faces are painted and its narrow ends are cut.
	for i: int in range(profile.size()): cut_edges[i] = CUT if depth <= .30 else color
	mesh.prism(profile, depth, center, color if depth <= .30 else CUT, false, cut_edges)

static func _sheet(mesh, profile: Array, thickness: float, center: Vector3, color: Color = WHITE) -> void:
	var part = _part()
	part.capture_shell = mesh.capture_shell
	_board(part, profile, thickness, Vector3.ZERO, color)
	_append(mesh, part, center, Vector3.RIGHT, Vector3.FORWARD, Vector3.UP)

static func _tube(mesh, center: Vector3, axis: Vector3, radius: float, length: float, color: Color = WHITE, bore: bool = false) -> void:
	var direction: Vector3 = axis.normalized()
	mesh.cylinder(center, radius, length, direction, color, 10, false)
	mesh.cylinder(center - direction * length * .23, radius + .007, .070, direction, TAPE, 10, false)
	var tip: Vector3 = center + direction * (length * .5 + .006)
	mesh.cylinder(tip, radius + .004, .018, direction, CUT, 10, false)
	if bore: mesh.cylinder(tip + direction * .013, radius * .68, .021, direction, INK, 10, false)

static func _beam(mesh, start: Vector3, end: Vector3, width: float, depth: float, color: Color = WHITE) -> void:
	var axis: Vector3 = (end - start).normalized()
	var right: Vector3 = axis.cross(Vector3.BACK)
	if right.length_squared() < .01: right = axis.cross(Vector3.RIGHT)
	right = right.normalized()
	var forward: Vector3 = right.cross(axis).normalized()
	var part = _part()
	part.capture_shell = mesh.capture_shell
	_carton(part, Vector3.ZERO, Vector3(width, start.distance_to(end), depth), color, .008, false)
	_append(mesh, part, (start + end) * .5, right, axis, forward)

static func _paper_ring(mesh, center: Vector3, normal: Vector3, radius: float, width: float, color: Color = PURPLE) -> void:
	var part = _part()
	part.capture_shell = mesh.capture_shell
	for i: int in range(8):
		var a: float = float(i) / 8.0 * TAU
		var b: float = float(i + 1) / 8.0 * TAU
		_board(part, [Vector2(cos(a), sin(a)) * radius, Vector2(cos(b), sin(b)) * radius, Vector2(cos(b), sin(b)) * (radius - width), Vector2(cos(a), sin(a)) * (radius - width)], .14, Vector3.ZERO, color)
	var outward: Vector3 = normal.normalized()
	var right: Vector3 = Vector3.RIGHT if absf(outward.y) > .9 else Vector3.UP.cross(outward).normalized()
	_append(mesh, part, center, right, outward.cross(right).normalized(), outward)

static func _equipment_lines(mesh, center: Vector3, width: float, depth: float) -> void:
	# Three marker strokes and one painted inspection patch on a flat top.
	mesh.line(center + Vector3(-width * .36, .014, -depth * .26), center + Vector3(width * .22, .014, -depth * .24), .011, INK)
	mesh.line(center + Vector3(width * .22, .014, -depth * .24), center + Vector3(width * .20, .014, depth * .09), .011, INK)
	mesh.line(center + Vector3(-width * .25, .018, depth * .20), center + Vector3(width * .03, .018, depth * .23), .009, INK)
	_sheet(mesh, [Vector2(-.20, -.10), Vector2(.23, -.12), Vector2(.21, .06), Vector2(-.18, .08)], .012, center + Vector3(-width * .09, .023, -depth * .12), PURPLE)

static func _scale_board(mesh, center: Vector3, width: float, height: float, normal: Vector3 = Vector3.BACK) -> void:
	var part = _part()
	_board(part, [Vector2(-width * .5, -height * .5), Vector2(-width * .5 + .027, height * .5), Vector2(width * .5, height * .5 - .025), Vector2(width * .5, -height * .5)], .085, Vector3.ZERO, WHITE)
	part.line(Vector3(-width * .35, 0, .049), Vector3(width * .35, .015, .049), .010, INK)
	for i: int in range(4):
		var x: float = (-.30 + float(i) * .20) * width
		part.line(Vector3(x, -.08, .049), Vector3(x + .010, .08 if i % 2 == 0 else .055, .049), .009, INK)
	var outward: Vector3 = normal.normalized()
	var right: Vector3 = Vector3.RIGHT if absf(outward.y) > .9 else Vector3.UP.cross(outward).normalized()
	_append(mesh, part, center, right, outward.cross(right).normalized(), outward)

static func _base(mesh, width: float, depth: float) -> void:
	_sheet(mesh, [Vector2(-width * .5, -depth * .5), Vector2(width * .49, -depth * .5 + .06), Vector2(width * .5, depth * .5), Vector2(-width * .48, depth * .5 - .025)], .20, Vector3(0, .13, 0), PEARL)
	_box(mesh, Vector3(-width * .27, .242, depth * .31), Vector3(width * .24, .018, .095), TAPE)

static func _entry(mesh, center: Vector3, width: float, height: float) -> void:
	_panel(mesh, center, width, height, Vector3.BACK, INK)
	_panel(mesh, center + Vector3(.015, .03, .039), width * .79, height * .90, Vector3.BACK, PURPLE)
	_box(mesh, center + Vector3(width * .40, 0, .078), Vector3(.033, height * .82, .032), TAPE)
	_box(mesh, center + Vector3(width * .18, -.05, .085), Vector3(.075, .055, .028), INK)

static func _wheels(mesh, positions: Array, half_width: float, radius: float) -> void:
	for side: float in [-1.0, 1.0]:
		for x: float in positions:
			mesh.cylinder(Vector3(x, radius + .025, side * half_width), radius, .18, Vector3.BACK, RUBBER, 10, false)
			mesh.cylinder(Vector3(x, radius + .025, side * (half_width + .10)), radius * .54, .055, Vector3.BACK, PEARL, 10, false)
			mesh.cylinder(Vector3(x, radius + .025, side * (half_width + .132)), radius * .20, .014, Vector3.BACK, PURPLE, 8, false)

static func _tracks(mesh, length: float, half_width: float, height: float, wheels: int) -> void:
	for side: float in [-1.0, 1.0]:
		mesh.prism([Vector2(-length * .50, .12), Vector2(-length * .43, height), Vector2(length * .43, height), Vector2(length * .50, .12), Vector2(length * .42, .035), Vector2(-length * .42, .035)], .26, Vector3(0, 0, side * half_width), RUBBER, false)
		_box(mesh, Vector3(0, height + .021, side * half_width), Vector3(length * .84, .050, .30), PURPLE)
		for i: int in range(wheels):
			var x: float = (-.38 + .76 * float(i) / float(maxi(wheels - 1, 1))) * length
			mesh.cylinder(Vector3(x, height * .46, side * (half_width + .15)), height * .30, .045, Vector3.BACK, PEARL, 8, false)

static func _weapon(gun, pivot: Vector3, muzzle: Vector3) -> Dictionary:
	return {"mesh": gun, "pivot": pivot, "muzzle": muzzle}

# BUILDINGS ------------------------------------------------------------------
static func _hq(mesh, owner: Color) -> void:
	_base(mesh, 4.88, 4.26)
	_carton(mesh, Vector3(0, .83, .16), Vector3(4.05, 1.18, 2.80))
	_entry(mesh, Vector3(-.08, .78, 1.61), .87, .91)
	for side: float in [-1.0, 1.0]:
		# Broad folded wings meet the roof along their entire lower edge.
		_board(mesh, [Vector2(-.83 * side, 0), Vector2(-.12 * side, .67), Vector2(.89 * side, .15), Vector2(.91 * side, .04), Vector2(-.10 * side, .52), Vector2(-.77 * side, -.08)], 1.87, Vector3(side * 1.00, 1.45, .05), PURPLE)
		_box(mesh, Vector3(side * .53, 1.44, .05), Vector3(.15, .15, 1.60), TAPE)
		_mark(mesh, Vector3(side * 1.14, .96, 1.66), owner, Vector3.BACK, .23)
	# The flat star-map board is a hand-drawn device, supported by two tabs.
	_box(mesh, Vector3(-.35, 1.69, -.79), Vector3(.16, .65, .23), PEARL)
	_box(mesh, Vector3(.41, 1.69, -.79), Vector3(.16, .65, .23), PEARL)
	_board(mesh, [Vector2(-.94, 0), Vector2(-.97, 1.03), Vector2(.92, .98), Vector2(.95, 0)], .16, Vector3(.04, 1.73, -.79), WHITE)
	mesh.line(Vector3(-.71, 2.24, -.69), Vector3(.72, 2.27, -.69), .018, INK)
	mesh.line(Vector3(-.42, 1.96, -.685), Vector3(.26, 2.52, -.685), .014, INK)
	_mark(mesh, Vector3(.05, 2.28, -.665), owner, Vector3.BACK, .22)
	_mark(mesh, Vector3(.06, 1.47, .99), owner, Vector3.UP, .26)

static func _power(mesh, owner: Color) -> void:
	_base(mesh, 3.62, 3.38)
	_carton(mesh, Vector3(0, .65, .09), Vector3(2.99, .84, 2.44))
	for side: float in [-1.0, 1.0]:
		var height: float = 1.93 if side < 0 else 1.74
		_tube(mesh, Vector3(side * .77, 1.03 + height * .5, -.20), Vector3.UP, .44, height, WHITE)
		for ring: int in range(3):
			mesh.cylinder(Vector3(side * .77, 1.55 + ring * .32, -.20), .459, .066, Vector3.UP, PURPLE, 10, false)
		_box(mesh, Vector3(side * .76, 1.11, .55), Vector3(.24, .18, .55), TAPE)
	# A visible broad connecting wire is physically attached at both ends.
	mesh.line(Vector3(-.76, 1.29, .24), Vector3(-.75, 1.26, .73), .045, VIOLET)
	mesh.line(Vector3(-.75, 1.26, .73), Vector3(.79, 1.28, .73), .045, VIOLET)
	mesh.line(Vector3(.79, 1.28, .73), Vector3(.78, 1.31, .22), .045, VIOLET)
	_scale_board(mesh, Vector3(.11, .66, 1.34), .72, .46)
	_mark(mesh, Vector3(-.91, .66, 1.37), owner, Vector3.BACK, .22)
	_mark(mesh, Vector3(.06, 1.10, 1.01), owner, Vector3.UP, .23)

static func _refinery(mesh, owner: Color) -> void:
	_base(mesh, 4.24, 3.62)
	_carton(mesh, Vector3(.68, .61, -.23), Vector3(2.07, .73, 2.49))
	_tube(mesh, Vector3(.54, 1.78, -.47), Vector3.UP, .55, 1.62)
	_box(mesh, Vector3(.54, 2.67, -.47), Vector3(1.29, .15, 1.32), PURPLE)
	# Inclined cut-board feed chute with raised folded edges and real support.
	_beam(mesh, Vector3(-1.66, .70, .26), Vector3(-.32, 2.15, -.46), .89, .11, WHITE)
	for z: float in [-.43, .43]:
		_beam(mesh, Vector3(-1.64, .78, .26 + z), Vector3(-.31, 2.23, -.46 + z), .095, .16, PURPLE)
	_beam(mesh, Vector3(-1.29, .26, .15), Vector3(-1.29, 1.10, .15), .17, .25, PEARL)
	# Open receiving hopper: an unobstructed dark mouth, four thick folded sides.
	_box(mesh, Vector3(.66, .46, 1.19), Vector3(1.60, .14, .90), VIOLET)
	for side: float in [-1.0, 1.0]:
		_box(mesh, Vector3(.66 + side * .83, .74, 1.17), Vector3(.13, .67, .99), WHITE)
	_box(mesh, Vector3(.66, .77, 1.67), Vector3(1.76, .69, .12), WHITE)
	_box(mesh, Vector3(.66, .49, .70), Vector3(1.74, .23, .12), PURPLE)
	_mark(mesh, Vector3(.68, .86, 1.76), owner, Vector3.BACK, .22)
	_mark(mesh, Vector3(.56, 2.77, -.49), owner, Vector3.UP, .24)

static func _barracks(mesh, owner: Color) -> void:
	_base(mesh, 3.85, 3.05)
	_carton(mesh, Vector3(.01, .79, -.17), Vector3(3.06, 1.12, 1.89))
	# A folded roof with a slightly offset ridge and exposed thick ends.
	_board(mesh, [Vector2(-1.65, -.06), Vector2(-.15, .50), Vector2(1.61, -.04), Vector2(1.57, -.15), Vector2(-.15, .35), Vector2(-1.63, -.18)], 2.07, Vector3(0, 1.37, -.17), PURPLE)
	mesh.line(Vector3(-.15, 1.89, -.86), Vector3(-.13, 1.89, .56), .014, TAPE)
	_entry(mesh, Vector3(-.51, .81, .82), .65, .97)
	_scale_board(mesh, Vector3(.59, .92, .84), .75, .40)
	_sheet(mesh, [Vector2(-1.23, -.30), Vector2(1.18, -.28), Vector2(1.20, .40), Vector2(-1.23, .44)], .065, Vector3(0, .284, 1.05), WHITE)
	for x: float in [-.76, .03, .82]: _box(mesh, Vector3(x, .325, 1.02), Vector3(.36, .021, .045), PURPLE)
	_mark(mesh, Vector3(.01, 1.21, .92), owner, Vector3.BACK, .20)
	_mark(mesh, Vector3(.74, 1.58, -.28), owner, Vector3.UP, .21)

static func _factory(mesh, owner: Color) -> void:
	_base(mesh, 5.08, 4.18)
	_carton(mesh, Vector3(0, .47, .01), Vector3(4.25, .44, 2.63), PEARL)
	# Open long assembly bed; broad triangular folded supports make the roofless
	# silhouette different from the closed workshops of the industrial faction.
	for side: float in [-1.0, 1.0]:
		_board(mesh, [Vector2(-1.99, 0), Vector2(-1.32, 1.63), Vector2(-.93, 1.62), Vector2(-1.36, .29), Vector2(1.30, .29), Vector2(.92, 1.43), Vector2(1.26, 1.48), Vector2(1.99, 0)], .17, Vector3(0, .68, side * 1.31), WHITE)
		_box(mesh, Vector3(0, 1.90, side * 1.28), Vector3(3.16, .20, .25), PURPLE)
		_box(mesh, Vector3(0, .78, side * .78), Vector3(3.85, .15, .11), VIOLET)
	_box(mesh, Vector3(-1.21, 1.95, 0), Vector3(.24, .23, 2.73), WHITE)
	_box(mesh, Vector3(-1.22, 1.61, .20), Vector3(.10, .48, .14), PEARL)
	_carton(mesh, Vector3(-1.22, 1.32, .20), Vector3(.39, .25, .42), PURPLE)
	_carton(mesh, Vector3(.30, .98, .16), Vector3(1.64, .43, 1.23), WHITE, -.035)
	_equipment_lines(mesh, Vector3(.30, 1.22, .16), 1.56, 1.10)
	_carton(mesh, Vector3(1.76, .74, -1.62), Vector3(.58, .95, .47), PURPLE)
	_mark(mesh, Vector3(-1.81, .94, 1.43), owner, Vector3.BACK, .22)
	_mark(mesh, Vector3(1.50, .725, .98), owner, Vector3.UP, .25)

static func _repair(mesh, owner: Color) -> void:
	# A visible open cross, with two bent cardboard arms rooted in its side pads.
	_sheet(mesh, [Vector2(-1.86, -.58), Vector2(-.57, -.58), Vector2(-.57, -1.83), Vector2(.56, -1.83), Vector2(.56, -.58), Vector2(1.85, -.58), Vector2(1.85, .58), Vector2(.56, .58), Vector2(.56, 1.82), Vector2(-.57, 1.82), Vector2(-.57, .58), Vector2(-1.86, .58)], .25, Vector3(0, .18, 0), PEARL)
	_box(mesh, Vector3(0, .36, 0), Vector3(1.25, .14, 2.97), WHITE)
	for side: float in [-1.0, 1.0]:
		_carton(mesh, Vector3(side * 1.48, .55, -.11), Vector3(.54, .50, .90), PURPLE)
		_board(mesh, [Vector2(-.11 * side, 0), Vector2(-.11 * side, 1.23), Vector2(-.66 * side, 1.61), Vector2(-.76 * side, 1.45), Vector2(-.28 * side, 1.08), Vector2(-.29 * side, 0)], .19, Vector3(side * 1.48, .79, -.12), WHITE)
		_box(mesh, Vector3(side * .82, 2.28, -.12), Vector3(.32, .24, .33), PURPLE)
	_scale_board(mesh, Vector3(-1.48, .65, .40), .38, .23)
	_box(mesh, Vector3(.10, .46, 1.32), Vector3(.70, .018, .11), PURPLE)
	_mark(mesh, Vector3(0, .36, 1.53), owner, Vector3.BACK, .22)
	_mark(mesh, Vector3(.05, .45, .24), owner, Vector3.UP, .23)

static func _command(mesh, owner: Color) -> void:
	_base(mesh, 3.69, 3.42)
	_carton(mesh, Vector3(0, .50, .07), Vector3(2.71, .53, 2.48))
	_carton(mesh, Vector3(-.39, .99, -.17), Vector3(.74, .48, .72), PURPLE)
	# Three large joined fan leaves. A simple crossbar and tabs carry the fan.
	_box(mesh, Vector3(-.39, 1.36, -.17), Vector3(.24, .75, .25), PEARL)
	_board(mesh, [Vector2(-.14, 0), Vector2(-1.34, 1.01), Vector2(-1.07, 1.63), Vector2(.00, .28)], .17, Vector3(-.39, 1.45, -.17), WHITE)
	_board(mesh, [Vector2(-.05, .03), Vector2(-.53, 1.70), Vector2(.05, 1.82), Vector2(.20, .14)], .18, Vector3(-.39, 1.45, -.17), PURPLE)
	_board(mesh, [Vector2(.02, .05), Vector2(.63, 1.62), Vector2(1.21, 1.20), Vector2(.29, .07)], .17, Vector3(-.39, 1.45, -.16), WHITE)
	mesh.line(Vector3(-.43, 1.59, -.056), Vector3(-1.51, 2.77, -.056), .017, INK)
	mesh.line(Vector3(-.38, 1.60, -.045), Vector3(.50, 2.74, -.045), .017, INK)
	_box(mesh, Vector3(-.39, 1.67, -.031), Vector3(.51, .20, .042), TAPE)
	_scale_board(mesh, Vector3(.77, .78, .84), .87, .46)
	_mark(mesh, Vector3(-.68, .56, 1.37), owner, Vector3.BACK, .21)
	_mark(mesh, Vector3(.06, .82, .34), owner, Vector3.UP, .25)

static func _tech(mesh, owner: Color) -> void:
	_base(mesh, 3.74, 3.53)
	_carton(mesh, Vector3(0, .51, .17), Vector3(2.92, .55, 2.53), PEARL)
	# Two slightly unequal thick cut-cardboard hoops rest on the same test bed.
	_paper_ring(mesh, Vector3(-.80, 1.82, -.21), Vector3.BACK, 1.06, .22, PURPLE)
	_paper_ring(mesh, Vector3(.84, 1.56, -.06), Vector3.BACK, .84, .22, WHITE)
	_box(mesh, Vector3(-.80, .89, -.21), Vector3(.48, .48, .43), WHITE)
	_box(mesh, Vector3(.84, .86, -.06), Vector3(.48, .31, .43), PURPLE)
	_carton(mesh, Vector3(.02, 1.10, .61), Vector3(.98, .60, .82), WHITE)
	_scale_board(mesh, Vector3(.02, 1.13, 1.064), .69, .33)
	mesh.line(Vector3(-.55, 1.10, .36), Vector3(-.79, 1.27, -.08), .043, VIOLET)
	mesh.line(Vector3(.54, 1.10, .37), Vector3(.83, 1.10, .04), .043, VIOLET)
	_box(mesh, Vector3(-.83, 2.86, -.21), Vector3(.30, .10, .19), TAPE)
	_mark(mesh, Vector3(.02, .55, 1.52), owner, Vector3.BACK, .23)
	_mark(mesh, Vector3(.04, 1.44, .57), owner, Vector3.UP, .23)

static func _airfield(mesh, owner: Color) -> void:
	_base(mesh, 5.63, 5.03)
	_sheet(mesh, [Vector2(-2.53, -1.43), Vector2(2.54, -1.47), Vector2(2.60, 2.13), Vector2(-2.51, 2.10)], .13, Vector3(0, .30, .13), WHITE)
	for z: float in [-.89, -.19, .53, 1.24, 1.92]:
		mesh.line(Vector3(.11, .379, z - .15), Vector3(.14, .379, z + .16), .027, PURPLE)
	for x: float in [-1.84, 2.10]: mesh.line(Vector3(x, .379, -1.10), Vector3(x + .035, .379, 1.88), .018, INK)
	# Folded open hangar: one cut roof and two end plates, grounded at the back.
	_board(mesh, [Vector2(-1.80, 0), Vector2(-1.02, 1.27), Vector2(1.29, 1.24), Vector2(1.81, 0), Vector2(1.64, 0), Vector2(1.19, 1.10), Vector2(-.94, 1.12), Vector2(-1.63, 0)], 1.37, Vector3(.38, .26, -1.62), PEARL)
	_box(mesh, Vector3(.38, .92, -2.32), Vector3(3.29, 1.22, .13), WHITE)
	_box(mesh, Vector3(.44, 1.54, -1.64), Vector3(.13, .02, 1.18), TAPE)
	_carton(mesh, Vector3(-2.02, .95, -1.58), Vector3(.57, 1.31, 1.19), PURPLE)
	_scale_board(mesh, Vector3(-2.01, 1.38, -.944), .50, .31)
	_box(mesh, Vector3(-2.02, 1.83, -1.57), Vector3(.11, .43, .11), WHITE)
	_board(mesh, [Vector2(-.30, -.13), Vector2(-.26, .21), Vector2(.31, .16), Vector2(.31, -.14)], .08, Vector3(-2.02, 2.04, -1.56), PURPLE)
	# Small hand-built aircraft on the apron makes the building's role immediate.
	_carton(mesh, Vector3(-.97, .48, .71), Vector3(1.38, .21, .27), PEARL, .014, false)
	_sheet(mesh, [Vector2(-.35, -.65), Vector2(.24, -.63), Vector2(.27, .59), Vector2(-.39, .63)], .07, Vector3(-.97, .57, .71), PURPLE)
	_mark(mesh, Vector3(.72, .394, 1.52), owner, Vector3.UP, .29)
	_mark(mesh, Vector3(-2.04, .79, -.934), owner, Vector3.BACK, .21)

static func _accumulator(mesh, owner: Color) -> void:
	_base(mesh, 3.77, 3.45)
	_carton(mesh, Vector3(0, .58, .07), Vector3(2.99, .68, 2.53), PEARL)
	# A tied capacitor bundle, with exposed paper-tube ends and one drawn gauge.
	for record: Vector3 in [Vector3(-.76, 1.24, -.34), Vector3(.01, 1.24, -.35), Vector3(.73, 1.24, -.30), Vector3(-.39, 1.88, -.31), Vector3(.40, 1.88, -.28)]:
		_tube(mesh, record, Vector3.BACK, .38, 1.83, WHITE)
	_box(mesh, Vector3(.01, 2.19, -.51), Vector3(1.17, .055, .19), PURPLE)
	for side: float in [-1.0, 1.0]: _beam(mesh, Vector3(side * 1.15, .93, -.53), Vector3(side * .57, 2.19, -.53), .075, .16, TAPE)
	_scale_board(mesh, Vector3(.03, .60, 1.40), .82, .41)
	_mark(mesh, Vector3(-.97, .61, 1.45), owner, Vector3.BACK, .21)
	_mark(mesh, Vector3(.70, .98, 1.10), owner, Vector3.UP, .21)

static func _outpost(mesh, owner: Color) -> void:
	_base(mesh, 3.24, 2.90)
	_carton(mesh, Vector3(0, .66, .10), Vector3(2.53, .81, 1.93))
	for side: float in [-1.0, 1.0]:
		_board(mesh, [Vector2(-.45 * side, 0), Vector2(-.08 * side, .48), Vector2(.58 * side, .10), Vector2(.56 * side, .01), Vector2(-.07 * side, .34), Vector2(-.40 * side, -.06)], .91, Vector3(side * .78, 1.12, -.19), PURPLE)
		_box(mesh, Vector3(side * .45, 1.12, -.18), Vector3(.16, .11, .69), TAPE)
	_entry(mesh, Vector3(-.18, .65, 1.12), .56, .66)
	_board(mesh, [Vector2(-.49, 0), Vector2(-.49, .56), Vector2(.47, .52), Vector2(.48, 0)], .11, Vector3(.04, 1.10, -.68), WHITE)
	_mark(mesh, Vector3(.64, .68, 1.13), owner, Vector3.BACK, .19)
	_mark(mesh, Vector3(.04, 1.10, .62), owner, Vector3.UP, .20)

static func _defense(mesh, art: String, owner: Color) -> Dictionary:
	var width: float = 2.40 if art == "tower" else 2.84
	_base(mesh, width, width * .89)
	# Grounded broad fold feet, with a three-legged compact gun stand.
	for z: float in [-.67, .67]:
		_board(mesh, [Vector2(-.89, 0), Vector2(-.31, .86), Vector2(.29, .83), Vector2(.94, 0)], .16, Vector3(0, .24, z), WHITE)
	_board(mesh, [Vector2(-.71, 0), Vector2(-.22, .79), Vector2(.22, .79), Vector2(.75, 0)], .15, Vector3(-.58, .24, 0), PURPLE)
	_box(mesh, Vector3(0, 1.12, 0), Vector3(.86, .17, 1.46), PEARL)
	_mark(mesh, Vector3(-.07, .61, .79), owner, Vector3.BACK, .20)
	_mark(mesh, Vector3(.76, .265, .68), owner, Vector3.UP, .19)
	var gun = _part()
	gun.capture_shell = true
	if art == "tower":
		_carton(gun, Vector3(0, .21, 0), Vector3(.79, .43, .67), WHITE)
		_tube(gun, Vector3(.66, .20, 0), Vector3.RIGHT, .09, .76, PURPLE, true)
		_scale_board(gun, Vector3(-.08, .29, .39), .41, .22)
		_mark(gun, Vector3(-.08, .45, 0), owner, Vector3.UP, .18)
		return _weapon(gun, Vector3(0, 1.22, 0), Vector3(1.10, .20, 0))
	if art == "aa_tower":
		_carton(gun, Vector3(-.15, .20, 0), Vector3(.99, .40, 1.29), WHITE, -.025)
		for side: float in [-1.0, 1.0]:
			var rear: Vector3 = Vector3(-.46, .22, side * .31)
			var tip: Vector3 = Vector3(.49, 1.10, side * .35)
			_tube(gun, (rear + tip) * .5, (tip - rear).normalized(), .17, rear.distance_to(tip), PURPLE, true)
			_board(gun, [Vector2(-.51, 0), Vector2(-.57, .96), Vector2(-.32, 1.08), Vector2(.50, .20)], .13, Vector3(0, .25, side * .68), WHITE)
		_mark(gun, Vector3(-.10, .44, 0), owner, Vector3.UP, .19)
		return _weapon(gun, Vector3(0, 1.22, 0), Vector3(.58, 1.19, -.35))
	# A fork of two thick boards clamps one very plain, very large emitter tube.
	for side: float in [-1.0, 1.0]:
		_board(gun, [Vector2(-.49, 0), Vector2(-.52, .92), Vector2(-.32, 1.37), Vector2(.27, 1.31), Vector2(.44, .91), Vector2(.27, .79), Vector2(-.24, .96), Vector2(-.22, 0)], .17, Vector3(0, 0, side * .47), WHITE)
	_tube(gun, Vector3(.20, 1.05, 0), Vector3.RIGHT, .33, 1.03, PURPLE, true)
	_box(gun, Vector3(-.24, .66, 0), Vector3(.19, .33, 1.07), TAPE)
	_mark(gun, Vector3(-.22, .32, .58), owner, Vector3.BACK, .17)
	return _weapon(gun, Vector3(0, 1.22, 0), Vector3(.80, 1.05, 0))

static func _wall(mesh, owner: Color) -> void:
	# A thick creased barrier with grounded fold feet and a pasted gate panel.
	_sheet(mesh, [Vector2(-.49, -.28), Vector2(.49, -.27), Vector2(.48, .29), Vector2(-.49, .29)], .12, Vector3(0, .10, 0), PEARL)
	_board(mesh, [Vector2(-.49, 0), Vector2(-.46, 1.37), Vector2(.43, 1.32), Vector2(.49, 0)], .18, Vector3(0, .17, 0), WHITE)
	for side: float in [-1.0, 1.0]:
		_board(mesh, [Vector2(-.13, 0), Vector2(0, .62), Vector2(.13, 0)], .29, Vector3(side * .30, .16, 0), PURPLE)
		_box(mesh, Vector3(side * .37, .94, .104), Vector3(.09, 1.11, .015), TAPE)
	_box(mesh, Vector3(0, .89, .11), Vector3(.33, 1.15, .025), PURPLE)
	mesh.line(Vector3(-.15, .32, .129), Vector3(-.15, 1.43, .129), .010, INK)
	mesh.line(Vector3(.145, .34, .129), Vector3(.13, 1.39, .129), .010, INK)
	_mark(mesh, Vector3(0, 1.05, .15), owner, Vector3.BACK, .10)
	_mark(mesh, Vector3(.13, .173, .18), owner, Vector3.UP, .09)

# GROUND UNITS ---------------------------------------------------------------
static func _harvester(mesh, owner: Color) -> void:
	_wheels(mesh, [-.83, -.05, .73], .73, .29)
	_carton(mesh, Vector3(0, .48, 0), Vector3(2.36, .25, 1.41), PEARL, .016, false)
	_carton(mesh, Vector3(.76, 1.04, 0), Vector3(.84, .87, 1.33), WHITE, -.025)
	_panel(mesh, Vector3(1.215, 1.15, 0), .88, .31, Vector3.RIGHT, PURPLE)
	for side: float in [-1.0, 1.0]:
		_panel(mesh, Vector3(.75, 1.15, side * .695), .40, .31, Vector3(0, 0, side), VIOLET)
		_carton(mesh, Vector3(-.53, 1.10, side * .65), Vector3(1.47, .77, .17), WHITE, .024, false)
		_box(mesh, Vector3(-.51, 1.51, side * .65), Vector3(1.53, .07, .23), PURPLE)
		_mark(mesh, Vector3(-.52, 1.10, side * .77), owner, Vector3(0, 0, side), .18)
	_box(mesh, Vector3(-.53, .77, 0), Vector3(1.43, .18, 1.37), PURPLE)
	_carton(mesh, Vector3(-1.22, 1.10, 0), Vector3(.15, .77, 1.42), WHITE, .015, false)
	_box(mesh, Vector3(-.49, 1.16, .759), Vector3(.090, .58, .018), TAPE)
	_mark(mesh, Vector3(.71, 1.51, 0), owner, Vector3.UP, .20)

static func _scout(mesh, owner: Color) -> Dictionary:
	_wheels(mesh, [-.53, .54], .58, .26)
	_carton(mesh, Vector3(0, .54, 0), Vector3(1.65, .47, 1.04), WHITE, -.026)
	_panel(mesh, Vector3(.84, .57, 0), .62, .21, Vector3.RIGHT, PURPLE)
	_mark(mesh, Vector3(.22, .80, 0), owner, Vector3.UP, .17)
	_mark(mesh, Vector3(-.30, .53, .553), owner, Vector3.BACK, .15)
	var gun = _part()
	gun.capture_shell = true
	_carton(gun, Vector3(0, .10, 0), Vector3(.44, .20, .43), PEARL, .008)
	_box(gun, Vector3(-.04, .50, 0), Vector3(.12, .69, .14), WHITE)
	# A single broad unfoldable survey disc dominates this light vehicle.
	_board(gun, [Vector2(-.45, 0), Vector2(-.62, .45), Vector2(-.42, .76), Vector2(.42, .72), Vector2(.61, .39), Vector2(.40, -.01)], .10, Vector3(-.03, .38, -.06), PURPLE)
	_scale_board(gun, Vector3(-.03, .78, .035), .76, .34)
	_tube(gun, Vector3(.37, .21, .21), Vector3.RIGHT, .053, .53, WHITE, true)
	return _weapon(gun, Vector3(-.20, .79, 0), Vector3(.67, .21, .21))

static func _tank(mesh, owner: Color) -> Dictionary:
	_tracks(mesh, 2.13, .67, .47, 4)
	_carton(mesh, Vector3(.01, .61, 0), Vector3(2.06, .49, 1.16), WHITE, .027)
	_equipment_lines(mesh, Vector3(.36, .871, 0), 1.20, .97)
	for side: float in [-1.0, 1.0]: _mark(mesh, Vector3(-.25, .63, side * .83), owner, Vector3(0, 0, side), .16)
	var gun = _part()
	gun.capture_shell = true
	# Exactly the box-tower / thick paper-tube example of the new faction brief.
	_carton(gun, Vector3(-.08, .25, 0), Vector3(.87, .51, .81), WHITE, -.030)
	_tube(gun, Vector3(.68, .25, 0), Vector3.RIGHT, .143, .97, PURPLE, true)
	_box(gun, Vector3(.34, .25, 0), Vector3(.13, .34, .36), TAPE)
	gun.line(Vector3(-.36, .29, .425), Vector3(.18, .33, .425), .010, INK)
	_mark(gun, Vector3(-.10, .54, 0), owner, Vector3.UP, .19)
	return _weapon(gun, Vector3(-.08, .88, 0), Vector3(1.22, .25, 0))

static func _artillery(mesh, owner: Color) -> Dictionary:
	_tracks(mesh, 2.30, .69, .45, 4)
	_carton(mesh, Vector3(0, .60, 0), Vector3(2.20, .31, 1.26), PEARL, .020)
	for side: float in [-1.0, 1.0]:
		_board(mesh, [Vector2(-.38, 0), Vector2(-.21, .23), Vector2(.38, .35), Vector2(.31, .17)], .16, Vector3(-.90, .075, side * .54), WHITE)
		_mark(mesh, Vector3(-.39, .61, side * .85), owner, Vector3(0, 0, side), .16)
	_mark(mesh, Vector3(-.76, .79, 0), owner, Vector3.UP, .16)
	var gun = _part()
	gun.capture_shell = true
	_carton(gun, Vector3(-.39, .17, 0), Vector3(.62, .34, .64), WHITE, -.018)
	# A long open folded launch trough, with two heavy rails and a rear stop.
	_board(gun, [Vector2(-.58, .28), Vector2(1.61, .61), Vector2(1.64, .76), Vector2(-.55, .43)], .53, Vector3.ZERO, PURPLE)
	for side: float in [-1.0, 1.0]:
		_board(gun, [Vector2(-.59, .29), Vector2(1.67, .65), Vector2(1.63, .88), Vector2(-.55, .57)], .115, Vector3(0, 0, side * .31), WHITE)
		gun.line(Vector3(-.29, .602, side * .246), Vector3(1.45, .864, side * .246), .017, VIOLET)
	_box(gun, Vector3(-.49, .53, 0), Vector3(.13, .30, .75), TAPE)
	_mark(gun, Vector3(-.40, .42, 0), owner, Vector3.UP, .16)
	return _weapon(gun, Vector3(-.18, .81, 0), Vector3(1.76, .77, 0))

static func _aa(mesh, owner: Color) -> Dictionary:
	_wheels(mesh, [-.76, .04, .78], .67, .27)
	_carton(mesh, Vector3(0, .56, 0), Vector3(2.20, .47, 1.24), WHITE, -.024)
	_mark(mesh, Vector3(.77, .82, 0), owner, Vector3.UP, .17)
	for side: float in [-1.0, 1.0]: _mark(mesh, Vector3(.08, .58, side * .654), owner, Vector3(0, 0, side), .16)
	var gun = _part()
	gun.capture_shell = true
	_box(gun, Vector3(-.10, .10, 0), Vector3(1.02, .21, 1.09), PURPLE)
	for side: float in [-1.0, 1.0]:
		_board(gun, [Vector2(-.62, .07), Vector2(-.54, .61), Vector2(.43, .58), Vector2(.56, .07)], .11, Vector3(0, 0, side * .61), WHITE)
		var start: Vector3 = Vector3(-.36, .24, side * .25)
		var tip: Vector3 = Vector3(.51, .74, side * .25)
		_tube(gun, (start + tip) * .5, (tip - start).normalized(), .14, start.distance_to(tip), PURPLE, true)
	# The open rear lid remains attached along its complete lower fold.
	_board(gun, [Vector2(-.61, .19), Vector2(-.84, .91), Vector2(-.71, .95), Vector2(-.48, .21)], 1.20, Vector3.ZERO, WHITE)
	_mark(gun, Vector3(-.17, .14, .70), owner, Vector3.BACK, .15)
	return _weapon(gun, Vector3(-.12, .82, 0), Vector3(.59, .79, -.25))

static func _inspection(mesh, owner: Color) -> void:
	_wheels(mesh, [-.60, .61], .59, .245)
	_carton(mesh, Vector3(0, .47, 0), Vector3(1.92, .30, 1.15), PEARL, .021, false)
	_carton(mesh, Vector3(.59, .81, 0), Vector3(.63, .67, 1.11), WHITE, -.027)
	_panel(mesh, Vector3(.93, .94, 0), .70, .26, Vector3.RIGHT, PURPLE)
	_carton(mesh, Vector3(-.48, .89, -.10), Vector3(.93, .83, .91), WHITE)
	for y: float in [.71, .93, 1.16]:
		_box(mesh, Vector3(-.48, y, .37), Vector3(.77, .035, .027), INK)
		_box(mesh, Vector3(-.45, y + .043, .394), Vector3(.23, .024, .028), PURPLE)
	# Two thick fold strips make a short inspection arm, with no robot fingers.
	_beam(mesh, Vector3(-.38, 1.31, -.14), Vector3(-.50, 1.79, -.14), .11, .15, WHITE)
	_beam(mesh, Vector3(-.50, 1.79, -.14), Vector3(.02, 1.62, -.14), .12, .16, PURPLE)
	_scale_board(mesh, Vector3(.05, 1.50, -.14), .48, .37, Vector3.RIGHT)
	_mark(mesh, Vector3(-.45, 1.37, -.10), owner, Vector3.UP, .17)
	_mark(mesh, Vector3(.26, .58, .607), owner, Vector3.BACK, .15)

static func _designation(mesh, owner: Color) -> void:
	_wheels(mesh, [-.64, .61], .61, .255)
	_carton(mesh, Vector3(0, .51, 0), Vector3(2.00, .42, 1.16), WHITE, -.025)
	_carton(mesh, Vector3(.64, .91, 0), Vector3(.66, .40, 1.02), WHITE)
	_panel(mesh, Vector3(.99, .94, 0), .71, .20, Vector3.RIGHT, PURPLE)
	_carton(mesh, Vector3(-.37, .84, 0), Vector3(.83, .24, .74), PEARL, .016, false)
	# Two large pasted boards form an unmistakable V around one coarse scope.
	for side: float in [-1.0, 1.0]:
		_beam(mesh, Vector3(-.38, .88, side * .10), Vector3(-.38, 1.73, side * .53), .70, .12, WHITE if side < 0 else PURPLE)
		_box(mesh, Vector3(-.38, .99, side * .18), Vector3(.71, .17, .09), TAPE)
	_tube(mesh, Vector3(-.08, 1.28, 0), Vector3.RIGHT, .19, .91, WHITE, true)
	_scale_board(mesh, Vector3(-.73, 1.12, .38), .26, .30)
	_mark(mesh, Vector3(.65, 1.145, 0), owner, Vector3.UP, .16)
	_mark(mesh, Vector3(-.10, .52, .613), owner, Vector3.BACK, .15)

static func _disruptor(mesh, owner: Color) -> Dictionary:
	_wheels(mesh, [-.60, .60], .63, .27)
	_carton(mesh, Vector3(-.08, .64, 0), Vector3(1.78, .68, 1.19), WHITE, .029)
	_carton(mesh, Vector3(-.62, 1.04, -.04), Vector3(.47, .18, .88), PURPLE)
	_panel(mesh, Vector3(.84, .88, 0), .75, .24, Vector3.RIGHT, VIOLET)
	_mark(mesh, Vector3(-.22, 1.012, .05), owner, Vector3.UP, .17)
	_mark(mesh, Vector3(-.08, .63, .628), owner, Vector3.BACK, .16)
	var gun = _part()
	gun.capture_shell = true
	_carton(gun, Vector3(-.17, .13, 0), Vector3(.46, .26, .79), PEARL, -.015, false)
	for side: float in [-1.0, 1.0]:
		_tube(gun, Vector3(.39, .23, side * .32), Vector3.RIGHT, .113, 1.05, PURPLE, true)
	_box(gun, Vector3(.58, .23, 0), Vector3(.16, .18, .89), WHITE)
	_box(gun, Vector3(.59, .33, .03), Vector3(.15, .025, .43), TAPE)
	gun.line(Vector3(.668, .235, -.16), Vector3(.668, .238, .17), .013, INK)
	return _weapon(gun, Vector3(.27, 1.02, 0), Vector3(.98, .23, -.32))

static func _pulse(mesh, owner: Color) -> Dictionary:
	_wheels(mesh, [-.68, .63], .70, .255)
	_carton(mesh, Vector3(0, .61, 0), Vector3(2.04, .57, 1.39), WHITE, -.029)
	_carton(mesh, Vector3(-.33, .99, 0), Vector3(1.02, .22, 1.25), PURPLE)
	_mark(mesh, Vector3(-.34, 1.14, 0), owner, Vector3.UP, .18)
	_mark(mesh, Vector3(-.14, .65, .728), owner, Vector3.BACK, .17)
	var gun = _part()
	gun.capture_shell = true
	_box(gun, Vector3(0, .16, 0), Vector3(.33, .32, .54), PEARL)
	# A thick central board plus two folded leaves; the face is a hand-drawn
	# array, not a forest of lenses or permanently luminous coils.
	_box(gun, Vector3(.05, .67, 0), Vector3(.15, 1.06, .79), WHITE)
	for side: float in [-1.0, 1.0]:
		_beam(gun, Vector3(.05, .71, side * .39), Vector3(-.24, .71, side * .92), .99, .13, PURPLE)
		_box(gun, Vector3(.05, .71, side * .39), Vector3(.20, 1.05, .095), TAPE)
		for y: float in [.43, .78, 1.08]:
			gun.line(Vector3(-.008, y, side * .41), Vector3(-.152, y + .025, side * .72), .018, WHITE)
	for z: float in [-.22, .22]:
		gun.line(Vector3(.139, .30, z), Vector3(.139, 1.11, z + .015), .017, VIOLET)
	_tube(gun, Vector3(.27, .70, 0), Vector3.RIGHT, .18, .33, PEARL, true)
	return _weapon(gun, Vector3(.26, .91, 0), Vector3(.49, .70, 0))

# AIRCRAFT -------------------------------------------------------------------
static func _fighter(mesh, owner: Color) -> void:
	# One broad asymmetrically cut wing, one short flat carton and two engines.
	_sheet(mesh, [Vector2(-.58, -1.66), Vector2(.10, -1.68), Vector2(.57, -.23), Vector2(.60, .27), Vector2(.14, 1.59), Vector2(-.62, 1.67), Vector2(-.38, .24), Vector2(-.39, -.22)], .13, Vector3(-.05, .29, 0), PURPLE)
	_carton(mesh, Vector3(.11, .35, 0), Vector3(2.47, .35, .40), WHITE, -.016)
	_board(mesh, [Vector2(-.34, 0), Vector2(-.39, .65), Vector2(.11, .55), Vector2(.34, 0)], .10, Vector3(-.92, .51, 0), PURPLE)
	_sheet(mesh, [Vector2(-.37, -.63), Vector2(.14, -.62), Vector2(.26, .60), Vector2(-.33, .64)], .09, Vector3(-.92, .47, 0), WHITE)
	for side: float in [-1.0, 1.0]:
		_tube(mesh, Vector3(-.46, .23, side * .53), Vector3.LEFT, .18, 1.14, WHITE, true)
		_box(mesh, Vector3(-.25, .37, side * .54), Vector3(.20, .16, .41), TAPE)
		_mark(mesh, Vector3(-.18, .374, side * 1.11), owner, Vector3.UP, .16)
		mesh.line(Vector3(-.45, .374, side * .83), Vector3(.10, .374, side * .87), .012, INK)
	_panel(mesh, Vector3(.55, .55, 0), .42, .18, Vector3.UP, VIOLET)
	_mark(mesh, Vector3(-.45, .36, .232), owner, Vector3.BACK, .13)
	_equipment_lines(mesh, Vector3(.18, .552, 0), 1.63, .34)

static func _attacker(mesh, owner: Color) -> void:
	_sheet(mesh, [Vector2(-.74, -1.92), Vector2(.42, -1.88), Vector2(.58, -.28), Vector2(.55, .29), Vector2(.44, 1.91), Vector2(-.80, 1.86), Vector2(-.50, .24), Vector2(-.50, -.21)], .16, Vector3(-.05, .39, 0), WHITE)
	_carton(mesh, Vector3(.05, .51, 0), Vector3(2.57, .41, .61), WHITE, .032)
	# A thick underslung weapons box differentiates the attack aircraft.
	_carton(mesh, Vector3(.49, .23, 0), Vector3(1.39, .24, .54), PURPLE, -.016)
	for side: float in [-1.0, 1.0]:
		_tube(mesh, Vector3(-.39, .29, side * .86), Vector3.LEFT, .225, 1.35, PURPLE, true)
		_box(mesh, Vector3(-.26, .41, side * .86), Vector3(.21, .22, .57), TAPE)
		_carton(mesh, Vector3(.48, .27, side * 1.39), Vector3(.78, .18, .22), PEARL, .010, false)
		_mark(mesh, Vector3(-.08, .49, side * 1.50), owner, Vector3.UP, .18)
		mesh.line(Vector3(-.57, .49, side * 1.15), Vector3(.22, .49, side * 1.14), .012, INK)
	_board(mesh, [Vector2(-.42, 0), Vector2(-.40, .55), Vector2(.20, .48), Vector2(.35, 0)], .13, Vector3(-.91, .70, 0), PURPLE)
	_sheet(mesh, [Vector2(-.45, -.74), Vector2(.10, -.73), Vector2(.22, .69), Vector2(-.40, .77)], .10, Vector3(-.90, .66, 0), PEARL)
	_panel(mesh, Vector3(.67, .745, 0), .40, .24, Vector3.UP, VIOLET)
	_mark(mesh, Vector3(-.43, .54, .338), owner, Vector3.BACK, .15)

static func _air_transport(mesh, owner: Color) -> void:
	_carton(mesh, Vector3(.05, .57, 0), Vector3(2.96, .79, .95), WHITE, -.039)
	# Straight thick board wings attach under the square cargo body's centre.
	_sheet(mesh, [Vector2(-.68, -2.08), Vector2(.28, -2.06), Vector2(.32, 2.02), Vector2(-.73, 2.10)], .17, Vector3(-.25, .55, 0), PURPLE)
	for side: float in [-1.0, 1.0]:
		_tube(mesh, Vector3(-.31, .38, side * 1.19), Vector3.LEFT, .235, 1.42, WHITE, true)
		_box(mesh, Vector3(-.27, .55, side * 1.18), Vector3(.23, .18, .61), TAPE)
		_mark(mesh, Vector3(-.20, .657, side * 1.68), owner, Vector3.UP, .19)
		_box(mesh, Vector3(.19, .38, side * .39), Vector3(.14, .39, .12), PEARL)
		mesh.cylinder(Vector3(.19, .16, side * .46), .13, .10, Vector3.BACK, RUBBER, 8, false)
		_beam(mesh, Vector3(-1.13, .70, side * .35), Vector3(-1.95, .80, side * .35), .15, .15, WHITE)
	# A structural tail beam and slab keep it a transport plane, not a spaceship.
	_sheet(mesh, [Vector2(-.27, -.85), Vector2(.21, -.85), Vector2(.20, .81), Vector2(-.26, .85)], .12, Vector3(-1.89, .79, 0), WHITE)
	_board(mesh, [Vector2(-.35, 0), Vector2(-.36, .63), Vector2(.15, .57), Vector2(.31, 0)], .13, Vector3(-1.83, .80, 0), PURPLE)
	_panel(mesh, Vector3(1.56, .72, 0), .63, .28, Vector3.RIGHT, VIOLET)
	_panel(mesh, Vector3(-1.45, .60, 0), .67, .58, Vector3.LEFT, PURPLE)
	_box(mesh, Vector3(-1.492, .56, 0), Vector3(.020, .48, .055), TAPE)
	_mark(mesh, Vector3(-.52, .60, .508), owner, Vector3.BACK, .18)
	_mark(mesh, Vector3(.25, 1.004, 0), owner, Vector3.UP, .19)

static func _recon(mesh, owner: Color) -> void:
	_carton(mesh, Vector3(.03, .27, 0), Vector3(1.85, .25, .24), WHITE, .019)
	# A minimal cross of two thick folding sheets around one observation tube.
	_sheet(mesh, [Vector2(-.36, -1.16), Vector2(.26, -1.11), Vector2(.28, 1.19), Vector2(-.33, 1.14)], .09, Vector3(-.05, .26, 0), WHITE)
	_sheet(mesh, [Vector2(-.23, -.43), Vector2(.20, -.41), Vector2(.20, .42), Vector2(-.22, .44)], .08, Vector3(-.76, .32, 0), PURPLE)
	_board(mesh, [Vector2(-.22, 0), Vector2(-.19, .33), Vector2(.13, .28), Vector2(.20, 0)], .07, Vector3(-.73, .34, 0), WHITE)
	_tube(mesh, Vector3(.47, .44, 0), Vector3.RIGHT, .13, .43, PURPLE, true)
	_box(mesh, Vector3(.45, .35, 0), Vector3(.18, .15, .23), TAPE)
	for side: float in [-1.0, 1.0]:
		_mark(mesh, Vector3(-.05, .324, side * .82), owner, Vector3.UP, .13)
		mesh.line(Vector3(-.28, .318, side * .55), Vector3(.16, .318, side * .58), .010, INK)
	_mark(mesh, Vector3(-.38, .28, .153), owner, Vector3.BACK, .10)
