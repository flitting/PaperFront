extends SceneTree
const Sim = preload("res://tests/rule_test_simulation.gd")
const Ground = preload("res://scripts/squad_ground_markers.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func run() -> void:
	var sim = Sim.new()
	sim.setup(RulesLoader.load_rules(),"dev",47,"kestrel",false,{"vision_enabled":false})
	for row in sim.map.heights: row.fill(2.0)
	for row in sim.map.terrain: row.fill(0)
	sim.ruins.clear(); sim._refresh_ruin_spatial(); sim._prepare_terrain_cache()
	var leader: int=sim.debug_spawn_squad(0,"kestrel_rifle",Vector2(20,26),true)
	var ids: Array=sim.squad_members(leader)
	var engineer: int=sim._spawn(0,"kestrel_engineer",Vector2(25,26),true)
	var camera:=Camera3D.new(); root.add_child(camera)
	camera.position=Vector3(23,22,55); camera.look_at(Vector3(23,2,27))
	var world:=PaperWorld.new(); root.add_child(world); world.setup(sim,camera)
	for native in [false,true]:
		world.native_world_sync_enabled=native
		world.sync(.016,ids+[engineer])
		check(world.squad_markers.size()==1 and world.squad_markers[0].count==5,"one ground base per selected squad; solo engineer has none")
		var marker: Dictionary=world.squad_markers[0]
		check(marker.segments.size()==8,"four L corners contain exactly eight short arms")
		check(marker.color==VolumeModels.player_color(0),"ground corners retain the exact owning force color")
		check(marker.points.size()==4 and Array(marker.points).all(func(p):return is_equal_approx(p.y,2.0+Ground.LIFT)),"all four corner anchors sit on the floor, not at head height")
		for segment: PackedVector2Array in marker.segments:
			check(segment[0].distance_to(segment[1])<=Ground.MAX_ARM+.001,"corner arms leave the middle of each edge disconnected")
		var mesh: ArrayMesh=world.squad_marker_node.mesh
		check(mesh.get_surface_count()==2,"only ink and force-color corner strokes are submitted")
		var positions: PackedVector3Array=mesh.surface_get_arrays(1)[Mesh.ARRAY_VERTEX]
		check(not positions.is_empty() and Array(positions).all(func(p):return absf(p.y-MapData.height_at(sim.map,Vector2(p.x,p.z))-Ground.LIFT)<.0001),"every stroke vertex follows the real terrain surface")
		var material: StandardMaterial3D=mesh.surface_get_material(1)
		check(not material.no_depth_test,"ground marker uses normal depth occlusion instead of drawing over bodies")
		var colors: PackedColorArray=mesh.surface_get_arrays(1)[Mesh.ARRAY_COLOR]
		check(Array(colors).all(func(c):return c==VolumeModels.player_color(0)),"rendered stroke vertices carry the owning force color")
		var old_mesh: Mesh=world.squad_marker_node.mesh
		world.sync(0.0,ids)
		check(world.squad_marker_node.mesh==old_mesh,"stationary ground geometry is reused")
		world.sync(0.0,[])
		check(not world.squad_marker_node.visible,"deselection removes all ground corner marks")
	var rotated:=PackedVector2Array([Vector2(0,0),Vector2(1,1),Vector2(-1,1),Vector2(0,2)])
	var frame: Dictionary=Ground.footprint(rotated,.66)
	check(absf(frame.right.x)>.5 and absf(frame.right.y)>.5,"footprint follows rotated squad rows rather than a camera-facing screen box")
	var old_position: Vector3=camera.position
	var before: Array[Dictionary]=Ground.collect(sim,ids)
	camera.position=Vector3(50,8,27);camera.look_at(Vector3(22,2,27))
	check(Ground.collect(sim,ids)==before,"changing camera angle cannot move or stand up the squad base")
	camera.position=old_position
	sim.entities[ids[2]].hp=0
	check(Ground.collect(sim,ids)[0].count==4,"dead members no longer enlarge the ground base")
	for id in ids:sim.entities[id].garrison_id=1
	check(Ground.collect(sim,ids).is_empty(),"garrisoned troops leave no marker outside the building")
	world.queue_free();camera.queue_free();await process_frame
	print("SQUAD_GROUND_MARKERS ",JSON.stringify({"checks":checks,"failures":failures}))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
