extends RefCounted
class_name CityEnvironmentModels

## Paper architecture retains three dimensional window frames, glazing,
## recessed entrances, cornices, rooftop fittings and visible cardboard edges.
const VOLUME = preload("res://scripts/volume_models.gd")
const VERSION = 3
const LANDMARK_ART: Array[String] = ["civic_hall", "church", "clock_tower", "rail_station", "ranger_tower", "sawmill", "forest_camp", "bazaar", "oasis_village", "adobe_house", "adobe_wall", "mesa_gate", "dig_site", "bell_tower", "alpine_cabin", "freight_depot", "snow_ruin", "fishing_hut", "stone_fort", "boat_shed", "shipwreck", "mesa_spire", "moss_spire", "snow_spire"]
const SOURCES: Array[String] = ["res://scripts/city_environment_models.gd", "res://scripts/volume_models.gd", "res://assets/environment/paper_environment.gdshader"]
static var cache: Dictionary = {}
static var _material: ShaderMaterial

static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = preload("res://assets/environment/paper_environment.gdshader")
		_material.set_shader_parameter("paper_grain", preload("res://assets/textures/pigment_noise.png"))
	return _material

static func meshes(archetype: String, height: float, variant: int = 0) -> Dictionary:
	var key: String = "house:%s:%.2f:%d:v%d" % [archetype, height, variant, VERSION]
	if cache.has(key): return cache[key]
	var baked_intact: ArrayMesh = _baked(key)
	var baked_rubble: ArrayMesh = _baked(key + ":rubble")
	if baked_intact != null and baked_rubble != null:
		cache[key] = {"intact": baked_intact, "rubble": baked_rubble}
		return cache[key]
	if archetype in LANDMARK_ART: return _landmark_meshes(key, archetype, height, variant)
	var intact = VOLUME.CraftMesh.new()
	var rubble = VOLUME.CraftMesh.new()
	var wall: Color = [Color("d6c4a0"), Color("bcbdad"), Color("bb9981")][posmod(variant, 3)]
	var frame := Color("eee0b8")
	var roof := Color("797d70")
	var ink := Color("524535")
	if archetype in ["old_townhouse", "old_shop", "rowhouse", "terrace", "church", "clock_tower"]:
		wall = [Color("d7b79c"), Color("e2cab0"), Color("bf9f87")][posmod(variant, 3)]
		roof = [Color("a65c44"), Color("b36c4e"), Color("8e503e")][posmod(variant, 3)]
	elif archetype in ["office_tower", "modern_block", "modern_shop", "civic_hall"]:
		wall = [Color("bfc4bf"), Color("aab4b5"), Color("d1ccbb")][posmod(variant, 3)]
		roof = Color("697478")
	elif archetype in ["rail_station", "freight_shed"]:
		wall = Color("ad9d88")
		roof = Color("646b68")
	intact.box(Vector3(0, 0.09, 0), Vector3(4.18, .18, 4.18), Color("a6a18a"))
	intact.box(Vector3(0, height * .5 + .18, 0), Vector3(3.92, height, 3.92), wall)
	# Foundation reveals and horizontal floor bands remain solid meshes.
	intact.box(Vector3(0, .35, 0), Vector3(4.02, .19, 4.02), wall.darkened(.16))
	var floors: int = maxi(1, roundi(height / 2.45))
	for floor_index: int in floors:
		var level: float = .95 + float(floor_index) * (height / float(floors))
		for side: int in [-1, 1]:
			for column: float in [-1.20, 0.0, 1.20]:
				# Real glazing slab and four extruded frame members on each facade.
				var front := Vector3(column, level + .40, side * 1.983)
				_window(intact, front, Vector3(.72, .94, .05), false, frame, side)
				var flank := Vector3(side * 1.983, level + .40, column)
				_window(intact, flank, Vector3(.05, .94, .72), true, frame, side)
		if floor_index > 0: intact.box(Vector3(0, level - .38, 0), Vector3(4.07, .12, 4.07), frame.darkened(.12))
	# Solid recessed door, trim, knob and two front steps.
	intact.box(Vector3(0, .80, -2.002), Vector3(.74, 1.40, .07), Color("6b756c"))
	for x: float in [-.43, .43]: intact.box(Vector3(x, .82, -2.04), Vector3(.095, 1.55, .12), frame)
	intact.box(Vector3(0, 1.61, -2.04), Vector3(.96, .10, .13), frame)
	intact.cylinder(Vector3(.24, .85, -2.105), .045, .055, Vector3.FORWARD, Color("bdab73"), 8)
	for i: int in 2: intact.box(Vector3(0, .06 + i * .09, -2.13 - (1 - i) * .18), Vector3(1.11, .12, .28), Color("ada995"))
	intact.box(Vector3(0, height + .23, 0), Vector3(4.14, .14, 4.14), frame)
	intact.box(Vector3(0, height + .36, 0), Vector3(3.97, .15, 3.97), roof)
	# Parapets and drainage cap are volumetric, not painted rectangles.
	for side: int in [-1, 1]:
		intact.box(Vector3(side * 1.99, height + .51, 0), Vector3(.12, .35, 4.08), wall)
		intact.box(Vector3(0, height + .51, side * 1.99), Vector3(4.08, .35, .12), wall)
	intact.box(Vector3(.75, height + .65, .52), Vector3(1.07, .50, .76), Color("a0a69b"))
	for grille: int in 5: intact.box(Vector3(.75, height + .78, .13 + grille * .15), Vector3(.94, .025, .037), ink)
	intact.cylinder(Vector3(-1.03, height + .82, .80), .18, .86, Vector3.UP, Color("918a78"), 10)
	intact.cylinder(Vector3(-1.03, height + 1.27, .80), .25, .065, Vector3.UP, frame, 10)
	for side: int in [-1, 1]:
		intact.box(Vector3(side * 1.98, height * .5 + .35, 1.59), Vector3(.07, height + .22, .075), Color("8b8774"))
	if archetype == "shop":
		intact.box(Vector3(0, 2.11, -2.28), Vector3(3.53, .22, .62), Color("749297"))
		for stripe: int in 8: intact.box(Vector3(-1.53 + stripe * .43, 2.23, -2.29), Vector3(.21, .035, .58), frame)
		intact.box(Vector3(0, 2.68, -2.06), Vector3(2.35, .46, .11), Color("94775b"))
		for letter: int in 6: intact.box(Vector3(-.90 + letter * .36, 2.68, -2.135), Vector3(.18, .25, .025), frame)
	elif archetype == "warehouse":
		intact.box(Vector3(1.09, 1.20, -2.02), Vector3(1.19, 1.89, .08), roof)
		for slat: int in 8: intact.box(Vector3(1.09, .38 + slat * .22, -2.085), Vector3(1.15, .028, .032), ink)
	elif archetype == "cottage":
		# A low folded roof and chimney keep cottages distinct at tactical scale.
		intact.prism([Vector2(-2.14, 0), Vector2(0, .90), Vector2(2.14, 0)], 4.24, Vector3(0, height + .58, 0), Color("99775d"))
		intact.box(Vector3(.87, height + 1.11, .81), Vector3(.36, .93, .41), wall.darkened(.12))
	if archetype in ["old_townhouse", "old_shop", "rowhouse", "terrace", "church"]:
		intact.prism([Vector2(-2.22, 0), Vector2(0, 1.10), Vector2(2.22, 0)], 4.38,
			Vector3(0, height + .42, 0), roof)
		for side: float in [-1.0, 1.0]:
			intact.box(Vector3(side * 1.13, height + 1.06, -.65), Vector3(.61, .77, .78), wall.lightened(.07))
			intact.box(Vector3(side * 1.13, height + 1.48, -.65), Vector3(.70, .08, .88), roof)
		intact.box(Vector3(1.48, height + 1.47, 1.10), Vector3(.42, 1.36, .48), wall.darkened(.10))
	if archetype in ["old_shop", "modern_shop"]:
		intact.box(Vector3(0, 2.10, -2.27), Vector3(3.62, .19, .63), Color("a47a56") if archetype == "old_shop" else Color("5b858c"))
		for stripe: int in 8: intact.box(Vector3(-1.55 + stripe * .44, 2.22, -2.28), Vector3(.20, .035, .56), frame)
	if archetype == "office_tower":
		for side: float in [-1.0, 1.0]:
			for column: float in [-1.35, -.45, .45, 1.35]:
				intact.box(Vector3(column, height * .52, side * 2.03), Vector3(.10, height * .96, .18), Color("d9d9cd"))
				intact.box(Vector3(side * 2.03, height * .52, column), Vector3(.18, height * .96, .10), Color("d9d9cd"))
		intact.box(Vector3(0, height + .78, 0), Vector3(2.27, 1.18, 2.35), Color("77868a"))
		intact.box(Vector3(0, height + 1.45, 0), Vector3(2.55, .13, 2.62), frame)
	if archetype == "modern_block":
		for level: int in 3:
			intact.box(Vector3(0, height + .53 + level * .18, -1.1 + level * .25), Vector3(2.7 - level * .35, .07, .76), roof.lightened(level * .06))
	if archetype == "civic_hall":
		intact.box(Vector3(0, 1.15, -2.88), Vector3(3.90, .27, 1.48), Color("b8ae94"))
		for column: float in [-1.42, -.47, .47, 1.42]:
			intact.cylinder(Vector3(column, 2.42, -2.77), .15, 3.85, Vector3.UP, frame, 10)
			intact.box(Vector3(column, 4.38, -2.77), Vector3(.35, .17, .35), frame)
		intact.prism([Vector2(-2.04, 0), Vector2(0, 1.10), Vector2(2.04, 0)], 1.39,
			Vector3(0, 4.65, -2.74), Color("b7ab91"))
		intact.cylinder(Vector3(0, height + 1.24, 0), .93, 1.40, Vector3.UP, Color("7eaaa2"), 14)
		intact.cylinder(Vector3(0, height + 2.06, 0), .55, .18, Vector3.UP, frame, 14)
	if archetype in ["clock_tower", "church"]:
		var tower_height: float = height + (2.5 if archetype == "church" else 0.0)
		intact.box(Vector3(0, tower_height * .65, -.55), Vector3(1.78, tower_height * .72, 1.76), wall.lightened(.05))
		intact.box(Vector3(0, tower_height + .17, -.55), Vector3(2.05, .25, 2.02), frame)
		for facing: float in [-1.0, 1.0]:
			intact.cylinder(Vector3(0, tower_height * .79, -.55 + facing * .94), .51, .08,
				Vector3.FORWARD, Color("eee5ca"), 16)
			intact.line(Vector3(0, tower_height * .79, -.55 + facing * 1.02),
				Vector3(.20, tower_height * .98, -.55 + facing * 1.02), .045, ink)
		intact.prism([Vector2(-1.26, 0), Vector2(0, 1.65), Vector2(1.26, 0)], 2.54,
			Vector3(0, tower_height + .39, -.55), roof)
		if archetype == "church":
			intact.line(Vector3(0, tower_height + 1.6, -.55), Vector3(0, tower_height + 2.9, -.55), .06, frame)
			intact.line(Vector3(-.45, tower_height + 2.43, -.55), Vector3(.45, tower_height + 2.43, -.55), .06, frame)
	if archetype in ["rail_station", "freight_shed"]:
		intact.box(Vector3(0, 3.28, -2.85), Vector3(4.44, .17, 1.65), roof)
		for side: float in [-1.0, 1.0]: intact.box(Vector3(side * 1.74, 1.62, -3.30), Vector3(.16, 3.1, .16), ink)
		for slat: int in 7: intact.box(Vector3(-1.48 + slat * .49, 1.30, -2.04), Vector3(.06, 2.18, .10), ink)
		if archetype == "rail_station":
			intact.cylinder(Vector3(0, 4.48, -2.08), .29, .08, Vector3.FORWARD, frame, 12)
		else:
			for ridge: int in 3: intact.prism([Vector2(-.72, 0), Vector2(0, .40), Vector2(.72, 0)], 4.0,
					Vector3(-1.36 + ridge * 1.36, height + .39, 0), roof)
	for i: int in 12:
		var a: float = float(i) * 2.399 + variant * .23
		var r: float = .40 + float(i % 4) * .41
		rubble.box(Vector3(cos(a) * r, .11 + float(i % 3) * .09, sin(a) * r), Vector3(.47, .21, .38), wall.darkened(float(i % 3) * .06))
	rubble.box(Vector3(0, .04, 0), Vector3(4.10, .08, 4.10), Color("a6a18a"))
	cache[key] = {"intact": _finish(intact, key, {"window_frames": floors * 12, "roof_equipment": 2, "floors": floors}), "rubble": _finish(rubble, key + ":rubble", {})}
	return cache[key]

