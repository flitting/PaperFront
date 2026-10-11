extends Control
class_name PaperSettings

signal changed(kind: String, value: Variant)
signal action(kind: String, value: Variant)
signal closed

const Paper = preload("res://scripts/paper_ui.gd")
const Localization = preload("res://scripts/localization.gd")
const INK := Color("392c21")
var sliders: Dictionary = {}
var percentages: Dictionary = {}
var mute_button: CheckButton
var language_option: OptionButton
var voice_language_option: OptionButton
var quality: OptionButton
var resolution: OptionButton
var dof: CheckButton
var ambient_occlusion: CheckButton
var shadows: CheckButton
var fullscreen: CheckButton
var debug_enabled: CheckButton
var audio_browser_enabled: CheckButton
var pitch: HSlider
var pitch_label: Label
var pitch_mode: OptionButton
var dynamic_pitch_note: Label
var close_button: Button
var session_controls: VBoxContainer
var save_button: Button
var load_button: Button
var new_game_button: Button
var home_button: Button
var wiki_button: Button
var quit_button: Button
var notice: Label
var tabs: TabContainer
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
	language_option = _option(stack, "语言 / Language", ["English", "简体中文"])
	language_option.name = "LanguageSwitch"
	language_option.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	language_option.select(1 if Localization.language() == "zh_CN" else 0)
	language_option.item_selected.connect(func(index: int):
		var locale: String = "zh_CN" if index == 1 else "en"
		Localization.set_language(locale)
		changed.emit("language", locale)
	)
	tabs = TabContainer.new()
	tabs.name = "SettingsTabs"
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preload("res://scripts/paper_tabs.gd").apply(tabs)
	stack.add_child(tabs)
	var content: VBoxContainer = _page("战局")
	session_controls = VBoxContainer.new()
	session_controls.add_theme_constant_override("separation", 8)
	content.add_child(session_controls)
	session_controls.add_child(_label("战局", 19))
	var session_grid := GridContainer.new()
	session_grid.columns = 2
	session_grid.add_theme_constant_override("h_separation", 10)
	session_grid.add_theme_constant_override("v_separation", 8)
	session_controls.add_child(session_grid)
	save_button = _session_button(session_grid, "保存战局 · F5", "save")
	load_button = _session_button(session_grid, "读取存档 · F9", "load")
	new_game_button = _session_button(session_grid, "开始新战局", "new_game")
	wiki_button = _session_button(session_grid, "军团档案 · Wiki", "wiki")
	home_button = _session_button(session_grid, "返回主菜单", "entry_home")
	quit_button = _session_button(session_grid, "退出游戏", "quit")
	session_controls.add_child(HSeparator.new())
	notice = _label("", 14)
	notice.name = "SessionNotice"
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.hide()
	stack.add_child(notice)
	content = _page("声音")
	content.add_child(_label("声音", 19))
	voice_language_option = _option(content, "语音语言", ["简体中文", "English"])
	voice_language_option.name = "VoiceLanguageSwitch"
	voice_language_option.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	voice_language_option.select(1)
	voice_language_option.item_selected.connect(func(index: int): changed.emit("voice_language", "en" if index == 1 else "zh_CN"))
	for item in [["master", "总音量"], ["music", "音乐"], ["sfx", "音效"], ["voice", "单位应答"], ["commander", "指挥官播报"]]:
		_add_volume(content, item[0], item[1])
	mute_button = CheckButton.new(); mute_button.text = "全部静音"
	content.add_child(mute_button)
	mute_button.toggled.connect(func(value: bool): changed.emit("audio_mix", {"muted": value}))
	content.add_child(HSeparator.new())
	content = _page("画面")
	content.add_child(_label("画面", 19))
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
	content = _page("镜头")
	content.add_child(_label("镜头", 19))
	pitch_mode = _option(content, "俯角模式", ["动态（随缩放）", "固定俯角"])
	pitch_mode.item_selected.connect(func(index: int): changed.emit("camera_pitch_mode", "dynamic" if index == 0 else "fixed"))
	dynamic_pitch_note = _label("最大放大时为 10°，缩小时平滑升至 45°；远景保持 45°。", 13)
	dynamic_pitch_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(dynamic_pitch_note)
	var row := HBoxContainer.new(); content.add_child(row)
	pitch_label = _label("镜头俯角 30°", 15); pitch_label.custom_minimum_size.x = 155
	row.add_child(pitch_label)
	pitch = HSlider.new(); pitch.min_value = 20; pitch.max_value = 45; pitch.step = 1
	pitch.size_flags_horizontal = Control.SIZE_EXPAND_FILL; pitch.custom_minimum_size.y = 26
	row.add_child(pitch)
	pitch.value_changed.connect(func(value: float): pitch_label.text = "镜头俯角 %.0f°" % value; changed.emit("pitch", value))
	content.add_child(HSeparator.new())
	content = _page("调试")
	content.add_child(_label("调试（可选）", 19))
	debug_enabled = CheckButton.new()
	debug_enabled.name = "DebugEnabled"
	debug_enabled.text = "启用调试面板"
	content.add_child(debug_enabled)
	debug_enabled.toggled.connect(func(value: bool): changed.emit("debug_enabled", value))
	var debug_note := _label("开启后可按 F2 显示或收起详细指标。对局显示帧率，加载时隐藏。", 13)
	debug_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(debug_note)
	audio_browser_enabled = CheckButton.new()
	audio_browser_enabled.name = "AudioBrowserEnabled"
	audio_browser_enabled.text = "启用 Wiki 音频浏览器（调试）"
	content.add_child(audio_browser_enabled)
	audio_browser_enabled.toggled.connect(func(value: bool): changed.emit("audio_browser_enabled", value))
	close_button = Button.new(); close_button.text = "完成 · 返回  /  Esc"
	close_button.custom_minimum_size.y = 44
	stack.add_child(close_button)
	close_button.pressed.connect(close)
	resized.connect(_fit)
	_fit()
	hide()

