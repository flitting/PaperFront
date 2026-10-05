extends SceneTree

const Sim=preload("res://tests/rule_test_simulation.gd")
var failures:Array[String]=[]
var checks:int=0

func _initialize() -> void:
	call_deferred("run")

func check(ok:bool,message:String) -> void:
	checks+=1
	if not ok:failures.append(message)

func run() -> void:
	var rules:Dictionary=RulesLoader.load_rules()
	var sim=Sim.new()
	sim.setup(rules,"dev",7,"rivet",false)
	var camera:=Camera3D.new()
	root.add_child(camera)
	camera.fov=42
	camera.position=Vector3(24,38,67)
	camera.look_at(Vector3(24,0,28))
	var world:=PaperWorld.new()
	root.add_child(world)
	world.setup(sim,camera)
	var colors:Dictionary={}
	var ids:Array[int]=[]
	for team in range(8):
		colors[VolumeModels.player_color(team)]=true
		var base:String=preload("res://scripts/performance_factions.gd").art_template(team)
		for art in ["rifle","tank","fighter"]:
			var source_id:String=base+"_"+art
			var id:int=sim.debug_spawn(0,source_id,Vector2(20.5+team*.8,30.5))
			var clone:Dictionary=rules.units[source_id].duplicate(true)
			clone.faction="render_army_%d" % team
			clone.art_faction=base
			var clone_id:String="render_army_%d_%s" % [team,art]
			sim.rules.units[clone_id]=clone
			sim.entities[id].spec=clone_id
			sim.entities[id].team=team
			ids.append(id)
			check(is_equal_approx(VolumeModels.bake_scale(clone,"unit"),VolumeModels.bake_scale(rules.units[source_id],"unit")),"clone scale retains its art template "+clone_id)
		var headquarters:Dictionary=rules.buildings[base+"_hq"].duplicate(true)
		headquarters.faction="render_army_%d" % team
		headquarters.art_faction=base
		var model:Dictionary=VolumeModels.create_model(headquarters,"building",team)
		check(not model.is_empty() and not model.meshes.is_empty() and model.player_color==VolumeModels.player_color(team),"cloned headquarters has geometry and its unique owner color "+str(team))
		model.root.free()
	check(colors.size()==8,"all eight owners have different visible colors")
	check(VolumeModels.player_color(0)==Color("e7ad42") and VolumeModels.player_color(1)==Color("41c7c6"),"the original two owner colors stay unchanged")
	world.sync(0.0,ids)
	for id in ids:
		var e:Dictionary=sim.entities[id]
		var model:Dictionary=world.models[id]
		check(model.ring.material_override.albedo_color==VolumeModels.player_color(int(e.team)),"selection rings support every owner "+str(id))
		if model.volumetric:
			check(model.volume.player_color==VolumeModels.player_color(int(e.team)),"solid units retain unique owner plates "+str(id))
		else:
			check(model.graphic.mesh.surface_get_material(0).get_shader_parameter("player_color")==VolumeModels.player_color(int(e.team)),"paper infantry use their template contour and correct identity mask "+str(id))
	world.configure_quality("performance")
	world.sync(.1,[])
	var reduced:int=0
	for id in ids:
		var model:Dictionary=world.models[id]
		if not model.volumetric:continue
		for part in model.render_parts:
			if part.quality_batch.multi.mesh!=part.batch.multi.mesh:reduced+=1
	check(reduced==0,"all eight owners retain authored solid geometry in every quality preset")
	world.configure_quality("native")
	world.sync(0.0,ids)
	check(world.models.size()>=ids.size(),"switching quality preserves all independent render models")
	print("EIGHT_OWNER_RENDER ",JSON.stringify({"checks":checks,"failures":failures,"reduced_meshes":reduced}))
	world.queue_free()
	camera.queue_free()
	await process_frame
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
