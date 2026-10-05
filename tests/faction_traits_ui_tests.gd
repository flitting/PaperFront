extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
const HUD = preload("res://scripts/paper_hud.gd")
const Catalog = preload("res://scripts/wiki_catalog.gd")
const Text = preload("res://scripts/faction_trait_text.gd")
var failures: Array[String] = []
var checks: int = 0
var hud: PaperHUD
var sim

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func row_value(sections: Array[Dictionary], label: String) -> String:
	for section in sections:
		for row in section.rows:
			if row.label == label: return str(row.value)
	return ""

func run() -> void:
	var config: Dictionary = Rules.load_rules("res://data/rules.json", false)
	check(not config.is_empty(), "Current rules validate before UI probes")
	if config.is_empty():
		quit(1)
		return
	sim = Sim.new()
	var ids: Array[String] = ["kestrel", "rivet", "iron", "sky"]
	var starts: Array[Vector2] = [Vector2(5.5, 42.5), Vector2(17.5, 42.5), Vector2(29.5, 42.5), Vector2(41.5, 42.5)]
	sim.setup_multiteam(config, "dev", 73026, ids, false, starts)
	hud = HUD.new()
	root.add_child(hud)
	await process_frame
	hud.sim = sim
	check(hud.channel_status_buttons.size() == 2, "Dual construction channels remain present")
	check(hud.unload_move_button.text.contains("U") and hud.land_button.text.contains("L"), "U selects unloading destination and L selects aircraft landing")
	check(hud.transport_menu.item_count == 2 and hud.transport_menu.get_item_text(0).contains("装载") and hud.transport_menu.get_item_text(1).contains("卸载"), "Separate load and unload actions remain present")
	for faction in ids:
		var summary: String = Text.menu_short(config, faction)
		check(hud.faction_buttons[faction].text.contains(summary), "Faction choice reads the shared specialty: " + faction)
		check(hud.faction_buttons[faction].tooltip_text == "\n".join(Text.faction_lines(config, faction)), "Faction choice reads the shared rules explanation: " + faction)
	check(hud.faction_buttons.iron.tooltip_text.contains("10%") and hud.faction_buttons.iron.tooltip_text.contains("1.2%"), "Iron card explains reduction and maximum-HP recovery")
	check(hud.faction_buttons.kestrel.tooltip_text.contains("2个其他同域") and hud.faction_buttons.kestrel.tooltip_text.contains("8%"), "Canon card explains the actual ally condition")
	check(hud.faction_buttons.rivet.tooltip_text.contains("攻击移动") and hud.faction_buttons.rivet.tooltip_text.contains("4秒"), "Hammer card explains breakthrough trigger and duration")
	check(hud.faction_buttons.sky.tooltip_text.contains("步兵不受EMP") and hud.faction_buttons.sky.tooltip_text.contains("供电"), "Sky card explains EMP scope")
	var changed: Dictionary = config.duplicate(true)
	changed.factions.iron.traits.damage_reduction = 0.25
	check(Text.menu_short(changed, "iron").contains("25%"), "Descriptions render changed rule values instead of baking current numbers")
	for faction in ["iron", "kestrel", "rivet"]: changed.factions[faction].erase("traits")
	changed.weapons.sky_disruptor.erase("emp_vehicle_duration")
	check(Text.faction_lines(changed, "iron").is_empty() and Text.faction_lines(changed, "sky").is_empty(), "Historical snapshots do not advertise unconfigured traits")
	check(Text.spec_lines(config, config.units.iron_fighter).size() == 1 and Text.spec_lines(config, config.units.iron_engineer).size() == 1, "Iron traits cover aircraft and engineers")
	check(Text.spec_lines(config, config.buildings.iron_refinery).is_empty(), "Unit-only Iron reduction is absent from refinery tooltips")
	var tank: int = sim.debug_spawn(2, "iron_tank", Vector2(30.5, 32.5))
	sim.time = 20.0
	sim.entities[tank].hp -= 100.0
	sim.entities[tank].last_damage_time = 19.0
	hud.selection = [tank]
	check(hud.selection_text().contains("自愈等待5.0秒"), "Selected Iron unit shows the damage-based recovery timer")
	sim.entities[tank].last_damage_time = 14.0
	check(hud.selection_text().contains("脱战自愈"), "Selected Iron unit shows active automatic recovery")
	sim.entities[tank].last_attack_time = 18.0
	check(hud.selection_text().contains("自愈等待4.0秒"), "Iron recovery timer also restarts after firing")
	check(Text.spec_lines(config, config.units.rivet_fighter).is_empty() and Text.spec_lines(config, config.units.rivet_harvester).is_empty(), "Hammer aircraft and unarmed vehicles do not advertise breakthrough")
	var hammer: int = sim.debug_spawn(1, "rivet_tank", Vector2(23.5, 32.5))
	sim.entities[hammer].commands = [{"kind":"attack_move", "pos":Vector2(24.5, 32.5), "target":-1}]
	sim.entities[hammer].breakthrough_progress = 3.0
	hud.selection = [hammer]
	check(hud.selection_text().contains("突破推进3.0/5米"), "Selected Hammer unit shows real distance progress")
	sim.entities[hammer].breakthrough_ready_until = 24.0
	check(hud.selection_text().contains("突破 +20% · 4.0秒"), "Selected Hammer unit shows one-shot bonus and expiration")
	var canon: int = sim.debug_spawn(0, "kestrel_rifle", Vector2(8.5, 32.5))
	var ally_one: int = sim.debug_spawn(0, "kestrel_rifle", Vector2(10.5, 32.5))
	var ally_two: int = sim.debug_spawn(0, "kestrel_rifle", Vector2(12.5, 32.5))
	sim._rebuild_spatial()
	hud.selection = [canon]
	check(hud.selection_text().contains("协同 +8%伤害"), "Selected Canon unit uses the authoritative cohesion check")
	sim.entities[ally_two].transport_id = 999
	sim._rebuild_spatial()
	check(hud.selection_text().contains("协同待集结"), "Loaded nearby infantry does not activate cohesion")
	sim.entities[hammer].emp_until = 22.0
	hud.selection = [hammer]
	check(hud.selection_text().contains("EMP失控 2.0秒"), "Selected armored unit exposes EMP duration")
	check(hud.spec_tooltip(config.units.sky_disruptor).contains("失控2秒") and hud.spec_tooltip(config.units.sky_disruptor).contains("失控1秒"), "EMP weapon tooltip reads both source durations")
	check(row_value(Catalog.sections(config, "kestrel_fighter"), "弹药容量") == "8 发", "Wiki renders unified fighter ammunition from the current rules")
	check(row_value(Catalog.sections(config, "sky_disruptor"), "装甲单位失控时间") == "2 秒", "Wiki gives an explicit EMP duration label")
	check(row_value(Catalog.sections(config, "iron_tank"), "作战特性").contains("1.2%"), "Wiki shares the active Iron trait explanation")
	check(Catalog.entries(config, "", "unit", "EMP").size() > 0, "EMP ability text is searchable in the catalog")
	for faction in ids:
		check(hud.spec_tooltip(config.units[faction + "_harvester"]).contains("生命 %d" % int(config.units[faction + "_harvester"].hp)), "Harvester card reads source HP: " + faction)
	var help: Label = hud.help_panel.find_child("HelpBody", true, false)
	check(help.text.contains("U 指定卸载地点") and help.text.contains("L：运输机指定降落地点") and not help.text.contains("U 当前卸载") and not help.text.contains("L 指定登陆海岸"), "Help consistently teaches destination unloading and aircraft landing")
	hud.queue_free()
	await process_frame
	sim = null
	print("Faction traits UI checks: ", checks - failures.size(), " passed, ", failures.size(), " failed")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
