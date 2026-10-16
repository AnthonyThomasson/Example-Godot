extends GameTest

## LD12 (`docs/leadership.md`): the squad-leaders debug overlay (`scenes/ui/overlays/leader_overlay.gd`, `LeaderOverlay`, drawn at
## `DrawLayers.ABOVE`). A global row of the overlay bar (`OverlayRegistry.LEADERS`, `show_leaders`, off by default); while it is on, a
## crown over each squad's living leader, moving to the next leader when the view names one. A decoupled observer: `watch(views)` takes
## the squads' `view()` callables and `drawn()` is what is shown (`[{ point, node }]`), which this test reads.
##
## Fake squad views (plain data) over three puppets for the overlay itself; then Main's wiring, on a Main that never enters the tree (as
## `command_menu_wiring_test.gd` does): two real squads, Main's `_build_leader_overlay`, and the bar's toggle through
## `_on_overlay_toggled`. `Settings.path` points at a scratch file (a toggle is saved).

const Registry := preload("res://scenes/ui/overlays/overlay_registry.gd")
const LeaderOverlay := preload("res://scenes/ui/overlays/leader_overlay.gd")
const MainScript := preload("res://scenes/main.gd")
const Order := preload("res://tests/_ai/order_probe.gd")

## The two fake squads' views, as the overlay's `view` callables return them.
var _views := [{}, {}]


func describe() -> Dictionary:
	return {
		"name": "The squad-leaders overlay crowns each side's leader while on",
		"description": "show_leaders is a global overlay row, off by default; on, one crown over each squad's living leader, following a new leader; Main builds it for every match and the bar's toggle shows it (LD12).",
		"tags": ["ui", "overlay", "leadership"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600))
	s.set_static(Settings, "path", "user://test_leader_overlay_settings.json")
	s.set_static(Settings, "overlays", {})
	s.actor(&"lead", &"puppet", Vector2(150, 300), { "faction": &"invader" })
	s.actor(&"next", &"puppet", Vector2(400, 200), { "faction": &"invader" })
	s.actor(&"boss", &"puppet", Vector2(700, 400), { "faction": &"household" })


func run(t: TestContext) -> void:
	var rows: Array = Registry.ENTRIES.filter(func(e): return e["flag"] == Registry.LEADERS)
	t.check(rows.size() == 1 and not rows[0]["default"], "the overlay table has one show_leaders row, off by default")
	t.check(Registry.is_global(Registry.LEADERS), "show_leaders drives one global overlay, not each NPC's")

	var lead := t.actor(&"lead")
	var next := t.actor(&"next")
	var boss := t.actor(&"boss")
	var overlay: Node2D = LeaderOverlay.new()
	t.world.add_child(overlay)
	t.expect_eq(overlay.z_index, DrawLayers.ABOVE, "drawn above the standing world (DrawLayers.ABOVE)")
	_views = [{ "leader": lead, "members": [] }, { "leader": boss, "members": [] }]
	overlay.watch([func(): return _views[0], func(): return _views[1]])
	await t.frames(2)
	t.check(overlay.drawn().is_empty(), "nothing is drawn while the overlay is off")

	overlay.show_leaders = true
	await t.frames(2)
	t.check(_crowned(overlay, lead) and _crowned(overlay, boss) and overlay.drawn().size() == 2, "on, one crown over each squad's leader (%s)" % str(overlay.drawn()))

	_views[0]["leader"] = next
	await t.frames(2)
	t.check(_crowned(overlay, next) and not _crowned(overlay, lead), "when a view names a new leader the crown moves to it (%s)" % str(overlay.drawn()))
	_views[1]["leader"] = null
	await t.frames(2)
	t.expect_eq(overlay.drawn().size(), 1, "a squad with nobody left to lead has no crown")
	overlay.queue_free()

	await _check_main(t, lead, next, boss)


## Main builds the overlay over its squads, off while the flag is, and the bar's toggle shows it.
func _check_main(t: TestContext, lead: Node, next: Node, boss: Node) -> void:
	var main = MainScript.new()
	main._world = t.world
	main._overlay_flags = Registry.defaults()
	var squads := {}
	for row in [[&"invader", [lead, next]], [&"household", [boss]]]:
		var squad: Node = (load(Order.SQUAD_SCRIPT) as GDScript).new()
		t.world.add_child(squad)
		squad.setup(row[0], row[1], [], t.rooms, null)
		squads[row[0]] = squad
	main._squads = squads
	main._build_leader_overlay()
	var overlay: Node = t.world.get_node_or_null("LeaderOverlay")
	if not t.require(overlay != null, "Main builds the LeaderOverlay under World (_build_leader_overlay)"):
		main.free()
		return
	await t.frames(2)
	t.check(overlay.drawn().is_empty(), "off by default: no crown")
	main._on_overlay_toggled(Registry.LEADERS, true)
	await t.frames(2)
	t.check(_crowned(overlay, lead) and _crowned(overlay, boss), "the bar's toggle shows a crown over each squad's leader (%s)" % str(overlay.drawn()))
	main._on_overlay_toggled(Registry.LEADERS, false)
	await t.frames(2)
	t.check(overlay.drawn().is_empty(), "toggled off, the crowns go")
	main.free()


## Whether a crown is drawn over `who`.
func _crowned(overlay: Node, who: Node) -> bool:
	return (overlay.drawn() as Array).any(func(c): return c.get("node") == who and (c["point"] as Vector2).distance_to(who.global_position) < 2.0)
