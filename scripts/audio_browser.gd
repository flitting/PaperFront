extends Control
class_name AudioBrowser

# The browser reads the same applied file inventory as the game and owns one
# preview player. Preview never sends simulation commands or writes preferences.
const DEMO_PATH := "res://scripts/audio_animation_preview.gd"
const Localization = preload("res://scripts/localization.gd")
const Catalog = preload("res://scripts/audio_browser_catalog.gd")
const INK := Color("392c21")
const CREAM := Color("f0dfbd")
const BLUE := Color("2865a5")
const ACTION_NAMES := {
	"select":"选中应答", "move":"移动应答", "attack":"攻击应答", "ready":"生产完成", "return":"返航",
	"combat":"战斗", "under_attack":"受击", "death":"阵亡", "fire_rifle":"步枪", "fire_machine_gun":"机枪",
	"fire_anti":"反装甲 / 防空发射", "fire_cannon":"坦克炮", "fire_artillery":"火炮", "fire_air":"空战射击",
	"fire_energy":"天翼能量发射", "impact_energy":"天翼能量弹着", "creator_hand_attack":"创世之手拍击", "creator_hand_impact":"创世之手能量扩散",
	"bomb_release":"空袭投弹", "impact_small":"小型命中", "impact_medium":"炮弹命中", "impact_large":"大型爆炸",
	"death_building":"建筑摧毁", "death_vehicle":"载具摧毁", "death_infantry":"步兵阵亡",
	"deploy_building":"建筑展开", "construct_building":"建筑施工", "engine_loop":"发动机", "tracks_loop":"履带",
	"aircraft_loop":"飞行引擎", "rearm":"补给", "command":"命令提示", "produce":"生产提示",
	"delivery":"交付提示", "sell":"出售提示", "low_power":"电力不足", "power_restored":"供电恢复", "select_power":"建筑电流选中", "ui_key":"按键触感", "ui_click":"纸板按钮点击", "result":"胜负提示", "error":"操作提示",
	"menu":"主菜单", "battle_calm":"平静战场", "battle_danger":"危机压迫", "battle_engaged":"轻度交战", "battle_intense":"激烈战斗", "battle":"平静战场", "win":"胜利", "lose":"失败", "draw":"平局",
	"battle_forest":"林地", "battle_desert":"荒漠", "battle_snow":"雪原", "battle_city":"城市",
	"battle_random_city":"随机城市", "battle_islands":"群岛", "battle_campaign":"战役"
}
const CATEGORY_NAMES := {"infantry":"步兵", "vehicle":"车辆", "air":"空军", "system":"系统提示", "battlefield":"战场声音", "movement":"移动声音", "interface":"界面提示", "score":"背景配乐"}
const TYPE_NAMES := {"voice":"单位语音", "sfx":"音效", "music":"音乐"}

