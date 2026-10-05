class_name GoldenVisual
extends RefCounted

## G0 is an opt-in visual fixture. It never advances a match or replaces RTS rules.
## The checked-in manifest owns actual positions, terrain and prop transforms.
const MANIFEST_PATH := "res://data/golden_visual_v1.json"
const FORMAT := "paper_war_golden_visual"
const VERSION := 1
const TICK := 135
const SEED := 73026
const SIMULATION = preload("res://scripts/simulation.gd")
const PROP_CAPTURE = preload("res://scripts/golden_landscape_capture.gd")


static func load_or_build(rules: Dictionary, path: String = MANIFEST_PATH) -> Dictionary:
	if FileAccess.file_exists(path):
		return _load(rules, path)
	return build(rules, path)


static func build(rules: Dictionary, path: String = MANIFEST_PATH) -> Dictionary:
	var rule_errors: Array[String] = RulesLoader.validate(rules, false)
	if not rule_errors.is_empty():
		return _error("G0 规则无效：" + rule_errors[0], path)
	var sim: WarSimulation = SIMULATION.new()
	sim.setup(rules, "handmade", SEED, "rivet", false)
	var selection: Array[int] = []
	for team: int in range(2):
		var mirror: float = 1.0 if team == 0 else -1.0
		var base := Vector2(63.0 if team == 0 else 97.0, 92.0)
		var buildings: Array = [["hq", Vector2(-5, -3)], ["power", Vector2(-8, 5)], ["barracks", Vector2(-5, 14)], ["refinery", Vector2(1, 15)], ["factory", Vector2(1, 5)], ["tower", Vector2(7, -5)]]
		for item: Array in buildings:
			var spec: String = sim.factions[team] + "_" + str(item[0])
			var offset: Vector2 = item[1]
			var desired: Vector2 = base + Vector2(offset.x * mirror, offset.y)
			var spot: Vector2 = _find_spot(sim, desired, float(sim.data_for(spec).size) * 0.6, team, spec)
			if not spot.is_finite():
				return _error("G0 无法找到合法建筑位置：" + spec, path)
			var id: int = sim.debug_spawn(team, spec, spot)
			if id < 0:
				return _error("G0 创建建筑失败：" + spec, path)
			sim.entities[id].construct_remaining = 0.0
			sim.entities[id].gift_pending = false
		var mine: Vector2 = _find_spot(sim, base + Vector2(0, 21), 1.4)
		if not mine.is_finite():
			return _error("G0 无法找到合法矿点", path)
		sim.map.mines.append({"pos": [mine.x, mine.y], "capacity": 3000})
		sim.mines.append({"pos": mine, "capacity": 3000.0, "amount": 3000.0})
	# Use the real paid order schema, then freeze its explicitly chosen progress.
	var build_error: String = sim.build(0, "rivet_power")
	if build_error != "":
		return _error("G0 创建固定订单失败：" + build_error, path)
	var order: Dictionary = sim.building_orders[0]
	order.progress = 0.3
	order.remaining = float(order.total) * 0.7
	order.ready = false
	sim.time = float(TICK) / 30.0
	for team: int in range(2):
		var mirror: float = 1.0 if team == 0 else -1.0
		var base := Vector2(70.0 if team == 0 else 90.0, 99.0)
		var roster: Array[String] = ["tank", "rifle", "anti", "rifle", "tank", "engineer", "rifle", "rifle", "harvester", "rifle", "anti", "assault" if team == 0 else "demolition"]
		for index: int in range(roster.size()):
			var role: String = roster[index]
			var spec: String = sim.factions[team] + "_" + role
			var desired: Vector2 = base + Vector2(-float(index % 3) * 3.0 * mirror, float(index / 3) * 3.0)
			if index == 0:
				desired = Vector2(75.0 if team == 0 else 85.0, 96.5)
			var spot: Vector2 = _find_spot(sim, desired, float(sim.data_for(spec).radius))
			if not spot.is_finite():
				return _error("G0 无法找到合法单位位置：" + spec, path)
			var id: int = sim.debug_spawn(team, spec, spot)
			if id < 0:
				return _error("G0 创建单位失败：" + spec, path)
			var entity: Dictionary = sim.entities[id]
			entity.harvest_override = true
			entity.alpha = 0.0 if team == 0 else 180.0
			entity.turret_alpha = entity.alpha
			if role == "tank":
				entity.alpha = (-25.0 if index == 0 else 20.0) if team == 0 else (155.0 if index == 0 else 205.0)
				entity.turret_alpha = (10.0 if index == 0 else -15.0) if team == 0 else (180.0 if index == 0 else 175.0)
				if team == 0:
					selection.append(id)
			elif role == "assault":
				entity.alpha = -8.0
				entity.turret_alpha = 25.0
	sim.events.clear()
	sim.notices.clear()
	var snapshot: Dictionary = _snapshot(sim)
	var validation_error: String = SIMULATION.SaveValidator.check(_with_rules(snapshot, rules))
	if validation_error != "":
		return _error("G0 固定状态验证失败：" + validation_error, path)
	var bytes: PackedByteArray = var_to_bytes(snapshot)
	var landscape: Node3D = PROP_CAPTURE.new()
	landscape._build(sim)
	var prop_batches: Array = landscape.frozen_prop_batches.duplicate(true)
	landscape.free()
	var manifest: Dictionary = {
		"format": FORMAT, "version": VERSION, "id": "G0", "seed": SEED,
		"tick": TICK, "simulation_time": sim.time, "visual_time": 0.0, "warmup_frames": 8,
		"camera": {"focus": [80.0, 102.0], "pitch": 30.0, "yaw": 0.32, "distance": 54.0, "h_offset": 8.10, "fov": 42.0, "near": 0.2, "far": 500.0},
		"render": {"renderer": "forward_plus", "physical_size": [1920, 1080], "logical_size": [1600, 900], "stretch": "canvas_items", "msaa_3d": 1, "shadow_size": 2048, "ssao_quality": 2},
		"light": {"rotation_degrees": [-48.0, -32.0, 0.0], "color": "ffe3b6", "energy": 1.3, "ambient_color": "b9cee1", "ambient_energy": 0.35, "background": "514439", "tonemap": "filmic", "reflection": "disabled", "ssao_radius": 1.35, "ssao_intensity": 1.15, "ssao_power": 1.4, "ssao_detail": 0.45, "ssao_light_affect": 0.28, "shadow_splits": 2, "shadow_max_distance": 105.0, "shadow_bias": 0.045, "shadow_normal_bias": 0.75, "shadow_blend_splits": true},
		"ui": {"selection": selection, "tab": "build", "scroll_vertical": 0, "menu_visible": false, "placing": false, "diagnostic_text": "G0 · 固定帧", "feedback": "G0 固定视觉场景 · 仿真与动画暂停"},
		"rules_hash": JSON.stringify(rules, "", true).sha256_text(),
		"map_hash": JSON.stringify(sim.map, "", true).sha256_text(),
		"state_encoding": "godot_variant_base64", "state_hash": _hash_bytes(bytes), "state_base64": Marshalls.raw_to_base64(bytes),
		"entities": _record_entities(sim, selection), "prop_batches": prop_batches,
		"rng": {"map_seed": SEED, "prop_seed": SEED + 61841, "noise_seed": SEED, "clock": "frozen", "source": "resolved map and prop transforms; no fresh placement on load"}
	}
	manifest.fixture_hash = _manifest_hash(manifest)
	var write_error: String = export_manifest(path, manifest)
	if write_error != "":
		return _error(write_error, path)
	# First creation uses the same standard save loader as every later startup.
	var result: Dictionary = _load(rules, path)
	result.created = true
	return result


