extends Control
class_name MatchScoreboard

signal action(kind: String, value: Variant)
const INK := Color("392c21")
const CREAM := Color("efdfbf")
const FACTIONS := {"kestrel":"正典军团", "rivet":"重锤军团", "iron":"长钉军团", "sky":"天翼教团"}
const HistoryChart := preload("res://scripts/match_history_chart.gd")
const PLAYER_COLORS: Array[Color] = preload("res://scripts/player_palette.gd").COLORS
const MILITARY := [["units_killed","击杀部队"],["units_lost","损失部队"],["buildings_destroyed","摧毁建筑"],["buildings_lost","损失建筑"],["units_produced","生产部队"],["buildings_built","建成建筑"]]
const ECONOMY := [["funds_earned","资源收入"],["funds_spent","净投入"],["money_remaining","剩余资金"],["alive_units","存活部队"],["alive_buildings","存留建筑"],["damage_dealt","累计伤害"]]
const ANALYSIS := [["infantry_total","存活步兵"],["building_total","建筑总量"],["structures_complete","完工建筑"],["army_value","部队造价"],["building_value","建筑造价"],["sales_income","出售收入"]]
const OPERATIONS := [["infantry_produced","生产步兵"],["infantry_lost","损失步兵"],["peak_units","兵力峰值"],["peak_infantry","步兵峰值"],["low_power_seconds_sampled","低电时长 / 秒"],["zero_funds_seconds_sampled","缺钱时长 / 秒"]]
const EXTRA_METRICS := [["funds_earned","累计资源收入"],["funds_spent","累计净投入"],["alive_units","全部存活部队"],["army_value","存活部队总造价"],["damage_dealt","累计造成伤害"]]
var result_label: Label
var summary_label: Label
var tables: VBoxContainer
var menu_button: Button
var new_battle_button: Button
var quit_button: Button
var export_button: Button
var export_status: Label
var history_note: Label
var history_charts: Array[Control] = []
var extra_metric_tabs: TabBar
var extra_chart: Control
var displayed_stats: Dictionary = {}
var displayed_result := ""
var content_scroll: ScrollContainer
var font_correction := 1.0
var physical_body_font := 24.0
var _font_targets: Dictionary = {}
var _sheet: PanelContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events=false
	z_index=120
	var background:=ColorRect.new();background.color=Color("65523e")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(background)
	_sheet=PanelContainer.new();_sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sheet.offset_left=32;_sheet.offset_right=-32;_sheet.offset_top=24;_sheet.offset_bottom=-24
	_sheet.add_theme_stylebox_override("panel",_style(CREAM,28));add_child(_sheet)
	var page:=VBoxContainer.new();page.add_theme_constant_override("separation",18);_sheet.add_child(page)
	var header:=HBoxContainer.new();header.add_theme_constant_override("separation",24);page.add_child(header)
	result_label=_label("战局结算",48);result_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(result_label)
	var stamp:=_label("PAPER FRONT\n作战报告",22);stamp.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;header.add_child(stamp)
	# The game retains its single always-on FPS layer in the upper-right corner.
	var fps_space:=Control.new();fps_space.custom_minimum_size.x=100;header.add_child(fps_space)
	summary_label=_label("",23);summary_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;page.add_child(summary_label)
	content_scroll=ScrollContainer.new();content_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	content_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	content_scroll.mouse_force_pass_scroll_events=false;page.add_child(content_scroll)
	tables=VBoxContainer.new();tables.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	tables.add_theme_constant_override("separation",18);content_scroll.add_child(tables)
	var buttons:=HBoxContainer.new();buttons.add_theme_constant_override("separation",16);page.add_child(buttons)
	menu_button=_button("返回主菜单",func():_choose("entry_home"))
	new_battle_button=_button("新建战局",func():_choose("entry_play"))
	export_button=_button("导出统计",func():action.emit("export_statistics",null))
	quit_button=_button("退出游戏",func():_choose("quit"))
	for button:Button in [menu_button,new_battle_button,export_button,quit_button]:buttons.add_child(button)
	var footer:=HBoxContainer.new();page.add_child(footer)
	export_status=_label("战场已停止 · 可导出 JSON 与 CSV 统计供复盘分析",19)
	export_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	export_status.size_flags_horizontal=Control.SIZE_EXPAND_FILL;footer.add_child(export_status)
	resized.connect(_fit_typography)
	get_viewport().size_changed.connect(_fit_typography)
	_fit_typography();hide()

