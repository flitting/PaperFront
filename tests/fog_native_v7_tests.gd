extends SceneTree

const SIM = preload("res://scripts/simulation.gd")
const MAP = preload("res://scripts/map_data.gd")
const WORLD = preload("res://scripts/paper_world.gd")
var checks: int = 0
var failures: Array[String] = []
var rows: Array = []
var kernels: RefCounted

# The pre-optimization SightMemory loop, retained as an independent reference.
class ReferenceMemory:
	extends RefCounted
	var map_size: int
	var width: int
	var pixels := PackedByteArray()
	var bucket_signatures: Dictionary = {}
	var changed_buckets: Dictionary = {}
	var queries: int = 0
	func initialize(size: int) -> void:
		map_size = size
		width = ceili(float(size) / 2)
		pixels.resize(width * width * 2)
		pixels.fill(0)
	func refresh(simulation) -> bool:
		queries = 0
		var next: Dictionary = {}
		for bucket: Vector2i in simulation._vision_observers[0]:
			var signature: Array = []
			for observer: Dictionary in simulation._vision_observers[0][bucket]:
				signature.append_array([observer.pos, observer.radius_sq, observer.air, observer.eye_height])
			next[bucket] = signature
		changed_buckets = {}
		for bucket: Vector2i in next:
			if not bucket_signatures.has(bucket) or bucket_signatures[bucket] != next[bucket]: changed_buckets[bucket] = true
		for bucket: Vector2i in bucket_signatures:
			if not next.has(bucket): changed_buckets[bucket] = true
		bucket_signatures = next
		var changed: bool = false
		for bucket: Vector2i in changed_buckets:
			for z: int in range(maxi(0, bucket.y * 8), mini(width, (bucket.y + 1) * 8)):
				for x: int in range(maxi(0, bucket.x * 8), mini(width, (bucket.x + 1) * 8)):
					var offset: int = (z * width + x) * 2
					var visible: bool = false
					if next.has(bucket):
						var point := Vector2(minf((x + .5) * 2, map_size - .001), minf((z + .5) * 2, map_size - .001))
						var domain: String = "naval" if MAP.terrain_at(simulation.map, point) == MAP.WATER else "ground"
						visible = simulation.position_visible_to(0, point, domain)
						queries += 1
					var value: int = 255 if visible else 0
					if pixels[offset] != value:
						pixels[offset] = value
						changed = true
					if visible and pixels[offset + 1] == 0:
						pixels[offset + 1] = 255
						changed = true
		return changed

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok and failures.size() < 20: failures.append(label)

func fixture(map: Dictionary) -> RefCounted:
	var sim = SIM.new()
	sim.factions.assign(["rivet", "kestrel"])
	sim.vision_enabled = true
	sim.rules = {"units": {"ground": {"domain": "ground", "vision_radius": 16}, "air": {"domain": "air", "vision_radius": 19}, "naval": {"domain": "naval", "vision_radius": 14}}, "buildings": {"tower": {"domain": "ground", "vision_radius": 20}}}
	sim.map = map
	return sim

func entity(sim, id: int, spec: String, pos: Vector2, team: int = 0) -> void:
	sim.entities[id] = {"id": id, "team": team, "hp": 100.0, "kind": "building" if spec == "tower" else "unit", "spec": spec, "pos": pos}

func compare(sim, reference: ReferenceMemory, pixels: PackedByteArray, label: String) -> PackedByteArray:
	var before: int = Time.get_ticks_usec()
	var changed: bool = reference.refresh(sim)
	var script_us: int = Time.get_ticks_usec() - before
	before = Time.get_ticks_usec()
	var result: Dictionary = kernels.refresh_sight_mask(sim.map, sim._vision_observers[0], reference.changed_buckets, pixels)
	var native_us: int = Time.get_ticks_usec() - before
	var actual: PackedByteArray = result.pixels
	check(actual == reference.pixels, label + ": current and explored bytes equal reference")
	if actual != reference.pixels:
		for index: int in actual.size():
			if actual[index] != reference.pixels[index]:
				failures.append("%s first byte %d (%s) native=%d script=%d" % [label, index, "current" if index % 2 == 0 else "explored", actual[index], reference.pixels[index]])
				break
	check(bool(result.changed) == changed, label + ": changed flag matches")
	check(int(result.queries) == reference.queries, label + ": exact query count matches")
	checks += actual.size()
	rows.append({"label": label, "queries": reference.queries, "script_us": script_us, "native_us": native_us, "changed": changed})
	return actual

func flat_map(size: int) -> Dictionary:
	var map: Dictionary = {"size": size, "terrain": [], "heights": []}
	for z: int in size:
		var heights: Array = []
		var terrain: Array = []
		for x: int in size:
			heights.append(0.0)
			terrain.append(0)
		map.heights.append(heights)
		map.terrain.append(terrain)
	return map

func _initialize() -> void:
	if not ClassDB.class_exists("PaperFrontKernels"):
		push_error("Native fog kernel unavailable")
		quit(1)
		return
	kernels = ClassDB.instantiate("PaperFrontKernels")
	if not kernels.has_method("refresh_sight_mask"):
		push_error("Native fog method unavailable")
		quit(1)
		return
	call_deferred("run")

