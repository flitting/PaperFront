extends SceneTree
const Demo = preload("res://scripts/audio_animation_preview.gd")
const Catalog = preload("res://scripts/audio_browser_catalog.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures.append(text)
func run() -> void:
	var rules: Dictionary = RulesLoader.load_rules()
	var before_rules: String = JSON.stringify(rules)
	var before_buses: int = AudioServer.bus_count
	var panel := Control.new(); root.add_child(panel)
	var demo = Demo.new(); panel.add_child(demo); demo.size = Vector2(640, 240)
	check(demo.viewport == null, "no viewport/model is allocated before an actor is selected")
	var rows: Array[Dictionary] = Catalog.load_catalog("zh_CN")
	var scenarios: Dictionary = {}
	var music_count := 0
	for row: Dictionary in rows:
		var plan: Dictionary = Demo.scenario_for_entry(row, rules)
		if row.type == "music":
			music_count += 1; check(plan.scene == "none", "pure music has no unrelated unit scene")
		else:
			check(plan.scene != "none" and not str(plan.spec).is_empty(), "every current effect/voice has a registered scene: " + str(row.id))
			var source: Dictionary = rules.buildings if plan.kind == "building" else rules.units
			check(source.has(plan.spec), "scene actor is actual authored equipment: " + str(row.id))
			if row.type == "voice" and row.category != "system": check(str(source[plan.spec].faction) == str(row.faction), "voice keeps its faction's actor")
			if row.type == "sfx": scenarios[str(row.action)] = plan.scene
	check(music_count == 5 and scenarios.size() == 34, "all 5 music and 34 active effect families are classified individually")
	for family: String in ["engine_loop", "tracks_loop", "aircraft_loop"]: check(scenarios.get(family) == "movement", "movement loop has a moving actor: " + family)
	for pair in [["select", "select"], ["command", "command"], ["produce", "produce"], ["delivery", "delivery"], ["sell", "sell"], ["low_power", "low_power"], ["result", "result"], ["error", "error"]]: check(scenarios.get(pair[0]) == pair[1], "interface scene matches its operation")
	check(Demo.scenario_for_entry({"type": "sfx", "action": "future_rain", "category": "environment"}, rules).scene == "none", "environment ambience remains blank")
	check(Demo.scenario_for_entry({"type": "sfx", "action": "unknown"}, rules).scene == "none", "unknown audio cannot masquerade as gunfire")
	var cannon: Dictionary = rows.filter(func(row): return row.type == "sfx" and row.action == "fire_cannon")[0]
	demo.configure_catalog_entry(cannon, rules)
	check(demo.viewport != null and demo.viewport.own_world_3d and demo._paper_factory.sim == null, "registered models use an isolated, simulation-free display case")
	var reference: Dictionary = VolumeModels.create_model(rules.units[demo.scene_plan.spec], "unit", 0)
	var meshes: Array = []
	var arrays: Array = []
	for index in range(reference.meshes.size()):
		meshes.append(reference.meshes[index].mesh)
		arrays.append(reference.meshes[index].mesh.surface_get_arrays(0).hash())
		check(reference.meshes[index].mesh == demo.model_data.meshes[index].mesh, "preview shares actual immutable authored meshes")
	check(demo.play_demo(), "fresh play starts the independent animation")
	demo._process(.35)
	check(is_equal_approx(demo.animation_time, .35) and demo.model_data.meshes[1].position.x < 0, "actual cannon barrel recoils on the demo clock")
	for index in range(meshes.size()): check(meshes[index].surface_get_arrays(0).hash() == arrays[index], "animation does not mutate shared source mesh data")
	var previous: float = demo.animation_time
	demo.pause_demo(true); demo._process(1.0)
	check(demo.animation_time == previous and demo.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "paused demo freezes without rendering")
	demo.pause_demo(false); demo._process(.1)
	check(is_equal_approx(demo.animation_time, previous + .1), "resume continues only its own clock")
	check(not demo.has_method("seek_to") and not demo.has_method("set_playback_speed"), "audio seeking/rate has no animation-clock API")
	demo.restart_demo()
	check(is_zero_approx(demo.animation_time) and demo.model_node.visible, "replay restores the initial actor pose and clock")
	demo._process(.4); panel.hide(); previous = demo.animation_time; demo._process(2.0)
	check(demo.animation_time == previous and demo.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "hidden preview freezes and disables rendering")
	panel.show(); demo.stop(); previous = demo.animation_time; demo._process(.5)
	check(demo.animation_time == previous and not demo.is_processing() and demo.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "manual stop ends updates independently of the audio cursor")
	var viewport_id: int = demo.viewport.get_instance_id()
	for family: String in scenarios:
		var row: Dictionary = rows.filter(func(item): return item.type == "sfx" and item.action == family)[0]
		demo.configure_catalog_entry(row, rules); demo.play_demo(); demo._process(.5)
		check(demo.viewport.get_instance_id() == viewport_id and demo.model_node != null, "family switching reuses one viewport and builds its real actor")
		check(demo.find_children("*", "AudioStreamPlayer", true, false).is_empty() and demo.find_children("*", "AudioStreamPlayer3D", true, false).is_empty(), "demo cannot produce any extra audio")
	demo.configure_catalog_entry({"type": "voice", "faction": "iron", "category": "vehicle", "action": "death"}, rules)
	demo.play_demo(); demo._process(.6)
	check(not demo.model_node.visible and demo._debris.any(func(node): return node.visible), "death demo replaces the actor with a private explosion/debris presentation")
	demo.configure_catalog_entry({"type": "music"}, rules)
	check(demo.model_node == null and demo.rotation_pivot.get_child_count() == 0 and not demo.visible and demo.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "music selection releases actors/effects and remains empty")
	demo.configure_catalog_entry({"type":"voice","faction":"iron","category":"infantry","action":"death"},rules);demo.play_demo();demo._process(.9)
	check(demo.model_node.rotation.x > .4 and not demo._flash.visible and demo._particles.all(func(node):return not node.visible),"infantry death falls without a vehicle fireball")
	demo.configure_catalog_entry({"type":"voice","faction":"sky","category":"air","action":"death"},rules)
	check(demo.scene_plan.scene=="air_crash" and demo.scene_plan.art=="fighter","airdeath uses authoredfighter crash ratherthanvehiclefireball")
	demo.play_demo();var starting_height:float=demo.model_node.position.y;demo._process(.6)
	check(demo.model_node.visible and demo.model_node.position.y<starting_height and demo.model_node.position.y>demo._home.y and demo.model_node.rotation.z<-.1 and demo._particles.any(func(p):return p.visible),"fighter banks/glidesdown leavingprivategraysmoke")
	check(not demo._flash.visible and demo.rotation_bounds.end.y>=demo.model_bounds.end.y+demo._radius*.8,"aircrash avoidsfireball andframesfullfall envelope")
	demo._process(1.0)
	check(not demo.model_node.visible and demo._debris.any(func(p):return p.visible),"fighter breaksintoprivatechips onlyaftergroundcontact")
	demo.restart_demo()
	check(demo.animation_time==0.0 and demo.model_node.visible and demo._debris.all(func(p):return not p.visible) and demo._particles.all(func(p):return not p.visible),"aircrash replay resetsaircraft smokechips andindependentclock")
	demo.clear_preview()
	check(JSON.stringify(rules) == before_rules and AudioServer.bus_count == before_buses, "demo never changes simulation rules or audio buses")
	reference.root.free()
	var factory: Node = demo._paper_factory
	demo.queue_free(); panel.queue_free(); await process_frame
	check(not is_instance_valid(factory), "preview teardown releases its lightweight unparented art factory")
	var report := {"checks": checks, "failures": failures, "mapped_rows": rows.size(), "effect_families": scenarios.size(), "music_empty": music_count, "scope": "CPU scene mappings, actual immutable authored meshes, independent clock and silent lifecycle; no GPU capture"}
	var file := FileAccess.open("res://artifacts/av_revision_20261006/audio_animation_preview_validation.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t") + "\n")
	print("AUDIO_ANIMATION_PREVIEW ", JSON.stringify(report))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
