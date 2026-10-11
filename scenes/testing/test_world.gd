extends Node2D

## Testing domain: one test's live world, built from a TestSetup through the published interfaces
## only (WorldGen, the Objects factories, NavBuilder, the character scenes + controller contract) —
## the same way main.gd composes a match. Freed between tests; `restore()` undoes the static-var
## overrides, which outlive the scene.

const ArenaBuilder = preload("res://scenes/testing/arena_builder.gd")
const TestSwitches = preload("res://scenes/testing/test_switches.gd")
const ScriptedController = preload("res://scenes/testing/scripted_controller.gd")
const PlayerController = preload("res://scenes/character/player_controller.gd")
const NAV_UPDATER := preload("res://scenes/navigation/nav_updater.gd")
const NAV_DEBUG := preload("res://scenes/navigation/nav_debug.gd")
const OVERLAY_REGISTRY := preload("res://scenes/ui/overlay_registry.gd")
const ACTOR_SCENES := {
	&"puppet": "res://scenes/character/character_base.tscn",
	&"player": "res://scenes/character/character_base.tscn",
	&"defender": "res://scenes/character/npc_defender.tscn",
	&"invader": "res://scenes/character/npc_invader.tscn",
}

## The house or arena root, its rooms, and the placed actors/objects by id.
var house: Node2D
var rooms: Array = []
var actors: Dictionary = {}
var objects: Dictionary = {}

## Original values of overridden statics: `[script, prop, value]`.
var _saved_statics: Array = []
var _overlay_flags: Dictionary = {}
## The navmesh-holes overlay (the "Nav holes" toggle), kept in step with re-bakes by the updater.
var _nav_debug: Node2D = null


## Build everything `setup` declares. Statics and switches are applied before anything spawns, so
## spawning already sees them.
func build(setup: TestSetup) -> void:
	for switch_name in setup.switches:
		if not TestSwitches.has(switch_name):
			push_error("TestWorld: unknown switch '%s'" % switch_name)
	_apply_statics(setup)
	_build_world(setup.resolved_world())
	# Objects go under the house/arena root (like furnished pieces) so the nav bake carves them.
	for o in setup.objects:
		var opts: Dictionary = o["opts"].duplicate()
		opts["name"] = String(o["id"])
		objects[o["id"]] = ObjectFactory.spawn(o["definition"], house.to_local(o["position"]), house, opts)
	_overlay_flags = {}
	for flag in OVERLAY_REGISTRY.defaults():
		_overlay_flags[flag] = setup.overlays.has(flag)
	_build_nav()
	for a in setup.actors:
		actors[a["id"]] = _spawn_actor(a, setup.switches)
	_apply_world_switches(setup.switches)


## Undo every static override (call after freeing the world, or before rebuilding).
func restore() -> void:
	for i in range(_saved_statics.size() - 1, -1, -1):
		var s: Array = _saved_statics[i]
		(s[0] as Script).set(s[1], s[2])
	_saved_statics.clear()


## The current per-NPC overlay flags (for the in-game toggle bar).
func overlay_flags() -> Dictionary:
	return _overlay_flags.duplicate()


## Turn one per-NPC debug overlay on/off on every actor (duck-typed by property, like main.gd).
## The global flags: the navmesh holes live here; the performance panel belongs to the runner.
## A redraw is forced because a paused overlay's own `_process` may not run.
func set_overlay(flag: String, on: bool) -> void:
	_overlay_flags[flag] = on
	if flag == OVERLAY_REGISTRY.NAV_HOLES:
		if is_instance_valid(_nav_debug):
			_nav_debug.show_holes = on
			_nav_debug.queue_redraw()
		return
	for id in actors:
		var a: Node = actors[id]
		if is_instance_valid(a):
			for child in a.get_children():
				if flag in child:
					child.set(flag, on)
					child.queue_redraw()


## Apply the switch rows' static knobs, then the explicit `set_static` overrides.
func _apply_statics(setup: TestSetup) -> void:
	for switch_name in setup.switches:
		var on: bool = setup.switches[switch_name]
		for knob in TestSwitches.row(switch_name).get("static", []):
			if knob.size() < 3:
				_set_static(knob[0], knob[1], on)
			elif not on:
				_set_static(knob[0], knob[1], knob[2])
	for s in setup.statics:
		_set_static(s[0], s[1], s[2])


## Set a static var, remembering its value for `restore()`.
func _set_static(script: Script, prop: StringName, value: Variant) -> void:
	_saved_statics.append([script, prop, script.get(prop)])
	script.set(prop, value)


## Build the generated house or the arena, and read its rooms.
func _build_world(world: Dictionary) -> void:
	if world["kind"] == "house":
		house = WorldGen.generate(int(world["seed"]), String(world.get("plan", "")), world.get("entrance", Vector2.ZERO), self)
	else:
		house = ArenaBuilder.build(world, self)
	rooms = WorldGen.get_rooms(house)


## Bake the nav map (after the objects, so they are carved) and add the re-baker.
func _build_nav() -> void:
	var region := NavBuilder.build(house, rooms, self)
	_nav_debug = NAV_DEBUG.new()
	_nav_debug.name = "NavDebug"
	add_child(_nav_debug)
	_nav_debug.setup(house)
	_nav_debug.show_holes = _overlay_flags.get(OVERLAY_REGISTRY.NAV_HOLES, false)
	var updater: Node = NAV_UPDATER.new()
	updater.name = "NavUpdater"
	add_child(updater)
	updater.setup(region, house, rooms, _nav_debug)


## Instance actor `a`, inject its controller and props/switches/overlays, then add it to the world.
func _spawn_actor(a: Dictionary, switches: Dictionary) -> Node:
	var kind: StringName = a["kind"]
	var path: String = ACTOR_SCENES.get(kind, String(kind))
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("TestWorld: actor '%s' has unknown kind/scene '%s'" % [a["id"], kind])
		return null
	var character := scene.instantiate()
	character.name = String(a["id"])
	if kind == &"puppet":
		var puppet: Node = ScriptedController.new()
		puppet.name = "ScriptedController"
		character.add_child(puppet)
	elif kind == &"player":
		var human: Node = PlayerController.new()
		human.name = "PlayerController"
		character.add_child(human)
	var props: Dictionary = a["props"]
	for prop in props:
		character.set(prop, props[prop])
	for switch_name in switches:
		var row: Dictionary = TestSwitches.row(switch_name).get("actor", {})
		if row.is_empty():
			continue
		var target: Node = character if row["child"] == "" else character.get_node_or_null(row["child"])
		if target != null:
			for prop in row["props"]:
				target.set(prop, switches[switch_name])
	var children: Dictionary = a["children"]
	for child_path in children:
		var child := character.get_node_or_null(child_path)
		if child == null:
			push_error("TestWorld: actor '%s' has no child '%s'" % [a["id"], child_path])
			continue
		for prop in children[child_path]:
			child.set(prop, children[child_path][prop])
	for child in character.get_children():
		for flag in _overlay_flags:
			if flag in child:
				child.set(flag, _overlay_flags[flag])
		# The AI learns the house's rooms from its composer (main.gd does the same).
		if child.has_method("control") and "rooms" in child:
			child.rooms = rooms
	add_child(character)
	character.global_position = a["position"]
	return character


## Apply the switch rows that target a node of the built world.
func _apply_world_switches(switches: Dictionary) -> void:
	for switch_name in switches:
		var row: Dictionary = TestSwitches.row(switch_name).get("world", {})
		if row.is_empty():
			continue
		var node := get_node_or_null(row["node"])
		if node != null:
			for prop in row["props"]:
				node.set(prop, switches[switch_name])
