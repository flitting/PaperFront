extends SceneTree
const Fixture = preload("res://tests/rts_regression_fixture.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var fixture = Fixture.new()
	for phase in ["setup", "produce_phase", "economy_phase", "capture_phase", "combat_phase", "rail_destruction_phase", "result_phase"]:
		print("RTS_FIXED_PHASE_START ", phase)
		fixture.call(phase)
		print("RTS_FIXED_PHASE_DONE ",JSON.stringify({"phase":phase,"time":fixture.sim.time,"checks":fixture.checks,"failures":fixture.failures}))
		await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/rts_revision"))
	var file := FileAccess.open("res://artifacts/rts_revision/four_faction_regression.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(fixture.evidence,"  "))
	print("RTS_FOUR_FACTION_REGRESSION ",JSON.stringify(fixture.evidence))
	for failure in fixture.failures: push_error(failure)
	quit(0 if fixture.failures.is_empty() else 1)
