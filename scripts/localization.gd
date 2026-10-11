extends RefCounted
class_name PaperLocalization

## Chinese source text remains in rules and saves. Godot translates native
## controls at presentation time, including messages formatted by simulation.
const EnglishTranslation = preload("res://scripts/english_translation.gd")
const SUPPORTED_LANGUAGES: Array[String] = ["en", "zh_CN"]
static var _english: Translation
static var _language: String = "en"

static func initialize(locale: String = "en") -> void:
	if _english == null:
		_english = EnglishTranslation.new()
		_english.set_locale("en")
		TranslationServer.add_translation(_english)
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree != null and not tree.root.tree_exiting.is_connected(shutdown):
			tree.root.tree_exiting.connect(shutdown)
	set_language(locale)

static func set_language(locale: String) -> void:
	_language = "zh_CN" if locale.begins_with("zh") else "en"
	if _english == null:
		initialize(_language)
		return
	# The engine fallback locale is English. Remove that catalog while Chinese
	# is active so untranslated dynamic source messages remain Chinese.
	if _language == "zh_CN":
		TranslationServer.remove_translation(_english)
	else:
		TranslationServer.add_translation(_english)
	TranslationServer.set_locale(_language)

static func language() -> String:
	return _language

static func text(source: String) -> String:
	if _english == null:
		initialize()
	if _language == "zh_CN":
		return source
	return str(_english.get_message(source))

static func shutdown() -> void:
	# Release scripted Translation callbacks before the engine tears down
	# GDScript; otherwise Godot can request a translation during shutdown.
	if _english != null:
		TranslationServer.remove_translation(_english)
		_english = null
