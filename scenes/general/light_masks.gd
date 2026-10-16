class_name LightMasks

## General: the light masks every domain builds its shadows and light layers on (a `class_name` static holder, like
## `PhysicsLayers`, interface 11), so who shadows whom is decided in one place (`docs/lighting.md`) and no domain imports
## another for it. Objects (walls, solid pieces) and Character (the living body) build their own LightOccluder2D through
## `occluder`, as they build their colliders; Objects puts the street on `STREET`; the Lighting domain gives its lights the
## matching shadow masks and item layers.

## Whether the domains build their occluders (the Testing domain's `lighting.enabled` switch turns it off with
## `LightingConfig.enabled`, so a world without lighting carries no occluder either).
static var shadows := true

# --- Occluder bits (`LightOccluder2D.occluder_light_mask`): an occluder shadows a light whose shadow mask holds its bit ----
## A 2D occluder has no height (its shadow runs to the rim of the light's pool), so who shadows whom is chosen by height
## instead: a light overhead is shadowed only by what reaches the ceiling (the walls), a low one also by what stands taller
## than a person (`TALL`), a flash at hand height by everything.
const WALL := 1  ## A wall run.
const FURNITURE := 2  ## A solid piece that gives no light, lower than `TALL_COVERAGE`.
## A solid piece that gives light: shadows only the flashes, never a piece's light (its own sits inside it, and a street
## lamp's own post would throw a shadow across the sidewalk).
const EMITTER := 4
const CHARACTER := 8  ## A living character (the dead cast none: a body on the floor would throw a wall-long shadow).
## A solid piece that gives no light and stands taller than a person (a wardrobe, a fridge, shelving, lockers): it shadows the
## low lights too.
const TALL := 16
## The `coverage` (the hittable's 0..100 height) from which a piece is `TALL`: above a standing character's 60.
const TALL_COVERAGE := 75.0

# --- Shadow masks (`Light2D.shadow_item_cull_mask`) ------------------------------------------------------------------
## An overhead light (a ceiling fixture, a standing lamp, the surgeon's lamp, a street lamp or sign): the walls only (they
## hang over the furniture and the characters).
const OVERHEAD_SHADOWS := WALL
## A low light (a screen, a neon tube, LEDs, a hotplate, neon trim): the walls and the tall pieces.
const LOW_SHADOWS := WALL | TALL
## A flash (a muzzle, a burst at hand height): everything.
const ALL_SHADOWS := WALL | FURNITURE | EMITTER | CHARACTER | TALL

# --- Item light layers (`CanvasItem.light_mask`; a light lights an item whose light mask meets its `range_item_cull_mask`) --
const HOUSE := 1  ## Godot's default: everything but the street.
## The street round a house: lit only by the street lamps, the flashes and its own unshadowed sky, so the house's lights
## never crowd a street floor (which spans the whole house) past the 15 point lights an item takes.
const STREET := 2


## A LightOccluder2D over `polygon` (in the frame of the node it is added to) on occluder bit `bit`, wound and culled so the
## shape itself stays lit and only what lies behind it falls dark; null while `shadows` is off. The caller adds it as a
## child, so it follows its owner.
static func occluder(polygon: PackedVector2Array, bit: int) -> LightOccluder2D:
	if not shadows or polygon.size() < 3:
		return null
	var area := 0.0
	for k in polygon.size():
		var p := polygon[k]
		var q := polygon[(k + 1) % polygon.size()]
		area += p.x * q.y - q.x * p.y
	var poly := polygon.duplicate()
	if area < 0.0:  # Clockwise on screen (y down), culled counter-clockwise: the probed winding that keeps the shape lit.
		poly.reverse()
	var shape := OccluderPolygon2D.new()
	shape.polygon = poly
	shape.cull_mode = OccluderPolygon2D.CULL_COUNTER_CLOCKWISE
	var occ := LightOccluder2D.new()
	occ.name = "LightOccluder"
	occ.occluder = shape
	occ.occluder_light_mask = bit
	return occ