var audio: PaperAudio
var rules: Dictionary = {}
var enabled := true
var catalog: Array[Dictionary] = []
var current_entries: Array[Dictionary] = []
var entry_buttons: Dictionary = {}
var row_by_id: Dictionary = {}
var selected_id := ""
var selected_entry: Dictionary = {}
var preview_player: AudioStreamPlayer
var type_filter: OptionButton
var faction_filter: OptionButton
var category_filter: OptionButton
var action_filter: OptionButton
var search: LineEdit
var count_label: Label
var list_scroll: ScrollContainer
var list_box: VBoxContainer
var title_label: Label
var caption_label: Label
var source_label: Label
var info_label: Label
var validation_label: Label
var status_label: Label
var play_button: Button
var stop_button: Button
var progress_label: Label
var restart_button: Button
var next_button: Button
var progress_slider: HSlider
var speed_slider: HSlider
var volume_slider: HSlider
var speed_label: Label
var volume_label: Label
var demo: Control
var session_active := false
var playback_speed := 1.0
var preview_volume := 100.0
var _cursor := 0.0
var _dragging_seek := false
var _seek_anchor_us := 0
var _seek_override_until_us := 0
var _preview_suspended := false
var _music_snapshot: Dictionary = {}
var _status_clock := 0.0

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	var page := VBoxContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("separation", 10)
	add_child(page)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	page.add_child(filters)
	type_filter = _option(filters, [["全部声音", ""], ["单位语音", "voice"], ["音效", "sfx"], ["音乐", "music"]])
	faction_filter = _option(filters, [["全部阵营", ""]])
	category_filter = _option(filters, [["全部类别", ""], ["步兵", "infantry"], ["车辆", "vehicle"], ["空军", "air"], ["战场声音", "battlefield"], ["移动声音", "movement"], ["界面提示", "interface"], ["背景配乐", "score"]])
	action_filter = _option(filters, [["全部场景 / 分组", ""]])
	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 12)
	page.add_child(search_row)
	search = LineEdit.new()
	search.placeholder_text = "搜索台词、阵营、音效或音乐名称"
	search.clear_button_enabled = true
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.add_theme_color_override("font_color", INK)
	search.add_theme_color_override("font_placeholder_color", Color("876e4f"))
	search_row.add_child(search)
	count_label = _label("", 14)
	search_row.add_child(count_label)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	page.add_child(columns)
	list_scroll = ScrollContainer.new()
	list_scroll.custom_minimum_size.x = 340
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.size_flags_stretch_ratio = .9
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.mouse_force_pass_scroll_events = false
	columns.add_child(list_scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 5)
	list_scroll.add_child(list_box)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.mouse_force_pass_scroll_events = false
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.size_flags_stretch_ratio = 1.25
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(detail_scroll)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 12)
	detail_scroll.add_child(details)
	title_label = _label("请选择音频", 24)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(title_label)
	caption_label = _label("", 22)
	caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(caption_label)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	details.add_child(controls)
	play_button = _button("▶ 播放", toggle_playback)
	controls.add_child(play_button)
	stop_button = _button("■ 停止", stop_preview)
	controls.add_child(stop_button)
	restart_button = _button("↻ 重播", restart_preview)
	controls.add_child(restart_button)
	next_button = _button("下一段 ›", next_clip)
	controls.add_child(next_button)
	var progress_row := HBoxContainer.new()
	details.add_child(progress_row)
	progress_label = _label("", 15)
	progress_row.add_child(progress_label)
	var timeline_hint := _label("拖动进度调整声音位置", 13)
	timeline_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	progress_row.add_child(timeline_hint)
	progress_slider = HSlider.new()
	progress_slider.name = "PreviewProgress"
	progress_slider.min_value = 0.0
	progress_slider.max_value = 1.0
	progress_slider.step = .01
	progress_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_child(progress_slider)
	progress_slider.value_changed.connect(seek_to)
	progress_slider.drag_started.connect(func(): _dragging_seek = true)
	progress_slider.drag_ended.connect(func(_changed): _dragging_seek = false; seek_to(progress_slider.value))
	var speed_row := HBoxContainer.new()
	details.add_child(speed_row)
	speed_label = _label("试听速度 1.00×", 14)
	speed_label.custom_minimum_size.x = 130
	speed_row.add_child(speed_label)
	speed_slider = HSlider.new()
	speed_slider.name = "PreviewSpeed"
	speed_slider.min_value = .5
	speed_slider.max_value = 2.0
	speed_slider.step = .05
	speed_slider.value = 1.0
	speed_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed_row.add_child(speed_slider)
	speed_slider.value_changed.connect(set_playback_speed)
	var volume_row := HBoxContainer.new()
	details.add_child(volume_row)
	volume_label = _label("试听音量 100%", 14)
	volume_label.custom_minimum_size.x = 130
	volume_row.add_child(volume_label)
	volume_slider = HSlider.new()
	volume_slider.name = "PreviewVolume"
	volume_slider.min_value = 0.0
	volume_slider.max_value = 200.0
	volume_slider.step = 1.0
	volume_slider.value = 100.0
	volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_row.add_child(volume_slider)
	volume_slider.value_changed.connect(set_preview_volume)
	if ResourceLoader.exists(DEMO_PATH):
		demo = load(DEMO_PATH).new()
		demo.name = "AudioAnimationDemo"
		demo.custom_minimum_size.y = 210
		demo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.add_child(demo)
	info_label = _label("", 16)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(info_label)
	validation_label = _label("", 15)
	details.add_child(validation_label)
	source_label = _label("", 14)
	source_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(source_label)
	status_label = _label("选择条目后播放；切换条目或页面会停止试听。", 15)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(status_label)
	preview_player = AudioStreamPlayer.new()
	preview_player.name = "AudioBrowserPreview"
	preview_player.finished.connect(_preview_finished)
	add_child(preview_player)
	type_filter.item_selected.connect(func(_index): _type_changed())
	for filter: OptionButton in [faction_filter, category_filter, action_filter]:
		filter.item_selected.connect(func(_index): _rebuild_entries())
	search.text_changed.connect(func(_text): _rebuild_entries())
	visibility_changed.connect(func():
		set_session_active(is_visible_in_tree() and enabled))
	configure(audio, rules)

