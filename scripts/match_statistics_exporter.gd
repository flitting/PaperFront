extends RefCounted
## Portable analysis bundle. JSON retains nested metadata/per-spec counters;
## UTF-8 CSV files provide one owner per row for ordinary analysis tools.
const SERIES_FIELDS := ["team", "faction", "money_remaining", "funds_earned", "sales_income", "funds_spent", "income_per_minute", "funds_spent_per_minute", "building_total", "alive_buildings", "structures_complete", "structures_under_construction", "infantry_total", "alive_units", "army_value", "building_value", "harvesters", "idle_harvesters", "waiting_harvesters", "unit_queue_total", "wounded_units", "power_generated", "power_consumed", "low_power", "units_produced", "buildings_built", "units_killed", "units_lost", "buildings_destroyed", "buildings_lost", "infantry_produced", "infantry_killed", "infantry_lost", "damage_dealt", "damage_received", "units_lost_value", "buildings_lost_value", "enemy_units_destroyed_value", "enemy_buildings_destroyed_value", "buildings_captured", "buildings_captured_lost", "buildings_sold", "peak_units", "peak_buildings", "peak_infantry", "peak_army_value", "low_power_seconds_sampled", "zero_funds_seconds_sampled", "units_by_spec", "buildings_by_spec", "unit_categories", "units_produced_by_spec", "buildings_built_by_spec", "units_killed_by_spec", "units_lost_by_spec", "buildings_destroyed_by_spec", "buildings_lost_by_spec"]
const EVENT_FIELDS := ["time", "kind", "team", "previous_team", "id", "target", "spec", "entity_kind", "construction_method", "destroyed", "result", "position", "cause", "reason", "forced"]

static func export_snapshot(snapshot: Dictionary, path_prefix: String) -> Dictionary:
	if path_prefix.strip_edges().is_empty(): return _error("导出路径为空")
	if not snapshot.get("teams") is Array or not snapshot.get("history") is Array or not snapshot.get("events") is Array:
		return _error("统计数据缺少 teams、history 或 events")
	for row: Variant in snapshot.teams:
		if not row is Dictionary: return _error("统计阵营数据格式无效")
	for sample: Variant in snapshot.history:
		if not sample is Dictionary or not sample.get("teams") is Array: return _error("统计曲线数据格式无效")
		for row: Variant in sample.teams:
			if not row is Dictionary: return _error("统计曲线中的阵营数据格式无效")
	for event: Variant in snapshot.events:
		if not event is Dictionary: return _error("统计事件数据格式无效")
	if path_prefix.ends_with(".json"): path_prefix = path_prefix.trim_suffix(".json")
	var prefix: String = ProjectSettings.globalize_path(path_prefix)
	if not prefix.is_absolute_path():
		var working_directory: DirAccess = DirAccess.open(".")
		if working_directory == null: return _error("无法读取当前导出目录：" + error_string(DirAccess.get_open_error()))
		prefix = working_directory.get_current_dir().path_join(prefix).simplify_path()
	var paths: Dictionary = {"json": prefix + ".json", "timeseries_csv": prefix + "_timeseries.csv", "summary_csv": prefix + "_summary.csv", "events_csv": prefix + "_events.csv"}
	var directory: String = prefix.get_base_dir()
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(directory)
	if directory_error != OK: return _error("无法创建导出目录：" + error_string(directory_error))
	var safe: Dictionary = _json_safe(snapshot)
	var contents: Dictionary = {
		"json": JSON.stringify(safe, "\t", true, true) + "\n",
		"timeseries_csv": _series_csv(safe),
		"summary_csv": _summary_csv(safe),
		"events_csv": _events_csv(safe)
	}
	# Stage all four files first, so an unwritable destination cannot yield an
	# apparently successful but incomplete new report. Existing bundles can be
	# re-exported (e.g. the settlement's manual export after automatic export).
	var temporary_paths: Dictionary = {}
	var token: String = ".tmp-" + str(Time.get_ticks_usec())
	for key: String in paths:
		var temp_path: String = str(paths[key]) + token
		temporary_paths[key] = temp_path
		var file: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)
		if file == null:
			_cleanup(temporary_paths)
			return _error("无法写入统计文件：" + error_string(FileAccess.get_open_error()))
		file.store_string(contents[key])
		file.flush()
		var write_error: Error = file.get_error()
		file.close()
		if write_error != OK:
			_cleanup(temporary_paths)
			return _error("统计文件写入失败：" + error_string(write_error))
	var written: Dictionary = {}
	for key: String in paths:
		var rename_error: Error = DirAccess.rename_absolute(temporary_paths[key], paths[key])
		if rename_error != OK:
			_cleanup(temporary_paths)
			return {"ok": false, "paths": written, "error": "无法保存统计文件：" + error_string(rename_error)}
		written[key] = paths[key]
	return {"ok": true, "paths": written, "error": ""}

