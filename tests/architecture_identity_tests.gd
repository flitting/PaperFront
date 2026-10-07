extends SceneTree
const V=preload("res://scripts/volume_models.gd")
var failures: Array[String]=[]
var checks: int=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures.append(message)
func intersects(mesh: Mesh,start: Vector3,end: Vector3) -> bool:
	for surface in range(mesh.get_surface_count()):
		var points: PackedVector3Array=mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for i in range(0,points.size(),3):
			if Geometry3D.segment_intersects_triangle(start,end,points[i],points[i+1],points[i+2])!=null: return true
	return false
func silhouette(recipe: Dictionary) -> PackedByteArray:
	var mask:=PackedByteArray(); mask.resize(64*64)
	var sources: Array=[{"mesh":recipe.body_mesh,"pivot":Vector3.ZERO}]
	sources.append_array(recipe.parts)
	for source in sources:
		var mesh: Mesh=source.mesh
		for surface in range(mesh.get_surface_count()):
			var points: PackedVector3Array=mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for i in range(0,points.size(),3):
				var tri: Array[Vector2]=[]
				for j in range(3):
					var v: Vector3=points[i+j]+(source.pivot as Vector3)
					tri.append(Vector2(32.0+(v.x*.85-v.z*.53)*10.0,47.0-(v.y*.89-(v.x*.53+v.z*.85)*.45)*10.0))
				var low:=Vector2(minf(tri[0].x,minf(tri[1].x,tri[2].x)),minf(tri[0].y,minf(tri[1].y,tri[2].y)))
				var high:=Vector2(maxf(tri[0].x,maxf(tri[1].x,tri[2].x)),maxf(tri[0].y,maxf(tri[1].y,tri[2].y)))
				for y in range(maxi(0,floori(low.y)),mini(63,ceili(high.y))+1):
					for x in range(maxi(0,floori(low.x)),mini(63,ceili(high.x))+1):
						if mask[y*64+x]: continue
						var p:=Vector2(float(x)+.5,float(y)+.5)
						var a: float=(tri[1]-tri[0]).cross(p-tri[0])
						var b: float=(tri[2]-tri[1]).cross(p-tri[1])
						var c: float=(tri[0]-tri[2]).cross(p-tri[2])
						if (a>=0 and b>=0 and c>=0) or (a<=0 and b<=0 and c<=0): mask[y*64+x]=1
	return mask
func run() -> void:
	var masks: Dictionary={}
	for faction in ["kestrel","rivet","iron","sky"]:
		for tier in range(3):
			var recipe: Dictionary=V._raw_recipe({"faction":faction,"art":"shipyard","size":4},"building",0,tier)
			if tier == 2: masks[faction]=silhouette(recipe)
			check(recipe.dimensions.x<=4 and recipe.dimensions.z<=4,"shipyard stays within 4x4: "+faction+" tier "+str(tier))
			for z in [-.95,0.0,.95]:
				for y in [.40,1.0,1.65]:
					check(not intersects(recipe.body_mesh,Vector3(-.3,y,z),Vector3(2.05,y,z)),"large ship has clear sea-facing slot: "+faction+" "+str(Vector2(y,z))+" tier "+str(tier))
	for art in ["hq","outpost"]:
		var size: int=8 if art=="hq" else 4
		var recipe: Dictionary=V._recipe({"faction":"sky","art":art,"size":size},"building",0)
		check(recipe.get("architecture_form","") in ["folded_command_wings","folded_field_node"],"sky command uses its own architectural layout")
		check(recipe.dimensions.x<=float(size) and recipe.dimensions.z<=float(size),"sky command fits original logical footprint")
		for x in [-.60,0.0,.60]:
			for y in [.30,.90,1.55]:
				check(not intersects(recipe.body_mesh,Vector3(x,y,0),Vector3(x,y,size*.55)),"folded sky command keeps actual +Z personnel throat clear: "+art+" "+str(Vector2(x,y)))
	# Project the actual far-LOD triangles into a monochrome coverage mask.
	# This is independent of paint, vertex counts and authoring signatures,
	# and runs without a renderer or pre-existing screenshots.
	var names: Array=masks.keys()
	for a in range(names.size()):
		for b in range(a+1,names.size()):
			var joined: int=0; var intersection: int=0
			for i in range(64*64):
				if masks[names[a]][i] or masks[names[b]][i]: joined+=1
				if masks[names[a]][i] and masks[names[b]][i]: intersection+=1
			var overlap: float=float(intersection)/maxi(1,joined)
			check(overlap<.83,"monochrome silhouette distinguishes "+names[a]+" / "+names[b]+": "+str(overlap))
	print("ARCHITECTURE_IDENTITY_TEST ",JSON.stringify({"checks":checks,"failures":failures}))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
