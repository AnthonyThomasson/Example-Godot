extends GameTest

## E18 (issue #51, R9): the route bands Von reads ("short / medium / long route") measure the route the NPC will walk: the
## door-avoiding one when it would take it, else the plain one. A small one-room house with its front door in the south wall; the
## invader stands west of it and gunfire is heard east of it. The plain way there, along the south wall through the front door's
## view, is a short route (under 400 px); the way the invader walks, round the house's north side out of the view (within the cap),
## is a medium one. The gunfire lead's option says "medium route". Scripted Von (one mechanism: the wording), the invader held still
## (`speed` 0) so the snapshot is the one taken from where it stands.

const View := preload("res://tests/_ai/door_view_probe.gd")
const Probe := preload("res://tests/_ai/investigate_probe.gd")
const ROOM := Rect2(0, 0, 240, 160)
const FRONT := { "id": "door_120_160", "pos": Vector2(120, 160), "width": 80.0, "out": Vector2.DOWN, "room": ROOM, "room_key": "front_room" }
const START := Vector2(-60, 220)
const GUNFIRE := Vector2(300, 220)
## The way round the north side of the house.
const ROUND := [Vector2(-25, -25), Vector2(265, -25)]
## SnapshotVocab.route_buckets: short up to 400 px, medium up to 900 px.
const SHORT := 400.0
const MEDIUM := 900.0


func describe() -> Dictionary:
	return {
		"name": "A route band is the band of the route walked round a doorway's view",
		"description": "Gunfire past a small house's front door: the plain way is short, the way round the house out of the door's view is medium, and the lead's option says medium route.",
		"tags": ["ai", "entry", "door_view", "snapshot", "scripted"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([{ "key": "front_room", "type": "living_room", "rect": ROOM }], [{ "pos": FRONT["pos"], "width": FRONT["width"] }])
	s.von_script([{ "pick": "investigate" }])
	s.actor(&"inv", &"invader", START, { "speed": 0.0, "facing": Vector2.RIGHT })


func run(t: TestContext) -> void:
	Probe.gunfire(GUNFIRE)
	var map := t.world.get_world_2d().navigation_map
	var plain := NavBuilder.route(map, START, GUNFIRE)
	var plain_len := NavBuilder.path_length(plain)
	var crosses := false
	for i in range(1, plain.size()):
		for k in 20:
			crosses = crosses or View.in_view(t, FRONT, plain[i - 1].lerp(plain[i], k / 20.0))
	var round_len := NavBuilder.path_length(NavBuilder.route(map, START, ROUND[0])) + ROUND[0].distance_to(ROUND[1]) + NavBuilder.path_length(NavBuilder.route(map, ROUND[1], GUNFIRE))
	if not t.require(crosses and plain_len <= SHORT, "set-up: the plain route is short and runs through the front door's view (%.0f px)" % plain_len):
		return
	if not t.require(round_len > SHORT and round_len <= MEDIUM and round_len <= View.AVOID_RATIO * plain_len + View.AVOID_SLACK, "set-up: the way round is medium and within the cap (%.0f px)" % round_len):
		return
	if not t.require(View.polygon(FRONT)[1].y > 320.0, "set-up: the view covers the outdoor strip south of the house, so the only way round is the north side"):
		return
	var brain := t.controller(&"inv", &"debug_zones")
	if not t.require(await t.until(func(): return brain.debug_state().get("decisions", 0) >= 1 and not brain.debug_zones().is_empty(), 5.0), "set-up: the invader made its first decision"):
		return
	var leads: Array = brain.debug_zones().filter(func(z): return z["category"] == &"lead" and str(z["desc"]).contains("gunfire"))
	if not t.require(not leads.is_empty(), "the gunfire lead is offered (zones %s)" % str(brain.debug_zones().map(func(z): return z["desc"]))):
		return
	var desc := str(leads[0]["desc"])
	t.check(desc.contains("medium route"), "its option reads the band of the route walked round the door's view, medium (%.0f px), not the plain short one (%.0f px): \"%s\"" % [round_len, plain_len, desc])
