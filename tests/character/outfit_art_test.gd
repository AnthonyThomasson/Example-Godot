extends GameTest

## O12 (docs/outfits.md): every garment changes how the body is drawn, standing and fallen. The drawing is read through
## `Visuals.drawn_art()`: the textures the body's last draw painted (pixel art is cached by what it depicts, so the same drawing
## gives the same textures and a changed part a new one).
## - Standing: from plain clothes, putting on a hat, a helmet instead, a shirt instead of the t-shirt, a tactical vest, a plate
##   carrier, tactical pants and boots each paint something the plain body never painted (sampled before and after each one).
## - A worn plate repaints: rifle rounds into a ceramic front plate paint a drawing the new plate never had (its cracks).
## - Crouched (drawn from the same folded trunk as a fallen body): a shirt, tactical pants and a vest each paint something the
##   crouched plain body never painted, and a plate carrier shows on the folded back as well as round the neck (two of its
##   textures are painted in the carrier's colour: the back's and the shoulders').
## - Fallen: a body that died in a plate carrier shows it; with the carrier taken off as it lies its drawing changes, and with
##   the carrier put back its drawing is the one it had in the carrier.

const OutfitProbe := preload("res://tests/_outfit/outfit_probe.gd")
## Frames each drawing is sampled over (the standing body breathes, so its textures are gathered over a while).
const SAMPLE_FRAMES := 20
## The garments a crouched body is checked in (its legs, sleeves and folded back).
const CROUCHED_CHANGES := [
	["a shirt", { "body": &"shirt" }],
	["a tactical vest", { "vest": &"tactical_vest" }],
	["tactical pants", { "pants": &"tactical_pants" }],
]
## Pixels of a garment's colour a texture needs before it counts as painting that garment (the shoulders' art of a carrier
## holds about 30, a trunk face's panel hundreds).
const GARMENT_PIXELS := 20
const CHANGES := [
	["a hat", { "head": &"hat" }],
	["a helmet", { "head": &"helmet" }],
	["a shirt", { "body": &"shirt" }],
	["a tactical vest", { "vest": &"tactical_vest" }],
	["a plate carrier", { "vest": &"plate_carrier" }],
	["tactical pants", { "pants": &"tactical_pants" }],
	["boots", { "feet": &"boots" }],
]


