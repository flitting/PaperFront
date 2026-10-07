extends SceneTree

const Hand=preload("res://scripts/creator_hand_models.gd")
const VOLUME=preload("res://scripts/volume_models.gd")
var checks: int=0
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label)
func run() -> void:
	var rules: Dictionary=RulesLoader.load_rules()
	var first: Dictionary=VOLUME.create_model(rules.units.sky_creator_hand,"unit",0)
	var second: Dictionary=VOLUME.create_model(rules.units.sky_creator_hand,"unit",1)
	root.add_child(first.root);root.add_child(second.root)
	var original: Mesh=first.skinned_mesh.mesh
	var source: Array=original.surface_get_arrays(0)
	var snapshot: PackedVector3Array=source[Mesh.ARRAY_VERTEX]
	check(first.skinned_mesh.mesh==second.skinned_mesh.mesh and first.skinned_mesh.skin==second.skinned_mesh.skin,"owner accents preserve the shared original continuous mesh and Skin")
	check(first.skeleton!=second.skeleton and first.skeleton.get_bone_count()==16,"each team still owns its private sixteen-bone animated skeleton")
	var a: ShaderMaterial=first.skinned_mesh.get_surface_override_material(0)
	var b: ShaderMaterial=second.skinned_mesh.get_surface_override_material(0)
	check(a!=b and a.shader==b.shader,"team owner uniforms have private material instances and one unchanged shared skin shader")
	check(a.get_shader_parameter("owner_color")!=b.get_shader_parameter("owner_color"),"different player teams receive visibly different owner paint colors")
	check(a.shader.code.contains("paint_cutoff") and a.shader.code.contains("mix(natural,pigment,paint"),"owner paint uses a measured longitudinal hard partition and preserves natural skin")
	for ratio: float in Hand.owner_area_evidence.surface_and_tabletop_owner_area:
		check(ratio<=.065 and 1.0-ratio>=.935,"small wrist mark and predominantly natural skin "+str(ratio))
	check(first.owner_color==VOLUME.player_color(0) and second.owner_color==VOLUME.player_color(1),"owner paint uses the game player-color palette rather than faction-wide purple")
	for team: int in range(2,8):
		var model: Dictionary=VOLUME.create_model(rules.units.sky_creator_hand,"unit",team)
		check(model.owner_color==VOLUME.player_color(team),"every player slot has its own hand identification color "+str(team))
		model.root.free()
	for state: String in ["idle","move","attack"]:
		for model: Dictionary in [first,second]:
			VOLUME.update_model(model,{"id":3,"state":state,"hand_strike":.18 if state=="attack" else 0.0,"hand_landing":Vector2(4,0),"hand_contact_height":.6},.15)
			check(model.skinned_mesh.mesh==original and original.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]==snapshot,"owner materials never mutate the mesh or replace authored bone animation "+state)
	check(first.skinned_mesh.get_surface_override_material(1)!=second.skinned_mesh.get_surface_override_material(1),"natural nail highlights have separate instance materials")
	first.root.free();second.root.free();await process_frame
	print("CREATOR_HAND_OWNER_COLORS ",JSON.stringify({"checks":checks,"failures":failures,"paint_area":Hand.owner_area_evidence}))
	for failure: String in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
