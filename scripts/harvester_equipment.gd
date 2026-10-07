extends RefCounted
## Mechanical mining cycle attached before model measurement/scaling and LOD
## registration: moving parts participate in the same batches as the chassis.
static func attach(recipe: Dictionary, faction: String, tier: int) -> void:
	var V = load("res://scripts/volume_models.gd")
	var parts: Array = recipe.get("parts",[])
	var origin: Vector3 = recipe.get("drill_pos",Vector3(1.18,.48,0))
	var paint: Color = {"kestrel":Color("2865a5"),"iron":Color("bb963e"),"sky":Color("74569d")}.get(faction,Color("bb4034"))
	var boom = V.CraftMesh.new()
	boom.detail_tier = tier
	boom.capture_shell = true
	for side in [-1.0,1.0]:
		boom.line(Vector3(-.35,.12,side*.42),Vector3(.53,-.08,side*.42),.105,paint)
		boom.cylinder(Vector3(-.25,.08,side*.45),.12,.12,Vector3.BACK,V.STEEL,8)
		boom.line(Vector3(-.30,.30,side*.42),Vector3(.28,.02,side*.42),.055,V.STEEL)
	_add(parts,boom,"MiningFeedBoom",origin,"harvest_feed")
	var rotor = V.CraftMesh.new()
	rotor.detail_tier = tier
	rotor.capture_shell = true
	if faction == "sky":
		# Two faceted cutting discs held in the feed fork.
		for side in [-1.0,1.0]:
			rotor.cylinder(Vector3(0,0,side*.27),.31,.075,Vector3.BACK,V.STEEL,10)
			for index in range(8):
				var angle: float = TAU*float(index)/8.0
				rotor.box(Vector3(cos(angle)*.30,sin(angle)*.30,side*.27),Vector3(.11,.10,.09),paint)
	else:
		rotor.cylinder(Vector3.ZERO,.23,.90,Vector3.BACK,V.STEEL,10)
		for index in range(8):
			var angle: float = TAU*float(index)/8.0
			rotor.box(Vector3(cos(angle)*.24,sin(angle)*.24,0),Vector3(.13,.10,.97),paint)
	_add(parts,rotor,"MiningCutter",origin+Vector3(.51,-.07,0),"harvest_cutter")
	# Moving ore packets travel up the elevator into the open cargo bed.
	for index in range(3):
		var packet = V.CraftMesh.new()
		packet.detail_tier = tier
		packet.prism([Vector2(-.085,0),Vector2(-.10,.12),Vector2(.02,.23),Vector2(.11,.08)],.16,Vector3.ZERO,Color("6595ad"),false)
		_add(parts,packet,"OreFeed"+str(index),origin+Vector3(.25,.12,0),"harvest_ore",float(index)/3.0)
	recipe.parts = parts

static func _add(parts: Array, craft, name: String, pivot: Vector3, role: String, phase: float = 0) -> void:
	parts.append({"name":name,"mesh":craft.mesh(),"border_mesh":craft.shell_mesh(),"pivot":pivot,"role":role,"phase":phase,"travel":.65})

static func animate(part: Dictionary, entity: Dictionary, clock: float, delta: float) -> void:
	var working: bool = str(entity.get("state","")) == "harvest"
	var node: Node3D = part.node
	match str(part.role):
		"harvest_feed":
			node.rotation.z = -.12 + sin(clock*3.6)*.09 if working else .12
		"harvest_cutter":
			if working: node.rotation.z += delta*11.0
			node.position.y = part.rest.y + (sin(clock*3.6)*.045 if working else .10)
		"harvest_ore":
			node.visible = working
			var progress: float = fposmod(clock*.85+float(part.phase),1.0)
			node.position = part.rest+Vector3(-progress*float(part.travel)*2.0,sin(progress*PI)*float(part.travel)*1.25,0)
			node.rotation.z = progress*TAU
