extends SceneTree

## Presentation fixtures validate tutorial directions against real HUD controls.
## The paid campaign playthrough remains campaign_real_commands_tests.gd.
const Sim = preload("res://tests/rule_test_simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
const HUD = preload("res://scripts/paper_hud.gd")
const Mission = preload("res://scripts/campaign_controller.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition: failures.append(description)

func entity_id(sim, spec: String) -> int:
	for entity: Dictionary in sim.entities.values():
		if int(entity.team) == 0 and str(entity.spec) == spec: return int(entity.id)
	return -1

func run() -> void:
	root.size = Vector2i(1100, 700)
	var sim = Sim.new()
	sim.setup(Rules.load_rules(), "campaign", 1, "kestrel", true)
	sim.ai_enabled = false
	var hud = HUD.new()
	root.add_child(hud)
	# No battlefield camera is under test. A standalone HUD cannot project the
	# main scene's camera footprint, so leave this optional reference unset.
	var camera: Camera3D = null
	await process_frame
	hud.show_entry(false)
	hud.show_menu(false)
	var actions: Array[Dictionary] = []
	hud.action.connect(func(kind: String, value: Variant): actions.append({"kind":kind,"value":value}))
	var hq: int = entity_id(sim, "kestrel_hq")
	var engineer: int = entity_id(sim, "kestrel_engineer")
	var carrier: int = entity_id(sim, "kestrel_scout")
	check(hq > 0 and engineer > 0 and carrier > 0, "tutorial has its actual headquarters, engineer and scout")
	if hq < 1 or engineer < 1 or carrier < 1:
		await finish(hud)
		return
	hud.refresh(sim, [], camera, false, "", 0)
	check(not hud.production_panel.visible and hud.campaign_ui.hint_label.text.contains("先选中总部"), "first hint directs selection while the initial construction bar is hidden")
	hud.refresh(sim, [hq], camera, false, "", 0)
	check(hud.production_panel.visible and hud.entry_widgets.has("kestrel_power"), "following first hint reveals the actual power card")
	if hud.entry_widgets.has("kestrel_power"):
		hud.entry_widgets.kestrel_power.button.pressed.emit()
		check(actions.back().kind == "build" and str(actions.back().value.get("spec", "")) == "kestrel_power", "power card emits the real construction action")
	# A completed power station is an explicit display fixture for stage four.
	sim._spawn(0, "kestrel_power", Vector2(57, 165), true)
	sim.campaign_controller.stage = 4
	hud.refresh(sim, [engineer], camera, false, "", 0)
	check(not hud.production_panel.visible and hud.deploy_outpost_button.visible and not hud.deploy_outpost_button.disabled, "engineer offers an enabled independent outpost action while its bottom bar is hidden")
	check(hud.campaign_ui.hint_label.text.contains("右侧「" + hud.deploy_outpost_button.text + "」"), "outpost hint names the visible engineer button exactly")
	hud.deploy_outpost_button.pressed.emit()
	check(actions.back().kind == "build" and str(actions.back().value.get("spec", "")) == "kestrel_outpost", "named engineer button emits the real outpost construction action")
	# Board a nearby rifle through the normal transport command before inspecting
	# the real loaded-scout controls; this does not complete the whole mission.
	sim.campaign_controller.stage = 5
	var passenger: int = sim._spawn(0, "kestrel_rifle", sim.entities[carrier].pos + Vector2(1.25, 0), true)
	sim.issue([passenger], "board", sim.entities[carrier].pos, carrier)
	for tick: int in range(60):
		if int(sim.entities[passenger].get("transport_id", -1)) == carrier: break
		sim.step(1.0 / 30.0)
	check(int(sim.entities[passenger].get("transport_id", -1)) == carrier, "tutorial scout actually boards a rifle before unload controls are checked")
	hud.refresh(sim, [carrier], camera, false, "", 0)
	check(hud.unload_move_button.visible and hud.unload_move_button.text.contains("U") and hud.campaign_ui.hint_label.text.contains("按 U"), "transport hint matches the visible destination-unload shortcut")
	hud.unload_move_button.pressed.emit()
	check(actions.back().kind == "unload_move", "visible destination-unload button emits the real command mode")
	for stage: int in range(Mission.STAGE_COUNT):
		sim.campaign_controller.stage = stage
		hud.refresh(sim, [], camera, false, "", 0)
		await process_frame
		check(hud.campaign_ui.hint_label.text == str(Mission.OBJECTIVES[stage].hint), "all tutorial phases show their current canonical hint: " + str(stage))
		check(hud.campaign_ui.panel.get_global_rect().encloses(hud.campaign_ui.target_button.get_global_rect()), "all tutorial phases keep the target action inside its panel: " + str(stage))
		check(not hud.campaign_ui.panel.get_global_rect().intersects(hud.minimap_panel.get_global_rect()), "all tutorial phases clear the minimap: " + str(stage))
	await finish(hud)

func finish(hud) -> void:
	print("DEMO_CAMPAIGN_HINTS ", JSON.stringify({"checks":checks,"failures":failures,"full_playthrough":false}))
	for failure: String in failures: push_error(failure)
	hud.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
