extends SceneTree

const V = preload("res://scripts/volume_models.gd")
const Sim = preload("res://tests/rule_test_simulation.gd")
var checks: int = 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func clear_aisle(mesh: Mesh, half_depth: float) -> bool:
	for surface in range(mesh.get_surface_count()):
		var vertices: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for x in [-.95,0.0,.95]:
			for y in [.25,1.0,2.25]:
				for index in range(0,vertices.size(),3):
					if Geometry3D.segment_intersects_triangle(Vector3(x,y,.05),Vector3(x,y,half_depth+.2),vertices[index],vertices[index+1],vertices[index+2]) != null: return false
	return true

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var original: Dictionary = load("res://scripts/faction_building_models.gd").make(V.CraftMesh.new(),"rivet","hq",0)
	var hq: Dictionary = V._recipe({"faction":"rivet","art":"hq","size":8},"building",0)
	var previous_height: float = original.dimensions.y*8*.96/maxf(original.dimensions.x,original.dimensions.z)
	check(hq.dimensions.y <= previous_height*.75,"redesigned rivet HQ retains reduced height")
	check(is_equal_approx(hq.dimensions.x,7.68) and is_equal_approx(hq.dimensions.z,7.68),"rivet HQ retains the eight-cell visual footprint")
	for faction in ["kestrel","rivet","iron","sky"]:
		for art in ["factory","refinery"]:
			var model: Dictionary = V.create_model({"faction":faction,"art":art,"size":6 if art == "factory" else 5},"building",0)
			var doors: Array = model.parts.filter(func(p): return p.role == "production_door")
			check(not doors.is_empty(),"functional faction-specific front door: "+faction+" "+art)
			check(clear_aisle(model.meshes[0].mesh,model.dimensions.z*.5),"real cutout keeps two-cell vehicle aisle clear: "+faction+" "+art)
			var door: Dictionary = doors[0]
			var bounds: AABB = door.node.get_child(0).mesh.get_aabb()
			check(model.definition.size>=5 and float(V._recipe(model.definition,"building",0).entrance.width)>=2.49,"two-cell vehicles fit reduced building gate: "+faction+" "+art)
			var root_rest: Transform3D = model.root.transform
			var body_rest: Transform3D = model.body.transform
			for fraction in [0.0,.25,.5,.75,1.0,.5,0.0]:
				V.update_model(model,{"id":12,"kind":"building","state":"emerging","production_door":fraction},.13)
				check(model.root.transform==root_rest and model.body.transform==body_rest,"only the door animates during production: "+faction+" "+art)
				if door.gate_mode == "roll":
					check(is_equal_approx(door.node.position.y,door.rest.y+door.travel*fraction),"roller follows open fraction: "+faction+" "+art)
				elif door.gate_mode == "hinge":
					check(is_equal_approx(door.node.rotation.y,door.side*fraction*PI*.5),"hinged gate follows open fraction: "+faction+" "+art)
				elif door.gate_mode == "slide":
					check(is_equal_approx(door.node.position.x,door.rest.x+door.side*door.travel*fraction),"sliding gate follows open fraction: "+faction+" "+art)
				else:
					check(door.node.scale.x <= 1.0,"phase gate remains bounded: "+faction+" "+art)
			model.root.free()
	var sim = Sim.new()
	sim.setup(RulesLoader.load_rules(),"dev",7,"rivet",false)
	for row in sim.map.terrain: row.fill(0)
	for row in sim.map.heights: row.fill(0.0)
	sim.mines.clear(); sim.bridges.clear(); sim.ruins.clear(); sim._refresh_ruin_spatial(); sim._prepare_terrain_cache()
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position=Vector3(28,20,46)
	camera.look_at(Vector3(28,0,28))
	var world := PaperWorld.new()
	root.add_child(world)
	world.setup(sim,camera)
	var id: int = sim._spawn(0,"rivet_hq",Vector2(28,28),true)
	world.sync(.01,[])
	var rendered: Dictionary = world.models[id]
	var model_root_rest: Transform3D = rendered.root.transform
	var model_body_rest: Transform3D = rendered.volume.body.transform
	var doors: Array = rendered.volume.parts.filter(func(p): return p.role == "production_door")
	check(doors.size()==2,"actual rivet HQ has a pair of hinged personnel leaves")
	var gate: Dictionary = doors[0]
	for native_mode in [false,true]:
		world.native_world_sync_enabled=native_mode
		for fraction in [0.0,.25,.5,.75,1.0,.5,0.0]:
			sim.entities[id].state="emerging"
			sim.entities[id].production_door=fraction
			world.sync(.13,[])
			check(rendered.root.transform==model_root_rest and rendered.volume.body.transform==model_body_rest,"HQ remains still through production in "+("native" if native_mode else "script"))
			check(is_equal_approx(gate.node.rotation.y,gate.side*fraction*PI*.5),"HQ door moves in "+("native" if native_mode else "script"))
	print("BUILDING_DOOR_REVISION ",JSON.stringify({"checks":checks,"failures":failures,"hq_height_before":previous_height,"hq_height_after":hq.dimensions.y}))
	world.queue_free(); camera.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
