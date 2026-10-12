extends GameTest

## What the bullet does to the surface changes the sound: a round that cannot get through is *blocked* (a dull
## embed), one that glances off something hard *ricochets* (a wall in plaster, a car in metal), and a fist
## *punches*. Each is checked with a real shot or swing, with the ballistics tuned only as far as needed to make
## the outcome certain.

const Probe := preload("res://tests/_audio/sound_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "Blocked, ricochet and punch impacts have their own sounds",
		"description": "A pistol round that cannot penetrate is heard as `blocked`, a glancing one off a wall and a car as `ricochet` (plaster and metal), and fists on a body, a chair and a wall as `punch`.",
		"tags": ["sound", "impact", "ricochet", "punch", "projectile"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 700))
	s.switch(&"projectile.flyover", false)
	s.switch(&"nav.rebake", false)  # shot furniture is shoved into overlaps; re-baking them logs a nav sync error
	s.set_static(SoundConfig, &"category_range", Probe.EVERYWHERE)
	var straight: Dictionary = GunConfig.guns.duplicate(true)
	for gun: StringName in straight:
		straight[gun]["spread_deg"] = 0.0
	s.set_static(GunConfig, &"guns", straight)
	# Glancing shots: one along the north wall, one down the west face of a car in the middle of the room.
	s.actor(&"skimmer", &"puppet", Vector2(100, 100), { "start_slot": 3 })
	s.actor(&"racer", &"puppet", Vector2(300, 100), { "start_slot": 3 })
	s.object(&"car", "car", Vector2(500, 300))
	# Fists: on a body, a chair and the west wall.
	s.actor(&"boxer_body", &"puppet", Vector2(700, 520), { "start_slot": 2 })
	s.actor(&"victim", &"puppet", Vector2(742, 520), { "max_health": 500.0 })
	s.actor(&"boxer_chair", &"puppet", Vector2(700, 620), { "start_slot": 2 })
	s.object(&"chair", "chair", Vector2(742, 620))
	s.actor(&"boxer_wall", &"puppet", Vector2(26, 450), { "start_slot": 2 })


func _first(t: TestContext, near: Vector2, radius: float, kind: StringName = &"impact") -> Dictionary:
	var heard := Probe.sounds(t, kind).filter(func(d): return d["position"].distance_to(near) < radius)
	return heard[0] if not heard.is_empty() else {}


func run(t: TestContext) -> void:
	# --- Ricochets: a long shallow shot at the north wall, and one scraping the car's west face.
	t.puppet(&"skimmer").aim_at(Vector2(700, 6))
	t.puppet(&"racer").aim_at(Vector2(437, 400))
	await t.seconds(0.5)
	t.puppet(&"skimmer").shoot()
	t.puppet(&"racer").shoot()
	await t.seconds(1.0)
	var wall: Dictionary = _first(t, Vector2(700, 6), 60.0)
	if t.check(not wall.is_empty(), "the shot skimming the north wall was heard"):
		t.expect_eq(wall["profile"], &"impact/wall/ricochet/medium", "it ricocheted off the plaster")
	var car: Dictionary = _first(t, Vector2(437, 396), 60.0)
	if t.check(not car.is_empty(), "the shot scraping the car was heard"):
		t.expect_eq(car["profile"], &"impact/metal/ricochet/medium", "it ricocheted off the metal")
	t.check(t.happened(&"hit", func(d): return d["outcome"] == &"ricochet" and d["material"] == "metal"),
		"the hit event itself says ricochet off metal")

	# --- Punches.
	t.puppet(&"boxer_body").aim_at(t.actor(&"victim"))
	t.puppet(&"boxer_chair").aim_at(t.object(&"chair"))
	t.puppet(&"boxer_wall").aim_at(Vector2(-50, 450))
	await t.seconds(0.4)
	for boxer in [&"boxer_body", &"boxer_chair", &"boxer_wall"]:
		t.puppet(boxer).punch()
	await t.seconds(0.8)
	var punches := Probe.sounds(t, &"impact", "impact/").filter(func(d): return String(d["profile"]).ends_with("/punch"))
	t.check(Probe.profiles(punches).has(&"impact/flesh/punch"), "a punch on a body is heard as flesh (%s)" % [Probe.profiles(punches)])
	t.check(Probe.profiles(punches).has(&"impact/wood/punch"), "a punch on a chair as wood")
	t.check(Probe.profiles(punches).has(&"impact/wall/punch"), "a punch on a wall as plaster")
