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
	var voice_count := 0
	var rules := RulesLoader.load_rules()
	if rules.is_empty():
		failures.append("Exported rules: " + str(RulesLoader.errors))
	else:
		if rules.units.size()!=69 or rules.buildings.size()!=58 or rules.factions.size()!=4:failures.append("Incomplete exported roster")
		if rules.units.iron_tank.name != "磐石坦克" or rules.units.iron_recycler.name != "拖救车" or not rules.units.sky_designation.has("designation_track_time") or not rules.units.has("iron_train") or not rules.buildings.has("rivet_drill") or rules.buildings.has("sky_accumulator"): failures.append("Export contains the previous faction revision")
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
		var manifest_path := "res://assets/audio/revision_v8/radio/manifest.json"
		if not FileAccess.file_exists(manifest_path):failures.append("Voice manifest was not exported")
		else:
			var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
			voice_count = manifest.get("clips",[]).size()
			if voice_count!=288:failures.append("Incomplete exported speech coverage")
			var groups: Dictionary = {}
			for clip in manifest.get("clips",[]):
				var key: String = str(clip.get("faction", "")) + "/" + str(clip.get("category", "")) + "/" + str(clip.get("action", ""))
				groups[key] = int(groups.get(key, 0)) + 1
				var path: String = str(clip.get("file", ""))
				if not path.begins_with("res://assets/audio/revision_v8/radio/"):failures.append("Retired or invalid speech path: " + path)
				if not ResourceLoader.exists(path):failures.append("Missing exported WAV: " + path)
				else:
					var stream: AudioStreamWAV=load(path)
					if stream==null or stream.get_length()<.25:failures.append("Unreadable exported speech: " + path)
			for id in rules.units:
				var info: Dictionary = rules.units[id]
				for action in ["select", "move", "attack", "ready", "return", "combat", "under_attack", "death"]:
					var key: String = str(info.faction) + "/" + str(info.get("voice_category", "vehicle")) + "/" + str(action)
					if int(groups.get(key, 0)) != 3:failures.append("Incomplete exported speech group for " + id + ": " + key)
		for retired in ["res://assets/audio/radio/manifest.json", "res://assets/audio/voices/manifest.json"]:
			if FileAccess.file_exists(retired):failures.append("Retired speech bank exported: " + retired)
		for faction in ["kestrel", "rivet", "iron", "sky"]:
			for action in ["select", "move", "attack", "ready", "return"]:
				var retired := "res://assets/audio/radio/%s_%s.wav" % [faction, action]
				if ResourceLoader.exists(retired):failures.append("Retired mechanical speech exported: " + retired)
		game.set_process(false)
		game.set_physics_process(false)
		game.audio.muted=true
		for faction in ["kestrel", "iron", "sky"]:
			if not game.start_match("dev",24,faction,true):failures.append("Exported game cannot start: " + faction)
	return {"revision":"combat_audio_v8", "units":rules.get("units",{}).size(),"buildings":rules.get("buildings",{}).size(),"voices":voice_count,"failures":failures}
