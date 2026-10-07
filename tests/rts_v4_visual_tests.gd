extends SceneTree
const V=preload("res://scripts/volume_models.gd")
var checks: int = 0
var failures: Array[String] = []
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label)
func _initialize() -> void:
	var rules: Dictionary=RulesLoader.load_rules()
	var original: Dictionary=rules.duplicate(true)
	for id in ["kestrel_artillery","kestrel_advanced","iron_harvester"]:
		var recipe: Dictionary=V._recipe(rules.units[id],"unit",0)
		var body: Vector3=recipe.body_mesh.get_aabb().size
		check(is_equal_approx(maxf(body.x,body.z),1.92),"two-cell chassis remains full size "+id)
		check(recipe.dimensions.x>body.x,"equipment extends without shrinking chassis "+id)
		check(rules.units[id].logical_size==2 and rules.units[id].radius==1.0,"collision is unchanged "+id)
	for id in rules.units:
		var spec: Dictionary=rules.units[id]
		if str(spec.get("domain",""))!="naval" and not str(spec.art).begins_with("naval_"):continue
		var recipe: Dictionary=V._recipe(spec,"unit",0)
		check(is_equal_approx(maxf(recipe.dimensions.x,recipe.dimensions.z),float(spec.logical_size)*1.92),"exactly double naval visual size "+id)
	var train: Dictionary=V._recipe(rules.units.iron_train,"unit",0)
	check(train.get("carriage_count",0)==3,"locomotive plus two complete fighting coaches")
	check(train.dimensions.x>=9.9,"long consist silhouette")
	check(rules.units.iron_train.radius==1.0,"train collision unchanged")
	for tier in ["far","extreme"]:check(V.quality_mesh(train.body_mesh,0,tier).get_aabb().size.x>9.8,"whole consist survives "+tier)
	for faction in ["iron","sky"]:
		var recipe: Dictionary=V._recipe(rules.buildings[faction+"_refinery"],"building",0)
		check(str(recipe.architecture_form).contains("open_process"),"separate processing-machine layout "+faction)
		check(recipe.entrance.width>=2.56 and recipe.entrance.height>=2.52,"working unloading clearance "+faction)
		check(recipe.integrated_gate,"refinery shares real animated unloading gate "+faction)
	var heavy: Dictionary=V._recipe(rules.units.sky_heavy_tank,"unit",0)
	var white: int = 0
	for c: Color in heavy.body_mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]:
		if c.is_equal_approx(Color("e9e5dc")):white+=1
	check(white>24,"Sky heavy tank has broad white chassis armour")
	for faction in ["kestrel","rivet","iron","sky"]:
		var aa: Dictionary=V._recipe({"faction":faction,"art":"naval_aa","logical_size":2,"domain":"naval"},"unit",0)
		check(not aa.is_empty() and aa.dimensions.y>1.7,"new naval AA silhouette has raised radar and high-angle guns "+faction)
	for faction in ["kestrel","rivet","iron","sky"]:
		var carrier_spec: Dictionary = rules.units[faction+"_carrier_plane"]
		var normal_spec: Dictionary = carrier_spec.duplicate(true)
		normal_spec.erase("carrier_plane");normal_spec.erase("internal_only");normal_spec.producer="airfield"
		var normal: Dictionary = V._recipe(normal_spec,"unit",0)
		var plane: Dictionary = V._recipe(carrier_spec,"unit",0)
		check(is_equal_approx(maxf(plane.dimensions.x,plane.dimensions.z),1.0),"carrier airframe fits deck "+faction)
		check(is_equal_approx(maxf(normal.dimensions.x,normal.dimensions.z),1.92),"ordinary aircraft retain full visual size "+faction)
		check(normal.body_mesh!=plane.body_mesh,"carrier and ordinary aircraft use separate recipe cache "+faction)
		check(carrier_spec.logical_size==2 and carrier_spec.radius==1.0,"carrier aircraft physics remains unchanged "+faction)
	check(rules==original,"visual generation never mutates rules")
	print("RTS_V4_VISUAL ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