func configure(owner_audio: PaperAudio, config: Dictionary = {}) -> void:
	if audio != owner_audio:
		set_session_active(false)
		if is_instance_valid(audio) and audio.voice_language_changed.is_connected(_voice_language_changed):
			audio.voice_language_changed.disconnect(_voice_language_changed)
	audio = owner_audio
	if is_instance_valid(audio) and not audio.voice_language_changed.is_connected(_voice_language_changed):
		audio.voice_language_changed.connect(_voice_language_changed)
	rules = config
	if not is_node_ready(): return
	catalog = Catalog.load_catalog(audio.voice_language if is_instance_valid(audio) else "en")
	row_by_id.clear()
	for row: Dictionary in catalog: row_by_id[str(row.id)] = row
	_refresh_filters()
	_rebuild_entries()
	set_session_active(enabled and is_visible_in_tree())

func _voice_language_changed(_language: String) -> void:
	stop_preview()
	configure(audio, rules)

func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled: set_session_active(false)
	elif is_visible_in_tree(): set_session_active(true)
	if is_node_ready(): _update_controls()

func _refresh_filters() -> void:
	var faction: String = _chosen(faction_filter)
	var action: String = _chosen(action_filter)
	var category: String = _chosen(category_filter)
	var chosen_type: String = _chosen(type_filter)
	faction_filter.disabled = chosen_type in ["sfx", "music"]
	faction_filter.clear()
	faction_filter.add_item("全部阵营")
	faction_filter.set_item_metadata(0, "")
	for id: String in ["kestrel", "rivet", "iron", "sky"]:
		faction_filter.add_item(_faction_name(id))
		faction_filter.set_item_metadata(faction_filter.item_count - 1, id)
		if faction == id: faction_filter.select(faction_filter.item_count - 1)
	category_filter.clear()
	category_filter.add_item("全部类别")
	category_filter.set_item_metadata(0, "")
	var categories: Array = ["infantry", "vehicle", "air", "system"] if chosen_type == "voice" else ["battlefield", "movement", "interface"] if chosen_type == "sfx" else ["score"] if chosen_type == "music" else CATEGORY_NAMES.keys()
	for category_id: String in categories:
		category_filter.add_item(str(CATEGORY_NAMES[category_id]))
		category_filter.set_item_metadata(category_filter.item_count - 1, category_id)
		if category == category_id: category_filter.select(category_filter.item_count - 1)
	category_filter.disabled = chosen_type == "music"
	var actions: Array[String] = []
	for row: Dictionary in catalog:
		if not chosen_type.is_empty() and str(row.type) != chosen_type: continue
		var action_id: String = str(row.get("action", ""))
		if not action_id.is_empty() and action_id not in actions: actions.append(action_id)
	actions.sort()
	action_filter.clear()
	action_filter.add_item("全部场景 / 分组")
	action_filter.set_item_metadata(0, "")
	for action_id: String in actions:
		action_filter.add_item(str(ACTION_NAMES.get(action_id, action_id)))
		action_filter.set_item_metadata(action_filter.item_count - 1, action_id)
		if action == action_id: action_filter.select(action_filter.item_count - 1)

