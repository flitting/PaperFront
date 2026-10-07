extends SceneTree

const Score = preload("res://scripts/match_scoreboard.gd")
const Chart = preload("res://scripts/match_history_chart.gd")
var checks := 0
var failures: Array[String] = []
var capture_dir := "res://artifacts/balance_preparation_20261007/settlement"

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func frames(count: int = 3) -> void:
	for frame: int in range(count): await process_frame

func fixture() -> Dictionary:
	var players: Array = []
	for owner: int in range(2):
		players.append({"team":owner, "faction":"sky" if owner == 0 else "iron", "money_remaining":1800, "funds_earned":7200, "funds_spent":6400, "units_killed":17, "units_lost":9, "buildings_built":12, "buildings_destroyed":5, "units_produced":29, "alive_units":20, "alive_buildings":10, "building_total":15, "structures_complete":11, "infantry_total":12, "army_value":12000, "building_value":16400, "damage_dealt":15500})
	var history: Array = []
	for second: int in range(181):
		var rows: Array = []
		for owner: int in range(2):
			var progress: float = float(second) / 180.0
			rows.append({"team":owner, "money_remaining":maxf(0.0, 5000.0 - second * (15.0 + owner * 2.0) + sin(second * 0.17 + owner) * 350.0), "funds_earned":second * (44.0 - owner * 6.0), "funds_spent":second * (41.0 - owner * 5.0), "building_total":2 + int(second / 16) - maxi(0, int((second - 130) / (25 - owner * 5))), "infantry_total":maxi(0, int(second / 5) - maxi(0, int((second - 80) / 3)) * (owner + 1)), "alive_units":int(second / 4), "army_value":progress * (16000.0 - owner * 4000), "damage_dealt":progress * progress * (22000.0 - owner * 8000.0)})
		history.append({"time":float(second), "teams":rows})
	return {"duration":180.0, "map_mode":"symmetric", "teams":players, "history":history, "history_complete":true, "telemetry_history_complete":true, "history_interval_seconds":1.0, "history_since_time":0.0, "metadata":{"match_options":{"slots":[{"color":"6498df"},{"color":"bc2941"}]}}}

func capture(score: Control, name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await frames()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(capture_dir)
	check(root.get_texture().get_image().save_png(capture_dir.path_join(name + ".png")) == OK, "screenshot " + name)

func run() -> void:
	var score = Score.new()
	var paper := Theme.new()
	var font := FontVariation.new()
	font.base_font = load("res://assets/fonts/NotoSansCJK-Regular.ttc")
	font.variation_face_index = 2
	paper.default_font = font
	score.theme = paper
	root.add_child(score)
	await frames()
	var stats := fixture()
	var original: Dictionary = stats.duplicate(true)
	var actions: Array = []
	score.action.connect(func(kind, value): actions.append({"kind":kind,"value":value}))
	var original_windows: int = root.find_children("", "Window", true, false).size()
	for dimensions: Vector2i in [Vector2i(1100,700),Vector2i(1440,810),Vector2i(1920,1080)]:
		root.size = dimensions
		score.show_result(stats, "win")
		await frames(5)
		check(score.history_charts.size() == 4, "three core series and extra analysis chart exist")
		check(score.content_scroll.get_global_rect().size.x >= score.history_charts[0].get_global_rect().size.x, "charts fit content width at " + str(dimensions))
		check(root.get_visible_rect().encloses(score.export_button.get_global_rect()), "export action stays visible at " + str(dimensions))
		check(root.find_children("", "Window", true, false).size() == original_windows, "curves create no popup windows")
		check(score.displayed_stats == original and stats == original, "chart preparation is read-only")
		check(score.history_charts[0].series[0].color.is_equal_approx(Color("6498df").darkened(0.30)), "legend uses configured owner colors")
		await capture(score, "funds_%d" % dimensions.x)
	var funds: Control = score.history_charts[0]
	check(funds.sample_times.size() == 181 and funds.sample_times[0] == 0.0 and funds.sample_times.back() == 180.0, "funds curve covers recorded start to finish")
	check(is_equal_approx(funds.series[0].values[92], stats.history[92].teams[0].money_remaining), "funds curve reads exact sampled owner value")
	check(score.history_charts[1].metric == "building_total" and score.history_charts[1].series[1].values[100] == stats.history[100].teams[1].building_total, "building curve uses total construction and rails field")
	check(score.history_charts[2].metric == "infantry_total" and score.history_charts[2].series[1].values[100] == stats.history[100].teams[1].infantry_total, "infantry curve excludes other unit classes")
	var motion := InputEventMouseMotion.new()
	motion.position = funds.point_for(92, funds.value_max * 0.5)
	funds._gui_input(motion)
	check(funds.hovered_sample == 92, "curve inspection selects actual nearest simulation sample")
	score.extra_metric_tabs.current_tab = 3
	check(score.extra_chart.metric == "army_value" and score.extra_chart.series[0].values[100] == stats.history[100].teams[0].army_value, "extra metric tabs use authoritative asset values")
	score.content_scroll.scroll_vertical = int(score.history_charts[1].position.y)
	await frames()
	# Scrolling uses the chart's enclosing card position within the report body.
	score.content_scroll.scroll_vertical = int(score.history_charts[1].get_parent().get_parent().position.y)
	await capture(score,"buildings_infantry_1920")
	score.content_scroll.scroll_vertical = int(score.extra_chart.get_parent().get_parent().position.y)
	await capture(score,"analysis_1920")
	score.export_button.pressed.emit()
	check(score.visible and actions.back().kind == "export_statistics" and actions.back().value == null, "export keeps settlement open and emits ordinary action")
	score.show_export_status("统计已导出：match.json",true)
	check(score.export_status.text.contains("match.json"), "export path feedback is visible on settlement")
	var legacy: Dictionary = {"duration":180.0,"teams":stats.teams,"telemetry_history_complete":false,"history_complete":false}
	score.show_result(legacy,"draw")
	check(score.history_note.text.contains("没有历史采样") and not score.history_charts[0].has_recorded_values(), "legacy saves show honest missing-history state")
	var partial: Dictionary = stats.duplicate(true)
	partial.history = partial.history.slice(90)
	partial.history_since_time = 90.0
	partial.telemetry_history_complete = false
	score.show_result(partial,"lose")
	check(score.history_note.text.contains("01:30") and score.history_charts[0].start_time == 90.0, "partial-save history scope is explicit")
	var gaps: Control = Chart.new()
	root.add_child(gaps)
	gaps.configure([{"time":0.0,"teams":[{"team":0}]},{"time":0.5,"teams":[{"team":0,"infantry_total":4}]}],[{"team":0,"chart_name":"玩家 1","chart_color":Color.RED}],"infantry_total",0.5)
	check(gaps.series[0].values[0] == null and gaps.series[0].values[1] == 4, "unknown legacy values are gaps rather than fabricated zeros")
	check(is_equal_approx(gaps.point_for(1,4).x,gaps.plot_rect().end.x), "subsecond matches place final sample at actual time axis endpoint")
	check(Chart.format_time(3661) == "61:01" and Chart.format_value(12500) == "12.5k", "long matches and large values have compact readable axes")
	gaps.queue_free()
	score.queue_free()
	await frames()
	print("SETTLEMENT_HISTORY_UI ",JSON.stringify({"checks":checks,"failures":failures,"visual_fixture":"Explicit two-player sampled display fixture; no played-match claim"}))
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
