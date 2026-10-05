extends SceneTree
var failures:Array[String]=[]
var checks:int=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value and failures.size()<20:failures.append(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	if not ClassDB.class_exists("PaperFrontRenderBatch"):push_error("Render batch extension missing");quit(1);return
	var mesh:=BoxMesh.new()
	for colored in [false,true]:
		var fast:=PaperWorld.new();var reference:=PaperWorld.new()
		reference.native_kernels_enabled=false
		root.add_child(fast);root.add_child(reference)
		var a:Dictionary=fast._batch_descriptor(mesh,null,false,colored)
		var b:Dictionary=reference._batch_descriptor(mesh,null,false,colored)
		var counts:Array[int]=[0,1,7,8,9,33,5,0,5,65,9,9,0]
		for frame in range(counts.size()):
			var count:int=counts[frame]
			# Cross the sparse/bulk boundary, reuse hidden slots, and switch both
			# the native queue and the upload API while the same resources live.
			fast.native_batches_enabled=frame not in [5,6]
			fast.native_bulk_buffers_enabled=frame not in [2,9]
			for world in [fast,reference]:
				world._uploaded_transforms=0;world._uploaded_colors=0;world._begin_batches()
			var expected:Array[Transform3D]=[]
			var colors:Array[Color]=[]
			for i in range(count):
				var basis:=Basis.from_euler(Vector3(i*.13,-i*.073,i*.21)).scaled(Vector3(.2+i*.01,-.5 if i%3==0 else 1.4,2.0))
				var transform:=Transform3D(basis,Vector3(i*1.5-13,i*.07,5-i*.23))
				var color:=Color(.23+i*.005,.7,.31,fmod(i*.13,1.0))
				expected.append(transform);colors.append(color)
				fast._append_batch(a,transform,color if colored else null)
				reference._append_batch(b,transform,color if colored else null)
			fast._flush_batches();reference._flush_batches()
			check(fast._batch_count(a)==count and reference._batch_count(b)==count,"ordered submission count")
			check(fast._batch_transforms(a)==expected,"native submissions preserve exact matrix order")
			check(not colored or fast._batch_colors(a)==colors,"native submissions preserve every color and alpha")
			check(a.multi.visible_instance_count==count and a.node.visible==(count>0),"visible count and empty-batch visibility")
			check(a.multi.instance_count==b.multi.instance_count,"capacity growth matches the existing renderer")
			if frame==11:check(fast._uploaded_transforms==0 and fast._uploaded_colors==0,"stationary buffers are not uploaded again")
			if DisplayServer.get_name()!="headless":
				for i in range(count):
					check(a.multi.get_instance_transform(i).is_equal_approx(expected[i]),"actual MultiMesh matrix matches the input, including mirrored nonuniform basis")
					check(a.multi.get_instance_transform(i).is_equal_approx(b.multi.get_instance_transform(i)),"bulk and original setter uploads agree")
					if colored:check(a.multi.get_instance_color(i).is_equal_approx(colors[i]) and a.multi.get_instance_color(i).is_equal_approx(b.multi.get_instance_color(i)),"actual MultiMesh color/alpha matches original setters")
		fast.free();reference.free()
	print("NATIVE_RENDER_BATCH ",JSON.stringify({"checks":checks,"rendered":DisplayServer.get_name()!="headless","failures":failures}))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
