extends RefCounted
class_name VolumeModels

## Original hand-painted tabletop models. All roofs, tracks, wheels and walls are
## solid geometry. +X is every vehicle's forward direction and every gun's bore.
## Body and turret use separate cached meshes so animation never rebuilds geometry.
const INK := Color("382a22")
const PAPER := Color("e6d5af")
const KRAFT := Color("c9ad7f")
const WOOD := Color("987b52")
const STEEL := Color("a9aea4")
const RUBBER := Color("625849")
const GLASS := Color("759591")
const BLUE := Color("2865a5")
const RED := Color("bb4034")
const PLAYER_COLORS := [Color("e7ad42"), Color("41c7c6"), Color("af80d1"), Color("9bb85a"), Color("6498df"), Color("df7860"), Color("d68eb5"), Color("e2d478")]
const INFANTRY_ART := ["rifle", "anti", "engineer", "demolition"]
const AIRCRAFT_ART := ["fighter", "attacker", "bomber", "air_transport", "recon"]
const EXPANSION_FACTIONS := ["iron", "sky"]
const WALL_CONNECTIONS = preload("res://scripts/wall_connections.gd")

static var recipes: Dictionary = {}
static var painted_material: ShaderMaterial
static var performance_material:ShaderMaterial
static var cargo_mesh: ArrayMesh
static var cutter_mesh: ArrayMesh
static var quality_meshes:Dictionary={}
static var quality_sources:Dictionary={}
const UNIT_LOD_RESOURCE=preload("res://assets/models/unit_lod_indices.res")


class CraftMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	# Explicitly enabled only while authoring a vehicle's major closed forms.
	# The original lit mesh and its hard normals never use these arrays.
	var capture_shell: bool = false
	var shell_vertices := PackedVector3Array()
	var shell_normals := PackedVector3Array()

	func triangle(a: Vector3, b: Vector3, c: Vector3, color: Color, normal: Vector3) -> void:
		# Godot's front winding is clockwise. Normals point out of the model.
		if (b-a).cross(c-a).dot(normal) > 0:
			vertices.append_array([a,c,b])
		else:
			vertices.append_array([a,b,c])
		for i in range(3):
			normals.append(normal)
			colors.append(color)
		if capture_shell:
			shell_vertices.append_array(vertices.slice(vertices.size()-3))
			shell_normals.append_array([normal,normal,normal])

	func face(points: Array, color: Color, normal: Vector3) -> void:
		for i in range(1,points.size()-1):
			triangle(points[0],points[i],points[i+1],color,normal)

	func palette_face(points: Array, center_color: Color, border_color: Color, normal: Vector3, inset: float = .075) -> void:
		# Five coplanar color regions on the existing quad: no extra thickness,
		# silhouette change or ink lines. .075 leaves 27.75% of its area painted.
		var u: Vector3=points[1]-points[0]
		var v: Vector3=points[3]-points[0]
		var inner: Array=[points[0]+u*inset+v*inset,points[0]+u*(1.0-inset)+v*inset,points[0]+u*(1.0-inset)+v*(1.0-inset),points[0]+u*inset+v*(1.0-inset)]
		face(inner,center_color,normal)
		for i in range(4):
			var next: int=(i+1)%4
			face([points[i],points[next],inner[next],inner[i]],border_color,normal)

	func shell_triangle(a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
		if (b-a).cross(c-a).dot(normal)>0:
			shell_vertices.append_array([a,c,b])
		else:
			shell_vertices.append_array([a,b,c])
		shell_normals.append_array([normal,normal,normal])

	func palette_cap(polygon: PackedVector2Array, indices: PackedInt32Array, depth: float, center: Vector3, center_color: Color, border_color: Color) -> void:
		# Keep the original closed-cap triangulation in the outline shell. The
		# coplanar paint regions belong only to the lit mesh, so their internal
		# vertices cannot produce extra halo edges or change corner normals.
		if capture_shell:
			for i in range(0,indices.size(),3):
				for side in [-1.0,1.0]:
					var normal: Vector3=Vector3(0,0,side)
					var points: Array=[]
					for offset in range(3):
						var p: Vector2=polygon[indices[i+offset]]
						points.append(center+Vector3(p.x,p.y,side*depth*.5))
					shell_triangle(points[0],points[1],points[2],normal)
		var midpoint:=Vector2.ZERO
		for p in polygon:midpoint+=p
		midpoint/=float(polygon.size())
		var previous_capture: bool=capture_shell
		capture_shell=false
		for side in [-1.0,1.0]:
			var normal:=Vector3(0,0,side)
			var outer: Array=[]
			var inner: Array=[]
			for p in polygon:
				outer.append(center+Vector3(p.x,p.y,side*depth*.5))
				var inset: Vector2=p.lerp(midpoint,.18)
				inner.append(center+Vector3(inset.x,inset.y,side*depth*.5))
			face(inner,center_color,normal)
			for i in range(outer.size()):
				var next: int=(i+1)%outer.size()
				face([outer[i],outer[next],inner[next],inner[i]],border_color,normal)
		capture_shell=previous_capture

	func box(center: Vector3, size: Vector3, color: Color, outline: bool = true) -> void:
		var h := size*.5
		var p: Array = []
		for v in [Vector3(-1,-1,-1),Vector3(1,-1,-1),Vector3(1,1,-1),Vector3(-1,1,-1),Vector3(-1,-1,1),Vector3(1,-1,1),Vector3(1,1,1),Vector3(-1,1,1)]:
			p.append(center+v*h)
		face([p[0],p[3],p[2],p[1]],color,Vector3.FORWARD)
		face([p[4],p[5],p[6],p[7]],color,Vector3.BACK)
		face([p[0],p[4],p[7],p[3]],color,Vector3.LEFT)
		face([p[1],p[2],p[6],p[5]],color,Vector3.RIGHT)
		face([p[3],p[7],p[6],p[2]],color,Vector3.UP)
		face([p[0],p[1],p[5],p[4]],color,Vector3.DOWN)
		if outline:
			for edge in [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]]:
				line(p[edge[0]],p[edge[1]],.022,VolumeModels.INK)

	func line(a: Vector3, b: Vector3, radius: float, color: Color) -> void:
		var axis: Vector3 = (b-a).normalized()
		if axis.length_squared() < .9:return
		var tangent: Vector3 = axis.cross(Vector3.UP)
		if tangent.length_squared() < .01:tangent=axis.cross(Vector3.RIGHT)
		tangent=tangent.normalized()
		var bitangent: Vector3 = axis.cross(tangent).normalized()
		# Broaden only fine ink strokes. Timber, painted seams and broad lines
		# retain their original radius, and the original radius selects sides.
		var stroke_radius: float=radius*1.45 if color==VolumeModels.INK and radius<=.035 else radius
		var segments: int=4 if radius<=.035 else 6
		# Ink strokes and interior seams are never independent outline shells.
		var previous_capture: bool = capture_shell
		capture_shell = false
		for i in range(segments):
			var aa: float = float(i)*TAU/float(segments)
			var ab: float = float(i+1)*TAU/float(segments)
			var oa: Vector3 = (tangent*cos(aa)+bitangent*sin(aa))*stroke_radius
			var ob: Vector3 = (tangent*cos(ab)+bitangent*sin(ab))*stroke_radius
			face([a+oa,b+oa,b+ob,a+ob],color,((oa+ob)*.5).normalized())
		capture_shell = previous_capture

	func cylinder(center: Vector3, radius: float, length: float, axis: Vector3, color: Color, segments: int = 12, outline: bool = true) -> void:
		var direction: Vector3 = axis.normalized()
		var tangent: Vector3 = direction.cross(Vector3.UP)
		if tangent.length_squared()<.01:tangent=direction.cross(Vector3.RIGHT)
		tangent=tangent.normalized()
		var bitangent: Vector3 = direction.cross(tangent).normalized()
		var a: Vector3 = center-direction*length*.5
		var b: Vector3 = center+direction*length*.5
		for i in range(segments):
			var aa: float = float(i)*TAU/float(segments)
			var ab: float = float(i+1)*TAU/float(segments)
			var oa: Vector3 = (tangent*cos(aa)+bitangent*sin(aa))*radius
			var ob: Vector3 = (tangent*cos(ab)+bitangent*sin(ab))*radius
			face([a+oa,b+oa,b+ob,a+ob],color,((oa+ob)*.5).normalized())
			triangle(a,a+ob,a+oa,color,-direction)
			triangle(b,b+oa,b+ob,color,direction)
			if outline:
				line(a+oa,a+ob,.014,VolumeModels.INK)
				line(b+oa,b+ob,.014,VolumeModels.INK)

	func prism(profile: Array, depth: float, center: Vector3, color: Color, outline: bool = true, edge_colors: Dictionary = {}, bordered_edges: Dictionary = {}, cap_border: Color = Color.TRANSPARENT) -> void:
		# Extrusion of an XY cut shape into real Z volume, including both caps.
		var polygon := PackedVector2Array()
		for p in profile:polygon.append(p)
		var indices := Geometry2D.triangulate_polygon(polygon)
		if cap_border.a>0:
			palette_cap(polygon,indices,depth,center,color,cap_border)
		else:
			for i in range(0,indices.size(),3):
				var a: Vector2 = polygon[indices[i]]
				var b: Vector2 = polygon[indices[i+1]]
				var c: Vector2 = polygon[indices[i+2]]
				triangle(center+Vector3(a.x,a.y,-depth*.5),center+Vector3(b.x,b.y,-depth*.5),center+Vector3(c.x,c.y,-depth*.5),color,Vector3.FORWARD)
				triangle(center+Vector3(a.x,a.y,depth*.5),center+Vector3(b.x,b.y,depth*.5),center+Vector3(c.x,c.y,depth*.5),color,Vector3.BACK)
		var clockwise: bool = Geometry2D.is_polygon_clockwise(polygon)
		for i in range(polygon.size()):
			var a: Vector2 = polygon[i]
			var b: Vector2 = polygon[(i+1)%polygon.size()]
			var normal: Vector3 = Vector3(b.y-a.y,a.x-b.x,0).normalized()
			if clockwise:normal=-normal
			var p0 := center+Vector3(a.x,a.y,-depth*.5)
			var p1 := center+Vector3(b.x,b.y,-depth*.5)
			var p2 := center+Vector3(b.x,b.y,depth*.5)
			var p3 := center+Vector3(a.x,a.y,depth*.5)
			var side_color: Color=edge_colors.get(i,color)
			if bordered_edges.has(i):
				var previous_capture: bool=capture_shell
				if previous_capture:
					shell_triangle(p0,p1,p2,normal)
					shell_triangle(p0,p2,p3,normal)
				capture_shell=false
				palette_face([p0,p1,p2,p3],side_color,bordered_edges[i],normal)
				capture_shell=previous_capture
			else:
				face([p0,p1,p2,p3],side_color,normal)
			if outline:
				line(p0,p1,.025,VolumeModels.INK)
				line(p3,p2,.025,VolumeModels.INK)
				line(p0,p3,.019,VolumeModels.INK)

	func gable(center: Vector3, width: float, depth: float, rise: float, color: Color) -> void:
		# Real pitched roof with thick eaves and a ridge. It is not a façade card.
		var half: float = width*.5
		var profile: Array = [Vector2(-half,0),Vector2(0,rise),Vector2(half,0),Vector2(half,-.105),Vector2(0,rise-.105),Vector2(-half,-.105)]
		# Paper gable ends and a few painted roof boards, with exposed eaves.
		# Broken seams follow the construction instead of covering every plane.
		prism(profile,depth,center,VolumeModels.KRAFT,true,{0:color,1:color.darkened(.08)},{0:VolumeModels.KRAFT,1:VolumeModels.KRAFT})
		roof_seams(center,width,depth,rise)

	func roof_seams(center: Vector3, width: float, depth: float, rise: float) -> void:
		for side in [-1.0,1.0]:
			for z_fraction in [-.23,.28]:
				var a: Vector3=center+Vector3(side*width*.08,rise*.84+.013,depth*z_fraction)
				var b: Vector3=center+Vector3(side*width*.44,rise*.12+.013,depth*z_fraction+.025)
				line(a,b,.009,VolumeModels.INK)
				line(a+Vector3(0,.008,.037),a.lerp(b,.57)+Vector3(0,.008,.037),.011,VolumeModels.PAPER.darkened(.13))
			# Two short, uneven dry-brush strokes belong to this roof only.
			# Their widths survive the gameplay view without a field of speckles.
			for mark in [Vector3(.19,-.36,.18),Vector3(.29,.10,.10)]:
				var a: Vector3=center+Vector3(side*width*mark.x,rise*(1.0-2.0*mark.x)+.016,depth*mark.y)
				var b: Vector3=center+Vector3(side*width*(mark.x+mark.z),rise*(1.0-2.0*(mark.x+mark.z))+.016,depth*mark.y+.018)
				var offset:=Vector3(0,0,.045)
				face([a,b,b+offset*.38,a+offset],VolumeModels.KRAFT.lightened(.09),Vector3(side*rise,width*.5,0).normalized())
		# One imperfect pale ridge catches the light over the dark join.
		line(center+Vector3(0,rise+.020,-depth*.43),center+Vector3(0,rise+.020,depth*.20),.013,VolumeModels.PAPER.darkened(.10))
		line(center+Vector3(-.025,rise+.026,depth*.27),center+Vector3(-.025,rise+.026,depth*.43),.008,VolumeModels.INK)

	func slab(profile: Array, thickness: float, center: Vector3, color: Color, outline: bool = true) -> void:
		# A closed XZ cutout: aircraft wings and runway plates have actual thickness.
		var part := CraftMesh.new()
		part.capture_shell = capture_shell
		part.prism(profile,thickness,Vector3.ZERO,color,outline)
		for i in range(part.vertices.size()):
			var p: Vector3 = part.vertices[i]
			var n: Vector3 = part.normals[i]
			vertices.append(center+Vector3(p.x,p.z,-p.y))
			normals.append(Vector3(n.x,n.z,-n.y))
			colors.append(part.colors[i])
		for i in range(part.shell_vertices.size()):
			var p: Vector3 = part.shell_vertices[i]
			var n: Vector3 = part.shell_normals[i]
			shell_vertices.append(center+Vector3(p.x,p.z,-p.y))
			shell_normals.append(Vector3(n.x,n.z,-n.y))

	func badge(center: Vector3, faction: String, accent: Color, normal: Vector3 = Vector3.BACK, size: float = .24) -> void:
		# Every identification plate has a neutral frame and a raised faction
		# emblem. Its player paint is independent of the large faction paint.
		var part := CraftMesh.new()
		part.box(Vector3.ZERO,Vector3(size*2.16,size*2.16,.060),VolumeModels.INK,false)
		part.box(Vector3(0,0,.037),Vector3(size*1.92,size*1.92,.035),accent,false)
		if faction == "rivet":
			part.line(Vector3(-size*.48,-size*.62,.078),Vector3(size*.28,size*.38,.078),size*.115,VolumeModels.PAPER)
			part.line(Vector3(-size*.25,size*.58,.081),Vector3(size*.61,-size*.04,.081),size*.225,VolumeModels.PAPER)
		else:
			part.prism([Vector2(-size*.78,size*.40),Vector2(-size*.30,size*.28),Vector2(0,-size*.55),Vector2(size*.30,size*.28),Vector2(size*.78,size*.40),Vector2(size*.46,-size*.16),Vector2(size*.14,-size*.25),Vector2(0,-size*.70),Vector2(-size*.14,-size*.25),Vector2(-size*.46,-size*.16)],.040,Vector3(0,0,.075),VolumeModels.PAPER,false)
		var outward: Vector3 = normal.normalized()
		var right: Vector3 = Vector3.RIGHT if absf(outward.y) > .9 else Vector3.UP.cross(outward).normalized()
		var up: Vector3 = outward.cross(right).normalized()
		for i in range(part.vertices.size()):
			var p: Vector3 = part.vertices[i]
			var n: Vector3 = part.normals[i]
			vertices.append(center+right*p.x+up*p.y+outward*p.z)
			normals.append(right*n.x+up*n.y+outward*n.z)
			colors.append(part.colors[i])

	func shell_mesh() -> ArrayMesh:
		# Weld only the normal calculation, preserving every source position.
		# Angle weights avoid triangulation-dependent normals at prism corners.
		var sums: Dictionary = {}
		for triangle_start in range(0,shell_vertices.size(),3):
			for corner in range(3):
				var index: int = triangle_start+corner
				var point: Vector3 = shell_vertices[index]
				var edge_a: Vector3 = shell_vertices[triangle_start+(corner+1)%3]-point
				var edge_b: Vector3 = shell_vertices[triangle_start+(corner+2)%3]-point
				if edge_a.length_squared()<0.0000000001 or edge_b.length_squared()<0.0000000001: continue
				var angle: float = acos(clampf(edge_a.normalized().dot(edge_b.normalized()),-1.0,1.0))
				var key: Vector3i = _shell_key(point)
				sums[key] = (sums.get(key,Vector3.ZERO) as Vector3)+shell_normals[index]*angle
		var smooth_normals := PackedVector3Array()
		for index in range(shell_vertices.size()):
			var summed: Vector3 = sums.get(_shell_key(shell_vertices[index]),shell_normals[index])
			smooth_normals.append(summed.normalized() if summed.length_squared()>0.0000000001 else shell_normals[index])
		var result := ArrayMesh.new()
		if shell_vertices.is_empty(): return result
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = shell_vertices
		arrays[Mesh.ARRAY_NORMAL] = smooth_normals
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		return result

	func _shell_key(point: Vector3) -> Vector3i:
		# A 10-micron tolerance also joins the cylinder's 0/TAU duplicate edge.
		return Vector3i(roundi(point.x*100000.0),roundi(point.y*100000.0),roundi(point.z*100000.0))

	func mesh() -> ArrayMesh:
		var result := ArrayMesh.new()
		var arrays: Array=[]
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=vertices
		arrays[Mesh.ARRAY_NORMAL]=normals
		arrays[Mesh.ARRAY_COLOR]=colors
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		result.surface_set_material(0,VolumeModels._paint())
		return result