static func _landmark_meshes(key: String, art: String, height: float, variant: int) -> Dictionary:
	var craft = VOLUME.CraftMesh.new()
	var rubble = VOLUME.CraftMesh.new()
	var timber := Color("927457")
	var dark := Color("554d41")
	var stone := Color("a59479")
	var snow := Color("e4e8df")
	var sand := Color("bd956a")
	craft.box(Vector3(0, .08, 0), Vector3(4.1, .16, 4.1), stone.darkened(.15))
	match art:
		"civic_hall":
			craft.box(Vector3(0, 2.44, 0), Vector3(3.86, 4.72, 3.72), Color("c9c2ae"))
			craft.box(Vector3(0, 4.85, 0), Vector3(4.13, .19, 4.07), Color("e2dbc7"))
			craft.box(Vector3(0, 1.14, -2.33), Vector3(4.06, .21, 1.13), Color("b7af99"))
			for column: float in [-1.46, -.49, .49, 1.46]:
				craft.cylinder(Vector3(column, 2.77, -2.25), .15, 3.45, Vector3.UP, Color("e8dfca"), 10)
				craft.box(Vector3(column, 4.51, -2.25), Vector3(.37, .14, .36), Color("e6dcc6"))
			craft.box(Vector3(0, 4.63, -2.32), Vector3(4.05, .38, 1.24), Color("e3dac5"))
			craft.cylinder(Vector3(0, 5.57, 0), 1.24, 1.37, Vector3.UP, Color("91aaa1"), 18)
			craft.cylinder(Vector3(0, 6.35, 0), .88, .17, Vector3.UP, Color("d6d3be"), 18)
			craft.cylinder(Vector3(0, 6.65, 0), .39, .48, Vector3.UP, Color("8eaaa1"), 14)
			for side: float in [-1.0, 1.0]: craft.box(Vector3(side * 1.94, 2.63, .0), Vector3(.10, 4.77, 3.80), Color("e1d5be"))
		"church":
			craft.box(Vector3(-.33, 2.20, 0), Vector3(3.10, 4.26, 3.77), Color("d5c1a3"))
			craft.prism([Vector2(-1.76, 0), Vector2(0, 1.18), Vector2(1.76, 0)], 4.09, Vector3(-.33, 4.37, 0), Color("a96249"))
			craft.box(Vector3(1.18, 6.88, -.39), Vector3(1.44, 12.45, 1.66), Color("c9b399"))
			for level: int in 3: craft.box(Vector3(1.18, 7.15 + level * 2.48, -1.27), Vector3(.42, 1.16, .11), Color("5e6d70"))
			craft.prism([Vector2(-1.08, 0), Vector2(0, 1.87), Vector2(1.08, 0)], 2.35, Vector3(1.18, 13.16, -.39), Color("975743"))
			craft.line(Vector3(1.18, 14.89, -.39), Vector3(1.18, 16.29, -.39), .07, Color("e5d9bd"))
			craft.line(Vector3(.72, 15.78, -.39), Vector3(1.64, 15.78, -.39), .07, Color("e5d9bd"))
		"clock_tower":
			craft.box(Vector3(0, height * .47, 0), Vector3(2.10, height * .92, 2.10), Color("c8ae94"))
			for tier: int in 5: craft.box(Vector3(0, 2.35 + tier * 2.82, -1.08), Vector3(2.23, .12, .18), Color("e3d1b2"))
			for side: float in [-1.0, 1.0]:
				craft.cylinder(Vector3(0, height * .75, side * 1.12), .58, .10, Vector3.FORWARD, Color("f4edd8"), 16)
				craft.line(Vector3(0, height * .75, side * 1.20), Vector3(.31, height * .88, side * 1.20), .045, dark)
			craft.prism([Vector2(-1.36, 0), Vector2(0, 1.65), Vector2(1.36, 0)], 2.74, Vector3(0, height * .95, 0), Color("9c614d"))
		"rail_station":
			craft.box(Vector3(0, 2.37, 0), Vector3(3.90, 4.57, 3.64), Color("b6aa96"))
			craft.prism([Vector2(-2.24, 0), Vector2(0, 1.16), Vector2(2.24, 0)], 4.17, Vector3(0, 4.68, 0), Color("626d70"))
			craft.box(Vector3(0, 2.49, -2.57), Vector3(4.17, .13, 1.19), Color("747d79"))
			for x: float in [-1.78, 1.78]: craft.box(Vector3(x, 1.38, -2.96), Vector3(.11, 2.44, .11), dark)
			craft.cylinder(Vector3(0, 3.87, -1.91), .40, .10, Vector3.FORWARD, Color("e9dfc6"), 14)
		"ranger_tower":
			for x: float in [-1.35, 1.35]:
				for z: float in [-1.35, 1.35]:
					craft.box(Vector3(x, height * .48, z), Vector3(.18, height * .94, .18), timber)
					craft.line(Vector3(x, .45, z), Vector3(-x, height * .70, z), .08, dark)
			craft.box(Vector3(0, height * .76, 0), Vector3(3.25, .24, 3.25), timber.darkened(.10))
			craft.box(Vector3(0, height * .85, 0), Vector3(2.68, 1.70, 2.68), timber.lightened(.16))
			craft.prism([Vector2(-1.72, 0), Vector2(0, .86), Vector2(1.72, 0)], 3.25, Vector3(0, height * .96, 0), Color("8b5543"))
			for rung: int in 15: craft.box(Vector3(-1.52, .50 + rung * .67, -1.65), Vector3(.52, .065, .12), dark)
		"sawmill":
			craft.box(Vector3(0, 2.20, 0), Vector3(8.9, 4.25, 4.6), timber.lightened(.14))
			craft.prism([Vector2(-4.7, 0), Vector2(0, 1.38), Vector2(4.7, 0)], 5.0, Vector3(0, 4.40, 0), Color("8e5b43"))
			craft.box(Vector3(0, 1.63, -2.37), Vector3(2.25, 2.65, .15), Color("493e35"))
			for plank: int in 8: craft.box(Vector3(-1.18 + plank * .34, 2.05, -2.48), Vector3(.035, 2.45, .04), timber)
			for side: float in [-1.0,1.0]:
				craft.box(Vector3(side * 3.35, 2.54, -2.38), Vector3(1.02, 1.12, .17), Color("456365"))
				craft.box(Vector3(side * 3.35, 2.54, -2.49), Vector3(.09, 1.20, .08), dark)
				craft.box(Vector3(side * 3.35, 2.54, 2.38), Vector3(1.02, 1.12, .17), Color("456365"))
				craft.box(Vector3(side * 3.35, 2.54, 2.49), Vector3(.09, 1.20, .08), dark)
			craft.box(Vector3(0, 1.63, 2.38), Vector3(2.25, 2.65, .15), Color("493e35"))
			for side: float in [-1.0,1.0]:
				for back: float in [-1.25, 1.25]: craft.box(Vector3(side * 4.53, 2.55, back), Vector3(.16, 1.22, .86), Color("456365"))
			craft.cylinder(Vector3(2.4, 1.55, -2.54), .78, .25, Vector3.FORWARD, dark, 14)
			for tooth: int in 3: craft.prism([Vector2(-1.38, 0), Vector2(0, .53), Vector2(1.38, 0)], 4.2, Vector3(-2.87 + tooth * 2.87, 4.83, .2), Color("9f6549"))
		"forest_camp":
			for offset: float in [-1.17, 1.17]:
				craft.prism([Vector2(-.91, 0), Vector2(0, 1.54), Vector2(.91, 0)], 2.20, Vector3(offset, .36, 0), Color("b8a678"))
				craft.line(Vector3(offset, .22, -1.24), Vector3(offset, 2.10, -1.24), .045, dark)
			craft.cylinder(Vector3(0, .11, -1.68), .65, .16, Vector3.UP, Color("6c5b49"), 10)
		"bazaar":
			for x: float in [-1.70, 1.70]:
				craft.box(Vector3(x, 2.30, 0), Vector3(.43, 4.5, 4.0), sand)
			craft.box(Vector3(0, 4.50, 0), Vector3(3.8, .58, 4.0), sand.lightened(.10))
			for side: float in [-1.0, 1.0]:
				craft.box(Vector3(side * 1.1, 1.28, -2.12), Vector3(.80, 2.3, .22), Color("8b6852"))
			craft.prism([Vector2(-2.15, 0), Vector2(0, .65), Vector2(2.15, 0)], 4.20, Vector3(0, 4.88, 0), Color("aa6a4c"))
		"oasis_village":
			craft.box(Vector3(-.62, 2.12, 0), Vector3(2.70, 4.08, 3.38), sand.lightened(.12))
			craft.box(Vector3(1.36, 3.43, .36), Vector3(1.18, 6.65, 1.40), sand)
			craft.cylinder(Vector3(1.36, 7.08, .36), .78, .42, Vector3.UP, Color("c7ad84"), 12)
			craft.prism([Vector2(-1.55, 0), Vector2(0, .37), Vector2(1.55, 0)], 3.60, Vector3(-.62, 4.26, 0), Color("b28a62"))
			craft.box(Vector3(-.79, 1.11, -1.76), Vector3(.73, 2.05, .13), Color("765846"))
			for side: float in [-1.0, 1.0]: craft.box(Vector3(-.79 + side * .47, 1.15, -1.82), Vector3(.10, 2.15, .12), Color("dfc59c"))
			for level: int in 2: craft.box(Vector3(-1.43, 2.19 + level * 1.12, -.92), Vector3(.09, .55, .66), Color("697671"))
			for awning: int in 3: craft.box(Vector3(-1.1 + awning * .72, 2.05, -1.92), Vector3(.67, .06, .68), Color("a8664d"))
			# A low U-shaped courtyard distinguishes the oasis village from sheds.
			for side: float in [-1.0,1.0]:
				craft.box(Vector3(side * 3.5, 1.14, .2), Vector3(.45, 2.2, 7.1), sand.darkened(.08))
				craft.box(Vector3(side * 1.84, 1.14, 3.55), Vector3(3.8, 2.2, .46), sand.darkened(.08))
				craft.box(Vector3(side * 2.3, 2.42, 3.55), Vector3(.85, .33, .67), sand.lightened(.15))
		"adobe_house":
			craft.box(Vector3(0, 1.89, 0), Vector3(3.72, 3.60, 3.58), sand.lightened(.11))
			craft.box(Vector3(0, 3.75, 0), Vector3(3.96, .21, 3.82), Color("d0b28a"))
			craft.box(Vector3(0, 1.15, -1.84), Vector3(.83, 2.20, .13), Color("725c49"))
			for side: float in [-1.0, 1.0]:
				craft.box(Vector3(side * .54, 1.13, -1.91), Vector3(.12, 2.31, .13), Color("e3cda9"))
				craft.box(Vector3(side * 1.27, 2.29, -1.84), Vector3(.43, .56, .12), Color("5f7778"))
				craft.box(Vector3(side * 1.27, 2.62, -1.91), Vector3(.54, .08, .15), Color("e3cda9"))
			craft.box(Vector3(0, 2.71, -2.09), Vector3(3.39, .13, .55), Color("a97556"))
		"adobe_wall":
			craft.box(Vector3(0, 1.15, 0), Vector3(4.02, 2.23, .48), sand)
			for course: int in 4: craft.box(Vector3(0, .38 + course * .51, -.27), Vector3(4.0, .05, .08), Color("946e50"))
			for cap: int in 6: craft.box(Vector3(-1.64 + cap * .66, 2.42, 0), Vector3(.42, .44, .53), Color("c7a17a"))
		"mesa_gate":
			for side: float in [-1.0, 1.0]:
				craft.box(Vector3(side * 1.38, 2.52, 0), Vector3(1.0, 4.95, 3.38), sand.darkened(.12))
				for course: int in 5: craft.box(Vector3(side * 1.38, .74 + course * .88, -1.73), Vector3(1.05, .08, .09), Color("8d674e"))
			craft.box(Vector3(0, 4.89, 0), Vector3(3.80, .58, 3.42), sand)
			for side: float in [-1.0,1.0]:
				craft.box(Vector3(side * 3.8, 1.25, 1.8), Vector3(5.2, 2.45, .72), sand.darkened(.13))
				craft.box(Vector3(side * 3.8, 1.25, -1.8), Vector3(5.2, 2.45, .72), sand.darkened(.13))
			craft.box(Vector3(-6.3, 1.25, 0), Vector3(.72, 2.45, 4.3), sand.darkened(.12))
		"dig_site":
			for side: float in [-1.0, 1.0]:
				craft.box(Vector3(side * 1.68, .38, 0), Vector3(.24, .76, 3.63), sand)
				craft.box(Vector3(0, .38, side * 1.68), Vector3(3.64, .76, .24), sand)
			for course: int in 4: craft.box(Vector3(-1.1 + course * .72, .21 + course * .13, -.95), Vector3(.52, .23, .42), sand.lightened(.10))
		"bell_tower":
			craft.box(Vector3(-2.25, 2.55, 0), Vector3(7.8, 4.9, 5.2), Color("b6afa1"))
			craft.prism([Vector2(-4.25, 0), Vector2(0, 1.88), Vector2(4.25, 0)], 5.7, Vector3(-2.25, 5.0, 0), Color("68707a"))
			craft.box(Vector3(2.35, height * .5, 0), Vector3(2.65, height, 2.65), Color("aaa99d"))
			for side: float in [-1.0, 1.0]:
				craft.box(Vector3(2.35 + side * .56, height * .78, -1.41), Vector3(.47, 1.42, .13), Color("414c52"))
				craft.cylinder(Vector3(2.35, height * .59, side * 1.38), .55, .12, Vector3.FORWARD, Color("ede6d0"), 18)
				craft.line(Vector3(2.35, height * .59, side * 1.47), Vector3(2.57, height * .66, side * 1.47), .05, dark)
				craft.cylinder(Vector3(2.35 + side * 1.38, height * .59, 0), .55, .12, Vector3.RIGHT, Color("ede6d0"), 18)
				craft.line(Vector3(2.35 + side * 1.47, height * .59, 0), Vector3(2.35 + side * 1.47, height * .68, .22), .05, dark)
			craft.box(Vector3(-4.2, 1.45, -2.68), Vector3(1.35, 2.75, .18), Color("49565a"))
			for window_x: float in [-4.0,-2.15,-.3]: craft.box(Vector3(window_x, 2.72, -2.69), Vector3(.72, 1.23, .14), Color("52676b"))
			for window_x: float in [-4.0,-2.15,-.3]: craft.box(Vector3(window_x, 2.72, 2.69), Vector3(.72, 1.23, .14), Color("52676b"))
			craft.prism([Vector2(-1.58, 0), Vector2(0, 2.52), Vector2(1.58, 0)], 3.08, Vector3(2.35, height + .47, 0), Color("68707a"))
			craft.box(Vector3(2.35, height + 1.03, 0), Vector3(3.10, .17, 3.1), snow)
		"alpine_cabin":
			craft.box(Vector3(0, 2.06, 0), Vector3(3.88, 3.96, 3.76), Color("9b806b"))
			craft.prism([Vector2(-2.27, 0), Vector2(0, 1.72), Vector2(2.27, 0)], 4.14, Vector3(0, 4.08, 0), Color("656d70"))
			craft.prism([Vector2(-2.15, 0), Vector2(0, 1.55), Vector2(2.15, 0)], 4.01, Vector3(0, 4.18, 0), snow)
			for rail: int in 5: craft.box(Vector3(-1.55 + rail * .78, 2.18, -2.14), Vector3(.09, 1.15, .09), dark)
		"freight_depot":
			craft.box(Vector3(0, 2.05, 0), Vector3(3.96, 3.96, 3.89), Color("929a94"))
			craft.prism([Vector2(-2.24, 0), Vector2(0, 1.15), Vector2(2.24, 0)], 4.28, Vector3(0, 4.11, 0), Color("626e73"))
			craft.box(Vector3(0, 4.49, 0), Vector3(4.35, .13, 4.18), snow)
			craft.box(Vector3(0, 1.35, -2.04), Vector3(1.85, 2.52, .14), Color("58646a"))
		"snow_ruin":
			for side: float in [-1.0, 1.0]:
				craft.box(Vector3(side * 1.36, 2.04, 0), Vector3(.68, 4.0, 3.53), stone.lightened(.23))
				craft.box(Vector3(side * 1.36, 4.03, 0), Vector3(.88, .25, 3.7), snow)
			craft.box(Vector3(0, 3.60, 0), Vector3(3.55, .51, 3.72), stone)
		"fishing_hut":
			for x: float in [-1.51, 1.51]:
				for z: float in [-1.36, 1.36]: craft.box(Vector3(x, 1.42, z), Vector3(.15, 2.84, .15), timber)
			craft.box(Vector3(0, 1.91, 0), Vector3(3.80, .17, 3.63), timber)
			craft.box(Vector3(0, 3.12, 0), Vector3(3.42, 2.22, 3.34), Color("b7a485"))
			craft.prism([Vector2(-2.05, 0), Vector2(0, 1.13), Vector2(2.05, 0)], 3.90, Vector3(0, 4.35, 0), Color("987451"))
			craft.box(Vector3(0, 2.76, -1.74), Vector3(.82, 1.54, .11), Color("71614d"))
		"stone_fort":
			for side: float in [-1.0, 1.0]:
				if side < 0.0:
					craft.box(Vector3(side * 4.3, 2.6, 0), Vector3(.9, 5.05, 8.95), Color("8e8878"))
				else:
					craft.box(Vector3(side * 4.3, 2.6, -2.95), Vector3(.9, 5.05, 3.05), Color("8e8878"))
					craft.box(Vector3(side * 4.3, 2.6, 2.95), Vector3(.9, 5.05, 3.05), Color("8e8878"))
					craft.box(Vector3(side * 4.3, 1.0, 0), Vector3(.9, 1.9, 2.9), Color("827b6b"))
				if side < 0.0:
					craft.box(Vector3(0, 2.6, side * 4.3), Vector3(8.95, 5.05, .9), Color("9e9988"))
				else:
					craft.box(Vector3(-2.95, 2.6, side * 4.3), Vector3(3.05, 5.05, .9), Color("9e9988"))
					craft.box(Vector3(2.95, 2.6, side * 4.3), Vector3(3.05, 5.05, .9), Color("9e9988"))
					craft.box(Vector3(0, 1.1, side * 4.3), Vector3(2.9, 2.1, .9), Color("827b6b"))
				for corner: float in [-1.0, 1.0]:
					craft.cylinder(Vector3(side * 4.3, 4.2, corner * 4.3), 1.28, 8.15, Vector3.UP, Color("898676"), 10)
					craft.cylinder(Vector3(side * 4.3, 8.32, corner * 4.3), 1.48, .24, Vector3.UP, Color("c0b5a0"), 10)
			craft.box(Vector3(0, 5.7, 0), Vector3(4.4, 11.2, 3.8), Color("8c8574"))
			craft.box(Vector3(0, 11.38, 0), Vector3(4.8, .36, 4.15), Color("b0a793"))
			craft.box(Vector3(0, 1.5, -4.85), Vector3(2.0, 2.65, .15), Color("4a4b43"))
			for breach: int in 3: craft.box(Vector3(1.25 + breach * .73, 4.75 - breach * .7, -4.45), Vector3(.63, .8, .42), Color("665f53"))
		"boat_shed":
			for x: float in [-1.72, 1.72]:
				for z: float in [-1.58, 1.58]: craft.box(Vector3(x, 2.06, z), Vector3(.19, 4.05, .19), timber)
			craft.prism([Vector2(-2.04, 0), Vector2(0, 1.15), Vector2(2.04, 0)], 4.15, Vector3(0, 4.22, 0), Color("80634c"))
			for plank: int in 8: craft.box(Vector3(-1.54 + plank * .44, .22, -1.76), Vector3(.32, .13, 2.83), timber.lightened(.07))
		"shipwreck":
			craft.prism([Vector2(-1.79, 0), Vector2(-1.35, 1.31), Vector2(1.35, 1.31), Vector2(1.79, 0)], 3.6, Vector3(0, .27, 0), Color("765943"))
			for rib: int in 6: craft.box(Vector3(-1.37 + rib * .55, 1.07 + float(rib % 2) * .28, 0), Vector3(.11, 1.55, 3.49), timber)
			craft.line(Vector3(.91, 1.0, 0), Vector3(2.28, 3.3, 0), .14, dark)
		"mesa_spire", "moss_spire", "snow_spire":
			var rock: Color = Color("a37151") if art == "mesa_spire" else Color("777b70") if art == "moss_spire" else Color("8c9799")
			for layer: int in 8:
				var shrink: float = 1.0 - float(layer) * .075
				var bulge: float = sin(float(layer) * 1.7 + float(variant)) * .18
				craft.cylinder(Vector3(bulge, .47 + layer * 1.02, -.14 * float(layer % 3)),
					(2.13 + bulge) * shrink, 1.08, Vector3.UP,
					rock.lightened(float(layer % 3) * .045), 7)
				for seam: int in 3: craft.box(Vector3(-1.28 + seam * 1.16, .84 + layer * 1.02, -1.64 * shrink),
						Vector3(.52, .055, .07), rock.darkened(.20))
			if art == "snow_spire":
				craft.prism([Vector2(-1.33, 0), Vector2(0, 1.40), Vector2(1.33, 0)], 2.52,
					Vector3(0, 8.55, 0), snow)
			elif art == "moss_spire": craft.box(Vector3(-.27, 8.62, .22), Vector3(1.20, .10, 1.06), Color("708b65"))
		_: craft.box(Vector3(0, height * .5, 0), Vector3(3.8, height, 3.8), stone)
	for shard: int in 14:
		var angle: float = float(shard) * 2.399 + float(variant) * .3
		var radius: float = .45 + float(shard % 4) * .36
		rubble.box(Vector3(cos(angle) * radius, .11, sin(angle) * radius), Vector3(.4, .22, .35), stone.darkened(float(shard % 3) * .06))
	cache[key] = {"intact":_finish(craft, key, {"landmark":art}), "rubble":_finish(rubble, key + ":rubble", {})}
	return cache[key]

