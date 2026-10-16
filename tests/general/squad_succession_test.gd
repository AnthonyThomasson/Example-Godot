extends GameTest

## LD4 (`docs/leadership.md`): succession. When the leader dies, the next in line by the same rule (LD3: rank, then spawn
## order) leads within the frame, the squad posts `&"leader"` `{ faction, leader, previous }`, and the orders already given stand; a
## later order (from the new leader) replaces them.
##
## The match is built the way Main builds one (`match_world_probe.gd`: the house, its navmesh and the NPCs in one frame, each NPC
## through `MatchSpawner`), its three invaders ranked as Main ranks a unit (lead, sergeant, trooper), then given their squad as Main
## does (`Squad.setup`, `MatchSpawner.bind_squad`). The leader is killed with `take_damage`.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Match := preload("res://tests/_ai/match_world_probe.gd")
const Order := preload("res://tests/_ai/order_probe.gd")

const INVADERS := [Vector2(1000, 60), Vector2(1000, 330), Vector2(1100, 190)]


func describe() -> Dictionary:
	return {
		"name": "The next in line leads when the leader dies; orders stand",
		"description": "In a Main-built match the lead invader is killed: the sergeant leads within a frame, a leader event is posted, the trooper keeps the order it was given, and a newer order replaces it (LD4).",
		"tags": ["ai", "leadership", "squad", "match"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	# Scripted Von (the first option offered): the members' own decisions are not under test. The match gets a world of its own.
	s.von_script([])


func run(t: TestContext) -> void:
	if not t.require(ResourceLoader.exists(Order.SQUAD_SCRIPT), "the squad script exists (%s)" % Order.SQUAD_SCRIPT):
		return
	var built := Match.build(_layout(), t.world, INVADERS)
	var npcs: Array = built["npcs"]
	if not t.require(npcs.size() == 3, "the match has its three invaders"):
		return
	for i in npcs.size():
		npcs[i].rank = 2 - i  # As Main ranks a unit: the first its lead, the second its sergeant, the rest troopers.
	var squad: Node = (load(Order.SQUAD_SCRIPT) as GDScript).new()
	squad.name = "Squad_invader"
	built["world"].add_child(squad)
	squad.setup(&"invader", npcs, built["openings"], built["rooms"], null)
	if not t.require(Order.bind(npcs, squad), "Main hands each NPC its squad (MatchSpawner.bind_squad)"):
		return
	var lead: Node = npcs[0]
	var sergeant: Node = npcs[1]
	var trooper: Node = npcs[2]
	if not t.require(squad.leader() == lead, "the lead leads before it dies (premise)"):
		return
	await t.seconds(0.5)

	var given := Order.issue(squad, { "kind": Order.DEFEND, "to": [trooper], "room": "kitchen" })
	if not t.require(not given.is_empty(), "the squad posts the order (issue)"):
		return
	var brain := TestContext.controller_of(trooper, &"current_act")
	if not t.require(await t.until(func(): return Order.on_order(brain), 3.0), "the trooper takes the order (act %s)" % brain.current_act()):
		return

	lead.take_damage(1.0e9)
	if not t.require(lead.is_dead, "the lead is dead"):
		return
	await t.frames(1)
	t.check(squad.leader() == sergeant, "the sergeant leads within a frame (leader %s)" % _name(squad.leader()))
	var calls := t.events_of(&"leader", func(d): return d.get("faction") == &"invader")
	t.check(calls.size() == 1, "one leader event is posted (%d)" % calls.size())
	if not calls.is_empty():
		t.check(calls[0].get("leader") == sergeant and calls[0].get("previous") == lead,
			"it names the new leader and the previous one (%s after %s)" % [_name(calls[0].get("leader")), _name(calls[0].get("previous"))])
	t.check(Order.view(squad).get("leader") == sergeant, "the squad's view names the new leader")

	await t.seconds(2.0)
	var kept: Dictionary = Order.member_view(squad, trooper).get("order", {})
	t.check(String(kept.get("kind", "")) == Order.DEFEND and String(kept.get("room", "")) == "kitchen", "the trooper's order stands in the squad's view (%s)" % str(kept))
	t.check(Order.on_order(brain), "and the trooper is still carrying it out (act %s)" % brain.current_act())

	var newer := Order.issue(squad, { "kind": Order.DEFEND, "to": [trooper], "room": "living_room" })
	t.check(newer.get("leader") == sergeant, "a later order is given by the new leader (%s)" % _name(newer.get("leader")))
	await t.seconds(1.0)
	var now: Dictionary = Order.member_view(squad, trooper).get("order", {})
	t.check(String(now.get("room", "")) == "living_room", "the later order replaces the standing one (%s)" % str(now))
	# The order's own params (`debug_state()["order"]`): the trooper's walk into the house is guarded (LD8), so the running params may be
	# those of an entry detour on its way.
	var running: Dictionary = brain.debug_state().get("order", {}).get("params", {})
	t.check(String(running.get("room", "")) == "living_room", "in the trooper's running order too (params %s)" % str(running))


## The Terrace house, bare, as a layout to read the rooms and doorways from.
func _layout() -> TestSetup:
	var layout := TestSetup.new()
	Maps.house(layout, false)
	return layout


## A node's name for a message, or the value as text.
func _name(n: Variant) -> String:
	return String(n.name) if n is Node and is_instance_valid(n) else str(n)
