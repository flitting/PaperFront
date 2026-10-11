extends SceneTree
const HUD = preload("res://scripts/paper_hud.gd")
const SIM = preload("res://scripts/simulation.gd")
const RULES = preload("res://scripts/rules_loader.gd")
const CATALOG = preload("res://scripts/wiki_catalog.gd")
var checks: int = 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func rows_text(rules: Dictionary, id: String) -> String:
	var lines: PackedStringArray = []
	for section: Dictionary in CATALOG.sections(rules, id):
		for row: Dictionary in section.rows: lines.append(str(row.label) + " " + str(row.value))
	return "\n".join(lines)
func run() -> void:
	var rules: Dictionary = RULES.load_rules("res://data/rules.json", false)
	check(not rules.is_empty(), "HUD consumes real validated naval rules: " + str(RULES.errors))
	if rules.is_empty(): quit(1); return
	var hud = HUD.new()
	root.add_child(hud)
	await process_frame
	hud.show_menu(false)
	var sim = SIM.new()
	sim.setup_multiteam(rules, "forest", 7, ["iron", "sky", "rivet"], false)
	sim.money[0] = 100000
	hud.refresh(sim, [], null, true, "", 0)
	hud.mini.make_texture()
	check(not hud.mini._cliff_edges.is_empty(), "authored forest mountain walls retain their actual cliff ink")
	# The authored forest now has real mountain walls. Isolate a level beach
	# instead of assuming its entire map is flat: water height stores +2.65,
	# while its rendered surface is exactly level with the adjacent land.
	var authored_map: Dictionary = sim.map
	sim.map = {"size":2,"terrain":[[0,1],[0,1]],"heights":[[0.0,2.65],[0.0,2.65]],"profile":{}}
	hud.mini._cache_cliff_edges(2)
	check(hud.mini._cliff_edges.is_empty(), "level beach compares actual water surface and stays free of false cliff ink")
	sim.map.heights = [[2.0,2.65],[2.0,2.65]]
	hud.mini._cache_cliff_edges(2)
	check(not hud.mini._cliff_edges.is_empty(), "actual steep coast retains cliff ink above the water surface")
	sim.map = authored_map
	hud.mini.make_texture()
	check(hud.category_buttons.size() == 6 and hud.category_buttons.has("naval"), "all production categories are registered, including navy")
	check(hud.channel_status_buttons.size() == 2, "both independent construction channels remain registered")
	for faction: String in rules.factions:
		sim.factions[0] = faction
		sim._spawn(0, faction + "_tech", Vector2(110, 90), true)
		var faction_yard: int = sim._spawn(0, faction + "_shipyard", sim.map.harbors[0].water_pos, true)
		hud.refresh(sim, [faction_yard], null, true, "", 0)
		hud.select_catalog("naval")
		var expected_ships: Array[String] = []
		var transport_spec: String = ""
		for id: String in rules.units:
			var info: Dictionary = rules.units[id]
			if str(info.faction) != faction or str(info.get("producer","")) not in ["shipyard","amphibious"] or bool(info.get("roster_hidden",false)) or bool(info.get("internal_only",false)): continue
			if not sim._requirements(0,info).is_empty(): continue
			expected_ships.append(id)
			if int(info.get("transport_capacity",0)) > 0: transport_spec = id
		var actual_ships: Array = hud.entry_widgets.keys()
		expected_ships.sort()
		actual_ships.sort()
		check(not expected_ships.is_empty() and actual_ships == expected_ships and actual_ships.all(func(id): return rules.units[id].domain == "naval" and rules.units[id].faction == faction), "navy catalog exactly matches the faction's current unlocked public shipyard and amphibious roster")
		check(not transport_spec.is_empty() and hud.entry_widgets.has(transport_spec), "navy catalog includes the faction's active troop transport instead of retired transport definitions")
		var ship: Dictionary = rules.units[transport_spec]
		var tooltip: String = hud.spec_tooltip(ship)
		check(tooltip.contains("海上单位") and tooltip.contains("搭载 %d 名地面步兵" % int(ship.transport_capacity)) and tooltip.contains("工程兵") and tooltip.contains("登陆海岸"), "navy transport tooltip reads actual capacity and explains coastal boarding")
		var producer_names: Array[String] = [str(rules.buildings[faction + "_shipyard"].name)]
		if ship.producer == "amphibious": producer_names.append(str(rules.buildings[faction + "_factory"].name))
		var transport_rows: String = rows_text(rules,transport_spec)
		check(transport_rows.contains("行动领域 海上") and producer_names.all(func(producer): return transport_rows.contains(producer)), faction + " wiki resolves naval domain and the named shipyard or both shared amphibious facilities")
		for id: String in rules.units:
			if str(rules.units[id].faction) == faction and str(rules.units[id].get("producer","")) == "carrier":
				check(rows_text(rules,id).contains("生产设施 航母飞行甲板"), faction + " carrier aircraft wiki names its real flight-deck producer")
		check(rows_text(rules, str(faction) + "_ship_frigate").contains("海上"), "wiki reads actual sea weapon target domain")
		check(hud.spec_tooltip(rules.buildings[faction + "_shipyard"]).contains("保护港湾") and hud.spec_tooltip(rules.buildings[faction + "_shipyard"]).contains("分基地"), "shipyard tooltip explains home authority and expansion outposts")
		sim.factions[0] = "iron"
	var factory: int = sim._spawn(0, "iron_factory", Vector2(112, 95), true)
	var shipyard: int = sim._spawn(0, "iron_shipyard", sim.map.harbors[0].water_pos, true)
	var ship: int = sim._spawn(0, "iron_ship_transport", sim.map.harbors[0].water_pos, true)
	check(factory >= 0 and shipyard >= 0 and ship >= 0, "real production and ship fixture spawns")
	hud.refresh(sim, [shipyard], null, true, "", 0)
	hud.select_catalog("naval")
	check(hud.production_building() == shipyard, "navy queue uses the selected completed shipyard")
	hud.refresh(sim, [factory], null, true, "", 0)
	hud.select_catalog("vehicle")
	check(hud.entry_widgets.has("iron_transport") and not hud.entry_widgets.has("iron_ship_transport"), "existing iron troop truck stays in ground vehicle catalog")
	hud.refresh(sim, [shipyard], null, true, "", 0)
	hud.select_catalog("naval")
	sim.entities[ship].state = "move"
	hud.refresh(sim, [ship], null, true, "", 0)
	check(hud.selection_text().contains("航行") and hud.selection_text().contains("搭载 0/%d" % int(rules.units.iron_ship_transport.transport_capacity)), "selected transport displays naval motion and live load")
	var engineer: int = sim._spawn(0, "iron_engineer", sim.map.layout[0].start + Vector2(3, 3), true)
	sim.entities[ship].passengers = [engineer]
	sim.entities[engineer].transport_id = ship
	hud.refresh(sim, [ship], null, true, "", 0)
	check(hud.unload_button.visible and hud.unload_move_button.visible and not hud.land_button.visible and not hud.return_button.visible, "loaded ships offer coastal unload controls without aircraft controls")
	check(hud.unload_move_button.tooltip_text.contains("登陆海岸"), "unload destination explains the real coastline constraint")
	sim.entities[ship].passengers = []
	sim.entities[engineer].transport_id = -1
	for window: Vector2i in [Vector2i(1600,900), Vector2i(1100,700)]:
		root.size = window
		for frame: int in 3: await process_frame
		for category: String in ["build", "naval", "air", "vehicle"]:
			hud.select_catalog(category)
			hud.refresh(sim, [shipyard], null, true, "", 0)
			for frame: int in 2: await process_frame
			var production: Rect2 = hud.production_panel.get_global_rect()
			check(root.get_visible_rect().encloses(production), "production panel stays fully in window " + str(window) + category)
			check(not production.intersects(hud.minimap_panel.get_global_rect()) and not production.intersects(hud.command_panel.get_global_rect()), "production never covers minimap or commands " + str(window) + category)
			check(hud.tab == "naval" and not hud.catalog_tabs.visible and not hud.construction_channels.visible, "shipyard only displays navy production and its own queue")
	# The marker builder must never access hidden enemy position or hp.
	var hidden: int = sim._spawn(1, "sky_tank", Vector2(210, 210), true)
	var remembered: int = sim._spawn(1, "sky_power", Vector2(213, 212), true)
	sim.entities[hidden].visible_to = 2
	sim.entities[remembered].visible_to = 2
	var old_pos := Vector2(190, 185)
	sim.team_vision.last_known[0][remembered] = {"pos": old_pos, "seen_at": 3.0, "spec": "sky_power", "kind": "building", "domain": "ground"}
	sim.entities[hidden].erase("pos"); sim.entities[hidden].erase("hp")
	sim.entities[remembered].erase("pos"); sim.entities[remembered].erase("hp")
	var markers: Array[Dictionary] = hud.mini.marker_records(0)
	check(not markers.any(func(m): return m.id == hidden), "hidden mobile enemies leave no current marker")
	check(markers.filter(func(m): return m.id == remembered).size() == 1 and markers.filter(func(m): return m.id == remembered)[0].pos == old_pos, "gray remembered building uses only saved last observed position")
	sim.entities.erase(remembered)
	check(hud.mini.marker_records(0).any(func(m): return m.id == remembered and m.pos == old_pos and m.remembered), "unseen destruction cannot leak into last observed building marker")
	sim.entities.erase(hidden)
	print("Stage3 HUD checks: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	for failure: String in failures: push_error(failure)
	hud.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
