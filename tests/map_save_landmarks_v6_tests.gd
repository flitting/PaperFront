extends SceneTree

const Sim=preload("res://tests/rule_test_simulation.gd")
const Saves=preload("res://scripts/sim_save_validator.gd")
var checks:int=0
var failures:Array[String]=[]

func _initialize()->void:call_deferred("run")

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)

func read_snapshot(path:String)->Dictionary:
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:return {}
	var value:Variant=file.get_var(false)
	file.close()
	return value if value is Dictionary else {}

func rejected(snapshot:Dictionary,index:int,patch:Dictionary,label:String)->void:
	var invalid:Dictionary=snapshot.duplicate(true)
	invalid.ruins[index].merge(patch,true)
	check(Saves.check(invalid)=="存档废墟占地无效",label)

func run()->void:
	var rules:Dictionary=RulesLoader.load_rules("res://data/rules.json",false)
	var all_factions:Array[String]=["kestrel","rivet","iron","sky"]
	var large_snapshot:Dictionary={}
	var large_index:int=-1
	var rounds:Array=[]
	var path:String="user://v6_authored_landmark_roundtrip.pfront"
	for mode:String in ["city","random_city","forest","desert","snow","islands"]:
		for players:int in [2,3,4]:
			var sim=Sim.new()
			var factions:Array[String]=[]
			for team in range(players):factions.append(all_factions[team])
			sim.setup_multiteam(rules,mode,17,factions,false)
			check(sim.save_game(path).is_empty(),mode+"/"+str(players)+" writes generated snapshot")
			var snapshot:Dictionary=read_snapshot(path)
			var validation:String=Saves.check(snapshot)
			check(validation.is_empty(),mode+"/"+str(players)+" generated snapshot validates: "+validation)
			var restored=Sim.new()
			var load_error:String=restored.load_game(path)
			check(load_error.is_empty(),mode+"/"+str(players)+" generated snapshot loads: "+load_error)
			if load_error.is_empty():
				check(restored.map.terrain==sim.map.terrain and restored.map.heights==sim.map.heights and restored.map.starts==sim.map.starts,mode+"/"+str(players)+" preserves terrain and fair starts")
				check(restored.ruins==sim.ruins and restored.factions==sim.factions,mode+"/"+str(players)+" preserves actual colliders, scenery state and owners")
			var broad:int=0
			for index in range(snapshot.ruins.size()):
				if (snapshot.ruins[index].half as Vector2).length()>6.0:
					broad+=1
					if mode=="islands" and players==2:
						large_snapshot=snapshot
						large_index=index
			rounds.append({"mode":mode,"players":players,"large_landmarks":broad,"validation_error":validation,"load_error":load_error})
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(large_index>=0,"island fixture contains its real broad stone fortress")
	if large_index>=0:
		rejected(large_snapshot,large_index,{"half":Vector2(10.6,10.5)},"named landmark still rejects an excessive axis")
		rejected(large_snapshot,large_index,{"half":Vector2(100,100)},"named landmark rejects arbitrary huge colliders")
		rejected(large_snapshot,large_index,{"half":Vector2(NAN,10.5)},"named landmark rejects NaN footprint")
		rejected(large_snapshot,large_index,{"half":Vector2(INF,10.5)},"named landmark rejects infinite footprint")
		rejected(large_snapshot,large_index,{"half":Vector2.ZERO},"named landmark rejects zero footprint")
		rejected(large_snapshot,large_index,{"half":Vector2(-1,10.5)},"named landmark rejects negative footprint")
		rejected(large_snapshot,large_index,{"archetype":"unknown_landmark"},"unknown archetype cannot bypass the ordinary bound")
		rejected(large_snapshot,large_index,{"kind":"tree"},"known house archetype cannot enlarge unrelated scenery")
		rejected(large_snapshot,large_index,{"pos":Vector2(2,2)},"full landmark footprint must remain inside the map")
		rejected(large_snapshot,large_index,{"yaw":NAN},"broad landmark rejects nonfinite rotation")
		var invalid:Dictionary=large_snapshot.duplicate(true)
		invalid.ruins[large_index].erase("archetype")
		check(Saves.check(invalid)=="存档废墟占地无效","unnamed ordinary ruin keeps the original six-metre bound")
		invalid=large_snapshot.duplicate(true)
		invalid.ruins[large_index].half=Vector2(4.2,4.2)
		invalid.ruins[large_index].erase("archetype")
		check(Saves.check(invalid).is_empty(),"historical ordinary footprint below six metres still validates")
		for version:Variant in ["6",6.0]:
			invalid=large_snapshot.duplicate(true)
			invalid.map.profile.design_version=version
			check(not Saves.check(invalid).is_empty(),"malformed authored version cannot grant a broad-footprint exception: "+str(version))
	print("V6_AUTHORED_LANDMARK_SAVES ",JSON.stringify({"checks":checks,"failures":failures,"roundtrips":rounds}))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