func _type_changed() -> void:
	stop_preview()
	faction_filter.select(0)
	category_filter.select(0)
	action_filter.select(0)
	search.text = ""
	_refresh_filters()
	_rebuild_entries()

func _chosen(filter: OptionButton) -> String:
	return str(filter.get_item_metadata(filter.selected)) if filter != null and filter.selected >= 0 else ""

func _faction_name(id: String) -> String:
	return str(rules.get("factions", {}).get(id, {}).get("name", Catalog.FACTION_NAMES.get(id, id)))

func _row_title(row: Dictionary) -> String:
	if str(row.type) == "voice":
		if str(row.get("category", "")) == "system": return "系统 · " + str(row.get("title", row.text))
		return "%s · %s · %s %d" % [_faction_name(str(row.faction)), CATEGORY_NAMES.get(str(row.category), row.category), ACTION_NAMES.get(str(row.action), row.action), int(row.variant)]
	return str(row.get("title", ACTION_NAMES.get(str(row.get("action", "")), row.id)))

func _rebuild_entries() -> void:
	stop_preview()
	if list_box == null: return
	for child in list_box.get_children():
		list_box.remove_child(child)
		child.queue_free()
	entry_buttons.clear()
	current_entries.clear()
	var query: String = search.text.strip_edges().to_lower()
	for row: Dictionary in catalog:
		if not _chosen(type_filter).is_empty() and str(row.type) != _chosen(type_filter): continue
		if not _chosen(faction_filter).is_empty() and str(row.get("faction", "")) != _chosen(faction_filter): continue
		if not _chosen(category_filter).is_empty() and str(row.get("category", "")) != _chosen(category_filter): continue
		if not _chosen(action_filter).is_empty() and str(row.get("action", "")) != _chosen(action_filter): continue
		var haystack: String = " ".join([_row_title(row), str(row.get("text", "")), str(row.id), str(row.file), str(row.get("provider", "")), str(row.get("spoken_text", ""))]).to_lower()
		haystack += " " + Localization.text(haystack).to_lower()
		var matches := true
		for term: String in query.split(" ", false):
			if not haystack.contains(term): matches = false; break
		if matches: current_entries.append(row)
	count_label.text = "%d / %d 段" % [current_entries.size(), catalog.size()]
	for row: Dictionary in current_entries:
		var id: String = str(row.id)
		var button := _button(_row_title(row), func(): select_entry(id))
		button.custom_minimum_size = Vector2(300, 46)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.tooltip_text = str(row.get("text", _row_title(row)))
		list_box.add_child(button)
		entry_buttons[id] = button
	if entry_buttons.has(selected_id): select_entry(selected_id)
	elif not current_entries.is_empty(): select_entry(str(current_entries[0].id))
	else:
		selected_id = ""
		selected_entry.clear()
		if demo != null: demo.clear()
		title_label.text = "没有匹配的音频"
		caption_label.text = ""
		info_label.text = "试试其它台词、名称或筛选条件。"
		source_label.text = ""
		validation_label.text = ""
		_update_controls()

func select_entry(id: String) -> void:
	if not row_by_id.has(id): return
	stop_preview()
	selected_id = id
	selected_entry = row_by_id[id].duplicate(true)
	title_label.text = _row_title(selected_entry)
	caption_label.text = str(selected_entry.get("text", ""))
	var family: String = str(TYPE_NAMES.get(str(selected_entry.type), selected_entry.type))
	info_label.text = "%s · %.2f 秒 · 变体 %d/%d\n%s\n%s" % [family, float(selected_entry.get("duration_s", 0.0)), int(selected_entry.get("variant", 1)), int(selected_entry.get("variants", 1)), str(selected_entry.get("provider", "原始游戏素材")), str(selected_entry.get("model", ""))]
	if str(selected_entry.get("type",""))=="voice":info_label.text += "\n固定声源："+str(selected_entry.get("speaker_id",""))
	source_label.text = "素材：" + str(selected_entry.file)
	var path: String = str(selected_entry.file)
	var inspection: Dictionary = inspect_entry(selected_entry)
	var valid: bool = bool(inspection.valid)
	validation_label.text = str(inspection.message)
	selected_entry["validation_mode"] = str(inspection.mode)
	validation_label.add_theme_color_override("font_color", Color("426b37") if valid else Color("bb4034"))
	selected_entry["preview_valid"] = valid
	for entry_id: String in entry_buttons:
		(entry_buttons[entry_id] as Button).add_theme_stylebox_override("normal", _style(Color("ecd092") if entry_id == selected_id else CREAM))
	if demo != null: demo.configure_catalog_entry(selected_entry, rules)
	_update_progress()
	_update_controls()

