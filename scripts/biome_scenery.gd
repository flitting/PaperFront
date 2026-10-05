extends RefCounted
class_name BiomeScenery

## Biome colour/scenery are separate from playable topology. Every stand keeps
## broad roads, clear construction pads, ore aprons and harbour approaches.
static func ground_color(map: Dictionary, point: Vector2, terrain: int, noise: float) -> Color:
	var profile: Dictionary = map.profile
	var color := Color(str(profile.road if terrain == 3 else profile.ground))
	var biome: String = str(profile.biome)
	if int(profile.get("design_version", 0)) >= 6 and biome == "city":
		if terrain != 3:
			var random_city: bool = str(profile.get("id", "")) == "random_city"
			var old_center: Vector2 = Vector2(89, 137) if random_city else Vector2(90, 120)
			var modern_center: Vector2 = Vector2(216, 138) if random_city else Vector2(205, 119)
			var park_center: Vector2 = Vector2(129, 220) if random_city else Vector2(190, 184)
			var freight_center: Vector2 = Vector2(248, 196) if random_city else Vector2(247, 213)
			var old: float = pow((point.x - old_center.x) / (50.0 if random_city else 61.0), 2) + pow((point.y - old_center.y) / (52.0 if random_city else 71.0), 2)
			var modern: float = pow((point.x - modern_center.x) / (42.0 if random_city else 54.0), 2) + pow((point.y - modern_center.y) / (50.0 if random_city else 67.0), 2)
			var park: float = pow((point.x - park_center.x) / (42.0 if random_city else 31.0), 2) + pow((point.y - park_center.y) / (31.0 if random_city else 34.0), 2)
			var freight: float = pow((point.x - freight_center.x) / (43.0 if random_city else 39.0), 2) + pow((point.y - freight_center.y) / (48.0 if random_city else 42.0), 2)
			if park < 1.0:
				var park_radius: float = sqrt(park)
				var spoke: float = absf(sin(atan2(point.y - park_center.y, point.x - park_center.x) * 4.0))
				color = Color("b5aa8c") if park_radius < .16 or absf(park_radius - .56) < .055 or absf(park_radius - .91) < .05 or spoke < .065 and park_radius < .92 else Color("71885d").lerp(Color("91a373"), clampf(park, 0, 1) * .28)
			elif old < 1.0: color = Color("a9a18a")
			elif modern < 1.0: color = Color("989d91")
			elif freight < 1.0: color = Color("8e9385")
			else: color = Color("788969").lerp(Color("9a9b78"), clampf(noise + .5, 0, 1) * .22)
			var plaza: Vector2 = Vector2(145, 162) if random_city else Vector2(188, 127)
			if absf(point.x - plaza.x) < 12.0 and absf(point.y - plaza.y) < 14.0:
				color = color.lerp(Color("c0bba6"), .62)
		return color.lightened(noise * .026)
	if terrain != 3:
		if biome == "snow": color = color.lerp(Color("99a6a0"), clampf(-noise, 0, 1) * 0.20)
		elif biome == "desert": color = color.lerp(Color("ac8c59"), (sin(point.x * 0.065 + point.y * 0.024) + 1.0) * 0.065)
		elif biome == "forest": color = color.lerp(Color("65734f"), clampf(noise + 0.5, 0, 1) * 0.16)
		elif biome == "islands":
			var height: float = float(map.heights[clampi(floori(point.y), 0, 319)][clampi(floori(point.x), 0, 319)])
			color = Color("d2bf92") if height < -0.1 else color.lerp(Color("81935f"), clampf(noise + 0.5, 0, 1) * 0.25)
		if int(profile.get("design_version", 0)) >= 6 and biome in ["forest", "desert", "snow"]:
			var elevation: float = float(map.heights[clampi(floori(point.y), 0, 319)][clampi(floori(point.x), 0, 319)])
			var rocky: float = smoothstep(3.5, 11.5, elevation)
			if biome == "forest": color = color.lerp(Color("70786b"), rocky * .93)
			elif biome == "desert": color = color.lerp(Color("986449"), rocky * .94)
			else: color = color.lerp(Color("818f96"), rocky * .68)
	return color.lightened(noise * (0.018 if biome == "snow" else 0.035))

