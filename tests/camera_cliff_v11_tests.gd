extends SceneTree
const Rig=preload("res://scripts/camera_terrain_transition.gd")
const Clearance=preload("res://scripts/camera_local_clearance.gd")
class TerrainSim:
	extends RefCounted
	var map:Dictionary={"size":320,"terrain":[],"heights":[]}
	func _nearby_entities(_p:Vector2,_radius:float)->Array:return []
var checks:=0
var failures:Array[String]=[]
var traces:Array=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
func eye(pose:Dictionary,focus:Vector2,yaw:float=0.0)->Vector3:
	var pitch:float=deg_to_rad(20)
	return pose.target+Vector3(sin(yaw)*float(pose.actual_distance)*cos(pitch),float(pose.actual_distance)*sin(pitch),cos(yaw)*float(pose.actual_distance)*cos(pitch))
func run()->void:
	var sim=TerrainSim.new();var clearance=Clearance.new()
	for z:int in 320:
		var heights:Array=[];var terrain:Array=[]
		for x:int in 320:heights.append(14.8 if x>=160 else 0.0);terrain.append(MapData.LAND)
		sim.map.heights.append(heights);sim.map.terrain.append(terrain)
	for hz:int in [30,60,120]:
		var rig=Rig.new();var focus:=Vector2(140,140)
		var previous:Vector3=eye(rig.pose(sim,focus,20,0,deg_to_rad(20),clearance),focus)
		var maximum_jump:=0.0;var unsafe:=0;var pixels:Array=[]
		for frame:int in int(3.4*hz):
			focus.x+=9.0/float(hz)
			var pose:Dictionary=rig.pose(sim,focus,20,0,deg_to_rad(20),clearance,1.0/float(hz))
			var position:Vector3=eye(pose,focus)
			maximum_jump=maxf(maximum_jump,absf(position.y-previous.y))
			if position.y<float(clearance.height_at(sim,Vector2(position.x,position.z)))+1.99:unsafe+=1
			pixels.append(position.y);previous=position
		check(maximum_jump<=40.0/float(hz)+.02,"cliff traversal has a bounded continuous vertical step at "+str(hz)+"Hz")
		# Historical v11 required unsafe==0 by pushing the orbit away. Latest
		# cutaway camera intentionally crosses obstacles, preserving close zoom.
		check(is_equal_approx(rig.extra_distance,0.0),"cliffs do not enlarge the requested orbit")
		for frame:int in hz*2:rig.pose(sim,focus,20,0,deg_to_rad(20),clearance,1.0/float(hz))
		check(absf(rig.focus_height-14.8)<.001 and rig.extra_distance<.001,"camera settles at correct local plateau height and normal zoom")
		# Reverse across the same cliff: descending must ease instead of snapping.
		maximum_jump=0.0;previous=eye(rig.pose(sim,focus,20,0,deg_to_rad(20),clearance,1.0/float(hz)),focus)
		for frame:int in hz*4:
			focus.x-=9.0/float(hz)
			var pose:Dictionary=rig.pose(sim,focus,20,0,deg_to_rad(20),clearance,1.0/float(hz));var position:Vector3=eye(pose,focus)
			maximum_jump=maxf(maximum_jump,absf(position.y-previous.y));previous=position
		check(maximum_jump<=40.0/float(hz)+.02,"descending cliff also retains continuous camera height")
		traces.append({"hz":hz,"maximum_descent_step":maximum_jump,"unsafe_frames":unsafe,"ascending_heights":pixels})
	sim.map.heights[270][270]=130.0
	var rig=Rig.new();var focus:=Vector2(40,40)
	var pose:Dictionary=rig.pose(sim,focus,20,0,deg_to_rad(20),clearance)
	check(is_equal_approx(float(pose.actual_distance),20) and pose.target.y==0,"remote mountain cannot pin the smoothed valley camera")
	var report:Dictionary={"checks":checks,"failures":failures,"scope":"real terrain sampling and production local-camera rig,30/60/120Hz climb/descent, no audio or GPU claim","traces":traces}
	var file:=FileAccess.open("res://artifacts/feedback_v11_20261007/camera_cliff_validation.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("CAMERA_CLIFF_V11 ",JSON.stringify({"checks":checks,"failures":failures}))
	for label:String in failures:push_error(label)
	quit(0 if failures.is_empty() else 1)
