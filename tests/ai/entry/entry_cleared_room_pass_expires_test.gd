extends GameTest

## E18 (issue #51, R3): a cleared room counts as safe to walk past for `entry_pass_clear_time` (60 s) only. A one-room house with its
## front door in the south wall; an ally radios the room clear. Sent east past the house at once, the invader walks the plain way along
## the south wall through the front door's view, neither going round it nor covering the door. Once the clear is more than 60 s old,
## sent back west past the same door it goes round the house or covers the door from the jamb first (E15 / E18). Scripted Von (one
## mechanism): each walk is an investigation of gunfire heard on the far side.
##
## The clear's age is the perception memory's, which counts game time (`GameClock`, frames run while unpaused); the test waits
## (`door_view_probe.wait_wall`, paced to real time) until 61 s have passed in sim time, and on the wall clock as well. While it
## waits the invader is held still (`speed` 0) where its first walk ended, so the second walk starts from the far side (a held
## move re-decides only at its commit cap, so the second order is waited for).

const Entry := preload("res://tests/_ai/entry_probe.gd")
const View := preload("res://tests/_ai/door_view_probe.gd")
const Probe := preload("res://tests/_ai/investigate_probe.gd")
const ROOM := Rect2(0, 0, 600, 300)
const FRONT := { "id": "door_300_300", "pos": Vector2(300, 300), "width": 80.0, "out": Vector2.DOWN, "room": ROOM, "room_key": "front_room" }
const WEST := Vector2(-100, 230)
const EAST := Vector2(700, 230)
## Seconds of gun through the doorway, from its outer side, that count as having secured it (as E15's tests).
const COVERED := 0.8


func describe() -> Dictionary:
	return {
		"name": "A cleared room is passed freely for a minute, then its doorway is avoided or secured",
		"description": "With the house radioed clear, the invader walks past the open front door freely; once the clear is over 60 s old it goes round the house or covers the door before passing it.",
		"tags": ["ai", "entry", "door_view", "callout", "scripted"],
		"timeout": 260.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([{ "key": "front_room", "type": "living_room", "rect": ROOM }], [{ "pos": FRONT["pos"], "width": FRONT["width"] }])
	Entry.guard_rules(s, ["investigate"])
	Entry.npc(s, &"inv", WEST)
	# The ally that cleared the room: it radios the clear and plays no part otherwise (far north of the house, out of the way).
	s.actor(&"ally", &"puppet", Vector2(300, -120), { "faction": &"invader", "max_health": 1000000.0 })


func run(t: TestContext) -> void:
	var inv := t.actor(&"inv")
	var ally := t.actor(&"ally")
	EventBus.post(&"callout", {
		"speaker": ally, "faction": ally.faction, "position": ally.global_position, "status": "", "path": "",
		"label": "", "target_id": 0, "point": ally.global_position, "entry_step": "clear", "opening": FRONT["id"],
		"cleared_room": "front_room",
	})
	var cleared_ms := Time.get_ticks_msec()
	var cleared_t := t.time
	Probe.gunfire(EAST)
	var east := func(): return inv.global_position.distance_to(EAST) < 40.0
	var first := await Entry.watch(t, [&"inv"], FRONT, 40.0, east)
	if not t.require(east.call() and Entry.asked(t, "investigate"), "the invader investigated the gunfire east of the house (act %s, at %s)" % [Entry.brain(t, &"inv").current_act(), inv.global_position.round()]):
		return
	var first_ms := Time.get_ticks_msec() - cleared_ms
	if not t.require(first_ms < View.PASS_CLEAR_TIME * 1000.0 * 0.5, "set-up: the first walk ended well within the minute (%.1f s after the clear)" % (first_ms / 1000.0)):
		return
	t.check(View.first_in_view(t, first, &"inv", FRONT) < INF, "just after the clear it walked the plain way, through the front door's view")
	t.check(View.time_covering(first, &"inv", FRONT) < COVERED, "and did not stop to cover the door (%.1f s)" % View.time_covering(first, &"inv", FRONT))

	# Hold it on the far side until the clear is more than a minute old, on the wall clock and in sim time.
	inv.speed = 0.0
	await View.wait_wall(t, cleared_ms, View.PASS_CLEAR_TIME + 1.0, cleared_t, View.PASS_CLEAR_TIME + 1.0)
	Probe.gunfire(WEST)
	var investigating_west := func(): return str(Entry.brain(t, &"inv").current_act()).contains("lead_gunfire_-1")
	if not t.require(await t.until(investigating_west, 40.0), "set-up: after the minute it investigates the gunfire west of the house (act %s)" % Entry.brain(t, &"inv").current_act()):
		return
	inv.speed = 150.0
	var west := func(): return inv.global_position.x < ROOM.position.x - 40.0
	var second := await Entry.watch(t, [&"inv"], FRONT, 60.0, west)
	if not t.require(west.call(), "the invader walked back west past the house (act %s, at %s)" % [Entry.brain(t, &"inv").current_act(), inv.global_position.round()]):
		return
	var in_view := View.first_in_view(t, second, &"inv", FRONT)
	var from_side := signf(Entry.lateral(FRONT, EAST))
	var covered := View.time_covering(second, &"inv", FRONT, View.axis_crossed_at(second, &"inv", FRONT, from_side))
	t.check(in_view == INF or covered >= COVERED, "with the clear over a minute old it went round the front door's view or covered the door first (in the view at %.2f s, covered %.1f s)" % [in_view, covered])
