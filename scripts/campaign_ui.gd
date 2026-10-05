extends Control
class_name CampaignUI

signal focus_target(point: Vector2)

var hud: PaperHUD
var panel: PanelContainer
var chapter_label: Label
var objective_label: Label
var detail_label: Label
var hint_label: Label
var progress_label: Label
var target_button: Button
var marker: Control
var target: Vector2 = Vector2.ZERO
var _cache: String = ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = hud.panel_at(self, Vector2(12, 86), Vector2(340, 245), Vector2.ZERO, Vector2.ZERO)
	panel.name = "CampaignObjectivePanel"
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	panel.add_child(column)
	chapter_label = hud.label("战役  ·  无字桥补给线", 12)
	chapter_label.add_theme_color_override("font_color", hud.BLUE)
	column.add_child(chapter_label)
	objective_label = hud.label("", 16)
	column.add_child(objective_label)
	detail_label = hud.label("", 12)
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.custom_minimum_size.y = 31
	column.add_child(detail_label)
	progress_label = hud.label("", 11)
	progress_label.add_theme_color_override("font_color", hud.BLUE)
	progress_label.clip_text = true
	column.add_child(progress_label)
	hint_label = hud.label("", 11)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.custom_minimum_size.y = 30
	column.add_child(hint_label)
	target_button = hud.button("◈  查看目标地点", func(): focus_target.emit(target))
	target_button.custom_minimum_size.y = 22
	target_button.add_theme_font_size_override("font_size", 11)
	column.add_child(target_button)
	marker = preload("res://scripts/campaign_minimap_marker.gd").new()
	hud.mini.add_child(marker)
	panel.hide()

func display(view: Dictionary) -> void:
	var active: bool = bool(view.get("active", false))
	panel.visible = active
	if marker != null: marker.set_target(view.get("marker", Vector2.ZERO), active and not bool(view.get("finished", false)))
	if not active: return
	var key: String = str(view.get("stage", -1)) + str(view.get("progress", "")) + str(view.get("finished", false))
	if key == _cache: return
	_cache = key
	target = view.get("marker", Vector2.ZERO)
	chapter_label.text = "战役  ·  %d / %d" % [mini(int(view.get("stage", 0)) + 1, int(view.get("total", 7))), int(view.get("total", 7))]
	objective_label.text = str(view.get("objective", ""))
	detail_label.text = str(view.get("body", ""))
	hint_label.text = str(view.get("hint", ""))
	progress_label.text = str(view.get("progress", ""))
	progress_label.visible = not progress_label.text.is_empty()
	target_button.disabled = bool(view.get("finished", false))
	if bool(view.get("finished", false)):
		objective_label.text = "任务完成"
		detail_label.text = "无字桥补给线已夺回。"
		hint_label.text = ""
