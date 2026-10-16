extends RefCounted

## Shared helpers for the leadership tests (`docs/leadership.md` LD1 to LD12; not a test itself):
## `const Order := preload("res://tests/_ai/order_probe.gd")`. A squad per side with a leader, orders (`defend_room`, `stack`,
## `cancel`) carried on the `&"order"` bus topic, the ORDER decision node, the progress radio (`order_id`, `order_step` on a
## callout), the pausable AI clock (`GameClock`), the command menu and the order markers.
##
## Everything new is reached by path and duck-typed (`ResourceLoader.exists`, `has_method`, `get`), so a test loads and runs
## before the feature exists and goes red on an assertion that names what is missing, never on a parse error. The NPC is read
## only through its controller's public reads: `current_act()`, `debug_state()` (the `facts` of its last decision, the running
## leaf's `primitive` and `params`, the levels of its last walk), `debug_entry()`, `debug_memory()`,
## `known_contacts_for_display()` and its radio.

const SQUAD_SCRIPT := "res://scenes/ai/team/squad.gd"
const COMMAND_MENU_SCRIPT := "res://scenes/ui/hud/command_menu.gd"
const ORDER_MARKERS_SCRIPT := "res://scenes/ui/hud/order_markers.gd"
const MatchSpawner := preload("res://scenes/match_spawner.gd")
## The order kinds (LD5).
const DEFEND := "defend_room"
const STACK := "stack"
const CANCEL := "cancel"
## D7: the safety cap (s) on an ordered stack's wait for all its recipients' `ready`.
const ORDER_READY_CAP := 60.0


# --- The squad (LD3, LD4, LD5) ----------------------------------------------------------------------------

## Build the squad of `faction` the way Main does (a `Squad` node under the world, `setup(faction, members, openings, rooms,
## leader)`), over the test world's house. Null when the script does not exist yet.
static func squad(t: TestContext, faction: StringName, members: Array, leader: Node = null) -> Node:
	if not ResourceLoader.exists(SQUAD_SCRIPT):
		return null
	var s: Node = (load(SQUAD_SCRIPT) as GDScript).new()
	s.name = "Squad_%s" % faction
	t.world.add_child(s)
	var openings: Array = t.world.get("openings") if t.world.get("openings") != null else []
	if s.has_method("setup"):
		s.setup(faction, members, openings, t.rooms, leader)
	return s


## Hand each NPC of `npcs` its squad the way Main does (`MatchSpawner.bind_squad(npc, squad)`); false when the spawner has no
## `bind_squad` yet.
static func bind(npcs: Array, s: Node) -> bool:
	var spawner = MatchSpawner.new()
	if not spawner.has_method("bind_squad"):
		return false
	for npc in npcs:
		spawner.bind_squad(npc, s)
	return true


## `squad.issue(request)` (`{ kind, to, pos, room, bang }`, what the command menu emits): the order it posted, or {} (also
## when the squad has no `issue` yet).
static func issue(s: Node, request: Dictionary) -> Dictionary:
	if s == null or not s.has_method("issue"):
		return {}
	var out = s.issue(request)
	return out if out is Dictionary else {}


## The squad's `view()` (`{ leader, members: [{ node, order, step }] }`), or {}.
static func view(s: Node) -> Dictionary:
	return s.view() if s != null and s.has_method("view") else {}


## What the squad's view says of `member`: `{ node, order, step }`, or {}.
static func member_view(s: Node, member: Node) -> Dictionary:
	for m in view(s).get("members", []):
		if m.get("node") == member:
			return m
	return {}


## The `&"order"` events posted so far (their data), optionally only those whose `to` names `who`.
static func orders(t: TestContext, who: Node = null) -> Array:
	return t.events_of(&"order", func(d): return who == null or (d.get("to", []) as Array).has(who))


## Post an order straight onto the bus, as a squad does (LD5): `{ id, leader, faction, to, kind, ... }`.
static func post(order: Dictionary) -> void:
	EventBus.post(&"order", order)


# --- The NPC ---------------------------------------------------------------------------------------------

## The controller of actor `id`.
static func brain(t: TestContext, id: StringName) -> Node:
	return t.controller(id, &"debug_state")


## Whether the NPC's last decision snapshot had the fact `ordered` (LD5).
static func ordered(b: Node) -> bool:
	return bool((b.debug_state().get("facts", {}) as Dictionary).get("ordered", false)) if b != null else false


