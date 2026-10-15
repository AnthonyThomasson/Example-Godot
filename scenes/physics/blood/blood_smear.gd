class_name BloodSmear
extends Node

## Physics System, blood: smears blood along the floor for a RigidBody2D that slides through it (a Node child of the
## body, composed like Knockback). The owner gives the body's footprint (`set_footprint`, a polygon in the body's local
## space); across it sits a grid of "fingers", fixed to the body so they turn with it. While the body moves, each finger
## soaks up wet blood (BloodField) under it and, every `smear_segment_length` px, extends a ribbon (BloodDecals) behind
## it. A ribbon is wider than the finger spacing so neighbours merge into one smudge, wanders sideways on smooth noise,
## thins with the finger's load (`smear_decay_per_px`), tapers to a point where it ends and, once the load is low,
## breaks into dry-brush dashes. Over blood already on the floor a ribbon is see-through and it eases in along its first
## px, so the smear flows out of a puddle with no edge. Nothing is laid with BloodConfig.smear_enabled off.

## A finger's decay, width and pickup vary by up to this fraction, so streaks end and thicken unevenly.
const VARIATION := 0.5
## Distance (px) over which a new ribbon's sideways wander eases in from the finger's own line.
const WANDER_RAMP := 8.0
## Width of a ribbon's thinnest point, as a fraction of its full width (at a load near 0).
const MIN_WIDTH := 0.3

## Fingers: { local (Vector2), soak (0..1), prev (world Vector2, or null at rest), ribbon (open mark, or
## null), run (px laid on this ribbon), travelled (px moved), alpha (last sample's), decay, gain, width, phase }.
var _fingers: Array[Dictionary] = []
var _spacing := 6.0  ## Gap (px) between neighbouring fingers.
## Smooth noise the ribbons wander on.
var _noise := FastNoiseLite.new()


func _init() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.seed = randi()


## Lay the fingers out across `polygon` (the body's footprint, local space). Resets their blood.
func set_footprint(polygon: PackedVector2Array) -> void:
	_fingers.clear()
	if polygon.size() < 3:
		return
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for p in polygon:
		bounds = bounds.expand(p)
	# Widen the spacing until the grid fits under the cap.
	_spacing = maxf(BloodConfig.smear_finger_spacing, 0.5)
	while (bounds.size.x / _spacing + 1.0) * (bounds.size.y / _spacing + 1.0) > BloodConfig.smear_max_fingers * 1.6:
		_spacing *= 1.25
	var y := bounds.position.y + _spacing * 0.5
	while y < bounds.end.y:
		var x := bounds.position.x + _spacing * 0.5
		while x < bounds.end.x:
			var local := Vector2(x, y)
			if Geometry2D.is_point_in_polygon(local, polygon) and _fingers.size() < BloodConfig.smear_max_fingers:
				_fingers.append({
					"local": local, "soak": 0.0, "prev": null, "ribbon": null, "run": 0.0, "travelled": 0.0, "alpha": 0.0,
					"decay": 1.0 + randf_range(-VARIATION, VARIATION),
					"gain": 1.0 - randf() * VARIATION,
					"width": 1.0 + randf_range(-VARIATION, VARIATION),
					"phase": randf() * 1000.0,
				})
			x += _spacing
		y += _spacing


func _physics_process(_delta: float) -> void:
	var body := get_parent() as RigidBody2D
	if body == null or _fingers.is_empty() or not (BloodConfig.enabled and BloodConfig.smear_enabled):
		return
	if body.linear_velocity.length() < BloodConfig.smear_min_speed:
		for f in _fingers:
			f["prev"] = null  # at rest: the next move starts a fresh ribbon
			f["ribbon"] = null
			f["run"] = 0.0
		return
	for f in _fingers:
		_drag(f, body.to_global(f["local"]), body)


