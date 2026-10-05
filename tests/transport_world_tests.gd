extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
const World = preload("res://tests/transport_world_probe.gd")
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _tick(sim, seconds: float) -> void:
	for i in range(ceili(seconds * 30.0)): sim.step(1.0 / 30.0)

func _instances(world, mesh: Mesh) -> int:
	var count: int = 0
	for batch in world.batches.values():
		if batch.multi.mesh == mesh: count += batch.multi.visible_instance_count
	return count

func run() -> void:
	var rules: Dictionary = RulesLoader.load_rules()
	_check(not rules.is_empty(), "World transport rules load")
	if rules.is_empty():
		quit(1)
		return
	var sim = Sim.new()
	sim.setup(rules, "dev", 7, "rivet", false)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(24, 30, 52)
	camera.look_at(Vector3(24, 0, 24))
	var world = World.new()
	root.add_child(world)
	world.setup(sim, camera)
	var tower: int = sim.debug_spawn(1, "kestrel_tower", Vector2(19.5, 35.5))
	var carrier: int = sim.debug_spawn(0, "rivet_scout", Vector2(13.5, 39.5))
	var passenger: int = sim.debug_spawn(0, "rivet_rifle", Vector2(11.5, 39.5))
	var engineer: int = sim.debug_spawn(0, "rivet_engineer", Vector2(9.5, 37.5))
	world.sync(0.0, [tower, passenger])
	var old_tower_root: Node3D = world.models[tower].root
	var old_faction_color: Color = world.models[tower].volume.faction_color
	sim.entities[tower].team = 0
	sim.entities[tower].captured = true
	world.sync(0.0, [tower, passenger])
	var tower_model: Dictionary = world.models[tower]
	_check(tower_model.root != old_tower_root and old_tower_root.is_queued_for_deletion(), "captured buildings replace the cached ownership model")
	_check(tower_model.team == 0 and tower_model.volume.player_color == VolumeModels.PLAYER_COLORS[0], "captured buildings refresh the owner identification color")
	_check(tower_model.spec.faction == "kestrel" and tower_model.volume.faction_color == old_faction_color, "captured buildings preserve their original faction model and paint")
	_check(tower_model.ring.material_override.albedo_color == PaperWorld.TEAM_COLORS[0], "captured buildings show the new owner's selection ring")
	var passenger_mesh: Mesh = world.models[passenger].graphic.mesh
	_check(_instances(world, passenger_mesh) == 1, "infantry on foot contribute a visible paper card")
	sim.issue([passenger], "board", sim.entities[carrier].pos, carrier)
	_tick(sim, 2.0)
	world.sync(0.0, [passenger])
	_check(world.models[passenger].embarked and _instances(world, passenger_mesh) == 0, "embarked infantry remain cached while their paper card is hidden")
	_check(sim.counts(0).x == 3, "render hiding preserves all friendly unit entities and counts")
	_check(sim.unload(carrier) == "", "world fixture unloads onto valid local terrain")
	world.sync(0.0, [passenger])
	passenger_mesh = world.models[passenger].graphic.mesh
	_check(not world.models[passenger].embarked and _instances(world, passenger_mesh) == 1, "unloading restores the existing infantry render model")
	sim.issue([passenger], "board", sim.entities[carrier].pos, carrier)
	_tick(sim, 0.5)
	world.sync(0.0, [])
	sim._kill_entity(carrier, true)
	world.sync(0.0, [])
	_check(not world.models.has(passenger) and not world.ghosts.any(func(ghost): return ghost.model.spec.art == "rifle"), "destroyed transported infantry do not leave an exposed death model")
	var pos := Vector2(27.5, 39.5)
	sim.building_orders[0] = {"spec": "rivet_power"}
	world.circle_radii.clear()
	world.sync(0.0, [], {"spec": "rivet_power", "pos": pos, "valid": true})
	_check(world.circle_radii.has(sim.construction_radius("rivet_hq")), "ordinary placement shows the headquarters range from the active match rules")
	sim.building_orders[0] = {"spec": "rivet_outpost", "builder": engineer}
	world.circle_radii.clear()
	world.sync(0.0, [], {"spec": "rivet_outpost", "pos": pos, "valid": true})
	_check(not world.circle_radii.has(sim.construction_radius("rivet_hq")), "engineer outpost placement omits headquarters range guides")
	world.queue_free()
	camera.queue_free()
	await process_frame
	print("Transport world checks: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
