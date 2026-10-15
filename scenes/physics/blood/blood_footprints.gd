class_name BloodFootprints
extends Node

## Physics System, blood: bloody footprints for a walker (a Node child of the host, composed like BloodWound). The owner
## reports each footfall with `step`; a foot that lands in wet blood (BloodField) soaks up a load of it, and every
## footfall after that stamps a sole print whose opacity follows the load, which drops a little per print, so the trail
## fades out over a dozen steps. A low load prints broken and patchy (the arch and edges drop out); a fast, heavy foot
## slips a little forward. Prints go to the world's BloodDecals. Nothing is stamped in blood that is already thick, nor
## with BloodConfig.footprints_enabled off.

## Points along the sole outline, per side.
const SOLE_STEPS := 14

## Blood on each foot, 0..1, by the owner's foot id.
var _load: Dictionary = {}


## A foot lands at world `at` (the middle of the sole), toes toward unit `direction`, sole `length` x
## `width` px, moving at `speed` px/s. `inner` is +1/-1: which side of the direction's frame (+y =
## `direction.orthogonal()`) the foot's arch faces.
func step(foot: int, at: Vector2, direction: Vector2, length: float, width: float, inner: float, speed: float) -> void:
	if not (BloodConfig.enabled and BloodConfig.footprints_enabled):
		return
	var host := get_parent()
	if host == null or host.get_parent() == null:
		return
	var wet := 0.0
	for k in [-0.35, 0.0, 0.35]:
		wet = maxf(wet, BloodField.wetness_at(at + direction * length * k))
	var soak: float = maxf(_load.get(foot, 0.0), wet * BloodConfig.pickup_gain)
	if soak >= BloodConfig.print_min_load and wet < BloodConfig.thick_blood:
		var poly := _sole(at, direction, length, width, inner, soak, speed)
		var alpha := lerpf(BloodConfig.print_alpha_min, BloodConfig.print_alpha_max, clampf(soak, 0.0, 1.0))
		BloodDecals.layer(host.get_parent()).print_at(poly, alpha)
		soak -= BloodConfig.print_decay
	_load[foot] = maxf(soak, 0.0)


## The sole outline in world space: heel at the back, arch on the `inner` side, ball, rounded toe.
## `soak` (the foot's load) thins the arch and roughens the edge; `speed` and `soak` slip it forward.
func _sole(at: Vector2, direction: Vector2, length: float, width: float, inner: float, soak: float, speed: float) -> PackedVector2Array:
	var fraction := clampf(soak, 0.0, 1.0)
	length += BloodConfig.print_slip * fraction * clampf(speed / 120.0, 0.0, 1.0)
	var turn := randf_range(-1.0, 1.0) * BloodConfig.print_turn_jitter
	var forward := direction.rotated(turn)
	var side := forward.orthogonal()
	var centre := at + Vector2.from_angle(randf() * TAU) * randf() * BloodConfig.print_jitter
	var rough := (1.0 - fraction) * 0.25
	var arch := lerpf(0.05, 0.55, smoothstep(0.1, 0.6, fraction))  # how much of the arch prints
	var outer_pts: Array[Vector2] = []
	var inner_pts: Array[Vector2] = []
	for i in SOLE_STEPS + 1:
		var t := float(i) / SOLE_STEPS
		var along := (t - 0.5) * length
		var cap := sqrt(clampf(t / 0.1, 0.0, 1.0)) * sqrt(clampf((1.0 - t) / 0.16, 0.0, 1.0))
		var body := _profile(t)
		var arch_dip := 1.0 - (1.0 - arch) * _arch_weight(t)
		var half_out := width * 0.5 * body * cap * (1.0 + randf_range(-rough, rough))
		var half_in := width * 0.5 * body * cap * arch_dip * (1.0 + randf_range(-rough, rough))
		outer_pts.append(centre + forward * along - side * inner * half_out)
		inner_pts.append(centre + forward * along + side * inner * half_in)
	var poly := PackedVector2Array()
	for p in outer_pts:
		poly.append(p)
	for i in range(inner_pts.size() - 1, -1, -1):
		poly.append(inner_pts[i])
	return _dedupe(poly)


## Width of the sole along its length (0 heel .. 1 toe): a narrow heel, a wide ball.
func _profile(t: float) -> float:
	return lerpf(0.62, 1.0, smoothstep(0.35, 0.75, t))


## 1 across the arch (about a third of the way along), falling to 0 at heel and ball.
func _arch_weight(t: float) -> float:
	return smoothstep(0.18, 0.34, t) * (1.0 - smoothstep(0.46, 0.62, t))


## The outline without the repeated points the rounded caps make, which would break triangulation.
func _dedupe(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		if out.is_empty() or out[out.size() - 1].distance_squared_to(p) > 0.0004:
			out.append(p)
	if out.size() > 1 and out[0].distance_squared_to(out[out.size() - 1]) <= 0.0004:
		out.remove_at(out.size() - 1)
	return out
