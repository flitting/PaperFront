extends SceneTree

var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func run() -> void:
	for native: bool in [false, true]:
		var sim := WarSimulation.new()
		sim.setup(RulesLoader.load_rules(), "dev", 7, "sky", false)
		var camera := Camera3D.new()
		root.add_child(camera)
		camera.position = Vector3(24, 22, 46)
		camera.look_at(Vector3(24, 0, 26))
		var world := PaperWorld.new()
		root.add_child(world)
		world.setup(sim, camera)
		world.native_world_sync_enabled = native
		world.configure_quality("native")
		var ordinary: int = sim._spawn(1, "rivet_tank", Vector2(26, 28), true)
		world.sync(.01, [])
		sim._kill_entity(ordinary, true)
		world.sync(.01, [])
		check(world.ghosts.is_empty() and world.effects.any(func(effect): return effect.kind=="death_blast") and world.effects.any(func(effect): return effect.kind=="debris"), "ordinary tank uses explosion and detached geometry")
		sim.events.clear()
		world.sync(2.6, [])
		var hand: int = sim._spawn(0, "sky_creator_hand", Vector2(22, 28), true)
		var target: int = sim._spawn(1, "rivet_tank", Vector2(27, 28), true)
		sim.entities[target].hp = 100.0
		world.sync(.01, [])
		sim.issue([hand], "attack", sim.entities[target].pos, target)
		var styled: bool = false
		for tick: int in 150:
			sim.step(1.0 / 30.0)
			for event: Dictionary in sim.events:
				if event.kind == "death" and int(event.id) == target:
					styled = event.get("death_style", "") == "creator_crush"
			world.sync(1.0 / 30.0, [])
			sim.events.clear()
			if not sim.entities.has(target): break
		check(styled, "real creator attack tags lethal target presentation")
		check(not sim.entities.has(target) and not world.models.has(target), "crushed target has no live world model")
		check(world.ghosts.is_empty(), "creator kill does not retain an intact target ghost")
		var rubble: Array = world.effects.filter(func(effect): return effect.kind == "creator_rubble")
		check(rubble.size() >= 5 and rubble.filter(func(effect): return effect.graphic.mesh is BoxMesh and effect.graphic.mesh.size.z > effect.graphic.mesh.size.y * 3.0).size() == 2, "tank leaves broken plates and two visibly flattened chassis sections")
		check(rubble.all(func(effect): return effect.graphic.mesh != null and effect.life == 6.0), "rubble is actual bounded-lifetime 3D geometry")
		world.sync(6.1, [])
		check(world.effects.all(func(effect): return effect.kind != "creator_rubble"), "crush geometry expires and is released")
		var replacement: int = sim._spawn(1, "rivet_tank", Vector2(28, 28), true)
		world.sync(.01, [])
		check(not world.models[replacement].has("creator_crushed"), "pooled targets cannot inherit crush death flags")
		sim._kill_entity(replacement, true)
		world.sync(.01, [])
		check(world.ghosts.is_empty() and world.effects.any(func(effect): return effect.kind=="death_blast"), "ordinary death after pooled crush still uses explosion presentation")
		sim.events.clear()
		world.sync(2.6, [])
		# A nonlethal strike must not mark a later unrelated death as a crush.
		var survivor: int = sim._spawn(1, "rivet_tank", Vector2(27, 28), true)
		sim.entities[survivor].hp = 100000.0
		sim.entities[hand].cooldown = 0.0
		sim.issue([hand], "attack", sim.entities[survivor].pos, survivor)
		for tick: int in 35: sim.step(1.0 / 30.0)
		check(sim.entities.has(survivor) and sim.entities[survivor].hp < 100000.0, "real nonlethal creator strike settles normally")
		sim.events.clear()
		sim._kill_entity(survivor, true)
		check(sim.events.all(func(event): return event.get("death_style", "") != "creator_crush"), "nonlethal strike metadata does not leak across ticks")
		world.sync(.01, [])
		sim.events.clear()
		world.sync(2.6, [])
		world.configure_quality("performance")
		var compact_target: int = sim._spawn(1, "rivet_tank", Vector2(27, 28), true)
		sim.entities[compact_target].hp = 100.0
		sim.entities[hand].cooldown = 0.0
		world.sync(.01, [])
		sim.issue([hand], "attack", sim.entities[compact_target].pos, compact_target)
		for tick: int in 150:
			sim.step(1.0 / 30.0)
			world.sync(1.0 / 30.0, [])
			sim.events.clear()
			if not sim.entities.has(compact_target): break
		check(not sim.entities.has(compact_target), "creator impact also resolves under compact effects")
		check(world.effects.all(func(effect): return effect.kind != "creator_rubble") and world.ghosts.is_empty(), "compact effects do not allocate unprocessed creator nodes or intact ghosts")
		world.free()
		camera.free()
		await process_frame
	print("CREATOR_CRUSH_EFFECTS ", JSON.stringify({"checks":checks,"failures":failures}))
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
