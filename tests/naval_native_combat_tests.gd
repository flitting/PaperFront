extends SceneTree

const Sim = preload("res://scripts/simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
const Navigation = preload("res://scripts/naval_navigation.gd")
var checks: int = 0
var failures: Array[String] = []

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _initialize() -> void:
	var rules: Dictionary = Rules.load_rules("res://data/rules.json", false)
	_check(not rules.is_empty(), "rules load")
	if rules.is_empty(): _report(); return
	var sim = Sim.new()
	sim.setup_multiteam(rules, "islands", 7, ["rivet", "kestrel"], false)
	_check(sim.native_unit_dispatch_enabled and sim.native_kernels_enabled and sim._kernels != null, "native unit dispatcher is active")
	var nav = Navigation.new()
	nav.configure(sim.map, sim.bridges)
	var water: Vector2 = Vector2.INF
	var land: Vector2 = Vector2.INF
	for z in range(2, int(sim.map.size) - 2):
		if water.is_finite(): break
		for x in range(2, int(sim.map.size) - 2):
			var candidate := Vector2(x + 0.5, z + 0.5)
			if not nav.static_clear(candidate, 2.65, 1.8): continue
			for offset in [Vector2(0, -5), Vector2(0, 5), Vector2(-5, 0), Vector2(5, 0)]:
				var shore: Vector2 = candidate + offset
				if sim._standing(shore, 0.75, -1, false):
					water = candidate
					land = shore
					break
			if water.is_finite(): break
	_check(water.is_finite(), "islands map has legal ship and shore battle positions")
	if not water.is_finite(): _report(); return
	var ship: int = sim.debug_spawn(1, "kestrel_ship_frigate", water)
	var tank: int = sim.debug_spawn(0, "rivet_tank", land)
	_check(ship > 0 and tank > 0, "opposing ship and tank spawn")
	if ship <= 0 or tank <= 0: _report(); return
	var ship_hp: float = sim.entities[ship].hp
	var tank_hp: float = sim.entities[tank].hp
	sim.issue([ship], "attack", sim.entities[tank].pos, tank)
	sim.issue([tank], "attack", sim.entities[ship].pos, ship)
	for i in range(300):
		sim.step(0.05)
		if not sim.entities.has(ship) or not sim.entities.has(tank): break
		if sim.entities[ship].hp < ship_hp and sim.entities[tank].hp < tank_hp: break
	_check(sim.entities.has(ship) and sim.entities[ship].hp < ship_hp, "native bit4 allows tank to damage ship")
	_check(sim.entities.has(tank) and sim.entities[tank].hp < tank_hp, "native bit4 allows ship to fire on shore")
	_check(sim._contact_domains.has(4), "contact domain buffer populated")
	if sim.entities.has(ship) and sim.entities.has(tank):
		var source: Dictionary = sim.entities[ship]
		var enemy: Dictionary = sim.entities[tank]
		source.cooldown = 0.0
		source.alpha = rad_to_deg((enemy.pos - source.pos).angle())
		source.turret_alpha = source.alpha
		sim._launch_shot(source, enemy.pos, tank, false)
		_check(not sim.projectiles.is_empty(), "naval shot remains in flight for snapshot verification")
		var path: String = "/tmp/paper_front_naval_projectile.save"
		_check(sim.save_game(path).is_empty(), "in-flight naval projectile snapshot writes")
		var restored = Sim.new()
		_check(restored.load_game(path).is_empty() and restored.projectiles == sim.projectiles, "naval domains and negative water offsets survive snapshot loading")
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		var snapshot: Dictionary = file.get_var(false)
		file.close()
		var invalid: Dictionary = snapshot.duplicate(true)
		invalid.projectiles[0].targets = ["naval", "naval"]
		_check(not preload("res://scripts/sim_save_validator.gd").check(invalid).is_empty(), "snapshot still rejects duplicate target domains")
		invalid = snapshot.duplicate(true)
		invalid.projectiles[0].targets = ["orbital"]
		_check(not preload("res://scripts/sim_save_validator.gd").check(invalid).is_empty(), "snapshot still rejects unknown target domains")
		DirAccess.remove_absolute(path)
	_report()

func _report() -> void:
	print("Naval native combat checks: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
