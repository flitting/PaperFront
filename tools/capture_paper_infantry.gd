extends SceneTree

func _initialize() -> void:
	var result:=Image.create(1152,640,false,Image.FORMAT_RGBA8)
	result.fill(Color("e4d2ad"))
	var row:=0
	for faction in ["kestrel","rivet"]:
		var column:=0
		for art in ["rifle","anti","engineer"]:
			var texture: Texture2D=load("res://assets/cards/%s_%s_idle.svg" % [faction,art])
			var pixels:=texture.get_image()
			pixels.convert(Image.FORMAT_RGBA8)
			result.blend_rect(pixels,Rect2i(Vector2i.ZERO,pixels.get_size()),Vector2i(column*384,row*320))
			column+=1
		row+=1
	result.save_png("res://artifacts/faction_validation/paper_infantry_comparison.png")
	quit()
