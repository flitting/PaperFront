extends SceneTree

## Real GPU camera/bridge evidence. Frozen gameplay and lighting; pan actual
## camera in small steps, inspect bridge head colors in tracked world samples.
var game: Node
var output: String = "res://artifacts/camera_feedback_20261005"
var modes: Array[String] = ["forest","city"]
var errors: Array[String] = []
var rows: Array[Dictionary] = []

func _initialize() -> void: call_deferred("run")

func run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Bridge camera validation requires a real GPU/display")
		quit(2)
		return
	if OS.get_environment("XDG_DATA_HOME").is_empty():
		push_error("Bridge camera validation requires isolated XDG_DATA_HOME")
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
		elif arg.begins_with("--maps="): modes.assign(arg.trim_prefix("--maps=").split(","))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size=Vector2i(1920,1080)
	game=load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	game.set_process_unhandled_input(false)
	root.gui_disable_input=true
	game._flush_render_simulation()
	# Silence only this process's output; never persist a user's audio mute.
	AudioServer.set_bus_mute(0,true)
	game.dof_override=0
	game.set_graphics_quality("balanced")
	game.set_render_scale(1.0)
	game.hud.show_menu(false)
	game.hud.show_entry(false)
	for mode in modes:
		if not game.start_match(mode,7,"rivet",true):
			errors.append("Cannot create map "+mode)
			continue
		game.sim.ai_enabled=false
		game.sim.vision_enabled=false
		game.sim.events.clear()
		game.sim.time=0.0
		game.hud.show_menu(false)
		game.hud.show_entry(false)
		var bridge: Dictionary=game.sim.bridges[0]
		var bounds: Array=bridge.bounds
		var along_x: bool=float(bounds[2])>=float(bounds[3])
		var center:=Vector2(float(bounds[0])+float(bounds[2])*.5,float(bounds[1])+float(bounds[3])*.5)
		var axis:=Vector2.RIGHT if along_x else Vector2.DOWN
		var side:=Vector2.DOWN if along_x else Vector2.RIGHT
		var length: float=maxf(float(bounds[2]),float(bounds[3]))
		var anchor: Vector2=center-axis*length*.5
		var height: float=MapData.height_at(game.sim.map,center)
		for distance: float in [40.0,110.0]:
			var samples: Array[Dictionary]=[]
			game.distance=distance
			game.camera_pitch=30.0
			game.yaw=0.0 if along_x else PI*.5
			game.focus=anchor
			game.update_camera()
			game.world.sync(0.0,[],{})
			game.hud.refresh(game.sim,[],game.camera,false,"",0.0)
			for warm in range(8): await RenderingServer.frame_post_draw
			for frame in range(45):
				var offset: float=-.55+float(frame)*.025
				game.focus=anchor+axis*offset
				game.update_camera()
				game.world.sync(0.0,[],{})
				if frame%9==0: game.hud.refresh(game.sim,[],game.camera,false,"",0.0)
				await RenderingServer.frame_post_draw
				var img: Image=root.get_texture().get_image()
				var colors: Array=[]
				for along: float in [.15,.55,1.1]:
					for across: float in [-.5,.5]:
						var point: Vector2=anchor+axis*along+side*across
						var pixel: Vector2=game.project_world_to_screen(Vector3(point.x,height+.001,point.y))
						var sum:=Color(0,0,0,0)
						for y in range(-1,2):
							for x in range(-1,2):sum+=img.get_pixel(clampi(roundi(pixel.x)+x,0,img.get_width()-1),clampi(roundi(pixel.y)+y,0,img.get_height()-1))
						sum/=9.0
						colors.append([sum.r,sum.g,sum.b])
				var mini=game.hud.mini
				var fresh: bool=not mini._outline_key.is_empty() and (mini._outline_key[0] as Transform3D).is_equal_approx(game.camera.get_camera_transform())
				var outline: Array=[]
				for point: Vector2 in mini._outline_world:outline.append([point.x,point.y])
				if not fresh:errors.append("Stale minimap camera outline "+mode+" frame "+str(frame))
				samples.append({"frame":frame,"focus":[game.focus.x,game.focus.y],"colors":colors,"minimap_fresh":fresh,"outline":outline})
				if frame in [0,22,44]:
					var file: String="%s_%d_frame%02d.png"%[mode,roundi(distance),frame]
					img.save_png(output.path_join(file))
			var worst: float=0.0
			for index in range(1,samples.size()):
				for point in range(samples[index].colors.size()):
					var before: Array=samples[index-1].colors[point]
					var after: Array=samples[index].colors[point]
					worst=maxf(worst,Vector3(before[0],before[1],before[2]).distance_to(Vector3(after[0],after[1],after[2])))
			var row: Dictionary={"map":mode,"seed":7,"bridge":bridge.id,"bounds":bounds,"distance":distance,"frame_count":samples.size(),"tracked_rgb_step_max":worst,"samples":samples}
			rows.append(row)
			print("BRIDGE_CAMERA ",JSON.stringify({"map":mode,"distance":distance,"frames":samples.size(),"tracked_rgb_step_max":worst,"minimap_errors":errors.size()}))
	var report: Dictionary={"scope":"Real Forward+GPU, frozen map/lighting, actual camera pan and per-frame minimap; tracked3x3color averages may contain ordinary antialias/shadow variation, geometry tests prove depth ownership.","gpu":RenderingServer.get_video_adapter_name(),"resolution":root.size,"rows":rows,"errors":errors,"source_sha256":{}}
	for path in ["res://scripts/main.gd","res://scripts/minimap.gd","res://scripts/landscape.gd","res://scripts/bridge_craft.gd","res://data/rules.json"]:report.source_sha256[path]=FileAccess.get_sha256(path)
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	game.quit_pending=true
	game.queue_free()
	await process_frame
	quit(0 if errors.is_empty() else 1)
