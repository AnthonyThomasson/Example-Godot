extends GameTest

## S2, S3 (ticket #56, `docs/grenades.md` G13): a stunned character bends over a little and staggers.
## - Hunch (S2): the spine and neck pitch forward by `CharacterConfig.stun_hunch_pitch` x `stun_level()`, on top of a crouch's own
##   pitch, and a bang that only deafens hunches too. It eases in and out with the level.
## - Stagger (S3): walking stunned, the strides are shorter and uneven, the hips sway and the head bobs more than walking unstunned.
##   The pace stays G13's x0.45 and the walk still drifts.
## - Smooth: the head and the pelvis never move more in one frame than an eased change does.
## Read off the standing skeleton (`rig()`), the pose's stride phase and the `footfall` events.

const Rig = preload("res://scenes/character/body/character_rig.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")

const STUN := 6.0
## The pitch measured off the rig (the line from the pelvis to the chest) against the one asked for: within this many degrees.
const PITCH_TOLERANCE := 4.0
## The most the head or the pelvis may move in one frame (px, 3D) as a stun comes on or wears off.
const STEP := 3.0
## Lanes (y) of the two walkers; they walk +x.
const LANE_NORMAL := 150.0
const LANE_STUNNED := 450.0


func describe() -> Dictionary:
	return {
		"name": "A stunned character hunches and staggers",
		"description": "Stunned, the spine pitches forward by stun_hunch_pitch x stun_level (crouched too, deaf-only too), easing in and out; walking, the strides are shorter and uneven, the hips sway and the head bobs, at 0.45 of the speed with the drift; no jumps.",
		"tags": ["grenade", "stun", "pose", "rig", "stride", "character"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 3200, 900))
	s.switch(&"nav.rebake", false)
	s.set_static(CharacterConfig, &"posture_change_time", 0.0)
	s.actor(&"stand", &"puppet", Vector2(150, 750), { "start_slot": 3, "max_health": 100000.0 })
	s.actor(&"crouch", &"puppet", Vector2(450, 750), { "start_slot": 3, "max_health": 100000.0 })
	s.actor(&"deaf", &"puppet", Vector2(750, 750), { "start_slot": 3, "max_health": 100000.0 })
	s.actor(&"normal", &"puppet", Vector2(100, LANE_NORMAL), { "start_slot": 3, "max_health": 100000.0 })
	s.actor(&"stunned", &"puppet", Vector2(100, LANE_STUNNED), { "start_slot": 3, "max_health": 100000.0 })


## The forward pitch (degrees) of `c`'s spine, from the pelvis to the chest, along its facing.
func _pitch(c: Node) -> float:
	var rig = c.rig()
	var chest: Vector3 = rig.point(Rig.CHEST)
	var pelvis: Vector3 = rig.point(Rig.PELVIS)
	var lean: float = Vector2(chest.x - pelvis.x, chest.y - pelvis.y).dot(c.facing)
	return rad_to_deg(atan2(lean, chest.z - pelvis.z))


## `CharacterConfig.stun_hunch_pitch` (rad), read by name; -1 when it does not exist.
func _hunch() -> float:
	var v: Variant = (CharacterConfig as Script).get(&"stun_hunch_pitch")
	return float(v) if v != null else -1.0


## Each frame until `until[0]`, the largest one-frame move (px) of the head and of the pelvis of each of `ids`, kept in `jumps`.
func _watch_jumps(t: TestContext, ids: Array, jumps: Dictionary, until: Array) -> void:
	var last := {}
	while not until[0]:
		for id: StringName in ids:
			var rig = t.actor(id).rig()
			var now := [rig.point(Rig.HEAD), rig.point(Rig.PELVIS)]
			if last.has(id):
				jumps[id] = maxf(jumps.get(id, 0.0), maxf(now[0].distance_to(last[id][0]), now[1].distance_to(last[id][1])))
			last[id] = now
		await t.frames(1)


