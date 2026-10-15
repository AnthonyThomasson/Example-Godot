extends RefCounted

## Shared helpers for the grenade tests (not a test itself): `const Probe := preload("res://tests/_ai/grenade_probe.gd")`.
## The behaviour they assert is `docs/grenades.md` (G1 to G19).
##
## Every grenade API is reached duck-typed (`has_method`, `call`, groups, EventBus topics), so a test loads and runs
## before the feature exists and goes red on an assertion that names what is missing, never on a parse error.
## What they read: `Character.item_count(slot)`, the `live_grenades` group, and the EventBus topics `throw`, `grenade`,
## `explosion`, `stun` and `hit` (outcome `blast`).

const STUN := 7
const FRAG := 8
const PISTOL := 3
## The throw range cap (G2, `max_range`), the blast radius (G7) and the stun's flash / bang radii (G11, G12).
const MAX_RANGE := 450.0
const BLAST_RADIUS := 250.0
const KILL_RADIUS := 120.0
const BLAST_DAMAGE := 60.0
const FLASH_RADIUS := 400.0
const FLASH_FULL := 100.0
const MAX_BLIND := 5.0
const BANG_RADIUS := 350.0
const MAX_DEAF := 6.0
const WALL_FACTOR := 0.4
## G16: how far past the blast radius a frag's danger zone reaches (`evade_margin`) and how far off a landing is heard
## (`hear_grenade`).
const EVADE_MARGIN := 120.0
const FRAG_ZONE := BLAST_RADIUS + EVADE_MARGIN
const HEAR_GRENADE := 300.0
const FUSE_FRAG := 3.0
const FUSE_STUN := 1.5
const WINDUP := 0.3


# --- Arming and reading a character -------------------------------------------------------------------

## Arm `c` the way a match does (`LoadoutConfig.apply`): the gun `weapon`, `stuns` stun grenades (slot 7) and `frags` frag
## grenades (slot 8). Call it at the start of `run`: tests keep the default inventory (no grenades) until they arm.
static func arm(c: Node, stun_count := 0, frag_count := 0, weapon := &"pistol") -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	LoadoutConfig.apply(c, { "weapon": weapon, "stuns": stun_count, "frags": frag_count }, rng)


## How many grenades `c` carries in `slot`; -1 when the Character has no `item_count` yet.
static func count(c: Node, slot: int) -> int:
	return int(c.call("item_count", slot)) if c.has_method("item_count") else -1


## `c.is_blind()` / `is_deaf()` / `stun_level()`; false / 0.0 while the Character lacks them.
static func blind(c: Node) -> bool:
	return bool(c.call("is_blind")) if c.has_method("is_blind") else false


static func deaf(c: Node) -> bool:
	return bool(c.call("is_deaf")) if c.has_method("is_deaf") else false


static func level(c: Node) -> float:
	return float(c.call("stun_level")) if c.has_method("stun_level") else 0.0


## `c.stun_view()` (seconds left blind / deaf, the burst's blind time, the level 0..1); {} while it does not exist.
static func view(c: Node) -> Dictionary:
	return c.call("stun_view") if c.has_method("stun_view") else {}


## Stun `c` as a burst at `from` would (`Character.take_stun(blind, deaf, from)`); false while it does not exist.
static func stun(c: Node, blind_s: float, deaf_s: float, from: Vector2) -> bool:
	if not c.has_method("take_stun"):
		return false
	c.call("take_stun", blind_s, deaf_s, from)
	return true


# --- Throwing -----------------------------------------------------------------------------------

## Select `slot` on puppet `who`, face `point` and give the facing time to settle. Does not throw.
static func ready(t: TestContext, who: StringName, slot: int, point: Vector2) -> void:
	var p := t.puppet(who)
	p.select_slot(slot)
	p.aim_at(point)
	await t.seconds(0.4)


## `ready` and then one click of the trigger: the throw starts (the grenade leaves 0.3 s later). Returns the sim time of the click.
static func throw_at(t: TestContext, who: StringName, slot: int, point: Vector2) -> float:
	await ready(t, who, slot, point)
	var at := t.time
	t.puppet(who).shoot()
	return at


## The nodes in the `live_grenades` group (each has `kind`, `fuse_left()`, `danger_radius()`, `thrower`).
static func live(t: TestContext) -> Array:
	return t.world.get_tree().get_nodes_in_group("live_grenades")


