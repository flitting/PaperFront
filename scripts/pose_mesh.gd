extends Node3D

## A transform and mesh reference for MultiMesh submission and picking.
## Unlike a hidden MeshInstance3D this never creates a second RenderingServer
## instance or submits transform notifications for geometry already batched.
var mesh: Mesh
var material_override: Material
var cast_shadow: int = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func get_aabb() -> AABB:
	return mesh.get_aabb() if mesh != null else AABB()
