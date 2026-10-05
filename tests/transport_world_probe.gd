extends "res://scripts/paper_world.gd"

var circle_radii: Array[float] = []

func _guide_circle(pos: Vector2, radius: float, color: Color) -> void:
	circle_radii.append(radius)
	super._guide_circle(pos, radius, color)
