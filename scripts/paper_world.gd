extends Node3D
class_name PaperWorld

## A visual reader of the simulation. Rendering never changes rules or commands.
## Faction vehicles and aircraft are solid models; infantry uses distinct folded-paper figures.
const CAMERA_OCCLUSION = preload("res://scripts/camera_occlusion.gd")
const MAP = preload("res://scripts/map_data.gd")
const VOLUME = preload("res://scripts/volume_models.gd")
const LANDSCAPE = preload("res://scripts/landscape.gd")
const SCAFFOLD = preload("res://scripts/construction_scaffold.gd")
const WALL_CONNECTIONS = preload("res://scripts/wall_connections.gd")
const MODEL_LOD = preload("res://scripts/model_lod.gd")
const AIR_VISUAL = preload("res://scripts/aircraft_visual_motion.gd")
const EFFECT_LOD = preload("res://scripts/battlefield_effect_lod.gd")
const BATTLEFIELD_DAMAGE = preload("res://scripts/battlefield_damage.gd")
const PAPER_CIVILIANS = preload("res://assets/civilians/paper_civilians.gd")
var landscape: Node3D
const CARD_DIR = "res://assets/cards/"
const TEAM_COLORS = VOLUME.PLAYER_COLORS
const EDGE_COLOR = Color("9b7950")

var startup_profile:Dictionary={}
var sim: WarSimulation
var camera: Camera3D
var contours: Dictionary = {}
var models: Dictionary = {}
var _wall_masks: Dictionary = {}
var _rail_shapes: Dictionary = {}
var card_cache: Dictionary = {}
var material_cache: Dictionary = {}
var infantry_border_shader: Shader
var vehicle_border_shader: Shader
var shells: Array[Node3D] = []
var effects: Array[Dictionary] = []
var _beam_channels: Dictionary = {}
var _emp_status_batch: Dictionary = {}
var ghosts: Array[Dictionary] = []
const CREATOR_CRUSH = preload("res://scripts/creator_crush_effects.gd")
var tracks: Array[Dictionary] = []
var craters: Array[Dictionary] = []
var crater_mesh: ArrayMesh
var crater_batch: Dictionary = {}
var _destroyed_this_frame: Dictionary = {}
var destruction_rng := RandomNumberGenerator.new()
var last_scatter_pattern: int = -1
var air_trails: Array[Dictionary] = []
const AIR_TRAIL_LIFETIME: float = 2.4
var _corpse_materials: Dictionary = {}
var _fade_shadow_batch: Dictionary = {}
var _air_trail_batches: Array = []
var cloud_shadows: Array[Dictionary] = []
var air_crash_smoke: Array[Dictionary] = []
var _air_crash_serial: int = 0
const MAX_AIR_CRASHES: int = 12
const AIR_CRASH_MAX_LIFE: float = 6.0
var _air_terrain_margin: float = -1.0
var _retired_air_offsets: Dictionary = {}
var _projectile_air_offsets: Dictionary = {}
const TRACK_LIFETIME: float = 32.0
const CRATER_LIFETIME: float = 110.0
var guide_mesh: ImmediateMesh
var guide_node: MeshInstance3D
var elapsed: float = 0.0
var frame_delta: float = 0.0
var camera_yaw: float = 999.0
var placement_node: Node3D
var placement_key: String = ""
var ring_mesh: ArrayMesh
var hand_owner_mesh: ArrayMesh
var shadow_mesh: ArrayMesh
var square_mesh: ArrayMesh
var explosion_mesh: ArrayMesh
var shell_mesh: ArrayMesh
var smoke_mesh: SphereMesh
var effect_spheres: Array[Mesh] = []
var _chip_lods: Dictionary = {}
var _performance_blast_lods: Array = []
var _performance_smoke_lods: Array = []
var _air_crash_smoke_lods: Array = []
var _fragment_warm_queue: Array = []
var _fragment_warm_sources: Dictionary = {}
var batches: Dictionary = {}
var batch_lookup: Dictionary = {}
var profile_enabled: bool = false
var profile_last: Dictionary = {}
var _uploaded_transforms: int = 0
var _uploaded_colors:int=0
var _submitted_transforms: int = 0
var _visible_entities: int = 0
var _culled_entities: int = 0
var _view_planes: Array[Plane] = []
var _plane_sides: Array[float] = []
var _view_key:Array=[]
var _guide_signature: Array = []
var track_materials: Array[Material] = []
var debris_meshes:Array[BoxMesh]=[]
var particle_mesh_cache:Dictionary={}
var projectile_material:Material
var energy_projectile_material:Material
var _warm_particle_batches:bool=false
var steam_batches:Array[Dictionary]=[]
var quality_policy:String="native"
var lod_enabled: bool = true
var lod_override: int = -1 # Only diagnostic captures explicitly force a tier.
var _lod_view: Dictionary = {}
var _syncing_entities: bool = false
var _lod_counts: PackedInt32Array = PackedInt32Array([0,0,0])
var _paper_lod_cache: Dictionary = {}
var _placement_lod: Dictionary = {}
var data_effects:Array[Dictionary]=[]
var data_corpses:Array[Dictionary]=[]
var model_pool:Dictionary={}
var _fx_spawned:int=0
var _models_reused:int=0
var _models_created:int=0
var _performance_shell_batch:Dictionary={}
var _performance_blast_batch:Dictionary={}
var _performance_smoke_batch:Dictionary={}
var native_kernels_enabled: bool = OS.get_environment("PAPER_FRONT_DISABLE_NATIVE") != "1"
var _kernels: RefCounted = ClassDB.instantiate("PaperFrontKernels") if ClassDB.class_exists("PaperFrontKernels") else null
var _recording_model: bool = false
var _model_submissions: Array = []
var _cached_entities: int = 0
var native_batches_enabled:bool=OS.get_environment("PAPER_FRONT_SCRIPT_BATCHES")!="1" and ClassDB.class_exists("PaperFrontRenderBatch")
var native_bulk_buffers_enabled:bool=OS.get_environment("PAPER_FRONT_BATCH_SETTERS")!="1" and RenderingServer.get_current_rendering_method()!="gl_compatibility"
var _active_batches:int=0
var _native_world_cache_active:bool=false
var native_world_sync_enabled: bool = OS.get_environment("PAPER_FRONT_SCRIPT_WORLD") != "1"
var pose_meshes_enabled: bool = OS.get_environment("PAPER_FRONT_RENDER_NODES") != "1"
var _fog_memory: SightMemory
var _fog_texture: ImageTexture
var _fog_material: ShaderMaterial
var _fog_node: MeshInstance3D
var _fog_next_refresh: float = 0.0


func _enter_tree() -> void:
	destruction_rng.randomize()
	BATTLEFIELD_DAMAGE.acquire_world()
func _exit_tree() -> void:
	_fragment_warm_queue.clear()
	_fragment_warm_sources.clear()
	BATTLEFIELD_DAMAGE.release_world()
	if BATTLEFIELD_DAMAGE.world_users<=0: CREATOR_CRUSH.fragments.clear()

## Cosmetic exploration belongs to the local view. Current visibility always
## comes from TeamVision; this cache never changes contacts or last-known data.
class SightMemory:
	extends RefCounted
	const CELL_SIZE: int = 2
	const BUCKET_SIZE: int = 16
	var map_size: int = 0
	var width: int = 0
	var pixels := PackedByteArray()
	var bucket_signatures: Dictionary = {}
	var queries: int = 0
	var updates: int = 0

	func initialize(size: int) -> void:
		map_size = size
		width = ceili(float(size) / CELL_SIZE)
		pixels.resize(width * width * 2)
		pixels.fill(0)
		bucket_signatures.clear()
		queries = 0
		updates = 0

	func refresh(simulation) -> bool:
		queries = 0
		if not simulation.vision_enabled: return false
		var next: Dictionary = {}
		if not simulation._vision_observers.is_empty():
			for bucket: Vector2i in simulation._vision_observers[0]:
				var signature: Array = []
				for observer: Dictionary in simulation._vision_observers[0][bucket]:
					signature.append_array([observer.pos, observer.radius_sq, observer.air, observer.eye_height])
				next[bucket] = signature
		var changed_buckets: Dictionary = {}
		for bucket: Vector2i in next:
			if not bucket_signatures.has(bucket) or bucket_signatures[bucket] != next[bucket]: changed_buckets[bucket] = true
		for bucket: Vector2i in bucket_signatures:
			if not next.has(bucket): changed_buckets[bucket] = true
		bucket_signatures = next
		if simulation.native_kernels_enabled and simulation._kernels != null and simulation._kernels.has_method("refresh_sight_mask"):
			var observers: Dictionary = simulation._vision_observers[0] if not simulation._vision_observers.is_empty() else {}
			var result: Dictionary = simulation._kernels.refresh_sight_mask(simulation.map,observers,changed_buckets,pixels)
			pixels=result.pixels
			queries=int(result.queries)
			if bool(result.changed):updates+=1
			return bool(result.changed)
		var changed: bool = false
		var cells_per_bucket: int = BUCKET_SIZE / CELL_SIZE
		for bucket: Vector2i in changed_buckets:
			for z: int in range(maxi(0, bucket.y * cells_per_bucket), mini(width, (bucket.y + 1) * cells_per_bucket)):
				for x: int in range(maxi(0, bucket.x * cells_per_bucket), mini(width, (bucket.x + 1) * cells_per_bucket)):
					var offset: int = (z * width + x) * 2
					var visible: bool = false
					if next.has(bucket):
						var point := Vector2(minf((x + .5) * CELL_SIZE, map_size - .001), minf((z + .5) * CELL_SIZE, map_size - .001))
						var domain: String = "naval" if MAP.terrain_at(simulation.map, point) == MAP.WATER else "ground"
						visible = simulation.position_visible_to(0, point, domain)
						queries += 1
					var value: int = 255 if visible else 0
					if pixels[offset] != value:
						pixels[offset] = value
						changed = true
					if visible and pixels[offset + 1] == 0:
						pixels[offset + 1] = 255
						changed = true
		if changed: updates += 1
		return changed

	func image() -> Image:
		return Image.create_from_data(width, width, false, Image.FORMAT_RG8, pixels)

	func explored_bytes() -> PackedByteArray:
		var result := PackedByteArray()
		result.resize(width * width)
		for index: int in result.size(): result[index] = pixels[index * 2 + 1]
		return result

	func restore_explored(data: PackedByteArray) -> bool:
		if data.size() != width * width: return false
		for value: int in data:
			if value != 0 and value != 255: return false
		for index: int in data.size():
			pixels[index * 2] = 0
			pixels[index * 2 + 1] = data[index]
		bucket_signatures.clear()
		return true


func setup(simulation: WarSimulation, view_camera: Camera3D) -> void:
	var setup_started: int = Time.get_ticks_usec()
	_prepare_setup(simulation, view_camera)
	var preload_started: int = Time.get_ticks_usec()
	_prewarm_cards()
	var landscape_started: int = Time.get_ticks_usec()
	landscape = LANDSCAPE.build(sim)
	_finish_setup(setup_started, preload_started, landscape_started)


func setup_with_progress(simulation: WarSimulation, view_camera: Camera3D, progress: Callable) -> void:
	if not progress.is_valid():
		setup(simulation, view_camera)
		return
	var setup_started: int = Time.get_ticks_usec()
	await progress.call(0.0, "准备战场资源")
	_prepare_setup(simulation, view_camera)
	var preload_started: int = Time.get_ticks_usec()
	await progress.call(0.1, "加载部队图像")
	await _prewarm_cards_with_progress(progress)
	var landscape_started: int = Time.get_ticks_usec()
	await progress.call(0.2, "加载地图")
	landscape = await LANDSCAPE.build_with_progress(sim, _report_landscape_progress.bind(progress))
	_finish_setup(setup_started, preload_started, landscape_started)
	await progress.call(1.0, "战场加载完成")


func _report_landscape_progress(fraction: float, stage: String, progress: Callable) -> void:
	await progress.call(0.2 + clampf(fraction, 0.0, 1.0) * 0.75, stage)


func _prepare_setup(simulation: WarSimulation, view_camera: Camera3D) -> void:
	if _kernels!=null:
		_kernels.clear_world_models()
		_kernels.clear_render_batches()
	_native_world_cache_active=false
	sim = simulation
	camera = view_camera
	if _kernels != null: _kernels.set_world_profiling("--profile-native-world" in OS.get_cmdline_user_args())
	for child in get_children():
		child.queue_free()
	models.clear()
	_wall_masks.clear()
	_rail_shapes.clear()
	model_pool.clear()
	data_effects.clear()
	data_corpses.clear()
	shells.clear()
	effects.clear()
	_beam_channels.clear()
	_emp_status_batch.clear()
	ghosts.clear()
	tracks.clear()
	air_trails.clear()
	air_crash_smoke.clear()
	_air_terrain_margin=-1.0
	_retired_air_offsets.clear();_projectile_air_offsets.clear()
	cloud_shadows.clear()
	_corpse_materials.clear()
	craters.clear()
	_destroyed_this_frame.clear()
	_fragment_warm_queue.clear()
	_fragment_warm_sources.clear()
	guide_node = null
	batches.clear()
	batch_lookup.clear()
	_guide_signature.clear()
	_view_key.clear()
	placement_node = null
	placement_key = ""
	_fog_memory = null
	_fog_texture = null
	_fog_material = null
	_fog_node = null
	_fog_next_refresh = 0.0
	contours = JSON.parse_string(FileAccess.get_file_as_string(CARD_DIR + "contours.json"))
	ring_mesh = _disc(1.0, 0.89, Color.WHITE, 36)
	hand_owner_mesh = _disc(1.0, 0.97, Color.WHITE, 36)
	shadow_mesh = _disc(1.0, 0.0, Color(0.23, 0.18, 0.12, 0.23), 24)
	square_mesh = _flat_quad()
	explosion_mesh = _star_mesh()
	shell_mesh = _dart_mesh()
	smoke_mesh = SphereMesh.new()
	smoke_mesh.radius = 0.5
	smoke_mesh.height = 1.0
	smoke_mesh.radial_segments = 8
	smoke_mesh.rings = 4
	var far_smoke := SphereMesh.new()
	far_smoke.radius=.5;far_smoke.height=1.0;far_smoke.radial_segments=6;far_smoke.rings=2
	effect_spheres=[smoke_mesh,far_smoke,EFFECT_LOD.octahedron()]
	_chip_lods.clear()
	track_materials.clear()
	for bucket in range(8):track_materials.append(_material(Color(.30,.24,.15,float(bucket)*.024),true))
	crater_mesh = _crater_mesh()
	crater_batch = _batch_descriptor(crater_mesh,null,false,true)
	var fade_shadow_material: StandardMaterial3D=_material(Color.WHITE,true).duplicate()
	fade_shadow_material.vertex_color_use_as_albedo=true
	fade_shadow_material.vertex_color_is_srgb=true
	_fade_shadow_batch=_batch_descriptor(shadow_mesh,fade_shadow_material,false,true)
	_prepare_air_trail_batches()
	debris_meshes.clear()
	for variant in range(3):
		var chip:=BoxMesh.new()
		chip.size=Vector3(.12,.09,.22)*(1.0+float(variant)*.4)
		debris_meshes.append(chip)
	projectile_material=_material(Color("f4d99a"))
	energy_projectile_material=_material(Color("b4a0ed"))
	_performance_shell_batch=_batch_descriptor(shell_mesh,projectile_material)
	particle_mesh_cache.clear()
	_particle_material(_blast_source_material(),"blast")
	_particle_material(_smoke_source_material(false),"smoke")
	_particle_material(_material(Color.WHITE,true),"shock")
	_performance_blast_batch=_batch_descriptor(smoke_mesh,_particle_material(_blast_source_material(),"blast"),false,true)
	_performance_smoke_batch=_batch_descriptor(smoke_mesh,_particle_material(_smoke_source_material(false),"smoke"),false,true)
	_performance_blast_lods.clear();_performance_smoke_lods.clear()
	for mesh: Mesh in effect_spheres:
		_performance_blast_lods.append(_batch_descriptor(mesh,_particle_material(_blast_source_material(),"blast"),false,true))
		_performance_smoke_lods.append(_batch_descriptor(mesh,_particle_material(_smoke_source_material(false),"smoke"),false,true))
	_prepare_air_crash_smoke_batches()
	_warm_particle_batches=true
	steam_batches.clear()
	for bucket in range(7):
		var key:String="workshop_steam_%d" % bucket
		if not material_cache.has(key):
			var material:=StandardMaterial3D.new()
			material.albedo_color=Color(.82,.80,.75,float(bucket)*.1)
			material.roughness=1.0
			material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
			material_cache[key]=material
		steam_batches.append(_batch_descriptor(smoke_mesh,material_cache[key]))


func _finish_setup(setup_started: int, preload_started: int, landscape_started: int) -> void:
	add_child(landscape)
	camera_yaw = 999.0
	if landscape.has_method("configure_quality"):landscape.configure_quality(quality_policy)
	_restore_scenery_detail()
	_configure_civilian_paper()
	_setup_fog()
	startup_profile={"resource_preparation_ms":(preload_started-setup_started)/1000.0,"card_preload_ms":(landscape_started-preload_started)/1000.0,"landscape_build_ms":(Time.get_ticks_usec()-landscape_started)/1000.0,"total_ms":(Time.get_ticks_usec()-setup_started)/1000.0}


func _configure_civilian_paper() -> void:
	# Keep landscape's authored routes/poses and its three existing MultiMeshes.
	# Replacing only these meshes preserves every environment bake's source hash.
	for group: Dictionary in landscape._civilian_batches:
		var people: Array = group.people
		if people.is_empty(): continue
		var variants: Array[Mesh] = PAPER_CIVILIANS.lod_meshes(int(people[0].get("variant",0)))
		group.multi.mesh = variants[0]
		for record: Dictionary in landscape.lod_records:
			if record.node is MultiMeshInstance3D and record.node.multimesh == group.multi:
				var old_center: Vector3 = record.source.get_aabb().get_center()
				record.source = variants[0]
				record.meshes = variants
				record.center.y += variants[0].get_aabb().get_center().y-old_center.y
				record.diameter = variants[0].get_aabb().size.length()
				record.baked = true
				record.tier = -1
	PAPER_CIVILIANS.face_camera(camera)


func _setup_fog() -> void:
	_fog_memory = SightMemory.new()
	_fog_memory.initialize(int(sim.map.size))
	_fog_memory.refresh(sim)
	_fog_texture = ImageTexture.create_from_image(_fog_memory.image())
	_fog_material = ShaderMaterial.new()
	_fog_material.shader = preload("res://assets/fog/battlefield_fog.gdshader")
	_fog_material.render_priority = 120
	_fog_material.set_shader_parameter("sight_mask", _fog_texture)
	_fog_material.set_shader_parameter("map_size", float(sim.map.size))
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	_fog_node = MeshInstance3D.new()
	_fog_node.name = "BattlefieldSightFilter"
	_fog_node.mesh = quad
	_fog_node.material_override = _fog_material
	_fog_node.extra_cull_margin = 16384.0
	_fog_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fog_node.ignore_occlusion_culling = true
	_fog_node.visible = sim.vision_enabled
	add_child(_fog_node)
	_fog_next_refresh = sim.time + .2


func _sync_fog() -> void:
	if _fog_material == null: return
	if profile_enabled:
		profile_last.fog_us = 0
		profile_last.fog_queries = 0
		profile_last.fog_texture_updates = _fog_memory.updates
	_fog_node.visible = sim.vision_enabled
	if not sim.vision_enabled: return
	if sim.time + .000001 < _fog_next_refresh: return
	_fog_next_refresh = sim.time + .2
	var started: int = Time.get_ticks_usec() if profile_enabled else 0
	if _fog_memory.refresh(sim): _fog_texture.update(_fog_memory.image())
	if profile_enabled:
		profile_last.fog_us = Time.get_ticks_usec() - started
		profile_last.fog_queries = _fog_memory.queries
		profile_last.fog_texture_updates = _fog_memory.updates


func export_visual_memory() -> Dictionary:
	if _fog_memory == null: return {}
	return {"version": 1, "map_size": int(sim.map.size), "map_seed": int(sim.map.get("seed", 0)), "map_mode": str(sim.map.get("mode", "")), "cell_size": SightMemory.CELL_SIZE, "explored": Marshalls.raw_to_base64(_fog_memory.explored_bytes())}


func restore_visual_memory(data: Dictionary) -> bool:
	if _fog_memory == null: return false
	# JSON stores numbers as floats; both numeric forms must match the actual
	# map exactly. Reject arrays, objects and strings before any conversion.
	var identity: Dictionary = {"version":1,"map_size":int(sim.map.size),"map_seed":int(sim.map.get("seed",0)),"cell_size":SightMemory.CELL_SIZE}
	for key: String in identity:
		if not data.has(key) or typeof(data[key]) not in [TYPE_INT,TYPE_FLOAT]:return false
		if data[key] != identity[key]:return false
	if typeof(data.get("map_mode")) != TYPE_STRING or data.map_mode != str(sim.map.get("mode", "")): return false
	if typeof(data.get("explored")) != TYPE_STRING:return false
	var encoded: String = data.explored
	var expected: int = _fog_memory.width * _fog_memory.width
	if encoded.length() != ceili(float(expected) / 3.0) * 4: return false
	if not _fog_memory.restore_explored(Marshalls.base64_to_raw(encoded)): return false
	_fog_memory.refresh(sim)
	_fog_texture.update(_fog_memory.image())
	_fog_next_refresh = sim.time + .2
	return true


