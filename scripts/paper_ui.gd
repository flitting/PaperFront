extends Control
class_name PaperUI

# A small deterministic canvas layer for the existing native controls.  It
# draws behind its owner, so buttons keep their normal focus and input rules.
var paper_color := Color("dec69a")
var inset := Vector2.ZERO
var ink_frame := false
var icon := ""
var ink := Color("342b22")
var paper_seed := 731

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if icon.is_empty():
		show_behind_parent = true
		if get_parent() is BaseButton:
			var owner_button: BaseButton = get_parent()
			owner_button.mouse_entered.connect(queue_redraw)
			owner_button.mouse_exited.connect(queue_redraw)
			owner_button.button_down.connect(queue_redraw)
			owner_button.button_up.connect(queue_redraw)
	resized.connect(queue_redraw)

func _draw() -> void:
	if not icon.is_empty():
		draw_icon()
		return
	var rect := Rect2(-inset, size + inset * 2.0)
	if rect.size.x < 2.0 or rect.size.y < 2.0: return
	var color := paper_color
	if get_parent() is BaseButton:
		var owner_button: BaseButton = get_parent()
		if owner_button.is_pressed(): color = color.darkened(0.12)
		elif owner_button.is_hovered(): color = color.lightened(0.12)
		if owner_button.disabled: color = color.darkened(0.13)
	var rng := RandomNumberGenerator.new()
	rng.seed = paper_seed
	var edge := PackedVector2Array()
	for i in range(ceili(rect.size.x / 19.0) + 1):
		var t := minf(float(i) * 19.0, rect.size.x)
		edge.append(rect.position + Vector2(t, 0.0 if t == 0.0 or t == rect.size.x else rng.randf_range(-1.1, 1.1)))
	for i in range(1, ceili(rect.size.y / 17.0) + 1):
		var t := minf(float(i) * 17.0, rect.size.y)
		edge.append(rect.position + Vector2(rect.size.x + (0.0 if t == 0.0 or t == rect.size.y else rng.randf_range(-1.1, 1.1)), t))
	for i in range(1, ceili(rect.size.x / 19.0) + 1):
		var t := minf(float(i) * 19.0, rect.size.x)
		edge.append(rect.end - Vector2(t, 0.0 if t == 0.0 or t == rect.size.x else rng.randf_range(-1.1, 1.1)))
	for i in range(1, ceili(rect.size.y / 17.0)):
		var t := minf(float(i) * 17.0, rect.size.y)
		edge.append(rect.position + Vector2(0.0 if t == 0.0 or t == rect.size.y else rng.randf_range(-1.1, 1.1), rect.size.y - t))
	var is_button: bool = get_parent() is BaseButton
	var shadow := PackedVector2Array()
	var shadow_offset := Vector2(0.7, 1.0) if is_button else Vector2(2.0, 3.0)
	for p in edge: shadow.append(p + shadow_offset)
	draw_colored_polygon(shadow, Color(0.12, 0.08, 0.05, 0.12 if is_button else 0.24))
	draw_colored_polygon(edge, color)
	for i in range(mini(90, int(rect.get_area() / 3600.0))):
		var broad_radius := minf(rng.randf_range(12.0, 42.0), minf(rect.size.x, rect.size.y) * 0.40)
		var margin := broad_radius * 1.1 + 2.0
		var center := rect.position + Vector2(rng.randf_range(margin, rect.size.x - margin), rng.randf_range(margin, rect.size.y - margin))
		var stain := PackedVector2Array()
		for j in range(8):
			var p := center + Vector2.from_angle(TAU * float(j) / 8.0) * broad_radius * rng.randf_range(0.6, 1.1)
			stain.append(p)
		draw_colored_polygon(stain, Color(0.35, 0.24, 0.13, 0.026))
	# Fibres and pressed folds stay in paper-space rather than becoming a
	# screen-sized noise overlay. Their fixed seed keeps comparisons stable.
	var count := mini(2200, int(rect.get_area() / 240.0))
	for i in range(count):
		var p := rect.position + Vector2(rng.randf_range(3.0, rect.size.x - 3.0), rng.randf_range(3.0, rect.size.y - 3.0))
		var shade := Color(0.31, 0.22, 0.12, rng.randf_range(0.045, 0.12))
		if i % 4 == 0:
			draw_circle(p, rng.randf_range(1.2, 3.8), Color(0.40, 0.28, 0.15, 0.035))
		else:
			draw_line(p, p + Vector2(rng.randf_range(0.6, 3.4), rng.randf_range(-1.0, 1.0)), shade, 0.7, true)
	for i in range(maxi(1, int(rect.size.x / 135.0))):
		var x := rect.position.x + rng.randf_range(9.0, rect.size.x - 9.0)
		var y := rect.position.y + rng.randf_range(4.0, maxf(5.0, rect.size.y - 16.0))
		var length := minf(rng.randf_range(12.0, 34.0), rect.end.y - y - 3.0)
		var drift := rng.randf_range(-2.8, 2.8)
		draw_line(Vector2(x, y), Vector2(x + drift, y + length), Color(0.35, 0.25, 0.14, 0.16), 1.0, true)
		draw_line(Vector2(x + 1.2, y), Vector2(x + drift + 1.2, y + length), Color(1.0, 0.91, 0.70, 0.23), 1.0, true)
	if not is_button:
		edge.append(edge[0])
		draw_polyline(edge, Color(0.36, 0.25, 0.14, 0.36), 1.0, true)
	if ink_frame:
		var r := rect.grow(-3.0)
		var frame := PackedVector2Array([r.position + Vector2(2, 0), Vector2(r.position.x + r.size.x * 0.42, r.position.y + 0.6), Vector2(r.end.x - 2, r.position.y - 0.3), Vector2(r.end.x, r.position.y + 2), Vector2(r.end.x - 0.6, r.position.y + r.size.y * 0.58), r.end - Vector2(0, 2), r.end - Vector2(2, 0), Vector2(r.position.x + r.size.x * 0.52, r.end.y - 0.6), Vector2(r.position.x + 2, r.end.y + 0.2), Vector2(r.position.x, r.end.y - 2), Vector2(r.position.x + 0.5, r.position.y + r.size.y * 0.39), r.position + Vector2(0, 2), r.position + Vector2(2, 0)])
		draw_polyline(frame, ink, 2.6, true)

