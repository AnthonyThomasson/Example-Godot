extends GameTest

## E9 / G17, the contrast to `locate_not_into_shots_room` (issue #51, R10): shot at by someone it cannot see from the open (the line back
## from the shot runs into no room), the NPC is still offered LOCATE, the walk toward the shots.
##
## Scripted Von (one mechanism: what the COMBAT level offers). The same lone invader in the back garden with a stun; the shot is one `hit`
## event nobody known fired, from the open garden to the south, landing beside it: the walk toward the shots runs down the garden (shots from
## beyond the walkable ground would give no LOCATE, issue #51 R12, `locate_never_where_it_stands`).

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const Suspect := preload("res://tests/_ai/suspect_probe.gd")
const AT := Vector2(980, -140)
## Where the shot came from (the open garden, east of the house, to the south) and where it landed (beside the invader).
const SHOOTER := Vector2(968, 400)
const LANDED := Vector2(968, -118)
## How far LOCATE looks toward the shots (the controller's `investigate_distance`), and a stride: a walk shorter than it ends where it began.
const REACH := 300.0
const STRIDE := 32.0


func describe() -> Dictionary:
	return {
		"name": "LOCATE toward shots from the open",
		"description": "Shot at from the open garden by someone it cannot see, the invader's COMBAT level still offers LOCATE toward the shots.",
		"tags": ["ai", "combat", "locate", "scripted"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	Suspect.world(s, AT, Vector2.INF)
	s.von_script([{ "pick": "retreat" }])


func run(t: TestContext) -> void:
	if not t.require(Suspect.arm(t), "the invader carries a stun grenade (Character.item_count(7))"):
		return
	var inv := t.actor(&"a")
	var here: Vector2 = inv.global_position
	var map: RID = (inv as Node2D).get_world_2d().navigation_map
	var toward := NavBuilder.snap(map, here + (SHOOTER - LANDED).normalized() * REACH)
	if not t.require(NavBuilder.path_length(NavBuilder.route(map, here, toward)) >= STRIDE,
			"the walk toward the shots goes somewhere (to %s from %s)" % [str(toward.round()), str(here.round())]):
		return
	EventBus.post(&"hit", { "position": LANDED, "direction": (LANDED - SHOOTER).normalized(), "damage": 10.0, "attacker": null, "victim": null })
	var brain := Entry.brain(t, &"a")
	if not t.require(await t.until(func(): return not Probe.offered(brain).is_empty(), 10.0), "the invader walked its COMBAT level after the shot (act %s)" % brain.current_act()):
		return
	var offered := Probe.offered(brain)
	t.check(offered.has("locate"), "LOCATE toward the shots from the open is offered (offered %s)" % str(offered))
