extends SceneTree
## Fixed eight-team scene. Rendering-only ablations; never gameplay acceptance.
var trunk_shadow_records:Array[Dictionary]=[]
class SparseTrunkBuilder:
	extends "res://scripts/landscape.gd"
	func _ink_strip(_data:Dictionary,_start:Vector3,_end:Vector3,_normal:Vector3,_color:Color,_width:float)->void:
		pass
func _initialize()->void:call_deferred("run")
func run()->void:
	var game=load("res://main.tscn").instantiate()
	root.add_child(game)
	var probe=load("res://scripts/gameplay_performance.gd").new()
	game.add_child(probe)
	probe.setup(game,{"case":"stress","resolution":Vector2i(1920,1080),"quality":"performance"})
	game.set_process(false);game.set_physics_process(false);probe.set_process(false)
	game.resize_battlefield();game.world.sync(0.0,[])
	var output:String="res://artifacts/performance_640/resumed/render_layers"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	var census:Array=[]
	for child in game.world.landscape.find_children("*","GeometryInstance3D",true,false):
		var mesh:Mesh=child.multimesh.mesh if child is MultiMeshInstance3D else child.mesh if child is MeshInstance3D else null
		if mesh==null:continue
		var triangles:int=0
		for s in range(mesh.get_surface_count()):
			triangles+=(mesh.surface_get_array_index_len(s) if mesh.surface_get_array_index_len(s)>0 else mesh.surface_get_array_len(s))/3
		var count:int=child.multimesh.instance_count if child is MultiMeshInstance3D else 1
		census.append({"name":str(child.name),"triangles":triangles,"count":count,"total":triangles*count,"shadow":child.cast_shadow,"bounds":str(child.get_aabb())})
	FileAccess.open(output+"_census.json",FileAccess.WRITE).store_string(JSON.stringify(census,"\t"))
	var cases:Array[String]=["full","single_shadow","no_shadows"]
	var sample_frames:int=80
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cases="):cases.assign(arg.trim_prefix("--cases=").split(","))
		if arg.begins_with("--sample-frames="):sample_frames=maxi(80,int(arg.trim_prefix("--sample-frames=")))
	var report:Dictionary={"scope":"frozen render diagnostic; no simulation", "fixture_version":preload("res://scripts/performance_factions.gd").FIXTURE_VERSION, "samples":[]}
	var simple_trunk_shader:=Shader.new()
	simple_trunk_shader.code="""shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_back;
varying float top;
void vertex(){top=abs(NORMAL.y);}
void fragment(){
    vec3 pigment=COLOR.rgb*1.01*(1.0-(1.0-top)*0.035);
    ALBEDO=mix(pigment/12.92,pow((pigment+vec3(0.055))/1.055,vec3(2.4)),step(vec3(0.04045),pigment));
    ROUGHNESS=0.95; SPECULAR=0.0;
}
"""
	var simple_trunk_material:=ShaderMaterial.new()
	simple_trunk_material.shader=simple_trunk_shader
	var sparse_builder:=SparseTrunkBuilder.new()
	var sparse_data:Dictionary=sparse_builder._data()
	preload("res://scripts/pine_model.gd").trunk(sparse_builder,sparse_data,false)
	var sparse_trunk:ArrayMesh=sparse_builder._finish(sparse_data,"paper")
	sparse_builder.free()
	var original_far_trunk:ArrayMesh=game.world.landscape._prop_mesh("trunk_far")
	for mode in cases:
		if mode=="fused_trunk_shadows" and trunk_shadow_records.is_empty():
			for key in ["trunk","trunk_far"]:
				var mesh:ArrayMesh=game.world.landscape._prop_mesh(key)
				var arrays:Array=mesh.surface_get_arrays(0)
				var welded:=PackedVector3Array()
				var indices:=PackedInt32Array()
				var by_position:Dictionary={}
				for point:Vector3 in arrays[Mesh.ARRAY_VERTEX]:
					if not by_position.has(point):by_position[point]=welded.size();welded.append(point)
					indices.append(by_position[point])
				var shadow_arrays:Array=[]
				shadow_arrays.resize(Mesh.ARRAY_MAX)
				shadow_arrays[Mesh.ARRAY_VERTEX]=welded
				shadow_arrays[Mesh.ARRAY_INDEX]=indices
				var shadow:=ArrayMesh.new()
				shadow.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,shadow_arrays)
				trunk_shadow_records.append({"mesh":mesh,"original":mesh.shadow_mesh,"fused":shadow})
		for record in trunk_shadow_records:record.mesh.shadow_mesh=record.fused if mode=="fused_trunk_shadows" else record.original
		game.key_light.shadow_enabled=mode!="no_shadows"
		game.key_light.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL if mode=="single_shadow" else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		game.world.landscape.visible=mode!="no_landscape"
		game.environment.ssao_enabled=mode!="no_post"
		game.set_render_scale(.5 if mode=="half_pixels" else 1.0)
		for batch in game.world.batches.values():batch.node.visible=mode!="no_units" and game.world._batch_count(batch)>0
		for child in game.world.landscape.get_children():
			if str(child.name).begins_with("TrunkDistant_"):child.visible=mode!="no_trunks" and not game.world.landscape.full_trunk_ink
			if str(child.name).begins_with("TrunkFar_"):child.multimesh.mesh=sparse_trunk if mode=="trunk_no_ink" else original_far_trunk
			if str(child.name).begins_with("TrunkFar_"):child.material_override=simple_trunk_material if mode=="simple_far_trunks" else null
			if str(child.name).begins_with("PropBatch_tree_") or str(child.name).begins_with("TreeNearCaster_") or str(child.name).begins_with("TreeFarCaster_") or str(child.name).begins_with("TreeMidVisual_") or str(child.name).begins_with("TreeFarVisual_"):child.visible=mode!="no_foliage"
			if str(child.name).begins_with("DestructibleRuin_"):child.visible=mode!="no_ruins"
			if str(child.name).begins_with("PropBatch_trunk") or str(child.name).begins_with("TrunkFar_"):child.visible=mode!="no_trunks"
			if str(child.name).begins_with("Ground_") or str(child.name).begins_with("TerrainCaster_"):child.visible=mode!="no_ground"
			if "Bridge" in str(child.name):child.visible=mode!="no_bridge"
		for frame in range(sample_frames/2):await RenderingServer.frame_post_draw
		var values:Array[float]=[]
		var frame_times:Array[float]=[]
		var previous:int=Time.get_ticks_usec()
		for frame in range(sample_frames):
			await RenderingServer.frame_post_draw
			var now:int=Time.get_ticks_usec()
			frame_times.append((now-previous)/1000.0);previous=now
			values.append(RenderingServer.viewport_get_measured_render_time_gpu(game.battlefield_viewport.get_viewport_rid()))
		values.sort();frame_times.sort()
		var row:Dictionary={"mode":mode,"sample_frames":sample_frames,"gpu_median_ms":values[sample_frames/2],"gpu_p95_ms":values[int(sample_frames*.95)],"frame_median_ms":frame_times[sample_frames/2],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}
		report.samples.append(row);print("RENDER_LAYER ",JSON.stringify(row))
		root.get_texture().get_image().save_png(output+"_"+mode+".png")
	FileAccess.open(output+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	game.quit_game()