func line(points: Array, width := 3.0) -> void:
	var vertices := PackedVector2Array()
	for point in points: vertices.append(Vector2(point[0], point[1]) * size)
	draw_polyline(vertices, ink, width, true)

func polygon(points: Array, color: Color = Color("342b22")) -> void:
	var vertices := PackedVector2Array()
	for point in points: vertices.append(Vector2(point[0], point[1]) * size)
	draw_colored_polygon(vertices, color)

func draw_icon() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.28
	match icon:
		"target":
			draw_arc(center, radius, 0, TAU, 32, ink, 4.0, true)
			line([[0.5, 0.08], [0.5, 0.33]], 4.0)
			line([[0.5, 0.67], [0.5, 0.92]], 4.0)
			line([[0.08, 0.5], [0.33, 0.5]], 4.0)
			line([[0.67, 0.5], [0.92, 0.5]], 4.0)
		"shield":
			polygon([[0.5,0.12],[0.77,0.23],[0.73,0.60],[0.63,0.76],[0.5,0.87],[0.36,0.75],[0.27,0.59],[0.23,0.23]])
			line([[0.49,0.20],[0.49,0.76]], 2.0)
		"patrol":
			line([[.18,.32],[.80,.32],[.80,.65]],4.0)
			line([[.82,.72],[.20,.72],[.20,.40]],4.0)
			polygon([[.67,.53],[.80,.72],[.93,.53]])
			polygon([[.07,.49],[.20,.30],[.33,.49]])
		"focus":
			for corner in [[.20,.20],[.80,.20],[.20,.80],[.80,.80]]:
				var x: float = corner[0]
				var y: float = corner[1]
				line([[x, y+(.15 if y<.5 else -.15)],[x,y],[x+(.15 if x<.5 else -.15),y]],3.5)
			draw_circle(center,5.0,ink)
		"hand":
			polygon([[0.30,0.14],[0.67,0.14],[0.85,0.32],[0.85,0.69],[0.67,0.87],[0.30,0.87],[0.13,0.69],[0.13,0.32]])
			var cream := Color("e4cca3")
			var hand := PackedVector2Array([Vector2(0.38,0.67),Vector2(0.31,0.43),Vector2(0.37,0.39),Vector2(0.42,0.50),Vector2(0.42,0.29),Vector2(0.47,0.27),Vector2(0.49,0.48),Vector2(0.50,0.23),Vector2(0.55,0.23),Vector2(0.57,0.48),Vector2(0.58,0.29),Vector2(0.63,0.29),Vector2(0.64,0.51),Vector2(0.66,0.35),Vector2(0.71,0.36),Vector2(0.68,0.62),Vector2(0.61,0.75),Vector2(0.45,0.75)])
			for i in range(hand.size()): hand[i] *= size
			draw_colored_polygon(hand, cream)
		"wrench":
			polygon([[0.35,0.57],[0.63,0.30],[0.60,0.17],[0.70,0.09],[0.69,0.24],[0.80,0.29],[0.91,0.18],[0.90,0.34],[0.78,0.44],[0.65,0.43],[0.42,0.75],[0.32,0.84],[0.21,0.77],[0.23,0.66]])
			draw_circle(Vector2(0.31,0.73) * size, 3.0, Color("dec69a"))
		"flag":
			line([[0.35,0.82],[0.35,0.18]], 4.0)
			polygon([[0.38,0.20],[0.57,0.17],[0.76,0.23],[0.80,0.21],[0.78,0.56],[0.58,0.51],[0.38,0.55]])
			line([[0.12,0.81],[0.66,0.81]], 3.0)
			polygon([[0.13,0.81],[0.26,0.72],[0.26,0.90]])
		"bolt": polygon([[0.47,0.07],[0.81,0.07],[0.61,0.39],[0.83,0.39],[0.25,0.94],[0.42,0.54],[0.20,0.54]])
		"people":
			draw_circle(size * Vector2(0.39,0.30), radius * 0.55, ink)
			draw_circle(size * Vector2(0.70,0.29), radius * 0.48, ink)
			polygon([[0.12,0.80],[0.16,0.60],[0.29,0.48],[0.48,0.48],[0.62,0.60],[0.64,0.80]])
			polygon([[0.57,0.48],[0.77,0.46],[0.91,0.61],[0.91,0.80],[0.69,0.80],[0.66,0.60]])
		"logs":
			line([[0.20,0.63],[0.65,0.20],[0.78,0.23],[0.85,0.34],[0.81,0.45],[0.39,0.85]], 3.0)
			draw_arc(size * Vector2(0.27,0.73), radius * 0.52, 0, TAU, 20, ink, 3.0, true)
			draw_arc(size * Vector2(0.27,0.73), radius * 0.18, 0, TAU, 14, ink, 2.0, true)
			line([[0.41,0.64],[0.76,0.32]], 2.0)
			line([[0.36,0.58],[0.66,0.30]], 2.0)
		"gear":
			var points := PackedVector2Array()
			for i in range(48):
				var r := radius * (1.25 if i % 4 in [0,1] else 1.0)
				points.append(center + Vector2.from_angle(TAU * float(i) / 48.0) * r)
			draw_colored_polygon(points, ink)
			draw_circle(center, radius * 0.60, Color("e4cca3"))
		"menu":
			for y in [0.26,0.50,0.74]: line([[0.19,y],[0.81,y]], 4.0)
