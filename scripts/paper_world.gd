extends Node3D
class_name PaperWorld

## A visual reader of the simulation. Rendering never changes rules or commands.
## Faction vehicles and aircraft are solid models; infantry retains cut-paper art.
const MAP = preload("res://scripts/map_data.gd")
const VOLUME = preload("res://scripts/volume_models.gd")
const LANDSCAPE = preload("res://scripts/landscape.gd")
const SCAFFOLD = preload("res://scripts/construction_scaffold.gd")
const WALL_CONNECTIONS = preload("res://scripts/wall_connections.gd")
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
var card_cache: Dictionary = {}
var material_cache: Dictionary = {}
var infantry_border_shader: Shader
var vehicle_border_shader: Shader
var shells: Array[Node3D] = []
var effects: Array[Dictionary] = []
var ghosts: Array[Dictionary] = []
const CREATOR_CRUSH = preload("res://scripts/creator_crush_effects.gd")
var tracks: Array[Dictionary] = []
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
	model_pool.clear()
	data_effects.clear()
	data_corpses.clear()
	shells.clear()
	effects.clear()
	ghosts.clear()
	tracks.clear()
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
	track_materials.clear()
	for bucket in range(8):track_materials.append(_material(Color(.25,.20,.13,float(bucket)*.04),true))
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
		if not people.is_empty(): group.multi.mesh = PAPER_CIVILIANS.mesh(int(people[0].get("variant", 0)))
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
		for ghost in ghosts:_pool_model(ghost.model)
		ghosts.clear()
		tracks.clear()
	if landscape!=null and landscape.has_method("configure_quality"):
		landscape.configure_quality(quality_policy)
		_restore_scenery_detail()
	if quality_policy!="native":
		for model in models.values():_prepare_quality_batches(model)


func _prepare_quality_batches(model:Dictionary) -> void:
	if not model.volumetric or model.scaffold or bool(model.get("direct_skinned", false)):return
	for part in model.render_parts:
		# All presets now retain the authored mesh, pigment and shadow casting.
		# Keep descriptor aliases for corpse records and older diagnostic tools.
		part.quality_batch=part.batch
		part.performance_batch=part.batch
		if part.has("ink_batch"):part.quality_ink_batch=part.ink_batch


func _restore_scenery_detail() -> void:
	# Reuse the original instances and destruction bookkeeping, but never swap
	# their visible geometry for the optimization-only crown/trunk meshes.
	for lod in landscape._forest_lods:
		lod.near.visible=true
		lod.near.visibility_range_end=0.0
		lod.near.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		lod.mid.visible=false
		lod.far.visible=false
	for lod in landscape._trunk_lods:
		lod.near.visible=true
		lod.near.visibility_range_end=0.0
		lod.far.visible=false
		lod.distant.visible=false
	for child in landscape.get_children():
		if str(child.name).begins_with("TreeNearCaster_") or str(child.name).begins_with("TreeFarCaster_"):
			child.visible=false
	landscape.stats.full_model_detail=true
	landscape.stats.forest_visual_lod_distance=0.0
	landscape.stats.trunk_ink_lod_distance=0.0


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
	_cache_view_planes()
	_begin_batches()
	CREATOR_CRUSH.mark_deaths(self)
	camera_yaw = atan2(camera.global_basis.z.x, camera.global_basis.z.z)
	PAPER_CIVILIANS.face_camera(camera)
	landscape.sync_resources(sim)
	_sync_wall_connections()
	if profile_enabled:
		profile_last={"landscape_us":Time.get_ticks_usec()-stage_us}
		stage_us=Time.get_ticks_usec()
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
			_batch(_particle_mesh(ring_mesh) if family=="flat" else smoke_mesh,transform,material_cache["particle_instances_"+family],false,Color(0,0,0,0))
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


func _model_pool_key(e: Dictionary) -> String:
	var key: String = str(e.spec) + ":" + str(e.team)
	if _wall_masks.has(int(e.id)): key += ":wall:" + str(_wall_masks[int(e.id)])
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
		if int(e.get("transport_id",-1))<=0 and not _entity_in_view(model,e):
			if model.last_pos!=e.pos:
				model.root.position=Vector3(e.pos.x,float(model.terrain_height),e.pos.y)
				model.last_pos=e.pos
			model.embarked=false
			model.view_culled=true
			if bool(model.get("direct_skinned", false)): model.root.visible = false
			_culled_entities+=1
			continue
		model.view_culled=false
		if int(e.get("transport_id",-1))<=0:_visible_entities+=1
		_sync_entity(model, e, selected_ids.has(id))
	for id in models.keys():
		if not alive_ids.has(id):
			if bool(models[id].get("embarked", false)):
				models[id].root.queue_free()
			else:
				_start_death(models[id])
			models.erase(id)

