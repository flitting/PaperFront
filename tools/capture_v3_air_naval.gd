extends "res://tools/capture_rts_v3_visuals.gd"
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size=Vector2i(1600,1100)
	root.content_scale_size=root.size
	V.configure_player_colors(["#369f95","#ba5065"])
	var rules:Dictionary=RulesLoader.load_rules()
	prepare("AIR + SEA EXPANSION / SIX DISTINCT SILHOUETTES / FOUR FACTIONS",16,Vector3(0,.2,0))
	floor_grid(24,17)
	var roles:Array=["helicopter","submarine","amphibious","hovercraft","support_ship","carrier"]
	for row in range(4):
		var faction:String=["kestrel","rivet","iron","sky"][row]
		for col in range(6):
			add_model(rules.units[faction+"_"+roles[col]],"unit",Vector3(-7.7+col*3.1,.5 if col==0 else .10,-5.0+row*3.4))
		text_label(faction.to_upper(),Vector2(38,178+row*231),20)
	text_label("HELICOPTER      SUBMARINE       AMPHIBIOUS       HOVERCRAFT        SUPPORT SHIP       LIGHT CARRIER",Vector2(130,1030),18)
	await capture("air_naval_fleet")
	prepare("AIRCRAFT CARRIER / ROTORCRAFT / PAPERBOARD DETAILS",8,Vector3(0,.7,0))
	floor_grid(12,10)
	for i in range(3):
		var role:String=["helicopter","carrier","hovercraft"][i]
		add_model(rules.units["iron_"+role],"unit",Vector3(-2.8+i*2.8,.6 if i==0 else .2,0))
	await capture("air_naval_closeup")
	var sim=load("res://tests/rule_test_simulation.gd").new()
	var factions:Array[String]=["kestrel","rivet"]
	sim.setup_multiteam(rules,"dev",7,factions,false)
	var id:int=sim._spawn(0,"kestrel_recon",Vector2(25,30),true)
	var trail:Array[Vector2]=[sim.entities[id].pos]
	var poses:Array[Dictionary]=[]
	for n in range(160):
		sim.step(.05)
		trail.append(sim.entities[id].pos)
		if n%40==0:poses.append(sim.entities[id].duplicate(true))
	prepare("FIXED-WING HOLD / ACTUAL SIMULATION TRAJECTORY OVER 8 SECONDS",12,Vector3(0,.6,0))
	floor_grid(18,15)
	var center:Vector2=sim.entities[id].loiter_center
	var line=V.CraftMesh.new()
	for n in range(1,trail.size()):
		var a:Vector2=trail[n-1]-center
		var b:Vector2=trail[n]-center
		line.line(Vector3(a.x,.15,a.y),Vector3(b.x,.15,b.y),.025,Color("ba5065"))
	var trail_mesh:=MeshInstance3D.new();trail_mesh.mesh=line.mesh();scene.add_child(trail_mesh)
	for pose:Dictionary in poses:
		var p:Vector2=(pose.pos as Vector2)-center
		var model:Dictionary=add_model(rules.units.kestrel_recon,"unit",Vector3(p.x,.75,p.y))
		model.root.rotation.y=-deg_to_rad(float(pose.alpha))
	text_label("Rose line = authoritative movement path; aircraft poses sampled every 2 seconds",Vector2(160,1020),22)
	await capture("fixed_wing_actual_loiter")
	quit()
