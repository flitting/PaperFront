extends SceneTree

## Read-only bridge/ground junction geometry inventory; no GPU work.
func _initialize() -> void:
	var records: Array[Dictionary] = []
	for mode: String in ["forest", "desert", "snow", "city", "random_city", "campaign", "dev"]:
		var map: Dictionary = MapData.generate(mode, 7)
		for bridge: Dictionary in map.bridges:
			var bounds: Array = bridge.bounds
			var center := Vector2(float(bounds[0]) + float(bounds[2]) * 0.5, float(bounds[1]) + float(bounds[3]) * 0.5)
			var height: float = MapData.height_at(map, center)
			var along_x: bool = float(bounds[2]) >= float(bounds[3])
			var length: float = maxf(float(bounds[2]), float(bounds[3]))
			var coplanar: int = 0
			for z: int in range(int(bounds[1]), int(bounds[1]) + int(bounds[3])):
				for x: int in range(int(bounds[0]), int(bounds[0]) + int(bounds[2])):
					if MapData.terrain_at(map, Vector2(x + 0.5, z + 0.5)) != MapData.WATER and is_equal_approx(MapData.height_at(map, Vector2(x + 0.5, z + 0.5)), height): coplanar += 1
			var axis: Vector2 = Vector2.RIGHT if along_x else Vector2.DOWN
			var left_focus: Vector2 = center - axis * length * 0.5
			var right_focus: Vector2 = center + axis * length * 0.5
			var old_last_edge: float = -length * 0.5 + 0.59 + float(ceili(length / 0.62) - 1) * 0.62
			records.append({"map": mode, "seed": 7, "bridge_id": bridge.id, "bounds": bounds, "deck_height": height, "coplanar_land_area_m2": coplanar,
				"old_tail_overshoot_m": old_last_edge - length * 0.5, "focus_left": [left_focus.x, left_focus.y], "focus_right": [right_focus.x, right_focus.y],
				"suggested_capture": {"distance": 40.0, "pitch": 30.0, "yaw": 0.0, "pan_axis": [axis.x, axis.y], "pan_amplitude_m": 0.5, "frames": 90}})
	print("BRIDGE_SEAM_GEOMETRY ", JSON.stringify({"bridges": records}))
	quit()
