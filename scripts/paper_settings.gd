extends Control
class_name PaperSettings

signal changed(kind: String, value: Variant)
signal closed

const Paper = preload("res://scripts/paper_ui.gd")
const INK := Color("392c21")
var sliders: Dictionary = {}
var percentages: Dictionary = {}
var mute_button: CheckButton
var quality: OptionButton
var resolution: OptionButton
var dof: CheckButton
var ambient_occlusion: CheckButton
var shadows: CheckButton
var fullscreen: CheckButton
var debug_enabled: CheckButton
var pitch: HSlider
var pitch_label: Label
var close_button: Button
var _panel: PanelContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.15, 0.10, 0.07, 0.82)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var panel := PanelContainer.new()
	_panel = panel
	panel.name = "SettingsPaper"
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -320; panel.offset_right = 320
	panel.offset_top = -315; panel.offset_bottom = 315
	var margins := StyleBoxFlat.new()
	margins.bg_color = Color.TRANSPARENT
	margins.content_margin_left = 30; margins.content_margin_right = 30
	margins.content_margin_top = 24; margins.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", margins)
	add_child(panel)
	var paper := Paper.new()
	paper.paper_color = Color("ead5af"); paper.ink_frame = true; paper.paper_seed = 9401
	paper.inset = Vector2(30,24)
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(paper)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	panel.add_child(stack)
	stack.add_child(_label("设置  /  SETTINGS", 28))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_force_pass_scroll_events = false
	stack.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)
	content.add_child(_label("声音", 19))
	for item in [["master", "总音量"], ["music", "音乐"], ["sfx", "音效"], ["voice", "单位应答"]]:
		_add_volume(content, item[0], item[1])
	mute_button = CheckButton.new(); mute_button.text = "全部静音"
	content.add_child(mute_button)
	mute_button.toggled.connect(func(value: bool): changed.emit("audio_mix", {"muted": value}))
	content.add_child(HSeparator.new())
	content.add_child(_label("画面与镜头", 19))
	quality = _option(content, "画面效果", ["完整效果", "均衡（默认）", "性能优先"])
	quality.item_selected.connect(func(index: int): changed.emit("graphics_quality", ["native", "balanced", "performance"][index]))
	resolution = _option(content, "3D 清晰度", ["100%（原生）", "85%", "75%"])
	resolution.item_selected.connect(func(index: int): changed.emit("render_scale", [1.0, 0.85, 0.75][index]))
	var note := _label("降低 3D 清晰度可减轻显卡负担；界面保持清晰。", 13)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(note)
	dof = CheckButton.new(); dof.text = "微缩景深"
	content.add_child(dof)
	dof.toggled.connect(func(value: bool): changed.emit("depth_of_field", value))
	ambient_occlusion = CheckButton.new(); ambient_occlusion.text = "环境遮蔽（AO）"
	content.add_child(ambient_occlusion)
	ambient_occlusion.toggled.connect(func(value: bool): changed.emit("ambient_occlusion", value))
	shadows = CheckButton.new(); shadows.text = "动态阴影"
	content.add_child(shadows)
	shadows.toggled.connect(func(value: bool): changed.emit("shadows", value))
	fullscreen = CheckButton.new(); fullscreen.text = "全屏"
	content.add_child(fullscreen)
	fullscreen.toggled.connect(func(value: bool): changed.emit("fullscreen", value))
	var row := HBoxContainer.new(); content.add_child(row)
	pitch_label = _label("镜头俯角 30°", 15); pitch_label.custom_minimum_size.x = 155
	row.add_child(pitch_label)
	pitch = HSlider.new(); pitch.min_value = 20; pitch.max_value = 45; pitch.step = 1
	pitch.size_flags_horizontal = Control.SIZE_EXPAND_FILL; pitch.custom_minimum_size.y = 26
	row.add_child(pitch)
	pitch.value_changed.connect(func(value: float): pitch_label.text = "镜头俯角 %.0f°" % value; changed.emit("pitch", value))
	content.add_child(HSeparator.new())
	content.add_child(_label("调试（可选）", 19))
	debug_enabled = CheckButton.new()
	debug_enabled.name = "DebugEnabled"
	debug_enabled.text = "启用调试面板"
	content.add_child(debug_enabled)
	debug_enabled.toggled.connect(func(value: bool): changed.emit("debug_enabled", value))
	var debug_note := _label("开启后可按 F2 显示或收起详细指标。角落帧率始终显示。", 13)
	debug_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(debug_note)
	close_button = Button.new(); close_button.text = "完成 · 返回  /  Esc"
	close_button.custom_minimum_size.y = 44
	stack.add_child(close_button)
	close_button.pressed.connect(close)
	resized.connect(_fit)
	_fit()
	hide()

func _add_volume(parent: Control, id: String, caption: String) -> void:
	var row := HBoxContainer.new(); parent.add_child(row)
	var label := _label(caption, 15); label.custom_minimum_size.x = 120; row.add_child(label)
	var slider := HSlider.new(); slider.min_value = 0; slider.max_value = 100; slider.step = 1
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL; slider.custom_minimum_size.y = 26
	row.add_child(slider)
	var percent := _label("100%", 14); percent.custom_minimum_size.x = 52
	percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; row.add_child(percent)
	sliders[id] = slider; percentages[id] = percent
	slider.value_changed.connect(func(value: float): percent.text = "%d%%" % roundi(value); changed.emit("audio_mix", {id: value / 100.0}))

func _option(parent: Control, caption: String, items: Array) -> OptionButton:
	var row := HBoxContainer.new(); parent.add_child(row)
	var label := _label(caption, 15); label.custom_minimum_size.x = 155; row.add_child(label)
	var option := OptionButton.new(); option.get_popup().force_native = true
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item: String in items: option.add_item(item)
	row.add_child(option)
	return option

func _label(text: String, font_size: int) -> Label:
	var label := Label.new(); label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", INK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func open(values: Dictionary) -> void:
	for id: String in sliders:
		var value: float = clampf(float(values.get(id, 1.0)), 0.0, 1.0) * 100.0
		sliders[id].set_value_no_signal(value); percentages[id].text = "%d%%" % roundi(value)
	mute_button.set_pressed_no_signal(bool(values.get("muted", false)))
	quality.select(maxi(0, ["native", "balanced", "performance"].find(str(values.get("quality", "balanced")))))
	var scale_index: int = [1.0, 0.85, 0.75].find(float(values.get("render_scale", 1.0)))
	resolution.select(maxi(0, scale_index))
	dof.set_pressed_no_signal(bool(values.get("depth_of_field", true)))
	ambient_occlusion.set_pressed_no_signal(bool(values.get("ambient_occlusion", true)))
	shadows.set_pressed_no_signal(bool(values.get("shadows", true)))
	fullscreen.set_pressed_no_signal(bool(values.get("fullscreen", false)))
	debug_enabled.set_pressed_no_signal(bool(values.get("debug_enabled", false)))
	pitch.set_value_no_signal(float(values.get("pitch", 30.0)))
	pitch_label.text = "镜头俯角 %.0f°" % pitch.value
	show(); close_button.grab_focus()

func close() -> void:
	hide(); closed.emit()

func _fit() -> void:
	if _panel == null: return
	var width: float = minf(640.0, maxf(280.0, size.x - 48.0))
	var height: float = minf(700.0, maxf(240.0, size.y - 48.0))
	_panel.offset_left = -width * 0.5; _panel.offset_right = width * 0.5
	_panel.offset_top = -height * 0.5; _panel.offset_bottom = height * 0.5
