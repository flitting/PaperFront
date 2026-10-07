extends RefCounted

## One continuous MakeHuman CC0 hand, skinned by a separate 16-bone skeleton.
## The two walking fingertips are centred on the simulation position; the palm
## and thumb are allowed to overhang it. No rigid finger meshes are constructed.
const SCENE:PackedScene=preload("res://assets/creator_hand/creator_hand.glb")
const META_PATH:="res://assets/creator_hand/rig.json"
const DIMENSIONS:=Vector3(7.2,5.6,5.4)
const PAD_CLEARANCE:=0.0
static var source_mesh:Mesh
static var rig_meta:Dictionary={}
static var skin_material:ShaderMaterial
static var owner_cutoff: float = INF
static var owner_area_evidence: Dictionary = {}

static func _metadata()->Dictionary:
	if rig_meta.is_empty():
		var contents:String=FileAccess.get_file_as_string(META_PATH)
		var parsed:Variant=JSON.parse_string(contents)
		assert(parsed is Dictionary and parsed.has("finger_joints_godot"))
		rig_meta=parsed
	return rig_meta

static func recipe_meta(_team:int)->Dictionary:
	if source_mesh==null:
		var sample:Node3D=SCENE.instantiate()
		var mesh:MeshInstance3D=sample.get_node("CreatorHandRig/Skeleton3D/CreatorHandSkin")
		source_mesh=mesh.mesh
		sample.free()
	return {
		"body_mesh":source_mesh,
		"parts":[],
		"dimensions":DIMENSIONS,
		"muzzle_pos":Vector3(0,2.6,0),
		"design":"sky_creator_hand_continuous_skin",
		"direct_skinned":true,
	}

static func _skin_material()->ShaderMaterial:
	if skin_material!=null:return skin_material
	var shader:=Shader.new()
	shader.code="""shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;
uniform vec3 skin_tint : source_color = vec3(0.78, 0.58, 0.49);
uniform vec4 owner_color : source_color = vec4(0.9059,0.6784,0.2588,1.0);
uniform float paint_cutoff = 0.0;
varying vec3 skin_point;
void vertex() { skin_point = VERTEX; }
float hash(vec3 p) { return fract(sin(dot(p,vec3(12.9898,78.233,39.425)))*43758.5453); }
float noise3(vec3 p) {
    vec3 i=floor(p), f=fract(p);
    f=f*f*(3.0-2.0*f);
    return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),
                   mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),
               mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),
                   mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
void fragment() {
    float broad=noise3(skin_point*3.5)-0.5;
    float pores=noise3(skin_point*48.0)-0.5;
    vec3 natural=skin_tint*(0.98+broad*0.055+pores*0.025);
    // A small wrist identification mark leaves the hand predominantly natural.
    float paint=1.0-step(paint_cutoff,skin_point.x);
    vec3 pigment=owner_color.rgb*(0.98+broad*0.025);
    ALBEDO=mix(natural,pigment,paint);
    ROUGHNESS=0.86+pores*0.035;
    SPECULAR=0.12;
}
"""
	skin_material=ShaderMaterial.new()
	skin_material.shader=shader
	return skin_material

static func _owner_paint_cutoff(mesh: Mesh) -> float:
	if is_finite(owner_cutoff): return owner_cutoff
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var views: Array[Vector3] = [Vector3.ZERO,Vector3.LEFT,Vector3.RIGHT,Vector3.UP,Vector3.DOWN,Vector3.FORWARD,Vector3.BACK,Vector3(.3,.72,.62).normalized()]
	var total := PackedFloat64Array();total.resize(views.size())
	var triangles: Array = []
	var low: float = INF
	var high: float = -INF
	for p in vertices:low=minf(low,p.x);high=maxf(high,p.x)
	for i in range(0,indices.size(),3):
		var points := PackedVector3Array([vertices[indices[i]],vertices[indices[i+1]],vertices[indices[i+2]]])
		var cross: Vector3 = (points[1]-points[0]).cross(points[2]-points[0])
		var area: float = cross.length()*.5
		var normal: Vector3 = -cross.normalized()
		var weights := PackedFloat64Array()
		for j in range(views.size()):
			var weight: float = 1.0 if views[j]==Vector3.ZERO else maxf(0,normal.dot(views[j]))
			weights.append(weight);total[j]+=area*weight
		triangles.append({"points":points,"weights":weights})
	var volume = load("res://scripts/volume_models.gd")
	for iteration in range(11):
		var cut: float = (low+high)*.5
		var areas := PackedFloat64Array();areas.resize(views.size())
		for triangle in triangles:
			var area: float = volume._livery_area(volume._livery_polygon(triangle.points,0,cut))
			for j in range(views.size()):areas[j]+=area*float(triangle.weights[j])
		var largest: float = 0.0
		for j in [0,views.size()-1]:largest=maxf(largest,areas[j]/maxf(.00001,total[j]))
		if largest <= .06:low=cut
		else:high=cut
	owner_cutoff=low
	var fractions: Array[float] = []
	var areas := PackedFloat64Array();areas.resize(views.size())
	for triangle in triangles:
		var area: float = volume._livery_area(volume._livery_polygon(triangle.points,0,owner_cutoff))
		for j in range(views.size()):areas[j]+=area*float(triangle.weights[j])
	for j in range(views.size()):fractions.append(areas[j]/maxf(.00001,total[j]))
	owner_area_evidence={"cutoff":owner_cutoff,"source_and_six_sides_and_tabletop_owner_area":fractions,"fixed_secondary":"natural_skin","surface_and_tabletop_owner_area":[fractions[0],fractions[-1]]}
	return owner_cutoff

