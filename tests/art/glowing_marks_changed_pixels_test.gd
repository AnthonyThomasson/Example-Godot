extends GameTest

## What a painter draws inside `PixelCanvas.glowing` is marked emissive: exactly the pixels the drawing changed within its
## area, whatever it drew over (a pixel set again to the colour it had is not changed), and `emissive()` hands those pixels
## back as they stand in the art, transparent elsewhere, or null when no glowing drawing changed one. This pins the marks to
## the plain comparison of every pixel before and after each drawing, over drawings that touch a few rows, every row, none,
## and only part of their area.

const SEED := 5151


func describe() -> Dictionary:
	return {
		"name": "A glowing drawing marks exactly the pixels it changed",
		"description": "PixelCanvas.glowing marks the pixels its drawing changed within its area, and emissive() returns them as drawn.",
		"tags": ["art", "emissive", "scripted"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var blank := PixelCanvas.new(20, 10, 1, ArtConfig.light_from)
	blank.glowing(func() -> void: blank.px(3, 3, blank.at(3, 3)))
	t.check(blank.emissive() == null, "a glowing drawing that changed nothing leaves nothing emissive")
	t.check(PixelCanvas.new(20, 10, 1, ArtConfig.light_from).emissive() == null, "a canvas with no glowing drawing has nothing emissive")

	var differing := 0
	for n in 40:
		var c := PixelCanvas.new(rng.randi_range(4, 120), rng.randi_range(4, 90), rng.randi(), ArtConfig.light_from)
		c.fill(PixelCanvas.rounded(Rect2i(1, 1, c.w - 2, c.h - 2), 3), Color(0.4, 0.35, 0.3))
		var marked := PackedByteArray()
		marked.resize(c.w * c.h)
		for _k in rng.randi_range(1, 3):
			var area := Rect2i() if rng.randf() < 0.4 else Rect2i(rng.randi_range(-4, c.w - 2), rng.randi_range(-4, c.h - 2),
				rng.randi_range(1, c.w), rng.randi_range(1, c.h))
			var marks := _drawing(rng, c)
			var before := c.img.duplicate() as Image
			c.glowing(func() -> void: _draw(c, marks), area)
			var r := Rect2i(0, 0, c.w, c.h) if area.size == Vector2i.ZERO else area.intersection(Rect2i(0, 0, c.w, c.h))
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					if before.get_pixel(x, y) != c.img.get_pixel(x, y):
						marked[y * c.w + x] = 1
		if not _same(c, marked):
			differing += 1
			if differing <= 3:
				t.check(false, "canvas %d (%dx%d): the emissive pixels differ from the plain comparison" % [n, c.w, c.h])
	t.check(differing == 0, "%d of 40 canvases mark exactly the changed pixels" % (40 - differing))


## A random drawing as `[x, y, colour]` marks: a few scattered pixels, a whole row, a line down a column, some set again to
## the colour already there (unchanged), some only in alpha.
func _drawing(rng: RandomNumberGenerator, c: PixelCanvas) -> Array:
	var marks: Array = []
	match rng.randi_range(0, 3):
		0:
			for _k in rng.randi_range(1, 12):
				marks.append([rng.randi_range(0, c.w - 1), rng.randi_range(0, c.h - 1), Color(rng.randf(), rng.randf(), rng.randf())])
		1:
			var y := rng.randi_range(0, c.h - 1)
			for x in c.w:
				marks.append([x, y, Color.CYAN])
		2:
			var x := rng.randi_range(0, c.w - 1)
			for y in c.h:
				marks.append([x, y, Color.MAGENTA if y % 2 == 0 else Color(0.4, 0.35, 0.3)])
		3:
			for k in rng.randi_range(1, 8):
				var x := rng.randi_range(0, c.w - 1)
				var y := rng.randi_range(0, c.h - 1)
				marks.append([x, y, c.at(x, y) if k % 2 == 0 else Color(c.at(x, y), 0.5)])
	return marks


func _draw(c: PixelCanvas, marks: Array) -> void:
	for m: Array in marks:
		c.px(m[0], m[1], m[2])


## Whether `emissive()` is the art at the `marked` pixels and transparent elsewhere (null when none is marked).
func _same(c: PixelCanvas, marked: PackedByteArray) -> bool:
	var out := c.emissive()
	if marked.count(1) == 0:
		return out == null
	if out == null or out.get_size() != Vector2i(c.w, c.h):
		return false
	for y in c.h:
		for x in c.w:
			var want := c.img.get_pixel(x, y) if marked[y * c.w + x] == 1 else PixelCanvas.CLEAR
			if out.get_pixel(x, y) != want:
				return false
	return true
