extends SceneTree

## Derive cut meshes from the same rasterized alpha used by Godot's SVG loader.
func _initialize() -> void:
	var contours: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/cards/contours.json"))
	var delta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/rules.json"))
	var count: int = 0
	for spec: String in delta.units:
		if delta.units[spec].get("armor_class", "") != "infantry": continue
		for pose: String in ["idle","move","combat","hit","death"]:
			for lod: int in range(3):
				var key: String = "%s_%s_%d" % [spec,pose,lod]
				var path: String = "res://assets/cards/paper_infantry_revision/"+key+".svg"
				var image := Image.new()
				if image.load_svg_from_string(FileAccess.get_file_as_string(path)) != OK:
					push_error("Cannot rasterize: "+path); quit(1); return
				var bitmap := BitMap.new()
				bitmap.create_from_image_alpha(image,.35)
				bitmap.grow_mask(1,Rect2i(Vector2i.ZERO,image.get_size()))
				var polygons: Array[PackedVector2Array] = bitmap.opaque_to_polygons(Rect2i(Vector2i.ZERO,image.get_size()),1.1)
				var outline: PackedVector2Array = PackedVector2Array()
				var largest: float = 0.0
				for polygon: PackedVector2Array in polygons:
					var area: float = 0.0
					for i in range(polygon.size()): area += polygon[i].cross(polygon[(i+1)%polygon.size()])
					if absf(area)>largest: largest=absf(area); outline=polygon
				if outline.is_empty() or Geometry2D.triangulate_polygon(outline).is_empty():
					push_error("Invalid contour: "+path); quit(1); return
				var points: Array = []
				for point: Vector2 in outline: points.append([point.x,point.y])
				contours[key] = {"width":image.get_width(),"height":image.get_height(),"outline":points,"path":path}
				count += 1
				if lod==0:
					var action: String = "attack" if pose=="combat" else pose
					var alias: Dictionary = contours[key].duplicate(true)
					alias.path = delta.units[spec].animations[action]
					contours[spec+"_"+action] = alias
	var path: String = "res://assets/cards/contours.json"
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	file.store_string(JSON.stringify(contours))
	file.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(path+".tmp"),ProjectSettings.globalize_path(path))
	print("Registered expanded infantry cut contours: ",count," plus live action aliases")
	quit()
