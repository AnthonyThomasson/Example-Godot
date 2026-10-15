class_name Explosion

## Projectile System: the burst of a grenade, called by the thrown grenade (Items) when its fuse runs out. `frag` is
## the frag grenade's blast and fragments, `stun` the stun grenade's flash and bang (docs/grenades.md G7 to G12).
## `at` is the burst point, `world` the world root, `source` the thrower (null when gone) and `row` the grenade's
## `GrenadeConfig` row. Both post `&"explosion"` `{ position, kind, attacker, radius }` (the sound, the camera shake and the
## AI's perception hear it) and call `Physics.spawn_explosion` for its look. A grenade hurts and stuns everyone, its
## thrower and its own side included (G9).
##
## **The blast** reaches every hittable body with a clear line from the burst point within `blast_radius`, measured to its
## centre. A wall (a static body) stops the line; so does a piece of furniture whose `coverage` is above the body's own
## height (a character's is its posture's), which is what shields a crouched character behind a couch and not a standing
## one. Fragments fly at a height too, so they behave so already. What it reaches takes `take_hit` and is shoved away.
## **The flash** works by sight (the same line rule, the facing of the victim scaling it); **the bang** by range, through
## walls at `wall_factor` (a wall only: furniture muffles nothing).

## The layer the line queries test (walls, solid furniture, the living).
const MASK := PhysicsLayers.SOLID
## Most bodies one blast considers.
const MAX_BODIES := 64
## Most colliders a line may pass through (the low ones it clears) before it is called blocked.
const MAX_CLEARED := 8


## The frag grenade goes off at `at`: its blast, then its fragments.
static func frag(at: Vector2, world: Node, source: Node, row: Dictionary) -> void:
	_announce(at, &"frag", source, float(row.get("blast_radius", 0.0)))
	Physics.spawn_explosion(world, at, &"frag")
	_blast(at, world, source, row)
	_fragments(at, world, source, row)


## The stun grenade goes off at `at`: its flash and its bang.
static func stun(at: Vector2, world: Node, source: Node, row: Dictionary) -> void:
	_announce(at, &"stun", source, float(row.get("flash_radius", 0.0)))
	Physics.spawn_explosion(world, at, &"stun")
	var space := (world as Node2D).get_world_2d().direct_space_state
	var flash_radius := float(row.get("flash_radius", 0.0))
	var bang_radius := float(row.get("bang_radius", 0.0))
	var characters := _characters(world)
	for c: Node2D in characters:
		if _dead(c):
			continue
		var d := at.distance_to(c.global_position)
		if d >= maxf(flash_radius, bang_radius):
			continue
		var seen := not _reach(space, at, c, characters, float(row.get("flash_cover_reach", INF))).is_empty()
		var walled := _reach(space, at, c, characters, INF, true).is_empty()
		var blind := _blind_time(row, c, at, d) if seen else 0.0
		var deaf := float(row.get("max_deaf", 0.0)) * clampf(1.0 - d / maxf(bang_radius, 0.01), 0.0, 1.0) \
				* (float(row.get("wall_factor", 1.0)) if walled else 1.0)
		c.call("take_stun", blind, deaf)
		if d < float(row.get("point_blank", 0.0)):
			c.call("take_damage", float(row.get("point_blank_damage", 0.0)))


## Post the burst for whoever listens (the Audio domain, the camera, the AI).
static func _announce(at: Vector2, kind: StringName, source: Node, radius: float) -> void:
	EventBus.post(&"explosion", { "position": at, "kind": kind, "attacker": source, "radius": radius })


# --- The frag blast and its fragments (G7, G8) -----------------------------------------------------------

## Hurt and shove everything the blast reaches: damage full out to `kill_radius`, falling linearly to 0 at `blast_radius`.
static func _blast(at: Vector2, world: Node, source: Node, row: Dictionary) -> void:
	var radius := float(row.get("blast_radius", 0.0))
	var kill := float(row.get("kill_radius", 0.0))
	var space := (world as Node2D).get_world_2d().direct_space_state
	var characters := _characters(world)
	for body: Node2D in _bodies_near(space, at, radius, characters):
		var d := at.distance_to(body.global_position)
		if d >= radius:
			continue
		var reach := _reach(space, at, body, characters)
		if reach.is_empty():
			continue
		var strength := clampf((radius - d) / maxf(radius - kill, 0.01), 0.0, 1.0)
		var away := (body.global_position - at).normalized() if d > 0.01 else Vector2.RIGHT
		if not _dead(body) and body.has_method("take_hit"):
			_strike(body, reach, away, float(row.get("blast_damage", 0.0)) * strength, source)
		var shove := float(row.get("blast_impulse", 0.0)) * strength
		if body.has_method("get_mass"):  # a light body is not thrown faster than the blast's top speed
			shove = minf(shove, float(body.call("get_mass")) * float(row.get("blast_max_speed", INF)))
		if body.has_method("blast_push"):
			body.call("blast_push", at, shove)
		elif body.has_method("apply_impulse"):
			body.call("apply_impulse", away * shove)


