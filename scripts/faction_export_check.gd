extends SceneTree

## Run the same resource check from the exported executable's embedded PCK.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game: Node3D=load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var report: Dictionary=verify_game(game)
	game.queue_free()
	await process_frame
	print("EXPORTED_FACTIONS ",JSON.stringify(report))
	for failure in report.failures:push_error(failure)
	quit(0 if report.failures.is_empty() else 1)

static func verify_game(game: Node3D) -> Dictionary:
	var failures: Array[String]=[]
	var rules := RulesLoader.load_rules()
	if rules.is_empty():
		failures.append("Exported rules: " + str(RulesLoader.errors))
	else:
		if rules.units.size()!=56 or rules.buildings.size()!=56 or rules.factions.size()!=4:failures.append("Incomplete exported roster")
		if rules.units.iron_tank.name != "磐石坦克" or rules.units.iron_recycler.name != "拖救车" or not rules.units.sky_designation.has("designation_track_time") or not rules.buildings.sky_accumulator.has("overcharge_power"): failures.append("Export contains the previous faction revision")
		for kind in ["unit", "building"]:
			var source: Dictionary = rules.units if kind=="unit" else rules.buildings
			for id in source:
				if kind=="unit" and source[id].art in ["rifle","anti","engineer","demolition"]:
					for card in source[id].animations.values():
						if not ResourceLoader.exists(card):failures.append("Missing paper infantry state: " + str(card))
						if not ResourceLoader.exists(str(card).trim_suffix(".svg")+"_identity.svg"):failures.append("Missing paper identity mask: " + str(card))
					continue
				var model := VolumeModels.create_model(source[id], kind, 0)
				if model.is_empty() or model.dimensions.y<=0:failures.append("Missing model: " + id)
				else:model.root.free()
		var manifest_path := "res://assets/audio/voices/manifest.json"
		if not FileAccess.file_exists(manifest_path):failures.append("Voice manifest was not exported")
		else:
			var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
			if manifest.get("clips",[]).size()!=96:failures.append("Incomplete exported speech coverage")
			for clip in manifest.get("clips",[]):
				if not ResourceLoader.exists(str(clip.path)):failures.append("Missing exported WAV: " + str(clip.path))
				else:
					var stream: AudioStreamWAV=load(str(clip.path))
					if stream==null or stream.get_length()<.25:failures.append("Unreadable exported speech: " + str(clip.path))
		game.set_process(false)
		game.set_physics_process(false)
		game.audio.muted=true
		for faction in ["kestrel", "iron", "sky"]:
			if not game.start_match("dev",24,faction,true):failures.append("Exported game cannot start: " + faction)
	return {"revision":"reliable_craft_and_simple_technology", "units":rules.get("units",{}).size(),"buildings":rules.get("buildings",{}).size(),"voices":96,"failures":failures}
