extends VBoxContainer

## Local match settings are independent of the production HUD and simulation.
signal changed

const CATALOG = preload("res://scripts/battlefield_catalog.gd")
const PROFILE_IDS = CATALOG.MODES
const FACTIONS := ["kestrel", "rivet", "iron", "sky"]
const DIFFICULTIES := ["easy", "normal", "hard"]
var players_option: OptionButton
var opponent_rows: Array[Dictionary] = []
var player_color_option: OptionButton
const COLOR_NAMES = preload("res://scripts/player_palette.gd").NAMES
var _preferred_players: int = 2

func build(hud) -> void:
	add_theme_constant_override("separation", 9)
	var player_row := HBoxContainer.new()
	add_child(player_row)
	player_row.add_child(hud.label("参战方数", 12))
	players_option = OptionButton.new()
	players_option.get_popup().force_native = true
	players_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for count in range(2, 5):
		players_option.add_item("%d 方" % count)
		players_option.set_item_metadata(players_option.item_count - 1, count)
	player_row.add_child(players_option)
	players_option.item_selected.connect(func(_index): _preferred_players = player_count(); _refresh_rows(); changed.emit(); hud.action.emit("ui_click",null))
	var rules: Dictionary = FactionTraitText.menu_rules()
	var color_row := HBoxContainer.new()
	color_row.add_child(hud.label("我的颜色", 13))
	player_color_option = _color_choice(0)
	color_row.add_child(player_color_option)
	add_child(color_row)
	player_color_option.item_selected.connect(func(_value): changed.emit(); hud.action.emit("ui_click", null))
	for index in range(3):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 9)
		var slot_label:Label=hud.label("对手 %d" % (index+1),13)
		slot_label.custom_minimum_size.x=52
		row.add_child(slot_label)
		var faction := OptionButton.new()
		faction.get_popup().force_native = true
		faction.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for id in FACTIONS:
			faction.add_item(str(rules.factions.get(id, {}).get("name", id)))
			faction.set_item_metadata(faction.item_count - 1, id)
		faction.select(index + 1)
		row.add_child(faction)
		var color := _color_choice(index + 1)
		row.add_child(color)
		var difficulty := OptionButton.new()
		difficulty.get_popup().force_native = true
		for title in ["简单", "普通", "困难"]: difficulty.add_item(title)
		difficulty.select(1)
		difficulty.tooltip_text = "难度调整决策与战术；各方使用相同的资金、生产和侦察规则。"
		row.add_child(difficulty)
		faction.item_selected.connect(func(_value):changed.emit();hud.action.emit("ui_click",null))
		difficulty.item_selected.connect(func(_value):changed.emit();hud.action.emit("ui_click",null))
		color.item_selected.connect(func(_value):changed.emit();hud.action.emit("ui_click",null))
		add_child(row)
		opponent_rows.append({"row": row, "faction": faction, "difficulty": difficulty, "color": color})
	_refresh_rows()

func _refresh_rows() -> void:
	for index in range(opponent_rows.size()): opponent_rows[index].row.visible = index < player_count() - 1

func player_count() -> int:
	return int(players_option.get_item_metadata(players_option.selected))

func set_map(mode: String) -> void:
	players_option.disabled = mode not in PROFILE_IDS
	players_option.select(0 if players_option.disabled else _preferred_players - 2)
	players_option.tooltip_text = "明原对称场固定两方参战；地形、矿区、树木和中立建筑完全镜像，无水域。" if mode == "symmetric" else "经典战场固定两方参战" if players_option.disabled else "新战场按两方对置、三方三角或四方环形生成真实出生点。"
	_refresh_rows()

func options(player_faction: String) -> Dictionary:
	var slots: Array = [{"faction": player_faction, "control": "human", "difficulty": "normal", "color": player_color_option.get_item_metadata(player_color_option.selected)}]
	for index in range(player_count() - 1):
		var row: Dictionary = opponent_rows[index]
		slots.append({"faction": str(row.faction.get_item_metadata(row.faction.selected)), "control": "ai", "difficulty": DIFFICULTIES[row.difficulty.selected], "color": row.color.get_item_metadata(row.color.selected)})
	return {"players": player_count(), "slots": slots}

func restore(options_value: Dictionary) -> void:
	_preferred_players = clampi(int(options_value.get("players", 2)), 2, 4)
	if not players_option.disabled: players_option.select(_preferred_players - 2)
	var slots: Array = options_value.get("slots", [])
	if not slots.is_empty(): _restore_color(player_color_option, str(slots[0].get("color", "")))
	for index in range(mini(3, slots.size() - 1)):
		var slot: Dictionary = slots[index + 1]
		_restore_color(opponent_rows[index].color, str(slot.get("color", "")))
		var faction_index: int = FACTIONS.find(str(slot.get("faction", "rivet")))
		if faction_index >= 0: opponent_rows[index].faction.select(faction_index)
		var difficulty_index: int = DIFFICULTIES.find(str(slot.get("difficulty", "normal")))
		if difficulty_index >= 0: opponent_rows[index].difficulty.select(difficulty_index)
	_refresh_rows()

func _color_choice(index: int) -> OptionButton:
	var choice := OptionButton.new()
	choice.get_popup().force_native = true
	choice.tooltip_text = "玩家颜色独立于阵营；不同玩家可选同色，归属仍按玩家判定。"
	for color_index in PaperHUD.PLAYER_COLORS.size():
		var pixels := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		pixels.fill(PaperHUD.PLAYER_COLORS[color_index])
		choice.add_icon_item(ImageTexture.create_from_image(pixels), COLOR_NAMES[color_index])
		choice.set_item_metadata(color_index, PaperHUD.PLAYER_COLORS[color_index].to_html(false))
	choice.select(index)
	return choice

func _restore_color(choice: OptionButton, value: String) -> void:
	for index in choice.item_count:
		if str(choice.get_item_metadata(index)) == value.trim_prefix("#"): choice.select(index); return
