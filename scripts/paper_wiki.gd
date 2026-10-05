extends Control
class_name PaperWiki

signal closed

const Catalog = preload("res://scripts/wiki_catalog.gd")
const Preview = preload("res://scripts/wiki_model_preview.gd")
const Paper = preload("res://scripts/paper_ui.gd")
const INK := Color("392c21")
const CREAM := Color("f0dfbd")
const KRAFT := Color("ccb083")
const BLUE := Color("2865a5")
const RED := Color("bb4034")

var rules: Dictionary = {}
var selected_id := ""
var current_entries: Array[Dictionary] = []
var entry_buttons: Dictionary = {}
var faction_filter: OptionButton
var kind_filter: OptionButton
var search: LineEdit
var list_scroll: ScrollContainer
var list_box: VBoxContainer
var count_label: Label
var title_label: Label
var formal_label: Label
var detail_scroll: ScrollContainer
var detail_box: VBoxContainer
var description_label: Label
var preview: Control
var rotation_button: Button
var table_sections: Array[Dictionary] = []
var displayed_rows: Array[Dictionary] = []
var empty_label: Label
var back_button: Button
var _paper_serial := 4000

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	var backdrop:=ColorRect.new()
	backdrop.color=Color("594635")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var sheet:=_panel(CREAM)
	add_child(sheet)
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sheet.offset_left=24;sheet.offset_top=22;sheet.offset_right=-24;sheet.offset_bottom=-22
	var page:=VBoxContainer.new()
	page.add_theme_constant_override("separation",14)
	sheet.add_child(page)
	var heading:=HBoxContainer.new()
	heading.add_theme_constant_override("separation",18)
	page.add_child(heading)
	var heading_text:=_label("军团档案  /  WIKI",30)
	heading_text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	heading.add_child(heading_text)
	heading.add_child(_label("单位 · 建筑 · 工业装备",16))
	back_button=_button("返回菜单  Esc",close_catalog)
	heading.add_child(back_button)
	var body:=HBoxContainer.new()
	body.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",20)
	page.add_child(body)
	var index_panel:=_panel(Color("dfc69e"))
	index_panel.custom_minimum_size.x=270
	index_panel.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_child(index_panel)
	var index:=VBoxContainer.new()
	index.add_theme_constant_override("separation",10)
	index_panel.add_child(index)
	index.add_child(_label("资料索引",22))
	faction_filter=OptionButton.new()
	faction_filter.get_popup().force_native=true
	_refresh_factions()
	index.add_child(faction_filter)
	kind_filter=OptionButton.new()
	kind_filter.get_popup().force_native=true
	for item in [["单位与建筑",""],["所有单位","unit"],["所有建筑","building"]]:
		kind_filter.add_item(item[0]);kind_filter.set_item_metadata(kind_filter.item_count-1,item[1])
	index.add_child(kind_filter)
	search=LineEdit.new()
	search.placeholder_text="搜索名称、型号或用途"
	search.add_theme_color_override("font_placeholder_color",Color("876e4f"))
	search.add_theme_color_override("font_color",INK)
	search.clear_button_enabled=true
	index.add_child(search)
	count_label=_label("",14)
	index.add_child(count_label)
	list_scroll=ScrollContainer.new()
	list_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.mouse_force_pass_scroll_events=false
	index.add_child(list_scroll)
	list_box=VBoxContainer.new()
	list_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation",6)
	list_scroll.add_child(list_box)
	var content:=VBoxContainer.new()
	content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	content.size_flags_vertical=Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",10)
	body.add_child(content)
	var model_panel:=_panel(Color("e7d1aa"))
	model_panel.custom_minimum_size.y=330
	content.add_child(model_panel)
	var model_box:=VBoxContainer.new()
	model_box.add_theme_constant_override("separation",4)
	model_panel.add_child(model_box)
	var model_heading:=HBoxContainer.new()
	model_box.add_child(model_heading)
	var names:=VBoxContainer.new()
	names.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	model_heading.add_child(names)
	title_label=_label("",26)
	title_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	names.add_child(title_label)
	formal_label=_label("",15)
	formal_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	names.add_child(formal_label)
	rotation_button=_button("暂停旋转",func():preview.toggle_rotation();_sync_rotation_button())
	model_heading.add_child(rotation_button)
	model_heading.add_child(_button("复位",func():preview.reset_rotation()))
	preview=Preview.new()
	preview.custom_minimum_size.y=230
	preview.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	preview.size_flags_vertical=Control.SIZE_EXPAND_FILL
	model_box.add_child(preview)
	preview.rotation_active_changed.connect(func(_active):_sync_rotation_button())
	var model_footer:=HBoxContainer.new()
	model_box.add_child(model_footer)
	var hint:=_label("拖动展台旋转 · 纸片步兵保留原剪影",13)
	hint.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	model_footer.add_child(hint)
	model_footer.add_child(_button("橙黄识别",func():preview.set_preview_team(0)))
	model_footer.add_child(_button("青色识别",func():preview.set_preview_team(1)))
	var info_panel:=_panel(Color("f4e7cc"))
	info_panel.size_flags_vertical=Control.SIZE_EXPAND_FILL
	content.add_child(info_panel)
	detail_scroll=ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.mouse_force_pass_scroll_events=false
	info_panel.add_child(detail_scroll)
	detail_box=VBoxContainer.new()
	detail_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	detail_box.add_theme_constant_override("separation",7)
	detail_scroll.add_child(detail_box)
	faction_filter.item_selected.connect(func(_i):_rebuild_entries())
	kind_filter.item_selected.connect(func(_i):_rebuild_entries())
	search.text_changed.connect(func(_text):_rebuild_entries())
	hide()
	visibility_changed.connect(_sync_active)
	resized.connect(_resize_preview)
	_resize_preview()

