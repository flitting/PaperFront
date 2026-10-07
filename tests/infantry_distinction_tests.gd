extends SceneTree
const Output="res://artifacts/infantry_distinction_20261007"
var checks:int=0
var failures:Array[String]=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label)
func _initialize()->void:
	var rules:Dictionary=RulesLoader.load_rules()
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/cards/paper_infantry_revision/distinct_roles_manifest.json"))
	var reader:=PaperWorld.new()
	reader.contours=JSON.parse_string(FileAccess.get_file_as_string("res://assets/cards/contours.json"))
	var silhouettes:Dictionary={}
	var silhouettes_far:Dictionary={}
	var roles:int=0
	var worst_same:Dictionary={"iou":0.0,"a":"","b":""}
	var worst_faction:Dictionary={"iou":0.0,"a":"","b":""}
	for faction:String in manifest.roles:
		for role:Dictionary in manifest.roles[faction]:
			roles+=1
			var spec:Dictionary=rules.units[role.id]
			check(not VolumeModels.supports(spec,"unit"),str(role.id)+" remains an original-direction paper card")
			check(is_equal_approx(float(spec.radius),.5) and int(spec.logical_size)==1,str(role.id)+" keeps logical 1x1 footprint")
			check(reader._dimensions(spec,"unit").is_equal_approx(Vector2(1.65,1.8)*.6),str(role.id)+" keeps visual 0.6 scaling")
			for pose:String in ["idle","move","combat","hit","death"]:
				for lod:int in range(3):
					var path:String="res://assets/cards/paper_infantry_revision/%s_%s_%d.svg"%[role.id,pose,lod]
					var img:=Image.new()
					check(img.load_svg_from_string(FileAccess.get_file_as_string(path))==OK,"rasterize "+path)
					if pose=="idle" and lod in [0,2]:
						img.resize(40,50,Image.INTERPOLATE_LANCZOS)
						var mask:PackedByteArray=[]
						for y in range(50):
							for x in range(40):mask.append(1 if img.get_pixel(x,y).a>.45 else 0)
						if lod==0:silhouettes[role.id]=mask
						else:silhouettes_far[role.id]=mask
				var action:String="attack" if pose=="combat" else pose
				var live_path:String=spec.animations[action]
				check(FileAccess.get_file_as_string(live_path)==FileAccess.get_file_as_string("res://assets/cards/paper_infantry_revision/%s_%s_0.svg"%[role.id,pose]),"live animation matches authored role "+str(role.id)+" "+action)
				var mesh:ArrayMesh=reader._card(str(role.id)+"_"+action,.99,1.08,live_path,0)
				check(mesh.get_surface_count()==3,"front, back and physical paper edge "+str(role.id)+" "+action)
				check(absf(mesh.get_aabb().size.z-.045)<.0001,"original card thickness "+str(role.id)+" "+action)
			check(FileAccess.get_file_as_string(spec.portrait)==FileAccess.get_file_as_string(spec.animations.idle),str(role.id)+" production portrait matches actual idle soldier")
			check(iou(silhouettes[role.id],silhouettes_far[role.id])>.88,str(role.id)+" retains silhouette at far LOD")
		for i in range(manifest.roles[faction].size()):
			for j in range(i+1,manifest.roles[faction].size()):
				var a:String=manifest.roles[faction][i].id
				var b:String=manifest.roles[faction][j].id
				var similarity:float=iou(silhouettes_far[a],silhouettes_far[b])
				if similarity>worst_same.iou:worst_same={"iou":similarity,"a":a,"b":b}
				check(similarity<.90,"far-detail role silhouettes differ: "+a+" / "+b)
	for art:String in ["rifle","anti","engineer"]:
		var factions:Array=["rivet","kestrel","iron","sky"]
		for i in range(4):
			for j in range(i+1,4):
				var a:String=factions[i]+"_"+art
				var b:String=factions[j]+"_"+art
				var similarity:float=iou(silhouettes_far[a],silhouettes_far[b])
				if similarity>worst_faction.iou:worst_faction={"iou":similarity,"a":a,"b":b}
				check(similarity<.90,"same-role faction silhouettes differ: "+a+" / "+b)
	check(roles==22,"all 22 real infantry types are covered")
	var result:Dictionary={"checks":checks,"failures":failures,"roles":roles,"same_faction_max_iou":worst_same,"same_role_max_iou":worst_faction}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Output))
	FileAccess.open(Output+"/checks.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("INFANTRY_DISTINCTION ",JSON.stringify(result))
	reader.free()
	for failure:String in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
func iou(a:PackedByteArray,b:PackedByteArray)->float:
	var both:int=0
	var either:int=0
	for i in range(a.size()):
		if a[i] or b[i]:either+=1
		if a[i] and b[i]:both+=1
	return float(both)/maxf(1,either)