func configure_quality(policy:String) -> void:
	quality_policy=policy if policy in ["native","balanced","performance"] else "native"
	for model in models.values(): model.erase("visual_signature")
	if quality_policy=="performance":
		for effect in effects:effect.root.queue_free()
		effects.clear()
		_beam_channels.clear()
		# An aircraft already falling remains visible when the quality preset changes.
		for index: int in range(ghosts.size()-1,-1,-1):
			if ghosts[index].kind!="air_crash":
				_pool_model(ghosts[index].model);ghosts.remove_at(index)
		var crashes: Array=ghosts.filter(func(ghost):return ghost.kind=="air_crash")
		while crashes.size()>6:
			var oldest: Dictionary=crashes.pop_front()
			_retire_aircraft_crash(oldest);ghosts.erase(oldest)
		tracks.clear()
	if landscape!=null and landscape.has_method("configure_quality"):
		landscape.configure_quality(quality_policy)
		_restore_scenery_detail()
	for model in models.values(): _prepare_quality_batches(model)


func _prepare_quality_batches(model:Dictionary) -> void:
	if not model.volumetric: return
	if bool(model.get("direct_skinned", false)):
		if not model.has("skinned_lods"):
			model.skinned_lods = []
			for node in model.volume.meshes:
				model.skinned_lods.append({"node":node,"source":node.mesh,"meshes":[node.mesh,VOLUME.quality_mesh(node.mesh,int(model.team),"far"),VOLUME.quality_mesh(node.mesh,int(model.team),"extreme")]})
		return
	for part in model.render_parts:
		if part.has("lod_batches"): continue
		part.lod_batches = _lod_batches(part.node.mesh,part.node.material_override,int(model.team))
		part.quality_batch = part.lod_batches[1]
		part.performance_batch = part.lod_batches[2]
		if part.has("ink_batch"):
			part.ink_lod_batches = _lod_batches(part.ink_batch.multi.mesh,_vehicle_border_material(false),int(model.team),false)
			part.paper_lod_batches = _lod_batches(part.paper_batch.multi.mesh,_vehicle_border_material(true),int(model.team),false)
			part.quality_ink_batch = part.ink_lod_batches[1]
	if not model.has("cargo_lod_batches"):
		model.cargo_lod_batches = []
		for piece in model.volume.get("cargo",[]): model.cargo_lod_batches.append(_lod_batches(piece.mesh,null,int(model.team)))

func _lod_batches(source: Mesh, material: Material, team: int, shadows: bool = true) -> Array:
	return [_batch_descriptor(source,material,shadows),
		_batch_descriptor(VOLUME.quality_mesh(source,team,"far"),material,shadows),
		_batch_descriptor(VOLUME.quality_mesh(source,team,"extreme"),material,shadows)]


func _restore_scenery_detail() -> void:
	# Landscape owns the original destruction slots and switches their meshes;
	# all quality presets preserve complete near models and painted materials.
	if landscape.has_method("sync_lods"):
		landscape.scenery_lod_enabled = lod_enabled
		landscape.sync_lods(camera)


func _prewarm_cards() -> void:
	# First shots and movement do not incur a texture import/mesh-building stall.
	for spec in sim.rules.units.values():
		_prewarm_unit_cards(spec)


func _prewarm_cards_with_progress(progress: Callable) -> void:
	var specs: Array = sim.rules.units.values()
	var completed: int = 0
	var yielded_at: int = Time.get_ticks_usec()
	for spec in specs:
		_prewarm_unit_cards(spec)
		completed += 1
		if Time.get_ticks_usec() - yielded_at >= 24000:
			await progress.call(0.1 + 0.1 * float(completed) / maxi(1, specs.size()), "加载部队图像")
			yielded_at = Time.get_ticks_usec()


func _prewarm_unit_cards(spec: Dictionary) -> void:
	if VOLUME.supports(spec, "unit"): return
	var dimensions: Vector2 = _dimensions(spec, "unit")
	for state in ["idle", "move", "attack", "hit", "death"]:
		for team in range(maxi(2, sim.factions.size())):
			_card(VOLUME.art_faction(spec) + "_" + spec.art + "_" + state, dimensions.x, dimensions.y, _texture_path(spec, state), team)


func sync(delta: float, selection: Array, placement: Dictionary = {}) -> void:
	if sim == null or camera == null:
		return
	elapsed += delta
	frame_delta = delta
	var started_us:int=Time.get_ticks_usec() if profile_enabled else 0
	var stage_us:int=started_us
	_uploaded_transforms=0
	_uploaded_colors=0
	_submitted_transforms=0
	_visible_entities=0
	_culled_entities=0
	_fx_spawned=0
	_models_reused=0
	_models_created=0
	_cached_entities=0
	_lod_counts.fill(0)
	_lod_view = MODEL_LOD.view(camera)
	BATTLEFIELD_DAMAGE.finalize_ready(1000)
	_warm_fragment_batches(1000)
	_cache_view_planes()
	_prepare_aircraft_motion()
	_begin_batches()
	_destroyed_this_frame.clear()
	_retired_air_offsets.clear()
	for event: Dictionary in sim.events:
		if event.get("kind","")=="carrier_recover" and models.has(int(event.get("aircraft",-1))):models[int(event.aircraft)].embarked=true
		if event.get("kind", "") != "death" or not models.has(int(event.get("id",-1))): continue
		var dying: Dictionary=models[int(event.id)]
		dying.death_style=str(event.get("death_style",""))
		dying.death_velocity=event.get("velocity",Vector2.ZERO)
		dying.death_heading=float(event.get("heading",event.get("alpha",0.0)))
		dying.death_flight_height=float(event.get("flight_height",event.get("height",0.0)))
		if not bool(event.get("destroyed",true)): dying.removed_without_burst=true
	CREATOR_CRUSH.mark_deaths(self)
	camera_yaw = atan2(camera.global_basis.z.x, camera.global_basis.z.z)
	PAPER_CIVILIANS.face_camera(camera)
	landscape.sync_resources(sim)
	if landscape.has_method("sync_lods"):
		landscape.scenery_lod_enabled = lod_enabled
		landscape.sync_lods(camera)
	_sync_wall_connections()
	_sync_rail_shapes()
	if profile_enabled:
		profile_last={"landscape_us":Time.get_ticks_usec()-stage_us}
		stage_us=Time.get_ticks_usec()
	_syncing_entities = true
	if native_kernels_enabled and native_world_sync_enabled and _kernels != null:
		if not _native_world_cache_active:_kernels.clear_world_models()
		_native_world_cache_active=true
		var selected_ids:Dictionary={}
		for id in selection:selected_ids[id]=true
		# The old performance pose path omits authored animation and border
		# passes. Retain native lifecycle/culling, with the complete model path.
		var counts:Dictionary=_kernels.sync_world_entities(self,sim.entities,models,selected_ids,sim.map,"native",elapsed,camera_yaw,float(sim.rules.economy.harvester_capacity),float(sim.rules.economy.construction_animation))
		_visible_entities=counts.visible;_culled_entities=counts.culled;_cached_entities=counts.cached
		_submitted_transforms+=int(counts.submitted)
		if profile_enabled:
			for key in counts:
				if str(key).ends_with("_us"):profile_last[key]=counts[key]
	else:
		if _native_world_cache_active and _kernels!=null:_kernels.clear_world_models()
		_native_world_cache_active=false
		_sync_entities_script(selection)
	_syncing_entities = false
	if profile_enabled:
		profile_last.entities_us=Time.get_ticks_usec()-stage_us
		stage_us=Time.get_ticks_usec()
	_sync_projectiles()
	_read_events()
	_update_effects(delta)
	_update_deaths(delta)
	if _warm_particle_batches:
		var pos:Vector3=camera.global_position-camera.global_basis.z*(camera.near+1.0)
		var transform:=Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*.001),pos)
		# Compile the same particle pipelines during initial warmup. Alpha zero
		# keeps these cache-only instances absent from the visible battlefield.
		for family in ["blast","smoke","flat"]:
			for mesh: Mesh in ([_particle_mesh(ring_mesh)] if family=="flat" else effect_spheres):
				_batch(mesh,transform,material_cache["particle_instances_"+family],false,Color(0,0,0,0))
		for batch: Dictionary in _air_crash_smoke_lods:_append_batch(batch,transform,Color(0,0,0,0))
		_warm_particle_batches=false
	if profile_enabled:
		profile_last.effects_us=Time.get_ticks_usec()-stage_us
		stage_us=Time.get_ticks_usec()
	_update_placement(placement)
	if profile_enabled:
		profile_last.placement_us=Time.get_ticks_usec()-stage_us
		stage_us=Time.get_ticks_usec()
	_flush_batches()
	if profile_enabled:
		profile_last.flush_us=Time.get_ticks_usec()-stage_us
	_sync_fog()
	if profile_enabled:
		profile_last.total_us=Time.get_ticks_usec()-started_us
		profile_last.visible_entities=_visible_entities
		profile_last.culled_entities=_culled_entities
		profile_last.submitted_transforms=_submitted_transforms
		profile_last.uploaded_transforms=_uploaded_transforms
		profile_last.uploaded_colors=_uploaded_colors
		profile_last.batches_active=_active_batches
		profile_last.models_total=models.size()
		profile_last.data_effects=data_effects.size()
		profile_last.data_corpses=data_corpses.size()
		profile_last.models_created=_models_created
		profile_last.models_reused=_models_reused
		profile_last.cached_entities=_cached_entities
		profile_last.lod_near = _lod_counts[0]
		profile_last.lod_far = _lod_counts[1]
		profile_last.lod_extreme = _lod_counts[2]


func _refresh_paper_infantry_batches(model: Dictionary) -> void:
	var pose: String = str(model.volume.infantry_pose)
	if str(model.get("render_paper_pose","idle")) == pose: return
	# A pose has its own immutable mesh/material/batch. Never change a shared
	# shader texture, so one idle soldier and one firing soldier can coexist.
	var part: Dictionary = model.render_parts[0]
	part.lod_batches = _lod_batches(part.node.mesh,part.node.material_override,int(model.team))
	part.quality_batch = part.lod_batches[1]
	part.performance_batch = part.lod_batches[2]
	model.render_paper_pose = pose


func _sync_wall_connections() -> void:
	var walls: Dictionary = {}
	for entity: Dictionary in sim._building_entities:
		if sim.entities.has(int(entity.id)) and WALL_CONNECTIONS.is_wall(entity, sim.rules): walls[int(entity.id)] = entity
	var next: Dictionary = WALL_CONNECTIONS.masks(walls, sim.rules)
	var changed: bool = false
	for id in next:
		if not models.has(id) or int(models[id].get("wall_mask", 0)) == int(next[id]): continue
		# Recreate just the affected wall; the old root has no corpse lifecycle.
		# Native records retain mesh/batch handles, so invalidate them once here.
		models[id].root.queue_free()
		models.erase(id)
		changed = true
	_wall_masks = next
	if changed and _kernels != null: _kernels.clear_world_models()


func _sync_rail_shapes() -> void:
	var next: Dictionary = {}
	var changed: bool = false
	for entity: Dictionary in sim._building_entities:
		if not sim.entities.has(int(entity.id)): continue
		var spec: Dictionary = sim.data_for(entity.spec)
		if str(spec.get("art","")) not in ["rail","rail_junction"]: continue
		var shape: Dictionary = {"mask":int(entity.get("rail_mask",0)) if int(entity.get("rail_mask",0)) != 0 else (5 if int(entity.get("rotation_quarters",entity.get("rail_rotation",0)))%2 == 0 else 10),"ports":int(entity.get("rail_ports",[7,14,13,11][posmod(int(entity.get("rail_rotation",0)),4)]))}
		next[int(entity.id)] = shape
		if models.has(int(entity.id)) and str(models[entity.id].get("rail_shape","")) != str(shape):
			models[entity.id].root.queue_free()
			models.erase(int(entity.id))
			changed = true
	_rail_shapes = next
	if changed and _kernels != null: _kernels.clear_world_models()


func _model_pool_key(e: Dictionary) -> String:
	var key: String = str(e.spec) + ":" + str(e.team)
	if _wall_masks.has(int(e.id)): key += ":wall:" + str(_wall_masks[int(e.id)])+":rotation:"+str(sim.BuildingOrientation.quarters(e))
	if _rail_shapes.has(int(e.id)): key += ":rail:" + str(_rail_shapes[int(e.id)])
	return key


func _sync_entities_script(selection:Array) -> void:
	var alive_ids: Dictionary = {}
	var selected_ids:Dictionary={}
	for id in selection:selected_ids[id]=true
	for id in sim.entities:
		var e: Dictionary = sim.entities[id]
		alive_ids[id] = true
		if models.has(id) and (int(models[id].team) != int(e.team) or bool(models[id].get("scaffold", false)) != SCAFFOLD.active(e)):
			models[id].root.queue_free()
			models.erase(id)
		if not models.has(id):
			models[id] = _create_entity(e)
		var model:Dictionary=models[id]
		model.fog_hidden = not sim.entity_visible_to(0, int(id))
		if bool(model.get("direct_skinned", false)): model.root.visible = not model.fog_hidden
		if model.fog_hidden:
			model.view_culled = true
			_culled_entities += 1
			continue
		if int(e.get("transport_id",-1))<=0 and int(e.get("garrison_id",-1))<0 and not _entity_in_view(model,e):
			if model.last_pos!=e.pos:
				model.root.position=Vector3(e.pos.x,float(model.terrain_height),e.pos.y)
				model.last_pos=e.pos
			model.embarked=false
			model.view_culled=true
			if bool(model.get("direct_skinned", false)): model.root.visible = false
			_culled_entities+=1
			continue
		model.view_culled=false
		if int(e.get("transport_id",-1))<=0 and int(e.get("garrison_id",-1))<0:_visible_entities+=1
		_sync_entity(model, e, selected_ids.has(id))
	for id in models.keys():
		if not alive_ids.has(id):
			if bool(models[id].get("embarked", false)) or sim.events.any(func(event):return event.get("kind","")=="carrier_recover" and int(event.get("aircraft",-1))==int(id)):
				models[id].root.queue_free()
			else:
				_start_death(models[id])
			models.erase(id)

func _cache_view_planes() -> void:
	var key:Array=[camera.global_transform,camera.fov,camera.projection,camera.size,camera.keep_aspect,camera.near,camera.far,camera.h_offset,camera.v_offset,camera.get_viewport().get_visible_rect()]
	if key==_view_key:return
	_view_key=key
	_view_planes=camera.get_frustum()
	_plane_sides.clear()
	var view:Transform3D=camera.get_camera_transform()
	var inside:Vector3=view.origin-view.basis.z*maxf(camera.near*2.0,1.0)
	for plane in _view_planes:_plane_sides.append(1.0 if plane.distance_to(inside)>=0.0 else -1.0)
	if _kernels != null: _kernels.set_frustum(_view_planes,_plane_sides)


func _point_in_view(pos:Vector3,radius:float) -> bool:
	if native_kernels_enabled and _kernels != null: return _kernels.point_in_view(pos,radius)
	for index in range(_view_planes.size()):
		if _view_planes[index].distance_to(pos)*_plane_sides[index]<-radius:return false
	return true


func _entity_in_view(model:Dictionary,e:Dictionary) -> bool:
	var pos:Vector2=e.pos
	if model.last_terrain_pos!=pos:
		model.terrain_height=MAP.entity_surface_y(sim.map,pos,str(model.get("domain", "ground")))
		model.last_terrain_pos=pos
	var terrain:float=model.terrain_height
	var height:float=model.dimensions.y
	var flight:float=float(model.get("visual_air_y",terrain+float(e.get("flight_height",model.spec.get("flight_height",0.0)))))-terrain if model.is_air else 0.0
	# The margin also retains nearby offscreen casters and contact shadows. Only
	# cosmetic work is culled: authoritative entities and pickable models remain.
	return _point_in_view(Vector3(pos.x,terrain+flight+height*.5,pos.y),float(model.cull_radius))


func _batch(mesh: Mesh, transform: Transform3D, material: Material = null, shadows: bool = false, instance_color:Variant=null) -> void:
	_append_batch(_batch_descriptor(mesh,material,shadows,instance_color!=null),transform,instance_color)


func _batch_descriptor(mesh:Mesh,material:Material=null,shadows:bool=false,colored:bool=false) -> Dictionary:
	var mesh_id:int=mesh.get_instance_id()
	var material_id:int=material.get_instance_id() if material!=null else 0
	if not batch_lookup.has(mesh_id):batch_lookup[mesh_id]={}
	var mesh_batches:Dictionary=batch_lookup[mesh_id]
	if not mesh_batches.has(material_id):mesh_batches[material_id]=[{},{}]
	var slots:Array=mesh_batches[material_id]
	var batch:Dictionary=slots[1 if shadows else 0]
	if batch.is_empty():
		var key:String=str(mesh_id)+":"+str(material_id)+(":lit" if shadows else ":flat")
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors=colored
		multi.mesh = CAMERA_OCCLUSION.mesh(mesh)
		var node := MultiMeshInstance3D.new()
		node.multimesh = multi
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if material != null:
			node.material_override = CAMERA_OCCLUSION.material(material)
		add_child(node)
		batch={"multi":multi,"node":node,"capacity":0,"transforms":[],"colors":[],"uploaded":[],"uploaded_colors":[],"visible_count":-1,"native_queue":null}
		if ClassDB.class_exists("PaperFrontRenderBatch"):
			batch.native_queue=ClassDB.instantiate("PaperFrontRenderBatch")
			batch.native_queue.initialize(multi,node,_uses_native_batches())
			if _kernels!=null:_kernels.register_render_batch(batch)
		batches[key]=batch
		slots[1 if shadows else 0]=batch
	return batch


func _append_batch(batch:Dictionary,transform:Transform3D,instance_color:Variant=null) -> void:
	if batch.get("native_queue")!=null and batch.native_queue.is_enabled():batch.native_queue.append(transform,instance_color)
	else:
		batch.transforms.append(transform)
		if instance_color!=null:batch.colors.append(instance_color)
	_submitted_transforms+=1
	if _recording_model: _model_submissions.append([batch,transform,instance_color])


func _begin_batches()->void:
	if _uses_native_batches():_kernels.begin_render_batches(batches)
	else:
		for batch in batches.values():
			if batch.get("native_queue")!=null and batch.native_queue.prepare(false):
				batch.uploaded.clear();batch.uploaded_colors.clear();batch.visible_count=-1
			batch.transforms.clear()
			batch.colors.clear()

func _uses_native_batches()->bool:
	return native_kernels_enabled and native_batches_enabled and _kernels!=null

func _batch_count(batch:Dictionary)->int:
	return batch.native_queue.get_count() if batch.get("native_queue")!=null and batch.native_queue.is_enabled() else batch.transforms.size()

func _batch_transforms(batch:Dictionary)->Array:
	return batch.native_queue.snapshot_transforms() if batch.get("native_queue")!=null and batch.native_queue.is_enabled() else batch.transforms

func _batch_colors(batch:Dictionary)->Array:
	return batch.native_queue.snapshot_colors() if batch.get("native_queue")!=null and batch.native_queue.is_enabled() else batch.colors

func _flush_batches() -> void:
	_active_batches=0
	if _uses_native_batches():
		var uploaded:Vector3i=_kernels.flush_render_batches(batches,native_bulk_buffers_enabled)
		_uploaded_transforms+=uploaded.x;_uploaded_colors+=uploaded.y;_active_batches=uploaded.z
		return
	for batch in batches.values():
		var count: int = batch.transforms.size()
		if count>0:_active_batches+=1
		if count > int(batch.capacity):
			var capacity: int = 8
			while capacity < count:
				capacity *= 2
			batch.multi.instance_count = capacity
			batch.capacity = capacity
			batch.uploaded.clear()
			batch.uploaded_colors.clear()
		if int(batch.visible_count)!=count:
			batch.multi.visible_instance_count = count
			batch.node.visible = count > 0
			batch.visible_count=count
		var previous:Array=batch.uploaded
		for i in range(count):
			var transform:Transform3D=batch.transforms[i]
			if i>=previous.size():
				batch.multi.set_instance_transform(i,transform)
				previous.append(transform)
				_uploaded_transforms+=1
			elif previous[i]!=transform:
				batch.multi.set_instance_transform(i,transform)
				previous[i]=transform
				_uploaded_transforms+=1
		if not batch.colors.is_empty():
			var previous_colors:Array=batch.uploaded_colors
			for index in range(count):
				var color:Color=batch.colors[index]
				if index>=previous_colors.size():
					batch.multi.set_instance_color(index,color)
					previous_colors.append(color)
					_uploaded_colors+=1
				elif previous_colors[index]!=color:
					batch.multi.set_instance_color(index,color)
					previous_colors[index]=color
					_uploaded_colors+=1


func _material(color: Color, transparent: bool = false) -> StandardMaterial3D:
	var key: String = str(color) + str(transparent)
	if material_cache.has(key):
		return material_cache[key]
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 1.0
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.no_depth_test = false
	material_cache[key] = material
	return material


func _particle_material(source:StandardMaterial3D,kind:String) -> StandardMaterial3D:
	var family:String="blast" if kind in ["blast","death_blast"] else ("smoke" if kind=="smoke" else "flat")
	var key:String="particle_instances_"+family
	if not material_cache.has(key):
		var material:StandardMaterial3D=source.duplicate()
		material.albedo_color=Color.WHITE
		material.vertex_color_use_as_albedo=true
		material.vertex_color_is_srgb=true
		material_cache[key]=material
	return material_cache[key]


func _blast_source_material() -> StandardMaterial3D:
	var key:String="particle_source_blast"
	if not material_cache.has(key):
		var material:StandardMaterial3D=_material(Color("efb34f"),true).duplicate()
		material.shading_mode=BaseMaterial3D.SHADING_MODE_PER_PIXEL
		material.emission_enabled=true
		material.emission=Color("da631b")
		material.emission_energy_multiplier=.35
		material_cache[key]=material
	return material_cache[key]


func _smoke_source_material(destruction:bool) -> StandardMaterial3D:
	var key:String="particle_source_smoke_"+str(destruction)
	if not material_cache.has(key):
		var material:=StandardMaterial3D.new()
		material.albedo_color=Color("37332d") if destruction else Color("596167")
		material.albedo_color.a=.8
		material.roughness=1.0
		material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		material_cache[key]=material
	return material_cache[key]


