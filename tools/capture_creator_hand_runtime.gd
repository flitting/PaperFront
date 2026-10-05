extends SceneTree
const PICKING=preload("res://scripts/entity_picking.gd")

## Main-scene attack capture. The normal simulation, terrain, camera, world
## renderer, target damage and hero windup all run; only fixture spawns and
## camera placement are scripted.
const OUT := "res://artifacts/creator_hand/runtime"
var game:Node
var captured:Array[String]=[]
var failures:Array[String]=[]
var contacts:Dictionary={}
var input_points:Dictionary={}

func _initialize()->void:call_deferred("run")

func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	game=load("res://main.tscn").instantiate()
	root.add_child(game)
	for i in range(5):await process_frame
	game.audio.muted=true
	if not game.start_match("dev",7,"sky",true):
		failures.append("start_match")
		_finish();return
	game.hud.show_menu(false)
	game.hud.show_entry(false)
	game.pve_paused=true
	for i in range(5):await process_frame
	var origin:=Vector2.INF
	for z in range(40,45):
		for x in range(12,23):
			var candidate:=Vector2(x+.5,z+.5)
			if game.sim._segment_static(candidate,candidate+Vector2(7,0),1.5,-1) and game.sim._standing(candidate+Vector2(7,0),2.0,-1):
				origin=candidate
				break
		if origin.is_finite():break
	if not origin.is_finite():
		failures.append("legal fixture corridor")
		_finish();return
	var hand_id:int=game.sim.debug_spawn(0,"sky_creator_hand",origin)
	if hand_id<1:
		failures.append("hand spawn")
		_finish();return
	game.focus=origin+Vector2(2.7,0)
	game.distance=27.0
	game.camera_pitch=34.0
	game.yaw=PI*.5+.25
	game.update_camera()
	game.world.sync(0.0,[],{})
	for i in range(5):await process_frame
	var hand_point:Vector2=_visible_point(hand_id)
	if not hand_point.is_finite():
		failures.append("visible anatomical hand pick point")
	else:
		await _click(hand_point,MOUSE_BUTTON_LEFT)
		if game.selected!=[hand_id]:failures.append("real left click selects skinned hand")
		input_points.hand=[hand_point.x,hand_point.y]
	await _capture("stand")
	await _attack_target(hand_id,"rivet_tank",origin+Vector2(5.2,0),"tank")
	if game.sim.entities.has(hand_id):
		game.sim.entities[hand_id].cooldown=0.0
		await _attack_target(hand_id,"rivet_power",origin+Vector2(5.2,0),"building")
	_finish()

func _attack_target(hand_id:int,spec:String,point:Vector2,label:String)->void:
	game.pve_paused=true
	var target_id:int=game.sim.debug_spawn(1,spec,point)
	if target_id<1:
		failures.append(label+" spawn")
		return
	game.world.sync(0.0,[],{})
	for i in range(3):await process_frame
	await _capture(label+"_before")
	var destination:Vector2=game.sim.entities[target_id].pos
	var target_point:Vector2=_visible_point(target_id)
	if not target_point.is_finite():
		failures.append(label+" visible target pick point")
		game.sim.issue([hand_id],"attack",destination,target_id)
	else:
		await _click(target_point,MOUSE_BUTTON_RIGHT)
		input_points[label]=[target_point.x,target_point.y]
		var commands:Array=game.sim.entities[hand_id].commands
		if commands.is_empty() or commands[0].kind!="attack" or int(commands[0].target)!=target_id:
			failures.append(label+" real right click attack command")
			game.sim.issue([hand_id],"attack",destination,target_id)
	game.pve_paused=false
	var windup:=false
	var contact:=false
	var result:=false
	var started:int=Time.get_ticks_usec()
	while Time.get_ticks_usec()-started<12000000:
		await process_frame
		if not game.sim.entities.has(hand_id):
			failures.append(label+" hand died")
			break
		if game.sim.entities.has(target_id):
			var e:Dictionary=game.sim.entities[hand_id]
			var remaining:float=float(e.get("hand_strike",0.0))
			if remaining>0.0 and remaining<.36 and not windup:
				windup=true
				game.pve_paused=true
				await _capture(label+"_windup")
				game.pve_paused=false
			if remaining>0.0 and remaining<.055 and not contact:
				contact=true
				game.pve_paused=true
				var volume:Dictionary=game.world.models[hand_id].volume
				var foot_positions:Array=[]
				for local_tip in volume.support_tips:
					var point3:Vector3=volume.root.to_global(local_tip)
					foot_positions.append([point3.x,point3.y,point3.z])
				var posed:Dictionary=PICKING._skinned_surface(volume.skinned_mesh,volume,{})
				var shell_min_y:float=INF
				for surface in posed.surfaces:
					for vertex in surface.vertices:
						var world_point:Vector3=volume.skinned_mesh.global_transform*vertex
						if absf(world_point.x-destination.x)<1.2 and absf(world_point.z-destination.y)<1.2:
							shell_min_y=minf(shell_min_y,world_point.y)
				contacts[label]={"target":[destination.x,destination.y],"height":float(e.get("hand_contact_height",0.0)),"fingertips":foot_positions,"shell_min_y":shell_min_y,"remaining":remaining}
				await _capture(label+"_contact")
				var old_yaw:float=game.yaw
				var old_pitch:float=game.camera_pitch
				var old_distance:float=game.distance
				var old_focus:Vector2=game.focus
				game.yaw=0.0
				game.camera_pitch=25.0
				game.distance=22.0
				game.focus=destination+Vector2(-2.0,0)
				game.update_camera()
				await _capture(label+"_contact_side")
				game.yaw=old_yaw
				game.camera_pitch=old_pitch
				game.distance=old_distance
				game.focus=old_focus
				game.update_camera()
				game.pve_paused=false
		elif not result:
			result=true
			# The native renderer consumes simulation deletion on the next world
			# update; capture after that update, not the last alive frame.
			for i in range(10):await process_frame
			game.pve_paused=true
			game.world.sync(0.0,[],{})
			for i in range(3):await process_frame
			await _capture(label+"_destroyed")
			game.pve_paused=false
			break
	if not windup:failures.append(label+" windup frame")
	if not contact:failures.append(label+" contact frame")
	if not result:failures.append(label+" actual target destruction")
	game.pve_paused=false
	var recovery_deadline:int=Time.get_ticks_usec()+1500000
	while Time.get_ticks_usec()<recovery_deadline and game.sim.entities.has(hand_id) and float(game.sim.entities[hand_id].get("hand_recover",0.0))>.045:
		await process_frame
	game.pve_paused=true
	await _capture(label+"_recovery")

