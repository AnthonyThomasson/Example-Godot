extends GameTest

## H1 (`docs/hearing.md`, issue #51, R5), the mechanism: an NPC hears the footfalls of characters not of its faction, through walls,
## out to a range set by the gait: walking 250 px, running 450 px, crouched 100 px; its own side's steps it does not take for anyone's.
## A defender stands in a closed room; on the far side of its wall puppets walk one at a time, each up and down a short lane at a set
## distance from it: a walk inside and outside the walking range, a run inside and outside the running range, a crouched walk inside
## and outside the crouched range (the second still inside the walking range, so only the crouch keeps it unheard), and an ally walking
## well inside the walking range. What it heard is read off its memory, `debug_memory()["footsteps"]` (`[{ pos, age }]`, as
## `gunfire`), and the steps themselves off the `footfall` events, which now say whose they are (`character`) and whether the
## walker was `crouched`. Scripted Von (one mechanism); the defender is held still (`speed` 0) so the distances hold.

const LISTENER := Vector2(250, 400)
const LISTEN_ROOM := Rect2(0, 0, 300, 800)
const WALK_ROOM := Rect2(300, 0, 700, 800)
## The phases, in order: who walks, its lane (x, at a fixed distance from the listener), its gait, the half-length of its lane
## (centred on the listener's y) and whether it is to be heard.
const PHASES := [
	{ "id": &"walk_near", "x": 450.0, "gait": &"walk", "half": 60.0, "faction": &"invader", "heard": true },     # 200 to 209 px
	{ "id": &"walk_far", "x": 580.0, "gait": &"walk", "half": 60.0, "faction": &"invader", "heard": false },     # 330 px and more
	{ "id": &"run_near", "x": 650.0, "gait": &"run", "half": 150.0, "faction": &"invader", "heard": true },      # 400 to 427 px
	{ "id": &"run_far", "x": 830.0, "gait": &"run", "half": 150.0, "faction": &"invader", "heard": false },      # 580 px and more
	{ "id": &"crouch_near", "x": 328.0, "gait": &"crouch", "half": 40.0, "faction": &"invader", "heard": true },  # 78 to 88 px
	{ "id": &"crouch_far", "x": 410.0, "gait": &"crouch", "half": 40.0, "faction": &"invader", "heard": false }, # 160 px and more
	{ "id": &"ally", "x": 372.0, "gait": &"walk", "half": 60.0, "faction": &"household", "heard": false },       # 122 to 136 px
]
## How long (sim s) each walker paces its lane.
const PACE_TIME := 4.0


func describe() -> Dictionary:
	return {
		"name": "Footsteps are heard through walls, out to a range set by the gait",
		"description": "A defender hears an invader walking within 250 px, running within 450 px and crouched within 100 px, through a wall; farther off it does not, and an ally's steps it never takes for anyone's.",
		"tags": ["ai", "perception", "hearing", "scripted"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "den", "type": "living_room", "rect": LISTEN_ROOM },
		{ "key": "hall", "type": "hallway", "rect": WALK_ROOM },
	])
	s.von_script([{ "pick": "stay" }])
	s.actor(&"listener", &"defender", LISTENER, { "speed": 0.0, "facing": Vector2.LEFT })
	for p in PHASES:
		s.actor(p["id"], &"puppet", Vector2(p["x"], LISTENER.y - p["half"]), { "faction": p["faction"], "max_health": 1000000.0 })


func run(t: TestContext) -> void:
	var brain := t.controller(&"listener", &"debug_memory")
	if not t.require(brain != null, "set-up: the listener is an NPC"):
		return
	for p in PHASES:
		var who := t.puppet(p["id"])
		var walker := t.actor(p["id"])
		var before := _heard(brain)
		var steps_from := t.events.size()
		who.set_posture(&"crouch" if p["gait"] == &"crouch" else &"stand")
		who.set_run(p["gait"] == &"run")
		await t.seconds(0.6)
		var ends := [Vector2(p["x"], LISTENER.y + p["half"]), Vector2(p["x"], LISTENER.y - p["half"])]
		var leg := 0
		var end_at := t.time + PACE_TIME
		who.walk_to(ends[0])
		while t.time < end_at:
			if who.has_arrived():
				leg = (leg + 1) % 2
				who.walk_to(ends[leg])
			await t.frames(1)
		who.stop()
		who.set_run(false)
		await t.seconds(0.3)
		var lane := Rect2(float(p["x"]) - 30.0, LISTENER.y - float(p["half"]) - 30.0, 60.0, float(p["half"]) * 2.0 + 60.0)
		var steps: Array = t.events.slice(steps_from).filter(func(e): return e["topic"] == &"footfall" and lane.has_point(e["data"]["position"]))
		if not t.require(steps.size() >= 4, "set-up: %s paced its lane (%d footfalls)" % [p["id"], steps.size()]):
			return
		t.check(steps.all(func(e): return e["data"].get("character") == walker), "%s's footfalls say whose they are (footfall `character`)" % p["id"])
		t.check(steps.all(func(e): return bool(e["data"].get("crouched", not (p["gait"] == &"crouch"))) == (p["gait"] == &"crouch")), "%s's footfalls say crouched = %s" % [p["id"], p["gait"] == &"crouch"])
		if p["gait"] == &"run":
			t.check(steps.any(func(e): return bool(e["data"].get("running", false))), "%s ran" % p["id"])
		var new := _heard(brain).filter(func(h): return not before.has(h))
		var near_lane := new.filter(func(h: Vector2): return absf(h.x - float(p["x"])) < 50.0)
		var nearest := INF
		for s in steps:
			nearest = minf(nearest, (s["data"]["position"] as Vector2).distance_to(LISTENER))
		if p["heard"]:
			t.check(not near_lane.is_empty(), "the listener heard %s through the wall (%d footfalls, the nearest %.0f px off; %d new heard)" % [p["id"], steps.size(), nearest, new.size()])
		else:
			t.check(new.is_empty(), "the listener did not hear %s (%d footfalls, the nearest %.0f px off; heard at %s)" % [p["id"], steps.size(), nearest, str(new)])


## The spots the listener has heard footsteps at, from its memory (`debug_memory()["footsteps"]`: `[{ pos, age }]`).
func _heard(brain: Node) -> Array:
	var out: Array = []
	for h in brain.debug_memory().get("footsteps", []):
		out.append(h.get("pos", Vector2.INF))
	return out
