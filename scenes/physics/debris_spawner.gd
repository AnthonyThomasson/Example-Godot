class_name DebrisSpawner

const Debris = preload("res://scenes/physics/debris.gd")
const DebrisVisuals = preload("res://scenes/physics/debris_visuals.gd")

## Per-material chip style, keyed by material tag ("default" covers walls and unlisted tags).
##   count    — Vector2i(min, max) chips per hit
##   size     — Vector2(min, max) chip side length (px)
##   aspect   — height/width ratio (< 1 = elongated splinter/shard)
##   shape    — "rect" | "tri" | "circle"
##   spread   — half-angle (radians) of the eject cone around the spray direction
##   distance — Vector2(min, max) eject travel (px)
##   tint     — how _tint() recolors the object's base color
const STYLES := {
	"wood":    { "count": Vector2i(3, 6),  "size": Vector2(3, 7), "aspect": 0.35, "shape": "rect",   "spread": 1.0, "distance": Vector2(16, 30), "tint": "wood" },
	"metal":   { "count": Vector2i(4, 7),  "size": Vector2(2, 5), "aspect": 0.5,  "shape": "tri",    "spread": 1.3, "distance": Vector2(24, 44), "tint": "metal" },
	"glass":   { "count": Vector2i(6, 10), "size": Vector2(2, 5), "aspect": 0.4,  "shape": "tri",    "spread": 1.6, "distance": Vector2(28, 50), "tint": "glass" },
	"ceramic": { "count": Vector2i(4, 7),  "size": Vector2(3, 6), "aspect": 0.7,  "shape": "tri",    "spread": 1.3, "distance": Vector2(20, 38), "tint": "light" },
	"fabric":  { "count": Vector2i(2, 4),  "size": Vector2(4, 7), "aspect": 1.0,  "shape": "rect",   "spread": 0.8, "distance": Vector2(10, 20), "tint": "soft" },
	"foliage": { "count": Vector2i(4, 7),  "size": Vector2(3, 6), "aspect": 0.7,  "shape": "tri",    "spread": 1.4, "distance": Vector2(18, 34), "tint": "leaf" },
	"default": { "count": Vector2i(3, 5),  "size": Vector2(2, 5), "aspect": 1.0,  "shape": "circle", "spread": 1.2, "distance": Vector2(14, 28), "tint": "dust" },
}


## Spray a burst of material-styled chips at world point `position`, thrown roughly along
## `direction`, added under `parent` (placed by global position, so `parent` may be offset
## from the world origin). `base_color` / `material` come from the struck object's surface
## and drive each chip's tint, count, shape and throw.
static func spawn(position: Vector2, direction: Vector2, parent: Node, base_color: Color, material: String) -> void:
	var style: Dictionary = STYLES.get(material, STYLES["default"])
	var spray := direction.normalized() if direction.length() > 0.001 else Vector2.UP
	var count: Vector2i = style["count"]
	var size_range: Vector2 = style["size"]
	var dist_range: Vector2 = style["distance"]
	var aspect: float = style["aspect"]
	var spread: float = style["spread"]

	for _i in randi_range(count.x, count.y):
		var chip := Node2D.new()
		chip.name = "Debris"
		chip.script = Debris
		chip.color = _tint(base_color, style["tint"])
		var side := randf_range(size_range.x, size_range.y)
		chip.chip_size = Vector2(side, side * aspect)
		chip.chip_shape = style["shape"]
		chip.eject_distance = randf_range(dist_range.x, dist_range.y)

		var visuals := Node2D.new()
		visuals.name = "DebrisVisuals"
		visuals.script = DebrisVisuals
		chip.add_child(visuals)

		parent.add_child(chip)
		# `position` is a world contact point; place the chip there regardless of the
		# parent's transform (a wall/furniture parent is offset from the world origin).
		chip.global_position = position
		Despawner.track(chip)

		var eject := spray.rotated(randf_range(-spread, spread)) * randf_range(0.5, 1.0)
		chip.start(eject)


## Derive a chip color from the object's base color per the style's tint mode.
static func _tint(base: Color, mode: String) -> Color:
	var jitter := randf_range(0.04, 0.12)
	match mode:
		"metal":
			if randf() < 0.3:
				return Color(1.0, 0.92, 0.65)  # occasional bright spark
			return base.lerp(Color(0.55, 0.57, 0.6), 0.6).lightened(randf_range(0.0, 0.15))
		"glass":
			var g := base.lerp(Color(0.85, 0.92, 1.0), 0.55)
			g.a = 0.7
			return g
		"light":
			return base.lightened(randf_range(0.1, 0.3))
		"leaf":
			return base.lerp(Color(0.3, 0.5, 0.2), 0.4).lightened(randf_range(-0.05, 0.1))
		"soft":
			return base.darkened(randf_range(0.0, 0.12))
		"dust":
			return Color(0.6, 0.6, 0.6).lightened(randf_range(-0.15, 0.15))
		_:  # "wood" and anything else: keep the object color with lightness jitter
			return base.lightened(jitter) if randf() > 0.5 else base.darkened(jitter)
