class_name ExplosionFx

## Physics System: the look of a grenade's burst (`Physics.spawn_explosion`). A frag is a bright flash, a fireball puff that
## swells and cools, smoke that drifts off and fades, and a scorch left on the floor; a stun is a white flash and thin smoke.
## Each is one colliderless node that draws itself in stepped rows of `PhysicsConfig.explosion_pixel` px (the pixel look of the
## debris and the blood), animates in `_process` and frees itself when its life is over, Despawner-tracked. The scorch is a mark
## in the world's `ScorchDecals` layer. Looks and timings: `PhysicsConfig.explosion_looks`.

## Draw order of the flash, fireball and smoke: above the living.
const Z_INDEX := 4
## The fireball cools through these as it ages: white-yellow core, orange, deep red.
const FIRE_CORE := Color(1.0, 0.92, 0.5)
const FIRE_MID := Color(1.0, 0.55, 0.12)
const FIRE_EDGE := Color(0.72, 0.16, 0.06)
## Lumps in the fireball, and how far from its centre (share of its radius) they sit.
const LOBES := 6
const LOBE_REACH := 0.45


## Put the burst of `kind` at `at` under `world`.
static func spawn(world: Node, at: Vector2, kind: StringName) -> void:
	var look: Dictionary = PhysicsConfig.explosion_looks.get(kind, {})
	if look.is_empty():
		return
	if float(look.get("flash_radius", 0.0)) > 0.0:
		_add(world, Flash.new(), "ExplosionFlash", at, look)
	if float(look.get("fireball_radius", 0.0)) > 0.0:
		_add(world, Fireball.new(), "ExplosionFireball", at, look)
	if int(look.get("smoke_puffs", 0)) > 0:
		_add(world, Smoke.new(), "ExplosionSmoke", at, look)
	if float(look.get("scorch_radius", 0.0)) > 0.0:
		ScorchDecals.layer(world).burn(at, float(look["scorch_radius"]))


## Put effect node `fx` under `world` at `at`, named `node_name`, carrying `look` and tracked by the `Despawner`.
static func _add(world: Node, fx: Node2D, node_name: String, at: Vector2, look: Dictionary) -> void:
	fx.name = node_name
	fx.set("look", look)
	fx.z_index = Z_INDEX
	world.add_child(fx)
	fx.global_position = at
	Despawner.track(fx)


## A disc of `radius` px about `center` drawn as rows of `step` px, so it has the stepped edge of the rest of the art.
static func pixel_disc(canvas: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	var step := maxf(PhysicsConfig.explosion_pixel, 1.0)
	var rows := int(ceil(radius / step))
	for j in range(-rows, rows):
		var y := (float(j) + 0.5) * step
		var cells := roundi(sqrt(maxf(radius * radius - y * y, 0.0)) / step)
		if cells > 0:
			canvas.draw_rect(Rect2(center + Vector2(-cells * step, j * step), Vector2(2.0 * cells * step, step)), color)


## One timed effect: ages in `_process`, redraws and frees itself at the end of its `life`.
class Timed:
	extends Node2D

	var look: Dictionary
	var age := 0.0
	var life := 1.0

	## 0..1 through its life.
	func progress() -> float:
		return clampf(age / maxf(life, 0.001), 0.0, 1.0)

	func _process(delta: float) -> void:
		age += delta
		if age >= life:
			queue_free()
			return
		queue_redraw()


## The flash: a pale disc over a white one that fades fast and swells a little.
class Flash:
	extends Timed

	func _ready() -> void:
		life = float(look["flash_time"])

	func _draw() -> void:
		var t := progress()
		var fade := pow(1.0 - t, 1.5)
		var radius := float(look["flash_radius"]) * (0.7 + 0.3 * t)
		var tint: Color = look["flash_color"]
		ExplosionFx.pixel_disc(self, Vector2.ZERO, radius, Color(tint.r, tint.g, tint.b, 0.55 * fade))
		ExplosionFx.pixel_disc(self, Vector2.ZERO, radius * 0.6, Color(1.0, 1.0, 1.0, fade))


## The fireball: a lumpy puff that swells quickly, cooling from a yellow core to deep red, and fades over its last stretch.
class Fireball:
	extends Timed

	var _lobes: Array[Vector2] = []  ## Direction of each lump, and (y) how big it is as a share of the fireball.

	func _ready() -> void:
		life = float(look["fireball_time"])
		var turn := randf() * TAU
		for i in LOBES:
			_lobes.append(Vector2(turn + TAU * float(i) / float(LOBES) + randf_range(-0.3, 0.3), randf_range(0.5, 0.7)))

	func _draw() -> void:
		var t := progress()
		var radius := float(look["fireball_radius"]) * (1.0 - pow(1.0 - t, 2.5)) * 0.9 + 6.0
		var alpha := clampf((1.0 - t) / 0.45, 0.0, 1.0)
		var rim := Color(FIRE_EDGE.r, FIRE_EDGE.g, FIRE_EDGE.b, alpha)
		var body := FIRE_MID.lerp(FIRE_EDGE, t)
		var core := FIRE_CORE.lerp(FIRE_MID, t)
		body.a = alpha
		core.a = alpha
		for lobe in _lobes:
			ExplosionFx.pixel_disc(self, Vector2.from_angle(lobe.x) * radius * LOBE_REACH, radius * lobe.y, rim)
		ExplosionFx.pixel_disc(self, Vector2.ZERO, radius * 0.85, body)
		ExplosionFx.pixel_disc(self, Vector2.ZERO, radius * (0.5 - 0.3 * t), core)


## The smoke: puffs that drift out from the burst, swell and fade, one lighter patch on each to round it.
class Smoke:
	extends Timed

	var _puffs: Array[Dictionary] = []  ## { at, drift, size (share of smoke_radius), delay (share of life) }

	func _ready() -> void:
		life = float(look["smoke_time"])
		var radius := float(look["smoke_radius"])
		for i in int(look["smoke_puffs"]):
			var way := Vector2.from_angle(randf() * TAU)
			_puffs.append({
				"at": way * radius * randf_range(0.2, 0.9), "drift": way * radius * randf_range(0.3, 0.8) + Vector2(randf_range(-6.0, 6.0), -10.0),
				"size": randf_range(0.6, 1.0), "delay": randf_range(0.0, 0.12),
			})

	func _draw() -> void:
		var tint: Color = look["smoke_color"]
		var alpha := float(look["smoke_alpha"])
		var radius := float(look["smoke_radius"])
		for puff: Dictionary in _puffs:
			var t := clampf((progress() - float(puff["delay"])) / (1.0 - float(puff["delay"])), 0.0, 1.0)
			if t <= 0.0:
				continue
			var at: Vector2 = puff["at"] + (puff["drift"] as Vector2) * (1.0 - pow(1.0 - t, 2.0))
			var size := radius * float(puff["size"]) * (0.4 + 0.6 * sqrt(t))
			var fade := alpha * minf(t / 0.1, 1.0) * (1.0 - t)
			ExplosionFx.pixel_disc(self, at, size, Color(tint.r, tint.g, tint.b, fade))
			ExplosionFx.pixel_disc(self, at + Vector2(-size, -size) * 0.2, size * 0.55, Color(tint.r + 0.1, tint.g + 0.1, tint.b + 0.1, fade * 0.8))
