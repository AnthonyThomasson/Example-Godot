extends GameTest

## O6 (docs/outfits.md): what a stopped round looks and sounds like. A round stopped by armour leaves no wound (no dent:
## `damage_taken()` stays put), no blood and no exit, still hurts a little (the armour's blunt share), and its `&"hit"` event
## carries the armour's material, which is what the impact is heard as: a steel plate rings as metal, a ceramic plate as
## ceramic, the helmet as its composite, the soft vest as its own fabric, never as flesh. A bare body shot the same way bleeds,
## is dented and is heard as flesh. One round at a time, so each one's blood can be counted.

const OutfitProbe := preload("res://tests/_outfit/outfit_probe.gd")
const SoundProbe := preload("res://tests/_audio/sound_probe.gd")
const TORSO := 40.0
const HEAD := 55.0

## Each lane: what the target wears, the round, its height, and the material the stopped round's hit carries ("" = any but
## flesh: the soft vest's material is its own to name).
const LANES := [
	{ "id": &"steel", "outfit": { "vest": &"plate_carrier", "front_plate": &"steel_iii", "back_plate": &"steel_iii" },
		"gun": &"rifle", "height": TORSO, "material": "metal" },
	{ "id": &"ceramic", "outfit": { "vest": &"plate_carrier", "front_plate": &"ceramic_iv", "back_plate": &"ceramic_iv" },
		"gun": &"rifle", "height": TORSO, "material": "ceramic" },
	{ "id": &"helmet", "outfit": { "head": &"helmet" }, "gun": &"pistol", "height": HEAD, "material": "composite" },
	{ "id": &"vest", "outfit": { "vest": &"tactical_vest" }, "gun": &"pistol", "height": TORSO, "material": "" },
	{ "id": &"bare", "outfit": {}, "gun": &"pistol", "height": TORSO, "material": "flesh" },
]


func describe() -> Dictionary:
	return {
		"name": "A stopped round shows the armour, not a wound",
		"description": "Single rounds into a steel plate, a ceramic plate, a helmet, a soft vest and a bare body: the stopped ones leave no dent, blood or exit, still hurt a little and are heard as metal, ceramic, composite and the vest's material; the bare body bleeds and is heard as flesh.",
		"tags": ["outfit", "armour", "projectile", "sound", "blood"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 400))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.debris", false)
	s.switch(&"physics.blood", true)
	s.switch(&"audio.sound", true)
	s.set_static(SoundConfig, &"category_range", SoundProbe.EVERYWHERE)
	OutfitProbe.pin_height(s)
	OutfitProbe.lay_lanes(s, LANES)


func run(t: TestContext) -> void:
	if not await OutfitProbe.dress(t, LANES):
		return
	for lane: Dictionary in LANES:
		var id: StringName = lane["id"]
		var splats_before := OutfitProbe.splats(t)
		var got: Dictionary = (await OutfitProbe.volley(t, [lane]))[id]
		await t.seconds(0.4)  # the wound's first splatter, if there is one
		var bled := OutfitProbe.splats(t) > splats_before
		var hit: Dictionary = got["hit"]
		var material := str(hit.get("material", ""))
		var target := t.actor(id)
		var heard := SoundProbe.sounds(t, &"impact").filter(func(d): return (d["position"] as Vector2).distance_to(target.global_position) < 30.0)
		var profile := str(heard[-1]["profile"]) if not heard.is_empty() else ""
		if id == &"bare":
			t.check(got["wounded"] and bled and got["through"], "a bare body is dented, bleeds and the round goes through (wounded %s, bled %s, through %s)" % [got["wounded"], bled, got["through"]])
			t.expect_eq(material, "flesh", "a round into a bare body hits flesh")
			t.check(profile.begins_with("impact/flesh/"), "and is heard as flesh (%s)" % profile)
			continue
		t.check(not got["wounded"], "%s: the stopped round leaves no dent or wound" % id)
		t.check(not bled, "%s: the stopped round draws no blood" % id)
		t.check(not got["through"], "%s: the stopped round has no exit" % id)
		t.check(got["lost"] > 0.0, "%s: the stopped round still hurts a little (%.1f)" % [id, got["lost"]])
		if lane["material"] != "":
			t.expect_eq(material, lane["material"], "%s: the stopped round's hit carries the armour's material" % id)
			t.check(profile.begins_with("impact/%s/" % lane["material"]), "%s: and is heard as %s (%s)" % [id, lane["material"], profile])
		else:
			t.check(material != "" and material != "flesh", "%s: the stopped round's hit carries the armour's own material (%s)" % [id, material])
			t.check(profile != "" and not profile.begins_with("impact/flesh/"), "%s: and is not heard as flesh (%s)" % [id, profile])
