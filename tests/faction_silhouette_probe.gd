extends RefCounted

# Geometry-only diagnostic. Every triangle uses its real transform and normal;
# the depth buffer resolves visible surfaces. Faction paint is never sampled.
# Each shape is fitted independently, so a scale tweak cannot pass as redesign.
const SIZE: int = 112
const VIEWS: Array[Vector2] = [Vector2(0,30),Vector2(45,30),Vector2(90,30)]
var records: Array[Dictionary] = []

func raster(model: Dictionary, view: Vector2) -> PackedFloat32Array:
	var yaw: float = deg_to_rad(view.x)
	var pitch: float = deg_to_rad(view.y)
	var direction := Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))
	var right := Vector3(cos(yaw),0,-sin(yaw))
	var up: Vector3 = direction.cross(right)
	var triangles: Array = []
	var minimum := Vector2.INF
	var maximum := -Vector2.INF
	var light := Vector3(.7,1.5,.9).normalized()
	for instance in model.meshes:
		var transform: Transform3D = instance.global_transform
		for surface in range(instance.mesh.get_surface_count()):
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count: int = indices.size() if not indices.is_empty() else vertices.size()
			for start in range(0,count,3):
				var points: Array[Vector2] = []
				var depths: Array[float] = []
				var normal := Vector3.ZERO
				for corner in range(3):
					var index: int = indices[start+corner] if not indices.is_empty() else start+corner
					var world: Vector3 = transform*vertices[index]
					var point := Vector2(world.dot(right),-world.dot(up))
					points.append(point)
					depths.append(world.dot(direction))
					minimum = minimum.min(point)
					maximum = maximum.max(point)
					if not normals.is_empty(): normal += (transform.basis*normals[index]).normalized()
				var shade: float = .24+.76*maxf(0.0,normal.normalized().dot(light))
				triangles.append({"points":points,"depths":depths,"shade":shade})
	var pixels := PackedFloat32Array()
	var buffer := PackedFloat32Array()
	pixels.resize(SIZE*SIZE)
	buffer.resize(SIZE*SIZE)
	buffer.fill(-1.0e20)
	if triangles.is_empty(): return pixels
	var extent: Vector2 = maximum-minimum
	var scale: float = float(SIZE-8)/maxf(.001,maxf(extent.x,extent.y))
	var offset: Vector2 = Vector2.ONE*float(SIZE)*.5-(minimum+maximum)*.5*scale
	for triangle in triangles:
		var a: Vector2 = triangle.points[0]*scale+offset
		var b: Vector2 = triangle.points[1]*scale+offset
		var c: Vector2 = triangle.points[2]*scale+offset
		var denominator: float = (b.y-c.y)*(a.x-c.x)+(c.x-b.x)*(a.y-c.y)
		if absf(denominator)<.000001: continue
		var low: Vector2 = a.min(b).min(c)
		var high: Vector2 = a.max(b).max(c)
		for y in range(maxi(0,floori(low.y)),mini(SIZE,ceili(high.y)+1)):
			for x in range(maxi(0,floori(low.x)),mini(SIZE,ceili(high.x)+1)):
				var p := Vector2(x+.5,y+.5)
				var w0: float = ((b.y-c.y)*(p.x-c.x)+(c.x-b.x)*(p.y-c.y))/denominator
				var w1: float = ((c.y-a.y)*(p.x-c.x)+(a.x-c.x)*(p.y-c.y))/denominator
				var w2: float = 1.0-w0-w1
				if w0<-.00001 or w1<-.00001 or w2<-.00001: continue
				var depth: float = w0*triangle.depths[0]+w1*triangle.depths[1]+w2*triangle.depths[2]
				var index: int = y*SIZE+x
				if depth>=buffer[index]:
					buffer[index] = depth
					pixels[index] = triangle.shade
	return pixels

func difference(a: PackedFloat32Array,b: PackedFloat32Array) -> Dictionary:
	var union: int = 0
	var changed: int = 0
	var gray: float = 0.0
	for index in range(a.size()):
		if a[index]<=0.0 and b[index]<=0.0: continue
		union += 1
		if (a[index]>0.0)!=(b[index]>0.0): changed += 1
		gray += absf(a[index]-b[index])
	return {"silhouette":float(changed)/maxi(1,union),"gray":gray/maxi(1,union),"union_pixels":union}