## The raw bus events (`{ topic, data, time }`, `time` in sim seconds) of `topic` passing `filter` on their data, oldest first.
## (`TestContext.events_of` gives the data dicts alone, without the time.)
static func raw(t: TestContext, topic: StringName, filter := Callable()) -> Array:
	var out: Array = []
	for e: Dictionary in t.events:
		if e["topic"] == topic and (not filter.is_valid() or filter.call(e["data"])):
			out.append(e)
	return out


## The `explosion` events (of `kind` when given), oldest first, as raw events: `data` is `{ position, kind, attacker, radius }`.
static func booms(t: TestContext, kind: StringName = &"") -> Array:
	return raw(t, &"explosion", func(d: Dictionary) -> bool: return kind == &"" or d.get("kind") == kind)


## Wait until `n` explosions (of `kind`) have happened; true on success. `timeout` is sim seconds.
static func wait_boom(t: TestContext, kind: StringName, timeout: float, n := 1) -> bool:
	return await t.until(func() -> bool: return booms(t, kind).size() >= n, timeout)


## Wait until the first grenade has come to rest (`grenade` event, stage `rest`); true on success.
static func wait_rest(t: TestContext, timeout: float) -> bool:
	return await t.until(func() -> bool: return t.happened(&"grenade", func(d: Dictionary) -> bool: return d.get("stage") == &"rest"), timeout)


## Where the first grenade came to rest.
static func rest_point(t: TestContext) -> Vector2:
	var rests := raw(t, &"grenade", func(d: Dictionary) -> bool: return d.get("stage") == &"rest")
	return rests[0]["data"]["position"] if not rests.is_empty() else Vector2.ZERO


## The `hit` events with outcome `blast` that struck `victim` (G7).
static func blast_hits(t: TestContext, victim: Node) -> Array:
	return raw(t, &"hit", func(d: Dictionary) -> bool: return d.get("victim") == victim and d.get("outcome") == &"blast")


## The `stun` events for `c`: `{ character, position, blind, deaf }`.
static func stuns(t: TestContext, c: Node) -> Array:
	return raw(t, &"stun", func(d: Dictionary) -> bool: return d.get("character") == c)


## Stand puppet `who` at `at`, facing `look`: a victim set up around a grenade that has come to rest, so its distance and facing
## are known exactly whatever the throw's scatter was.
static func place(t: TestContext, who: StringName, at: Vector2, look: Vector2) -> void:
	var c := t.actor(who)
	c.global_position = at
	c.velocity = Vector2.ZERO
	t.puppet(who).aim_at(look)


# --- The numbers of the spec, so a test checks the doc and not the code --------------------------------

## G7: blast damage at distance `d` from the blast point: full to `KILL_RADIUS`, linear to 0 at `BLAST_RADIUS`.
static func blast_damage(d: float) -> float:
	return BLAST_DAMAGE * clampf((BLAST_RADIUS - d) / (BLAST_RADIUS - KILL_RADIUS), 0.0, 1.0)


## G11: the flash's reach at distance `d` (1 inside `FLASH_FULL`, linear to 0 at `FLASH_RADIUS`).
static func flash_scale(d: float) -> float:
	return clampf((FLASH_RADIUS - d) / (FLASH_RADIUS - FLASH_FULL), 0.0, 1.0)


## G11: the facing factor from the dot of the victim's facing with the direction to the burst: 1 facing it, 0.6 side-on,
## 0.25 back to it, linear between those anchors.
static func facing_factor(dot: float) -> float:
	return lerpf(0.6, 1.0, dot) if dot >= 0.0 else lerpf(0.6, 0.25, -dot)


## G11: the blind time of a victim at `at` facing `facing`, in line of sight of a burst at `burst`.
static func expected_blind(at: Vector2, facing: Vector2, burst: Vector2) -> float:
	var to_burst := burst - at
	var dot := facing.normalized().dot(to_burst.normalized()) if to_burst.length() > 0.5 else 1.0
	return MAX_BLIND * flash_scale(to_burst.length()) * facing_factor(dot)


## G12: the deaf time of a victim `d` from the burst (linear from `MAX_DEAF` at 0 to nothing at `BANG_RADIUS`), times `factor`
## (`WALL_FACTOR` through a wall).
static func expected_deaf(d: float, factor := 1.0) -> float:
	return MAX_DEAF * clampf(1.0 - d / BANG_RADIUS, 0.0, 1.0) * factor


