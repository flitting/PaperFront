extends SceneTree
func _init() -> void:
	var f:=FileAccess.open("res://artifacts/linux/GODOT_LICENSE.txt",FileAccess.WRITE)
	f.store_string(Engine.get_license_text())
	var credits:=FileAccess.open("res://artifacts/linux/GODOT_THIRD_PARTY.json",FileAccess.WRITE)
	credits.store_string(JSON.stringify({"copyright":Engine.get_copyright_info(),"licenses":Engine.get_license_info()},"  "))
	quit()