func _cache_view_planes() -> void:
	var key:Array=[camera.global_transform,camera.fov,camera.near,camera.far,camera.h_offset,camera.v_offset,camera.get_viewport().get_visible_rect()]
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
	var flight:float=float(e.get("flight_height",model.spec.get("flight_height",0.0))) if model.is_air else 0.0
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
		multi.mesh = mesh
		var node := MultiMeshInstance3D.new()
		node.multimesh = multi
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if material != null:
			node.material_override = material
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


func _card(key: String, width: float, height: float, texture_path: String = "", team: int = -1) -> ArrayMesh:
	if texture_path.is_empty():
		texture_path = CARD_DIR + key + ".svg"
	# A configuration can swap both drawing and its matching registered contour.
	var mapped_key: String = texture_path.get_file().get_basename()
	if contours.has(mapped_key):
		key = mapped_key
	var cache_key: String = key + ":" + str(width) + ":" + str(height) + ":" + texture_path+":team"+str(team)
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
	var paper := _infantry_paper_material(texture_path,team)
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
	mesh.surface_set_material(1, _material(EDGE_COLOR))
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

func _infantry_paper_material(texture_path: String, team: int = -1) -> ShaderMaterial:
	var key := "infantry_border:" + texture_path+":team"+str(team)
	if material_cache.has(key): return material_cache[key]
	if infantry_border_shader == null:
		infantry_border_shader = Shader.new()
		infantry_border_shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
uniform sampler2D illustration : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D identity_mask : filter_linear_mipmap, repeat_disable;
uniform vec4 player_color : source_color = vec4(0.90588,0.67843,0.25882,1.0);
uniform float identity_enabled = 0.0;
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
    vec3 color = mix(original.rgb, player_color.rgb, owner_mask);
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
	material.set_shader_parameter("illustration", load(texture_path))
	var mask_path: String=texture_path.get_basename()+"_identity.svg"
	if team>=0 and ResourceLoader.exists(mask_path):
		material.set_shader_parameter("identity_mask",load(mask_path))
		material.set_shader_parameter("player_color",VOLUME.player_color(team))
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
    clip.z *= clip_depth_scale;
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
		spec.wall_mask = int(_wall_masks[int(e.id)])
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
		for mesh in volume.meshes:mesh.visible = direct_skinned
	else:
		graphic = _pose_mesh(_card(VOLUME.art_faction(spec)+"_"+spec.art+"_idle", dimensions.x, dimensions.y, _texture_path(spec,"idle"),int(e.team)))
		art_root.add_child(graphic)
		graphic.visible = false
	var shadow = _pose_mesh(shadow_mesh, _material(Color(0.19, 0.15, 0.1, 0.2), true))
	root.add_child(shadow)
	shadow.position.y = 0.025
	shadow.scale = Vector3(dimensions.x * 0.4, 1.0, dimensions.x * 0.19)
	shadow.visible = false
	var ring = _pose_mesh(ring_mesh, _material(TEAM_COLORS[int(e.team)]))
	root.add_child(ring)
	var radius: float = float(spec.radius) if e.kind == "unit" else float(spec.size) * 0.66
	ring.scale = Vector3(radius + 0.25, 1, radius + 0.25)
	ring.position.y = 0.045
	ring.visible = false
	var hp_root := Node3D.new()
	root.add_child(hp_root)
	hp_root.visible = false
	hp_root.position.y = (volume.height if volumetric else _visible_height(VOLUME.art_faction(spec)+"_"+spec.art+"_idle",dimensions.y)) + 0.2
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
	model.direct_skinned = direct_skinned
	if direct_skinned:
		# The natural skin stays untouched. A thin outer owner mark remains
		# distinct from the thicker, selection-only inner ring.
		var owner_mark = _pose_mesh(hand_owner_mesh, _material(TEAM_COLORS[int(e.team)]))
		root.add_child(owner_mark)
		owner_mark.scale = Vector3(radius + 0.60, 1, radius + 0.60)
		owner_mark.position.y = 0.065
		owner_mark.visible = false
		model.hand_owner_mark = owner_mark
		model.hand_owner_batch = _batch_descriptor(hand_owner_mesh, owner_mark.material_override)
	if _wall_masks.has(int(e.id)): model.wall_mask = int(_wall_masks[int(e.id)])
	if scaffold:
		var progress_back = _pose_mesh(square_mesh, _material(Color("40382c")))
		hp_root.add_child(progress_back)
		progress_back.position = Vector3(0, -.25, .01)
		progress_back.scale = Vector3(hp_width, .08, 1)
		var progress_fill = _pose_mesh(square_mesh, _material(TEAM_COLORS[int(e.team)]))
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
	elif not volumetric:model.paper_batch=_batch_descriptor(graphic.mesh,null,true)
	if quality_policy!="native":_prepare_quality_batches(model)
	model.terrain_height=root.position.y
	model.last_terrain_pos=e.pos
	model.is_air=spec.get("domain","ground")=="air"
	model.domain=str(spec.get("domain","ground"))
	model.fog_hidden=not sim.entity_visible_to(0,int(e.id))
	model.cull_radius=maxf(dimensions.x,dimensions.y)*.7+8.0
	model.last_visual_elapsed=elapsed-frame_delta
	model.last_hp_yaw=INF
	model.last_turret_angle=INF
	model.last_progress=-1.0
	if volumetric:model.volume.cargo_capacity=float(sim.rules.economy.harvester_capacity)
	model.smoke_ports=[]
	model.smoke_size_factor=1.0 if VOLUME.art_faction(model.spec)=="rivet" else .47
	if model.kind=="building" and model.spec.art=="power":
		for port in model.volume.get("smoke_ports",[]):
			if port is Vector3:model.smoke_ports.append(port)
		if model.smoke_ports.is_empty():
			if VOLUME.art_faction(model.spec)=="rivet":model.smoke_ports.append(Vector3(.73,3.49,-.87))
			else:model.smoke_ports.append_array([Vector3(-.78,2.08,-.35),Vector3(0,2.08,-.35),Vector3(.78,2.08,-.35)])
	return model