static func _window(mesh, center: Vector3, size: Vector3, flank: bool, frame: Color, side: int) -> void:
	mesh.box(center, size, Color("77979a"), false)
	var wide: float = size.z if flank else size.x
	var depth: Vector3 = Vector3(side * .04, 0, 0) if flank else Vector3(0, 0, side * .04)
	for edge: float in [-1.0, 1.0]:
		mesh.box(center + depth + (Vector3(0, 0, edge * (wide + .06) * .5) if flank else Vector3(edge * (wide + .06) * .5, 0, 0)), Vector3(.12, size.y + .13, .075) if flank else Vector3(.075, size.y + .13, .12), frame)
		mesh.box(center + depth + Vector3(0, edge * (size.y + .06) * .5, 0), Vector3(.12, .075, wide + .15) if flank else Vector3(wide + .15, .075, .12), frame)
	mesh.box(center + depth, Vector3(.13, size.y, .036) if flank else Vector3(.036, size.y, .13), frame.darkened(.09))
	mesh.box(center + depth, Vector3(.13, .036, wide) if flank else Vector3(wide, .036, .13), frame.darkened(.09))
	mesh.box(center + Vector3(0, -size.y * .5 - .10, 0) + depth, Vector3(.22, .075, wide + .24) if flank else Vector3(wide + .24, .075, .22), frame)

