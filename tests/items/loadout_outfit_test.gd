extends GameTest

## O1, O11 (docs/outfits.md): a loadout carries an outfit. `LoadoutConfig.outfit_options()` is the plain data a UI shows: one row
## per slot (head, body, vest, pants, feet, front plate, back plate), each `{ slot, label, choices: [{ id, label }] }`, offering the
## ticket's garments in their own slot only, and an empty choice (`id` &"") exactly where nothing may be worn (head, vest, each
## plate). `normalize` makes a loadout's `outfit` valid (every slot present, body, pants and feet always worn, an unknown or
## misplaced id replaced by a valid one, a valid outfit kept), `apply` dresses the character in it (read back through
## `outfit_view()`: each garment by the label the options give it, each plate as `{ type, condition }`), and `random` draws
## valid outfits, not always the same one (the Endless run's randomised outfits). Plates need a carrier (11b on issue #38): the
## options mark the plate carrier's vest choice, and only it, `plates: true`, and `normalize` clears both plates (`&""`) when the vest
## is not the plate carrier, so a saved setup never carries a plate that does nothing.

const OutfitProbe := preload("res://tests/_outfit/outfit_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "Loadouts carry an outfit",
		"description": "outfit_options() offers each slot's garments (and none where allowed); outfit_options() marks the plate carrier plates: true; normalize keeps a valid outfit, repairs a bad one and clears plates without a carrier; apply dresses the character (outfit_view); random draws varied valid outfits.",
		"tags": ["outfit", "item", "loadout", "setup"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.actor(&"soldier", &"puppet", Vector2(200, 250))


func run(t: TestContext) -> void:
	t.require(OutfitProbe.loadout_has(&"grenade_options"), "the probe reads LoadoutConfig's functions")
	if not t.require(OutfitProbe.loadout_has(&"outfit_options"), "LoadoutConfig.outfit_options() exists (docs/outfits.md O11)"):
		return
	var options := OutfitProbe.options()
	var slots: Array = options.map(func(row): return str(row.get("slot", "")))
	t.expect_eq(slots, Array(OutfitProbe.SLOTS), "one row per slot, in order")
	for row: Dictionary in options:
		var slot := str(row.get("slot", ""))
		t.check(str(row.get("label", "")) != "", "the %s row has a label" % slot)
		var ids: Array = (row.get("choices", []) as Array).map(func(c): return StringName(c.get("id", &"")))
		for garment: StringName in OutfitProbe.GARMENTS.get(slot, []):
			t.check(garment in ids, "%s offers %s (%s)" % [slot, garment, ids])
			t.check(OutfitProbe.label_of(slot, garment) != "", "%s's %s has a label" % [slot, garment])
		t.expect_eq(&"" in ids, slot in OutfitProbe.MAY_BE_EMPTY, "%s offers nothing as a choice only if it may be left empty" % slot)
		for id: StringName in ids:
			t.check(id == &"" or id in OutfitProbe.GARMENTS.get(slot, []), "%s offers only its own garments (%s)" % [slot, id])

	# normalize: a valid outfit is kept, a blank one filled in, a bad one repaired.
	var kept: Dictionary = LoadoutConfig.normalize({ "weapon": &"pistol", "outfit": OutfitProbe.PLATED_KIT }).get("outfit", {})
	for slot: String in OutfitProbe.SLOTS:
		t.expect_eq(StringName(kept.get(slot, &"?")), StringName(OutfitProbe.PLATED_KIT[slot]), "a valid outfit keeps its %s" % slot)
	var plain: Dictionary = LoadoutConfig.normalize({ "weapon": &"pistol", "outfit": OutfitProbe.PLAIN_CLOTHES }).get("outfit", {})
	for slot: String in OutfitProbe.SLOTS:
		t.expect_eq(StringName(plain.get(slot, &"?")), StringName(OutfitProbe.PLAIN_CLOTHES[slot]), "an outfit with nothing on its head, vest and plates keeps its %s" % slot)
	_check_valid(t, LoadoutConfig.normalize({ "weapon": &"pistol" }).get("outfit", {}), "a loadout without an outfit")
	var repaired: Dictionary = LoadoutConfig.normalize({ "weapon": &"pistol", "outfit": {
		"head": &"boots", "body": &"nonsense", "pants": &"", "feet": &"helmet", "front_plate": &"plate_carrier" } }).get("outfit", {})
	_check_valid(t, repaired, "a bad outfit")
	var from_menu: Dictionary = LoadoutConfig.normalize({ "weapon": &"pistol", "outfit": { "head": "helmet", "body": "shirt", "vest": "plate_carrier",
		"pants": "tactical_pants", "feet": "boots", "front_plate": "ceramic_iv", "back_plate": "steel_iii" } }).get("outfit", {})
	t.expect_eq(StringName(from_menu.get("front_plate", &"")), &"ceramic_iv", "plain String ids (the setup window's) are read too")

	# 11b: plates need a carrier. The options mark the vest choice that holds plates; normalize drops plates from any other vest
	# (a valid outfit with the carrier keeps them: PLATED_KIT and from_menu above).
	for row: Dictionary in options:
		for choice: Dictionary in row.get("choices", []):
			var holds := str(row.get("slot", "")) == "vest" and StringName(choice.get("id", &"")) == &"plate_carrier"
			t.expect_eq(bool(choice.get("plates", false)), holds, "%s's %s choice is marked plates: %s" % [row.get("slot"), choice.get("id"), holds])
	for vest: StringName in [&"", &"tactical_vest"]:
		var kit := OutfitProbe.PLATED_KIT.duplicate()
		kit["vest"] = vest
		var cleared: Dictionary = LoadoutConfig.normalize({ "weapon": &"pistol", "outfit": kit }).get("outfit", {})
		var named := "no vest" if vest == &"" else str(vest)
		t.expect_eq([StringName(cleared.get("front_plate", &"?")), StringName(cleared.get("back_plate", &"?"))], [&"", &""],
			"normalize clears both plates with %s" % named)
		t.expect_eq(StringName(cleared.get("vest", &"?")), vest, "and keeps the %s" % named)
		var as_strings := { "head": "helmet", "body": "shirt", "vest": str(vest), "pants": "tactical_pants", "feet": "boots",
			"front_plate": "ceramic_iv", "back_plate": "steel_iii" }
		cleared = LoadoutConfig.normalize({ "weapon": &"pistol", "outfit": as_strings }).get("outfit", {})
		t.expect_eq([StringName(cleared.get("front_plate", &"?")), StringName(cleared.get("back_plate", &"?"))], [&"", &""],
			"normalize clears both plates with %s, from the setup window's String ids" % named)

	# apply: the character wears it.
	var soldier := t.actor(&"soldier")
	if not OutfitProbe.require_api(t, soldier):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	LoadoutConfig.apply(soldier, { "weapon": &"pistol", "outfit": OutfitProbe.PLATED_KIT }, rng)
	var view := OutfitProbe.view(soldier)
	for slot: String in ["head", "body", "vest", "pants", "feet"]:
		t.expect_eq(str(view.get(slot, "?")), OutfitProbe.label_of(slot, OutfitProbe.PLATED_KIT[slot]), "apply dresses the %s (outfit_view)" % slot)
	for side: String in ["front_plate", "back_plate"]:
		var plate: Dictionary = view.get(side, {}) if view.get(side) is Dictionary else {}
		t.expect_eq(StringName(plate.get("type", &"?")), &"steel_iii", "the %s is a steel III plate" % side)
		t.expect_near(float(plate.get("condition", -1.0)), 1.0, 0.001, "in full condition")
	LoadoutConfig.apply(soldier, { "weapon": &"pistol", "outfit": OutfitProbe.PLAIN_CLOTHES }, rng)
	view = OutfitProbe.view(soldier)
	t.expect_eq(str(view.get("head", "?")), "", "a new loadout takes the helmet off: outfit_view shows nothing on the head")
	var bare_plate: Dictionary = view.get("front_plate", {}) if view.get("front_plate") is Dictionary else {}
	t.expect_eq(StringName(bare_plate.get("type", &"?")), &"", "and no front plate")

	# random: always valid, not always the same.
	var seen := {}
	for i in 30:
		var pick := LoadoutConfig.random(rng)
		var outfit: Dictionary = pick.get("outfit", {})
		_check_valid(t, outfit, "random outfit %d" % i)
		seen[str(outfit.get("body", "")) + "/" + str(outfit.get("vest", "")) + "/" + str(outfit.get("head", ""))] = true
	t.check(seen.size() >= 3, "random draws varied outfits (%d different in 30)" % seen.size())


## `outfit` names every slot with an id valid there: body, pants and feet always worn, the rest worn or empty.
func _check_valid(t: TestContext, outfit: Dictionary, what: String) -> void:
	for slot: String in OutfitProbe.SLOTS:
		if not t.check(outfit.has(slot), "%s names its %s (%s)" % [what, slot, outfit]):
			continue
		var id := StringName(outfit[slot])
		var valid: bool = id in OutfitProbe.GARMENTS[slot] or (id == &"" and slot in OutfitProbe.MAY_BE_EMPTY)
		t.check(valid, "%s has a valid %s (%s)" % [what, slot, id])
