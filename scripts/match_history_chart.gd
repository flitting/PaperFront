extends Control
class_name MatchHistoryChart

## A native, read-only plot of authoritative match samples. No interpolated
## samples are created: hovering inspects the nearest recorded simulation tick.
const INK := Color("392c21")
const GRID := Color("d8c9af")
var metric := ""
var series: Array[Dictionary] = []
var sample_times: Array[float] = []
var end_time := 0.0
var start_time := 0.0
var value_max := 1.0
var font_size := 22
var hovered_sample := -1
var empty_text := "本局没有可用的时间曲线"

func _ready() -> void:
	custom_minimum_size.y = 250
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(_clear_hover)
	resized.connect(queue_redraw)

func configure(history: Array, players: Array, field: String, duration: float, since_time: float = 0.0) -> void:
	metric = field
	end_time = maxf(0.0, duration)
	start_time = maxf(0.0, since_time)
	series.clear()
	sample_times.clear()
	hovered_sample = -1
	for index: int in players.size():
		var row: Dictionary = players[index]
		series.append({"team":int(row.get("team", index)), "name":str(row.get("chart_name", "玩家 %d" % (index + 1))), "color":row.get("chart_color", Color("386b70")), "values":[]})
	for sample: Variant in history:
		if not sample is Dictionary or not sample.get("teams", []) is Array:
			continue
		var stamp: float = float(sample.get("time", 0.0))
		if not sample_times.is_empty() and stamp < sample_times.back():
			continue
		sample_times.append(stamp)
		var rows: Dictionary = {}
		for index: int in sample.teams.size():
			var row: Dictionary = sample.teams[index]
			rows[int(row.get("team", index))] = row
		for line: Dictionary in series:
			var row: Dictionary = rows.get(int(line.team), {})
			# Absent fields in historical saves remain gaps instead of invented zeros.
			line.values.append(maxf(0.0, float(row[field])) if row.has(field) else null)
	value_max = 1.0
	for line: Dictionary in series:
		for value: Variant in line.values:
			if value != null: value_max = maxf(value_max, float(value))
	value_max = ceil(value_max / 4.0) * 4.0 if value_max <= 20.0 else _nice_ceiling(value_max)
	if not sample_times.is_empty():
		start_time = minf(start_time, sample_times[0])
		end_time = maxf(end_time, sample_times.back())
	queue_redraw()

func set_font_scale(correction: float) -> void:
	font_size = ceili(22.0 * correction)
	custom_minimum_size.y = 250.0 * correction
	queue_redraw()

func has_recorded_values() -> bool:
	for line: Dictionary in series:
		for value: Variant in line.values:
			if value != null: return true
	return false

func plot_rect() -> Rect2:
	return Rect2(Vector2(85.0, 12.0), Vector2(maxf(1.0, size.x - 110.0), maxf(1.0, size.y - 60.0)))

func point_for(sample_index: int, value: float) -> Vector2:
	var plot := plot_rect()
	var elapsed: float = maxf(0.000001, end_time - start_time)
	return Vector2(plot.position.x + (sample_times[sample_index] - start_time) / elapsed * plot.size.x, plot.end.y - value / value_max * plot.size.y)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not sample_times.is_empty():
		if not plot_rect().has_point(event.position):
			_clear_hover()
			return
		var plot := plot_rect()
		var stamp: float = start_time + (event.position.x - plot.position.x) / plot.size.x * maxf(0.000001, end_time - start_time)
		# Binary search keeps inspection cheap even in long headless matches.
		var lo := 0
		var hi := sample_times.size() - 1
		while lo < hi:
			var mid: int = (lo + hi) / 2
			if sample_times[mid] < stamp: lo = mid + 1
			else: hi = mid
		if lo > 0 and absf(sample_times[lo - 1] - stamp) < absf(sample_times[lo] - stamp): lo -= 1
		hovered_sample = lo
		queue_redraw()

func _clear_hover() -> void:
	hovered_sample = -1
	queue_redraw()

func _draw() -> void:
	var font: Font = get_theme_default_font()
	var plot := plot_rect()
	draw_rect(plot, Color("fff9ed"))
	for tick: int in range(5):
		var y: float = plot.end.y - plot.size.y * float(tick) / 4.0
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), GRID, 1.0)
		var text: String = format_value(value_max * float(tick) / 4.0)
		draw_string(font, Vector2(plot.position.x - 10.0 - font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x, y + font_size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, INK)
	for tick: int in range(5):
		var x: float = plot.position.x + plot.size.x * float(tick) / 4.0
		draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), GRID, 1.0)
		var text: String = format_time(start_time + (end_time - start_time) * float(tick) / 4.0)
		var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, Vector2(clampf(x - width * 0.5, 0.0, size.x - width), plot.end.y + font_size + 10.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, INK)
	draw_rect(plot, Color("b29771"), false, 1.0)
	if not has_recorded_values():
		var width: float = font.get_string_size(empty_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, Vector2(maxf(plot.position.x + 8.0, plot.get_center().x - width * 0.5), plot.get_center().y), empty_text, HORIZONTAL_ALIGNMENT_LEFT, plot.size.x - 16.0, font_size, INK)
		return
	for line: Dictionary in series:
		var segment := PackedVector2Array()
		for index: int in line.values.size():
			if line.values[index] == null:
				_draw_segment(segment, line.color)
				segment.clear()
			else: segment.append(point_for(index, float(line.values[index])))
		_draw_segment(segment, line.color)
	if hovered_sample >= 0: _draw_inspection(font, plot)

func _draw_segment(points: PackedVector2Array, color: Color) -> void:
	if points.size() == 1: draw_circle(points[0], 4.0, color)
	elif points.size() > 1: draw_polyline(points, color, 3.0, true)

func _draw_inspection(font: Font, plot: Rect2) -> void:
	var x: float = point_for(hovered_sample, 0.0).x
	draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), INK, 1.0)
	var rows: Array[String] = ["记录时间 " + format_time(sample_times[hovered_sample]) + " · %.2f 秒" % sample_times[hovered_sample]]
	var width := 0.0
	for line: Dictionary in series:
		var value: Variant = line.values[hovered_sample]
		rows.append(str(line.name) + "  " + ("—" if value == null else "%.0f" % float(value)))
		if value != null: draw_circle(point_for(hovered_sample, float(value)), 5.0, line.color)
	for row: String in rows: width = maxf(width, font.get_string_size(row, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	var box := Rect2(Vector2(clampf(x + 14.0, 0.0, size.x - width - 24.0), plot.position.y + 10.0), Vector2(width + 24.0, (font_size + 8.0) * rows.size() + 12.0))
	draw_rect(box, Color("f5e8cc"))
	draw_rect(box, Color("b29771"), false, 1.0)
	for index: int in rows.size():
		draw_string(font, box.position + Vector2(12.0, 8.0 + font_size + index * (font_size + 8.0)), rows[index], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, INK if index == 0 else series[index - 1].color)

static func _nice_ceiling(value: float) -> float:
	var magnitude: float = pow(10.0, floor(log(maxf(1.0, value)) / log(10.0)))
	return ceil(value / magnitude / 0.25) * magnitude * 0.25

static func format_value(value: float) -> String:
	if value >= 1000000.0: return "%.1fm" % (value / 1000000.0)
	if value >= 10000.0: return "%.1fk" % (value / 1000.0)
	return "%.0f" % value

static func format_time(seconds: float) -> String:
	var whole: int = maxi(0, roundi(seconds))
	return "%02d:%02d" % [whole / 60, whole % 60]
