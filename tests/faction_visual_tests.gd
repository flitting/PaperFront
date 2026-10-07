extends SceneTree

var failures: Array[String]=[]
var checks: int=0
const SILHOUETTES = preload("res://tests/faction_silhouette_probe.gd")

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks+=1
	if not value:failures.append(message)

func run() -> void:
	var rules: Dictionary=RulesLoader.load_rules()
	var scene:=Node3D.new()
	root.add_child(scene)
	var total: int=0
	for kind in ["building","unit"]:
		var source: Dictionary=rules.buildings if kind=="building" else rules.units
		for id in source:
			var spec: Dictionary=source[id]
			if kind == "unit" and spec.art in VolumeModels.INFANTRY_ART:
				expect(not VolumeModels.supports(spec,kind),id+": infantry must use the original paper card")
				expect(VolumeModels.create_model(spec,kind,0).is_empty(),id+": solid infantry model still active")
				continue
			var a: Dictionary=VolumeModels.create_model(spec,kind,0)
			var b: Dictionary=VolumeModels.create_model(spec,kind,1)
			expect(not a.is_empty() and not b.is_empty(),id+": no solid model")
			if a.is_empty() or b.is_empty():continue
			scene.add_child(a.root)
			scene.add_child(b.root)
			if bool(a.get("direct_skinned",false)):
				expect(bool(b.get("direct_skinned",false)) and spec.art=="creator_hand",id+": continuous skin is retained for both owners")
				expect(a.faction==spec.faction and b.faction==spec.faction and a.team==0 and b.team==1,id+": skin preserves faction and distinct owner identity")
				expect(a.meshes.size()==1 and b.meshes.size()==1 and a.meshes[0]==a.skinned_mesh and b.meshes[0]==b.skinned_mesh,id+": each owner submits exactly one original continuous skin")
				expect(a.skinned_mesh.mesh==b.skinned_mesh.mesh,id+": owners share the original anatomical geometry")
				expect(a.skinned_mesh.skin!=null and b.skinned_mesh.skin!=null and a.skinned_mesh.skin.get_bind_count()==16 and b.skinned_mesh.skin.get_bind_count()==16,id+": both skins retain all sixteen bindings")
				expect(a.skeleton!=b.skeleton and a.skeleton.get_bone_count()==16 and b.skeleton.get_bone_count()==16 and a.skinned_mesh.get_node_or_null(a.skinned_mesh.skeleton)==a.skeleton and b.skinned_mesh.get_node_or_null(b.skinned_mesh.skeleton)==b.skeleton,id+": both owners retain independent bound skeletons")
				a.root.free()
				b.root.free()
				total+=1
				continue
			var faction_paint: Color={"rivet":Color("bb4034"),"kestrel":Color("2865a5"),"iron":Color("bb963e"),"sky":Color("67578b")}[spec.faction]
			expect(a.faction_color==faction_paint and b.faction_color==faction_paint,id+": faction paint follows player")
			expect(a.player_color!=b.player_color,id+": player colors identical")
			expect(a.emblem=={"rivet":"hammer","kestrel":"wing","iron":"repair_triangle","sky":"star_wing"}[spec.faction],id+": wrong faction emblem")
			var painted_a: int=0
			var painted_b: int=0
			var faction_a: int=0
			var faction_b: int=0
			for i in range(a.meshes.size()):
				var aa: Array=a.meshes[i].mesh.surface_get_arrays(0)
				var bb: Array=b.meshes[i].mesh.surface_get_arrays(0)
				expect(aa[Mesh.ARRAY_VERTEX]==bb[Mesh.ARRAY_VERTEX],id+": player changed model silhouette")
				var positions: PackedVector3Array=aa[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array=aa[Mesh.ARRAY_NORMAL]
				var colors_a: PackedColorArray=aa[Mesh.ARRAY_COLOR]
				var colors_b: PackedColorArray=bb[Mesh.ARRAY_COLOR]
				var top_paint: bool=false
				var side_paint: bool=false
				for j in range(colors_a.size()):
					if colors_a[j].is_equal_approx(a.player_color):
						painted_a+=1
						if normals[j].y>.7:top_paint=true
						if absf(normals[j].z)>.7:side_paint=true
					if colors_b[j].is_equal_approx(b.player_color):painted_b+=1
					if colors_a[j].is_equal_approx(faction_paint):faction_a+=1
					if colors_b[j].is_equal_approx(faction_paint):faction_b+=1
				if i==0:
					expect(top_paint or spec.art in ["tank","assault"],id+": no top identification plate")
					expect(side_paint,id+": no side identification plate")
				expect(positions.size()>0,id+": empty body")
			expect(painted_a>=12 and painted_b>=12,id+": missing independent player identification paint")
			expect(faction_a==faction_b,id+": team tint changed fixed faction paint coverage")
			if kind=="unit" and spec.get("domain","ground")=="air":
				expect(a.aircraft,id+": aircraft rendered as ground vehicle")
				expect(a.dimensions.z>2.0 and a.dimensions.y>.5,id+": aircraft wing volume missing")
				if not str(spec.get("weapon","")).is_empty():expect(a.muzzle!=null,id+": armed aircraft firing point missing")
			a.root.free()
			b.root.free()
			total+=1
	var configured_paper:int=rules.units.values().filter(func(spec):return spec.art in ["rifle","anti","engineer","demolition"]).size()
	expect(total==rules.units.size()+rules.buildings.size()-configured_paper,"all configured vehicle and building models must remain solid")
	var comparisons: Array[Dictionary] = SILHOUETTES.new().run(scene,rules)
	expect(comparisons.size()==22,"all remaining corresponding solid and paper roles must have silhouette comparisons after merging Rivet bases")
	for comparison in comparisons:
		expect(comparison["pass"],"Faction geometry too similar: "+str(comparison.key)+" silhouette="+str(comparison.get("silhouette_mean",0.0))+" gray="+str(comparison.get("gray_mean",0.0)))
	# Actual renderer keeps aircraft in the sky while marks stay on the ground.
	var sim:=WarSimulation.new()
	sim.setup(rules,"dev",73026,"kestrel",false)
	var camera:=Camera3D.new()
	root.add_child(camera)
	camera.position=Vector3(24,30,52)
	camera.look_at(Vector3(24,0,24))
	var world:=PaperWorld.new()
	root.add_child(world)
	world.setup(sim,camera)
	var paper_count: int = check_paper_infantry(world,sim,rules)
	var plane_id: int=sim.debug_spawn(0,"kestrel_fighter",Vector2(14,25))
	var plane: Dictionary=sim.entities[plane_id]
	plane.flight_height=4.2
	plane.airborne=true
	world.sync(.1,[plane_id])
	var model: Dictionary=world.models[plane_id]
	var ground: float=MapData.height_at(sim.map,plane.pos)
	expect(absf(model.art_root.global_position.y-ground-4.2)<.001,"aircraft not at flight height")
	expect(model.hp_root.global_position.y>ground+4.2,"aircraft health bar stayed on ground")
	expect(absf(model.ring.global_position.y-ground-.045)<.001,"aircraft selection ring floated")
	expect(absf(model.shadow.global_position.y-ground-.025)<.001,"aircraft shadow floated")
	plane.flight_height=.35
	plane.airborne=false
	world.sync(.1,[plane_id])
	expect(absf(model.art_root.global_position.y-ground-.35)<.001,"stationary aircraft altitude not updated")
	# Ballistic endpoints retain source and target flight heights even when the
	# source aircraft is destroyed; rendered coordinates use immutable launch data.
	var start:=Vector2(14,25)
	var landing:=Vector2(19,27)
	var flight_spec: Dictionary=rules.units.kestrel_fighter
	var muzzle: Vector3=VolumeModels.muzzle_offset(flight_spec,"unit",0,0,0)
	sim.projectiles=[{"start":start,"landing":landing,"elapsed":0.0,"duration":1.0,"source_height":4.2,"target_height":5.1,"spec":"kestrel_fighter","heading":0.0,"body_heading":0.0,"team":0}]
	world._sync_projectiles()
	expect(world.shells[0].position.distance_to(Vector3(start.x,MapData.height_at(sim.map,start)+4.2,start.y)+muzzle)<.001,"air projectile source lost flight height")
	sim.entities.erase(plane_id)
	world._sync_projectiles()
	expect(world.shells[0].position.distance_to(Vector3(start.x,MapData.height_at(sim.map,start)+4.2,start.y)+muzzle)<.001,"source death moved projectile launch point")
	sim.projectiles[0].elapsed=1.0
	world._sync_projectiles()
	expect(absf(world.shells[0].position.y-MapData.height_at(sim.map,landing)-5.1)<.001,"air projectile impact stayed on ground")
	world.effects.clear()
	world._spawn_effect(landing,"impact",1.0,5.1)
	var air_shock: bool=false
	for effect in world.effects:
		if effect.kind=="shock" or effect.kind=="scorch":air_shock=true
	expect(not air_shock,"airburst created a ground shock/scorch")
	# Exercise both actual power-station steam ports through the field renderer,
	# rather than only creating their static geometry in the model gallery.
	for team in range(2):
		var power_id: int=sim.debug_spawn(team,("kestrel" if team==0 else "rivet")+"_power",Vector2(24.5+team*5,24.5))
		world.sync(.1,[])
		var before_steam:=0
		for batch in world.batches.values():
			if batch.multi.mesh==world.smoke_mesh:before_steam+=world._batch_count(batch)
		world._industrial_smoke(world.models[power_id],sim.entities[power_id])
		var after_steam:=0
		for batch in world.batches.values():
			if batch.multi.mesh==world.smoke_mesh:after_steam+=world._batch_count(batch)
		expect(after_steam>before_steam,"Faction power station failed to render steam: "+str(team))
	print("FACTION_VISUAL ",JSON.stringify({"solid_models":total,"paper_infantry":paper_count,"checks":checks,"failures":failures}))
	world.queue_free()
	camera.queue_free()
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)


