extends RefCounted

# The painted canopy owns its aspect ratio. Preserve placement, rotation,
# and both horizontal basis axes; cap only the existing vertical stretch.
static func corrected(key: String, transform: Transform3D) -> Transform3D:
	if not key.begins_with("tree_") and key != "trunk":
		return transform
	var horizontal: float = maxf(transform.basis.x.length(), transform.basis.z.length())
	var vertical: float = transform.basis.y.length()
	var limit: float = horizontal * 1.08
	if vertical > limit:
		transform.basis.y *= limit / vertical
	return transform
