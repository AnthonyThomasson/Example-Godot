extends GameTest

## G17: the shots' origin group (shot at by someone unseen from a room the NPC is outside of, GRENADE where the shots came from) uses throw
## spots too. An invader with a frag stands outside the Terrace house's back door, against the kitchen's east
## wall north of it (where a stack's slot is). A shot from inside the kitchen comes out through the doorway and lands beside it; nobody is seen.
## From where it stands no point of the shots' line inside the kitchen has a clear lob (the wall beside the door is in the way), and LOCATE is
## not offered toward a room the shots came from; GRENADE is offered through a throw spot in front of the doorway: the invader steps there and
## throws the frag into the kitchen, where the shots came from.
##
## The whole pipeline runs with real Von. `require`s come first: the shot registered and the invader's line back from it runs into the kitchen,
## and from where it stood no point of that line in the kitchen (past the threshold: `INSIDE` px in) has a clear lob in range (550 px, the
## throw range). The check is on the first decision, made where it was shot at: without a throw spot it would offer RETREAT alone, and a throw
## would follow only if the spot it retreated to happened to have a lob.
##
## Premises: the shot is one `hit` event nobody known fired (as tests/_ai/investigate_probe.gd posts gunfire), posted first thing in `run` so it
## is in the invader's first decision; it lands 125 px from the invader, its direction the line from a spot inside the kitchen out through the
## doorway (clear of both jambs, so a bullet could have come that way). The invader is armed with one frag at the start of `run`, the way Main
## arms a spawn.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const Spot := preload("res://tests/_ai/throw_spot_probe.gd")
const INVADER_AT := Vector2(875, 100)
## Where the shot came from (inside the kitchen) and where it landed (in the garden in front of the door): the line runs out through the doorway
## at y 210 (its gap spans y 145 to 235) and back to the kitchen's west wall, below the doorway into the living room.
const SHOOTER := Vector2(600, 210)
const LANDED := Vector2(930, 210)
## How far past the doorway's wall plane a point of the shots' line counts as in the room (a grenade on the threshold is not thrown into it).
const INSIDE := 60.0


func describe() -> Dictionary:
	return {
		"name": "Shot at from a room it cannot lob into, an NPC throws from a throw spot",
		"description": "A shot out of the kitchen's back door lands beside an invader with a frag standing against the wall beside it, with no lob into the kitchen from there: GRENADE where the shots came from is offered through a throw spot in front of the doorway, and the invader throws the frag into the kitchen.",
		"tags": ["ai", "grenade", "combat", "throw_spot", "von"],
		"requires_von": true,
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.actor(&"i", &"invader", INVADER_AT, { "facing": Vector2.UP })


func run(t: TestContext) -> void:
	var inv := t.actor(&"i")
	Probe.arm(inv, 0, 1)
	if not t.require(Probe.count(inv, Probe.FRAG) == 1, "the invader carries a frag grenade (item_count(8) = %d)" % Probe.count(inv, Probe.FRAG)):
		return
	EventBus.post(&"hit", { "position": LANDED, "direction": (LANDED - SHOOTER).normalized(), "damage": 10.0, "attacker": null, "victim": null })
	var brain := t.controller(&"i", &"debug_zones")
	var state := {}
	var walks: Array = []
	var acts: Array = []
	var shot := {}
	var watch := func() -> bool:
		Spot.note(t, brain, inv, state, walks)
		var act := Probe.acts(t, &"i")
		if not acts.has(act):
			acts.append(act)
		var lines: Array = brain.debug_memory().get("shot_from", [])
		if shot.is_empty() and not lines.is_empty():
			shot.merge(lines[0])
		return t.happened(&"throw", func(d): return d.get("attacker") == inv)
	await t.until(watch, 40.0)
	if not t.require(not shot.is_empty(), "the shot registered: the invader remembers where it was shot at from (acts %s)" % str(acts)):
		return
	var room := Maps.HOUSE_KITCHEN
	var poly := PackedVector2Array([room.position, Vector2(room.end.x, room.position.y), room.end, Vector2(room.position.x, room.end.y)])
	var pieces := Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([shot["at"], shot["pos"]]), poly)
	if not t.require(not pieces.is_empty(), "set-up: its line back from the shot runs into the kitchen (%s)" % str(shot)):
		return
	var stretch: PackedVector2Array = pieces[0]
	var a: Vector2 = stretch[0]
	var b: Vector2 = stretch[stretch.size() - 1]
	if a.x < b.x:
		var swap := a
		a = b
		b = swap
	a = a.move_toward(b, INSIDE)  # From the doorway end, past the threshold.
	if not t.require(not Spot.any_lob_along(t, INVADER_AT, a, b, Spot.THROW_RANGE),
			"set-up: from where it stood no point of that line in the kitchen (from %s to %s) has a clear lob within range" % [str(a.round()), str(b.round())]):
		return
	var first: Array = walks.filter(func(w): return not w["combat"].is_empty() and (w["pos"] as Vector2).distance_to(INVADER_AT) <= 12.0)
	if not t.require(not first.is_empty(), "the invader made a COMBAT decision where it was shot at (walks %s)" % str(Spot.describe(walks))):
		return
	t.check(first[0]["combat"].has("grenade"), "that decision offered GRENADE where the shots came from, through a throw spot (offered %s; walks %s)" % [str(first[0]["combat"]), str(Spot.describe(walks))])
	var throws := Probe.raw(t, &"throw", func(d): return d.get("attacker") == inv)
	if not t.check(not throws.is_empty(), "the invader threw its frag (acts %s)" % str(acts)):
		return
	var at: Vector2 = throws[0]["data"]["position"]
	t.check(at.distance_to(INVADER_AT) >= 40.0, "from a throw spot it walked to (thrown at %s)" % str(at.round()))
	if t.check(await Probe.wait_boom(t, &"frag", 6.0), "the frag went off"):
		var boom: Vector2 = Probe.booms(t, &"frag")[0]["data"]["position"]
		t.check(room.has_point(boom), "in the kitchen, where the shots came from (%s)" % str(boom.round()))
		t.check(Probe.blast_hits(t, inv).is_empty(), "without catching the thrower")