static func _load(rules: Dictionary, path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return _error("G0 manifest 无法解析：" + path, path)
	var manifest: Dictionary = parsed
	if manifest.get("format") != FORMAT or int(manifest.get("version", -1)) != VERSION or manifest.get("id") != "G0":
		return _error("G0 manifest 格式不兼容", path)
	if not manifest.get("state_base64") is String or not manifest.get("state_hash") is String or not manifest.get("fixture_hash") is String:
		return _error("G0 manifest 缺少固定状态", path)
	if _manifest_hash(manifest) != manifest.fixture_hash:
		return _error("G0 manifest 校验失败；请通过 export_manifest 显式保存校准", path)
	var bytes: PackedByteArray = Marshalls.base64_to_raw(manifest.state_base64)
	if _hash_bytes(bytes) != manifest.state_hash:
		return _error("G0 固定状态校验失败", path)
	var decoded: Variant = bytes_to_var(bytes)
	if not decoded is Dictionary:
		return _error("G0 固定状态损坏", path)
	var snapshot: Dictionary = _with_rules(decoded, rules)
	var validation_error: String = SIMULATION.SaveValidator.check(snapshot)
	if validation_error != "":
		return _error("G0 固定状态不兼容：" + validation_error, path)
	var metadata_error: String = _check_metadata(manifest, snapshot)
	if metadata_error != "":
		return _error(metadata_error, path)
	# Reuse the game's validated loader without exposing a second loading policy.
	var temporary: String = "user://g0_load_%d_%d.pfront" % [OS.get_process_id(), Time.get_ticks_usec()]
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _error("G0 临时状态无法写入：" + error_string(FileAccess.get_open_error()), path)
	file.store_var(snapshot, false)
	file.close()
	var sim: WarSimulation = SIMULATION.new()
	var load_error: String = sim.load_game(temporary)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
	if load_error != "":
		return _error("G0 固定状态无法加载：" + load_error, path)
	var selection: Array[int] = []
	for id in manifest.ui.selection:
		selection.append(int(id))
	var camera: Dictionary = manifest.camera.duplicate(true)
	camera.focus = Vector2(float(camera.focus[0]), float(camera.focus[1]))
	return {"sim": sim, "selection": selection, "camera": camera, "fixture_hash": str(manifest.fixture_hash), "tick": int(manifest.tick), "manifest_path": path, "manifest": manifest, "error": "", "created": false, "rules_hash_changed": JSON.stringify(rules, "", true).sha256_text() != manifest.rules_hash}


## Call after world.setup and before its first sync(0). Main owns the paused
## physics/input policy, lighting, HUD and eight-frame capture barrier.
static func apply_world(world: PaperWorld, manifest: Dictionary) -> void:
	world.elapsed = float(manifest.visual_time)
	world.frame_delta = 0.0
	for model: Dictionary in world.models.values():
		if bool(model.get("volumetric", false)):
			model.volume.clock = float(manifest.visual_time)
	for effect: Dictionary in world.effects:
		effect.root.queue_free()
	world.effects.clear()
	for ghost: Dictionary in world.ghosts:
		ghost.root.queue_free()
	world.ghosts.clear()
	for shell: Node3D in world.shells:
		shell.queue_free()
	world.shells.clear()
	_restore_props(world.landscape, manifest.prop_batches)


## Explicit calibration saves a new hash. Ordinary startup never rewrites G0.
static func export_manifest(path: String, manifest: Dictionary) -> String:
	manifest.fixture_hash = _manifest_hash(manifest)
	var absolute: String = ProjectSettings.globalize_path(path)
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if directory_error != OK:
		return "G0 manifest 目录无法建立：" + error_string(directory_error)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "G0 manifest 无法写入：" + error_string(FileAccess.get_open_error())
	file.store_string(JSON.stringify(manifest, "\t", true) + "\n")
	file.close()
	return ""


static func _find_spot(sim: WarSimulation, desired: Vector2, radius: float, team: int = -1, spec: String = "") -> Vector2:
	for ring: int in range(16):
		var count: int = maxi(1, ring * 8)
		for index: int in range(count):
			var position: Vector2 = desired + Vector2.from_angle(float(index) / float(count) * TAU) * float(ring) * 1.8
			if position.x < 2.0 or position.y < 2.0 or position.x > float(sim.map.size) - 2.0 or position.y > float(sim.map.size) - 2.0:
				continue
			if spec == "":
				if sim._standing(position, radius, -1, true):
					return position
			else:
				var previous: Dictionary = sim.building_orders[team]
				sim.building_orders[team] = {"spec": spec, "ready": true}
				position = sim.snap_build_position(team, position)
				var problem: String = sim.placement_error(team, position)
				sim.building_orders[team] = previous
				# This explicitly marked developer fixture is not base expansion.
				if problem != "" and problem != "超出己方已完成建筑的扩建范围":
					continue
				var padded: bool = true
				for entity: Dictionary in sim.entities.values():
					var other_radius: float = float(sim.data_for(entity.spec).size) * 0.73 if entity.kind == "building" else float(sim.data_for(entity.spec).radius)
					if (entity.pos as Vector2).distance_to(position) < other_radius + radius + 0.1:
						padded = false
						break
				if padded:
					return position
	return Vector2.INF


static func _snapshot(sim: WarSimulation) -> Dictionary:
	# Rules are supplied by the current build, not restored from a historical save.
	return {"format": "paper_war", "version": WarSimulation.SAVE_VERSION, "map": sim.map.duplicate(true), "factions": sim.factions.duplicate(), "money": sim.money.duplicate(), "time": sim.time, "result": sim.result, "entities": sim.entities.duplicate(true), "projectiles": [], "mines": sim.mines.duplicate(true), "bridges": sim.bridges.duplicate(true), "ruins": sim.ruins.duplicate(true), "building_orders": sim.building_orders.duplicate(true), "next_id": sim._next_id, "ai_enabled": false, "ai_clock": 0.0, "ai_attack_clock": 0.0, "low_power": [false, false], "nav_dirty": true, "nav_regions": [], "planning_max_wait": 0.0, "planning_queue": []}


static func _with_rules(snapshot: Dictionary, rules: Dictionary) -> Dictionary:
	var result: Dictionary = snapshot.duplicate(true)
	result.rules = rules.duplicate(true)
	return result


static func _record_entities(sim: WarSimulation, selection: Array) -> Array:
	var result: Array = []
	for id in sim.entities:
		var entity: Dictionary = sim.entities[id]
		result.append({"id": int(id), "spec": entity.spec, "kind": entity.kind, "team": int(entity.team), "pos": [entity.pos.x, entity.pos.y], "height": MapData.height_at(sim.map, entity.pos), "alpha": entity.alpha, "turret_alpha": entity.turret_alpha, "hp": entity.hp, "state": entity.state, "selected": selection.has(id)})
	return result


static func _restore_props(landscape: Node3D, groups: Array) -> void:
	for child: Node in landscape.get_children():
		if child is MultiMeshInstance3D and str(child.name).begins_with("PropBatch_"):
			landscape.remove_child(child)
			child.queue_free()
	var instances: int = 0
	for group: Dictionary in groups:
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = landscape._prop_mesh(str(group.mesh_key))
		multi.instance_count = group.transforms.size()
		for index: int in range(multi.instance_count):
			multi.set_instance_transform(index, _array_transform(group.transforms[index]))
		var instance := MultiMeshInstance3D.new()
		instance.name = group.name
		instance.multimesh = multi
		instance.cast_shadow = int(group.shadow)
		landscape.add_child(instance)
		instances += multi.instance_count
	landscape.stats.prop_instances = instances
	landscape.stats.prop_draws = groups.size()


static func _array_transform(values: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(values[0], values[1], values[2]), Vector3(values[3], values[4], values[5]), Vector3(values[6], values[7], values[8])), Vector3(values[9], values[10], values[11]))


