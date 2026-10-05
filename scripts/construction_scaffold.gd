extends RefCounted

const VOLUME = preload("res://scripts/volume_models.gd")
static var meshes: Dictionary = {}

static func active(e: Dictionary) -> bool:
	return e.get("kind") == "building" and e.get("construction", {}) is Dictionary and not e.get("construction", {}).is_empty()

static func progress(e: Dictionary) -> float:
	return clampf(float(e.get("construction", {}).get("progress", 0.0)), 0.0, 1.0)

static func health_cap(e: Dictionary, spec: Dictionary) -> float:
	var initial: float = float(e.get("construction", {}).get("initial_hp", minf(50.0, float(spec.hp) * .03)))
	return initial + (float(spec.hp) - initial) * progress(e)

static func create_model(spec: Dictionary, team: int) -> Dictionary:
	var key: String = str(spec.get("size", 3)) + ":" + str(team)
	var side: float = float(spec.get("size", 3)) * .84
	var half: float = side * .5
	if not meshes.has(key):
		var frame = VOLUME.CraftMesh.new()
		var walls = VOLUME.CraftMesh.new()
		frame.box(Vector3(0, .065, 0), Vector3(side, .13, side), Color("b59b72"), false)
		for x in [-half, half]:
			for z in [-half, half]:
				frame.box(Vector3(x, 1.05, z), Vector3(.09, 2.1, .09), Color("826647"), false)
		for y in [.6, 1.25, 1.9]:
			for x in [-half, half]: frame.box(Vector3(x, y, 0), Vector3(.09, .085, side), Color("a28861"), false)
			for z in [-half, half]: frame.box(Vector3(0, y, z), Vector3(side, .085, .09), Color("a28861"), false)
		for x in [-half, half]:
			frame.line(Vector3(x, .2, -half), Vector3(x, 1.85, half), .045, Color("775a3c"))
		for z in [-half, half]:
			frame.line(Vector3(-half, .2, z), Vector3(half, 1.85, z), .045, Color("775a3c"))
		for i in range(6):
			frame.box(Vector3(-half + .15 + float(i) * (side - .3) / 5.0, 1.32, 0), Vector3(.16, .05, side + .12), Color("ad936b"), false)
		# A coloured temporary sign identifies the builder's side before completion.
		frame.box(Vector3(0, 1.67, half + .055), Vector3(.78, .4, .045), VOLUME.player_color(team), false)
		for row in range(5):
			for z in [-half + .22, half - .22]:
				walls.box(Vector3(0, .17 + float(row) * .22, z), Vector3(side - .42, .2, .18), Color("b9a17b"), false)
			walls.box(Vector3(-half + .22, .17 + float(row) * .22, 0), Vector3(.18, .2, side - .42), Color("a99169"), false)
		meshes[key] = [frame.mesh(), walls.mesh()]
	var root := Node3D.new()
	root.name = "ConstructionScaffold"
	var parts: Array[MeshInstance3D] = []
	for mesh in meshes[key]:
		var part := MeshInstance3D.new()
		part.mesh = mesh
		part.visible = false
		root.add_child(part)
		parts.append(part)
	return {"root": root, "meshes": parts, "dimensions": Vector3(side + .18, 2.1, side + .18), "height": 2.1, "turret": null, "muzzle": null, "aircraft": false, "infantry": false, "cargo_count": 0, "smoke_ports": [], "player_color": VOLUME.player_color(team)}

static func update_model(model: Dictionary, e: Dictionary) -> void:
	var structure: MeshInstance3D = model.meshes[1]
	structure.scale.y = maxf(.02, progress(e))
