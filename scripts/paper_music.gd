extends Node
class_name PaperMusic

# A single PCM player makes scene transitions deterministic and prevents
# overlapping music beds. Fade out, change at silence, then fade in.
const TRACKS := ["menu", "battle", "win", "lose", "draw"]
const MAP_TRACKS := {
	"forest": "battle_forest", "desert": "battle_desert", "snow": "battle_snow",
	"city": "battle_city", "random_city": "battle_random_city", "islands": "battle_islands",
	"campaign": "battle_campaign"
}
const TRANSITION_SECONDS := 1.20
var player: AudioStreamPlayer
var tracks: Dictionary = {}
var scene := "silent"
var requested_scene := "silent"
var requested_track := "silent"
var active_track := "silent"
var map_id := ""
var gain := 0.0
var silent := false

func _ready() -> void:
	player = AudioStreamPlayer.new()
	player.bus = "Paper Music"
	add_child(player)
	var names: Array = TRACKS.duplicate()
	names.append_array(MAP_TRACKS.values())
	for name in names:
		var path := "res://assets/audio/music/%s.wav" % name
		if not ResourceLoader.exists(path): continue
		var source: AudioStreamWAV = load(path)
		if source == null: continue
		var stream: AudioStreamWAV = source.duplicate()
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(round(stream.get_length() * stream.mix_rate))
		tracks[name] = stream
	player.volume_db = -80.0

func set_scene(value: String) -> void:
	requested_scene = value if value in TRACKS else "silent"
	_refresh_requested_track()

# Map selection is independent of menu/result scenes, so loading a save or
# choosing another battlefield updates its music even while scene == battle.
func set_map(value: String) -> void:
	if map_id == value: return
	map_id = value
	_refresh_requested_track()

func track_for_map(value: String) -> String:
	return str(MAP_TRACKS.get(value, "battle"))

func _refresh_requested_track() -> void:
	requested_track = track_for_map(map_id) if requested_scene == "battle" else requested_scene

func set_silent(value: bool) -> void:
	# A map changed while muted may have a newly assigned stopped stream.
	# Fade that stream in on restore; an existing playback keeps its position.
	if silent and not value and player != null and not player.playing: gain = 0.0
	silent = value
	# Bus muting is immediate. Keep playback position while muted so toggling
	# the preference does not repeatedly restart a musical phrase.

func _process(delta: float) -> void:
	if player == null: return
	if active_track != requested_track:
		gain = move_toward(gain, 0.0, delta / TRANSITION_SECONDS)
		if gain <= 0.0:
			player.stop()
			scene = requested_scene
			active_track = requested_track
			player.stream = tracks.get(active_track, null)
			if player.stream != null and not silent: player.play()
	else:
		scene = requested_scene
		gain = move_toward(gain, 1.0 if scene != "silent" else 0.0, delta / TRANSITION_SECONDS)
		if player.stream != null and not player.playing and not silent: player.play()
	player.volume_db = linear_to_db(gain) if gain > 0.0001 else -80.0

func stop_all() -> void:
	requested_scene = "silent"
	requested_track = "silent"
	active_track = "silent"
	scene = "silent"
	gain = 0.0
	if player != null:
		player.stop()
		player.stream = null
