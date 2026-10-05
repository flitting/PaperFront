extends SceneTree

## Rendering-only diagnosis, NOT a gameplay benchmark. No simulation FPS claims.
var sim: WarSimulation
var world: PaperWorld
var camera: Camera3D
var selected: Array = []
var frame_times: Array[float] = []
var sync_times: Array[float] = []
var total: float = 0.0
var previous: int = 0
var unbatched: bool = false

func _initialize() -> void:
	call_deferred("setup")

func setup() -> void:
	unbatched = "--unbatched" in OS.get_cmdline_user_args()
	root.size=Vector2i(1920,1080)
	sim=WarSimulation.new()
	sim.setup(RulesLoader.load_rules(),"handmade",73026,"rivet",false)
	sim.entities.clear()
	for team in range(2):
		for i in range(112):
			var kind: String = ["rifle","anti","tank","harvester","engineer"][i%5]
			var id: int = sim.debug_spawn(team,sim.factions[team]+"_"+kind,Vector2(48+team*42+(i%14)*1.65,80+(i/14)*1.7))
			if id>=0:
				selected.append(id)
		for i in range(16):
			var kind: String = ["hq","power","refinery","barracks","factory","tower","tech"][i%7]
			sim.debug_spawn(team,sim.factions[team]+"_"+kind,Vector2(30+team*76+(i%4)*5.3,104+(i/4)*5.3))
	camera=Camera3D.new()
	root.add_child(camera)
	camera.current=true
	camera.fov=42
	camera.position=Vector3(80,90,188)
	camera.look_at(Vector3(80,0,94))
	world=PaperWorld.new()
	root.add_child(world)
	world.setup(sim,camera)
	world.sync(0,selected,{})
	previous=Time.get_ticks_usec()

func _process(delta: float) -> bool:
	if world==null:return false
	total+=delta
	var tick: int = Time.get_ticks_usec()
	if total>1.0:frame_times.append(float(tick-previous)/1000.0)
	previous=tick
	for e in sim.entities.values():
		if e.kind=="unit":
			e.alpha=wrapf(e.id*13.0+total*40.0,-180,180)
			e.state="move" if e.id%3!=0 else "idle"
	world.sync(delta,selected,{})
	if unbatched:
		for batch in world.batches.values():batch.node.visible=false
		for id in world.models:
			var model: Dictionary = world.models[id]
			if model.volumetric:
				for mesh in model.volume.meshes:mesh.visible=true
			else:model.graphic.visible=true
			model.shadow.visible=true
			model.ring.visible=selected.has(id)
			model.hp_root.visible=selected.has(id)
	if total>1.0:sync_times.append(float(Time.get_ticks_usec()-tick)/1000.0)
	if total>5.0:
		frame_times.sort()
		sync_times.sort()
		var mean: float = 0.0
		for time in sync_times:mean+=time
		print("RENDER_DIAGNOSTIC ",JSON.stringify({"mode":"unbatched" if unbatched else "multimesh","resolution":root.size,"entities":sim.entities.size(),"samples":frame_times.size(),"mean_sync_ms":mean/maxi(1,sync_times.size()),"sync_p95_ms":sync_times[int(sync_times.size()*.95)],"frame_p95_ms":frame_times[int(frame_times.size()*.95)],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"simulation_active":false}))
		quit()
	return false