static func prop_mesh(kind: String, variant: int = 0) -> ArrayMesh:
	var key: String = "prop:%s:%d:v%d" % [kind, variant, VERSION]
	if cache.has(key): return cache[key]
	var baked: ArrayMesh = _baked(key)
	if baked != null:
		cache[key] = baked
		return baked
	var craft = VOLUME.CraftMesh.new()
	var ink := Color("505248")
	var paper := Color("d9ceb3")
	if kind == "streetlamp":
		craft.box(Vector3(0, .13, 0), Vector3(.38, .26, .38), Color("918d7d"))
		craft.cylinder(Vector3(0, 1.82, 0), .065, 3.40, Vector3.UP, ink, 8)
		craft.line(Vector3(0, 3.46, 0), Vector3(.63, 3.65, 0), .06, ink)
		craft.box(Vector3(.66, 3.60, 0), Vector3(.53, .13, .31), paper)
		craft.box(Vector3(.66, 3.52, 0), Vector3(.37, .035, .23), Color("efdaa2"), false)
	elif kind == "bench":
		for x: float in [-.54, .54]:
			craft.box(Vector3(x, .26, 0), Vector3(.075, .52, .57), ink)
			craft.box(Vector3(x, .60, .24), Vector3(.075, .69, .075), ink)
		for slat: int in 4: craft.box(Vector3(0, .50, -.22 + slat * .14), Vector3(1.32, .055, .10), Color("a99068"))
		for slat: int in 3: craft.box(Vector3(0, .70 + slat * .12, .27), Vector3(1.32, .075, .055), Color("a99068"))
	elif kind == "pedestrian":
		var cloth: Color = [Color("a07063"), Color("638388"), Color("9b9772")][posmod(variant, 3)]
		craft.box(Vector3(0, .78, 0), Vector3(.32, .57, .22), cloth)
		craft.cylinder(Vector3(0, 1.17, 0), .105, .25, Vector3.UP, Color("c8ab88"), 10)
		craft.box(Vector3(0, 1.31, 0), Vector3(.24, .065, .25), ink)
		for side: float in [-1, 1]:
			craft.line(Vector3(side * .085, .51, 0), Vector3(side * .12, .12, side * .045), .068, ink)
			craft.box(Vector3(side * .12, .045, -.055), Vector3(.14, .09, .23), ink)
			craft.line(Vector3(side * .23, 1.0, 0), Vector3(side * .23, .59, side * .055), .055, cloth)
	elif kind == "cactus":
		craft.cylinder(Vector3(0, 1.0, 0), .18, 2.0, Vector3.UP, Color("788859"), 8)
		for side: float in [-1, 1]:
			craft.line(Vector3(0, .84 + side * .18, 0), Vector3(side * .57, .84 + side * .18, 0), .115, Color("718254"))
			craft.cylinder(Vector3(side * .55, 1.14 + side * .18, 0), .115, .65, Vector3.UP, Color("788859"), 8)
	elif kind == "snow_pine":
		craft.cylinder(Vector3(0, .8, 0), .10, 1.60, Vector3.UP, Color("8b785e"), 8)
		for level: int in 3:
			var low: float = .65 + level * .67
			var radius: float = .92 - level * .20
			_cone(craft, low, 1.15, radius, Color("45675d"))
			_cone(craft, low + .28, .72, radius * .54, Color("e4e8e1"))
	elif kind == "palm":
		craft.line(Vector3.ZERO, Vector3(.13, 2.9, .08), .13, Color("a58c64"))
		for fruit: int in 3:
			craft.cylinder(Vector3(.13 + cos(fruit * 2.1) * .20, 2.71, .08 + sin(fruit * 2.1) * .20), .11, .19, Vector3.UP, Color("8d7858"), 8, false)
		for leaf: int in 7:
			var angle: float = leaf * TAU / 7
			var end := Vector3(cos(angle) * 1.40, 2.32, sin(angle) * 1.40)
			var tip := Vector3(cos(angle) * .73, 3.13, sin(angle) * .73)
			var side := Vector3(-sin(angle), 0, cos(angle)) * .17
			craft.face([Vector3(.13, 2.85, .08), tip + side, end, tip - side], Color("6d915e"), Vector3.UP)
			craft.face([Vector3(.13, 2.85, .08), tip - side, end, tip + side], Color("577c50"), Vector3.DOWN)
	elif kind == "sidewalk":
		craft.box(Vector3(0, .055, 0), Vector3(.48, .11, 14.8), Color("c8c4b1"), false)
		for seam: int in 10: craft.box(Vector3(0, .112, -6.7 + seam * 1.48), Vector3(.46, .004, .024), Color("92958b"), false)
	elif kind == "fountain":
		craft.cylinder(Vector3(0, .14, 0), 3.45, .28, Vector3.UP, Color("c6c0aa"), 24)
		craft.cylinder(Vector3(0, .31, 0), 2.88, .075, Vector3.UP, Color("6fabb2"), 24, false)
		craft.cylinder(Vector3(0, .37, 0), 2.95, .13, Vector3.UP, Color("e3ddc8"), 24)
		craft.cylinder(Vector3(0, .68, 0), .43, .75, Vector3.UP, Color("c7c4af"), 12)
		craft.cylinder(Vector3(0, 1.08, 0), 1.18, .14, Vector3.UP, Color("dcd5bf"), 18)
		craft.cylinder(Vector3(0, 1.15, 0), .92, .035, Vector3.UP, Color("6dabb5"), 18, false)
		craft.cylinder(Vector3(0, 1.66, 0), .13, 1.13, Vector3.UP, Color("dad6c3"), 10)
		for jet: int in 8:
			var angle: float = float(jet) * TAU / 8.0
			craft.line(Vector3(0, 2.25, 0), Vector3(cos(angle) * 1.38, .52, sin(angle) * 1.38), .026, Color("b5e1df"))
	elif kind == "lighthouse":
		craft.cylinder(Vector3(0, .24, 0), 1.54, .48, Vector3.UP, Color("867e68"), 18)
		craft.cylinder(Vector3(0, 5.15, 0), .62, 9.4, Vector3.UP, Color("e5dfcf"), 18)
		for band: int in [1, 3, 5, 7]: craft.cylinder(Vector3(0, float(band) + .74, 0), .65, .72, Vector3.UP, Color("b05f52"), 18)
		craft.cylinder(Vector3(0, 10.0, 0), .95, .36, Vector3.UP, Color("8e8170"), 18)
		craft.cylinder(Vector3(0, 10.64, 0), .72, 1.02, Vector3.UP, Color("b8d3ce"), 12, false)
		for pillar: int in 8:
			var a: float = float(pillar) * TAU / 8.0
			craft.box(Vector3(cos(a) * .67, 10.65, sin(a) * .67), Vector3(.10, 1.06, .10), ink)
		craft.cylinder(Vector3(0, 11.28, 0), .86, .22, Vector3.UP, Color("b05f52"), 16)
		_cone(craft, 11.39, .82, .86, Color("7e6154"))
	elif kind == "harbor_crane":
		for side: float in [-1.0, 1.0]:
			craft.box(Vector3(side * .84, 3.25, 0), Vector3(.21, 6.50, .24), Color("8e6e55"))
			craft.line(Vector3(side * .84, 1.0, 0), Vector3(-side * .84, 5.8, 0), .10, ink)
		craft.box(Vector3(0, 6.32, 0), Vector3(2.05, .23, 2.0), Color("a68962"))
		craft.line(Vector3(-4.2, 7.2, 0), Vector3(3.0, 8.2, 0), .16, Color("a77d58"))
		craft.line(Vector3(0, 6.37, 0), Vector3(3.0, 8.2, 0), .10, ink)
		craft.line(Vector3(-3.75, 7.24, 0), Vector3(-3.75, 3.22, 0), .044, ink)
		craft.box(Vector3(-3.75, 3.02, 0), Vector3(.34, .31, .32), Color("8a795f"))
	elif kind == "cargo_stack":
		for layer: int in 2:
			var box_color: Color = [Color("aa7156"), Color("70868a"), Color("9e8b67")][posmod(variant + layer, 3)]
			craft.box(Vector3(0, .64 + layer * 1.25, 0), Vector3(4.2, 1.22, 1.65), box_color)
			for rib: int in 11: craft.box(Vector3(-1.94 + rib * .39, .68 + layer * 1.25, -.86), Vector3(.035, 1.03, .07), box_color.darkened(.22))
			craft.box(Vector3(0, .64 + layer * 1.25, -.89), Vector3(4.0, .05, .05), Color("d6c9af"))
	elif kind == "rail_track":
		craft.box(Vector3(0, .045, 0), Vector3(1.76, .09, .14), Color("88745d"), false)
		for side: float in [-1.0, 1.0]: craft.box(Vector3(0, .13, side * .41), Vector3(1.80, .10, .09), Color("666c69"), false)
	elif kind == "log_stack":
		for row: int in 3:
			for column: int in (3 - row):
				var center: Vector3 = Vector3(-.62 + column * .62 + float(row) * .31, .28 + row * .48, 0)
				craft.cylinder(center, .26, 3.20, Vector3.FORWARD, Color("8a694a"), 10)
				craft.cylinder(center + Vector3(0, 0, -1.64), .23, .035, Vector3.FORWARD, Color("d0ad76"), 10)
		for band: float in [-.94, .94]: craft.box(Vector3(0, .75, band), Vector3(2.6, .09, .11), Color("5c5542"))
	elif kind == "market_tent":
		for x: float in [-1.34, 1.34]:
			for z: float in [-1.10, 1.10]: craft.box(Vector3(x, 1.15, z), Vector3(.09, 2.30, .09), Color("7e6145"))
		craft.prism([Vector2(-1.58, 0), Vector2(0, .88), Vector2(1.58, 0)], 2.64,
			Vector3(0, 2.27, 0), [Color("b76e50"), Color("bca47b"), Color("798d8a")][posmod(variant, 3)])
		for stripe: int in 5: craft.box(Vector3(-1.15 + stripe * .56, 2.14, -1.30), Vector3(.18, .06, .25), Color("ead9b1"))
	elif kind == "fuel_tank":
		craft.cylinder(Vector3(0, 1.75, 0), 1.05, 3.42, Vector3.UP, Color("9aa6a4"), 14)
		craft.cylinder(Vector3(0, 3.51, 0), 1.09, .17, Vector3.UP, Color("d6ddd8"), 14)
		for side: float in [-1.0, 1.0]: craft.box(Vector3(side * 1.06, 1.63, 0), Vector3(.08, 2.75, .09), Color("687674"))
		craft.line(Vector3(0, 3.61, 0), Vector3(.42, 4.07, 0), .06, Color("6f7875"))
	elif kind == "birch":
		craft.cylinder(Vector3(0, 1.45, 0), .11, 2.90, Vector3.UP, Color("e2e0d3"), 9)
		for band: int in 6: craft.box(Vector3(.10, .36 + band * .43, 0), Vector3(.045, .07, .23), Color("535e59"))
		for branch: int in 5:
			var angle: float = float(branch) * TAU / 5.0
			craft.line(Vector3(0, 1.85, 0), Vector3(cos(angle) * .74, 2.65, sin(angle) * .74), .055, Color("939589"))
			craft.cylinder(Vector3(cos(angle) * .74, 2.65, sin(angle) * .74), .46, .53, Vector3.UP, Color("dfe5dd"), 8)
	elif kind in ["moss_boulder", "sandstone", "snow_boulder"]:
		var rock: Color = Color("8b8978") if kind == "moss_boulder" else Color("a67959") if kind == "sandstone" else Color("aaaeb0")
		for layer: int in 4:
			var shrink: float = 1.0 - float(layer) * .17
			craft.box(Vector3(.11 * layer, .28 + layer * .47, -.08 * layer), Vector3(2.50 * shrink, .47, 2.03 * shrink), rock.lightened(float(layer % 2) * .08))
		if kind == "snow_boulder": craft.box(Vector3(.24, 2.09, -.12), Vector3(1.10, .12, 1.05), Color("e7e9e2"))
		elif kind == "moss_boulder": craft.box(Vector3(-.24, 1.92, .19), Vector3(.82, .10, .69), Color("718d60"))
	elif kind == "ice_floe":
		craft.cylinder(Vector3(0, .05, 0), 1.28 + float(variant) * .17, .10, Vector3.UP, Color("c8e2e9"), 7, false)
		craft.cylinder(Vector3(.08, .11, -.06), 1.03, .065, Vector3.UP, Color("e0f0ee"), 7, false)
	elif kind == "pier":
		for plank: int in 11: craft.box(Vector3(0, .11, -2.25 + plank * .45), Vector3(3.5, .13, .38), Color("9b7958"))
		for x: float in [-1.51, 1.51]:
			for z: float in [-2.30, 0, 2.30]: craft.box(Vector3(x, -.57, z), Vector3(.16, 1.4, .16), Color("675341"))
	elif kind == "coastal_rock":
		for layer: int in 4:
			var shrink: float = 1.0 - float(layer) * .18
			craft.box(Vector3(.14 * layer, .24 + layer * .53, -.12 * layer), Vector3(2.1 * shrink, .54, 1.7 * shrink), Color("777971").lightened(float(layer % 2) * .11))
		craft.box(Vector3(-.33, 1.91, .14), Vector3(.68, .12, .46), Color("869472"))
	elif kind == "sea_rock":
		for layer: int in 3: craft.box(Vector3(.07 * layer, .10 + layer * .38, -.04 * layer), Vector3(1.15 - layer * .18, .44, 1.08 - layer * .17), Color("777971"))
	elif kind == "buoy":
		craft.cylinder(Vector3(0, .15, 0), .34, .31, Vector3.UP, Color("a9463d"), 12)
		craft.cylinder(Vector3(0, .36, 0), .25, .13, Vector3.UP, Color("eee4cf"), 12)
		craft.line(Vector3(0, .42, 0), Vector3(0, 1.45, 0), .055, Color("67675e"))
		craft.cylinder(Vector3(0, 1.48, 0), .15, .21, Vector3.UP, Color("ddc18a"), 10)
	elif kind == "boat":
		craft.prism([Vector2(-.67, 0), Vector2(-.50, .54), Vector2(.50, .54), Vector2(.67, 0)], 2.5,
			Vector3(0, .18, 0), Color("796752"))
		craft.box(Vector3(0, .64, 0), Vector3(.9, .08, 1.73), Color("bdad87"))
		craft.line(Vector3(0, .55, 0), Vector3(0, 2.17, 0), .06, Color("e6e2cf"))
		craft.face([Vector3(0, 1.92, 0), Vector3(0, .75, 0), Vector3(.81, .76, 0)], Color("e9e3d2"), Vector3.FORWARD)
	elif kind == "quay_wall":
		craft.box(Vector3(0, .43, 0), Vector3(3.15, .86, .47), Color("9c9989"))
		craft.box(Vector3(0, .91, 0), Vector3(3.18, .12, .55), Color("d3cab0"))
		for joint: int in 5: craft.box(Vector3(-1.29 + joint * .64, .41, -.26), Vector3(.035, .72, .025), Color("726c61"))
	elif kind == "waterfall":
		craft.box(Vector3(0, 11.2, -1.0), Vector3(5.45, .24, 2.8), Color("81bfc7"), false)
		craft.box(Vector3(0, 11.25, .38), Vector3(5.7, .25, .38), Color("e8f2ec"), false)
		for sheet: int in 11:
			var x: float = -2.52 + float(sheet) * .50
			craft.box(Vector3(x + .23, 5.58, .57), Vector3(.48, 10.96, .18),
				Color("87c5d2") if sheet % 3 else Color("d5edf0"), false)
		for foam: int in 7:
			craft.box(Vector3(-2.4 + foam * .8, .11, 1.0 + float(foam % 2) * .32),
				Vector3(.78, .12, 1.6), Color("f1f5eb"), false)
	else: craft.box(Vector3(0, .4, 0), Vector3(.13, .8, .13), ink)
	cache[key] = _finish(craft, key, {})
	return cache[key]

