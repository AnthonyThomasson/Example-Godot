extends GameTest

## G15, blind: a flash-blinded NPC sees nothing new and starts no new decision. It does not spot an invader that walks in front of
## it, so what it knows of it stays where it was last seen; it may fire blindly at that last-known spot (with the stun's sway, at most
## 25 degrees off); and when the blindness lifts it re-decides from what it sees. A defender is fighting a hostile it can see; the flash
## hits it; the hostile then walks across its front.
##
## Premises: the flash is `take_stun(6, 6, ...)` called on the defender, as a grenade's flash would (the grenade's own throw is
## tested elsewhere); the hostile is an invader *puppet* that cannot be killed and never shoots. Real Von; everything else is on.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const DEFENDER_AT := Vector2(200, 420)
const FIRST_SPOT := Vector2(600, 420)   ## where the hostile is seen last
const SECOND_SPOT := Vector2(450, 170)  ## 45 degrees off the first, well inside the defender's view cone, where it walks to
const BLIND := 6.0


func describe() -> Dictionary:
	return {
		"name": "A blinded defender neither spots the intruder nor stops firing at the old spot",
		"description": "Blinded for 6 s, a defender fighting an invader keeps the invader's last-known spot while it walks 45 degrees across its front, fires only toward that spot, and sees it again once it can see.",
		"tags": ["ai", "grenade", "stun", "blind", "von"],
		"requires_von": true,
		"timeout": 80.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 500))
	s.actor(&"d", &"defender", DEFENDER_AT, { "facing": Vector2.RIGHT })
	s.actor(&"p", &"puppet", FIRST_SPOT, { "faction": &"invader", "max_health": 1000000.0, "aim_point": DEFENDER_AT })


## The defender's remembered position of the invader, from its contacts: `{ pos, visible }`, or {} when it knows none.
func _known(brain: Node, p: Node) -> Dictionary:
	for c in brain.known_contacts_for_display():
		if c.get("node") == p:
			return c
	return {}


func run(t: TestContext) -> void:
	var d := t.actor(&"d")
	var p := t.actor(&"p")
	var brain := t.controller(&"d", &"current_act")
	if not t.require(await t.until(func(): return not _known(brain, p).is_empty() and str(brain.current_act()).begins_with("combat"), 20.0), "the defender knows the invader and is fighting it (acting: %s)" % str(brain.current_act())):
		return
	var seen_at: Vector2 = _known(brain, p).get("pos", FIRST_SPOT)

	if not t.require(Probe.stun(d, BLIND, BLIND, FIRST_SPOT + Vector2(0, -100)), "Character.take_stun(blind, deaf, from) exists"):
		return
	var flashed := t.time
	t.puppet(&"p").walk_to(SECOND_SPOT)
	var seen := {}
	var dirs: Array = []  # the direction of each round the defender fires, read the frame it appears
	var capture := func() -> void:
		for n in t.world.get_children():
			if String(n.name).begins_with("Projectile") and n is Node2D and not seen.has(n.get_instance_id()) and n.get("ignore") == d:
				seen[n.get_instance_id()] = true
				dirs.append(n.get("direction"))
	await t.frames(30)
	t.check(Probe.blind(d), "the flash blinded the defender (is_blind)")
	while t.time < flashed + 3.5:
		capture.call()
		await t.frames(1)
	t.check(t.puppet(&"p").has_arrived(), "the invader walked across the defender's front")
	var known := _known(brain, p)
	t.check(not known.is_empty() and (known["pos"] as Vector2).distance_to(seen_at) < 60.0, "the defender still holds the invader at the spot it last saw it (%s, now at %s)" % [str(known.get("pos")), str(p.global_position.round())])
	t.check(not known.is_empty() and not bool(known.get("visible", true)), "and does not see it")

	# Its shots while blind go to the old spot, within the sway, never to where the invader really is.
	while Probe.blind(d) and t.time < flashed + BLIND + 2.0:
		capture.call()
		await t.frames(1)
	var to_old: Vector2 = (seen_at - d.global_position).normalized()
	var to_new: Vector2 = (SECOND_SPOT - d.global_position).normalized()
	var worst := 0.0
	for dir in dirs:
		worst = maxf(worst, absf(rad_to_deg(to_old.angle_to(dir))))
	t.check(dirs.size() >= 2, "it fired blindly while the flash lasted (%d rounds)" % dirs.size())
	t.check(worst <= 28.0, "every blind shot went toward the old spot, within the 25 degree sway (worst %.1f degrees off it; the invader was %.0f degrees away)" % [worst, absf(rad_to_deg(to_old.angle_to(to_new)))])
	t.check(t.time - flashed >= BLIND - 0.5, "(the blindness ran its course)")

	# The blindness is over: it sees the invader again, where it is now, and decides afresh.
	t.check(await t.until(func(): return bool(_known(brain, p).get("visible", false)) and (_known(brain, p)["pos"] as Vector2).distance_to(p.global_position) < 40.0, 4.0),
		"once it can see it re-reads the invader where it stands (acting: %s)" % str(brain.current_act()))