func configure(config: Dictionary) -> void:
	rules=config.duplicate(true)
	if is_node_ready():
		_refresh_factions()
		_rebuild_entries(selected_id if not selected_id.is_empty() else "kestrel_hq")

func _refresh_factions() -> void:
	var previous: String=""
	if faction_filter.item_count>0 and faction_filter.selected>=0:
		previous=str(faction_filter.get_item_metadata(faction_filter.selected))
	faction_filter.clear()
	faction_filter.add_item("全部阵营")
	faction_filter.set_item_metadata(0,"")
	for id: String in rules.get("factions",{}):
		faction_filter.add_item(str(rules.factions[id].name))
		var index: int=faction_filter.item_count-1
		faction_filter.set_item_metadata(index,id)
		if id==previous:faction_filter.select(index)

func _faction_color(id: String) -> Color:
	return Color(str(rules.get("factions",{}).get(id,{}).get("color","392c21")))

func _faction_short_name(id: String) -> String:
	var info: Dictionary=rules.get("factions",{}).get(id,{})
	return str(info.get("short_name",str(info.get("name",id)).trim_suffix("军团").trim_suffix("同盟").trim_suffix("教团")))

func open_catalog(initial_id: String="") -> void:
	if rules.is_empty():return
	show()
	_rebuild_entries(initial_id if not initial_id.is_empty() else selected_id if not selected_id.is_empty() else "kestrel_hq")
	preview.set_preview_active(true)
	search.grab_focus()

func close_catalog() -> void:
	if not visible:return
	hide()
	preview.clear_preview()
	closed.emit()

func _input(event: InputEvent) -> void:
	if is_visible_in_tree() and event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:
		close_catalog()
		get_viewport().set_input_as_handled()
	elif is_visible_in_tree() and event is InputEventKey and event.pressed and event.keycode==KEY_DOWN and search.has_focus() and not current_entries.is_empty():
		entry_buttons[current_entries[0].id].grab_focus()
		list_scroll.ensure_control_visible(entry_buttons[current_entries[0].id])
		get_viewport().set_input_as_handled()

func _sync_active() -> void:
	if preview!=null:preview.set_preview_active(is_visible_in_tree())

func _resize_preview() -> void:
	if preview==null:return
	# Leave a useful lower reading area at the minimum supported window.
	preview.get_parent().get_parent().custom_minimum_size.y=clampf(size.y*.44,330,430)

func _rebuild_entries(preferred: String="") -> void:
	for child in list_box.get_children():list_box.remove_child(child);child.queue_free()
	entry_buttons.clear()
	current_entries=Catalog.entries(rules,str(faction_filter.get_item_metadata(faction_filter.selected)),str(kind_filter.get_item_metadata(kind_filter.selected)),search.text)
	count_label.text="%d 项资料" % current_entries.size()
	for entry in current_entries:
		var id: String=entry.id
		var faction_name: String=rules.factions[entry.spec.faction].name
		var title: String=_faction_short_name(str(entry.spec.faction))+" · "+str(entry.spec.name)
		var button:=_button(title,func():select_entry(id))
		button.name=id
		button.custom_minimum_size=Vector2(228,55)
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.tooltip_text=faction_name+" · "+("单位" if entry.kind=="unit" else "建筑")+"\n"+str(entry.spec.get("description",""))
		button.add_theme_font_size_override("font_size",17)
		list_box.add_child(button)
		entry_buttons[id]=button
	var pick: String=preferred if entry_buttons.has(preferred) else selected_id
	if not entry_buttons.has(pick) and not current_entries.is_empty():pick=current_entries[0].id
	if current_entries.is_empty():
		selected_id=""
		preview.clear_preview()
		title_label.text="没有匹配的资料"
		formal_label.text="试试其它名称、用途或筛选条件"
		_clear_details()
		rotation_button.disabled=true
	else:select_entry(pick)

