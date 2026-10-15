extends GameTest

## E17 as amended by issue #51 R16: a member of a bang stack leaving for a fight does not cancel the bang. From the bang call until the stun leaves
## its hand the thrower is committed to the bang: a hostile seen on its walk out to the throw spot or in the wind-up does not make it leave; it
## throws, then fights from where it stands. The members still at the door go in on the burst (R8). The matches showed bang stacks breaking up
## instead: a defender seen in the doorway, the members leave for COMBAT, the thrower too on its way out, and no stun goes in.
##
## Three invaders, each with a stun, in the Terrace house's back garden north-east of the back door; gunfire is heard in the kitchen, so the stack
## goes for the kitchen by a bang (G18). The moment the thrower calls the bang, a householder stands just inside the doorway, at a spot the point
## and the thrower see from their slots and the front of the doorway (where the thrower throws from) does, but the third member's slot does not.
## The point leaves for the fight; the thrower, committed since its call, walks out with the householder in view and still throws: the planned stun
## goes off in the kitchen within `KEPT` s of the call, and a member still at the door at the burst goes in on it within `BANG_WINDOW` s. Then the
## thrower fights: the sighting it held off for the bang is decided once the stun has left its hand (a COMBAT order within `FIGHT` s of the
## release), not dropped. The householder steps back out of the doorway once the stun is thrown (so the crossing is not blocked by a body that
## cannot be killed).
##
## The whole pipeline runs with real Von. `require`d first: the stack claimed the back door in bang mode, a member left the stack for COMBAT before
## the stun left the thrower's hand, the bang was called, and the thrower had the householder in view `LEAD` s or more before the release.
##
## Premises: the gunfire is a `hit` event nobody known fired, inside the kitchen (as tests/_ai/investigate_probe.gd posts it), first thing in
## `run`; the householder is a puppet that cannot be killed and never shoots, put in the doorway at the bang call and walked back
## out once the stun is thrown (a defender showing itself, timed against the stack); the invaders are armed with one stun each at the start of
## `run`, the way Main arms a spawn; the stun's wind-up is held to `WINDUP` s (from 0.3). Von answers the sighting about 0.7 to 1.2 s after it, and
## from a thrower's own slot the walk out and a 0.3 s wind-up take about 1.25 s: the point's answer then came in a tenth of a second before the
## release, or after it, and the thrower's often during the wind-up, which already holds a throw (its answer dropped, so a run passed without
## the walk out being held at all). With the longer wind-up the point leaves well before the release, and a thrower whose answer comes during the
## wind-up must still act on it after the release.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Investigate := preload("res://tests/_ai/investigate_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const IDS := [&"a", &"b", &"c"]
const HIDDEN := Vector2(780, 30)
## Where a thrower stands to throw a stun in through the back door: in front of it, out from the wall (the test's own frame for "seen from the
## throw spot").
const FRONT := [Vector2(900, 170), Vector2(920, 160), Vector2(910, 190)]
## From the bang call, the planned stun goes off in the kitchen within this many seconds: the walk out, the wind-up and the 1.5 s fuse.
const KEPT := 7.0
const BANG_WINDOW := 3.0
## The entry phases of a member still at the door.
const AT_DOOR := ["approach", "stack", "bang", "pie"]
## The thrower has the householder in view at least this long before the stun leaves its hand: it sees it on its walk out, not only once the
## stun is on its way.
const LEAD := 0.7
## The stun's wind-up in this test (s; the row's is 0.3): see the premises.
const WINDUP := 1.0
## Once the stun has left its hand, the thrower fights within this many seconds: the sighting it held off is decided (Von answers in about 1 s).
const FIGHT := 2.0
## The thrower's view cone (the NPC's `fov_degrees`, 110) as a half-angle.
const HALF_FOV := deg_to_rad(55.0)


