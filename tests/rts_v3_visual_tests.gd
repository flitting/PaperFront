extends SceneTree
const V = preload("res://scripts/volume_models.gd")
var checks: int = 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func pigment_count(mesh: Mesh, pigment: Color) -> int:
	var total: int = 0
	for surface in range(mesh.get_surface_count()):
		var colors: PackedColorArray = mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]
		for color in colors:
			if Vector3(color.r,color.g,color.b).normalized().distance_to(Vector3(pigment.r,pigment.g,pigment.b).normalized()) < .025: total += 1
	return total
func _initialize() -> void:
	V.configure_player_colors(["#369f95","#ba5065"])
	var designs: Dictionary = {}
	for faction in ["kestrel","rivet","iron","sky"]:
		for art in ["hq","factory","airfield","tank","fighter"]:
			var kind: String = "building" if art in ["hq","factory","airfield"] else "unit"
			var spec: Dictionary = {"faction":faction,"art":art,"size":7,"logical_size":2}
			var a: Dictionary = V._recipe(spec,kind,0)
			var b: Dictionary = V._recipe(spec,kind,1)
			check(a.dimensions == b.dimensions,"owner pigment must not change geometry "+faction+"/"+art)
			check(pigment_count(a.body_mesh,V.player_color(0)) > 0,"owner painted surfaces exist "+faction+"/"+art)
			check(pigment_count(b.body_mesh,V.player_color(1)) > 0,"setup color changes surfaces "+faction+"/"+art)
			var badge_count: int = pigment_count(a.body_mesh,V.BADGE_ORANGE)
			for part in a.get("parts",[]): badge_count += pigment_count(part.mesh,V.BADGE_ORANGE)
			check(badge_count > 0,"fixed orange faction badge "+faction+"/"+art)
			for mode in ["far","extreme"]:
				var lod: Mesh = V.quality_mesh(a.body_mesh,0,mode)
				check(pigment_count(lod,V.player_color(0)) > 0,"owner paint survives "+mode+" "+faction+"/"+art)
			if art == "airfield":
				designs[a.design] = true
				var pads: Array = a.parts.filter(func(p): return p.role == "parking_pad")
				check(pads.size() == 4,"four separate airport stands "+faction)
				for pad in pads: check(is_equal_approx(absf(pad.pivot.x),1.6) and is_equal_approx(absf(pad.pivot.z),1.6),"airport stand contract "+faction)
	check(designs.size() == 4,"all four airports own their architecture")
	for art in ["armored_train","zeppelin"]:
		var spec: Dictionary = {"faction":"iron" if art=="armored_train" else "rivet","art":art,"logical_size":2,"radius":1.0}
		var recipe: Dictionary = V._recipe(spec,"unit",0)
		check(recipe.dimensions.x >= 4.19,"longer special silhouette "+art)
		check(spec.logical_size==2 and spec.radius==1.0,"visual scale retains logical footprint "+art)
	var world = load("res://scripts/paper_world.gd").new()
	var star: Mesh = world._veteran_star_mesh()
	check(star.get_surface_count()==1 and star.surface_get_array_len(0)==24,"five-point concave gold star triangulates")
	var material: ShaderMaterial = V.veteran_paint(0)
	check(material.get_shader_parameter("veteran") == true,"veteran service livery is enabled")
	check(material.get_shader_parameter("veteran_owner") == V.player_color(0),"veteran livery retains selected player pigment")
	world.free()
	V.configure_player_colors()
	print("RTS_V3_VISUAL ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
