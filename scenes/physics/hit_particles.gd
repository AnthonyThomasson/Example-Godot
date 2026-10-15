class_name HitParticles

## Physics System: one-shot particle bursts where a projectile enters and leaves an object, styled by the struck
## surface's material. Stateless statics like DebrisSpawner; each burst is a CPUParticles2D (headless
## safe, deterministic) that frees itself once its particles have died, is placed by world position and
## is Despawner-tracked. Switched by PhysicsConfig.hit_particles_enabled (+ hit_particles_scale / _max).

## ENTRY: where a round goes in and out the other side (weak: the exit carries the burst). EXIT: where it
## leaves (the strongest a burst gets). IMPACT: a hit that does not pass through (blocked, ricochet,
## no exit found): one burst on the surface, as strong as an exit.
enum Kind { ENTRY, EXIT, IMPACT }

## Per-material burst style, keyed by material tag ("default" covers walls and unlisted tags).
##   amount  — particles per burst
##   life    — seconds each particle lives
##   speed   — Vector2(min, max) launch speed (px/s)
##   spread  — half-angle (degrees) of the cone around the burst direction
##   damping — velocity lost per second, so particles slow to a stop rather than fly on
##   size    — Vector2(min, max) square side (px)
##   tint    — how _color() recolors the object's base color
const STYLES := {
	"wood":    { "amount": 8,  "life": 0.45, "speed": Vector2(60, 150),  "spread": 55.0, "damping": 160.0, "size": Vector2(1.5, 3.5), "tint": "wood" },
	"metal":   { "amount": 10, "life": 0.3,  "speed": Vector2(120, 320), "spread": 40.0, "damping": 220.0, "size": Vector2(1.0, 2.0), "tint": "spark" },
	"glass":   { "amount": 12, "life": 0.5,  "speed": Vector2(90, 260),  "spread": 70.0, "damping": 150.0, "size": Vector2(1.0, 2.5), "tint": "glass" },
	"ceramic": { "amount": 9,  "life": 0.45, "speed": Vector2(70, 190),  "spread": 60.0, "damping": 170.0, "size": Vector2(1.5, 3.0), "tint": "light" },
	"fabric":  { "amount": 6,  "life": 0.7,  "speed": Vector2(25, 70),   "spread": 80.0, "damping": 70.0,  "size": Vector2(2.0, 4.0), "tint": "soft" },
	"foliage": { "amount": 8,  "life": 0.6,  "speed": Vector2(40, 110),  "spread": 75.0, "damping": 90.0,  "size": Vector2(1.5, 3.0), "tint": "leaf" },
	"flesh":   { "amount": 10, "life": 0.5,  "speed": Vector2(60, 190),  "spread": 45.0, "damping": 170.0, "size": Vector2(1.5, 3.0), "tint": "blood" },
	"blood":   { "amount": 8,  "life": 0.45, "speed": Vector2(50, 150),  "spread": 60.0, "damping": 170.0, "size": Vector2(1.5, 2.5), "tint": "blood" },
	"default": { "amount": 7,  "life": 0.55, "speed": Vector2(35, 100),  "spread": 65.0, "damping": 110.0, "size": Vector2(1.5, 3.5), "tint": "dust" },
}

## An exit burst (and a lone impact) is the full-strength one: the round tears out what it pushed through.
const EXIT_AMOUNT := 1.4
const EXIT_SPEED := 1.3
const EXIT_SPREAD := 0.75
## A penetrating round's entry burst is a fraction of that: much weaker than the exit.
const ENTRY_AMOUNT := 0.35
const ENTRY_SPEED := 0.6


## Burst `kind` particles at world `position`, thrown along `direction`, under `parent`. `surface` is the
## struck object's get_surface() (its `material` picks the style, its `color` tints it); `strength`
## (~0.5..1.5) scales how many particles and how fast, from how hard the hit was. Returns the emitter
## (null when switched off or the count rounds to nothing).
static func spawn(position: Vector2, direction: Vector2, parent: Node, surface: Dictionary, kind: Kind,
		strength: float = 1.0) -> CPUParticles2D:
	if not PhysicsConfig.hit_particles_enabled:
		return null
	var material: String = surface.get("material", "")
	var style: Dictionary = STYLES.get(material, STYLES["default"])
	var exit := kind == Kind.EXIT
	var strong := kind != Kind.ENTRY
	var amount := int(round(float(style["amount"]) * (EXIT_AMOUNT if strong else ENTRY_AMOUNT) * strength * PhysicsConfig.hit_particles_scale))
	amount = mini(amount, PhysicsConfig.hit_particles_max)
	if amount <= 0:
		return null

	var base: Color = surface.get("color", Color(0.6, 0.6, 0.6))
	var speed: Vector2 = style["speed"]
	var size: Vector2 = style["size"]
	var life: float = style["life"]
	var aim := direction.normalized() if direction.length() > 0.001 else Vector2.UP

	var p := CPUParticles2D.new()
	p.name = "HitParticles"
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = life
	p.lifetime_randomness = 0.4
	p.direction = aim
	p.spread = rad_to_deg(deg_to_rad(float(style["spread"])) * (EXIT_SPREAD if exit else 1.0))
	p.gravity = Vector2.ZERO  # Top-down: nothing falls.
	var boost := (EXIT_SPEED if strong else ENTRY_SPEED) * strength
	p.initial_velocity_min = speed.x * boost
	p.initial_velocity_max = speed.y * boost
	p.damping_min = float(style["damping"]) * 0.8
	p.damping_max = float(style["damping"]) * 1.2
	p.scale_amount_min = size.x
	p.scale_amount_max = size.y
	p.angle_max = 360.0
	var start := _color(base, style["tint"])
	var fade := start
	fade.a = 0.0
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([start, start, fade])
	ramp.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	p.color_ramp = ramp

	p.finished.connect(p.queue_free)
	parent.add_child(p, true)  # readable names (HitParticles, HitParticles2, …)
	p.global_position = position
	p.emitting = true
	Despawner.track(p)
	return p


## A burst colour from the object's base colour per the style's tint mode.
static func _color(base: Color, mode: String) -> Color:
	match mode:
		"spark":
			return Color(1.0, 0.92, 0.65) if randf() < 0.6 else Color(0.75, 0.77, 0.8)
		"glass":
			var g := base.lerp(Color(0.85, 0.92, 1.0), 0.55)
			g.a = 0.8
			return g
		"light":
			return base.lightened(0.25)
		"leaf":
			return base.lerp(Color(0.3, 0.5, 0.2), 0.4)
		"soft":
			return base.lightened(0.08)
		"blood":
			return Color(0.6, 0.05, 0.06)
		"dust":
			return base.lerp(Color(0.75, 0.75, 0.72), 0.55)
		_:  # "wood": the splinters and pale core of the object's own wood
			return base.lightened(0.15)
