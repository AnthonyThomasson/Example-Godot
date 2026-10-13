extends GameTest

## G19: the `show_grenades` overlay (a child of every NPC, in the overlay table) draws the planned throw arc and landing spot with
## the grenade's danger radius, the live grenades the NPC knows of with their radii and fuse left, and the escape spot it is running
## to. It is draw-only and reads the controller's `debug_grenades()`, so this test reads that: an invader whose scripted Von picks
## GRENADE shows its planned throw, then the live grenade it threw; a defender beside the hostile shows the grenade it sees
## and the escape spot it runs to. The overlay is on throughout, so a draw error fails the test.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const Flank := preload("res://tests/_ai/flank_probe.gd")
const Registry := preload("res://scenes/ui/overlays/overlay_registry.gd")
const NPC_AT := Vector2(100, 250)
const HOSTILE_AT := Vector2(520, 250)


func describe() -> Dictionary:
	return {
		"name": "The grenade overlay draws the throw, the live grenade and the escape",
		"description": "show_grenades is in the overlay table and on each NPC; debug_grenades() reports the planned throw (spot and radius), the live grenade with fuse and radius, and a witness's escape spot.",
		"tags": ["ai", "grenade", "overlays", "scripted"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.object(&"desk", "desk", Vector2(330, 250))
	Flank.rules(s, [{ "pick": "combat" }, { "pick": "grenade" }, { "pick": "engage" }, { "pick": "advance" }, { "pick": "retreat" }])
	Flank.npc(s, &"n", NPC_AT, {}, &"invader", HOSTILE_AT)
	Probe.hostile(s, &"h", HOSTILE_AT, NPC_AT)
	s.actor(&"d", &"defender", Vector2(600, 330), { "facing": Vector2.LEFT })
	s.show_overlays(["show_grenades"])


func run(t: TestContext) -> void:
	t.check(Registry.ENTRIES.any(func(e): return e["flag"] == "show_grenades"), "the overlay table has a show_grenades row")
	var n := t.actor(&"n")
	var d := t.actor(&"d")
	t.check(n.get_children().any(func(c): return "show_grenades" in c and c.show_grenades), "the invader has a grenade overlay child, switched on")
	t.check(d.get_children().any(func(c): return "show_grenades" in c and c.show_grenades), "so does the defender")
	Probe.arm(n, 0, 1)
	if not t.require(Probe.count(n, Probe.FRAG) == 1, "the invader carries a frag grenade (Character.item_count(8) = %d)" % Probe.count(n, Probe.FRAG)):
		return
	var nb := t.controller(&"n", &"current_act")
	var db := t.controller(&"d", &"current_act")
	if not t.require(nb.has_method("debug_grenades"), "GoalController.debug_grenades() exists"):
		return

	# The plan: the throw it is about to make.
	var planned := await t.until(func(): return not (Probe.grenades(nb).get("throw", {}) as Dictionary).is_empty(), 8.0)
	if not t.require(planned, "the invader's order to throw shows a planned throw (acting: %s)" % str(nb.current_act())):
		return
	var plan: Dictionary = Probe.grenades(nb)["throw"]
	t.check((plan["to"] as Vector2).distance_to(HOSTILE_AT) < 60.0, "the planned landing spot is the hostile's (%s)" % str(plan["to"]))
	t.check((plan["from"] as Vector2).distance_to(n.global_position) < 40.0, "thrown from where the invader stands")
	t.check(absf(float(plan["radius"]) - Probe.BLAST_RADIUS) < 1.0 and plan["kind"] == &"frag", "with the frag's 250 px danger radius")
	t.screenshot("planned_throw")

	# The grenade in the air and on the floor: known to the thrower and seen by the defender.
	if not t.require(await t.until(func(): return t.happened(&"throw"), 6.0), "the invader throws"):
		return
	await t.frames(10)
	var own: Array = Probe.grenades(nb).get("known", [])
	if t.check(not own.is_empty(), "the thrower knows the live grenade"):
		t.check(own[0]["kind"] == &"frag" and own[0]["source"] == &"own", "a frag of its own")
		t.check(absf(float(own[0]["radius"]) - Probe.BLAST_RADIUS) < 1.0, "with its 250 px danger radius")
		t.check(float(own[0]["fuse_left"]) > 0.0 and float(own[0]["fuse_left"]) <= Probe.FUSE_FRAG, "and the fuse left (%.2f s)" % float(own[0]["fuse_left"]))
	var before := float(own[0]["fuse_left"]) if not own.is_empty() else 0.0
	await t.seconds(0.5)
	var later: Array = Probe.grenades(nb).get("known", [])
	t.check(not later.is_empty() and float(later[0]["fuse_left"]) < before - 0.3, "the fuse counts down")

	var fled := await t.until(func(): return (Probe.grenades(db).get("escape", Vector2.INF) as Vector2) != Vector2.INF, 2.0)
	if t.check(fled, "the defender 100 px from the landing runs to an escape spot"):
		var seen: Array = Probe.grenades(db).get("known", [])
		t.check(not seen.is_empty() and seen[0]["source"] in [&"seen", &"heard"], "having seen or heard the grenade itself")
		if not Probe.booms(t).is_empty():
			return
		var escape: Vector2 = Probe.grenades(db)["escape"]
		var landed: Vector2 = Probe.rest_point(t) if t.happened(&"grenade", func(e): return e.get("stage") == &"rest") else HOSTILE_AT
		t.check(not Probe.line_clear(t, landed, escape) or escape.distance_to(landed) >= Probe.BLAST_RADIUS, "the escape spot is out of the grenade's line or beyond its radius")
	t.screenshot("live_grenade")
	await Probe.wait_boom(t, &"frag", 5.0)