func select_entry(id: String) -> void:
	var kind: String="unit" if rules.units.has(id) else "building"
	var spec: Dictionary=rules.get("units" if kind=="unit" else "buildings",{}).get(id,{})
	if spec.is_empty():return
	selected_id=id
	title_label.text=str(spec.name)
	formal_label.text=str(rules.factions[spec.faction].name)+" / "+str(spec.get("formal_name",spec.name))+" / "+("单位" if kind=="unit" else "建筑")
	title_label.add_theme_color_override("font_color",_faction_color(str(spec.faction)))
	preview.set_entry(spec,kind,0)
	preview.set_preview_active(is_visible_in_tree())
	rotation_button.disabled=false
	_sync_rotation_button()
	for key in entry_buttons:
		var button: Button=entry_buttons[key]
		button.add_theme_stylebox_override("normal",_style(Color("ecd092") if key==id else CREAM,_faction_color(str(spec.faction)) if key==id else INK,2 if key==id else 1))
	_clear_details()
	detail_box.add_child(_label("用途与介绍",21))
	description_label=_label(str(spec.get("description","")),17)
	description_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	description_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	detail_box.add_child(description_label)
	table_sections=Catalog.sections(rules,id)
	for section in table_sections:
		var heading:=_label(str(section.title),20)
		heading.add_theme_color_override("font_color",Color("785c3a"))
		detail_box.add_child(heading)
		var row_number:=0
		for row in section.rows:
			var panel:=PanelContainer.new()
			panel.add_theme_stylebox_override("panel",_style(Color("ead9b7") if row_number%2==0 else Color("f5e8ce"),Color("baa37d"),1))
			panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			detail_box.add_child(panel)
			var columns:=HBoxContainer.new()
			columns.add_theme_constant_override("separation",18)
			panel.add_child(columns)
			var key_label:=_label(str(row.label),16)
			key_label.custom_minimum_size.x=210
			key_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			columns.add_child(key_label)
			var value_label:=_label(str(row.value),16)
			value_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			value_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			columns.add_child(value_label)
			displayed_rows.append(row)
			row_number+=1
	detail_scroll.scroll_vertical=0
	call_deferred("_reveal_selected")

func _reveal_selected() -> void:
	if entry_buttons.has(selected_id):list_scroll.ensure_control_visible(entry_buttons[selected_id])

func _clear_details() -> void:
	for child in detail_box.get_children():detail_box.remove_child(child);child.queue_free()
	table_sections.clear();displayed_rows.clear()

func _sync_rotation_button() -> void:
	rotation_button.text="暂停旋转" if preview.rotation_active else "继续旋转"

func _style(color: Color, border: Color=INK, width: int=1) -> StyleBoxFlat:
	var style:=StyleBoxFlat.new()
	style.bg_color=color;style.border_color=border;style.set_border_width_all(width)
	style.content_margin_left=12;style.content_margin_right=12;style.content_margin_top=8;style.content_margin_bottom=8
	return style

func _panel(color: Color) -> PanelContainer:
	var panel:=PanelContainer.new()
	panel.add_theme_stylebox_override("panel",_style(Color.TRANSPARENT,Color.TRANSPARENT,0))
	panel.mouse_force_pass_scroll_events=false
	var paper:=Paper.new()
	paper.paper_color=color;paper.ink_frame=true;paper.paper_seed=_paper_serial;_paper_serial+=1
	paper.inset=Vector2(12,8)
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(paper)
	return panel

func _label(text: String,font_size: int=16) -> Label:
	var label:=Label.new();label.text=text
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",INK)
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return label

func _button(text: String,pressed: Callable) -> Button:
	var button:=Button.new();button.text=text;button.custom_minimum_size.y=40
	button.add_theme_stylebox_override("normal",_style(CREAM))
	button.add_theme_stylebox_override("hover",_style(Color("faefd7"),BLUE,2))
	button.add_theme_stylebox_override("pressed",_style(Color("d7bd8d"),INK,2))
	button.add_theme_font_size_override("font_size",16)
	button.mouse_force_pass_scroll_events=false
	button.pressed.connect(pressed)
	return button
