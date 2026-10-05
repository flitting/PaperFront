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
		check(not landscape._forest_lods.is_empty() and landscape._forest_lods.all(func(lod): return lod.near.visible and lod.near.visibility_range_end == 0.0 and not lod.mid.visible and not lod.far.visible), "complete tree crowns at all distances " + policy)
		check(not landscape._trunk_lods.is_empty() and landscape._trunk_lods.all(func(lod): return lod.near.visible and lod.near.visibility_range_end == 0.0 and not lod.far.visible and not lod.distant.visible), "complete trunks, roots and ink at all distances " + policy)
		for distance: float in [20.0, 40.0, 110.0]:
			game.distance = distance
			game.update_camera()
			world._begin_batches()
			for id in world.models:
				var model: Dictionary = world.models[id]
				world._sync_entity(model, sim.entities[id], false)
				if not model.volumetric: continue
				for part in model.render_parts:
					var label: String = "%s/%s/%s" % [model.pool_spec, policy, distance]
					check(part.batch.multi.mesh == part.node.mesh, "authored full mesh " + label)
					check(part.batch.node.material_override == part.node.material_override, "authored pigment material " + label)
					check(part.batch.node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "full model shadows " + label)
					check(world._batch_transforms(part.batch).has(part.node.global_transform), "complete mesh actually submitted " + label)
					if part.has("ink_batch"):
						check(world._batch_transforms(part.ink_batch).has(part.node.global_transform) and world._batch_transforms(part.paper_batch).has(part.node.global_transform), "ink and paper borders actually submitted " + label)
					if part.has("performance_batch"):
						check(part.performance_batch == part.batch and part.quality_batch == part.batch, "quality aliases cannot reduce geometry " + label)
			world._flush_batches()
	print("MODEL_DETAIL_TESTS ", JSON.stringify({"checks":checks, "solid_models":solids, "buildings_including_starting_hqs":buildings, "failures":failures}))
	game.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