static func apply(map: Dictionary) -> void:
	var biome: String = str(map.profile.biome)
	var players: int = int(map.profile.players)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(map.seed) + 873403
	var stand_count: int = 36 if biome == "forest" else 22 if biome == "snow" else 12 if biome == "islands" else 7 if biome == "desert" else 5
	# A shared sector is rotated for each participant. Resource / traffic
	# exclusions are evaluated against every spawn, retaining equal open lanes.
	for stand: int in stand_count:
		var angle: float = float(stand % 3 - 1) * 0.16 + rng.randf_range(-0.14, 0.14)
		var radius: float = rng.randf_range(38, 142)
		var local := Vector2.from_angle(angle) * radius
		for team: int in players:
			var home_angle: float = (map.layout[team].outward as Vector2).angle()
			var center: Vector2 = Vector2(160, 160) + local.rotated(home_angle)
			for dz: int in range(-5, 6):
				for dx: int in range(-5, 6):
					if dx * dx + dz * dz > 25 or rng.randf() > (0.75 if biome == "forest" else 0.51): continue
					var point: Vector2 = center + Vector2(dx + 0.5, dz + 0.5)
					if not _safe(map, point, 1.8): continue
					var kind: String = "cactus" if biome == "desert" else "snow_pine" if biome == "snow" else "palm" if biome == "islands" else "tree"
					var cell := Vector2i(floori(point.x), floori(point.y))
					point = Vector2(cell) + Vector2.ONE * 0.5
					if kind == "tree": map.decorations.append({"pos": [point.x, point.y], "kind": "tree"})
					else:
						var id: int = map.ruins.size()
						var variant: int = posmod(cell.x * 7 + cell.y * 11, 3)
						map.environment_props.append({"pos": point, "kind": kind, "variant": variant, "yaw": rng.randf_range(0, TAU), "scale": rng.randf_range(0.86, 1.18), "ruin_id": id})
						map.ruins.append({"id": id, "kind": "tree", "environment_kind": kind, "pos": point, "half": Vector2(.48, .48), "cell": cell, "yaw": 0.0, "hp": 180.0, "max_hp": 180.0, "variant": variant})
	# Low ruined landmarks give the non-city biomes a human scale.
	if biome != "city":
		for team: int in players:
			var record: Dictionary = map.layout[team]
			for side: float in [-1.0, 1.0]:
				var point: Vector2 = record.start + record.inward * 34.0 + record.tangent * side * 32.0
				if not _safe(map, point, 4.5): continue
				var id: int = map.ruins.size()
				map.ruins.append({"id": id, "kind": "house", "archetype": "warehouse" if biome == "desert" else "cottage", "height": 2.9, "pos": point, "half": Vector2(2.1, 2.1), "yaw": record.outward.angle(), "hp": 900.0, "max_hp": 900.0, "variant": team % 3})

static func _safe(map: Dictionary, point: Vector2, radius: float) -> bool:
	if point.x < 4 + radius or point.y < 4 + radius or point.x >= 316 - radius or point.y >= 316 - radius: return false
	for start: Array in map.starts:
		if point.distance_to(Vector2(start[0], start[1])) < 26 + radius: return false
	for mine: Dictionary in map.mines:
		if point.distance_to(Vector2(mine.pos[0], mine.pos[1])) < 6 + radius: return false
	for harbor: Dictionary in map.harbors:
		if point.distance_to(harbor.land_pos) < 13 + radius or point.distance_to(harbor.shore_pos) < 13 + radius: return false
	for z: int in range(floori(point.y - radius), ceili(point.y + radius) + 1):
		for x: int in range(floori(point.x - radius), ceili(point.x + radius) + 1):
			if int(map.terrain[z][x]) != 0 or not is_zero_approx(float(map.heights[z][x])): return false
	for ruin: Dictionary in map.ruins:
		if point.distance_to(ruin.pos) < (.95 if ruin.kind == "tree" else 5 + radius): return false
	return true