static func create(spec:Dictionary,team:int,_pose_only:bool=false)->Dictionary:
	var root:Node3D=SCENE.instantiate()
	root.name="Tabletop_sky_creator_hand"
	var body:Node3D=root.get_node("CreatorHandRig")
	var skeleton:Skeleton3D=body.get_node("Skeleton3D")
	var skin:MeshInstance3D=skeleton.get_node("CreatorHandSkin")
	# Explicitly bind each instance. The imported ArrayMesh and Skin resources
	# are shared, while Skeleton3D pose state remains per spawned hand.
	skin.skeleton=NodePath("..")
	skin.skin=skin.skin
	var owner: Color=spec.get("owner_color_override",load("res://scripts/volume_models.gd").player_color(team))
	var paint: ShaderMaterial=_skin_material().duplicate()
	paint.set_shader_parameter("owner_color",owner)
	paint.set_shader_parameter("paint_cutoff",_owner_paint_cutoff(skin.mesh))
	skin.set_surface_override_material(0,paint)
	var owner_materials: Array[Material]=[paint]
	var nail_source: Material=skin.mesh.surface_get_material(1)
	if nail_source is StandardMaterial3D:
		var nails: StandardMaterial3D=nail_source.duplicate()
		nails.roughness=.75
		skin.set_surface_override_material(1,nails)
		owner_materials.append(nails)
	var base_rotations:Array[Quaternion]=[]
	for index in range(skeleton.get_bone_count()):
		base_rotations.append(skeleton.get_bone_pose_rotation(index))
	var muzzle:=Marker3D.new()
	muzzle.name="Muzzle"
	muzzle.position=Vector3(0,2.6,0)
	body.add_child(muzzle)
	var result:Dictionary={
		"root":root,"body":body,"turret":null,"muzzle":muzzle,
		"meshes":[skin],"border_meshes":[],"parts":[],
		"skinned_mesh":skin,"skeleton":skeleton,"direct_skinned":true,
		"dimensions":DIMENSIONS,"height":DIMENSIONS.y,
		"footprint":Vector2(DIMENSIONS.x,DIMENSIONS.z),
		"volumetric":true,"faction":str(spec.get("faction","sky")),
		"art":"creator_hand","team":team,"owner_color":owner,"owner_materials":owner_materials,"clock":0.0,
		"pose_version":0,"pose_active":true,"recoil":Vector3.ZERO,
		"base_bone_rotations":base_rotations,
		"model_scale":1.0,"recoil_distance":0.0,
		"cargo":[],"cargo_count":0,"drill":null,
		"aircraft":false,"infantry":false,
		"design":"sky_creator_hand_continuous_skin",
	}
	update_pose(result,{"state":"idle","id":0})
	return result

static func _bone(model:Dictionary,name:String,degrees:float)->void:
	var skeleton:Skeleton3D=model.skeleton
	var index:int=skeleton.find_bone(name)
	assert(index>=0)
	skeleton.set_bone_pose_rotation(index,model.base_bone_rotations[index]*Quaternion(Vector3.BACK,deg_to_rad(degrees)))

static func _tip_source(digit:String)->Vector3:
	var values:Array=_metadata().finger_joints_godot[digit][3]
	return Vector3(float(values[0]),float(values[1]),float(values[2]))

static func _finger_tip(skeleton:Skeleton3D,digit:String)->Vector3:
	var index:int=skeleton.find_bone(digit+"Distal")
	var source:Vector3=_tip_source(digit)
	return skeleton.get_bone_global_pose(index)*skeleton.get_bone_global_rest(index).affine_inverse()*source

