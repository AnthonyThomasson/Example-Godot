class_name WorldLighting
extends Node2D

## The Lighting domain's one node: a world's dusk lighting (`docs/lighting.md`), a leaf like Audio. Built by Main and the
## Testing world through `light(root, seed_value, rooms)` under the world root, in the group `world_lighting`; it reads the
## world only duck-typed (Objects' floors: `floor_material` / `size`; a light-giving piece's `get_lights()`; the characters in
## the group `characters`: `is_dead`, `radius`) and the `shot` / `explosion` events, and imports nothing but General.
##   - Dusk: one CanvasModulate in `LightingConfig.ambient_color`, and two DirectionalLight2Ds in `sky_color` low from the
##     south-west: one on the street (`LightMasks.STREET`), unshadowed (a directional shadow runs to the edge of the view, so a
##     body out there would throw one across the whole street), one on the house's items, shadowed by everything, so only
##     the doorways let it in.
##   - A PointLight2D per light a piece declares (`get_lights()`: `offset`, `turn`, `colour`, `energy`, `radius`, `shape`,
##     `rhythm`, `room_light`, `street`, `glow`), a child of the piece so a shoved lamp carries it; and a ceiling fixture
##     (a bulb glyph and its light, shadowed by the walls only) in every room no kept `room_light` lights.
##   - The budget (light_budget.gd): no floor reached by more than `LightingConfig.per_floor()` lights; the fixtures first,
##     then the declared lights strongest first, so a room over budget drops its weakest (`budget().dropped`).
##   - Rhythms (light_rhythm.gd) seeded per light from `seed_value` and the piece, dimming the light and its `glow` (the
##     piece's unshaded light-source overlay) together.
##   - Flashes: a pool of `LightingConfig.flash_pool` lights lit at a `shot`'s muzzle and an `explosion`'s burst.
##   - Each frame a light whose centre a living character stands within `LightingConfig.body_clear` of its radius leaves the
##     characters out of its shadows (a body would black out the light it stands in).
## Shadows are cast by the occluders the walls, solid pieces and living characters build themselves on `LightMasks`.

const Rhythm := preload("res://scenes/lighting/light_rhythm.gd")
const Budget := preload("res://scenes/lighting/light_budget.gd")
const Fixture := preload("res://scenes/lighting/ceiling_fixture.gd")

const GROUP := &"world_lighting"


## One kept light: its node, its full energy and own shadow mask, its rhythm (null: steady) and what glows with it.
class Lit:
	var light: PointLight2D
	var energy: float
	var mask: int
	var rhythm: Rhythm
	var glow: CanvasItem


static var _textures := {}  ## The light textures made so far, by shape.
static var _unshaded: CanvasItemMaterial  ## The unshaded material the fixtures' glyphs draw through.

var _seed := 0  ## The world's seed, which the rhythms are seeded from.
var _lit: Array[Lit] = []  ## Every kept piece and fixture light.
var _lights: Array = []  ## Their nodes (`lights()`).
var _fixtures: Array = []  ## `{ room, light }` per fixture.
var _dropped: Array = []  ## `{ piece, index }` per declared light the budget left out.
var _flashes: Array = []  ## The pooled flash lights.
var _flash_energy := PackedFloat32Array()  ## Each flash's energy as it was lit.
var _flash_life := PackedFloat32Array()  ## Each flash's life (s).
var _flash_t := PackedFloat32Array()  ## Each flash's time since it was lit (s).
var _next_flash := 0  ## The pooled flash lit next.
var _bodies: Array[Node] = []  ## The world's characters (refreshed when the group's size changes).
var _body_count := -1  ## The size of the group `characters` when `_bodies` was read.
var _body_at := PackedVector2Array()  ## This frame: each living character's position (INF for the dead and the gone).
var _body_reach := PackedFloat32Array()  ## Its `body_clear` reach squared.


## Light the world under `root` (built, in the tree): `seed_value` seeds the rhythms, `rooms` are its `WorldGen.get_rooms`
## (world-space `{ key, rect }`; none: no fixtures). Returns the WorldLighting it added under `root`, or null while
## `LightingConfig.enabled` is off (nothing is built).
static func light(root: Node2D, seed_value: int, rooms: Array = []) -> WorldLighting:
	if not LightingConfig.enabled:
		return null
	var node := WorldLighting.new()
	node.name = "WorldLighting"
	node._seed = seed_value
	node.add_to_group(GROUP)
	root.add_child(node)
	node._build(root, rooms)
	return node


