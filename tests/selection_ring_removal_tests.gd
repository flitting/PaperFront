extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
var checks: int = 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _initialize() -> void:
	call_deferred("run")

func ring_count(world, ids: Array) -> int:
	var unique: Dictionary = {}
	var count: int = 0
	for id: int in ids:
		var batch: Dictionary = world.models[id].ring_batch
		var key: int = batch.multi.get_instance_id()
		if unique.has(key): continue
		unique[key] = true
		count += world._batch_count(batch)
	return count

func run() -> void:
	check(ClassDB.class_exists("PaperFrontKernels"), "native renderer is available for comparison")
	if not ClassDB.class_exists("PaperFrontKernels"):
		quit(1)
		return
	var sim = Sim.new()
	sim.setup(RulesLoader.load_rules(), "dev", 7, "kestrel", false)
	var leader: int = sim.debug_spawn_squad(0, "kestrel_rifle", Vector2(20,26), true)
	var selected: Array = sim.squad_members(leader)
	selected.append(sim._spawn(0, "kestrel_engineer", Vector2(25,26), true))
	var tank: int = sim._spawn(0, "kestrel_tank", Vector2(29,26), true)
	selected.append(tank)
	selected.append(sim._spawn(0, "kestrel_power", Vector2(26,32), true))
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(25,30,61)
	camera.look_at(Vector3(25,0,28))
	var world := PaperWorld.new()
	root.add_child(world)
	world.setup(sim, camera)
	var records: Array = []
	for quality: String in ["native", "balanced", "performance"]:
		world.configure_quality(quality)
		for native_batches: bool in [false, true]:
			world.native_batches_enabled = native_batches
			for native_sync: bool in [false, true]:
				world.native_world_sync_enabled = native_sync
				world.sync(.016, selected)
				var context: String = "%s / %s sync / %s batches" % [quality, "native" if native_sync else "script", "native" if native_batches else "script"]
				check(selected.all(func(id): return world.models.has(id) and not bool(world.models[id].get("view_culled", false)) and not bool(world.models[id].get("embarked", false))), "selected squad/engineer/tank/building are actually visible: " + context)
				check(ring_count(world, selected) == 0, "actual submitted selection ring count is zero: " + context)
				check(world._batch_count(world.models[tank].hp_batches[0]) > 0, "selection still submits health indicators: " + context)
				records.append({"path":context,"rings":ring_count(world,selected)})
	# Public native entry points can bypass _sync_entity. Exercise them directly
	# even while the normal world selects its complete authored model path.
	world.native_batches_enabled = true
	world.native_world_sync_enabled = true
	world.sync(.016, selected)
	check(bool(world.models[tank].volumetric), "tank exercises the volumetric native entry point")
	world._begin_batches()
	var pose_submitted: int = world._kernels.update_volume(world.models[tank], sim.entities[tank], true, world.camera_yaw, world.elapsed, float(sim.rules.economy.harvester_capacity), float(sim.rules.economy.construction_animation))
	check(pose_submitted > 0, "direct native volume pose submits real geometry")
	check(ring_count(world, selected) == 0, "direct native volume pose submits zero selection rings")
	world._begin_batches()
	world._kernels.clear_world_models()
	var selected_ids: Dictionary = {}
	for id: int in selected: selected_ids[id] = true
	var counts: Dictionary = world._kernels.sync_world_entities(world, sim.entities, world.models, selected_ids, sim.map, "performance", world.elapsed, world.camera_yaw, float(sim.rules.economy.harvester_capacity), float(sim.rules.economy.construction_animation))
	check(int(counts.submitted) > 0, "direct performance world path submits real geometry")
	check(ring_count(world, selected) == 0, "native paper and volume fast paths submit zero selection rings")
	print("SELECTION_RING_REMOVAL ", JSON.stringify({"checks":checks,"failures":failures,"paths":records}))
	world.queue_free(); camera.queue_free()
	await process_frame
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