static func _paint() -> ShaderMaterial:
	if painted_material!=null:return painted_material
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_back;
varying vec3 paper_position;
void vertex() { paper_position = VERTEX; }
float hash(vec3 p) { return fract(sin(dot(p, vec3(12.9898,78.233,39.425))) * 43758.5453); }
float wash(vec3 p) {
    vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),
               mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
void fragment() {
    vec3 p = paper_position;
    float broad = wash(p * 3.0);
    float strokes = wash(p * vec3(25.0, 5.0, 9.0));
    vec3 pigment = COLOR.rgb;
    float blue = smoothstep(0.09, 0.23, pigment.b - pigment.r);
    float red = smoothstep(0.19, 0.34, pigment.r - pigment.g) * (1.0 - smoothstep(0.40, 0.62, pigment.g));
    float team_paint = max(blue, red);
    // Thin, faded pigment over warm paper. Sparse elongated misses describe a
    // dry brush; broad noise never cuts the roof into camouflage islands.
    vec3 paper = vec3(0.73, 0.60, 0.42);
    pigment = mix(pigment, paper, team_paint * (0.15 + broad * 0.12));
    float brush = wash(p * vec3(3.0, 11.0, 18.0));
    float dry_brush = smoothstep(0.82, 0.96, brush) * team_paint;
    pigment = mix(pigment, paper, dry_brush * 0.40);
    pigment *= 0.91 + broad * 0.13 + strokes * 0.04;
    float phase = dot(p, vec3(211.0, 137.0, 73.0));
    float fibre = sin(phase) * 0.018 * (1.0 - smoothstep(1.0, 3.0, fwidth(phase)));
    pigment *= 1.0 + fibre;
    ALBEDO = mix(pigment / 12.92, pow((pigment + vec3(0.055)) / 1.055, vec3(2.4)), step(vec3(0.04045), pigment));
    ROUGHNESS = 0.94;
    METALLIC = 0.0;
    SPECULAR = 0.0;
}
"""
	painted_material=ShaderMaterial.new()
	painted_material.shader=shader
	return painted_material

static func fast_paint() -> ShaderMaterial:
	if performance_material!=null:return performance_material
	var shader:=Shader.new()
	shader.code="""shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_back;
