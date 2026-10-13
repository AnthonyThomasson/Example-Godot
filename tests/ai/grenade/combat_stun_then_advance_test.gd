extends GameTest

## G17: an invader with only a stun grenade, a hostile hidden from its line of fire behind a sofa in a hall, flashes it and then
## closes in while it is blind: after a stun the tree naturally goes on to ADVANCE or ENGAGE. The whole pipeline runs, real Von at
## every level. A `require` that the AI took the GRENADE path comes first, so a different Von choice reads as a set-up finding.
##
## The sofa stands against one wall of the hall and leaves a lane along the other, so the hostile can be reached and shot once it
## is passed. The hall is 140 px deep so that the lane is walkable in the navmesh (in a 100 px one the sofa seals it: the way to the hostile is then a
## 1500 px loop outside the house, and the "closes in" below passes or fails on how far round that loop the invader got). Premises: the hostile is a household *puppet* that cannot be killed and never shoots; the invader is armed with one
## stun here because the test world keeps the default inventory, the way Main arms a spawn.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const INVADER_AT := Vector2(450, 31)
const HOSTILE_AT := Vector2(800, 31)


func describe() -> Dictionary:
	return {
		"name": "An invader stuns a hidden hostile and closes in while it is blind",
		"description": "A hostile hides behind a sofa; the invader with only a stun grenade takes the GRENADE tactic, flashes it, radios bang out and, while it is blind, closes at least 150 px on it.",
		"tags": ["ai", "grenade", "combat", "stun", "von"],
		"requires_von": true,
		"timeout": 100.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([{ "key": "hall", "type": "entry_hall", "rect": Rect2(0, 0, 900, 140) }], [{ "pos": Vector2(0, 70), "width": 80.0 }])
	s.object(&"sofa", "sofa", Vector2(700, 31))
	s.actor(&"i", &"invader", INVADER_AT, { "facing": Vector2.RIGHT })
	Probe.hostile(s, &"h", HOSTILE_AT, INVADER_AT)


func run(t: TestContext) -> void:
	var inv := t.actor(&"i")
	var hostile := t.actor(&"h")
	Probe.arm(inv, 1, 0)
	if not t.require(Probe.count(inv, Probe.STUN) == 1, "the invader carries a stun grenade (Character.item_count(7) = %d)" % Probe.count(inv, Probe.STUN)):
		return
	var seen: Array = []
	if not t.require(await Probe.wait_act(t, &"i", "grenade", 60.0, seen), "the AI took the GRENADE tactic (its acts: %s)" % str(seen)):
		return
	if not t.require(await t.until(func(): return t.happened(&"throw"), 10.0), "the invader threw (acting: %s)" % str(seen.back())):
		return
	if not t.require(await Probe.wait_boom(t, &"stun", Probe.FUSE_STUN + 2.0), "the stun went off within its fuse of the throw (acting: %s)" % str(seen.back())):
		return
	var throw: Dictionary = Probe.raw(t, &"throw")[0]
	t.check(throw["data"].get("attacker") == inv and throw["data"].get("kind") == &"stun", "the invader threw its stun")
	t.check(not Probe.callouts(t, &"bang_out", &"i").is_empty(), "and radioed bang out")
	await t.frames(3)
	var flash := Probe.stuns(t, hostile)
	if not t.require(not flash.is_empty() and float(flash[0]["data"].get("blind", 0.0)) > 1.0, "the hostile was blinded by it"):
		return
	var blind_for := float(flash[0]["data"]["blind"])
	var start := t.time
	var from: float = inv.global_position.distance_to(hostile.global_position)
	var closest := from
	while t.time < start + blind_for:
		closest = minf(closest, inv.global_position.distance_to(hostile.global_position))
		await t.frames(1)
	t.check(closest <= from - 150.0, "while it was blind (%.1f s) the invader closed in from %.0f px to %.0f px (acting: %s)" % [blind_for, from, closest, str(Probe.acts(t, &"i"))])