## A stretch of walking by `id` along +x: `speed` (px/s along the walk), `drift` (the largest offset off its lane's line reached during
## the stretch, px, sampled every frame), `stride` (px walked per
## stride cycle), `step_cv` (the spread of its step lengths, standard deviation over mean, from its footfalls), `sway` (the range of
## the pelvis's side-to-side place, px) and `bob` (how far the head moves about on the body: the largest of its ranges along the walk,
## across it and in height, px; an unstunned walk bobs it ~0.4 px along the walk, twice a stride).
func _gait(t: TestContext, id: StringName, lane: float, seconds: float) -> Dictionary:
	var c := t.actor(id)
	var from: Vector2 = c.global_position
	var since := t.events_of(&"footfall").size()
	var phase := 0.0
	var last_phase: float = c.pose.stride_phase()
	var sway := [INF, -INF]
	var head_lo := Vector3.INF
	var head_hi := -Vector3.INF
	var drift := 0.0
	var frames := int(seconds * 60.0)
	for i in frames:
		await t.frames(1)
		var rig = c.rig()
		drift = maxf(drift, absf(c.global_position.y - lane))
		var now: float = c.pose.stride_phase()
		phase += fposmod(now - last_phase, TAU)
		last_phase = now
		var pelvis: Vector3 = rig.point(Rig.PELVIS)
		var head: Vector3 = rig.point(Rig.HEAD)
		sway = [minf(sway[0], pelvis.y), maxf(sway[1], pelvis.y)]
		head_lo = head_lo.min(head)
		head_hi = head_hi.max(head)
	var head_range := head_hi - head_lo
	var walked: float = c.global_position.x - from.x
	var steps: Array = []
	var prev: Variant = null
	var falls := t.events_of(&"footfall")
	for k in range(since, falls.size()):
		var at: Vector2 = falls[k]["position"]
		if absf(at.y - lane) > 120.0:
			continue
		if prev != null:
			steps.append((prev as Vector2).distance_to(at))
		prev = at
	var mean := 0.0
	for s: float in steps:
		mean += s
	mean /= maxf(steps.size(), 1)
	var spread := 0.0
	for s: float in steps:
		spread += (s - mean) * (s - mean)
	spread = sqrt(spread / maxf(steps.size(), 1))
	return {
		"speed": walked / seconds, "drift": drift, "stride": walked / maxf(phase / TAU, 0.01),
		"steps": steps.size(), "step_cv": spread / maxf(mean, 0.01), "sway": sway[1] - sway[0], "bob": maxf(head_range.x, maxf(head_range.y, head_range.z)),
	}


