extends RefCounted

## Shared by the weapon-style tests (ticket #61, R3): how a gun or grenade is DRAWN in a weapon style, read through the published
## `Item.drawn_art()` (the textures the item's last `draw_weapon` / `draw_dropped` painted, like `CharacterVisuals.drawn_art()`).
## Art is cached by what it depicts, so two items
## drawn alike paint the very same textures and a changed look new ones: a drawing is compared as the set of its textures'
## instance ids.
## An item is drawn on a `DrawProbe` (a plain `Node2D` of the test's whose `_draw` calls the item's published `draw_weapon(canvas,
## user)` or `draw_dropped(canvas, at, angle, modulate, opts)`), one probe per item, since `drawn_art` is its last draw only.
## Not a test (`const StyleProbe := preload(...)`).

const STYLES: Array[StringName] = [&"police", &"scrap", &"pipe"]
## The weapon style an item never given one is drawn in.
const DEFAULT_STYLE := &"police"
## Each gun's and grenade's inventory slot, by name (`ItemRegistry`: the guns' `GunConfig` slots, `STUN_SLOT`, `FRAG_SLOT`).
const GUNS := { &"pistol": 3, &"smg": 5, &"rifle": 6 }
const GRENADES := { &"frag": 8, &"stun": 7 }


## A node of the test's that draws one item: held in `user`'s hand (`draw_weapon`) or lying at its origin along `angle` with `opts`
## (`draw_dropped`; `opts.flip` is which side is up).
class DrawProbe extends Node2D:
	var item: Item
	var user: Node
	var held := false
	var angle := 0.0
	var opts := {}

	func _draw() -> void:
		if item == null:
			return
		if held:
			item.draw_weapon(self, user)
		else:
			item.draw_dropped(self, Vector2.ZERO, angle, Color.WHITE, opts)


## The textures `item`'s last draw painted (`Item.drawn_art()`), as a set of their instance ids.
static func drawn(item: Item) -> Dictionary:
	var out := {}
	for tex in item.drawn_art():
		out[(tex as Object).get_instance_id() if tex is Object else 0] = true
	return out


## A fresh item for inventory `slot` in weapon `style` (`Item.style`); `&""` leaves it never given one.
static func make(slot: int, style: StringName) -> Item:
	var item := ItemRegistry.create(slot)
	if style != &"":
		item.style = style
	return item


## A probe drawing `item` under the test's world at `at`: in `user`'s hand when `held`, else lying along `angle` with `opts`.
static func probe(t: TestContext, item: Item, at: Vector2, held: bool, user: Node = null, angle := 0.0, opts := {}) -> DrawProbe:
	var p := DrawProbe.new()
	p.item = item
	p.user = user
	p.held = held
	p.angle = angle
	p.opts = opts
	p.position = at
	t.world.add_child(p)
	p.queue_redraw()
	return p


## The angles a lying item is drawn along so its art is lit for every one of `ArtConfig.turn_steps` lighting steps (`draw_dropped`
## lights it for its angle less a quarter turn, snapped to a step).
static func every_step() -> Array[float]:
	var out: Array[float] = []
	var step := TAU / maxi(1, ArtConfig.turn_steps)
	for k in maxi(1, ArtConfig.turn_steps):
		out.append(k * step + PI * 0.5)
	return out


## Lay probes for the item in `slot` drawn in weapon `style`, lying at every lighting step with each side up, at `at`; returns them
## (read their union with `union` once they have drawn).
static func lying_everywhere(t: TestContext, slot: int, style: StringName, at: Vector2) -> Array:
	var out: Array = []
	for angle in every_step():
		for flip in [false, true]:
			out.append(probe(t, make(slot, style), at, false, null, angle, { "flip": flip }))
	return out


## The union of what `probes` drew, as a set of texture instance ids.
static func union(probes: Array) -> Dictionary:
	var out := {}
	for p: DrawProbe in probes:
		out.merge(drawn(p.item))
	return out


## Whether every texture in `a` is in `b`.
static func within(a: Dictionary, b: Dictionary) -> bool:
	return a.keys().all(func(k) -> bool: return b.has(k))


## Whether `a` and `b` share no texture.
static func apart(a: Dictionary, b: Dictionary) -> bool:
	return not a.keys().any(func(k) -> bool: return b.has(k))
