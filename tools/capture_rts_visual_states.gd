extends SceneTree

## Renderer evidence for live simulation states. Infrastructure is a controlled
## initial fixture; every queue, building scaffold, air command and weapon fires
## through the production simulation. Captures require a real GPU/display.
const Fixture = preload("res://tests/rts_regression_fixture.gd")
const OUTPUT := "res://artifacts/rts_revision"
var rig
var world: PaperWorld
var camera: Camera3D
var label: Label
var manifest: Array[Dictionary] = []

func _initialize() -> void: call_deferred("run")
func aim(target: Vector2, size: float, title: String, y: float = .6) -> void:
	camera.size=size
	camera.position=Vector3(target.x,y,target.y)+Vector3(6,8,12)
	camera.look_at(Vector3(target.x,y,target.y))
	if is_instance_valid(label):label.text=title
	world.lod_override=0

func capture(file: String, selected: Array = [], warmup: int = 10) -> void:
	for frame in range(warmup):
		world.sync(.016,selected)
		await process_frame
	RenderingServer.force_draw()
	var error: Error = root.get_texture().get_image().save_png(OUTPUT+"/"+file+".png")
	manifest.append({"file":file+".png","sim_time":rig.sim.time,"error":error,"camera_size":camera.size})
	print("RTS_STATE_CAPTURE ",file," ",error)