func describe() -> Dictionary:
	return {
		"name": "Each garment changes the drawing",
		"description": "Every garment paints something plain clothes never do; a ceramic plate worn by rifle rounds repaints; a body fallen in a plate carrier is drawn with it, and differently without it.",
		"tags": ["outfit", "art", "character", "fallen"],
		"timeout": 24.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.debris", false)
	s.set_static(BloodConfig, &"enabled", false)
	OutfitProbe.pin_height(s)
	s.actor(&"model", &"puppet", Vector2(250, 200), { "facing": Vector2.DOWN, "aim_point": Vector2(250, 900) })
	s.actor(&"plated", &"puppet", Vector2(OutfitProbe.TARGET_X, 120), { "max_health": 10000.0, "facing": Vector2.LEFT, "aim_point": Vector2(0, 120) })
	# The camera stops framing a body once it is dead, and a body out of its view is not drawn (its drawing could not change):
	# the fallen one lies inside the view the two living actors keep framed (headless, the smallest one: 160 px plus the cull margin).
	s.actor(&"fallen", &"puppet", Vector2(450, 280), { "max_health": 10.0 })
	s.actor(&"crouched", &"puppet", Vector2(380, 380), { "facing": Vector2.RIGHT, "aim_point": Vector2(900, 380) })
	s.camera_follow([&"model", &"plated", &"fallen", &"crouched"])


func run(t: TestContext) -> void:
	var model := t.actor(&"model")
	if not OutfitProbe.require_api(t, model):
		return
	if not t.require(OutfitProbe.can_read_art(model), "Visuals.drawn_art() reads the textures the body's last draw painted"):
		return
	t.puppet(&"model").aim_at(Vector2(250, 900))
	t.puppet(&"plated").aim_at(Vector2(0, 120))

	# Standing: each garment against plain clothes.
	OutfitProbe.wear(model, OutfitProbe.PLAIN_CLOTHES)
	await t.seconds(0.5)
	var plain := await _sample(t, model)
	t.require(not plain.is_empty(), "the plain body is drawn")
	for change: Array in CHANGES:
		OutfitProbe.wear(model, OutfitProbe.PLAIN_CLOTHES.merged(change[1], true))
		var worn := await _sample(t, model)
		OutfitProbe.wear(model, OutfitProbe.PLAIN_CLOTHES)
		var back := await _sample(t, model)
		plain.merge(back)  # the plain body as it breathes, drawn before and after
		t.check(not _new_in(worn, plain).is_empty(), "%s paints something plain clothes never do" % change[0])

	# Crouched: the folded trunk and the limbs carry the outfit too.
	t.puppet(&"model").set_posture(&"crouch")
	OutfitProbe.wear(model, OutfitProbe.PLAIN_CLOTHES)
	await t.seconds(1.0)
	var crouched_plain := await _sample(t, model)
	for change: Array in CROUCHED_CHANGES:
		OutfitProbe.wear(model, OutfitProbe.PLAIN_CLOTHES.merged(change[1], true))
		var worn := await _sample(t, model)
		OutfitProbe.wear(model, OutfitProbe.PLAIN_CLOTHES)
		crouched_plain.merge(await _sample(t, model))
		t.check(not _new_in(worn, crouched_plain).is_empty(), "crouched, %s paints something plain clothes never do" % change[0])
	var crouched := t.actor(&"crouched")
	t.puppet(&"crouched").aim_at(Vector2(900, 380))
	t.puppet(&"crouched").set_posture(&"crouch")
	OutfitProbe.wear(crouched, OutfitProbe.PLAIN_CLOTHES.merged({ "vest": &"plate_carrier", "front_plate": &"steel_iii", "back_plate": &"steel_iii" }, true))
	await t.seconds(1.0)
	var carrier_color: Color = OutfitConfig.garment(&"plate_carrier")["look"]["color"]
	var in_carrier := _painted_in(crouched, carrier_color)
	t.check(in_carrier >= 2, "crouched, the plate carrier shows on the folded back as well as round the neck (textures in its colour: %d)" % in_carrier)

	# A worn plate repaints.
	var plated := t.actor(&"plated")
	OutfitProbe.wear(plated, { "vest": &"plate_carrier", "front_plate": &"ceramic_iv", "back_plate": &"ceramic_iv" })
	await t.seconds(0.5)
	var new_plate := await _sample(t, plated)
	for i in 3:
		OutfitProbe.fire(t, Vector2(OutfitProbe.FROM_X, plated.global_position.y), Vector2.RIGHT, &"rifle", 40.0)
		await t.seconds(0.3)
	t.check(OutfitProbe.condition(plated, "front_plate") < 1.0, "three rifle rounds wear the ceramic front plate (%.2f)" % OutfitProbe.condition(plated, "front_plate"))
	await t.seconds(0.5)
	var worn_plate := await _sample(t, plated)
	t.check(not _new_in(worn_plate, new_plate).is_empty(), "the worn plate repaints: its drawing has something the new plate's never had")

	# Fallen: the vest is drawn on the body where it lies.
	var fallen := t.actor(&"fallen")
	var carrier := OutfitProbe.PLAIN_CLOTHES.merged({ "vest": &"plate_carrier", "front_plate": &"steel_iii", "back_plate": &"steel_iii" }, true)
	OutfitProbe.wear(fallen, carrier)
	await t.seconds(0.3)
	fallen.take_damage(100.0)
	if not t.require(await t.until(func(): return fallen.ragdoll != null and fallen.ragdoll.is_settled(), 6.0), "the body falls and comes to rest"):
		return
	await t.seconds(0.3)
	var lying := OutfitProbe.art(fallen)
	t.require(not lying.is_empty(), "the fallen body is drawn")
	OutfitProbe.wear(fallen, OutfitProbe.PLAIN_CLOTHES)
	await t.seconds(0.3)
	var stripped := OutfitProbe.art(fallen)
	t.check(stripped != lying, "the fallen body is drawn differently without its plate carrier")
	OutfitProbe.wear(fallen, carrier)
	await t.seconds(0.3)
	t.check(OutfitProbe.art(fallen) == lying, "and with it back on, the drawing it had in the carrier: the difference is the carrier")


## Every texture `c`'s body paints over `SAMPLE_FRAMES` frames, as a set (instance id -> true).
func _sample(t: TestContext, c: Node) -> Dictionary:
	var seen := {}
	for i in SAMPLE_FRAMES:
		await t.frames(1)
		for id in OutfitProbe.art(c):
			seen[id] = true
	return seen


## The textures in `drawn` that are not in `before`.
func _new_in(drawn: Dictionary, before: Dictionary) -> Array:
	return drawn.keys().filter(func(id): return not before.has(id))


## How many of the textures `c`'s body last painted hold at least `GARMENT_PIXELS` pixels of `color` (a garment's base colour,
## as the painters fill it before shading and weave).
func _painted_in(c: Node, color: Color) -> int:
	var count := 0
	for tex in OutfitProbe.visuals(c).call("drawn_art"):
		var img: Image = (tex as Texture2D).get_image()
		if img == null:
			continue
		var hits := 0
		for y in img.get_height():
			for x in img.get_width():
				var p := img.get_pixel(x, y)
				if p.a > 0.5 and absf(p.r - color.r) < 0.01 and absf(p.g - color.g) < 0.01 and absf(p.b - color.b) < 0.01:
					hits += 1
		if hits >= GARMENT_PIXELS:
			count += 1
	return count
