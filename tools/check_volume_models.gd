extends SceneTree

var failures: Array[String]=[]
var checked: int=0
var surfaces: int=0
var muzzle_cases: int=0
var recoil_cases: int=0
var deleted_sources: int=0
var vertices: int=0
var triangles_by_kind: Dictionary={"building":0,"unit":0}
var model_costs: Dictionary={}
var capture: bool=false
var scene: Node3D

func _initialize() -> void:
	capture="--capture" in OS.get_cmdline_user_args()
	call_deferred("run")

func run() -> void:
	var rules: Dictionary=RulesLoader.load_rules()
	scene=Node3D.new()
	root.add_child(scene)
	for kind in ["building","unit"]:
		var source: Dictionary=rules.buildings if kind=="building" else rules.units
		for spec in source.values():
			if not VolumeModels.supports(spec,kind):continue
			var team: int=0 if spec.faction=="rivet" else 1
			var model: Dictionary=VolumeModels.create_model(spec,kind,team)
			var model_triangles: Array[int]=[]
			scene.add_child(model.root)
			model.root.position=Vector3((checked%5)*5.0-10.0,0,float(checked/5)*5.0-7.5)
			for graphic in model.meshes:
				var bounds: AABB=graphic.mesh.get_aabb()
				if bounds.size.x<.1 or bounds.size.y<.1 or bounds.size.z<.1:failures.append(spec.name+": collapsed volume")
				if graphic.cast_shadow!=GeometryInstance3D.SHADOW_CASTING_SETTING_ON:failures.append(spec.name+": shadows disabled")
				if bool(model.get("direct_skinned",false)):
					# Generic recipes clone ArrayMesh data even at scale 1. Direct
					# skins submit the actual imported GLB mesh from the hand author.
					var recipe:Dictionary=load("res://scripts/creator_hand_models.gd").recipe_meta(team)
					if model.meshes.size()!=1 or graphic!=model.skinned_mesh or graphic.mesh!=recipe.body_mesh:failures.append(spec.name+": original continuous skin mesh not retained")
					if graphic.mesh.get_surface_count()<1 or graphic.mesh.get_surface_count()!=recipe.body_mesh.get_surface_count():failures.append(spec.name+": original skin/nail surfaces not retained")
					if graphic.skin==null or graphic.skin.get_bind_count()!=16 or model.skeleton.get_bone_count()!=16:failures.append(spec.name+": original sixteen skin bindings not retained")
				elif graphic.mesh.get_surface_count()!=1:failures.append(spec.name+": unnecessary surfaces")
				surfaces+=graphic.mesh.get_surface_count()
				var mesh_triangles:int=0
				for surface in range(graphic.mesh.get_surface_count()):
					var arrays:Array=graphic.mesh.surface_get_arrays(surface)
					vertices+=arrays[Mesh.ARRAY_VERTEX].size()
					var indices:Variant=arrays[Mesh.ARRAY_INDEX]
					mesh_triangles+=(indices.size() if indices!=null and not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size())/3
					if arrays[Mesh.ARRAY_NORMAL].size()!=arrays[Mesh.ARRAY_VERTEX].size():failures.append(spec.name+": missing light normals surface "+str(surface))
					for normal in arrays[Mesh.ARRAY_NORMAL]:
						if not normal.is_finite():failures.append(spec.name+": nonfinite normal surface "+str(surface))
					for vertex in arrays[Mesh.ARRAY_VERTEX]:
						if not vertex.is_finite():failures.append(spec.name+": nonfinite vertex surface "+str(surface))
				model_triangles.append(mesh_triangles)
				triangles_by_kind[kind]+=mesh_triangles
			if model.turret!=null:
				var old_body: Transform3D=model.body.transform
				var resting_muzzle: Vector3=VolumeModels.muzzle_world(model)-model.turret.global_position
				model.turret.rotation.y=-PI*.5
				var muzzle: Vector3=VolumeModels.muzzle_world(model)-model.turret.global_position
				# Twin launchers can have a lateral muzzle offset. Rotation must
				# preserve that authored offset instead of moving it onto the axis.
				if not muzzle.is_equal_approx(Basis(Vector3.UP,-PI*.5)*resting_muzzle):failures.append(spec.name+": muzzle/turret rotation mismatch")
				if model.body.transform!=old_body:failures.append(spec.name+": turret moved hull")
				for body_heading in [0,79,80,81,135,180,-90]:
					for turret_heading in [-135,0,90,180]:
						model.root.rotation.y=-deg_to_rad(body_heading)
						model.turret.rotation.y=-deg_to_rad(turret_heading-body_heading)
						var actual: Vector3=VolumeModels.muzzle_world(model)-model.root.global_position
						var restored: Vector3=VolumeModels.muzzle_offset(spec,kind,team,body_heading,turret_heading)
						if actual.distance_to(restored)>.0001:failures.append(spec.name+": snapshot muzzle offset differs")
						muzzle_cases+=1
				model.root.rotation.y=0
				model.turret.rotation.y=0
				var muzzle_at_rest: Vector3=VolumeModels.muzzle_world(model)
				var recoil_distance: float=model.recoil_distance
				VolumeModels.update_model(model,{"state":"idle","attack_flash":.25,"hit_flash":0,"id":1},.1)
				var muzzle_after_recoil: Vector3=VolumeModels.muzzle_world(model)
				if absf((muzzle_after_recoil-muzzle_at_rest).x+recoil_distance)>.0001:failures.append(spec.name+": muzzle failed to recoil with gun")
				var restored_recoil: Vector3=VolumeModels.muzzle_offset(spec,kind,team,0,0,-recoil_distance)
				if (muzzle_after_recoil-model.root.global_position).distance_to(restored_recoil)>.0001:failures.append(spec.name+": restored recoil point differs")
				VolumeModels.update_model(model,{"state":"idle","attack_flash":0,"hit_flash":0,"id":1},.1)
				if VolumeModels.muzzle_world(model).distance_to(muzzle_at_rest)>.0001:failures.append(spec.name+": gun did not return to rest")
				recoil_cases+=1
			var cached: Dictionary=VolumeModels.create_model(spec,kind,team)
			if cached.meshes[0].mesh!=model.meshes[0].mesh:failures.append(spec.name+": mesh cache missed")
			cached.root.free()
			if model.turret!=null:
				# Capture a launch point, remove the source, reconstruct from immutable
				# spec and saved absolute headings without access to any source node.
				var disposable: Dictionary=VolumeModels.create_model(spec,kind,team)
				scene.add_child(disposable.root)
				disposable.root.position=Vector3(13,2,-7)
				disposable.root.rotation.y=-deg_to_rad(135)
				disposable.turret.rotation.y=-deg_to_rad(81-135)
				var launch: Vector3=VolumeModels.muzzle_world(disposable)
				disposable.root.free()
				var reconstructed: Vector3=Vector3(13,2,-7)+VolumeModels.muzzle_offset(spec,kind,team,135,81)
				if launch.distance_to(reconstructed)>.0001:failures.append(spec.name+": source death changed projectile launch point")
				deleted_sources+=1
			var expected_scale: float=VolumeModels.bake_scale(spec,kind)
			if not is_equal_approx(float(model.model_scale),expected_scale):failures.append(spec.name+": unexpected baked scale")
			if kind=="unit" and spec.art=="tank":
				var chassis_width: float=model.meshes[0].mesh.get_aabb().size.z
				if chassis_width>float(spec.radius)*2.4:failures.append(spec.name+": tank chassis exceeds its formation gap ("+str(chassis_width)+")")
			if model.root.scale!=Vector3.ONE:failures.append(spec.name+": model uses runtime root scale")
			if model.dimensions.x<=.1 or model.dimensions.y<=.1 or model.dimensions.z<=.1:failures.append(spec.name+": invalid model dimensions")

			model_costs[str(spec.faction)+"_"+str(spec.art)]=model_triangles
			checked+=1
	print("VOLUME_CHECK ",JSON.stringify({"models":checked,"surfaces":surfaces,"vertices":vertices,"triangles":int(triangles_by_kind.building)+int(triangles_by_kind.unit),"triangles_by_kind":triangles_by_kind,"model_costs":model_costs,"muzzle_cases":muzzle_cases,"recoil_cases":recoil_cases,"deleted_sources":deleted_sources,"failures":failures}))
	if not capture:
		scene.queue_free()
		await process_frame
		quit(0 if failures.is_empty() else 1)
		return
	root.size=Vector2i(1600,1100)
	var floor_mesh:=BoxMesh.new()
	floor_mesh.size=Vector3(28,.18,25)
	var floor_instance:=MeshInstance3D.new()
	floor_instance.mesh=floor_mesh
	floor_instance.position=Vector3(0,-.1,0)
	var material:=StandardMaterial3D.new()
	material.albedo_color=Color("cdb78d")
	material.roughness=1.0
	floor_instance.material_override=material
	scene.add_child(floor_instance)
	var camera:=Camera3D.new()
	scene.add_child(camera)
	camera.current=true
	camera.fov=40
	camera.position=Vector3(22,23,29)
	camera.look_at(Vector3(0,1,0))
	var light:=DirectionalLight3D.new()
	scene.add_child(light)
	light.rotation_degrees=Vector3(-52,-35,0)
	light.light_energy=.9
	light.shadow_enabled=true
	var environment:=WorldEnvironment.new()
	scene.add_child(environment)
	environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color("4c3c2d")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color("eedfc2")
	environment.environment.ambient_light_energy=.55
	for frame in range(20):await process_frame
	await RenderingServer.frame_post_draw
	var error: int=root.get_texture().get_image().save_png("/tmp/volume_models_gallery.png")
	print("VOLUME_GALLERY /tmp/volume_models_gallery.png ",error)
	quit(0 if failures.is_empty() else 1)
