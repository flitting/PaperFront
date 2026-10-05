extends SceneTree

## Independently compare picker CPU skinning against Godot's rendered pose.
## Display-dependent; run separately from the headless regression suite.
const PICK = preload("res://scripts/entity_picking.gd")
var failures: Array[String] = []
var checks: int = 0
var errors: Array[float] = []

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func run() -> void:
	check(DisplayServer.get_name() != "headless", "real rendering server for independent GPU pose snapshot")
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(8, 10, 14)
	camera.look_at(Vector3(0, 2, 0))
	var model: Dictionary = VolumeModels.create_model(RulesLoader.load_rules().units.sky_creator_hand, "unit", 0)
	root.add_child(model.root)
	var skin: MeshInstance3D = model.skinned_mesh
	var cache: Dictionary = {}
	for pose: Dictionary in [
		{"id":1,"state":"idle"},
		{"id":1,"state":"move"},
		{"id":1,"state":"attack","hand_strike":.1,"hand_landing":Vector2(4, 1),"hand_contact_height":.6},
		{"id":1,"state":"attack","hand_recover":.2,"hand_landing":Vector2(4, 1),"hand_contact_height":1.1,"hand_ground_height":0.0},
	]:
		VolumeModels.update_model(model, pose, .19)
		for frame: int in 3: await process_frame
		await RenderingServer.frame_post_draw
		var gpu: ArrayMesh = skin.bake_mesh_from_current_skeleton_pose()
		var cpu: Dictionary = PICK._skinned_surface(skin, model, cache)
		check(gpu != null and gpu.get_surface_count() == cpu.get("surfaces", []).size(), "rendered and pickable skin have identical material surfaces")
		var maximum: float = 0.0
		for surface: int in gpu.get_surface_count():
			var rendered: PackedVector3Array = gpu.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			var picked: PackedVector3Array = cpu.surfaces[surface].vertices
			check(rendered.size() == picked.size(), "CPU and GPU preserve source vertex correspondence")
			for vertex: int in rendered.size(): maximum = maxf(maximum, rendered[vertex].distance_to(picked[vertex]))
		errors.append(maximum)
		check(maximum < .002, "CPU picking matches rendered bone deformation within2mm")
	model.root.free()
	camera.free()
	await process_frame
	print("CREATOR_HAND_SKINNING_GPU ", JSON.stringify({"checks":checks,"failures":failures,"max_vertex_errors":errors}))
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
