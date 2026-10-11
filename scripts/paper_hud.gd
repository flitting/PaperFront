extends CanvasLayer
class_name PaperHUD

signal action(kind: String, value: Variant)

const PAPER_UI = preload("res://scripts/paper_ui.gd")
const TraitText = preload("res://scripts/faction_trait_text.gd")
const Battlefields = preload("res://scripts/battlefield_catalog.gd")
const CatalogText = preload("res://scripts/wiki_catalog.gd")
const ContextualProduction = preload("res://scripts/contextual_production.gd")
const TransportCommands = preload("res://scripts/transport_commands.gd")
const UnitBrief = preload("res://scripts/unit_brief.gd")
const OwnerPortrait = preload("res://scripts/owner_portrait_material.gd")

const INK := Color("392c21")
const PAPER := Color("d5b88d")
const CREAM := Color("e4cba5")
const BLUE := Color("38627b")
const RED := Color("a7563e")
const PLAYER_COLORS: Array[Color] = preload("res://scripts/player_palette.gd").COLORS
const DOCK_WIDTH := 0.0
var dock: PanelContainer
var sim: WarSimulation
var selection: Array = []
var theme_paper: Theme
var resource_label: Label
var status_label: Label
var info_label: Label
var queue_label: Label
var queue_buttons: HBoxContainer
var queue_cache: String = ""
var order_label: Label
var cancel_build_button:Button
var build_scroll: ScrollContainer
var ui_panels: Array[Control] = []
var entry_widgets: Dictionary = {}
var list_box: HBoxContainer
var mini: Control
var minimap_panel: PanelContainer
var _catalog_width: float = 840.0
var setup_backdrop: ColorRect
var menu: PanelContainer
var setup_tabs: TabContainer
var map_thumbnail: Control
var map_preview_label: Label
var start_button: Button
var scoreboard: Control
var end_panel: PanelContainer
var faction_option: OptionButton
var faction_buttons: Dictionary = {}
var map_option: OptionButton
var debug_menu_enabled: bool = false
var match_setup
var seed_input: LineEdit
var pitch_slider:HSlider
var pitch_label:Label
var title_label: Label
var tab: String = "build"
var category_buttons: Dictionary = {}
var catalog_tabs: HBoxContainer
var channel_status_buttons: Dictionary = {}
var construction_channels: HBoxContainer
var transport_button: Button
var transport_caption: Label
var transport_menu: PopupMenu
var deploy_outpost_button: Button
var cancel_deployment_button: Button
var mode_label: Label
var help_panel: PanelContainer
var dev_button: Button
var cache_key: String = ""
var muted: bool = false
var is_started: bool = false
var fps_label: Label
var time_label: Label
var money_value: Label
var power_value: Label
var population_value: Label
var production_column: VBoxContainer
var production_panel: PanelContainer
var selection_panel: PanelContainer
var selection_header: HBoxContainer
var selection_portrait_frame: PanelContainer
var selection_portrait: TextureRect
var selection_portrait_spec: String = ""
var selection_portrait_team: int = -1
var _selection_portrait_key: String = ""
var _fitting_production: bool = false
var command_panel: PanelContainer
var unit_cancel_button: Button
var pause_button: Button
var maintenance_row: HBoxContainer
var return_button: Button
var unload_button: Button
var land_button: Button
var unload_move_button: Button
var dismantle_button: Button
var voice_label: Label
var voice_timer: float = 0.0
var entry_menu: Control
var wiki: Control
var campaign_ui: Control
var settings: Control
var group_panel: PanelContainer
var group_rows: Dictionary = {}
var group_key := ""
var owner_label: Label
var hover_panel: PanelContainer
var hover_owner: Label
var hover_detail: Label
var base_marker_layer: Control
var placement_label: Label

