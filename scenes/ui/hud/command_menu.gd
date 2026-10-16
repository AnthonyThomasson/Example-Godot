extends CanvasLayer

## UI domain: the command menu (`docs/leadership.md` LD11), how the human leader orders its teammates. Main builds it only when the
## human leads its side ("Lead the team" in the setup window). A right-click (`Keybinds.COMMAND`) pauses the whole tree and opens the
## menu on what is under the cursor:
## - a teammate within `PICK_RADIUS`: "Select <name>" / "Deselect <name>" (the menu stays open);
## - else a doorway the squad resolves a stack at the click to (its `resolve` callable: the doorway nearest the click within its width):
##   "Stack into the <room> (quiet)" and "Stack into the <room> with stun", `<room>` the room that stack goes into (the squad's `into`,
##   named from the plain room dicts it was set up with), so the label names the room of the order; the stun item is greyed while no
##   recipient carries a stun (`Character.item_count(ItemRegistry.STUN_SLOT)`, D1);
## - else a room: "Defend the <room>";
## - and "Cancel order" while a recipient holds an order (the squad's `view()`).
## The panel also lists the teammates to tick. The recipients are the selection (ticked, or picked by a left-click on a teammate's body
## while the menu is open), or every living teammate when nothing is selected; never the human. The selection lasts until it is
## changed, and a dead teammate leaves it. Choosing an order emits `order_requested` and closes the menu; Escape closes it too (consumed
## in `_input`, so Main's MENU never sees it); closing unpauses the tree. Space stays the player's INTERACT.
##
## The panel is docked at the left of the screen, so it never covers the teammates and doorways it is about; a ring marks the clicked
## point. A decoupled observer: it reads its teammates through the Character API only (`global_position`, `name`, `is_dead`,
## `item_count`) and the squad through its `view()` and `resolve()` callables, emits plain requests and works out no AI id: the squad
## (interface 21) resolves the click into its doorway, side and room. `PROCESS_MODE_ALWAYS`, so it works while the tree is paused.

## Emitted when an order is chosen: `{ kind: "stack", to, pos, bang }` (`pos` the click itself), `{ kind: "defend_room", to, room }` (a
## room key) or `{ kind: "cancel", to }` (the recipients holding an order). `to` is the recipients (characters). Main hands it to the
## squad's `issue`.
signal order_requested(request: Dictionary)
## Emitted when the highlighted selection changes: the selected teammates while the menu is open, [] once it closes (the order
## markers' `set_selection`).
signal selection_changed(nodes: Array)

## World-space radius (px) around the cursor within which a click picks a teammate's body.
const PICK_RADIUS := 28.0
## The panel's place on screen (docked at the left, below the match HUD's timer) and its least width.
const PANEL_LEFT := 24.0
const PANEL_TOP := 120.0
const PANEL_WIDTH := 440.0
const TITLE_FONT := 28
const ITEM_FONT := 26
const LIST_FONT := 22
const HINT_FONT := 18
## The ring on the clicked point: its radius (screen px) and colour.
const MARK_RADIUS := 14.0
const MARK_COLOR := Color(1.0, 0.85, 0.3, 0.95)

var _rooms: Array = []        ## The house's rooms (`WorldGen.get_rooms`: `{ key, type, rect }`).
var _teammates: Array = []    ## The characters the human may order (its squad without itself), in squad order.
var _view: Callable           ## The squad's `view()`: `{ leader, members: [{ node, order, step }] }`.
var _resolve: Callable        ## The squad's `resolve(request)`: what a stack at a click names (`{ opening, pos, into, ... }`, or {}).
var _leader: Node = null      ## The human: the menu opens only while the view names it the leader (null: no such check).
var _selection: Array = []    ## The selected teammates.
var _open := false            ## Whether the menu is open.
var _paused_tree := false     ## Whether opening the menu paused the tree (closing then unpauses it).
var _click := Vector2.ZERO    ## The world point the menu is open on.
var _items: Array = []        ## What is offered now: `{ label, disabled, act: Callable }`.