void fragment() {
    ALBEDO = pow(COLOR.rgb, vec3(2.2)) * 0.96;
    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
}
"""
	performance_material=ShaderMaterial.new()
	performance_material.shader=shader
	return performance_material


static func supports(spec: Dictionary, kind: String) -> bool:
	if str(spec.get("art", "")) in ["naval_transport", "naval_frigate", "naval_signature", "shipyard"]: return true
	if art_faction(spec) in EXPANSION_FACTIONS:
		return kind=="building" or str(spec.get("art","")) not in INFANTRY_ART
	return kind=="building" or str(spec.get("art","")) in AIRCRAFT_ART + ["tank","harvester","assault","scout","aa","artillery","advanced"]

static func art_faction(spec:Dictionary) -> String:
	return str(spec.get("art_faction",spec.get("faction","rivet")))

static func faction_color(faction: String) -> Color:
	match faction:
		"iron": return Color("bb963e")
		"sky": return Color("67578b")
		"rivet": return RED
	return BLUE

static func faction_emblem(faction: String) -> String:
	match faction:
		"iron": return "repair_triangle"
		"sky": return "star_wing"
		"rivet": return "hammer"
	return "wing"

static func lod_source_signature(source:Mesh,team:int) -> String:
	var hash:=HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	var owner:Color=player_color(team)
	for surface in range(source.get_surface_count()):
		var arrays:Array=source.surface_get_arrays(surface)
		for attribute in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_INDEX]:
			hash.update(var_to_bytes(arrays[attribute]))
		# Identity plates use different owner RGB values with identical topology.
		# Normalize just that paint; all other authored colors remain validated.
		if arrays[Mesh.ARRAY_COLOR]!=null:
			var colors:PackedColorArray=(arrays[Mesh.ARRAY_COLOR] as PackedColorArray).duplicate()
			for index in range(colors.size()):
				if colors[index].is_equal_approx(owner):colors[index]=Color(1,0,1,1)
			hash.update(var_to_bytes(colors))
	return hash.finish().hex_encode()


static func quality_mesh(source:Mesh,team:int) -> Mesh:
	if not source is ArrayMesh:return source
	var key:int=source.get_instance_id()
	if quality_meshes.has(key):return quality_meshes[key]
	var template:String=str(quality_sources.get(key,""))
	var records:Dictionary=UNIT_LOD_RESOURCE.get_meta("lod_indices",{})
	var surfaces:Array=records.get(template,[])
	if surfaces.is_empty():
		quality_meshes[key]=source
		return source
	var hashes:Dictionary=UNIT_LOD_RESOURCE.get_meta("source_signatures",{})
	if surfaces.size()!=source.get_surface_count() or str(hashes.get(template,""))!=lod_source_signature(source,team):
		# A stale reduction must never index a changed recipe or erase new badges.
		quality_meshes[key]=source
		return source
	for surface in range(source.get_surface_count()):
		var indices:PackedInt32Array=surfaces[surface]
		if indices.is_empty() or indices.size()%3!=0:
			quality_meshes[key]=source
			return source
		var vertex_count:int=source.surface_get_array_len(surface)
		for index in indices:
			if index<0 or index>=vertex_count:
				quality_meshes[key]=source
				return source
	var mesh:=ArrayMesh.new()
	for surface in range(source.get_surface_count()):
		var arrays:Array=source.surface_get_arrays(surface)
		arrays[Mesh.ARRAY_INDEX]=surfaces[surface]
		mesh.add_surface_from_arrays(source.surface_get_primitive_type(surface),arrays)
		mesh.surface_set_material(surface,source.surface_get_material(surface))
	quality_meshes[key]=mesh
	return mesh


static func _geometry_node(pose_only: bool):
	return preload("res://scripts/pose_mesh.gd").new() if pose_only else MeshInstance3D.new()


static func create_model(spec: Dictionary, kind: String, team: int, pose_only: bool = false) -> Dictionary:
	if not supports(spec,kind):return {}
	if kind=="unit" and str(spec.art)=="creator_hand":
		return load("res://scripts/creator_hand_models.gd").create(spec,team,pose_only)
	var faction: String = art_faction(spec)
	var art: String = str(spec.art)
	var recipe: Dictionary=_recipe(spec,kind,team)
	var root := Node3D.new()
	root.name="Tabletop_"+faction+"_"+art
	var body := Node3D.new()
	body.name="Body"
	root.add_child(body)
	var graphic = _geometry_node(pose_only)
	graphic.mesh=recipe.body_mesh
	graphic.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	body.add_child(graphic)
	var meshes: Array=[graphic]
	# Source references keep border transforms identical to body/turret/recoil.
	var border_meshes: Array[Dictionary]=[]
	if recipe.has("body_border_mesh"):
		border_meshes.append({"mesh":recipe.body_border_mesh,"source":graphic})
	var turret: Node3D=null
	var muzzle: Marker3D=null
	if recipe.has("turret_mesh"):
		turret=Node3D.new()
		turret.name="Turret"
		turret.position=recipe.turret_pos
		root.add_child(turret)
		var turret_graphic = _geometry_node(pose_only)
		turret_graphic.mesh=recipe.turret_mesh
		turret_graphic.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		turret.add_child(turret_graphic)
		meshes.append(turret_graphic)
		if recipe.has("turret_border_mesh"):
			border_meshes.append({"mesh":recipe.turret_border_mesh,"source":turret_graphic})
		muzzle=Marker3D.new()
		muzzle.name="Muzzle"
		muzzle.position=recipe.muzzle_pos
		turret_graphic.add_child(muzzle)
	if muzzle == null and recipe.has("muzzle_pos"):
		muzzle=Marker3D.new()
		muzzle.name="Muzzle"
		muzzle.position=recipe.muzzle_pos
		body.add_child(muzzle)
	var parts: Array[Dictionary] = []
	var part_nodes: Dictionary = {}
	for part in recipe.get("parts",[]):
		var pivot := Node3D.new()
		pivot.name=part.name
		pivot.position=part.pivot
		var parent: Node3D=part_nodes.get(part.get("parent",""),body)
		parent.add_child(pivot)
		part_nodes[part.name]=pivot
		var piece = _geometry_node(pose_only)
		piece.mesh=part.mesh
		piece.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		pivot.add_child(piece)
		meshes.append(piece)
		if part.has("border_mesh"):
			border_meshes.append({"mesh":part.border_mesh,"source":piece})
		parts.append({"node":pivot,"role":part.role,"phase":part.get("phase",0.0),"name":part.name})
	var cargo: Array = []
	var drill: Node3D = null
	if art == "harvester":
		# Shared ore / drill meshes keep every miner in the same render batches.
		if cargo_mesh==null:
			var shard := CraftMesh.new()
			shard.prism([Vector2(-.10,0),Vector2(-.12,.20),Vector2(.02,.39),Vector2(.12,.17),Vector2(.09,0)],.19,Vector3.ZERO,Color("6595ad"),false)
			cargo_mesh=shard.mesh()
		for i in range(12):
			var piece = _geometry_node(pose_only)
			piece.mesh = cargo_mesh
			var origin: Vector3=recipe.get("cargo_origin",Vector3(-1.2,1.55,-.32))
			var spacing: Vector3=recipe.get("cargo_step",Vector3(.35,.15,.48))
			piece.position = (origin+Vector3((i%4)*spacing.x,(i/8)*spacing.y,((i/4)%2)*spacing.z))*float(recipe.model_scale)
			piece.scale = Vector3.ONE * float(recipe.model_scale)
			body.add_child(piece)
			piece.visible = false
			cargo.append(piece)
		drill = Node3D.new()
		drill.name="HarvestDrill"
		drill.position = (recipe.get("drill_pos",Vector3(1.18,.48,0)) as Vector3)*float(recipe.model_scale)
		body.add_child(drill)
		if cutter_mesh==null:
			var cutter := CraftMesh.new()
			cutter.cylinder(Vector3.ZERO,.23,.85,Vector3.BACK,STEEL,8)
			for i in range(6):
				var angle: float = i * TAU / 6.0
				cutter.box(Vector3(cos(angle)*.23,sin(angle)*.23,0),Vector3(.12,.12,.9),WOOD)
			cutter_mesh=cutter.mesh()
		var tool = _geometry_node(pose_only)
		tool.mesh = cutter_mesh
		tool.scale=Vector3.ONE*float(recipe.model_scale)
		drill.add_child(tool)
		meshes.append(tool)

	return {"cargo":cargo,"drill":drill,"root":root,"body":body,"turret":turret,"muzzle":muzzle,"meshes":meshes,"border_meshes":border_meshes,"dimensions":recipe.dimensions,"height":recipe.dimensions.y,"footprint":Vector2(recipe.dimensions.x,recipe.dimensions.z),"volumetric":true,"faction":faction,"art":art,"team":team,"clock":0.0,"recoil":Vector3.ZERO,"model_scale":recipe.get("model_scale",1.0),"recoil_distance":recipe.get("recoil_distance",.085),"parts":parts,"aircraft":spec.get("domain","air" if art in AIRCRAFT_ART else "ground")=="air","infantry":art in INFANTRY_ART,"faction_color":faction_color(faction),"player_color":player_color(team),"emblem":faction_emblem(faction),"design":recipe.get("design",recipe.get("design_signature",faction+"_"+art)),"smoke_ports":recipe.get("smoke_ports",[]).duplicate()}


static func _recipe(spec: Dictionary, kind: String, team: int) -> Dictionary:
	var faction: String=art_faction(spec)
	var key: String=kind+":"+faction+":"+str(spec.art)+":"+str(team)
	var wall_mask: int = int(spec.get("wall_mask", 0)) if kind == "building" and str(spec.get("role", "")) in ["wall", "barricade"] else 0
	if wall_mask != 0: key += ":connections:" + str(wall_mask)
	if recipes.has(key):return recipes[key]
	if wall_mask != 0:
		var isolated: Dictionary = spec.duplicate()
		isolated.erase("wall_mask")
		var connected: Dictionary = WALL_CONNECTIONS.connected_recipe(_recipe(isolated, kind, team), wall_mask, faction, team)
		recipes[key] = connected
		return connected
	var recipe: Dictionary
	if kind=="unit" and str(spec.art)=="creator_hand":
		recipe=load("res://scripts/creator_hand_models.gd").recipe_meta(team)
	elif str(spec.art) in ["naval_transport", "naval_frigate", "naval_signature", "shipyard"]:
		recipe = load("res://scripts/naval_models.gd").make(CraftMesh.new(), str(spec.art), faction, team, kind)
	elif faction in EXPANSION_FACTIONS:
		# Each expansion owns its geometry, including matching production roles.
		# Runtime loading keeps CraftMesh available without a preload cycle.
		var author = load("res://scripts/"+faction+"_models.gd")
		recipe=author.make(CraftMesh.new(),str(spec.art),team,kind)
	elif kind=="building":recipe=_building(faction,str(spec.art),team)
	elif str(spec.art) in AIRCRAFT_ART:recipe=_aircraft(faction,str(spec.art),team)
	elif str(spec.art) in ["scout","aa","artillery","advanced"]:recipe=_special_vehicle(faction,str(spec.art),team)
	else:recipe=_faction_vehicle(faction,str(spec.art),team)
	var factor: float=bake_scale(spec,kind)
	if kind=="unit":
		recipe.body_mesh=_bake_mesh_scale(recipe.body_mesh,factor)
		if recipe.has("body_border_mesh"):
			recipe.body_border_mesh=_bake_mesh_scale(recipe.body_border_mesh,factor)
		if recipe.has("turret_mesh"):
			recipe.turret_mesh=_bake_mesh_scale(recipe.turret_mesh,factor)
			if recipe.has("turret_border_mesh"):
				recipe.turret_border_mesh=_bake_mesh_scale(recipe.turret_border_mesh,factor)
			recipe.turret_pos=(recipe.turret_pos as Vector3)*factor
		if recipe.has("muzzle_pos"):recipe.muzzle_pos=(recipe.muzzle_pos as Vector3)*factor
		for part in recipe.get("parts",[]):
			part.mesh=_bake_mesh_scale(part.mesh,factor)
			if part.has("border_mesh"):part.border_mesh=_bake_mesh_scale(part.border_mesh,factor)
			part.pivot=(part.pivot as Vector3)*factor
		recipe.dimensions=(recipe.dimensions as Vector3)*factor
	recipe.model_scale=factor
	recipe.recoil_distance=.085*factor
	if kind=="unit":
		for field in ["body_mesh","turret_mesh","body_border_mesh","turret_border_mesh"]:
			if recipe.has(field):quality_sources[recipe[field].get_instance_id()]=faction+"/"+str(spec.art)+"/"+field
	recipes[key]=recipe
	return recipe


static func bake_scale(spec: Dictionary, kind: String) -> float:
	if str(spec.get("art", "")).begins_with("naval_"): return 1.0
	if kind!="unit":return 1.0
	# These recipes are authored at their final tabletop dimensions.
	if art_faction(spec) in EXPANSION_FACTIONS:return 1.0
	var art: String=str(spec.art)
	var hammer: bool=art_faction(spec)=="rivet"
	if art=="tank":return .51 if hammer else .60
	if art=="harvester":return .64 if hammer else .75
	if art=="assault":return .60
	return .70 if art=="advanced" else .75


static func _bake_mesh_scale(source: ArrayMesh, factor: float) -> ArrayMesh:
	var result:=ArrayMesh.new()
	for surface in range(source.get_surface_count()):
		var arrays: Array=source.surface_get_arrays(surface)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		for i in range(vertices.size()):vertices[i]*=factor
		arrays[Mesh.ARRAY_VERTEX]=vertices
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		result.surface_set_material(surface,source.surface_get_material(surface))
	return result


static func muzzle_world(model: Dictionary) -> Vector3:
	var marker: Marker3D=model.get("muzzle")
	return marker.global_position if is_instance_valid(marker) else model.root.global_position+Vector3(0,model.height*.55,0)


static func muzzle_offset(spec: Dictionary, kind: String, team: int, body_heading: float, turret_heading: float, visual_recoil: float = 0.0) -> Vector3:
	# Headings are absolute simulation degrees: zero=+X, positive toward +Z.
	# No node/instance is required, so a projectile retains its launch point
	# after its firing unit has been destroyed or its turret has turned away.
	if not supports(spec,kind):return Vector3(0,.9,0)
	var recipe: Dictionary=_recipe(spec,kind,team)
	var body_basis := Basis(Vector3.UP,-deg_to_rad(body_heading))
	if not recipe.has("turret_mesh"):
		return body_basis*(recipe.muzzle_pos as Vector3) if recipe.has("muzzle_pos") else body_basis*Vector3(0,float(recipe.dimensions.y)*.55,0)
	var gun_basis := Basis(Vector3.UP,-deg_to_rad(turret_heading))
	return body_basis*(recipe.turret_pos as Vector3)+gun_basis*((recipe.muzzle_pos as Vector3)+Vector3(visual_recoil,0,0))


static func update_model(model: Dictionary, e: Dictionary, delta: float) -> void:
	# Cosmetic reactions only. Root heading and independent turret aiming remain
	# under the renderer's control and never feed back into the simulation.
	model.clock=float(model.clock)+delta
	if model.art=="creator_hand":
		load("res://scripts/creator_hand_models.gd").update_pose(model,e)
		return
	var body: Node3D=model.body
	var moving: bool = e.get("state","") in ["move","returning"]
	if model.art=="harvester":
		var load_fraction:float=clampf(float(e.get("cargo",0))/float(model.get("cargo_capacity",500)),0,1)
		model.cargo_count=ceili(load_fraction*model.cargo.size())
	var animating:bool=moving or (model.aircraft and bool(e.get("airborne",true))) or float(e.get("hit_flash",0))>0.0 or float(e.get("attack_flash",0))>0.0 or (model.art=="harvester" and e.get("state","")=="harvest") or (model.infantry and model.art=="engineer" and e.get("state","") in ["repair","capture"])
	var was_animating:bool=bool(model.get("pose_active",true))
	model.pose_active=animating
	# Idle poses are already at rest. Reassigning identical transforms marks the
	# whole hierarchy dirty and needlessly uploads the same batched matrices.
	if not animating and not was_animating:return
	body.position.y = sin(float(model.clock)*12+float(e.get("id",0)))*.018 if moving else 0
	body.rotation.z = sin(float(model.clock)*10+float(e.get("id",0)))*.009 if moving else 0
	if model.infantry:
		body.position.y=absf(sin(float(model.clock)*10))* .025 if moving else 0.0
		for part in model.parts:
			var pivot: Node3D=part.node
			pivot.rotation.z=sin(float(model.clock)*10+float(part.phase))*.34 if moving else 0.0
		if model.art=="engineer" and e.get("state","") in ["repair","capture"]:
			body.rotation.z=sin(float(model.clock)*15)*.04
	if model.aircraft:
		body.position.y=sin(float(model.clock)*3+float(e.get("id",0)))*.065 if bool(e.get("airborne",true)) else 0.0
		body.rotation.x=sin(float(model.clock)*2)*.035 if moving else 0.0
		body.rotation.z=-.035 if moving else 0.0
	if model.art == "harvester":
		if e.get("state", "") == "harvest":
			body.position.y = sin(float(model.clock)*32)*.025
			body.rotation.z = sin(float(model.clock)*19)*.015
			model.drill.rotation.z += delta * 14
	var flash: float=float(e.get("hit_flash",0))
	body.position.z=sin(float(model.clock)*60)*.035 if flash>0 else 0
	if model.turret!=null:
		var attack: float=float(e.get("attack_flash",0))
		var gun: Node3D=model.meshes[1]
		gun.position.x=-float(model.recoil_distance)*minf(attack*4,1)


static func _window(mesh: CraftMesh, x: float, y: float, z: float, width: float = .5, height: float = .44) -> void:
	var side: float=signf(z)
	# The dark reveal remains visible behind a smaller pane and pale jambs.
	mesh.box(Vector3(x,y,z),Vector3(width+.07,height+.075,.075),INK,false)
	mesh.box(Vector3(x,y-.025,z+side*.044),Vector3(width*.80,height*.76,.025),GLASS.darkened(.30),false)
	mesh.box(Vector3(x-width*.32,y+height*.23,z+side*.062),Vector3(width*.28,height*.10,.014),GLASS.lightened(.14),false)
	for edge in [-1.0,1.0]:
		mesh.line(Vector3(x+edge*width*.49,y-height*.48,z+side*.065),Vector3(x+edge*width*.49,y+height*.48,z+side*.065),.017,KRAFT)
	mesh.line(Vector3(x-width*.50,y+height*.49,z+side*.061),Vector3(x+width*.5,y+height*.49,z+side*.061),.015,PAPER)
	mesh.box(Vector3(x,y-height*.52,z+side*.070),Vector3(width+.11,.07,.13),KRAFT)
	mesh.line(Vector3(x,y-height*.42,z+side*.061),Vector3(x,y+height*.40,z+side*.061),.011,WOOD)


static func _flag(mesh: CraftMesh, pos: Vector3, faction: String, accent: Color) -> void:
	mesh.line(pos,pos+Vector3(0,1.02,0),.025,INK)
	mesh.box(pos+Vector3(.35,.8,0),Vector3(.67,.39,.055),accent)
	mesh.badge(pos+Vector3(.34,.8,.045),faction,accent,Vector3.BACK,.12)
	mesh.cylinder(pos+Vector3(0,1.045,0),.055,.055,Vector3.UP,PAPER,6,false)


static func _facade(mesh: CraftMesh, width: float, depth: float, height: float, faction: String, accent: Color, factory: bool = false, barracks: bool = false) -> void:
	var front: float=depth*.5+.045
	var door_width: float=width*.63 if factory else width*.40 if barracks else .7
	var door_height: float=1.30 if factory else 1.00 if barracks else 1.13
	mesh.box(Vector3(0,door_height*.5+.18,front),Vector3(door_width+.15,door_height+.10,.07),INK,false)
	mesh.box(Vector3(0,door_height*.5+.17,front+.048),Vector3(door_width*.93,door_height*.95,.035),accent.darkened(.10))
	for side in [-1.0,1.0]:
		mesh.box(Vector3(side*(door_width*.5+.053),door_height*.5+.19,front+.055),Vector3(.08,door_height+.12,.105),KRAFT,false)
	mesh.box(Vector3(0,door_height+.24,front+.052),Vector3(door_width+.24,.09,.12),WOOD)
	if factory:
		for y in [.45,.69,.93,1.17,1.41]:mesh.line(Vector3(-door_width*.43,y,front+.078),Vector3(door_width*.43,y,front+.078),.012,INK)
		mesh.line(Vector3(-door_width*.42,.48,front+.085),Vector3(door_width*.12,.48,front+.085),.009,KRAFT)
	else:
		mesh.line(Vector3(0,.24,front+.078),Vector3(0,door_height+.11,front+.078),.013,INK)
		mesh.line(Vector3(-door_width*.29,.30,front+.08),Vector3(-door_width*.29,door_height*.75,front+.08),.010,KRAFT)
		mesh.cylinder(Vector3(.19,.76,front+.09),.037,.06,Vector3.BACK,INK,6,false)
	mesh.box(Vector3(0,.1,front+.24),Vector3(door_width+.24,.18,.49),KRAFT)
	var window_x: float=width*(.415 if factory else .32)
	var window_width: float=.30 if factory else .5
	_window(mesh,-window_x,height*.59,front,window_width)
	_window(mesh,window_x,height*.59,front,window_width)
	_window(mesh,-width*.24,height*.59,-front)
	_window(mesh,width*.24,height*.59,-front)
	for side in [-1.0,1.0]:
		# Side windows and buttresses have thickness, visible in a full orbit.
		for z in [-depth*.25,depth*.25]:
			var reveal_x: float=side*(width*.5+.036)
			mesh.box(Vector3(reveal_x,height*.6,z),Vector3(.072,.50,.61),INK,false)
			mesh.box(Vector3(reveal_x+side*.043,height*.59,z),Vector3(.024,.35,.43),GLASS.darkened(.30),false)
			mesh.box(Vector3(reveal_x+side*.060,height*.37,z),Vector3(.12,.075,.68),KRAFT)
			mesh.line(Vector3(reveal_x+side*.065,height*.39,z),Vector3(reveal_x+side*.065,height*.81,z),.012,WOOD)
			mesh.line(Vector3(reveal_x+side*.068,height*.81,z-.28),Vector3(reveal_x+side*.068,height*.81,z+.28),.012,PAPER)
		for z in [-depth*.43,depth*.43]:
			mesh.box(Vector3(side*(width*.5+.065),height*.48,z),Vector3(.19,height*.88,.19),KRAFT if faction=="rivet" else WOOD)
	mesh.badge(Vector3(0,height*.88,front+.03),faction,accent,Vector3.BACK,.23)
	mesh.badge(Vector3(0,height*.83,-front-.03),faction,accent,Vector3.FORWARD,.18)
	if faction=="kestrel":
		for side in [-1.0,1.0]:
			mesh.line(Vector3(side*width*.44,.26,front+.025),Vector3(side*width*.22,height*.72,front+.025),.028,WOOD)
	_wall_age(mesh,width,depth,height)


static func _wall_age(mesh: CraftMesh, width: float, depth: float, height: float) -> void:
	# Local rubbed corners and plinth dirt leave broad plaster areas quiet.
	# Every mark sits on its wall; these are construction wear, not free noise.
	for side in [-1.0,1.0]:
		var z: float=side*(depth*.5+.014)
		var normal:=Vector3(0,0,side)
		for corner in [-1.0,1.0]:
			var x: float=corner*width*.46
			mesh.face([Vector3(x,.27,z),Vector3(x-corner*.22,.28,z),Vector3(x-corner*.13,.39,z),Vector3(x-corner*.04,.43,z)],WOOD.lightened(.13),normal)
			mesh.line(Vector3(x,.45,z+side*.008),Vector3(x-corner*.025,.72,z+side*.008),.007,INK)
		# A short irregular settling crack, kept away from the openings.
		var x: float=width*.17*side
		mesh.line(Vector3(x,height*.89,z),Vector3(x+.065,height*.80,z),.006,INK)
		mesh.line(Vector3(x+.065,height*.80,z),Vector3(x+.040,height*.73,z),.006,INK)
		mesh.line(Vector3(-width*.44,.32,z),Vector3(-width*.25,.33,z),.009,INK)
		mesh.line(Vector3(width*.27,.32,z),Vector3(width*.44,.30,z),.007,INK)
		# A broken seam on the side suggests plaster over two large boards.
		var sx: float=side*(width*.5+.012)
		mesh.line(Vector3(sx,.42,-depth*.41),Vector3(sx,.45,-depth*.17),.007,INK)
		mesh.line(Vector3(sx,.45,depth*.10),Vector3(sx,.42,depth*.39),.007,INK)
		mesh.face([Vector3(sx,.26,depth*.39),Vector3(sx,.26,depth*.16),Vector3(sx,.36,depth*.25),Vector3(sx,.43,depth*.39)],WOOD.lightened(.12),Vector3(side,0,0))


static func player_color(team: int) -> Color:
	return PLAYER_COLORS[posmod(team,PLAYER_COLORS.size())]


static func _assembly_number(mesh: CraftMesh, center: Vector3, text: String, normal: Vector3, size: float=.15) -> void:
	var right: Vector3=Vector3.RIGHT if absf(normal.y)>.9 else Vector3.UP.cross(normal).normalized()
	var up: Vector3=normal.cross(right).normalized()
	var segments: Array=[[Vector2(-.5,1),Vector2(.5,1)],[Vector2(.5,1),Vector2(.5,0)],[Vector2(.5,0),Vector2(.5,-1)],[Vector2(-.5,-1),Vector2(.5,-1)],[Vector2(-.5,0),Vector2(-.5,-1)],[Vector2(-.5,1),Vector2(-.5,0)],[Vector2(-.5,0),Vector2(.5,0)]]
	var digits: Dictionary={"0":[0,1,2,3,4,5],"1":[1,2],"2":[0,1,6,4,3],"3":[0,1,6,2,3],"4":[5,6,1,2],"5":[0,5,6,2,3],"6":[0,5,6,2,3,4],"7":[0,1,2],"8":[0,1,2,3,4,5,6],"9":[0,1,2,3,5,6]}
	for i in range(text.length()):
		var origin: Vector3=center+right*(i-(text.length()-1)*.5)*size*1.65
		for index in digits.get(text[i],[]):
			var a: Vector2=segments[index][0]
			var b: Vector2=segments[index][1]
			mesh.line(origin+(right*a.x+up*a.y)*size,origin+(right*b.x+up*b.y)*size,.014,PAPER)


static func _new_track(mesh: CraftMesh, center: Vector3, length: float, breadth: float, height: float, wheels: int, square: bool, wheel_paint: Color) -> void:
	# New faction chassis belts: squared compression belts and arched lightweight
	# suspension share only this extrusion helper, not the former demo recipe.
	var half: float=length*.5
	var profile: Array=[Vector2(-half+.12,.06),Vector2(half-.12,.06),Vector2(half,.19),Vector2(half,height-.13),Vector2(half-.12,height),Vector2(-half+.12,height),Vector2(-half,height-.13),Vector2(-half,.19)] if square else [Vector2(-half+.28,.05),Vector2(half-.28,.05),Vector2(half-.08,.19),Vector2(half,height*.45),Vector2(half-.08,height*.78),Vector2(half-.28,height),Vector2(-half+.28,height),Vector2(-half+.08,height*.78),Vector2(-half,height*.45),Vector2(-half+.08,.19)]
	mesh.capture_shell=true
	mesh.prism(profile,breadth,center,INK if square else RUBBER)
	mesh.capture_shell=false
	var side: float=signf(center.z)
	for i in range(wheels):
		var x: float=lerpf(-half+.35,half-.35,float(i)/float(wheels-1))
		var radius: float=height*.29 if square else height*.36
		mesh.cylinder(center+Vector3(x,height*.49,side*(breadth*.5+.034)),radius,.075,Vector3.BACK,wheel_paint,10)
		mesh.cylinder(center+Vector3(x,height*.49,side*(breadth*.5+.075)),radius*.43,.028,Vector3.BACK,INK,8,false)
	for i in range(9 if square else 7):
		var x: float=lerpf(-half+.16,half-.16,float(i)/float(8 if square else 6))
		mesh.box(center+Vector3(x,height+.027,0),Vector3(.065,.045,breadth*.94),KRAFT,false)


static func _faction_vehicle(faction: String, art: String, team: int) -> Dictionary:
	if art=="tank":return _hammer_tank(team) if faction=="rivet" else _canon_tank(team)
	if art=="assault":return _hammer_siege(team)
	return _hammer_harvester(team) if faction=="rivet" else _canon_harvester(team)


static func _canon_tank(team: int) -> Dictionary:
	var owner: Color=player_color(team)
	var body:=CraftMesh.new()
	# Short wide engineering hull with separate arched shoulders. The hexagonal
	# deck, inclined glacis and light suspension form a new original chassis.
	for side in [-1.0,1.0]:
		_new_track(body,Vector3(0,0,side*1.10),3.30,.44,.76,4,false,KRAFT)
	body.capture_shell=true
	body.slab([Vector2(-1.44,-.83),Vector2(.95,-.83),Vector2(1.43,-.56),Vector2(1.43,.56),Vector2(.95,.83),Vector2(-1.44,.83)],.49,Vector3(0,.74,0),KRAFT)
	body.prism([Vector2(-1.42,.72),Vector2(-1.26,1.17),Vector2(.63,1.17),Vector2(1.40,.85),Vector2(1.40,.72)],1.52,Vector3.ZERO,BLUE)
	for side in [-1.0,1.0]:
		body.prism([Vector2(-1.50,.70),Vector2(-1.47,.99),Vector2(-1.19,1.25),Vector2(.62,1.25),Vector2(1.43,.96),Vector2(1.52,.70)],.42,Vector3(0,0,side*.99),PAPER,true,{1:BLUE,2:BLUE,3:BLUE})
		body.box(Vector3(-.97,1.27,side*.96),Vector3(.76,.10,.43),BLUE)
	body.capture_shell=false
	for side in [-1.0,1.0]:
		# Clear folded diagonal braces and maintenance fasteners.
		body.line(Vector3(-1.11,.88,side*1.23),Vector3(-.65,1.19,side*1.23),.038,KRAFT)
		body.line(Vector3(.58,1.18,side*1.22),Vector3(1.14,.88,side*1.22),.038,KRAFT)
		body.badge(Vector3(-.11,1.00,side*1.23),"kestrel",owner,Vector3(0,0,side),.20)
		_assembly_number(body,Vector3(.71,.94,side*1.24),"07",Vector3(0,0,side),.10)
		body.box(Vector3(1.41,.70,side*.61),Vector3(.13,.18,.20),PAPER)
	body.box(Vector3(-.89,1.24,0),Vector3(.69,.065,.63),INK,false)
	for x in [-1.13,-.95,-.77,-.59]:body.line(Vector3(x,1.29,-.28),Vector3(x,1.29,.28),.016,KRAFT)
	body.badge(Vector3(.91,1.155,0),"kestrel",owner,Vector3.UP,.26)
	var turret:=CraftMesh.new()
	turret.capture_shell=true
	# Standard sloped hexagonal gunhouse, ring and a narrow rectangular mantlet.
	turret.cylinder(Vector3(0,.04,0),.65,.13,Vector3.UP,INK,12)
	turret.slab([Vector2(-.76,-.48),Vector2(-.48,-.72),Vector2(.48,-.62),Vector2(.73,-.37),Vector2(.73,.37),Vector2(.48,.62),Vector2(-.48,.72),Vector2(-.76,.48)],.45,Vector3(0,.30,0),BLUE)
	turret.slab([Vector2(-.56,-.42),Vector2(-.34,-.53),Vector2(.38,-.48),Vector2(.56,-.28),Vector2(.56,.28),Vector2(.38,.48),Vector2(-.34,.53),Vector2(-.56,.42)],.16,Vector3(0,.58,0),PAPER)
	turret.box(Vector3(.62,.33,0),Vector3(.31,.31,.47),BLUE)
	turret.cylinder(Vector3(1.28,.34,0),.095,1.37,Vector3.RIGHT,STEEL,10)
	turret.cylinder(Vector3(1.94,.34,0),.13,.19,Vector3.RIGHT,INK,8)
	turret.capture_shell=false
	turret.cylinder(Vector3(-.29,.73,0),.23,.13,Vector3.UP,BLUE,10)
	turret.badge(Vector3(-.08,.685,0),"kestrel",owner,Vector3.UP,.25)
	for side in [-1.0,1.0]:turret.badge(Vector3(-.14,.33,side*.73),"kestrel",owner,Vector3(0,0,side),.17)
	turret.line(Vector3(-.49,.67,-.40),Vector3(-.49,1.16,-.40),.018,INK)
	return {"body_mesh":body.mesh(),"body_border_mesh":body.shell_mesh(),"turret_mesh":turret.mesh(),"turret_border_mesh":turret.shell_mesh(),"turret_pos":Vector3(.11,1.16,0),"muzzle_pos":Vector3(2.05,.34,0),"dimensions":Vector3(3.35,2.35,2.78),"design":"canon_engineering_07"}


static func _hammer_tank(team: int) -> Dictionary:
	var owner: Color=player_color(team)
	var body:=CraftMesh.new()
	# Low compression hull: broad squared tracks, rear-biased mass, layered wedge
	# armour and a transverse front press beam instead of the canon shoulders.
	for side in [-1.0,1.0]:
		_new_track(body,Vector3(-.03,0,side*1.22),3.92,.69,.88,6,true,KRAFT)
	body.capture_shell=true
	body.box(Vector3(-.12,.54,0),Vector3(3.56,.60,2.02),INK)
	body.prism([Vector2(-1.75,.66),Vector2(-1.66,1.12),Vector2(-.82,1.25),Vector2(.37,1.10),Vector2(1.68,.76),Vector2(1.68,.54)],2.16,Vector3.ZERO,RED)
	for layer in range(3):
		body.prism([Vector2(.34,.94+layer*.10),Vector2(.74,1.05+layer*.10),Vector2(1.81,.70+layer*.10),Vector2(1.81,.55+layer*.10)],2.24-layer*.10,Vector3.ZERO,RED if layer%2==0 else KRAFT)
	body.box(Vector3(1.73,.59,0),Vector3(.38,.37,3.04),RED.darkened(.18))
	for side in [-1.0,1.0]:
		body.box(Vector3(-.28,1.02,side*1.28),Vector3(2.84,.18,.62),RED)
		for x in [-1.17,-.24,.70]:body.box(Vector3(x,.83,side*1.56),Vector3(.64,.27,.10),RED)
		body.box(Vector3(1.52,.83,side*1.00),Vector3(.45,.48,.19),KRAFT)
	body.capture_shell=false
	for side in [-1.0,1.0]:
		body.line(Vector3(1.27,1.19,side*1.03),Vector3(1.80,.81,side*1.03),.055,INK)
		body.line(Vector3(-1.41,1.11,side*1.26),Vector3(-1.41,1.42,side*1.26),.035,KRAFT)
		body.badge(Vector3(-.22,.90,side*1.64),"rivet",owner,Vector3(0,0,side),.19)
		body.box(Vector3(1.90,.61,side*1.06),Vector3(.08,.12,.23),PAPER)
	body.box(Vector3(-1.19,1.30,0),Vector3(.59,.10,1.58),KRAFT)
	for z in [-.59,-.30,0.0,.30,.59]:body.line(Vector3(-1.46,1.36,z),Vector3(-.92,1.36,z),.019,INK)
	body.badge(Vector3(1.13,1.24,0),"rivet",owner,Vector3.UP,.29)
	var turret:=CraftMesh.new()
	turret.capture_shell=true
	# Wide shallow rectangular block and thick clamped mantlet give the gun
	# a different outline and weight distribution from the standard gunhouse.
	turret.box(Vector3(-.16,.23,0),Vector3(1.92,.46,1.88),RED)
	turret.box(Vector3(-.18,.51,0),Vector3(2.03,.13,1.98),KRAFT)
	turret.box(Vector3(-.23,.61,0),Vector3(1.54,.09,1.56),RED)
	turret.box(Vector3(.82,.22,0),Vector3(.47,.50,.84),INK)
	turret.box(Vector3(.93,.22,0),Vector3(.20,.45,.67),RED)
	turret.cylinder(Vector3(1.67,.23,0),.18,1.67,Vector3.RIGHT,KRAFT,10)
	turret.cylinder(Vector3(2.48,.23,0),.25,.25,Vector3.RIGHT,INK,10)
	turret.capture_shell=false
	for x in [1.04,1.30,1.56]:turret.cylinder(Vector3(x,.23,0),.225,.07,Vector3.RIGHT,RED.darkened(.12),10)
	for side in [-1.0,1.0]:
		turret.box(Vector3(-.20,.23,side*1.00),Vector3(1.10,.23,.13),RED.darkened(.20))
		turret.badge(Vector3(-.23,.24,side*1.09),"rivet",owner,Vector3(0,0,side),.20)
		turret.box(Vector3(.37,.52,side*.88),Vector3(.20,.20,.21),INK)
	turret.badge(Vector3(-.28,.68,0),"rivet",owner,Vector3.UP,.31)
	_assembly_number(turret,Vector3(.48,.69,0),"14",Vector3.UP,.12)
	return {"body_mesh":body.mesh(),"body_border_mesh":body.shell_mesh(),"turret_mesh":turret.mesh(),"turret_border_mesh":turret.shell_mesh(),"turret_pos":Vector3(-.29,1.12,0),"muzzle_pos":Vector3(2.625,.23,0),"dimensions":Vector3(4.10,1.87,3.33),"design":"hammer_compression_14"}


static func _hammer_siege(team: int) -> Dictionary:
	var owner: Color=player_color(team)
	var body:=CraftMesh.new()
	for side in [-1.0,1.0]:_new_track(body,Vector3(-.14,0,side*1.22),4.35,.73,.88,7,true,KRAFT)
	body.capture_shell=true
	body.box(Vector3(-.28,.69,0),Vector3(3.63,.57,2.04),INK)
	body.prism([Vector2(-2.12,.62),Vector2(-1.89,1.36),Vector2(-.67,1.36),Vector2(-.19,.98),Vector2(1.78,.76),Vector2(1.78,.56)],2.13,Vector3.ZERO,RED)
	for side in [-1.0,1.0]:
		body.box(Vector3(-.42,1.03,side*1.33),Vector3(3.46,.19,.56),RED)
		body.box(Vector3(1.60,.54,side*1.29),Vector3(.34,.45,.72),KRAFT)
		body.box(Vector3(-1.72,1.22,side*1.39),Vector3(.67,.72,.27),RED.darkened(.15))
	body.capture_shell=false
	for side in [-1.0,1.0]:
		body.badge(Vector3(-.32,.94,side*1.64),"rivet",owner,Vector3(0,0,side),.23)
		body.line(Vector3(.55,.94,side*1.26),Vector3(1.61,.49,side*1.26),.07,INK)
	body.badge(Vector3(-1.30,1.395,0),"rivet",owner,Vector3.UP,.31)
	# Articulated siege cradle, oversized breech and side recoil cylinders.
	var gun:=CraftMesh.new()
	gun.capture_shell=true
	gun.box(Vector3(-.43,.29,0),Vector3(1.33,.58,1.32),RED)
	gun.box(Vector3(-.63,.68,0),Vector3(.89,.18,1.45),KRAFT)
	gun.box(Vector3(.10,.25,0),Vector3(.51,.70,.76),INK)
	gun.cylinder(Vector3(1.46,.41,0),.21,2.85,Vector3.RIGHT,KRAFT,12)
	gun.cylinder(Vector3(2.85,.41,0),.30,.33,Vector3.RIGHT,RED.darkened(.22),12)
	for side in [-1.0,1.0]:
		gun.cylinder(Vector3(.79,.10,side*.49),.12,1.36,Vector3.RIGHT,STEEL,8)
		gun.box(Vector3(-.20,.40,side*.73),Vector3(.71,.56,.21),RED)
	gun.capture_shell=false
	gun.badge(Vector3(-.52,.81,0),"rivet",owner,Vector3.UP,.28)
	for side in [-1.0,1.0]:gun.badge(Vector3(-.23,.37,side*.88),"rivet",owner,Vector3(0,0,side),.19)
	return {"body_mesh":body.mesh(),"body_border_mesh":body.shell_mesh(),"turret_mesh":gun.mesh(),"turret_border_mesh":gun.shell_mesh(),"turret_pos":Vector3(-.08,1.12,0),"muzzle_pos":Vector3(3.04,.41,0),"dimensions":Vector3(4.50,2.05,3.47),"design":"hammer_siege_cradle"}


static func _canon_harvester(team: int) -> Dictionary:
	var owner: Color=player_color(team)
	var mesh:=CraftMesh.new()
	mesh.capture_shell=true
	mesh.box(Vector3(0,.48,0),Vector3(3.40,.27,1.51),INK)
	for side in [-1.0,1.0]:
		for x in [-1.12,1.07]:
			mesh.cylinder(Vector3(x,.42,side*.87),.39,.25,Vector3.BACK,RUBBER,10)
			mesh.cylinder(Vector3(x,.42,side*1.02),.22,.06,Vector3.BACK,KRAFT,10)
	# Light sloped cabin and segmented collection trough with tidy braced sides.
	mesh.prism([Vector2(.30,.62),Vector2(.40,1.72),Vector2(.92,1.86),Vector2(1.64,1.38),Vector2(1.70,.62)],1.49,Vector3.ZERO,PAPER,true,{1:BLUE,2:BLUE,3:BLUE})
	mesh.box(Vector3(-.64,.86,0),Vector3(1.85,.18,1.73),KRAFT)
	for side in [-1.0,1.0]:
		mesh.prism([Vector2(-1.61,.86),Vector2(-1.61,1.42),Vector2(-.12,1.42),Vector2(.28,1.10),Vector2(.28,.86)],.13,Vector3(0,0,side*.82),BLUE)
		mesh.box(Vector3(-.66,1.49,side*.85),Vector3(1.94,.10,.18),PAPER)
	for x in [-1.60,.20]:mesh.box(Vector3(x,1.17,0),Vector3(.12,.58,1.73),KRAFT)
	mesh.capture_shell=false
	for side in [-1.0,1.0]:
		mesh.box(Vector3(.88,1.41,side*.785),Vector3(.59,.36,.03),GLASS)
		mesh.line(Vector3(-1.36,.98,side*.91),Vector3(-.95,1.39,side*.91),.037,KRAFT)
		mesh.line(Vector3(-.18,.98,side*.91),Vector3(-.59,1.39,side*.91),.037,KRAFT)
		mesh.badge(Vector3(-.70,1.22,side*.915),"kestrel",owner,Vector3(0,0,side),.23)
		mesh.box(Vector3(1.66,.78,side*.57),Vector3(.11,.20,.23),PAPER)
	mesh.badge(Vector3(.87,1.87,0),"kestrel",owner,Vector3.UP,.25)
	_assembly_number(mesh,Vector3(.43,1.20,.79),"21",Vector3.BACK,.10)
	mesh.box(Vector3(-.64,.975,0),Vector3(1.66,.035,1.45),INK,false)
	return {"body_mesh":mesh.mesh(),"body_border_mesh":mesh.shell_mesh(),"dimensions":Vector3(3.60,2.0,2.17),"cargo_origin":Vector3(-1.32,1.05,-.38),"cargo_step":Vector3(.34,.12,.38),"drill_pos":Vector3(1.53,.43,0),"design":"canon_supply_trough"}


static func _hammer_harvester(team: int) -> Dictionary:
	var owner: Color=player_color(team)
	var mesh:=CraftMesh.new()
	# Heavy crawler extractor: the low tracked spine, offset cabin, articulated
	# cutter boom and high braced hopper replace the canon road-truck outline.
	for side in [-1.0,1.0]:_new_track(mesh,Vector3(-.09,0,side*1.03),3.85,.60,.82,6,true,KRAFT)
	mesh.capture_shell=true
	mesh.box(Vector3(-.08,.69,0),Vector3(3.47,.36,1.98),INK)
	mesh.box(Vector3(.97,1.12,-.50),Vector3(1.20,.86,.92),RED)
	mesh.box(Vector3(.97,1.62,-.50),Vector3(1.32,.16,1.09),KRAFT)
	mesh.box(Vector3(-.75,1.06,0),Vector3(2.04,.18,1.72),KRAFT)
	for side in [-1.0,1.0]:
		mesh.prism([Vector2(-1.77,1.04),Vector2(-1.77,2.10),Vector2(-.40,2.10),Vector2(.29,1.44),Vector2(.29,1.04)],.18,Vector3(0,0,side*.80),RED)
		mesh.box(Vector3(-1.06,2.16,side*.84),Vector3(1.57,.15,.25),KRAFT)
		mesh.box(Vector3(-.10,.96,side*1.11),Vector3(3.21,.18,.32),RED)
		for x in [-1.50,-.88]:mesh.box(Vector3(x,1.67,side*.98),Vector3(.16,1.03,.18),INK)
	mesh.box(Vector3(-1.80,1.56,0),Vector3(.18,1.04,1.78),RED)
	mesh.capture_shell=false
	mesh.box(Vector3(1.03,1.28,-1.0),Vector3(.76,.30,.04),GLASS)
	mesh.badge(Vector3(1.0,1.745,-.50),"rivet",owner,Vector3.UP,.28)
	for side in [-1.0,1.0]:mesh.badge(Vector3(-.16,.91,side*1.29),"rivet",owner,Vector3(0,0,side),.21)
	# Offset reinforced loading arm, its hydraulic brace and a wide front scoop.
	mesh.line(Vector3(.57,1.04,.47),Vector3(.79,2.34,.47),.13,RED)
	mesh.line(Vector3(.79,2.34,.47),Vector3(1.94,1.12,.47),.13,RED)
	mesh.line(Vector3(.32,1.08,.47),Vector3(1.00,2.07,.47),.075,STEEL)
	mesh.line(Vector3(.84,2.12,.47),Vector3(1.72,1.13,.47),.075,STEEL)
	mesh.cylinder(Vector3(.79,2.34,.47),.20,.28,Vector3.BACK,KRAFT,10)
	mesh.prism([Vector2(-.29,0),Vector2(-.30,.35),Vector2(.19,.14),Vector2(.30,0)],1.82,Vector3(1.90,.49,0),KRAFT)
	mesh.box(Vector3(-.77,1.18,0),Vector3(1.82,.03,1.53),INK,false)
	return {"body_mesh":mesh.mesh(),"body_border_mesh":mesh.shell_mesh(),"dimensions":Vector3(4.50,2.63,2.84),"cargo_origin":Vector3(-1.56,1.33,-.43),"cargo_step":Vector3(.37,.17,.43),"drill_pos":Vector3(2.02,.55,0),"design":"hammer_crawler_extractor"}


static func _aircraft(faction: String, art: String, team: int) -> Dictionary:
	if art=="bomber":return _hammer_bomber(team)
	if art=="attacker":return _canon_attacker(team)
	return _hammer_fighter(team) if faction=="rivet" else _canon_fighter(team)


static func _special_vehicle(faction: String, art: String, team: int) -> Dictionary:
	if art=="scout":return _hammer_scout(team) if faction=="rivet" else _canon_scout(team)
	if art=="aa":return _hammer_aa(team) if faction=="rivet" else _canon_aa(team)
	if art=="advanced":return _hammer_advanced(team) if faction=="rivet" else _canon_advanced(team)
	return _canon_artillery(team)


static func _vehicle_recipe(body: CraftMesh, gun: CraftMesh, gun_pos: Vector3, muzzle: Vector3, dimensions: Vector3) -> Dictionary:
	return {"body_mesh":body.mesh(),"body_border_mesh":body.shell_mesh(),"turret_mesh":gun.mesh(),"turret_border_mesh":gun.shell_mesh(),"turret_pos":gun_pos,"muzzle_pos":muzzle,"dimensions":dimensions}


static func _canon_scout(team: int) -> Dictionary:
	var owner: Color=player_color(team)
	var body:=CraftMesh.new()
	body.capture_shell=true
	body.box(Vector3(0,.45,0),Vector3(2.55,.19,1.22),INK)
	for side in [-1.0,1.0]:
		for x in [-.86,.81]:body.cylinder(Vector3(x,.35,side*.73),.32,.22,Vector3.BACK,RUBBER,10)
	body.prism([Vector2(-1.14,.49),Vector2(-.92,.95),Vector2(.28,1.02),Vector2(1.21,.61),Vector2(1.21,.49)],1.12,Vector3.ZERO,BLUE)
	# Open rear roll frame and arched fenders distinguish a light patrol jeep.
	for side in [-1.0,1.0]:
		body.prism([Vector2(-1.23,.56),Vector2(-1.05,.87),Vector2(-.55,.87),Vector2(-.38,.56)],.21,Vector3(0,0,side*.75),PAPER)
		body.prism([Vector2(.44,.56),Vector2(.62,.87),Vector2(1.05,.87),Vector2(1.25,.56)],.21,Vector3(0,0,side*.75),PAPER)
	body.capture_shell=false
	for side in [-1.0,1.0]:
		for x in [-.86,.81]:body.cylinder(Vector3(x,.35,side*.86),.17,.045,Vector3.BACK,KRAFT,8)
		body.line(Vector3(-.86,.97,side*.44),Vector3(-.86,1.43,side*.44),.035,KRAFT)
		body.badge(Vector3(-.10,.75,side*.60),"kestrel",owner,Vector3(0,0,side),.18)
	body.line(Vector3(-.86,1.43,-.44),Vector3(-.86,1.43,.44),.035,BLUE)
	body.badge(Vector3(.82,.87,0),"kestrel",owner,Vector3.UP,.22)
	var gun:=CraftMesh.new()
	gun.box(Vector3(0,.07,0),Vector3(.39,.23,.37),BLUE)
	gun.cylinder(Vector3(.51,.10,0),.055,.89,Vector3.RIGHT,INK,6)
	return _vehicle_recipe(body,gun,Vector3(-.22,1.08,0),Vector3(.98,.10,0),Vector3(2.63,1.55,1.86))


static func _hammer_scout(team: int) -> Dictionary:
	var owner: Color=player_color(team)
	var body:=CraftMesh.new()
	body.capture_shell=true
	for side in [-1.0,1.0]:
		for x in [-.99,0.0,.99]:body.cylinder(Vector3(x,.35,side*.81),.34,.29,Vector3.BACK,INK,8)
	body.prism([Vector2(-1.25,.44),Vector2(-1.13,1.04),Vector2(-.46,1.12),Vector2(1.29,.67),Vector2(1.29,.44)],1.43,Vector3.ZERO,RED)
	body.box(Vector3(1.21,.59,0),Vector3(.22,.28,1.73),KRAFT)
	for side in [-1.0,1.0]:body.box(Vector3(-.08,.84,side*.84),Vector3(2.32,.18,.21),RED.darkened(.18))
	body.capture_shell=false
	for side in [-1.0,1.0]:
		for x in [-.99,0.0,.99]:body.cylinder(Vector3(x,.35,side*.985),.15,.045,Vector3.BACK,KRAFT,8)
		body.badge(Vector3(-.39,.87,side*.97),"rivet",owner,Vector3(0,0,side),.19)
	body.badge(Vector3(.87,.865,0),"rivet",owner,Vector3.UP,.22)
	body.box(Vector3(-.87,1.30,0),Vector3(.31,.47,.31),INK)
	body.box(Vector3(-.87,1.60,0),Vector3(.49,.16,.44),RED)
	var gun:=CraftMesh.new()
	gun.box(Vector3(0,.12,0),Vector3(.72,.35,.58),RED)
	gun.cylinder(Vector3(.56,.17,0),.08,.85,Vector3.RIGHT,STEEL,8)
	return _vehicle_recipe(body,gun,Vector3(.10,.93,0),Vector3(1.03,.17,0),Vector3(2.72,1.78,2.05))


static func _canon_aa(team: int) -> Dictionary:
	var owner: Color=player_color(team)
	var body:=CraftMesh.new()
	body.capture_shell=true
	for side in [-1.0,1.0]:
		for x in [-1.04,.98]:body.cylinder(Vector3(x,.41,side*.82),.37,.27,Vector3.BACK,RUBBER,10)
	body.slab([Vector2(-1.39,-.66),Vector2(.88,-.66),Vector2(1.40,-.44),Vector2(1.40,.44),Vector2(.88,.66),Vector2(-1.39,.66)],.40,Vector3(0,.71,0),PAPER)
	body.box(Vector3(.82,1.02,0),Vector3(.87,.39,1.13),BLUE)
	body.capture_shell=false
	for side in [-1.0,1.0]:
		body.line(Vector3(-1.19,.87,side*.73),Vector3(-.91,1.20,side*.73),.032,KRAFT)
		body.badge(Vector3(.32,.83,side*.74),"kestrel",owner,Vector3(0,0,side),.19)
	body.badge(Vector3(.82,1.255,0),"kestrel",owner,Vector3.UP,.25)
	# Fine upright radar mast above a light, exposed twin-missile mounting.
	body.line(Vector3(-1.02,.91,0),Vector3(-1.02,2.42,0),.042,KRAFT)
	body.box(Vector3(-1.02,2.45,0),Vector3(.17,.42,.81),BLUE)
	body.box(Vector3(-.915,2.45,0),Vector3(.06,.30,.65),GLASS)
	var gun:=CraftMesh.new()
	gun.box(Vector3(-.12,.12,0),Vector3(.47,.28,.75),BLUE)
	for side in [-1.0,1.0]:
		gun.cylinder(Vector3(.50,.29,side*.35),.11,1.32,Vector3.RIGHT,PAPER,8)
		gun.prism([Vector2(-.13,0),Vector2(.16,.12),Vector2(-.13,.24)],.15,Vector3(1.15,.17,side*.35),BLUE)
	return _vehicle_recipe(body,gun,Vector3(-.12,1.14,0),Vector3(1.35,.29,0),Vector3(2.92,2.80,2.01))


static func _hammer_aa(team: int) -> Dictionary:
	var owner: Color=player_color(team)
	var body:=CraftMesh.new()
	for side in [-1.0,1.0]:_new_track(body,Vector3(0,0,side*.97),3.09,.49,.79,5,true,KRAFT)
	body.capture_shell=true
	body.prism([Vector2(-1.36,.43),Vector2(-1.27,.97),Vector2(-.64,1.10),Vector2(.54,1.02),Vector2(1.40,.65),Vector2(1.40,.43)],1.68,Vector3.ZERO,RED)
	for side in [-1.0,1.0]:body.box(Vector3(0,.97,side*1.02),Vector3(2.65,.17,.39),RED)
	body.box(Vector3(1.38,.57,0),Vector3(.26,.28,2.04),INK)
	body.capture_shell=false
	for side in [-1.0,1.0]:body.badge(Vector3(-.48,.83,side*1.26),"rivet",owner,Vector3(0,0,side),.20)
	body.badge(Vector3(1.03,.90,0),"rivet",owner,Vector3.UP,.23)
	var gun:=CraftMesh.new()
	gun.capture_shell=true
	# Broad low four-cell missile box; no copy of the canon radar tower.
	gun.box(Vector3(-.12,.29,0),Vector3(1.51,.57,1.37),INK)
	for side in [-1.0,1.0]:
		gun.box(Vector3(.03,.45,side*.42),Vector3(1.68,.81,.60),RED)
		for y in [.24,.65]:
			gun.cylinder(Vector3(.91,y,side*.42),.15,.15,Vector3.RIGHT,KRAFT,8)
			gun.cylinder(Vector3(1.01,y,side*.42),.10,.10,Vector3.RIGHT,INK,8)
	gun.capture_shell=false
	gun.badge(Vector3(-.37,.91,0),"rivet",owner,Vector3.UP,.25)
	for side in [-1.0,1.0]:gun.badge(Vector3(-.31,.45,side*.76),"rivet",owner,Vector3(0,0,side),.21)
	return _vehicle_recipe(body,gun,Vector3(-.27,1.02,0),Vector3(1.08,.45,0),Vector3(3.15,2.01,2.58))


static func _canon_advanced(team: int) -> Dictionary:
	var owner: Color=player_color(team)
	var body:=CraftMesh.new()
	body.capture_shell=true
	for side in [-1.0,1.0]:
		for x in [-1.15,1.09]:body.cylinder(Vector3(x,.44,side*.90),.39,.28,Vector3.BACK,RUBBER,10)
	body.prism([Vector2(-1.48,.57),Vector2(-1.12,.98),Vector2(.68,1.10),Vector2(1.50,.72),Vector2(1.50,.57)],1.45,Vector3.ZERO,BLUE)
	for side in [-1.0,1.0]:body.box(Vector3(-.65,1.18,side*.54),Vector3(.99,.27,.41),PAPER)
	body.capture_shell=false
	for side in [-1.0,1.0]:
		body.badge(Vector3(-.68,1.365,side*.54),"kestrel",owner,Vector3.UP,.18)
		body.badge(Vector3(.27,.80,side*.78),"kestrel",owner,Vector3(0,0,side),.19)
	var gun:=CraftMesh.new()
	gun.capture_shell=true
	gun.box(Vector3(-.46,.17,0),Vector3(.92,.38,.98),BLUE)
	for side in [-1.0,1.0]:
		gun.box(Vector3(1.05,.45,side*.28),Vector3(2.97,.10,.10),STEEL)
		for x in [.13,.61,1.09,1.57]:gun.box(Vector3(x,.27,side*.28),Vector3(.12,.49,.18),KRAFT)
	gun.capture_shell=false
	gun.line(Vector3(-.49,.17,-.40),Vector3(-.21,.47,-.40),.035,PAPER)
	gun.badge(Vector3(-.43,.415,0),"kestrel",owner,Vector3.UP,.22)
	for side in [-1.0,1.0]:gun.badge(Vector3(-.50,.18,side*.52),"kestrel",owner,Vector3(0,0,side),.15)
	return _vehicle_recipe(body,gun,Vector3(.15,1.09,0),Vector3(2.60,.45,0),Vector3(3.15,1.86,2.16))


static func _hammer_advanced(team: int) -> Dictionary:
	var owner: Color=player_color(team)
	var body:=CraftMesh.new()
	for side in [-1.0,1.0]:_new_track(body,Vector3(-.13,0,side*1.03),3.74,.58,.81,6,true,KRAFT)
	body.capture_shell=true
	body.box(Vector3(-.26,.74,0),Vector3(3.36,.43,1.75),RED)
	for side in [-1.0,1.0]:
		body.box(Vector3(-.24,1.01,side*1.07),Vector3(3.11,.20,.44),RED.darkened(.12))
		body.box(Vector3(-1.27,1.32,side*.70),Vector3(.69,.53,.31),KRAFT)
	body.box(Vector3(1.39,.65,0),Vector3(.43,.36,2.12),INK)
	body.capture_shell=false
	for side in [-1.0,1.0]:body.badge(Vector3(-.39,.84,side*1.37),"rivet",owner,Vector3(0,0,side),.21)
	body.badge(Vector3(-1.28,1.62,0),"rivet",owner,Vector3.UP,.28)
	var gun:=CraftMesh.new()
	gun.capture_shell=true
	# Low massive cradle and a single thick accelerator with broad wound rings.
	gun.box(Vector3(-.35,.25,0),Vector3(1.35,.48,1.53),RED)
	gun.box(Vector3(-.30,.55,0),Vector3(1.62,.15,1.65),KRAFT)
	gun.cylinder(Vector3(1.10,.34,0),.27,2.83,Vector3.RIGHT,INK,12)
	for x in [.10,.49,.88,1.27,1.66]:gun.cylinder(Vector3(x,.34,0),.41,.16,Vector3.RIGHT,RED,12)
	gun.cylinder(Vector3(2.49,.34,0),.32,.18,Vector3.RIGHT,KRAFT,12)
	gun.capture_shell=false
	gun.badge(Vector3(-.52,.66,0),"rivet",owner,Vector3.UP,.25)
	for side in [-1.0,1.0]:gun.badge(Vector3(-.55,.26,side*.85),"rivet",owner,Vector3(0,0,side),.18)
	return _vehicle_recipe(body,gun,Vector3(.04,1.0,0),Vector3(2.60,.34,0),Vector3(3.92,1.80,2.79))


static func _canon_artillery(team: int) -> Dictionary:
	var owner: Color=player_color(team)
	var body:=CraftMesh.new()
	for side in [-1.0,1.0]:_new_track(body,Vector3(-.17,0,side*.89),3.23,.39,.71,4,false,KRAFT)
	body.capture_shell=true
	body.prism([Vector2(-1.43,.57),Vector2(-1.16,1.05),Vector2(.82,1.15),Vector2(1.35,.72),Vector2(1.35,.57)],1.50,Vector3.ZERO,PAPER)
	for side in [-1.0,1.0]:body.box(Vector3(-.20,1.02,side*.90),Vector3(2.43,.18,.27),BLUE)
	body.capture_shell=false
	for side in [-1.0,1.0]:body.badge(Vector3(-.17,.91,side*1.10),"kestrel",owner,Vector3(0,0,side),.19)
	body.badge(Vector3(-1.10,1.20,0),"kestrel",owner,Vector3.UP,.25)
	var gun:=CraftMesh.new()
	gun.prism([Vector2(-.76,0),Vector2(-.54,.66),Vector2(.37,.55),Vector2(.65,.26),Vector2(.65,0)],1.09,Vector3.ZERO,BLUE)
	gun.cylinder(Vector3(1.44,.37,0),.105,2.19,Vector3.RIGHT,STEEL,10)
	gun.cylinder(Vector3(2.53,.37,0),.155,.19,Vector3.RIGHT,INK,8)
	gun.badge(Vector3(-.20,.59,0),"kestrel",owner,Vector3.UP,.21)
	for side in [-1.0,1.0]:gun.badge(Vector3(-.25,.25,side*.57),"kestrel",owner,Vector3(0,0,side),.16)
	return _vehicle_recipe(body,gun,Vector3(.03,1.12,0),Vector3(2.65,.37,0),Vector3(3.28,1.95,2.25))


static func _air_recipe(mesh: CraftMesh, muzzle: Vector3, dimensions: Vector3) -> Dictionary:
	return {"body_mesh":mesh.mesh(),"body_border_mesh":mesh.shell_mesh(),"muzzle_pos":muzzle,"dimensions":dimensions}


static func _canon_fighter(team: int) -> Dictionary:
	var owner: Color=player_color(team)
	var mesh:=CraftMesh.new()
	mesh.capture_shell=true
	# A narrow pointed nose, one precise swept wing and a high single tail.
	mesh.prism([Vector2(-1.65,.25),Vector2(-1.48,.53),Vector2(.62,.62),Vector2(1.91,.29),Vector2(.52,.16),Vector2(-1.48,.16)],.46,Vector3.ZERO,BLUE)
	mesh.slab([Vector2(-1.07,-2.17),Vector2(-.65,-2.17),Vector2(.70,-.24),Vector2(.70,.24),Vector2(-.65,2.17),Vector2(-1.07,2.17),Vector2(-.36,.23),Vector2(-.36,-.23)],.12,Vector3(0,.31,0),BLUE)
	mesh.slab([Vector2(-.43,-.91),Vector2(-.07,-.91),Vector2(.35,-.12),Vector2(.35,.12),Vector2(-.07,.91),Vector2(-.43,.91)],.11,Vector3(-1.31,.54,0),PAPER)
	mesh.prism([Vector2(-.45,0),Vector2(-.39,.90),Vector2(-.07,.88),Vector2(.33,0)],.115,Vector3(-1.21,.53,0),BLUE)
	mesh.cylinder(Vector3(-1.56,.31,0),.20,.30,Vector3.RIGHT,INK,10)
	mesh.cylinder(Vector3(-1.73,.31,0),.13,.035,Vector3.RIGHT,KRAFT,10)
	mesh.capture_shell=false
	mesh.prism([Vector2(-.25,0),Vector2(-.09,.26),Vector2(.37,.14),Vector2(.49,0)],.36,Vector3(.48,.62,0),GLASS)
	for side in [-1.0,1.0]:
		mesh.badge(Vector3(-.67,.425,side*1.40),"kestrel",owner,Vector3.UP,.25)
	mesh.badge(Vector3(-1.40,1.12,.083),"kestrel",owner,Vector3.BACK,.18)
	_assembly_number(mesh,Vector3(.51,.671,0),"09",Vector3.UP,.08)
	return _air_recipe(mesh,Vector3(1.92,.30,0),Vector3(3.90,1.55,4.40))


static func _hammer_fighter(team: int) -> Dictionary:
	var owner: Color=player_color(team)
	var mesh:=CraftMesh.new()
	mesh.capture_shell=true
	# Short blunt armoured centre with two broad exposed propulsion nacelles.
	mesh.slab([Vector2(-1.17,-.55),Vector2(.91,-.55),Vector2(1.40,-.36),Vector2(1.40,.36),Vector2(.91,.55),Vector2(-1.17,.55)],.40,Vector3(0,.42,0),RED)
	mesh.box(Vector3(.83,.54,0),Vector3(.76,.31,.75),RED)
	for side in [-1.0,1.0]:
		mesh.cylinder(Vector3(-.17,.30,side*.68),.29,2.62,Vector3.RIGHT,INK,10)
		mesh.cylinder(Vector3(-1.49,.30,side*.68),.32,.18,Vector3.RIGHT,KRAFT,10)
		mesh.cylinder(Vector3(1.11,.30,side*.68),.30,.15,Vector3.RIGHT,RED,10)
	mesh.slab([Vector2(-.87,-2.15),Vector2(.33,-2.15),Vector2(.81,-1.43),Vector2(.82,-.44),Vector2(.82,.44),Vector2(.81,1.43),Vector2(.33,2.15),Vector2(-.87,2.15),Vector2(-.62,.49),Vector2(-.62,-.49)],.20,Vector3(0,.43,0),RED)
	for side in [-1.0,1.0]:
		mesh.prism([Vector2(-.48,0),Vector2(-.36,.57),Vector2(.05,.57),Vector2(.31,0)],.16,Vector3(-1.0,.55,side*.69),RED)
	mesh.box(Vector3(-1.15,.59,0),Vector3(.58,.13,1.95),KRAFT)
	mesh.capture_shell=false
	mesh.box(Vector3(.56,.765,0),Vector3(.68,.15,.62),GLASS)
	for side in [-1.0,1.0]:mesh.badge(Vector3(-.27,.585,side*1.38),"rivet",owner,Vector3.UP,.29)
	mesh.badge(Vector3(-1.02,.90,.80),"rivet",owner,Vector3.BACK,.17)
	return _air_recipe(mesh,Vector3(1.43,.39,0),Vector3(3.14,1.29,4.40))


static func _canon_attacker(team: int) -> Dictionary:
	var owner: Color=player_color(team)
	var mesh:=CraftMesh.new()
	mesh.capture_shell=true
	# A twin-boom aircraft: separated tail rails, a central short attack cabin
	# and straight stub wings differ from the interceptor's swept single fuselage.
	mesh.prism([Vector2(-.81,.30),Vector2(-.54,.67),Vector2(.45,.74),Vector2(1.67,.35),Vector2(.35,.15),Vector2(-.69,.15)],.64,Vector3.ZERO,BLUE)
	for side in [-1.0,1.0]:
		mesh.prism([Vector2(-1.95,.26),Vector2(-1.87,.54),Vector2(.81,.52),Vector2(1.21,.34),Vector2(.77,.18),Vector2(-1.88,.18)],.29,Vector3(0,0,side*.84),BLUE)
		mesh.cylinder(Vector3(.22,.34,side*.84),.24,1.32,Vector3.RIGHT,INK,10)
		mesh.cylinder(Vector3(-.44,.34,side*.84),.27,.13,Vector3.RIGHT,KRAFT,10)
		mesh.prism([Vector2(-.35,0),Vector2(-.28,.58),Vector2(.03,.58),Vector2(.22,0)],.13,Vector3(-1.72,.49,side*.84),BLUE)
	mesh.slab([Vector2(-.72,-2.08),Vector2(.39,-2.08),Vector2(.72,-.31),Vector2(.72,.31),Vector2(.39,2.08),Vector2(-.72,2.08)],.17,Vector3(0,.39,0),BLUE)
	mesh.box(Vector3(-1.81,.56,0),Vector3(.39,.12,2.05),PAPER)
	for side in [-1.0,1.0]:
		mesh.cylinder(Vector3(.14,.12,side*1.41),.13,1.12,Vector3.RIGHT,KRAFT,8)
	mesh.capture_shell=false
	mesh.prism([Vector2(-.33,0),Vector2(-.10,.24),Vector2(.44,.13),Vector2(.53,0)],.47,Vector3(.30,.75,0),GLASS)
	for side in [-1.0,1.0]:mesh.badge(Vector3(-.10,.51,side*1.51),"kestrel",owner,Vector3.UP,.29)
	mesh.badge(Vector3(-1.73,.81,1.0),"kestrel",owner,Vector3.BACK,.17)
	return _air_recipe(mesh,Vector3(1.71,.33,0),Vector3(3.75,1.29,4.30))


static func _hammer_bomber(team: int) -> Dictionary:
	var owner: Color=player_color(team)
	var mesh:=CraftMesh.new()
	mesh.capture_shell=true
	# A thick straight-wing heavy bomber with an actual box-shaped bomb bay.
	# Its two broad propulsion nacelles and transverse mass are independent of the interceptor.
	mesh.prism([Vector2(-1.91,.31),Vector2(-1.68,.79),Vector2(.72,.90),Vector2(1.94,.58),Vector2(2.07,.36),Vector2(1.62,.18),Vector2(-1.81,.18)],.99,Vector3.ZERO,RED)
	mesh.box(Vector3(.18,.13,0),Vector3(1.85,.29,.87),INK)
	for side in [-1.0,1.0]:
		mesh.box(Vector3(.18,-.035,side*.31),Vector3(1.84,.08,.27),KRAFT)
	mesh.slab([Vector2(-.90,-2.87),Vector2(.50,-2.87),Vector2(.85,-.47),Vector2(.85,.47),Vector2(.50,2.87),Vector2(-.90,2.87)],.27,Vector3(0,.49,0),RED)
	for side in [-1.0,1.0]:
		for station in [1.30]:
			mesh.cylinder(Vector3(.12,.38,side*station),.45,2.35,Vector3.RIGHT,INK,12)
			mesh.cylinder(Vector3(-1.07,.38,side*station),.48,.19,Vector3.RIGHT,KRAFT,12)
			mesh.cylinder(Vector3(1.31,.38,side*station),.47,.18,Vector3.RIGHT,RED,12)
	mesh.box(Vector3(-1.49,.78,0),Vector3(.68,.21,2.74),RED)
	for side in [-1.0,1.0]:mesh.prism([Vector2(-.49,0),Vector2(-.42,.73),Vector2(.06,.73),Vector2(.34,0)],.20,Vector3(-1.56,.79,side*1.13),RED)
	mesh.capture_shell=false
	mesh.box(Vector3(1.36,.87,0),Vector3(.70,.20,.64),GLASS)
	for side in [-1.0,1.0]:mesh.badge(Vector3(-.05,.69,side*2.36),"rivet",owner,Vector3.UP,.36)
	mesh.badge(Vector3(-1.67,1.16,1.25),"rivet",owner,Vector3.BACK,.23)
	return _air_recipe(mesh,Vector3(.29,-.05,0),Vector3(4.28,1.70,5.85))


static func _arch(mesh: CraftMesh, center: Vector3, width: float, height: float, depth: float, paint: Color, heavy: bool=false) -> void:
	# A real opening between columns; the dark interior is not a painted door.
	var thickness: float=.36 if heavy else .24
	for side in [-1.0,1.0]:
		mesh.box(center+Vector3(side*(width*.5-thickness*.5),height*.44,0),Vector3(thickness,height*.88,depth),KRAFT)
		mesh.box(center+Vector3(side*(width*.5-thickness*.5),height*.48,depth*.52),Vector3(thickness*.72,height*.68,.10),paint)
	mesh.prism([Vector2(-width*.5,0),Vector2(-width*.5,.38),Vector2(-width*.33,.59),Vector2(width*.33,.59),Vector2(width*.5,.38),Vector2(width*.5,0),Vector2(width*.33,.21),Vector2(-width*.33,.21)],depth,center+Vector3(0,height*.88,0),paint)


static func _dish(mesh: CraftMesh, center: Vector3, radius: float, paint: Color) -> void:
	mesh.cylinder(center-Vector3(0,.37,0),.12,.72,Vector3.UP,INK,8)
	mesh.cylinder(center,radius,.14,Vector3(0,.65,1),paint,14)
	mesh.cylinder(center+Vector3(0,.09,.14),radius*.73,.11,Vector3(0,.65,1),PAPER,14)
	mesh.line(center+Vector3(-radius*.7,.05,.16),center+Vector3(0,.23,.55),.035,INK)
	mesh.line(center+Vector3(radius*.7,.05,.16),center+Vector3(0,.23,.55),.035,INK)
	mesh.cylinder(center+Vector3(0,.23,.57),.09,.12,Vector3.BACK,INK,6)


static func _building(faction: String, art: String, team: int) -> Dictionary:
	var mesh := CraftMesh.new()
	if art not in ["wall","barricade"]:
		var builder = load("res://scripts/faction_building_models.gd")
		return builder.make(mesh,faction,art,team)
	var paint: Color=RED if faction=="rivet" else BLUE
	var owner: Color=player_color(team)
	if art=="wall":
		mesh.prism([Vector2(-.48,0),Vector2(-.48,.76),Vector2(-.34,.96),Vector2(.34,.96),Vector2(.48,.76),Vector2(.48,0)],.85,Vector3.ZERO,KRAFT)
		mesh.box(Vector3(0,.97,0),Vector3(1.0,.15,.95),paint)
	else:
		for z in [-.31,.31]:
			mesh.line(Vector3(-.43,.08,z),Vector3(.43,.94,z),.065,WOOD)
			mesh.line(Vector3(.43,.08,z),Vector3(-.43,.94,z),.065,WOOD)
		mesh.line(Vector3(0,.50,-.47),Vector3(0,.50,.47),.075,paint)
	mesh.badge(Vector3(0,.60,.48),faction,owner,Vector3.BACK,.15)
	mesh.badge(Vector3(0,1.06 if art=="wall" else .55,0),faction,owner,Vector3.UP,.16)
	return {"body_mesh":mesh.mesh(),"dimensions":Vector3(1.08,1.15,1.08)}
