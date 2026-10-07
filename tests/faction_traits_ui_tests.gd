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
	check(hud.faction_buttons.iron.tooltip_text.contains("1.2%") and hud.faction_buttons.iron.tooltip_text.contains("扳手维修车") and not hud.faction_buttons.iron.tooltip_text.contains("减伤"), "Iron card keeps recovery and specific maintenance platforms without reduction")
	check(hud.faction_buttons.kestrel.tooltip_text.contains("校正炮") and not hud.faction_buttons.kestrel.tooltip_text.contains("同域") and not hud.faction_buttons.kestrel.tooltip_text.contains("8%"), "Canon card describes specific equipment without a faction damage bonus")
	check(hud.faction_buttons.rivet.tooltip_text.contains("基地兵营") and hud.faction_buttons.rivet.tooltip_text.contains("开局即可") and hud.faction_buttons.rivet.tooltip_text.contains("全部建筑") and hud.faction_buttons.rivet.tooltip_text.contains("1000资金"), "Hammer card explains immediate infantry production and engineering of the unified base barracks")
	check(hud.faction_buttons.rivet.tooltip_text.contains("没有分基地") and hud.faction_buttons.rivet.tooltip_text.contains("同一种建筑") and hud.spec_tooltip(config.buildings.rivet_hq).contains("100电力"), "Hammer starting and expansion base barracks share one locally powered building type")
	check(hud.faction_buttons.sky.tooltip_text.contains("步兵不受EMP") and hud.faction_buttons.sky.tooltip_text.contains("供电"), "Sky card explains EMP scope")
	check(hud.faction_buttons.sky.text.contains("断流车EMP") and hud.faction_buttons.sky.text.contains("局部蓄能"), "Sky card ties its combat mechanisms to a specific platform and local building")
	for faction in ids:
		check(hud.faction_buttons[faction].tooltip_text.contains("100电力") and hud.faction_buttons[faction].tooltip_text.contains("半径12格"), "Faction card explains headquarters local power: " + faction)
	var changed: Dictionary = config.duplicate(true)
	changed.factions.iron.traits.regen_fraction_per_second = 0.025
	changed.buildings.rivet_hq.cost = 1350
	changed.buildings.rivet_hq.build_time = 19
	changed.buildings.rivet_hq.construction_radius = 17
	changed.buildings.rivet_hq.local_power = 80
	changed.buildings.rivet_hq.local_power_radius = 9
	check("\n".join(Text.faction_lines(changed, "iron")).contains("2.5%") and "\n".join(Text.faction_lines(changed, "rivet")).contains("1350资金") and "\n".join(Text.faction_lines(changed, "rivet")).contains("施工19秒") and "\n".join(Text.faction_lines(changed, "rivet")).contains("17格建设范围") and "\n".join(Text.faction_lines(changed, "rivet")).contains("80电力") and "\n".join(Text.faction_lines(changed, "rivet")).contains("半径9格"), "Descriptions render recovery and all base barracks parameters from the active blueprint")
	var old_engineer: Dictionary = config.duplicate(true)
	old_engineer.buildings.rivet_hq.rebuildable = false
	old_engineer.buildings.rivet_barracks = config.buildings.rivet_hq.duplicate(true)
	old_engineer.buildings.rivet_barracks.role = "barracks"
	old_engineer.buildings.rivet_barracks.cost = 1400
	check("\n".join(Text.faction_lines(old_engineer, "rivet")).contains("额外大兵营") and "\n".join(Text.faction_lines(old_engineer, "rivet")).contains("1400资金") and not "\n".join(Text.faction_lines(old_engineer, "rivet")).contains("同一种建筑"), "Historical engineering snapshots retain their split headquarters and expansion barracks descriptions")
	for faction in ["iron", "kestrel", "rivet"]: changed.factions[faction].erase("traits")
	changed.weapons.sky_disruptor.erase("emp_vehicle_duration")
	check(not "\n".join(Text.faction_lines(changed, "iron")).contains("自动恢复") and Text.spec_lines(changed, changed.units.iron_tank).is_empty() and not "\n".join(Text.faction_lines(changed, "sky")).contains("失控"), "Unconfigured recovery and EMP effects are absent from detailed descriptions")
	check(not Text.menu_short(changed, "iron").contains("自愈"), "Unconfigured recovery is absent from the menu summary")
	changed.factions.rivet.erase("building_method")
	check(not Text.menu_short(changed, "rivet").contains("工兵建设") and not "\n".join(Text.faction_lines(changed, "rivet")).contains("脚手架"), "Snapshots without engineer construction do not advertise that mechanism")
	check(Text.spec_lines(config, config.units.iron_fighter).size() == 1 and Text.spec_lines(config, config.units.iron_engineer).size() == 1, "Iron traits cover aircraft and engineers")
	check(Text.spec_lines(config, config.buildings.iron_refinery).is_empty(), "Unit-only Iron recovery is absent from refinery tooltips")
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
	check(Text.spec_lines(config, config.units.rivet_fighter).is_empty() and Text.spec_lines(config, config.units.rivet_harvester).is_empty() and Text.spec_lines(config, config.units.rivet_tank).is_empty(), "Hammer units do not advertise a faction combat bonus")
	var hammer: int = sim.debug_spawn(1, "rivet_tank", Vector2(23.5, 32.5))
	sim.entities[hammer].commands = [{"kind":"attack_move", "pos":Vector2(24.5, 32.5), "target":-1}]
	sim.entities[hammer].breakthrough_progress = 3.0
	hud.selection = [hammer]
	check(not hud.selection_text().contains("突破"), "Selected Hammer unit does not expose removed breakthrough progress")
	sim.entities[hammer].breakthrough_ready_until = 24.0
	check(not hud.selection_text().contains("突破"), "Stale breakthrough readiness does not display a removed bonus")
	var canon: int = sim.debug_spawn(0, "kestrel_rifle", Vector2(8.5, 32.5))
	var ally_one: int = sim.debug_spawn(0, "kestrel_rifle", Vector2(10.5, 32.5))
	var ally_two: int = sim.debug_spawn(0, "kestrel_rifle", Vector2(12.5, 32.5))
	sim._rebuild_spatial()
	hud.selection = [canon]
	check(not hud.selection_text().contains("协同"), "Nearby Canon infantry do not display a faction damage bonus")
	sim.entities[ally_two].transport_id = 999
	sim._rebuild_spatial()
	check(not hud.selection_text().contains("协同"), "Loading nearby infantry does not display removed cohesion state")
	sim.entities[hammer].emp_until = 22.0
	hud.selection = [hammer]
	check(hud.selection_text().contains("EMP失控 2.0秒"), "Selected armored unit exposes EMP duration")
	check(hud.spec_tooltip(config.units.sky_disruptor).contains("失控2秒") and hud.spec_tooltip(config.units.sky_disruptor).contains("失控1秒"), "EMP weapon tooltip reads both source durations")
	check(row_value(Catalog.sections(config, "kestrel_fighter"), "弹药容量") == "8 发", "Wiki renders unified fighter ammunition from the current rules")
	check(row_value(Catalog.sections(config, "sky_disruptor"), "装甲单位失控时间") == "2 秒", "Wiki gives an explicit EMP duration label")
	check(row_value(Catalog.sections(config, "iron_tank"), "作战特性").contains("1.2%"), "Wiki shares the active Iron trait explanation")
	check(Catalog.entries(config, "rivet", "building").filter(func(entry): return entry.name == "基地兵营").size() == 1 and not config.buildings.has("rivet_barracks"), "Wiki contains one canonical base barracks building entry")
	check(row_value(Catalog.sections(config, "rivet_hq"), "现场施工时间") == "15 秒" and row_value(Catalog.sections(config, "rivet_hq"), "基地兵营数量").contains("可建造多座") and row_value(Catalog.sections(config, "rivet_hq"), "总部数量限制").is_empty(), "Wiki describes repeatable field construction for the unified base barracks")
	check(row_value(Catalog.sections(config, "rivet_engineer"), "生产设施") == "基地兵营", "Wiki resolves the infantry producer alias to the unified base barracks")
	check(row_value(Catalog.sections(old_engineer, "rivet_hq"), "总部数量限制").contains("最多拥有一座"), "Wiki preserves the historical headquarters cap when its blueprint is not rebuildable")
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
