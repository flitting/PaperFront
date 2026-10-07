class_name AudioAnimationPreview
extends "res://scripts/wiki_model_preview.gd"

## Silent, isolated presentation. The browser owns the selected WAV. This
## clock never reads an audio cursor, playback rate, simulation or game events.
const FX_SCENES := {
	"fire_machine_gun": ["fire", "scout"], "fire_rifle": ["fire", "rifle"],
	"fire_anti": ["fire", "anti"], "fire_cannon": ["fire", "tank"],
	"fire_artillery": ["fire", "artillery"], "fire_air": ["fire", "fighter"],
	"fire_energy": ["energy_fire", "tank"], "impact_energy": ["energy_impact", "tank"],
	"creator_hand_attack": ["hand_attack", "creator_hand"], "creator_hand_impact": ["hand_impact", "creator_hand"],
	"impact_small": ["impact", "tank"], "impact_medium": ["impact", "tank"],
	"impact_large": ["impact", "artillery"], "death_vehicle": ["death", "tank"],
	"death_infantry": ["infantry_death", "rifle"], "death_building": ["death", "hq"],
	"deploy_building": ["deploy", "factory"], "construct_building": ["construct", "factory"],
	"bomb_release": ["bomb_release", "attacker"], "rearm": ["rearm", "tank"],
	"engine_loop": ["movement", "tank"], "tracks_loop": ["movement", "tank"],
	"aircraft_loop": ["movement", "fighter"],
	"select": ["select", "tank"], "command": ["command", "tank"],
	"produce": ["produce", "factory"], "delivery": ["delivery", "harvester"],
	"sell": ["sell", "refinery"], "low_power": ["low_power", "power"],
	"result": ["result", "hq"], "error": ["error", "tank"],
	"select_power": ["power_select", "hq"], "power_restored": ["power_restored", "power"], "ui_key": ["command", "tank"], "ui_click": ["command", "tank"]
}
const BUILDING_ART := ["hq", "factory", "refinery", "power"]
const VOICE_SCENES := {"select": "select", "move": "movement", "attack": "fire", "ready": "ready", "return": "return", "combat": "fire", "under_attack": "hit", "death": "death", "low_power": "low_power", "power_restored": "power_restored"}

var catalog_entry: Dictionary = {}
var scene_plan: Dictionary = {}
var animation_time := 0.0
var demo_duration := 3.2
var running := false
var paused := false
var demo_playing: bool:
	get: return running
var demo_age: float:
	get: return animation_time
var demo_paused: bool:
	get: return paused
var scene_kind: String:
	get: return "blank" if scene_plan.get("scene", "none") == "none" else str(scene_plan.scene)
var _home := Vector3.ZERO
var _fx_root: Node3D
var _marker: MeshInstance3D
var _flash: MeshInstance3D
var _bullet: MeshInstance3D
var _particles: Array[MeshInstance3D] = []
var _debris: Array[MeshInstance3D] = []
var _flags: Array[MeshInstance3D] = []
var _extra_model: Dictionary = {}
var _extra_home := Vector3.ZERO
var _lights: Array[DirectionalLight3D] = []
var _light_levels: Array[float] = []
var _radius := 1.0

static func _actor(rules: Dictionary, faction: String, art: String, kind: String) -> String:
	var source: Dictionary = rules.get("buildings" if kind == "building" else "units", {})
	for id: String in source:
		if str(source[id].get("faction", "")) == faction and str(source[id].get("art", "")) == art: return id
	return ""