func check_paper_infantry(world: PaperWorld, sim: WarSimulation, rules: Dictionary) -> int:
	var papers: int = 0
	for spec_id in rules.units:
		var spec: Dictionary = rules.units[spec_id]
		if spec.art not in VolumeModels.INFANTRY_ART: continue
		papers += 1
		var pair: Array = []
		for team in [0,1]: pair.append(sim.debug_spawn(team,spec_id,Vector2(14,25)))
		world.sync(0.0,pair)
		var a: Dictionary = world.models[pair[0]]
		var b: Dictionary = world.models[pair[1]]
		expect(not a.volumetric and not b.volumetric,spec_id+": infantry did not restore thin paper rendering")
		expect(a.graphic.mesh.get_aabb().size.z <= 0.066 and a.graphic.mesh.get_aabb().size.z > 0.04,spec_id+": paper edge thickness changed")
		for state in ["idle","move","attack","hit","death"]:
			var texture_path: String = str(spec.animations[state])
			var mask_path: String = texture_path.get_basename()+"_identity.svg"
			check_identification_mask(texture_path,mask_path,str(spec.faction))
			var ma: ArrayMesh = world._card(spec.faction+"_"+spec.art+"_"+state,a.dimensions.x,a.dimensions.y,texture_path,0)
			var mb: ArrayMesh = world._card(spec.faction+"_"+spec.art+"_"+state,b.dimensions.x,b.dimensions.y,texture_path,1)
			expect(ma != mb,spec_id+" "+state+": player cache reused a material from the other team")
			expect(ma.get_surface_count()==3 and mb.get_surface_count()==3,spec_id+" "+state+": paper lost front, cut edge or back")
			for surface in range(3):
				var aa: Array = ma.surface_get_arrays(surface)
				var bb: Array = mb.surface_get_arrays(surface)
				expect(aa[Mesh.ARRAY_VERTEX]==bb[Mesh.ARRAY_VERTEX] and aa[Mesh.ARRAY_TEX_UV]==bb[Mesh.ARRAY_TEX_UV],spec_id+" "+state+": player changed cut silhouette or UV")
			for surface in [0,2]:
				for team in [0,1]:
					var material: ShaderMaterial = (ma if team == 0 else mb).surface_get_material(surface)
					expect(material != null,spec_id+" "+state+": paper face has no illustration shader")
					if material == null: continue
					var identity: Texture2D = material.get_shader_parameter("identity_mask")
					var picture: Texture2D = material.get_shader_parameter("illustration")
					expect(identity != null and identity.resource_path==mask_path,spec_id+" "+state+": wrong identity mask")
					expect(picture != null and picture.resource_path==texture_path,spec_id+" "+state+": source illustration changed")
					expect(float(material.get_shader_parameter("identity_enabled"))==1.0,spec_id+" "+state+": player mask is disabled")
					expect(material.get_shader_parameter("player_color")==PaperWorld.TEAM_COLORS[team],spec_id+" "+state+": wrong player identification uniform")
			expect(ma.surface_get_material(1)==mb.surface_get_material(1),spec_id+" "+state+": cut edge was tinted by player")
			if state == "death": continue
			for id in pair:
				var e: Dictionary = sim.entities[id]
				e.state = state if state != "hit" else "idle"
				e.attack_flash = 0.2 if state == "attack" else 0.0
				e.hit_flash = 0.2 if state == "hit" else 0.0
			world.sync(0.12,pair)
			expect(a.state==state and b.state==state,spec_id+": live paper pose failed: "+state)
			if state == "move":
				expect(absf(a.art_root.rotation.z)>0.0001 and a.art_root.position.y>0.0,spec_id+": moving paper lacks its original sway and bob")
			if state == "attack": expect(a.art_root.position.x<0.0,spec_id+": paper attack recoil disappeared")
		for id in pair:
			sim.entities[id].state = "idle"
			sim.entities[id].attack_flash = 0.0
			sim.entities[id].hit_flash = 0.0
		for alpha in [-180,-81,-80,0,80,81,180]:
			for id in pair: sim.entities[id].alpha = float(alpha)
			world.sync(0.0,pair)
			for model in [a,b]:
				expect(bool(model.root.get_meta("mirrored"))==(absf(float(alpha))>80.0),spec_id+": paper mirror boundary at "+str(alpha))
				var depicted: Vector3 = model.root.basis*model.art_root.basis*Vector3.RIGHT
				var heading := Vector3(cos(deg_to_rad(float(alpha))),0,sin(deg_to_rad(float(alpha))))
				expect(depicted.normalized().dot(heading)>.999,spec_id+": paper muzzle reversed after mirror at "+str(alpha))
				expect(is_zero_approx(model.hp_root.rotation.y),spec_id+": paper health bar left its card plane")
		var before: Transform3D = a.root.transform
		var previous_camera: Transform3D = world.camera.transform
		world.camera.position=Vector3(52,30,24)
		world.camera.look_at(Vector3(24,0,24))
		world.sync(0.0,pair)
		expect(a.root.transform.is_equal_approx(before),spec_id+": orbit camera rotated the paper unit in world coordinates")
		world.camera.transform = previous_camera
		for id in pair: sim.entities.erase(id)
		world.sync(0.1,[])
		expect(world.ghosts.any(func(g): return g.model.root==a.root) and world.ghosts.any(func(g): return g.model.root==b.root),spec_id+": death did not retain falling paper")
		for team in [0,1]:
			var material: ShaderMaterial = (a if team == 0 else b).graphic.mesh.surface_get_material(0)
			var texture: Texture2D = material.get_shader_parameter("illustration")
			expect(texture.resource_path==str(spec.animations.death),spec_id+": death did not use the prone illustration")
			expect(material.get_shader_parameter("player_color")==PaperWorld.TEAM_COLORS[team],spec_id+": death lost player identification")
			expect(absf((a if team == 0 else b).art_root.rotation.x)>0.0,spec_id+": death paper did not start falling")
	var configured_paper:int=rules.units.values().filter(func(spec):return spec.art in ["rifle","anti","engineer","demolition"]).size()
	expect(papers==configured_paper,"all configured infantry types must remain paper cards")
	return papers