## Hand `body` a blast `HitInfo` of `damage` and post the `&"hit"` the listeners hear (outcome `blast`). The hit carries
## no impact of its own (`speed_factor` 0): the shove of a blast is the grenade's `blast_impulse`, applied by the caller; and no
## height (-1): it strikes the whole body (a character's torso armour cuts it).
static func _strike(body: Node2D, reach: Dictionary, away: Vector2, damage: float, source: Node) -> void:
	if damage <= 0.0:
		return
	var info := HitInfo.new()
	info.position = reach["position"]
	info.normal = reach["normal"]
	info.direction = away
	info.damage = damage
	info.speed_factor = 0.0
	info.height = -1.0  # no height: the blast strikes the whole body
	body.call("take_hit", info)
	var surface: Dictionary = body.call("get_surface") if body.has_method("get_surface") else {}
	EventBus.post(&"hit", {
		"position": info.position, "victim": body, "source": null, "direction": away, "damage": damage,
		"attacker": source, "outcome": &"blast", "material": String(surface.get("material", "")),
		"speed_factor": 0.0, "power": 1.0,
	})


## The grenade's fragments: `fragments` bullets evenly round the circle (each jittered within its share of it), low power
## and fast, spent past `fragment_range`. They strike like any bullet and name the thrower, who is not spared (G9).
static func _fragments(at: Vector2, world: Node, source: Node, row: Dictionary) -> void:
	var count := int(row.get("fragments", 0))
	if count <= 0:
		return
	var turn := randf() * TAU
	for i in count:
		var angle := turn + TAU * (float(i) + randf_range(-0.4, 0.4)) / float(count)
		var fragment := ProjectileSpawner.spawn(at, Vector2.from_angle(angle), world, source, 0.0,
			float(row.get("fragment_speed", -1.0)), float(row.get("fragment_penetration", 1.0)),
			float(row.get("fragment_range", -1.0)), true)
		fragment.set("damage", float(row.get("fragment_damage", 10.0)))


# --- The flash (G11) ------------------------------------------------------------------------------

## Seconds `c`, `d` px from the burst at `at`, is blinded by it with a clear line: `max_blind` scaled by distance (full inside
## `flash_full`, linearly less out to `flash_radius`) and by how squarely it faces the burst (x1 facing it, x0.6 side-on, x0.25
## back to it, linear between).
static func _blind_time(row: Dictionary, c: Node2D, at: Vector2, d: float) -> float:
	var radius := float(row.get("flash_radius", 0.0))
	var full := float(row.get("flash_full", 0.0))
	var reach := clampf((radius - d) / maxf(radius - full, 0.01), 0.0, 1.0)
	var facing: Vector2 = c.get("facing")
	var dot := facing.normalized().dot((at - c.global_position).normalized()) if d > 0.5 and facing.length() > 0.0 else 1.0
	var share := lerpf(0.6, 1.0, dot) if dot >= 0.0 else lerpf(0.6, 0.25, -dot)
	return float(row.get("max_blind", 0.0)) * reach * share


# --- Lines and who is near -------------------------------------------------------------------------

## Whether `body` is a character that has died (a body with no `is_dead` is not).
static func _dead(body: Object) -> bool:
	return body.get("is_dead") == true


## Every character under `world` (a node with `current_item()`, dead ones included).
static func _characters(world: Node) -> Array:
	var out: Array = []
	_collect_characters(world, out)
	return out


## Append to `out` every character under `node`, at any depth.
static func _collect_characters(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child.has_method("current_item"):
			out.append(child)
		_collect_characters(child, out)


## The bodies a blast of `radius` at `at` may reach: what its circle overlaps on the solid layer (furniture, the living; walls
## are what block it, so they are left out) and the fallen, who have left that layer but are still shoved. Each once.
static func _bodies_near(space: PhysicsDirectSpaceState2D, at: Vector2, radius: float, characters: Array) -> Array:
	var circle := CircleShape2D.new()
	circle.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, at)
	query.collision_mask = MASK
	var out: Array = []
	for found: Dictionary in space.intersect_shape(query, MAX_BODIES):
		var body: Object = found["collider"]
		if body is StaticBody2D or out.has(body):
			continue
		if body.has_method("take_hit") or body.has_method("apply_impulse"):
			out.append(body)
	for c: Node2D in characters:
		if _dead(c) and not out.has(c):
			out.append(c)
	return out


