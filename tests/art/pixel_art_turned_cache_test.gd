extends GameTest

## `PixelArt.render_turned` shares one texture between calls that mean the same art, however their arguments were built:
## equal values passed as new objects, and an angle that differs below the four decimals the cache key keeps. A different
## colour, material, option or angle is a different texture, and an options dictionary changed after the call does not
## change what was cached.

const Painter := preload("res://scenes/character/body/hand_painter.gd")
const SIZE := Vector2(14, 14)
const COLOR := Color(0.93, 0.76, 0.6)


func describe() -> Dictionary:
	return {
		"name": "Turned pixel art is cached by what it depicts",
		"description": "render_turned returns the same texture for equal inputs and a different one when any input differs.",
		"tags": ["art", "cache", "scripted"],
		"timeout": 5.0,
	}


func run(t: TestContext) -> void:
	var first := PixelArt.render_turned(Painter, SIZE, COLOR, 1.5, "", { "side": -1 })
	t.check(first != null, "a texture is rendered")
	t.check(PixelArt.render_turned(Painter, Vector2(14, 14), Color(0.93, 0.76, 0.6), 1.5, "", { "side": -1 }) == first,
		"equal inputs passed as new objects share one texture")
	t.check(PixelArt.render_turned(Painter, SIZE, COLOR, 1.5 + 0.00001, "", { "side": -1 }) == first,
		"an angle that differs below the key's precision is the same texture")
	t.check(PixelArt.render_turned(Painter, SIZE, COLOR, 1.6, "", { "side": -1 }) != first, "another angle is another texture")
	t.check(PixelArt.render_turned(Painter, SIZE, COLOR, 1.5, "", { "side": 1 }) != first, "another option is another texture")
	t.check(PixelArt.render_turned(Painter, SIZE, COLOR, 1.5, "fabric", { "side": -1 }) != first, "another material is another texture")
	t.check(PixelArt.render_turned(Painter, SIZE, Color(0.2, 0.3, 0.4), 1.5, "", { "side": -1 }) != first, "another colour is another texture")
	t.check(PixelArt.render_turned(Painter, Vector2(16, 16), COLOR, 1.5, "", { "side": -1 }) != first, "another size is another texture")

	var opts := { "side": -1 }
	var left := PixelArt.render_turned(Painter, SIZE, COLOR, 2.0, "", opts)
	opts["side"] = 1
	var right := PixelArt.render_turned(Painter, SIZE, COLOR, 2.0, "", opts)
	t.check(left != right, "an options dictionary changed after a call is read afresh by the next one")
	t.check(PixelArt.render_turned(Painter, SIZE, COLOR, 2.0, "", { "side": -1 }) == left, "the first texture is still what its options ask for")
	t.check(PixelArt.render_turned(Painter, SIZE, COLOR, 2.0, "", { "side": 1 }) == right, "and so is the second")
