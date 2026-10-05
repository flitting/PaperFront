extends SceneTree

## Short graphics-cost isolation only. This is never an acceptance benchmark.
func _initialize() -> void:
	call_deferred("start")

func start() -> void:
	var game:Node3D=load("res://main.tscn").instantiate()
	root.add_child(game)
	var args:=OS.get_cmdline_user_args()
	if "--no-ao" in args:game.environment.ssao_enabled=false
	if "--no-shadows" in args:game.key_light.shadow_enabled=false
	if "--no-msaa" in args:game.battlefield_viewport.msaa_3d=Viewport.MSAA_DISABLED
	if "--shadow-2048" in args:RenderingServer.directional_shadow_atlas_set_size(2048,false)
	if "--ao-low" in args:
		RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_LOW,true,0.5,1,50.0,120.0)
	if "--fxaa" in args:game.battlefield_viewport.screen_space_aa=Viewport.SCREEN_SPACE_AA_FXAA
	print("GRAPHICS_DIAGNOSTIC ",JSON.stringify({"ao":game.environment.ssao_enabled,"shadows":game.key_light.shadow_enabled,"msaa":game.battlefield_viewport.msaa_3d,"shadow_2048":"--shadow-2048" in args}))
