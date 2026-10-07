extends SceneTree
func _initialize() -> void:
	var rules: Dictionary=RulesLoader.load_rules()
	for id in ["kestrel_artillery","kestrel_advanced","iron_harvester","iron_train","kestrel_carrier","sky_heavy_tank"]:
		var spec: Dictionary=rules.units[id]
		var recipe: Dictionary=VolumeModels._recipe(spec,"unit",0)
		print(id," dims=",recipe.dimensions," body=",recipe.body_mesh.get_aabb().size," factor=",recipe.model_scale," muzzle=",recipe.get("muzzle_pos",Vector3.ZERO)," turret=",recipe.get("turret_pos",Vector3.ZERO))
	quit()