func _reset_model(model:Dictionary,e:Dictionary) -> void:
	model.erase("visual_signature")
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
	model.erase("track_pos")
	if model.volumetric:
		model.volume.clock=0.0
		model.volume.pose_active=true
		if not bool(model.get("direct_skinned", false)):
			model.volume.body.position=Vector3.ZERO
			model.volume.body.rotation=Vector3.ZERO
		elif model.volume.get("skeleton") is Skeleton3D:
			model.volume.skeleton.reset_bone_poses()
	if quality_policy != "native": _prepare_quality_batches(model)


func _pool_model(model:Dictionary) -> void:
	model.erase("creator_crushed")
	var key:String=str(model.spec.get("id", ""))+":"+str(model.team)
	# Definitions do not carry their dictionary key. The root retains that ID.
	key=str(model.get("pool_spec",""))+":"+str(model.team)
	if model.has("wall_mask"): key += ":wall:" + str(model.wall_mask)
	if not model_pool.has(key):model_pool[key]=[]
	if model_pool[key].size()<12 and not model.scaffold:
		model.root.visible=false
		model_pool[key].append(model)
	else:model.root.queue_free()


func _sync_entity(model: Dictionary, e: Dictionary, selected: bool) -> void:
	model.erase("visual_signature")
	_update_entity(model,e,selected)