## Every PointLight2D given to a piece or a room fixture (not the flashes).
func lights() -> Array:
	return _lights


## `{ room, light }` per room fixture (`room` the room's key).
func fixtures() -> Array:
	return _fixtures


## The pooled flash PointLight2Ds.
func flashes() -> Array:
	return _flashes


## `{ per_floor, dropped }`: the most lights one floor may be reached by, and `{ piece, index }` per declared light left without a
## PointLight2D (`index` into the piece's `get_lights()`).
func budget() -> Dictionary:
	return { "per_floor": LightingConfig.per_floor(), "dropped": _dropped }


func _exit_tree() -> void:
	if EventBus.posted.is_connected(_on_posted):
		EventBus.posted.disconnect(_on_posted)


func _process(delta: float) -> void:
	for lit in _lit:
		if lit.rhythm == null:
			continue
		var f := lit.rhythm.step(delta)
		lit.light.energy = lit.energy * f
		if lit.glow != null:
			var g := clampf(0.3 + 0.7 * f, 0.0, 1.1)
			lit.glow.modulate = Color(g, g, g)
	for k in _flashes.size():
		if _flash_t[k] >= _flash_life[k]:
			continue
		_flash_t[k] += delta
		var left := 1.0 - clampf(_flash_t[k] / _flash_life[k], 0.0, 1.0)
		var l: PointLight2D = _flashes[k]
		l.energy = _flash_energy[k] * left * left
		l.enabled = left > 0.0
	_clear_bodies()


# --- Building ----------------------------------------------------------------------------------------------------------

## Build the lighting of the world under `root` once: the ambient and the sky, the pieces' lights and the rooms' fixtures within
## the budget, the flash pool and its events.
func _build(root: Node2D, rooms: Array) -> void:
	if _unshaded == null:
		_unshaded = CanvasItemMaterial.new()
		_unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	var ambient := CanvasModulate.new()
	ambient.name = "Ambient"
	ambient.color = LightingConfig.ambient_color
	add_child(ambient)
	_sky(true)
	_sky(false)

	var floors := Budget.new()
	var candidates: Array = []  ## `[piece, index, spec, order]` per declared light.
	var lit_rooms := {}  ## Room key -> true for a room a piece's `room_light` stands in.
	for node in root.find_children("*", "", true, false):
		if node == self or is_ancestor_of(node):
			continue
		if "floor_material" in node and "size" in node:
			floors.add_floor(node)
		elif node.has_method(&"get_lights"):
			var specs: Array = node.call(&"get_lights")
			for i in specs.size():
				candidates.append([node, i, specs[i], candidates.size()])
				if (specs[i] as Dictionary).get("room_light", false):
					lit_rooms[_room_of(rooms, (node as Node2D).global_position)] = true

	# A room's own fixture first (always counted), then the declared lights strongest first.
	for room: Dictionary in rooms:
		if not lit_rooms.has(room["key"]):
			_fixture(room, floors, true)
	candidates.sort_custom(func(a: Array, b: Array) -> bool:
		var ea := float((a[2] as Dictionary).get("energy", 0.0))
		var eb := float((b[2] as Dictionary).get("energy", 0.0))
		return ea > eb if ea != eb else int(a[3]) < int(b[3]))
	var kept_rooms := {}
	for c: Array in candidates:
		if _piece_light(c[0], c[1], c[2], floors) and (c[2] as Dictionary).get("room_light", false):
			kept_rooms[_room_of(rooms, (c[0] as Node2D).global_position)] = true
	# A room whose every room light the budget left out still gets its fixture, where its floors have room for it.
	for room: Dictionary in rooms:
		if lit_rooms.has(room["key"]) and not kept_rooms.has(room["key"]):
			_fixture(room, floors, false)

	for k in LightingConfig.flash_pool:
		var flash := _point(Color.WHITE, 0.0, 1.0, &"round", LightMasks.ALL_SHADOWS, LightMasks.HOUSE | LightMasks.STREET)
		flash.name = "Flash%d" % (k + 1)
		flash.enabled = false
		add_child(flash)
		_flashes.append(flash)
	_flash_energy.resize(_flashes.size())
	_flash_life.resize(_flashes.size())
	_flash_t.resize(_flashes.size())
	_flash_life.fill(0.0)
	_flash_t.fill(0.0)
	EventBus.posted.connect(_on_posted)


