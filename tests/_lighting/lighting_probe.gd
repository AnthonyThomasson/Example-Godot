extends RefCounted

## Ticket #61 R10 (the Lighting domain): the shared reads of the `tests/lighting/` tests. Not a test.
##
## The plan's numbers are kept here as consts, so a test checks the plan and not the code.
##
## What the tests read (each test names the ones it uses):
## - `WorldLighting` (class_name, `scenes/lighting/`): the world's lighting node, built by Main and the Testing world under
##   the world root and in the group `world_lighting`, with
##   - `lights() -> Array`: every PointLight2D it gave a piece or a room fixture (not the flashes);
##   - `fixtures() -> Array`: `{ room, light }` per room fixture (`room` the `WorldGen.get_rooms` key, `light` its PointLight2D);
##   - `flashes() -> Array`: the pooled PointLight2Ds the `shot` / `explosion` flashes are lit with;
##   - `budget() -> Dictionary`: `{ per_floor, dropped }`, `per_floor` the most piece and fixture lights one floor may be reached by,
##     `dropped` `{ piece, index }` per declared light the budget left without a PointLight2D (`index` into its `get_lights()`);
##   - `static light(root: Node2D, seed_value: int, rooms := []) -> WorldLighting`: light the world under `root` (`rooms` the
##     `WorldGen.get_rooms` dicts, for the fixtures; the call Main and the Testing world make).
## - `LightingConfig` (class_name static holder): `ambient_color`, `sky_color` and `enabled` (the `lighting.enabled` switch).
## - On a piece that gives light (Objects): `get_lights() -> Array`, one plain dict per light (`offset`, `colour`, `energy`,
##   `radius`, `shape`, `rhythm`, `room_light`: true when it lights its room, so the room needs no fixture, and `height`:
##   `overhead` or `low`), read duck-typed.
## - A light's pool is its texture: a radial GradientTexture2D, read through its `gradient` (`profile`).
## - Occluders, flashes, the ambient and the sky are plain Godot nodes (LightOccluder2D, PointLight2D, CanvasModulate,
##   DirectionalLight2D) under the test world, read by their own properties.

const GROUP := &"world_lighting"
## Godot 4.4 lights a canvas item with at most this many point lights.
const ITEM_LIGHTS := 15
## The most piece (and fixture) lights one floor is reached by: 3 of the 15 kept for the flashes.
const PER_FLOOR := 12
## The dusk ambient (the plan's numbers).
const AMBIENT := Color(0.40, 0.37, 0.55)
## How far (px) from the event a flash's light may stand.
const FLASH_NEAR := 24.0
## An overhead light's pool shines down: still this bright (of its centre) at half its radius; a low light's glow falls below
## `LOW_HALF_MAX` there.
const OVERHEAD_HALF_MIN := 0.9
const LOW_HALF_MAX := 0.7
## A light's pool falls off smoothly, without rings: sampled `SMOOTH_SAMPLES` times from its centre to its rim, no two
## neighbouring samples differ by more than `SMOOTH_STEP_MAX` of its centre's brightness.
const SMOOTH_SAMPLES := 64
const SMOOTH_STEP_MAX := 0.08
## A street lamp's (or sign's) pool: at most this radius (px), centred within `STREET_POOL_CENTRE` px of its head.
const STREET_POOL_MAX := 140.0
const STREET_POOL_CENTRE := 4.0
## A standing lamp's pool radius (px), within `LAMP_POOL_SLACK`.
const LAMP_POOL := 160.0
const LAMP_POOL_SLACK := 10.0


# --- The domain -------------------------------------------------------------------------------------------------------

## The WorldLighting node under the test world (null without one).
static func lighting(t: TestContext) -> WorldLighting:
	for n in t.world.get_tree().get_nodes_in_group(GROUP):
		if t.world.is_ancestor_of(n):
			return n as WorldLighting
	return null


## Require the test world's WorldLighting; the node, or null (the test has failed).
static func require_lighting(t: TestContext) -> WorldLighting:
	var node := lighting(t)
	if not t.require(node != null, "the test world has its WorldLighting (a node in the group %s under the world)" % GROUP):
		return null
	return node


## Every node of Godot class `type` under `root`.
static func under(root: Node, type: String) -> Array:
	return root.find_children("*", type, true, false)


# --- Pieces and their lights -----------------------------------------------------------------------------------------

## The pieces (RigidBody2D objects with an `art`) under `root`.
static func pieces(root: Node) -> Array:
	return under(root, "RigidBody2D").filter(func(n: Node) -> bool: return "art" in n and "art_opts" in n)