func _update_entity(model: Dictionary, e: Dictionary, selected: bool) -> void:
	model.embarked = int(e.get("transport_id", -1)) > 0
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
	if model.volumetric and bool(model.volume.get("aircraft",false)) and float(model.flight_height)!=flight_height:
		model.art_root.position.y=flight_height
		model.hp_root.position.y=float(model.base_hp_height)+flight_height
		# Grounded identification stays separate from the aircraft's flying body.
		var shadow_factor: float=clampf(1.0-flight_height*.035,.52,1.0)
		model.shadow.scale=Vector3(model.dimensions.x*.40*shadow_factor,1.0,model.dimensions.x*.19*shadow_factor)
	model.flight_height=flight_height
	if quality_policy!="performance" and model.volumetric and e.kind == "unit" and model.get("domain","ground") != "naval" and not model.volume.aircraft and not model.volume.infantry and frame_delta > 0:
		var last_track: Vector2 = model.get("track_pos", pos)
		if e.state == "move" and pos.distance_to(last_track) > .32:
			var heading: float = deg_to_rad(float(e.alpha))
			var side := Vector2(-sin(heading),cos(heading)) * float(e.radius) * .72
			for offset in [-side,side]:
				var point: Vector2 = pos + offset
				var basis:=Basis(Vector3.UP,-heading)*Basis(Vector3.RIGHT,-PI*.5)
				tracks.append({"pos":Vector3(point.x,MAP.height_at(sim.map,point)+.035,point.y),"heading":heading,"basis":basis.scaled_local(Vector3(.28,.13,1)),"age":0.0})
			while tracks.size() > 1800: tracks.pop_front()
			model.track_pos = pos
		elif not model.has("track_pos"): model.track_pos = pos
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
		var building_alpha: float = float(e.alpha) if model.spec.get("role", "") == "shipyard" else 0.0
		if model.last_alpha != building_alpha:
			root.rotation.y = -deg_to_rad(building_alpha)
			model.last_alpha = building_alpha
		if model.volume.turret != null:
			var angle:float=-deg_to_rad(float(e.get("turret_alpha",0.0)))
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
		model.last_visual_elapsed=elapsed
		var hp_yaw:float=camera_yaw-root.rotation.y
		if float(model.last_hp_yaw)!=hp_yaw:
			model.hp_root.rotation.y=hp_yaw
			model.last_hp_yaw=hp_yaw
		model.state = state
	if state != model.state:
		_set_paper_state(model,state)
	var health_cap: float = SCAFFOLD.health_cap(e, model.spec) if model.scaffold else float(model.spec.hp)
	var fraction: float = clampf(float(e.hp) / maxf(health_cap, .001), 0.0, 1.0)
	var hp_width: float = model.hp_width
	if fraction != model.hp_fraction:
		model.hp_fill.scale.x = hp_width * fraction
		model.hp_fill.position.x = (fraction - 1.0) * hp_width * 0.5
		model.hp_fill_back.scale.x = hp_width * fraction
		model.hp_fill_back.position.x = (fraction - 1.0) * hp_width * 0.5
		model.hp_fraction = fraction
	if model.volumetric:
		for part in model.render_parts:
			var transform:Transform3D=part.node.global_transform
			_append_batch(part.batch,transform)
			if part.has("ink_batch"):
				_append_batch(part.ink_batch,transform)
				_append_batch(part.paper_batch,transform)
		for i in range(int(model.volume.get("cargo_count",0))):
			var piece: Node3D = model.volume.cargo[i]
			_append_batch(model.cargo_batches[i],piece.global_transform)
	else:
		_append_batch(model.paper_batch,root.global_transform * model.art_root.transform)
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
	if selected or model.scaffold or float(e.get("hit_flash",0.0)) > 0.0:
		var hp_transform:Transform3D=transform*model.hp_root.transform
		for index in range(model.hp_bars.size()):_append_batch(model.hp_batches[index],hp_transform*model.hp_bars[index].transform)


func _set_paper_state(model:Dictionary,state:String) -> void:
	var dimensions:Vector2=model.dimensions
	model.graphic.mesh=_card(VOLUME.art_faction(model.spec)+"_"+model.spec.art+"_"+state,dimensions.x,dimensions.y,_texture_path(model.spec,state),int(model.team))
	model.paper_batch=_batch_descriptor(model.graphic.mesh,null,true)
	model.state=state


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


func _start_death(model: Dictionary) -> void:
	if bool(model.get("fog_hidden", false)):
		_pool_model(model)
		return
	if bool(model.get("creator_crushed", false)):
		if quality_policy != "performance": CREATOR_CRUSH.spawn(self, model)
		_pool_model(model)
		return
	if quality_policy=="performance":
		if model.volumetric and not model.scaffold and not bool(model.get("direct_skinned", false)) and data_corpses.size()<24:
			data_corpses.append({"transform":model.render_parts[0].node.global_transform,"batch":model.render_parts[0].performance_batch,"age":0.0})
		_pool_model(model)
		return
	model.hp_root.visible = false
	model.ring.visible = false
	if not model.volumetric:
		model.graphic.visible = false
		model.shadow.visible = false
		var dimensions: Vector2 = model.dimensions
		model.graphic.mesh = _card(VOLUME.art_faction(model.spec)+"_"+model.spec.art+"_death", dimensions.x, dimensions.y, _texture_path(model.spec,"death"),int(model.team))
		model.paper_batch=_batch_descriptor(model.graphic.mesh,null,true)
	ghosts.append({"root":model.root,"art":model.art_root,"age":0.0,"building":model.kind == "building","model":model})


