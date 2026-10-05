extends SceneTree

const WORLD = preload("res://scripts/paper_world.gd")
const CIVILIANS = preload("res://assets/civilians/paper_civilians.gd")
const SIM = preload("res://scripts/simulation.gd")
var checks: int = 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var sim = SIM.new()
	sim.factions.assign(["rivet", "kestrel"])
	sim.vision_enabled = true
	sim.rules = {"units": {"rivet_rifle": {"domain": "ground", "vision_radius": 16}}, "buildings": {}}
	sim.map = {"size": 64, "seed": 9, "mode": "forest", "terrain": [], "heights": []}
	for z: int in 64:
		var heights: Array = []
		var terrain: Array = []
		for x: int in 64:
			heights.append(5.0 if x == 14 else 0.0)
			terrain.append(0)
		sim.map.heights.append(heights)
		sim.map.terrain.append(terrain)
	sim.entities[1] = {"id": 1, "team": 0, "hp": 100, "kind": "unit", "spec": "rivet_rifle", "pos": Vector2(9, 9)}
	sim.TeamVision.initialize(sim)
	var contacts_before: Dictionary = sim.team_vision.duplicate(true)
	var entities_before: Dictionary = sim.entities.duplicate(true)
	var memory = WORLD.SightMemory.new()
	memory.initialize(64)
	check(memory.refresh(sim), "initial legal sight uploads a changed mask")
	var home: int = (4 * memory.width + 4) * 2
	var hidden: int = (4 * memory.width + 9) * 2
	var far: int = (26 * memory.width + 26) * 2
	check(memory.pixels[home] == 255 and memory.pixels[home + 1] == 255, "current terrain sight is explored and clear")
	check(memory.pixels[hidden] == 0 and memory.pixels[hidden + 1] == 0, "height-blocked terrain stays unexplored inside observer radius")
	check(memory.pixels[far] == 0 and memory.pixels[far + 1] == 0, "unobserved distant terrain remains a separate unknown state")
	check(sim.team_vision == contacts_before and sim.entities == entities_before, "cosmetic fog leaves contact memory and entities unchanged")
	var first_queries: int = memory.queries
	check(not memory.refresh(sim) and memory.queries == 0, "unchanged observers do no terrain queries or texture updates")
	sim.entities[1].pos = Vector2(49, 49)
	sim.TeamVision.refresh(sim, true)
	memory.refresh(sim)
	check(memory.pixels[home] == 0 and memory.pixels[home + 1] == 255, "lost sight preserves explored terrain without current sight")
	check(memory.pixels[far] == 255 and memory.pixels[far + 1] == 255, "moving legal observer reveals its new region")
	var remembered: PackedByteArray = memory.explored_bytes()
	var restored = WORLD.SightMemory.new()
	restored.initialize(64)
	check(restored.restore_explored(remembered), "exploration bytes restore exactly")
	check(restored.pixels[far] == 0 and restored.pixels[far + 1] == 255, "restore never carries stale current visibility")
	restored.refresh(sim)
	check(restored.pixels[far] == 255 and restored.pixels[home] == 0, "restore recomputes current sight from the active TeamVision")
	check(not restored.restore_explored(PackedByteArray([0, 255])), "wrong-sized exploration cannot replace the mask")
	var invalid: PackedByteArray = remembered.duplicate()
	invalid[0] = 42
	check(not restored.restore_explored(invalid), "invalid exploration values are rejected atomically")
	for variant: int in 3:
		var mesh: ArrayMesh = CIVILIANS.mesh(variant)
		var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var minimum: float = 100
		var maximum: float = -100
		for vertex: Vector3 in vertices:
			minimum = minf(minimum, vertex.z)
			maximum = maxf(maximum, vertex.z)
		check(vertices.size() > 100 and maximum - minimum < .007, "civilian variant %d is a detailed flat paper print" % variant)
		check(mesh.get_meta("representation") == "flat_cut_paper" and mesh.surface_get_material(0) is ShaderMaterial, "civilian variant %d uses the paper billboard material" % variant)
	var world = WORLD.new()
	world.sim = sim
	root.add_child(world)
	world.landscape = preload("res://scripts/landscape.gd").new()
	world.add_child(world.landscape)
	var camera := Camera3D.new()
	root.add_child(camera)
	world.camera = camera
	for variant: int in 3:
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = BoxMesh.new()
		multi.instance_count = 1
		multi.set_instance_transform(0, Transform3D(Basis(Vector3.UP, .9), Vector3(12, 3, 19)))
		world.landscape._civilian_batches.append({"multi": multi, "people": [{"variant": variant}]})
	world._configure_civilian_paper()
	for group: Dictionary in world.landscape._civilian_batches:
		check(group.multi.mesh.get_meta("representation") == "flat_cut_paper", "actual world substitutes the pedestrian mesh")
		check(group.multi.instance_count == 1 and group.people.size() == 1, "civilian replacement keeps batch size and original route records")
	world._setup_fog()
	check(world._fog_node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and world._fog_material.render_priority == 120, "one unshadowed fog pass runs after normal battlefield transparency")
	world.profile_enabled = true
	world._sync_fog()
	check(world.profile_last.fog_queries == 0, "fog refresh cadence skips queries inside its time interval")
	sim.vision_enabled = false
	world._sync_fog()
	check(not world._fog_node.visible, "matches with vision disabled have no cosmetic shroud")
	sim.vision_enabled = true
	world._sync_fog()
	check(world._fog_node.visible, "enabling vision restores the shroud without rebuilding the world")
	world._fog_memory = memory
	world._fog_texture = ImageTexture.create_from_image(memory.image())
	var snapshot: Dictionary = world.export_visual_memory()
	check(not snapshot.has("entities") and not snapshot.has("visible_to") and not snapshot.has("last_known"), "visual save contains exploration only")
	check(world.restore_visual_memory(snapshot), "world exploration API roundtrips")
	var wrong_map: Dictionary = snapshot.duplicate()
	wrong_map.map_seed = 11
	check(not world.restore_visual_memory(wrong_map), "exploration for another map seed is rejected")
	wrong_map = snapshot.duplicate()
	wrong_map.map_mode = "desert"
	check(not world.restore_visual_memory(wrong_map), "same-size same-seed exploration from another map mode is rejected")
	wrong_map = snapshot.duplicate()
	wrong_map.erase("map_mode")
	check(not world.restore_visual_memory(wrong_map), "ambiguous memory without map mode is rejected")
	var pixels_before: PackedByteArray=world._fog_memory.pixels.duplicate()
	for bad_key: String in ["version","map_size","map_seed","cell_size","map_mode","explored"]:
		var malformed: Dictionary=snapshot.duplicate(true)
		malformed[bad_key]=[] if bad_key in ["version","cell_size","map_mode"] else {}
		check(not world.restore_visual_memory(malformed),"malformed cosmetic field rejected: " + bad_key)
	check(world._fog_memory.pixels==pixels_before,"malformed cosmetic fields leave actual sight unchanged")
	var json_copy: Dictionary=JSON.parse_string(JSON.stringify(snapshot))
	check(world.restore_visual_memory(json_copy),"JSON numeric exploration identity roundtrips")
	world.free()
	camera.free()
	print("WORLD_VISUAL_V7 ", JSON.stringify({"checks": checks, "failed": failures.size(), "initial_queries": first_queries, "mask_pixels": memory.width * memory.width, "mask_format": "RG8", "civilian_variants": 3}))
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
