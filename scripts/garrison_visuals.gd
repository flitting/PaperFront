extends RefCounted

const Operations = preload("res://scripts/garrison_operations.gd")
const Volume = preload("res://scripts/volume_models.gd")
const Map = preload("res://scripts/map_data.gd")

## Applied paint bands, sandbags and visible occupied firing ports identify
## ownership/count without replacing or recoloring the neutral architecture.
static func sync(landscape: Node3D, sim) -> void:
	var visuals: Dictionary = landscape.get_meta("garrison_visuals", {})
	for ruin: Dictionary in sim.ruins:
		if not Operations.suitable(ruin): continue
		var count: int = ruin.get("garrison", []).size()
		var id: int = int(ruin.id)
		var team: int = int(ruin.get("garrison_team", -1))
		var stamp: String = "%d:%d" % [team,count]
		var old: Node3D = visuals.get(id)
		if count == 0:
			if is_instance_valid(old): old.queue_free(); visuals.erase(id)
			continue
		if is_instance_valid(old) and old.get_meta("stamp", "") == stamp:
			old.visible = sim.position_visible_to(0,ruin.pos) or team == 0
			continue
		if is_instance_valid(old): old.queue_free()
		var root := Node3D.new()
		root.name = "GarrisonPaint_%d" % id
		root.position = Vector3(ruin.pos.x,Map.height_at(sim.map,ruin.pos),ruin.pos.y)
		root.set_meta("stamp",stamp)
		root.visible = sim.position_visible_to(0,ruin.pos) or team == 0
		landscape.add_child(root)
		visuals[id] = root
		var owner: Color = Volume.player_color(team)
		var half: Vector2 = ruin.half
		for side in range(4):
			var forward: Vector2 = Vector2.RIGHT.rotated(side*PI*.5)
			var extent: float = half.x if side%2==0 else half.y
			var position: Vector2 = forward * (extent+.03)
			_box(root,Vector3(position.x,.46,position.y),Vector3(.055,.27,1.65) if side%2==0 else Vector3(1.65,.27,.055),owner)
		var ports: Array[Vector3] = Operations.windows(ruin)
		for n in range(count):
			var p: Vector3 = ports[n%ports.size()]
			_box(root,p+Vector3(0,-.26,0),Vector3(.4,.14,.2),Color("b7a584"))
			_box(root,p+Vector3(0,-.12,0),Vector3(.15,.23,.15),owner)
			_box(root,p+Vector3(0,.04,0),Vector3(.14,.13,.14),Color("d4ae8f"))
	landscape.set_meta("garrison_visuals",visuals)

static func _box(parent: Node3D, center: Vector3, size: Vector3, color: Color) -> void:
	var box := BoxMesh.new()
	box.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	box.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = box
	instance.position = center
	parent.add_child(instance)
