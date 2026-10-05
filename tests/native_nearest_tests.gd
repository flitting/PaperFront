extends SceneTree
var failures:Array[String]=[]
var checks:int=0
func _initialize()->void:
	if not ClassDB.class_exists("PaperFrontKernels"):
		push_error("Native kernel is not loaded; this comparison cannot silently test the fallback")
		quit(1);return
	var sim:=WarSimulation.new()
	sim.setup(RulesLoader.load_rules(),"dev",7,"rivet",false)
	var rng:=RandomNumberGenerator.new()
	rng.seed=73026
	sim.entities.clear();sim._building_entities.clear()
	for i in range(180):
		var team:int=i%2
		var role:String=["rifle","tank","aa","fighter","engineer"][i%5]
		var id:int=sim._spawn(team,sim.factions[team]+"_"+role,Vector2(rng.randf_range(0,48),rng.randf_range(0,48)),true)
		if i%17==0:sim.entities[id].transport_id=999
		if i%23==0:sim.entities[id].hp=0.0
	sim._rebuild_spatial();sim._in_step=true
	sim._spec_cache=sim.rules.units.duplicate()
	sim._spec_cache.merge(sim.rules.buildings)
	for id in sim.rules.units:
		if sim.rules.units[id].get("domain","ground")=="air":sim._air_specs[id]=true
	for spec_id in sim._spec_cache:sim._weapon_target_masks[spec_id]=sim._target_mask_for_spec(sim._spec_cache[spec_id])
	for round_index in range(30):
		sim.native_kernels_enabled=false
		sim._rebuild_spatial()
		var expected:Array=[sim._spatial.duplicate(true),sim._combat_spatial.duplicate(true),sim._contact_spatial.duplicate(true),sim._contact_indices.duplicate(),sim._contact_ids.slice(0,sim._contacts_used),sim._contact_positions.slice(0,sim._contacts_used),sim._contact_teams.slice(0,sim._contacts_used),sim._contact_domains.slice(0,sim._contacts_used),sim._team_spatial.duplicate(true)]
		sim.native_kernels_enabled=true
		sim._rebuild_spatial()
		var actual:Array=[sim._spatial,sim._combat_spatial,sim._contact_spatial,sim._contact_indices,sim._contact_ids.slice(0,sim._contacts_used),sim._contact_positions.slice(0,sim._contacts_used),sim._contact_teams.slice(0,sim._contacts_used),sim._contact_domains.slice(0,sim._contacts_used),sim._team_spatial]
		checks+=1
		if actual!=expected:failures.append("native spatial index differs in round "+str(round_index))
		for e in sim.entities.values():
			var radius:float=[0.0,1.0,8.0,16.0,40.0][round_index%5]
			var original:Vector2=e.pos
			e.pos=Vector2(rng.randf_range(0,48),rng.randf_range(0,48))
			sim._spatial_move(e,original,e.pos)
			sim.native_kernels_enabled=true
			var native_result:int=sim._nearest_enemy(e,radius)
			sim.native_kernels_enabled=false
			var script_result:int=sim._nearest_enemy(e,radius)
			checks+=1
			if native_result!=script_result:failures.append("native nearest changed target in round %d, unit %d"%[round_index,e.id])
	for source in sim.entities.values():
		if int(source.id)%3==0:source.commands=[{"kind":"force_attack","target":-1}]
		elif int(source.id)%3==1:source.commands=[{"kind":"force_attack","target":7}]
		for target in sim.entities.keys().slice(0,40):
			for force in [false,true]:
				sim.native_kernels_enabled=true
				var native_result:bool=sim._weapon_can_target(source,target,force)
				sim.native_kernels_enabled=false
				var script_result:bool=sim._weapon_can_target(source,target,force)
				checks+=1
				if native_result!=script_result and failures.size()<10:failures.append("native weapon permissions changed")

	sim._in_step=false
	print("NATIVE_NEAREST ",JSON.stringify({"checks":checks,"failures":failures}))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
