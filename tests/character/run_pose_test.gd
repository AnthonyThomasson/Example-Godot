extends GameTest

## A run looks like a run: the feet stride wider than a walk, both arms drop to the sides (a pistol is
## carried in its hand rather than aimed), and the pistol cannot be fired until the run stops.

const Rig = preload("res://scenes/character/character_rig.gd")
const WEAPON_HAND := 0


func describe() -> Dictionary:
	return {
		"name": "Running pose",
		"description": "Running strides wider than walking, drops the armed hand to the side, and holds fire; stopping restores the aim and the shot.",
		"tags": ["run", "pose", "stride", "pistol"],
		"timeout": 25.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 4000, 600))
	s.switch(&"nav.rebake", false)
	s.set_static(CharacterConfig, &"run_stamina_seconds", 30.0)
	s.actor(&"runner", &"puppet", Vector2(100, 300), { "start_slot": 3 })


func run(t: TestContext) -> void:
	var puppet := t.puppet(&"runner")
	var body := t.actor(&"runner")
	puppet.aim_at(Vector2(3900, 300))
	await t.seconds(1.0)

	var aimed: float = body.hand_position(WEAPON_HAND).length()
	t.check(aimed > 22.0, "standing, the pistol hand reaches out to aim (%.1f px)" % aimed)
	var shots := t.spawned("Projectile").size()
	puppet.shoot()
	await t.frames(3)
	t.check(t.spawned("Projectile").size() == shots + 1, "the pistol fires standing still")

	puppet.walk(Vector2.RIGHT)
	await t.seconds(0.6)
	var walk := await _gait(t, body)

	puppet.set_run(true)
	await t.seconds(0.6)
	t.require(body.is_running(), "running while holding run and moving")
	var run := await _gait(t, body)
	t.check(run.span > walk.span * 1.3, "a run strides wider than a walk (%.1f vs %.1f px)" % [run.span, walk.span])
	t.check(run.shift > 0.8, "the shoulders shift side to side as a runner steps (%.1f px)" % run.shift)
	t.check(run.head < run.shift, "the head stays steadier than the shoulders (%.1f vs %.1f px)" % [run.head, run.shift])
	t.check(run.cadence < 2.5, "a run's stride is unhurried (%.1f strides/s)" % run.cadence)
	t.check(run.flare < 5.0, "a running elbow stays in by the hand, not out to the side (%.1f px)" % run.flare)
	t.check(run.rise > 1.0, "the arms pump: the hands' heights differ by %.1f px" % run.rise)
	t.check(walk.shift < 0.5, "a walker's shoulders stay put (%.1f px)" % walk.shift)
	t.check(run.twist > 0.12, "the shoulders rock against the hips (%.2f rad)" % run.twist)
	t.check(run.rock > 0.0, "the shoulder on the forward-swinging arm's side comes forward (%.0f)" % run.rock)

	var carried: float = body.hand_position(WEAPON_HAND).length()
	t.check(carried < 19.0, "running, the pistol hand hangs by the side (%.1f px)" % carried)
	shots = t.spawned("Projectile").size()
	puppet.shoot()
	await t.frames(3)
	t.check(t.spawned("Projectile").size() == shots, "the pistol does not fire while running")

	puppet.set_run(false)
	puppet.stop()
	await t.seconds(0.8)
	t.check(not body.is_running(), "stopped")
	t.check(body.hand_position(WEAPON_HAND).length() > 22.0, "the pistol hand comes back up to aim")
	puppet.shoot()
	await t.frames(3)
	t.check(t.spawned("Projectile").size() == shots + 1, "the pistol fires again once the run is over")


## One gait sampled over a stretch of strides: `span` how far (px) a foot swings fore and aft of its hip,
## `shift` how far (px) the upper body moves sideways, `twist` how far (rad) the shoulders turn off the
## aim, `head` how far (px) the head moves sideways, `cadence` strides per second, `flare` how far (px) an elbow sits out past its hand and shoulder, `rise` the largest
## height difference (px) between the two hands, and `rock` > 0 when the shoulder on the side of the forward-swinging hand is the forward one.
func _gait(t: TestContext, body: Node) -> Dictionary:
	var span := 0.0
	var lateral := [INF, -INF]
	var turn := [INF, -INF]
	var rock := 0.0
	var head := [INF, -INF]
	var rise := 0.0
	var flare := 0.0
	var stride := 0.0
	var last: float = body.pose.stride_phase()
	for k in 60:
		await t.frames(2)
		var rig = body.rig()
		var phase: float = body.pose.stride_phase()
		stride += fposmod(phase - last, TAU)
		last = phase
		head = [minf(head[0], body.pose.head_offset.y), maxf(head[1], body.pose.head_offset.y)]
		for i in 2:  # How far an elbow sits out past both its hand and its shoulder (the run is along x).
			var out := absf(rig.point(Rig.ELBOW[i]).y)
			flare = maxf(flare, out - maxf(absf(rig.point(Rig.HAND[i]).y), absf(rig.point(Rig.SHOULDER[i]).y)))
		rise = maxf(rise, absf(rig.point(Rig.HAND[0]).z - rig.point(Rig.HAND[1]).z))
		for i in 2:
			span = maxf(span, absf(rig.point(Rig.ANKLE[i]).x - rig.point(Rig.HIP[i]).x))
		lateral = [minf(lateral[0], body.pose.torso_offset.y), maxf(lateral[1], body.pose.torso_offset.y)]
		var off := angle_difference(body.facing.angle(), body.pose.torso_angle)
		turn = [minf(turn[0], off), maxf(turn[1], off)]
		rock += (rig.point(Rig.SHOULDER[0]).x - rig.point(Rig.SHOULDER[1]).x) \
			* (body.hand_position(0).x - body.hand_position(1).x)
	return {
		"span": span, "shift": lateral[1] - lateral[0], "twist": (turn[1] - turn[0]) * 0.5, "rock": rock,
		"head": head[1] - head[0], "rise": rise, "flare": flare, "cadence": stride / TAU / (120.0 / 60.0),
	}
