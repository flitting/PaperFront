extends CanvasLayer
class_name PaperPerformanceOverlay

# This layer owns only the small FPS readout. Expensive renderer measurements
# remain under the optional diagnostics panel's control.
const Paper = preload("res://scripts/paper_ui.gd")
const UPDATE_INTERVAL := 0.5
const INK := Color("392c21")

# Assign the HUD's retained label before adding this layer to the tree, so there
# is one FPS readout across the entry, match, settings and outcome screens.
var fps_label: Label
var paper_theme: Theme
var screen: Control
var chip: PanelContainer
var update_timer: Timer
var _last_fps := -1

func _ready() -> void:
	layer = 7
	process_mode = Node.PROCESS_MODE_ALWAYS
	screen = Control.new()
	screen.name = "PerformanceScreen"
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.theme = paper_theme
	add_child(screen)
	chip = PanelContainer.new()
	chip.name = "FPSPaper"
	chip.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	# The session controls occupy y=14..70; this corner tag starts below them.
	chip.offset_left = -104.0; chip.offset_right = -12.0
	chip.offset_top = 78.0; chip.offset_bottom = 103.0
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margins := StyleBoxFlat.new()
	margins.bg_color = Color.TRANSPARENT
	margins.content_margin_left = 8.0; margins.content_margin_right = 8.0
	margins.content_margin_top = 2.0; margins.content_margin_bottom = 2.0
	chip.add_theme_stylebox_override("panel", margins)
	screen.add_child(chip)
	var paper := Paper.new()
	paper.paper_color = Color("ead5af")
	paper.ink_frame = false
	paper.paper_seed = 9402
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paper.inset = Vector2(8.0, 2.0)
	chip.add_child(paper)
	if fps_label == null:
		fps_label = Label.new()
		chip.add_child(fps_label)
	elif fps_label.get_parent() == null:
		chip.add_child(fps_label)
	else:
		fps_label.reparent(chip, false)
	fps_label.name = "FPS"
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fps_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fps_label.add_theme_font_size_override("font_size", 13)
	fps_label.add_theme_color_override("font_color", INK)
	fps_label.show()
	update_timer = Timer.new()
	update_timer.name = "FPSRefresh"
	update_timer.wait_time = UPDATE_INTERVAL
	update_timer.ignore_time_scale = true
	update_timer.timeout.connect(refresh)
	add_child(update_timer)
	refresh()
	update_timer.start()

func refresh() -> void:
	var fps := maxi(0, Engine.get_frames_per_second())
	if fps == _last_fps: return
	_last_fps = fps
	fps_label.text = "%d FPS" % fps

func set_loading(active: bool) -> void:
	# Hide the whole paper chip, including its background, before loading draws.
	screen.visible = not active
	if active:
		update_timer.stop()
	else:
		refresh()
		update_timer.start()