## How many decision walks the NPC has started.
static func decisions(b: Node) -> int:
	return int(b.debug_state().get("decisions", 0)) if b != null else 0


## The running leaf's primitive (`debug_state()["primitive"]`).
static func primitive(b: Node) -> String:
	return String(b.debug_state().get("primitive", "")) if b != null else ""


## The running leaf's params (`debug_state()["params"]`).
static func params(b: Node) -> Dictionary:
	return b.debug_state().get("params", {}) if b != null else {}


## Whether the NPC is carrying out an order: its decision path starts at the ORDER node (LD6).
static func on_order(b: Node) -> bool:
	return b != null and String(b.current_act()).begins_with("order")


## The levels of the NPC's last decision walk.
static func levels(b: Node) -> Array:
	return b.debug_state().get("decision", {}).get("levels", []) if b != null else []


## Force a decision on the NPC now without touching its brain: gunfire from nobody it knows lands beside it (`&"hit"`, no
## attacker), which it hears as fire at it.
static func gunfire_near(c: Node) -> void:
	EventBus.post(&"hit", { "position": c.global_position + Vector2(40, 0), "direction": Vector2.LEFT, "damage": 10.0, "attacker": null, "victim": null })


# --- The radio (LD7) ----------------------------------------------------------------------------------------

## The callouts that carry an `order_step` (LD7), optionally only step `step` and / or only from character `who`.
static func progress(t: TestContext, step := "", who: Node = null) -> Array:
	return t.events_of(&"callout", func(d):
		if String(d.get("order_step", "")) == "":
			return false
		if step != "" and String(d.get("order_step", "")) != step:
			return false
		return who == null or d.get("speaker") == who)


## The entry claims (any entry step) from `who` that carry an `order_id`.
static func ordered_claims(t: TestContext, who: Node, opening := "") -> Array:
	return t.events_of(&"callout", func(d):
		return d.get("speaker") == who and String(d.get("entry_step", "")) != "" and str(d.get("order_id", "")) != "" \
				and (opening == "" or String(d.get("opening", "")) == opening))


## The raw callout events (`{ topic, data, time }`) of entry step `step` from `who` (any step when ""), oldest first.
static func raw_calls(t: TestContext, who: Node, step := "") -> Array:
	var out: Array = []
	for e: Dictionary in t.events:
		if e["topic"] != &"callout" or e["data"].get("speaker") != who:
			continue
		var s := String(e["data"].get("entry_step", ""))
		if s == "" or (step != "" and s != step):
			continue
		out.append(e)
	return out


## The sim time of the first raw event of `topic` passing `filter`, or INF.
static func first_time(t: TestContext, topic: StringName, filter: Callable) -> float:
	for e: Dictionary in t.events:
		if e["topic"] == topic and filter.call(e["data"]):
			return float(e["time"])
	return INF


# --- The clock (LD1) ----------------------------------------------------------------------------------------

## Hold the tree paused for `wall_s` seconds of wall time, then unpause. The test's own clock stops with the world (the runner
## stops counting sim time while paused), so this waits on the wall clock, a physics frame at a time.
static func pause_for(t: TestContext, wall_s: float) -> void:
	var tree := t.world.get_tree()
	tree.paused = true
	var since := Time.get_ticks_msec()
	while Time.get_ticks_msec() - since < int(wall_s * 1000.0):
		OS.delay_msec(16)
		await t.frames(1)
	tree.paused = false


# --- UI (LD11, LD12) -----------------------------------------------------------------------------------------

## A new command menu (by path), added under the test world; null when the script does not exist yet.
static func command_menu(t: TestContext) -> Node:
	if not ResourceLoader.exists(COMMAND_MENU_SCRIPT):
		return null
	var menu: Node = (load(COMMAND_MENU_SCRIPT) as GDScript).new()
	menu.name = "CommandMenu"
	t.world.add_child(menu)
	return menu


## The items the menu offers now (`items()`: `[{ label, disabled, ... }]`), or [].
static func items(menu: Node) -> Array:
	return menu.items() if menu != null and menu.has_method("items") else []


## The offered item whose label contains `text` (case-insensitive), or {}.
static func item(menu: Node, text: String) -> Dictionary:
	for i in items(menu):
		if String(i.get("label", "")).to_lower().contains(text.to_lower()):
			return i
	return {}


## The labels of the offered items.
static func labels(menu: Node) -> Array:
	return items(menu).map(func(i): return String(i.get("label", "")))


