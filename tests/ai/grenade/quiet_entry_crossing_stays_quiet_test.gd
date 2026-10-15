extends GameTest

## E17 / G18, a late reason (issue #51, R11), its limit: once the point is crossing, a quiet entry stays quiet. A stack of two with a
## stun takes the quiet ENTER at the back door; gunfire is heard in the kitchen the moment the point radios `going_in`: nobody calls a
## bang, nothing is thrown and the claims stay quiet. Scripted Von (SEARCH > ENTER > the back door: one mechanism); both invaders carry a
## stun, the way Main arms a spawn. The gunfire is a `hit` event nobody known fired, inside the kitchen.

const Bang := preload("res://tests/_ai/bang_probe.gd")
const Entry := preload("res://tests/_ai/entry_probe.gd")
const Investigate := preload("res://tests/_ai/investigate_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A quiet entry already crossing stays quiet on a late reason",
		"description": "Two invaders with a stun go in by the quiet ENTER; gunfire is heard in the kitchen as the point crosses: no bang, nothing thrown, the claims stay quiet.",
		"tags": ["ai", "grenade", "entry", "stun", "scripted"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	Bang.stack(s)


func run(t: TestContext) -> void:
	if not t.require(Bang.arm(t, Bang.IDS), "both invaders carry a stun grenade (Character.item_count(7))"):
		return
	if not t.require(await t.until(func(): return not Entry.calls(t, "going_in").is_empty(), 40.0), "the point went in"):
		return
	if not t.require(Entry.calls(t).all(func(c): return c.get("bang") == false), "set-up: the stack went for it quietly (ENTER)"):
		return
	Investigate.gunfire(Maps.KITCHEN_CENTRE)
	await t.until(func(): return not Entry.calls(t, "clear").is_empty(), 30.0)
	await t.seconds(1.0)
	t.check(Entry.calls(t, "bang").is_empty(), "nobody called a bang")
	t.check(not t.happened(&"throw") and Probe.booms(t).is_empty(), "nothing was thrown")
	t.check(Entry.calls(t).all(func(c): return c.get("bang") == false), "every claim stayed quiet")