func run() -> void:
	if DisplayServer.get_name()=="headless":quit(2);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size=Vector2i(1600,1000);root.content_scale_size=root.size
	VolumeModels.configure_player_colors(["#26aaa7","#26aaa7","#26aaa7","#26aaa7"])
	rig=Fixture.new();rig.setup();rig.produce_phase()
	var env_node:=WorldEnvironment.new()
	var env:=Environment.new()
	env.background_mode=Environment.BG_COLOR;env.background_color=Color("e6dac7")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("fff2dc");env.ambient_light_energy=.75
	env_node.environment=env;root.add_child(env_node)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-30,0);light.light_energy=1.05;light.shadow_enabled=true;root.add_child(light)
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.current=true;root.add_child(camera)
	world=PaperWorld.new();root.add_child(world)
	aim(Vector2(32,32),72,"FOUR FACTION LIVE FIXTURE / PAID PRODUCTION / 2D PAPER INFANTRY")
	world.setup(rig.sim,camera)
	var canvas:=CanvasLayer.new();root.add_child(canvas)
	var caption := ColorRect.new();caption.color=Color("e6dac7");caption.size=Vector2(1600,78);canvas.add_child(caption)
	label=Label.new();label.position=Vector2(32,24);label.add_theme_font_size_override("font_size",30);label.add_theme_color_override("font_color",Color("302b25"));canvas.add_child(label)
	aim(Vector2(20.5,13),9,"LIVE WORLD / 2D EXOSUIT INFANTRY + ENGINEER / PAID BARRACKS EXIT")
	await capture("live_2d_infantry",[rig.ids.kestrel_rifle,rig.ids.kestrel_engineer])
	# A second same-spec soldier is paid for and then fires a real weapon.
	# Keep its idle neighbor's record idle to expose any shared-material bug.
	var original_rifle: int = rig.ids.kestrel_rifle
	rig.sim.produce(rig.ids.kestrel_barracks,"kestrel_rifle")
	rig.wait_for(func():return rig.sim.entities.values().filter(func(e):return e.spec=="kestrel_rifle" and not bool(e.get("emerging",false))).size()==2,15)
	var combat_rifle: int = -1
	for e in rig.sim.entities.values():
		if e.spec=="kestrel_rifle" and int(e.id)!=original_rifle:combat_rifle=e.id
	if combat_rifle>0:
		var soldier: Dictionary = rig.sim.entities[combat_rifle]
		var target: int = rig.sim._spawn(1,"rivet_rifle",soldier.pos+Vector2(4,0),true)
		soldier.alpha=0;soldier.turret_alpha=0;soldier.cooldown=0;soldier.motion=0
		rig.sim._fire(soldier,target)
		rig.sim.entities[original_rifle].state="idle"
		rig.sim.entities[original_rifle].motion=0
		rig.sim.entities[original_rifle].attack_flash=0
		rig.sim.entities[original_rifle].hit_flash=0
		rig.sim.entities[original_rifle].alpha=0
		aim((soldier.pos+rig.sim.entities[original_rifle].pos)*.5,6.5,"LIVE SAME-SPEC SOLDIERS / IDLE AND FIRING SIMULTANEOUSLY / SEPARATE MATERIALS")
		await capture("live_same_unit_idle_combat",[original_rifle,combat_rifle],2)
		rig.sim._kill_entity(target,true)
		rig.sim.issue([combat_rifle],"hold",soldier.pos)
	# Actual drill scaffold, working spindle, visible original ore and damage.
	var engineer: int = rig.ids.rivet_engineer
	rig.sim.build(1,"rivet_drill",engineer);rig.sim.place_building(1,rig.sim.mines[1].pos)
	rig.wait_for(func():return int(rig.sim.mines[1].get("drill",-1))>0,20)
	var drill: int = int(rig.sim.mines[1].get("drill",-1))
	aim(rig.sim.mines[1].pos,5.8,"LIVE HEAVY DRILL CONSTRUCTION / TALL DERRICK + ORIGINAL ORE",1.9)
	await capture("live_drill_scaffold_ore",[drill])
	rig.advance(22)
	aim(rig.sim.mines[1].pos,5.8,"LIVE HEAVY DRILL / ROTATING AUGER + FLYWHEEL / ORIGINAL ORE ROOT",1.9)
	await capture("live_drill_working_ore",[drill])
	rig.sim._add_damage(drill,float(rig.sim.entities[drill].hp)*.66);rig.sim._apply_damage();rig.sim._damage.clear()
	label.text="LIVE DAMAGED DRILL / 34% HEALTH / ORIGINAL ORE IS STILL INDEPENDENT"
	await capture("live_drill_damaged_ore",[drill])
	# A second tank enters a paid factory queue, then its real inside/exit phase.
	var factory: int = rig.ids.kestrel_factory
	rig.sim.produce(factory,"kestrel_tank")
	rig.wait_for(func():return rig.sim.entities.values().any(func(e):return e.spec=="kestrel_tank" and bool(e.get("emerging",false))),25)
	aim(rig.sim.entities[factory].pos,10,"LIVE FACTORY / TANK INSIDE / DOOR OPENING")
	await capture("live_factory_tank_inside",[factory])
	rig.advance(.8);label.text="LIVE FACTORY / DOOR OPEN / TANK DRIVING OUT"
	await capture("live_factory_tank_exit",[factory])
	rig.advance(2);label.text="LIVE FACTORY / EXIT COMPLETE / DOOR CLOSED"
	await capture("live_factory_tank_closed",[factory])
	# Aircraft have an isolated, live two-owner observation arena; no hostile
	# seeded army can destroy the airport while four ordinary queues complete.
	var air_sim = preload("res://tests/rule_test_simulation.gd").new()
	air_sim.setup(RulesLoader.load_rules(),"dev",117,"sky",false)
	for row in air_sim.map.terrain:row.fill(0)
	for row in air_sim.map.heights:row.fill(0.0)
	air_sim.mines.clear();air_sim.ruins.clear();air_sim.bridges.clear()
	air_sim._refresh_ruin_spatial();air_sim._prepare_terrain_cache()
	air_sim.money.assign([20000.0,20000.0])
	rig.sim=air_sim
	aim(Vector2(25.5,25.5),10,"AIRFIELD OBSERVATION ARENA")
	world.setup(air_sim,camera)
	rig.sim._spawn(0,"sky_power",Vector2(14,18),true)
	rig.sim._spawn(0,"sky_power",Vector2(25.5,15.5),true)
	rig.sim._spawn(0,"sky_command",Vector2(14,26),true)
	var field: int = rig.sim._spawn(0,"sky_airfield",Vector2(25.5,25.5),true)
	for i in range(4):rig.check(rig.sim.produce(field,"sky_fighter").is_empty(),"visual fixture paid aircraft order "+str(i))
	rig.wait_for(func():return rig.sim.entities.values().filter(func(e):return e.spec=="sky_fighter").size()==4,300)
	rig.advance(2)
	var planes: Array = rig.sim.entities.values().filter(func(e):return e.spec=="sky_fighter")
	rig.check(planes.size()==4 and planes.all(func(e):return not bool(e.airborne) and str(e.state)=="parked"),"visual capture contains four actual parked aircraft")
	print("RTS_AIRCRAFT_PARKING ",JSON.stringify(planes.map(func(e):return {"id":e.id,"pos":str(e.pos),"airborne":e.airborne,"state":e.state,"home":e.home_airfield})))
	aim(rig.sim.entities[field].pos,10,"LIVE AIRFIELD / FOUR DISTINCT RESERVED STANDS / FOUR PAID PARKED PLANES")
	await capture("live_airfield_four_parked",[field])
	if not planes.is_empty():
		var plane: Dictionary = planes[0]
		rig.sim.issue([plane.id],"move",rig.sim.entities[field].pos+Vector2(0,-8));rig.advance(.1)
		world.sync(.08,[plane.id]);label.text="LIVE AIRCRAFT TAKEOFF / GRADUAL CLIMB FROM ITS OWN STAND"
		await capture("live_aircraft_takeoff",[plane.id])
		rig.advance(1.5)
		for frame in range(50):world.sync(.04,[plane.id]);await process_frame
		rig.sim.issue([plane.id],"return",rig.sim.entities[field].pos)
		rig.wait_for(func():return not bool(plane.airborne),15)
		world.sync(.06,[plane.id]);label.text="LIVE AIRCRAFT RETURN / DESCENT ONTO RESERVED STAND"
		await capture("live_aircraft_landing",[plane.id])
		for frame in range(100):world.sync(.04,[plane.id]);await process_frame
		rig.advance(6);label.text="LIVE AIRCRAFT / LANDING COMPLETE / PARKED"
		await capture("live_aircraft_parked_again",[plane.id])
	# Point ray, sustained tracked beam and actual EMP vehicle control.
	var laser: int = rig.sim._spawn(0,"sky_tank",Vector2(30,29),true)
	var beam: int = rig.sim._spawn(0,"sky_pulse",Vector2(30,33),true)
	var emp: int = rig.sim._spawn(0,"sky_disruptor",Vector2(30,37),true)
	var victims: Array[int] = []
	for z in [29,33,37]:victims.append(rig.sim._spawn(1,"rivet_tank",Vector2(37,z),true))
	for source in [laser,beam,emp]:rig.sim.entities[source].turret_alpha=0;rig.sim.entities[source].alpha=0
	for i in range(3):rig.sim._fire(rig.sim.entities[[laser,beam,emp][i]],victims[i])
	rig.sim._apply_damage();rig.sim._damage.clear()
	aim(Vector2(33.5,33),13,"LIVE WEAPONS / POINT LASER - TRACKED CONTINUOUS BEAM - EMP CONTROL")
	world.sync(.01,[])
	RenderingServer.force_draw();await process_frame
	await capture("live_laser_beam_emp",[laser,beam,emp],2)
	rig.sim.issue([victims[1]],"move",Vector2(39,33));rig.advance(.25)
	label.text="LIVE CONTINUOUS BEAM FOLLOWS MOVING TARGET / EMP STATUS REMAINS VISIBLE"
	await capture("live_beam_tracking_emp_status",[beam,emp])
	var report := FileAccess.open(OUTPUT+"/visual_states_manifest.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"renderer":RenderingServer.get_current_rendering_method(),"device":RenderingServer.get_video_adapter_name(),"captures":manifest,"fixture_failures":rig.failures},"  "))
	print("RTS_VISUAL_STATE_RESULT ",JSON.stringify({"captures":manifest.size(),"failures":rig.failures}))
	world.queue_free();camera.queue_free();canvas.queue_free();env_node.queue_free();light.queue_free()
	await process_frame
	VolumeModels.configure_player_colors()
	quit(0 if rig.failures.is_empty() else 1)