func _update_deaths(delta: float) -> void:
	for i in range(ghosts.size() - 1, -1, -1):
		var ghost: Dictionary = ghosts[i]
		ghost.age += delta
		var age: float = ghost.age
		if age>2.5:
			_pool_model(ghost.model)
			ghosts.remove_at(i)
			continue
		if not _point_in_view(ghost.root.global_position,float(ghost.model.dimensions.length())+8.0):continue
		if ghost.model.volumetric:
			if bool(ghost.model.volume.get("aircraft",false)):
				ghost.art.position.y=maxf(0.0,float(ghost.model.get("flight_height",0.0))-age*age*4.8)
				ghost.art.rotation.x=age*.7
			ghost.art.rotation.z = lerpf(0.0,0.12 if ghost.building else -0.22,clampf(age*2.0,0,1))
			if age > 1.0:
				ghost.art.scale = Vector3.ONE * maxf(0.0,1.0-(age-1.0)*0.7)
			if not bool(ghost.model.get("direct_skinned", false)):
				for mesh in ghost.model.volume.meshes:
					_batch(mesh.mesh,mesh.global_transform,mesh.material_override,true)
		else:
			ghost.art.rotation.x = lerpf(0.0,-PI*0.46,clampf(age*1.2,0,1))
			if age > 1.0:ghost.art.scale.y = maxf(0.0,1.0-(age-1.0)*0.7)
			_batch(ghost.model.graphic.mesh,ghost.root.global_transform*ghost.art.transform,null,true)
			_batch(shadow_mesh,ghost.root.global_transform*ghost.model.shadow.transform,ghost.model.shadow.material_override)


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
		var start: Vector2 = projectile.start
		var landing: Vector2 = projectile.landing
		var progress: float = clampf(float(projectile.elapsed) / maxf(float(projectile.duration), 0.001),0,1)
		var source_height: float=float(projectile.get("source_height",0.0))
		var source := Vector3(start.x,MAP.height_at(sim.map,start)+source_height+.9,start.y)
		if projectile.has("spec") and projectile.has("heading"):
			var spec: Dictionary = sim.data_for(projectile.spec)
			var kind: String = "building" if sim.rules.buildings.has(projectile.spec) else "unit"
			if VOLUME.supports(spec,kind):
				source = Vector3(start.x,MAP.height_at(sim.map,start)+source_height,start.y) + VOLUME.muzzle_offset(spec,kind,int(projectile.team),float(projectile.get("body_heading",projectile.heading)),float(projectile.heading))
		var destination := Vector3(landing.x,MAP.height_at(sim.map,landing)+float(projectile.get("target_height",.15)),landing.y)
		var arc: float = clampf(start.distance_to(landing)*.045,.08,.6)
		shells[i].position = source.lerp(destination,progress)+Vector3.UP*(4.0*progress*(1.0-progress))*arc
		var direction: Vector3 = destination-source
		shells[i].rotation.y = -atan2(direction.z,direction.x)
		var graphic:Variant=shells[i].get_child(0)
		graphic.rotation.z = atan2(direction.y+4.0*(1.0-2.0*progress)*arc,maxf(Vector2(direction.x,direction.z).length(),.1))
		_batch(shell_mesh,graphic.global_transform,energy_projectile_material if _energy_weapon(str(projectile.get("spec", ""))) else projectile_material)


