extends "res://scripts/landscape.gd"

## Capture authoritative CPU transforms before MultiMesh uploads them.
## The headless Dummy backend does not support reading that buffer back.
var frozen_prop_batches: Array = []


func _flush_batches() -> void:
	frozen_prop_batches.clear()
	for key: String in _batches:
		var group: Dictionary = _batches[key]
		var transforms: Array = []
		for transform: Transform3D in group.transforms:
			transforms.append([transform.basis.x.x, transform.basis.x.y, transform.basis.x.z, transform.basis.y.x, transform.basis.y.y, transform.basis.y.z, transform.basis.z.x, transform.basis.z.y, transform.basis.z.z, transform.origin.x, transform.origin.y, transform.origin.z])
		frozen_prop_batches.append({"name": "PropBatch_" + key.replace(":", "_"), "mesh_key": key.get_slice(":", 0), "shadow": GeometryInstance3D.SHADOW_CASTING_SETTING_ON if bool(group.shadow) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "transforms": transforms})
	super._flush_batches()