static func _strike_amount(e:Dictionary)->float:
	var windup:float=float(e.get("hand_strike",0.0))
	var recovery:float=float(e.get("hand_recover",0.0))
	if windup>0.0:
		var progress:float=clampf(1.0-windup/.5,0.0,1.0)
		return progress*progress*(3.0-2.0*progress)
	if recovery>0.0:
		# The first 0.19s hold pressure against low wreckage, then recoil.
		var hold:float=clampf(recovery/.16,0.0,1.0)
		return hold*hold*(3.0-2.0*hold)
	return 0.0

static func update_pose(model:Dictionary,e:Dictionary)->void:
	var skeleton:Skeleton3D=model.skeleton
	var body:Node3D=model.body
	var strike:float=_strike_amount(e)
	var moving:bool=e.get("state","") in ["move","returning"]
	var time:float=float(model.clock)
	var sway:float=sin(time*6.0) if moving else 0.0
	for entry in [
		{"name":"Index","phase":sway,"angles":[-5.0,-20.0,-25.0]},
		{"name":"Middle","phase":-sway,"angles":[-5.0,-20.0,-25.0]},
	]:
		var digit:String=entry.name
		var phase:float=entry.phase
		var lift:float=maxf(0.0,phase)
		var base:Array=entry.angles
		_bone(model,digit+"Proximal",lerpf(float(base[0])+phase*7.0,5.0,strike))
		_bone(model,digit+"Middle",lerpf(float(base[1])-lift*13.0,-10.0,strike))
		_bone(model,digit+"Distal",lerpf(float(base[2])+lift*9.0,-15.0,strike))
	for digit in ["Ring","Little"]:
		var proximal:float=-80.0
		var inward:float=-20.0 if digit=="Ring" else -25.0
		var bone_index:int=skeleton.find_bone(digit+"Proximal")
		skeleton.set_bone_pose_rotation(bone_index,model.base_bone_rotations[bone_index]*Quaternion(Vector3.RIGHT,deg_to_rad(inward))*Quaternion(Vector3.BACK,deg_to_rad(proximal-4.0*strike)))
		_bone(model,digit+"Middle",(-105.0 if digit=="Ring" else -110.0)-3.0*strike)
		_bone(model,digit+"Distal",-50.0)
	var thumb:int=skeleton.find_bone("ThumbProximal")
	skeleton.set_bone_pose_rotation(thumb,model.base_bone_rotations[thumb]*Quaternion(Vector3.RIGHT,deg_to_rad(15.0))*Quaternion(Vector3.BACK,deg_to_rad(15.0)))
	_bone(model,"ThumbMiddle",0.0)
	_bone(model,"ThumbDistal",0.0)
	skeleton.force_update_all_bone_transforms()
	var pitch:float=deg_to_rad(lerpf(-28.0,-10.0,strike))
	body.rotation=Vector3(0,0,pitch)
	var basis:=Basis(Vector3.BACK,pitch)
	var index_tip:Vector3=basis*_finger_tip(skeleton,"Index")
	var middle_tip:Vector3=basis*_finger_tip(skeleton,"Middle")
	var midpoint:Vector3=(index_tip+middle_tip)*.5
	var lowest:float=minf(index_tip.y,middle_tip.y)-PAD_CLEARANCE
	var idle:=Vector3(-midpoint.x,-lowest+.025,-midpoint.z)
	var origin:Vector2=e.get("pos",Vector2.ZERO)
	var landing:Vector2=e.get("hand_landing",origin)
	var delta:Vector2=landing-origin
	var heading:float=deg_to_rad(float(e.get("alpha",0.0)))
	var contact_height:float=float(e.get("hand_contact_height",0.0))
	var recovery:float=float(e.get("hand_recover",0.0))
	if recovery>0.0:
		var ground:float=float(e.get("hand_ground_height",0.0))+.07
		var compression:float=clampf((.35-recovery)/.08,0.0,1.0)
		compression=compression*compression*(3.0-2.0*compression)
		contact_height=lerpf(contact_height,ground,compression)
	var target:=Vector3(delta.x*cos(heading)+delta.y*sin(heading),contact_height,-delta.x*sin(heading)+delta.y*cos(heading))
	var reach:float=strike*strike*(3.0-2.0*strike)
	var contact:=Vector3(target.x-midpoint.x,target.y-lowest-.045,target.z-midpoint.z)
	body.position=idle.lerp(contact,reach)+Vector3(0,sin(PI*reach)*.28,0)
	model.support_tips=[index_tip+body.position,middle_tip+body.position]
	model.pose_version=int(model.get("pose_version",0))+1
	model.pose_active=true
