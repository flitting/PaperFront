extends SceneTree

## Real renderer verification for every wiki asset, without a battle scene.
const PREVIEW = preload("res://scripts/wiki_model_preview.gd")
var failures: Array[String] = []
var captures: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/wiki"))
	var preview: WikiModelPreview = PREVIEW.new()
	root.add_child(preview)
	preview.size = Vector2(640, 400)
	preview.set_rotation_active(false)
	var rules: Dictionary = RulesLoader.load_rules()
	for kind in ["unit", "building"]:
		var source: Dictionary = rules.units if kind == "unit" else rules.buildings
		for id in source:
			await capture(preview, source[id], kind, id, 0, 0.0)
	for fixture in [
		["kestrel_rifle", 1, 0.0],
		["kestrel_rifle", 1, PI * 0.5],
		["rivet_anti", 1, 0.8],
		["rivet_harvester", 1, 2.4],
		["kestrel_airfield", 1, 1.7],
		["rivet_command", 1, 1.0],
	]:
		var kind: String = "unit" if rules.units.has(fixture[0]) else "building"
		var spec: Dictionary = rules.units[fixture[0]] if kind == "unit" else rules.buildings[fixture[0]]
		await capture(preview, spec, kind, fixture[0], fixture[1], fixture[2])
	var sheet := Image.create(1920, 800, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("efdfbe"))
	for index in range(6):
		var entry: Dictionary = captures[captures.size() - 6 + index]
		var pixels := Image.new()
		pixels.load(ProjectSettings.globalize_path(entry.path))
		sheet.blend_rect(pixels, Rect2i(Vector2i.ZERO, pixels.get_size()), Vector2i((index % 3) * 640, (index / 3) * 400))
	sheet.save_png("res://artifacts/wiki/preview_contact_sheet.png")
	var file := FileAccess.open("res://artifacts/wiki/preview_capture_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"count": captures.size(), "failures": failures, "captures": captures}, "\t"))
	file.close()
	print("WIKI_RENDER ", JSON.stringify({"count": captures.size(), "failures": failures}))
	preview.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)


func capture(preview: WikiModelPreview, spec: Dictionary, kind: String, id: String, team: int, yaw: float) -> void:
	preview.set_entry(spec, kind, team)
	preview.angle = yaw
	preview.rotation_pivot.rotation.y = yaw
	preview._request_redraw()
	for frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var pixels: Image = preview.viewport.get_texture().get_image()
	var opaque: int = 0
	var border: int = 0
	for y in range(pixels.get_height()):
		for x in range(pixels.get_width()):
			if pixels.get_pixel(x, y).a > 0.08:
				opaque += 1
				if x < 3 or y < 3 or x >= pixels.get_width() - 3 or y >= pixels.get_height() - 3: border += 1
	if opaque < 100: failures.append(id + ": blank rendered preview")
	if border > 0: failures.append(id + ": rendered preview clips at its edge")
	if pixels.get_pixel(0, 0).a > 0.001: failures.append(id + ": model viewport is not transparent")
	var path: String = "res://artifacts/wiki/%s_team%d_yaw%d.png" % [id, team, roundi(rad_to_deg(yaw))]
	if pixels.save_png(path) != OK: failures.append(id + ": capture failed to save")
	captures.append({"id": id, "team": team, "yaw": yaw, "path": path, "opaque_pixels": opaque, "border_pixels": border, "camera_size": preview.camera.size})