func _particle_mesh(source:Mesh) -> Mesh:
	# Existing particle materials ignored mesh vertex tint. White vertex colors
	# preserve that behavior when their exact RGBA now comes from an instance.
	if not source is ArrayMesh:return source
	var key:int=source.get_instance_id()
	if particle_mesh_cache.has(key):return particle_mesh_cache[key]
	var mesh:=ArrayMesh.new()
	for surface in range(source.get_surface_count()):
		var arrays:Array=source.surface_get_arrays(surface)
		var colors:=PackedColorArray()
		colors.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
		colors.fill(Color.WHITE)
		arrays[Mesh.ARRAY_COLOR]=colors
		mesh.add_surface_from_arrays(source.surface_get_primitive_type(surface),arrays)
	particle_mesh_cache[key]=mesh
	return mesh

func _paper_lod_mesh(source: ArrayMesh, tier: int) -> ArrayMesh:
	if tier == 0: return source
	var key: String = str(source.get_instance_id()) + ":" + str(tier)
	if _paper_lod_cache.has(key): return _paper_lod_cache[key]
	var face: Array = source.surface_get_arrays(0)
	var vertices: PackedVector3Array = face[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = face[Mesh.ARRAY_TEX_UV]
	var outline := PackedVector2Array()
	for point in vertices: outline.append(Vector2(point.x,point.y))
	var polygon: PackedVector2Array = Geometry2D.convex_hull(outline)
	if polygon.size() > 1 and polygon[0] == polygon[polygon.size()-1]: polygon.resize(polygon.size()-1)
	if tier == 2:
		var bounds: AABB = source.get_aabb()
		polygon = PackedVector2Array([Vector2(bounds.position.x,bounds.position.y),Vector2(bounds.end.x,bounds.position.y),Vector2(bounds.end.x,bounds.end.y),Vector2(bounds.position.x,bounds.end.y)])
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(polygon)
	if indices.is_empty(): return source
	# UVs are affine in the authored sheet plane. Keep the exact illustration,
	# owner mask, printed margin and ground anchor while flattening tiny thickness.
	var first: Vector3 = vertices[0]
	var uv_scale := Vector2.ZERO
	for index in range(vertices.size()):
		if absf(vertices[index].x-first.x) > .001: uv_scale.x = (uv[index].x-uv[0].x)/(vertices[index].x-first.x)
		if absf(vertices[index].y-first.y) > .001: uv_scale.y = (uv[index].y-uv[0].y)/(vertices[index].y-first.y)
	var positions := PackedVector3Array()
	var coordinates := PackedVector2Array()
	var normals := PackedVector3Array()
	for point in polygon:
		positions.append(Vector3(point.x,point.y,first.z))
		coordinates.append(uv[0]+(point-Vector2(first.x,first.y))*uv_scale)
		normals.append(Vector3.FORWARD)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = coordinates
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.surface_set_material(0,source.surface_get_material(0))
	_paper_lod_cache[key] = mesh
	return mesh

func _paper_lod_batches(source: ArrayMesh) -> Array:
	return [_batch_descriptor(source,null,true),_batch_descriptor(_paper_lod_mesh(source,1),null,true),_batch_descriptor(_paper_lod_mesh(source,2),null,true)]


func _pose_mesh(mesh: Mesh, material: Material = null):
	if not pose_meshes_enabled: return _mesh_instance(mesh, material)
	var node = preload("res://scripts/pose_mesh.gd").new()
	node.mesh = mesh
	node.material_override = material
	return node


func _mesh_instance(mesh: Mesh, material: Material = null) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if material != null:
		instance.material_override = material
	return instance


func _card(key: String, width: float, height: float, texture_path: String = "", team: int = -1, owner_override: Color = Color.TRANSPARENT) -> ArrayMesh:
	if texture_path.is_empty():
		texture_path = CARD_DIR + key + ".svg"
	# A configuration can swap both drawing and its matching registered contour.
	var mapped_key: String = texture_path.get_file().get_basename()
	if contours.has(mapped_key):
		key = mapped_key
	var cache_key: String = key + ":" + str(width) + ":" + str(height) + ":" + texture_path+":team"+str(team)+":"+str(owner_override)
	if card_cache.has(cache_key):
		return card_cache[cache_key]
	if not contours.has(key):
		push_error("Missing paper cut contour: " + key)
		return ArrayMesh.new()
	var info: Dictionary = contours[key]
	var polygon := PackedVector2Array()
	var bottom: float = 0.0
	for raw in info.outline:
		polygon.append(Vector2(float(raw[0]), float(raw[1])))
		bottom = maxf(bottom,float(raw[1]))
	# Keep the actual thickness wall on its original cut contour. Only the
	# front/back sheet grows to contain the screen-space printed paper border.
	var cut_polygon := polygon.duplicate()
	polygon = _infantry_border_polygon(polygon, width, height, info, bottom)
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(polygon)
	if indices.is_empty():
		push_error("Cannot triangulate original paper illustration: " + key)
		return ArrayMesh.new()
	var vertices := PackedVector3Array()
	var uv := PackedVector2Array()
	var normals := PackedVector3Array()
	var thickness: float = 0.045 if height < 2.0 else 0.065
	for index in indices:
		var point: Vector2 = polygon[index]
		vertices.append(Vector3((point.x / float(info.width) - 0.5) * width, (bottom - point.y) / float(info.height) * height, thickness * 0.5))
		uv.append(Vector2(point.x / float(info.width), point.y / float(info.height)))
		normals.append(Vector3.FORWARD)
	# Double-sided textured face: the same drawing is visible on both faces.
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var paper := _infantry_paper_material(texture_path,team,owner_override)
	mesh.surface_set_material(0, paper)
	var edge_vertices := PackedVector3Array()
	for i in range(cut_polygon.size()):
		var a: Vector2 = cut_polygon[i]
		var b: Vector2 = cut_polygon[(i + 1) % cut_polygon.size()]
		var pa := Vector3((a.x / float(info.width) - 0.5) * width, (bottom - a.y) / float(info.height) * height, -thickness * 0.5)
		var pb := Vector3((b.x / float(info.width) - 0.5) * width, (bottom - b.y) / float(info.height) * height, -thickness * 0.5)
		var front := Vector3(0, 0, thickness)
		edge_vertices.append_array([pa, pb, pb + front, pa, pb + front, pa + front])
	arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = edge_vertices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(1, _material(VOLUME.player_color(team) if team >= 0 else EDGE_COLOR))
	# A second face is physically separated from the first by the paper thickness.
	var back_vertices := PackedVector3Array()
	for point in vertices:
		back_vertices.append(point - Vector3(0, 0, thickness))
	arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = back_vertices
	arrays[Mesh.ARRAY_TEX_UV] = uv
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(2, paper)
	card_cache[cache_key] = mesh
	return mesh


func _infantry_border_polygon(source: PackedVector2Array, width: float, height: float, info: Dictionary, bottom: float) -> PackedVector2Array:
	var metric := PackedVector2Array()
	for p in source:
		metric.append(Vector2((p.x / float(info.width) - 0.5) * width, (bottom - p.y) / float(info.height) * height))
	var expanded: Array[PackedVector2Array] = Geometry2D.offset_polygon(metric, 0.15, Geometry2D.JOIN_ROUND)
	if expanded.is_empty():
		push_warning("Paper border expansion failed; retaining the original infantry contour.")
		return source
	var outer := _largest_paper_polygon(expanded)
	var min_x: float = INF
	var max_x: float = -INF
	var max_y: float = 0.0
	for p in outer:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		max_y = maxf(max_y, p.y)
	# Clip rather than clamp vertices: no duplicate or crossed foot vertices,
	# and the printed margin cannot extend below the original ground anchor.
	var ground_clip := PackedVector2Array([Vector2(min_x - 1, 0), Vector2(max_x + 1, 0), Vector2(max_x + 1, max_y + 1), Vector2(min_x - 1, max_y + 1)])
	var clipped: Array[PackedVector2Array] = Geometry2D.intersect_polygons(outer, ground_clip)
	if clipped.is_empty(): return source
	outer = _largest_paper_polygon(clipped)
	var canvas := PackedVector2Array()
	for p in outer:
		canvas.append(Vector2((p.x / width + 0.5) * float(info.width), bottom - p.y / height * float(info.height)))
	return canvas

func _largest_paper_polygon(polygons: Array[PackedVector2Array]) -> PackedVector2Array:
	var largest := PackedVector2Array()
	var largest_area: float = -1.0
	for polygon in polygons:
		var twice_area: float = 0.0
		for i in range(polygon.size()):
			var a: Vector2 = polygon[i]
			var b: Vector2 = polygon[(i + 1) % polygon.size()]
			twice_area += a.cross(b)
		if absf(twice_area) > largest_area:
			largest_area = absf(twice_area)
			largest = polygon
	return largest

func _infantry_paper_material(texture_path: String, team: int = -1, owner_override: Color = Color.TRANSPARENT) -> ShaderMaterial:
	var key := "infantry_border:" + texture_path+":team"+str(team)+":"+str(owner_override)
	if material_cache.has(key): return material_cache[key]
	if infantry_border_shader == null:
		infantry_border_shader = Shader.new()
		infantry_border_shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
uniform sampler2D illustration : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D identity_mask : filter_linear_mipmap, repeat_disable;
uniform vec4 player_color : source_color = vec4(0.90588,0.67843,0.25882,1.0);
uniform float identity_enabled = 0.0;
uniform float palette_enabled = 0.0;
uniform vec4 faction_accent : source_color = vec4(0.23,0.52,0.48,1.0);
uniform vec4 paper_color : source_color = vec4(0.75, 0.64, 0.45, 1.0);
uniform vec4 ink_color : source_color = vec4(0.25, 0.20, 0.16, 1.0);
float alpha_at(vec2 p, vec2 dx, vec2 dy) {
    // Clamp the sampler as well as rejecting outside UVs: no wrap or painted
    // edge smear can create a false ring at an illustration's canvas bounds.
    float inside = step(0.0, p.x) * step(p.x, 1.0) * step(0.0, p.y) * step(p.y, 1.0);
    return textureGrad(illustration, clamp(p, vec2(0.0), vec2(1.0)), dx, dy).a * inside;
}
void fragment() {
    // Derivatives must be computed outside the non-uniform alpha branch.
    vec2 dx = dFdx(UV);
    vec2 dy = dFdy(UV);
    vec4 original = textureGrad(illustration, clamp(UV, vec2(0.0), vec2(1.0)), dx, dy);
    original.a *= step(0.0, UV.x) * step(UV.x, 1.0) * step(0.0, UV.y) * step(UV.y, 1.0);
    vec4 identification = textureGrad(identity_mask, clamp(UV, vec2(0.0), vec2(1.0)), dx, dy);
    float owner_mask = identification.r * identification.a * identity_enabled;
    vec3 contrasted = clamp((original.rgb - vec3(0.42)) * 1.12 + vec3(0.39), vec3(0.0), vec3(1.0));
    float saturation = max(original.r,max(original.g,original.b))-min(original.r,min(original.g,original.b));
    // Authored infantry use a dedicated magenta cloth pigment. Warm skin and
    // leather must never be inferred as player paint from red saturation.
    float fabric = smoothstep(0.12,0.22,min(original.r,original.b)-original.g);
    fabric = clamp(fabric,0.0,1.0) * (1.0-owner_mask) * palette_enabled;
    vec3 owner_fabric = player_color.rgb * clamp(max(original.r,max(original.g,original.b))*1.3,0.55,1.05);
    vec3 color = mix(contrasted,owner_fabric,fabric);
    float heritage = step(0.76,fract(UV.y*3.0+UV.x*0.35)) * fabric;
    color = mix(color,faction_accent.rgb,heritage);
    color = mix(color,vec3(0.94,0.71,0.22),owner_mask);
    float alpha = original.a;
    if (original.a < 0.15) {
        float paper_mask = 0.0;
        float outer_mask = 0.0;
        for (int i = 0; i < 16; i++) {
            float angle = float(i) * 6.28318530718 / 16.0;
            vec2 pixel_step = dx * cos(angle) + dy * sin(angle);
            // Both inner radii sample a disk, preventing tiny rifle/ankle
            // features from being skipped by one hollow sampling ring.
            paper_mask = max(paper_mask, alpha_at(UV + pixel_step * 0.45, dx, dy));
            paper_mask = max(paper_mask, alpha_at(UV + pixel_step * 0.85, dx, dy));
            outer_mask = max(outer_mask, alpha_at(UV + pixel_step * 1.65, dx, dy));
        }
        alpha = max(paper_mask, outer_mask);
        color = paper_mask >= 0.15 ? paper_color.rgb : ink_color.rgb;
    }
    ALBEDO = color;
    ALPHA = alpha;
    ALPHA_SCISSOR_THRESHOLD = 0.15;
}
"""
	var material := ShaderMaterial.new()
	material.shader = infantry_border_shader
	material.set_shader_parameter("faction_accent",VOLUME.faction_color(texture_path.get_file().get_slice("_",0)))
	material.set_shader_parameter("illustration", load(texture_path))
	if team >= 0:
		material.set_shader_parameter("player_color",owner_override if owner_override.a > 0.0 else VOLUME.player_color(team))
		material.set_shader_parameter("palette_enabled",1.0)
	var mask_path: String=texture_path.get_basename()+"_identity.svg"
	if team>=0 and ResourceLoader.exists(mask_path):
		material.set_shader_parameter("identity_mask",load(mask_path))
		material.set_shader_parameter("player_color",owner_override if owner_override.a > 0.0 else VOLUME.player_color(team))
		material.set_shader_parameter("identity_enabled",1.0)
	material_cache[key] = material
	return material


func _vehicle_border_material(paper: bool) -> ShaderMaterial:
	var key: String = "vehicle_border:paper" if paper else "vehicle_border:ink"
	if material_cache.has(key): return material_cache[key]
	if vehicle_border_shader == null:
		vehicle_border_shader = Shader.new()
		vehicle_border_shader.code = """shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;
uniform vec4 border_color : source_color;
uniform float border_pixels = 3.0;
uniform float clip_depth_scale = 1.0;
void vertex() {
    vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
    vec3 view_normal = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
    vec4 clip_normal = PROJECTION_MATRIX * vec4(view_normal, 0.0);
    // Derivative of perspective division, normalized in viewport pixel space.
    vec2 pixel_direction = (clip_normal.xy * clip.w - clip.xy * clip_normal.w) * VIEWPORT_SIZE;
    float direction_length = length(pixel_direction);
    if (direction_length > 0.00001) {
        clip.xy += pixel_direction / direction_length * border_pixels * (2.0 / VIEWPORT_SIZE) * clip.w;
    }
    // Forward+ uses reversed Z. Only ink moves a tiny relative distance away;
    // paper stays at the source shell depth so thin parts are not painted over.
    // Subtract in clip space: scaling a negative Compatibility Z would
    // pull the opaque back shell in front and hide the complete lit model.
    clip.z -= (1.0 - clip_depth_scale) * 0.005 * clip.w;
    POSITION = clip;
}
void fragment() {
    ALBEDO = border_color.rgb;
}
"""
	var material := ShaderMaterial.new()
	material.shader = vehicle_border_shader
	material.set_shader_parameter("border_color",Color(0.75,0.64,0.45) if paper else Color(0.25,0.20,0.16))
	material.set_shader_parameter("border_pixels",0.65 if paper else 1.65)
	material.set_shader_parameter("clip_depth_scale",1.0 if paper else 0.9995)
	material_cache[key] = material
	return material


func _texture_path(spec: Dictionary, state: String) -> String:
	var animations: Dictionary = spec.get("animations", {})
	return str(animations.get(state, CARD_DIR + VOLUME.art_faction(spec) + "_" + spec.art + "_" + state + ".svg"))


func _visible_height(key: String, full_height: float) -> float:
	var info: Dictionary = contours[key]
	var top: float = float(info.height)
	var bottom: float = 0.0
	for point in info.outline:
		top = minf(top,float(point[1]))
		bottom = maxf(bottom,float(point[1]))
	return (bottom-top) / float(info.height) * full_height


func _dimensions(spec: Dictionary, kind: String) -> Vector2:
	var art: String = spec.art
	if kind == "building":
		match art:
			"hq": return Vector2(5.0, 4.3)
			"factory", "refinery": return Vector2(5.2, 3.9)
			"tower": return Vector2(3.0, 4.0)
			_: return Vector2(4.0, 3.6)
	if art in VOLUME.INFANTRY_ART: return Vector2(1.65,1.8)*.6
	match art:
		"tank": return Vector2(3.25, 2.2)
		"harvester": return Vector2(3.4, 2.5)
		"assault": return Vector2(4.15, 2.65)
		_: return Vector2(1.65, 1.8)


func _create_entity(e: Dictionary) -> Dictionary:
	var pool_key:String=_model_pool_key(e)
	if not SCAFFOLD.active(e) and model_pool.has(pool_key) and not model_pool[pool_key].is_empty():
		var reused:Dictionary=model_pool[pool_key].pop_back()
		_reset_model(reused,e)
		_models_reused+=1
		return reused
	_models_created+=1
	var spec: Dictionary = sim.rules.units[e.spec] if e.kind == "unit" else sim.rules.buildings[e.spec]
	if _wall_masks.has(int(e.id)):
		spec = spec.duplicate()
		spec.wall_mask = sim.BuildingOrientation.rotated_mask(int(_wall_masks[int(e.id)]),-sim.BuildingOrientation.quarters(e))
	if _rail_shapes.has(int(e.id)):
		spec = spec.duplicate()
		spec.rail_mask = _rail_shapes[int(e.id)].mask
		spec.rail_ports = _rail_shapes[int(e.id)].ports
	var dimensions: Vector2 = _dimensions(spec, e.kind)
	var root := Node3D.new()
	root.name = "Paper_%s_%s" % [e.spec, e.id]
	add_child(root)
	root.position=Vector3(e.pos.x,MAP.entity_surface_y(sim.map,e.pos,str(spec.get("domain","ground"))),e.pos.y)
	var scaffold: bool = SCAFFOLD.active(e)
	var volume: Dictionary = SCAFFOLD.create_model(spec, int(e.team)) if scaffold else VOLUME.create_model(spec,e.kind,int(e.team),pose_meshes_enabled)
	var volumetric: bool = not volume.is_empty()
	var direct_skinned: bool = bool(volume.get("direct_skinned", false))
	var art_root: Node3D = volume.root if volumetric else Node3D.new()
	root.add_child(art_root)
	var graphic: Variant
	if volumetric:
		dimensions = Vector2(maxf(volume.dimensions.x,volume.dimensions.z),volume.height)
		graphic = volume.meshes[0]
		for mesh in volume.meshes:
			mesh.visible = direct_skinned
			if direct_skinned: CAMERA_OCCLUSION.wrap_instance(mesh)
	else:
		graphic = _pose_mesh(_card(VOLUME.art_faction(spec)+"_"+spec.art+"_idle", dimensions.x, dimensions.y, _texture_path(spec,"idle"),int(e.team)))
		art_root.add_child(graphic)
		graphic.visible = false
	var shadow = _pose_mesh(shadow_mesh, _material(Color(0.19, 0.15, 0.1, 0.2), true))
	root.add_child(shadow)
	shadow.position.y = 0.025
	shadow.scale = Vector3(dimensions.x * 0.4, 1.0, dimensions.x * 0.19)
	shadow.visible = false
	var ring = _pose_mesh(ring_mesh, _material(VOLUME.player_color(int(e.team))))
	root.add_child(ring)
	var radius: float = float(spec.radius) if e.kind == "unit" else float(spec.size) * 0.66
	ring.scale = Vector3(radius + 0.25, 1, radius + 0.25)
	ring.position.y = 0.045
	ring.visible = false
	var hp_root := Node3D.new()
	root.add_child(hp_root)
	hp_root.visible = false
	var human_card: bool = e.kind == "unit" and str(spec.get("art","")) in VOLUME.INFANTRY_ART
	hp_root.position.y = (volume.height if volumetric else _visible_height(VOLUME.art_faction(spec)+"_"+spec.art+"_idle",dimensions.y)) + (.12 if human_card else .2)
	if human_card: hp_root.scale=Vector3.ONE*.6
	var hp_width: float = clampf(dimensions.x * 0.6, 1.05, 2.9)
	var hp_back = _pose_mesh(square_mesh, _material(Color("40382c")))
	hp_root.add_child(hp_back)
	hp_back.scale = Vector3(hp_width + 0.08, 0.17, 1)
	var hp_paper = _pose_mesh(square_mesh, _material(Color("f5e7c4")))
	hp_root.add_child(hp_paper)
	hp_paper.position.z = 0.006
	hp_paper.scale = Vector3(hp_width, 0.115, 1)
	var hp_paper_back = _pose_mesh(square_mesh, _material(Color("f5e7c4")))
	hp_root.add_child(hp_paper_back)
	hp_paper_back.position.z = -0.006
	hp_paper_back.scale = hp_paper.scale
	var hp_fill = _pose_mesh(square_mesh, _material(Color("799665")))
	hp_root.add_child(hp_fill)
	hp_fill.position.z = 0.012
	hp_fill.scale = Vector3(hp_width - 0.05, 0.075, 1)
	var hp_fill_back = _pose_mesh(square_mesh, _material(Color("799665")))
	hp_root.add_child(hp_fill_back)
	hp_fill_back.position.z = -0.012
	hp_fill_back.scale = hp_fill.scale
	var model: Dictionary = {"scaffold":scaffold,"volumetric":volumetric,"volume":volume,"root":root,"art_root":art_root,"graphic":graphic,"shadow":shadow,"ring":ring,"hp_root":hp_root,"hp_fill":hp_fill,"hp_fill_back":hp_fill_back,"hp_width":hp_width - 0.05,"dimensions":dimensions,"spec":spec,"state":"idle","kind":e.kind,"team":int(e.team),"last_pos":Vector2.INF,"last_alpha":INF,"mirror":false,"hp_fraction":1.0,"base_hp_height":hp_root.position.y,"flight_height":0.0}
	model.pool_spec=str(e.spec)
	model.entity_id=int(e.id)
	model.damage_stage=0
	model.direct_skinned = direct_skinned
	if direct_skinned:
		# The natural skin stays untouched. A thin outer owner mark remains
		# distinct from the thicker, selection-only inner ring.
		var owner_mark = _pose_mesh(hand_owner_mesh, _material(VOLUME.player_color(int(e.team))))
		root.add_child(owner_mark)
		owner_mark.scale = Vector3(radius + 0.60, 1, radius + 0.60)
		owner_mark.position.y = 0.065
		owner_mark.visible = false
		model.hand_owner_mark = owner_mark
		model.hand_owner_batch = _batch_descriptor(hand_owner_mesh, owner_mark.material_override)
	if _wall_masks.has(int(e.id)):
		model.wall_mask = int(_wall_masks[int(e.id)])
		model.wall_rotation = sim.BuildingOrientation.quarters(e)
	if _rail_shapes.has(int(e.id)): model.rail_shape = str(_rail_shapes[int(e.id)])
	if scaffold:
		var progress_back = _pose_mesh(square_mesh, _material(Color("40382c")))
		hp_root.add_child(progress_back)
		progress_back.position = Vector3(0, -.25, .01)
		progress_back.scale = Vector3(hp_width, .08, 1)
		var progress_fill = _pose_mesh(square_mesh, _material(VOLUME.player_color(int(e.team))))
		hp_root.add_child(progress_fill)
		progress_fill.position = Vector3(-hp_width * .5, -.25, .02)
		progress_fill.scale = Vector3(0, .06, 1)
		model.progress_fill = progress_fill
	model.hp_bars=hp_root.get_children()
	model.hp_batches=[]
	for bar in model.hp_bars:model.hp_batches.append(_batch_descriptor(square_mesh,bar.material_override))
	model.shadow_batch=_batch_descriptor(shadow_mesh,shadow.material_override)
	model.ring_batch=_batch_descriptor(ring_mesh,ring.material_override)
	model.render_parts=[]
	model.cargo_batches=[]
	if volumetric and not direct_skinned:
		for source in volume.meshes:
			var part:Dictionary={"node":source,"batch":_batch_descriptor(source.mesh,source.material_override,true)}
			for border in volume.get("border_meshes",[]):
				if border.source==source:
					part.ink_batch=_batch_descriptor(border.mesh,_vehicle_border_material(false))
					part.paper_batch=_batch_descriptor(border.mesh,_vehicle_border_material(true))
			model.render_parts.append(part)
		for piece in volume.get("cargo",[]):model.cargo_batches.append(_batch_descriptor(piece.mesh,null,true))
	elif not volumetric:
		model.paper_batch = _batch_descriptor(graphic.mesh,null,true)
		model.paper_lod_batches = _paper_lod_batches(graphic.mesh)
	_prepare_quality_batches(model)
	model.lod_tier = 0
	model.lod_pixels = 0.0
	# The exposed ring/dish is the main visual identity of research/command
	# buildings. The 20px comparison still resolves it, so defer their most
	# compact tier until the complete model is below roughly ten pixels.
	model.lod_extreme_pixels = 10.0 if e.kind == "building" and str(spec.get("role","")) in ["tech","command"] else MODEL_LOD.EXTREME_PIXELS
	model.terrain_height=root.position.y
	model.last_terrain_pos=e.pos
	model.is_air=spec.get("domain","ground")=="air"
	model.domain=str(spec.get("domain","ground"))
	model.fog_hidden=not sim.entity_visible_to(0,int(e.id))
	model.cull_radius=maxf(dimensions.x,dimensions.y)*.7+8.0
	if model.is_air: model.cull_radius+=_aircraft_terrain_margin()
	model.last_visual_elapsed=elapsed-frame_delta
	model.last_hp_yaw=INF
	model.last_turret_angle=INF
	model.last_progress=-1.0
	if volumetric:model.volume.cargo_capacity=float(sim.rules.economy.harvester_capacity)
	model.smoke_ports=[]
	model.smoke_size_factor=1.0 if VOLUME.art_faction(model.spec)=="rivet" else .47
	if model.kind=="building" and model.spec.art=="power" and VOLUME.art_faction(model.spec)!="sky":
		for port in model.volume.get("smoke_ports",[]):
			if port is Vector3:model.smoke_ports.append(port)
		if model.smoke_ports.is_empty():
			if VOLUME.art_faction(model.spec)=="rivet":model.smoke_ports.append(Vector3(.73,3.49,-.87))
			else:model.smoke_ports.append_array([Vector3(-.78,2.08,-.35),Vector3(0,2.08,-.35),Vector3(.78,2.08,-.35)])
	if not model.scaffold:
		for part: Dictionary in model.render_parts: _queue_fragment_warm(part.lod_batches[1].multi.mesh,part.node.material_override)
	return model


func _reset_model(model:Dictionary,e:Dictionary) -> void:
	model.erase("visual_signature")
	model.lod_tier = 0
	model.lod_pixels = 0.0
	for item in model.get("skinned_lods",[]): item.node.mesh = item.source
	model.root.name="Paper_%s_%s" % [e.spec,e.id]
	model.root.visible=true
	model.domain=str(model.spec.get("domain","ground"))
	model.fog_hidden=not sim.entity_visible_to(0,int(e.id))
	model.root.position=Vector3(e.pos.x,MAP.entity_surface_y(sim.map,e.pos,model.domain),e.pos.y)
	model.root.rotation=Vector3.ZERO
	model.root.remove_meta("mirrored")
	model.art_root.position=Vector3.ZERO
	model.art_root.rotation=Vector3.ZERO
	model.art_root.scale=Vector3.ONE
	model.last_pos=Vector2.INF
	model.last_alpha=INF
	model.last_turret_angle=INF
	model.last_hp_yaw=INF
	model.last_visual_elapsed=elapsed-frame_delta
	model.last_terrain_pos=e.pos
	model.terrain_height=model.root.position.y
	model.hp_fraction=INF
	model.flight_height=0.0
	model.hp_root.position.y=model.base_hp_height
	model.mirror=false
	model.embarked=false
	model.view_culled=false
	model.state=""
	model.entity_id=int(e.id)
	model.erase("removed_without_burst")
	model.erase("track_pos")
	model.erase("track_heading")
	for field: String in ["air_transition","air_logical_airborne","visual_air_y","visual_air_velocity","visual_air_measured_velocity","air_motion_pos","air_motion_elapsed","logical_flight_height","airborne_visual","air_trail_world","death_velocity","death_heading","death_flight_height"]:model.erase(field)
	model.erase("air_trail_pos")
	model.erase("air_trail_stamp")
	model.erase("death_style")
	model.erase("motion_pos")
	model.erase("motion_moving")
	model.erase("brake_age")
	model.erase("brake_speed")
	_set_building_damage(model,0)
	if model.volumetric:
		model.volume.clock=0.0
		model.volume.pose_active=true
		if not bool(model.get("direct_skinned", false)):
			model.volume.body.position=Vector3.ZERO
			model.volume.body.rotation=Vector3.ZERO
		elif model.volume.get("skeleton") is Skeleton3D:
			model.volume.skeleton.reset_bone_poses()
	_prepare_quality_batches(model)


func _pool_model(model:Dictionary) -> void:
	model.erase("creator_crushed")
	var key:String=str(model.spec.get("id", ""))+":"+str(model.team)
	# Definitions do not carry their dictionary key. The root retains that ID.
	key=str(model.get("pool_spec",""))+":"+str(model.team)
	if model.has("wall_mask"): key += ":wall:" + str(model.wall_mask)+":rotation:"+str(model.get("wall_rotation",0))
	if model.has("rail_shape"): key += ":rail:" + str(model.rail_shape)
	if not model_pool.has(key):model_pool[key]=[]
	if model_pool[key].size()<12 and not model.scaffold:
		model.root.visible=false
		model_pool[key].append(model)
	else:model.root.queue_free()


func _sync_entity(model: Dictionary, e: Dictionary, selected: bool) -> void:
	model.erase("visual_signature")
	_update_entity(model,e,selected)


func _update_entity(model: Dictionary, e: Dictionary, selected: bool) -> void:
	model.embarked = int(e.get("transport_id", -1)) > 0 or int(e.get("garrison_id",-1)) >= 0
	if bool(model.get("direct_skinned", false)):
		model.root.visible = not model.embarked and not bool(model.get("fog_hidden", false)) and not bool(model.get("view_culled", false))
	if model.embarked: return
	var root: Node3D = model.root
	var pos: Vector2 = e.pos
	if model.last_pos != pos:
		if model.last_terrain_pos!=pos:
			model.terrain_height=MAP.entity_surface_y(sim.map,pos,str(model.get("domain","ground")))
			model.last_terrain_pos=pos
		root.position = Vector3(pos.x,float(model.terrain_height),pos.y)
		model.last_pos = pos
	var flight_height: float=float(e.get("flight_height",model.spec.get("flight_height",0.0))) if model.spec.get("domain","ground")=="air" else 0.0
	if bool(model.get("is_air",false)):
		_sync_aircraft_motion(model,e)
		flight_height=float(model.flight_height)
	if model.volumetric and bool(model.volume.get("aircraft",false)):
		model.art_root.position.y=flight_height
		model.hp_root.position.y=float(model.base_hp_height)+flight_height
		var shadow_factor: float=clampf(1.0-flight_height*.035,.52,1.0)
		model.shadow.scale=Vector3(model.dimensions.x*.40*shadow_factor,1.0,model.dimensions.x*.19*shadow_factor)
	model.flight_height=flight_height
	if bool(model.get("is_air",false)): _update_aircraft_trails(model,e)
	if _is_tracked_vehicle(model) and frame_delta > 0.0:
		_update_tread_marks(model,e)
	var state: String = "idle"
	if e.kind == "unit":
		state = e.state if e.state in ["idle", "move", "attack"] else "idle"
		if float(e.get("attack_flash",0.0)) > 0.0:
			state = "attack"
		if float(e.get("hit_flash", 0.0)) > 0.0:
			state = "hit"
		var alpha: float = wrapf(float(e.alpha), -180.0, 180.0)
		if model.last_alpha != alpha:
			root.rotation.y = -deg_to_rad(alpha)
			model.last_alpha = alpha
			root.set_meta("alpha",alpha)
		var mirrored: bool = not model.volumetric and absf(alpha) > 80.0
		# An equivalent plane rotated 180 degrees plus a local picture reflection
		# keeps the depicted +X muzzle in the actual world heading. It exchanges
		# front/back at the fixed boundary without reflecting any rule coordinates.
		if model.mirror != mirrored:
			model.art_root.rotation.y = PI if mirrored else 0.0
			model.art_root.scale.x = -1.0 if mirrored else 1.0
			model.mirror = mirrored
			root.set_meta("mirrored",mirrored)
		elif not root.has_meta("mirrored"):root.set_meta("mirrored",mirrored)
		if not model.volumetric and state == "move":
			model.art_root.rotation.z = sin(elapsed * 12.0 + float(e.id)) * 0.028
			model.art_root.position.y = absf(sin(elapsed * 8.0 + float(e.id))) * 0.04
		elif not model.volumetric and model.state == "move":
			model.art_root.rotation.z = 0
			model.art_root.position.y = 0
		var recoil: float = float(e.get("attack_flash",0.0))
		if model.volumetric and model.volume.turret != null:
			var angle:float=-deg_to_rad(wrapf(float(e.get("turret_alpha",alpha))-alpha,-180.0,180.0))
			if float(model.last_turret_angle)!=angle:
				model.volume.turret.rotation.y=angle
				model.last_turret_angle=angle
		if not model.volumetric and state == "attack":
			model.art_root.position.x = -0.12 * minf(recoil * 4.0,1.0)
		elif not model.volumetric and model.state == "attack":
			model.art_root.position.x = 0
	else:
		# Complete buildings stay anchored to the map when the camera orbits.
		var building_alpha: float = sim.BuildingOrientation.angle(e,model.spec)
		if model.last_alpha != building_alpha:
			root.rotation.y = -deg_to_rad(building_alpha)
			model.last_alpha = building_alpha
		if model.volume.turret != null:
			var angle:float=-deg_to_rad(float(e.get("turret_alpha",0.0))-building_alpha)
			if float(model.last_turret_angle)!=angle:
				model.volume.turret.rotation.y=angle
				model.last_turret_angle=angle
		var remaining: float = float(e.get("construct_remaining", 0.0))
		var build_time: float = float(sim.rules.economy.construction_animation)
		var progress: float = 1.0 - clampf(remaining / maxf(build_time, 0.001), 0, 1)
		if not model.scaffold and (remaining > 0 or model.art_root.scale.y != 1.0):
			model.art_root.scale.y = 0.08 + 0.92 * progress
	if model.volumetric:
		if model.scaffold:
			var progress: float = SCAFFOLD.progress(e)
			if float(model.last_progress)!=progress:
				SCAFFOLD.update_model(model.volume,e)
				model.progress_fill.scale.x = float(model.hp_width) * progress
				model.progress_fill.position.x = (progress - 1.0) * float(model.hp_width) * .5
				model.last_progress=progress
		else:
			VOLUME.update_model(model.volume,e,maxf(0.0,elapsed-float(model.last_visual_elapsed)))
			if bool(model.volume.get("paper_infantry",false)): _refresh_paper_infantry_batches(model)
		model.last_visual_elapsed=elapsed
		if _is_tracked_vehicle(model): _update_tank_braking(model,e)
		var hp_yaw:float=camera_yaw-root.rotation.y
		if float(model.last_hp_yaw)!=hp_yaw:
			model.hp_root.rotation.y=hp_yaw
			model.last_hp_yaw=hp_yaw
		model.state = state
	if state != model.state:
		_set_paper_state(model,state)
	var health_cap: float = SCAFFOLD.health_cap(e, model.spec) if model.scaffold else float(e.get("max_hp",model.spec.hp))
	var fraction: float = clampf(float(e.hp) / maxf(health_cap, .001), 0.0, 1.0)
	var hp_width: float = model.hp_width
	if model.kind == "building" and not model.scaffold:
		_set_building_damage(model,BATTLEFIELD_DAMAGE.damage_stage(fraction))
		_damage_smoke(model,e)
	if fraction != model.hp_fraction:
		model.hp_fill.scale.x = hp_width * fraction
		model.hp_fill.position.x = (fraction - 1.0) * hp_width * 0.5
		model.hp_fill_back.scale.x = hp_width * fraction
		model.hp_fill_back.position.x = (fraction - 1.0) * hp_width * 0.5
		model.hp_fraction = fraction
	var tier: int = _update_model_lod(model)
	if model.volumetric:
		for part in model.render_parts:
			var transform:Transform3D=part.node.global_transform
			if bool(e.get("veteran",false)) and model.kind == "unit":
				if not part.has("veteran_lod_batches"):
					part.veteran_lod_batches = []
					for lod_batch in part.lod_batches: part.veteran_lod_batches.append(_batch_descriptor(lod_batch.multi.mesh,VOLUME.veteran_paint(int(e.team)),true))
				_append_batch(part.veteran_lod_batches[tier],transform)
			else:
				_append_batch(part.lod_batches[tier],transform)
			if part.has("ink_batch"):
				_append_batch(part.ink_lod_batches[tier],transform)
				_append_batch(part.paper_lod_batches[tier],transform)
		for i in range(int(model.volume.get("cargo_count",0))):
			var piece: Node3D = model.volume.cargo[i]
			_append_batch(model.cargo_lod_batches[i][tier],piece.global_transform)
	else:
		_append_batch(model.paper_lod_batches[tier],root.global_transform * model.art_root.transform)
	# A small ink wash tightens contact at the feet/tracks without replacing shadows.
	var transform:Transform3D=root.global_transform
	_append_batch(model.shadow_batch,transform*model.shadow.transform)
	if model.has("hand_owner_batch") and model.root.visible:
		# Only living, visible, unloaded hand entities reach this submission.
		# Fog/culling skip _sync_entity; corpses never submit the owner mark.
		_append_batch(model.hand_owner_batch,transform*model.hand_owner_mark.transform)
	if selected:
		_append_batch(model.ring_batch,transform*model.ring.transform)
	_industrial_smoke(model, e)
	if float(e.get("emp_until",0)) > sim.time: _draw_emp_status(model,e)
	if selected or model.scaffold or bool(e.get("veteran",false)) or float(e.get("hit_flash",0.0)) > 0.0:
		var hp_transform:Transform3D=transform*model.hp_root.transform
		for index in range(model.hp_bars.size()):_append_batch(model.hp_batches[index],hp_transform*model.hp_bars[index].transform)
		if bool(e.get("veteran",false)):
			if not model.has("veteran_star_batch"): model.veteran_star_batch = _batch_descriptor(_veteran_star_mesh())
			var star_transform: Transform3D = hp_transform
			star_transform.origin += hp_transform.basis*Vector3(float(model.hp_width)*.5+.22,0,.03)
			_append_batch(model.veteran_star_batch,star_transform)


func _set_paper_state(model:Dictionary,state:String) -> void:
	var dimensions:Vector2=model.dimensions
	model.graphic.mesh=_card(VOLUME.art_faction(model.spec)+"_"+model.spec.art+"_"+state,dimensions.x,dimensions.y,_texture_path(model.spec,state),int(model.team))
	model.paper_batch=_batch_descriptor(model.graphic.mesh,null,true)
	model.paper_lod_batches = _paper_lod_batches(model.graphic.mesh)
	model.state=state

func _update_model_lod(model: Dictionary) -> int:
	var center: Vector3 = model.root.global_position + Vector3.UP*(float(model.get("flight_height",0.0))+float(model.dimensions.y)*.5)
	if _lod_view.is_empty() or not _syncing_entities: _lod_view = MODEL_LOD.view(camera)
	var pixels: float = MODEL_LOD.pixels_from_view(_lod_view,center,(model.dimensions as Vector2).length())
	var tier: int = MODEL_LOD.choose(pixels,int(model.get("lod_tier",0)),MODEL_LOD.FAR_PIXELS,float(model.get("lod_extreme_pixels",MODEL_LOD.EXTREME_PIXELS))) if lod_enabled else 0
	if lod_override >= 0: tier = clampi(lod_override,0,2)
	model.lod_tier = tier
	model.lod_pixels = pixels
	for item in model.get("skinned_lods",[]):
		if item.node.mesh != item.meshes[tier]: item.node.mesh = item.meshes[tier]
	_lod_counts[tier] += 1
	return tier

func _industrial_smoke(model: Dictionary, entity: Dictionary) -> void:
	if quality_policy=="performance":return
	# Small continuous workshop steam, anchored to the real chimney mouth.
	# The visual clock is deterministic in frozen captures and independent of sim.
	if model.kind != "building" or model.spec.art != "power" or float(entity.get("construct_remaining",0.0)) > 0.0:
		return
	var root: Node3D = model.root
	if camera.global_position.distance_squared_to(root.global_position) > 90.0*90.0:
		return
	var ports:Array=model.smoke_ports
	var root_transform:Transform3D=root.global_transform
	# The building recipe owns chimney positions. Enlarged rooms and roofs can
	# move the stacks without leaving steam emerging from the previous model.
	for chimney: int in ports.size():
		for puff: int in 4:
			var phase: float = fposmod(elapsed*0.27 + float(puff)*0.25 + float(entity.id % 7)*0.09 + chimney*.12,1.0)
			var opacity: float = sin(phase*PI)*0.56
			var bucket: int = clampi(roundi(opacity*10.0),0,6)
			if bucket == 0:continue
			var local: Vector3 = ports[chimney]+Vector3.UP*(phase*1.65)
			local.x += phase*.40 + sin(phase*8.0+chimney)*.075
			local.z += phase*.19
			var size:float=(.28+sin(phase*PI)*.52)*float(model.smoke_size_factor)
			var transform:Transform3D=root_transform*Transform3D(Basis.IDENTITY.scaled(Vector3(size,size*.82,size)),local)
			_append_batch(steam_batches[bucket],transform)


func _aircraft_terrain_margin() -> float:
	if _air_terrain_margin>=0:return _air_terrain_margin
	var low: float=INF;var high: float=-INF
	for row: Array in sim.map.heights:
		for value in row:low=minf(low,float(value));high=maxf(high,float(value))
	_air_terrain_margin=maxf(0.0,high-low)
	return _air_terrain_margin


func _sync_aircraft_motion(model: Dictionary, entity: Dictionary) -> void:
	if float(model.get("air_motion_elapsed",-INF))==elapsed:return
	model.air_terrain_span=_aircraft_terrain_margin()
	var initialized: bool = model.has("visual_air_y")
	var previous_y: float = float(model.get("visual_air_y",0))
	var airborne: bool = bool(entity.get("airborne",true)) and float(entity.get("flight_height",0))>1.8
	if initialized and airborne != bool(model.get("air_logical_airborne",airborne)):
		model.air_transition = "takeoff" if airborne else "landing"
	model.air_logical_airborne = airborne
	AIR_VISUAL.update(model,entity,sim.map,frame_delta)
	var transition: String = str(model.get("air_transition",""))
	if initialized and not transition.is_empty():
		var target_y: float = float(model.visual_air_y)
		var rate: float = AIR_VISUAL.CLIMB_RATE if transition == "takeoff" else AIR_VISUAL.DESCENT_RATE
		model.visual_air_y = move_toward(previous_y,target_y,rate*maxf(0,frame_delta))
		model.flight_height = float(model.visual_air_y)-MAP.height_at(sim.map,entity.pos)
		model.airborne_visual = airborne or model.flight_height>.40
		if absf(float(model.visual_air_y)-target_y)<.01: model.erase("air_transition")
	model.air_motion_elapsed=elapsed
	var actual: float=float(model.visual_air_y)
	var logical: float=MAP.height_at(sim.map,entity.pos)+float(model.logical_flight_height)
	model.cull_radius=maxf(float(model.dimensions.x),float(model.dimensions.y))*.7+8.0+maxf(_aircraft_terrain_margin(),absf(actual-logical))


func _prepare_aircraft_motion() -> void:
	for id: int in models:
		var model: Dictionary=models[id]
		if bool(model.get("is_air",false)) and sim.entities.has(id):_sync_aircraft_motion(model,sim.entities[id])


func _is_infantry_model(model: Dictionary) -> bool:
	return model.kind=="unit" and (str(model.spec.get("art","")) in VOLUME.INFANTRY_ART or str(model.spec.get("armor_class",""))=="infantry")


func _update_aircraft_trails(model: Dictionary, entity: Dictionary) -> void:
	var pos: Vector2=entity.pos
	var previous: Vector2=model.get("air_trail_pos",pos)
	model.air_trail_pos=pos
	var current_world:=Vector3(pos.x,float(model.get("visual_air_y",MAP.height_at(sim.map,pos)+float(model.flight_height))),pos.y)
	if not model.has("air_trail_world"):model.air_trail_world=current_world
	var last_world: Vector3=model.air_trail_world
	var speed: float=previous.distance_to(pos)/maxf(frame_delta,.001)
	if frame_delta<=0 or not bool(model.get("airborne_visual",false)) or model.embarked or bool(model.get("fog_hidden",false)) or speed<maxf(2.5,float(model.spec.get("speed",8.0))*.45) or previous.distance_to(pos)>8:
		model.air_trail_world=current_world;return
	var distance: float=Vector2(current_world.x-last_world.x,current_world.z-last_world.z).length()
	var spacing: float=.8 if quality_policy=="performance" else .5
	if distance<spacing:return
	var dimensions: Vector3=model.volume.get("dimensions",Vector3(4,1,4))
	var samples: int=clampi(ceili(distance/spacing),1,4)
	var heading: float=-deg_to_rad(float(entity.alpha))
	var engine_z: Array=[0.0] if quality_policy=="performance" else [-dimensions.z*.18,dimensions.z*.18]
	for sample: int in range(1,samples+1):
		for z: float in engine_z:
			var tail: Vector3=Vector3(-dimensions.x*.42,.12,z).rotated(Vector3.UP,heading)
			var origin: Vector3=last_world.lerp(current_world,float(sample)/samples)+tail
			var start: Vector3=last_world.lerp(current_world,float(sample-1)/samples)+tail
			air_trails.append({"pos":origin,"start":start,"age":0.0,"life":AIR_TRAIL_LIFETIME,"radius":.20,"lod_tier":0,"owner":int(entity.id),"team":int(entity.team)})
	while air_trails.size()>(128 if quality_policy=="performance" else 384):air_trails.pop_front()
	model.air_trail_world=current_world


func _prepare_air_trail_batches() -> void:
	_air_trail_batches.clear()
	var shader:=Shader.new()
	shader.code="""shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_prepass_alpha;
void fragment() {
    float across=abs(UV.y-0.5)*2.0;
    float soft=1.0-smoothstep(0.2,1.0,across);
    float cloud=1.0;
    ALBEDO=vec3(0.83,0.83,0.80);
    ALPHA=soft*cloud*COLOR.a;
}
"""
	var material:=ShaderMaterial.new();material.shader=shader
	for sections: int in [4,2,1]:
		var vertices:=PackedVector3Array();var uv:=PackedVector2Array();var normals:=PackedVector3Array();var colors:=PackedColorArray()
		for index: int in sections:
			var a: float=float(index)/sections;var b: float=float(index+1)/sections
			for point: Vector2 in [Vector2(a,0),Vector2(b,0),Vector2(b,1),Vector2(a,0),Vector2(b,1),Vector2(a,1)]:
				vertices.append(Vector3(point.x-.5,0,point.y-.5));uv.append(point);normals.append(Vector3.UP);colors.append(Color.WHITE)
		var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_COLOR]=colors
		var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);mesh.surface_set_material(0,material)
		_air_trail_batches.append(_batch_descriptor(mesh,null,false,true))


func _update_air_trail_effects(delta: float) -> void:
	for index: int in range(air_trails.size()-1,-1,-1):
		var trail: Dictionary=air_trails[index];trail.age+=delta
		var progress: float=float(trail.age)/float(trail.life)
		if progress>=1.0:air_trails.remove_at(index);continue
		if int(trail.team)!=0 and not sim.position_visible_to(0,Vector2(trail.pos.x,trail.pos.z),"air"):continue
		if models.has(int(trail.owner)) and bool(models[int(trail.owner)].get("fog_hidden",false)):continue
		var center: Vector3=(trail.start+trail.pos)*.5+Vector3(0,progress*.05,0)
		var direction: Vector3=(trail.pos-trail.start).normalized()
		if direction.length_squared()<.5:continue
		var length: float=(trail.pos-trail.start).length()
		if not _point_in_view(center,length+1):continue
		var side: Vector3=direction.cross(Vector3.UP).normalized()
		var up: Vector3=side.cross(direction).normalized()
		var width: float=float(trail.radius)*(1.35+progress*3.2)
		var transform:=Transform3D(Basis(direction,up,side).scaled_local(Vector3(length,1,width)),center)
		var tier: int=_choose_effect_lod(trail,transform,_air_trail_batches[0].multi.mesh.get_aabb())
		_append_batch(_air_trail_batches[tier],transform,Color(1,1,1,(1.0-smoothstep(.15,1.0,progress))*.34))


func _cloud_receiver_mesh(rect: Rect2, step: int) -> ArrayMesh:
	var vertices:=PackedVector3Array();var normals:=PackedVector3Array()
	var min_x: int=maxi(0,floori(rect.position.x));var min_z: int=maxi(0,floori(rect.position.y))
	var max_x: int=mini(int(sim.map.size)-1,ceili(rect.end.x));var max_z: int=mini(int(sim.map.size)-1,ceili(rect.end.y))
	for z: int in range(min_z,max_z,step):
		for x: int in range(min_x,max_x,step):
			var ex: int=mini(x+step,max_x);var ez: int=mini(z+step,max_z)
			for point: Vector2 in [Vector2(x,z),Vector2(ex,z),Vector2(ex,ez),Vector2(x,z),Vector2(ex,ez),Vector2(x,ez)]:
				vertices.append(Vector3(point.x,_cursor_surface_y(point)+.028,point.y));normals.append(Vector3.UP)
	var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh


func _prepare_cloud_shadows() -> void:
	if not cloud_shadows.is_empty():return
	var shader:=Shader.new()
	shader.code="""shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_prepass_alpha;
uniform vec2 center;
uniform vec2 extent=vec2(5.5,3.7);
uniform float phase=0.0;
uniform float drift_time=0.0;
varying vec2 ground;
void vertex() { ground=(MODEL_MATRIX*vec4(VERTEX,1.0)).xz; }
void fragment() {
    vec2 drift=vec2(sin(drift_time*0.045+phase)*4.0,cos(drift_time*0.034+phase)*3.0);
    vec2 p=(ground-center-drift)/extent;
    float wash=exp(-dot(p,p)*1.75);
    wash+=exp(-dot(p-vec2(0.40,-0.25),p-vec2(0.40,-0.25))*3.8)*0.28;
    ALBEDO=vec3(0.03,0.035,0.045);
    ALPHA=wash*0.12;
}
"""
	var map_size: float=float(sim.map.size)
	for index: int in 6:
		var center:=Vector2(map_size*(.20+float(index%3)*.30),map_size*(.30+float(index/3)*.40))
		var rect:=Rect2(center-Vector2(13,11),Vector2(26,22))
		var material:=ShaderMaterial.new();material.shader=shader;material.set_shader_parameter("center",center);material.set_shader_parameter("phase",float(index)*1.71)
		var batches_for_patch: Array=[]
		for step: int in [1,2,4]:batches_for_patch.append(_batch_descriptor(_cloud_receiver_mesh(rect,step),material,false))
		cloud_shadows.append({"center":Vector3(center.x,MAP.height_at(sim.map,center),center.y),"radius":18.0,"bounds":AABB(Vector3(rect.position.x,0,rect.position.y),Vector3(rect.size.x,1,rect.size.y)),"lod_tier":0,"batches":batches_for_patch,"material":material})


func _update_cloud_shadows() -> void:
	_prepare_cloud_shadows()
	for patch: Dictionary in cloud_shadows:
		if not _point_in_view(patch.center,float(patch.radius)):continue
		patch.material.set_shader_parameter("drift_time",elapsed)
		var tier: int=_choose_effect_lod(patch,Transform3D.IDENTITY,patch.bounds)
		if quality_policy=="performance":tier=maxi(tier,1)
		_append_batch(patch.batches[tier],Transform3D.IDENTITY)


func _corpse_fade_material(source: ShaderMaterial) -> ShaderMaterial:
	var key: int=source.get_instance_id()
	if _corpse_materials.has(key): return _corpse_materials[key]
	var material: ShaderMaterial=source.duplicate()
	var shader:=Shader.new()
	shader.code=source.shader.code.replace("depth_draw_opaque","depth_prepass_alpha, blend_mix").replace("ALPHA = alpha;","ALPHA = alpha * COLOR.a;").replace("ALPHA = pigment.a;","ALPHA = pigment.a * COLOR.a;").replace("ALPHA_SCISSOR_THRESHOLD = 0.45;","if (pigment.a < 0.45) { discard; }").replace("ALPHA_SCISSOR_THRESHOLD = 0.15;","if (alpha < 0.15) { discard; }")
	material.shader=shader;_corpse_materials[key]=material
	return material


func _start_infantry_fall(model: Dictionary) -> void:
	if model.volumetric and bool(model.volume.get("paper_infantry",false)):
		VOLUME.set_infantry_pose(model.volume,"death")
		_refresh_paper_infantry_batches(model)
		model.paper_corpse_batches=[]
		for batch: Dictionary in model.render_parts[0].lod_batches:
			var mesh: Mesh = batch.multi.mesh
			model.paper_corpse_batches.append(_batch_descriptor(mesh,_corpse_fade_material(mesh.surface_get_material(0)),false,true))
	if not model.volumetric:
		_set_paper_state(model,"death")
		var material: ShaderMaterial=_corpse_fade_material(model.graphic.mesh.surface_get_material(0))
		model.corpse_batches=[]
		for batch: Dictionary in model.paper_lod_batches: model.corpse_batches.append(_batch_descriptor(batch.multi.mesh,material,false,true))
	ghosts.append({"kind":"infantry_fall","model":model,"age":0.0,"life":2.2,"start":model.art_root.transform})


func _spawn_paper_fragments(model: Dictionary) -> void:
	if model.volumetric: _spawn_model_fragments(model);return
	var source: Mesh=model.graphic.mesh
	var raw: Array=source.surface_get_arrays(0)
	var vertices: PackedVector3Array=raw[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array=raw[Mesh.ARRAY_TEX_UV]
	var first: Vector3=vertices[0];var uv_scale:=Vector2.ZERO
	for index: int in vertices.size():
		if absf(vertices[index].x-first.x)>.001: uv_scale.x=(uv[index].x-uv[0].x)/(vertices[index].x-first.x)
		if absf(vertices[index].y-first.y)>.001: uv_scale.y=(uv[index].y-uv[0].y)/(vertices[index].y-first.y)
	var bounds: AABB=source.get_aabb()
	var rows: int=3 if quality_policy=="performance" else 4
	for index: int in rows*2:
		if effects.size()>=_effect_limit(): break
		var x: int=index%2;var y: int=index/2
		var low:=Vector2(bounds.position.x+float(x)*bounds.size.x/2,bounds.position.y+float(y)*bounds.size.y/rows)
		var high:=low+Vector2(bounds.size.x/2,bounds.size.y/rows)
		var center:=Vector3((low.x+high.x)*.5,(low.y+high.y)*.5,first.z)
		var points: Array[Vector3]=[Vector3(low.x,low.y,first.z),Vector3(high.x,low.y,first.z),Vector3(high.x,high.y,first.z),Vector3(low.x,low.y,first.z),Vector3(high.x,high.y,first.z),Vector3(low.x,high.y,first.z)]
		var positions:=PackedVector3Array();var coordinates:=PackedVector2Array();var normals:=PackedVector3Array()
		for point: Vector3 in points:
			positions.append(point-center);coordinates.append(uv[0]+(Vector2(point.x,point.y)-Vector2(first.x,first.y))*uv_scale);normals.append(Vector3.BACK)
		var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=positions;arrays[Mesh.ARRAY_TEX_UV]=coordinates;arrays[Mesh.ARRAY_NORMAL]=normals
		var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);mesh.surface_set_material(0,source.surface_get_material(0))
		var root:=Node3D.new();add_child(root);root.global_transform=Transform3D(model.art_root.global_basis,model.art_root.global_transform*center)
		var graphic=_pose_mesh(mesh);root.add_child(graphic)
		var angle: float=destruction_rng.randf_range(0,TAU)
		var velocity:=Vector3(cos(angle)*destruction_rng.randf_range(.7,1.5),destruction_rng.randf_range(1.3,2.1),sin(angle)*destruction_rng.randf_range(.7,1.5))
		var launch: Vector3=root.global_position
		var settle: float=(velocity.y+sqrt(velocity.y*velocity.y+19.6*maxf(launch.y-_cursor_surface_y(Vector2(launch.x,launch.z)),0)))/9.8
		var landing: Vector3=launch+velocity*settle
		_add_effect({"root":root,"graphic":graphic,"kind":"debris","paper_fragment":true,"age":0.0,"delay":0.0,"base":Vector3.ONE,"velocity":root.global_basis.inverse()*velocity,"world_velocity":velocity,"world_floor":_cursor_surface_y(Vector2(landing.x,landing.z))+.03,"settle_age":settle,"spin":Vector3(destruction_rng.randf_range(-4,4),destruction_rng.randf_range(-4,4),destruction_rng.randf_range(-4,4)),"life":5.0})


func _start_sell_fold(model: Dictionary) -> void:
	ghosts.append({"kind":"sell_fold","model":model,"age":0.0,"life":.85,"start_scale":model.art_root.scale})


func _queue_fragment_warm(source: Mesh, material: Material) -> void:
	var key: String=str(source.get_instance_id())+":"+str(material.get_instance_id() if material!=null else 0)
	if _fragment_warm_sources.has(key): return
	_fragment_warm_sources[key]=true
	BATTLEFIELD_DAMAGE.queue_fragments(source)
	_fragment_warm_queue.push_front({"source":source,"material":material,"index":0})


func _warm_fragment_batches(budget_us: int) -> void:
	var started: int=Time.get_ticks_usec()
	var attempts: int=0
	while not _fragment_warm_queue.is_empty() and Time.get_ticks_usec()-started<budget_us:
		var pending: Dictionary=_fragment_warm_queue[0]
		var pieces: Array=BATTLEFIELD_DAMAGE.peek_fragments(pending.source)
		if pieces.is_empty():
			_fragment_warm_queue.append(_fragment_warm_queue.pop_front())
			attempts+=1
			if attempts>=_fragment_warm_queue.size(): return
			continue
		var piece: Dictionary=pieces[int(pending.index)]
		for mesh: Mesh in piece.lod_meshes:
			var batch: Dictionary=_batch_descriptor(mesh,pending.material)
			if batch.multi.instance_count==0:
				batch.multi.instance_count=8
				batch.multi.visible_instance_count=0
				batch.node.visible=false
				batch.capacity=8
		pending.index+=1
		if int(pending.index)>=pieces.size(): _fragment_warm_queue.pop_front()


func _is_tracked_vehicle(model: Dictionary) -> bool:
	return model.kind == "unit" and model.volumetric and not bool(model.get("direct_skinned",false)) and model.get("domain","ground") == "ground" and not bool(model.volume.get("infantry",false)) and str(model.spec.get("art","")) in ["tank","heavy_tank","assault","artillery","advanced","harvester","aa"]


func _update_tread_marks(model: Dictionary, entity: Dictionary) -> void:
	var pos: Vector2 = entity.pos
	var heading: float = deg_to_rad(float(entity.alpha))
	var last: Vector2 = model.get("track_pos",pos)
	var last_heading: float = float(model.get("track_heading",heading))
	var turn: float = wrapf(heading-last_heading,-PI,PI)
	var distance: float = pos.distance_to(last)
	if distance > 4.0 or not model.has("track_pos"):
		model.track_pos = pos
		model.track_heading = heading
		return
	# Rotation is sampled even when the rule position stays fixed. Each tread
	# sweeps its own arc, creating the paired circular scuffs of a pivot turn.
	if distance < .27 and absf(turn) < deg_to_rad(4.0): return
	var samples: int = clampi(maxi(ceili(distance/.22),ceili(absf(turn)/deg_to_rad(4.0))),1,24)
	var width: float = float(model.volume.dimensions.z)*.39
	for sample: int in range(1,samples+1):
		var progress: float = float(sample)/samples
		var point: Vector2 = last.lerp(pos,progress)
		var angle: float = last_heading+turn*progress
		var side := Vector2(-sin(angle),cos(angle))*width
		for offset: Vector2 in [-side,side]:
			var mark: Vector2 = point+offset
			if not sim._in_bounds(mark) or MAP.terrain_at(sim.map,mark)==MAP.WATER: continue
			var basis := Basis(Vector3.UP,-angle)*Basis(Vector3.RIGHT,-PI*.5)
			tracks.append({"pos":Vector3(mark.x,MAP.height_at(sim.map,mark)+.038,mark.y),"basis":basis.scaled_local(Vector3(.28,.22,1)),"age":0.0})
	while tracks.size()>2400: tracks.pop_front()
	model.track_pos = pos
	model.track_heading = heading


func _update_tank_braking(model: Dictionary, entity: Dictionary) -> void:
	var delta: float = maxf(frame_delta,.001)
	var previous: Vector2 = model.get("motion_pos",entity.pos)
	var moving: bool = entity.get("state","") in ["move","returning"]
	var speed: float = minf(previous.distance_to(entity.pos)/delta,float(model.spec.get("speed",4.0)))
	if moving:
		model.motion_speed = lerpf(float(model.get("motion_speed",speed)),speed,clampf(delta*10.0,0,1))
		model.brake_age = .55
	elif bool(model.get("motion_moving",false)):
		model.brake_speed = float(model.get("motion_speed",0.0))
		model.brake_age = 0.0
	model.motion_pos = entity.pos
	model.motion_moving = moving
	var age: float = float(model.get("brake_age",.55))
	if not moving and age < .55:
		age += delta
		model.brake_age = age
		var phase: float = clampf(age/.55,0,1)
		var envelope: float = sin(phase*PI)*(1.0-phase)
		# Only the artwork overshoots. Rule position, collision, destination and
		# turret aiming stay authoritative, preventing a brake from entering walls.
		model.art_root.position.x = clampf(float(model.get("brake_speed",0.0))*.085,0,.22)*envelope
		model.art_root.rotation.z = -.035*envelope
	else:
		model.art_root.position.x = 0.0
		model.art_root.rotation.z = 0.0


func _set_building_damage(model: Dictionary, stage: int) -> void:
	if model.kind != "building" or model.scaffold or not model.volumetric or int(model.get("damage_stage",0))==stage: return
	for part: Dictionary in model.render_parts:
		if not part.has("healthy_lod_batches"):
			part.healthy_lod_batches = part.lod_batches
			part.healthy_mesh = part.node.mesh
			part.damage_batches = {}
			if part.has("ink_batch"):
				part.healthy_ink_lod_batches = part.ink_lod_batches
				part.healthy_paper_lod_batches = part.paper_lod_batches
		if stage > 0 and not part.damage_batches.has(stage):
			var stages: Dictionary = {"paint":[],"ink":[],"paper":[]}
			for tier: int in 3:
				var source: Mesh = part.healthy_lod_batches[tier].multi.mesh
				stages.paint.append(_batch_descriptor(BATTLEFIELD_DAMAGE.damaged(source,stage),part.node.material_override,true))
				if part.has("ink_batch"):
					stages.ink.append(_batch_descriptor(BATTLEFIELD_DAMAGE.damaged(part.healthy_ink_lod_batches[tier].multi.mesh,stage),_vehicle_border_material(false),false))
					stages.paper.append(_batch_descriptor(BATTLEFIELD_DAMAGE.damaged(part.healthy_paper_lod_batches[tier].multi.mesh,stage),_vehicle_border_material(true),false))
			_queue_fragment_warm(stages.paint[1].multi.mesh,part.node.material_override)
			part.damage_batches[stage] = stages
		part.lod_batches = part.healthy_lod_batches if stage==0 else part.damage_batches[stage].paint
		part.node.mesh = part.healthy_mesh if stage==0 else part.lod_batches[0].multi.mesh
		if part.has("ink_batch"):
			part.ink_lod_batches = part.healthy_ink_lod_batches if stage==0 else part.damage_batches[stage].ink
			part.paper_lod_batches = part.healthy_paper_lod_batches if stage==0 else part.damage_batches[stage].paper
	model.damage_stage = stage


func _damage_smoke(model: Dictionary, entity: Dictionary) -> void:
	if int(model.get("damage_stage",0))==0: return
	var phase: float = fmod(elapsed*.35+float(entity.id)*.618,1.0)
	var dimensions: Vector3 = model.volume.dimensions
	var local := Vector3(dimensions.x*.12,dimensions.y*.67+phase*.65,dimensions.z*.12)
	var bucket: int = clampi(roundi((1.0-phase)*4.0),0,6)
	var size: float = (.20+phase*.48)*(1.2 if int(model.damage_stage)==2 else 1.0)
	_append_batch(steam_batches[bucket],model.root.global_transform*Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*size),local))


func _effect_limit() -> int:
	return 96 if quality_policy=="performance" else 360


func set_destruction_seed(value: int) -> void:
	# Runtime randomizes once per world; only captures/tests supply a seed.
	destruction_rng.seed=value


func _scatter_velocity(pattern: int, index: int, count: int, radial: Vector3, forward: Vector3, bias: Vector3, width: float) -> Vector3:
	var speed: float=clampf(width*.35,1.1,2.6)
	var side: Vector3=Vector3(-forward.z,0,forward.x)
	var lift: float=destruction_rng.randf_range(2.0,3.9)
	var velocity: Vector3
	match pattern:
		1: # Forward plates shear away; the remaining pieces fall to either side.
			velocity=forward*destruction_rng.randf_range(2.0,4.0)+side*destruction_rng.randf_range(-1.6,1.6)
			lift=destruction_rng.randf_range(1.4,2.8)
		2: # An off-centre hit throws most mass into one broad, uneven fan.
			velocity=bias*destruction_rng.randf_range(1.6,3.2)+radial*.7
			if index%4==0: velocity=-bias*.7+radial*.8
		3: # Roof/turret plates rise first, then settle close to the footprint.
			velocity=radial*destruction_rng.randf_range(.55,1.0)
			lift=destruction_rng.randf_range(4.2,5.8)
		_: velocity=radial*destruction_rng.randf_range(1.15,1.9)
	velocity*=speed
	velocity.y=lift
	return velocity


func _spawn_model_fragments(model: Dictionary) -> void:
	last_scatter_pattern=destruction_rng.randi_range(0,3)
	if not model.volumetric or bool(model.get("direct_skinned",false)):
		var pos: Vector2 = Vector2(model.root.position.x,model.root.position.z)
		_spawn_debris(pos,float(model.dimensions.x)*.45,float(model.dimensions.y)*.5+float(model.get("flight_height",0.0)))
		return
	var candidates: Array=[]
	for part: Dictionary in model.render_parts:
		for piece: Dictionary in BATTLEFIELD_DAMAGE.fragments(part.lod_batches[1].multi.mesh):
			candidates.append({"piece":piece,"transform":part.node.global_transform,"material":part.node.material_override})
	var budget: int=6 if quality_policy=="performance" else (12 if model.kind=="building" else 10)
	budget=mini(budget,candidates.size())
	if budget==0: return
	var stride: float=float(candidates.size())/budget
	var first: float=destruction_rng.randf_range(0,stride*.9)
	var forward: Vector3=model.root.global_basis.x.normalized()
	var bias: Vector3=Vector3.RIGHT.rotated(Vector3.UP,destruction_rng.randf_range(0,TAU))
	var center: Vector3=model.root.global_position
	for index: int in budget:
		if effects.size()>=_effect_limit(): return
		var selected: Dictionary=candidates[mini(int(first+index*stride),candidates.size()-1)]
		var piece: Dictionary=selected.piece
		var transform: Transform3D=selected.transform
		var root:=Node3D.new();add_child(root)
		root.global_transform=Transform3D(transform.basis,transform*piece.center)
		var graphic=_pose_mesh(piece.mesh,selected.material);root.add_child(graphic)
		var launch: Vector3=root.global_position
		var radial: Vector3=Vector3(launch.x-center.x,0,launch.z-center.z)
		if radial.length_squared()<.001: radial=Vector3.RIGHT.rotated(Vector3.UP,float(index)*TAU/budget)
		radial=radial.normalized()
		var velocity: Vector3=_scatter_velocity(last_scatter_pattern,index,budget,radial,forward,bias,float(model.dimensions.x))
		var settle_age: float=(velocity.y+sqrt(velocity.y*velocity.y+19.6*maxf(launch.y-_cursor_surface_y(Vector2(launch.x,launch.z)),0.0)))/9.8
		var landing: Vector3=launch+velocity*settle_age
		var floor_y: float=_cursor_surface_y(Vector2(landing.x,landing.z))+.07
		var spin:=Vector3(destruction_rng.randf_range(-3.5,3.5),destruction_rng.randf_range(-4,4),destruction_rng.randf_range(-3.5,3.5))
		_add_effect({"root":root,"graphic":graphic,"kind":"debris","age":0.0,"delay":0.0,"base":Vector3.ONE,"velocity":transform.basis.inverse()*velocity,"world_velocity":velocity,"world_floor":floor_y,"lod_meshes":piece.lod_meshes,"floor":floor_y-launch.y,"settle_age":settle_age,"spin":spin,"scatter_pattern":last_scatter_pattern,"life":20.0 if model.kind=="building" else 14.0})


func _spawn_crater(pos: Vector2, radius: float, height: float = 0.0) -> void:
	if height>2.0 or not sim._in_bounds(pos) or MAP.terrain_at(sim.map,pos)==MAP.WATER: return
	var size: float=clampf(radius,.25,5.2)
	var center: float=MAP.height_at(sim.map,pos)
	var normal:=Vector3(-(MAP.height_at(sim.map,pos+Vector2(.4,0))-center)/.4,1.0,-(MAP.height_at(sim.map,pos+Vector2(0,.4))-center)/.4).normalized()
	var right: Vector3=Vector3.RIGHT.slide(normal).normalized()
	var basis:=Basis(right,normal,right.cross(normal))
	basis=basis.rotated(normal,destruction_rng.randf_range(0,TAU)).scaled_local(Vector3(size*destruction_rng.randf_range(.92,1.16),1.0,size*destruction_rng.randf_range(.86,1.08)))
	craters.append({"transform":Transform3D(basis,Vector3(pos.x,center+.024,pos.y)),"radius":size*1.2,"age":0.0,"opacity":destruction_rng.randf_range(.56,.78),"seed":destruction_rng.randf()})
	while craters.size()>192: craters.pop_front()


func _crater_mesh() -> ArrayMesh:
	var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(-1,0,-1),Vector3(1,0,-1),Vector3(1,0,1),Vector3(-1,0,-1),Vector3(1,0,1),Vector3(-1,0,1)])
	arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP])
	arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,0),Vector2(1,1),Vector2(0,1)])
	arrays[Mesh.ARRAY_COLOR]=PackedColorArray([Color.WHITE,Color.WHITE,Color.WHITE,Color.WHITE,Color.WHITE,Color.WHITE])
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var shader:=Shader.new()
	shader.code="""shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_prepass_alpha;
void fragment() {
    vec2 p=(UV-vec2(0.5))*2.0;
    float r=length(p);
    float grain=0.95+0.05*sin(p.x*22.0+p.y*17.0+COLOR.r*13.0);
    float core=exp(-5.2*r*r);
    float haze=exp(-2.3*r*r)*0.24;
    float streak=exp(-p.y*p.y*85.0)*exp(-pow(p.x-0.40,2.0)*8.0)*0.24;
    streak+=exp(-pow(p.y+p.x*0.37,2.0)*110.0)*exp(-pow(p.x+0.33,2.0)*9.0)*0.15;
    float edge=1.0-smoothstep(0.76,1.0,r);
    ALBEDO=vec3(0.008,0.007,0.006);
    ALPHA=clamp((core+haze+streak)*grain*COLOR.a*edge,0.0,0.85);
}
"""
	var material:=ShaderMaterial.new();material.shader=shader
	mesh.surface_set_material(0,material)
	return mesh


func _air_crash_visible(model: Dictionary, position: Vector3) -> bool:
	return int(model.team)==0 or sim.position_visible_to(0,Vector2(position.x,position.z),"air")


func _prepare_air_crash_smoke_batches() -> void:
	_air_crash_smoke_lods.clear()
	var shader:=Shader.new()
	shader.code="""shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_prepass_alpha;
void fragment() {
    float facing=clamp(abs(dot(normalize(NORMAL),normalize(VIEW))),0.0,1.0);
    ALBEDO=COLOR.rgb;
    ALPHA=COLOR.a*smoothstep(0.0,0.60,facing);
}
"""
	var material:=ShaderMaterial.new();material.shader=shader
	for mesh: Mesh in effect_spheres:_air_crash_smoke_lods.append(_batch_descriptor(mesh,material,false,true))


func _add_air_crash_smoke(position: Vector3, team: int, radius: float = .8) -> void:
	air_crash_smoke.append({"pos":position,"team":team,"age":0.0,"life":2.8,"radius":radius,"lod_tier":0})
	while air_crash_smoke.size()>(96 if quality_policy=="performance" else 192):air_crash_smoke.pop_front()


func _update_air_crash_smoke(delta: float) -> void:
	for index: int in range(air_crash_smoke.size()-1,-1,-1):
		var puff: Dictionary=air_crash_smoke[index];puff.age+=delta
		var progress: float=float(puff.age)/float(puff.life)
		if progress>=1.0:air_crash_smoke.remove_at(index);continue
		var position: Vector3=puff.pos+Vector3(progress*.20,progress*.85,progress*.12)
		if int(puff.team)!=0 and not sim.position_visible_to(0,Vector2(position.x,position.z),"air"):continue
		if not _point_in_view(position,2.5):continue
		var scale: float=float(puff.radius)*(.7+progress*.85)
		var transform:=Transform3D(Basis.IDENTITY.scaled(Vector3(scale,scale*1.1,scale)),position)
		var tier: int=_choose_effect_lod(puff,transform,effect_spheres[0].get_aabb())
		_append_batch(_air_crash_smoke_lods[tier],transform,Color(.105,.102,.095,(1.0-smoothstep(.35,1.0,progress))*.78))


func _start_aircraft_crash(model: Dictionary) -> void:
	var existing: Array=ghosts.filter(func(ghost):return ghost.kind=="air_crash")
	if existing.size()>=(6 if quality_policy=="performance" else MAX_AIR_CRASHES):
		var oldest: Dictionary=existing[0]
		# Budget eviction must never fabricate a contact blast in mid-air.
		_retire_aircraft_crash(oldest)
		ghosts.erase(oldest)
	var origin: Vector3=model.art_root.global_position
	var velocity: Vector2=model.get("visual_air_measured_velocity",model.get("visual_air_velocity",Vector2.ZERO))
	var fallback: Vector2=model.get("death_velocity",Vector2.ZERO)
	if velocity.length()<.1 and fallback.length()>.1:velocity=fallback
	var max_speed: float=maxf(float(model.spec.get("speed",8.0))*1.5,8.0)
	velocity=velocity.limit_length(max_speed)
	var initial_basis: Basis=model.art_root.basis
	model.root.position=origin
	model.art_root.position=Vector3.ZERO
	model.flight_height=0.0
	model.hp_root.visible=false;model.ring.visible=false
	_air_crash_serial+=1
	var crash: Dictionary={"kind":"air_crash","model":model,"age":0.0,"life":AIR_CRASH_MAX_LIFE,"start":origin,"velocity":Vector3(velocity.x,-.35,velocity.y),"basis":initial_basis,"smoke_clock":0.0,"serial":_air_crash_serial,"impacted":false}
	ghosts.append(crash)
	var exhaust: Vector3=origin-Vector3(velocity.x,0,velocity.y).normalized()*float(model.dimensions.x)*.24+Vector3.UP*float(model.dimensions.y)*.3
	_add_air_crash_smoke(exhaust,int(model.team),clampf(float(model.dimensions.x)*.30,1.2,1.8))


func _crash_world_bounds(model: Dictionary) -> AABB:
	var bounds:=AABB();var first: bool=true
	for part: Dictionary in model.render_parts:
		var box: AABB=part.node.global_transform*part.node.mesh.get_aabb()
		bounds=box if first else bounds.merge(box);first=false
	return bounds if not first else AABB(model.root.global_position,Vector3(.5,.5,.5))


func _update_aircraft_crash(crash: Dictionary, delta: float) -> bool:
	var model: Dictionary=crash.model
	var age: float=float(crash.age)
	var velocity: Vector3=crash.velocity
	var distance_time: float=age-.035*age*age
	var position: Vector3=crash.start+Vector3(velocity.x*distance_time,velocity.y*age-3.8*age*age,velocity.z*distance_time)
	position.x=clampf(position.x,.5,float(sim.map.size)-.5);position.z=clampf(position.z,.5,float(sim.map.size)-.5)
	model.root.position=position
	model.art_root.basis=(crash.basis as Basis)*Basis(Vector3.BACK,-minf(age*.58,.72))*Basis(Vector3.RIGHT,sin(age*2.6)*.10)
	var bounds: AABB=_crash_world_bounds(model)
	var lowest_surface: float=-INF
	for point: Vector2 in [Vector2(position.x,position.z),Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.end.x,bounds.position.z),Vector2(bounds.position.x,bounds.end.z),Vector2(bounds.end.x,bounds.end.z)]:
		point=Vector2(clampf(point.x,0,float(sim.map.size)-1.01),clampf(point.y,0,float(sim.map.size)-1.01))
		lowest_surface=maxf(lowest_surface,_cursor_surface_y(point))
	if bounds.position.y<=lowest_surface+.08:
		model.root.position.y+=maxf(0.0,lowest_surface+.08-bounds.position.y)
		_finish_aircraft_crash(crash)
		return true
	if age>=AIR_CRASH_MAX_LIFE:
		_retire_aircraft_crash(crash)
		return true
	var visible: bool=_air_crash_visible(model,position)
	crash.smoke_clock+=delta
	var interval: float=.13 if quality_policy=="performance" else .075
	if visible and float(crash.smoke_clock)>=interval:
		crash.smoke_clock=fmod(float(crash.smoke_clock),interval)
		var exhaust: Vector3=position-Vector3(velocity.x,0,velocity.z).normalized()*float(model.dimensions.x)*.24+Vector3.UP*float(model.dimensions.y)*.3
		_add_air_crash_smoke(exhaust,int(model.team),clampf(float(model.dimensions.x)*.30,1.2,1.8))
	if not visible or not _point_in_view(position,float(model.cull_radius)):return false
	var tier: int=_update_model_lod(model)
	for part: Dictionary in model.render_parts:
		_append_batch(part.lod_batches[tier],part.node.global_transform)
		if part.has("ink_batch"):
			_append_batch(part.ink_lod_batches[tier],part.node.global_transform);_append_batch(part.paper_lod_batches[tier],part.node.global_transform)
	var point:=Vector2(position.x,position.z)
	var shadow_transform:=Transform3D(Basis.IDENTITY.scaled(Vector3(float(model.dimensions.x)*.35,1,float(model.dimensions.x)*.16)),Vector3(point.x,_cursor_surface_y(point)+.03,point.y))
	_append_batch(_fade_shadow_batch,shadow_transform,Color(.16,.14,.12,.12))
	return false


func _retire_aircraft_crash(crash: Dictionary) -> void:
	if bool(crash.get("impacted",false)):return
	crash.impacted=true
	_pool_model(crash.model)


func _finish_aircraft_crash(crash: Dictionary) -> void:
	if bool(crash.get("impacted",false)):return
	crash.impacted=true
	var model: Dictionary=crash.model
	var position: Vector3=model.root.global_position
	var point:=Vector2(position.x,position.z)
	if _air_crash_visible(model,position):
		# Visual contact only: no event is added, no damage or projectile is run.
		_spawn_effect(point,"impact",clampf(float(model.dimensions.x)*.22,.65,1.6),position.y-MAP.height_at(sim.map,point))
		_add_air_crash_smoke(position,int(model.team),1.0)
		_spawn_model_fragments(model)
		if MAP.terrain_at(sim.map,point)!=MAP.WATER:_spawn_crater(point,clampf(float(model.dimensions.x)*.3,.6,2.5),0.0)
	_pool_model(model)


func _start_death(model: Dictionary) -> void:
	if bool(model.get("fog_hidden",false)):
		_pool_model(model);return
	if bool(model.get("removed_without_burst",false)):
		if model.kind=="building": _start_sell_fold(model)
		else: _pool_model(model)
		return
	if bool(model.get("creator_crushed",false)):
		if quality_policy != "performance": CREATOR_CRUSH.spawn(self,model)
		_pool_model(model)
		return
	_destroyed_this_frame[int(model.get("entity_id",-1))] = true
	if _is_infantry_model(model):
		if str(model.get("death_style","infantry_fall"))=="infantry_shatter":
			_spawn_paper_fragments(model);_pool_model(model)
		else: _start_infantry_fall(model)
		return
	if bool(model.get("is_air",false)) and bool(model.get("airborne_visual",float(model.flight_height)>1.8)):
		_retired_air_offsets[int(model.get("entity_id",-1))]=float(model.get("visual_air_y",model.art_root.global_position.y))-MAP.height_at(sim.map,Vector2(model.root.position.x,model.root.position.z))-float(model.get("logical_flight_height",model.get("death_flight_height",0.0)))
		_start_aircraft_crash(model)
		return
	var origin: Vector3 = model.root.global_position
	var pos := Vector2(origin.x,origin.z)
	var dimensions: Vector3 = model.volume.get("dimensions",Vector3(model.dimensions.x,model.dimensions.y,.5)) if model.volumetric else Vector3(model.dimensions.x,model.dimensions.y,.5)
	var height: float = origin.y-MAP.height_at(sim.map,pos)+float(model.get("flight_height",0.0)) + dimensions.y * .5
	var radius: float = maxf(dimensions.x,dimensions.z) * .52
	_spawn_effect(pos,"death",radius,height,dimensions)
	_spawn_smoke(pos,radius,height,true)
	if model.kind == "building" or _is_tracked_vehicle(model): _spawn_crater(pos,radius * .85,float(model.get("flight_height",0.0)))
	_spawn_model_fragments(model)
	# The blast replaces the intact model immediately. Cached fragment meshes
	# own their immutable geometry, so the original hierarchy can be reused.
	_pool_model(model)


func _update_deaths(delta: float) -> void:
	for index: int in range(ghosts.size()-1,-1,-1):
		var ghost: Dictionary=ghosts[index];ghost.age+=delta
		var model: Dictionary=ghost.model
		if ghost.kind=="air_crash":
			if _update_aircraft_crash(ghost,delta):ghosts.remove_at(index)
			continue
		var progress: float=clampf(float(ghost.age)/float(ghost.life),0,1)
		if progress>=1.0: _pool_model(model);ghosts.remove_at(index);continue
		if not _point_in_view(model.root.global_position,float(model.cull_radius)): continue
		var tier: int=_update_model_lod(model)
		if ghost.kind=="sell_fold":
			var fold: float=smoothstep(0,.95,progress)
			model.art_root.scale=ghost.start_scale*Vector3(1.0-fold*.45,1.0-fold*.97,1.0-fold*.45)
			for part: Dictionary in model.render_parts:
				_append_batch(part.lod_batches[tier],part.node.global_transform)
				if part.has("ink_batch"):
					_append_batch(part.ink_lod_batches[tier],part.node.global_transform);_append_batch(part.paper_lod_batches[tier],part.node.global_transform)
		else:
			var pose: Transform3D=ghost.start
			pose.basis=pose.basis.rotated(Vector3.RIGHT,-PI*.46*smoothstep(0,.28,progress))
			model.art_root.transform=pose
			var fade: float=1.0-smoothstep(.58,1.0,progress)
			if not model.volumetric: _append_batch(model.corpse_batches[tier],model.root.global_transform*pose,Color(1,1,1,fade))
			elif bool(model.volume.get("paper_infantry",false)):
				_append_batch(model.paper_corpse_batches[tier],model.render_parts[0].node.global_transform,Color(1,1,1,fade))
			else:
				for part: Dictionary in model.render_parts: _append_batch(part.lod_batches[tier],part.node.global_transform)
			_append_batch(_fade_shadow_batch,model.root.global_transform*model.shadow.transform,Color(.19,.15,.1,fade*.16))


func _visual_air_offset(id: int) -> float:
	if models.has(id) and bool(models[id].get("is_air",false)):
		var model: Dictionary=models[id]
		var point:=Vector2(model.root.position.x,model.root.position.z)
		return float(model.get("visual_air_y",model.art_root.global_position.y))-MAP.height_at(sim.map,point)-float(model.get("logical_flight_height",model.flight_height))
	return float(_retired_air_offsets.get(id,0.0))


func _projectile_source_air_offset(projectile: Dictionary) -> float:
	var source: int=int(projectile.get("source",projectile.get("source_id",-1)))
	if source<0:return 0.0
	var key: String=str(source)+":"+str(projectile.get("start",Vector2.ZERO))+":"+str(projectile.get("target",-1))+":"+str(roundi((float(sim.time)-float(projectile.get("elapsed",0.0)))*1000.0))
	if not _projectile_air_offsets.has(key):
		if _projectile_air_offsets.size()>512:_projectile_air_offsets.clear()
		_projectile_air_offsets[key]=_visual_air_offset(source)
	return float(_projectile_air_offsets[key])


func _sync_projectiles() -> void:
	if quality_policy=="performance":
		for shell in shells:shell.queue_free()
		shells.clear()
		_sync_data_projectiles()
		return
	while shells.size() < sim.projectiles.size():
		var shell := Node3D.new()
		add_child(shell)
		var graphic = _pose_mesh(shell_mesh,projectile_material)
		graphic.visible=false
		shell.add_child(graphic)
		shells.append(shell)
	while shells.size() > sim.projectiles.size():
		shells.pop_back().queue_free()
	for i in range(sim.projectiles.size()):
		var projectile: Dictionary = sim.projectiles[i]
		if not _projectile_visible(projectile): continue
		if str(projectile.get("trajectory","")) == "gravity_bomb":
			var bombs = load("res://scripts/zeppelin_weapons.gd")
			var bomb_transform: Transform3D = bombs.bomb_transform(projectile)
			if _point_in_view(bomb_transform.origin,2.0): _batch(bombs.bomb_mesh(),bomb_transform)
			continue
		var start: Vector2 = projectile.start
		var landing: Vector2 = projectile.landing
		var progress: float = clampf(float(projectile.elapsed) / maxf(float(projectile.duration), 0.001),0,1)
		var source_height: float=float(projectile.get("source_height",0.0))
		var source := Vector3(start.x,MAP.height_at(sim.map,start)+source_height+(0.0 if bool(projectile.get("garrison_fire",false)) else .9),start.y)
		if projectile.has("spec") and projectile.has("heading") and not bool(projectile.get("garrison_fire",false)):
			var spec: Dictionary = sim.data_for(projectile.spec)
			var kind: String = "building" if sim.rules.buildings.has(projectile.spec) else "unit"
			if VOLUME.supports(spec,kind):
				source = Vector3(start.x,MAP.height_at(sim.map,start)+source_height,start.y) + VOLUME.muzzle_offset(spec,kind,int(projectile.team),float(projectile.get("body_heading",projectile.heading)),float(projectile.heading))
		source.y+=_projectile_source_air_offset(projectile)
		var destination := Vector3(landing.x,MAP.height_at(sim.map,landing)+float(projectile.get("target_height",.15))+_visual_air_offset(int(projectile.get("target",-1))),landing.y)
		var nail:bool=sim.rules.weapons.get(str(projectile.get("weapon","")),{}).get("trajectory","")=="nail"
		var arc: float = 0.0 if nail else clampf(start.distance_to(landing)*.045,.08,.6)
		shells[i].scale=Vector3(.35,.35,2.4) if nail else Vector3.ONE
		shells[i].position = source.lerp(destination,progress)+Vector3.UP*(4.0*progress*(1.0-progress))*arc
		var direction: Vector3 = destination-source
		shells[i].rotation.y = -atan2(direction.z,direction.x)
		var graphic:Variant=shells[i].get_child(0)
		graphic.rotation.z = atan2(direction.y+4.0*(1.0-2.0*progress)*arc,maxf(Vector2(direction.x,direction.z).length(),.1))
		_batch(shell_mesh,graphic.global_transform,energy_projectile_material if _energy_weapon(str(projectile.get("spec", ""))) else projectile_material)


func _sync_data_projectiles() -> void:
	for projectile in sim.projectiles:
		if not _projectile_visible(projectile): continue
		if str(projectile.get("trajectory","")) == "gravity_bomb":
			var bombs = load("res://scripts/zeppelin_weapons.gd")
			var bomb_transform: Transform3D = bombs.bomb_transform(projectile)
			if _point_in_view(bomb_transform.origin,2.0): _batch(bombs.bomb_mesh(),bomb_transform)
			continue
		var start:Vector2=projectile.start
		var landing:Vector2=projectile.landing
		var source:Vector3=Vector3(start.x,MAP.height_at(sim.map,start)+float(projectile.get("source_height",0.0))+.9,start.y)
		source.y+=_projectile_source_air_offset(projectile)
		var destination:=Vector3(landing.x,MAP.height_at(sim.map,landing)+float(projectile.get("target_height",.15))+_visual_air_offset(int(projectile.get("target",-1))),landing.y)
		var progress:float=clampf(float(projectile.elapsed)/maxf(float(projectile.duration),.001),0.0,1.0)
		var arc:float=clampf(start.distance_to(landing)*.045,.08,.6)
		var position:Vector3=source.lerp(destination,progress)+Vector3.UP*4.0*progress*(1.0-progress)*arc
		if not _point_in_view(position,2.0):continue
		var direction:Vector3=destination-source
		var yaw:float=-atan2(direction.z,direction.x)
		var pitch:float=atan2(direction.y+4.0*(1.0-2.0*progress)*arc,maxf(Vector2(direction.x,direction.z).length(),.1))
		_append_batch(_performance_shell_batch,Transform3D(Basis(Vector3.UP,yaw)*Basis(Vector3.BACK,pitch),position))



func _projectile_visible(projectile: Dictionary) -> bool:
	var point: Vector2 = projectile.get("pos", projectile.start)
	var domain: String = "air" if maxf(float(projectile.get("source_height",0.0)),float(projectile.get("target_height",0.0))) > 2.0 else "naval" if MAP.terrain_at(sim.map,point) == MAP.WATER else "ground"
	return int(projectile.get("team", 0)) == 0 or sim.position_visible_to(0, point, domain)

func _event_visible(event: Dictionary) -> bool:
	var point: Vector2 = event.get("pos",Vector2.ZERO)
	var domain: String = "air" if float(event.get("height",0.0)) > 2.0 else "naval" if MAP.terrain_at(sim.map,point) == MAP.WATER else "ground"
	return int(event.get("team", 0)) == 0 or sim.position_visible_to(0, point, domain)

func _cursor_surface_y(pos: Vector2) -> float:
	return MAP.water_surface_y(sim.map,pos) if MAP.terrain_at(sim.map,pos) == MAP.WATER else MAP.height_at(sim.map,pos)

func _read_events() -> void:
	# main owns event lifetime and clears the buffer after both visual and audio readers.
	for event in sim.events:
		if not _event_visible(event): continue
		if event.kind == "impact":
			var impact_weapon: Dictionary = sim.rules.weapons.get(str(event.get("weapon","")),{})
			if float(impact_weapon.get("emp_vehicle_duration",0))>0 or float(impact_weapon.get("emp_building_duration",0))>0: continue
			var radius: float = float(event.get("blast",event.get("radius",1.0)))
			var impact_height: float=float(event.get("height",event.get("target_height",.18)))+_visual_air_offset(int(event.get("target",-1)))
			_spawn_effect(event.pos, "impact", radius,impact_height)
			if bool(event.get("projectile",radius > 0.0)): _spawn_smoke(event.pos,radius,impact_height)
			if bool(event.get("projectile",radius > 0.0)):
				_spawn_crater(event.pos,clampf(maxf(radius,.45)*.58,.25,1.25),impact_height)
				_spawn_debris(event.pos,clampf(radius,.4,1.4),impact_height,false)
		elif event.kind == "death" and bool(event.get("destroyed",true)):
			if _destroyed_this_frame.has(int(event.get("id",-1))): continue
			var spec: Dictionary = sim.data_for(event.spec)
			var kind: String = "building" if sim.rules.buildings.has(event.spec) else "unit"
			if kind=="unit" and (str(spec.get("art","")) in VOLUME.INFANTRY_ART or str(spec.get("armor_class",""))=="infantry"): continue
			if kind=="unit" and spec.get("domain","ground")=="air":continue
			var dimensions: Vector3 = VOLUME._recipe(spec,kind,int(event.team)).dimensions if VOLUME.supports(spec,kind) else Vector3(1.0,1.7,.5)
			var radius: float = maxf(dimensions.x,dimensions.z) * .52
			var altitude: float = float(event.get("height",0.0))
			var burst_height: float = altitude + dimensions.y * .5
			_spawn_effect(event.pos,"death",radius,burst_height,dimensions)
			_spawn_smoke(event.pos,radius,burst_height,true)
			_spawn_debris(event.pos,radius,burst_height)
			if kind == "building": _spawn_crater(event.pos,radius * .85,altitude)
		elif event.kind == "ruin_destroy":
			_spawn_smoke(event.pos,float(event.radius),.5,true)
			_spawn_debris(event.pos,float(event.radius),1.0)
		elif event.kind == "fire":
			if str(event.get("weapon_slot","")) == "bomb": continue
			var source: Vector2 = event.pos
			var landing: Vector2 = event.get("landing",source+Vector2.RIGHT)
			var direction: Vector2 = (landing-source).normalized()
			var muzzle_height: float = float(event.get("height",0.0))+(0.0 if bool(event.get("garrison_fire",false)) else .9)
			if models.has(event.get("id",-1)) and not bool(event.get("garrison_fire",false)):
				var model: Dictionary = models[event.id]
				if str(event.get("weapon_slot","")) == "secondary" and model.volumetric:
					for part: Dictionary in model.volume.parts:
						if str(part.role) != "zeppelin_mg": continue
						var muzzle: Vector3 = part.node.global_transform*(Vector3(.295,.025,0)*float(model.volume.model_scale))
						source = Vector2(muzzle.x,muzzle.z)
						muzzle_height = muzzle.y-MAP.height_at(sim.map,source)
				elif model.volumetric and model.volume.muzzle != null:
					var muzzle: Vector3 = model.volume.muzzle.global_position
					source = Vector2(muzzle.x,muzzle.z)
					muzzle_height = muzzle.y-MAP.height_at(sim.map,source)
				else:
					var size: Vector2 = model.dimensions
					source += direction*size.x*.35
					muzzle_height = size.y*.5
			var emp_fire: bool = float(sim.rules.weapons.get(event.get("weapon",""),{}).get("emp_vehicle_duration",0))>0 or float(sim.rules.weapons.get(event.get("weapon",""),{}).get("emp_building_duration",0))>0
			if not emp_fire: _spawn_effect(source,"fire",0.5,muzzle_height)
			if not emp_fire and _energy_weapon(str(event.get("spec", ""))) and sim.rules.weapons.get(event.get("weapon",""),{}).get("kind","") not in ["laser","beam"]:
				_spawn_tracer(source-direction*.65, source+direction*.18, muzzle_height, muzzle_height, Color("c6b8ef"))
			var weapon: Dictionary = sim.rules.weapons.get(event.get("weapon",""),{})
			if emp_fire:
				_spawn_emp_pulse(landing,float(event.get("target_height",.18)))
			elif str(weapon.get("kind","")) in ["laser","beam"]:
				_spawn_weapon_beam(source,landing,muzzle_height,float(event.get("target_height",.8))+_visual_air_offset(int(event.get("target",-1))),event,str(weapon.kind))
			elif str(weapon.get("kind","")) == "emp":
				_spawn_emp_pulse(landing,float(event.get("target_height",.18)))
			elif weapon.get("kind","") == "instant":
				_spawn_tracer(source,landing,muzzle_height,float(event.get("target_height",.8))+_visual_air_offset(int(event.get("target",-1))))
		elif event.kind == "build" or event.kind == "produce":
			_spawn_effect(event.pos,"build",0.75)
		elif event.kind == "overcharge":
			_spawn_effect(event.pos,"build",1.0,1.2)

	# A continuous beam is a live simulation channel, not a delayed fire flash.
	# Rebuild after quality switches and follow movers even without another event.
	for source: Dictionary in sim.entities.values():
		if not source.has("beam") or not sim.entity_visible_to(0,int(source.id)): continue
		var channel: Dictionary = source.beam
		var target: Dictionary = sim.entities.get(int(channel.get("target",-1)),{})
		if target.is_empty(): continue
		_spawn_weapon_beam(source.pos,target.pos,float(source.get("flight_height",0.0))+.4,float(target.get("flight_height",0.0))+.35,{"id":source.id,"target":target.id,"beam_duration":channel.remaining},"beam")

func _energy_weapon(spec_id: String) -> bool:
	return spec_id in ["iron_advanced", "sky_tank", "sky_artillery", "sky_disruptor", "sky_pulse", "sky_anti_tower"]


func _add_effect(effect:Dictionary) -> void:
	# Shape, material family, cull extent and source tint are fixed at birth.
	# Alpha/pose still evolve continuously with the same original formulas.
	var graphic=effect.graphic
	graphic.visible=false
	effect.base_color=graphic.material_override.albedo_color if graphic.material_override is StandardMaterial3D else Color.WHITE
	var travel_time: float = minf(float(effect.life),float(effect.get("settle_age",1.0)))
	effect.cull_radius=(graphic.mesh.get_aabb().size*(effect.base as Vector3)).length()+(effect.get("velocity",Vector3.ZERO) as Vector3).length()*travel_time+2.5
	effect.colored=effect.kind in ["blast","death_blast","smoke","scorch","shock"]
	effect.batch=_batch_descriptor(_particle_mesh(graphic.mesh),_particle_material(graphic.material_override,str(effect.kind)),false,true) if effect.colored else _batch_descriptor(graphic.mesh,graphic.material_override)
	effect.lod_tier=0
	if effect.kind in ["blast","death_blast","smoke","debris","creator_rubble"]:
		var meshes: Array = effect.get("lod_meshes",[])
		if effect.kind not in ["debris","creator_rubble"]: meshes=effect_spheres
		elif meshes.is_empty():
			var key: int = graphic.mesh.get_instance_id()
			if not _chip_lods.has(key): _chip_lods[key]=EFFECT_LOD.fragment_tiers(graphic.mesh)
			meshes=_chip_lods[key]
		effect.lod_batches=[]
		for mesh: Mesh in meshes:
			effect.lod_batches.append(_batch_descriptor(_particle_mesh(mesh),_particle_material(graphic.material_override,str(effect.kind)),false,true) if effect.colored else _batch_descriptor(mesh,graphic.material_override))
		effect.lod_bounds=meshes[0].get_aabb()
	effects.append(effect)


func _spawn_tracer(start: Vector2, end: Vector2, height: float, target_height: float = .8, color: Color = Color("ecd298")) -> void:
	if quality_policy=="performance":return
	var a := Vector3(start.x,MAP.height_at(sim.map,start)+height,start.y)
	var b := Vector3(end.x,MAP.height_at(sim.map,end)+target_height,end.y)
	var root := Node3D.new()
	add_child(root)
	root.position = a
	var strip := BoxMesh.new()
	strip.size = Vector3(.035,.035,a.distance_to(b))
	var graphic = _pose_mesh(strip,_material(color))
	root.add_child(graphic)
	graphic.position.z = -a.distance_to(b)*.5
	root.look_at(b,Vector3.UP)
	_add_effect({"root":root,"graphic":graphic,"kind":"tracer","age":0.0,"base":Vector3.ONE,"life":.09})


func _spawn_weapon_beam(start: Vector2, end: Vector2, height: float, target_height: float, event: Dictionary, kind: String) -> void:
	var source_id: int = int(event.get("id",-1))
	if kind == "beam" and _beam_channels.has(source_id) and is_instance_valid(_beam_channels[source_id].root): return
	var a := Vector3(start.x,MAP.height_at(sim.map,start)+height,start.y)
	var b := Vector3(end.x,MAP.height_at(sim.map,end)+target_height,end.y)
	if a.distance_squared_to(b) < .0001: return
	var beam_root := Node3D.new()
	add_child(beam_root)
	beam_root.position = a
	beam_root.look_at(b,Vector3.UP)
	var strip := BoxMesh.new()
	strip.size = Vector3(.035 if kind == "laser" else .075,.035 if kind == "laser" else .075,a.distance_to(b))
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("f7fff1") if kind == "laser" else Color("84ecdd")
	material.emission_enabled = true
	material.emission = Color("bfe9d9") if kind == "laser" else Color("48afae")
	material.emission_energy_multiplier = 1.1
	var graphic = _pose_mesh(strip,material)
	beam_root.add_child(graphic)
	graphic.position.z = -a.distance_to(b)*.5
	var effect: Dictionary = {"root":beam_root,"graphic":graphic,"kind":"tracer","age":0.0,"base":Vector3.ONE,"life":3600.0 if kind == "beam" else maxf(.10,float(event.get("beam_duration",event.get("duration",.12)))),"beam_kind":kind,"source_id":source_id,"target_id":int(event.get("target",-1)),"beam_end":b,"initial_length":a.distance_to(b)}
	_add_effect(effect)
	if kind == "beam": _beam_channels[source_id] = effect

func _update_weapon_channel(effect: Dictionary) -> bool:
	var source: Dictionary = sim.entities.get(int(effect.source_id),{})
	if source.is_empty() or not source.has("beam") or float(source.get("emp_until",0)) > sim.time: return false
	var channel: Dictionary = source.beam
	if float(channel.get("remaining",0)) <= 0: return false
	var target: Dictionary = sim.entities.get(int(channel.get("target",-1)),{})
	if target.is_empty() or float(target.hp) <= 0: return false
	effect.target_id = int(target.id)
	var source_spec: Dictionary = sim.data_for(source.spec)
	var a: Vector3 = Vector3(source.pos.x,MAP.height_at(sim.map,source.pos)+float(source.get("flight_height",0)),source.pos.y)+VOLUME.muzzle_offset(source_spec,source.kind,int(source.team),float(source.alpha),float(source.get("turret_alpha",source.alpha)))
	if models.has(int(source.id)) and models[source.id].volume.get("muzzle") != null: a = models[source.id].volume.muzzle.global_position
	var b := Vector3(target.pos.x,MAP.height_at(sim.map,target.pos)+float(target.get("flight_height",0))+.35,target.pos.y)
	if models.has(int(target.id)): b.y = MAP.height_at(sim.map,target.pos)+float(models[target.id].volume.get("height",.7))*.5+float(models[target.id].flight_height)
	var distance: float = a.distance_to(b)
	if distance < .001: return false
	effect.root.position = a
	effect.root.look_at(b,Vector3.UP)
	effect.graphic.position.z = -distance*.5
	effect.graphic.scale = Vector3(1,1,distance/maxf(.001,float(effect.initial_length)))
	effect.beam_end = b
	return true

func _draw_emp_status(model: Dictionary, entity: Dictionary) -> void:
	if _emp_status_batch.is_empty():
		var craft := VOLUME.CraftMesh.new()
		craft.face([Vector3(-.025,.17,0),Vector3(.08,.17,0),Vector3(.005,.045,0),Vector3(.07,.045,0),Vector3(-.085,-.15,0),Vector3(-.025,-.015,0),Vector3(-.08,-.015,0)],Color("65ddea"),Vector3.BACK)
		var material := _material(Color("65ddea"))
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_emp_status_batch = _batch_descriptor(craft.mesh(),material,false)
	var pos: Vector3 = model.root.global_position+Vector3(0,float(model.volume.get("height",model.dimensions.y))+float(model.get("flight_height",0))+.26,0)
	var basis := Basis(Vector3.UP,camera_yaw)
	_append_batch(_emp_status_batch,Transform3D(basis,pos))


func _spawn_emp_pulse(pos: Vector2, height: float) -> void:
	var pulse_root := Node3D.new()
	add_child(pulse_root)
	pulse_root.position = Vector3(pos.x,MAP.height_at(sim.map,pos)+maxf(.12,height),pos.y)
	var ring := TorusMesh.new()
	ring.inner_radius = .38
	ring.outer_radius = .44
	ring.rings = 12
	ring.ring_segments = 4
	var material := _material(Color("78dfea"))
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var graphic = _pose_mesh(ring,material)
	pulse_root.add_child(graphic)
	_add_effect({"root":pulse_root,"graphic":graphic,"kind":"shock","age":0.0,"base":Vector3.ONE*1.8,"life":.6})


func _spawn_destruction_bursts(pos: Vector2, radius: float, height: float, dimensions: Vector3) -> void:
	var volume: Vector3=dimensions if dimensions!=Vector3.ZERO else Vector3(radius*1.8,maxf(radius*1.2,.8),radius*1.6)
	volume=volume.max(Vector3(.55,.7,.55))
	var center:=Vector3(pos.x,MAP.height_at(sim.map,pos)+(volume.y*.5 if height==-1.0 else height),pos.y)
	var grid:=Vector3i(3,2,2) if quality_policy=="performance" else (Vector3i(4,3,3) if volume.y>2.7 else Vector3i(4,2,3))
	var points: Array[Vector3]=[]
	for y: int in grid.y:
		for z: int in grid.z:
			for x: int in grid.x:
				points.append((Vector3((float(x)+.5)/grid.x,(float(y)+.5)/grid.y,(float(z)+.5)/grid.z)-Vector3.ONE*.5)*volume)
	# Permuted grid order keeps distant subsets spread across the footprint.
	var step: int=5 if points.size()%5!=0 else 7
	var cell: Vector3=volume/Vector3(grid)
	var diameter: float=clampf(maxf(cell.x,maxf(cell.y,cell.z))*.95,.36,1.25)
	var bounds:=AABB(-volume*.5,volume)
	for index: int in points.size():
		var offset: Vector3=points[(index*step)%points.size()]
		offset+=Vector3(destruction_rng.randf_range(-.07,.07),destruction_rng.randf_range(-.05,.05),destruction_rng.randf_range(-.07,.07))
		var base:=Vector3.ONE*diameter*destruction_rng.randf_range(.88,1.10)
		var velocity: Vector3=Vector3(offset.x*.16,destruction_rng.randf_range(.16,.38),offset.z*.16)
		if quality_policy=="performance":
			var before: int=data_effects.size()
			_spawn_data_effect(Vector2(center.x+offset.x,center.z+offset.z),diameter,(center+offset).y-MAP.height_at(sim.map,pos),"death")
			if data_effects.size()>before: data_effects.back().merge({"small_burst":true,"base":base,"velocity":velocity,"detail_index":index,"cluster_primary":index==0,"cluster_origin":center,"cluster_bounds":bounds})
		else:
			if effects.size()>=_effect_limit(): break
			var root:=Node3D.new();add_child(root);root.position=center+offset
			var graphic=_pose_mesh(smoke_mesh,_blast_source_material());root.add_child(graphic)
			_add_effect({"root":root,"graphic":graphic,"kind":"death_blast","age":0.0,"delay":0.0,"base":base,"small_burst":true,"detail_index":index,"cluster_primary":index==0,"cluster_origin":center,"cluster_bounds":bounds,"velocity":velocity,"life":destruction_rng.randf_range(.55,.78)})


func _spawn_effect(pos: Vector2, kind: String, radius: float, height: float = -1.0, dimensions: Vector3 = Vector3.ZERO) -> void:
	if kind=="death":
		_spawn_destruction_bursts(pos,radius,height,dimensions)
		return
	if quality_policy=="performance":
		if kind in ["impact","death","fire"]:_spawn_data_effect(pos,radius,.2 if height == -1.0 else height,kind,dimensions)
		return
	if kind in ["impact","death"]:
		var destroyed: bool=kind=="death"
		# Anchored fireballs and a low shock ring; no billboard, outline or card.
		var spread: float = clampf(radius,.45,6.0)*(1.1 if destroyed else 1.0)
		for i in range(6):
			var root := Node3D.new()
			add_child(root)
			var angle: float = i * 2.39996
			root.position = Vector3(pos.x+cos(angle)*spread*.26,MAP.height_at(sim.map,pos)+(.18 if height == -1.0 else height),pos.y+sin(angle)*spread*.26)
			if destroyed and i == 0: root.position.x=pos.x; root.position.z=pos.y
			var mat:StandardMaterial3D=_blast_source_material()
			var graphic = _pose_mesh(smoke_mesh,mat)
			root.add_child(graphic)
			graphic.scale = Vector3.ONE * .01
			var burst_scale: Vector3 = Vector3(spread*1.0,spread*.9,spread*1.0)*(1.0-float(i%3)*.16)
			if destroyed and i == 0 and dimensions != Vector3.ZERO: burst_scale = dimensions.max(Vector3(.7,.7,.7))*1.16
			_add_effect({"root":root,"graphic":graphic,"kind":"death_blast" if destroyed else "blast","delay":float(i%3)*.06 if destroyed else 0.0,"age":0.0,"silhouette":destroyed and i==0 and dimensions!=Vector3.ZERO,"detail_index":i,"base":burst_scale,"velocity":Vector3(cos(angle)*spread*.35,.15+float(i%3)*.4,sin(angle)*spread*.35),"life":.85+float(i%3)*.1 if destroyed else .38+float(i%3)*.07})
		# Airbursts illuminate the target altitude without a ground shock ring.
		if height>2.0:return
		var ring := Node3D.new()
		add_child(ring)
		ring.position = Vector3(pos.x,_cursor_surface_y(pos)+.05,pos.y)
		var mat:StandardMaterial3D=_material(Color("b89b70"),true)
		var graphic = _pose_mesh(ring_mesh,mat)
		ring.add_child(graphic)
		_add_effect({"root":ring,"graphic":graphic,"kind":"shock","age":0.0,"base":Vector3(spread*1.5,1,spread*1.5),"life":1.0 if destroyed else .5})
		return
	var root := Node3D.new()
	add_child(root)
	root.position = Vector3(pos.x,MAP.height_at(sim.map,pos)+(.9 if height == -1.0 else height),pos.y)
	var graphic = _pose_mesh(smoke_mesh,_material(Color("ffe1a0")))
	root.add_child(graphic)
	graphic.scale = Vector3(.3,.2,.3) if kind == "fire" else Vector3(.5,.1,.5)
	_add_effect({"root":root,"graphic":graphic,"kind":kind,"age":0.0,"base":graphic.scale,"life":.12 if kind == "fire" else .5})


func _spawn_debris(pos: Vector2, radius: float, height: float, destruction: bool = true) -> void:
	for i in range((6 if destruction else 2) if quality_policy=="performance" else (8 if destruction else 4)):
		if effects.size() >= _effect_limit(): break
		var root:=Node3D.new()
		add_child(root)
		root.position=Vector3(pos.x,MAP.height_at(sim.map,pos)+height,pos.y)
		var chip:BoxMesh=debris_meshes[i%3]
		var graphic=_pose_mesh(chip,_material(Color("5d4b37") if i%3 else Color("cdb991")))
		root.add_child(graphic)
		var angle: float=i*2.39996
		var velocity := Vector3(cos(angle),1.1+float(i%3)*.4,sin(angle))*clampf(radius*1.4,1.2,3.5)
		var settle_age: float = (velocity.y+sqrt(velocity.y*velocity.y+19.6*maxf(height-.05,0.0)))/9.8
		_add_effect({"root":root,"graphic":graphic,"kind":"debris","age":0.0,"base":Vector3.ONE,"velocity":velocity,"floor":-height+.05,"settle_age":settle_age,"spin":Vector3(5,3,4),"life":8.0 if destruction else 2.4})

func _spawn_smoke(pos: Vector2, radius: float, height: float = .5, destruction: bool = false) -> void:
	if quality_policy=="performance":
		_spawn_data_effect(pos,clampf(radius*(.7 if destruction else .45),.4,1.8),height,"smoke")
		return
	# Small faceted paint clouds reinforce volume without hiding a whole fight.
	for i in range(3):
		var root := Node3D.new()
		add_child(root)
		root.position = Vector3(pos.x+float(i-1)*.25,MAP.height_at(sim.map,pos)+height+float(i)*.2,pos.y)
		var material:StandardMaterial3D=_smoke_source_material(destruction)
		var graphic = _pose_mesh(smoke_mesh,material)
		root.add_child(graphic)
		var base := Vector3.ONE*clampf(radius*(.8 if destruction else .55),.55,1.8 if destruction else 1.1)
		graphic.scale = base*.4
		_add_effect({"root":root,"graphic":graphic,"kind":"smoke","detail_index":i,"age":0.0,"base":base,"life":5.8+float(i)*.45 if destruction else 3.4+float(i)*.3})


func _spawn_data_effect(pos:Vector2,radius:float,height:float,kind:String,dimensions:Vector3=Vector3.ZERO) -> void:
	if data_effects.size()>=128 or _fx_spawned>=24:return
	var origin:=Vector3(pos.x,MAP.height_at(sim.map,pos)+height,pos.y)
	if not _point_in_view(origin,maxf(radius,2.0)):return
	_fx_spawned+=1
	data_effects.append({"pos":origin,"radius":clampf(radius,.25,6.0),"kind":kind,"dimensions":dimensions,"lod_tier":0,"age":0.0,"life":3.8 if kind=="smoke" else .55 if kind=="death" else .3 if kind=="impact" else .09})


func _update_data_effects(delta:float) -> void:
	for index in range(data_effects.size()-1,-1,-1):
		var effect:Dictionary=data_effects[index]
		effect.age+=delta
		var progress:float=float(effect.age)/float(effect.life)
		if progress>=1.0:data_effects.remove_at(index);continue
		var position:Vector3=effect.pos
		var size:float=float(effect.radius)*(.25+progress*.85)
		var color:Color
		var batch:Dictionary
		if effect.kind=="smoke":
			position+=Vector3(progress*.15,progress*.8,0)
			color=Color(.28,.27,.25,(1.0-progress)*.6)
			batch=_performance_smoke_batch
		else:
			color=Color("ff9d28").lerp(Color("8b3521"),progress)
			color.a=1.0-progress
			batch=_performance_blast_batch
		var burst_scale: Vector3 = Vector3.ONE*size
		if bool(effect.get("small_burst",false)):
			burst_scale=effect.base*(.80+sin(progress*PI)*.26)
			position+=effect.velocity*progress
		var transform := Transform3D(Basis.IDENTITY.scaled(burst_scale),position)
		var tier: int = _choose_effect_lod(effect,transform,effect_spheres[0].get_aabb())
		batch = _performance_smoke_lods[tier] if effect.kind=="smoke" else _performance_blast_lods[tier]
		if bool(effect.get("small_burst",false)) and not _burst_lobe_visible(effect,tier): continue
		_append_batch(batch,transform,color)


func _update_effects(delta: float) -> void:
	_update_air_crash_smoke(delta)
	_update_cloud_shadows()
	_update_air_trail_effects(delta)
	if quality_policy=="performance":
		_update_data_effects(delta)
	for i in range(craters.size()-1,-1,-1):
		var crater: Dictionary = craters[i]
		crater.age += delta
		if crater.age >= CRATER_LIFETIME:
			craters.remove_at(i)
			continue
		if _point_in_view(crater.transform.origin,crater.radius):
			var alpha: float=float(crater.get("opacity",.65))*(1.0-smoothstep(CRATER_LIFETIME*.8,CRATER_LIFETIME,float(crater.age)))
			_append_batch(crater_batch,crater.transform,Color(float(crater.get("seed",.5)),1,1,alpha))
	for i in range(tracks.size()-1,-1,-1):
		var track: Dictionary = tracks[i]
		track.age += delta
		if track.age >= TRACK_LIFETIME:
			tracks.remove_at(i)
			continue
		if not _point_in_view(track.pos,1.0):continue
		var basis:Basis=track.basis
		# Quantized alpha shares materials and draw batches across all vehicles.
		var bucket:int=clampi(roundi((1.0-smoothstep(TRACK_LIFETIME*.55,TRACK_LIFETIME,float(track.age)))*7.0),0,7)
		_batch(square_mesh,Transform3D(basis,track.pos),track_materials[bucket])
	for i in range(effects.size()-1,-1,-1):
		var effect: Dictionary = effects[i]
		if str(effect.get("beam_kind","")) == "beam" and not _update_weapon_channel(effect):
			_beam_channels.erase(int(effect.source_id))
			effect.root.queue_free()
			effects.remove_at(i)
			continue
		effect.age += delta
		var delay: float=float(effect.get("delay",0))
		var show:bool=float(effect.age)>=delay
		if effect.graphic.visible:effect.graphic.visible=false
		var progress: float = clampf((float(effect.age)-delay)/float(effect.life),0,1)
		if progress>=1.0:
			effect.root.queue_free()
			effects.remove_at(i)
			continue
		if not _point_in_view(effect.root.global_position,float(effect.cull_radius)):continue
		var color:Color=effect.base_color
		if effect.kind in ["blast","death_blast"]:
			effect.graphic.scale = effect.base * ((.80+sin(progress*PI)*.26) if bool(effect.get("small_burst",false)) else (.15+sin(progress*PI)*.9))
			effect.graphic.position = effect.velocity * progress
			color=Color("ff9d28").lerp(Color("8b3521"),progress)
			color.a=1.0-progress
		elif effect.kind == "debris":
			var age: float = minf(maxf(float(effect.age)-delay,0.0),float(effect.get("settle_age",.85)))
			var offset: Vector3 = effect.velocity*age+Vector3.DOWN*4.9*age*age
			if effect.has("world_velocity"):
				offset = effect.world_velocity*age+Vector3.DOWN*4.9*age*age
				offset.y = maxf(offset.y,float(effect.world_floor)-effect.root.global_position.y)
				effect.graphic.position = effect.root.global_basis.inverse()*offset
			else:
				offset.y = maxf(offset.y,float(effect.floor))
				effect.graphic.position = offset
			effect.graphic.rotation = effect.get("spin",Vector3(6,4,3))*age
			effect.graphic.scale = effect.base*(1.0-smoothstep(.9,1.0,progress))
		elif effect.kind == "creator_rubble":
			effect.graphic.scale = effect.base * (1.0 - smoothstep(.82, 1.0, progress))
		elif effect.kind == "scorch":
			effect.graphic.scale=effect.base
			color.a=(1-progress)*.5
		elif effect.kind == "shock":
			effect.graphic.scale = effect.base * (.3+progress)
			color.a=(1-progress)*.45
		elif effect.kind == "smoke":
			effect.graphic.scale = effect.base*(0.4+progress*1.3)
			effect.graphic.position.y = progress*1.9
			effect.graphic.position.x = progress*.35
			color.a=(1.0-smoothstep(.3,1.0,progress))*.7
		elif effect.kind != "tracer":
			effect.root.rotation.y = camera_yaw
			effect.graphic.scale = effect.base * (0.35 + sin(progress*PI)*0.9)
			effect.graphic.position.y = progress * 0.7
			effect.graphic.rotation.z = progress*.22
		if show:
			if effect.has("lod_batches"):
				var tier: int = _choose_effect_lod(effect,effect.graphic.global_transform,effect.lod_bounds)
				effect.batch=effect.lod_batches[tier]
				# The central occupied volume remains at every range. Distant
				# secondary lobes merge into it, reducing overdraw and submissions.
				var detail: int = int(effect.get("detail_index",0))
				if bool(effect.get("small_burst",false)):
					if not _burst_lobe_visible(effect,tier): continue
				elif effect.kind in ["blast","smoke"] and ((tier==1 and detail>2) or (tier==2 and detail>0)): continue
			_append_batch(effect.batch,effect.graphic.global_transform,color if effect.colored else null)


func _burst_lobe_visible(effect: Dictionary, tier: int) -> bool:
	return int(effect.get("detail_index",0))<(8 if tier==1 else 4 if tier==2 else 36)


func _choose_effect_lod(effect: Dictionary, transform: Transform3D, bounds: AABB) -> int:
	if effect.has("cluster_bounds"):
		transform=Transform3D(Basis.IDENTITY,effect.cluster_origin)
		bounds=effect.cluster_bounds
	if _lod_view.is_empty(): _lod_view=MODEL_LOD.view(camera)
	var diameter: float = (bounds.size*transform.basis.get_scale().abs()).length()
	var pixels: float = MODEL_LOD.pixels_from_view(_lod_view,transform*bounds.get_center(),diameter)
	var tier: int = MODEL_LOD.choose(pixels,int(effect.get("lod_tier",0))) if lod_enabled else 0
	if lod_override>=0: tier=clampi(lod_override,0,2)
	effect.lod_tier=tier
	return tier


func _guide_segment(a: Vector2, b: Vector2, color: Color) -> void:
	if not sim._in_bounds(a) or not sim._in_bounds(b): return
	var ha: float = MAP.height_at(sim.map,a)
	var hb: float = MAP.height_at(sim.map,b)
	if absf(ha-hb) > .8: return
	var side: Vector2 = (b-a).normalized().orthogonal() * .028
	var p := Vector3(a.x-side.x,ha+.07,a.y-side.y)
	var q := Vector3(b.x-side.x,hb+.07,b.y-side.y)
	var r := Vector3(b.x+side.x,hb+.07,b.y+side.y)
	var t := Vector3(a.x+side.x,ha+.07,a.y+side.y)
	for point in [p,q,r,p,r,t]:
		guide_mesh.surface_set_color(color)
		guide_mesh.surface_add_vertex(point)

func _guide_circle(pos: Vector2, radius: float, color: Color) -> void:
	for i in range(96):
		var a: float = i * TAU / 96.0
		var b: float = (i+1) * TAU / 96.0
		_guide_segment(pos+Vector2(cos(a),sin(a))*radius,pos+Vector2(cos(b),sin(b))*radius,color)

func _update_placement(placement: Dictionary) -> void:
	if placement.is_empty() and not is_instance_valid(guide_node):return
	if not is_instance_valid(guide_node):
		guide_mesh = ImmediateMesh.new()
		guide_node = _mesh_instance(guide_mesh)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		guide_node.material_override = mat
		add_child(guide_node)
	if placement.is_empty():
		if not _guide_signature.is_empty():
			guide_mesh.clear_surfaces()
			_guide_signature.clear()
		if is_instance_valid(placement_node):
			placement_node.visible = false
		return
	var zones: Array[Dictionary] = sim.construction_zones(0)
	var signature:Array=[placement.spec,placement.pos,placement.valid,str(placement.get("channel","normal")),int(placement.get("builder",sim.building_orders[0].get("builder",-1))),int(placement.get("rotation_quarters",0))]
	for zone: Dictionary in zones: signature.append_array([zone.id, zone.pos, zone.radius, zone.role])
	for building in sim._building_entities:
		signature.append_array([building.id,building.team,building.pos,float(building.construct_remaining)<=0.0,float(building.hp)>0.0])
	if signature==_guide_signature:
		if is_instance_valid(placement_node):
			placement_node.visible=true
			_update_placement_lod()
		return
	_guide_signature=signature
	guide_mesh.clear_surfaces()
	var spec: Dictionary = sim.rules.buildings[placement.spec]
	if str(spec.get("art","")) in ["rail","rail_junction"]:
		spec = spec.duplicate()
		spec.rail_ports = [7,14,13,11][posmod(int(placement.get("rotation_quarters",placement.get("rail_rotation",0))),4)]
		spec.rail_mask = spec.rail_ports if str(spec.art) == "rail_junction" else (5 if int(placement.get("rotation_quarters",0))%2 == 0 else 10)
	guide_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	if int(placement.get("builder", sim.building_orders[0].get("builder", -1))) <= 0:
		for zone: Dictionary in zones:
			_guide_circle(zone.pos, float(zone.radius), Color("159a38"))
		if spec.role in ["wall","barricade"]:
			for e in sim._building_entities:
				if int(e.team) != 0 or float(e.hp) <= 0 or float(e.construct_remaining) > 0 or sim.data_for(e.spec).get("role", "") not in ["wall", "barricade"]: continue
				# Four straight construction directions, each capped at six cells.
				for direction in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
					for i in range(24):
						_guide_segment(e.pos+direction*i*.25,e.pos+direction*(i+1)*.25,Color("159a38"))
	if not str(spec.weapon).is_empty():
		_guide_circle(placement.pos,float(sim.rules.weapons[spec.weapon].range),Color("df9c16"))
	for point in sim.defense_extension(0,placement.pos,str(placement.get("channel","normal"))):
		_guide_circle(point,.48,Color("159a38") if placement.valid else Color("d97355"))
	var arrow_direction: Vector2 = sim.BuildingOrientation.offset(Vector2.RIGHT if str(spec.get("role","")) in ["rail","rail_junction","shipyard"] else Vector2.DOWN,int(placement.get("rotation_quarters",0)))
	var arrow_start: Vector2 = placement.pos
	var arrow_end: Vector2 = arrow_start+arrow_direction*(float(spec.size)*.5+.7)
	_guide_segment(arrow_start,arrow_end,Color("f5bb28"))
	_guide_segment(arrow_end,arrow_end-arrow_direction*.45+arrow_direction.orthogonal()*.3,Color("f5bb28"))
	_guide_segment(arrow_end,arrow_end-arrow_direction*.45-arrow_direction.orthogonal()*.3,Color("f5bb28"))
	guide_mesh.surface_end()
	var key: String = spec.faction + "_" + spec.art + "_idle"
	if str(spec.art) in ["rail","rail_junction"]: key += ":" + str(spec.get("rail_ports",0))
	if not is_instance_valid(placement_node) or placement_key != key:
		if is_instance_valid(placement_node):
			placement_node.queue_free()
		placement_node = Node3D.new()
		add_child(placement_node)
		var preview: Dictionary = VOLUME.create_model(spec,"building",0)
		placement_node.add_child(preview.root)
		_placement_lod = {"parts":[],"diameter":(preview.dimensions as Vector3).length(),"height":float(preview.height),"tier":0}
		for node in preview.meshes:
			_placement_lod.parts.append({"node":node,"meshes":[node.mesh,VOLUME.quality_mesh(node.mesh,0,"far"),VOLUME.quality_mesh(node.mesh,0,"extreme")]})
		var border := _mesh_instance(ring_mesh)
		placement_node.add_child(border)
		border.scale = Vector3(float(spec.size)*.76,1,float(spec.size)*.76)
		border.position.y = .05
		placement_key = key
	var pos: Vector2 = placement.pos
	placement_node.visible = true
	placement_node.position = Vector3(pos.x,MAP.entity_surface_y(sim.map,pos,str(spec.get("domain","ground"))),pos.y)
	placement_node.rotation.y = -deg_to_rad(sim.BuildingOrientation.angle(placement,spec))
	placement_node.get_child(1).material_override = _material(Color("7b9764") if placement.valid else Color("c56c4d"))
	_update_placement_lod()

func _update_placement_lod() -> void:
	if _placement_lod.is_empty() or not is_instance_valid(placement_node): return
	var center: Vector3 = placement_node.global_position+Vector3.UP*float(_placement_lod.height)*.5
	var pixels: float = MODEL_LOD.projected_pixels(camera,center,float(_placement_lod.diameter))
	var tier: int = MODEL_LOD.choose(pixels,int(_placement_lod.tier)) if lod_enabled else 0
	if lod_override >= 0: tier = clampi(lod_override,0,2)
	for part in _placement_lod.parts:
		if part.node.mesh != part.meshes[tier]: part.node.mesh = part.meshes[tier]
	_placement_lod.tier = tier


func _flat_quad() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-.5,-.5,0),Vector3(.5,-.5,0),Vector3(.5,.5,0),Vector3(-.5,-.5,0),Vector3(.5,.5,0),Vector3(-.5,.5,0)])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh


func _disc(outer: float, inner: float, color: Color, count: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	for i in range(count):
		var a: float = float(i)*TAU/float(count)
		var b: float = float(i+1)*TAU/float(count)
		var po := Vector3(cos(a)*outer,0,sin(a)*outer)
		var qo := Vector3(cos(b)*outer,0,sin(b)*outer)
		var pi := Vector3(cos(a)*inner,0,sin(a)*inner)
		var qi := Vector3(cos(b)*inner,0,sin(b)*inner)
		vertices.append_array([po,qo,qi,po,qi,pi])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.surface_set_material(0,_material(color,color.a<1))
	return mesh


func _veteran_star_mesh() -> ArrayMesh:
	if material_cache.has("veteran_star_mesh"): return material_cache["veteran_star_mesh"]
	var polygon := PackedVector2Array()
	for i in range(10):
		var angle: float = -PI*.5+i*TAU/10.0
		var radius: float = .18 if i%2 == 0 else .078
		polygon.append(Vector2(cos(angle),sin(angle))*radius)
	var mesh := ArrayMesh.new()
	var vertices := PackedVector3Array()
	for index in Geometry2D.triangulate_polygon(polygon): vertices.append(Vector3(polygon[index].x,-polygon[index].y,0))
	var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX] = vertices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.surface_set_material(0,_material(Color("ffd447")))
	material_cache["veteran_star_mesh"] = mesh
	return mesh

func _star_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var polygon := PackedVector2Array()
	for i in range(18):
		var angle: float = float(i)*TAU/18.0
		var radius: float = 0.65 if i % 2 == 0 else .3
		polygon.append(Vector2(cos(angle)*radius,sin(angle)*radius))
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(polygon)
	for index in indices:
		vertices.append(Vector3(polygon[index].x,polygon[index].y+.55,0))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.surface_set_material(0,_material(Color("dfa850")))
	return mesh


func _dart_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-.32,-.04,0),Vector3(.18,0,0),Vector3(-.32,.05,0),Vector3(-.18,0,-.04),Vector3(.18,0,0),Vector3(-.18,0,.04)])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh
