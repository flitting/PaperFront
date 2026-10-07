extends SceneTree

## Reproducible visual-contract checks; uses the actual renderer and simulation.
func _initialize() -> void:
	call_deferred("check")

func check() -> void:
	var failures: Array[String] = []
	var contours: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/cards/contours.json"))
	for key in contours:
		var polygon := PackedVector2Array()
		for point in contours[key].outline:
			polygon.append(Vector2(point[0],point[1]))
		if Geometry2D.triangulate_polygon(polygon).is_empty():
			failures.append("Invalid cut contour: " + key)
		var image := Image.new()
		if image.load_svg_from_string(FileAccess.get_file_as_string(str(contours[key].get("path", "res://assets/cards/"+key+".svg")))) != OK:
			failures.append("Invalid SVG: " + key)
	var sim := WarSimulation.new()
	sim.setup(RulesLoader.load_rules(),"dev",73026,"rivet",false)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position=Vector3(24,30,52)
	camera.look_at(Vector3(24,0,24))
	var world := PaperWorld.new()
	root.add_child(world)
	world.setup(sim,camera)
	var id: int = sim.debug_spawn(0,"rivet_rifle",Vector2(12.5,25.5))
	var entity: Dictionary = sim.entities[id]
	for alpha in [0,79,80,81,90,135,180,-135,-90,-81,-80,-79]:
		entity.alpha=float(alpha)
		for yaw in [0,90,180,270]:
			camera.position=Vector3(24+cos(deg_to_rad(yaw))*30,30,24+sin(deg_to_rad(yaw))*30)
			camera.look_at(Vector3(24,0,24))
			world.sync(0,[id],{})
			var model: Dictionary = world.models[id]
			var depicted_heading: Vector3 = model.root.basis * model.art_root.basis * Vector3.RIGHT
			var heading := Vector3(cos(deg_to_rad(alpha)),0,sin(deg_to_rad(alpha)))
			if depicted_heading.normalized().dot(heading) < .999:
				failures.append("Muzzle reversed at alpha=%s, camera=%s" % [alpha,yaw])
			if model.volumetric or bool(model.root.get_meta("mirrored")) != (absf(float(alpha))>80.0):
				failures.append("Paper infantry 80-degree mirror boundary wrong at " + str(alpha))
			if not is_zero_approx(model.hp_root.rotation.y):
				failures.append("Paper infantry health bar lost its original card-plane orientation")
	var tank_id:int=sim.debug_spawn(0,"rivet_tank",Vector2(17.5,30.5))
	var tank_entity:Dictionary=sim.entities[tank_id]
	for alpha in [0,79,80,81,90,135,180,-135,-90,-81,-80,-79]:
		tank_entity.alpha=float(alpha)
		tank_entity.turret_alpha=wrapf(float(alpha)+73.0,-180,180)
		for yaw in [0,90,180,270]:
			camera.position=Vector3(24+cos(deg_to_rad(yaw))*30,30,24+sin(deg_to_rad(yaw))*30)
			camera.look_at(Vector3(24,0,24))
			world.sync(0,[tank_id],{})
			var model:Dictionary=world.models[tank_id]
			var body_heading:=Vector3(cos(deg_to_rad(alpha)),0,sin(deg_to_rad(alpha)))
			var aim_heading:=Vector3(cos(deg_to_rad(tank_entity.turret_alpha)),0,sin(deg_to_rad(tank_entity.turret_alpha)))
			if not model.volumetric or bool(model.root.get_meta("mirrored")) or model.root.global_basis.x.dot(body_heading)<.999:
				failures.append("Volume hull orientation wrong at %s / camera %s" % [alpha,yaw])
			if model.volume.turret.global_basis.x.dot(aim_heading)<.999:
				failures.append("Independent turret world aim wrong at %s / camera %s" % [alpha,yaw])
			var bar_normal:=Vector3(sin(world.camera_yaw),0,cos(world.camera_yaw))
			if model.hp_root.global_basis.z.dot(bar_normal)<.999:
				failures.append("Volume health bar no longer readable from orbit camera")
	entity.state="move"
	world.sync(.1,[id],{})
	if world.models[id].state != "move":failures.append("Move state not displayed")
	if world.models[id].volumetric:failures.append("Infantry unexpectedly uses a solid body")
	elif absf(world.models[id].art_root.rotation.z)<.0001 or world.models[id].art_root.position.y<=0:failures.append("Moving paper infantry lacks its original sway/bob")
	entity.state="idle"
	entity.attack_flash=.2
	world.sync(.1,[id],{})
	if world.models[id].state != "attack":failures.append("Attack flash not displayed")
	entity.hit_flash=.2
	world.sync(.1,[id],{})
	if world.models[id].state != "hit":failures.append("Hit card not displayed")
	sim.entities.erase(id)
	world.sync(.1,[],{})
	if world.ghosts.is_empty():failures.append("Death paper did not fall")
	print("ART_CHECK ", JSON.stringify({"cards":contours.size(),"infantry_orientation_cases":48,"volume_orientation_cases":48,"failures":failures}))
	world.queue_free()
	camera.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