static func _cone(craft, low: float, height: float, radius: float, color: Color) -> void:
	for i: int in 9:
		var angle: float = i * TAU / 9
		var next: float = (i + 1) * TAU / 9
		var a := Vector3(cos(angle) * radius, low, sin(angle) * radius)
		var b := Vector3(cos(next) * radius, low, sin(next) * radius)
		craft.triangle(a, Vector3(0, low + height, 0), b, color, Vector3(cos(angle), .5, sin(angle)).normalized())

static func _finish(craft, key: String, details: Dictionary) -> ArrayMesh:
	var mesh: ArrayMesh = craft.mesh()
	mesh.surface_set_material(0, material())
	mesh.set_meta("environment_version", VERSION)
	mesh.set_meta("environment_key", key)
	mesh.set_meta("environment_details", details)
	var hashes: Dictionary = {}
	for source: String in SOURCES: hashes[source] = FileAccess.get_sha256(source)
	mesh.set_meta("environment_source_hashes", hashes)
	return mesh


static func resource_path(key: String) -> String:
	return "res://assets/environment/" + key.sha256_text() + ".res"


static func _baked(key: String) -> ArrayMesh:
	var path: String = resource_path(key)
	if not FileAccess.file_exists(path): return null
	var mesh: ArrayMesh = ResourceLoader.load(path, "ArrayMesh")
	if mesh == null or mesh.get_meta("environment_version", 0) != VERSION: return null
	var hashes: Dictionary = mesh.get_meta("environment_source_hashes", {})
	for source: String in SOURCES:
		if FileAccess.file_exists(source) and str(hashes.get(source, "")) != FileAccess.get_sha256(source): return null
	return mesh
