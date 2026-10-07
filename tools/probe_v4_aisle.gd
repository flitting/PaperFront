extends SceneTree
func _initialize() -> void:
	for faction in ["iron","sky"]:
		var r=VolumeModels._recipe({"faction":faction,"art":"refinery","size":5},"building",0)
		var points:PackedVector3Array=r.body_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for x in [-1.2,0.0,1.2]:
			for y in [.25,1.1,2.4]:
				for i in range(0,points.size(),3):
					var hit=Geometry3D.segment_intersects_triangle(Vector3(x,y,0),Vector3(x,y,4),points[i],points[i+1],points[i+2])
					if hit!=null:
						print(faction," probe=",Vector2(x,y)," hit=",hit," tri=",[points[i],points[i+1],points[i+2]])
						break
	quit()