static func scenario_for_entry(row: Dictionary, rules: Dictionary) -> Dictionary:
	var type: String = str(row.get("type", ""))
	var category: String = str(row.get("category", ""))
	if type == "music" or category in ["ambience", "environment"]: return {"scene": "none", "spec": "", "kind": "", "reason": "music or environment has no unit demonstration"}
	var faction: String = str(row.get("faction", "kestrel"))
	if faction.is_empty(): faction = "kestrel"
	var action: String = str(row.get("action", row.get("family", "")))
	if action in ["fire_energy", "impact_energy", "creator_hand_attack", "creator_hand_impact"]: faction = "sky"
	var scene := ""
	var art := ""
	if type == "voice":
		scene = str(VOICE_SCENES.get(action, ""))
		if action == "death" and category == "infantry": scene = "infantry_death"
		if action == "death" and category == "air": scene = "air_crash"
		art = "power" if category == "system" else "rifle" if category == "infantry" else "fighter" if category == "air" else "tank"
	elif type == "sfx" and FX_SCENES.has(action):
		scene = str(FX_SCENES[action][0]); art = str(FX_SCENES[action][1])
	if scene.is_empty(): return {"scene": "none", "spec": "", "kind": "", "reason": "unregistered future sound, no misleading generic-fire fallback"}
	var kind: String = "building" if art in BUILDING_ART else "unit"
	var spec: String = _actor(rules, faction, art, kind)
	if spec.is_empty(): return {"scene": "none", "spec": "", "kind": "", "reason": "registered actor is unavailable"}
	return {"scene": scene, "spec": spec, "kind": kind, "faction": faction, "category": category, "action": action, "art": art}

func _ready() -> void:
	super._ready()
	custom_minimum_size.y = 210.0
	set_rotation_active(false)
	tooltip_text = "独立动作演示 · 拖动旋转 · 重播重新开始动作"

func _ensure_scene() -> void:
	if scene_plan.is_empty() or str(scene_plan.get("scene", "none")) == "none": return
	super._ensure_scene()

func configure_catalog_entry(row: Dictionary, rules: Dictionary) -> void:
	clear_preview()
	catalog_entry = row.duplicate(true)
	scene_plan = scenario_for_entry(row, rules)
	if scene_plan.scene == "none":
		hide()
		return
	show()
	var definitions: Dictionary = rules.buildings if scene_plan.kind == "building" else rules.units
	super.set_entry(definitions[scene_plan.spec], scene_plan.kind, 0)
	set_rotation_active(false)
	_home = model_node.position
	_radius = maxf(.65, maxf(model_bounds.size.x, model_bounds.size.z) * .35)
	demo_duration = 4.0 if scene_plan.scene in ["movement", "return", "delivery", "produce", "air_crash"] else 3.2
	_create_props(rules)
	_reset_pose()
	# Frame the registered model and local props together, with space for motion.
	var bounds: AABB = _collect_bounds(rotation_pivot)
	rotation_bounds = AABB(bounds.position - Vector3(_radius, .1, _radius), bounds.size + Vector3(_radius * 2.0, .6, _radius * 2.0))
	if scene_plan.scene == "air_crash": rotation_bounds.size.y += _radius * .85
	_frame_camera()
	_request_redraw()
	_sync_activity()

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material

