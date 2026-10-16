extends GameTest

## The setup window's three start buttons each report their mode with the chosen side and each side's
## count and loadout; a weapon without a gun hides its magazine rows. Each side also picks an outfit (O11 in
## docs/outfits.md): one dropdown per slot (`Outfit_<slot>` in the side's column) from the plain `outfits` rows Main
## passes (`LoadoutConfig.outfit_options()`'s shape), reported as the side's `outfit` (`{ <slot>: id }`, "" for nothing)
## and restored from the side's seeded `outfit`. Plates need a carrier (11b on issue #38): the vest choice that holds plates comes
## marked `plates: true`, and while a side's vest pick is any other its two plate picks are disabled, show "None" and report "".
## "Lead the team" (LD10 in docs/leadership.md): a checkbox, off by default, reported as the config's `lead` by
## `current_config()` and Start, and restored from a remembered config.

const SetupMenu := preload("res://scenes/ui/menus/setup_menu.gd")

const WEAPONS := [
	{ "id": "pistol", "label": "Pistol", "magazines": [{ "id": "standard", "label": "Standard" }, { "id": "extended", "label": "Extended" }] },
	{ "id": "fists", "label": "Fists", "magazines": [] },
]

## The outfit rows as Main passes them (`LoadoutConfig.outfit_options()`'s shape, plain data).
const OUTFITS := [
	{ "slot": "head", "label": "Head", "choices": [{ "id": "", "label": "None" }, { "id": "hat", "label": "Hat" }, { "id": "helmet", "label": "Helmet" }] },
	{ "slot": "body", "label": "Body", "choices": [{ "id": "tshirt", "label": "T-shirt" }, { "id": "shirt", "label": "Shirt" }] },
	{ "slot": "vest", "label": "Vest", "choices": [{ "id": "", "label": "None" }, { "id": "tactical_vest", "label": "Tactical vest" },
		{ "id": "plate_carrier", "label": "Plate carrier", "plates": true }] },
	{ "slot": "pants", "label": "Pants", "choices": [{ "id": "jeans", "label": "Jeans" }, { "id": "tactical_pants", "label": "Tactical pants" }] },
	{ "slot": "feet", "label": "Feet", "choices": [{ "id": "shoes", "label": "Shoes" }, { "id": "boots", "label": "Boots" }] },
	{ "slot": "front_plate", "label": "Front plate", "plate": true, "choices": [{ "id": "", "label": "None" }, { "id": "soft_iiia", "label": "Soft IIIA" },
		{ "id": "steel_iii", "label": "Steel III" }, { "id": "ceramic_iv", "label": "Ceramic IV" }] },
	{ "slot": "back_plate", "label": "Back plate", "plate": true, "choices": [{ "id": "", "label": "None" }, { "id": "soft_iiia", "label": "Soft IIIA" },
		{ "id": "steel_iii", "label": "Steel III" }, { "id": "ceramic_iv", "label": "Ceramic IV" }] },
]
const PLAIN := { "head": "", "body": "tshirt", "vest": "", "pants": "jeans", "feet": "shoes", "front_plate": "", "back_plate": "" }
const PLATED := { "head": "helmet", "body": "shirt", "vest": "plate_carrier", "pants": "tactical_pants", "feet": "boots",
	"front_plate": "steel_iii", "back_plate": "ceramic_iv" }

const COLUMNS: Array[String] = ["DefendersColumn", "InvadersColumn"]
const SIDES: Array[String] = ["defenders", "invaders"]
## Seeds that name plates without a carrier: the defenders with no vest, the invaders with the tactical vest.
const NO_VEST_PLATES := { "head": "", "body": "tshirt", "vest": "", "pants": "jeans", "feet": "shoes",
	"front_plate": "steel_iii", "back_plate": "ceramic_iv" }
const SOFT_VEST_PLATES := { "head": "helmet", "body": "shirt", "vest": "tactical_vest", "pants": "tactical_pants", "feet": "boots",
	"front_plate": "ceramic_iv", "back_plate": "steel_iii" }


func describe() -> Dictionary:
	return {
		"name": "Setup window reports mode, side and loadouts",
		"description": "Start / Watch / Endless emit their mode with the chosen side, counts, weapons, magazines, spares and outfits; a gunless weapon hides the magazine rows; each side picks a garment per slot; the plate picks are disabled and none without the plate carrier; \"Lead the team\" is off by default and reported as lead.",
		"tags": ["setup", "ui", "outfit", "leadership"],
		"timeout": 5.0,
	}