func _ready() -> void:
	layer = 3
	theme_paper = Theme.new()
	var font := FontVariation.new()
	font.base_font = load("res://assets/fonts/NotoSansCJK-Regular.ttc")
	font.variation_face_index = 2
	font.variation_embolden = 0.5
	theme_paper.default_font = font
	theme_paper.default_font_size = 12
	theme_paper.set_stylebox("panel", "TooltipPanel", style(Color("f3e5c9"),INK,2))
	theme_paper.set_color("font_color", "TooltipLabel", INK)
	theme_paper.set_stylebox("panel", "PopupMenu", style(CREAM, INK, 2))
	theme_paper.set_stylebox("hover", "PopupMenu", style(Color("f8efda"), BLUE, 1))
	theme_paper.set_color("font_color", "PopupMenu", INK)
	theme_paper.set_color("font_hover_color", "PopupMenu", INK)
	theme_paper.set_color("font_disabled_color", "PopupMenu", Color("877961"))
	theme_paper.set_font_size("font_size", "PopupMenu", 14)
	theme_paper.set_color("font_shadow_color", "TooltipLabel", Color.TRANSPARENT)
	theme_paper.set_font_size("font_size", "TooltipLabel", 14)
	for cname in ["Label", "Button", "OptionButton", "CheckButton", "LineEdit"]:
		theme_paper.set_color("font_color", cname, INK)
		theme_paper.set_color("font_hover_color", cname, INK)
		theme_paper.set_color("font_focus_color", cname, INK)
		theme_paper.set_color("font_pressed_color", cname, CREAM)
		theme_paper.set_color("font_disabled_color", cname, Color("877961"))
	for cname in ["Button", "OptionButton"]:
		theme_paper.set_stylebox("normal", cname, style(CREAM))
		theme_paper.set_stylebox("hover", cname, style(Color("f8efda"), BLUE, 2))
		theme_paper.set_stylebox("pressed", cname, style(BLUE))
		theme_paper.set_stylebox("disabled", cname, style(Color("c9b58f"), Color("ae9974")))
	theme_paper.set_stylebox("normal", "LineEdit", style(CREAM))
	theme_paper.set_stylebox("slider","HSlider",style(Color("a99167"),INK,1))
	theme_paper.set_stylebox("grabber_area","HSlider",style(BLUE,BLUE,0))
	theme_paper.set_icon("grabber","HSlider",load("res://assets/pitch_knob.svg"))
	theme_paper.set_icon("grabber_highlight","HSlider",load("res://assets/pitch_knob.svg"))
	theme_paper.set_stylebox("panel", "PanelContainer", style(PAPER, INK, 2))
	theme_paper.set_stylebox("background", "ProgressBar", style(Color("9c8967")))
	theme_paper.set_stylebox("fill", "ProgressBar", style(BLUE, BLUE, 0))
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = theme_paper
	add_child(root)
	group_panel = panel_at(root, Vector2(12, 88), Vector2(258, 322), Vector2.ZERO, Vector2.ZERO)
	group_panel.name = "ControlGroups"
	var group_column := VBoxContainer.new()
	group_column.add_theme_constant_override("separation", 2)
	group_panel.add_child(group_column)
	group_column.add_child(label("编队 · Ctrl + 1–6 保存", 12))
	for number in range(1, 7):
		var group_number: int = number
		var row := button("", func(): action.emit("select_group", group_number))
		row.name = "Group%d" % number
		row.add_theme_font_size_override("font_size", 11)
		row.custom_minimum_size.y = 30
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		group_column.add_child(row)
		group_rows[number] = row
		row.hide()
	group_panel.hide()
	hover_panel = PanelContainer.new()
	hover_panel.name = "VisibleEntityIdentity"
	hover_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_panel.custom_minimum_size = Vector2(250, 58)
	root.add_child(hover_panel)
	var hover_column := VBoxContainer.new()
	hover_panel.add_child(hover_column)
	hover_owner = label("", 16)
	hover_detail = label("", 11)
	hover_column.add_child(hover_owner); hover_column.add_child(hover_detail)
	hover_panel.hide()
	base_marker_layer = Control.new()
	base_marker_layer.name = "BaseMarkers"
	base_marker_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base_marker_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(base_marker_layer)
	placement_label = label("", 13)
	placement_label.name = "PlacementReason"
	placement_label.position = Vector2(280, 90)
	placement_label.add_theme_color_override("font_color", Color("f8eecf"))
	placement_label.add_theme_color_override("font_shadow_color", INK)
	placement_label.add_theme_constant_override("shadow_offset_x", 1)
	placement_label.add_theme_constant_override("shadow_offset_y", 1)
	root.add_child(placement_label)
	placement_label.hide()
	# The reference HUD is a set of paper pieces laid over a full-width table.
	var resources := panel_at(root, Vector2(12, 14), Vector2(550, 70), Vector2.ZERO, Vector2.ZERO)
	var resource_row := HBoxContainer.new()
	resource_row.add_theme_constant_override("separation", 9)
	resources.add_child(resource_row)
	for item in [["logs", "money"], ["bolt", "power"], ["people", "population"]]:
		var symbol := ink_icon(item[0], Vector2(38, 40))
		resource_row.add_child(symbol)
		var value := label("", 24)
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		resource_row.add_child(value)
		match item[1]:
			"money": money_value = value
			"power": power_value = value
			"population": population_value = value
		if item[1] != "population":
			var divider := VSeparator.new()
			resource_row.add_child(divider)
	# These retained labels remain available to callers and diagnostics.
	resource_label = label("", 12)
	resource_label.hide()
	root.add_child(resource_label)
	fps_label = label("", 12)
	fps_label.z_index = 100
	fps_label.hide()
	root.add_child(fps_label)
	var session := panel_at(root, Vector2(-340, 14), Vector2(-12, 70), Vector2(1, 0), Vector2(1, 0))
	var session_row := HBoxContainer.new()
	session_row.add_theme_constant_override("separation", 7)
	session.add_child(session_row)
	time_label = label("00:00", 24)
	time_label.custom_minimum_size.x = 88
	time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	session_row.add_child(time_label)
	pause_button = button("暂停",func(): action.emit("pause",null))
	pause_button.tooltip_text = "暂停 / 继续 PVE 对局 · P"
	pause_button.custom_minimum_size = Vector2(70,40)
	session_row.add_child(pause_button)
	var menu_button := button("", func(): action.emit("settings_open",null))
	menu_button.name="SettingsGear"
	menu_button.tooltip_text = "设置 · 声音、画面与镜头"
	menu_button.custom_minimum_size = Vector2(47, 40)
	menu_button.add_child(ink_icon("gear", Vector2.ZERO, true))
	session_row.add_child(menu_button)
	dev_button = button("Debug", func(): action.emit("debug_panel", null))
	dev_button.custom_minimum_size = Vector2(70, 40)
	dev_button.tooltip_text = "调试信息 · F2"
	dev_button.visible = false
	session_row.add_child(dev_button)
	var map_panel := panel_at(root, Vector2(12, -228), Vector2(305, -16), Vector2(0, 1), Vector2(0, 1))
	minimap_panel = map_panel
	mini = preload("res://scripts/minimap.gd").new()
	mini.custom_minimum_size = Vector2(272, 192)
	mini.hud = self
	map_panel.add_child(mini)
	production_panel = panel_at(root, Vector2(-420, -242), Vector2(420, -16), Vector2(0.5, 1), Vector2(0.5, 1))
	production_panel.name = "ProductionPaper"
	dock = production_panel # Retained for callers which used the old dock reference.
	var production_col := VBoxContainer.new()
	production_column = production_col
	production_col.minimum_size_changed.connect(_queue_production_fit)
	production_col.add_theme_constant_override("separation", 3)
	production_panel.add_child(production_col)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 6)
	production_col.add_child(heading)
	title_label = label("", 12)
	title_label.clip_text = true
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.custom_minimum_size.x = 106
	order_label = label("", 11)
	order_label.clip_text = true
	order_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	order_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title_label)
	heading.add_child(order_label)
	cancel_build_button = button("取消", func(): action.emit("cancel_build", {"channel": "defense" if tab == "defense" else "normal"}))
	cancel_build_button.custom_minimum_size = Vector2(47, 23)
	cancel_build_button.add_theme_font_size_override("font_size", 10)
	heading.add_child(cancel_build_button)
	unit_cancel_button = button("取消首项", func(): action.emit("cancel_unit", null))
	unit_cancel_button.custom_minimum_size.y = 23
	unit_cancel_button.add_theme_font_size_override("font_size", 10)
	heading.add_child(unit_cancel_button)
	queue_buttons = HBoxContainer.new()
	queue_buttons.add_theme_constant_override("separation", 3)
	heading.add_child(queue_buttons)
	var channel_row := HBoxContainer.new()
	construction_channels = channel_row
	channel_row.add_theme_constant_override("separation", 5)
	production_col.add_child(channel_row)
	for item in [["normal", "常规"], ["defense", "防御"]]:
		var channel_id: String = item[0]
		var status_button := button(item[1] + " · 空闲", func(): choose_construction_channel(channel_id))
		status_button.custom_minimum_size = Vector2(172, 23)
		status_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		status_button.add_theme_font_size_override("font_size", 10)
		channel_row.add_child(status_button)
		channel_status_buttons[channel_id] = status_button
	catalog_tabs = HBoxContainer.new()
	catalog_tabs.add_theme_constant_override("separation", 3)
	production_col.add_child(catalog_tabs)
	for item in [["build", "建筑"], ["defense", "防御"], ["infantry", "步兵"], ["vehicle", "车辆"], ["air", "空军"], ["naval", "海军"]]:
		var category: String = item[0]
		var tab_button := button(item[1], func(): select_catalog(category))
		tab_button.custom_minimum_size = Vector2(66, 22)
		tab_button.add_theme_font_size_override("font_size", 10)
		catalog_tabs.add_child(tab_button)
		category_buttons[category] = tab_button
	root.resized.connect(_fit_production)
	build_scroll = ScrollContainer.new()
	build_scroll.mouse_force_pass_scroll_events = false
	build_scroll.gui_input.connect(_build_scroll_input)
	build_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	build_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	build_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	production_col.add_child(build_scroll)
	list_box = HBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 5)
	list_box.alignment = BoxContainer.ALIGNMENT_CENTER
	build_scroll.add_child(list_box)
	list_box.minimum_size_changed.connect(_queue_production_fit)
	queue_label = label("", 10)
	queue_label.hide()
	root.add_child(queue_label)
	mode_label = label("", 10)
	mode_label.hide()
	root.add_child(mode_label)
	production_panel.hide()
	command_panel = panel_at(root, Vector2(-264, -214), Vector2(-12, -16), Vector2(1, 1), Vector2(1, 1))
	var cmds := GridContainer.new()
	cmds.columns = 3
	cmds.add_theme_constant_override("h_separation", 7)
	cmds.add_theme_constant_override("v_separation", 7)
	command_panel.add_child(cmds)
	for command in [["attack_move", "target", "进攻移动 Z"], ["waypoint", "flag", "路径点 C"], ["transport", "people", "装载/卸载"], ["stop", "hand", "停止 X"], ["force_attack", "target", "强制攻击 H"], ["force_move", "flag", "强制移动 F"]]:
		var id: String = command[0]
		var b := button("", func(): action.emit(id, null))
		b.tooltip_text = command[2]
		b.custom_minimum_size = Vector2(73, 87)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var symbol := ink_icon(command[1], Vector2.ZERO, true)
		symbol.offset_left = 10
		symbol.offset_top = 14
		symbol.offset_right = -10
		symbol.offset_bottom = -32
		b.add_child(symbol)
		var caption := label(command[2], 11)
		caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		caption.offset_top = -25
		caption.offset_bottom = -5
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(caption)
		cmds.add_child(b)
		if id == "transport":
			transport_button = b
			transport_caption = caption
	transport_menu = PopupMenu.new()
	transport_menu.name = "TransportActions"
	transport_menu.theme = theme_paper
	transport_menu.add_item("装载", 0)
	transport_menu.add_item("卸载", 1)
	transport_menu.id_pressed.connect(func(id): action.emit("load_transport" if id == 0 else "unload_move", null))
	root.add_child(transport_menu)
	selection_panel = panel_at(root, Vector2(-264, -408), Vector2(-12, -226), Vector2(1, 1), Vector2(1, 1))
	selection_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	info_label = label("", 12)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.max_lines_visible = 3
	info_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var selection_column := VBoxContainer.new()
	selection_panel.add_child(selection_column)
	selection_column.minimum_size_changed.connect(_fit_selection)
	selection_header = HBoxContainer.new()
	selection_header.name = "SelectedIdentity"
	selection_header.add_theme_constant_override("separation", 10)
	selection_column.add_child(selection_header)
	selection_portrait_frame = PanelContainer.new()
	selection_portrait_frame.name = "SelectedPortraitFrame"
	selection_portrait_frame.custom_minimum_size = Vector2(76, 82)
	selection_portrait_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_header.add_child(selection_portrait_frame)
	selection_portrait = TextureRect.new()
	selection_portrait.name = "SelectedPortrait"
	selection_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	selection_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	selection_portrait.custom_minimum_size = Vector2(64, 70)
	selection_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_portrait_frame.add_child(selection_portrait)
	owner_label = label("", 15)
	owner_label.name = "SelectedOwner"
	owner_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	owner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	owner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	selection_header.add_child(owner_label)
	selection_column.add_child(info_label)
	maintenance_row = HBoxContainer.new()
	selection_column.add_child(maintenance_row)
	for item in [["修理","repair"],["出售","sell"]]:
		var action_id: String = item[1]
		maintenance_row.add_child(button(item[0],func():action.emit(action_id,null)))
	deploy_outpost_button = button("部署分基地", func(): action.emit("build", {"spec": sim.factions[0] + "_outpost", "channel": "normal"}))
	deploy_outpost_button.tooltip_text = "工程兵前往指定位置部署分基地，现场施工并逐步付款。"
	selection_column.add_child(deploy_outpost_button)
	deploy_outpost_button.hide()
	cancel_deployment_button = button("取消分基地选址", func(): action.emit("cancel_build", {"channel": "normal"}))
	selection_column.add_child(cancel_deployment_button)
	cancel_deployment_button.hide()
	return_button = button("回厂 / 返航 B", func(): action.emit("return", null))
	return_button.tooltip_text = "选中的飞机返回可用机场补充弹药并维修；按 B 返航且没有后续任务时停机。"
	selection_column.add_child(return_button)
	return_button.hide()
	unload_button = button("卸下步兵 ", func(): action.emit("unload", null))
	unload_button.tooltip_text = "在运输载具附近可通行的位置卸下搭载的地面步兵，包括工程兵和反甲兵；运输船须停靠陆岸。"
	selection_column.add_child(unload_button)
	unload_button.hide()
	land_button = button("指定降落地点 L", func(): action.emit("land", null))
	land_button.tooltip_text = "选择一处可用空地，让飞机降落。再次下达飞行命令即可起飞。"
	selection_column.add_child(land_button)
	land_button.hide()
	unload_move_button = button("指定地点卸载 U", func(): action.emit("unload_move", null))
	unload_move_button.tooltip_text = "选择地点，运输载具到达后卸下搭载的步兵；运输船请选择合法登陆海岸。"
	selection_column.add_child(unload_move_button)
	unload_move_button.hide()
	dismantle_button=button("拆除脚手架",func():action.emit("dismantle_outpost",null))
	dismantle_button.tooltip_text="拆除未完工建筑，释放占地；已花施工和维修资金不退款。"
	selection_column.add_child(dismantle_button)
	dismantle_button.hide()
	selection_panel.hide()
	voice_label = label("", 15)
	voice_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	voice_label.offset_left = -330
	voice_label.offset_right = 330
	voice_label.offset_top = 84
	voice_label.offset_bottom = 120
	voice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	voice_label.add_theme_color_override("font_color", Color("fff0cf"))
	voice_label.add_theme_color_override("font_shadow_color", INK)
	voice_label.add_theme_constant_override("shadow_offset_x", 2)
	voice_label.add_theme_constant_override("shadow_offset_y", 2)
	voice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	voice_label.hide()
	root.add_child(voice_label)
	status_label = label("", 14)
	status_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	status_label.offset_left = -410
	status_label.offset_right = 410
	status_label.offset_top = -274
	status_label.offset_bottom = -248
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.max_lines_visible = 1
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_label.add_theme_color_override("font_shadow_color", Color("f0dfb9"))
	status_label.add_theme_constant_override("shadow_offset_x", 1)
	status_label.add_theme_constant_override("shadow_offset_y", 1)
	root.add_child(status_label)
	make_menu(root)
	make_help(root)
	make_end(root)
	campaign_ui=preload("res://scripts/campaign_ui.gd").new()
	campaign_ui.hud=self
	root.add_child(campaign_ui)
	campaign_ui.focus_target.connect(func(point: Vector2): action.emit("campaign_target", point))
	entry_menu=preload("res://scripts/paper_entry_menu.gd").new()
	entry_menu.name="EntryMenu"
	root.add_child(entry_menu)
	entry_menu.action.connect(func(kind,value):action.emit(kind,value))
	entry_menu.hide()
	wiki=preload("res://scripts/paper_wiki.gd").new()
	wiki.name="ArmyWiki"
	root.add_child(wiki)
	wiki.closed.connect(func():action.emit("wiki_closed",null))
	settings=preload("res://scripts/paper_settings.gd").new()
	settings.name="Settings"
	root.add_child(settings)
	settings.changed.connect(func(kind,value):action.emit(kind,value))
	settings.action.connect(func(kind,value):action.emit(kind,value))
	settings.closed.connect(func():action.emit("settings_closed",null))