## The dusk sky on the street (unshadowed) or on the house's items (shadowed by everything).
func _sky(street: bool) -> void:
	var sky := DirectionalLight2D.new()
	sky.name = "SkyStreet" if street else "SkyHouse"
	sky.color = LightingConfig.sky_color
	sky.energy = LightingConfig.sky_street_energy if street else LightingConfig.sky_house_energy
	sky.rotation = Vector2.DOWN.angle_to(-LightingConfig.sky_from)  # A directional light shines along its +y.
	sky.shadow_enabled = not street
	sky.shadow_filter = Light2D.SHADOW_FILTER_NONE
	sky.shadow_item_cull_mask = LightMasks.ALL_SHADOWS
	sky.range_item_cull_mask = LightMasks.STREET if street else LightMasks.HOUSE
	add_child(sky)


## Give `piece` its declared light `index` (`spec`, one of its `get_lights()`) if the floors it reaches have room for it;
## whether it did (else it is listed in `budget().dropped`).
func _piece_light(piece: Node2D, index: int, spec: Dictionary, floors: Budget) -> bool:
	var item_mask := LightMasks.HOUSE | (LightMasks.STREET if spec.get("street", false) else 0)
	var energy := float(spec.get("energy", 1.0))
	var l := _point(spec.get("colour", Color.WHITE), energy, float(spec.get("radius", 100.0)), spec.get("shape", &"round"),
		LightMasks.PIECE_SHADOWS, item_mask)
	l.position = spec.get("offset", Vector2.ZERO)
	l.rotation = float(spec.get("turn", 0.0))
	if not floors.take(Budget.box_of(l, piece.global_transform * l.transform), item_mask):
		l.free()
		_dropped.append({ "piece": piece, "index": index })
		return false
	l.name = "Light%d" % (index + 1)
	piece.add_child(l)
	var seed_value := hash([_seed, Vector2i(piece.global_position.round()), index])
	_keep(l, energy, LightMasks.PIECE_SHADOWS, spec.get("rhythm", []), seed_value, spec.get("glow"))
	return true


## A ceiling fixture at the centre of `room` (`{ key, rect }`): its bulb glyph and its light, shadowed by the walls only;
## `always` counts it against the budget whatever (a room no piece lights). Whether it was placed.
func _fixture(room: Dictionary, floors: Budget, always: bool) -> bool:
	var rect: Rect2 = room["rect"]
	var reach := clampf(maxf(rect.size.x, rect.size.y) * LightingConfig.fixture_reach_scale + LightingConfig.fixture_reach_pad,
		LightingConfig.fixture_reach_range.x, LightingConfig.fixture_reach_range.y)
	var l := _point(LightingConfig.fixture_color, LightingConfig.fixture_energy, reach * 0.5, &"round", LightMasks.FIXTURE_SHADOWS,
		LightMasks.HOUSE)
	l.position = to_local(rect.get_center())
	if not floors.take(Budget.box_of(l, global_transform * l.transform), LightMasks.HOUSE, always):
		l.free()
		return false
	l.name = "FixtureLight"
	add_child(l)
	var glyph: Node2D = Fixture.new().setup(LightingConfig.fixture_color, _unshaded)
	glyph.position = l.position
	add_child(glyph)
	_fixtures.append({ "room": room["key"], "light": l })
	_keep(l, LightingConfig.fixture_energy, LightMasks.FIXTURE_SHADOWS, LightingConfig.fixture_rhythms,
		hash([_seed, "fixture", room["key"]]), glyph)
	return true


## Keep light `l` (its full `energy`, its shadow `mask`) with a rhythm drawn from `kinds` (`[[mode, weight], ...]`) by an RNG
## seeded with `seed_value` (none when it draws `steady`), and the item that glows with it (or null).
func _keep(l: PointLight2D, energy: float, mask: int, kinds: Array, seed_value: int, glow: Variant) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var mode := Rhythm.pick(kinds, rng)
	var lit := Lit.new()
	lit.light = l
	lit.energy = energy
	lit.mask = mask
	lit.rhythm = null if mode == &"steady" else Rhythm.new(mode, rng.randi())
	lit.glow = glow as CanvasItem if glow is CanvasItem else null
	_lit.append(lit)
	_lights.append(l)


## A shadowed PointLight2D of `colour` at `energy`, its pool `radius` px out along its long axis in the texture of `shape`
## (`round`, `wide`, `tube`), shadowed by the occluders in `shadow_mask`, lighting the items in `item_mask`.
static func _point(colour: Color, energy: float, radius: float, shape: StringName, shadow_mask: int, item_mask: int) -> PointLight2D:
	if not LightingConfig.textures.has(shape):
		shape = &"round"
	var l := PointLight2D.new()
	l.texture = _texture(shape)
	l.texture_scale = radius * 2.0 / float((LightingConfig.textures[shape] as Vector2i).x)
	l.color = colour
	l.energy = energy
	l.shadow_enabled = true
	l.shadow_filter = Light2D.SHADOW_FILTER_NONE  # Hard edges, as pixel art; the cheapest.
	l.shadow_item_cull_mask = shadow_mask
	l.range_item_cull_mask = item_mask
	return l


