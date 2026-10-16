extends GameTest

## LD1 (`docs/leadership.md`): every AI ttl and timer runs on `GameClock`, which advances only while the tree is
## unpaused, so a pause of any length expires nothing. An invader in the Terrace house's kitchen sees a household target and hears an
## ally's radio call; the target then steps out of its sight and the tree is paused for 10 s of wall time, more than the contact's
## 4 s and the callout's 6 s ttl. On resume the contact and the callout are still known, and no older than they were (give or take
## the frames around the pause).
##
## Scripted Von (one mechanism: the memory's clock). The target is a puppet that cannot be killed and is moved out of sight by hand
## (a teleport behind the kitchen's east wall), so the moment the NPC last saw it is known to the frame.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")

## How long the tree is held paused, in wall seconds: past the contact's ttl (4 s) and the callout's (6 s).
const PAUSE_WALL := 10.0
## Behind the kitchen's east wall, out of the NPC's sight through the back door.
const HIDDEN := Vector2(1000, 40)


func describe() -> Dictionary:
	return {
		"name": "A pause expires no AI memory",
		"description": "An NPC that knows a contact and an ally's callout still knows both, no older, after the tree is paused for 10 s of wall time (LD1: the pausable AI clock).",
		"tags": ["ai", "perception", "leadership", "clock", "scripted"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_script([{ "pick": "engage" }])
	s.switch(&"projectile.flyover", false)
	s.actor(&"a", &"invader", Vector2(600, 190), { "max_health": 1000000.0, "facing": Vector2.RIGHT, "aim_point": Vector2(900, 190) })
	s.actor(&"target", &"puppet", Vector2(760, 200), { "faction": &"household", "max_health": 1000000.0, "aim_point": Vector2(600, 190) })
	# The ally on the radio: an invader puppet in the back garden, out of the NPC's sight (it is only heard).
	s.actor(&"mate", &"puppet", Vector2(1000, 330), { "faction": &"invader", "max_health": 1000000.0 })


func run(t: TestContext) -> void:
	var b := Order.brain(t, &"a")
	var target := t.actor(&"target")
	var mate := t.actor(&"mate")
	if not t.require(await t.until(func(): return _contact(b, target).get("visible", false), 3.0), "the NPC sees the target (premise)"):
		return
	EventBus.post(&"callout", {
		"speaker": mate, "faction": mate.faction, "position": mate.global_position, "status": "", "path": "search/enter",
		"label": "SEARCH - ENTER", "target_id": 0, "point": mate.global_position,
	})
	if not t.require(await t.until(func(): return not _callout(b, mate).is_empty(), 1.0), "the NPC heard the ally's callout (premise)"):
		return
	target.global_position = HIDDEN
	target.velocity = Vector2.ZERO
	if not t.require(await t.until(func(): return not _contact(b, target).get("visible", true), 1.0), "the target is out of the NPC's sight (premise)"):
		return
	var contact_age := float(_contact(b, target).get("age", INF))
	var callout_age := float(_callout(b, mate).get("age", INF))

	await Order.pause_for(t, PAUSE_WALL)
	await t.frames(1)

	var names: Array = b.debug_state().get("contacts", []).map(func(c): return String(c.get("name", "")))
	t.check(names.has(String(target.name)), "the contact is still known after the pause (contacts: %s)" % str(names))
	var after := _contact(b, target)
	t.check(not after.is_empty() and float(after.get("age", INF)) < contact_age + 1.0,
		"the contact aged no more than the frames around the pause (%.2f s before, %s after)" % [contact_age, str(after.get("age", "gone"))])
	var heard := _callout(b, mate)
	t.check(not heard.is_empty(), "the ally's callout is still known after the pause")
	t.check(not heard.is_empty() and float(heard.get("age", INF)) < callout_age + 1.0,
		"the callout aged no more than the frames around the pause (%.2f s before, %s after)" % [callout_age, str(heard.get("age", "gone"))])


## What the NPC knows of character `who` (`known_contacts_for_display()`: `{ node, pos, name, hostile, visible, age }`), or {}.
func _contact(b: Node, who: Node) -> Dictionary:
	for c in b.known_contacts_for_display():
		if c.get("node") == who:
			return c
	return {}


## The callout the NPC holds from `speaker` (`debug_memory()["callouts"]`: `{ name, age, label, pos, point }`), or {}.
func _callout(b: Node, speaker: Node) -> Dictionary:
	for c in b.debug_memory().get("callouts", []):
		if String(c.get("name", "")) == String(speaker.name):
			return c
	return {}
