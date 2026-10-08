# Keeps each room as one file, <CODE>.json, in a directory. A save writes a temporary file and renames it over the old one,
# so a crash in the middle leaves either the old room or the new one, never half of each.
# The interface (shared with MemoryStore): save(code, text) -> bool, remove(code), load_all() -> Array of texts.
# Paths may be absolute or user:// (the default).

var directory: String


func _init(dir: String) -> void:
	directory = dir.trim_suffix("/")
	DirAccess.make_dir_recursive_absolute(directory)


func save(code: String, text: String) -> bool:
	if not _is_code(code):
		return false
	var final_path: String = "%s/%s.json" % [directory, code]
	var temp_path: String = final_path + ".tmp"
	var file: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error("can't write %s (error %d)" % [temp_path, FileAccess.get_open_error()])
		return false
	file.store_string(text)
	file.flush()
	file.close()
	if DirAccess.rename_absolute(temp_path, final_path) != OK:
		push_error("can't move %s into place" % temp_path)
		return false
	return true


func remove(code: String) -> void:
	if _is_code(code):
		DirAccess.remove_absolute("%s/%s.json" % [directory, code])


func load_all() -> Array:
	var texts: Array = []
	var dir: DirAccess = DirAccess.open(directory)
	if dir == null:
		return texts
	for file_name in dir.get_files():
		if file_name.ends_with(".json") and _is_code(file_name.trim_suffix(".json")):
			var file: FileAccess = FileAccess.open("%s/%s" % [directory, file_name], FileAccess.READ)
			if file != null:
				texts.append(file.get_as_text())
	return texts


# Only the codes the server itself makes: capital letters, so a file name can never point somewhere else.
func _is_code(code: String) -> bool:
	if code.is_empty() or code.length() > 8:
		return false
	for i in code.length():
		var c: int = code.unicode_at(i)
		if c < 65 or c > 90:
			return false
	return true
