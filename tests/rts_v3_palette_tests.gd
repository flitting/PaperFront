extends SceneTree
const V = preload("res://scripts/volume_models.gd")
var checks: int = 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:failures.append(message)
func count_color(recipe: Dictionary, color: Color, tier: String = "near") -> int:
	var meshes: Array = [recipe.body_mesh]
	if recipe.has("turret_mesh"):meshes.append(recipe.turret_mesh)
	for part in recipe.get("parts",[]):meshes.append(part.mesh)
	var count: int = 0
	for source: Mesh in meshes:
		var mesh: Mesh = V.quality_mesh(source,0,tier)
		for surface in range(mesh.get_surface_count()):
			var colors = mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]
			if colors == null:continue
			for c: Color in colors:
				if Vector3(c.r,c.g,c.b).normalized().distance_to(Vector3(color.r,color.g,color.b).normalized()) < .025:count+=1
	return count
func _initialize() -> void:
	var rules: Dictionary = RulesLoader.load_rules()
	var palette: Array = V.owner_palette.duplicate()
	var original_color: Color = V.player_color(0)
	var rose := Color("c14e6c")
	var blue := Color("429ac9")
	for id in rules.buildings:
		var spec: Dictionary = rules.buildings[id].duplicate(true)
		if spec.faction != "sky":continue
		spec.owner_color_override = rose
		var a: Dictionary = V._recipe(spec,"building",0)
		spec.owner_color_override = blue
		var b: Dictionary = V._recipe(spec,"building",0)
		for tier in ["near","far","extreme"]:
			check(count_color(a,rose,tier)>0,"Sky rose colour remains visible "+id+" "+tier)
			check(count_color(b,blue,tier)>0,"Sky blue colour remains visible "+id+" "+tier)
		check(a.dimensions==b.dimensions,"owner never affects collision/model extent "+id)
	for id in rules.units:
		var spec: Dictionary = rules.units[id].duplicate(true)
		if spec.faction != "iron":continue
		if str(spec.art) in V.INFANTRY_ART:
			var world := PaperWorld.new()
			var material: ShaderMaterial = world._infantry_paper_material(spec.animations.idle,0,rose)
			check(material.get_shader_parameter("faction_accent")==V.faction_color("iron"),"Iron infantry fixed teal "+id)
			check(material.get_shader_parameter("player_color")==rose,"Iron infantry independent owner "+id)
			world.free()
		else:
			spec.owner_color_override = rose
			var recipe: Dictionary = V._recipe(spec,"unit",0)
			for tier in ["near","far","extreme"]:
				check(count_color(recipe,rose,tier)>0,"Iron unit owner panel "+id+" "+tier)
				check(count_color(recipe,V.faction_color("iron"),tier)>0,"Iron unit fixed teal "+id+" "+tier)
	check(V.owner_palette==palette and V.player_color(0)==original_color,"isolated comparisons never alter game palette")
	print("RTS_V3_PALETTE ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