# Source WAVs are not necessarily in a Godot export: the applied imported
# stream is the playable resource. Hash raw files only when they exist.
func inspect_entry(row: Dictionary) -> Dictionary:
	var path: String = str(row.file)
	if not ResourceLoader.exists(path): return {"valid": false, "mode": "missing", "message": "素材校验：音频资源缺失"}
	if FileAccess.file_exists(path):
		var expected_hash: String = str(row.get("sha256", ""))
		var valid: bool = expected_hash.is_empty() or FileAccess.get_sha256(path) == expected_hash
		return {"valid": valid, "mode": "source", "message": "素材校验：原始文件与清单一致" if valid else "素材校验：原始文件已改变"}
	var stream: AudioStreamWAV = load(path)
	var valid: bool = imported_clip_valid(row, stream)
	return {"valid": valid, "mode": "imported", "message": "素材校验：导入音频格式、时长一致" if valid else "素材校验：导入音频格式或时长异常"}

static func imported_clip_valid(row: Dictionary, stream: AudioStreamWAV) -> bool:
	if stream == null: return false
	var expected_rate: int = int(row.get("sample_rate", 22050 if str(row.type) in ["voice", "music"] else 44100))
	return stream.format == AudioStreamWAV.FORMAT_16_BITS and not stream.stereo and stream.mix_rate == expected_rate and not stream.data.is_empty() and absf(stream.get_length() - float(row.duration_s)) < .001

func set_session_active(value: bool) -> void:
	var active: bool = value and enabled and is_visible_in_tree() and is_instance_valid(audio)
	if active == session_active: return
	session_active = active
	if session_active:
		_suspend_runtime_audio()
	else:
		stop_preview()
		_restore_runtime_audio()
		if demo != null: demo.clear()
	if is_node_ready(): _update_controls()

func play_selected(replay: bool = false) -> void:
	if not enabled or not is_visible_in_tree() or not is_instance_valid(audio) or selected_entry.is_empty() or not bool(selected_entry.get("preview_valid", false)): return
	set_session_active(true)
	var source: AudioStreamWAV = load(str(selected_entry.file))
	if source == null: return
	preview_player.stop()
	preview_player.stream_paused = false
	var stream: AudioStreamWAV = source.duplicate()
	if bool(selected_entry.get("loop", false)):
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(round(stream.get_length() * stream.mix_rate))
	else: stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	preview_player.stream = stream
	var family: String = str(selected_entry.type)
	preview_player.bus = PaperAudio.VOICE_BUS if family == "voice" else PaperAudio.MUSIC_BUS if family == "music" else PaperAudio.BUS_NAME
	_apply_preview_settings()
	_cursor = clampf(_cursor, 0.0, maxf(0.0, stream.get_length() - 1.0 / stream.mix_rate))
	preview_player.play(_cursor)
	_seek_anchor_us = Time.get_ticks_usec()
	_seek_override_until_us = _seek_anchor_us + 150000
	if demo != null:
		if replay: demo.restart_demo()
		else: demo.play_demo()
	status_label.text = "正在试听；背景音乐在整个音频浏览页面保持暂停。"
	_update_controls()

func toggle_playback() -> void:
	if preview_player != null and preview_player.stream != null and (preview_player.playing or preview_player.stream_paused):
		pause_preview(not preview_player.stream_paused)
	else:
		if _cursor >= _duration() - .001: _cursor = 0.0
		play_selected()

