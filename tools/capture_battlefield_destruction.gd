extends SceneTree

## Frozen real-GPU evidence for the destruction revision; no gameplay state ticks.
const Sim = preload("res://tests/rule_test_simulation.gd")
const OUTPUT: String = "res://artifacts/av_revision_20261006/visual/"
var world: PaperWorld
var sim
var camera: Camera3D
var stage: Node3D
var rows: Array = []
var shards_only: bool = false

func _initialize() -> void: call_deferred("run")
func sync(delta: float = .016) -> void:
	world.sync(delta,[])
	sim.events.clear()
func capture(name: String) -> void:
	if shards_only and not name.begins_with("shrapnel_lod_"): return
	for frame: int in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+name+".png")
	var triangles: int=0
	var submissions: int=0
	var seen: Dictionary={}
	for effect: Dictionary in world.effects:
		var batch: Dictionary=effect.batch
		var key: int=batch.multi.get_instance_id()
		if seen.has(key): continue
		seen[key]=true
		var count: int=world._batch_count(batch)
		triangles+=count*preload("res://scripts/battlefield_effect_lod.gd").triangles(batch.multi.mesh)
		submissions+=count
	rows.append({"capture":name,"effects":world.effects.size(),"drawn_effect_triangles":triangles,"drawn_effect_instances":submissions,"craters":world.craters.size(),"tracks":world.tracks.size()})
func label(text: String, pos: Vector3) -> void:
	var node := Label3D.new()
	node.text=text
	node.font_size=64
	node.pixel_size=.012
	node.position=pos
	node.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	node.modulate=Color("f4e9cc")
	node.outline_modulate=Color("342d26")
	stage.add_child(node)
func clear_labels() -> void:
	for node: Node in stage.get_children():
		if node is Label3D: node.queue_free()

func run() -> void:
	shards_only="--shrapnel-only" in OS.get_cmdline_user_args()
	if DisplayServer.get_name()=="headless":
		push_error("This capture requires a real display and GPU.");quit(1);return
	root.size=Vector2i(1600,900)
	stage=Node3D.new();root.add_child(stage)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode=Environment.BG_COLOR
	settings.background_color=Color("b7ab91")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color=Color("ece5d5")
	settings.ambient_light_energy=.75
	environment.environment=settings;stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-55,-30,0)
	light.light_energy=1.15;light.shadow_enabled=true
	stage.add_child(light)
	camera=Camera3D.new();stage.add_child(camera)
	camera.current=true
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=25
	camera.position=Vector3(24,29,58);camera.look_at(Vector3(24,0,29))
	sim=Sim.new();sim.setup(RulesLoader.load_rules(),"dev",7,"rivet",false)
	for id: int in sim.entities.keys(): sim._kill_entity(id,false)
	for z: int in 48:
		for x: int in 48:
			sim.map.terrain[z][x]=0;sim.map.heights[z][x]=0.0
	sim.ruins.clear();sim.mines.clear();sim.bridges.clear()
	for key: String in ["ruins","mines","bridges","decorations"]:
		if sim.map.has(key): sim.map[key].clear()
	sim._prepare_terrain_cache();sim.events.clear()
	world=PaperWorld.new();stage.add_child(world);world.setup(sim,camera)
	world.configure_quality("balanced")
	var buildings: Array[int] = []
	for index: int in 3:
		var id: int = sim.debug_spawn(0,"rivet_factory",Vector2(13+index*11,29))
		sim.entities[id].hp*= [1.0,.45,.20][index]
		buildings.append(id)
		label(["100% HP","45% HP · damaged","20% HP · critical"][index],Vector3(13+index*11,6.8,29))
	sync();await capture("building_damage_comparison")
	for tier: int in 3:
		world.lod_override=tier;sync(0)
		await capture("building_damage_lod_"+["near","far","ultra"][tier])
	world.lod_override=-1
	for id: int in buildings: sim._kill_entity(id,false)
	clear_labels();sync()
	camera.size=18;camera.position=Vector3(24,24,53);camera.look_at(Vector3(24,0,31))
	var tank: int = sim.debug_spawn(0,"rivet_tank",Vector2(20,30))
	sync()
	sim.entities[tank].state="move"
	for angle: int in range(0,361,4):
		sim.entities[tank].alpha=float(angle);sync(.016)
	for frame: int in 35:
		sim.entities[tank].pos += Vector2(.18,0);sync(.035)
	sim.entities[tank].state="idle";sync(.15)
	label("Pivot circles + persistent paired treads",Vector3(23,5.0,30))
	await capture("tank_pivot_treads")
	clear_labels()
	sim._kill_entity(tank,true)
	var destruction_started: int = Time.get_ticks_usec()
	sync(.23)
	var cold_destruction_ms: float = (Time.get_ticks_usec()-destruction_started)/1000.0
	await capture("tank_silhouette_explosion")
	for tier: int in 3:
		world.lod_override=tier;sync(0)
		await capture("explosion_lod_"+["near","far","ultra"][tier])
	world.lod_override=-1
	for frame: int in 16: sync(.15)
	await capture("tank_crater_smoke_rubble")
	for tier: int in 3:
		world.lod_override=tier;sync(0)
		await capture("shrapnel_lod_"+["near","far","ultra"][tier])
	world.lod_override=-1
	sim.events.append({"kind":"impact","pos":Vector2(22,34),"team":0,"projectile":true,"blast":1.2,"height":.18})
	sync(.20)
	await capture("shell_impact")
	for frame: int in 12: sync(.15)
	await capture("shell_smoke_after_two_seconds")
	var report: Dictionary = {"scope":"Real GPU static visual fixtures; rule simulation never stepped.","gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"display":DisplayServer.get_name(),"resolution":[root.size.x,root.size.y],"cold_destruction_ms":cold_destruction_ms,"rows":rows}
	var file := FileAccess.open(OUTPUT+("shrapnel_capture_report.json" if shards_only else "capture_report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("BATTLEFIELD_DESTRUCTION_GPU ",JSON.stringify(report))
	stage.free();await process_frame
	quit()
