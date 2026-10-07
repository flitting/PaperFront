extends SceneTree

var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game._flush_render_simulation()
	game.set_process(false)
	game.set_physics_process(false)
	game.audio.muted = true
	var sim: WarSimulation = game.sim
	var world: PaperWorld = game.world
	for catalog in [sim.rules.buildings, sim.rules.units]:
		for spec_id in catalog:
			var id: int = sim._spawn(0, spec_id, Vector2(22.5, 32.5), true)
			world.models[id] = world._create_entity(sim.entities[id])
	var solids: int = 0
	var buildings: int = 0
	for model in world.models.values():
		if model.volumetric: solids += 1
		if model.kind == "building": buildings += 1
	for policy: String in ["native", "balanced", "performance"]:
		game.set_graphics_quality(policy)
		check(game.battlefield_viewport.mesh_lod_threshold == 0.0, "automatic mesh decimation disabled " + policy)
		check(game.battlefield_viewport.msaa_3d == root.msaa_3d, "original edge antialiasing retained " + policy)
		var landscape = world.landscape
		check(not landscape._forest_lods.is_empty() and landscape._forest_lods.all(func(lod): return lod.meshes.size() == 3 and lod.meshes[0] == lod.source and lod.node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON), "three crown tiers retain the authored near model and shadows " + policy)
		check(not landscape._trunk_lods.is_empty() and landscape._trunk_lods.all(func(lod): return lod.meshes.size() == 3 and lod.meshes[0] == lod.source), "three trunk tiers retain the authored near roots and ink " + policy)
		for tier: int in range(3):
			game.distance = [20.0, 75.0, 110.0][tier]
			world.lod_override = tier
			game.update_camera()
			world._begin_batches()
			for id in world.models:
				var model: Dictionary = world.models[id]
				world._sync_entity(model, sim.entities[id], false)
				if not model.volumetric: continue
				for part in model.render_parts:
					var label: String = "%s/%s/tier%s" % [model.pool_spec, policy, tier]
					var active: Dictionary = part.lod_batches[tier]
					check(part.batch.multi.mesh == part.node.mesh, "authored full source remains intact " + label)
					check(active.node.material_override == part.node.material_override, "authored pigment material at every tier " + label)
					check(active.node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "model shadow retained at every tier " + label)
					check(world._batch_transforms(active).has(part.node.global_transform), "chosen LOD actually submitted " + label)
					if part.has("ink_batch"):
						check(world._batch_transforms(part.ink_lod_batches[tier]).has(part.node.global_transform) and world._batch_transforms(part.paper_lod_batches[tier]).has(part.node.global_transform), "matching ink and paper borders actually submitted " + label)
					if part.has("performance_batch"):
						check(part.quality_batch == part.lod_batches[1] and part.performance_batch == part.lod_batches[2], "far and extreme descriptors are available in every preset " + label)
			world._flush_batches()
	print("MODEL_DETAIL_TESTS ", JSON.stringify({"checks":checks, "solid_models":solids, "buildings_including_starting_hqs":buildings, "failures":failures}))
	game.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
