extends SceneTree

var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func submitted(world: PaperWorld, model: Dictionary) -> bool:
	return world._batch_transforms(model.hand_owner_batch).has(model.root.global_transform * model.hand_owner_mark.transform)

func run() -> void:
	check(ClassDB.class_exists("PaperFrontKernels"), "native lifecycle kernel available for both-route verification")
	var sim := WarSimulation.new()
	sim.setup_multiteam(RulesLoader.load_rules(), "dev", 7, ["sky", "sky", "sky", "sky"], false)
	sim.entities.clear()
	sim.events.clear()
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(28, 35, 63)
	camera.look_at(Vector3(28, 0, 27))
	var worlds: Array[PaperWorld] = []
	for native_route: bool in [true, false]:
		var world := PaperWorld.new()
		world.native_world_sync_enabled = native_route
		world.native_kernels_enabled = native_route
		root.add_child(world)
		world.setup(sim, camera)
		world.configure_quality("balanced")
		worlds.append(world)
	var ids: Array[int] = []
	for team: int in range(4):
		ids.append(sim._spawn(team, "sky_creator_hand", Vector2(16 + team * 8, 24), true))
	var tank_id: int = sim._spawn(0, "sky_tank", Vector2(28, 31), true)
	for world in worlds:
		world.sync(0.05, [])
		var route: String = "native" if world.native_world_sync_enabled else "script"
		check(world._native_world_cache_active == world.native_world_sync_enabled, route + " lifecycle route actually used")
		var colors: Array[Color] = []
		for id in ids:
			var model: Dictionary = world.models[id]
			check(model.direct_skinned and model.volume.skeleton.get_bone_count() == 16, route + " continuous 16-bone hand retained")
			check(submitted(world, model), route + " unselected visible hand has owner mark " + str(id))
			check(world._batch_count(model.ring_batch) == 0, route + " unselected hand does not gain selection ring " + str(id))
			var material: StandardMaterial3D = model.hand_owner_mark.material_override
			check(material.albedo_color == VolumeModels.player_color(int(sim.entities[id].team)), route + " player color is independent of faction " + str(id))
			check(not colors.has(material.albedo_color), route + " four same-faction owners have distinct marks " + str(id))
			colors.append(material.albedo_color)
			check(model.hand_owner_mark.scale.x > model.ring.scale.x, route + " owner mark lies outside selection ring " + str(id))
			check(not model.hand_owner_mark.visible, route + " owner mark uses gated batch only " + str(id))
		check(not world.models[tank_id].has("hand_owner_batch"), route + " ordinary vehicles are unchanged")
		world.sync(0.05, [ids[0]])
		var selected: Dictionary = world.models[ids[0]]
		check(submitted(world, selected) and world._batch_count(selected.ring_batch) == 1, route + " selected hand retains separate owner and selection marks")
	# Manual visibility bits exercise real fog submission gates without forcing
	# a vision refresh to overwrite this fixed fixture between world frames.
	sim.vision_enabled = true
	for id in ids: sim.entities[id].visible_to = 15
	sim.entities[ids[1]].visible_to = 0
	sim.entities[ids[2]].transport_id = 999
	sim.entities[ids[3]].pos = Vector2(220, 220)
	for world in worlds:
		world.sync(0.05, ids)
		var route: String = "native" if world.native_world_sync_enabled else "script"
		check(not submitted(world, world.models[ids[1]]) and world.models[ids[1]].fog_hidden, route + " fog-hidden hand reveals no owner marker")
		check(not submitted(world, world.models[ids[2]]) and world.models[ids[2]].embarked, route + " loaded hand reveals no owner marker")
		check(not submitted(world, world.models[ids[3]]) and world.models[ids[3]].view_culled, route + " culled hand submits no owner marker")
	sim.entities[ids[1]].visible_to = 15
	sim.entities[ids[2]].transport_id = -1
	sim.entities[ids[3]].pos = Vector2(40, 24)
	for world in worlds:
		world.sync(0.05, [])
		for id in ids: check(submitted(world, world.models[id]), "owner marker returns after visibility/transport/culling transition " + str(id))
	var previous: Array[Dictionary] = []
	for world in worlds: previous.append(world.models[ids[0]])
	sim.entities[ids[0]].team = 3
	for index: int in range(worlds.size()):
		var world: PaperWorld = worlds[index]
		world.sync(0.05, [])
		var changed: Dictionary = world.models[ids[0]]
		check(changed.team == 3 and changed.hand_owner_mark.material_override.albedo_color == VolumeModels.player_color(3), "ownership change rebuilds marker material")
		check(submitted(world, changed) and world._batch_count(previous[index].hand_owner_batch) == 0, "ownership change does not replay previous owner color")
	var deceased: Array[Dictionary] = []
	for world in worlds: deceased.append(world.models[ids[1]])
	sim._kill_entity(ids[1], true)
	sim.events.clear()
	for index: int in range(worlds.size()):
		var world: PaperWorld = worlds[index]
		world.sync(0.05, [])
		check(not submitted(world, deceased[index]), "dead hand corpse has no living owner marker")
		world.sync(2.6, [])
		check(not deceased[index].root.visible and world._batch_count(deceased[index].hand_owner_batch) == 0, "hidden pooled hand submits no marker")
	var replacement: int = sim._spawn(1, "sky_creator_hand", Vector2(24, 24), true)
	sim.entities[replacement].visible_to = 15
	for index: int in range(worlds.size()):
		var world: PaperWorld = worlds[index]
		world.sync(0.05, [])
		var reused: Dictionary = world.models[replacement]
		check(reused.root == deceased[index].root and submitted(world, reused), "same-owner pooled skeleton and marker restore together")
		check(reused.hand_owner_mark.material_override.albedo_color == VolumeModels.player_color(1), "pool reuse retains correct owner color")
	for world in worlds: world.free()
	camera.free()
	await process_frame
	print("DEMO_HAND_OWNER ", JSON.stringify({"checks": checks, "failures": failures}))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
