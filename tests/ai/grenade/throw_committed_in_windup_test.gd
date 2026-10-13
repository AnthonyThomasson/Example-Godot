extends GameTest

## G17, the `throw` primitive: once the wind-up has begun the throw is committed. The hand is drawn back and the grenade will leave it; a lob that is
## blocked from then on (a wardrobe shoved in front) does not undo the order, so the grenade that leaves the hand is also radioed (`frag_out`) like any
## other. One mechanism, scripted Von: the invader throws a frag onto a hostile hidden behind a desk, and a wardrobe (coverage 95) is put across the line
## the moment the wind-up begins.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const START := Vector2(100, 150)
const HOSTILE := Vector2(520, 150)
const ASIDE := Vector2(250, 40)
const ON_THE_LINE := Vector2(250, 150)


func describe() -> Dictionary:
	return {
		"name": "A throw is committed once the wind-up has begun",
		"description": "A wardrobe is put across the lob as the invader's hand is drawn back: the grenade still leaves the hand, frag out is radioed and the invader waits for the burst.",
		"tags": ["ai", "grenade", "combat", "scripted"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([{ "key": "hall", "type": "living_room", "rect": Rect2(0, 0, 900, 300) }], [{ "pos": Vector2(880, 0), "width": 60.0 }])
	s.object(&"desk", "desk", Vector2(330, 150))
	s.object(&"wardrobe", "wardrobe", ASIDE)
	s.von_script([{ "pick": "combat" }, { "pick": "grenade" }, { "pick": "engage" }, { "pick": "advance" }, { "pick": "retreat" }])
	s.switch(&"ai.hostile_on_trespass", false)
	s.switch(&"projectile.flyover", false)
	s.actor(&"i", &"invader", START, { "facing": Vector2.RIGHT })
	Probe.hostile(s, &"h", HOSTILE, START)


func run(t: TestContext) -> void:
	var inv := t.actor(&"i")
	Probe.arm(inv, 0, 1)
	if not t.require(Probe.count(inv, Probe.FRAG) == 1, "the invader carries a frag (item_count(8) = %d)" % Probe.count(inv, Probe.FRAG)):
		return
	var winding := func() -> bool:
		var item: Object = inv.current_item()
		return inv.current_slot() == Probe.FRAG and item.has_method("is_winding_up") and item.is_winding_up()
	if not t.require(await t.until(winding, 10.0), "the invader began its wind-up"):
		return
	var wardrobe := t.object(&"wardrobe")
	wardrobe.freeze = true  # a frozen body takes a teleport (a free one is put back by the physics step)
	await t.frames(1)
	wardrobe.global_position = ON_THE_LINE
	await t.frames(1)
	t.check(not Probe.line_clear(t, inv.global_position, HOSTILE), "set-up: a wardrobe stands across the lob")
	if not t.require(await t.until(func(): return t.happened(&"throw", func(d): return d.get("attacker") == inv), 2.0), "the grenade left the hand"):
		return
	await t.frames(3)
	t.check(not Probe.callouts(t, &"frag_out", &"i").is_empty(), "and was radioed (frag out)")
	t.check(await Probe.wait_boom(t, &"frag", Probe.FUSE_FRAG + 2.0), "and it went off")
