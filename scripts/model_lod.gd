extends RefCounted
class_name ModelLod

## Select by the model's projected size, rather than a world distance that
## changes meaning with zoom, window size, terrain elevation and camera pitch.
const NEAR: int = 0
const FAR: int = 1
const EXTREME: int = 2
const FAR_PIXELS: float = 64.0
const EXTREME_PIXELS: float = 20.0
const HYSTERESIS: float = .10

static func view(camera: Camera3D) -> Dictionary:
	var transform: Transform3D = camera.get_camera_transform()
	var height: float = maxf(1.0, camera.get_viewport().get_visible_rect().size.y)
	var orthographic: bool = camera.projection == Camera3D.PROJECTION_ORTHOGONAL
	var projection: Projection = camera.get_camera_projection()
	return {"origin":transform.origin,"forward":-transform.basis.z,"orthographic":orthographic,
		"scale":height*.5*absf(projection.y.y)}

static func pixels_from_view(context: Dictionary, center: Vector3, diameter: float) -> float:
	if bool(context.orthographic): return maxf(0.0,diameter)*float(context.scale)
	var depth: float = (center-(context.origin as Vector3)).dot(context.forward)
	# Behind the near plane is conservative full detail; culling owns visibility.
	if depth <= .001: return INF
	return maxf(0.0,diameter)*float(context.scale)/depth

static func projected_pixels(camera: Camera3D, center: Vector3, diameter: float) -> float:
	return pixels_from_view(view(camera),center,diameter)

static func choose(pixels: float, previous: int = NEAR, far_threshold: float = FAR_PIXELS, extreme_threshold: float = EXTREME_PIXELS) -> int:
	if not is_finite(pixels): return NEAR
	if previous < NEAR or previous > EXTREME:
		return NEAR if pixels >= far_threshold else FAR if pixels >= extreme_threshold else EXTREME
	if previous == NEAR:
		if pixels < extreme_threshold*(1.0-HYSTERESIS): return EXTREME
		return FAR if pixels < far_threshold*(1.0-HYSTERESIS) else NEAR
	if previous == EXTREME:
		if pixels > far_threshold*(1.0+HYSTERESIS): return NEAR
		return FAR if pixels > extreme_threshold*(1.0+HYSTERESIS) else EXTREME
	if pixels > far_threshold*(1.0+HYSTERESIS): return NEAR
	if pixels < extreme_threshold*(1.0-HYSTERESIS): return EXTREME
	return FAR
