extends GameTest

## O8 (docs/outfits.md): a plate's condition starts at 1 and is worn by every hit it takes (damage / durability), and its stop
## power falls toward the soft panel's as it wears. A ceramic IV plate wears fast: it stops the first rifle round but yields
## after a few. A steel III plate barely wears and stops every one of the same rifle rounds. `outfit_view()` shows each plate's
## condition. Rifle rounds, one at a time, into the front plate of two carriers facing the shooter.

const OutfitProbe := preload("res://tests/_outfit/outfit_probe.gd")
const TORSO := 40.0
## Rifle rounds fired at each plate; the ceramic one yields within them, the steel one holds through all.
const ROUNDS := 8
const LANES := [
	{ "id": &"ceramic", "outfit": { "vest": &"plate_carrier", "front_plate": &"ceramic_iv", "back_plate": &"ceramic_iv" },
		"gun": &"rifle", "height": TORSO },
	{ "id": &"steel", "outfit": { "vest": &"plate_carrier", "front_plate": &"steel_iii", "back_plate": &"steel_iii" },
		"gun": &"rifle", "height": TORSO },
]


func describe() -> Dictionary:
	return {
		"name": "A ceramic plate yields after a few rifle hits, steel holds",
		"description": "Eight rifle rounds one by one into a ceramic IV and a steel III front plate: the ceramic stops the first and lets one through within the eight; the steel stops all; both conditions fall, the ceramic's further.",
		"tags": ["outfit", "armour", "plate", "wear", "projectile"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 300))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.debris", false)
	s.set_static(BloodConfig, &"enabled", false)
	OutfitProbe.pin_height(s)
	OutfitProbe.lay_lanes(s, LANES)


func run(t: TestContext) -> void:
	if not await OutfitProbe.dress(t, LANES):
		return
	for lane: Dictionary in LANES:
		var target := t.actor(lane["id"])
		t.expect_near(OutfitProbe.condition(target, "front_plate"), 1.0, 0.001, "the %s front plate starts in full condition" % lane["id"])

	var first_through := {}  # lane id -> the round (1-based) that first got through
	var conditions := {}  # lane id -> the front plate's condition after each round
	for lane: Dictionary in LANES:
		conditions[lane["id"]] = []
	for n in range(1, ROUNDS + 1):
		var got := await OutfitProbe.volley(t, LANES)
		for lane: Dictionary in LANES:
			var id: StringName = lane["id"]
			if got[id]["through"] and not first_through.has(id):
				first_through[id] = n
			conditions[id].append(OutfitProbe.condition(t.actor(id), "front_plate"))
		await t.seconds(0.2)

	t.check(first_through.get(&"ceramic", 1) > 1, "the ceramic plate stops the first rifle round (first through: %s)" % first_through.get(&"ceramic", "none"))
	t.check(first_through.has(&"ceramic"), "and yields within %d rifle rounds" % ROUNDS)
	t.check(not first_through.has(&"steel"), "the steel plate stops all %d (first through: %s)" % [ROUNDS, first_through.get(&"steel", "none")])

	for lane: Dictionary in LANES:
		var id: StringName = lane["id"]
		var series: Array = conditions[id]
		var falling := true
		for i in range(1, series.size()):
			falling = falling and float(series[i]) <= float(series[i - 1]) + 0.0001
		t.check(falling, "the %s plate's condition never recovers (%s)" % [id, series])
		t.check(float(series[0]) < 1.0 and float(series[0]) >= 0.0, "the %s plate is worn by its first hit (%.3f)" % [id, series[0]])
	var ceramic_left := float(conditions[&"ceramic"][0])
	var steel_left := float(conditions[&"steel"][0])
	t.check(ceramic_left < steel_left, "one rifle hit wears ceramic more than steel (%.3f against %.3f)" % [ceramic_left, steel_left])
