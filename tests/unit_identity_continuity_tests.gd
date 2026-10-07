extends SceneTree

var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func run() -> void:
	var rules: Dictionary = RulesLoader.load_rules()
	var voice := PaperAudio.new()
	voice._configure_definitions(rules)
	for id: String in rules.units:
		var spec: Dictionary = rules.units[id]
		var group: String = str(spec.faction) + "/" + str(spec.voice_category)
		for action: String in PaperAudio.RADIO_ACTIONS:
			check(voice.speech_key(id, action) == group + "/" + action, "same unit keeps its faction/class voice identity: " + id + "/" + action)
		if str(spec.art) in VolumeModels.INFANTRY_ART:
			var base: String = VolumeModels.art_faction(spec) + "_" + str(spec.art)
			var paint: String = "#" + str(rules.factions[spec.faction].color)
			for state: String in ["idle", "move", "attack", "hit"]:
				var path: String = str(spec.animations[state])
				check(path.get_file().get_basename() == base + "_" + state, "paper animation retains the same unit/faction asset family: " + id + "/" + state)
				var svg: String = FileAccess.get_file_as_string(path)
				check(svg.contains(paint) and svg.contains("player-identification"), "paper action retains faction uniform and owner identification: " + id + "/" + state)
			continue
		var model: Dictionary = VolumeModels.create_model(spec, "unit", 0)
		check(not model.is_empty(), "same authored model exists: " + id)
		if model.is_empty(): continue
		root.add_child(model.root)
		var original: Array = []
		for mesh: MeshInstance3D in model.meshes: original.append(mesh.mesh)
		var node_id: int = model.root.get_instance_id()
		var event: Dictionary = {"id": 1, "spec": id, "state": "idle", "hit_flash": 0.0, "attack_flash": 0.0, "airborne": true, "cargo": 0.0, "alpha": 0.0}
		for state: String in ["idle", "move", "attack", "hit"]:
			event.state = state
			event.hit_flash = .18 if state == "hit" else 0.0
			event.attack_flash = .25 if state == "attack" else 0.0
			VolumeModels.update_model(model, event, .1)
			check(model.root.get_instance_id() == node_id, "action keeps the original model hierarchy: " + id + "/" + state)
			for index: int in model.meshes.size(): check(model.meshes[index].mesh == original[index], "action animates the same geometry without replacing identity: " + id + "/" + state)
		model.root.free()
	voice.free()
	await process_frame
	print("UNIT_IDENTITY_CONTINUITY ", JSON.stringify({"checks": checks, "failures": failures, "units": rules.units.size(), "scope": "voice routing identity and real model/animation asset continuity; not an acoustic identity assertion"}))
	call_deferred("finish")

func finish() -> void:
	await process_frame
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