## Choose the menu's item whose label contains `text` the way a click does: press the button that shows it (a `BaseButton`
## whose text it is), or the entry of a `PopupMenu` that shows it. False when no control shows it.
static func choose(menu: Node, text: String) -> bool:
	if menu == null:
		return false
	var wanted := text.to_lower()
	for node in menu.find_children("*", "BaseButton", true, false):
		var shown := String(node.get("text")).to_lower() if node.get("text") != null else ""
		if shown.contains(wanted) and not bool(node.get("disabled")):
			if node is CheckBox or node is CheckButton:
				node.button_pressed = not node.button_pressed
			node.pressed.emit()
			return true
	for popup: PopupMenu in menu.find_children("*", "PopupMenu", true, false):
		for i in popup.item_count:
			if popup.get_item_text(i).to_lower().contains(wanted) and not popup.is_item_disabled(i):
				popup.id_pressed.emit(popup.get_item_id(i))
				popup.index_pressed.emit(i)
				return true
	return false


## Tick (or untick) the teammate named `name` in the menu's list: the `CheckBox` whose text is that name.
static func tick(menu: Node, name: String, on: bool) -> bool:
	if menu == null:
		return false
	for box: BaseButton in menu.find_children("*", "BaseButton", true, false):
		if (box is CheckBox or box is CheckButton) and String(box.text) == name:
			if box.button_pressed != on:
				box.button_pressed = on
				box.toggled.emit(on)
			return true
	return false


## Where world point `p` is on the screen of the test world's viewport (what a click there sends).
static func screen_of(t: TestContext, p: Vector2) -> Vector2:
	return t.world.get_viewport().get_canvas_transform() * p


## Click mouse button `button` at world point `p` (a motion there first, so the pointer is where the click is), as the test's own input.
static func click(t: TestContext, p: Vector2, button: MouseButton) -> void:
	var at := screen_of(t, p)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	TestContext.inject(motion)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		TestContext.inject(ev)


# --- Stack orders at the Terrace house's back door (LD9) ---------------------------------------------------------------
# The back door (`Entry.BACK`: `door_840_190`, 90 px wide, in the kitchen's east wall) and where a leader's click on it lands (D3): the
# side of the wall plane clicked is the side the stack forms on; left or right of the opening along the wall picks the stack's side of
# the door; a click on the opening (within its half-width along the wall) is a split stack; an exterior door always goes into the house.

## Outside (the back garden), along the wall north of the opening: a stack north of the door, into the kitchen.
const BACK_NORTH := Vector2(870, 125)
## Outside, along the wall south of the opening: a stack south of the door, into the kitchen.
const BACK_SOUTH := Vector2(870, 255)
## Outside, on the opening: a split stack, into the kitchen.
const BACK_ON := Vector2(870, 190)
## Inside the kitchen, north of the opening: an exterior door still goes into the house's room.
const BACK_INSIDE_NORTH := Vector2(810, 125)
## The back door's centre y and half-width: north of the door is y < 190 - 45, south y > 190 + 45.
const BACK_Y := 190.0
const BACK_HALF := 45.0


## The squad of invader actors `ids` led by the puppet actor `lead` (a stand-in for the human leader), built as Main builds it.
static func raid(t: TestContext, ids: Array, lead: StringName) -> Node:
	var members: Array = [t.actor(lead)]
	for id in ids:
		members.append(t.actor(id))
	return squad(t, &"invader", members, t.actor(lead))


## Which side of the back door point `p` lies on along its wall: `north`, `south`, or `door` (within the opening's width).
static func back_side(p: Vector2) -> String:
	if p.y < BACK_Y - BACK_HALF:
		return "north"
	if p.y > BACK_Y + BACK_HALF:
		return "south"
	return "door"


## Where actor `id`'s running entry has it stand in the stack (`debug_entry()["stack_point"]`), or INF.
static func stack_point(t: TestContext, id: StringName) -> Vector2:
	var e: Dictionary = brain(t, id).debug_entry()
	var p = e.get("stack_point", Vector2.INF)
	return p if p is Vector2 else Vector2.INF


## Whether actor `id` is in its stack slot (its entry's phase is past the approach: `stack` or later).
static func stacked(t: TestContext, id: StringName) -> bool:
	var phase := String(brain(t, id).debug_entry().get("phase", ""))
	return phase != "" and phase != "approach"
