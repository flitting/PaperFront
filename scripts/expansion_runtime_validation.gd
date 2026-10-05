extends RefCounted

## Explicit runtime smoke entry point. This harness is never run by a normal
## match and does not change the rule catalog, costs, weapons or quality presets.
const CATALOG = preload("res://scripts/battlefield_catalog.gd")
const PICKING = preload("res://scripts/entity_picking.gd")
const MODELS = preload("res://scripts/volume_models.gd")
const POSE_MESH = preload("res://scripts/pose_mesh.gd")

static func run(game: Node) -> void:
	if "--verify-expansion" not in OS.get_cmdline_user_args(): return
	var probe := RuntimeProbe.new()
	await probe.execute(game)

class RuntimeProbe extends RefCounted:
	var game: Node
	var checks: Array[Dictionary] = []
	var failures: Array[String] = []
	var details: Dictionary = {}
	var output: String = "user://expansion_runtime.json"
	var capture_dir: String = ""
	var hand_only: bool = false
	var audit: InputAudit
	var normal_save_existed: bool = false
	var normal_save_backup := PackedByteArray()
	var normal_save_touched: bool = false
	var picking_cache: Dictionary = {}

	func check(ok: bool, label: String) -> void:
		checks.append({"label":label,"pass":ok})
		if not ok: failures.append(label)

	func frames(count: int = 3) -> void:
		for frame in range(count): await game.get_tree().process_frame

	func click(point: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
		# Parse genuine client-pixel mouse events, including Input's held-button
		# state, through GUI and _unhandled_input. The main scene cancels a drag
		# when that state is released, so push_input alone cannot model a click.
		# Selection and target IDs are resolved by the application's mesh picker.
		# Synthetic events do not move the OS pointer. BaseButton also checks
		# the actual hover at release, so establish that real input precondition.
		game.get_window().grab_focus()
		game.get_viewport().warp_mouse(point)
		await game.get_tree().process_frame
		var motion := InputEventMouseMotion.new()
		var pixel: Vector2 = game.get_viewport().get_final_transform() * point
		motion.position = pixel
		motion.global_position = pixel
		Input.parse_input_event(motion)
		for pressed in [true, false]:
			var event := InputEventMouseButton.new()
			event.position = pixel
			event.global_position = pixel
			event.button_index = button
			event.pressed = pressed
			event.button_mask = (MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if pressed else 0
			Input.parse_input_event(event)
			await game.get_tree().process_frame

	func key(keycode: Key) -> void:
		for pressed in [true,false]:
			var event := InputEventKey.new()
			event.keycode = keycode
			event.physical_keycode = keycode
			event.pressed = pressed
			Input.parse_input_event(event)
			await game.get_tree().process_frame

	func wait_hud_selection(expected: Array) -> void:
		var deadline: int = Time.get_ticks_usec() + 2000000
		while game.hud.selection != expected and Time.get_ticks_usec() < deadline:
			await game.get_tree().process_frame

	## Plan real clicks from current visible mesh surfaces. Model revisions may
	## change palm/finger height or joint angle; the scene picker owns the hit.
	func visible_mesh_point(id: int, sources: Array) -> Vector2:
		if bool(game.world.models[id].get("direct_skinned",false)):
			return skinned_region_point(id,game.world.models[id].volume,[]).get("screen",Vector2.INF)
		for source in sources:
			if not (source is MeshInstance3D or source is Node3D and source.get_script()==POSE_MESH) or source.mesh == null: continue
			var center: Vector2 = game.project_world_to_screen(source.global_transform * source.mesh.get_aabb().get_center())
			if not game.world.models[id].get("volumetric", false) and world_click_hits(center, id): return center
			for surface in range(source.mesh.get_surface_count()):
				var arrays: Array = source.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				var count: int = vertices.size() if indices.is_empty() else indices.size()
				var stride: int = maxi(1, count / 300) * 3
				for index in range(0, count - 2, stride):
					var point := Vector3.ZERO
					for corner in range(3): point += vertices[index + corner if indices.is_empty() else indices[index + corner]] / 3.0
					var world_point: Vector3 = source.global_transform * point
					var screen: Vector2 = game.project_world_to_screen(world_point)
					if world_click_hits(screen, id, world_point): return screen
		return Vector2.INF

	func world_click_hits(screen: Vector2, id: int, surface_point: Vector3 = Vector3.INF) -> bool:
		if not screen.is_finite() or not game.battlefield_rect().has_point(screen) or game.hud.blocks_world_scroll(screen) or game.pick_entity(screen) != id: return false
		if not surface_point.is_finite() or not game.world.models[id].get("volumetric", false): return true
		var pixel: Vector2 = game.screen_to_battlefield(screen)
		var origin: Vector3 = game.camera.project_ray_origin(pixel)
		var direction: Vector3 = game.camera.project_ray_normal(pixel)
		var hit: Dictionary = game._building_ray_hit(origin, direction) if game.sim.entities[id].kind == "building" else game._unit_ray_hit(origin, direction)
		# A finger point hidden behind this same hand's palm would also yield the
		# hand ID. Require its visible surface depth, not merely the entity ID.
		var tolerance:float=.006 if bool(game.world.models[id].get("direct_skinned",false)) else .04
		return int(hit.id) == id and absf(float(hit.depth) - (surface_point - origin).dot(direction)) < tolerance

	func model_meshes(model: Dictionary) -> Array:
		var sources: Array = []
		if bool(model.get("direct_skinned",false)):
			for source in model.get("volume",{}).get("meshes",[]):
				if source is MeshInstance3D:sources.append(source)
		for part in model.get("render_parts", []):
			var source:Variant=part.get("node")
			if source is MeshInstance3D or source is Node3D and source.get_script()==POSE_MESH:
				# PoseMesh is the actual transform/original mesh source of the
				# visible MultiMesh batch, not an independently drawn placeholder.
				if part.get("batch") is Dictionary and part.batch.get("multi") is MultiMesh:
					check(part.batch.multi.mesh==source.mesh,"mouse fixture retains original submitted mesh for "+str(model.spec.get("id",model.spec.get("art","model"))))
					if part.batch.multi.mesh!=source.mesh:continue
				sources.append(source)
		var graphic:Variant=model.get("graphic")
		if sources.is_empty() and (graphic is MeshInstance3D or graphic is Node3D and graphic.get_script()==POSE_MESH): sources.append(graphic)
		return sources

	func skin_report(volume: Dictionary, label: String, require_visible: bool = true) -> Dictionary:
		var skeleton: Skeleton3D = volume.get("skeleton")
		var graphic: MeshInstance3D = volume.get("skinned_mesh")
		check(bool(volume.get("direct_skinned",false)) and volume.get("parts",[]).is_empty(),label+" uses one continuous skin without rigid mesh pieces")
		check(skeleton != null and graphic != null and graphic.mesh != null and graphic.skin != null,label+" has a real MeshInstance3D, Skin and Skeleton3D")
		if skeleton==null or graphic==null or graphic.mesh==null or graphic.skin==null:return {}
		var bones: Array[String] = []
		for bone in range(skeleton.get_bone_count()):bones.append(str(skeleton.get_bone_name(bone)))
		var expected: Array = ["Palm","ThumbProximal","ThumbMiddle","ThumbDistal","IndexProximal","IndexMiddle","IndexDistal","MiddleProximal","MiddleMiddle","MiddleDistal","RingProximal","RingMiddle","RingDistal","LittleProximal","LittleMiddle","LittleDistal"]
		check(bones.size()==16 and expected.all(func(name):return name in bones),label+" has the sixteen palm/finger bones and no wrist or forearm bone")
		check(volume.get("meshes",[]).size()==1 and volume.meshes[0]==graphic,label+" submits a single original continuous skin mesh")
		check(graphic.get_node_or_null(graphic.skeleton)==skeleton,label+" skin resolves its own skeleton binding")
		check(not require_visible or graphic.is_visible_in_tree(),label+" continuous mesh is actually visible in the scene tree")
		var bound: bool = graphic.skin.get_bind_count()==16
		for slot in range(graphic.skin.get_bind_count()):
			var bone: int = graphic.skin.get_bind_bone(slot)
			if bone<0:bone=skeleton.find_bone(graphic.skin.get_bind_name(slot))
			bound=bound and bone>=0 and bone<skeleton.get_bone_count()
		check(bound,label+" all sixteen Skin bindings reference valid private bones")
		var weighted: int = 0
		var vertices: int = 0
		var valid: bool = true
		for surface in range(graphic.mesh.get_surface_count()):
			var arrays: Array = graphic.mesh.surface_get_arrays(surface)
			var count: int = arrays[Mesh.ARRAY_VERTEX].size()
			var ids: Variant = arrays[Mesh.ARRAY_BONES]
			var weights: Variant = arrays[Mesh.ARRAY_WEIGHTS]
			var stride: int = int(ids.size()/maxi(1,count)) if ids!=null else 0
			vertices+=count
			valid=valid and stride>0 and weights!=null and weights.size()==ids.size()
			if stride<=0 or weights==null:continue
			for vertex in range(count):
				var total: float = 0.0
				for influence in range(stride):
					var offset: int = vertex*stride+influence
					var weight: float = float(weights[offset])
					valid=valid and is_finite(weight) and weight>=0.0
					if weight>0.0:valid=valid and int(ids[offset])>=0 and int(ids[offset])<graphic.skin.get_bind_count()
					total+=weight
				if total>.001:weighted+=1
		check(valid and vertices>0 and weighted==vertices,label+" original mesh carries finite valid skin weights on every vertex")
		return {"valid":valid and bound and vertices>0 and weighted==vertices and bones.size()==16 and expected.all(func(name):return name in bones),"representation":"MakeHuman continuous skinned mesh","mesh_count":1,"bone_count":bones.size(),"bone_names":bones,"skin_bindings":graphic.skin.get_bind_count(),"vertices":vertices,"weighted_vertices":weighted,"mesh_visible":graphic.is_visible_in_tree()}

	## The positions below come only from the CPU pose used by EntityPicking.
	## Original mesh arrays supply weights/indices for region classification;
	## rest positions are never projected into a mouse click.
	func skinned_region_point(id: int, volume: Dictionary, region: Array[String]) -> Dictionary:
		var graphic: MeshInstance3D = volume.skinned_mesh
		var skeleton: Skeleton3D = volume.skeleton
		skeleton.force_update_all_bone_transforms()
		var posed: Dictionary = PICKING._skinned_surface(graphic,volume,picking_cache)
		if posed.is_empty():return {}
		var names: Array[String] = []
		for bind in range(graphic.skin.get_bind_count()):
			var bone: int = graphic.skin.get_bind_bone(bind)
			if bone<0:bone=skeleton.find_bone(graphic.skin.get_bind_name(bind))
			names.append(str(skeleton.get_bone_name(bone)))
		var candidates: Array[Dictionary] = []
		for surface_index in range(posed.surfaces.size()):
			var surface: Dictionary = posed.surfaces[surface_index]
			var arrays: Array = graphic.mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = surface.vertices
			var indices: PackedInt32Array = surface.indices
			var ids: Variant = arrays[Mesh.ARRAY_BONES]
			var weights: Variant = arrays[Mesh.ARRAY_WEIGHTS]
			var stride: int = int(ids.size()/maxi(1,vertices.size()))
			var count: int = indices.size() if not indices.is_empty() else vertices.size()
			for offset in range(0,count-2,3):
				var chosen: Array[int] = []
				var coverage: float = 0.0
				var center := Vector3.ZERO
				var screens: Array[Vector2] = []
				for corner in range(3):
					var vertex: int = indices[offset+corner] if not indices.is_empty() else offset+corner
					chosen.append(vertex)
					center+=vertices[vertex]/3.0
					for influence in range(stride):
						var slot: int = vertex*stride+influence
						if names[int(ids[slot])] in region:coverage+=float(weights[slot])/3.0
					screens.append(game.project_world_to_screen(graphic.global_transform*vertices[vertex]))
				if region.is_empty():coverage=1.0
				if coverage<.5:continue
				var world_point: Vector3 = graphic.global_transform*center
				if game.camera.is_position_behind(world_point):continue
				var area: float = absf((screens[1]-screens[0]).cross(screens[2]-screens[0]))*.5
				if area<.2:continue
				candidates.append({"screen":game.project_world_to_screen(world_point),"world":world_point,"area":area,"region_weight":coverage,"surface":surface_index,"triangle":offset/3,"vertices":chosen,"bone_region":region})
		candidates.sort_custom(func(a,b):return a.area>b.area)
		for candidate: Dictionary in candidates.slice(0,120):
			if world_click_hits(candidate.screen,id,candidate.world):return candidate
		return {}

	func support_point(model: Dictionary, index: int = 0) -> Vector3:
		var volume: Dictionary = model.volume
		return model.root.to_local(volume.root.global_transform*volume.support_tips[index])

	func restore_normal_save() -> void:
		if not normal_save_touched: return
		if normal_save_existed:
			var file := FileAccess.open(game.SAVE_PATH,FileAccess.WRITE)
			if file: file.store_buffer(normal_save_backup)
		else: DirAccess.remove_absolute(ProjectSettings.globalize_path(game.SAVE_PATH))
		normal_save_touched = false

	func capture(name: String) -> void:
		if capture_dir.is_empty() or DisplayServer.get_name() == "headless": return
		await RenderingServer.frame_post_draw
		var path: String = capture_dir.path_join(name + ".png")
		check(game.get_viewport().get_texture().get_image().save_png(path) == OK, "capture " + name)

	func execute(owner_game: Node) -> void:
		game = owner_game
		audit = InputAudit.new()
		game.add_child(audit)
		var args := OS.get_cmdline_user_args()
		hand_only = "--expansion-hand-only" in args
		for i in range(args.size() - 1):
			if args[i] == "--expansion-output": output = args[i+1]
			if args[i] == "--expansion-capture-dir": capture_dir = args[i+1]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
		if not capture_dir.is_empty(): DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_dir))
		check(DisplayServer.get_name() != "headless", "real display for rendered runtime input smoke")
		game.audio.muted = true
		await frames()
		if not hand_only: await menus_and_maps()
		await creator_input()
		if not hand_only: await campaign_smoke()
		check(details.has("creator_input"), "Creator input sequence completed without script errors")
		if not hand_only: check(details.has("campaign") and details.has("normal_opening"), "full runtime smoke sequence completed")
		restore_normal_save()
		var report: Dictionary = {
			"schema":2,"expansion_version":6,"scope":"continuous-skin Creator mouse input" if hand_only else "exportable V6 expansion functionality smoke",
			"opt_in_flag":"--verify-expansion","fixture_only":true,
			"godot":Engine.get_version_info().string,"display":DisplayServer.get_name(),
			"renderer":RenderingServer.get_current_rendering_method(),"debug_build":OS.is_debug_build(),
			"native_simulation":game.sim.native_kernels_enabled,"native_render_batches":game.world.native_batches_enabled,
			"native_world_sync":game.world.native_world_sync_enabled,"checks":checks,"failures":failures,"details":details,"mouse_input_audit":audit.events
		}
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file: file.store_string(JSON.stringify(report, "  "))
		print("EXPANSION_RUNTIME ", JSON.stringify(report))
		for failure in failures: push_error(failure)
		game.quit_game(0 if failures.is_empty() else 1)

	func menus_and_maps() -> void:
		check(game.hud.entry_menu.visible, "entry menu starts visible")
		await click(game.hud.entry_menu.wiki_button.get_global_rect().get_center())
		check(game.hud.wiki.visible, "entry Wiki button opens real catalog")
		game.hud.wiki.select_entry("sky_creator_hand")
		await frames()
		var preview: Dictionary = game.hud.wiki.preview.model_data
		check(game.hud.wiki.selected_id == "sky_creator_hand", "Creator hand Wiki entry selectable")
		details.wiki_skin = skin_report(preview,"Creator Wiki preview")
		check(not game.hud.wiki.displayed_rows.is_empty(), "Creator Wiki numerical facts render")
		await capture("wiki_creator_hand")
		await click(game.hud.wiki.back_button.get_global_rect().get_center())
		check(game.hud.entry_menu.visible, "Wiki back button restores entry")
		await click(game.hud.entry_menu.play_button.get_global_rect().get_center())
		check(game.hud.menu.visible, "entry play button opens match settings")
		var maps: Array[Dictionary] = []
		for mode: String in CATALOG.MODES:
			game.hud.select_map(mode)
			check(game.hud.selected_map() == mode, "settings selects " + mode)
			check(not game.hud.match_setup.players_option.disabled, mode + " enables 2–4 slots")
			for players in range(2, 5):
				game.hud.match_setup.players_option.select(players-2)
				game.hud.match_setup.players_option.item_selected.emit(players-2)
				var options: Dictionary = game.hud.match_setup.options("sky")
				check(options.players == players and options.slots.size() == players, mode + " settings emits " + str(players) + " slots")
			var map: Dictionary = MapData.generate(mode, 73026, {"players":4})
			check(map.size == 320 and map.starts.size() == 4, mode + " creates real 320 map and four starts")
			maps.append({"mode":mode,"size":map.size,"starts":map.starts,"profile":map.profile})
		details.maps = maps
		await capture("match_settings_four_slots")
		check(game.start_match("forest", 73026, "sky", true), "normal forest match starts")
		game.hud.show_menu(false)
		game.hud.show_entry(false)
		game.pve_paused = true
		await frames()
		check(not game.dev_mode and game.started, "normal match uses normal mode")
		check(game.sim.counts(0) == Vector2i(0,1), "normal opening contains only headquarters")
		check(game.sim.money[0] <= float(game.sim.rules.economy.initial_money), "normal opening gets configured starting money")
		check(game.sim.order_for_team(0).is_empty(), "normal opening starts without a free construction order")
		check(game.selected.is_empty() and not game.hud.production_panel.visible and game.hud.entry_widgets.is_empty(), "normal opening hides the global construction bar until a production building is selected")
		details.normal_opening = {"tab":game.hud.tab,"money":game.sim.money[0],"units":game.sim.counts(0).x,"buildings":game.sim.counts(0).y,"dev_mode":game.dev_mode,"global_bar_visible":game.hud.production_panel.visible}
		await capture("normal_opening")
		var hq_id: int = -1
		for entity: Dictionary in game.sim.entities.values():
			if int(entity.team) == 0 and entity.kind == "building" and game.sim.data_for(entity.spec).get("role", "") == "hq": hq_id = int(entity.id); break
		check(hq_id > 0, "normal opening has a real friendly headquarters for mouse selection")
		if hq_id < 1: return
		game.focus = game.sim.entities[hq_id].pos
		game.distance = 34.0
		game.update_camera()
		game.world.sync(0.0, [], {})
		await frames()
		var hq_point: Vector2 = visible_mesh_point(hq_id, model_meshes(game.world.models[hq_id]))
		check(hq_point.is_finite(), "normal headquarters exposes an unobstructed visible mesh click point")
		if not hq_point.is_finite(): return
		await click(hq_point)
		await wait_hud_selection([hq_id])
		check(game.selected == [hq_id] and game.hud.production_panel.visible, "real left mouse click on headquarters opens its construction bar")
		check(game.hud.entry_widgets.has("sky_power") and not game.hud.entry_widgets.sky_power.button.disabled, "selected headquarters offers the unlocked power plant")
		check(not game.hud.entry_widgets.has("sky_hq") and not game.hud.entry_widgets.has("sky_tech") and not game.hud.entry_widgets.has("sky_outpost"), "headquarters hides rebuilding, locked technology and engineer-only deployment")
		check(game.hud.category_buttons.build.visible and game.hud.category_buttons.defense.visible and not game.hud.category_buttons.vehicle.visible, "headquarters only exposes its two independent construction channels")
		await capture("normal_headquarters_selected")
		# A unit is added only after checking the untouched normal opening; this
		# explicit interaction fixture cannot be mistaken for free opening units.
		var unit_id: int = game.sim.debug_spawn(0, "sky_rifle", game.sim.entities[hq_id].pos + Vector2(6, 4))
		check(unit_id > 0, "unit-only selection fixture spawns a friendly rifleman")
		if unit_id < 1: return
		game.world.sync(0.0, game.selected, {})
		await frames()
		var unit_point: Vector2 = visible_mesh_point(unit_id, model_meshes(game.world.models[unit_id]))
		check(unit_point.is_finite(), "unit-only fixture has an actual visible model click point")
		if not unit_point.is_finite(): return
		await click(unit_point)
		await wait_hud_selection([unit_id])
		check(game.selected == [unit_id] and not game.hud.production_panel.visible and game.hud.entry_widgets.is_empty(), "real mouse selection of only a unit hides the construction bar")
		details.normal_opening.headquarters_screen = [hq_point.x, hq_point.y]
		details.normal_opening.unit_screen = [unit_point.x, unit_point.y]
		details.normal_opening.unit_selection_fixture_only = true
		await capture("normal_unit_selected")

	func creator_input() -> void:
		check(game.start_match("dev", 7, "sky", true), "explicit input fixture starts")
		game.hud.show_menu(false)
		game.hud.show_entry(false)
		game.pve_paused = true
		# Keep the 1.45m hand on a verified wide land corridor. The dev map's
		# centre is a river/cliff junction, unsuitable for this walking fixture.
		var fixture_start := Vector2.INF
		for z in range(40,45):
			for x in range(12,23):
				var candidate := Vector2(x+.5,z+.5)
				if game.sim._segment_static(candidate,candidate+Vector2(14,0),1.5,-1) and game.sim._standing(candidate+Vector2(14,0),2.0,-1):
					fixture_start = candidate
					break
			if fixture_start.is_finite(): break
		check(fixture_start.is_finite(), "input fixture has a legal wide walking corridor")
		if not fixture_start.is_finite(): return
		var hand_id: int = game.sim.debug_spawn(0, "sky_creator_hand", fixture_start)
		check(hand_id > 0, "input fixture spawns Creator hand")
		if hand_id < 1: return
		game.focus = fixture_start + Vector2(2,1)
		game.distance = 28.0
		game.camera_pitch = 32.0
		game.yaw = PI * .5 + .3
		game.update_camera()
		game.world.sync(0.0, [], {})
		await frames()
		var model: Dictionary = game.world.models[hand_id]
		check(bool(model.get("direct_skinned",false)) and model.render_parts.is_empty(),"world renders the continuous hand directly instead of rigid MultiMesh parts")
		var rig: Dictionary = skin_report(model.volume,"world Creator hand")
		if rig.is_empty() or not rig.valid:return
		var skeleton: Skeleton3D = model.volume.skeleton
		var twin: Dictionary = MODELS.create_model(game.sim.data_for("sky_creator_hand"),"unit",0,true)
		game.add_child(twin.root)
		twin.root.hide()
		var index_bone: int = skeleton.find_bone("IndexProximal")
		var original_rotation: Quaternion = skeleton.get_bone_pose_rotation(index_bone)
		check(twin.skeleton!=skeleton and twin.skinned_mesh!=model.volume.skinned_mesh,"each continuous hand owns an independent Skeleton and mesh instance")
		twin.skeleton.set_bone_pose_rotation(twin.skeleton.find_bone("IndexProximal"),Quaternion(Vector3.BACK,.25))
		check(skeleton.get_bone_pose_rotation(index_bone).is_equal_approx(original_rotation),"changing another hand skeleton cannot alter the selected hero pose")
		twin.root.queue_free()
		var palm_hit: Dictionary = skinned_region_point(hand_id,model.volume,["Palm"])
		var palm_point: Vector2 = palm_hit.get("screen",Vector2.INF)
		check(palm_point.is_finite(), "current palm geometry supplies a visible mouse hit point")
		if not palm_point.is_finite(): return
		await click(palm_point)
		check(game.selected == [hand_id], "real left mouse click selects visible palm")
		game.selected.clear()
		var finger_hit: Dictionary = skinned_region_point(hand_id,model.volume,["IndexDistal","IndexMiddle"])
		var finger_point: Vector2 = finger_hit.get("screen",Vector2.INF)
		check(finger_point.is_finite(), "current walking finger geometry supplies a visible mouse hit point")
		if not finger_point.is_finite(): return
		await click(finger_point)
		check(game.selected == [hand_id], "real left mouse click selects visible walking finger")
		await capture("creator_selected")
		game.pve_paused = false
		var origin: Vector2 = game.sim.entities[hand_id].pos
		var destination: Vector2 = fixture_start + Vector2(4,0)
		var move_point: Vector2 = game.project_world_to_screen(Vector3(destination.x, game.cursor_surface_y(destination), destination.y))
		await click(move_point, MOUSE_BUTTON_RIGHT)
		var command_seen: bool = not game.sim.entities[hand_id].commands.is_empty() and game.sim.entities[hand_id].commands[0].kind == "move"
		check(command_seen, "real right mouse click issues a move command through ground picker")
		var minimum: Array[float] = [INF,INF]
		var maximum: Array[float] = [-INF,-INF]
		var walking_origins: Array[Quaternion] = []
		for name: String in ["IndexProximal","MiddleProximal"]:walking_origins.append(skeleton.get_bone_pose_rotation(skeleton.find_bone(name)))
		var moving_frames: int = 0
		var started_us: int = Time.get_ticks_usec()
		while Time.get_ticks_usec()-started_us < 3000000:
			await game.get_tree().process_frame
			if not game.sim.entities.has(hand_id): break
			if game.sim.entities[hand_id].state == "move":
				moving_frames += 1
				for i in range(2):
					var bone: int = skeleton.find_bone(["IndexProximal","MiddleProximal"][i])
					var relative:Quaternion=walking_origins[i].inverse()*skeleton.get_bone_pose_rotation(bone)
					var angle: float = relative.get_angle()*signf(relative.get_axis().dot(Vector3.BACK))
					minimum[i] = minf(minimum[i], angle)
					maximum[i] = maxf(maximum[i], angle)
		check(game.sim.entities[hand_id].pos.distance_to(origin) > 1.5, "main simulation actually moves the selected hand")
		check(moving_frames > 3 and maximum[0]-minimum[0] > .15 and maximum[1]-minimum[1] > .15, "both walking fingers animate during real movement")
		await capture("creator_stride")
		# The enemy is created outside auto-acquisition range. The application must
		# obtain its ID from the right-clicked visible building mesh.
		game.pve_paused = true
		game._flush_render_simulation()
		var target_pos: Vector2 = fixture_start + Vector2(14,0)
		var target_id: int = game.sim.debug_spawn(1, "rivet_power", target_pos)
		check(target_id > 0, "attack fixture spawns enemy building outside melee range")
		if target_id < 1: return
		game.world.sync(0.0, game.selected, {})
		game.focus = fixture_start + Vector2(8,0)
		game.distance = 34.0
		game.update_camera()
		await frames()
		var building: Dictionary = game.world.models[target_id]
		var target_point: Vector2 = visible_mesh_point(target_id, model_meshes(building))
		check(target_point.is_finite(), "enemy building supplies a visible surface for the actual attack click")
		if not target_point.is_finite(): return
		await click(target_point, MOUSE_BUTTON_RIGHT)
		var commands: Array = game.sim.entities[hand_id].commands
		check(not commands.is_empty() and commands[0].kind == "attack" and commands[0].target == target_id, "real right click picks enemy building and issues normal attack")
		game.pve_paused = false
		var hp_before: float = game.sim.entities[target_id].hp
		var windup_seen: bool = false
		var windup_captured: bool = false
		var alive_during_windup: bool = false
		var maximum_press: float = 0.0
		var contact_origin: float = support_point(model).x
		var maximum_contact_advance: float = 0.0
		var crush_event_seen: bool = false
		var windup_starts: int = 0
		var windup_active: bool = false
		var windup_sim_time: float = -1.0
		var destroyed_sim_time: float = -1.0
		started_us = Time.get_ticks_usec()
		while Time.get_ticks_usec()-started_us < 12000000:
			await game.get_tree().process_frame
			for event: Dictionary in game.sim.events:
				if event.get("kind")=="death" and int(event.get("id",-1))==target_id and event.get("death_style")=="creator_crush":crush_event_seen=true
			if not game.sim.entities.has(target_id):
				destroyed_sim_time = game.sim.time
				break
			var entity: Dictionary = game.sim.entities[hand_id]
			if float(entity.get("hand_strike",0.0)) > 0.0:
				if not windup_active: windup_starts += 1
				if not windup_seen:
					windup_sim_time = game.sim.time
				windup_seen = true
				alive_during_windup = alive_during_windup or game.sim.entities[target_id].hp == hp_before
				maximum_press = maxf(maximum_press, model.volume.body.position.x)
				maximum_contact_advance = maxf(maximum_contact_advance, support_point(model).x - contact_origin)
				if not windup_captured and float(entity.hand_strike) <= .14:
					windup_captured = true
					await capture("creator_slap_windup")
			windup_active = float(entity.get("hand_strike", 0.0)) > 0.0
		check(windup_seen and alive_during_windup, "normal slap has observable windup before building damage")
		check(destroyed_sim_time>windup_sim_time and destroyed_sim_time-windup_sim_time>=.35 and destroyed_sim_time-windup_sim_time<=.65,"observed normal slap retains its half-second windup within fixed-tick sampling tolerance")
		check(maximum_contact_advance > .25, "skinned contact fingertips visibly advance during the normal attack")
		check(windup_starts == 1 and not game.sim.entities.has(target_id), "one observed normal slap destroys the clicked enemy building")
		var recovery_start: float = float(game.sim.entities[hand_id].get("hand_recover",0.0))
		check(recovery_start>0.0,"normal slap enters its real recovery phase after impact")
		await capture("creator_slap_result")
		var rubble_seen: bool = false
		var recovery_frames: int = 0
		var recovery_low: float = INF
		var recovery_high: float = -INF
		started_us=Time.get_ticks_usec()
		while Time.get_ticks_usec()-started_us<1200000:
			await game.get_tree().process_frame
			rubble_seen=rubble_seen or game.world.effects.any(func(effect):return effect.get("kind")=="creator_rubble")
			if float(game.sim.entities[hand_id].get("hand_recover",0.0))>0.0:
				recovery_frames+=1
				var height:float=support_point(model).y
				recovery_low=minf(recovery_low,height)
				recovery_high=maxf(recovery_high,height)
		check(rubble_seen,"actual creator kill leaves visible compressed fragments")
		check(not game.world.ghosts.any(func(ghost):return ghost.model.get("spec",{}).get("art")=="power" and ghost.model.get("team",-1)==1),"creator crush leaves no intact enemy-building death ghost")
		check(float(game.sim.entities[hand_id].get("hand_recover",0.0))==0.0 and model.volume.skinned_mesh.is_visible_in_tree(),"continuous skin remains visible and returns from recovery")
		await capture("creator_recovered")
		details.creator_input = {"hand_id":hand_id,"target_id":target_id,"skin":rig,"palm_click_surface":palm_hit,"index_click_surface":finger_hit,"palm_screen":[palm_point.x,palm_point.y],"finger_screen":[finger_point.x,finger_point.y],"target_screen":[target_point.x,target_point.y],"moving_frames":moving_frames,"finger_rotation_range":[maximum[0]-minimum[0] if moving_frames > 0 else 0.0,maximum[1]-minimum[1] if moving_frames > 0 else 0.0],"windup_started_sim_seconds":windup_sim_time,"destroyed_sim_seconds":destroyed_sim_time,"windup_starts":windup_starts,"max_contact_finger_advance":maximum_contact_advance,"max_palm_press":maximum_press,"creator_crush_event_observed":crush_event_seen,"rubble_observed":rubble_seen,"recovery_started_seconds":recovery_start,"recovery_frames":recovery_frames,"recovery_contact_height_range":[recovery_low if recovery_frames>0 else 0.0,recovery_high if recovery_frames>0 else 0.0],"input_route":"posed Skin-weighted palm/index triangle/depth -> Input.parse_input_event -> GUI -> main._unhandled_input -> pick_entity/right_command","final_sim_time":game.sim.time,"final_entity":game.sim.entities[hand_id]}

	func campaign_smoke() -> void:
		game.hud.show_entry(true)
		await frames()
		await click(game.hud.entry_menu.campaign_button.get_global_rect().get_center())
		var deadline: int = Time.get_ticks_usec() + 90000000
		while (game.loading or game.sim.map.mode != "campaign") and Time.get_ticks_usec() < deadline: await game.get_tree().process_frame
		check(game.sim.map.mode == "campaign" and game.started and not game.loading, "real entry campaign button loads mission")
		if game.sim.map.mode != "campaign": return
		game.pve_paused = true
		await frames()
		check(game.sim.map.size == 320 and game.sim.campaign_controller != null, "campaign map and controller available at runtime")
		check(game.hud.campaign_ui.panel.visible and not game.hud.campaign_ui.objective_label.text.is_empty(), "runtime campaign objective panel visible")
		await click(game.hud.campaign_ui.target_button.get_global_rect().get_center())
		check(game.focus.is_equal_approx(game.hud.campaign_ui.target), "objective location button moves actual camera focus")
		await capture("campaign_runtime")
		var state: Dictionary = game.sim.campaign_controller.to_dict()
		var snapshot_path: String = "user://expansion_runtime_smoke.pfront"
		game._flush_render_simulation()
		check(game.sim.save_game(snapshot_path).is_empty(), "runtime campaign snapshot writes")
		var restored := WarSimulation.new()
		check(restored.load_game(snapshot_path).is_empty(), "runtime campaign snapshot reads")
		check(restored.campaign_controller != null and restored.campaign_controller.to_dict() == state, "runtime save preserves mission progress")
		# Exercise the main-scene save/load keyboard route while preserving any
		# player's existing save, even when this probe runs in their user folder.
		normal_save_existed = FileAccess.file_exists(game.SAVE_PATH)
		if normal_save_existed: normal_save_backup = FileAccess.get_file_as_bytes(game.SAVE_PATH)
		normal_save_touched = true
		await key(KEY_F5)
		check(FileAccess.file_exists(game.SAVE_PATH), "real F5 writes main-scene campaign save")
		await key(KEY_F9)
		deadline = Time.get_ticks_usec() + 90000000
		while game.loading and Time.get_ticks_usec() < deadline: await game.get_tree().process_frame
		check(not game.loading and game.sim.map.mode == "campaign" and game.started, "real F9 restores campaign through loading screen")
		check(game.sim.campaign_controller != null and game.sim.campaign_controller.to_dict() == state, "main-scene load preserves mission progress")
		restore_normal_save()
		await game.handle_action("restart", null)
		check(game.sim.map.mode == "campaign" and game.sim.campaign_controller.stage == 0, "real restart action resets campaign to objective one")
		check(game.hud.campaign_ui.panel.visible, "campaign objective panel survives restart")
		details.campaign = {"size":game.sim.map.size,"stage_after_restart":game.sim.campaign_controller.stage,"saved_state":state,"full_playthrough":false}

class InputAudit extends Node:
	var events: Array[Dictionary] = []
	func _input(event: InputEvent) -> void:
		if event is InputEventMouseButton: events.append({"phase":"input","position":[event.position.x,event.position.y],"pressed":event.pressed})
	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton: events.append({"phase":"unhandled","position":[event.position.x,event.position.y],"pressed":event.pressed})
