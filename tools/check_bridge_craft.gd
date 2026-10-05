extends SceneTree

const CRAFT=preload("res://scripts/bridge_craft.gd")
var failures: Array[String]=[]
var checked_vertices: int=0
var largest_triangles: int=0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var builder:=PaperLandscape.new()
	for length: float in [6.0,10.0,14.0]:
		for breadth: float in [2.0,4.0]:
			for heading: float in [0.0,PI*.5]:
				var turn:=Basis(Vector3.UP,heading)
				var arch: Dictionary=builder._data()
				builder._bridge_arch(arch,length,breadth,turn)
				var detail: Dictionary=builder._data()
				CRAFT.arch(builder,detail,length,breadth,turn)
				check_on_surface(arch,detail,"arch")
				var foundation: Dictionary=builder._data()
				for side: float in [-1.0,1.0]:
					builder._box(foundation,turn*Vector3(side*(length*.5-.55),-2.65*.5,0),Vector3(.85,2.73,breadth),Color.WHITE,turn)
				var stone_detail: Dictionary=builder._data()
				CRAFT.abutments(builder,stone_detail,length,breadth,turn)
				check_on_surface(foundation,stone_detail,"abutments")
				var boards: Dictionary=builder._data()
				for index: int in ceili(length/.62):
					builder._box(boards,turn*Vector3(-length*.5+.30+index*.62,-.07,0),Vector3(minf(.58,length),.14,breadth),Color.WHITE,turn)
				var wood_detail: Dictionary=builder._data()
				CRAFT.planks(builder,wood_detail,length,breadth,turn)
				check_on_surface(boards,wood_detail,"planks")
				for point: Vector3 in wood_detail.vertices:
					if absf(point.y-CRAFT.OFFSET)>.00001:failures.append("board top height changed")
				var triangles: int=(detail.vertices.size()+stone_detail.vertices.size()+wood_detail.vertices.size())/3
				largest_triangles=maxi(largest_triangles,triangles)
	if largest_triangles>1600:failures.append("detail triangle budget exceeded")
	print("BRIDGE_CRAFT_CHECK ",JSON.stringify({"cases":12,"checked_vertices":checked_vertices,"max_detail_triangles":largest_triangles,"facet_offset":CRAFT.OFFSET,"failures":failures}))
	if "--capture" in OS.get_cmdline_user_args():
		await capture(builder)
	builder.free()
	quit(0 if failures.is_empty() else 1)

func check_on_surface(base: Dictionary, detail: Dictionary, stage: String) -> void:
	for index: int in range(0,detail.vertices.size(),3):
		var a: Vector3=detail.vertices[index]
		var b: Vector3=detail.vertices[index+1]
		var c: Vector3=detail.vertices[index+2]
		var normal: Vector3=detail.normals[index]
		if (b-a).cross(c-a).dot(normal)>=0:failures.append(stage+": inward winding")
	for index: int in detail.vertices.size():
		checked_vertices+=1
		var point: Vector3=detail.vertices[index]
		var normal: Vector3=detail.normals[index]
		var support: bool=false
		for triangle: int in range(0,base.vertices.size(),3):
			if normal.dot(base.normals[triangle])<.999:continue
			var a: Vector3=base.vertices[triangle]
			var b: Vector3=base.vertices[triangle+1]
			var c: Vector3=base.vertices[triangle+2]
			# Measure attachment to the authoritative facet plane. The normal
			# of a tiny clipped triangle carries greater float rounding error.
			var facet_normal: Vector3=base.normals[triangle]
			var gap: float=(point-a).dot(facet_normal)
			if absf(gap-CRAFT.OFFSET)>.00002:continue
			var projected: Vector3=point-facet_normal*gap
			var ab: Vector3=b-a
			var ac: Vector3=c-a
			var ap: Vector3=projected-a
			var denominator: float=ab.dot(ab)*ac.dot(ac)-ab.dot(ac)*ab.dot(ac)
			if absf(denominator)<.000001:continue
			var u: float=(ac.dot(ac)*ap.dot(ab)-ab.dot(ac)*ap.dot(ac))/denominator
			var v: float=(ab.dot(ab)*ap.dot(ac)-ab.dot(ac)*ap.dot(ab))/denominator
			if u>=-.0001 and v>=-.0001 and u+v<=1.0001:
				support=true
				break
		if not support:failures.append(stage+": overlay outside actual facet "+str(point)+" normal "+str(normal))

func capture(builder) -> void:
	root.size=Vector2i(1280,900)
	var scene:=Node3D.new()
	root.add_child(scene)
	var data: Dictionary=builder._data()
	var length: float=10.0
	var breadth: float=3.0
	builder._bridge_arch(data,length,breadth,Basis.IDENTITY)
	CRAFT.arch(builder,data,length,breadth,Basis.IDENTITY)
	for side: float in [-1.0,1.0]:
		builder._box(data,Vector3(side*(length*.5-.55),-1.325,0),Vector3(.85,2.73,breadth),Color("a99a82"))
	CRAFT.abutments(builder,data,length,breadth,Basis.IDENTITY)
	for index: int in ceili(length/.62):
		builder._box(data,Vector3(-length*.5+.30+index*.62,-.07,0),Vector3(.58,.14,breadth),Color("a39171").lightened((index%3)*.025))
	CRAFT.planks(builder,data,length,breadth,Basis.IDENTITY)
	for side: float in [-1.0,1.0]:
		builder._box(data,Vector3(0,.64,side*breadth*.47),Vector3(length,.1,.09),Color("75634a"))
		for index: int in ceili(length/1.45):builder._box(data,Vector3(-length*.5+.23+index*1.45,.36,side*breadth*.47),Vector3(.105,.85,.105),Color("897455"))
	var graphic:=MeshInstance3D.new()
	graphic.mesh=builder._finish(data)
	scene.add_child(graphic)
	var camera:=Camera3D.new()
	scene.add_child(camera)
	camera.position=Vector3(10,7,15)
	camera.look_at(Vector3(0,-1.9,0))
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=14
	camera.current=true
	var light:=DirectionalLight3D.new()
	scene.add_child(light)
	light.rotation_degrees=Vector3(-48,-25,0)
	light.light_energy=.95
	light.shadow_enabled=true
	var env:=WorldEnvironment.new()
	scene.add_child(env)
	env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color("374a4d")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color("e6d5b5")
	env.environment.ambient_light_energy=.6
	for frame: int in range(12):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/visual_iteration/v44_reference_rebuild/bridge/bridge_preview.png")
