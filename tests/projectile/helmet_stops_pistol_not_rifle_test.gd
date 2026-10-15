extends GameTest

## O6, O7 (docs/outfits.md): the helmet stops a pistol and an SMG round at the head, not a rifle round. A stopped round has no
## exit (the witness standing behind is not struck), leaves no wound (`damage_taken()` does not rise) and deals only a small
## blunt share of what the same round does to a bare head. A rifle round goes through the helmet and wounds. The helmet guards
## the head only: a pistol round in the torso of a helmeted body is unprotected and goes through.

const OutfitProbe := preload("res://tests/_outfit/outfit_probe.gd")
const HELMET := { "head": &"helmet" }
const HEAD := 55.0
const TORSO := 40.0

const LANES := [
	{ "id": &"helmet_pistol", "outfit": HELMET, "gun": &"pistol", "height": HEAD },
	{ "id": &"helmet_smg", "outfit": HELMET, "gun": &"smg", "height": HEAD },
	{ "id": &"helmet_rifle", "outfit": HELMET, "gun": &"rifle", "height": HEAD },
	{ "id": &"helmet_pistol_torso", "outfit": HELMET, "gun": &"pistol", "height": TORSO },
	{ "id": &"bare_pistol", "outfit": {}, "gun": &"pistol", "height": HEAD },
	{ "id": &"bare_smg", "outfit": {}, "gun": &"smg", "height": HEAD },
	{ "id": &"bare_rifle", "outfit": {}, "gun": &"rifle", "height": HEAD },
]


func describe() -> Dictionary:
	return {
		"name": "A helmet stops a pistol or SMG round, not a rifle round",
		"description": "Head-height pistol, SMG and rifle rounds at helmeted and bare heads: the helmet stops the first two (no exit, no wound, a small blunt share) and lets the rifle through; it does not guard the torso.",
		"tags": ["outfit", "armour", "helmet", "projectile"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.debris", false)
	OutfitProbe.pin_height(s)
	OutfitProbe.lay_lanes(s, LANES)


func run(t: TestContext) -> void:
	if not await OutfitProbe.dress(t, LANES):
		return
	var got := await OutfitProbe.volley(t, LANES)

	for gun: StringName in [&"pistol", &"smg", &"rifle"]:
		t.check(got[StringName("bare_%s" % gun)]["through"], "a %s round goes through a bare head and strikes the witness behind" % gun)
	for gun: StringName in [&"pistol", &"smg"]:
		var r: Dictionary = got[StringName("helmet_%s" % gun)]
		var bare: float = got[StringName("bare_%s" % gun)]["lost"]
		t.check(not r["through"], "the helmet stops a %s round: nothing comes out behind" % gun)
		t.check(not r["wounded"], "a %s round stopped by the helmet leaves no wound" % gun)
		t.check(r["lost"] < bare * 0.5, "it deals only a blunt share of a bare head shot (%.1f against %.1f)" % [r["lost"], bare])
	var rifle: Dictionary = got[&"helmet_rifle"]
	t.check(rifle["through"], "a rifle round goes through the helmet")
	t.check(rifle["wounded"], "and wounds")
	t.check(rifle["lost"] > float(got[&"bare_rifle"]["lost"]) * 0.5,
		"dealing most of a bare head shot (%.1f against %.1f)" % [rifle["lost"], got[&"bare_rifle"]["lost"]])
	var torso: Dictionary = got[&"helmet_pistol_torso"]
	t.check(torso["through"] and torso["wounded"], "the helmet does not guard the torso: a pistol round there goes through and wounds")
