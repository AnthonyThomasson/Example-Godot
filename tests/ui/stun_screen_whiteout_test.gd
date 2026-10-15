extends GameTest

## G14: the stunned human sees the screen go white at the burst and fade back over the blind time through a frozen afterimage
## of the moment of the flash. The screen only watches the one character it is given, and a deaf-only stun does not whiten it.

const SCREEN := "res://scenes/ui/hud/stun_screen.gd"
const Probe := preload("res://tests/_ai/grenade_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "The stun screen whites out and fades over the blind time",
		"description": "A 4 s flash on the watched character: white at once with the afterimage frozen, fading to clear by 4 s; a deaf-only stun or someone else's flash changes nothing.",
		"tags": ["ui", "hud", "stun", "grenade"],
		"timeout": 16.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.actor(&"human", &"puppet", Vector2(200, 250), { "max_health": 100000.0 })
	s.actor(&"other", &"puppet", Vector2(600, 250), { "max_health": 100000.0 })


func run(t: TestContext) -> void:
	if not t.require(ResourceLoader.exists(SCREEN), "the stun screen script exists"):
		return
	var screen: Node = (load(SCREEN) as GDScript).new()
	t.world.add_child(screen)
	var human := t.actor(&"human")
	screen.watch(human)
	await t.frames(3)
	var rest: Dictionary = screen.drawn()
	t.check(float(rest.get("white", 1.0)) == 0.0 and not bool(rest.get("afterimage", true)), "nothing is drawn while the human sees")

	Probe.stun(t.actor(&"other"), 4.0, 4.0)
	await t.frames(3)
	t.check(float(screen.drawn().get("white", 1.0)) == 0.0, "someone else's flash does not whiten this screen")
	Probe.stun(human, 0.0, 4.0)
	await t.frames(3)
	t.check(float(screen.drawn().get("white", 1.0)) == 0.0, "a bang that only deafens does not either")
	await t.until(func(): return not Probe.deaf(human), 6.0)

	if not t.require(Probe.stun(human, 4.0, 4.0), "Character.take_stun exists"):
		return
	await t.frames(3)
	var burst: Dictionary = screen.drawn()
	t.check(float(burst.get("white", 0.0)) >= 0.9, "the screen is white at the burst (%.2f)" % float(burst.get("white", 0.0)))
	t.check(bool(burst.get("afterimage", false)), "with the frozen afterimage of the flash held")
	t.check(float(burst.get("remaining", 0.0)) > 3.5 and float(burst.get("remaining", 0.0)) <= 4.0, "and the blind time left is read from the character (%.2f s)" % float(burst.get("remaining", 0.0)))
	var seen := []
	for second in [0.5, 1.0, 1.0, 1.0]:  # 0.5, 1.5, 2.5, 3.5 s after the burst
		await t.seconds(second)
		seen.append(float(screen.drawn().get("white", -1.0)))
	t.check(seen[0] < float(burst.get("white", 0.0)) and seen[0] > seen[1] and seen[1] > seen[2] and seen[2] > seen[3], "the white fades steadily over the blind time (%s)" % str(seen))
	t.check(seen[3] < 0.3 and seen[1] > 0.2 and seen[1] < 0.8, "to nearly clear by the end, about half-way in the middle (%s)" % str(seen))
	await t.seconds(0.8)
	var after: Dictionary = screen.drawn()
	t.check(float(after.get("white", 1.0)) == 0.0 and not bool(after.get("afterimage", true)), "and it is clear again, the afterimage gone, once the blindness has ended")
