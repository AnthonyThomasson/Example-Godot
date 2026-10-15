extends GameTest

## O6, O7 (docs/outfits.md): the tactical vest is a soft IIIA panel all round the torso. It stops a pistol round, an SMG round
## and a frag's fragment, from the front and from behind, and does not stop a rifle round. A stopped round has no exit (the
## witness behind is not struck; a fragment never exits flesh anyway), leaves no wound and deals only a small blunt share of
## the same round into a bare torso; a rifle round goes through and wounds. The vest covers the torso only: a pistol round in
## the head or the legs of a vested body is unprotected and goes through.

const OutfitProbe := preload("res://tests/_outfit/outfit_probe.gd")
const VEST := { "vest": &"tactical_vest" }
const TORSO := 40.0

const LANES := [
	{ "id": &"vest_pistol", "outfit": VEST, "gun": &"pistol", "height": TORSO },
	{ "id": &"vest_smg", "outfit": VEST, "gun": &"smg", "height": TORSO },
	{ "id": &"vest_fragment", "outfit": VEST, "gun": &"fragment", "height": TORSO },
	{ "id": &"vest_pistol_back", "outfit": VEST, "gun": &"pistol", "height": TORSO, "facing": Vector2.RIGHT },
	{ "id": &"vest_rifle", "outfit": VEST, "gun": &"rifle", "height": TORSO },
	{ "id": &"vest_pistol_head", "outfit": VEST, "gun": &"pistol", "height": 55.0 },
	{ "id": &"vest_pistol_legs", "outfit": VEST, "gun": &"pistol", "height": 25.0 },
	{ "id": &"bare_pistol", "outfit": {}, "gun": &"pistol", "height": TORSO },
	{ "id": &"bare_smg", "outfit": {}, "gun": &"smg", "height": TORSO },
	{ "id": &"bare_fragment", "outfit": {}, "gun": &"fragment", "height": TORSO },
	{ "id": &"bare_rifle", "outfit": {}, "gun": &"rifle", "height": TORSO },
]


func describe() -> Dictionary:
	return {
		"name": "A soft vest stops pistol, SMG and fragments, not the rifle",
		"description": "Torso-height rounds into vested and bare bodies: the vest stops pistol, SMG and fragment rounds front and back (no exit, no wound, a blunt share), lets a rifle round through, and leaves the head and legs bare.",
		"tags": ["outfit", "armour", "vest", "projectile", "fragment"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 700))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.debris", false)
	OutfitProbe.pin_height(s)
	OutfitProbe.lay_lanes(s, LANES)


func run(t: TestContext) -> void:
	if not await OutfitProbe.dress(t, LANES):
		return
	var got := await OutfitProbe.volley(t, LANES)

	for kind: StringName in [&"pistol", &"smg", &"fragment", &"rifle"]:
		var bare: Dictionary = got[StringName("bare_%s" % kind)]
		t.check(bare["wounded"] and bare["lost"] > 0.0, "a %s round wounds a bare torso (%.1f)" % [kind, bare["lost"]])
	t.check(got[&"bare_pistol"]["through"], "a pistol round goes through a bare body and strikes the witness behind")

	for kind: StringName in [&"pistol", &"smg", &"fragment"]:
		var r: Dictionary = got[StringName("vest_%s" % kind)]
		var bare: float = got[StringName("bare_%s" % kind)]["lost"]
		if kind != &"fragment":  # a fragment never leaves a body, bare or not (too weak to get through flesh)
			t.check(not r["through"], "the vest stops a %s round: nothing comes out behind" % kind)
		t.check(not r["wounded"], "a %s round stopped by the vest leaves no wound" % kind)
		t.check(r["lost"] < bare * 0.5, "it deals only a blunt share of a bare torso shot (%.1f against %.1f)" % [r["lost"], bare])
	var back: Dictionary = got[&"vest_pistol_back"]
	t.check(not back["through"] and not back["wounded"], "the vest goes all round: a pistol round in the back is stopped too")

	var rifle: Dictionary = got[&"vest_rifle"]
	t.check(rifle["through"] and rifle["wounded"], "a rifle round goes through the vest and wounds")
	t.check(rifle["lost"] > float(got[&"bare_rifle"]["lost"]) * 0.5,
		"dealing most of a bare torso shot (%.1f against %.1f)" % [rifle["lost"], got[&"bare_rifle"]["lost"]])

	for zone: String in ["head", "legs"]:
		var r: Dictionary = got[StringName("vest_pistol_%s" % zone)]
		t.check(r["through"] and r["wounded"], "the vest leaves the %s bare: a pistol round there goes through and wounds" % zone)
