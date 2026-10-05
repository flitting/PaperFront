extends CanvasLayer

const INK := Color("392c21")
const PAPER := Color("e4cba5")
const BLUE := Color("38627b")

var screen: Control
var title_label: Label
var detail_label: Label
var stage_label: Label
var progress_bar: ProgressBar

func _ready() -> void:
	layer = 6
	screen = Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(screen)
	var background := ColorRect.new()
	background.color = Color("65513d")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(background)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -310
	panel.offset_right = 310
	panel.offset_top = -140
	panel.offset_bottom = 140
	var paper := StyleBoxFlat.new()
	paper.bg_color = PAPER
	paper.border_color = INK
	paper.set_border_width_all(2)
	paper.content_margin_left = 32
	paper.content_margin_right = 32
	paper.content_margin_top = 28
	paper.content_margin_bottom = 28
	paper.shadow_size = 5
	panel.add_theme_stylebox_override("panel", paper)
	screen.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)
	title_label = _label("正在加载战场", 30)
	column.add_child(title_label)
	detail_label = _label("", 16)
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(detail_label)
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size.y = 30
	progress_bar.step = 0.1
	var track := StyleBoxFlat.new()
	track.bg_color = Color("b59d78")
	track.border_color = INK
	track.set_border_width_all(1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = BLUE
	progress_bar.add_theme_stylebox_override("background", track)
	progress_bar.add_theme_stylebox_override("fill", fill)
	progress_bar.add_theme_color_override("font_color", Color("fff0cf"))
	progress_bar.add_theme_color_override("font_outline_color", INK)
	progress_bar.add_theme_constant_override("outline_size", 2)
	column.add_child(progress_bar)
	stage_label = _label("准备战场…", 16)
	column.add_child(stage_label)
	screen.hide()

func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", INK)
	return label

func open(title: String, detail: String) -> void:
	title_label.text = title
	detail_label.text = detail
	progress_bar.value = 0.0
	stage_label.text = "准备战场…"
	screen.show()

func update_progress(fraction: float, stage: String) -> void:
	progress_bar.value = maxf(progress_bar.value, clampf(fraction, 0.0, 1.0) * 100.0)
	stage_label.text = stage

func close() -> void:
	screen.hide()
