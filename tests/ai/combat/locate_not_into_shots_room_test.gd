extends GameTest

## E9 as amended (issue #51, R10) / G17: shot at by someone it cannot see from a room it is outside of, the NPC treats the shooter as a
## barricaded hostile and is not offered LOCATE (a walk toward the shots, into that room): its COMBAT level offers GRENADE at the shots'
## origin (or RETREAT) instead. The contrast, shots from the open, still offers LOCATE: `locate_toward_shots_from_open`.
##
## Scripted Von (one mechanism: what the COMBAT level offers). A lone invader in the back garden, armed with a stun the way Main arms a
## spawn; the shot is one `hit` event nobody known fired (as tests/_ai/investigate_probe.gd posts gunfire), from a spot inside the kitchen
## out through the middle of the back doorway, landing beside the invader, so the line back from it (`shot_from`) runs into the kitchen
## (`stun_entry_shot_from_room`'s premise; a `require` checks it).

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const Suspect := preload("res://tests/_ai/suspect_probe.gd")
const AT := Vector2(980, -140)
## Where the shot came from (inside the kitchen) and where it landed (beside the invader): the line runs out through the middle of the
## back doorway (y 190 on the wall's plane).
const SHOOTER := Vector2(800, 286)
const LANDED := Vector2(968, -118)


func describe() -> Dictionary:
	return {
		"name": "No LOCATE toward shots from a room the NPC is outside of",
		"description": "Shot at through the back door from inside the kitchen by someone it cannot see, the invader's COMBAT level offers GRENADE at the shots' origin and no LOCATE.",
		"tags": ["ai", "combat", "grenade", "locate", "scripted"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	Suspect.world(s, AT, Vector2.INF)
	s.von_script([{ "pick": "retreat" }])


func run(t: TestContext) -> void:
	if not t.require(Suspect.arm(t), "the invader carries a stun grenade (Character.item_count(7))"):
		return
	EventBus.post(&"hit", { "position": LANDED, "direction": (LANDED - SHOOTER).normalized(), "damage": 10.0, "attacker": null, "victim": null })
	var brain := Entry.brain(t, &"a")
	if not t.require(await t.until(func(): return not Probe.offered(brain).is_empty(), 10.0), "the invader walked its COMBAT level after the shot (act %s)" % brain.current_act()):
		return
	var shots: Array = brain.debug_memory().get("shot_from", [])
	if not t.require(not shots.is_empty() and _runs_into(shots[0], Maps.HOUSE_KITCHEN), "set-up: the line back from the shot runs into the kitchen (%s)" % str(shots)):
		return
	var offered := Probe.offered(brain)
	t.check(not offered.has("locate"), "LOCATE is not offered toward the kitchen the shots came from (offered %s)" % str(offered))
	t.check(offered.has("grenade"), "GRENADE at the shots' origin is offered (offered %s)" % str(offered))


## Whether the line back from a shot (`shot_from` memory: `at` where it landed, `pos` the wall behind) runs into `room`.
func _runs_into(shot: Dictionary, room: Rect2) -> bool:
	var poly := PackedVector2Array([room.position, Vector2(room.end.x, room.position.y), room.end, Vector2(room.position.x, room.end.y)])
	return not Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([shot["at"], shot["pos"]]), poly).is_empty()