func show_result(stats: Dictionary, result: String) -> void:
	displayed_stats=stats.duplicate(true);displayed_result=result
	result_label.text={"win":"胜利","lose":"战败","draw":"平局"}.get(result,"战局结束")+"  /  作战结算"
	result_label.add_theme_color_override("font_color",Color("386b4a") if result=="win" else Color("a7563e") if result=="lose" else INK)
	var seconds:int=maxi(0,roundi(float(stats.get("duration",0))))
	summary_label.text="%s  ·  作战时间 %02d:%02d  ·  %d 方参战"%[BattlefieldCatalog.display_name(str(stats.get("map_mode",""))),seconds/60,seconds%60,stats.get("teams",[]).size()]
	if not bool(stats.get("history_complete",true)):summary_label.text+="  ·  从读取时开始统计"
	for child:Node in tables.get_children():tables.remove_child(child);child.queue_free()
	history_charts.clear()
	_build_history(stats)
	_table("战场表现",MILITARY,stats.get("teams",[]));_table("经济与留存",ECONOMY,stats.get("teams",[]))
	_table("复盘辅助 · 结束时兵力与资产",ANALYSIS,stats.get("teams",[]))
	_table("复盘辅助 · 生产与运转",OPERATIONS,stats.get("teams",[]))
	tables.add_child(_note("建筑总量包含施工中的建筑及轨道；存留建筑沿用原有口径。部队与建筑造价按当前存活对象统计。峰值与低电、缺钱时长按采样估计；缺钱指可用资金少于 1。"))
	show_export_status("战场已停止 · 可导出 JSON 与 CSV 统计供复盘分析",true)
	content_scroll.scroll_vertical=0;content_scroll.scroll_horizontal=0
	_fit_typography();show();menu_button.grab_focus()

func show_export_status(message: String, success: bool = true) -> void:
	export_status.text=message
	export_status.add_theme_color_override("font_color",INK if success else Color("a7563e"))
	export_status.tooltip_text=message

func _chart_players(stats: Dictionary) -> Array:
	var players: Array = stats.get("teams",[]).duplicate(true)
	var slots: Array=stats.get("metadata",{}).get("match_options",stats.get("match_options",{})).get("slots",[])
	for index: int in players.size():
		var row: Dictionary=players[index]
		var owner: int=int(row.get("team",index))
		row.chart_name="玩家 %d · %s"%[owner+1,FACTIONS.get(str(row.get("faction","")),str(row.get("faction","")))]
		var color: Color=PLAYER_COLORS[posmod(owner,PLAYER_COLORS.size())]
		if owner >= 0 and owner < slots.size():
			var html: String=str(slots[owner].get("color",""))
			if not html.is_empty() and Color.html_is_valid(html):color=Color.html(html)
		row.chart_color=color.darkened(0.30)
	return players

func _build_history(stats: Dictionary) -> void:
	tables.add_child(_label("战局曲线",30))
	var history: Array=stats.get("history",[])
	history_note=_label("",20)
	history_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	if history.is_empty():history_note.text="本局没有历史采样（旧存档可能只包含累计统计）。下方表格仍显示已记录的结果。"
	else:
		var interval: float=float(stats.get("history_interval_seconds",1.0))
		history_note.text="约每 %.0f 个游戏秒采样，包含开局与结算 · 横轴为游戏时间 · 鼠标移入查看实际采样值"%interval
		if not bool(stats.get("telemetry_history_complete",true)):
			history_note.text+="\n此存档的曲线从 %s 开始，之前没有时间采样。"%HistoryChart.format_time(float(stats.get("history_since_time",0.0)))
	tables.add_child(history_note)
	var players: Array=_chart_players(stats)
	_chart_card("资金余额","money_remaining",stats,players)
	_chart_card("建筑总量 · 含施工与轨道","building_total",stats,players)
	_chart_card("存活步兵总量","infantry_total",stats,players)
	var panel:=PanelContainer.new();panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL;panel.add_theme_stylebox_override("panel",_style(Color("f5e8cc"),16));tables.add_child(panel)
	var body:=VBoxContainer.new();body.add_theme_constant_override("separation",8);panel.add_child(body)
	body.add_child(_label("更多复盘曲线",26))
	extra_metric_tabs=TabBar.new();_font_targets[extra_metric_tabs]=22;extra_metric_tabs.add_theme_font_size_override("font_size",22)
	extra_metric_tabs.size_flags_horizontal=Control.SIZE_EXPAND_FILL;extra_metric_tabs.clip_tabs=true
	extra_metric_tabs.add_theme_stylebox_override("tab_selected",_style(Color("edd19b"),12))
	extra_metric_tabs.add_theme_stylebox_override("tab_unselected",_style(Color("f5e8cc"),12))
	extra_metric_tabs.add_theme_stylebox_override("tab_hovered",_style(Color("faedd0"),12))
	for state: String in ["font_selected_color","font_unselected_color","font_hovered_color"]:extra_metric_tabs.add_theme_color_override(state,INK)
	for field: Array in EXTRA_METRICS:extra_metric_tabs.add_tab(str(field[1]))
	body.add_child(extra_metric_tabs)
	body.add_child(_legend(players))
	extra_chart=HistoryChart.new();body.add_child(extra_chart);history_charts.append(extra_chart)
	extra_chart.configure(history,players,str(EXTRA_METRICS[0][0]),float(stats.get("duration",0.0)),float(stats.get("history_since_time",0.0)))
	extra_metric_tabs.tab_changed.connect(func(index: int):extra_chart.configure(displayed_stats.get("history",[]),_chart_players(displayed_stats),str(EXTRA_METRICS[index][0]),float(displayed_stats.get("duration",0.0)),float(displayed_stats.get("history_since_time",0.0))))
	tables.add_child(_note("资金余额为可用资金；净投入扣除退款；建筑和步兵曲线记录当时存活数量，生产及损失另见下方累计统计。"))

