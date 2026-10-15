extends GameTest

## G17 / G18 (`docs/grenades.md`): the room a shot came from is the one behind the doorway it came through, not the room it landed in.
## An invader in the Terrace house's kitchen is shot at from the living room, through the doorway between them; it then steps into the
## hall. The line back from the shot (`shot_from`) starts where the shot landed, in the kitchen, and runs back through the doorway into the
## living room: the living room is where the shots came from, the kitchen is only where the invader stood. From the hall, its snapshot words
## the living room's entry as "shots at you came from there" and the kitchen's without it, and a GRENADE where the shots came from aims into
## the living room (a lob through the hall's doorway into it), never into the kitchen.
##
## Scripted Von (one mechanism: what the snapshot says and offers; the pick is RETREAT, which the test does not follow). Premises: the shot is
## one `hit` event nobody known fired (as tests/_ai/investigate_probe.gd posts gunfire), landing beside the invader; once it has been taken in,
## the invader is moved into the hall (it "steps" there), and it is held still (`speed` 0) and decides every 0.4 s, so the snapshots read are
## made where it was put (`speed` 0 and a 0.4 s commit and tactic cadence, as `flank_probe.npc` holds an NPC); it carries a stun and a frag, armed the way Main arms a spawn.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
## Where the invader stands in the kitchen, and where the shot lands beside it: the line back runs west through the middle of the
## living room doorway (y 150) to the living room's west wall.
const IN_KITCHEN := Vector2(565, 150)
const LANDED := Vector2(575, 150)
const SHOOTER := Vector2(250, 150)
## Where it steps to in the hall: in front of the doorway into the living room, so a lob into the living room goes through it.
const IN_HALL := Vector2(150, 420)
## A stack slot of an entry lies within this many px of its doorway.
const SLOT_NEAR := 120.0
const SHOTS_PHRASE := "shots at you came from there"


func describe() -> Dictionary:
	return {
		"name": "The shots' room is the one they came from, not where they landed",
		"description": "Shot at in the kitchen from the living room, an invader that steps into the hall suspects the living room and aims a grenade where the shots came from into it; the kitchen, where it stood, is neither.",
		"tags": ["ai", "grenade", "suspect", "scripted"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_script([{ "pick": "retreat" }])
	Entry.npc(s, &"a", IN_KITCHEN, 0.4, { "max_commit_time": 0.4, "tactic_interval": 0.4 }, { "facing": Vector2.LEFT, "speed": 0.0 })


func run(t: TestContext) -> void:
	var inv := t.actor(&"a")
	Probe.arm(inv, 1, 1)
	EventBus.post(&"hit", { "position": LANDED, "direction": (LANDED - SHOOTER).normalized(), "damage": 10.0, "attacker": null, "victim": null })
	var brain := Entry.brain(t, &"a")
	var taken := func(): return not (brain.debug_memory().get("shot_from", []) as Array).is_empty()
	if not t.require(await t.until(taken, 3.0), "the shot was taken in as one at the invader (act %s)" % brain.current_act()):
		return
	var shot: Dictionary = brain.debug_memory()["shot_from"][0]
	if not t.require(_runs_into(shot, Maps.HOUSE_KITCHEN) and _runs_into(shot, Maps.HOUSE_LIVING), "set-up: the line back from the shot runs from the kitchen into the living room (%s)" % str(shot)):
		return
	inv.global_position = IN_HALL
	var decisions := int(brain.debug_state().get("decisions", 0))
	var from_hall := func(): return int(brain.debug_state().get("decisions", 0)) >= decisions + 2 and not _entry_by(brain, Maps.DOOR_HALL_LIVING).is_empty()
	if not t.require(await t.until(from_hall, 6.0), "the invader decided again from the hall (act %s, at %s)" % [brain.current_act(), inv.global_position.round()]):
		return
	if not t.require(brain.debug_state().get("under_fire", false), "it is still under fire when it decides from the hall"):
		return
	var living := _entry_by(brain, Maps.DOOR_HALL_LIVING)
	var kitchen := _entry_by(brain, Maps.DOOR_HALL_KITCHEN)
	t.check(str(living.get("desc", "")).contains(SHOTS_PHRASE), "the living room's entry says the shots came from there (%s)" % living.get("desc", ""))
	t.check(not kitchen.is_empty() and not str(kitchen.get("desc", "")).contains(SHOTS_PHRASE), "the kitchen's entry does not (%s)" % kitchen.get("desc", "none offered"))
	var throws: Array = brain.debug_zones().filter(func(z): return z["category"] == &"grenade")
	var where := throws.map(func(z): return (z["point"] as Vector2).round())
	t.check(not throws.is_empty(), "a grenade where the shots came from is offered")
	t.check(throws.all(func(z): return Maps.HOUSE_LIVING.has_point(z["point"])), "every such throw aims into the living room (%s)" % str(where))
	t.check(not throws.any(func(z): return Maps.HOUSE_KITCHEN.has_point(z["point"])), "none aims into the kitchen, where the invader stood (%s)" % str(where))


## The entry zone of the last snapshot whose stack slot lies by the doorway at `door`, or {}.
func _entry_by(brain: Node, door: Vector2) -> Dictionary:
	for z in brain.debug_zones():
		if z["category"] == &"entry" and (z["point"] as Vector2).distance_to(door) < SLOT_NEAR:
			return z
	return {}


## Whether the line back from a shot (`shot_from` memory: `at` where it landed, `pos` the wall behind) runs into `room`.
func _runs_into(shot: Dictionary, room: Rect2) -> bool:
	var poly := PackedVector2Array([room.position, Vector2(room.end.x, room.position.y), room.end, Vector2(room.position.x, room.end.y)])
	return not Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([shot["at"], shot["pos"]]), poly).is_empty()
