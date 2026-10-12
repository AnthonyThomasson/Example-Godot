extends GameTest

## Impacts have weight. Whatever a round hits, even something hard that rings (metal, glass, ceramic), most of the
## sound is a low thump rather than a thin ring, and a heavier round lands harder than a lighter one: its low-end
## energy, counting its louder level, grows light -> medium -> heavy on every material for a round that stops in
## it and one that goes through. So an SMG round is lighter than a pistol round, which is lighter than a rifle's.

const Probe := preload("res://tests/_audio/sound_probe.gd")

## Measured least ~0.57 of a medium impact's energy below 250 Hz (metal, blocked); before the body layer, hard
## materials had a few percent.
const LOW_FLOOR := 0.4
## Measured least step between neighbouring weights is ~1.5x (medium over light) and ~2.1x (heavy over medium).
const LIGHT_TO_MEDIUM := 1.3
const MEDIUM_TO_HEAVY := 1.8

const MATERIALS := ["wood", "metal", "glass", "ceramic", "stone", "plastic", "fabric", "foliage", "electronics", "flesh", "wall", "default"]


func describe() -> Dictionary:
	return {
		"name": "Impacts have body, and heavier rounds hit harder",
		"description": "Every material's impact keeps most of its energy in the low end, and low-end weight rises light -> medium -> heavy for blocked and penetrating rounds.",
		"tags": ["sound", "impact", "weight"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))


func run(t: TestContext) -> void:
	for material in MATERIALS:
		for outcome in ["blocked", "penetrate"]:
			var medium := StringName("impact/%s/%s/medium" % [material, outcome])
			var body := Probe.low_share(Probe.samples(medium))
			t.check(body > LOW_FLOOR, "%s has body (%.2f of its energy under 250 Hz)" % [medium, body])

			var light := Probe.low_weight(StringName("impact/%s/%s/light" % [material, outcome]))
			var mid := Probe.low_weight(medium)
			var heavy := Probe.low_weight(StringName("impact/%s/%s/heavy" % [material, outcome]))
			t.check(mid > light * LIGHT_TO_MEDIUM, "%s/%s: a pistol round hits harder than an SMG round (%.0f vs %.0f)" % [material, outcome, mid, light])
			t.check(heavy > mid * MEDIUM_TO_HEAVY, "%s/%s: a rifle round hits harder than a pistol round (%.0f vs %.0f)" % [material, outcome, heavy, mid])

	# The rifle's deep boom is part of that: only the heavier rounds have a sub layer.
	var light_layers: int = SoundBank.recipe_for(&"impact/wall/blocked/light")["layers"].size()
	var heavy_layers: int = SoundBank.recipe_for(&"impact/wall/blocked/heavy")["layers"].size()
	t.check(heavy_layers > light_layers, "a heavy round has a layer a light one lacks (%d vs %d)" % [heavy_layers, light_layers])