func _chart_card(title_text: String, field: String, stats: Dictionary, players: Array) -> void:
	var panel:=PanelContainer.new();panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel",_style(Color("f5e8cc"),16));tables.add_child(panel)
	var body:=VBoxContainer.new();body.add_theme_constant_override("separation",8);panel.add_child(body)
	body.add_child(_label(title_text,26))
	body.add_child(_legend(players))
	var chart:=HistoryChart.new();body.add_child(chart);history_charts.append(chart)
	chart.configure(stats.get("history",[]),players,field,float(stats.get("duration",0.0)),float(stats.get("history_since_time",0.0)))

func _legend(players: Array) -> HFlowContainer:
	var legend:=HFlowContainer.new();legend.add_theme_constant_override("h_separation",24);legend.add_theme_constant_override("v_separation",8)
	for row: Dictionary in players:
		var chip:=HBoxContainer.new();chip.add_theme_constant_override("separation",8);legend.add_child(chip)
		var swatch:=ColorRect.new();swatch.color=row.chart_color;swatch.custom_minimum_size=Vector2(26,8);swatch.size_flags_vertical=Control.SIZE_SHRINK_CENTER;chip.add_child(swatch)
		chip.add_child(_label(str(row.chart_name),22))
	return legend

func close_scoreboard() -> void:hide()
func _choose(kind:String)->void:
	hide();action.emit(kind,null)

func _fit_typography()->void:
	if not is_inside_tree():return
	var logical:Vector2=get_viewport().get_visible_rect().size
	var pixels:Vector2=Vector2(get_window().size)
	var canvas_scale:float=minf(pixels.x/maxf(1,logical.x),pixels.y/maxf(1,logical.y))
	# Canvas scaling already follows resolution. Compensate at small windows so
	# the actual table body never shrinks below18physicalpixels; don't shrink to fit.
	font_correction=clampf(18.0/maxf(1,24.0*canvas_scale),1.0,1.5)
	for node:Variant in _font_targets.keys():
		if not is_instance_valid(node):_font_targets.erase(node);continue
		node.add_theme_font_size_override("font_size",ceili(float(_font_targets[node])*font_correction))
	physical_body_font=ceili(24.0*font_correction)*canvas_scale
	for chart: Control in history_charts:
		if is_instance_valid(chart):chart.set_font_scale(font_correction)

func _table(title_text:String,fields:Array,players:Array)->void:
	tables.add_child(_label(title_text,30))
	var grid:=GridContainer.new();grid.columns=fields.size()+1
	grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",3);grid.add_theme_constant_override("v_separation",3)
	var scroll:=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO;scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.mouse_force_pass_scroll_events=false;tables.add_child(scroll);scroll.add_child(grid)
	grid.add_child(_cell("参战军团",true,true))
	for field:Array in fields:grid.add_child(_cell(str(field[1]),true,false))
	for i:int in players.size():
		var row:Dictionary=players[i];var team:int=int(row.get("team",i));var faction:String=str(row.get("faction",""))
		grid.add_child(_cell(str(FACTIONS.get(faction,faction))+(" · 玩家" if team==0 else " · AI %d"%team),false,true))
		for field:Array in fields:grid.add_child(_cell("%.0f"%float(row[field[0]]) if row.has(field[0]) else "—",false,false))

func _cell(value:String,header:bool,name_cell:bool)->Control:
	var panel:=PanelContainer.new();panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel",_style(Color("d8c09a") if header else Color("f5e8cc"),12))
	var label:=_label(value,24);label.custom_minimum_size.x=250 if name_cell else 134
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_LEFT if name_cell else HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label);return panel

func _style(color:Color,margin:int)->StyleBoxFlat:
	var style:=StyleBoxFlat.new();style.bg_color=color;style.border_color=Color("b29771");style.set_border_width_all(1)
	style.content_margin_left=margin;style.content_margin_right=margin;style.content_margin_top=margin;style.content_margin_bottom=margin
	return style
func _label(value:String,font_size:int)->Label:
	var label:=Label.new();label.text=value;label.add_theme_color_override("font_color",INK)
	label.add_theme_font_size_override("font_size",font_size);_font_targets[label]=font_size
	return label
func _note(value: String) -> Label:
	var label:=_label(value,19);label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	return label
func _button(value:String,callback:Callable)->Button:
	var button:=Button.new();button.text=value;button.custom_minimum_size.y=64
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_font_targets[button]=26
	button.add_theme_font_size_override("font_size",26)
	for state: String in ["font_color","font_hover_color","font_focus_color","font_pressed_color"]:button.add_theme_color_override(state,INK)
	button.add_theme_stylebox_override("normal",_style(Color("edd19b"),16))
	button.add_theme_stylebox_override("hover",_style(Color("faedd0"),16));button.pressed.connect(callback)
	return button
