extends "res://tools/capture_rts_v3_visuals.gd"
const Sim=preload("res://tests/rule_test_simulation.gd")
const Expansion=preload("res://scripts/air_naval_expansion.gd")
func run()->void:
	var output:String="res://artifacts/rts_revision_v4/carrier_launch/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size=Vector2i(1400,900);root.content_scale_size=root.size
	var rules:Dictionary=RulesLoader.load_rules()
	V.configure_player_colors(["#bf5664","#497fa2"])
	var sim=Sim.new();sim.setup(rules,"dev",7,"kestrel",false)
	for id in sim.entities.keys():sim._kill_entity(int(id),false)
	sim.ruins.clear();sim.mines.clear();sim.bridges.clear()
	for row in sim.map.terrain:row.fill(1)
	for row in sim.map.heights:row.fill(0.0)
	sim._prepare_terrain_cache();sim._spawn(0,"kestrel_hq",Vector2(4,4),true);sim._spawn(1,"rivet_hq",Vector2(44,4),true)
	var carrier:int=sim._spawn(0,"kestrel_carrier",Vector2(20,30),true)
	var target:int=sim._spawn(1,"rivet_ship_frigate",Vector2(40,30),true)
	sim.entities[carrier].alpha=0
	Expansion.carrier_fire(sim,sim.entities[carrier],target)
	var moments:Array[float]=[0,.55,1.2,1.85,2.55]
	var manifest:Array=[]
	for index in range(moments.size()):
		while sim.time<moments[index]-.001:sim.step(minf(.05,moments[index]-sim.time))
		prepare("CARRIER LAUNCH / ACTUAL DECK ROLL AND CLIMB / %.2f SECONDS"%sim.time,11,Vector3(2,1.6,0))
		var ocean:=MeshInstance3D.new();var plane_mesh:=PlaneMesh.new();plane_mesh.size=Vector2(30,20);ocean.mesh=plane_mesh
		var mat:=StandardMaterial3D.new();mat.albedo_color=Color("7599a5");mat.roughness=1;ocean.material_override=mat;scene.add_child(ocean)
		add_model(rules.units.kestrel_carrier,"unit",Vector3.ZERO)
		var records:Array=[]
		for entity:Dictionary in sim.entities.values():
			if int(entity.get("carrier_id",-1))!=carrier:continue
			var relative:Vector2=entity.pos-sim.entities[carrier].pos
			var height:float=sim._height(entity.pos)+float(entity.flight_height)-MapData.water_surface_y(sim.map,sim.entities[carrier].pos)
			var model:Dictionary=add_model(rules.units[entity.spec],"unit",Vector3(relative.x,height,relative.y))
			model.root.rotation.y=-deg_to_rad(float(entity.alpha))
			records.append({"id":entity.id,"position":str(entity.pos),"height_above_sea":height,"phase":entity.state,"launch":entity.get("carrier_launch",{}).duplicate(true)})
		manifest.append({"time":sim.time,"planes":records})
		for i in range(5):await process_frame
		RenderingServer.force_draw();root.get_texture().get_image().save_png(output+"launch_%02d.png"%index)
	var file:=FileAccess.open(output+"manifest.json",FileAccess.WRITE);file.store_string(JSON.stringify(manifest,"\t"))
	print("CARRIER_LAUNCH_CAPTURE ",JSON.stringify(manifest))
	quit()
