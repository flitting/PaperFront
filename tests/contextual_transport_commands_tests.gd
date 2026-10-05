extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
const Transport = preload("res://scripts/transport_commands.gd")
var failures: Array[String] = []
var checks: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _initialize() -> void:
	var sim = Sim.new()
	sim.setup(Rules.load_rules(), "dev", 7, "iron", false)
	var scout: int = sim.debug_spawn(0, "iron_scout", Vector2(22.5, 42.5))
	var rifle: int = sim.debug_spawn(0, "iron_rifle", Vector2(18.5, 42.5))
	var engineer: int = sim.debug_spawn(0, "iron_engineer", Vector2(17.5, 42.5))
	var enemy: int = sim.debug_spawn(1, "sky_air_transport", Vector2(36.5, 42.5))
	check(not bool(Transport.menu_state(sim, []).enabled), "no selection disables the transport command")
	check(not bool(Transport.menu_state(sim, [enemy]).enabled), "enemy transport cannot enable friendly transport controls")
	check(bool(Transport.menu_state(sim, [rifle]).load), "friendly infantry can target an available carrier")
	var first: Dictionary = Transport.load_at(sim, [scout], rifle, false)
	check(first.passengers == [rifle] and sim.entities[rifle].commands[0].kind == "board", "carrier-first load targets a legal infantry passenger")
	check(Transport.free_seats(sim, scout) == 0 and not bool(Transport.menu_state(sim, [scout]).load), "in-flight boarding reserves the last seat and disables further loading")
	var overflow: Dictionary = Transport.load_at(sim, [engineer], scout, false)
	check(overflow.passengers.is_empty() and str(overflow.error).contains("满员"), "second passenger cannot reserve an already claimed seat")
	check(Transport.load_at(sim, [scout], enemy, false).passengers.is_empty(), "load cursor refuses an enemy passenger or carrier")
	sim.issue([rifle], "stop", Vector2.ZERO)
	check(Transport.free_seats(sim, scout) == 1, "canceling an outstanding board order releases its reservation")
	check(Transport.load_at(sim, [engineer], scout, false).passengers == [engineer], "passenger-first load targets the same authoritative boarding operation")
	for frame in range(180): sim.step(1.0 / 30.0)
	check(int(sim.entities[engineer].get("transport_id", -1)) == scout and bool(Transport.menu_state(sim, [scout]).unload), "board order physically loads passenger and enables unload")
	check(not bool(Transport.menu_state(sim, [scout]).load), "a fully occupied carrier offers only unloading")
	check(not Transport.destination_error(sim, scout, Vector2(-1, -1)).is_empty(), "destination outside map is rejected")
	check(Transport.destination_error(sim, scout, Vector2(30.5, 42.5)).is_empty(), "open ground is a valid ground-carrier unloading destination")
	check(not Transport.board(sim, [rifle], -1, false).error.is_empty(), "invalid or deleted transport target returns a player-facing error")
	print("Contextual transport commands: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
