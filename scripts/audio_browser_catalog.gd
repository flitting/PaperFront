class_name AudioBrowserCatalog
extends RefCounted

## Inventory of applied runtime audio, not a recursive asset-folder listing.
## Runtime family/scene names select metadata; new assets shadow old aliases.
## Reading the inventory never starts playback or loads an AudioStream.
const INTERFACE_MANIFEST := "res://assets/audio/revision_v8/interface_manifest.json"
const ORIGINAL_MUSIC_MANIFEST := "res://assets/audio/music/manifest.json"
const SYSTEM_MANIFEST := "res://assets/audio/revision_v8/system/manifest.json"
const FACTION_NAMES := {"kestrel": "正典军团", "rivet": "重锤军团", "iron": "铁钉同盟", "sky": "天翼教团"}
const CATEGORY_NAMES := {"infantry": "步兵", "vehicle": "车辆", "air": "空军"}
const ACTION_NAMES := {"select": "选中", "move": "移动", "attack": "攻击", "ready": "就绪", "return": "返程", "combat": "交战", "under_attack": "遇袭", "death": "阵亡"}
const EFFECT_NAMES := {
	"fire_machine_gun": "机枪点射", "fire_rifle": "步枪射击", "fire_anti": "反装甲发射",
	"fire_cannon": "坦克炮发射", "fire_artillery": "火炮发射", "fire_air": "航空机关炮",
	"impact_small": "小型弹着爆炸", "impact_medium": "炮弹命中", "impact_large": "大型弹着爆炸",
	"death_building": "建筑摧毁", "death_vehicle": "装甲摧毁", "death_infantry": "步兵倒地",
	"deploy_building": "建筑展开", "construct_building": "建筑施工", "bomb_release": "投弹机构",
	"rearm": "弹药装填", "engine_loop": "发动机循环", "tracks_loop": "履带循环", "aircraft_loop": "飞机引擎循环", "fire_energy": "天翼能量发射", "impact_energy": "天翼能量弹着", "creator_hand_attack": "创世之手拍击", "creator_hand_impact": "创世之手能量扩散",
	"select": "选中提示", "command": "指令确认", "produce": "生产完成", "delivery": "资源卸载", "sell": "机械纸板收折", "low_power": "电力断续提示", "result": "战果提示", "error": "指令受阻",
	"select_power": "建筑电流选中提示", "ui_key": "轻短按键触感", "ui_click": "纸板按钮点击"
}