func _shape(kind: String, color: Color, dimensions: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	if kind == "sphere":
		var mesh := SphereMesh.new(); mesh.radius = .5; mesh.height = 1.0; mesh.radial_segments = 10; mesh.rings = 5
		node.mesh = mesh
	elif kind == "disc":
		var mesh := CylinderMesh.new(); mesh.top_radius = .5; mesh.bottom_radius = .5; mesh.height = .012; mesh.radial_segments = 40
		node.mesh = mesh
	else:
		var mesh := BoxMesh.new(); mesh.size = Vector3.ONE
		node.mesh = mesh
	node.scale = dimensions
	node.material_override = _material(color)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx_root.add_child(node)
	return node

func _create_props(rules: Dictionary) -> void:
	_fx_root = Node3D.new(); _fx_root.name = "SilentDemoProps"; rotation_pivot.add_child(_fx_root)
	_marker = _shape("disc", Color(.18, .65, .65, .32), Vector3(_radius * 2.6, 1, _radius * 2.6)); _marker.position.y = .015
	_flash = _shape("sphere", Color(1, .62, .16, .9)); _flash.visible = false
	_bullet = _shape("box", Color(1, .86, .42, .95), Vector3(.32, .04, .04)); _bullet.visible = false
	for index in range(8):
		var particle: MeshInstance3D = _shape("sphere", Color(.42, .37, .32, .36)); particle.visible = false; _particles.append(particle)
	for index in range(10):
		var chip: MeshInstance3D = _shape("box", VOLUME.faction_color(str(scene_plan.faction)), Vector3(.13, .08, .19)); chip.visible = false; _debris.append(chip)
	if scene_plan.scene == "result":
		for side in [-1.0, 1.0]:
			var flag: MeshInstance3D = _shape("box", Color("e7ad42"), Vector3(.6, .35, .05)); flag.position = Vector3(side * _radius, model_bounds.end.y + .4, 0); _flags.append(flag)
	if scene_plan.scene in ["produce", "delivery"]:
		var art: String = "tank" if scene_plan.scene == "produce" else "refinery"
		var kind: String = "unit" if scene_plan.scene == "produce" else "building"
		var spec: String = _actor(rules, str(scene_plan.faction), art, kind)
		var source: Dictionary = rules.units if kind == "unit" else rules.buildings
		if not spec.is_empty():
			_extra_model = VOLUME.create_model(source[spec], kind, 0)
			if not _extra_model.is_empty():
				rotation_pivot.add_child(_extra_model.root)
				_extra_home = Vector3(_radius * 1.8, 0, 0)
				_extra_model.root.position = _extra_home
	for light: DirectionalLight3D in stage.find_children("*", "DirectionalLight3D", true, false):
		_lights.append(light); _light_levels.append(light.light_energy)

func play_demo() -> bool:
	if model_node == null or scene_plan.get("scene", "none") == "none": return false
	animation_time = 0.0; running = true; paused = false
	_reset_pose(); _sync_activity(); return true

func restart_demo() -> bool: return play_demo()

func pause_demo(value: bool) -> void:
	paused = value
	_sync_activity()

func stop() -> void:
	running = false; paused = false
	_sync_activity()

func clear() -> void: clear_preview()

func clear_preview() -> void:
	running = false; paused = false; animation_time = 0.0
	if is_instance_valid(_fx_root): _fx_root.free()
	_fx_root = null; _marker = null; _flash = null; _bullet = null
	_particles.clear(); _debris.clear(); _flags.clear()
	if not _extra_model.is_empty() and is_instance_valid(_extra_model.get("root")): _extra_model.root.free()
	_extra_model.clear()
	for index in range(_lights.size()):
		if is_instance_valid(_lights[index]): _lights[index].light_energy = _light_levels[index]
	_lights.clear(); _light_levels.clear()
	super.clear_preview()
	scene_plan.clear(); catalog_entry.clear()

func _reset_pose() -> void:
	if model_node == null: return
	model_node.position = _home; model_node.rotation = Vector3.ZERO; model_node.scale = Vector3.ONE; model_node.visible = true
	for graphic: MeshInstance3D in model_data.get("meshes", []): graphic.transparency = 0.0
	model_data.clock = 0.0
	if is_volumetric: VOLUME.update_model(model_data, {"id": 0, "state": "idle", "attack_flash": 0.0, "hit_flash": 0.0, "cargo": 500.0, "airborne": false}, 0.0)
	for piece in model_data.get("cargo", []): piece.visible = true
	for node in _particles + _debris: node.visible = false
	if _flash != null: _flash.visible = false
	if _bullet != null: _bullet.visible = false
	if not _extra_model.is_empty(): _extra_model.root.position = _extra_home
	_apply_pose(0.0)

func _sync_activity() -> void:
	var active: bool = _is_preview_active() and running and not paused
	set_process(active)
	if viewport != null: viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED

func _process(delta: float) -> void:
	if not running or paused or not _is_preview_active(): return
	animation_time = minf(demo_duration, animation_time + maxf(0.0, delta))
	_apply_pose(delta)
	if animation_time >= demo_duration: running = false
	_sync_activity()

func _apply_pose(delta: float) -> void:
	if model_node == null: return
	var scene: String = str(scene_plan.scene)
	var t: float = animation_time
	var progress: float = clampf(t / demo_duration, 0.0, 1.0)
	var moving: bool = scene in ["movement", "return", "command", "delivery", "error"]
	var fired: float = maxf(0.0, .25 - absf(t - .35)) if scene in ["fire", "energy_fire", "hand_attack"] else 0.0
	var hit: float = 1.0 if scene == "hit" and t > .3 and t < .65 else 0.0
	if is_volumetric:
		var presentation: Dictionary = {"id": 0, "state": "move" if moving else "attack" if fired > 0 else "idle", "attack_flash": fired, "hit_flash": hit, "cargo": 500.0 * (1.0 - progress) if scene == "delivery" else 500.0, "airborne": bool(model_data.get("aircraft", false))}
		if scene in ["hand_attack", "hand_impact"]:
			presentation["hand_strike"] = maxf(.001, .5 - t) if t < .5 else 0.0
			presentation["hand_recover"] = maxf(0.0, .85 - t) if t >= .5 else 0.0
			presentation["hand_landing"] = Vector2(_radius * .45, 0)
			presentation["hand_contact_height"] = .05
		VOLUME.update_model(model_data, presentation, delta)
	model_node.position = _home
	if moving:
		var travel: float = sin(progress * PI) * _radius * .6
		model_node.position.x += -travel if scene == "return" else travel
		if scene == "error": model_node.position.x = _home.x + minf(travel, _radius * .25)
	if scene in ["deploy", "construct"]: model_node.scale.y = .08 + .92 * smoothstep(0.0, 1.3 if scene == "deploy" else 2.5, t)
	if scene == "ready": model_node.position.y = _home.y - .2 * (1.0 - smoothstep(0.0, .7, t))
	if scene == "sell": model_node.scale = Vector3.ONE * maxf(.02, 1.0 - smoothstep(.4, 2.0, t))
	if scene == "infantry_death":
		model_node.rotation.x = smoothstep(.12, .95, t) * PI * .48
		for graphic: MeshInstance3D in model_data.get("meshes", []): graphic.transparency = smoothstep(1.2, 2.6, t)
	if scene == "air_crash":
		# The real fighter glides and banks down, then breaks at ground contact.
		# Smoke, chips and transforms are private presentation objects only.
		var contact_time := 1.35
		var travel: float = clampf(t / contact_time, 0.0, 1.0)
		model_node.position = _home + Vector3(_radius * .7 * travel, _radius * .85 * (1.0 - travel * travel), 0)
		model_node.rotation.z = -.06 - .3 * travel
		model_node.rotation.x = .12 * travel
		model_node.visible = t < contact_time
		_flash.visible = false
		for index in range(_particles.size()):
			var emitted: float = .05 + float(index) * .11
			var age: float = t - emitted
			var at: float = clampf(emitted / contact_time, 0.0, 1.0)
			var puff: MeshInstance3D = _particles[index]
			puff.visible = age > 0.0 and age < 2.4
			puff.position = _home + Vector3(_radius * .7 * at - age * .08, _radius * .85 * (1.0 - at * at) + age * .18, sin(float(index) * 2.1) * .04)
			puff.scale = Vector3.ONE * _radius * (.1 + maxf(age, 0.0) * .18)
			var smoke: StandardMaterial3D = puff.material_override
			smoke.albedo_color = Color(.32, .35, .38, maxf(0.0, .35 * (1.0 - maxf(age, 0.0) / 2.4)))
		var broken: float = maxf(0.0, t - contact_time)
		for index in range(_debris.size()):
			var chip: MeshInstance3D = _debris[index]
			var angle: float = TAU * float(index) / _debris.size()
			chip.visible = broken > 0.0
			chip.position = _home + Vector3(_radius * .7 + cos(angle) * minf(broken, 1.1) * _radius * .65, maxf(.05, broken * .8 - broken * broken * 1.3), sin(angle) * minf(broken, 1.1) * _radius * .65)
			chip.rotation = Vector3(broken * 3.0, angle, broken * 4.0)
	if scene == "produce" and not _extra_model.is_empty(): _extra_model.root.position = _extra_home + Vector3(_radius * smoothstep(.3, 2.5, t), 0, 0)
	if scene == "delivery":
		var cargo: Array = model_data.get("cargo", [])
		for index in range(cargo.size()): cargo[index].visible = float(index) / maxf(1, cargo.size()) < 1.0 - progress
	if scene in ["low_power", "power_restored", "power_select"]:
		for index in range(_lights.size()):
			var energy: float = .28 if scene == "low_power" else .3 + .7 * smoothstep(.15, 1.2, t) if scene == "power_restored" else .85 + .15 * sin(t * 8)
			_lights[index].light_energy = _light_levels[index] * energy
	if _marker != null:
		_marker.visible = scene in ["select", "command", "ready", "rearm", "error", "power_select", "power_restored", "low_power"]
		_marker.position = Vector3(_radius * .8 if scene in ["command", "error"] else 0.0, .015, 0.0)
		var material: StandardMaterial3D = _marker.material_override
		material.albedo_color = Color(.8, .18, .14, .35) if scene in ["error", "low_power"] else Color(.18, .65, .65, .22 + .15 * sin(t * 8))
	if scene == "rearm": model_node.rotation.z = sin(t * 16) * .015 * (1 - progress)
	if scene == "result":
		for flag in _flags: flag.rotation.z = sin(t * 5) * .08
	if scene in ["energy_fire", "energy_impact", "hand_attack", "hand_impact"]:
		var glow: StandardMaterial3D = _flash.material_override
		glow.albedo_color = Color(.25, .9, 1.0, .75)
		var beam: StandardMaterial3D = _bullet.material_override
		beam.albedo_color = Color(.35, .95, 1.0, .85)
		for spark: MeshInstance3D in _particles:
			var ion: StandardMaterial3D = spark.material_override
			ion.albedo_color = Color(.2, .75, 1.0, ion.albedo_color.a)
	if scene == "bomb_release":
		_bullet.visible = t > .25 and t < 1.4
		_bullet.scale = Vector3(.15, .3, .15)
		_bullet.position = Vector3(0, model_bounds.end.y - maxf(0.0, t - .25) * _radius * 1.3, 0)
	if scene in ["fire", "energy_fire"]:
		var muzzle: Vector3 = rotation_pivot.to_local(VOLUME.muzzle_world(model_data)) if is_volumetric and model_data.get("muzzle") != null else Vector3(_radius * .45, model_bounds.end.y * .6, .05)
		_flash.visible = fired > .06; _flash.position = muzzle; _flash.scale = Vector3.ONE * (.15 + fired * .8)
		_bullet.visible = t > .35 and t < .6; _bullet.position = muzzle + Vector3(maxf(0, t - .35) * _radius * 8, 0, 0)
	if scene in ["impact", "death", "hit", "energy_impact", "hand_attack", "hand_impact"]:
		var blast: float = maxf(0.0, t - (.5 if scene in ["hand_attack", "hand_impact"] else .32))
		_flash.visible = blast > 0 and blast < .24
		_flash.position = Vector3(0, model_bounds.end.y * .4, 0)
		_flash.scale = Vector3.ONE * _radius * (.5 + blast * 4)
		if scene == "death": model_node.visible = t < .43
		for index in range(_particles.size()):
			var angle: float = TAU * float(index) / _particles.size()
			var node: MeshInstance3D = _particles[index]
			node.visible = blast > 0 and blast < 2.4
			node.position = Vector3(cos(angle) * blast * _radius * .35, .2 + blast * .45, sin(angle) * blast * _radius * .35)
			node.scale = Vector3.ONE * _radius * (.15 + blast * .18)
			var material: StandardMaterial3D = node.material_override
			material.albedo_color.a = maxf(0, .34 * (1 - blast / 2.4))
		for index in range(_debris.size()):
			var angle: float = TAU * float(index) / _debris.size()
			var node: MeshInstance3D = _debris[index]
			node.visible = scene in ["death", "impact", "hand_impact"] and blast > 0
			node.position = Vector3(cos(angle) * minf(blast, 1.1) * _radius, maxf(.05, blast * 1.3 - blast * blast * 1.5), sin(angle) * minf(blast, 1.1) * _radius)
			node.rotation = Vector3(blast * 3, angle, blast * 4)

func _draw() -> void:
	if scene_plan.get("scene", "none") != "none": super._draw()

func _exit_tree() -> void:
	stop()
	super._exit_tree()