func _sync_data_projectiles() -> void:
	for projectile in sim.projectiles:
		if not _projectile_visible(projectile): continue
		var start:Vector2=projectile.start
		var landing:Vector2=projectile.landing
		var source:Vector3=Vector3(start.x,MAP.height_at(sim.map,start)+float(projectile.get("source_height",0.0))+.9,start.y)
		var destination:=Vector3(landing.x,MAP.height_at(sim.map,landing)+float(projectile.get("target_height",.15)),landing.y)
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
			var radius: float = float(event.get("blast",event.get("radius",1.0)))
			var impact_height: float=float(event.get("height",event.get("target_height",.18)))
			_spawn_effect(event.pos, "impact", radius,impact_height)
			_spawn_smoke(event.pos,radius,impact_height)
		elif event.kind == "death" and bool(event.get("destroyed",true)):
			var spec: Dictionary = sim.data_for(event.spec)
			var kind: String = "building" if sim.rules.buildings.has(event.spec) else "unit"
			if VOLUME.supports(spec,kind):
				var radius: float = float(spec.get("size", 1.8)) * .85
				var burst_height: float = float(event.get("height",0.0))+float(VOLUME._recipe(spec,kind,int(event.team)).dimensions.y) * .7
				_spawn_effect(event.pos,"death",radius,burst_height)
				_spawn_smoke(event.pos,radius,burst_height,true)
				_spawn_debris(event.pos,radius,burst_height)
		elif event.kind == "ruin_destroy":
			_spawn_smoke(event.pos,float(event.radius),.5,true)
			_spawn_debris(event.pos,float(event.radius),1.0)
		elif event.kind == "fire":
			var source: Vector2 = event.pos
			var landing: Vector2 = event.get("landing",source+Vector2.RIGHT)
			var direction: Vector2 = (landing-source).normalized()
			var muzzle_height: float = float(event.get("height",0.0))+.9
			if models.has(event.get("id",-1)):
				var model: Dictionary = models[event.id]
				if model.volumetric and model.volume.muzzle != null:
					var muzzle: Vector3 = model.volume.muzzle.global_position
					source = Vector2(muzzle.x,muzzle.z)
					muzzle_height = muzzle.y-MAP.height_at(sim.map,source)
				else:
					var size: Vector2 = model.dimensions
					source += direction*size.x*.35
					muzzle_height = size.y*.5
			_spawn_effect(source,"fire",0.5,muzzle_height)
			if _energy_weapon(str(event.get("spec", ""))):
				_spawn_tracer(source-direction*.65, source+direction*.18, muzzle_height, muzzle_height, Color("c6b8ef"))
			var weapon: Dictionary = sim.rules.weapons.get(event.get("weapon",""),{})
			if weapon.get("kind","") == "instant":
				_spawn_tracer(source,landing,muzzle_height,float(event.get("target_height",.8)))
		elif event.kind == "build" or event.kind == "produce":
			_spawn_effect(event.pos,"build",0.75)
		elif event.kind == "overcharge":
			_spawn_effect(event.pos,"build",1.0,1.2)

func _energy_weapon(spec_id: String) -> bool:
	return spec_id in ["iron_advanced", "sky_tank", "sky_artillery", "sky_disruptor", "sky_pulse", "sky_anti_tower"]


func _add_effect(effect:Dictionary) -> void:
	# Shape, material family, cull extent and source tint are fixed at birth.
	# Alpha/pose still evolve continuously with the same original formulas.
	var graphic=effect.graphic
	graphic.visible=false
	effect.base_color=graphic.material_override.albedo_color
	effect.cull_radius=(effect.base as Vector3).length()+(effect.get("velocity",Vector3.ZERO) as Vector3).length()*float(effect.life)+8.0
	effect.colored=effect.kind in ["blast","death_blast","smoke","scorch","shock"]
	effect.batch=_batch_descriptor(_particle_mesh(graphic.mesh),_particle_material(graphic.material_override,str(effect.kind)),false,true) if effect.colored else _batch_descriptor(graphic.mesh,graphic.material_override)
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


