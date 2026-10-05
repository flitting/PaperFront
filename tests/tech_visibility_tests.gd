extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
var failures: Array[String] = []
var checks: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var sim = Sim.new()
	sim.setup(Rules.load_rules(), "dev", 7, "rivet", false)
	var hud := PaperHUD.new()
	root.add_child(hud)
	await process_frame
	hud.show_menu(false)
	var hq: int = sim.entities.values().filter(func(e): return int(e.team) == 0 and sim.data_for(e.spec).get("role", "") == "hq")[0].id
	hud.refresh(sim, [], null, false, "", 0.0)
	check(not hud.production_panel.visible and hud.entry_widgets.is_empty(), "no selection hides the construction panel and its global catalog")
	hud.refresh(sim, [hq], null, false, "", 0.0)
	check(hud.production_panel.visible and hud.entry_widgets.has("rivet_power") and not hud.entry_widgets.has("rivet_tech"), "headquarters only shows unlocked building cards")
	check(not hud.entry_widgets.has("rivet_hq") and not hud.entry_widgets.has("rivet_outpost"), "headquarters rebuilding and engineer-only deployment are absent from headquarters catalog")
	check(hud.category_buttons.build.visible and hud.category_buttons.defense.visible and not hud.category_buttons.vehicle.visible, "headquarters only offers its two construction channels")
	hud.select_catalog("defense")
	check(hud.entry_widgets.has("rivet_wall") and not hud.entry_widgets.has("rivet_tower"), "locked defenses are hidden rather than gray")
	var power: int = sim.debug_spawn(0, "rivet_power", Vector2(28.5, 42.5))
	hud.refresh(sim, [hq], null, false, "", 0.0)
	hud.select_catalog("build")
	check(hud.entry_widgets.has("rivet_barracks") and hud.entry_widgets.has("rivet_refinery"), "completed prerequisite unlocks building cards during refresh")
	sim.money[0] = 0.0
	hud.refresh(sim, [hq], null, false, "", 0.0)
	check(hud.entry_widgets.has("rivet_power") and hud.entry_widgets.rivet_power.button.disabled and hud.entry_widgets.rivet_power.price_label.text.contains("$600"), "temporary funds shortage preserves unlocked card and its price")
	var engineer: int = sim.debug_spawn(0, "rivet_engineer", Vector2(32.5, 42.5))
	hud.refresh(sim, [engineer], null, false, "", 0.0)
	check(not hud.production_panel.visible and hud.entry_widgets.is_empty() and hud.deploy_outpost_button.visible, "engineer has a separate deployment action while the construction bar stays hidden")
	check(sim.build(0, "rivet_outpost", engineer).is_empty(), "separate engineer deployment creates its normal choosing-site order")
	hud.refresh(sim, [engineer], null, false, "", 0.0)
	check(hud.deploy_outpost_button.visible and not hud.deploy_outpost_button.disabled and hud.cancel_deployment_button.visible and not hud.production_panel.visible, "engineer can reopen or cancel a ready deployment without a global construction bar")
	sim.cancel_build(0, "normal")
	hud.refresh(sim, [power], null, false, "", 0.0)
	check(not hud.production_panel.visible and not hud.deploy_outpost_button.visible, "non-production building hides construction and engineer actions")
	var factory: int = sim.debug_spawn(0, "rivet_factory", Vector2(14.5, 42.5))
	hud.refresh(sim, [factory], null, false, "", 0.0)
	check(hud.production_panel.visible and hud.tab == "vehicle" and not hud.entry_widgets.has("rivet_assault"), "selected factory only offers its unlocked vehicle production")
	check(sim.availability(0, "rivet_assault", -1, factory).contains("科技"), "purchase validation reports missing technology")
	var tech: int = sim.debug_spawn(0, "rivet_tech", Vector2(18.5, 42.5))
	sim.money[0] = 10000.0
	hud.refresh(sim, [factory], null, false, "", 0.0)
	check(hud.entry_widgets.has("rivet_assault") and not hud.entry_widgets.rivet_assault.button.disabled and hud.production_building("rivet_assault") == factory, "technology unlocks production at the selected factory")
	sim.entities[tech].construct_remaining = 5.0
	hud.refresh(sim, [factory], null, false, "", 0.0)
	check(not hud.entry_widgets.has("rivet_assault"), "unfinished prerequisite removes advanced cards even when building count is unchanged")
	sim.entities[tech].construct_remaining = 0.0
	hud.refresh(sim, [], null, false, "", 0.0)
	check(not hud.production_panel.visible and hud.production_building("rivet_assault") < 0, "clearing selection prevents automatic routing to another facility")
	var field: int = sim.debug_spawn(0, "rivet_airfield", Vector2(25.5, 36.5))
	var capacity: int = int(sim.data_for("rivet_airfield").aircraft_capacity)
	for i in range(capacity):
		sim.entities[field].queue.append({"spec": "rivet_fighter", "remaining": 10.0, "total": 10.0, "cost": 100.0, "started": false, "ready": false, "progress": 0.0})
	hud.refresh(sim, [field], null, false, "", 0.0)
	check(hud.tab == "air" and hud.production_building() == field and hud.unit_cancel_button.visible and hud.queue_buttons.visible, "selected full airport retains its queue and cancel controls")
	check(sim.cancel_production(field, 0).is_empty() and sim._airfield_load(field) < capacity and hud.production_building("rivet_fighter") == field, "canceling a selected airport queue releases a production slot")
	sim.entities[field].construct_remaining = 3.0
	hud.refresh(sim, [field], null, false, "", 0.0)
	check(not hud.production_panel.visible, "unfinished production facility offers no production bar")
	root.remove_child(hud)
	hud.queue_free()
	print("Tech visibility checks: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	for failure in failures: push_error(failure)
	quit(1 if not failures.is_empty() else 0)