static func _series_csv(snapshot: Dictionary) -> String:
	var header: Array = ["time", "ore_remaining"]
	header.append_array(SERIES_FIELDS)
	var lines: Array[String] = [_csv_line(header)]
	for sample: Dictionary in snapshot.history:
		for row: Dictionary in sample.get("teams", []):
			var values: Array = [sample.get("time", ""), sample.get("ore_remaining", "")]
			for field: String in SERIES_FIELDS: values.append(row.get(field, ""))
			lines.append(_csv_line(values))
	return "\n".join(lines) + "\n"

static func _summary_csv(snapshot: Dictionary) -> String:
	var fields: Array = SERIES_FIELDS.duplicate()
	# Preserve any additional scalar counters introduced by simulation hooks.
	for row: Dictionary in snapshot.teams:
		for field: String in row:
			if field not in fields: fields.append(field)
	var scope_fields: Array = ["schema_version", "duration", "result", "map_mode", "history_complete", "since_time", "telemetry_history_complete", "history_since_time", "winner_teams_known", "winner_teams", "eliminated_teams"]
	var header: Array = scope_fields.duplicate()
	header.append_array(fields)
	var lines: Array[String] = [_csv_line(header)]
	for row: Dictionary in snapshot.teams:
		var values: Array = []
		for field: String in scope_fields: values.append(snapshot.get(field, ""))
		for field: String in fields: values.append(row.get(field, ""))
		lines.append(_csv_line(values))
	return "\n".join(lines) + "\n"

static func _events_csv(snapshot: Dictionary) -> String:
	var lines: Array[String] = [_csv_line(EVENT_FIELDS)]
	for event: Dictionary in snapshot.events:
		var values: Array = []
		for field: String in EVENT_FIELDS: values.append(event.get(field, ""))
		lines.append(_csv_line(values))
	return "\n".join(lines) + "\n"

static func _csv_line(values: Array) -> String:
	var cells: Array[String] = []
	for value: Variant in values:
		var cell: String = JSON.stringify(value) if value is Dictionary or value is Array else str(value)
		if cell.contains(",") or cell.contains("\"") or cell.contains("\n") or cell.contains("\r"):
			cell = "\"" + cell.replace("\"", "\"\"") + "\""
		cells.append(cell)
	return ",".join(cells)

static func _json_safe(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value: result[str(key)] = _json_safe(value[key])
		return result
	if value is Array or value is PackedStringArray or value is PackedVector2Array or value is PackedVector3Array or value is PackedFloat32Array or value is PackedFloat64Array or value is PackedInt32Array or value is PackedInt64Array or value is PackedByteArray:
		var result: Array = []
		for item: Variant in value: result.append(_json_safe(item))
		return result
	if value is Vector2 or value is Vector2i: return [value.x, value.y]
	if value is Vector3 or value is Vector3i: return [value.x, value.y, value.z]
	if value is Color: return [value.r, value.g, value.b, value.a]
	if value is float and not is_finite(value): return null
	if value == null or value is bool or value is int or value is float or value is String: return value
	return str(value)

static func _cleanup(paths: Dictionary) -> void:
	for path: String in paths.values():
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)

static func _error(message: String) -> Dictionary:
	return {"ok": false, "paths": {}, "error": message}