func _spawn_effect(pos: Vector2, kind: String, radius: float, height: float = -1.0) -> void:
	if quality_policy=="performance":
		if kind in ["impact","death","fire"]:_spawn_data_effect(pos,radius,.2 if height == -1.0 else height,kind)
		return
	if kind in ["impact","death"]:
		var destroyed: bool=kind=="death"
		# Anchored fireballs and a low shock ring; no billboard, outline or card.
		var spread: float = clampf(radius,.45,2.5)*(1.3 if destroyed else 1.0)
		for i in range(6):
			var root := Node3D.new()
			add_child(root)
			var angle: float = i * 2.39996
			root.position = Vector3(pos.x+cos(angle)*spread*.14,MAP.height_at(sim.map,pos)+(.18 if height == -1.0 else height),pos.y+sin(angle)*spread*.14)
			var mat:StandardMaterial3D=_blast_source_material()
			var graphic = _pose_mesh(smoke_mesh,mat)
			root.add_child(graphic)
			graphic.scale = Vector3.ONE * .01
			_add_effect({"root":root,"graphic":graphic,"kind":"death_blast" if destroyed else "blast","delay":float(i%3)*.14 if destroyed else 0.0,"age":0.0,"base":Vector3(spread*.7,spread*.65,spread*.7)*(1.0-float(i%3)*.16),"velocity":Vector3(cos(angle)*spread*.35,.15+float(i%3)*.4,sin(angle)*spread*.35),"life":.85+float(i%3)*.1 if destroyed else .38+float(i%3)*.07})
		# Airbursts illuminate the target altitude without a ground shock ring.
		if height>2.0:return
		var ring := Node3D.new()
		add_child(ring)
		ring.position = Vector3(pos.x,_cursor_surface_y(pos)+.05,pos.y)
		var mat:StandardMaterial3D=_material(Color("b89b70"),true)
		var graphic = _pose_mesh(ring_mesh,mat)
		ring.add_child(graphic)
		_add_effect({"root":ring,"graphic":graphic,"kind":"shock","age":0.0,"base":Vector3(spread*1.5,1,spread*1.5),"life":1.0 if destroyed else .5})
		if destroyed:
			var scorch:=Node3D.new()
			add_child(scorch)
			scorch.position=ring.position-Vector3.UP*.015
			var mark=_pose_mesh(shadow_mesh,_material(Color(.15,.10,.07,.5),true))
			scorch.add_child(mark)
			_add_effect({"root":scorch,"graphic":mark,"kind":"scorch","age":0.0,"base":Vector3(spread,1,spread),"life":7.0})
		return
	var root := Node3D.new()
	add_child(root)
	root.position = Vector3(pos.x,MAP.height_at(sim.map,pos)+(.9 if height == -1.0 else height),pos.y)
	var graphic = _pose_mesh(smoke_mesh,_material(Color("ffe1a0")))
	root.add_child(graphic)
	graphic.scale = Vector3(.3,.2,.3) if kind == "fire" else Vector3(.5,.1,.5)
	_add_effect({"root":root,"graphic":graphic,"kind":kind,"age":0.0,"base":graphic.scale,"life":.12 if kind == "fire" else .5})


func _spawn_debris(pos: Vector2, radius: float, height: float) -> void:
	if quality_policy=="performance":return
	for i in range(10):
		var root:=Node3D.new()
		add_child(root)
		root.position=Vector3(pos.x,MAP.height_at(sim.map,pos)+height,pos.y)
		var chip:BoxMesh=debris_meshes[i%3]
		var graphic=_pose_mesh(chip,_material(Color("5d4b37") if i%3 else Color("cdb991")))
		root.add_child(graphic)
		var angle: float=i*2.39996
		_add_effect({"root":root,"graphic":graphic,"kind":"debris","age":0.0,"base":Vector3.ONE,"velocity":Vector3(cos(angle),1.1+float(i%3)*.4,sin(angle))*clampf(radius*1.4,1.2,3.5),"floor":-height+.05,"life":1.6})

func _spawn_smoke(pos: Vector2, radius: float, height: float = .5, destruction: bool = false) -> void:
	if quality_policy=="performance":
		if destruction:_spawn_data_effect(pos,radius,height,"smoke")
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
		_add_effect({"root":root,"graphic":graphic,"kind":"smoke","age":0.0,"base":base,"life":3.0+float(i)*.3 if destruction else 1.35+float(i)*.15})


