extends SceneTree
const Sim=preload("res://tests/rule_test_simulation.gd")
var hud: PaperHUD
func _initialize() -> void:call_deferred("run")
func run() -> void:
	if OS.get_environment("PAPER_FRONT_CAPTURE_OFFSCREEN")!="1":quit(2);return
	root.size=Vector2i(1600,1000);root.content_scale_size=root.size
	var bg=ColorRect.new();bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);bg.color=Color("ddd0b7");root.add_child(bg)
	hud=PaperHUD.new();root.add_child(hud)
	for frame in range(3):await process_frame
	hud.show_entry(false);hud.show_menu(false)
	var manifest:Array=[]
	for faction in ["kestrel","rivet","iron","sky"]:
		var sim=Sim.new();sim.setup(RulesLoader.load_rules(),"dev",211,faction,false,{"vision_enabled":false})
		# Real constructed tech unlocks the shipyard through the ordinary catalog.
		for id in sim.rules.buildings:
			if sim.rules.buildings[id].faction==faction:sim._spawn(0,id,Vector2(20,20),true)
		var selected:int=-1
		for e in sim.entities.values():
			if e.team==0 and ((faction=="rivet" and e.spec=="rivet_engineer") or (faction!="rivet" and sim.data_for(e.spec).get("role","")=="hq")):selected=e.id;break
		if selected<0:selected=sim._spawn(0,faction+"_engineer",Vector2(20,20),true)
		hud.sim=sim;hud.selection=[selected];hud.tab="build";hud.rebuild_list()
		hud.production_panel.show();hud.dock.show()
		for frame in range(4):await process_frame
		var id:String=faction+"_shipyard"
		if not hud.entry_widgets.has(id):push_error("Missing real shipyard catalog button "+id);quit(1);return
		var entry: Dictionary=hud.entry_widgets[id]
		var button:Button=entry.button
		hud.build_scroll.ensure_control_visible(button)
		for frame in range(4):await process_frame
		RenderingServer.force_draw()
		var path:String="res://artifacts/latest_visual_v2/"+faction+"_shipyard_catalog.png"
		root.get_texture().get_image().save_png(path)
		manifest.append({"faction":faction,"source":sim.rules.buildings[id].animations.idle,"button_visible":button.is_visible_in_tree(),"image":path})
	print("SHIPYARD_ACTUAL_UI ",JSON.stringify(manifest))
	hud.free();await process_frame;quit()
