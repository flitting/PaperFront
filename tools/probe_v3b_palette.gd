extends SceneTree
const V = preload("res://scripts/volume_models.gd")
func count(recipe: Dictionary, color: Color) -> int:
	var meshes: Array = [recipe.body_mesh]
	if recipe.has("turret_mesh"):meshes.append(recipe.turret_mesh)
	for p in recipe.get("parts",[]):meshes.append(p.mesh)
	var n: int = 0
	for mesh: Mesh in meshes:
		for surface in range(mesh.get_surface_count()):
			var colors: PackedColorArray = mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]
			for c in colors:
				if Vector3(c.r,c.g,c.b).normalized().distance_to(Vector3(color.r,color.g,color.b).normalized())<.025: n+=1
	return n
func _initialize() -> void:
	var rules: Dictionary = RulesLoader.load_rules()
	for kind in ["building","unit"]:
		for id in rules[kind+"s"]:
			var spec: Dictionary = rules[kind+"s"][id].duplicate(true)
			if spec.faction not in ["sky","iron"] or not V.supports(spec,kind) or spec.art == "creator_hand":continue
			spec.owner_color_override = Color("b04c67")
			var recipe: Dictionary = V._recipe(spec,kind,0)
			var owner: int = count(recipe,spec.owner_color_override)
			var fixed: int = count(recipe,V.faction_color(spec.faction))
			if owner == 0 or fixed == 0:print("MISSING ",id," ",spec.name," owner=",owner," heritage=",fixed)
	print("PALETTE_PROBE_DONE")
	quit()
