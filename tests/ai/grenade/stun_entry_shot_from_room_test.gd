extends GameTest

## G18 as amended (issue #51, R6) and E9 as amended (R10): a room the NPC was shot at from is suspect, and the NPC does not walk into
## the shooter. A shot from inside the kitchen, out through its back door, lands beside the stack of two invaders (both carrying a stun)
## in the back garden; nobody is seen. Shot at from a room they are outside of, they treat it as a barricaded hostile: neither walks in
## through that doorway unguarded (no LOCATE straight in under fire, the E9 exemption does not cover a walk into the room the shots came
## from), and before anyone goes in the stack takes STUN ENTRY or throws a grenade into the kitchen. Fully natural: real Von at every
## level, whatever it makes of the shot; a `require` that the shot registered (the stack was under fire, or remembers where it was shot
## at from) comes first.
##
## Premise: the shot is one `hit` event nobody known fired (as tests/_ai/investigate_probe.gd posts gunfire), landing within the stack's
## awareness, its direction the line from a spot inside the kitchen out through the middle of the doorway (clear of both jambs, so a
## bullet could have come that way); posted first thing in `run`, so it is in the stack's first decision. A `require` checks that each
## invader's line back from the shot (`debug_memory()["shot_from"]`) runs into the kitchen. The invaders start in the garden north-east
## of the house, about 340 px from the doorway along that line. Both are armed with a stun at the start of `run`, the way Main arms a
## spawn.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const Suspect := preload("res://tests/_ai/suspect_probe.gd")
const A_AT := Vector2(980, -140)
const B_AT := Vector2(950, -100)
## Where the shot came from (inside the kitchen) and where it landed (between the two invaders): the line runs out through the
## middle of the back doorway (y 190 on the wall's plane).
const SHOOTER := Vector2(800, 286)
const LANDED := Vector2(968, -118)
## The entry phases a member is in once it has crossed by entry.
const INSIDE_PHASES := ["cross", "corner", "clear", "cover", "rear"]


func describe() -> Dictionary:
	return {
		"name": "A stack shot at from a room does not walk into the shooter",
		"description": "A shot out of the kitchen's back door lands beside two invaders with a stun; nobody is seen. Neither walks into the kitchen unguarded: before anyone goes in, the stack takes STUN ENTRY or throws a grenade into the kitchen, and it goes in by entry.",
		"tags": ["ai", "grenade", "entry", "stun", "von"],
		"requires_von": true,
		"timeout": 100.0,
	}


func configure(s: TestSetup) -> void:
	Suspect.world(s, A_AT, B_AT)


func run(t: TestContext) -> void:
	if not t.require(Suspect.arm(t), "both invaders carry a stun grenade (Character.item_count(7))"):
		return
	EventBus.post(&"hit", { "position": LANDED, "direction": (LANDED - SHOOTER).normalized(), "damage": 10.0, "attacker": null, "victim": null })
	var ids := Suspect.IDS
	var registered := [false]
	# Each member's line back from the shot, once it has one: whether it runs into the kitchen (the room the shots came from).
	var into_kitchen := {}
	var acts := { &"a": [], &"b": [] }
	var phases := { &"a": [], &"b": [] }
	# Each member's first moment in the kitchen: `[time, phase]`.
	var first_in := { &"a": [], &"b": [] }
	var end := t.time + 80.0
	while t.time < end and ids.any(func(id): return first_in[id].is_empty()):
		for id in ids:
			var brain := Entry.brain(t, id)
			var state: Dictionary = brain.debug_state()
			var shots: Array = brain.debug_memory().get("shot_from", [])
			if state.get("under_fire", false) or not shots.is_empty():
				registered[0] = true
			if not into_kitchen.has(id) and not shots.is_empty():
				into_kitchen[id] = _runs_into(shots[0], Maps.HOUSE_KITCHEN)
			var act := str(brain.current_act())
			if acts[id].is_empty() or acts[id].back()[1] != act:
				acts[id].append([t.time, act])
			var phase := str(Entry.entry(brain).get("phase", ""))
			phases[id].append([t.time, phase])
			if first_in[id].is_empty() and Maps.HOUSE_KITCHEN.grow(-Entry.INSIDE_DEPTH).has_point(t.actor(id).global_position):
				first_in[id] = [t.time, phase]
		await t.frames(1)
	var seen := { &"a": acts[&"a"].map(func(p): return p[1]), &"b": acts[&"b"].map(func(p): return p[1]) }
	if not t.require(registered[0], "the shot registered: the stack was under fire, or remembers where it was shot at from (debug_memory shot_from) (acts %s)" % str(seen)):
		return
	if not t.require(ids.all(func(id): return into_kitchen.get(id, false)), "set-up: each invader's line back from the shot runs into the kitchen (%s)" % str(into_kitchen)):
		return

	# (1) Nobody walked into the kitchen unguarded: each got in, if at all, by an entry's crossing it radioed.
	var first_entry := INF
	for id in ids:
		if first_in[id].is_empty():
			continue
		var at: float = first_in[id][0]
		var going := INF
		for c in Probe.raw(t, &"callout", func(d): return d.get("speaker") == t.actor(id) and String(d.get("entry_step", "")) == "going_in" and String(d.get("into", "")) == "kitchen"):
			going = float(c["time"])
			break
		t.check(going <= at + 0.05 and INSIDE_PHASES.has(first_in[id][1]), "%s got into the kitchen only by an entry's crossing (in at %.2f s in phase '%s', going_in at %.2f s; acts %s)" % [id, at, first_in[id][1], going, str(seen[id])])
		first_entry = minf(first_entry, at)

	# (2) Before anyone went in, the stack took STUN ENTRY or threw a grenade into the kitchen.
	var stun_entry := INF
	for id in ids:
		for pair in acts[id]:
			if String(pair[1]).begins_with("search/stun_entry/"):
				stun_entry = minf(stun_entry, float(pair[0]))
				break
	var grenade_in := INF
	for b in Probe.booms(t):
		if ids.any(func(id): return b["data"].get("attacker") == t.actor(id)) and Maps.HOUSE_KITCHEN.has_point(b["data"]["position"]):
			grenade_in = minf(grenade_in, float(b["time"]))
	var answered := minf(stun_entry, grenade_in)
	t.check(answered < INF and answered <= first_entry, "the stack took STUN ENTRY (at %.2f s) or threw a grenade into the kitchen (at %.2f s) before anyone went in (first in at %.2f s; acts %s)" % [stun_entry, grenade_in, first_entry, str(seen)])


## Whether the line back from a shot (`shot_from` memory: `at` where it landed, `pos` the wall behind) runs into `room`.
func _runs_into(shot: Dictionary, room: Rect2) -> bool:
	var poly := PackedVector2Array([room.position, Vector2(room.end.x, room.position.y), room.end, Vector2(room.position.x, room.end.y)])
	return not Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([shot["at"], shot["pos"]]), poly).is_empty()
