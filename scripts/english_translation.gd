extends Translation

## Native Label/Button/Popup/Tab controls call this for their current source
## text. Exact phrases and printf templates support live gameplay messages
## without changing simulation data or serialised Chinese identifiers.
const CATALOGS: Array[String] = ["res://data/localization/en_content.json", "res://data/localization/en_ui.json", "res://data/localization/en_runtime.json"]
var _messages: Dictionary = {}
var _phrases: Dictionary = {}
var _templates: Array[Dictionary] = []
var _cache: Dictionary = {}
var _format_pattern: RegEx
var _han_pattern: RegEx

func _init() -> void:
	_format_pattern = RegEx.new()
	_format_pattern.compile("%(?:[-+0 #]*[0-9]*(?:\\.[0-9]+)?[sdfgeExXo]|%)|\\{[a-zA-Z_][a-zA-Z_0-9]*\\}")
	_han_pattern = RegEx.new()
	_han_pattern.compile("[\\x{3400}-\\x{9fff}]")
	for path: String in CATALOGS:
		if not FileAccess.file_exists(path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			_messages.merge(parsed, true)
	for raw_source: Variant in _messages:
		var source: String = str(raw_source)
		if source.is_empty():
			continue
		var formats: Array[RegExMatch] = _format_pattern.search_all(source)
		var has_format: bool = false
		for format: RegExMatch in formats:
			if format.get_string() != "%%": has_format = true
		if has_format:
			var expression: String = "(?s)^"
			var cursor: int = 0
			var tokens: Array[String] = []
			for format: RegExMatch in formats:
				expression += _escape_regex(source.substr(cursor, format.get_start() - cursor))
				var token: String = format.get_string()
				if token == "%%": expression += "%"
				elif token.ends_with("s") or token.begins_with("{"): expression += "(.*?)"
				else: expression += "([-+0-9.,eE]+)"
				if token != "%%": tokens.append(token)
				cursor = format.get_end()
			expression += _escape_regex(source.substr(cursor)) + "$"
			var pattern := RegEx.new()
			if pattern.compile(expression) == OK:
				_templates.append({"pattern": pattern, "english": str(_messages[source]), "weight": source.length(), "tokens": tokens})
		else:
			var first: String = source.substr(0, 1)
			if not _phrases.has(first): _phrases[first] = []
			_phrases[first].append(source)
	for first: Variant in _phrases:
		_phrases[first].sort_custom(func(a: String, b: String): return a.length() > b.length())
	_templates.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.weight) > int(b.weight))

func _get_message(src_message: StringName, _context: StringName) -> StringName:
	return StringName(localize(str(src_message)))

func localize(source: String, depth: int = 0) -> String:
	if source.is_empty() or _han_pattern.search(source) == null:
		return source
	if _messages.has(source):
		return str(_messages[source])
	if _cache.has(source):
		return str(_cache[source])
	var result: String = source
	if depth < 6:
		for template: Dictionary in _templates:
			var matched: RegExMatch = template.pattern.search(source)
			if matched == null:
				continue
			var english: String = str(template.english)
			var output: String = ""
			var cursor: int = 0
			var group: int = 1
			for format: RegExMatch in _format_pattern.search_all(english):
				output += english.substr(cursor, format.get_start() - cursor)
				if format.get_string() == "%%": output += "%"
				else:
					var capture: int = group
					if format.get_string().begins_with("{"):
						capture = template.tokens.find(format.get_string()) + 1
					output += localize(matched.get_string(capture), depth + 1)
					group += 1
				cursor = format.get_end()
			result = output + english.substr(cursor)
			_cache_result(source, result)
			return result
	# Composite tooltips often join independent lines or small status labels.
	# Translate the longest known fragment at each position, preserving numbers,
	# keyboard shortcuts, BBCode, paths, and player-entered text verbatim.
	var parts: PackedStringArray = []
	for line: String in source.split("\n"):
		if line != source and depth < 6:
			parts.append(localize(line, depth + 1))
			continue
		var output: String = ""
		var cursor: int = 0
		while cursor < line.length():
			var found: bool = false
			for phrase: String in _phrases.get(line.substr(cursor, 1), []):
				if line.substr(cursor, phrase.length()) == phrase:
					output += str(_messages[phrase])
					cursor += phrase.length()
					found = true
					break
			if not found:
				output += line.substr(cursor, 1)
				cursor += 1
		parts.append(output)
	result = "\n".join(parts)
	_cache_result(source, result)
	return result

func _cache_result(source: String, result: String) -> void:
	if _cache.size() >= 4096:
		_cache.clear()
	_cache[source] = result

func _escape_regex(value: String) -> String:
	var output: String = ""
	for index in range(value.length()):
		var character: String = value.substr(index, 1)
		if character in ["\\", ".", "^", "$", "|", "?", "*", "+", "(", ")", "[", "]", "{", "}"]:
			output += "\\"
		output += character
	return output