func _press(t: TestContext, mode_button: String) -> Dictionary:
	var menu := SetupMenu.new()
	t.world.add_child(menu)
	menu.open({
		"side": "invader", "seed": 42,
		"defenders": { "count": 2, "weapon": "fists" },
		"invaders": { "count": 3, "weapon": "pistol", "magazine": "extended", "spares": 1 },
		"weapons": WEAPONS,
	})
	var got := []
	menu.start_requested.connect(func(c): got.append(c))
	(menu.find_child(mode_button, true, false) as Button).pressed.emit()
	menu.queue_free()
	return got[0] if not got.is_empty() else {}


func run(t: TestContext) -> void:
	var play := _press(t, "StartButton")
	t.expect_eq(play.get("mode"), "play", "Start plays")
	t.expect_eq(play.get("side"), "invader", "as the chosen side")
	t.expect_eq(play.get("seed"), 42, "the seed is passed")
	t.expect_eq(play["defenders"]["count"], 2, "defender count")
	t.expect_eq(play["defenders"]["weapon"], "fists", "defender weapon")
	t.expect_eq(play["defenders"]["magazine"], "", "a gunless weapon has no magazine")
	t.expect_eq(play["invaders"]["count"], 3, "invader count")
	t.expect_eq(play["invaders"]["weapon"], "pistol", "invader weapon")
	t.expect_eq(play["invaders"]["magazine"], "extended", "invader magazine")
	t.expect_eq(play["invaders"]["spares"], 1, "invader spares")
	t.expect_eq(_press(t, "WatchButton").get("mode"), "watch", "Watch watches")
	t.expect_eq(_press(t, "EndlessButton").get("mode"), "endless", "Endless goes endless")

	# current_config() is what the window shows right now, and reopening with it restores the same choices.
	var first := SetupMenu.new()
	t.world.add_child(first)
	first.open({ "side": "invader", "seed": 42, "defenders": { "count": 2, "weapon": "fists" },
		"invaders": { "count": 3, "weapon": "pistol", "magazine": "extended", "spares": 1 }, "weapons": WEAPONS })
	var kept: Dictionary = first.current_config()
	first.queue_free()
	t.check(not kept.has("mode"), "the remembered config carries no start mode")
	var second := SetupMenu.new()
	t.world.add_child(second)
	second.open(kept.merged({ "weapons": WEAPONS }))
	t.expect_eq(second.current_config(), kept, "reopening with a remembered config restores every choice")
	second.queue_free()

	# Without weapon choices (an older caller) the window still works and reports plain counts.
	var bare := SetupMenu.new()
	t.world.add_child(bare)
	bare.open({ "defenders": 4 })
	var got := []
	bare.start_requested.connect(func(c): got.append(c))
	(bare.find_child("StartButton", true, false) as Button).pressed.emit()
	t.expect_eq(got[0]["defenders"], { "count": 4 }, "no weapon rows without choices")

	_check_outfits(t)
	_check_plates(t)
	_check_lead(t)


## LD10: the "Lead the team" checkbox: off by default, reported as `lead`, restored on reopening.
func _check_lead(t: TestContext) -> void:
	var menu := SetupMenu.new()
	t.world.add_child(menu)
	menu.open({ "side": "invader", "seed": 42, "weapons": WEAPONS, "defenders": { "count": 2, "weapon": "pistol" },
		"invaders": { "count": 3, "weapon": "pistol" } })
	var box := _lead_box(menu)
	if not t.check(box != null, "the window has a \"Lead the team\" checkbox"):
		menu.queue_free()
		return
	t.check(not box.button_pressed, "it is off by default")
	t.expect_eq(menu.current_config().get("lead"), false, "current_config reports lead off by default")
	box.button_pressed = true
	box.toggled.emit(true)
	t.expect_eq(menu.current_config().get("lead"), true, "ticked, current_config reports lead on")
	var started := _start(menu)
	t.expect_eq(started.get("lead"), true, "Start reports lead on")
	t.expect_eq(started.get("mode"), "play", "for a played match")
	var kept: Dictionary = menu.current_config()
	menu.queue_free()
	var again := SetupMenu.new()
	t.world.add_child(again)
	again.open(kept.merged({ "weapons": WEAPONS }))
	var reopened := _lead_box(again)
	t.check(reopened != null and reopened.button_pressed, "reopening with the remembered config ticks it again")
	t.expect_eq(again.current_config().get("lead"), true, "and reports lead on")
	again.queue_free()


## The window's "Lead the team" checkbox (a CheckBox or CheckButton showing that text), or null.
func _lead_box(menu: Node) -> BaseButton:
	for b: BaseButton in menu.find_children("*", "BaseButton", true, false):
		if (b is CheckBox or b is CheckButton) and String(b.text).to_lower().contains("lead the team"):
			return b
	return null