## Whether something between `burst` and `p` shields a body `height` tall at `p` from a burst there (G7): a wall, or a piece of
## furniture whose `coverage` is above `height` (the lower ones are cleared); with a finite `cover_reach` (a stun's flash, G11) a piece
## only when `p` is within that many px of it on the burst's side. `exclude` holds the rids the line passes through (the characters').
## The rule the blast and the flash keep, which the AI's perception asks of a grenade (interface 3).
static func shields(space: PhysicsDirectSpaceState2D, burst: Vector2, p: Vector2, height: float, exclude: Array, cover_reach := INF) -> bool:
	return not _walk(space, burst, p, height, exclude, cover_reach).is_empty()


## The first wall or piece of furniture on the line from `a` to `b` that stops it for a body `height` tall, as its ray hit
## (`{ position, normal, collider, rid, ... }`), or {} when none does: the lower pieces are cleared. `exclude` holds the rids the
## line passes through. Where the AI's perception looks for the shadow behind cover (interface 3).
static func first_stop(space: PhysicsDirectSpaceState2D, a: Vector2, b: Vector2, height: float, exclude: Array) -> Dictionary:
	var found := _walk(space, a, b, height, exclude)
	return {} if found.has("exhausted") else found


## Where the line from `at` meets `body`, `{ position, normal }`, or {} when something stops it first (`_walk`): a wall, or a piece of
## furniture taller than `body` (its `get_surface().coverage`, a character's being its posture's). Lower pieces are cleared and so are
## the other characters. A body with no collider (the fallen) is reached at its centre. With a finite `cover_reach` (the flash, G11) a
## piece of furniture only stops the line when `body` is within that many px of it on the burst's side; with `walls_only` (the bang,
## G12) furniture does not stop it at all.
static func _reach(space: PhysicsDirectSpaceState2D, at: Vector2, body: Node2D, characters: Array, cover_reach := INF, walls_only := false) -> Dictionary:
	var height := float(body.call("get_surface").get("coverage", 100.0)) if body.has_method("get_surface") else 0.0
	var skip: Array[RID] = []
	for c: Node2D in characters:
		if c != body and c is CollisionObject2D:
			skip.append((c as CollisionObject2D).get_rid())
	var found := _walk(space, at, body.global_position, height, skip, cover_reach, walls_only, body)
	if found.is_empty():
		return { "position": body.global_position, "normal": (at - body.global_position).normalized() }
	if found.get("collider") == body:
		return { "position": found["position"], "normal": found["normal"] }
	return {}


## Walk the line from `at` to `to` past what does not stop it for a body `height` tall and return the ray hit that ends it: `target`
## when the line meets it, else the first wall or piece of furniture that stops it (`_stops`; with a finite `cover_reach` a piece only
## when `to` is within that many px of it, `_against`; with `walls_only` a wall only). {} when the line is clear, and
## `{ exhausted = true }` (stopped) once it has cleared `MAX_CLEARED` pieces. `exclude` holds the rids the line passes through.
static func _walk(space: PhysicsDirectSpaceState2D, at: Vector2, to: Vector2, height: float, exclude: Array, cover_reach := INF,
		walls_only := false, target: Object = null) -> Dictionary:
	var skip: Array[RID] = []
	skip.assign(exclude)
	var query := PhysicsRayQueryParameters2D.create(at, to, MASK)
	for _i in MAX_CLEARED:
		query.exclude = skip
		var found := space.intersect_ray(query)
		if found.is_empty():
			return {}
		var collider: Object = found["collider"]
		if collider == target or collider is StaticBody2D:
			return found
		if not walls_only and _stops(collider, height) and _against(space, at, to, collider, skip, target, cover_reach):
			return found
		skip.append(found["rid"])
	return { "exhausted": true }


## Whether `to` is within `cover_reach` px of `piece`, the piece's face on the burst's side taken along the line from `to` to `at`
## (`target`, the body at `to`, left out of that line).
static func _against(space: PhysicsDirectSpaceState2D, at: Vector2, to: Vector2, piece: Object, skip: Array[RID], target: Object,
		cover_reach: float) -> bool:
	if cover_reach == INF:
		return true
	var query := PhysicsRayQueryParameters2D.create(to, at, MASK)
	query.exclude = skip + ([(target as CollisionObject2D).get_rid()] if target is CollisionObject2D else [])
	var found := space.intersect_ray(query)
	return not found.is_empty() and found["collider"] == piece and to.distance_to(found["position"]) <= cover_reach


## Whether `collider` stops a line to something `height` tall: a wall always does, and so does anything that reports no height;
## a piece of furniture when it stands above it.
static func _stops(collider: Object, height: float) -> bool:
	if collider == null or collider is StaticBody2D or not collider.has_method("get_surface"):
		return true
	return float(collider.call("get_surface").get("coverage", 100.0)) > height