func run(t: TestContext) -> void:
	for id: StringName in [&"stand", &"crouch", &"deaf", &"normal", &"stunned"]:
		t.puppet(id).aim_at(t.actor(id).global_position + Vector2(5000, 0))
	t.puppet(&"crouch").set_posture(&"crouch")
	await t.seconds(1.5)
	var hunch := _hunch()
	t.check(hunch > 0.0, "CharacterConfig.stun_hunch_pitch exists (%s)" % str(hunch))
	var upright := _pitch(t.actor(&"stand"))
	var crouched := _pitch(t.actor(&"crouch"))
	t.check(absf(upright) < 3.0, "unstunned, a standing spine is upright (%.1f degrees)" % upright)

	# --- S2: the hunch, easing in with the stun.
	var jumps := {}
	var stop := [false]
	_watch_jumps(t, [&"stand", &"crouch", &"deaf"], jumps, stop)
	Probe.stun(t.actor(&"stand"), STUN, STUN)
	Probe.stun(t.actor(&"crouch"), STUN, STUN)
	Probe.stun(t.actor(&"deaf"), 0.0, STUN)
	await t.frames(1)
	t.check(_pitch(t.actor(&"stand")) < upright + maxf(hunch, 2.0) * 0.5, "the hunch does not snap in on the frame of the stun (%.1f degrees)" % _pitch(t.actor(&"stand")))
	await t.seconds(1.0)
	var level := Probe.level(t.actor(&"stand"))
	t.check(level >= 0.95, "(the stun is at its full level: %.2f)" % level)
	var bent := _pitch(t.actor(&"stand"))
	t.check(bent - upright >= 5.0, "stunned, the standing body bends over (%.1f degrees forward)" % (bent - upright))
	t.check(hunch > 0.0 and absf(bent - upright - hunch * level) <= PITCH_TOLERANCE, "stunned, the spine pitches forward by stun_hunch_pitch x level (%.1f degrees, want %.1f)" % [bent - upright, hunch * level])
	var bent_crouched := _pitch(t.actor(&"crouch"))
	t.check(hunch > 0.0 and absf(bent_crouched - crouched - hunch * level) <= PITCH_TOLERANCE, "crouched, the hunch comes on top of the crouch's own pitch (%.1f over %.1f degrees, want %.1f)" % [bent_crouched - crouched, crouched, hunch * level])
	var bent_deaf := _pitch(t.actor(&"deaf"))
	t.check(bent_deaf - upright >= maxf(hunch, 0.0) * 0.75 and bent_deaf - upright >= 5.0, "a bang that only deafens hunches too (%.1f degrees)" % (bent_deaf - upright))

	# The tail: the hunch falls with the level.
	await t.until(func() -> bool: return Probe.level(t.actor(&"stand")) <= 0.5, STUN)
	await t.seconds(0.2)
	var tail_level := Probe.level(t.actor(&"stand"))
	var tail := _pitch(t.actor(&"stand")) - upright
	t.check(tail < (bent - upright) * 0.8 and tail > 0.0, "as the stun tails off the hunch eases with it (%.1f degrees at level %.2f, %.1f at full)" % [tail, tail_level, bent - upright])
	await t.until(func() -> bool: return Probe.level(t.actor(&"stand")) <= 0.0 and Probe.level(t.actor(&"deaf")) <= 0.0, 3.0)
	await t.seconds(0.6)
	t.check(absf(_pitch(t.actor(&"stand")) - upright) < 2.0, "once recovered the spine is upright again (%.1f degrees)" % _pitch(t.actor(&"stand")))
	stop[0] = true
	await t.frames(1)
	for id: StringName in [&"stand", &"crouch", &"deaf"]:
		t.check(float(jumps.get(id, 0.0)) <= STEP, "%s: the head and the pelvis never moved more than %.0f px in a frame (worst %.1f px)" % [id, STEP, float(jumps.get(id, 0.0))])

	# --- S3: the stagger. Two walkers side by side, one stunned.
	Probe.stun(t.actor(&"stunned"), STUN, STUN)
	t.puppet(&"normal").walk(Vector2.RIGHT)
	t.puppet(&"stunned").walk(Vector2.RIGHT)
	await t.seconds(0.8)
	var both := [{}, {}]
	var normal_walk := func() -> void: both[0] = await _gait(t, &"normal", LANE_NORMAL, 3.0)
	normal_walk.call()
	both[1] = await _gait(t, &"stunned", LANE_STUNNED, 3.0)
	await t.frames(2)
	var normal: Dictionary = both[0]
	var staggered: Dictionary = both[1]
	t.check(Probe.level(t.actor(&"stunned")) >= 0.95, "(the walker was at its full stun throughout: %.2f)" % Probe.level(t.actor(&"stunned")))
	GameLog.say("gait normal %s / stunned %s" % [str(normal), str(staggered)])
	var ratio: float = staggered["speed"] / maxf(normal["speed"], 1.0)
	t.check(ratio >= 0.38 and ratio <= 0.5, "stunned it still walks at x0.45 of its pace (x%.2f: %.0f of %.0f px/s)" % [ratio, staggered["speed"], normal["speed"]])
	t.check(staggered["drift"] >= 3.0, "and still drifts off its line (largest offset %.1f px)" % staggered["drift"])
	t.check(staggered["stride"] <= normal["stride"] * 0.8, "its strides are shorter (%.0f px a stride against %.0f)" % [staggered["stride"], normal["stride"]])
	t.check(staggered["steps"] >= 4 and normal["steps"] >= 4, "(both walkers stepped: %d and %d footfalls)" % [staggered["steps"], normal["steps"]])
	t.check(staggered["step_cv"] >= 0.1 and staggered["step_cv"] >= normal["step_cv"] * 2.0, "and uneven (step lengths spread %.2f against %.2f)" % [staggered["step_cv"], normal["step_cv"]])
	t.check(staggered["sway"] >= 2.0 and staggered["sway"] >= normal["sway"] * 2.0, "the hips sway (%.1f px side to side against %.1f)" % [staggered["sway"], normal["sway"]])
	t.check(staggered["bob"] >= normal["bob"] * 1.5 + 0.5, "the head bobs about on the body (%.1f px against %.1f)" % [staggered["bob"], normal["bob"]])
