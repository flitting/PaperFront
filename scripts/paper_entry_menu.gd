extends Control
class_name PaperEntryMenu

signal action(kind: String, value: Variant)

const Paper = preload("res://scripts/paper_ui.gd")
const TraitText = preload("res://scripts/faction_trait_text.gd")
const INK := Color("392c21")
var resume_button: Button
var wiki_button: Button
var play_button: Button
var campaign_button: Button
var notice_label: Label
var _serial := 8100

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	var background:=ColorRect.new()
	background.color=Color("65513d")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var outer:=_panel(Color("ccb086"))
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.offset_left=28;outer.offset_right=-28;outer.offset_top=28;outer.offset_bottom=-28
	add_child(outer)
	var deck:=_panel(Color("edd9b4"))
	deck.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	deck.offset_left=-560;deck.offset_right=560;deck.offset_top=-330;deck.offset_bottom=330
	add_child(deck)
	var columns:=HBoxContainer.new()
	columns.add_theme_constant_override("separation",24)
	deck.add_child(columns)
	var left:=VBoxContainer.new()
	left.custom_minimum_size.x=435
	left.add_theme_constant_override("separation",9)
	columns.add_child(left)
	left.add_child(_label("手工微缩  ·  即时战略",17,Color("866142")))
	left.add_child(_label("纸境战线",54))
	left.add_child(_label("P A P E R   F R O N T",25,Color("38627b")))
	left.add_child(_label("从一张纸板，建立你的军团。",18))
	var spacer:=Control.new();spacer.custom_minimum_size.y=8;left.add_child(spacer)
	play_button=_button("新建战局",func():action.emit("entry_play",null),46)
	left.add_child(play_button)
	campaign_button=_button("战役  ·  无字桥补给线",func():action.emit("entry_campaign",null),46)
	campaign_button.tooltip_text="正典单关教程 · 基地建设、采矿、修桥、运输与反攻"
	left.add_child(campaign_button)
	wiki_button=_button("军团档案  /  Wiki",func():action.emit("wiki",null),46)
	wiki_button.tooltip_text="查阅全部单位与建筑 · 旋转模型 · 完整数值"
	left.add_child(wiki_button)
	left.add_child(_button("读取存档",func():action.emit("load",null),46))
	resume_button=_button("继续战局",func():action.emit("entry_resume",null),46)
	resume_button.hide()
	left.add_child(resume_button)
	var options:=HBoxContainer.new()
	options.add_theme_constant_override("separation",12)
	left.add_child(options)
	options.add_child(_button("设置 · 声音与画面",func():action.emit("settings_open",null),42))
	options.add_child(_button("退出游戏",func():action.emit("quit",null),42))
	notice_label=_label("第一次游玩推荐先选「战役」教程。",15,Color("785d3b"))
	notice_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	left.add_child(notice_label)
	var right:=GridContainer.new()
	right.columns=2
	right.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("h_separation",12)
	right.add_theme_constant_override("v_separation",14)
	columns.add_child(right)
	for info in [["kestrel","正典军团","2865a5","按图建造，按令前进。"],["rivet","重锤军团","bb4034","让胜利作证。"],["iron","长钉军团","39847b","放心，不会散架的。"],["sky","天翼教团","67578b","这就是先进科技。"]]:
		var faction: String=info[0]
		var card:=_panel(Color("e4cda7"))
		card.tooltip_text="\n".join(TraitText.faction_lines(TraitText.menu_rules(), faction))
		card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		card.size_flags_vertical=Control.SIZE_EXPAND_FILL
		right.add_child(card)
		var inner:=VBoxContainer.new()
		card.add_child(inner)
		inner.add_child(_label(info[1],22,Color(info[2])))
		var portraits:=VBoxContainer.new()
		portraits.size_flags_vertical=Control.SIZE_EXPAND_FILL
		inner.add_child(portraits)
		for art in ["current_force"]:
			var picture:=TextureRect.new()
			picture.texture=load("res://assets/cards/faction_covers_current/%s.png"%faction)
			picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
			picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			picture.custom_minimum_size=Vector2(150,204)
			picture.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			picture.size_flags_vertical=Control.SIZE_EXPAND_FILL
			picture.mouse_filter=Control.MOUSE_FILTER_IGNORE
			portraits.add_child(picture)
		inner.add_child(_label(info[3],14))
		inner.add_child(_label(TraitText.menu_short(TraitText.menu_rules(), faction),13,Color("70563b")))
	var edition:=_label("纸板工业战争  /  四阵营 · 地空海协同",14,Color("70563b"))
	edition.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	edition.offset_left=-410;edition.offset_right=-40;edition.offset_top=-55;edition.offset_bottom=-26
	add_child(edition)
	resized.connect(_fit)
	_fit()

func set_can_resume(allowed: bool) -> void:
	resume_button.visible=allowed
	_fit()

func show_notice(text: String) -> void:
	notice_label.text=text
	notice_label.add_theme_color_override("font_color",Color("a14d37"))

func _fit() -> void:
	if get_child_count()<3:return
	var deck: Control=get_child(2)
	var width:=minf(1080,maxf(940,size.x-64))
	deck.offset_left=-width*.5;deck.offset_right=width*.5
	var height: float=minf(706.0 if resume_button!=null and resume_button.visible else 660.0,size.y-40)
	deck.offset_top=-height*.5;deck.offset_bottom=height*.5

func _panel(color: Color) -> PanelContainer:
	var panel:=PanelContainer.new()
	var style:=StyleBoxFlat.new()
	style.bg_color=Color.TRANSPARENT
	style.content_margin_left=24;style.content_margin_right=24;style.content_margin_top=20;style.content_margin_bottom=20
	panel.add_theme_stylebox_override("panel",style)
	var paper:=Paper.new();paper.paper_color=color;paper.ink_frame=true;paper.paper_seed=_serial;_serial+=1
	paper.inset=Vector2(24,20)
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(paper)
	return panel

func _label(text: String,font_size: int,color: Color=INK) -> Label:
	var label:=Label.new();label.text=text
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return label

func _button(text: String,pressed: Callable,height: float=50) -> Button:
	var button:=Button.new();button.text=text;button.custom_minimum_size.y=height
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size",20 if height>45 else 16)
	for state in ["normal","hover","pressed","disabled"]:button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	var paper:=Paper.new();paper.paper_color=Color("f2dfba");paper.ink_frame=true;paper.paper_seed=_serial;_serial+=1
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.add_child(paper)
	button.pressed.connect(pressed)
	return button