## The stepped light texture of `shape` (built once).
static func _texture(shape: StringName) -> Texture2D:
	if _textures.has(shape):
		return _textures[shape]
	var gradient := Gradient.new()
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	gradient.offsets = LightingConfig.texture_bands
	var colors := PackedColorArray()
	for v in LightingConfig.texture_levels:
		colors.append(Color(v, v, v))
	gradient.colors = colors
	var tex := GradientTexture2D.new()
	var dims: Vector2i = LightingConfig.textures[shape]
	tex.width = dims.x
	tex.height = dims.y
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.gradient = gradient
	_textures[shape] = tex
	return tex


## The key of the room in `rooms` holding world point `p` ("" for none).
static func _room_of(rooms: Array, p: Vector2) -> String:
	for room: Dictionary in rooms:
		if (room["rect"] as Rect2).has_point(p):
			return String(room["key"])
	return ""


# --- Flashes -----------------------------------------------------------------------------------------------------------

## Light a flash for a `shot` at its muzzle or an `explosion` at its burst (EventBus).
func _on_posted(topic: StringName, data: Dictionary) -> void:
	if not data.has("position"):
		return
	match topic:
		&"shot":
			_flash(data["position"], LightingConfig.flashes[&"shot"], 0.0)
		&"explosion":
			var kind: StringName = &"stun" if data.get("kind", &"frag") == &"stun" else &"frag"
			_flash(data["position"], LightingConfig.flashes[kind], float(data.get("radius", 0.0)))


## Light the pooled flash next in turn at world point `at` in `look` (a `LightingConfig.flashes` row), its pool at least
## `radius` × the row's `reach_per_radius` across, falling off to dark over its `life`.
func _flash(at: Vector2, look: Dictionary, radius: float) -> void:
	if _flashes.is_empty():
		return
	var k := _next_flash
	_next_flash = (_next_flash + 1) % _flashes.size()
	var l: PointLight2D = _flashes[k]
	var reach := maxf(float(look["reach"]), radius * float(look.get("reach_per_radius", 0.0)))
	l.global_position = at
	l.color = look["color"]
	l.energy = look["energy"]
	l.texture_scale = reach / float((LightingConfig.textures[&"round"] as Vector2i).x)
	l.enabled = true
	_flash_energy[k] = look["energy"]
	_flash_life[k] = look["life"]
	_flash_t[k] = 0.0
	_clear_bodies()  # This frame already: a blast at someone's feet must not black out the room it lights.


# --- Characters --------------------------------------------------------------------------------------------------------

## Leave the characters out of the shadows of every lit light one of them stands in this frame (and put them back once
## none does). The character list is re-read only when the group's size changes, so a frame allocates nothing.
func _clear_bodies() -> void:
	var tree := get_tree()
	var count := tree.get_node_count_in_group(&"characters")
	if count != _body_count:
		_body_count = count
		_bodies.assign(tree.get_nodes_in_group(&"characters"))
		_body_at.resize(_bodies.size())
		_body_reach.resize(_bodies.size())
	for i in _bodies.size():
		var body := _bodies[i]
		if not is_instance_valid(body) or body.get(&"is_dead"):
			_body_at[i] = Vector2.INF
			continue
		_body_at[i] = (body as Node2D).global_position
		var reach := float(body.get(&"radius")) * LightingConfig.body_clear
		_body_reach[i] = reach * reach
	for lit in _lit:
		_clear_light(lit.light, lit.mask)
	for l: PointLight2D in _flashes:
		_clear_light(l, LightMasks.ALL_SHADOWS)


## Light `l`'s shadow mask: its own `mask`, without the characters while one stands within reach of its centre.
func _clear_light(l: PointLight2D, mask: int) -> void:
	if mask & LightMasks.CHARACTER == 0 or not l.enabled:
		return
	var at := l.global_position
	for i in _body_at.size():
		if at.distance_squared_to(_body_at[i]) < _body_reach[i]:
			mask &= ~LightMasks.CHARACTER
			break
	if l.shadow_item_cull_mask != mask:
		l.shadow_item_cull_mask = mask
