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
const WALL := 1  ## A wall run.
const FURNITURE := 2  ## A solid piece that gives no light.
## A solid piece that gives light: shadows only the flashes and the sky, never a piece's light (its own sits inside it, and a
## 2D occluder has no height, so a street lamp's own post would throw a shadow across the sidewalk).
const EMITTER := 4
const CHARACTER := 8  ## A living character (the dead cast none: a body on the floor would throw a wall-long shadow).

# --- Shadow masks (`Light2D.shadow_item_cull_mask`) ------------------------------------------------------------------
## A piece's light and a street lamp's: walls, furniture and the living.
const PIECE_SHADOWS := WALL | FURNITURE | CHARACTER
## A ceiling fixture: the walls only (it hangs over the furniture and the characters).
const FIXTURE_SHADOWS := WALL
## A flash and the house's sky: everything.
const ALL_SHADOWS := WALL | FURNITURE | EMITTER | CHARACTER

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