## O11: the per-side outfit picks.
func _check_outfits(t: TestContext) -> void:
	var menu := SetupMenu.new()
	t.world.add_child(menu)
	menu.open({ "side": "invader", "seed": 7, "weapons": WEAPONS, "outfits": OUTFITS,
		"defenders": { "count": 2, "weapon": "pistol", "outfit": PLAIN },
		"invaders": { "count": 3, "weapon": "pistol", "outfit": PLATED } })
	for column: String in ["DefendersColumn", "InvadersColumn"]:
		for row: Dictionary in OUTFITS:
			var pick := _pick(menu, column, row["slot"])
			if t.check(pick != null, "%s has an outfit pick for the %s (Outfit_%s)" % [column, row["slot"], row["slot"]]):
				var labels: Array = []
				for i in pick.item_count:
					labels.append(pick.get_item_text(i))
				t.expect_eq(labels, row["choices"].map(func(c): return c["label"]), "the %s pick offers that slot's choices" % row["slot"])
	var config: Dictionary = menu.current_config()
	t.expect_eq(config.get("defenders", {}).get("outfit"), PLAIN, "the defenders' seeded outfit is shown")
	t.expect_eq(config.get("invaders", {}).get("outfit"), PLATED, "the invaders' seeded outfit is shown")

	var head := _pick(menu, "DefendersColumn", "head")
	if head != null:
		head.select(2)  # Helmet
		head.item_selected.emit(2)
	var got := []
	menu.start_requested.connect(func(c): got.append(c))
	(menu.find_child("StartButton", true, false) as Button).pressed.emit()
	if t.check(not got.is_empty(), "Start reports the setup"):
		var defenders: Dictionary = got[0]["defenders"].get("outfit", {})
		t.expect_eq(defenders.get("head"), "helmet", "a pick changed in the window is what Start reports")
		t.expect_eq(defenders.get("body"), "tshirt", "the other slots keep their picks")
		t.expect_eq(got[0]["invaders"].get("outfit"), PLATED, "each side reports its own outfit")
	var kept: Dictionary = menu.current_config()
	menu.queue_free()
	var again := SetupMenu.new()
	t.world.add_child(again)
	again.open(kept.merged({ "weapons": WEAPONS, "outfits": OUTFITS }))
	t.expect_eq(again.current_config(), kept, "reopening with the remembered config restores the outfits")
	again.queue_free()


## 11b: a side's plate picks follow its vest pick. The window is driven with the real rows (`LoadoutConfig.outfit_options()`, plain
## data), whose plate carrier choice is marked `plates: true`. Both seeds name plates without a carrier: the defenders' with no
## vest, the invaders' with the tactical vest.
func _check_plates(t: TestContext) -> void:
	var rows := LoadoutConfig.outfit_options()
	var vest_row: Array = rows.filter(func(r): return str(r.get("slot", "")) == "vest")
	var marked: Array = [] if vest_row.is_empty() else (vest_row[0].get("choices", []) as Array).filter(func(c): return c.get("plates", false))
	t.expect_eq(marked.map(func(c): return str(c.get("id", ""))), ["plate_carrier"], "the vest row marks the plate carrier's choice plates: true")

	# Opened on vests that hold no plates: every plate pick disabled and on "None", the plates reported as none.
	var menu := _plates_menu(t, rows)
	for column: String in COLUMNS:
		_expect_plates_off(t, menu, column, "opened with %s vest" % _vest_name(column))
	var started := _start(menu)
	for side: String in SIDES:
		var outfit: Dictionary = started.get(side, {}).get("outfit", {})
		t.expect_eq([outfit.get("front_plate"), outfit.get("back_plate")], ["", ""],
			"Start reports no plates for the %s, whose seeded vest holds none" % side)
	menu.queue_free()

	for i in COLUMNS.size():
		var column: String = COLUMNS[i]
		var side: String = SIDES[i]
		# Carrier on: the plates are picked and reported; tactical vest: off and cleared; carrier again: on; a plate picked is reported by Start.
		menu = _plates_menu(t, rows)
		_choose(menu, column, "vest", "plate_carrier")
		_expect_plates_on(t, menu, column, "the plate carrier picked")
		_choose(menu, column, "front_plate", "steel_iii")
		_choose(menu, column, "back_plate", "ceramic_iv")
		var outfit: Dictionary = menu.current_config().get(side, {}).get("outfit", {})
		t.expect_eq([outfit.get("front_plate"), outfit.get("back_plate")], ["steel_iii", "ceramic_iv"],
			"%s: plates picked with the carrier are reported (current_config)" % side)
		_choose(menu, column, "vest", "tactical_vest")
		_expect_plates_off(t, menu, column, "switched from the carrier to the tactical vest")
		_choose(menu, column, "vest", "plate_carrier")
		_expect_plates_on(t, menu, column, "the plate carrier picked again")
		_choose(menu, column, "front_plate", "ceramic_iv")
		outfit = _start(menu).get(side, {}).get("outfit", {})
		t.expect_eq(outfit.get("vest"), "plate_carrier", "%s: Start reports the carrier" % side)
		t.expect_eq(outfit.get("front_plate"), "ceramic_iv", "%s: Start reports the front plate picked with the carrier" % side)
		menu.queue_free()

		# Carrier with plates, then no vest: off, "None", and Start reports no plates.
		menu = _plates_menu(t, rows)
		_choose(menu, column, "vest", "plate_carrier")
		_choose(menu, column, "front_plate", "steel_iii")
		_choose(menu, column, "back_plate", "steel_iii")
		_choose(menu, column, "vest", "")
		_expect_plates_off(t, menu, column, "switched from the carrier to no vest")
		outfit = _start(menu).get(side, {}).get("outfit", {})
		t.expect_eq([outfit.get("vest"), outfit.get("front_plate"), outfit.get("back_plate")], ["", "", ""],
			"%s: Start reports no vest and no plates" % side)
		menu.queue_free()


