extends RefCounted
class_name MiniatureLens

## A broad sharp middle distance, with gradual foreground/background bokeh.
## Depth follows the terrain-aware camera target, so orbiting never moves focus
## to a fixed world strip. CanvasLayer controls remain outside the 3D effect.
const SUBJECT_HEIGHT: float = 1.0
const SHARP_TOP: float = 0.28
const SHARP_BOTTOM: float = 0.72

static func create() -> CameraAttributesPractical:
	var attributes := CameraAttributesPractical.new()
	attributes.dof_blur_near_enabled = true
	attributes.dof_blur_far_enabled = true
	attributes.auto_exposure_enabled = false
	return attributes


static func update(camera: Camera3D, attributes: CameraAttributesPractical, target: Vector3, distance: float) -> void:
	# The DOF buffer contains view-space Z, not Euclidean distance. The camera's
	# horizontal offset and the ground elevation must be included in this pose.
	var subject: Vector3 = target + Vector3.UP * SUBJECT_HEIGHT
	var view: Transform3D = camera.get_camera_transform().affine_inverse()
	var depth: float = -(view * subject).z
	# Fixed fractions of zoom put both blur regions outside the visible terrain
	# at steeper camera pitches. Project a central screen band onto the focus
	# plane instead, so pitch, FOV and viewport aspect all affect the clear range.
	var plane := Plane(Vector3.UP, subject.y)
	var near_depth: float = _plane_depth(camera, view, plane, SHARP_BOTTOM, depth - distance * 0.18)
	var far_depth: float = _plane_depth(camera, view, plane, SHARP_TOP, depth + distance * 0.22)
	# Keep the focused ground and the top of an ordinary unit/building clear,
	# including the closest supported zoom on elevated plateaus.
	var subject_top: float = -(view * (target + Vector3.UP * 3.0)).z
	var subject_ground: float = -(view * target).z
	near_depth = minf(near_depth, subject_top - 0.4)
	far_depth = maxf(far_depth, subject_ground + 0.4)
	attributes.dof_blur_near_distance = maxf(camera.near + 1.0, near_depth)
	attributes.dof_blur_far_distance = far_depth
	attributes.dof_blur_near_transition = maxf(1.0, (depth - near_depth) * 0.65)
	attributes.dof_blur_far_transition = maxf(1.5, (far_depth - depth) * 0.60)
	# Close views have a stronger miniature feel; the wide tactical overview
	# keeps small silhouettes legible while retaining the same bokeh pipeline.
	attributes.dof_blur_amount = lerpf(0.13, 0.07, smoothstep(54.0, 110.0, distance))


static func _plane_depth(camera: Camera3D, view: Transform3D, plane: Plane, fraction: float, fallback: float) -> float:
	var size: Vector2 = camera.get_viewport().get_visible_rect().size
	var pixel := Vector2(size.x * 0.5, size.y * fraction)
	var hit: Variant = plane.intersects_ray(camera.project_ray_origin(pixel), camera.project_ray_normal(pixel))
	if hit == null: return fallback
	var depth: float = -(view * (hit as Vector3)).z
	return depth if is_finite(depth) and depth > camera.near else fallback


static func metadata(attributes: CameraAttributesPractical) -> Dictionary:
	return {
		"near_enabled": attributes.dof_blur_near_enabled,
		"far_enabled": attributes.dof_blur_far_enabled,
		"near_distance": attributes.dof_blur_near_distance,
		"far_distance": attributes.dof_blur_far_distance,
		"near_transition": attributes.dof_blur_near_transition,
		"far_transition": attributes.dof_blur_far_transition,
		"blur_amount": attributes.dof_blur_amount,
		"bokeh_quality": ProjectSettings.get_setting("rendering/camera/depth_of_field/depth_of_field_bokeh_quality"),
		"bokeh_shape": ProjectSettings.get_setting("rendering/camera/depth_of_field/depth_of_field_bokeh_shape"),
		"jitter": ProjectSettings.get_setting("rendering/camera/depth_of_field/depth_of_field_use_jitter")
	}
