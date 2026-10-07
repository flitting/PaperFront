extends SceneTree
func _initialize():
 var rules = RulesLoader.load_rules()
 print("RULES_ERRORS ", RulesLoader.errors)
 print("RULES_OK ", not rules.is_empty())
 quit(0 if not rules.is_empty() else 1)