func pause_preview(paused: bool = true) -> void:
	if preview_player == null or preview_player.stream == null: return
	_cursor = playback_position()
	preview_player.stream_paused = paused
	_seek_anchor_us = Time.get_ticks_usec()
	_seek_override_until_us = _seek_anchor_us + 150000
	if demo != null and demo.has_method("pause_demo"): demo.pause_demo(paused)
	status_label.text = "已暂停试听；背景音乐仍保持暂停。" if paused else "正在试听；背景音乐仍保持暂停。"
	_update_progress()
	_update_controls()

func restart_preview() -> void:
	stop_preview()
	_cursor = 0.0
	play_selected(true)

func next_clip() -> void:
	if current_entries.is_empty(): return
	var index := -1
	for i in range(current_entries.size()):
		if str(current_entries[i].id) == selected_id: index = i; break
	select_entry(str(current_entries[(index + 1) % current_entries.size()].id))
	play_selected()

func seek_to(seconds: float) -> void:
	if selected_entry.is_empty(): return
	_cursor = clampf(seconds, 0.0, _duration())
	_seek_anchor_us = Time.get_ticks_usec()
	_seek_override_until_us = _seek_anchor_us + 150000
	if preview_player != null and preview_player.stream != null:
		var rate: int = (preview_player.stream as AudioStreamWAV).mix_rate
		_cursor = minf(_cursor, maxf(0.0, _duration() - 1.0 / rate))
		preview_player.seek(_cursor)
	_update_progress()
	_update_controls()
	# Audio scrubbing deliberately never changes the independent demo clock.

func set_playback_speed(value: float) -> void:
	_cursor = playback_position()
	_seek_anchor_us = Time.get_ticks_usec()
	_seek_override_until_us = _seek_anchor_us + 150000
	playback_speed = clampf(value, .5, 2.0)
	if speed_slider != null:
		speed_slider.set_value_no_signal(playback_speed)
		speed_label.text = "试听速度 %.2f×" % playback_speed
	_apply_preview_settings()

func set_preview_volume(percent: float) -> void:
	preview_volume = clampf(percent, 0.0, 200.0)
	if volume_slider != null:
		volume_slider.set_value_no_signal(preview_volume)
		volume_label.text = "试听音量 %d%%" % roundi(preview_volume)
	_apply_preview_settings()

func _apply_preview_settings() -> void:
	if preview_player == null: return
	preview_player.pitch_scale = playback_speed
	preview_player.volume_linear = db_to_linear(_preview_gain(selected_entry)) * preview_volume / 100.0 if not selected_entry.is_empty() else 0.0

func _duration() -> float:
	return preview_player.stream.get_length() if preview_player != null and preview_player.stream != null else float(selected_entry.get("duration_s", 0.0))

func playback_position() -> float:
	var duration: float = _duration()
	if preview_player == null or preview_player.stream == null or preview_player.stream_paused or not preview_player.playing: return _cursor
	var now: int = Time.get_ticks_usec()
	var position: float = _cursor + float(now - _seek_anchor_us) / 1000000.0 * playback_speed if now < _seek_override_until_us else preview_player.get_playback_position() + AudioServer.get_time_since_last_mix() * playback_speed
	return fposmod(maxf(0.0, position), maxf(duration, .001)) if bool(selected_entry.get("loop", false)) else clampf(position, 0.0, duration)

func _update_progress() -> void:
	if progress_slider == null: return
	var duration: float = _duration()
	progress_slider.max_value = maxf(duration, .001)
	if not _dragging_seek: progress_slider.set_value_no_signal(playback_position())
	progress_label.text = "%.2f / %.2f 秒%s" % [playback_position(), duration, " · 循环" if bool(selected_entry.get("loop", false)) else ""]

func _preview_gain(row: Dictionary) -> float:
	return PaperAudio.catalog_gain(row)

func _suspend_runtime_audio() -> void:
	if _preview_suspended: return
	_preview_suspended = true
	audio.begin_preview()
	var music: PaperMusic = audio.music
	if music == null or music.player == null: return
	_music_snapshot = {"owner": music, "processing": music.is_processing(), "stream": music.player.stream, "position": music.get_playback_position(), "playing": music.player.stream != null and (music.player.playing or music.player.stream_paused or music.preview_resume_position >= 0.0), "track": music.active_track}
	music.set_process(false)
	music.player.stop()

