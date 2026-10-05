extends SceneTree

# Real Forward+ pixels. Exploration/teleport and result fixtures are disclosed;
# this probe does not claim paid gameplay, human listening or speed gains.
const OUT := "res://artifacts/revision_v7_integration/visual"
var game
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var report: Dictionary = {}
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String,evidence:Variant=null)->void:
	checks.append({"label":label,"pass":ok,"evidence":evidence})
	if not ok:failures.append(label)
func frames(count:int=8)->void:
	for i:int in count:await process_frame
func capture(name:String)->Image:
	await frames()
	await RenderingServer.frame_post_draw
	var img:Image=root.get_texture().get_image()
	check(img.save_png(OUT+"/"+name+".png")==OK,"save actual GPU pixels: "+name)
	return img
func fps_visible()->bool:
	return game.hud.fps_label.is_visible_in_tree() and game.hud.fps_label.text.ends_with(" FPS") and game.performance_overlay.layer==7
func fog_pixel_probe(reference:Image,filtered:Image)->Dictionary:
	var rows:Array=[]
	var clear:Array[float]=[];var hidden:Array[float]=[]
	var bounds:Rect2=game.battlefield_rect()
	for x:int in range(6,315,3):
		for z:int in range(6,315,3):
			var p:=Vector2(x,z)
			var pixel:Vector2=game.project_world_to_screen(Vector3(x,MapData.height_at(game.sim.map,p),z))
			if not bounds.grow(-12).has_point(pixel):continue
			pixel *= Vector2(reference.get_size()) / root.get_visible_rect().size
			var ix:int=clampi(roundi(pixel.x),0,reference.get_width()-1)
			var iz:int=clampi(roundi(pixel.y),0,reference.get_height()-1)
			var a:Color=reference.get_pixel(ix,iz);var b:Color=filtered.get_pixel(ix,iz)
			var la:float=a.get_luminance();var lb:float=b.get_luminance()
			if la<.08:continue
			var visible:bool=game.sim.position_visible_to(0,p)
			if visible:clear.append(absf(lb-la))
			else:hidden.append(lb/la)
	clear.sort();hidden.sort()
	return {"clear_samples":clear.size(),"hidden_samples":hidden.size(),"clear_median_absolute_luminance_change":clear[clear.size()/2] if not clear.is_empty() else -1,"hidden_median_luminance_ratio":hidden[hidden.size()/2] if not hidden.is_empty() else -1}
func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size=Vector2i(1920,1080)
	game=load("res://main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_physics_process(false);game.audio.muted=true
	await create_timer(.7).timeout
	check(fps_visible(),"FPS appears on clean entry with Debug disabled")
	await capture("entry_1080")
	game.handle_action("settings_open",null)
	await capture("settings_1080")
	check(fps_visible(),"FPS remains above unified settings")
	game.hud.settings.close();game.handle_action("entry_play",null)
	await capture("maps_1080")
	check(game.hud.map_option.item_count==6,"six maps and no legacy/dev options by default")
	root.size=Vector2i(1100,700);await frames()
	game.handle_action("settings_open",null);await capture("settings_minimum")
	check(fps_visible(),"FPS remains visible at minimum window")
	game.hud.settings.close();await capture("maps_minimum")
	root.size=Vector2i(1920,1080)
	check(game.start_match("city",73026,"kestrel",true),"current city map starts in actual main")
	game.hud.show_menu(false);game.hud.show_entry(false);game.sim.ai_enabled=false;game.pve_paused=true
	game.focus+=Vector2(9,9);game.distance=72;game.update_camera()
	game.world.sync(0,[],{})
	await create_timer(2.5).timeout
	game.world._fog_node.hide();var reference:Image=await capture("city_fog_reference")
	game.world._fog_node.show();var filtered:Image=await capture("city_fog_current")
	var pixels:Dictionary=fog_pixel_probe(reference,filtered);report.fog_pixels=pixels
	check(pixels.clear_samples>5 and pixels.hidden_samples>20,"fixed camera contains both live and unobserved pixels",pixels)
	check(pixels.clear_median_absolute_luminance_change<.03,"fog preserves current-vision pixels",pixels)
	check(pixels.hidden_median_luminance_ratio<.65,"no-current-vision terrain has a strong visible dark filter",pixels)
	check(game.world._fog_material.render_priority==120,"fog renders after ordinary transparency")
	var groups:Array=game.world.landscape._civilian_batches
	check(groups.size()==3,"city has three real civilian batches")
	for group:Dictionary in groups:
		check(group.multi.mesh.get_meta("representation","")=="flat_cut_paper","real civilian batch uses flat paper mesh")
		check(group.multi.mesh.surface_get_material(0) is ShaderMaterial,"real civilian batch uses camera-facing paper shader")
	if not groups.is_empty() and groups[0].multi.instance_count>0:
		var anchor:Vector3=groups[0].multi.get_instance_transform(0).origin
		game.focus=Vector2(anchor.x,anchor.z);game.distance=17;game.update_camera()
		game.world._fog_node.hide();game.world.sync(0,[],{});game.world._fog_node.hide()
		await capture("civilians_close")
		game.yaw=PI*.5;game.update_camera();game.world.sync(0,[],{});game.world._fog_node.hide()
		await capture("civilians_rotated")
	game.world._fog_node.show()
	var memory:Dictionary=game.world.export_visual_memory()
	check(game.sim.save_game("user://v7_visual.pfront",memory).is_empty(),"save actual map and explored visual memory")
	check(game.sim.load_game("user://v7_visual.pfront").is_empty() and not game.sim.visual_memory.is_empty(),"load keeps explored memory in real save snapshot")
	check(game.world.restore_visual_memory(game.sim.visual_memory),"restore JSON exploration in actual world")
	check(fps_visible(),"FPS remains on paused battlefield")
	game.hud.action.emit("entry_home",null);await capture("return_entry")
	check(game.hud.entry_menu.visible and fps_visible(),"return menu preserves FPS overlay")
	report.merge({"godot":Engine.get_version_info().string,"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"quality":game.graphics_quality,"render_scale":game.render_scale,"ao":game.environment.ssao_enabled,"shadows":game.key_light.shadow_enabled,"dof":game.lens.dof_blur_far_enabled,"checks":checks,"failures":failures,"sources":{},"native_sha256":FileAccess.get_sha256("res://assets/native/libpaper_front_kernels.so"),"performance_scope":"paused city opening fixture; FPS screenshot is not a benchmark"})
	for p:String in ["res://scripts/main.gd","res://scripts/paper_hud.gd","res://scripts/paper_world.gd","res://scripts/paper_audio.gd","res://scripts/paper_music.gd","res://scripts/performance_overlay.gd","res://assets/fog/battlefield_fog.gdshader","res://assets/civilians/paper_civilian.gdshader"]:report.sources[p]=FileAccess.get_sha256(p)
	var f:=FileAccess.open(OUT+"/report.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close()
	print("REVISION_V7_VISUAL ",JSON.stringify({"checks":checks.size(),"failed":failures.size(),"fog_pixels":pixels,"renderer":report.renderer}))
	for failure:String in failures:push_error(failure)
	await game.quit_game(0 if failures.is_empty() else 1)
