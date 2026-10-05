extends SceneTree
const Cache=preload("res://scripts/terrain_resource_cache.gd")
const Factions=preload("res://scripts/performance_factions.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var report:Array=[]
	for preset in ["normal","large_hq","eight_owners"]:
		var sim:=WarSimulation.new()
		if preset=="eight_owners":
			var positions:Array[Vector2]=[]
			for team in range(8):positions.append(Vector2(320,352)+Vector2.from_angle(float(team)*TAU/8.0)*70)
			sim.setup_multiteam(Factions.make_rules(RulesLoader.load_rules()),"mountains640",73026,Factions.ids(),false,positions)
		else:sim.setup(RulesLoader.load_rules(),"mountains640",73026,"iron" if preset=="large_hq" else "rivet",false)
		var began:int=Time.get_ticks_usec()
		var landscape:=PaperLandscape.new();landscape.terrain_disk_cache_enabled=false
		landscape._build(sim)
		var key:String=Cache.key_for([sim.map,landscape._ground_exclusions])
		var error:int=Cache.store_entry(key,PaperLandscape._terrain_cache,"res://assets/terrain_cache",0)
		if error!=OK:push_error("Cannot bake terrain preset "+preset);landscape.free();quit(1);return
		var row:Dictionary={"preset":preset,"key":key,"path":"res://assets/terrain_cache/"+key+".res","build_ms":(Time.get_ticks_usec()-began)/1000.0,"stats":landscape.stats.duplicate()}
		report.append(row);print("BAKED_TERRAIN_PRESET ",JSON.stringify(row))
		landscape.free();sim=null
	FileAccess.open("res://assets/terrain_cache/manifest.json",FileAccess.WRITE).store_string(JSON.stringify({"schema":1,"presets":report},"\t"))
	quit()
