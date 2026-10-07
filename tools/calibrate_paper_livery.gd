extends SceneTree
const ROOT="res://assets/cards/paper_infantry_revision/"
const FIXED={"kestrel":Color("9eaaa8"),"rivet":Color("99705a"),"iron":Color("b39b67"),"sky":Color("e9e5dc")}
func _initialize()->void:
	var offsets:=RegEx.new();offsets.compile('offset="[0-9.]+%"')
	var entries:Array=[]
	for file in DirAccess.get_files_at(ROOT):
		if not file.ends_with(".svg") or file.ends_with("_portrait.svg"):continue
		var original:String=FileAccess.get_file_as_string(ROOT+file)
		var faction:String=file.get_slice("_",0)
		var fixed:Color=FIXED[faction]
		var low:float=0.0
		var high:float=75.0
		var ratios:=Vector2.ZERO
		for iteration in range(8):
			var offset:float=(low+high)*.5
			var source:String=offsets.sub(original,'offset="%.4f%%"'%offset,true)
			var pixels:=Image.new()
			assert(pixels.load_svg_from_string(source)==OK)
			var total:int=0;var owner:int=0;var secondary:int=0
			for y in pixels.get_height():
				for x in pixels.get_width():
					var c:Color=pixels.get_pixel(x,y)
					if c.a<.5:continue
					total+=1
					if minf(c.r,c.b)-c.g>.3:owner+=1
					if absf(c.r-fixed.r)+absf(c.g-fixed.g)+absf(c.b-fixed.b)<.08:secondary+=1
			ratios=Vector2(float(owner)/total,float(secondary)/total)
			if ratios.x<=.46 and ratios.y>=.33:low=offset
			else:high=offset
		var result:String=offsets.sub(original,'offset="%.4f%%"'%low,true)
		var output:=FileAccess.open(ROOT+file,FileAccess.WRITE);output.store_string(result);output.close()
		if file.ends_with("_idle_0.svg"):
			var portrait:=FileAccess.open(ROOT+file.replace("_idle_0.svg","_portrait.svg"),FileAccess.WRITE)
			portrait.store_string(result.replace("#ff00ff","#95b0ae"));portrait.close()
		entries.append({"file":file,"owner_stop":low})
	var report:=FileAccess.open("res://artifacts/rts_revision/paper_livery_authored_stops.json",FileAccess.WRITE);report.store_string(JSON.stringify(entries,"  "))
	print("PAPER_LIVERY_CALIBRATED ",entries.size())
	quit()