func check_pair(scene: Node3D,a_spec: Dictionary,b_spec: Dictionary,kind: String,key: String) -> Dictionary:
	var a: Dictionary = VolumeModels.create_model(a_spec,kind,0)
	var b: Dictionary = VolumeModels.create_model(b_spec,kind,0)
	if a.is_empty() or b.is_empty(): return {"key":key,"pass":false,"reason":"no solid geometry"}
	scene.add_child(a.root)
	scene.add_child(b.root)
	var views: Array[Dictionary] = []
	var silhouette_sum: float = 0.0
	var gray_sum: float = 0.0
	var silhouette_peak: float = 0.0
	var gray_peak: float = 0.0
	var sheet := Image.create(SIZE*6,SIZE,false,Image.FORMAT_RGBA8)
	for index in range(VIEWS.size()):
		var aa: PackedFloat32Array = raster(a,VIEWS[index])
		var bb: PackedFloat32Array = raster(b,VIEWS[index])
		var score: Dictionary = difference(aa,bb)
		score["yaw"] = VIEWS[index].x
		score["pitch"] = VIEWS[index].y
		views.append(score)
		silhouette_sum += score.silhouette
		gray_sum += score.gray
		silhouette_peak = maxf(silhouette_peak,score.silhouette)
		gray_peak = maxf(gray_peak,score.gray)
		for y in range(SIZE):
			for x in range(SIZE):
				var pixel: int = y*SIZE+x
				for side in [0,1]:
					var shade: float = aa[pixel] if side==0 else bb[pixel]
					sheet.set_pixel(index*SIZE*2+side*SIZE+x,y,Color(shade,shade,shade,1.0))
	var silhouette_mean: float = silhouette_sum/float(VIEWS.size())
	var gray_mean: float = gray_sum/float(VIEWS.size())
	var pass_result: bool = (silhouette_mean>=.20 and silhouette_peak>=.28) or (gray_mean>=.18 and gray_peak>=.25)
	var record: Dictionary = {"key":key,"a":a_spec.name,"b":b_spec.name,"kind":kind,"silhouette_mean":silhouette_mean,"silhouette_peak":silhouette_peak,"gray_mean":gray_mean,"gray_peak":gray_peak,"views":views,"pass":pass_result}
	records.append(record)
	var folder: String = ProjectSettings.globalize_path("res://artifacts/faction_validation/")
	DirAccess.make_dir_recursive_absolute(folder)
	sheet.save_png(folder.path_join("geometry_"+key+".png"))
	a.root.free()
	b.root.free()
	return record

func run(scene: Node3D,rules: Dictionary) -> Array[Dictionary]:
	records.clear()
	for role in ["hq","power","refinery","barracks","factory","tech","tower","outpost","repair","command","airfield"]:
		if not rules.buildings.has("rivet_"+role) or not rules.buildings.has("kestrel_"+role): continue
		check_pair(scene,rules.buildings["rivet_"+role],rules.buildings["kestrel_"+role],"building",role)
	for role in ["tank","harvester","scout","aa","fighter","advanced"]:
		check_pair(scene,rules.units["rivet_"+role],rules.units["kestrel_"+role],"unit",role)
	check_pair(scene,rules.units.rivet_assault,rules.units.kestrel_artillery,"unit","artillery")
	check_pair(scene,rules.units.rivet_bomber,rules.units.kestrel_attacker,"unit","strike_aircraft")
	# Fighter and ground strike aircraft must also differ within each faction.
	check_pair(scene,rules.units.rivet_fighter,rules.units.rivet_bomber,"unit","rivet_air_roles")
	check_pair(scene,rules.units.kestrel_fighter,rules.units.kestrel_attacker,"unit","kestrel_air_roles")
	for role in ["rifle","anti","engineer"]: check_paper_pair(rules.units["rivet_"+role],rules.units["kestrel_"+role],role)
	var output: String = "res://artifacts/faction_validation/geometry_comparison.json"
	var file: FileAccess = FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"method":"depth-buffered grayscale projections from actual mesh vertices/normals; faction paint ignored; independent scale fit","views":VIEWS,"silhouette_min_mean":.20,"silhouette_min_peak":.28,"gray_min_mean":.18,"gray_min_peak":.25,"pairs":records},"\t"))
	return records


func paper_pixels(path: String) -> PackedFloat32Array:
	var texture: Texture2D = load(path)
	var image: Image = texture.get_image()
	var bounds: Rect2i = image.get_used_rect()
	var cropped: Image = image.get_region(bounds)
	var factor: float = float(SIZE-8)/maxi(1,maxi(cropped.get_width(),cropped.get_height()))
	cropped.resize(maxi(1,roundi(cropped.get_width()*factor)),maxi(1,roundi(cropped.get_height()*factor)),Image.INTERPOLATE_NEAREST)
	var pixels := PackedFloat32Array()
	pixels.resize(SIZE*SIZE)
	var offset := Vector2i((SIZE-cropped.get_width())/2,(SIZE-cropped.get_height())/2)
	for y in range(cropped.get_height()):
		for x in range(cropped.get_width()):
			if cropped.get_pixel(x,y).a>.3: pixels[(y+offset.y)*SIZE+x+offset.x]=1.0
	return pixels

func check_paper_pair(a: Dictionary,b: Dictionary,role: String) -> Dictionary:
	var states: Array[Dictionary] = []
	var total: float = 0.0
	var weakest: float = 1.0
	var sheet := Image.create(SIZE*5,SIZE*2,false,Image.FORMAT_RGBA8)
	var column: int = 0
	for state in ["idle","move","attack","hit","death"]:
		var aa: PackedFloat32Array = paper_pixels(str(a.animations[state]))
		var bb: PackedFloat32Array = paper_pixels(str(b.animations[state]))
		var score: Dictionary = difference(aa,bb)
		score["state"] = state
		states.append(score)
		total += score.silhouette
		weakest = minf(weakest,score.silhouette)
		for y in range(SIZE):
			for x in range(SIZE):
				for side in [0,1]:
					var shade: float = aa[y*SIZE+x] if side==0 else bb[y*SIZE+x]
					sheet.set_pixel(column*SIZE+x,side*SIZE+y,Color(shade,shade,shade,1.0))
		column += 1
	var record: Dictionary = {"key":"paper_"+role,"a":a.name,"b":b.name,"kind":"paper","silhouette_mean":total/5.0,"silhouette_minimum":weakest,"states":states,"pass":total/5.0>=.20 and weakest>=.12}
	records.append(record)
	sheet.save_png(ProjectSettings.globalize_path("res://artifacts/faction_validation/geometry_paper_"+role+".png"))
	return record
