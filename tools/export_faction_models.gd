extends SceneTree

## Deliver individually loadable paper models, preserving articulated node paths.
func _initialize() -> void:
	call_deferred("run")

func assign_owner(node: Node, owner_root: Node) -> void:
	for child in node.get_children():
		child.owner=owner_root
		assign_owner(child,owner_root)

func run() -> void:
	var rules: Dictionary=RulesLoader.load_rules()
	var output: String="res://artifacts/faction_models"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var index: Dictionary={"version":1,"source":"docs/派系设定/paper_front_world_setting_four_factions.md","team":0,"player_color":"e7ad42","assets":[],"paper_infantry":[]}
	var failures: Array[String]=[]
	for kind in ["building","unit"]:
		var source: Dictionary=rules.buildings if kind=="building" else rules.units
		for id in source:
			var spec: Dictionary=source[id]
			if kind=="unit" and spec.art in VolumeModels.INFANTRY_ART:
				var old_path: String=output+"/"+id+".tscn"
				if FileAccess.file_exists(old_path):DirAccess.remove_absolute(ProjectSettings.globalize_path(old_path))
				index.paper_infantry.append({"id":id,"name":spec.name,"faction":spec.faction,"representation":"paper_card","states":["idle","move","attack","hit","death"],"card_prefix":"res://assets/cards/"+spec.faction+"_"+spec.art,"player_mask_suffix":"_identity.svg"})
				continue
			var model: Dictionary=VolumeModels.create_model(spec,kind,0)
			if model.is_empty():
				failures.append(id+": no model")
				continue
			var node: Node3D=model.root
			node.name=id
			node.set_meta("spec_id",id)
			node.set_meta("kind",kind)
			node.set_meta("faction",spec.faction)
			node.set_meta("team",0)
			node.set_meta("faction_color",model.faction_color)
			node.set_meta("player_color",model.player_color)
			node.set_meta("emblem",model.emblem)
			node.set_meta("domain",spec.get("domain","ground"))
			node.set_meta("flight_height",spec.get("flight_height",0.0))
			node.set_meta("dimensions",model.dimensions)
			assign_owner(node,node)
			var scene:=PackedScene.new()
			var path: String=output+"/"+id+".tscn"
			if scene.pack(node)!=OK or ResourceSaver.save(scene,path)!=OK:
				failures.append(id+": export failed")
			else:
				var restored: Node3D=load(path).instantiate()
				if not restored.has_node("Body") or restored.get_meta("spec_id","")!=id:
					failures.append(id+": reloaded scene lost body or identity")
				if model.turret!=null and not restored.has_node("Turret"):
					failures.append(id+": reloaded scene lost independent turret")
				index.assets.append({"id":id,"name":spec.name,"kind":kind,"faction":spec.faction,"path":path,"domain":spec.get("domain","ground"),"height":model.height,"body":"Body","turret":"Turret" if model.turret!=null else "","emblem":model.emblem})
				restored.free()
			node.free()
	var file:=FileAccess.open(output+"/index.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(index,"\t"))
	file.close()
	print("FACTION_MODELS_EXPORT ",JSON.stringify({"models":index.assets.size(),"paper_infantry":index.paper_infantry.size(),"directory":ProjectSettings.globalize_path(output),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
