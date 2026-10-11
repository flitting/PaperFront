extends SceneTree
const Sim = preload("res://tests/rule_test_simulation.gd")
const Overlay = preload("res://scripts/selection_overlay.gd")
const L = preload("res://scripts/localization.gd")
const OUT = "res://artifacts/squad_readability_20261009/"
var sim
var world: PaperWorld
var camera: Camera3D
var overlay
var selected: Array = []
var title: Label

class Projector:
	extends Node3D
	var camera: Camera3D
	func project_world_to_screen(point: Vector3) -> Vector2: return camera.unproject_position(point)
	func battlefield_rect() -> Rect2: return Rect2(Vector2.ZERO,Vector2(1600,900))

func _initialize() -> void: call_deferred("run")
func capture(name: String) -> void:
	world.sync(0.0,selected)
	overlay.selection = selected
	overlay.refresh_overlay()
	for i in range(6): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+name+".png")
	print("SQUAD_READABILITY ",name)

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	L.initialize("en")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1600,900); root.content_scale_size = root.size
	VolumeModels.configure_player_colors(["#347dd0","#d85140"])
	sim = Sim.new(); sim.setup(RulesLoader.load_rules(),"dev",47,"kestrel",false,{"vision_enabled":false})
	for e in sim.entities.keys(): sim._kill_entity(e,false)
	for z in range(sim.map.size):
		for x in range(sim.map.size): sim.map.terrain[z][x]=0; sim.map.heights[z][x]=0.0
	sim.ruins.clear(); sim.mines.clear(); sim.bridges.clear(); sim.map.bridges.clear()
	sim.events.clear(); sim._refresh_ruin_spatial(); sim._refresh_mine_spatial(); sim._prepare_terrain_cache()
	for pos: Vector2 in [Vector2(20,23),Vector2(24.2,23),Vector2(20,28.2),Vector2(24.2,28.2)]:
		var id: int = sim.debug_spawn_squad(0,"kestrel_rifle",pos,true)
		selected.append_array(sim.squad_members(id))
	for pos: Vector2 in [Vector2(29,24),Vector2(29,29)]:
		var id: int = sim.debug_spawn_squad(1,"rivet_rifle",pos,true)
		selected.append_array(sim.squad_members(id))
	selected.append(sim._spawn(0,"kestrel_engineer",Vector2(17,26),true))
	selected.append(sim._spawn(0,"kestrel_tank",Vector2(17,30),true))
	selected.append(sim._spawn(0,"kestrel_power",Vector2(16,22),true))
	var env := WorldEnvironment.new(); var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR; settings.background_color = Color("d8ccb5")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; settings.ambient_light_color = Color("d7dfef"); settings.ambient_light_energy=.6
	env.environment = settings; root.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-48,-36,0); sun.light_energy=1.0; sun.shadow_enabled=true; root.add_child(sun)
	camera = Camera3D.new(); camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 21
	root.add_child(camera); camera.current=true
	camera.position = Vector3(24,19,47); camera.look_at(Vector3(24,0,26))
	world = PaperWorld.new(); root.add_child(world); world.setup(sim,camera)
	var layer := CanvasLayer.new(); root.add_child(layer)
	overlay = Overlay.new(); overlay.sim=sim; overlay.camera=camera
	var projector := Projector.new(); root.add_child(projector); projector.camera=camera; overlay.projector=projector
	layer.add_child(overlay); overlay.size=Vector2(1600,900)
	title = Label.new(); title.position=Vector2(24,20); title.add_theme_font_size_override("font_size",25); title.add_theme_color_override("font_color",Color("292b2b")); layer.add_child(title)
	title.text = "COMPACT SQUADS / FORCE-COLORED BOUNDARIES / NO UNIT CIRCLES"
	await capture("compact_oblique")
	camera.position = Vector3(24,34,35); camera.look_at(Vector3(24,0,26))
	await capture("compact_top")
	camera.size=14; camera.position=Vector3(26,9,41); camera.look_at(Vector3(24,0,26))
	await capture("compact_close")
	L.set_language("zh_CN")
	await capture("compact_close_chinese")
	world.free(); camera.free(); overlay.free(); projector.free(); sun.free(); env.free(); layer.free()
	sim = null
	await process_frame; quit()