func check_identification_mask(texture_path: String,mask_path: String,faction: String) -> void:
	expect(FileAccess.file_exists(mask_path),"missing explicit paper identification mask: "+mask_path)
	if not FileAccess.file_exists(mask_path): return
	var picture_texture: Texture2D = load(texture_path)
	var mask_texture: Texture2D = load(mask_path)
	expect(picture_texture != null and mask_texture != null,"infantry textures failed to import: "+texture_path)
	if picture_texture == null or mask_texture == null: return
	var picture: Image = picture_texture.get_image()
	var mask: Image = mask_texture.get_image()
	expect(not picture.is_empty() and not mask.is_empty(),"imported infantry or mask pixels are empty: "+texture_path)
	expect(picture.get_size()==mask.get_size(),"identification mask changed illustration UV extent: "+mask_path)
	if picture.get_size()!=mask.get_size(): return
	var faction_color: Color = {"rivet":Color("bb4034"),"kestrel":Color("2865a5"),"iron":Color("bb963e"),"sky":Color("67578b")}[faction]
	var original_player := Color("e7ad42")
	var opaque: int = 0
	var identified: int = 0
	var fixed_paint: int = 0
	var masked_fixed: int = 0
	var outside_cut: int = 0
	var wrong_source: int = 0
	for y in range(picture.get_height()):
		for x in range(picture.get_width()):
			var source: Color = picture.get_pixel(x,y)
			var coverage: Color = mask.get_pixel(x,y)
			var amount: float = coverage.r*coverage.a
			if source.a>.95: opaque += 1
			if source.a>.95 and maxf(absf(source.r-faction_color.r),maxf(absf(source.g-faction_color.g),absf(source.b-faction_color.b)))<.015:
				fixed_paint += 1
				if amount>.1: masked_fixed += 1
			if amount>.95:
				identified += 1
				if source.a<.95: outside_cut += 1
				# A few original paper flecks can cross the paint; the explicit mask
				# still must overwhelmingly correspond to authored orange plates.
				if maxf(absf(source.r-original_player.r),maxf(absf(source.g-original_player.g),absf(source.b-original_player.b)))>.1: wrong_source += 1
	expect(identified>50 and float(identified)/maxi(1,opaque)<.35,"paper identity is missing or covers the whole soldier: "+texture_path)
	expect(fixed_paint>30 and masked_fixed==0,"paper player mask repainted fixed faction color: "+texture_path)
	expect(outside_cut==0,"paper identification mask escaped the cut: "+texture_path)
	expect(wrong_source<=maxi(4,roundi(identified*.04)),"paper identity mask replaced skin, equipment or ink: "+texture_path)
