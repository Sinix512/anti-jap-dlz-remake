extends SceneTree
func _initialize() -> void:
	var failures := 0
	var paths: Array[String] = []
	collect_scripts("res://scripts",paths)
	for path in paths:
		var script = load(path)
		if script == null or not script.can_instantiate():
			push_error("SCRIPT_CHECK_FAIL " + path)
			failures += 1
	print("SCRIPT_CHECK failures=",failures)
	quit(failures)

func collect_scripts(directory: String, paths: Array[String]) -> void:
	for file in DirAccess.get_files_at(directory):
		if file.ends_with(".gd"): paths.append(directory+"/"+file)
	for folder in DirAccess.get_directories_at(directory): collect_scripts(directory+"/"+folder,paths)