static func _read_manifest(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

static func _row(entry: Dictionary, type: String, id: String, group: String, title: String, category: String, action: String, origin: String = "") -> Dictionary:
	var source: Dictionary = entry.get("provenance", {})
	var text: String = PaperAudio.caption_text(entry) if type == "voice" else str(entry.get("text", title))
	return {
		"id": id, "group_id": group, "file": str(entry.get("file", entry.get("path", ""))),
		"title": title, "text": text, "spoken_text": str(entry.get("text", text)), "voice_language": str(entry.get("language", "zh_CN")), "duration_s": float(entry.get("duration_s", 0.0)),
		"channels": int(entry.get("channels", 1)), "sample_width": int(entry.get("sample_width", 2)),
		"sample_rate": int(entry.get("sample_rate", 22050 if type in ["voice", "music"] else 44100)),
		"type": type, "faction": str(entry.get("faction", "")), "category": category, "action": action,
		"provider": str(source.get("provider", origin)), "model": str(source.get("model", "")),
		"speaker_id": str(entry.get("speaker_id", source.get("speaker_id", ""))),
		"speaker_gender": str(entry.get("speaker_gender", "")),
		"variant": int(entry.get("variant", 1)), "variants": 1, "sha256": str(entry.get("sha256", "")),
		"loop": bool(entry.get("loop", false)), "family": action if type == "sfx" else ""
	}

static func _add(result: Array[Dictionary], seen: Dictionary, row: Dictionary) -> void:
	var file: String = str(row.file)
	if file.is_empty() or seen.has(file): return
	# Retired banks cannot re-enter the browser, even through stale metadata.
	if file.begins_with("res://assets/audio/radio/") or file.begins_with("res://assets/audio/voices/"): return
	seen[file] = true
	result.append(row)

static func load_catalog(voice_language: String = "en") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	var voices: Dictionary = _read_manifest(PaperAudio.voice_manifest(voice_language))
	for entry: Dictionary in voices.get("clips", []):
		var faction: String = str(entry.get("faction", ""))
		var category: String = str(entry.get("category", ""))
		var action: String = str(entry.get("action", ""))
		if category not in PaperAudio.RADIO_CATEGORIES or action not in PaperAudio.RADIO_ACTIONS: continue
		var group: String = "voice/" + faction + "/" + category + "/" + action
		var variant: int = int(entry.get("variant", 1))
		var title: String = "%s · %s · %s %d" % [FACTION_NAMES.get(faction, faction), CATEGORY_NAMES.get(category, category), ACTION_NAMES.get(action, action), variant]
		_add(result, seen, _row(entry, "voice", group + "/" + str(variant), group, title, category, action))
	for entry: Dictionary in _read_manifest(PaperAudio.system_manifest(voice_language)).get("clips", []):
		var action: String = str(entry.get("action", ""))
		var group: String = "voice/system/" + action
		var title: String = "电力不足警报" if action == "low_power" else "供电恢复提示"
		_add(result, seen, _row(entry, "voice", group + "/1", group, title, "system", action))
	# These canonical families are what _event_family and movement playback use.
	# Generic fire/impact/death and build aliases would duplicate or expose their
	# shadowed historical source files; only current family records are listed.
	var effects: Dictionary = _read_manifest(PaperAudio.SFX_MANIFEST)
	var current_families: Dictionary = {}
	for entry: Dictionary in effects.get("effects", []):
		var family: String = str(entry.get("family", ""))
		if not EFFECT_NAMES.has(family): continue
		current_families[family] = true
		var group: String = "sfx/" + family
		var variant: int = int(entry.get("variant", 1))
		var title: String = str(EFFECT_NAMES[family]) + (" %d" % variant if not bool(entry.get("loop", false)) else "")
		_add(result, seen, _row(entry, "sfx", group + "/" + str(variant), group, title, "movement" if bool(entry.get("loop", false)) else "interface" if family in PaperAudio.UI_EVENTS + ["select_power","ui_key","ui_click"] else "battlefield", family))
	var interface: Dictionary = _read_manifest(INTERFACE_MANIFEST)
	for entry: Dictionary in interface.get("effects", []):
		var family: String = str(entry.get("family", ""))
		if family not in PaperAudio.UI_EVENTS or current_families.has(family) or family == "build": continue
		var group: String = "sfx/" + family
		_add(result, seen, _row(entry, "sfx", group + "/1", group, str(entry.get("title", family)), "interface", family))
	var active_music: Array = PaperMusic.APPLIED_TRACKS
	var current_music: Dictionary = {}
	# Exactly the runtime precedence: new menu/intense first, other map/result
	# score rows only when a new track has not replaced that scene name.
	for path in [PaperMusic.REVISION_MANIFEST]:
		var manifest: Dictionary = _read_manifest(path)
		for entry: Dictionary in manifest.get("tracks", []):
			var name: String = str(entry.get("id", entry.get("scene", "")))
			if name not in active_music or current_music.has(name): continue
			current_music[name] = true
			var group: String = "music/" + name
			var row: Dictionary = _row(entry, "music", group, group, str(entry.get("title", name)), "score", name, "Local original score synthesis")
			row.loop = true
			_add(result, seen, row)
	var counts: Dictionary = {}
	for row: Dictionary in result:
		counts[row.group_id] = int(counts.get(row.group_id, 0)) + 1
	for row: Dictionary in result: row.variants = int(counts[row.group_id])
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
	return result