func _capture(name:String)->void:
	for i in range(2):await process_frame
	await RenderingServer.frame_post_draw
	var path:String=OUT.path_join(name+".png")
	if game.get_viewport().get_texture().get_image().save_png(path)!=OK:
		failures.append("save "+name)
	else:captured.append(name)

func _visible_point(id:int)->Vector2:
	if not game.world.models.has(id):return Vector2.INF
	var model:Dictionary=game.world.models[id]
	for graphic in model.volume.meshes:
		var surfaces:Array=[]
		if bool(model.get("direct_skinned",false)):
			var posed:Dictionary=PICKING._skinned_surface(graphic,model.volume,{})
			if not posed.is_empty():surfaces=posed.surfaces
		else:
			for s in range(graphic.mesh.get_surface_count()):
				var arrays:Array=graphic.mesh.surface_get_arrays(s)
				surfaces.append({"vertices":arrays[Mesh.ARRAY_VERTEX],"indices":arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()})
		for surface in surfaces:
			var vertices:PackedVector3Array=surface.vertices
			var indices:PackedInt32Array=surface.indices
			var count:int=indices.size() if not indices.is_empty() else vertices.size()
			var stride:int=maxi(3,(count/180)/3*3)
			for i in range(0,count-2,stride):
				var bary:=Vector3.ZERO
				for corner in range(3):
					bary+=vertices[indices[i+corner] if not indices.is_empty() else i+corner]/3.0
				var screen:Vector2=game.project_world_to_screen(graphic.global_transform*bary)
				if screen.is_finite() and game.battlefield_rect().has_point(screen) and not game.hud.blocks_world_scroll(screen) and game.pick_entity(screen)==id:
					return screen
	return Vector2.INF

func _click(point:Vector2,button:MouseButton)->void:
	var pixel:Vector2=game.get_viewport().get_final_transform()*point
	var motion:=InputEventMouseMotion.new()
	motion.position=pixel
	motion.global_position=pixel
	Input.parse_input_event(motion)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new()
		event.position=pixel
		event.global_position=pixel
		event.button_index=button
		event.pressed=pressed
		event.button_mask=(MOUSE_BUTTON_MASK_LEFT if button==MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if pressed else 0
		Input.parse_input_event(event)
		await process_frame

func _finish()->void:
	for name in ["stand","tank_before","tank_windup","tank_contact","tank_contact_side","tank_destroyed","tank_recovery","building_before","building_windup","building_contact","building_contact_side","building_destroyed","building_recovery"]:
		if not captured.has(name):failures.append("missing "+name)
	var report:Dictionary={"captures":captured,"contacts":contacts,"input_points":input_points,"failures":failures,"native_simulation":game.sim.native_kernels_enabled if game and game.sim else false,"native_render":game.world.native_batches_enabled if game and game.world else false}
	var file:=FileAccess.open(OUT+"/report.json",FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(report,"  "))
	print("CREATOR_HAND_RUNTIME ",JSON.stringify(report))
	for issue in failures:push_error(issue)
	quit(0 if failures.is_empty() else 1)