func describe() -> Dictionary:
	return {
		"name": "A bang stack's thrower throws the planned stun through a fight",
		"description": "A stack of three going into the kitchen by a bang sees a householder in the doorway: the point leaves for the fight, the thrower sees it on its way out but still throws the planned stun into the kitchen, then fights, and a member still at the door goes in on its burst.",
		"tags": ["ai", "grenade", "entry", "stun", "von"],
		"requires_von": true,
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.actor(&"a", &"invader", Vector2(960, 60))
	s.actor(&"b", &"invader", Vector2(985, 110))
	s.actor(&"c", &"invader", Vector2(990, -30))
	Probe.hostile(s, &"h", HIDDEN, Maps.DOOR_BACK)
	var rows: Dictionary = GrenadeConfig.grenades.duplicate(true)
	rows[&"stun"]["windup"] = WINDUP
	s.set_static(GrenadeConfig, "grenades", rows)


func run(t: TestContext) -> void:
	for id in IDS:
		Probe.arm(t.actor(id), 1, 0)
	if not t.require(IDS.all(func(id): return Probe.count(t.actor(id), Probe.STUN) == 1), "each invader carries a stun (item_count(7))"):
		return
	Investigate.gunfire(Maps.KITCHEN_CENTRE)
	var door: String = Entry.BACK["id"]
	var h := t.puppet(&"h")
	var acts := { &"a": [], &"b": [], &"c": [] }
	var phases := { &"a": [], &"b": [], &"c": [] }
	var shown := Vector2.INF
	var left := [INF, &""]
	var called := [INF, &""]   # The bang call: its time and the thrower that made it.
	var in_view := INF       # When the thrower first had the householder in view after the call.
	var released := INF      # When the thrower's stun left its hand.
	var released_under := ""  # The thrower's order when it did: the bang entry's for the planned stun, a COMBAT > GRENADE for one thrown after leaving.
	var stepped_back := false
	var end := t.time + 70.0
	while t.time < end:
		for id in IDS:
			var brain := Entry.brain(t, id)
			var act := str(brain.current_act())
			if acts[id].is_empty() or acts[id].back()[1] != act:
				acts[id].append([t.time, act])
			var phase := str(Entry.entry(brain).get("phase", ""))
			if phases[id].is_empty() or phases[id].back()[1] != phase:
				phases[id].append([t.time, phase])
			if left[0] == INF and act.begins_with("combat") and phases[id].any(func(p): return AT_DOOR.has(p[1])):
				left = [t.time, id]
		if called[0] == INF:
			for c in Probe.raw(t, &"callout", func(d): return String(d.get("entry_step", "")) == "bang" and String(d.get("opening", "")) == door):
				called = [float(c["time"]), IDS.filter(func(id): return t.actor(id) == c["data"].get("speaker")).front()]
				break
			if called[0] < INF:
				shown = _show_spot(t, _point(t, door), called[1])
				if not t.require(shown != Vector2.INF, "set-up: a spot just inside the doorway is in view of the point and the thrower, and of the front of the doorway, and out of the third member's"):
					return
				Probe.place(t, &"h", shown, Maps.DOOR_BACK + Vector2(200, 0))
		elif released == INF:
			var thrower: Node2D = t.actor(called[1])
			if in_view == INF and _sees(t, thrower, t.actor(&"h").global_position):
				in_view = t.time
			if t.happened(&"throw", func(d): return d.get("attacker") == thrower and d.get("kind") == &"stun"):
				released = t.time
				released_under = str(Entry.brain(t, called[1]).current_act())
		if released < INF and not stepped_back:
			stepped_back = true
			h.walk_to(HIDDEN)
		var burst := Probe.booms(t, &"stun").filter(func(b): return Maps.HOUSE_KITCHEN.has_point(b["data"]["position"]))
		if not burst.is_empty() and t.time > float(burst[0]["time"]) + BANG_WINDOW + 0.5:
			break
		if burst.is_empty() and t.time > float(called[0]) + KEPT + 1.0:
			break  # No stun in the kitchen within `KEPT` s of the call: the verdict is in.
		await t.frames(1)
	var seen := {}
	for id in IDS:
		seen[id] = acts[id].map(func(p): return "%.1f %s" % [p[0], p[1]])
	var bang_claims := Entry.calls(t, "claim").filter(func(c): return String(c.get("opening", "")) == door and c.get("bang") == true)
	if not t.require(not bang_claims.is_empty(), "the stack claimed the back door in bang mode (acts %s)" % str(seen)):
		return
	if not t.require(called[0] < INF, "the bang was called (acts %s)" % str(seen)):
		return
	if not t.require(left[0] < released, "a member left the stack for COMBAT before the stun left the thrower's hand (left %s at %.2f s, released at %.2f s; acts %s)" % [left[1], left[0], released, str(seen)]):
		return
	if not t.require(in_view <= released - LEAD, "the thrower (%s) had the householder in view after the call, %.1f s or more before the release (in view at %.2f s, call at %.2f s, released at %.2f s)" % [called[1], LEAD, in_view, called[0], released]):
		return
	var planned := Probe.booms(t, &"stun").filter(func(b): return Maps.HOUSE_KITCHEN.has_point(b["data"]["position"]) and b["data"].get("attacker") == t.actor(called[1]))
	var burst_at: float = float(planned[0]["time"]) if not planned.is_empty() else INF
	var kept: bool = released_under.begins_with("search/stun_entry/%s" % door) \
		and acts[called[1]].all(func(a): return float(a[0]) <= float(called[0]) or float(a[0]) > released or str(a[1]).begins_with("search/stun_entry/%s" % door))
	t.check(kept, "the thrower kept to the bang from its call to the release: the stun was the planned one, thrown without leaving for the fight (released at %.2f s under '%s'; %s's acts %s)" % [released, released_under, called[1], str(seen[called[1]])])
	var fought: Array = acts[called[1]].filter(func(a): return float(a[0]) > released and float(a[0]) <= released + FIGHT and str(a[1]).begins_with("combat"))
	t.check(not fought.is_empty(), "then the thrower fought from where it stood: a COMBAT order within %.0f s of the release (released at %.2f s; %s's acts %s)" % [FIGHT, released, called[1], str(seen[called[1]])])
	t.check(burst_at <= float(called[0]) + KEPT, "the planned stun went off in the kitchen within %.0f s of the call (call %.2f s, released %.2f s, burst %.2f s)" % [KEPT, called[0], released, burst_at])
	if burst_at == INF:
		return
	var at_door: Array = IDS.filter(func(id): return AT_DOOR.has(_phase_at(phases[id], burst_at)))
	t.check(not at_door.is_empty(), "a member was still at the door when it went off (phases at %.2f s: %s)" % [burst_at, str(IDS.map(func(id): return [id, _phase_at(phases[id], burst_at)]))])
	var went_in := at_door.filter(func(id):
		var go := Entry.first_call_time(t, "going_in", id, door)
		return go >= burst_at and go <= burst_at + BANG_WINDOW)
	t.check(not went_in.is_empty(), "and a member still at the door went in on its burst, within %.0f s (at the door %s; going_in %s)" % [BANG_WINDOW, str(at_door), str(IDS.map(func(id): return [id, Entry.first_call_time(t, "going_in", id, door)]))])


## The member whose claim on `door` holds slot 1, or &"".
func _point(t: TestContext, door: String) -> StringName:
	for id in IDS:
		if Entry.calls(t, "claim", id).any(func(c): return String(c.get("opening", "")) == door and int(c.get("slot", 0)) == 1):
			return id
	return &""


## A spot just inside the back doorway in the line of sight of point `p` and thrower `thrower` where they stand, out of every other member's, and
## in sight from each of `FRONT`; INF when there is none. The one nearest the doorway.
func _show_spot(t: TestContext, p: StringName, thrower: StringName) -> Vector2:
	var seers: Array = [t.actor(thrower).global_position]
	if p != &"":
		seers.append(t.actor(p).global_position)
	var others: Array = IDS.filter(func(id): return id != p and id != thrower).map(func(id): return t.actor(id).global_position)
	var best := Vector2.INF
	for x in range(835, 740, -5):
		for y in range(150, 300, 5):
			var q := Vector2(x, y)
			if not Maps.HOUSE_KITCHEN.grow(-16.0).has_point(q) or q.distance_to(Maps.DOOR_BACK) >= best.distance_to(Maps.DOOR_BACK):
				continue
			if seers.all(func(f): return Probe.line_clear(t, f, q)) and others.all(func(o): return not Probe.line_clear(t, o, q)) and FRONT.all(func(f): return Probe.line_clear(t, f, q)):
				best = q
	return best


## Whether `who` has `at` in view: within its view cone and on a clear line.
func _sees(t: TestContext, who: Node2D, at: Vector2) -> bool:
	var facing: Vector2 = who.get("facing")
	return absf(facing.angle_to(at - who.global_position)) <= HALF_FOV and Probe.line_clear(t, who.global_position, at)


## The entry phase of `samples` (`[time, phase]`, in time order) at time `at`.
func _phase_at(samples: Array, at: float) -> String:
	var out := ""
	for p in samples:
		if float(p[0]) <= at:
			out = p[1]
	return out
