extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
var checks := 0
var failures: Array[String] = []
var sim
var sound: PaperAudio
var voice
var recording: AudioEffectRecord
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func route(expected: String) -> void:
	voice.reset(sim); voice.enabled = true
	for event: Dictionary in sim.events: voice.observe_event(event, sim)
	check(voice.pending.has(expected), "actual simulation event triggers " + expected)
	voice._process(.02)
	check(voice.active_action == expected and voice.player.playing and voice.player.stream == voice.streams[expected], "correct audible recording starts for " + expected)
	voice.clear_playback(); sim.events.clear()
func peak(stream: AudioStreamWAV) -> int:
	var maximum := 0
	if stream == null: return maximum
	for offset in range(0, stream.data.size() - 1, 2): maximum = maxi(maximum, absi(stream.data.decode_s16(offset)))
	return maximum
func run() -> void:
	sim = Sim.new(); sim.setup(RulesLoader.load_rules(), "dev", 27, "kestrel", false)
	sound = PaperAudio.new(); sound.voice_language = "zh_CN"; root.add_child(sound)
	await process_frame
	sound.music.stop_all()
	voice = sound.commander; voice.set_process(false); voice.enabled = true
	check(voice.clips.size() == 13 and voice.streams.size() == 13, "all thirteen distinct required reports have local PCM recordings")
	for action: String in voice.streams:
		var clip: AudioStreamWAV = voice.streams[action]
		check(clip != null and clip.get_length() > .5 and clip.data.size() > 10000 and peak(clip) > 100, action + " contains audible speech samples")
	sim.events.clear(); sim.build(0, "kestrel_power")
	sim.BuildingConstruction.advance(sim, 0, "normal", 100, 1.0)
	route("building_ready")
	var building: int = sim._spawn(0, "kestrel_power", Vector2(20,20), false)
	sim._step_building(sim.entities[building], 10, 1.0)
	route("building_complete")
	var barracks: int = sim._spawn(0, "kestrel_barracks", Vector2(19, 26), true)
	check(sim.produce(barracks, "kestrel_rifle").is_empty(), "real barracks accepts a production order")
	sim._step_building(sim.entities[barracks], 100, 1.0)
	route("unit_ready")
	var shooter: int = sim._spawn(0, "kestrel_tank", Vector2(17,20), true)
	var target: int = sim._spawn(1, "rivet_tank", Vector2(23,20), true)
	sim._launch_shot(sim.entities[shooter], sim.entities[target].pos, target, false)
	route("combat")
	for pair: Array in [["kestrel_rifle", "infantry_attacked"], ["kestrel_tank", "vehicle_attacked"], ["kestrel_harvester", "harvester_attacked"], ["kestrel_power", "building_attacked"], ["kestrel_hq", "base_attacked"]]:
		var id: int = sim._spawn(0, pair[0], Vector2(32,30), true)
		sim._add_damage(id, 2); sim._apply_damage(); sim._damage.clear()
		route(pair[1])
	sim._kill_entity(shooter, true); route("unit_lost")
	voice.reset(sim); voice.enabled = true
	voice.observe_visibility(sim)
	check(voice.pending.has("enemy_base"), "visible enemy headquarters triggers enemy base discovery")
	voice._process(.02)
	check(voice.active_action == "enemy_base" and voice.player.stream == voice.streams.enemy_base, "enemy base discovery starts its recorded phrase")
	voice.clear_playback()
	voice.report_clock += 19.0
	var scout: int = sim._spawn(1, "rivet_rifle", Vector2(25,20), true)
	voice.observe_visibility(sim)
	check(voice.pending.has("enemy_seen"), "a newly visible enemy triggers initial contact")
	voice._process(.02)
	check(voice.active_action == "enemy_seen" and voice.player.stream == voice.streams.enemy_seen, "initial contact starts its recorded phrase")
	voice.clear_playback()
	for index in 8: sim._spawn(1, "rivet_tank", Vector2(25+index%3, 21+index/3), true)
	voice.observe_visibility(sim)
	check(voice.pending.has("enemy_mass"), "eight local visible enemy units trigger large force discovery")
	voice._process(.02)
	check(voice.active_action == "enemy_mass" and voice.player.stream == voice.streams.enemy_mass, "large force discovery starts its recorded phrase")
	voice.clear_playback(); voice.report_clock += 30; voice.observe_visibility(sim)
	check(not voice.pending.has("enemy_mass"), "unchanged large force does not announce every cooldown interval")
	var bus := AudioServer.get_bus_index("Paper Commander")
	recording = AudioEffectRecord.new()
	recording.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(0, recording)
	await create_timer(.15).timeout
	voice.reset(sim); voice.enabled = true
	recording.set_recording_active(true)
	voice.request("base_attacked"); voice._process(.02)
	await create_timer(.65).timeout
	recording.set_recording_active(false)
	check(peak(recording.get_recording()) > 100, "actual commander bus emits nonzero PCM into the engine audio mixer")
	sound.set_mix({"commander":0.0})
	await create_timer(.15).timeout
	recording.set_recording_active(true)
	voice.request("unit_ready"); voice._process(.02)
	await create_timer(.25).timeout
	recording.set_recording_active(false)
	check(peak(recording.get_recording()) == 0, "commander zero-volume bus emits silence while ordinary voice mix stays unchanged")
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0)-1)
	recording = null; voice = null
	sound.stop_all(); sound.queue_free(); sound = null; sim = null
	await process_frame; await create_timer(.2).timeout
	print("COMMANDER_EVENT_AUDIO ", JSON.stringify({"checks":checks,"failures":failures}))
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