var _panel: PanelContainer    ## The panel docked at the left, holding everything below.
var _title: Label             ## Names what the menu is open on.
var _recipients: Label        ## "Orders go to: ...".
var _item_box: VBoxContainer  ## The offered items' buttons.
var _list_box: VBoxContainer  ## The teammates' CheckBoxes.
var _checks := {}             ## Teammate instance id -> its CheckBox in the list.
var _mark: Control            ## Full-screen, mouse-ignoring: draws the ring on the clicked point.


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 40


## Set the menu up: `{ rooms, teammates, view, resolve, leader? }`, `rooms` the house's (plain dicts), `teammates` the characters it
## may order, `view` and `resolve` the squad's `view()` and `resolve(request)` callables (with no `resolve` no doorway is offered) and
## `leader` the human (the menu then opens only while it leads). Called by Main once the squads are built.
func setup(config: Dictionary) -> void:
	_rooms = config.get("rooms", [])
	_teammates = (config.get("teammates", []) as Array).filter(func(n): return n is Node)
	var view = config.get("view")
	_view = view if view is Callable else Callable()
	var resolve = config.get("resolve")
	_resolve = resolve if resolve is Callable else Callable()
	_leader = config.get("leader") as Node
	_build()


## Pause the tree and open the menu on world point `at`: the items for what lies there.
func open_at(at: Vector2) -> void:
	if not _may_open():
		return
	_click = at
	if not _open:
		_open = true
		_paused_tree = not get_tree().paused
		get_tree().paused = true
		_panel.visible = true
	_drop_dead()
	_refresh()
	selection_changed.emit(_selection.duplicate())


## Close the menu (no order) and unpause the tree if opening it paused it.
func close() -> void:
	if not _open:
		return
	_open = false
	_panel.visible = false
	_set_items([])
	_mark.queue_redraw()
	if _paused_tree and is_inside_tree():
		get_tree().paused = false
	_paused_tree = false
	selection_changed.emit([])


## Whether the menu is open.
func is_open() -> bool:
	return _open


## What the menu offers now, `[{ label, disabled }]` in display order; [] while it is closed.
func items() -> Array:
	return _items.map(func(i): return { "label": i["label"], "disabled": i["disabled"] })


func _exit_tree() -> void:
	if _open and _paused_tree:
		get_tree().paused = false  # A menu freed while open (the match torn down) never leaves the game paused.


## Escape closes the open menu; consumed here, before Main's `_unhandled_input` would read it as MENU.
func _input(event: InputEvent) -> void:
	if _open and event.is_action_pressed(Keybinds.MENU) and not event.is_echo():
		close()
		get_viewport().set_input_as_handled()


## COMMAND (a right-click by default) opens the menu on the point under the cursor; while it is open, a left-click on a teammate's
## body toggles it in the selection. Clicks on the panel never get here (it takes them first).
func _unhandled_input(event: InputEvent) -> void:
	var screen: Vector2 = event.position if event is InputEventMouse else get_viewport().get_mouse_position()
	if event.is_action_pressed(Keybinds.COMMAND) and not event.is_echo():
		if _may_open():
			open_at(_world_of(screen))
			get_viewport().set_input_as_handled()
	elif _open and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mate := _teammate_at(_world_of(screen))
		if mate != null:
			_toggle(mate, not _selection.has(mate))
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _open:
		_mark.queue_redraw()  # The camera may still zoom while paused: keep the ring on the clicked point.


# --- What lies under the click ----------------------------------------------------------------------------------