func stop_preview() -> void:
	if preview_player != null:
		preview_player.stop()
		preview_player.stream = null
	_cursor = 0.0
	if preview_player != null: preview_player.stream_paused = false
	if demo != null: demo.stop()
	if is_node_ready():
		_update_progress()
		status_label.text = "选择条目后播放；背景音乐在本页面保持暂停。"
		_update_controls()

func _preview_finished() -> void:
	_cursor = _duration()
	preview_player.stream_paused = false
	preview_player.stream = null
	# Audio completion (including a seek near the end) cannot alter the demo clock.
	status_label.text = "播放完毕；背景音乐仍保持暂停。"
	_update_progress()
	_update_controls()

func _restore_runtime_audio() -> void:
	if not _preview_suspended: return
	_preview_suspended = false
	if is_instance_valid(audio): audio.end_preview()
	var owner: Variant = _music_snapshot.get("owner")
	if is_instance_valid(owner):
		var music: PaperMusic = owner
		music.set_process(bool(_music_snapshot.get("processing", true)))
		if bool(_music_snapshot.get("playing", false)) and music.active_track == str(_music_snapshot.get("track", "")) and music.player.stream == _music_snapshot.get("stream"):
			music.restore_playback(float(_music_snapshot.get("position", 0.0)))
	_music_snapshot.clear()

func _update_controls() -> void:
	if play_button == null: return
	var valid: bool = enabled and session_active and is_instance_valid(audio) and not selected_entry.is_empty() and bool(selected_entry.get("preview_valid", false))
	var playing: bool = preview_player != null and preview_player.stream != null and (preview_player.playing or preview_player.stream_paused)
	play_button.disabled = not valid
	play_button.text = "▶ 继续" if playing and preview_player.stream_paused else "Ⅱ 暂停" if playing else "▶ 播放"
	stop_button.disabled = not playing and _cursor <= 0.0
	restart_button.disabled = not valid
	next_button.disabled = not enabled or not session_active or current_entries.is_empty()
	progress_slider.editable = valid
	speed_slider.editable = valid
	volume_slider.editable = valid

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	_update_progress()
	_status_clock -= delta
	if _status_clock > 0.0: return
	_status_clock = .10
	if preview_player != null and preview_player.stream != null:
		if is_instance_valid(audio):
			var levels: Dictionary = audio.get_mix()
			var bus_key: String = "voice" if str(selected_entry.get("type", "")) == "voice" else "music" if str(selected_entry.get("type", "")) == "music" else "sfx"
			if bool(levels.muted) or float(levels.master) <= 0.0 or float(levels[bus_key]) <= 0.0 or preview_volume <= 0.0:
				status_label.text = "声音已静音；本页面始终暂停背景音乐。"
			elif preview_player.stream_paused:
				status_label.text = "已暂停试听；背景音乐仍保持暂停。"
			else:
				status_label.text = "正在试听；背景音乐仍保持暂停。"
	_update_controls()

func _exit_tree() -> void:
	if is_instance_valid(preview_player):
		preview_player.stop()
		preview_player.stream = null
	_restore_runtime_audio()
	if is_instance_valid(demo): demo.clear()

func _option(parent: Control, choices: Array) -> OptionButton:
	var option := OptionButton.new()
	option.get_popup().force_native = true
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for choice: Array in choices:
		option.add_item(str(choice[0]))
		option.set_item_metadata(option.item_count - 1, choice[1])
	parent.add_child(option)
	return option

func _label(value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_color_override("font_color", INK)
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = INK
	style.set_border_width_all(1)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style

func _button(value: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size.y = 40
	button.mouse_force_pass_scroll_events = true
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_stylebox_override("normal", _style(CREAM))
	button.add_theme_stylebox_override("hover", _style(Color("faefd7")))
	button.add_theme_stylebox_override("pressed", _style(Color("d7bd8d")))
	button.pressed.connect(handler)
	return button
