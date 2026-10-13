extends GameTest

## G4 (and G2's "dying mid-wind-up throws nothing"): a dead character's unthrown grenades vanish with it. Nothing is
## dropped, nothing is ever live in a dead hand, and a character killed during the wind-up throws nothing.

const Probe := preload("res://tests/_ai/grenade_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A dead thrower drops no grenade",
		"description": "A character holding a grenade dies: no DroppedItem, no live grenade, no throw. Another is killed 0.1 s into the wind-up and throws nothing.",
		"tags": ["grenade", "death", "drop", "item"],
		"timeout": 14.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.actor(&"holder", &"puppet", Vector2(200, 150))
	s.actor(&"winder", &"puppet", Vector2(200, 380))


func run(t: TestContext) -> void:
	var holder := t.actor(&"holder")
	var winder := t.actor(&"winder")
	Probe.arm(holder, 1, 2)
	Probe.arm(winder, 0, 2)
	if not t.require(Probe.count(holder, Probe.FRAG) == 2 and Probe.count(holder, Probe.STUN) == 1, "the holder carries a stun and two frags"):
		return
	t.puppet(&"holder").select_slot(Probe.FRAG)
	t.puppet(&"holder").aim_at(Vector2(600, 150))
	t.puppet(&"winder").select_slot(Probe.FRAG)
	t.puppet(&"winder").aim_at(Vector2(600, 380))
	await t.seconds(0.4)
	if not t.require(holder.current_slot() == Probe.FRAG and winder.current_slot() == Probe.FRAG, "both hold a frag grenade"):
		return

	holder.take_damage(1000.0)
	t.puppet(&"winder").shoot()
	await t.frames(6)
	if not t.require(winder.current_item() != null and winder.current_item().hand_stance(0) == &"throw", "the winder is in its wind-up"):
		return
	winder.take_damage(1000.0)
	await t.seconds(4.0)

	t.check(holder.is_dead and winder.is_dead, "both are dead")
	t.check(not t.world.get_children().any(func(n): return n is DroppedItem), "no item lies in the world: grenades are not dropped")
	t.check(Probe.live(t).is_empty(), "no grenade is live anywhere")
	t.check(not t.happened(&"throw"), "the one killed mid-wind-up threw nothing, and a dead hand throws nothing")
	t.check(Probe.booms(t).is_empty(), "nothing exploded")
	t.check(not t.happened(&"grenade"), "and nothing clattered on the floor")