## Rebuild the panel for the point the menu is open on: its title, the recipients line and the items.
func _refresh() -> void:
	var offered: Array = []
	var mate := _teammate_at(_click)
	var door := {} if mate != null else _stack_at(_click)
	if mate != null:
		_title.text = String(mate.name)
		var picked := _selection.has(mate)
		offered.append(_item("%s %s" % ["Deselect" if picked else "Select", mate.name], false, _toggle.bind(mate, not picked)))
	elif not door.is_empty():
		var into := _room_name(_room_by_key(String(door.get("into", ""))))
		_title.text = "Doorway into the %s" % into
		offered.append(_item("Stack into the %s (quiet)" % into, false, _order.bind({ "kind": "stack", "pos": _click, "bang": false })))
		offered.append(_item("Stack into the %s with stun" % into, not _recipients_carry_stun(),
			_order.bind({ "kind": "stack", "pos": _click, "bang": true })))
	else:
		var room := _room_at(_click)
		_title.text = "The %s" % _room_name(room) if not room.is_empty() else "Outside"
		if not room.is_empty():
			offered.append(_item("Defend the %s" % _room_name(room), false, _order.bind({ "kind": "defend_room", "room": String(room["key"]) })))
	if not _ordered_recipients().is_empty():
		offered.append(_item("Cancel order", false, _cancel))
	_recipients.text = "Orders go to: %s" % (", ".join(_selection.map(func(n): return String(n.name))) if not _selection.is_empty() else "the whole squad")
	_set_items(offered)
	_mark.queue_redraw()


## The living teammate nearest world point `at` within `PICK_RADIUS`, or null.
func _teammate_at(at: Vector2) -> Node:
	var best: Node = null
	var best_d := PICK_RADIUS
	for mate in _teammates:
		if not _alive(mate):
			continue
		var d: float = (mate.global_position as Vector2).distance_to(at)
		if d <= best_d:
			best_d = d
			best = mate
	return best


## What a stack ordered at world point `at` names, as the squad resolves it (`{ opening, pos, into, ... }`), or {} for no doorway there.
func _stack_at(at: Vector2) -> Dictionary:
	var out = _resolve.call({ "kind": "stack", "pos": at }) if _resolve.is_valid() else {}
	return out if out is Dictionary else {}


## The room whose rect holds world point `at`, or {}.
func _room_at(at: Vector2) -> Dictionary:
	for r: Dictionary in _rooms:
		if (r["rect"] as Rect2).has_point(at):
			return r
	return {}


## Room `key`'s dict, or {}.
func _room_by_key(key: String) -> Dictionary:
	for r: Dictionary in _rooms:
		if String(r["key"]) == key:
			return r
	return {}


## A room as the menu names it: its type, words apart ("living_room" -> "living room").
func _room_name(room: Dictionary) -> String:
	return String(room.get("type", room.get("key", "room"))).replace("_", " ") if not room.is_empty() else "room"


# --- Recipients and orders ----------------------------------------------------------------------------------------

## Who an order goes to: the selection, or every living teammate when nothing is selected.
func _recipients_now() -> Array:
	return _selection.duplicate() if not _selection.is_empty() else _teammates.filter(_alive)


## Whether any recipient carries a stun grenade (D1: the stun stack is offered only then).
func _recipients_carry_stun() -> bool:
	return _recipients_now().any(func(n): return n.has_method("item_count") and int(n.item_count(ItemRegistry.STUN_SLOT)) > 0)


## The recipients that hold an order now (the squad's `view()`).
func _ordered_recipients() -> Array:
	var held: Array = []
	var view: Dictionary = _view.call() if _view.is_valid() else {}
	for row: Dictionary in view.get("members", []):
		if not (row.get("order", {}) as Dictionary).is_empty():
			held.append(row.get("node"))
	return _recipients_now().filter(func(n): return held.has(n))


## Emit `request` for the recipients now and close the menu.
func _order(request: Dictionary) -> void:
	var out := request.duplicate()
	out["to"] = _recipients_now()
	close()
	order_requested.emit(out)


## Cancel the recipients' orders and close the menu.
func _cancel() -> void:
	var to := _ordered_recipients()
	close()
	order_requested.emit({ "kind": "cancel", "to": to })


## Put `mate` in the selection (`on`) or take it out, tick its box to match, and redraw an open menu.
func _toggle(mate: Node, on: bool) -> void:
	if on and _alive(mate) and not _selection.has(mate):
		_selection.append(mate)
	elif not on:
		_selection.erase(mate)
	var box: CheckBox = _checks.get(mate.get_instance_id())
	if box != null and box.button_pressed != _selection.has(mate):
		box.set_pressed_no_signal(_selection.has(mate))
	if _open:
		_refresh()
		selection_changed.emit(_selection.duplicate())


