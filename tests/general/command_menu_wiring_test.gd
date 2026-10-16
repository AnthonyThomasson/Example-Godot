extends GameTest

## LD11 and interface 21 (`docs/leadership.md`): the wiring, in a match Main builds. With "Lead the team" on, Main builds one
## squad per faction from its combatants after arming them (`_build_squads`), hands each NPC its squad, and, because the human leads, adds
## the command menu and the order markers (`_build_command_menu`), the menu's `order_requested` connected to the squad's `issue`. The
## human leader opens the menu on the Terrace house's back door, ticks its two NPC teammates and orders "Stack into the kitchen with stun";
## after the menu closes (and the tree is unpaused), both NPCs claim slots at the back door under the order, in bang mode.
##
## Main's match-setup logic runs on a Main that never enters the tree (as `match_setup_test.gd` and `lead_rank_test.gd` do): the window's
## config through `_on_setup_chosen`, the NPCs placed with Main's `MatchSpawner`, the human a puppet standing in for the player, then
## Main's own `_arm_characters`, `_build_squads` and `_build_command_menu` over this world. Scripted Von (the first option offered): the
## NPCs' own decisions are not under test, and the order level asks nothing. `Settings.path` points at a scratch file.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const MainScript := preload("res://scenes/main.gd")
const MatchSpawner := preload("res://scenes/match_spawner.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")

const NPC_AT := [Vector2(960, 60), Vector2(985, 110)]


func describe() -> Dictionary:
	return {
		"name": "The leader's menu orders a stun stack in a Main-built match",
		"description": "With Lead the team on, Main builds the squads and the command menu; ordering two ticked teammates to stack on the back door with a stun makes both claim slots there in bang mode once the menu closes (LD11, interface 21).",
		"tags": ["setup", "match", "leadership", "order", "ui"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_script([])
	s.switch(&"ai.hostile_on_trespass", false)
	s.lock_interaction([&"camera", &"pause"])
	s.set_static(Settings, "path", "user://test_command_menu_wiring_settings.json")
	s.set_static(Settings, "setup", {})
	s.actor(&"me", &"puppet", Vector2(1150, 500), { "faction": &"invader", "max_health": 1000000.0 })


func run(t: TestContext) -> void:
	var main = MainScript.new()
	await main._on_setup_chosen({ "mode": "play", "side": "invader", "seed": 5, "lead": true,
		"defenders": { "count": 0 }, "invaders": { "count": 2 } })
	var spawner = MatchSpawner.new()
	spawner.world = t.world
	spawner.openings = t.world.get("openings")
	for i in NPC_AT.size():
		spawner.add_npc(MatchSpawner.INVADER_SCENE, spawner.npc_name("Invader", i), NPC_AT[i], t.rooms)
	var npcs: Array = spawner.combatants.duplicate()
	var me := t.actor(&"me")
	main._world = t.world
	main._spawner = spawner
	main._player = me
	var combatants: Array = npcs + [me]
	main._arm_characters(combatants)
	if not t.require(npcs.all(func(n): return Probe.count(n, Probe.STUN) >= 1), "Main armed the NPC invaders with a stun each (premise: the invaders' loadout)"):
		main.free()
		return
	if not t.require(_call(main, &"_build_squads", [combatants, t.rooms]), "Main builds the squads (_build_squads)"):
		main.free()
		return
	if not t.require(_call(main, &"_build_command_menu", [t.rooms]), "Main builds the command menu when the human leads (_build_command_menu)"):
		main.free()
		return
	var menu := _find_menu(t.world)
	if not t.require(menu != null, "the command menu is in the match's world (a node with open_at under World)"):
		main.free()
		return

	for npc in npcs:
		t.check(Order.tick(menu, String(npc.name), true), "the menu lists teammate %s to tick" % npc.name)
	menu.open_at(Order.BACK_NORTH)
	await t.frames(1)
	t.check(t.world.get_tree().paused, "the menu pauses the match")
	if not t.require(Order.choose(menu, "Stack into the kitchen with stun"), "it offers \"Stack into the kitchen with stun\" (items %s)" % str(Order.labels(menu))):
		t.world.get_tree().paused = false
		main.free()
		return
	await t.frames(1)
	t.check(not t.world.get_tree().paused, "choosing it closes the menu and unpauses")
	t.check(not Order.orders(t).is_empty(), "the squad posted the order (Main wired order_requested to Squad.issue)")

	var claimed := func(): return npcs.all(func(n): return not Order.ordered_claims(t, n, Entry.BACK["id"]).is_empty())
	t.check(await t.until(claimed, 10.0), "both teammates claim slots at the back door under the order")
	for n in npcs:
		var claims := Order.ordered_claims(t, n, Entry.BACK["id"])
		t.check(not claims.is_empty() and claims.all(func(c): return c.get("bang") == true), "%s claims in bang mode (%s)" % [n.name, str(claims.map(func(c): return c.get("bang")))])
	main.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))


## Call Main's `method` with as many of `args` as it takes; false when Main has no such method.
func _call(main: Object, method: StringName, args: Array) -> bool:
	for m in main.get_method_list():
		if StringName(m["name"]) == method:
			main.callv(method, args.slice(0, (m["args"] as Array).size()))
			return true
	return false


## The command menu Main built: the node with `open_at` and `order_requested` under `root`, or null.
func _find_menu(root: Node) -> Node:
	for n in root.find_children("*", "", true, false):
		if n.has_method("open_at") and n.has_signal("order_requested"):
			return n
	return null
