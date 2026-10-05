extends VBoxContainer

## Local match settings are independent of the production HUD and simulation.
const CATALOG = preload("res://scripts/battlefield_catalog.gd")
const PROFILE_IDS = CATALOG.MODES
const FACTIONS := ["kestrel", "rivet", "iron", "sky"]
const DIFFICULTIES := ["easy", "normal", "hard"]
var players_option: OptionButton
var opponent_rows: Array[Dictionary] = []
var _preferred_players: int = 2

func build(hud) -> void:
	add_theme_constant_override("separation", 7)
	var player_row := HBoxContainer.new()
	add_child(player_row)
	player_row.add_child(hud.label("参战方数 · 玩家与 AI", 12))
	players_option = OptionButton.new()
	players_option.get_popup().force_native = true
	players_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for count in range(2, 5):
		players_option.add_item("%d 方" % count)
		players_option.set_item_metadata(players_option.item_count - 1, count)
	player_row.add_child(players_option)
	players_option.item_selected.connect(func(_index): _preferred_players = player_count(); _refresh_rows())
	var rules: Dictionary = FactionTraitText.menu_rules()
	for index in range(3):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 7)
		row.add_child(hud.label("对手 %d" % (index + 1), 12))
		var faction := OptionButton.new()
		faction.get_popup().force_native = true
		faction.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for id in FACTIONS:
			faction.add_item(str(rules.factions.get(id, {}).get("name", id)))
			faction.set_item_metadata(faction.item_count - 1, id)
		faction.select(index + 1)
		row.add_child(faction)
		var difficulty := OptionButton.new()
		difficulty.get_popup().force_native = true
		for title in ["简单", "普通", "困难"]: difficulty.add_item(title)
		difficulty.select(1)
		difficulty.tooltip_text = "难度调整决策与战术；各方使用相同的资金、生产和侦察规则。"
		row.add_child(difficulty)
		add_child(row)
		opponent_rows.append({"row": row, "faction": faction, "difficulty": difficulty})
	_refresh_rows()

func _refresh_rows() -> void:
	for index in range(opponent_rows.size()): opponent_rows[index].row.visible = index < player_count() - 1

func player_count() -> int:
	return int(players_option.get_item_metadata(players_option.selected))

func set_map(mode: String) -> void:
	players_option.disabled = mode not in PROFILE_IDS
	players_option.select(0 if players_option.disabled else _preferred_players - 2)
	players_option.tooltip_text = "经典战场固定两方参战" if players_option.disabled else "新战场按两方对置、三方三角或四方环形生成真实出生点。"
	_refresh_rows()

func options(player_faction: String) -> Dictionary:
	var slots: Array = [{"faction": player_faction, "control": "human", "difficulty": "normal"}]
	for index in range(player_count() - 1):
		var row: Dictionary = opponent_rows[index]
		slots.append({"faction": str(row.faction.get_item_metadata(row.faction.selected)), "control": "ai", "difficulty": DIFFICULTIES[row.difficulty.selected]})
	return {"players": player_count(), "slots": slots}

func restore(options_value: Dictionary) -> void:
	_preferred_players = clampi(int(options_value.get("players", 2)), 2, 4)
	if not players_option.disabled: players_option.select(_preferred_players - 2)
	var slots: Array = options_value.get("slots", [])
	for index in range(mini(3, slots.size() - 1)):
		var slot: Dictionary = slots[index + 1]
		var faction_index: int = FACTIONS.find(str(slot.get("faction", "rivet")))
		if faction_index >= 0: opponent_rows[index].faction.select(faction_index)
		var difficulty_index: int = DIFFICULTIES.find(str(slot.get("difficulty", "normal")))
		if difficulty_index >= 0: opponent_rows[index].difficulty.select(difficulty_index)
	_refresh_rows()
