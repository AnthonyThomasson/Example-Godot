extends GameTest

## G13: a stunned character (player and NPC alike) is slowed to at most `stun_speed` x0.45 with a slow drift, cannot run, and
## its aim sways (a wandering offset up to `stun_sway` 25 degrees applied to where its shots go). The effect tails off over
## the last `recover_tail` 1.5 s and then it is as before. `stun_level()` reads 0..1; a new stun takes the longer of the old and
## the new timers.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const SPEED := 150.0
const TARGET := Vector2(1100, 500)


func describe() -> Dictionary:
	return {
		"name": "A stunned character is slow, cannot run and cannot aim straight",
		"description": "take_stun(4, 4): the puppet walks at under half speed, a held run is refused, its pistol shots (zero spread) stray up to 25 degrees; after the stun it is back to normal; stun timers take the longer.",
		"tags": ["grenade", "stun", "slow", "sway", "character"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1200, 700))
	var straight: Dictionary = GunConfig.guns.duplicate(true)
	for gun: StringName in straight:
		straight[gun]["spread_deg"] = 0.0
	s.set_static(GunConfig, "guns", straight)
	s.switch(&"projectile.flyover", false)
	s.actor(&"walker", &"puppet", Vector2(100, 150), { "max_health": 100000.0 })
	s.actor(&"shooter", &"puppet", Vector2(100, 500), { "start_slot": 3, "max_health": 100000.0 })
	s.actor(&"target", &"puppet", TARGET, { "max_health": 100000.0 })


## Metres per second walked in `span` s heading right from the walker's spot, then back where it started.
func _walk_speed(t: TestContext, span: float) -> float:
	var walker := t.actor(&"walker")
	walker.global_position = Vector2(100, 150)
	await t.frames(2)
	var from: Vector2 = walker.global_position
	t.puppet(&"walker").walk(Vector2.RIGHT)
	await t.seconds(span)
	t.puppet(&"walker").stop()
	return from.distance_to(walker.global_position) / span


## A full magazine in the shooter's pistol (it fires a dozen rounds a phase).
func _top_up(t: TestContext) -> void:
	if t.actor(&"shooter").ammo() < 12:
		t.puppet(&"shooter").reload()
		await t.seconds(2.0)


## The largest angle (degrees) any of `shots` pistol rounds strays from the straight line to the target, one every 0.25 s.
func _stray(t: TestContext, shots: int) -> float:
	var shooter := t.actor(&"shooter")
	await _top_up(t)
	var seen := {}
	var worst := 0.0
	for i in shots:
		var line: Vector2 = (TARGET - shooter.global_position).normalized()
		t.puppet(&"shooter").shoot()
		await t.frames(2)
		for n in t.world.get_children():
			if String(n.name).begins_with("Projectile") and not seen.has(n.get_instance_id()):
				seen[n.get_instance_id()] = true
				worst = maxf(worst, absf(rad_to_deg(line.angle_to(n.get("direction")))))
		await t.seconds(0.25)
	return worst


func run(t: TestContext) -> void:
	var walker := t.actor(&"walker")
	if not t.require(walker.has_method("take_stun") and walker.has_method("stun_level"), "Character.take_stun(blind, deaf, from) and stun_level() exist"):
		return
	t.puppet(&"shooter").aim_at(t.actor(&"target"))
	t.puppet(&"walker").aim_at(Vector2(1100, 150))
	await t.seconds(0.5)

	# --- Before: the baseline, so the numbers below mean something.
	var normal := await _walk_speed(t, 0.6)
	t.check(normal > SPEED * 0.9, "unstunned the walker covers %.0f px/s" % normal)
	t.puppet(&"walker").set_run(true)
	t.puppet(&"walker").walk(Vector2.RIGHT)
	await t.seconds(0.4)
	var ran: bool = walker.is_running()
	t.puppet(&"walker").stop()
	t.puppet(&"walker").set_run(false)
	t.check(ran, "unstunned it can run")
	var straight_before := await _stray(t, 4)
	t.check(straight_before < 2.0, "unstunned, a zero-spread pistol shoots straight (%.1f degrees off)" % straight_before)

	# --- The shooter is stunned for 6 s: its zero-spread shots stray, and are only the sway.
	await _top_up(t)
	Probe.stun(t.actor(&"shooter"), 6.0, 6.0, Vector2(-300, 500))
	await t.seconds(0.3)
	var stray := await _stray(t, 11)
	t.check(stray >= 5.0, "its shots go astray: the aim sways %.1f degrees at the worst" % stray)
	t.check(stray <= 28.0, "but never more than the 25 degree sway (%.1f)" % stray)

	# --- The walker is stunned for 4 s.
	Probe.stun(walker, 4.0, 4.0, Vector2(-300, 150))
	await t.seconds(0.3)
	t.check(Probe.level(walker) >= 0.95, "the stun is at its full level at first (%.2f)" % Probe.level(walker))
	var slow := await _walk_speed(t, 0.8)
	t.check(slow <= SPEED * 0.5, "stunned it walks at most about 0.45 of its speed (%.0f px/s of %.0f)" % [slow, SPEED])
	t.check(slow >= 10.0, "but it does move (%.0f px/s)" % slow)
	t.puppet(&"walker").set_run(true)
	t.puppet(&"walker").walk(Vector2.RIGHT)
	await t.seconds(0.4)
	t.check(not walker.is_running(), "stunned it cannot run, even holding run while moving")
	t.puppet(&"walker").stop()
	t.puppet(&"walker").set_run(false)

	# --- The tail: over the last 1.5 s the effect eases off.
	var view := Probe.view(walker)
	t.check(view.has("blind") and view.has("deaf") and view.has("level"), "stun_view() reports blind, deaf and level")
	await t.until(func(): return float(Probe.view(walker).get("deaf", 99.0)) <= 0.75, 6.0)
	var tail := Probe.level(walker)
	t.check(tail > 0.2 and tail < 0.8, "with 0.75 s of the stun left the level has tailed to about half (%.2f)" % tail)

	# --- After: back to normal.
	await t.until(func(): return Probe.level(walker) <= 0.0 and Probe.level(t.actor(&"shooter")) <= 0.0, 6.0, "both stuns end")
	t.check(not Probe.blind(walker) and not Probe.deaf(walker), "no longer blind or deaf")
	var recovered := await _walk_speed(t, 0.6)
	t.check(recovered > SPEED * 0.9, "it walks at full speed again (%.0f px/s)" % recovered)
	var straight_after := await _stray(t, 4)
	t.check(straight_after < 2.0, "and the shooter shoots straight again (%.1f degrees off)" % straight_after)

	# --- A new stun takes the longer of the old and the new timers.
	var other := t.actor(&"target")
	Probe.stun(other, 4.0, 4.0, Vector2.ZERO)
	Probe.stun(other, 1.0, 1.0, Vector2.ZERO)
	var kept := Probe.view(other)
	t.check(float(kept.get("blind", 0.0)) > 3.5 and float(kept.get("deaf", 0.0)) > 3.5, "a shorter stun does not cut a longer one short (blind %.1f, deaf %.1f)" % [kept.get("blind", 0.0), kept.get("deaf", 0.0)])
	Probe.stun(other, 6.0, 6.0, Vector2.ZERO)
	var longer := Probe.view(other)
	t.check(float(longer.get("blind", 0.0)) > 5.5 and float(longer.get("deaf", 0.0)) > 5.5, "a longer one replaces it (blind %.1f, deaf %.1f)" % [longer.get("blind", 0.0), longer.get("deaf", 0.0)])
