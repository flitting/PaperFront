extends SceneTree

const V = preload("res://scripts/volume_models.gd")
var failures: Array[String] = []
var checks: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	V.configure_player_colors(["#35bba7","#35bba7","#db9470","#d2b43a"])
	check(V.player_color(0)==V.player_color(1),"different owners can use the same color")
	for faction in ["kestrel","rivet","iron","sky"]:
		for art in ["rifle","anti","engineer","demolition","tank","harvester","fighter"]:
			var spec: Dictionary = {"faction":faction,"art":art,"domain":"air" if art=="fighter" else "ground"}
			if art in V.INFANTRY_ART:
				check(not V.supports(spec,"unit"),"infantry returns to original contour-card renderer "+faction+"_"+art)
				continue
			var recipe: Dictionary = V._recipe(spec,"unit",0)
			check(not recipe.is_empty(),faction+"_"+art+" has a real model")
			if recipe.is_empty(): continue
			var footprint: float = maxf(recipe.dimensions.x,recipe.dimensions.z)
			if faction=="iron" and art=="harvester":
				var chassis: Vector3=recipe.body_mesh.get_aabb().size
				footprint=maxf(chassis.x,chassis.z)
			check(is_equal_approx(footprint,float(spec.get("logical_size",1))*.96),"unit visual footprint follows explicit logical_size "+faction+"_"+art)
			var near: Mesh = recipe.body_mesh
			var middle: Mesh = V.quality_mesh(near,0,"far")
			var distant: Mesh = V.quality_mesh(near,0,"extreme")
			check(near.get_instance_id()!=middle.get_instance_id() and near.get_instance_id()!=distant.get_instance_id(),"independent LOD meshes "+faction+"_"+art)
			check(distant.surface_get_array_len(0)<near.surface_get_array_len(0),"distant geometry is simpler "+faction+"_"+art)
	for art in ["drill","zeppelin","armored_train","rail","rail_junction"]:
		var spec: Dictionary = {"faction":"rivet" if art in ["drill","zeppelin"] else "iron","art":art,"rail_mask":3,"rail_ports":7}
		var kind: String = "building" if art in ["drill","rail","rail_junction"] else "unit"
		var model: Dictionary = V.create_model(spec,kind,0)
		check(not model.is_empty(),"new model exists "+art)
		if model.is_empty():continue
		var near: Mesh = model.meshes[0].mesh
		check(V.quality_mesh(near,0,"extreme").surface_get_array_len(0)<near.surface_get_array_len(0),"new model independent far geometry "+art)
		if art=="drill":
			V.update_model(model,{"state":"work","id":1,"construct_remaining":0},.3)
			check(absf(model.parts[0].node.rotation.y)>0,"drill visibly rotates while working")
			var flywheel: Dictionary = model.parts.filter(func(p):return p.role=="mine_flywheel")[0]
			check(absf(flywheel.node.rotation.x)>0,"side flywheel turns on its own horizontal axle while working")
			var spindle_angle: float = model.parts[0].node.rotation.y
			var wheel_angle: float = flywheel.node.rotation.x
			V.update_model(model,{"state":"work","id":1,"construct_remaining":2},.3)
			check(is_equal_approx(spindle_angle,model.parts[0].node.rotation.y) and is_equal_approx(wheel_angle,flywheel.node.rotation.x),"unfinished drill cannot animate either drive assembly")
			V.update_model(model,{"state":"waiting","id":1,"construct_remaining":0},.3)
			check(is_equal_approx(spindle_angle,model.parts[0].node.rotation.y) and is_equal_approx(wheel_angle,flywheel.node.rotation.x),"waiting or unpowered drill stops both drive assemblies")
			for part in model.parts:
				var middle: Mesh = V.quality_mesh(part.node.get_child(0).mesh,0,"far")
				var distant: Mesh = V.quality_mesh(part.node.get_child(0).mesh,0,"extreme")
				check(middle.get_instance_id()!=distant.get_instance_id(),"drill moving/damaged part has independent medium and far geometry "+str(part.role))
			V.update_model(model,{"state":"harvest","id":1,"construct_remaining":0,"hp":300},.1)
			check(model.parts[1].node.scale==Vector3.ONE,"damaged drill has a visible torn/charred gearbox state")
			V.update_model(model,{"state":"waiting","id":1,"construct_remaining":0,"hp":1000},.1)
			check(model.parts[1].node.scale==Vector3.ZERO,"healthy drill hides damaged geometry")
		model.root.free()
	for faction in ["kestrel","rivet","iron","sky"]:
		var hq: Dictionary = V._recipe({"art":"hq","faction":faction,"size":8},"building",0)
		for entry in [["factory",7],["airfield",7],["refinery",6]]:
			var recipe: Dictionary = V._recipe({"art":entry[0],"faction":faction,"size":entry[1]},"building",0)
			check(maxf(hq.dimensions.x,hq.dimensions.z)>maxf(recipe.dimensions.x,recipe.dimensions.z),"HQ is largest "+faction+"_"+entry[0])
		var factory: Dictionary = V.create_model({"art":"factory","faction":faction,"size":7},"building",0)
		var doors: Array = factory.parts.filter(func(p):return p.role=="production_door")
		check(not doors.is_empty(),"separate faction gate leaves "+faction)
		var gate_rest: Transform3D = doors[0].node.transform
		V.update_model(factory,{"id":1,"production_door":1.0},.1)
		check(doors[0].node.transform != gate_rest or not doors[0].node.visible,"factory door actually opens "+faction)
		factory.root.free()
	V.configure_player_colors()
	print("RTS_MODEL_REVISION ",JSON.stringify({"checks":checks,"failures":failures}))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
