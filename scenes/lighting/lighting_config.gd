class_name LightingConfig

## The Lighting domain's tuning (a `class_name` static holder, like the other domains' configs): the dusk, the room fixtures,
## the flashes, the per-floor light budget and the light textures (`docs/lighting.md`). What each piece's light is (where,
## what colour, how bright, which rhythms) is the piece's own declaration (Objects' `get_lights()`), not tuned here.

## Master switch (the Testing domain's `lighting.enabled`, which also turns General's `LightMasks.shadows` off, so no domain
## builds an occluder): off, `WorldLighting.light` builds nothing, and the world is drawn as its art alone.
static var enabled := true

# --- Dusk --------------------------------------------------------------------------------------------------------------
## The ambient (one CanvasModulate over the world): a cool blue-violet, bright enough to read a room and the characters.
static var ambient_color := Color(0.40, 0.37, 0.55)
## The sky light: a dim orange-magenta, low in the south-west (the front of a house is south), from `sky_from`.
static var sky_color := Color(1.0, 0.5, 0.42)
static var sky_from := Vector2(-0.38, 1.0)
## Its energy on the street (unshadowed) and on the house's items (shadowed by everything, so only doorways let it in).
static var sky_street_energy := 0.42
static var sky_house_energy := 0.36

# --- Room fixtures -----------------------------------------------------------------------------------------------------
## A room no piece lights (none of its lights is a kept `room_light`) gets a ceiling fixture at its centre: a bare bulb on its
## flex (drawn unshaded) and its light, shadowed by the walls only (it hangs over the furniture and the characters). Its pool
## spans the room and barely past its walls: the room's longer side × `fixture_reach_scale` + `fixture_reach_pad`, clamped.
static var fixture_color := Color(1.0, 0.62, 0.22)
static var fixture_energy := 0.8
static var fixture_reach_scale := 1.1
static var fixture_reach_pad := 60.0
static var fixture_reach_range := Vector2(300.0, 900.0)
## The rhythms a fixture's light is drawn from, by weight (`LightRhythm.MODES`).
static var fixture_rhythms: Array = [[&"steady", 12.0], [&"failing", 1.0]]

# --- Flashes -----------------------------------------------------------------------------------------------------------
## A pool of point lights lit by the `shot` and `explosion` events (the 3 of the 15 point lights an item takes that the budget
## keeps free). Each kind: colour, energy, pool diameter (px; an explosion's at least `radius × reach_per_radius`) and
## how long (s) it falls off to dark.
static var flash_pool := 3
static var flashes: Dictionary = {
	&"shot": { "color": Color(1.0, 0.82, 0.55), "energy": 1.6, "reach": 340.0, "life": 0.07 },
	&"frag": { "color": Color(1.0, 0.62, 0.3), "energy": 2.6, "reach": 600.0, "reach_per_radius": 4.0, "life": 0.5 },
	&"stun": { "color": Color(0.92, 0.95, 1.0), "energy": 3.2, "reach": 700.0, "reach_per_radius": 3.5, "life": 0.3 },
}

# --- Budget ------------------------------------------------------------------------------------------------------------
## Godot 4.4 lights a canvas item with at most 15 point lights (the renderer stops gathering at MAX_LIGHTS_PER_ITEM - 1;
## directional lights are apart). A floor (with its walls and wear, one room's items) takes at most `item_lights` minus the
## flash pool of the piece and fixture lights: a light that would crowd a floor past it gets none (the piece still glows).
static var item_lights := 15
## A floor's items are counted out this far (px) past its rect: its walls and wear reach a little past the floor.
static var floor_reach := 8.0

# --- Characters --------------------------------------------------------------------------------------------------------
## A light whose centre a living character stands within this many of its radii leaves the characters out of its shadows
## that frame: a body would black out the light it stands in (a screen's spill, under a street lamp's head).
static var body_clear := 1.3

# --- Textures ----------------------------------------------------------------------------------------------------------
## The pool textures, by a light's `shape`: a round pool, a wide one (2:1, a screen's spill) and a tube's (3:1). Stepped, as
## pixel-art light is: bright in the middle, in bands down to nothing at the rim.
static var textures: Dictionary = { &"round": Vector2i(128, 128), &"wide": Vector2i(256, 128), &"tube": Vector2i(240, 80) }
static var texture_bands := PackedFloat32Array([0.0, 0.22, 0.4, 0.56, 0.7, 0.82, 0.92, 0.985])
static var texture_levels := PackedFloat32Array([1.0, 0.82, 0.64, 0.46, 0.3, 0.16, 0.06, 0.0])


## The most piece and fixture lights one floor may be reached by.
static func per_floor() -> int:
	return item_lights - flash_pool
