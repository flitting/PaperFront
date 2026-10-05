extends SceneTree

const PREVIEW = preload("res://scripts/wiki_model_preview.gd")
var failures: Array[String] = []
var checks: int = 0
var entries: int = 0
var solid_entries: int = 0
var paper_entries: int = 0
var mesh_count: int = 0


func _initialize() -> void:
	call_deferred("run")


func expect(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)


func run() -> void:
	var rules: Dictionary = RulesLoader.load_rules()
	expect(not rules.is_empty(), "Preview must use valid registered rules")
	var configured_entries: int = rules.units.size() + rules.buildings.size()
	var configured_paper: int = rules.units.values().filter(func(spec): return spec.art in ["rifle", "anti", "engineer", "demolition"]).size()
	var panel := Control.new()
	root.add_child(panel)
	var preview: WikiModelPreview = PREVIEW.new()
	panel.add_child(preview)
	preview.size = Vector2(640, 400)
	preview.set_rotation_active(false)
	var viewport_id: int = preview.viewport.get_instance_id()
	var stage_child_count: int = preview.stage.get_child_count()
	expect(preview.viewport.own_world_3d, "Gallery must own an isolated World3D")
	expect(preview.viewport.world_3d != root.world_3d, "Gallery must not render the battle world")
	expect(preview._paper_factory.sim == null and preview._paper_factory.camera == null, "Infantry art factory must not start a simulation")
	expect(not preview.is_processing(), "Empty preview should not rotate")
	expect(preview.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Empty preview should not render")
	for kind in ["unit", "building"]:
		var source: Dictionary = rules.units if kind == "unit" else rules.buildings
		for id in source:
			var spec: Dictionary = source[id]
			entries += 1
			var original_meshes: Array[Mesh] = []
			for team in [0, 1]:
				preview.set_entry(spec, kind, team)
				expect(preview.model_node != null, id + ": no live model")
				expect(preview.viewport.get_instance_id() == viewport_id, id + ": selection created a new viewport")
				expect(preview.stage.get_child_count() == stage_child_count, id + ": selection leaked stage nodes")
				expect(preview.rotation_pivot.get_child_count() == 2, id + ": must have exactly one model and one plinth")
				expect(is_zero_approx(preview.angle), id + ": new entry must start at the initial pose")
				expect(preview.model_node.find_children("*", "AudioStreamPlayer", true, false).is_empty() and preview.model_node.find_children("*", "AudioStreamPlayer3D", true, false).is_empty(), id + ": viewing an entry must be silent")
				var graphics: Array[Node] = preview.model_node.find_children("*", "MeshInstance3D", true, false)
				expect(not graphics.is_empty(), id + ": empty registered model")
				mesh_count += graphics.size()
				for graphic: MeshInstance3D in graphics:
					expect(graphic.mesh != null and graphic.mesh.get_surface_count() > 0, id + ": mesh failed to load")
					if team == 0: original_meshes.append(graphic.mesh)
				if kind == "unit" and spec.art in VolumeModels.INFANTRY_ART:
					if team == 0: paper_entries += 1
					check_paper(preview, spec, id, team)
				else:
					if team == 0: solid_entries += 1
					check_volume(preview, spec, kind, id, team)
				# Framing tests project every rendered part at all quarter views
				# and at wide, regular and tall preview sizes. The actual model
				# bounds include offsets ignored by nominal recipe dimensions.
				for dimensions: Vector2 in [Vector2(1000, 320), Vector2(640, 400), Vector2(420, 640)]:
					preview.size = dimensions
					preview._resize_viewport()
					for step in range(8):
						preview.angle = TAU * float(step) / 8.0
						preview.rotation_pivot.rotation.y = preview.angle
						check_framing(preview, id, team, step)
				preview.reset_rotation()
				expect(is_zero_approx(preview.angle), id + ": reset did not restore the initial pose")
			var previous_model: Node3D = preview.model_node
			preview.set_entry(spec, kind, 0)
			expect(not is_instance_valid(previous_model), id + ": switching selection retained its previous model")
			if not preview.is_volumetric:
				expect(preview.model_data.meshes[0].mesh == original_meshes[0], id + ": registered paper mesh cache was not reused")
	expect(entries == configured_entries and solid_entries == configured_entries - configured_paper and paper_entries == configured_paper, "Every configured entry keeps its required solid equipment or paper infantry model")
	expect(preview._paper_factory.card_cache.size() == configured_paper * 2, "Paper cache should contain exactly one idle pose per configured infantry and team")
	check_interaction_and_lifecycle(preview, panel, rules.units.kestrel_rifle)
	preview.clear_preview()
	expect(preview.model_node == null and preview.rotation_pivot.get_child_count() == 0, "Clearing preview must release model and platform")
	expect(not preview.is_processing() and preview.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Clearing preview must stop rotation and rendering")
	var helper: PaperWorld = preview._paper_factory
	preview.queue_free()
	panel.queue_free()
	await process_frame
	expect(not is_instance_valid(helper), "Freeing preview must release the unparented paper art factory")
	print("WIKI_PREVIEW ", JSON.stringify({"entries": entries, "solid": solid_entries, "paper": paper_entries, "part_meshes": mesh_count, "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)


func check_paper(preview: WikiModelPreview, spec: Dictionary, id: String, team: int) -> void:
	expect(not preview.is_volumetric, id + ": infantry became a solid model")
	var graphic: MeshInstance3D = preview.model_data.meshes[0]
	var mesh: Mesh = graphic.mesh
	expect(mesh.get_surface_count() == 3, id + ": original paper front, thickness wall or back missing")
	expect(mesh.get_aabb().size.z > 0.04 and mesh.get_aabb().size.z <= 0.066, id + ": cardboard edge thickness changed")
	expect(is_zero_approx(preview.camera.position.x), id + ": initial camera does not face the original illustration")
	for surface in [0, 2]:
		var material: ShaderMaterial = mesh.surface_get_material(surface)
		var picture: Texture2D = material.get_shader_parameter("illustration")
		var identity: Texture2D = material.get_shader_parameter("identity_mask")
		expect(picture != null and picture.resource_path == spec.animations.idle, id + ": preview replaced the registered idle illustration")
		expect(identity != null and identity.resource_path == str(spec.animations.idle).get_basename() + "_identity.svg", id + ": preview omitted the registered team mask")
		expect(material.get_shader_parameter("player_color") == VolumeModels.player_color(team), id + ": paper player color is wrong")
		expect(float(material.get_shader_parameter("identity_enabled")) == 1.0, id + ": paper player identification is disabled")


func check_volume(preview: WikiModelPreview, spec: Dictionary, kind: String, id: String, team: int) -> void:
	expect(preview.is_volumetric, id + ": vehicle or building lost its actual 3D model")
	var reference: Dictionary = VolumeModels.create_model(spec, kind, team)
	for index in range(reference.meshes.size()):
		expect(preview.model_data.meshes[index].mesh == reference.meshes[index].mesh, id + ": preview did not use the registered model mesh")
	if spec.get("has_turret", false):
		expect(preview.model_data.turret != null and preview.model_data.turret.get_child_count() > 0, id + ": turret and barrel are absent")
	if spec.art == "harvester":
		expect(preview.model_data.cargo.size() == 12, id + ": gallery harvester omitted its cargo")
		expect(preview.model_data.cargo.all(func(piece): return piece.visible), id + ": cargo is hidden")
	if spec.get("domain", "ground") == "air":
		expect(preview.model_data.aircraft and preview.model_bounds.size.z > 2.0, id + ": aircraft lost wing and tail volume")
	if spec.art == "airfield" and VolumeModels.art_faction(spec) in ["rivet","kestrel"]:
		# This vertex guard belongs to the original two hangar designs. Each
		# expansion design is checked against its own complete recipe above.
		var vertices: PackedVector3Array = preview.model_data.meshes[0].mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		expect(vertices.size() > 3000, id + ": airfield lost its merged hangar and parked aircraft geometry")
	reference.root.free()


func check_framing(preview: WikiModelPreview, id: String, team: int, step: int) -> void:
	var width: float = preview.camera.size * float(preview.viewport.size.x) / float(preview.viewport.size.y)
	var height: float = preview.camera.size
	var inverse: Transform3D = preview.camera.global_transform.affine_inverse()
	var fits: bool = true
	for graphic: MeshInstance3D in preview.model_node.find_children("*", "MeshInstance3D", true, false):
		if not graphic.visible: continue
		for corner in range(8):
			var point: Vector3 = inverse * (graphic.global_transform * graphic.mesh.get_aabb().get_endpoint(corner))
			if absf(point.x) > width * 0.48 or absf(point.y) > height * 0.48 or -point.z < preview.camera.near or -point.z > preview.camera.far:
				fits = false
				break
	expect(fits, "%s team%d view%d at %s: camera clips a rendered model part" % [id, team, step, str(preview.viewport.size)])
	expect(preview.get_model_bounds().size.length() > 0.1, id + ": live mesh bounds missing")


func check_interaction_and_lifecycle(preview: WikiModelPreview, panel: Control, spec: Dictionary) -> void:
	preview.size = Vector2(640, 400)
	preview.set_entry(spec, "unit", 0)
	preview.set_rotation_active(true)
	preview._process(1.0)
	expect(absf(preview.angle - preview.rotation_speed) < 0.001, "Automatic preview must rotate slowly around Y")
	expect(is_zero_approx(preview.rotation_pivot.rotation.x) and is_zero_approx(preview.rotation_pivot.rotation.z), "Automatic turntable must retain the card's upright axes")
	preview.toggle_rotation()
	var paused_angle: float = preview.angle
	preview._process(1.0)
	expect(is_equal_approx(preview.angle, paused_angle) and not preview.is_processing(), "Pause button must stop rotation")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(100, 100)
	preview._gui_input(click)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(120, 100)
	motion.relative = Vector2(20, 0)
	preview._gui_input(motion)
	expect(preview.angle > paused_angle, "Dragging the preview must rotate the model")
	var inside_angle: float = preview.angle
	motion.position = Vector2(-10, 100)
	preview._gui_input(motion)
	expect(is_equal_approx(preview.angle, inside_angle) and not preview._dragging, "Preview drag must stop when pointer leaves its bounds")
	preview.set_preview_team(1)
	expect(preview.preview_team == 1 and is_equal_approx(preview.angle, inside_angle), "Changing player color must preserve the current view")
	check_paper(preview, spec, "team switch", 1)
	click.double_click = true
	preview._gui_input(click)
	expect(is_zero_approx(preview.angle), "Double click must restore the initial pose")
	preview.set_rotation_active(true)
	panel.hide()
	preview._process(1.0)
	expect(not preview.is_processing() and preview.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and is_zero_approx(preview.angle), "Hiding ancestor panel must stop rendering and rotation")
	panel.show()
	expect(preview.is_processing() and preview.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "Reopening panel must resume active preview")
	preview.set_preview_active(false)
	preview._process(1.0)
	expect(not preview.is_processing() and preview.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and is_zero_approx(preview.angle), "Closing preview must stop rendering and rotation")
	preview.set_preview_active(true)
	expect(preview.is_processing() and preview.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "Activating preview must restore render state")
	preview.set_rotation_active(false)
