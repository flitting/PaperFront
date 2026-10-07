extends SceneTree
const V = preload("res://scripts/volume_models.gd")
const A = preload("res://scripts/architecture_revision.gd")
var failures: Array[String] = []
var checks: int = 0
func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func _initialize() -> void: call_deferred("run")
func vertices(mesh: Mesh) -> int:
	var count: int = 0
	for i in range(mesh.get_surface_count()): count += mesh.surface_get_array_len(i)
	return count
func aisle_clear(mesh: Mesh, service: bool = false) -> bool:
	for surface in range(mesh.get_surface_count()):
		var points: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for x in ([-.90,0.0,.90] if service else [-1.20,0.0,1.20]):
			for y in ([.55,1.1,1.5] if service else [.25,1.1,2.40]):
				for index in range(0,points.size(),3):
					if Geometry3D.segment_intersects_triangle(Vector3(x,y,0),Vector3(x,y,4),points[index],points[index+1],points[index+2]) != null: return false
	return true
func run() -> void:
	for faction in ["kestrel","rivet","iron","sky"]:
		for art in ["factory","refinery","repair"]:
			var spec: Dictionary = {"faction":faction,"art":art,"size":6 if art == "factory" else 5 if art == "refinery" else 4}
			var recipe: Dictionary = V._recipe(spec,"building",0)
			check(aisle_clear(recipe.body_mesh,art == "repair"),"unobstructed 2.4m front aisle: "+faction+" "+art)
			var model: Dictionary = V.create_model(spec,"building",0)
			root.add_child(model.root)
			var gates: Array = model.parts.filter(func(p): return p.role == "production_door")
			var mode: String = {"kestrel":"slide","rivet":"hinge","iron":"roll","sky":"phase"}[faction]
			if art != "repair":
				check(not gates.is_empty() and gates.all(func(p): return p.gate_mode == mode),"faction door mechanism: "+faction)
				var body_rest: Transform3D = model.body.transform
				var root_rest: Transform3D = model.root.transform
				var first: Dictionary = gates[0]
				var gate_rest: Transform3D = first.node.transform
				V.update_model(model,{"id":1,"production_door":1.0,"state":"emerging"},1.0)
				check(model.body.transform==body_rest and model.root.transform==root_rest,"production never moves whole building: "+faction+" "+art)
				check(first.node.transform != gate_rest or not first.node.visible,"gate truly opens: "+faction)
				if faction == "sky":check((first.node.position.x-first.rest.x)*first.side>0,"sky leaves move toward outside emitters")
				V.update_model(model,{"id":1,"production_door":0.0,"state":"idle"},.25)
				check(first.node.transform.is_equal_approx(gate_rest),"gate returns to closed transform: "+faction)
			else:
				check(gates.is_empty(),"open service cradle has no blocking door")
			var idle_parts: Array = model.parts.filter(func(p): return str(p.role).begins_with("building_"))
			check(not idle_parts.is_empty(),"idle equipment exists: "+faction+" "+art)
			var device: Dictionary = idle_parts[0]
			var before: Transform3D = device.node.transform
			V.update_model(model,{"id":1,"state":"idle"},1.0)
			check(device.node.transform!=before,"equipment animates when idle: "+faction+" "+art)
			model.root.free()
		for art in A.ARTS:
			var spec: Dictionary = {"faction":faction,"art":art,"size":5 if art in ["factory","refinery"] else 4 if art in ["repair","shipyard"] else 3}
			var counts: Array[int] = []
			for tier in range(3):
				var recipe: Dictionary = V._raw_recipe(spec,"building",0,tier)
				check(not recipe.is_empty() and recipe.dimensions.y > .1,"valid architectural recipe: "+faction+" "+art+" "+str(tier))
				counts.append(vertices(recipe.body_mesh))
			check(counts[0]>counts[1] and counts[1]>=counts[2],"LOD removes geometry: "+faction+" "+art)
		var yard: Dictionary = V._recipe({"faction":faction,"art":"shipyard","size":4},"building",0)
		check(yard.dimensions.x<=4.0 and yard.dimensions.z<=4.0,"shipyard stays on 4x4 footprint: "+faction)
	var sky_tech: Dictionary = V._recipe({"faction":"sky","art":"tech","size":3},"building",0)
	check(sky_tech.dimensions.y>sky_tech.dimensions.x*1.5,"sky research institute is a tall narrow leaf")
	var original: Dictionary = A.make({"art":"hq","size":8},"rivet",V.player_color(0),0)
	var hq: Dictionary = V._recipe({"faction":"rivet","art":"hq","size":8},"building",0)
	check(is_equal_approx(hq.dimensions.y,original.dimensions.y*.75*7.68/maxf(original.dimensions.x,original.dimensions.z)),"hammer headquarters preserves reduced height")
	print("ARCHITECTURE_REVISION ",JSON.stringify({"checks":checks,"failures":failures}))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
