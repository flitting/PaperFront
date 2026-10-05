extends SceneTree

const Sim = preload("res://scripts/simulation.gd")


func _initialize() -> void:
	var source_path: String = "/tmp/paper_war_stalled_rivet_dev.save"
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if not arguments.is_empty():
		source_path = arguments[0]
	var sim = Sim.new()
	var error: String = sim.load_game(source_path)
	if error != "":
		push_error(error)
		quit(1)
		return
	print("Stalled load time=", sim.time, " funds=", sim.money, " bridge=", sim.bridges)
	var building_ids: Array = []
	for building: Dictionary in sim._building_entities:
		building_ids.append(int(building.id))
	print("Rebuilt building IDs=", building_ids, " nav_dirty=", sim._nav_dirty)
	for entity: Dictionary in sim.entities.values():
		if int(entity.team) != 1 or entity.kind != "unit":
			continue
		var radius: float = sim._radius(entity)
		if str(entity.spec).ends_with("_harvester"):
			var refinery: int = sim._find_refinery(entity)
			var goal: Vector2 = sim._refinery_approach(entity, sim.entities[6])
			var path: Array = sim._path_between(entity.pos, goal, radius, int(entity.id))
			print("Vehicle ", entity.id, " radius=", radius, " pos=", entity.pos, " cargo=", entity.cargo, " path_wait=", entity.path_wait, " stuck=", entity.stuck, " chosen_refinery=", refinery, " approach=", goal, " path=", path, " rebuilt_start_id=", sim._nav_point_for_radius(entity.pos, radius, int(entity.id)), " rebuilt_goal_id=", sim._nav_point_for_radius(goal, radius, int(entity.id)))
		else:
			var target_pos: Vector2 = sim.entities[22].pos
			var weapon: Dictionary = sim.rules.weapons[str(sim.data_for(entity.spec).weapon)]
			var wanted: Vector2 = target_pos + (entity.pos - target_pos).normalized() * (float(weapon.range) - 0.5)
			var goal: Vector2 = sim._near_stand(wanted, radius, int(entity.id), 4.0, false)
			var path: Array = sim._path_between(entity.pos, goal, radius, int(entity.id))
			var old_goal: Vector2 = entity.commands[0].pos if not entity.commands.is_empty() else entity.pos
			var old_path: Array = sim._path_between(entity.pos, old_goal, radius, int(entity.id))
			print("Fighter ", entity.id, " pos=", entity.pos, " state=", entity.state, " auto_target=", entity.auto_target, " old_goal=", old_goal, " old_path_count=", old_path.size(), " factory_firing_goal=", goal, " factory_path_count=", path.size())
	quit(0)
