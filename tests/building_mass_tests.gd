extends SceneTree

const Probe = preload("res://tools/check_faction_buildings.gd")
const Models = preload("res://scripts/volume_models.gd")
var failures: Array[String] = []
var checks: int = 0

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	# Verify the measurement can distinguish a skeleton from a filled building
	# at identical bounds, and cannot be inflated by double-counting overlaps.
	var filled = Models.CraftMesh.new()
	filled.box(Vector3(0, 1.35, 0), Vector3(3.6, 2.0, 3.6), Color.WHITE, false)
	var filled_measure: Dictionary = Probe.measure_vertices(filled.vertices, 4.0)
	expect(absf(filled_measure.mass_volume_above_plinth - 25.92) < .8, "Filled solid volume should match analytic box within grid sampling tolerance")
	expect(filled_measure.mass_coverage > .78, "Filled building should occupy most of its actual rule footprint")
	var overlapped = Models.CraftMesh.new()
	overlapped.box(Vector3(0, 1.35, 0), Vector3(3.6, 2.0, 3.6), Color.WHITE, false)
	overlapped.box(Vector3(0, 1.35, 0), Vector3(2.0, 1.5, 2.0), Color.WHITE, false)
	var overlap_measure: Dictionary = Probe.measure_vertices(overlapped.vertices, 4.0)
	expect(absf(overlap_measure.mass_volume_above_plinth - filled_measure.mass_volume_above_plinth) < .01, "Nested solid must count once in the union")
	var skeleton = Models.CraftMesh.new()
	for x: float in [-1.7, 1.7]:
		for z: float in [-1.7, 1.7]:
			skeleton.box(Vector3(x, 1.35, z), Vector3(.2, 2.0, .2), Color.WHITE, false)
	skeleton.box(Vector3(0, 2.25, 0), Vector3(3.6, .2, .2), Color.WHITE, false)
	skeleton.box(Vector3(0, .1, 0), Vector3(3.9, .2, 3.9), Color.WHITE, false)
	var skeleton_measure: Dictionary = Probe.measure_vertices(skeleton.vertices, 4.0)
	expect(skeleton_measure.centered_extent[0] > 3.8, "Fixture should have deceptively wide base bounds")
	expect(skeleton_measure.mass_coverage < .08 and skeleton_measure.mass_volume_above_plinth < .6, "Frame and broad plinth must fail meaningful mass requirements")
	var huge_plinth = Models.CraftMesh.new()
	huge_plinth.box(Vector3(0, .10, 0), Vector3(3.9, .20, 3.9), Color.WHITE, false)
	var plinth_measure: Dictionary = Probe.measure_vertices(huge_plinth.vertices, 4.0)
	expect(plinth_measure.mass_volume_above_plinth == 0.0 and plinth_measure.mass_coverage == 0.0, "A broad bottom board must contribute no house mass")
	var displaced = Models.CraftMesh.new()
	displaced.box(Vector3(1.0, 1.35, 0), Vector3(3.6, 2.0, 3.6), Color.WHITE, false)
	var displaced_measure: Dictionary = Probe.measure_vertices(displaced.vertices, 4.0)
	expect(displaced_measure.actual_aabb[0] < 4.0 and displaced_measure.centered_extent[0] > 4.0, "A translated body must be rejected even when its raw AABB width fits the rule")
	print("building_mass_tests: %d checks, %d failures" % [checks, failures.size()])
	for message in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)
