extends SceneTree
const CUT=preload("res://scripts/camera_occlusion.gd")
const RIG=preload("res://scripts/camera_terrain_transition.gd")
class TerrainSim:
	extends RefCounted
	var map:Dictionary={"size":100,"terrain":[],"heights":[]}
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var main=load("res://scripts/main.gd").new()
	main.distance=8;main.camera_pitch_mode="dynamic"
	check(is_equal_approx(main.effective_camera_pitch(),10),"maximum magnification reaches actual 10 degree target")
	main.distance=20
	check(is_equal_approx(main.effective_camera_pitch(),20),"new close range joins existing pitch without a discontinuity")
	main.distance=8;main.camera_pitch=33
	check(is_equal_approx(main.effective_camera_pitch(),33),"fixed mode is independent of new close dynamic range")
	main.free()
	var eye:=Vector3(0,1.389,7.878);var target:=Vector3.ZERO
	var axis:Vector3=(target-eye).normalized();var mid:Vector3=eye+axis*3.5
	check(CUT.strength(mid,eye,target)==0.0,"normal-distance central object remains completely opaque")
	check(CUT.strength(mid+Vector3(.3,0,0),eye,target)==0.0,"central view has no fade hole around its axis")
	check(CUT.strength(eye+axis*1.0,eye,target)>.9,"only very near central geometry fades")
	var edge:Vector3=eye+axis*4.0+Vector3(4.0*tan(deg_to_rad(42)*.5)*1.6*.9,0,0)
	check(CUT.strength(edge,eye,target)>.3,"foreground geometry at screen edge fades")
	check(CUT.strength(Vector3(0,0,4),eye,target)==0,"focal floor stays intact")
	check(CUT.strength(target+Vector3(0,.6,0),eye,target)==0,"target units remain opaque")
	check(CUT.strength(eye-axis*3,eye,target)==0,"objects behind camera stay unchanged")
	var zoomed_out_eye:Vector3=eye.normalized()*20.0
	check(CUT.parameters(20,42,1.6).limits.w>CUT.parameters(8,42,1.6).limits.w,"nearby fade threshold changes with zoom scale")
	check(CUT.strength(zoomed_out_eye+axis,zoomed_out_eye,target)<CUT.strength(eye+axis,eye,target),"nearby fade strength reduces as camera zooms out")
	check(is_zero_approx(CUT.strength(eye.normalized()*60.0+axis,eye.normalized()*60.0,target)),"tactical overview restores full opacity")
	var edge_a:float=CUT.strength(edge,eye,target)
	var edge_b:float=CUT.strength(edge+Vector3(.01,0,0),eye,target)
	check(edge_a>0 and edge_a<1 and absf(edge_a-edge_b)<.03,"edge fade and restoration have smooth spatial boundaries")
	var sim=TerrainSim.new()
	for z in 100:
		var row:Array=[];row.resize(100);row.fill(0.0);sim.map.heights.append(row)
		var terrain:Array=[];terrain.resize(100);terrain.fill(MapData.LAND);sim.map.terrain.append(terrain)
	for z in range(44,55):
		for x in range(30,70):sim.map.heights[z][x]=14.0
	for hz in [30,60,120]:
		var rig=RIG.new();var focus:=Vector2(35,40)
		var first:Dictionary=rig.pose(sim,focus,8,0,deg_to_rad(10),null)
		var exact:=true
		for frame in hz*3:
			focus.x+=2.0/float(hz)
			var pose:Dictionary=rig.pose(sim,focus,8,0,deg_to_rad(10),null,1.0/float(hz))
			exact=exact and is_equal_approx(float(pose.actual_distance),8) and (pose.target as Vector3).y==0.0
		check(exact and absf(focus.x-41)<.001,"high terrain around eye cannot block pan or force zoom at "+str(hz)+" Hz")
	var view:=Camera3D.new();root.add_child(view);view.position=eye;view.look_at(target)
	var lens:=MiniatureLens.create()
	MiniatureLens.update(view,lens,target,8)
	check(lens.dof_blur_amount==0.0 and lens.dof_blur_near_enabled,"closest inspection view releases blur without changing user toggle")
	MiniatureLens.update(view,lens,target,20)
	check(is_equal_approx(lens.dof_blur_amount,.13),"ordinary zoom retains original miniature blur strength")
	view.free()
	var authored:=ShaderMaterial.new();var shader:=Shader.new()
	shader.code="shader_type spatial; uniform vec3 authored_paint=vec3(.2,.4,.7); void fragment(){ALBEDO=authored_paint;}"
	authored.shader=shader;authored.set_shader_parameter("authored_paint",Vector3(.3,.5,.8))
	var wrapped:Material=CUT.material(authored)
	check(wrapped!=authored and not authored.shader.code.contains("paper_camera_occlusion"),"shared authored shader remains unchanged")
	check(wrapped.get_shader_parameter("authored_paint")==Vector3(.3,.5,.8),"private shader retains authored paint uniform")
	check(CUT.material(wrapped)==wrapped,"wrapping cached geometry cannot inject duplicate uniforms")
	print("CAMERA_OCCLUSION_REVISION ",JSON.stringify({"checks":checks,"failures":failures}))
	for label in failures:push_error(label)
	quit(0 if failures.is_empty() else 1)
