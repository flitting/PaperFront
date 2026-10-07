extends RefCounted
## Authored building +Z is the ground doorway; shipyards open along +X.
## Integer quarter turns share exactly the same transform in logic and art.
static func quarters(value: Dictionary) -> int:
	return posmod(int(value.get("rotation_quarters",value.get("rail_rotation",0))),4)
static func offset(local: Vector2, turns: int) -> Vector2:
	match posmod(turns,4):
		1:return Vector2(-local.y,local.x)
		2:return -local
		3:return Vector2(local.y,-local.x)
	return local
static func point(building: Dictionary, local: Vector2) -> Vector2:
	return (building.pos as Vector2)+offset(local,quarters(building))
static func front(building: Dictionary) -> Vector2:
	return offset(Vector2.DOWN,quarters(building))
static func angle(building: Dictionary, info: Dictionary = {}) -> float:
	# Connected rails have their world-space port mask baked into the mesh.
	return 0.0 if str(info.get("role","")) in ["rail","rail_junction"] else float(quarters(building))*90.0
static func rectangle(center: Vector2, local: Rect2, turns: int) -> Rect2:
	var a: Vector2=center+offset(local.position,turns)
	var b: Vector2=center+offset(local.end,turns)
	return Rect2(a.min(b),(b-a).abs())
static func rotated_mask(mask: int, turns: int) -> int:
	var result: int = 0
	for direction in range(4):
		if mask & (1 << direction): result |= 1 << posmod(direction+turns,4)
	return result
