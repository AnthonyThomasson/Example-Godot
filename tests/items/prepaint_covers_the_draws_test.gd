extends GameTest

## Every gun and grenade an inventory makes paints its art ahead of time (`Item.prepaint`, from `ItemRegistry.inventory_for`):
## a gun held at every raise step and lying either side up, a grenade with its lever held and gone, each at every lighting step.
## It only fills PixelArt's cache with what the draws would paint. This makes each weapon style's guns and grenades, then draws
## them every way a match does (held at random facings and raises, lying at random angles and sides): no draw paints anything
## new, and every texture prepainted is the one a fresh paint of the same inputs gives (when the renderer hands images back).

const DRAWS := 400
const STYLES: Array[StringName] = [&"police", &"scrap", &"pipe"]


func describe() -> Dictionary:
	return {
		"name": "Prepainted weapon art covers every draw",
		"description": "After ItemRegistry makes guns and grenades in each style, drawing them held, raised and lying at any angle paints no new texture.",
		"tags": ["art", "gun", "grenade", "cache"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))


## Stands in for the character a held item asks where and how to draw.
class FakeUser:
	extends RefCounted

	var facing := Vector2.DOWN
	var raise := 0.0

	## The way the held item is drawn pointing.
	func weapon_facing() -> Vector2:
		return facing

	## How far a long gun is raised off a wall (0..1).
	func weapon_raise() -> float:
		return raise

	## How far a hand is thrown in a punch: 0, no punch.
	func punch_amount(_hand: int) -> float:
		return 0.0

	## Where a hand holds the item (local px): one fixed point.
	func hand_position(_hand: int) -> Vector2:
		return Vector2(10.0, 4.0)


## Draws the items every way, from a seeded RNG.
class Drawer:
	extends Node2D

	var items: Array = []
	var drawn := false

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 77
		var user := FakeUser.new()
		for i in DRAWS:
			for item: Item in items:
				user.facing = Vector2.from_angle(rng.randf() * TAU)
				user.raise = rng.randf() if i % 2 == 0 else float(rng.randi_range(0, 1))
				item.draw_weapon(self, user)
				item.draw_dropped(self, Vector2.ZERO, rng.randf_range(-TAU, TAU), Color.WHITE, { "flip": rng.randf() < 0.5 })
		drawn = true


func run(t: TestContext) -> void:
	var slots := ItemRegistry.gun_slots() + [ItemRegistry.STUN_SLOT, ItemRegistry.FRAG_SLOT]
	var items: Array = []
	for style in STYLES:
		var inv := ItemRegistry.inventory_for(slots, -1, &"", { ItemRegistry.STUN_SLOT: 1, ItemRegistry.FRAG_SLOT: 1 }, style)
		for item in inv.values():
			items.append(item)
	var guns := items.filter(func(item: Item) -> bool: return item is GunItem).size()
	var grenades := items.filter(func(item: Item) -> bool: return item is GrenadeItem).size()
	t.check(guns >= 3 * STYLES.size() and grenades == 2 * STYLES.size(), "every style's guns and grenades were made (%d guns, %d grenades)" % [guns, grenades])
	var painted := PixelArt._cache.size()
	var drawer := Drawer.new()
	drawer.items = items
	t.world.add_child(drawer)
	await t.until(func() -> bool: return drawer.drawn, 2.0)
	t.check(drawer.drawn, "the items were drawn")
	t.check(PixelArt._cache.size() == painted, "no draw painted a new texture (%d new)" % (PixelArt._cache.size() - painted))

	# A prepainted texture is the one a fresh paint of its inputs gives.
	var compared := 0
	var differing := 0
	for item: Item in items:
		var drawn: Dictionary = item.look()
		var size: Vector2 = item.flat_size() if item is GunItem else item.art_size()
		var colour: Color = drawn["body"] if item is GunItem else drawn["shell"]
		var opts := { "gun": item.gun, "look": item._look_handle(drawn), "flat": true, "flip": true } if item is GunItem \
			else { "kind": item.kind, "look": item._look_handle(drawn), "spoon": false }
		var angle := PixelArt.snap_angle(TAU * 5.0 / ArtConfig.turn_steps)
		var image := PixelArt.render_turned(drawn["painter"], size, colour, angle, drawn["finish"], opts).get_image()
		if image == null:
			continue
		var base_key := PixelArt._key(drawn["painter"], size, colour, drawn["finish"], opts)
		var fresh := PixelArt._paint(drawn["painter"], PixelArt._resolution(size), colour, -angle, drawn["finish"], opts, base_key).img
		compared += 1
		if image.get_data() != fresh.get_data():
			differing += 1
	if DisplayServer.get_name() != "headless":
		t.check(compared == items.size(), "every item's texture was compared (%d of %d)" % [compared, items.size()])
	if compared > 0:
		t.check(differing == 0, "%d of %d prepainted textures differ from a fresh paint" % [differing, compared])
