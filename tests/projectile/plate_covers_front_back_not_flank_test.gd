extends GameTest

## O4, O7, O8 (docs/outfits.md): a plate carrier holds a front plate and a back plate over its soft panel. The side a round
## strikes is the angle between the way back to the shooter and the shoulders' facing: front up to 60 degrees, back from 120,
## the flank between. A steel III plate stops a rifle round on its own side (front plate: the front, back plate: the back) and
## nowhere else, so a rifle round in the flank goes through the soft panel. A carrier with no plates, or with soft IIIA inserts,
## does not stop a rifle round from the front; its soft panel still stops a pistol round in the flank.
## Every round flies right (+x); the target's facing sets the angle.

const OutfitProbe := preload("res://tests/_outfit/outfit_probe.gd")
const TORSO := 40.0
const STEEL := { "vest": &"plate_carrier", "front_plate": &"steel_iii", "back_plate": &"steel_iii" }
const FRONT_ONLY := { "vest": &"plate_carrier", "front_plate": &"steel_iii", "back_plate": &"" }
const NO_PLATES := { "vest": &"plate_carrier", "front_plate": &"", "back_plate": &"" }
const SOFT_INSERTS := { "vest": &"plate_carrier", "front_plate": &"soft_iiia", "back_plate": &"soft_iiia" }

## The way back to the shooter is -x (`Vector2.LEFT`): a target facing it is struck in the front, one facing (-1, -1) 45
## degrees off it (still the front), up or down in the flank, (1, 1) 135 degrees off (the back) and +x in the back.
const LANES := [
	{ "id": &"steel_front", "outfit": STEEL, "gun": &"rifle", "height": TORSO, "facing": Vector2.LEFT },
	{ "id": &"steel_front_45", "outfit": STEEL, "gun": &"rifle", "height": TORSO, "facing": Vector2(-0.70710678, -0.70710678) },
	{ "id": &"steel_flank", "outfit": STEEL, "gun": &"rifle", "height": TORSO, "facing": Vector2.UP },
	{ "id": &"steel_flank_other", "outfit": STEEL, "gun": &"rifle", "height": TORSO, "facing": Vector2.DOWN },
	{ "id": &"steel_back_135", "outfit": STEEL, "gun": &"rifle", "height": TORSO, "facing": Vector2(0.70710678, 0.70710678) },
	{ "id": &"steel_back", "outfit": STEEL, "gun": &"rifle", "height": TORSO, "facing": Vector2.RIGHT },
	{ "id": &"front_only_back", "outfit": FRONT_ONLY, "gun": &"rifle", "height": TORSO, "facing": Vector2.RIGHT },
	{ "id": &"no_plates_front", "outfit": NO_PLATES, "gun": &"rifle", "height": TORSO, "facing": Vector2.LEFT },
	{ "id": &"soft_inserts_front", "outfit": SOFT_INSERTS, "gun": &"rifle", "height": TORSO, "facing": Vector2.LEFT },
	{ "id": &"no_plates_flank_pistol", "outfit": NO_PLATES, "gun": &"pistol", "height": TORSO, "facing": Vector2.UP },
]


func describe() -> Dictionary:
	return {
		"name": "Plates stop the rifle on their own side only",
		"description": "Rifle rounds into a steel-plated carrier from 0, 45, 90, 135 and 180 degrees off its front: stopped front and back, through at the flank; no plates or soft inserts let the rifle through; the soft panel still stops a pistol in the flank.",
		"tags": ["outfit", "armour", "plate", "side", "projectile"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 650))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.debris", false)
	OutfitProbe.pin_height(s)
	OutfitProbe.lay_lanes(s, LANES)


func run(t: TestContext) -> void:
	if not await OutfitProbe.dress(t, LANES):
		return
	var got := await OutfitProbe.volley(t, LANES)

	for id: StringName in [&"steel_front", &"steel_front_45", &"steel_back_135", &"steel_back"]:
		var r: Dictionary = got[id]
		t.check(not r["through"] and not r["wounded"], "%s: the steel plate on that side stops the rifle round (through %s, wounded %s)" % [id, r["through"], r["wounded"]])
	for id: StringName in [&"steel_flank", &"steel_flank_other"]:
		var r: Dictionary = got[id]
		t.check(r["through"] and r["wounded"], "%s: no plate guards the flank, the rifle round goes through the soft panel (through %s, wounded %s)" % [id, r["through"], r["wounded"]])
	var bare_back: Dictionary = got[&"front_only_back"]
	t.check(bare_back["through"] and bare_back["wounded"], "a front plate does not guard the back: a rifle round there goes through")
	for id: StringName in [&"no_plates_front", &"soft_inserts_front"]:
		var r: Dictionary = got[id]
		t.check(r["through"] and r["wounded"], "%s: without a hard plate a rifle round from the front goes through" % id)
	var pistol: Dictionary = got[&"no_plates_flank_pistol"]
	t.check(not pistol["through"] and not pistol["wounded"], "the carrier's soft panel goes all round: a pistol round in the flank is stopped")
