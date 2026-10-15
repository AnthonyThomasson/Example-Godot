class_name TestSetup extends RefCounted

## Testing domain: what a test asks for, filled in by `GameTest.configure()`. Pure data — it builds
## nothing; test_world.gd turns it into a live scene. Positions are world-space.

## When non-zero, every `house()` uses this seed instead of its own (the runner's `--seed=N`).
static var seed_override := 0

## The world: `{ kind: "arena", rect, floor, walls, thickness }` or `{ kind: "house", seed, plan,
## entrance }`. Empty = an empty arena (see `resolved_world`).
var world: Dictionary = {}
## Objects to place: `{ id, definition, position, opts }` (definition already resolved to a dict).
var objects: Array = []
## Vehicles to place: `{ id, kind, position, rotation, props }` (see `vehicle`).
var vehicles: Array = []
## Characters to place: `{ id, kind, position, props, children }` — `props` set on the character,
## `children` maps a child node path to props set on that child, all before it enters the tree.
var actors: Array = []
## Behaviour switches (test_switches.gd rows) by name → on.
var switches: Dictionary = {}
## Static-var overrides `[script, prop, value]`, restored after the test.
var statics: Array = []
## Actor ids the camera keeps framed; empty = every actor.
var camera_targets: Array = []
## Debug overlay flags (overlay_registry.gd `show_<x>` names) to turn on for every actor; the rest
## start off. Toggle them live with the in-game overlay bar in an interactive run.
var overlays: Array = []
## Interactions a person could use in a headed run that would change this test's result, which the runner
## switches off (see `lock_interaction`).
var locked: Array = []
## What `lock_interaction` knows: `camera` (the user's wheel / trackpad / camera-key events and the
## runner's own hand-pan), `pause` (the banner's Pause button and Space), `overlays` (the overlay bar).
const LOCKABLE := [&"camera", &"pause", &"overlays"]


## A walled single-room arena covering `rect`. `opts`: `floor` (a catalogue floor key, default
## "oak_planks"), `walls` (default true), `thickness` (default 12).
func arena(rect: Rect2, opts: Dictionary = {}) -> TestSetup:
	world = {
		"kind": "arena", "rect": rect,
		"floor": opts.get("floor", "oak_planks"),
		"walls": opts.get("walls", true),
		"thickness": opts.get("thickness", 12.0),
	}
	return self


## A hand-laid building: `rooms` is `[{ key, type, rect, floor? }]` (world-space rects; walls run along
## their edges, `floor` is a catalogue floor key, default "oak_planks") and `doors` is `[{ pos, width }]`,
## each `pos` a point on a wall's centerline (on a wall two rooms share it is an interior doorway, on an
## outer edge an entrance). Walls are the house's own, so the nav bake carves them and leaves the doorways
## open. `opts`: `thickness` (default 12).
func layout(room_list: Array, doors: Array = [], opts: Dictionary = {}) -> TestSetup:
	world = { "kind": "layout", "rooms": room_list, "doors": doors, "thickness": opts.get("thickness", 12.0) }
	return self


## A generated house from `seed` (pinned, never random) and an optional floorplan key; its front
## entrance lands at `entrance`.
func house(house_seed: int, plan: String = "", entrance := Vector2.ZERO) -> TestSetup:
	world = { "kind": "house", "seed": seed_override if seed_override != 0 else house_seed, "plan": plan, "entrance": entrance }
	return self


## Place an object `id` at `position`. `definition` is a catalogue key (WorldGen.object_definition) or
## a full definition dict; `opts` are ObjectFactory's (rotated, color, facing).
func object(id: StringName, definition: Variant, position: Vector2, opts: Dictionary = {}) -> TestSetup:
	var def: Dictionary = definition if definition is Dictionary else WorldGen.object_definition(String(definition))
	if def.is_empty():
		push_error("TestSetup: unknown object definition '%s'" % [definition])
	objects.append({ "id": id, "definition": def, "position": position, "opts": opts })
	return self


