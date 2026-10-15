extends GameTest

## G17 as amended by issue #51 R13, with E15 / E18 of docs/tactical-entry.md: the walk to a throw spot is guarded like any walk to a fire spot.
## A throw spot whose walk needs no detour is preferred; when every one in reach is past the view of a doorway into a room not cleared, the walk
## goes round the view or, with no way round, covers the doorway from beside its jamb and only then crosses the view, and then throws.
##
## A hand-laid corridor, 140 px wide, with a study off its north side. A household puppet is hidden behind a desk at the corridor's west end;
## an invader with a stun stands at the east end, 740 px off: out of throw range (550 px), in sight over the desk. Every spot within a stun's
## reach of the puppet is west of the study's doorway, and the doorway's view fills the corridor in front of it, so the walk to any throw spot
## crosses it, with no way round (the corridor is the only way west). Scripted Von (COMBAT > GRENADE > stun when offered): the invader's first
## COMBAT decision offers GRENADE through a throw spot west of the doorway; on the way it secures the study's doorway (an entry with `secure`:
## stacked beside the jamb, one side of the pie sliced, no crossing into the study) before it is in the view, then walks on and throws from
## the spot, and the stun bursts on the puppet.
##
## Premises: the puppet cannot be killed and never shoots; the invader is armed at the start of `run`, the way Main arms a spawn.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const Spot := preload("res://tests/_ai/throw_spot_probe.gd")
const View := preload("res://tests/_ai/door_view_probe.gd")
const CORRIDOR := Rect2(0, 300, 1000, 140)
const STUDY := Rect2(600, 0, 320, 300)
const STUDY_DOOR := Vector2(760, 300)
const EXIT_DOOR := Vector2(1000, 370)
const H_AT := Vector2(130, 370)
const DESK_AT := Vector2(220, 370)
const I_AT := Vector2(870, 370)
## The study's doorway as the doorway-view probe frames it (`out`: away from the study, into the corridor).
const DOOR := { "id": "door_760_300", "pos": STUDY_DOOR, "width": 80.0, "out": Vector2.DOWN, "room": STUDY, "room_key": "study" }


func describe() -> Dictionary:
	return {
		"name": "The walk to a throw spot secures a doorway it must pass",
		"description": "Every throw spot in reach of a hidden hostile is past the view of a side room's doorway with no way round it: the invader secures the doorway from beside its jamb on the way, then throws from the spot.",
		"tags": ["ai", "grenade", "combat", "throw_spot", "door_view", "scripted"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "corridor", "type": "hallway", "rect": CORRIDOR },
		{ "key": "study", "type": "home_office", "rect": STUDY },
	], [{ "pos": STUDY_DOOR, "width": 80.0 }, { "pos": EXIT_DOOR, "width": 80.0 }])
	s.object(&"desk", "desk", DESK_AT)
	s.von_script([{ "pick": "combat" }, { "pick": "grenade" }, { "pick": "stun" }, { "pick": "engage" }, { "pick": "advance" }, { "pick": "retreat" }])
	s.actor(&"i", &"invader", I_AT, { "facing": Vector2.LEFT })
	Probe.hostile(s, &"h", H_AT, I_AT)


func run(t: TestContext) -> void:
	var inv := t.actor(&"i")
	Probe.arm(inv, 1, 0)
	if not t.require(Probe.count(inv, Probe.STUN) == 1, "the invader carries a stun (item_count(7) = %d)" % Probe.count(inv, Probe.STUN)):
		return
	if not t.require(I_AT.distance_to(H_AT) > Spot.THROW_RANGE and not View.in_view(t, DOOR, I_AT) and View.in_view(t, DOOR, Vector2(STUDY_DOOR.x, CORRIDOR.end.y - 20.0))
			and View.in_view(t, DOOR, Vector2(STUDY_DOOR.x, CORRIDOR.position.y + 20.0))
			and STUDY_DOOR.x - H_AT.x > Probe.MAX_RANGE - 15.0 - 80.0,
			"set-up: out of throw range, outside the study doorway's view, which fills the corridor in front of it; every spot in reach is past it"):
		return
	var brain := t.controller(&"i", &"debug_zones")
	var state := {}
	var walks: Array = []
	var first := {}
	var zones: Array = []
	var secured := { "at": -1.0, "pos": Vector2.INF }
	var entered_view := [-1.0]
	var watch := func() -> bool:
		Spot.note(t, brain, inv, state, walks)
		if first.is_empty():
			for w in walks:
				if not w["combat"].is_empty():
					first.merge(w)
					zones.assign(Spot.throws(brain))
					break
		var entry: Dictionary = brain.debug_entry() if brain.has_method("debug_entry") else {}
		if secured["at"] < 0.0 and bool(entry.get("secure", false)) and str(entry.get("into", "")) == "study" and str(entry.get("phase", "")) in ["pie", "done", ""]:
			secured["at"] = t.time
			secured["pos"] = inv.global_position
		if entered_view[0] < 0.0 and View.in_view(t, DOOR, inv.global_position):
			entered_view[0] = t.time
		return t.happened(&"throw", func(d): return d.get("attacker") == inv)
	await t.until(watch, 30.0)
	if not t.require(not first.is_empty() and (first["pos"] as Vector2).distance_to(I_AT) <= 12.0, "the invader made a COMBAT decision where it stands (walks %s)" % str(Spot.describe(walks))):
		return
	t.check(first["combat"].has("grenade"), "GRENADE was offered from out of range (offered %s)" % str(first["combat"]))
	var near := zones.filter(func(z): return (z["point"] as Vector2).distance_to(H_AT) < 60.0 and Spot.from_of(z) != Vector2.INF)
	if not t.check(not near.is_empty(), "through a throw spot (zones %s)" % str(zones)):
		return
	var from := Spot.from_of(near[0])
	t.check(from.x < STUDY_DOOR.x and from.distance_to(H_AT) <= Spot.THROW_RANGE, "the throw spot is past the study's doorway, in range (%s)" % str(from.round()))
	t.check(secured["at"] >= 0.0, "on the way it secured the study's doorway from beside its jamb (an entry with secure, into the study)")
	t.check(entered_view[0] < 0.0 or (secured["at"] >= 0.0 and secured["at"] <= entered_view[0] + 0.5),
		"before it walked into the doorway's view (secured at %.2f s, in the view at %.2f s)" % [secured["at"], entered_view[0]])
	t.check(not STUDY.has_point(secured["pos"]) and not t.events_of(&"callout", func(d): return d.get("speaker") == inv and str(d.get("entry_step", "")) == "going_in").size() > 0,
		"without going into the study")
	var throws := Probe.raw(t, &"throw", func(d): return d.get("attacker") == inv)
	if t.check(not throws.is_empty(), "then it threw (acts %s)" % Probe.acts(t, &"i")):
		var at: Vector2 = throws[0]["data"]["position"]
		t.check(at.distance_to(from) <= 30.0, "from the throw spot (thrown at %s, the spot %s)" % [str(at.round()), str(from.round())])
		if t.check(await Probe.wait_boom(t, &"stun", 4.0), "the stun went off"):
			var boom: Vector2 = Probe.booms(t, &"stun")[0]["data"]["position"]
			t.check(boom.distance_to(H_AT) < 110.0, "on the puppet's spot (%.0f px from it)" % boom.distance_to(H_AT))
