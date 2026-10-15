extends GameTest

## E17 as amended by issue #51 R17 with R11: footsteps heard while a quiet stack with a stun listens at the stack turn the entry into a bang
## before the point has started the pie. The stack of two at the back door takes the quiet ENTER (scripted Von, nothing suspected); a second
## after the point is in its slot, a householder walks up and down just inside the kitchen's east wall north of the door, out of sight of the
## stack and within earshot. The point is still in its slot when the steps are heard: the claims turn to bang, the bang is called and a stun
## goes off in the kitchen before anyone goes in, and the point never sliced the pie before the bang was called.
##
## Premises: the householder is a puppet that cannot be killed and never shoots, walked to and fro (a defender moving about the kitchen) from
## the moment the point has stood in its slot a second; the invaders are armed with one stun each at the start of `run`, the way Main arms a
## spawn.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Listen := preload("res://tests/_ai/listen_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
## The householder's beat, inside the kitchen's east wall north of the door: behind the wall from every slot north of the door and from a
## thrower's spot in front of it, within the 250 px a walk is heard at.
const BEAT_A := Vector2(790, 20)
const BEAT_B := Vector2(790, 85)
const AFTER := 1.0


func describe() -> Dictionary:
	return {
		"name": "Steps heard while a quiet stack listens turn it into a bang before the pie",
		"description": "A quiet stack of two with a stun holds at the back door; a second in, a householder is heard walking in the kitchen: the claims turn to bang and a stun goes off in the kitchen before anyone goes in, the point never having sliced the pie.",
		"tags": ["ai", "grenade", "entry", "stun", "listen", "hearing", "scripted"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Listen.world(s)
	Probe.hostile(s, &"h", BEAT_A, Maps.DOOR_BACK)


func run(t: TestContext) -> void:
	for id in Listen.IDS:
		Probe.arm(t.actor(id), 1, 0)
	if not t.require(Listen.IDS.all(func(id): return Probe.count(t.actor(id), Probe.STUN) == 1), "each invader carries a stun"):
		return
	var p := await Listen.wait_point_ready(t, 15.0)
	if not t.require(p != &"", "the stack's point got to its slot at the back door"):
		return
	if not t.require(Entry.calls(t, "claim").all(func(c): return c.get("bang") == false), "set-up: the stack went for it quietly (ENTER)"):
		return
	var ready := Entry.first_call_time(t, "ready", p, Entry.BACK["id"])
	var h := t.puppet(&"h")
	var samples: Array = []
	var heard := [INF]
	var walking := [false]
	var leg := [BEAT_B]
	var gone_in := func() -> bool:
		var phase := str(Entry.entry(Entry.brain(t, p)).get("phase", ""))
		if samples.is_empty() or samples.back()[1] != phase:
			samples.append([t.time, phase])
		if not walking[0] and t.time >= ready + AFTER:
			walking[0] = true
			h.walk_to(leg[0])
		elif walking[0] and h.has_arrived():
			leg[0] = BEAT_A if leg[0] == BEAT_B else BEAT_B
			h.walk_to(leg[0])
		if heard[0] == INF and Listen.IDS.any(func(id): return not Entry.brain(t, id).debug_memory().get("footsteps", []).is_empty()):
			heard[0] = t.time
		return not Entry.calls(t, "going_in").is_empty()
	await t.until(gone_in, 40.0)
	if not t.require(heard[0] < INF, "set-up: the stack heard the householder's steps (footsteps memory)"):
		return
	var bang_called := INF
	for c in Probe.raw(t, &"callout", func(d): return String(d.get("entry_step", "")) == "bang"):
		bang_called = float(c["time"])
		break
	var pie := Listen.first(samples, "pie", ready)
	t.check(pie > minf(heard[0], bang_called), "the point was still listening in its slot when the steps were heard: it had not started the pie (pie at %.2f s, steps heard at %.2f s, bang called at %.2f s, its ready at %.2f s; phases %s)" % [pie, heard[0], bang_called, ready, str(samples)])
	var going_in: float = float(Probe.raw(t, &"callout", func(d): return String(d.get("entry_step", "")) == "going_in")[0]["time"]) if not Entry.calls(t, "going_in").is_empty() else INF
	for id in Listen.IDS:
		var turned := Probe.raw(t, &"callout", func(d): return d.get("speaker") == t.actor(id) and String(d.get("entry_step", "")) != "" and d.get("bang") == true)
		t.check(not turned.is_empty(), "%s's claims turned to bang" % id)
	t.check(bang_called < going_in, "the bang was called before anyone went in (bang %.2f s, going_in %.2f s)" % [bang_called, going_in])
	var booms := Probe.booms(t, &"stun").filter(func(b): return Maps.HOUSE_KITCHEN.has_point(b["data"]["position"]))
	t.check(not booms.is_empty() and float(booms[0]["time"]) <= going_in, "a stun went off in the kitchen before anyone went in (bursts %s, going_in %.2f s)" % [str(booms.map(func(b): return snappedf(float(b["time"]), 0.01))), going_in])