## Move finger `f` to world `pos`: soak what is under it, then extend (or start, or end) its ribbon.
func _drag(f: Dictionary, pos: Vector2, body: Node) -> void:
	var wet := BloodField.wetness_at(pos)
	f["soak"] = maxf(f["soak"], wet * BloodConfig.pickup_gain * f["gain"])
	if f["prev"] == null:
		f["prev"] = pos
		return
	var prev: Vector2 = f["prev"]
	var dist := prev.distance_to(pos)
	if dist < BloodConfig.smear_segment_length:
		return
	f["travelled"] += dist
	var at := pos + (pos - prev).normalized().orthogonal() * _wander(f)
	f["prev"] = pos
	if not _lays(f):
		_close(f, at)
		return
	_feed_pool(f, at)
	var decals := BloodDecals.layer(body.get_parent())
	if f["ribbon"] == null:
		f["run"] = 0.0
	else:
		f["run"] += dist
	var soak: float = clampf(f["soak"], 0.0, 1.0)
	# A ribbon eases in along its first px (a tongue, never a cut edge) and is see-through over blood that
	# is already there, so it fades in exactly as the puddle's own coverage fades out.
	var ease_in := smoothstep(0.0, maxf(BloodConfig.smear_fade_in, 0.001), f["run"])
	var absorbed := 1.0 - smoothstep(BloodConfig.smear_absorb_lo, BloodConfig.smear_absorb_hi, wet)
	var width: float = _spacing * BloodConfig.smear_width * f["width"] * lerpf(MIN_WIDTH, 1.0, sqrt(soak)) * lerpf(0.5, 1.0, ease_in)
	var target := soak * BloodConfig.smear_alpha_max * randf_range(1.0 - VARIATION * 0.4, 1.0) * ease_in * absorbed
	# Opacity may fall at once (entering blood) but only rise gradually, so the streak swells out of a
	# puddle's crisp edge instead of switching on there.
	var alpha := minf(target, f["alpha"] + BloodConfig.smear_alpha_rise) if f["ribbon"] != null else 0.0
	f["alpha"] = alpha
	if f["ribbon"] == null:
		f["ribbon"] = decals.ribbon_begin(at, width, alpha)
	else:
		decals.ribbon_extend(f["ribbon"], at, width, alpha)
		if (f["ribbon"]["points"] as PackedVector2Array).size() >= BloodConfig.smear_max_ribbon_points:
			f["ribbon"] = decals.ribbon_begin(at, width, alpha)  # carry on in a fresh one, seamlessly
			f["run"] = BloodConfig.smear_fade_in  # already eased in: no second tongue
	f["soak"] = maxf(f["soak"] - dist * BloodConfig.smear_decay_per_px * f["decay"], 0.0)


## A finger carrying plenty of blood near a pool pulls that blood out of the pool: the pool's own outline
## stretches to `at`, so the smear's thick part is drawn by the pool (same colour, rim and edge).
func _feed_pool(f: Dictionary, at: Vector2) -> void:
	if f["soak"] < BloodConfig.smear_trail_min:
		return
	var pool := BloodField.pool_near(at, BloodConfig.smear_trail_reach)
	if pool != null:
		pool.call(&"drag_out", at, f["soak"] * BloodConfig.smear_trail_gain)


## Whether finger `f` lays blood now: it carries enough and (when its load is low) wins the dry-brush
## chance that grows with the load. Blood already underfoot doesn't stop it: the ribbon just runs
## through it unseen (see `_drag`), so it is already under way when it leaves the puddle.
func _lays(f: Dictionary) -> bool:
	if f["soak"] < BloodConfig.print_min_load:
		return false
	var brk := BloodConfig.smear_break_load
	return f["soak"] >= brk or randf() < f["soak"] / maxf(brk, 0.001)


## End finger `f`'s open ribbon with a point at `at` (zero width: it tapers off).
func _close(f: Dictionary, at: Vector2) -> void:
	if f["ribbon"] == null:
		return
	var decals := BloodDecals.layer((get_parent() as Node).get_parent())
	decals.ribbon_extend(f["ribbon"], at, 0.0, 0.0)
	f["ribbon"] = null
	f["run"] = 0.0


## Sideways offset (px) of finger `f`'s ribbon from its own line: smooth noise along the distance moved,
## eased in over the first `WANDER_RAMP` px of a ribbon.
func _wander(f: Dictionary) -> float:
	var ramp := clampf(f["run"] / WANDER_RAMP, 0.0, 1.0)
	return _noise.get_noise_1d(f["travelled"] * BloodConfig.smear_wobble_freq + f["phase"]) * BloodConfig.smear_wobble * _spacing * ramp
