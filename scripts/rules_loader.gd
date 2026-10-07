class_name RulesLoader
extends RefCounted

## All gameplay values and animation paths come from this one configuration.
## Invalid configuration never yields a partially usable set of rules.
static var errors: Array[String] = []


static func load_rules(path: String = "res://data/rules.json", check_assets: bool = true) -> Dictionary:
	errors.clear()
	if not FileAccess.file_exists(path):
		errors.append("%s: rules file does not exist" % path)
		return {}
	var source: String = FileAccess.get_file_as_string(path)
	errors = _duplicate_keys(source)
	var json: JSON = JSON.new()
	var parse_error: Error = json.parse(source)
	if parse_error != OK:
		errors.append("%s:%d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	if not json.data is Dictionary:
		errors.append("$: expected a JSON object")
		return {}
	var data: Dictionary = json.data
	errors.append_array(validate(data, check_assets))
	if not errors.is_empty():
		return {}
	return data


static func load_and_validate(path: String = "res://data/rules.json", check_assets: bool = true) -> Dictionary:
	var rules: Dictionary = load_rules(path, check_assets)
	return {"rules": rules, "errors": errors.duplicate()}


static func validate(data: Dictionary, check_assets: bool = true) -> Array[String]:
	var issues: Array[String] = []
	for category: String in ["economy", "factions", "units", "buildings", "weapons"]:
		if not data.get(category) is Dictionary:
			issues.append("$.%s: expected an object" % category)
	if not issues.is_empty():
		return issues
	_positive(data, "version", "$", issues, false)
	var economy: Dictionary = data.economy
	for key: String in ["initial_money", "ore_capacity", "ore_regen", "harvester_capacity", "harvest_rate", "construction_animation", "repair_rate", "repair_cost", "bridge_hp", "bridge_cost", "bridge_time", "build_radius", "fire_angle"]:
		_positive(economy, key, "$.economy", issues, key in ["ore_regen", "repair_cost", "bridge_cost"])
	# Optional so a saved match without the role table retains its own rules.
	if economy.has("construction_radii"):
		if not economy.construction_radii is Dictionary:
			issues.append("$.economy.construction_radii: expected an object")
		else:
			var radii: Dictionary = economy.construction_radii
			_positive(radii, "default", "$.economy.construction_radii", issues, false)
			for raw_role: Variant in radii:
				var role: String = str(raw_role)
				if role not in ["default", "hq", "power", "refinery", "barracks", "factory", "tower", "tech", "wall", "barricade", "outpost", "repair", "command", "airfield", "shipyard", "drill", "rail", "rail_junction"]:
					issues.append("$.economy.construction_radii.%s: unknown building role" % role)
				elif role != "default":
					_positive(radii, role, "$.economy.construction_radii", issues, true)
	for key: String in ["low_power_multiplier", "sell_ratio"]:
		_positive(economy, key, "$.economy", issues, true)
		if _number(economy.get(key)) and float(economy[key]) > 1.0:
			issues.append("$.economy.%s: expected a ratio in [0, 1]" % key)
	if _number(economy.get("fire_angle")) and float(economy.fire_angle) > 180.0:
		issues.append("$.economy.fire_angle: expected an angle no greater than 180 degrees")
	var factions: Dictionary = data.factions
	var buildings: Dictionary = data.buildings
	var weapons: Dictionary = data.weapons
	var all_ids: Dictionary = {}
	for category: String in ["factions", "units", "buildings", "weapons"]:
		var items: Dictionary = data[category]
		if items.is_empty():
			issues.append("$.%s: cannot be empty" % category)
		for raw_id: Variant in items:
			var id: String = str(raw_id)
			var prefix: String = "$.%s.%s" % [category, id]
			if id.is_empty() or not _stable_id(id):
				issues.append("%s: ID must contain lowercase letters, digits or underscores" % prefix)
			# Weapon IDs intentionally equal their owning unit IDs; references are namespaced.
			var scoped_id: String = category + ":" + id
			if category in ["units", "buildings"]:
				scoped_id = "entity:" + id
			if all_ids.has(scoped_id):
				issues.append("%s: duplicate ID" % prefix)
			all_ids[scoped_id] = true
			if not items[raw_id] is Dictionary:
				issues.append("%s: expected an object" % prefix)
				continue
			var spec: Dictionary = items[raw_id]
			if category == "factions":
				for key: String in ["name", "mark"]:
					_text(spec, key, prefix, issues)
				if spec.has("building_method") and spec.building_method not in ["hq", "engineer"]:
					issues.append("%s.building_method: expected hq or engineer" % prefix)
				if spec.has("traits"):
					if not spec.traits is Dictionary:
						issues.append("%s.traits: expected an object" % prefix)
					else:
						# Old snapshot keys remain readable but no longer affect gameplay.
						for key: String in ["regen_delay", "regen_fraction_per_second"]:
							if spec.traits.has(key): _positive(spec.traits, key, prefix + ".traits", issues, false)
						for key: String in ["regen_fraction_per_second"]:
							if _number(spec.traits.get(key)) and float(spec.traits[key]) > 1.0: issues.append("%s.traits.%s: expected a ratio no greater than 1" % [prefix, key])
				continue
			if category == "weapons":
				if spec.has("penetration"):
					_positive(spec,"penetration",prefix,issues,true)
					if _number(spec.penetration) and (float(spec.penetration)!=floorf(float(spec.penetration)) or float(spec.penetration)>9999): issues.append(prefix+".penetration: expected integer 0..9999")
				if spec.has("aoe_falloff") and spec.aoe_falloff!="linear": issues.append(prefix+".aoe_falloff: expected linear")
				if spec.has("friendly_fire") and not spec.friendly_fire is bool: issues.append(prefix+".friendly_fire: expected boolean")
				for key: String in ["damage", "interval", "range"]:
					_positive(spec, key, prefix, issues, false)
				_positive(spec, "blast", prefix, issues, true)
				_positive(spec, "speed", prefix, issues, spec.get("kind") in ["instant", "laser", "beam"])
				if spec.get("kind") not in ["instant", "shell", "laser", "beam"]:
					issues.append("%s.kind: expected instant, shell, laser or beam" % prefix)
				if spec.has("trajectory"):
					if str(spec.trajectory) not in ["gravity_bomb","nail"] or spec.get("kind") != "shell": issues.append("%s.trajectory: expected gravity_bomb or nail shell" % prefix)
					if str(spec.trajectory)=="gravity_bomb":
						for field in ["gravity","inherited_velocity"]: _positive(spec,field,prefix,issues,field=="inherited_velocity")
				if spec.has("targets"):
					_domains(spec.targets, prefix + ".targets", issues)
				if spec.has("multipliers"):
					_multipliers(spec.multipliers, prefix + ".multipliers", issues)
				for key: String in ["emp_vehicle_duration", "emp_building_duration"]:
					if spec.has(key): _positive(spec, key, prefix, issues, false)
				if spec.has("execute_building") and not spec.execute_building is bool:
					issues.append("%s.execute_building: expected a boolean" % prefix)
				if bool(spec.get("execute_building", false)) and (spec.get("kind") != "instant" or not _number(spec.get("blast")) or float(spec.get("blast", 0.0)) != 0.0):
					issues.append("%s.execute_building: requires a direct instant weapon" % prefix)
				continue
			if spec.has("tier") and (not _number(spec.tier) or float(spec.tier)!=floorf(float(spec.tier)) or int(spec.tier)<0 or int(spec.tier)>3): issues.append("%s.tier: expected integer 0..3" % prefix)
			if spec.has("armor"):
				_positive(spec,"armor",prefix,issues,true)
				if _number(spec.armor) and (float(spec.armor)!=floorf(float(spec.armor)) or float(spec.armor)>9999): issues.append(prefix+".armor: expected integer 0..9999")
			for key: String in ["name", "faction", "art"]:
				_text(spec, key, prefix, issues)
			for key: String in ["cost", "hp", "build_time"]:
				_positive(spec, key, prefix, issues, key == "cost")
			for group: Array in [["rescue_radius", "rescue_speed_bonus"], ["designation_radius", "designation_track_time", "damage_bonus"], ["overcharge_radius", "overcharge_window", "overcharge_recharge", "overcharge_cost", "overcharge_power", "damage_bonus"]]:
				if spec.has(group[0]):
					for key: String in group: _positive(spec, key, prefix, issues, false)
			for key: String in ["rescue_speed_bonus", "damage_bonus"]:
				if spec.has(key) and _number(spec[key]) and float(spec[key]) > 1.0: issues.append("%s.%s: expected a ratio no greater than 1" % [prefix, key])
			if spec.has("aircraft_repair_rate"): _positive(spec, "aircraft_repair_rate", prefix, issues, false)
			var faction: String = str(spec.get("faction", ""))
			if not factions.has(faction):
				issues.append("%s.faction: unknown faction '%s'" % [prefix, faction])
			if not spec.get("requires") is Array:
				issues.append("%s.requires: expected an array of building IDs" % prefix)
			else:
				var seen_requires: Dictionary = {}
				for prerequisite: Variant in spec.requires:
					if not prerequisite is String or not buildings.has(prerequisite):
						issues.append("%s.requires: unknown building '%s'" % [prefix, str(prerequisite)])
					elif buildings[prerequisite] is Dictionary and buildings[prerequisite].get("faction") != faction:
						issues.append("%s.requires: prerequisite '%s' belongs to another faction" % [prefix, prerequisite])
					if seen_requires.has(str(prerequisite)):
						issues.append("%s.requires: duplicate prerequisite '%s'" % [prefix, str(prerequisite)])
					seen_requires[str(prerequisite)] = true
			var weapon: Variant = spec.get("weapon")
			if not weapon is String or (not str(weapon).is_empty() and not weapons.has(weapon)):
				issues.append("%s.weapon: unknown weapon '%s'" % [prefix, str(weapon)])
			if spec.has("secondary_weapon") and (not spec.secondary_weapon is String or not weapons.has(str(spec.secondary_weapon))):
				issues.append("%s.secondary_weapon: unknown independent weapon" % prefix)
			if category == "units":
				if spec.has("roster_hidden") and not spec.roster_hidden is bool:issues.append(prefix+".roster_hidden: expected boolean")
				if spec.has("naval_role") and spec.naval_role not in ["basic","transport","aa","heavy","support","carrier","submarine","amphibious"]:issues.append(prefix+".naval_role: unknown naval role")
				if spec.has("max_active"):
					_positive(spec, "max_active", prefix, issues, false)
					if _number(spec.max_active) and float(spec.max_active) != floorf(float(spec.max_active)):
						issues.append("%s.max_active: expected a whole number" % prefix)
				if spec.has("hero") and not spec.hero is bool: issues.append("%s.hero: expected a boolean" % prefix)
				if bool(spec.get("hero", false)):
					for key: String in ["attack_windup", "attack_recovery"]: _positive(spec, key, prefix, issues, false)
				if spec.get("domain", "ground") not in ["ground", "air", "naval"]:
					issues.append("%s.domain: expected ground, air or naval" % prefix)
				if spec.has("armor_class") and spec.armor_class not in ["infantry", "armored"]:
					issues.append("%s.armor_class: expected infantry or armored" % prefix)
				if spec.get("domain", "ground") == "air":
					for key: String in ["flight_height", "ammo_capacity", "rearm_time"]:
						_positive(spec, key, prefix, issues, false)
					if _number(spec.get("ammo_capacity")) and float(spec.ammo_capacity) != floor(float(spec.ammo_capacity)):
						issues.append("%s.ammo_capacity: expected a whole number" % prefix)
					if spec.get("producer") not in ["airfield","carrier"] or (spec.get("producer")=="carrier" and not bool(spec.get("internal_only",false))) or spec.get("crush", false) or spec.get("crushable", false):
						issues.append("%s: aircraft require an airfield producer and cannot crush or be crushable" % prefix)
				elif spec.get("producer") == "airfield":
					issues.append("%s.producer: airfield can only produce aircraft" % prefix)
				for key: String in ["repair_radius", "repair_rate"]:
					if spec.has(key): _positive(spec, key, prefix, issues, false)
				if spec.get("domain", "ground") == "naval": _positive(spec, "naval_air_draft", prefix, issues, false)
				if spec.has("transport_capacity"):
					_positive(spec, "transport_capacity", prefix, issues, true)
					if _number(spec.get("transport_capacity")) and float(spec.transport_capacity) != floor(float(spec.transport_capacity)):
						issues.append("%s.transport_capacity: expected a whole number" % prefix)
					var ground_carrier: bool = spec.get("domain", "ground") == "ground" and spec.get("art") in ["scout", "transport"]
					var air_carrier: bool = spec.get("domain", "ground") == "air" and spec.get("art") == "air_transport" and str(spec.get("weapon", "")).is_empty()
					var naval_carrier: bool = spec.get("domain", "ground") == "naval" and spec.get("art") in ["naval_transport","naval_hovercraft"] and str(spec.get("weapon", "")).is_empty()
					if _number(spec.get("transport_capacity")) and float(spec.transport_capacity) > 0.0 and not ground_carrier and not air_carrier and not naval_carrier:
						issues.append("%s.transport_capacity: expected a personnel carrier or unarmed transport aircraft" % prefix)
				for key: String in ["speed", "radius", "turn_speed"]:
					_positive(spec, key, prefix, issues, false)
				for key: String in ["crush", "crushable"]:
					if not spec.get(key) is bool:
						issues.append("%s.%s: expected a boolean" % [prefix, key])
				for key: String in ["has_turret", "fire_while_moving"]:
					if spec.has(key) and not spec[key] is bool:
						issues.append("%s.%s: expected a boolean" % [prefix, key])
				if spec.has("turret_turn_speed"):
					_positive(spec, "turret_turn_speed", prefix, issues, false)
				if spec.get("has_turret", false) and not spec.has("turret_turn_speed") and spec.get("domain", "ground") != "naval":
					issues.append("%s.turret_turn_speed: required for configured turret" % prefix)
				if spec.get("fire_while_moving", false) and (not spec.get("has_turret", false) or str(weapon).is_empty()) and spec.get("domain", "ground") != "naval":
					issues.append("%s.fire_while_moving: requires a turret and weapon" % prefix)
				var producer: String = str(spec.get("producer", ""))
				if producer not in ["barracks", "factory", "airfield", "shipyard","amphibious","carrier"] or (producer=="carrier" and not bool(spec.get("internal_only",false))) or (producer=="amphibious" and not (_has_producer(buildings,faction,"factory") and _has_producer(buildings,faction,"shipyard"))) or (producer not in ["amphibious","carrier"] and not _has_producer(buildings, faction, producer)):
					issues.append("%s.producer: missing faction producer '%s'" % [prefix, producer])
			else:
				if spec.has("rebuildable"):
					if not spec.rebuildable is bool: issues.append("%s.rebuildable: expected a boolean" % prefix)
					if spec.get("role") != "hq": issues.append("%s.rebuildable: only headquarters may enable rebuilding" % prefix)
				if spec.get("domain", "ground") not in ["ground", "naval"] or (spec.get("domain", "ground") == "naval" and spec.get("role") != "shipyard"):
					issues.append("%s.domain: only shipyards may use the naval building surface" % prefix)
				_positive(spec, "size", prefix, issues, false)
				if _number(spec.get("size")) and float(spec.size) != floor(float(spec.size)):
					issues.append("%s.size: footprint must be an integer number of cells" % prefix)
				if not _number(spec.get("power")):
					issues.append("%s.power: expected a finite numeric supply/demand value" % prefix)
				if spec.has("local_power") or spec.has("local_power_radius"):
					_positive(spec, "local_power", prefix, issues, false)
					_positive(spec, "local_power_radius", prefix, issues, false)
					if spec.get("role") not in ["hq", "barracks"]: issues.append("%s.local_power: only headquarters or barracks bases may supply local power" % prefix)
				for key: String in ["production_roles", "prerequisite_roles"]:
					if not spec.has(key): continue
					if not spec[key] is Array or spec[key].is_empty():
						issues.append("%s.%s: expected a nonempty array of producer roles" % [prefix, key])
						continue
					var seen_roles: Dictionary = {}
					var allowed_roles: Array[String] = ["barracks", "factory", "airfield", "shipyard"]
					if key == "prerequisite_roles": allowed_roles.append("hq")
					for role: Variant in spec[key]:
						if role not in allowed_roles or seen_roles.has(str(role)):
							issues.append("%s.%s: expected unique supported producer roles" % [prefix, key])
						seen_roles[str(role)] = true
					if spec.get("role") != "hq" and not (key == "prerequisite_roles" and spec.get("role") == "barracks"):
						issues.append("%s.%s: only headquarters and barracks bases may alias these roles" % [prefix, key])
				if spec.get("role") not in ["hq", "power", "refinery", "barracks", "factory", "tower", "tech", "wall", "barricade", "outpost", "repair", "command", "airfield", "shipyard", "drill", "rail", "rail_junction"]:
					issues.append("%s.role: unknown building role" % prefix)
				if spec.get("role") == "shipyard":
					if spec.get("domain", "ground") == "ground":
						_positive(spec, "coast_split", prefix, issues, false)
					elif spec.has("coast_split"):
						_positive(spec, "coast_split", prefix, issues, true)
					_positive(spec, "harbor_depth", prefix, issues, false)
				if spec.get("role") == "airfield":
					_positive(spec, "aircraft_capacity", prefix, issues, false)
					if _number(spec.get("aircraft_capacity")) and float(spec.aircraft_capacity) != floor(float(spec.aircraft_capacity)):
						issues.append("%s.aircraft_capacity: expected a whole number" % prefix)
				if spec.get("role") == "repair":
					if spec.has("service_rate"):
						_positive(spec, "service_rate", prefix, issues, false)
					else:
						for key: String in ["repair_radius", "repair_rate"]: _positive(spec, key, prefix, issues, false)
				if spec.has("vision_bonus"): _positive(spec, "vision_bonus", prefix, issues, true)
				if spec.has("construction_radius"): _positive(spec, "construction_radius", prefix, issues, true)
				if not spec.get("expands") is bool:
					issues.append("%s.expands: expected a boolean" % prefix)
			_validate_animations(spec, category == "units", prefix, check_assets, issues)
	var visit: Dictionary = {}
	for id: Variant in buildings:
		_check_cycle(str(id), buildings, visit, [], issues)
	return issues


static func _has_producer(buildings: Dictionary, faction: String, role: String) -> bool:
	for info: Variant in buildings.values():
		if not info is Dictionary or str(info.get("faction", "")) != faction: continue
		if str(info.get("role", "")) == role: return true
		var roles: Variant = info.get("production_roles", [])
		if roles is Array and role in roles: return true
	return false


static func _domains(value: Variant, prefix: String, issues: Array[String]) -> void:
	if not value is Array or value.is_empty():
		issues.append("%s: expected a nonempty domain array" % prefix)
		return
	var seen: Dictionary = {}
	for domain: Variant in value:
		if domain not in ["ground", "air", "naval"] or seen.has(str(domain)):
			issues.append("%s: domains must be unique ground/air/naval values" % prefix)
		seen[str(domain)] = true

static func _multipliers(value: Variant, prefix: String, issues: Array[String]) -> void:
	if not value is Dictionary:
		issues.append("%s: expected an armor multiplier object" % prefix)
		return
	for armor: Variant in value:
		if armor not in ["building", "armored", "infantry"] or not _number(value[armor]) or float(value[armor]) < 0.0:
			issues.append("%s.%s: expected a nonnegative multiplier for a known armor class" % [prefix, str(armor)])

static func _validate_animations(spec: Dictionary, unit: bool, prefix: String, check_assets: bool, issues: Array[String]) -> void:
	if not spec.get("animations") is Dictionary:
		issues.append("%s.animations: missing animation mapping" % prefix)
		return
	var animations: Dictionary = spec.animations
	var states: Array[String] = ["idle", "death"]
	if unit:
		states.append_array(["move", "hit"])
		if not str(spec.get("weapon", "")).is_empty():
			states.append("attack")
	for state: String in states:
		if not animations.get(state) is String or str(animations[state]).is_empty():
			issues.append("%s.animations.%s: missing animation path" % [prefix, state])
		elif check_assets and not ResourceLoader.exists(str(animations[state])):
			issues.append("%s.animations.%s: missing file '%s'" % [prefix, state, animations[state]])


static func _check_cycle(id: String, buildings: Dictionary, visit: Dictionary, chain: Array, issues: Array[String]) -> void:
	if int(visit.get(id, 0)) == 2:
		return
	if int(visit.get(id, 0)) == 1:
		var names: Array = chain.duplicate()
		names.append(id)
		issues.append("$.buildings.%s.requires: prerequisite cycle %s" % [id, " -> ".join(names)])
		return
	visit[id] = 1
	var next_chain: Array = chain.duplicate()
	next_chain.append(id)
	if buildings.get(id) is Dictionary and buildings[id].get("requires") is Array:
		for dependency: Variant in buildings[id].requires:
			if dependency is String and buildings.has(dependency):
				_check_cycle(dependency, buildings, visit, next_chain, issues)
	visit[id] = 2


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _positive(source: Dictionary, key: String, prefix: String, issues: Array[String], allow_zero: bool) -> void:
	if not _number(source.get(key)) or float(source[key]) < 0.0 or (not allow_zero and float(source[key]) == 0.0):
		issues.append("%s.%s: expected a finite %s number" % [prefix, key, "nonnegative" if allow_zero else "positive"])


static func _text(source: Dictionary, key: String, prefix: String, issues: Array[String]) -> void:
	if not source.get(key) is String or str(source[key]).is_empty():
		issues.append("%s.%s: expected a nonempty string" % [prefix, key])


static func _stable_id(id: String) -> bool:
	for i: int in id.length():
		var code: int = id.unicode_at(i)
		if not (code >= 97 and code <= 122) and not (code >= 48 and code <= 57) and code != 95:
			return false
	return true


## JSON.parse silently keeps the last duplicate dictionary key. Scan source first
## so an accidentally repeated stable ID is reported with its original path.
static func _duplicate_keys(source: String) -> Array[String]:
	var issues: Array[String] = []
	var stack: Array[Dictionary] = []
	var i: int = 0
	while i < source.length():
		var character: String = source.substr(i, 1)
		if character == "{" or character == "[":
			var path: String = "$"
			if not stack.is_empty():
				var parent: Dictionary = stack.back()
				path = str(parent.path) + ("." + str(parent.pending) if not str(parent.pending).is_empty() else "[]")
			stack.append({"kind": character, "path": path, "keys": {}, "pending": ""})
		elif character == "}" or character == "]":
			if not stack.is_empty():
				stack.pop_back()
		elif character == '"':
			var start: int = i
			i += 1
			while i < source.length() and source.substr(i, 1) != '"':
				if source.substr(i, 1) == "\\":
					i += 1
				i += 1
			var after: int = i + 1
			while after < source.length() and source.substr(after, 1) in [" ", "\t", "\r", "\n"]:
				after += 1
			if after < source.length() and source.substr(after, 1) == ":" and not stack.is_empty() and stack.back().kind == "{":
				var decoded: Variant = JSON.parse_string(source.substr(start, i - start + 1))
				var key: String = str(decoded)
				var frame: Dictionary = stack.back()
				if frame.keys.has(key):
					issues.append("%s.%s: duplicate JSON key / stable ID" % [frame.path, key])
				frame.keys[key] = true
				frame.pending = key
		i += 1
	return issues
