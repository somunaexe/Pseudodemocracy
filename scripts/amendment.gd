class_name Amendment

static func validate_words(old_words: Array, new_texts: Array) -> String:
	if old_words.size() != new_texts.size():
		return "Expected %d words but got %d." % [old_words.size(), new_texts.size()]
		
	var one_word := RegEx.create_from_string("^[\\p{L}\\p{N}%+\\-−±×'’.,:]+$")
	for i in old_words.size():
		var word = old_words[i]
		var new_text: String = new_texts[i]
		if not word.amendable:
			if word.text != new_text:
				return "Word %d ('%s') is fixed and can't change." % [i + 1, word.text]
			continue
		new_text = new_text.strip_edges()
		if new_text.is_empty():
			return "Word %d can't be blank." % (i + 1)
		if one_word.search(new_text) == null:
			return "Word %d must be a single word (letters, numbers or simple symbols)." % (i + 1)
	return ""