## A dead teammate leaves the selection and its box is disabled.
func _drop_dead() -> void:
	for mate in _teammates:
		var box: CheckBox = _checks.get(mate.get_instance_id()) if is_instance_valid(mate) else null
		if not _alive(mate):
			_selection.erase(mate)
			if box != null:
				box.set_pressed_no_signal(false)
				box.disabled = true


## Whether `n` is a living character.
func _alive(n) -> bool:
	return n is Node and is_instance_valid(n) and n.get("is_dead") != true


## Whether the menu may open: it was set up and, when it was given the human, the squad's view still names the human its leader.
func _may_open() -> bool:
	if _panel == null:
		return false
	if _leader == null:
		return true
	var view: Dictionary = _view.call() if _view.is_valid() else {}
	return is_instance_valid(_leader) and view.get("leader") == _leader


## World point under screen point `screen` (the world's canvas transform).
func _world_of(screen: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen


# --- The panel --------------------------------------------------------------------------------------------------

## One offered item: its label, whether it is greyed out, and what choosing it does.
func _item(label: String, disabled: bool, act: Callable) -> Dictionary:
	return { "label": label, "disabled": disabled, "act": act }


## Show `offered` as the panel's buttons, replacing the ones shown.
func _set_items(offered: Array) -> void:
	_items = offered
	for old in _item_box.get_children():
		_item_box.remove_child(old)
		old.queue_free()
	for i: Dictionary in offered:
		var button := Button.new()
		button.text = i["label"]
		button.disabled = i["disabled"]
		button.focus_mode = Control.FOCUS_NONE  # Space must never press it (it stays INTERACT)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", ITEM_FONT)
		if i["disabled"]:
			button.tooltip_text = "Nobody it would go to carries a stun grenade."
		button.pressed.connect(i["act"])
		_item_box.add_child(button)


## Build the hidden panel (title, recipients, items, the teammate list, the hint) and the ring layer.
func _build() -> void:
	if _panel != null:
		return
	_mark = Control.new()
	_mark.name = "ClickMark"
	_mark.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mark.draw.connect(_draw_mark)
	add_child(_mark)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.position = Vector2(PANEL_LEFT, PANEL_TOP)
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP  # a click on the panel never reaches the world
	_panel.visible = false
	add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	_title = _label(box, TITLE_FONT)
	_recipients = _label(box, LIST_FONT)
	_recipients.modulate = Color(1, 1, 1, 0.75)
	_item_box = VBoxContainer.new()
	_item_box.add_theme_constant_override("separation", 4)
	box.add_child(_item_box)
	box.add_child(HSeparator.new())
	var heading := _label(box, LIST_FONT)
	heading.text = "Teammates"
	_list_box = VBoxContainer.new()
	box.add_child(_list_box)
	for mate: Node in _teammates:
		var check := CheckBox.new()
		check.text = String(mate.name)
		check.focus_mode = Control.FOCUS_NONE
		check.add_theme_font_size_override("font_size", LIST_FONT)
		check.toggled.connect(func(on: bool): _toggle(mate, on))
		_list_box.add_child(check)
		_checks[mate.get_instance_id()] = check
	var hint := _label(box, HINT_FONT)
	hint.text = "Click a teammate to select it · Esc closes"
	hint.modulate = Color(1, 1, 1, 0.6)


## A new Label at font size `size`, added under `parent`.
func _label(parent: Control, size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
	return label


## The ring on the clicked point, while the menu is open.
func _draw_mark() -> void:
	if not _open:
		return
	var at := get_viewport().get_canvas_transform() * _click
	_mark.draw_arc(at, MARK_RADIUS, 0.0, TAU, 24, MARK_COLOR, 3.0)
	_mark.draw_circle(at, 3.0, MARK_COLOR)