## Place a drivable vehicle `id` of `kind` (`car`, `van`: the scene `res://scenes/vehicle/<kind>.tscn`) at `position`,
## turned by `rotation` (rad; 0 = its front toward +x, its left side toward -y). `props` are set on it before it enters
## the tree. It goes under the world root after the nav bake, so it is not carved (the AI ignores vehicles). A kind
## with no scene places nothing: `t.vehicle(id)` is then null.
func vehicle(id: StringName, kind: StringName, position: Vector2, rotation := 0.0, props: Dictionary = {}) -> TestSetup:
	vehicles.append({ "id": id, "kind": kind, "position": position, "rotation": rotation, "props": props })
	return self


## Place a character `id` at `position`. `kind`: `puppet` (scripted), `player` (human-driven),
## `defender` / `invader` (the AI presets) or a scene path. `props` are set on the character before it
## enters the tree (e.g. `max_health`, `start_slot`, `faction`).
func actor(id: StringName, kind: StringName, position: Vector2, props: Dictionary = {}) -> TestSetup:
	actors.append({ "id": id, "kind": kind, "position": position, "props": props, "children": {} })
	return self


## Set `props` on child `child_path` of actor `id` before it enters the tree (e.g. an NPC's
## "GoalController" exports). Merges with earlier calls.
func set_props(id: StringName, child_path: String, props: Dictionary) -> TestSetup:
	for a in actors:
		if a["id"] == id:
			var children: Dictionary = a["children"]
			var existing: Dictionary = children.get(child_path, {})
			existing.merge(props, true)
			children[child_path] = existing
			return self
	push_error("TestSetup.set_props: no actor '%s' (declare it with actor() first)" % id)
	return self


## Turn a named behaviour on or off (see test_switches.gd for the names).
func switch(name: StringName, on: bool) -> TestSetup:
	switches[name] = on
	return self


## Override a `static var` on a config holder (e.g. `PhysicsConfig`, "impact_impulse") for this test;
## the original value is restored afterwards.
func set_static(script: Script, prop: StringName, value: Variant) -> TestSetup:
	statics.append([script, prop, value])
	return self


## Replace the Von server with scripted picks for this test: `rules` is DecisionStub's ordered list of
## `{ pick: id, question: substring (optional) }` (first rule whose id is offered wins; otherwise the
## first offered option). AI tests that use it need no server and are deterministic. `latency_frames` holds each
## answer back that many physics frames, to test what an NPC does while a decision is in flight.
func von_script(rules: Array, latency_frames := 0) -> TestSetup:
	statics.append([DecisionStub, &"active", true])
	statics.append([DecisionStub, &"rules", rules])
	statics.append([DecisionStub, &"requests", []])
	statics.append([DecisionStub, &"latency_frames", latency_frames])
	return self


## Like `von_script`, but every decision fails, as with the server down (NPCs hold steady).
func von_down() -> TestSetup:
	von_script([])
	statics.append([DecisionStub, &"fail", true])
	return self


## Start these debug overlays on (e.g. `["show_vision", "show_actions"]`).
func show_overlays(flags: Array) -> TestSetup:
	overlays = flags
	return self


## Switch off the listed user interactions while this test runs in the in-game runner, because a person
## using them would change the result (a camera test must not be zoomed by the user's own wheel). Events the
## test sends itself through `TestContext.inject` still get through; keys held down are polled state and
## cannot be told apart, so a person should not hold a camera key during a camera test.
func lock_interaction(what: Array) -> TestSetup:
	for name in what:
		if not LOCKABLE.has(name):
			push_error("TestSetup: unknown interaction '%s' (known: %s)" % [name, LOCKABLE])
	locked = what
	return self


## Keep these actor ids framed by the camera (default: every actor).
func camera_follow(ids: Array) -> TestSetup:
	camera_targets = ids
	return self


## The world to build: the declared one, or an 800×500 arena when none was declared.
func resolved_world() -> Dictionary:
	if world.is_empty():
		return { "kind": "arena", "rect": Rect2(0, 0, 800, 500), "floor": "oak_planks", "walls": true, "thickness": 12.0 }
	return world
