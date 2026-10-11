extends SceneTree

const Localization = preload("res://scripts/localization.gd")
const Catalog = preload("res://scripts/wiki_catalog.gd")
const Loader = preload("res://scripts/rules_loader.gd")
const Settings = preload("res://scripts/paper_settings.gd")
const TraitText = preload("res://scripts/faction_trait_text.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func run() -> void:
	Localization.initialize()
	check(Localization.language() == "en" and TranslationServer.get_locale() == "en", "new sessions default to English regardless of operating system locale")
	check(Localization.text("返回主菜单") == "Main Menu", "menu caption is translated")
	check(Localization.text("步枪兵") == "Rifleman", "data-driven unit name is translated")
	check(Localization.text("动态俯角 30°") == "Dynamic Pitch 30°", "formatted numeric camera text is translated")
	check(Localization.text("步枪兵 · 5人小队") == "Rifleman · 5-Person Squad", "formatted squad label translates its nested unit name")
	check(Localization.text("成员 4 · HP 120/500") == "Member 4 · HP 120/500", "independent squad health status retains numbers")
	check(Localization.text("已选中 3 个操控对象 · 12 名成员 · 飞机 1\nZ 进攻移动 · X 停止 · Shift 追加") == "3 command units selected · 12 members · Aircraft 1\nZ Attack Move · X Stop · Shift Queue", "selection summary translates nested suffixes and shortcuts")
	check(Localization.text("资金不足") == "Insufficient Funds", "runtime command failures are translated")
	check(Localization.text("Return B · 100% · user://save.json") == "Return B · 100% · user://save.json", "English text, numbers, and paths are preserved")
	var rich := RichTextLabel.new()
	rich.text = "返回主菜单"
	root.add_child(rich)
	await process_frame
	check(rich.get_parsed_text() == "Main Menu", "native RichTextLabel renders English while retaining Chinese source")
	check(rich.text == "返回主菜单", "native UI translation does not overwrite source strings")
	var settings := Settings.new()
	root.add_child(settings)
	await process_frame
	settings.open({"in_match":false})
	check(settings.language_option.item_count == 2 and settings.language_option.selected == 0, "in-game language switch lists English and Simplified Chinese with English selected")
	settings.language_option.item_selected.emit(1)
	await process_frame
	check(Localization.language() == "zh_CN", "settings switch activates Simplified Chinese")
	check(rich.get_parsed_text() == "返回主菜单", "existing native controls immediately render Chinese")
	check(Localization.text("步枪兵 · 5人小队") == "步枪兵 · 5人小队", "Chinese preserves formatted source text")
	Localization.set_language("en")
	await process_frame
	check(rich.get_parsed_text() == "Main Menu" and settings.language_option.selected == 0, "switching back updates existing controls and language selector")
	var rules: Dictionary = Loader.load_rules("res://data/rules.json", false)
	var snapshot: String = JSON.stringify(rules)
	var results: Array[Dictionary] = Catalog.entries(rules, "kestrel", "unit", "rifleman")
	check(results.any(func(entry: Dictionary): return entry.id == "kestrel_rifle"), "wiki accepts displayed English unit names")
	check(Catalog.entries(rules, "kestrel", "unit", "步枪兵").any(func(entry: Dictionary): return entry.id == "kestrel_rifle"), "wiki retains source-language name search")
	check(JSON.stringify(rules) == snapshot and rules.units.kestrel_rifle.name == "步枪兵", "localization never mutates rule/save source data")
	var base_rows: Array = Catalog.sections(rules, "kestrel_rifle")[0].rows
	check(base_rows.any(func(row): return row.label == "整组招募费用" and row.value == "550 资金"), "wiki shows the actual five-member recruitment cost")
	check(base_rows.any(func(row): return row.label == "整组训练时间" and row.value == "18 秒"), "wiki shows full squad training time")
	check(base_rows.any(func(row): return row.label == "每名成员造价" and row.value == "110 资金"), "wiki labels original per-member cost explicitly")
	check(base_rows.any(func(row): return row.label == "编制人数" and row.value == "5 人"), "wiki shows squad membership")
	check(Localization.text("T1 · 正典 · 步枪兵") == "T1 · Canon · Rifleman", "wiki's shortened faction names translate in composite list captions")
	var han := RegEx.new(); han.compile("[\\x{3400}-\\x{9fff}]")
	for faction: String in ["kestrel", "rivet", "iron", "sky"]:
		for line: String in TraitText.faction_lines(rules, faction):
			check(han.search(Localization.text(line)) == null, "numeric faction trait templates are fully translated: " + faction)
	for category: String in ["units", "buildings"]:
		for spec: Dictionary in rules[category].values():
			check(han.search(Localization.text(str(spec.name))) == null, "roster display name translated: " + str(spec.name))
			check(han.search(Localization.text(str(spec.get("description", "")))) == null, "roster description translated: " + str(spec.name))
	settings.queue_free(); rich.queue_free()
	await process_frame
	if failures.is_empty():
		print("LOCALIZATION TESTS PASSED: %d checks" % checks)
	else:
		for failure: String in failures: push_error(failure)
		print("LOCALIZATION TESTS FAILED: %d/%d" % [failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
