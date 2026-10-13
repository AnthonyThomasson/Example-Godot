extends GameTest

## G18, the bang entry: a stack of two invaders, both carrying a stun, at the back door of a kitchen where gunfire was heard (and
## where a defender is) takes STUN ENTRY instead of the quiet ENTER. Once the stack is ready the thrower (the slot-2 member when it
## carries a stun) radios `bang` and throws the stun to the room's far side through the doorway; every member holds its slot turned
## away from the door; on the detonation the point skips the pie and crosses at once. The defender inside is blinded. The whole
## pipeline runs: the heard gunfire, the snapshot's entries, real Von choosing STUN ENTRY over ENTER, the stack on the radio, the bang.
## A `require` that the AI took STUN ENTRY comes first, so a different Von choice reads as a set-up finding.
##
## Premises: the gunfire is one shot heard from the kitchen (`hit` event with nobody known behind it, as tests/_ai/investigate_probe.gd
## posts it), at the start so it is in the first decision; both invaders are armed with a stun here because the test world keeps the
## default inventory, the way Main arms a spawn; and the defender is waiting in the room (seated on a kitchen chair facing into it, started
## through `interact_with` at the start of `run`, as in `evade_frag_ally_warned`): left to itself it walks out of the kitchen
## to search the living room within the 4 s the stack takes to get its stun off, and the check is about someone in the room.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const Investigate := preload("res://tests/_ai/investigate_probe.gd")
const IDS := [&"a", &"b"]


func describe() -> Dictionary:
	return {
		"name": "A stack takes a stun entry into a room where gunfire was heard",
		"description": "Two invaders with a stun at the kitchen's back door, gunfire heard inside: STUN ENTRY, the slot-2 member radios bang and throws into the far side, all face away, the point crosses on the bang without slicing the pie, the defender inside is blinded.",
		"tags": ["ai", "grenade", "entry", "stun", "von"],
		"requires_von": true,
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.actor(&"a", &"invader", Vector2(960, 60))
	s.actor(&"b", &"invader", Vector2(985, 110))
	s.object(&"chair", "chair", Vector2(740, 60), { "facing": Vector2.LEFT })
	s.actor(&"d", &"defender", Vector2(760, 60), { "facing": Vector2.LEFT })


func run(t: TestContext) -> void:
	for id in IDS:
		Probe.arm(t.actor(id), 1, 0)
	if not t.require(IDS.all(func(id): return Probe.count(t.actor(id), Probe.STUN) == 1), "both invaders carry a stun grenade (Character.item_count(7))"):
		return
	var d := t.actor(&"d")
	d.interact_with(t.object(&"chair"), "sit")
	if not t.require(await t.until(d.is_busy, 1.0), "set-up: the defender sits on the kitchen chair (is_busy)"):
		return
	Investigate.gunfire(Maps.KITCHEN_CENTRE)
	var door := Entry.BACK
	var seen := { &"a": [], &"b": [] }
	var phases := { &"a": [], &"b": [] }
	var samples: Array = []
	var end := t.time + 100.0
	var through := func(): return not Entry.calls(t, "going_in").is_empty() and not Probe.booms(t, &"stun").is_empty()
	while t.time < end and not (through.call() and t.time > float(Probe.booms(t, &"stun")[0]["time"]) + 2.0):
		var pos := {}
		var facing := {}
		for id in IDS:
			var brain := Entry.brain(t, id)
			var act := str(brain.current_act())
			if not seen[id].has(act):
				seen[id].append(act)
			var phase := str(Entry.entry(brain).get("phase", ""))
			phases[id].append([t.time, phase])
			pos[id] = t.actor(id).global_position
			facing[id] = t.actor(id).facing
		samples.append({ "t": t.time, "pos": pos, "facing": facing })
		await t.frames(1)
	var took := IDS.any(func(id): return seen[id].any(func(a): return a.contains("stun_entry")))
	if not t.require(took, "the AI took STUN ENTRY into the kitchen (acts: %s)" % str(seen)):
		return
	var claims := Entry.calls(t, "claim")
	var slot_of := func(id: StringName) -> int:
		var mine := claims.filter(func(e): return e.get("speaker") == t.actor(id))
		return int(mine.back().get("slot", 0)) if not mine.is_empty() else 0
	var thrower_id: StringName = &"a" if slot_of.call(&"a") == 2 else &"b"
	var point_id: StringName = &"b" if thrower_id == &"a" else &"a"
	t.expect_eq([slot_of.call(thrower_id), slot_of.call(point_id)], [2, 1], "the stack is two: the point in slot 1, the second in slot 2")

	var throws := Probe.raw(t, &"throw")
	if not t.require(throws.size() == 1, "one stun was thrown (%d throws)" % throws.size()):
		return
	var throw: Dictionary = throws[0]
	t.check(throw["data"].get("attacker") == t.actor(thrower_id) and throw["data"].get("kind") == &"stun", "by the slot-2 member (the thrower is %s)" % thrower_id)
	var banged := Entry.first_call_time(t, "bang", thrower_id)
	t.check(banged < INF and banged <= float(throw["time"]), "which radioed bang before the throw (at %.2f s, the throw at %.2f s)" % [banged, float(throw["time"])])
	var boom: Dictionary = Probe.booms(t, &"stun")[0]
	var at: Vector2 = boom["data"]["position"]
	t.check(Maps.HOUSE_KITCHEN.has_point(at) and at.distance_to(door["pos"]) >= 120.0, "the stun went through the doorway to the room's far side (burst at %s, %.0f px from the door)" % [str(at.round()), at.distance_to(door["pos"])])

	# Everyone held their slot turned away from the door while the stun was in the room.
	var window: Array = samples.filter(func(s): return float(s["t"]) >= float(boom["time"]) - 0.5 and float(s["t"]) <= float(boom["time"]))
	for id in IDS:
		var looking := window.filter(func(s): return Entry.faces_through(door, s["pos"][id], s["facing"][id]))
		t.check(looking.is_empty(), "%s was turned away from the door as the stun went off (%d of %d frames looking through it)" % [id, looking.size(), window.size()])

	# The point skipped the pie and crossed on the bang.
	var point_phases: Array = phases[point_id]
	t.check(not point_phases.any(func(p): return p[1] == "pie"), "the point never sliced the pie")
	var went_in: float = Entry.first_call_time(t, "going_in", point_id, door["id"])
	t.check(went_in >= float(boom["time"]) - 0.1 and went_in <= float(boom["time"]) + 1.2, "and crossed on the bang (going_in at %.2f s, the stun went off at %.2f s)" % [went_in, float(boom["time"])])

	var flash := Probe.stuns(t, t.actor(&"d"))
	t.check(not flash.is_empty() and float(flash[0]["data"].get("blind", 0.0)) > 0.0, "the defender inside was blinded")
