extends GameTest

## G18 as amended (issue #51, R6): a room an ally radioed a hostile or a fight in is suspect. An ally in the hall is fighting a
## householder it sees in the kitchen through the hall door, and says so on the radio; the stack of two invaders, both carrying a stun,
## at the kitchen's back door (which cannot see the householder) takes STUN ENTRY into the kitchen, not the quiet ENTER. The whole
## pipeline runs with real Von for the stack; a `require` that it went for the kitchen by its back door comes first.
##
## Premises: the ally is a puppet whose radio call is posted first thing in `run` (a call that lands before the stack decides, as in a
## match where the fight started first: an NPC's own call would come only once Von has answered it, after the stack's first decision,
## and a call forces no re-decision). It is shaped as `GoalController._post_callout` sends an ENGAGE from where it stands, plus the
## `target_pos` every combat call is to carry (the hostile's last-known spot, issue #51). The householder is a puppet in the kitchen's
## north-east corner, hidden from every spot outside the back door; unkillable, it never shoots. Both invaders are armed with a stun at
## the start of `run`, the way Main arms a spawn.

const Suspect := preload("res://tests/_ai/suspect_probe.gd")
const ALLY_AT := Vector2(690, 420)
const HOSTILE_AT := Vector2(790, 45)


func describe() -> Dictionary:
	return {
		"name": "A stack takes a stun entry into a room an ally radioed a fight in",
		"description": "An ally in the hall radios that it is fighting a householder in the kitchen; the stack of two with a stun at the back door takes STUN ENTRY, not the quiet ENTER.",
		"tags": ["ai", "grenade", "entry", "stun", "callout", "von"],
		"requires_von": true,
		"timeout": 80.0,
	}


func configure(s: TestSetup) -> void:
	Suspect.world(s)
	s.actor(&"ally", &"puppet", ALLY_AT, { "faction": &"invader", "max_health": 1000000.0, "aim_point": HOSTILE_AT })
	s.actor(&"hostile", &"puppet", HOSTILE_AT, { "faction": &"household", "max_health": 1000000.0 })


func run(t: TestContext) -> void:
	if not t.require(Suspect.arm(t), "both invaders carry a stun grenade (Character.item_count(7))"):
		return
	var ally := t.actor(&"ally")
	var hostile := t.actor(&"hostile")
	var target := "t_%d" % hostile.get_instance_id()
	EventBus.post(&"callout", {
		"speaker": ally, "faction": ally.faction, "position": ally.global_position, "status": "",
		"path": "combat/%s/engage/fire_here" % target, "label": "COMBAT - %s - ENGAGE - where you stand" % hostile.name,
		"target_id": hostile.get_instance_id(), "point": ally.global_position, "target_pos": HOSTILE_AT,
	})
	var result: Dictionary = await Suspect.watch(t, 60.0)
	Suspect.check_stun_entry(t, result, "an ally's radio of a fight in the kitchen")