func style(color: Color, border: Color = INK, width: int = 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = border
	s.set_border_width_all(width)
	s.corner_radius_top_left = 3
	s.corner_radius_top_right = 1
	s.corner_radius_bottom_left = 1
	s.corner_radius_bottom_right = 4
	s.content_margin_left = 7
	s.content_margin_right = 7
	s.content_margin_top = 5
	s.content_margin_bottom = 5
	s.shadow_color = Color(0.12, 0.08, 0.05, 0.3)
	s.shadow_size = 3
	return s

func panel_at(parent: Control, a: Vector2, b: Vector2, anchors_a: Vector2, anchors_b: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	parent.add_child(p)
	var transparent := style(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0)
	transparent.shadow_size = 0
	p.add_theme_stylebox_override("panel", transparent)
	var paper := PAPER_UI.new()
	paper.paper_color = PAPER
	paper.inset = Vector2(7, 5)
	paper.paper_seed = 730 + ui_panels.size() * 47
	p.add_child(paper)
	p.mouse_force_pass_scroll_events = false
	ui_panels.append(p)
	p.anchor_left = anchors_a.x
	p.anchor_top = anchors_a.y
	p.anchor_right = anchors_b.x
	p.anchor_bottom = anchors_b.y
	p.offset_left = a.x
	p.offset_top = a.y
	p.offset_right = b.x
	p.offset_bottom = b.y
	return p

func battlefield_rect() -> Rect2:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	return Rect2(Vector2.ZERO, viewport_size)

func separator() -> HSeparator:
	var line := HSeparator.new()
	var line_style := StyleBoxLine.new()
	line_style.color = Color("aa9270")
	line_style.thickness = 1
	line.add_theme_stylebox_override("separator", line_style)
	return line

func label(text_value: String, font_size: int = 12) -> Label:
	var l := Label.new()
	l.text = text_value
	l.add_theme_font_size_override("font_size", font_size)
	return l

func button(text_value: String, callable: Callable) -> Button:
	var b := Button.new()
	b.text = text_value
	b.mouse_force_pass_scroll_events = false
	b.custom_minimum_size.y = 28
	for state in ["normal", "hover", "pressed", "disabled"]:
		var box := style(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0)
		box.shadow_size = 0
		b.add_theme_stylebox_override(state, box)
	b.add_theme_color_override("font_pressed_color", INK)
	var paper := PAPER_UI.new()
	paper.paper_color = PAPER.lightened(0.025)
	paper.ink_frame = true
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(paper)
	b.pressed.connect(callable)
	return b

func ink_icon(kind: String, minimum: Vector2, full_rect := false) -> Control:
	var symbol := PAPER_UI.new()
	symbol.icon = kind
	symbol.custom_minimum_size = minimum
	if full_rect: symbol.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return symbol

func make_menu(root: Control) -> void:
	setup_backdrop=ColorRect.new();setup_backdrop.color=Color("65513d");setup_backdrop.mouse_filter=Control.MOUSE_FILTER_STOP
	setup_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(setup_backdrop)
	menu = panel_at(root, Vector2(-540, -330), Vector2(540, 330), Vector2(.5,.5), Vector2(.5,.5))
	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation",14)
	menu.add_child(controls)
	menu.visibility_changed.connect(func():setup_backdrop.visible=menu.visible)
	var heading := HBoxContainer.new()
	controls.add_child(heading)
	var title := label("新战局",32)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	heading.add_child(button("返回入口",func():action.emit("entry_home",null)))
	var intro := label("选择你的军团，部署对手，再出发。",15)
	intro.add_theme_color_override("font_color",Color("785d3b"))
	controls.add_child(intro)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",22)
	controls.add_child(body)
	setup_tabs = TabContainer.new()
	setup_tabs.name = "MatchSetupTabs"
	setup_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	setup_tabs.size_flags_stretch_ratio = 1.1
	preload("res://scripts/paper_tabs.gd").apply(setup_tabs)
	body.add_child(setup_tabs)
	var faction_page: VBoxContainer = _setup_page("军团")
	var battlefield_page: VBoxContainer = _setup_page("战场")
	var deployment_page: VBoxContainer = _setup_page("部署")
	var col: VBoxContainer = faction_page
	col.add_child(label("你的军团",19))
	faction_option = OptionButton.new()
	faction_option.get_popup().force_native = true
	col.add_child(faction_option); faction_option.hide()
	var factions := GridContainer.new()
	factions.columns = 2
	factions.add_theme_constant_override("h_separation",10)
	factions.add_theme_constant_override("v_separation",8)
	col.add_child(factions)
	var group := ButtonGroup.new()
	var faction_rules: Dictionary = TraitText.menu_rules()
	for item in [["kestrel","正典军团"],["rivet","重锤军团"],["iron","长钉军团"],["sky","天翼教团"]]:
		var id: String = item[0]
		var specialty: String = TraitText.menu_short(faction_rules,id)
		faction_option.add_item(str(item[1])+"  ·  "+specialty)
		faction_option.set_item_metadata(faction_option.item_count-1,id)
		var card := button(str(item[1])+"\n"+specialty,func():select_faction(id);action.emit("ui_click",null))
		card.tooltip_text = "\n".join(TraitText.faction_lines(faction_rules,id))
		card.toggle_mode = true; card.button_group = group
		card.custom_minimum_size = Vector2(190,64)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_font_size_override("font_size",14)
		faction_buttons[id] = card; factions.add_child(card)
	faction_option.item_selected.connect(func(_index):_refresh_faction_cards())
	_refresh_faction_cards()
	col = battlefield_page
	col.add_child(label("战场",19))
	map_option = OptionButton.new()
	map_option.name = "BattlefieldChoice"
	map_option.get_popup().force_native = true
	for item in Battlefields.entries():
		if item.id == "dev" and not debug_menu_enabled: continue
		map_option.add_item("%s · %d×%d" % [item.name,item.size,item.size])
		map_option.set_item_metadata(map_option.item_count-1,item.id)
	col.add_child(map_option)
	col = deployment_page
	col.add_child(label("参战部署",19))
	match_setup = preload("res://scripts/skirmish_setup.gd").new()
	col.add_child(match_setup); match_setup.build(self)
	col = battlefield_page
	var advanced := VBoxContainer.new()
	advanced.add_theme_constant_override("separation",6)
	var detail_button := button("布局种子  ▾",func():advanced.visible=not advanced.visible)
	detail_button.add_theme_font_size_override("font_size",13)
	col.add_child(detail_button); col.add_child(advanced)
	advanced.hide()
	var seed_row := HBoxContainer.new(); advanced.add_child(seed_row)
	seed_row.add_child(label("地图种子",13))
	seed_input = LineEdit.new(); seed_input.text="73026"; seed_input.placeholder_text="输入整数"
	seed_input.size_flags_horizontal=Control.SIZE_EXPAND_FILL; seed_row.add_child(seed_input)
	var pitch_row := HBoxContainer.new(); col.add_child(pitch_row); pitch_row.hide()
	pitch_label=label("镜头俯角 30°",14);pitch_row.add_child(pitch_label)
	pitch_slider=HSlider.new();pitch_slider.min_value=20;pitch_slider.max_value=45;pitch_slider.value=30;pitch_slider.step=1
	pitch_row.add_child(pitch_slider)
	pitch_slider.value_changed.connect(func(v):pitch_label.text="镜头俯角 %.0f°" % v;action.emit("pitch",v))
	var preview_panel := PanelContainer.new()
	preview_panel.add_theme_stylebox_override("panel",style(Color("ecdbb9"),Color("ad9068"),1))
	preview_panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	preview_panel.size_flags_stretch_ratio=1.0
	preview_panel.custom_minimum_size.x=330
	body.add_child(preview_panel)
	var preview_col:=VBoxContainer.new();preview_col.add_theme_constant_override("separation",10);preview_panel.add_child(preview_col)
	preview_col.add_child(label("战场预览",20))
	map_thumbnail=preload("res://scripts/map_thumbnail.gd").new()
	map_thumbnail.name="ActualMapPreview"
	map_thumbnail.custom_minimum_size=Vector2(280,250)
	map_thumbnail.size_flags_horizontal=Control.SIZE_EXPAND_FILL;map_thumbnail.size_flags_vertical=Control.SIZE_EXPAND_FILL
	preview_col.add_child(map_thumbnail)
	map_preview_label=label("正在绘制地图…",14)
	map_preview_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	preview_col.add_child(map_preview_label)
	var legend:=label("● 你的出生点  ·  ● 对手出生点（颜色可自行选择）\n蓝色矿点  ·  水域、道路与高地按真实布局绘制",12)
	legend.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;preview_col.add_child(legend)
	map_thumbnail.updated.connect(_map_thumbnail_updated)
	map_option.item_selected.connect(func(_index):match_setup.set_map(selected_map());_request_map_preview();action.emit("ui_click",null))
	match_setup.changed.connect(_request_map_preview)
	seed_input.text_changed.connect(func(_text):_request_map_preview())
	match_setup.set_map(selected_map())
	_request_map_preview()
	start_button=button("开始遭遇战",func():action.emit("start",{"faction":selected_faction(),"mode":selected_map(),"seed":seed_input.text.to_int(),"match_options":match_setup.options(selected_faction())}))
	start_button.custom_minimum_size.y=48;controls.add_child(start_button)
	var resume:=button("返回进行中的战局",func():action.emit("setup_resume",null));resume.name="Resume";controls.add_child(resume)
	root.resized.connect(_fit_menu);_fit_menu()

func _setup_page(caption: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = caption
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_force_pass_scroll_events = false
	setup_tabs.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)
	return content

func _request_map_preview() -> void:
	if map_thumbnail==null or seed_input==null or match_setup==null:return
	var colors: Array = []
	for slot: Dictionary in match_setup.options(selected_faction()).slots: colors.append(slot.color)
	map_thumbnail.set_player_colors(colors)
	var key:String="%s/%d/%d" % [selected_map(),seed_input.text.to_int(),match_setup.player_count()]
	if map_thumbnail.source_key==key:
		_map_thumbnail_updated(map_thumbnail.source_metadata);return
	map_preview_label.text="%s · 更新预览…" % Battlefields.display_name(selected_map())
	map_thumbnail.request(selected_map(),seed_input.text.to_int(),match_setup.player_count())

func _map_thumbnail_updated(meta:Dictionary) -> void:
	map_preview_label.text="%s  ·  %d 方  ·  种子 %d\n%d×%d 格，与本局生成布局一致" % [Battlefields.display_name(str(meta.mode)),int(meta.players),int(meta.seed),int(meta.size),int(meta.size)]

func _fit_menu() -> void:
	var area:=get_viewport().get_visible_rect().size
	var width:float=minf(1080.0,area.x-48.0)
	var height:float=minf(720.0,area.y-48.0)
	menu.offset_left=-width*.5;menu.offset_right=width*.5
	menu.offset_top=-height*.5;menu.offset_bottom=height*.5

func make_help(root: Control) -> void:
	help_panel = panel_at(root, Vector2(28, 94), Vector2(470, 610), Vector2.ZERO, Vector2.ZERO)
	help_panel.visible = false
	var c := VBoxContainer.new()
	c.name="HelpColumn"
	help_panel.add_child(c)
	c.add_child(label("沙盘操作手册", 23))
	var text_value := "左键点选 / 拖框：选择独立单位\n右键地面：移动；右键敌人：指定攻击\nShift：追加命令；Ctrl + 1–6：保存编队\n1–6：选择编队；Z + 左键：攻击移动\nC：连续路径点；G：往返巡逻；H + 左键：强制攻击目标 / 地面\n装载/卸载：选载具点步兵装载，或选步兵点载具；U 指定卸载地点\nL：运输机指定降落地点；B：飞机返航补给\nP：暂停 / 继续；X：停止；F + 左键：强制移动；空格：最近战斗热点 / 主基地\nHome：返回总部；WASD：相机平移\nQ / E：环绕；R / T：调节俯角；中键：平移；滚轮：缩放\n鼠标贴屏幕四边：平移\nHUD纸板不会触发战场点击或滚轮缩放。\n矿车右键辉晶矿柱：无限采集；每根同时只允许一辆矿车开采。\n矿柱不可摧毁，地面单位不可穿过。\n中立树木 / 房屋 / 石墙：仅 H 强制攻击可以清理\nF5 / F9：保存 / 读取；Esc：设置菜单\n\n正典、长钉与天翼最多一座总部，总部不可重造。\n重锤只有一种基地兵营，开局部署与后续工兵建造完全相同，可建造多座。\n正典、长钉与天翼选中总部 / 分基地显示建筑卡，工兵可部署分基地。\n重锤基地兵营开局训练步兵与工兵；选中工兵显示建筑卡。\n重锤取消分基地，通过新的基地兵营扩张基地。\n选中兵营 / 工厂 / 机场 / 船厂显示对应训练卡。
正典、长钉与天翼：普通建筑卡点击付款 → 完成后再次点击 → 放置。\n重锤：工兵选建筑卡立即选址，到场搭脚手架并按进度付款。\n普通重锤建筑须在已完成基地兵营范围内施工，新基地兵营可远程选址。\n工程兵选中后使用右侧「部署分基地」立即选址，抵达后开始施工并逐步扣款。\n脚手架受伤先修复；工兵阵亡暂停，其他工兵右键接手或选中后拆除。\n绿色标记合法，红色非法；建造预览按R每次旋转90°，右键退出放置。\n训练栏使用选中的兵营 / 工厂 / 机场 / 船厂，各自独立排队。\n选中生产建筑右键地面：设置集结点。\n工程兵接近友方建筑后立即修满；地面单位按恢复生命付费维修。\n工程兵右键敌方建筑：接近后立即占领，包括防御塔，排除围墙 / 拒马 / 铁路 / 岔道口。
工程兵右键受损桥梁或断桥桥头：按进度付费修桥。
地面步兵（含工程兵与反甲兵）右键己方运输载具：上车；容量见单位介绍；U 指定卸载地点，抵达合法地面或海岸后卸载。\n飞机按空中机身位置点选 / 框选；B 返航补给维修。\n运输机可点击降落选择空地，也可用 L 在指定地点降落；卸载用 U 指定地点。
飞机弹药耗尽自动返航；机场容量与防空制约航空作战。\n海军在连通海域航行；船厂全占地直接建在海面，海军目录由所选船厂独立排队。
船厂须满足己方建设权限、前置与出航/往返岸点通道；其他阵营海岸分基地或重锤基地兵营可扩展建设权限。
步兵右键停靠岸边的运输船登船；U 指定合法登陆海岸卸载。
新战场敌军仅在己方视野内可见；小地图灰色建筑是上次侦察位置。
右键桥梁：武装单位攻击中立桥。\nF 强制移动可让坦克碾压敌方步兵，不能碾压友方步兵。\n己方建筑：修理开关；出售返还原价一半。\n\n移动命令优先行军；Z 攻击移动让坦克边行军边开火。\n坦克炮塔独立瞄准；步兵停下交战。\n炮弹落点固定、可躲避，也会误伤友军。\n仅摧毁总部不会结束比赛，须清除敌方所有非围墙 / 拒马建筑；围墙与拒马不参与结算。"
	var help_scroll:=ScrollContainer.new()
	text_value += "\n\n科技等级：T0 初始即可建造；T1 建成兵营后；T2 建成战车工厂或飞机场任一后；T3 建成科技中心类建筑后。\n等级只规定科技解锁，单位仍须在对应生产设施训练，并满足卡片列出的特殊前置。\n普通车辆占地 1×1 格；重型坦克与少数大型高级单位为 2×2 格，能够碾压敌方普通坦克。\n编队列表只显示已有部队的编队；点击左侧编队或按 1–6 立即选中，单位可加入多个编队。"
	text_value += "\n修理厂：选中受损己方地面装甲车，右键己方修理厂；载具进入车间后才开始维修，按实际恢复生命付费，需要正常供电。飞机返航机场维修，舰船沿用海上维修。"
	help_scroll.name="HelpScroll"
	help_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	help_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	help_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
	help_scroll.mouse_force_pass_scroll_events=false
	c.add_child(help_scroll)
	var help_body:=label(text_value,14)
	help_body.name="HelpBody"
	help_body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	help_body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	help_scroll.add_child(help_body)
	c.add_child(button("收起说明", func(): help_panel.hide()))

func make_end(root: Control) -> void:
	scoreboard=preload("res://scripts/match_scoreboard.gd").new()
	scoreboard.name="MatchScoreboard"
	scoreboard.theme=theme_paper
	add_child(scoreboard)
	scoreboard.action.connect(func(kind,value):action.emit(kind,value))
	end_panel = panel_at(root, Vector2(-245, -150), Vector2(245, 150), Vector2(0.5, 0.5), Vector2(0.5, 0.5))
	end_panel.visible = false
	var c := VBoxContainer.new()
	end_panel.add_child(c)
	var l := label("", 34)
	l.name = "Outcome"
	c.add_child(l)
	var s := label("", 15)
	s.name = "Stats"
	c.add_child(s)
	c.add_child(button("再战一次", func(): action.emit("restart", null)))
	c.add_child(button("返回主菜单", func(): action.emit("entry_home", null)))
	c.add_child(button("退出游戏", func(): action.emit("quit", null)))

func show_menu(show: bool) -> void:
	menu.visible = show
	if show and entry_menu!=null:entry_menu.hide()
	for child in menu.get_child(1).get_children():
		if child.name == "Resume": child.visible = is_started and sim != null and sim.result.is_empty()

func show_entry(show: bool) -> void:
	entry_menu.set_can_resume(is_started and sim!=null and sim.result.is_empty())
	entry_menu.visible=show
	if show:
		menu.hide();help_panel.hide();end_panel.hide()
		if scoreboard!=null:scoreboard.close_scoreboard()

func modal_catalog_visible() -> bool:
	return (entry_menu!=null and entry_menu.visible) or (wiki!=null and wiki.visible) or (settings!=null and settings.visible) or (scoreboard!=null and scoreboard.visible)

func refresh(new_sim: WarSimulation, ids: Array, camera: Camera3D, dev_mode: bool, feedback: String, cpu_ms: float, bridge_id:int=-1, debug_available:bool=false) -> void:
	sim = new_sim
	if sim == null:return
	var previous_selection: Array = selection
	selection = ids.filter(func(id):return sim.entities.has(id) and sim.entity_visible_to(0, int(id)) and not sim.Transport.is_loaded(sim.entities[id]))
	if previous_selection != selection: transport_menu.hide()
	var available_categories: Array = ContextualProduction.categories(sim, selection)
	if not available_categories.is_empty() and tab not in available_categories:
		tab = available_categories[0]
		cache_key = ""
	dev_button.visible = debug_available
	var p := sim.power(0)
	var n := sim.counts(0)
	resource_label.text = "$ %s  ·  %02d:%02d\n电力 %d/%d  ·  单位 %d  ·  建筑 %d" % [int(sim.money[0]), int(sim.time) / 60, int(sim.time) % 60, int(p.x), int(p.y), n.x, n.y]
	resource_label.add_theme_color_override("font_color", RED if p.x < p.y else INK)
	money_value.text = str(int(sim.money[0]))
	power_value.text = "%d/%d" % [int(p.x), int(p.y)]
	var supply: Dictionary = sim.local_power_summary(0)
	power_value.tooltip_text = "全域供电 %d · 未被局部供电覆盖的需求 %d\n主基地局部供电 %d（已用 %d）；只覆盖附近建筑。" % [int(supply.global_supply), int(supply.global_demand), int(supply.local_supply), int(supply.local_used)]
	power_value.add_theme_color_override("font_color", RED if p.x < p.y else INK)
	population_value.text = str(n.x)
	population_value.tooltip_text = "当前单位 %d · 建筑 %d" % [n.x, n.y]
	time_label.text = "%02d:%02d" % [int(sim.time) / 60, int(sim.time) % 60]
	var context_building: int = ContextualProduction.building(sim, selection)
	title_label.text = str(sim.data_for(sim.entities[context_building].spec).name) if context_building >= 0 else ""
	mode_label.text = ("无字桥补给线" if sim.map.mode == "campaign" else Battlefields.display_name(sim.map.mode)) + "  ·  %d×%d" % [sim.map.size, sim.map.size]
	status_label.text = feedback.get_slice("\n", maxi(0, feedback.count("\n")))
	status_label.tooltip_text = feedback
	mini.sim = sim
	mini.camera = camera
	mini.queue_redraw()
	if campaign_ui != null:
		campaign_ui.display(sim.campaign_controller.view_state() if sim.campaign_controller != null else {})
	var channel: String = "defense" if tab == "defense" else "normal"
	var bo: Dictionary = sim.order_for_team(0, channel)
	for channel_id in channel_status_buttons:
		var status_order: Dictionary = sim.order_for_team(0, channel_id)
		var status_button: Button = channel_status_buttons[channel_id]
		var prefix: String = "防御" if channel_id == "defense" else "常规"
		status_button.text = prefix + " · 空闲" if status_order.is_empty() else prefix + " · " + str(sim.data_for(status_order.spec).name) + (" 就绪" if bool(status_order.get("ready", false)) else " %d%%" % int(float(status_order.get("progress", 0.0)) * 100.0))
		status_button.tooltip_text = "点击切换到" + prefix + "目录" if status_order.is_empty() or not bool(status_order.get("ready", false)) else "点击选择就绪建筑的放置位置"
	var choosing_site: bool = int(bo.get("builder", -1)) >= 0
	cancel_build_button.text = "取消"
	cancel_build_button.tooltip_text = "取消建筑选址；尚未花费资金" if choosing_site else ("取消就绪建筑（不退款）" if not bo.is_empty() and bo.get("ready", false) else "取消当前建筑，按未完成进度退款")
	if bo.is_empty():
		order_label.text = ("防御" if channel == "defense" else "建筑") + "队列空闲"
	else:
		var d: Dictionary = sim.data_for(bo.spec)
		var ready: bool = bo.get("ready", false)
		var pr: float = float(bo.get("progress", 0.0))
		order_label.text = d.name + (" · 选址，左键指定位置" if choosing_site else (" · 就绪，点击后放置" if ready else " · 建造 %d%%" % int(pr * 100)))
	info_label.text = selection_text()
	owner_label.visible = sim.selection_ids(selection).size() == 1
	if owner_label.visible: owner_label.text = entity_owner_text(sim.entities[selection[0]])
	refresh_selection_portrait()
	selection_panel.visible = not selection.is_empty() or bridge_id >= 0
	if selection.is_empty() and bridge_id>=0:
		var bridge:Dictionary=sim._bridge_by_id(bridge_id)
		if not bridge.is_empty():
			info_label.text="中立桥梁 · HP %d / %d   ·   %s\n修复 %.0f%% · 工程兵右键桥面或桥头修复；武装单位右键攻击。" % [int(bridge.hp),int(sim.rules.economy.bridge_hp),"通行中" if bridge.alive else "已断路",float(bridge.repair_progress)*100]
	info_label.tooltip_text = selection_details() if not selection.is_empty() else info_label.text
	var producer := production_building()
	if producer >= 0:
		var e: Dictionary = sim.entities[producer]
		var lines: Array[String] = []
		for o in e.queue:
			lines.append(sim.data_for(o.spec).name + " %d%%" % int(float(o.get("progress", 0.0)) * 100) + (" · 等待铁路连接" if bool(o.get("ready",false)) and bool(e.get("rail_waiting",false)) else " · 等待出厂" if bool(o.get("ready",false)) else ""))
		queue_label.text = "生产队列：" + ("空闲" if lines.is_empty() else " → ".join(lines))
	else: queue_label.text = "选择兵营 / 工厂 / 机场 / 船厂，或先建设生产设施"
	queue_label.tooltip_text = queue_label.text
	var building := selected_building()
	var engineer := selected_engineer()
	var scaffold:bool=building>=0 and sim.entities[building].has("construction") and float(sim.entities[building].construct_remaining)>0.0
	info_label.max_lines_visible=4 if scaffold else (8 if sim.selection_ids(selection).size()==1 and sim.entities[selection[0]].kind=="unit" else 3)
	maintenance_row.visible = building >= 0 and not scaffold
	dismantle_button.visible=scaffold
	return_button.visible = selection.any(func(id): return sim.entities.has(id) and int(sim.entities[id].team) == 0 and (str(sim.data_for(sim.entities[id].spec).get("domain", "ground")) == "air" and not bool(sim.data_for(sim.entities[id].spec).get("permanent_air",false)) or sim.data_for(sim.entities[id].spec).get("art","")=="harvester"))
	unload_button.visible = selection.any(func(id): return sim.entities.has(id) and int(sim.entities[id].team) == 0 and not sim.entities[id].get("passengers", []).is_empty())
	land_button.visible = selection.any(func(id): return sim.entities.has(id) and int(sim.entities[id].team) == 0 and sim._is_air(sim.entities[id]) and int(sim.data_for(sim.entities[id].spec).get("transport_capacity", 0)) > 0)
	unload_move_button.visible = unload_button.visible
	selection_panel.offset_top = selection_panel.offset_bottom - selection_panel.get_combined_minimum_size().y
	production_panel.visible = not available_categories.is_empty()
	construction_channels.visible = "build" in available_categories
	catalog_tabs.visible = available_categories.size() > 1
	for category in category_buttons:
		category_buttons[category].visible = category in available_categories
		category_buttons[category].disabled = category == tab
	var outpost_spec: String = sim.factions[0] + "_outpost"
	var deployment_order: Dictionary = sim.order_for_team(0, "normal")
	var selected_deployment: bool = engineer >= 0 and str(deployment_order.get("spec", "")) == outpost_spec and int(deployment_order.get("builder", -1)) == engineer and bool(deployment_order.get("ready", false))
	deploy_outpost_button.visible = ContextualProduction.deployment_visible(sim, engineer)
	deploy_outpost_button.text = "选择分基地位置" if selected_deployment else "部署分基地"
	deploy_outpost_button.disabled = deploy_outpost_button.visible and not selected_deployment and not sim.availability(0, outpost_spec, engineer).is_empty()
	cancel_deployment_button.visible = selected_deployment
	if deploy_outpost_button.visible:
		deploy_outpost_button.tooltip_text = "重新选择分基地部署位置；未开始施工前可取消。" if selected_deployment else "工程兵部署分基地 · $%d · 现场施工逐步付款\n%s" % [int(sim.data_for(outpost_spec).cost), sim.availability(0, outpost_spec, engineer)]
	refresh_transport_controls()
	cancel_build_button.visible = tab in ["build", "defense"] and not bo.is_empty()
	unit_cancel_button.visible = tab not in ["build", "defense"] and producer >= 0 and not sim.entities[producer].queue.is_empty()
	if tab not in ["build", "defense"]:
		order_label.text = queue_label.text
	order_label.tooltip_text = order_label.text
	order_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	refresh_queue_buttons(producer if tab not in ["build", "defense"] else -1)
	var visible_specs: Array[String] = ContextualProduction.visible_specs(sim, selection, tab)
	var key := tab + sim.factions[0] + str(visible_specs)
	if key != cache_key:
		cache_key = key
		rebuild_list()
	refresh_entry_progress()
	_fit_production()
	_fit_selection()
	if not sim.result.is_empty() and not menu.visible and not modal_catalog_visible():
		end_panel.hide()
		end_panel.get_child(1).get_node("Outcome").text = ("战役完成 · 无字桥补给线" if sim.result == "win" else "战役失败 · 总部失守") if sim.map.mode == "campaign" else {"win":"胜利 · 战场归你", "lose":"失败 · 基地失守", "draw":"平局 · 双方基地覆灭"}.get(sim.result, sim.result)
		end_panel.get_child(1).get_node("Stats").text = "作战时间 %02d:%02d\n剩余资金 %d · 存活单位 %d\n%s" % [int(sim.time)/60, int(sim.time)%60, int(sim.money[0]), n.x, "补给线已恢复，正典军团守住东岸。" if sim.map.mode == "campaign" and sim.result == "win" else "双方按相同经济和战斗规则结算"]

func selection_text() -> String:
	if selection.is_empty(): return ("指挥提示：主基地可立即训练步兵和工兵；选工兵搭建建筑。" if sim.rules.factions.get(sim.factions[0], {}).get("building_method", "") == "engineer" else "指挥提示：先建设电站，再建设精炼厂与兵营。") + "\n左键选择 / 拖框 · 右键行动 · WASD 平移 · 滚轮缩放"
	var valid: Array = []
	for id in selection:
		if sim.entities.has(id): valid.append(sim.entities[id])
	if valid.is_empty(): return "选中对象已消失"
	var command_ids: Array = sim.selection_ids(selection)
	if command_ids.size() == 1 and int(valid[0].get("squad_capacity", 1)) > 1:
		var leader: Dictionary = sim.entities[command_ids[0]]
		var info: Dictionary = sim.data_for(leader.spec)
		var squad_members: Array = sim.squad_members(int(leader.id)).filter(func(member): return int(leader.team) == 0 or sim.entity_visible_to(0, int(member)))
		var hp: float = 0.0
		var maximum: float = 0.0
		for member_id in squad_members:
			hp += float(sim.entities[member_id].hp)
			maximum += sim.max_hp(sim.entities[member_id])
		return tr("%s · %s\n成员 %d/%d · HP %d/%d\n独立生命 · 单队指挥\n%s") % [tr(str(info.name)), tr("狙击小队" if info.get("squad_role", "") == "sniper" else "步兵小队"), squad_members.size(), int(leader.squad_capacity), int(hp), int(maximum), tr(UnitBrief.role(sim.rules, info))]
	if valid.size() > 1:
		var aircraft: int = valid.filter(func(item): return str(sim.data_for(item.spec).get("domain", "ground")) == "air").size()
		var ships: int = valid.filter(func(item): return str(sim.data_for(item.spec).get("domain", "ground")) == "naval").size()
		return tr("已选中 %d 个操控对象 · %d 名成员%s%s\nZ 进攻移动 · X 停止 · Shift 追加") % [command_ids.size(), valid.size(), " · 飞机 %d" % aircraft if aircraft > 0 else "", " · 舰艇 %d" % ships if ships > 0 else ""]
	var e: Dictionary = valid[0]
	var d: Dictionary = sim.data_for(e.spec)
	var owner_text: String = entity_owner_text(e)
	var stats: String = "HP %d / %d" % [int(e.hp), int(sim.max_hp(e))]
	if bool(e.get("veteran",false)):stats+=" · ★ 星级"
	var state: String = {"idle":"待命", "move":"行进", "force_move":"强制移动", "attack":"开火", "force_attack":"强制攻击", "unreachable":"暂不可达", "build":"施工中", "construct":"现场施工", "repair":"现场维修", "service":"厂内维修", "harvest":"采矿", "blocked":"等待让路", "repair_unit":"现场维修", "repair_building":"修复建筑", "repair_bridge":"修桥", "capture":"占领建筑", "deploy_outpost":"前往搭建", "resume_outpost":"现场施工", "board":"前往上车", "waiting":"等待", "waiting_rail":"等待铁路连接", "waiting_exit":"等待出厂", "emerging":"正在出厂", "unload":"卸矿", "parked":"停机待命", "rearm":"机场整备", "emp":"EMP失控"}.get(e.state, e.state)
	var service_job: Dictionary = e.get("refinery_docking", {})
	if service_job.get("mode", "") == "repair":
		if e.state == "unload": state = "驶出修理厂" if service_job.get("phase", "") in ["exit", "clear"] else "进入修理厂"
		elif e.state == "waiting_exit": state = "等待厂门开启"
	if e.state == "rescue": state = "拖救护送"
	if e.has("construction") and float(e.construct_remaining)>0.0:
		var construction:Dictionary=e.construction
		var work_state:String={"working":"施工中","repairing":"修复脚手架","paused":"施工暂停"}.get(str(construction.get("work_state","paused")),"施工暂停")
		var reason:String=str(construction.get("pause_reason",""))
		if not reason.is_empty():work_state=reason
		var builder:int=int(construction.get("builder",-1))
		return "%s · 施工 %d%%\n%s · HP %d/%d\n%s · 已付 $%d/%d\n维修 $%d · 工兵可右键接手" % [str(d.name),int(float(construction.get("progress",0.0))*100.0),work_state,int(e.hp),int(d.hp),"工兵 #%d" % builder if sim.entities.has(builder) else "等待工兵",int(construction.get("spent",0.0)),int(d.cost),int(construction.get("repair_spent",0.0))]
	if e.kind == "unit":
		if str(d.get("domain", "ground")) == "naval":
			state = {"idle": "海上待命", "move": "航行", "attack": "海上交战", "waiting": "等待靠岸 / 登陆", "unreachable": "航道暂不可达"}.get(str(e.state), state)
		if str(d.get("domain", "ground")) == "air":
			stats += " · 永久留空 / 无需补弹" if bool(d.get("permanent_air",false)) else " · 弹药 %d/%d" % [int(e.get("ammo", 0)), int(d.get("ammo_capacity", 0))]
			state = {"airborne":"空中巡航", "returning":"返航补给", "rearming":"机场补给维修", "stranded":"等待可用机场", "landed":"已降落"}.get(str(e.get("flight_state", "airborne")), "飞行")
			if str(e.get("flight_state", "")) == "rearming": state += " · 剩余 %.1f秒" % float(e.get("rearm_remaining", 0.0))
			if e.state == "parked": state = "停机装卸 · 下达移动命令起飞"
		elif d.get("art", "") == "harvester": stats += " · 货物 %d/%d" % [int(e.get("cargo", 0)), int(sim.rules.economy.harvester_capacity)]
		elif int(d.get("transport_capacity", 0)) > 0: stats += " · 搭载 %d/%d" % [e.get("passengers", []).size(), int(d.transport_capacity)]
		elif d.get("art", "") == "engineer" and int(e.team) == 0:state += " · 修满 / 修桥 / 占领 / " + ("建筑施工" if sim.rules.factions.get(sim.factions[0], {}).get("building_method", "") == "engineer" else "分基地")
		elif d.get("has_turret", false): state += " · 炮塔独立 · " + ("行进射击" if bool(d.get("fire_while_moving", true)) else "停稳射击")
		if int(d.get("transport_capacity", 0)) > 0 and str(d.get("domain", "ground")) == "air": stats += " · 搭载 %d/%d" % [e.get("passengers", []).size(), int(d.transport_capacity)]
		if d.has("rescue_radius"): state += " · 右键受损友军护送撤离"
		elif d.has("repair_rate") and d.get("art", "") != "engineer": state += " · 右键受损载具维修"
		if d.has("designation_radius"):
			state += " · 标定 %s" % ("已锁定" if float(e.get("designation_progress", 0.0)) >= float(d.designation_track_time) else "追踪 %.1f秒" % float(e.get("designation_progress", 0.0)))
		if float(e.get("rescue_speed_scale", 1.0)) > 1.0: state += " · 拖救加速"
	else:
		if float(d.get("local_power", 0.0)) > 0.0: stats += " · 局部供电 %d / %.0f格" % [int(d.local_power), float(d.local_power_radius)]
		if sim.LocalPower.is_locally_powered(sim, e, sim.local_power_summary(int(e.team))): state += " · 局部供电"
		elif sim.building_low_power(e): state += " · 电力不足"
		if d.has("vision_radius"):stats+=" · 视野 %.0f" % float(d.vision_radius)
		state += " · 修理" + ("开启" if e.get("repairing", false) else "关闭")
		if str(d.get("role", "")) == "airfield": stats += " · 机位 %d/%d" % [airfield_occupancy(int(e.id)), int(d.get("aircraft_capacity", 0))]
		if str(d.get("role", "")) == "shipyard": state += " · 水侧出航 · 独立海军队列"
		if str(d.get("role", "")) == "repair": state += " · 受损装甲车右键入厂维修" if d.has("service_rate") else " · 范围 %.1f" % float(d.get("repair_radius", 0.0))
	var trait_state: String = TraitText.state_text(sim, e)
	if not trait_state.is_empty(): state = trait_state + " · " + state
	if bool(e.get("rail_waiting", false)): state = "等待铁路连接"
	if float(e.get("emp_until", 0.0)) > float(sim.time): state = "EMP失控 · 剩余 %.1f秒" % (float(e.emp_until) - float(sim.time))
	var brief: String = "\n" + UnitBrief.summary(sim, e) if e.kind == "unit" else ""
	return "%s · %s\n%s%s\n%s" % [str(d.name), faction_name(e), stats, brief, state]

func selected_building() -> int:
	if sim == null: return -1
	for id in selection:
		if sim.entities.has(id):
			var e: Dictionary = sim.entities[id]
			if e.team == 0 and e.kind == "building": return id
	return -1

func selected_engineer() -> int:
	if sim == null:return -1
	for id in selection:
		if sim.entities.has(id):
			var e:Dictionary=sim.entities[id]
			if int(e.team)==0 and e.kind=="unit" and int(e.get("transport_id",-1))<0 and sim.data_for(e.spec).get("art","")=="engineer":return int(id)
	return -1

func refresh_transport_controls() -> void:
	var state: Dictionary = TransportCommands.menu_state(sim, selection)
	transport_button.disabled = not bool(state.enabled)
	transport_caption.text = "装载/卸载"
	transport_button.tooltip_text = "选择己方运输机、运输船或载客车辆以装载/卸载步兵；也可先选步兵，再指定运输载具。"
	if int(state.capacity) > 0:
		transport_button.tooltip_text += "\n搭载 %d/%d · 可用空位 %d；包括工程兵和反甲兵。" % [int(state.passengers), int(state.capacity), int(state.seats)]
	transport_menu.set_item_text(0, "装载 · 空位 %d" % int(state.seats) if int(state.capacity) > 0 else "装载 · 指定运输载具")
	transport_menu.set_item_disabled(0, not bool(state.load))
	transport_menu.set_item_text(1, "卸载 · %d 人 · 指定地点 U" % int(state.passengers))
	transport_menu.set_item_disabled(1, not bool(state.unload))
	if not bool(state.enabled): transport_menu.hide()

func show_transport_menu() -> void:
	if sim == null: return
	refresh_transport_controls()
	if transport_button.disabled: return
	transport_menu.reset_size()
	var origin: Vector2 = transport_button.get_screen_position()
	var button_width: float = transport_button.size.x
	if transport_menu.is_embedded():
		var transform: Transform2D = get_viewport().get_final_transform()
		origin = transform * transport_button.get_global_rect().position
		button_width = transform.basis_xform(transport_button.size).x
	transport_menu.position = Vector2i(origin - Vector2(transport_menu.size.x - button_width, transport_menu.size.y + 4))
	transport_menu.popup()

func production_building(spec_id: String = "") -> int:
	if sim == null: return -1
	var required: String = str(sim.data_for(spec_id).get("producer", "")) if not spec_id.is_empty() else {"infantry": "barracks", "vehicle": "factory", "air": "airfield", "naval": "shipyard"}.get(tab, "")
	for id in selection:
		if _producer_usable(int(id), required): return int(id)
	return -1

func _producer_usable(id: int, required: String) -> bool:
	if required.is_empty() or not sim.entities.has(id): return false
	var e: Dictionary = sim.entities[id]
	if int(e.team) != 0 or e.kind != "building" or float(e.hp) <= 0.0 or float(e.construct_remaining) > 0.0: return false
	var info: Dictionary = sim.data_for(e.spec)
	if not sim.TechAvailability.producer_matches(sim, e, required): return false
	return true

func select_catalog(category: String) -> void:
	if sim == null or category not in ContextualProduction.categories(sim, selection): return
	tab = category
	cache_key = ""
	queue_cache = ""
	if sim != null:
		rebuild_list()
		refresh_entry_progress()
	for name in category_buttons: category_buttons[name].disabled = name == tab

func choose_construction_channel(channel: String) -> void:
	if sim == null or "build" not in ContextualProduction.categories(sim, selection) or channel not in ["normal", "defense"]: return
	select_catalog("defense" if channel == "defense" else "build")
	var order: Dictionary = sim.order_for_team(0, channel)
	if not order.is_empty() and bool(order.get("ready", false)):
		action.emit("build", {"spec": str(order.spec), "channel": channel})

func requirement_names(spec: Dictionary) -> String:
	var names: PackedStringArray = [CatalogText.tier_label(spec) + " · " + CatalogText.tier_description(spec)]
	for id in spec.get("requires", []): names.append(str(sim.data_for(id).get("name",id)))
	return "；".join(names)

func rebuild_list() -> void:
	if sim == null: return
	for c in list_box.get_children():
		list_box.remove_child(c)
		c.queue_free()
	entry_widgets.clear()
	var action_kind := "build" if tab in ["build", "defense"] else "produce"
	for spec: String in ContextualProduction.visible_specs(sim, selection, tab):
		var d: Dictionary = sim.data_for(spec)
		var sid: String = spec
		var category_channel: String = "defense" if tab == "defense" else "normal"
		var b := button("", func(): action.emit(action_kind, {"spec": sid, "channel": category_channel} if action_kind == "build" else sid))
		b.mouse_force_pass_scroll_events = false
		b.gui_input.connect(_build_scroll_input)
		b.custom_minimum_size = Vector2(110, 120)
		b.add_theme_font_size_override("font_size", 11)
		b.tooltip_text = spec_tooltip(d)
		if sim.rules.buildings.has(spec) and sim.TechAvailability.engineer_building(sim, 0, d):b.tooltip_text += "\n点击立即选址；工兵抵达后搭起脚手架，随施工进度付款；重锤通过新兵营扩张基地建设范围。\n受损后先维修再继续施工；工兵阵亡则暂停，其他工兵可右键接手，也可选中脚手架拆除。"
		if d.get("role", "") in ["wall", "barricade"]:
			b.tooltip_text += "\n沿已有围墙 / 拒马直线延伸 1–6 格，每格 $%d" % d.cost
			b.tooltip_text += "\n步兵以 35% 速度穿越；车辆无法通过" if d.role == "barricade" else "\n阻挡步兵和车辆"
		if d.get("role", "") == "rail": b.tooltip_text += "\n沿己方铁路批量铺设1–6格；非法连接、间距或闭环会显示原因。铁路只供所属玩家使用。"
		if d.get("role", "") == "rail_junction": b.tooltip_text += "\n三向岔道；建造预览按R旋转90°。禁止岔道相邻、第四端口与网络闭环。"
		var art_path: String = str(d.get("animations", {}).get("idle", ""))
		var picture: TextureRect = null
		if ResourceLoader.exists(art_path):
			picture = TextureRect.new()
			picture.texture = load(art_path)
			if str(d.get("art","")) in VolumeModels.INFANTRY_ART or art_path.get_extension().to_lower() == "png": picture.material = OwnerPortrait.make(art_path,0)
			picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			picture.offset_left = 9
			picture.offset_right = -9
			picture.offset_top = 11
			picture.offset_bottom = -36
			picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(picture)
		var tier_text := label(CatalogText.tier_label(d), 12)
		tier_text.name = "TechTier"
		tier_text.position = Vector2(6, 18)
		tier_text.add_theme_color_override("font_color", INK)
		tier_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(tier_text)
		var name_text := label(production_name(d), 11)
		name_text.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		name_text.offset_left = 5
		name_text.offset_right = -5
		name_text.offset_top = -35
		name_text.offset_bottom = -18
		name_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(name_text)
		var price_text := label("$%d" % purchase_cost(d), 11)
		price_text.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		price_text.offset_left = 5
		price_text.offset_right = -5
		price_text.offset_top = -20
		price_text.offset_bottom = -3
		price_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		price_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(price_text)
		list_box.add_child(b)
		var progress := ProgressBar.new()
		progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
		progress.show_percentage = false
		progress.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		progress.offset_left = 13
		progress.offset_right = -13
		progress.offset_top = 8
		progress.offset_bottom = 14
		progress.add_theme_stylebox_override("background", progress_style(Color("645740")))
		progress.add_theme_stylebox_override("fill", progress_style(Color("76a044")))
		b.add_child(progress)
		entry_widgets[spec] = {"button": b, "progress": progress, "name_label": name_text, "price_label": price_text, "tier_label": tier_text, "picture": picture, "text": production_name(d), "ready": false, "locked": false}
	_catalog_width = minf(840.0, maxf(440.0, float(entry_widgets.size()) * 110.0 + float(maxi(0, entry_widgets.size() - 1)) * 5.0 + 14.0))
	_fit_production()
	refresh_entry_progress()

func refresh_queue_buttons(producer:int) -> void:
	var orders:Array=[] if producer<0 else sim.entities[producer].queue
	var key:String=str(producer)+str(orders.map(func(o):return o.spec))
	if key==queue_cache:return
	queue_cache=key
	queue_buttons.visible = not orders.is_empty()
	for child in queue_buttons.get_children():
		queue_buttons.remove_child(child)
		child.queue_free()
	for i in range(mini(4,orders.size())):
		var index:int=i
		var building:int=producer
		var b:=button("× %d" % (i+1),func():action.emit("cancel_queue",{"building":building,"index":index}))
		b.tooltip_text="取消第%d项 %s\n未开始全额退款；进行中按剩余比例退款。" % [i+1,sim.data_for(orders[i].spec).name]
		b.custom_minimum_size = Vector2(31, 23)
		b.add_theme_font_size_override("font_size", 10)
		queue_buttons.add_child(b)

func progress_style(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_border_width_all(0)
	box.set_corner_radius_all(1)
	return box

func refresh_entry_progress() -> void:
	if sim == null:return
	var order: Dictionary = sim.order_for_team(0, "defense" if tab == "defense" else "normal") if tab in ["build", "defense"] else {}
	var producer: int = production_building()
	if tab not in ["build", "defense"] and producer >= 0 and not sim.entities[producer].queue.is_empty():
		order = sim.entities[producer].queue[0]
	for spec in entry_widgets:
		var entry: Dictionary = entry_widgets[spec]
		var active: bool = not order.is_empty() and order.spec == spec
		var ready: bool = active and bool(order.get("ready",false))
		entry.progress.visible = active
		entry.progress.value = 100.0 if ready else (float(order.get("progress",0.0))*100.0 if active else 0.0)
		entry.name_label.text = entry.text
		var card_producer: int = production_building(spec) if tab not in ["build", "defense"] else -1
		var card_builder: int = selected_engineer() if sim.rules.buildings.has(spec) and sim.TechAvailability.engineer_building(sim, 0, sim.data_for(spec)) else -1
		var reason: String = sim.availability(0, spec, card_builder, card_producer)
		var locked: bool = not ready and not reason.is_empty()
		entry.button.disabled = locked
		entry.button.tooltip_text = spec_tooltip(sim.data_for(spec)) + ("\n" + reason if not reason.is_empty() and not ready else "")
		entry.price_label.text = ("选址 · 无需预付" if int(order.get("builder",-1))>=0 else ("就绪 · 放置" if tab in ["build", "defense"] else "等待出口")) if ready else "$%d" % sim.production_cost(spec)
		if ready and tab not in ["build","defense"] and producer >= 0: entry.price_label.text = "等待铁路连接" if bool(sim.entities[producer].get("rail_waiting",false)) else "等待出厂"
		if tab not in ["build", "defense"] and producer >= 0:
			var copies: int = 0
			for queued in sim.entities[producer].queue:
				if queued.spec == spec: copies += 1
			if copies > 0: entry.price_label.text += "  ×%d" % copies
		if locked:
			var status: String = "资金不足" if reason == "资金不足" else ("机位已满" if reason.contains("机位") else ("数量已满" if reason.contains("英雄") else ("前置不足" if reason.begins_with("缺少") else "队列忙")))
			entry.price_label.text = status + " · $%d" % sim.production_cost(spec)
		if ready != entry.ready or locked != entry.locked:
			entry.ready = ready
			entry.locked = locked
			var paper: Control = entry.button.get_child(0)
			paper.paper_color = Color("ded3aa") if ready else PAPER.lightened(0.025)
			paper.ink = BLUE if ready else INK
			paper.queue_redraw()
			if entry.picture != null: entry.picture.modulate = Color.WHITE
			entry.name_label.add_theme_color_override("font_color", RED if locked else (BLUE if ready else INK))
			entry.price_label.add_theme_color_override("font_color", RED if locked else (BLUE if ready else INK))
			entry.progress.add_theme_stylebox_override("fill", progress_style(Color("8ebc68") if ready else Color("76a044")))

func _build_scroll_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN,MOUSE_BUTTON_WHEEL_LEFT,MOUSE_BUTTON_WHEEL_RIGHT]:
		build_scroll.scroll_horizontal += 90 * (1 if event.button_index in [MOUSE_BUTTON_WHEEL_DOWN,MOUSE_BUTTON_WHEEL_RIGHT] else -1)
		get_viewport().set_input_as_handled()

func blocks_world_scroll(screen: Vector2) -> bool:
	if modal_catalog_visible():return true
	for panel in ui_panels:
		if panel.is_visible_in_tree() and panel.get_global_rect().has_point(screen):return true
	return false

# One detailed definition feeds production cards and selected-object tooltips.
func purchase_cost(d: Dictionary) -> int:
	return int(d.cost) * int(d.get("squad_size", 1))

func production_name(d: Dictionary) -> String:
	var members: int = int(d.get("squad_size", 1))
	return tr("%s · %d人小队") % [tr(str(d.name)), members] if members > 1 else str(d.name)

func spec_tooltip(d: Dictionary) -> String:
	var lines: PackedStringArray = [str(d.get("formal_name", d.get("name", ""))), str(d.get("description", ""))]
	if d.has("speed"):
		lines.append("定位：" + UnitBrief.role(sim.rules,d))
		lines.append(CatalogText.veteran_kill_experience_text(sim.rules))
	lines.append_array(TraitText.spec_lines(sim.rules, d))
	var members: int = int(d.get("squad_size", 1))
	lines.append(tr("造价 $%d · %s %s秒 · 生命 %d") % [purchase_cost(d), tr("现场施工" if d.get("role","")=="outpost" else "生产"), str(d.get("squad_build_time", float(d.build_time) * members)), int(d.hp)])
	if members > 1:
		lines.append(tr("小队编制 %d 人 · 每人 $%d · 每人生命 %d") % [members, int(d.cost), int(d.hp)])
		lines.append(tr("整队生产与指挥；每名成员独立承受伤害。"))
	if d.has("vision_radius"):lines.append("视野半径 %.0f格" % float(d.vision_radius))
	if d.has("armor"):lines.append("护甲 %.0f" % float(d.armor))
	if d.has("role"):lines.append("建造预览：R每次旋转90°，仅四个直角朝向。")
	if d.has("speed"): lines.append("移动速度 %.1f · %s单位" % [float(d.speed), CatalogText.domain_name(str(d.get("domain", "ground")))])
	var weapon: Dictionary = sim.rules.weapons.get(str(d.get("weapon", "")), {})
	if not weapon.is_empty():
		if weapon.get("trajectory", "") == "gravity_bomb": lines.append("主武器 · 短程自由落体炸弹：飞临目标附近后从吊舱向下投放，受重力下落。")
		lines.append("伤害 %.0f · 射程 %.1f · 间隔 %.2f秒 · 攻击%s" % [float(weapon.damage), float(weapon.range), float(weapon.interval), CatalogText.target_names(weapon.get("targets", weapon.get("target_domains", ["ground"])))])
		if weapon.has("penetration"): lines.append("穿透 %.0f · %s" % [float(weapon.penetration), CatalogText.penetration_rule_text(sim.rules, true)])
		if float(weapon.get("blast", 0.0)) > 0: lines.append(("范围伤害 %.1f格 · 注意友军位置" if bool(weapon.get("friendly_fire",true)) else "范围伤害 %.1f格 · 仅伤害敌军") % float(weapon.blast))
	var secondary: Dictionary = sim.rules.weapons.get(str(d.get("secondary_weapon", "")), {})
	if not secondary.is_empty():
		lines.append("独立副武器 · 背部机枪：伤害 %.0f · 射程 %.1f格 · 间隔 %.2f秒 · 射速 %.2f发/秒 · 攻击%s" % [float(secondary.damage), float(secondary.range), float(secondary.interval), 1.0 / maxf(.001, float(secondary.interval)), CatalogText.target_names(secondary.get("targets", ["ground"]))])
		lines.append("机枪独立转向瞄准，可与主武器同时开火，不消耗炸弹弹药。")
	if bool(d.get("permanent_air",false)):lines.append("永久留空，无需降落和补充弹药。")
	if d.has("ammo_capacity") and not bool(d.get("permanent_air",false)): lines.append(("主武器弹药" if not secondary.is_empty() else "弹药") + " %d · 机场补给 %s秒 · 弹尽自动返航" % [int(d.ammo_capacity), str(d.get("rearm_time", 0))])
	if d.has("aircraft_capacity"): lines.append("飞机容量 %d（包含生产队列预留）" % int(d.aircraft_capacity))
	if int(d.get("transport_capacity", 0)) > 0: lines.append(CatalogText.transport_instructions(d))
	if d.get("role", "") == "shipyard": lines.append(CatalogText.shipyard_instructions())
	if d.has("repair_radius"): lines.append("维修半径 %.1f · 每秒恢复 %.0f生命 · 按恢复生命付费" % [float(d.repair_radius), float(d.get("repair_rate", 0))])
	if d.has("service_rate"): lines.append("选中受损地面装甲载具，右键本厂进入维修；每秒恢复 %.0f生命，按实际恢复生命付费。需要供电；飞机使用机场，舰船使用海上维修。" % float(d.service_rate))
	if d.has("unlocks_tier"): lines.append("完工后解锁 T%d 科技。" % int(d.unlocks_tier))
	if d.has("rescue_radius"): lines.append("右键友方受损载具护送；生命≤60%%且撤离时，范围%.1f内移动速度+%.0f%%，不叠加" % [float(d.rescue_radius), float(d.rescue_speed_bonus)*100.0])
	if d.has("designation_radius"): lines.append("范围%.1f内持续视线追踪%.1f秒，己方对该地面载具伤害+%.0f%%；失去视线即失效" % [float(d.designation_radius), float(d.designation_track_time), float(d.damage_bonus)*100.0])
	if d.has("aircraft_repair_rate"): lines.append("返航停机飞机每秒维修%.0f生命，按恢复生命付费" % float(d.aircraft_repair_rate))
	if float(d.get("power", 0)) != 0: lines.append("电力 %s%d" % ["+" if int(d.power) > 0 else "", int(d.power)])
	if float(d.get("vision_bonus", 0)) != 0: lines.append("己方索敌范围 +%.1f" % float(d.vision_bonus))
	if d.has("counters"): lines.append("适合：" + _detail_list(d.counters))
	if d.has("weaknesses"): lines.append("弱点：" + _detail_list(d.weaknesses))
	elif d.has("weakness"): lines.append("弱点：" + _detail_list(d.weakness))
	lines.append("科技前置：" + requirement_names(d))
	return "\n".join(lines)

func _detail_list(value: Variant) -> String:
	if value is Array or value is PackedStringArray:
		var parts: PackedStringArray = []
		for item in value: parts.append(str(item))
		return "、".join(parts)
	return str(value)

func selection_details() -> String:
	var lines: PackedStringArray = []
	if sim.selection_ids(selection).size() == 1 and not selection.is_empty() and int(sim.entities[selection[0]].get("squad_capacity", 1)) > 1:
		for member in sim.squad_members(int(selection[0])):
			if int(sim.entities[member].team) != 0 and not sim.entity_visible_to(0, int(member)): continue
			var soldier: Dictionary = sim.entities[member]
			lines.append(tr("成员 %d · HP %d/%d") % [int(soldier.get("squad_slot", 0)) + 1, int(soldier.hp), int(sim.max_hp(soldier))])
		return selection_text() + "\n\n" + "\n".join(lines)
	for id in sim.selection_ids(selection):
		if sim.entities.has(id):
			lines.append(spec_tooltip(sim.data_for(sim.entities[id].spec)))
			if lines.size() >= 4: break
	return selection_text() + "\n\n" + "\n\n".join(lines)

func entity_owner_text(entity: Dictionary) -> String:
	var team: int = int(entity.get("team", -1))
	if team < 0: return "中立势力 · 中立"
	var slots: Array = sim.match_options.get("slots", [])
	var owner: String = str(slots[team].get("name", "玩家 %d" % (team + 1))) if team < slots.size() else "玩家 %d" % (team + 1)
	return "%s · %s" % [owner, "己方" if team == 0 else "敌对"]

func faction_name(entity: Dictionary) -> String:
	var info: Dictionary = sim.data_for(str(entity.spec))
	return str(sim.rules.factions.get(str(info.get("faction", "")), {}).get("name", "中立"))

func entity_identity(id: int) -> String:
	if sim == null or not sim.entities.has(id) or not sim.entity_visible_to(0, id): return ""
	var e: Dictionary = sim.entities[id]
	return "%s\n%s · %s" % [entity_owner_text(e), str(sim.data_for(e.spec).name), faction_name(e)]

func show_entity_hover(id: int, pointer: Vector2) -> void:
	var identity := entity_identity(id)
	hover_panel.visible = not identity.is_empty() and is_started and not modal_catalog_visible()
	if not hover_panel.visible: return
	var lines := identity.split("\n", true, 1)
	hover_owner.text = lines[0]
	hover_owner.add_theme_color_override("font_color", BLUE if int(sim.entities[id].team) == 0 else RED)
	hover_detail.text = lines[1]
	var extent: Vector2 = get_viewport().get_visible_rect().size
	hover_panel.position = (pointer + Vector2(18, 20)).clamp(Vector2(8, 8), extent - hover_panel.size - Vector2(8, 8))

func refresh_groups(groups: Dictionary) -> void:
	if sim == null:
		group_panel.hide()
		return
	var records: Dictionary = {}
	var active_count := 0
	for number in range(1, 7):
		var counts: Dictionary = {}
		for id in sim.selection_ids(groups.get(number, [])):
			if not sim.entities.has(id) or int(sim.entities[id].team) != 0 or sim.entities[id].kind != "unit" or float(sim.entities[id].hp) <= 0: continue
			var spec: String = str(sim.entities[id].spec)
			counts[spec] = int(counts.get(spec, 0)) + 1
		records[number] = counts
		if not counts.is_empty(): active_count += 1
	group_panel.visible = active_count > 0 and is_started and not modal_catalog_visible()
	var key := str(records)
	if key == group_key: return
	group_key = key
	for number in range(1, 7):
		var parts: PackedStringArray = []
		var counts: Dictionary = records[number]
		for spec: String in counts:
			var info: Dictionary = sim.data_for(spec)
			var symbol: String = "✈" if info.get("domain", "ground") == "air" else "⚓" if info.get("domain", "ground") == "naval" else "◇" if info.get("art", "") in ["rifle", "anti", "engineer", "demolition"] else "▰"
			parts.append("%s %s ×%d" % [symbol, production_name(info), int(counts[spec])])
		var row: Button = group_rows[number]
		row.visible = not counts.is_empty()
		row.text = ""
		row.tooltip_text = "编队 %d\n%s\n按 %d 选中；Ctrl + %d 覆盖。单位可加入多个编队。" % [number, "\n".join(parts), number, number]
		row.set_meta("composition", " / ".join(parts))
		# Keep the button's paper decoration; replace only its composition.
		for child in row.get_children():
			if child.name == "Composition":
				row.remove_child(child)
				child.queue_free()
		if not counts.is_empty():
			var content := HFlowContainer.new()
			content.name = "Composition"
			content.mouse_filter = Control.MOUSE_FILTER_IGNORE
			content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			content.offset_left = 5; content.offset_right = -5
			content.add_theme_constant_override("h_separation", 3)
			row.add_child(content)
			content.add_child(label(str(number), 12))
			for spec: String in counts:
				var item := HBoxContainer.new()
				item.mouse_filter = Control.MOUSE_FILTER_IGNORE
				item.add_theme_constant_override("separation", 1)
				content.add_child(item)
				var info: Dictionary = sim.data_for(spec)
				var icon_path: String = str(info.get("portrait", info.get("animations", {}).get("idle", "")))
				var portrait := TextureRect.new()
				portrait.custom_minimum_size = Vector2(24, 26)
				portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
				portrait.texture = load(icon_path) if not icon_path.is_empty() and ResourceLoader.exists(icon_path) else null
				if str(info.get("art","")) in VolumeModels.INFANTRY_ART or icon_path.get_extension().to_lower() == "png": portrait.material = preload("res://scripts/owner_portrait_material.gd").make(icon_path,0)
				item.add_child(portrait); item.add_child(label("×%d" % int(counts[spec]), 10))
		row.custom_minimum_size.y = 30 if counts.size() <= 5 else 58
	var height := 30.0
	for number in range(1,7):
		if group_rows[number].visible: height += group_rows[number].custom_minimum_size.y + 2
	group_panel.offset_bottom = group_panel.offset_top + height

func refresh_base_markers(records: Array[Dictionary]) -> void:
	for child in base_marker_layer.get_children(): child.queue_free()
	if not is_started or modal_catalog_visible(): return
	for record: Dictionary in records:
		var marker := label(str(record.text), 12)
		marker.position = record.pos - Vector2(38, 42)
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marker.add_theme_color_override("font_color", Color("f6eccb"))
		marker.add_theme_color_override("font_shadow_color", INK)
		marker.add_theme_constant_override("shadow_offset_x", 1)
		marker.add_theme_constant_override("shadow_offset_y", 1)
		base_marker_layer.add_child(marker)

func show_placement_reason(reason: String, role: String, rotation: int) -> void:
	placement_label.visible = not role.is_empty() and is_started and not modal_catalog_visible()
	placement_label.text = reason if not reason.is_empty() else "可放置"
	if role == "rail": placement_label.text += " · 沿已铺铁路直线延伸 1–6 格"
	placement_label.text += " · R 旋转90° · 朝向%d°" % (posmod(rotation,4)*90)
	if role in ["rail","rail_junction"]:placement_label.text += " · 按当前铁路方向延伸"

func airfield_occupancy(id: int) -> int:
	return sim._airfield_load(id)

func selected_faction() -> String:
	return str(faction_option.get_item_metadata(faction_option.selected))

func selected_map() -> String:
	return str(map_option.get_item_metadata(map_option.selected))

func set_debug_available(enabled:bool) -> void:
	debug_menu_enabled=enabled
	if map_option==null:return
	var previous:String=selected_map() if map_option.item_count>0 else "forest"
	map_option.clear()
	for item in Battlefields.entries():
		if item.id=="dev" and not enabled:continue
		map_option.add_item("%s · %d×%d" % [item.name,item.size,item.size])
		map_option.set_item_metadata(map_option.item_count-1,item.id)
	select_map(previous)

func select_map(id:String) -> void:
	id=Battlefields.selectable_mode(id,debug_menu_enabled)
	for index in map_option.item_count:
		if str(map_option.get_item_metadata(index))==id:
			map_option.select(index)
			if match_setup != null: match_setup.set_map(id)
			_request_map_preview()
			return

func select_faction(id: String) -> void:
	for index in faction_option.item_count:
		if str(faction_option.get_item_metadata(index)) == id:
			faction_option.select(index)
			_refresh_faction_cards()
			return

func _refresh_faction_cards() -> void:
	var chosen := selected_faction()
	for index in faction_option.item_count:
		var id := str(faction_option.get_item_metadata(index))
		var card: Button = faction_buttons[id]
		var selected := id == chosen
		card.set_pressed_no_signal(selected)
		card.text = ("✓ " if selected else "") + faction_option.get_item_text(index).replace("  ·  ", "\n")
		var paper: PaperUI = card.get_child(0)
		paper.paper_color = Color("ecd092") if selected else PAPER.lightened(0.025)
		paper.ink = BLUE if selected else INK
		paper.queue_redraw()

func show_voice(text: String, duration: float) -> void:
	voice_label.text = text
	voice_timer = maxf(2.5, duration)
	voice_label.visible = not text.is_empty()

func _process(delta: float) -> void:
	if voice_timer > 0.0:
		voice_timer -= delta
		if voice_timer <= 0.0: voice_label.hide()


func _queue_production_fit() -> void:
	call_deferred("_fit_production")

func _fit_selection() -> void:
	if selection_panel == null: return
	selection_panel.offset_top = selection_panel.offset_bottom - selection_panel.get_combined_minimum_size().y

func refresh_selection_portrait() -> void:
	var command_ids: Array = sim.selection_ids(selection) if sim != null else []
	selection_header.visible = command_ids.size() == 1
	if command_ids.size() != 1:
		selection_portrait_frame.hide()
		selection_portrait.texture = null
		selection_portrait.material = null
		selection_portrait_spec = ""
		selection_portrait_team = -1
		_selection_portrait_key = ""
		return
	var entity: Dictionary = sim.entities[command_ids[0]]
	var definition: Dictionary = sim.data_for(str(entity.spec))
	var path: String = str(definition.get("portrait", definition.get("animations", {}).get("idle", "")))
	if not ResourceLoader.exists(path): path = str(definition.get("animations", {}).get("idle", ""))
	selection_portrait_frame.visible = ResourceLoader.exists(path)
	if not selection_portrait_frame.visible:
		selection_portrait.texture = null
		selection_portrait.material = null
		selection_portrait_spec = ""
		selection_portrait_team = -1
		_selection_portrait_key = ""
		return
	var team: int = int(entity.team)
	var owner_color: Color = VolumeModels.player_color(team)
	var key: String = str(entity.spec) + "/" + path + "/" + str(team) + "/" + owner_color.to_html()
	if key == _selection_portrait_key: return
	_selection_portrait_key = key
	selection_portrait_spec = str(entity.spec)
	selection_portrait_team = team
	selection_portrait.texture = load(path)
	selection_portrait.material = OwnerPortrait.make(path, team)
	selection_portrait_frame.add_theme_stylebox_override("panel", style(CREAM.lightened(.04), owner_color, 2))
	selection_portrait_frame.tooltip_text = str(definition.get("formal_name", definition.get("name", "")))

func _fit_production() -> void:
	if _fitting_production or production_panel == null or minimap_panel == null or command_panel == null or build_scroll == null: return
	_fitting_production = true
	var screen_width: float = get_viewport().get_visible_rect().size.x
	var left: float = minimap_panel.get_global_rect().end.x + 12.0
	var right: float = command_panel.get_global_rect().position.x - 12.0
	var width: float = minf(_catalog_width, maxf(440.0, right - left))
	var center: float = clampf(screen_width * .5, left + width * .5, right - width * .5)
	production_panel.offset_left = center - screen_width * .5 - width * .5
	production_panel.offset_right = center - screen_width * .5 + width * .5
	for category: String in category_buttons:
		category_buttons[category].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var panel_margins: Vector2 = production_panel.get_theme_stylebox("panel").get_minimum_size()
	var cards: Vector2 = list_box.get_combined_minimum_size()
	var horizontal_overflow: bool = cards.x > width - panel_margins.x + .5
	var scrollbar_height: float = build_scroll.get_h_scroll_bar().get_combined_minimum_size().y if horizontal_overflow else 0.0
	build_scroll.custom_minimum_size.y = cards.y + scrollbar_height
	var height: float = panel_margins.y
	var visible_rows: int = 0
	for child: Control in production_column.get_children():
		if not child.visible: continue
		height += build_scroll.custom_minimum_size.y if child == build_scroll else child.get_combined_minimum_size().y
		visible_rows += 1
	height += maxi(0, visible_rows - 1) * production_column.get_theme_constant("separation")
	production_panel.offset_top = production_panel.offset_bottom - ceilf(height)
	_fitting_production = false