## What light-giving kind `piece` is ("lamp", "screen", "neon tube", "streetlight"), or "" for none of them.
static func light_kind(piece: Node) -> String:
	var opts: Dictionary = piece.get("art_opts") if piece.get("art_opts") is Dictionary else {}
	match String(piece.get("art")):
		"lamp":
			return "lamp"
		"streetlight":
			return "streetlight"
		"appliance":
			return "screen" if String(opts.get("panel", "")) == "tv" else ""
		"table":
			var props: Array = opts.get("props", [])
			return "screen" if props.any(func(p: Variant) -> bool: return p is Dictionary and p.get("kind", "") == "monitor") else ""
		"tech":
			return "screen" if String(opts.get("kind", "")) == "monitor_wall" else ""
		"decor":
			return "neon tube" if String(opts.get("kind", "")) == "neon_tube" else ""
	return ""


## The lights `piece` (a piece from `pieces`) declares: its `get_lights()`.
static func declared(piece: Node) -> Array:
	return piece.get_lights()


## The brightness of light `l`'s pool at `at` of its radius (0 the centre, 1 the rim), over its centre's; -1 when its texture
## is not a radial gradient.
static func profile(l: PointLight2D, at: float) -> float:
	var tex := l.texture as GradientTexture2D
	if tex == null or tex.gradient == null or tex.fill != GradientTexture2D.FILL_RADIAL:
		return -1.0
	var centre := tex.gradient.sample(0.0).v
	return tex.gradient.sample(at).v / centre if centre > 0.0 else -1.0


## The biggest jump in light `l`'s pool between neighbouring samples from its centre to its rim (`SMOOTH_SAMPLES` of them),
## over its centre's brightness; -1 when its texture is not a radial gradient.
static func largest_step(l: PointLight2D) -> float:
	var worst := 0.0
	var last := profile(l, 0.0)
	if last < 0.0:
		return -1.0
	for k in range(1, SMOOTH_SAMPLES + 1):
		var v := profile(l, float(k) / SMOOTH_SAMPLES)
		worst = maxf(worst, absf(v - last))
		last = v
	return worst


## The lights of `node` that are under `piece`.
static func lights_of(node: WorldLighting, piece: Node) -> Array:
	return node.lights().filter(func(l: Variant) -> bool: return l is Node and piece.is_ancestor_of(l))


## The `budget().dropped` entries of `node` for `piece`.
static func dropped_of(node: WorldLighting, piece: Node) -> Array:
	var dropped: Array = node.budget().get("dropped", [])
	return dropped.filter(func(d: Variant) -> bool: return d is Dictionary and d.get("piece") == piece)


# --- Floors and what reaches them -------------------------------------------------------------------------------------

## The floors (Objects' Floor nodes: a room's, the arena's or a piece of the street) under `root`.
static func floors(root: Node) -> Array:
	return under(root, "Node2D").filter(func(n: Node) -> bool: return "floor_material" in n and "size" in n)


## The world rect `ground` covers.
static func floor_rect(ground: Node2D) -> Rect2:
	return Rect2(ground.global_position, ground.get("size"))


## The light-mask bits of `ground`'s canvas items (the floor and everything drawn under it).
static func floor_mask(ground: Node2D) -> int:
	var mask := ground.light_mask
	for item in under(ground, "CanvasItem"):
		mask |= (item as CanvasItem).light_mask
	return mask


## The world rect the pool of light `l` covers (its texture's box, scaled and turned).
static func light_box(l: PointLight2D) -> Rect2:
	if l.texture == null:
		return Rect2(l.global_position, Vector2.ZERO)
	var half := Vector2(l.texture.get_size()) * l.texture_scale * 0.5
	var xf := l.global_transform
	var out := Rect2(xf * -half, Vector2.ZERO)
	for corner in [Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)]:
		out = out.expand(xf * (corner as Vector2))
	return out


## Whether light `l` lights `ground`: its item mask takes the floor's items and its pool reaches the floor's rect.
static func reaches(l: PointLight2D, ground: Node2D) -> bool:
	return l.range_item_cull_mask & floor_mask(ground) != 0 and light_box(l).intersects(floor_rect(ground))


## Whether flash light `l` is lit now.
static func lit(l: PointLight2D) -> bool:
	return l.enabled and l.energy > 0.01 and l.is_visible_in_tree()


# --- Occluders --------------------------------------------------------------------------------------------------------

## Whether occluder `occ` casts now (in the tree, visible, with a polygon).
static func casting(occ: LightOccluder2D) -> bool:
	return occ.is_visible_in_tree() and occ.occluder != null and occ.occluder.polygon.size() >= 3


## Whether occluder `occ`'s polygon holds world point `p`.
static func holds(occ: LightOccluder2D, p: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(occ.global_transform.affine_inverse() * p, occ.occluder.polygon)


## The casting occluders under `root` whose polygon holds world point `p`.
static func occluders_at(root: Node, p: Vector2) -> Array:
	return under(root, "LightOccluder2D").filter(func(o: LightOccluder2D) -> bool: return casting(o) and holds(o, p))


## The casting occluders under `node` itself.
static func own_occluders(node: Node) -> Array:
	return under(node, "LightOccluder2D").filter(func(o: LightOccluder2D) -> bool: return casting(o))
