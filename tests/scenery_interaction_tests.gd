extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
const Scaffold = preload("res://scripts/construction_scaffold.gd")
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _tick(sim, seconds: float) -> void:
	for i in range(ceili(seconds * 30.0)): sim.step(1.0 / 30.0)

func run() -> void:
	var rules: Dictionary = RulesLoader.load_rules()
	var sim = Sim.new()
	sim.setup(rules, "dev", 7, "rivet", false)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(24, 30, 52)
	camera.look_at(Vector3(24, 0, 24))
	var world := PaperWorld.new()
	root.add_child(world)
	world.setup(sim, camera)
	var trees: Array = sim.ruins.filter(func(e): return e.kind == "tree")
	_check(not trees.is_empty(), "fresh maps register interactive forest trees")
	var tree: Dictionary = trees[0]
	var target: int = Sim.RUIN_TARGET_BASE - int(tree.id)
	_check(MapData.terrain_at(sim.map, tree.pos) == MapData.LAND and not sim._standing(tree.pos, .35, -1, false), "live trees block dynamically over legal terrain")
	_check(world.landscape.tree_visuals.has(int(tree.id)) and world.landscape.tree_visuals[int(tree.id)].size() >= 2, "tree crown and trunk share persistent render batch slots")
	var tank: int = sim.debug_spawn(0, "rivet_tank", tree.pos + Vector2(-5, 0))
	var hp_before: float = float(tree.hp)
	sim.issue([tank], "attack", tree.pos, target)
	_tick(sim, 2.0)
	_check(float(tree.hp) == hp_before, "ordinary attack cannot damage a forest tree")
	sim.issue([tank], "attack_move", tree.pos)
	_tick(sim, 2.0)
	_check(float(tree.hp) == hp_before, "attack-move does not clear forest scenery")
	sim.issue([tank], "force_attack", tree.pos, target)
	_tick(sim, 15.0)
	_check(float(tree.hp) == 0.0 and not sim._target_alive(target), "forced attack destroys a tree and retires its target")
	world.sync(0.0, [])
	var vanished: bool = true
	for piece in world.landscape.tree_visuals[int(tree.id)]:
		var displayed: Transform3D = piece.current_transform if DisplayServer.get_name() == "headless" else piece.multi.get_instance_transform(piece.slot)
		vanished = vanished and displayed.basis.x.length() == 0.0
	_check(vanished, "destroyed trees disappear from all render batch slots in the same sync")
	_check(sim._standing(tree.pos, .35, -1, false), "destroyed trees leave their original ground cell open to infantry")
	var path: Array = sim._path_between(sim.entities[tank].pos, tree.pos, .35, tank)
	_check(not path.is_empty() and (path.back() as Vector2).distance_to(tree.pos) < .01, "navigation can plan into the removed tree's original cell")
	# The renderer represents construction using its own open frame and progress,
	# then atomically replaces it with the normal finished model.
	var engineer: int = sim.debug_spawn(0, "rivet_engineer", Vector2(11.5, 40.5))
	var outpost: int = sim.debug_spawn(0, "rivet_hq", Vector2(16.5, 40.5))
	var site: Dictionary = sim.entities[outpost]
	site.construction = {"builder": engineer, "progress": 0.0, "spent": 0.0, "initial_hp": 50.0, "repair_spent": 0.0, "work_state": "working", "pause_reason": ""}
	site.construct_remaining = float(rules.buildings.rivet_hq.build_time)
	site.hp = 50.0
	world.sync(0.0, [])
	var model: Dictionary = world.models[outpost]
	_check(model.scaffold and model.art_root.name == "ConstructionScaffold" and model.art_root.scale.y == 1.0, "construction shows an open scaffold without the finished building or compressed frame")
	_check(model.hp_fraction == 1.0 and model.progress_fill.scale.x == 0.0, "new construction shows its initial health and independent zero progress")
	site.construction.progress = .5
	site.construction.work_state = "paused"
	site.hp = Scaffold.health_cap(site, rules.buildings.rivet_hq) * .5
	world.sync(0.0, [])
	_check(model.hp_fraction == .5 and absf(model.progress_fill.scale.x - float(model.hp_width) * .5) < .001, "damaged paused construction displays health and structural progress separately")
	_check(model.scaffold and absf(model.volume.meshes[1].scale.y - .5) < .001, "paused construction retains a scaffold with its actual built structure")
	var scaffold_root: Node3D = model.root
	site.erase("construction")
	site.construct_remaining = 0.0
	site.hp = float(rules.buildings.rivet_hq.hp)
	world.sync(0.0, [])
	_check(not world.models[outpost].scaffold and scaffold_root.is_queued_for_deletion(), "completed construction replaces the scaffold with the finished outpost")
	world.queue_free()
	camera.queue_free()
	await process_frame
	print("Scenery interaction checks: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
