extends Control
class_name CampaignMinimapMarker

var target: Vector2 = Vector2.ZERO
var active: bool = false
var pulse: float = 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)

func set_target(point: Vector2, enabled: bool) -> void:
	target = point
	active = enabled
	queue_redraw()

func _process(delta: float) -> void:
	if not active: return
	pulse = fposmod(pulse + delta * 2.8, TAU)
	queue_redraw()

func _draw() -> void:
	if not active: return
	var rect := Rect2(Vector2(5, 20), Vector2(maxf(1.0, size.x - 10), maxf(1.0, size.y - 25)))
	var center: Vector2 = rect.position + target / 320.0 * rect.size
	var radius: float = 5.5 + (sin(pulse) + 1.0) * 1.1
	draw_circle(center, radius + 2.0, Color("413124"), false, 2.4, true)
	draw_circle(center, radius, Color("ffd36e"), false, 2.0, true)
	draw_circle(center, 2.2, Color("ffdc78"), true, -1, true)