## A setup window on `rows`, both sides seeded with plates but no carrier.
func _plates_menu(t: TestContext, rows: Array) -> Node:
	var menu := SetupMenu.new()
	t.world.add_child(menu)
	menu.open({ "side": "invader", "seed": 7, "weapons": WEAPONS, "outfits": rows,
		"defenders": { "count": 2, "weapon": "pistol", "outfit": NO_VEST_PLATES },
		"invaders": { "count": 3, "weapon": "pistol", "outfit": SOFT_VEST_PLATES } })
	return menu


## How the check messages name the vest `column` was opened with (`_plates_menu`): none for the defenders, the tactical vest for the invaders.
func _vest_name(column: String) -> String:
	return "no" if column == "DefendersColumn" else "the tactical"


## Pick the choice whose id is `id` in `column`'s `slot` dropdown, as a click would (select + item_selected).
func _choose(menu: Node, column: String, slot: String, id: String) -> void:
	var pick := _pick(menu, column, slot)
	if pick == null:
		return
	for i in pick.item_count:
		if str(pick.get_item_metadata(i)) == id:
			pick.select(i)
			pick.item_selected.emit(i)
			return


## `column`'s two plate picks are disabled and show "None", and current_config reports its plates as "".
func _expect_plates_off(t: TestContext, menu: Node, column: String, what: String) -> void:
	for slot: String in ["front_plate", "back_plate"]:
		var pick := _pick(menu, column, slot)
		if not t.check(pick != null, "%s has an Outfit_%s pick" % [column, slot]):
			continue
		t.check(pick.disabled, "%s, %s: the %s pick is disabled" % [column, what, slot])
		t.expect_eq([pick.get_item_text(pick.selected), str(pick.get_item_metadata(pick.selected))], ["None", ""],
			"%s, %s: the %s pick shows None" % [column, what, slot])
	var outfit: Dictionary = menu.current_config().get(SIDES[COLUMNS.find(column)], {}).get("outfit", {})
	t.expect_eq([outfit.get("front_plate"), outfit.get("back_plate")], ["", ""], "%s, %s: no plates reported (current_config)" % [column, what])


## `column`'s two plate picks are enabled.
func _expect_plates_on(t: TestContext, menu: Node, column: String, what: String) -> void:
	for slot: String in ["front_plate", "back_plate"]:
		var pick := _pick(menu, column, slot)
		if t.check(pick != null, "%s has an Outfit_%s pick" % [column, slot]):
			t.check(not pick.disabled, "%s, %s: the %s pick is enabled" % [column, what, slot])


## What Start reports for `menu` (one press: the window disables its start buttons on the way out).
func _start(menu: Node) -> Dictionary:
	var got := []
	menu.start_requested.connect(func(c): got.append(c))
	(menu.find_child("StartButton", true, false) as Button).pressed.emit()
	return got[0] if not got.is_empty() else {}


## The outfit dropdown for `slot` in the side column named `column`, or null.
func _pick(menu: Node, column: String, slot: String) -> OptionButton:
	var col := menu.find_child(column, true, false)
	return col.find_child("Outfit_%s" % slot, true, false) as OptionButton if col != null else null