static func _hash_bytes(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


static func _manifest_hash(manifest: Dictionary) -> String:
	var content: Dictionary = manifest.duplicate(true)
	content.erase("fixture_hash")
	# JSON parsing promotes integers to floats. Hash the JSON-normalized form so
	# the first export and later reads have exactly the same canonical payload.
	var normalized: Variant = JSON.parse_string(JSON.stringify(content, "", true))
	return JSON.stringify(normalized, "", true).sha256_text()


static func _check_metadata(manifest: Dictionary, snapshot: Dictionary) -> String:
	for field: String in ["camera", "ui", "render", "light"]:
		if not manifest.get(field) is Dictionary:
			return "G0 元数据缺少：" + field
	if int(manifest.get("tick", -1)) != TICK or float(manifest.get("visual_time", -1.0)) != 0.0 or not is_equal_approx(float(snapshot.time), float(TICK) / 30.0):
		return "G0 固定时钟无效"
	if int(snapshot.map.get("seed", -1)) != SEED or snapshot.map.get("mode") != "handmade" or snapshot.ai_enabled or not snapshot.projectiles.is_empty():
		return "G0 场景或无特效约束无效"
	if not manifest.camera.get("focus") is Array or manifest.camera.focus.size() != 2 or not manifest.ui.get("selection") is Array or manifest.ui.selection.size() != 2:
		return "G0 镜头或选择状态无效"
	for key: String in ["pitch", "yaw", "distance", "h_offset", "fov", "near", "far"]:
		if not _finite_number(manifest.camera.get(key)):
			return "G0 镜头参数无效：" + key
	if not manifest.get("prop_batches") is Array:
		return "G0 缺少固定 props"
	for group in manifest.prop_batches:
		if not group is Dictionary or not group.get("name") is String or not group.get("mesh_key") is String or not group.get("transforms") is Array or not _finite_number(group.get("shadow")):
			return "G0 props 分组无效"
		if str(group.mesh_key) not in ["tree_0", "tree_1", "tree_2", "rock_0", "rock_1", "rock_2", "trunk", "fence", "ruin", "contact", "context_wall_broken", "context_wall_stub", "context_wall_corner_r", "context_wall_corner_l"]:
			return "G0 props 类型无效"
		for transform in group.transforms:
			if not transform is Array or transform.size() != 12:
				return "G0 props 变换无效"
			for value in transform:
				if not _finite_number(value):
					return "G0 props 变换包含非数值"
			if absf(float(transform[9])) + absf(float(transform[11])) < 0.001:
				return "G0 props 位于原点；必须记录 CPU 变换，不能读取 Dummy 渲染器缓冲"
	var buildings: int = 0
	var units: int = 0
	for entity: Dictionary in snapshot.entities.values():
		buildings += 1 if entity.kind == "building" else 0
		units += 1 if entity.kind == "unit" else 0
		if entity.state != "idle" or float(entity.construct_remaining) != 0.0 or float(entity.attack_flash) != 0.0 or float(entity.hit_flash) != 0.0 or not entity.commands.is_empty():
			return "G0 实体没有处于静态主帧"
	if buildings != 14 or units != 24:
		return "G0 建筑/单位数量无效"
	for id in manifest.ui.selection:
		if not _finite_number(id) or not snapshot.entities.has(int(id)) or snapshot.entities[int(id)].spec != "rivet_tank":
			return "G0 必须选中两辆蓝军普通坦克"
	return ""


static func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _error(message: String, path: String) -> Dictionary:
	return {"sim": null, "selection": [], "camera": {}, "fixture_hash": "", "tick": TICK, "manifest_path": path, "manifest": {}, "error": message, "created": false}
