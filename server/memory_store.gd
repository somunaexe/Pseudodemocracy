# A store that keeps rooms in memory: for tests, and the default when a server is run without a data directory.
# The interface (shared with DiskStore): save(code, text) -> bool, remove(code), load_all() -> Array of texts.
var files: Dictionary = {}
var saves: int = 0


func save(code: String, text: String) -> bool:
	files[code] = text
	saves += 1
	return true


func remove(code: String) -> void:
	files.erase(code)


func load_all() -> Array:
	return files.values()
