extends SceneTree
const V=preload("res://scripts/volume_models.gd")
const Hand=preload("res://scripts/creator_hand_models.gd")
var failures:Array[String]=[]
var checks:=0
var evidence:Array=[]
var card_source_sha256:Dictionary={}
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label)
func fraction_below(values:PackedVector2Array,i:int,cut:float)->float:
	var p:Array=[Vector3(0,0,values[i].y),Vector3(1,0,values[i+1].y),Vector3(0,1,values[i+2].y)]
	var out:Array=[]
	for k in range(3):
		var a:Vector3=p[k];var b:Vector3=p[(k+1)%3]
		if a.z<=cut:out.append(a)
		if (a.z<=cut)!=(b.z<=cut):out.append(a.lerp(b,(cut-a.z)/(b.z-a.z)))
	var area:=0.0
	for k in range(1,out.size()-1):
		var a:Vector2=Vector2(out[k].x-out[0].x,out[k].y-out[0].y)
		var b:Vector2=Vector2(out[k+1].x-out[0].x,out[k+1].y-out[0].y)
		area+=absf(a.cross(b))
	return area
func coverage(mesh:Mesh)->Vector3:
	var result:=Vector3.ZERO
	for surface in range(mesh.get_surface_count()):
		var a:Array=mesh.surface_get_arrays(surface)
		var vertices:PackedVector3Array=a[Mesh.ARRAY_VERTEX]
		var uv:PackedVector2Array=a[Mesh.ARRAY_TEX_UV2] if a[Mesh.ARRAY_TEX_UV2]!=null else PackedVector2Array()
		for i in range(0,vertices.size(),3):
			var area:float=(vertices[i+1]-vertices[i]).cross(vertices[i+2]-vertices[i]).length()*.5
			if uv.is_empty() or uv[i].x<=0:continue
			result.z+=area
			var owner:float=fraction_below(uv,i,uv[i].x)-fraction_below(uv,i,-uv[i].x)
			var paper:float=fraction_below(uv,i,.45)-fraction_below(uv,i,.40)+fraction_below(uv,i,-.40)-fraction_below(uv,i,-.45)
			result.x+=area*owner;result.y+=area*(1.0-paper-owner)
	return result
func run()->void:
	var rules:Dictionary=RulesLoader.load_rules()
	if rules.is_empty():
		print("RULE_ERRORS ",RulesLoader.errors);quit(1);return
	var signatures:Dictionary={}
	var world:=PaperWorld.new()
	for id in rules.units:
		var spec:Dictionary=rules.units[id]
		if not str(spec.art) in V.INFANTRY_ART:continue
		check(not V.supports(spec,"unit"),id+" uses original contour-card renderer")
		check(world._dimensions(spec,"unit").is_equal_approx(Vector2(.99,1.08)),id+" is original visual dimensions times .6")
		var path:String=world._texture_path(spec,"idle")
		var hash:String=FileAccess.get_file_as_string(path).sha256_text()
		check(not signatures.has(hash),id+" has independent original illustration")
		signatures[hash]=id
		for state in ["idle","move","attack","hit","death"]:
			var texture_path:String=world._texture_path(spec,state)
			card_source_sha256[texture_path]=FileAccess.get_file_as_string(texture_path).sha256_text()
			card_source_sha256[texture_path.get_basename()+"_identity.svg"]=FileAccess.get_file_as_string(texture_path.get_basename()+"_identity.svg").sha256_text()
			var tex:Texture2D=load(texture_path)
			var mask:Texture2D=load(texture_path.get_basename()+"_identity.svg")
			check(tex!=null and mask!=null,id+" original "+state+" illustration and identity map exist")
			var pixels:Image=tex.get_image();var identity:Image=mask.get_image()
			var total:=0.0;var owner:=0.0;var fixed_pixels:=0.0
			var faction_color:Color=Color(rules.factions[V.art_faction(spec)].color)
			for y in pixels.get_height():
				for x in pixels.get_width():
					if pixels.get_pixel(x,y).a<.5:continue
					total+=1
					var color:Color=identity.get_pixel(x,y)
					owner+=color.r*color.a
					var original:Color=pixels.get_pixel(x,y)
					if Vector3(original.r-faction_color.r,original.g-faction_color.g,original.b-faction_color.b).length()<.08:fixed_pixels+=1.0-color.r*color.a
			var ratio:float=owner/maxf(1,total)
			evidence.append({"id":id,"state":state,"owner_pixels":ratio,"fixed_faction_pixels":fixed_pixels/maxf(1,total),"fixed_minus_owner":fixed_pixels/maxf(1,total)-ratio})
			check(ratio>=0 and ratio<=.12,id+" "+state+" owner is restricted to small insignia: "+str(ratio))
			check(FileAccess.get_file_as_string(texture_path).contains("stroke="),id+" retains original ink linework")
	world.free()
	V.configure_player_colors(["#337ddd","#e94b40"])
	for faction in ["kestrel","rivet","iron","sky"]:
		for art in ["tank","heavy_tank","fighter"]:
			var spec:Dictionary=rules.units[faction+"_"+art]
			var recipe:Dictionary=V._recipe(spec,"unit",0)
			check(is_equal_approx(maxf(recipe.dimensions.x,recipe.dimensions.z),float(spec.get("logical_size",1))*.96),faction+" "+art+" uses logical footprint for visual scale")
			for tier in range(3):
				var raw:Dictionary=V._raw_recipe(spec,"unit",0,tier)
				var area:=Vector3.ZERO
				for field in ["body_mesh","turret_mesh"]:
					if raw.has(field):area+=coverage(raw[field])
				for part in raw.get("parts",[]):area+=coverage(part.mesh)
				evidence.append({"id":faction+"_"+art,"tier":tier,"central_repaint_area":area.z})
				check(is_zero_approx(area.z),faction+" "+art+" preserves authored colors without central recoloring at tier "+str(tier))
	var hand:Dictionary=V.create_model(rules.units.sky_creator_hand,"unit",0)
	for ratio:float in Hand.owner_area_evidence.surface_and_tabletop_owner_area:
		check(ratio>0 and ratio<=.065,"creator hand small wrist mark: "+str(ratio))
	hand.root.free()
	await process_frame
	var report:=FileAccess.open("res://artifacts/latest_faction_revision/appearance_checks.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"evidence":evidence,"card_source_sha256":card_source_sha256},"  "));report.close()
	print("LATEST_APPEARANCE ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
