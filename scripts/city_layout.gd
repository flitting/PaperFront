extends RefCounted
class_name CityLayout
const BIOME = preload("res://scripts/biome_scenery.gd")

static func apply(map: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(map.seed) + 202603
	var randomized: bool = map.mode == "random_city"
	var spacing: int = 22 if not randomized else rng.randi_range(21, 25)
	var origin: int = 16 if not randomized else rng.randi_range(12, 20)
	map.profile.street_spacing = spacing
	map.profile.street_origin = origin
	for z: int in int(map.size):
		for x: int in int(map.size):
			if int(map.terrain[z][x]) == 0 and is_zero_approx(float(map.heights[z][x])) and (posmod(x - origin, spacing) < 5 or posmod(z - origin, spacing) < 5): map.terrain[z][x] = 3
	var block: int = 0
	for z: int in range(origin + 9, 306, spacing):
		for x: int in range(origin + 9, 306, spacing):
			block += 1
			var point := Vector2(x + 0.5, z + 0.5)
			if not BIOME._safe(map, point, 3.0): continue
			var archetype: String = ["cottage", "townhouse", "shop", "warehouse"][rng.randi_range(0, 3)] if randomized else ["cottage", "townhouse", "shop", "warehouse"][posmod(block, 4)]
			var height: float = 2.9 if archetype == "cottage" else 5.1 if archetype == "townhouse" else 5.9 if archetype == "shop" else 3.7
			for offset: Vector2 in [Vector2.ZERO, Vector2(7.2, 0), Vector2(0, 7.2)]:
				var house: Vector2 = point + offset
				if not BIOME._safe(map, house, 2.1): continue
				var id: int = map.ruins.size()
				map.ruins.append({"id": id, "group": block, "kind": "house", "archetype": archetype, "height": height, "pos": house, "half": Vector2(2.1, 2.1), "yaw": 0.0 if offset.y == 0 else PI * 0.5, "hp": 1400.0, "max_hp": 1400.0, "variant": posmod(block, 3)})
			var lamp: Vector2 = Vector2(x - 4.2, z - 5.6)
			map.environment_props.append({"pos": lamp, "kind": "streetlamp", "variant": block % 3, "yaw": 0.0, "scale": 1.0})
			map.environment_props.append({"pos": lamp + Vector2(0, 3.5), "kind": "bench", "variant": block % 3, "yaw": PI * 0.5, "scale": 1.0})
			for offset: Vector2 in [Vector2(-4.2, 2.5), Vector2(10.6, 2.5), Vector2(3.2, -5.7), Vector2(3.2, 10.6)]:
				map.environment_props.append({"pos": point + offset, "kind": "sidewalk", "variant": 0, "yaw": 0.0 if offset.x in [-4.2, 10.6] else PI * 0.5, "scale": 1.0})
			# Visual people travel a pavement rectangle. No neutral footprint is
			# registered, so they never enter unit clearance / attack targets.
			if block % 3 == 0:
				var route: Array[Vector2] = [Vector2(x - 4.2, z - 5.7), Vector2(x + 10.6, z - 5.7), Vector2(x + 10.6, z + 10.6), Vector2(x - 4.2, z + 10.6)]
				map.civilians.append({"id": map.civilians.size(), "route": route, "speed": 0.56 + rng.randf() * 0.24, "phase": rng.randf_range(0, 50), "variant": map.civilians.size() % 3})


static func civilian_sample(person: Dictionary, time: float) -> Dictionary:
	var route: Array = person.route
	var length: float = 0.0
	for index: int in route.size(): length += (route[index] as Vector2).distance_to(route[(index + 1) % route.size()])
	var distance: float = fposmod(time * float(person.speed) + float(person.phase), length)
	for index: int in route.size():
		var from: Vector2 = route[index]
		var to: Vector2 = route[(index + 1) % route.size()]
		var segment: float = from.distance_to(to)
		if distance <= segment: return {"pos": from.lerp(to, distance / segment), "direction": (to - from).normalized()}
		distance -= segment
	return {"pos": route[0], "direction": Vector2.RIGHT}