func run() -> void:
	var map: Dictionary = flat_map(33)
	for z: int in 33:
		map.heights[z][14] = 5.0
		for x: int in range(22, 33): map.terrain[z][x] = MAP.WATER
		map.terrain[z][5] = MAP.RAMP
		map.heights[z][5] = float(z % 7) * .25
	var sim = fixture(map)
	entity(sim, 1, "ground", Vector2(9, 9))
	sim.TeamVision.initialize(sim)
	var reference := ReferenceMemory.new()
	reference.initialize(33)
	var pixels := PackedByteArray()
	pixels.resize(reference.pixels.size())
	pixels.fill(0)
	pixels = compare(sim, reference, pixels, "cliff-ground-odd-edge")
	check(pixels[(4 * reference.width + 9) * 2] == 0, "ground sight is blocked behind the five-metre cliff")
	pixels = compare(sim, reference, pixels, "stationary-zero-queries")
	check(reference.queries == 0, "stationary observers perform no LOS queries")
	entity(sim, 2, "air", Vector2(9, 9))
	entity(sim, 3, "naval", Vector2(27, 17))
	entity(sim, 4, "tower", Vector2(5, 17.25))
	entity(sim, 5, "ground", Vector2(-.1, 32.999))
	entity(sim, 6, "ground", Vector2(32.999, -.1))
	entity(sim, 7, "ground", Vector2(1, 1), 1)
	entity(sim, 8, "ground", Vector2(17, 17))
	sim.entities[8].transport_id = 999
	sim.TeamVision.refresh(sim, true)
	pixels = compare(sim, reference, pixels, "air-naval-ramp-loaded-other-team-boundaries")
	check(pixels[(4 * reference.width + 9) * 2] == 255, "air observer retains its authoritative cliff bypass")
	sim.entities.erase(2)
	sim.entities.erase(3)
	sim.entities[1].pos = Vector2(28.5, 28.5)
	sim.entities[4].hp = 0.0
	sim.TeamVision.refresh(sim, true)
	pixels = compare(sim, reference, pixels, "multiple-observer-remove-shift-death")
	# Reuse the same native sampler and map reference after direct live grid edits.
	map.heights[28][25] = 9.0
	map.terrain[28][25] = MAP.LAND
	reference.bucket_signatures.clear()
	pixels = compare(sim, reference, pixels, "live-terrain-edit-cache-refresh")
	sim.entities.clear()
	sim.TeamVision.refresh(sim, true)
	pixels = compare(sim, reference, pixels, "all-observers-removed-exploration-retained")
	for offset: int in range(0, pixels.size(), 2): check(pixels[offset] == 0, "no stale current sight remains")
	var rng := RandomNumberGenerator.new()
	rng.seed = 73027
	for mode: String in ["forest", "desert", "snow", "city", "random_city", "islands"]:
		var actual_map: Dictionary = MAP.generate(mode, 7, {"players": 4})
		check(bool(actual_map.valid), mode + ": real map validates")
		sim = fixture(actual_map)
		for id: int in 48:
			var spec: String = ["ground", "ground", "naval", "air", "tower"][id % 5]
			entity(sim, id + 1, spec, Vector2(rng.randf_range(-.1, 320.1), rng.randf_range(-.1, 320.1)))
		sim.TeamVision.initialize(sim)
		reference = ReferenceMemory.new()
		reference.initialize(int(actual_map.size))
		pixels = reference.pixels.duplicate()
		pixels = compare(sim, reference, pixels, mode + "/initial")
		for id: int in sim.entities:
			sim.entities[id].pos += Vector2(4.75, -3.25)
			if id % 6 == 0: sim.entities[id].hp = 0.0
			if id % 7 == 0: sim.entities[id].transport_id = 999
		sim.TeamVision.refresh(sim, true)
		pixels = compare(sim, reference, pixels, mode + "/move-remove-load")
		sim.entities.clear()
		sim.TeamVision.refresh(sim, true)
		pixels = compare(sim, reference, pixels, mode + "/remove-all")
	# Public SightMemory dispatch must select the same bytes as its forced fallback.
	sim = fixture(flat_map(64))
	entity(sim, 1, "ground", Vector2(9, 9))
	sim.TeamVision.initialize(sim)
	var native_memory = WORLD.SightMemory.new()
	var script_memory = WORLD.SightMemory.new()
	native_memory.initialize(64)
	script_memory.initialize(64)
	for stage: int in 3:
		sim.native_kernels_enabled = true
		var native_changed: bool = native_memory.refresh(sim)
		sim.native_kernels_enabled = false
		var script_changed: bool = script_memory.refresh(sim)
		check(native_memory.pixels == script_memory.pixels and native_changed == script_changed and native_memory.queries == script_memory.queries, "public SightMemory native/fallback equivalence stage %d" % stage)
		sim.entities[1].pos += Vector2(16, 16)
		sim.TeamVision.refresh(sim, true)
	var report: Dictionary = {"checks": checks, "failures": failures, "cell_size": 2, "bucket_size": 16, "format": "RG8", "scope": "original GDScript current/explored pixel and query equivalence; real six maps plus cliff/ramp/water/air/naval/boundary/removal/live-map cases", "rows": rows}
	var out := FileAccess.open("res://artifacts/revision_v7_integration/fog_native_equivalence.json", FileAccess.WRITE)
	out.store_string(JSON.stringify(report, "  "))
	out.close()
	print("V7_FOG_NATIVE ", JSON.stringify(report))
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