## The `sound` categories the grenades add, merged into the audio tests' "nothing is out of earshot" range table.
static func everywhere(base: Dictionary) -> Dictionary:
	var out := base.duplicate()
	for kind in [&"throw", &"grenade", &"explosion", &"tinnitus"]:
		out[kind] = 1.0e9
	return out


# --- AI: reading an NPC, setting a scene -----------------------------------------------------------------

## The tactic level's offered option ids of the NPC `brain` (the controller) from its last decision walk: the last `combat`
## level (the first one picks the hostile).
static func offered(brain: Node) -> Array:
	var found: Array = []
	for l in brain.debug_state().get("decision", {}).get("levels", []):
		if l["node"] == "combat":
			found = (l.get("offered", {}) as Dictionary).keys()
	return found


## The callouts (EventBus `callout`) with `status`, optionally only those spoken by actor `who`.
static func callouts(t: TestContext, status: StringName, who: StringName = &"") -> Array:
	var speaker := t.actor(who) if who != &"" else null
	return raw(t, &"callout", func(d: Dictionary) -> bool:
		return d.get("status") == status and (speaker == null or d.get("speaker") == speaker))


## What the NPC's grenade awareness reports (`GoalController.debug_grenades()`: `known`, `escape`, `throw`); {} while it
## does not exist.
static func grenades(brain: Node) -> Dictionary:
	return brain.call("debug_grenades") if brain.has_method("debug_grenades") else {}


## True when nothing solid (a wall or a tall piece, not a character) lies on the straight line from `a` to `b`.
static func line_clear(t: TestContext, a: Vector2, b: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(a, b, PhysicsLayers.SOLID)
	var bodies: Array = []
	for c in t.world.find_children("*", "CharacterBody2D", true, false):
		bodies.append((c as CharacterBody2D).get_rid())
	query.exclude = bodies
	return t.world.get_world_2d().direct_space_state.intersect_ray(query).is_empty()


## An unkillable household puppet standing at `pos` looking at `look_at`: the hostile of a scene (it never shoots).
static func hostile(s: TestSetup, id: StringName, pos: Vector2, look_at: Vector2, props: Dictionary = {}) -> void:
	var p := { "faction": &"household", "max_health": 1000000.0, "aim_point": look_at, "facing": (look_at - pos).normalized() }
	p.merge(props, true)
	s.actor(id, &"puppet", pos, p)


## Whether `p` is out of harm from a frag that went off at `burst`: behind a wall or tall piece from it, or past its blast radius.
static func safe_from_frag(t: TestContext, burst: Vector2, p: Vector2) -> bool:
	return p.distance_to(burst) >= BLAST_RADIUS or not line_clear(t, burst, p)


## Wait (sim seconds) until actor `who`'s brain is carrying out an order whose path contains `needle` (a decision-tree id such as
## `grenade` or `stun_entry`); true as soon as it is. `seen` (an Array) collects every distinct act that was current, for messages.
static func wait_act(t: TestContext, who: StringName, needle: String, timeout: float, seen: Array = []) -> bool:
	var brain := t.controller(who, &"current_act")
	return await t.until(func() -> bool:
		var act := str(brain.current_act())
		if not seen.has(act):
			seen.append(act)
		return act.contains(needle), timeout)


## The act path (`current_act()`) of actor `who`'s brain right now, for messages.
static func acts(t: TestContext, who: StringName) -> String:
	return str(t.controller(who, &"current_act").current_act())


## G7 cover: whether something between a blast at `burst` and character `c` shields it: a wall, or a piece of furniture whose
## `coverage` is above the character's own (its posture's: crouched 35, standing 60), on the straight line from the blast to its body.
static func shielded(t: TestContext, burst: Vector2, c: Node2D) -> bool:
	var height := float(c.get_surface().get("coverage", 60.0))
	var exclude: Array = []
	for body in t.world.find_children("*", "CharacterBody2D", true, false):
		exclude.append((body as CharacterBody2D).get_rid())
	var space := t.world.get_world_2d().direct_space_state
	for i in 8:
		var query := PhysicsRayQueryParameters2D.create(burst, c.global_position, PhysicsLayers.SOLID)
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return false
		var collider: Object = hit["collider"]
		var cover := float(collider.get_surface().get("coverage", 100.0)) if collider.has_method("get_surface") else 100.0
		if cover > height:
			return true
		exclude.append(hit["rid"])
	return false
