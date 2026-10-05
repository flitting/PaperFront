extends SceneTree

const HUD = preload("res://scripts/paper_hud.gd")
const Mission = preload("res://scripts/campaign_controller.gd")
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1100, 700)
	var hud = HUD.new()
	root.add_child(hud)
	await process_frame
	var events: Array = []
	hud.action.connect(func(kind, value): events.append({"kind":kind,"value":value}))
	check(hud.entry_menu.campaign_button != null and hud.entry_menu.campaign_button.text.contains("战役"), "entry shows real campaign button")
	hud.show_entry(true)
	await process_frame
	var deck_rect: Rect2 = hud.entry_menu.get_child(2).get_global_rect()
	check(deck_rect.encloses(hud.entry_menu.campaign_button.get_global_rect()), "campaign entry remains inside menu card at 1100 width")
	hud.entry_menu.campaign_button.pressed.emit()
	check(events.size() == 1 and events[0].kind == "entry_campaign", "campaign button starts dedicated route")
	var view := {"active":true,"stage":2,"total":7,"objective":"组建先遣队",
		"body":"训练步兵与工程兵。","hint":"去桥西岸。","progress":"步兵 ✓ · 工程兵 ○",
		"marker":Vector2(147.5,160.5),"finished":false}
	hud.campaign_ui.display(view)
	await process_frame
	check(hud.campaign_ui.panel.visible, "objective panel appears")
	check(hud.campaign_ui.objective_label.text == "组建先遣队", "current objective displayed")
	check(hud.campaign_ui.marker.active, "minimap target marker appears")
	check(not hud.campaign_ui.panel.get_global_rect().intersects(hud.production_panel.get_global_rect()), "mission panel clears production catalog at 1100 width")
	check(not hud.campaign_ui.panel.get_global_rect().intersects(hud.minimap_panel.get_global_rect()), "mission panel clears minimap at 1100 width")
	hud.campaign_ui.target_button.pressed.emit()
	check(events.size() == 2 and events[1].kind == "campaign_target" and events[1].value == view.marker, "target button moves camera to objective")
	for stage: int in [0, 4, 5]:
		var objective: Dictionary = Mission.OBJECTIVES[stage]
		var tutorial_view: Dictionary = {"active":true,"stage":stage,"total":7,"objective":objective.title,
			"body":objective.body,"hint":objective.hint,"progress":"","marker":objective.marker,"finished":false}
		hud.campaign_ui.display(tutorial_view)
		await process_frame
		check(hud.campaign_ui.hint_label.text == str(objective.hint), "current tutorial hint reaches objective panel: " + str(stage))
		check(hud.campaign_ui.panel.get_global_rect().encloses(hud.campaign_ui.target_button.get_global_rect()), "tutorial hint keeps target action within its panel: " + str(stage))
	check(str(Mission.OBJECTIVES[0].hint).contains("先选中总部"), "first objective explains how to reveal construction cards")
	check(str(Mission.OBJECTIVES[4].hint).contains("右侧「部署分基地」") and not str(Mission.OBJECTIVES[4].hint).contains("建筑目录"), "outpost objective describes the independent engineer action")
	check(str(Mission.OBJECTIVES[5].hint).contains("按 U") and not str(Mission.OBJECTIVES[5].hint).contains("卸载到此处"), "transport objective names the actual unload shortcut")
	hud.campaign_ui.display({})
	check(not hud.campaign_ui.panel.visible and not hud.campaign_ui.marker.active, "ordinary matches hide campaign chrome")
	print("CAMPAIGN_UI ",JSON.stringify({"checks":checks,"failures":failures}))
	for failure: String in failures: push_error(failure)
	hud.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
