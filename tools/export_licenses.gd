extends SceneTree
func _init() -> void:
	var output := "res://artifacts/linux"
	var arguments := OS.get_cmdline_user_args()
	for index in range(arguments.size() - 1):
		if arguments[index] == "--output": output = arguments[index + 1]
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output)) != OK:
		push_error("Cannot create license directory: " + output)
		quit(1)
		return
	var f:=FileAccess.open(output.path_join("GODOT_LICENSE.txt"),FileAccess.WRITE)
	if f == null:
		push_error("Cannot write Godot license")
		quit(1)
		return
	f.store_string(Engine.get_license_text())
	var credits:=FileAccess.open(output.path_join("GODOT_THIRD_PARTY.json"),FileAccess.WRITE)
	if credits == null:
		push_error("Cannot write Godot third party notices")
		quit(1)
		return
	credits.store_string(JSON.stringify({"copyright":Engine.get_copyright_info(),"licenses":Engine.get_license_info()},"  "))
	quit()