func _page(caption: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = caption
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_force_pass_scroll_events = false
	tabs.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)
	return content

func _session_button(parent: Control, caption: String, kind: String) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 40
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func(): action.emit(kind, null))
	parent.add_child(button)
	return button

func _add_volume(parent: Control, id: String, caption: String) -> void:
	var row := HBoxContainer.new(); parent.add_child(row)
	var label := _label(caption, 15); label.custom_minimum_size.x = 120; row.add_child(label)
	var slider := HSlider.new(); slider.min_value = 0; slider.max_value = 200; slider.step = 1
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
	show_notice("")
	language_option.select(1 if Localization.language() == "zh_CN" else 0)
	voice_language_option.select(1 if values.get("voice_language", "en") == "en" else 0)
	var in_match: bool = bool(values.get("in_match", false))
	session_controls.visible = in_match
	tabs.set_tab_hidden(0, not in_match)
	tabs.current_tab = 0 if in_match else 1
	save_button.disabled = not bool(values.get("can_save", false))
	for id: String in sliders:
		var value: float = clampf(float(values.get(id, 1.0)), 0.0, 2.0) * 100.0
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
	audio_browser_enabled.set_pressed_no_signal(bool(values.get("audio_browser_enabled", true)))
	set_pitch_controls(str(values.get("pitch_mode", "dynamic")), float(values.get("pitch", 30.0)), float(values.get("effective_pitch", 30.0)))
	show(); close_button.grab_focus()

func close() -> void:
	if not visible: return
	hide(); closed.emit()

func show_notice(message: String) -> void:
	notice.text = message
	notice.visible = not message.is_empty()

func set_pitch_controls(mode: String, fixed_pitch: float, effective_pitch: float) -> void:
	var dynamic: bool = mode != "fixed"
	pitch_mode.select(0 if dynamic else 1)
	dynamic_pitch_note.visible = dynamic
	pitch.editable = not dynamic
	pitch.set_value_no_signal(effective_pitch if dynamic else fixed_pitch)
	pitch_label.text = ("动态俯角 %.0f°" if dynamic else "固定俯角 %.0f°") % pitch.value

func _fit() -> void:
	if _panel == null: return
	var width: float = minf(640.0, maxf(280.0, size.x - 48.0))
	var height: float = minf(700.0, maxf(240.0, size.y - 48.0))
	_panel.offset_left = -width * 0.5; _panel.offset_right = width * 0.5
	_panel.offset_top = -height * 0.5; _panel.offset_bottom = height * 0.5

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_instance_valid(language_option):
		language_option.select(1 if Localization.language() == "zh_CN" else 0)