func _spawn_data_effect(pos:Vector2,radius:float,height:float,kind:String) -> void:
	if data_effects.size()>=128 or _fx_spawned>=24:return
	var origin:=Vector3(pos.x,MAP.height_at(sim.map,pos)+height,pos.y)
	if not _point_in_view(origin,maxf(radius,2.0)):return
	_fx_spawned+=1
	data_effects.append({"pos":origin,"radius":clampf(radius,.25,2.0),"kind":kind,"age":0.0,"life":1.0 if kind=="smoke" else .55 if kind=="death" else .3 if kind=="impact" else .09})


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
		_append_batch(batch,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*size),position),color)
	for index in range(data_corpses.size()-1,-1,-1):
		var corpse:Dictionary=data_corpses[index]
		corpse.age+=delta
		var progress:float=float(corpse.age)/.45
		if progress>=1.0:data_corpses.remove_at(index);continue
		var transform:Transform3D=corpse.transform
		transform.basis=transform.basis.rotated(Vector3.RIGHT,progress*.25).scaled(Vector3.ONE*(1.0-progress*.7))
		_append_batch(corpse.batch,transform)


func _update_effects(delta: float) -> void:
	if quality_policy=="performance":
		_update_data_effects(delta)
		return
	for i in range(tracks.size()-1,-1,-1):
		var track: Dictionary = tracks[i]
		track.age += delta
		if track.age >= 5.0:
			tracks.remove_at(i)
			continue
		if not _point_in_view(track.pos,1.0):continue
		var basis:Basis=track.basis
		# Quantized alpha shares materials and draw batches across all vehicles.
		var bucket:int=clampi(roundi((1.0-float(track.age)/5.0)*7.0),0,7)
		_batch(square_mesh,Transform3D(basis,track.pos),track_materials[bucket])
	for i in range(effects.size()-1,-1,-1):
		var effect: Dictionary = effects[i]
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
			effect.graphic.scale = effect.base * (.15 + sin(progress*PI)*.9)
			effect.graphic.position = effect.velocity * progress
			color=Color("ff9d28").lerp(Color("8b3521"),progress)
			color.a=1.0-progress
		elif effect.kind == "debris":
			var age: float=float(effect.age)
			var offset: Vector3=effect.velocity*age+Vector3.DOWN*4.9*age*age
			offset.y=maxf(offset.y,float(effect.floor))
			effect.graphic.position=offset
			effect.graphic.rotation=Vector3(age*6,age*4,age*3)
			effect.graphic.scale=Vector3.ONE*minf(1,(1-progress)*4)
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
			color.a=(1.0-progress)*.8
		elif effect.kind != "tracer":
			effect.root.rotation.y = camera_yaw
			effect.graphic.scale = effect.base * (0.35 + sin(progress*PI)*0.9)
			effect.graphic.position.y = progress * 0.7
			effect.graphic.rotation.z = progress*.22
		if show:
			_append_batch(effect.batch,effect.graphic.global_transform,color if effect.colored else null)


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
	var signature:Array=[placement.spec,placement.pos,placement.valid,str(placement.get("channel","normal")),int(placement.get("builder",sim.building_orders[0].get("builder",-1)))]
	for zone: Dictionary in zones: signature.append_array([zone.id, zone.pos, zone.radius, zone.role])
	for building in sim._building_entities:
		signature.append_array([building.id,building.team,building.pos,float(building.construct_remaining)<=0.0,float(building.hp)>0.0])
	if signature==_guide_signature:
		if is_instance_valid(placement_node):placement_node.visible=true
		return
	_guide_signature=signature
	guide_mesh.clear_surfaces()
	var spec: Dictionary = sim.rules.buildings[placement.spec]
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
	guide_mesh.surface_end()
	var key: String = spec.faction + "_" + spec.art + "_idle"
	if not is_instance_valid(placement_node) or placement_key != key:
		if is_instance_valid(placement_node):
			placement_node.queue_free()
		placement_node = Node3D.new()
		add_child(placement_node)
		var preview: Dictionary = VOLUME.create_model(spec,"building",0)
		placement_node.add_child(preview.root)
		var border := _mesh_instance(ring_mesh)
		placement_node.add_child(border)
		border.scale = Vector3(float(spec.size)*.76,1,float(spec.size)*.76)
		border.position.y = .05
		placement_key = key
	var pos: Vector2 = placement.pos
	placement_node.visible = true
	placement_node.position = Vector3(pos.x,MAP.entity_surface_y(sim.map,pos,str(spec.get("domain","ground"))),pos.y)
	placement_node.rotation.y = -deg_to_rad(load("res://scripts/naval_operations.gd").shipyard_heading(sim,pos)) if spec.get("role","") == "shipyard" else 0.0
	placement_node.get_child(1).material_override = _material(Color("7b9764") if placement.valid else Color("c56c4d"))


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
