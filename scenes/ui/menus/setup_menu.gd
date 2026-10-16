extends CanvasLayer

## UI domain, pre-game setup window: a modal shown before the match starts so a human can choose
## the run's parameters — which side they play, how many defenders and invaders spawn and what each
## side carries, and whether the human leads its side ("Lead the team", for Start only) — then pick how to run it: **Start**
## (play as the chosen side), **Watch** (the AI alone) or **Endless** (the AI alone, a fresh randomised match after each one
## ends). Hands the choice
## back to Main, which builds the world. Built entirely in code (no scene-side layout), like the other
## UI HUDs.
##
## Main opens it on a fresh launch and spawns the world only once a start button is pressed; scripted
## restarts (the dev command server) set an Engine `skip_setup` meta and bypass it, so the headless
## match harness is unaffected. A decoupled piece: it knows nothing of the domains, only the parameter
## dicts it is given and emits (the weapon, grenade and outfit choices arrive as plain data in `open`).

## Emitted when a start button is pressed, carrying the chosen parameters:
## `{ mode: "play"|"watch"|"endless", side: "defender"|"invader", seed: int, lead: bool,
##    defenders: { count, weapon, magazine, spares, stuns, frags, outfit: { <slot>: "<id>" } }, invaders: { ... } }`.
## Main applies these and builds the world.
signal start_requested(config: Dictionary)
## Emitted when the Tests button is pressed: Main opens the test browser instead of a match.
signal tests_requested
## Emitted when the Settings button is pressed: Main opens the settings page over this window.
signal settings_requested

const _MAX_COUNT := 8  ## Upper bound per side in the spinboxes; spawn spread handles any count in range.
const _SIDES := ["defender", "invader"]  ## The sides the human can play, in dropdown order.
## The grenade rows when Main gives none (`open`'s `grenades`): a Stun and a Frag count. They name no cap of their own; a row without a `max`
## counts up to `_MAX_COUNT` (Main's rows carry `LoadoutConfig.max_grenades`).
const _GRENADES := [{ "id": "stun", "label": "Stun" }, { "id": "frag", "label": "Frag" }]
const _FONT := 30         ## The controls' font size.
const _OUTFIT_FONT := 24  ## The outfit dropdowns' font size: smaller, so a side's seven picks stay compact.

var _side_option: OptionButton      ## Which side a human plays (for Start).
var _seed_edit: LineEdit            ## The level seed; blank/0 = a fresh random seed each run.
var _lead_box: CheckBox             ## "Lead the team": the human leads its side's squad (Start only; Main ignores it otherwise).
var _side_rows := {}                ## "defenders"/"invaders" -> { count, weapon, magazine, spares, magazine_row } controls.
var _weapons: Array = []            ## Weapon choices `[{ id, label, magazines: [{ id, label }] }]` handed in by Main.
var _grenades: Array = _GRENADES    ## Grenade count rows `[{ id, label, max }]` (`max` optional): a side's count of each is reported as `<id>s`.
## Outfit rows `[{ slot, label, choices: [{ id, label, plates? }], plate? }]` handed in by Main: one dropdown per slot. A row marked
## `plate` is a plate slot, offered only while a choice marked `plates` (a vest that holds plates) is picked in another row.
var _outfits: Array = []
var _start_buttons: Array[Button] = []  ## Start / Watch / Endless: all disabled on press, so a start can't be triggered twice.
var _scroll: ScrollContainer        ## Holds the controls; sized to fit the window.
var _content: Control               ## The controls' margin box, whose height the scroll area tries to show whole.
var _status: Label                  ## Status line Main shows while it holds the start (hidden when blank).


## Build the window seeded from `defaults` and show it. Keys (all optional): `side` ("defender" /
## "invader"), `seed`, `lead` (whether "Lead the team" starts ticked; off when absent), `defenders` / `invaders` (each `{ count, weapon, magazine, spares, stuns, frags }`, or a bare
## count; a side may also carry `outfit`, `{ <slot>: id }`), `weapons` (the choices described at `_weapons`; empty = no
## weapon rows, nor grenade rows), `grenades` (the grenade rows described at `_grenades`), `outfits` (the rows described at
## `_outfits`; empty = no outfit rows) and `ticket` (a non-blank one is shown above the title). Called by Main before the
## world is spawned.
func open(defaults: Dictionary) -> void:
	_weapons = defaults.get("weapons", [])
	_grenades = defaults.get("grenades", _GRENADES)
	_outfits = defaults.get("outfits", [])
	_build_ui(defaults)
	get_viewport().size_changed.connect(_fit_scroll)
	_fit_scroll.call_deferred()


## Size the scroll area to the controls' full height, or to the window's if that is shorter (leaving a
## margin), so everything is reachable in a small window and the panel stays snug in a big one.
func _fit_scroll() -> void:
	if _scroll == null or not is_inside_tree():
		return
	var room := get_viewport().get_visible_rect().size.y - 48.0
	_scroll.custom_minimum_size.y = minf(_content.get_combined_minimum_size().y, room)


# --- UI construction (built in code like the other UI HUDs; no scene-side layout) ----------

## Lay out the dimmer, the centred panel and its controls, seeded from `defaults`.
func _build_ui(defaults: Dictionary) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP  # swallow any clicks meant for the (unbuilt) world
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)

	# The controls scroll when the window is too short to show them all (fitted in `_fit_scroll`).
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(_scroll)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	_scroll.add_child(margin)
	_content = margin

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	margin.add_child(box)

	var ticket := str(defaults.get("ticket", "")).strip_edges()
	if not ticket.is_empty():
		var ticket_label := Label.new()
		ticket_label.name = "TicketLabel"
		ticket_label.text = ticket
		ticket_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ticket_label.add_theme_font_size_override("font_size", 32)
		ticket_label.modulate = Color(1, 1, 1, 0.75)
		box.add_child(ticket_label)

	var title := Label.new()
	title.text = "MATCH SETUP"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	box.add_child(title)

	_side_option = _option_row(box, "Play as", ["Defender", "Invader"], _SIDES.find(str(defaults.get("side", "defender"))))
	_side_option.name = "SideOption"
	_lead_box = _check_row(box, "Lead the team", bool(defaults.get("lead", false)))
	_lead_box.name = "LeadCheck"
	_lead_box.tooltip_text = "Start only: you lead your side. Right-click in the match to order your teammates."

	_seed_edit = _seed_row(box, int(defaults.get("seed", 0)))

	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 40)
	box.add_child(sides)
	_side_rows["defenders"] = _side_column(sides, "Defenders", defaults.get("defenders", 1))
	_side_rows["invaders"] = _side_column(sides, "Invaders", defaults.get("invaders", 1))

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 24)
	_status.modulate = Color(1, 1, 1, 0.75)
	_status.visible = false
	box.add_child(_status)

	var starts := HBoxContainer.new()
	starts.add_theme_constant_override("separation", 12)
	box.add_child(starts)
	for entry in [["Start", "play"], ["Watch", "watch"], ["Endless", "endless"]]:
		var button := Button.new()
		button.name = "%sButton" % entry[0]
		button.text = entry[0]
		button.tooltip_text = {
			"play": "Play as the chosen side.",
			"watch": "Watch the AI play it out, with no player.",
			"endless": "Watch an endless run of matches with different parameters (a new one 5 s after each ends). Esc stops.",
		}[entry[1]]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 32)
		button.pressed.connect(_on_start.bind(entry[1]))
		starts.add_child(button)
		_start_buttons.append(button)

	var tests_button := Button.new()
	tests_button.text = "Tests"
	tests_button.add_theme_font_size_override("font_size", 28)
	tests_button.pressed.connect(tests_requested.emit)
	box.add_child(tests_button)

	var settings_button := Button.new()
	settings_button.text = "Settings"
	settings_button.add_theme_font_size_override("font_size", 28)
	settings_button.pressed.connect(settings_requested.emit)
	box.add_child(settings_button)


## One side's controls — count, weapon, magazine, spare magazines, grenade counts, outfit — in a titled column added to
## `parent`. `seed_values` is `{ count, weapon, magazine, spares, stuns, frags, outfit }` or a bare count. Returns the controls
## by name (the outfit's as `outfit`: slot -> its dropdown).
func _side_column(parent: Control, title: String, seed_values: Variant) -> Dictionary:
	var values: Dictionary = seed_values if seed_values is Dictionary else { "count": seed_values }
	var column := VBoxContainer.new()
	column.name = title + "Column"
	column.add_theme_constant_override("separation", 12)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 36)
	column.add_child(heading)

	var rows := {}
	rows["count"] = _spin_row(column, "Count", int(values.get("count", 1)), _MAX_COUNT)
	if not _weapons.is_empty():
		var labels: Array = _weapons.map(func(w): return w["label"])
		var wanted := _weapon_index(StringName(values.get("weapon", &"")))
		rows["weapon"] = _option_row(column, "Weapon", labels, wanted)
		var magazine_row := HBoxContainer.new()
		column.add_child(magazine_row)
		rows["magazine_row"] = magazine_row
		rows["magazine"] = _option_row(magazine_row, "Magazine", [], 0)
		rows["spares"] = _spin_row(column, "Spares", int(values.get("spares", 2)), 8)
		rows["weapon"].item_selected.connect(func(_i): _refresh_magazines(rows, StringName()))
		_refresh_magazines(rows, StringName(values.get("magazine", &"")))
		for grenade: Dictionary in _grenades:
			var key := _grenade_key(grenade)
			rows[key] = _spin_row(column, str(grenade["label"]), int(values.get(key, 0)), int(grenade.get("max", _MAX_COUNT)))
	if not _outfits.is_empty():
		var worn: Dictionary = values.get("outfit", {}) if values.get("outfit") is Dictionary else {}
		rows["outfit"] = _outfit_rows(column, worn)
	return rows


## The outfit's dropdowns (one per `_outfits` row, named `Outfit_<slot>`, each choice's id as its metadata) under an "Outfit"
## sub-heading in `column`, smaller and tighter than the rows above so seven fit, each selecting the id `worn` names for its
## slot (the slot's first choice when it names none offered), the plate rows then following the vest pick (`_refresh_plates`).
## Returns slot -> dropdown.
func _outfit_rows(column: Control, worn: Dictionary) -> Dictionary:
	var heading := Label.new()
	heading.text = "Outfit"
	heading.add_theme_font_size_override("font_size", _OUTFIT_FONT + 4)
	heading.modulate = Color(1, 1, 1, 0.75)
	column.add_child(heading)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	column.add_child(box)
	var picks := {}
	for row: Dictionary in _outfits:
		var slot := str(row["slot"])
		var choices: Array = row["choices"]
		var wanted := choices.map(func(c): return str(c["id"])).find(str(worn.get(slot, "")))
		var option := _option_row(box, str(row["label"]), choices.map(func(c): return c["label"]), maxi(wanted, 0), _OUTFIT_FONT)
		option.name = "Outfit_%s" % slot
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # one width for all seven, whatever their longest choice
		for i in choices.size():
			option.set_item_metadata(i, str(choices[i]["id"]))
		picks[slot] = option
	for slot: String in picks:
		picks[slot].item_selected.connect(func(_i): _refresh_plates(picks))
	_refresh_plates(picks)
	return picks


## Enable a side's plate dropdowns (rows marked `plate`) while one of its other picks is a choice marked `plates`, else disable
## them and show their "None" choice (id ""), so a side never reports a plate with nothing to hold it.
func _refresh_plates(picks: Dictionary) -> void:
	var held := false
	for row: Dictionary in _outfits:
		var option: OptionButton = picks[str(row["slot"])]
		if not row.get("plate", false) and option.selected >= 0:
			held = held or bool(row["choices"][option.selected].get("plates", false))
	for row: Dictionary in _outfits:
		if not row.get("plate", false):
			continue
		var option: OptionButton = picks[str(row["slot"])]
		option.disabled = not held
		if not held:
			var none := (row["choices"] as Array).map(func(c): return str(c["id"])).find("")
			if none >= 0:
				option.select(none)


## The key a grenade row's count is reported under: `stuns`, `frags`.
func _grenade_key(grenade: Dictionary) -> String:
	return "%ss" % grenade["id"]


## Index of weapon `id` in `_weapons` (0, the first listed, when blank or unknown).
func _weapon_index(id: StringName) -> int:
	for i in _weapons.size():
		if StringName(_weapons[i]["id"]) == id:
			return i
	return 0


## Refill a side's Magazine dropdown for the weapon now selected, selecting `wanted` when it is offered.
## A weapon with no magazines hides the magazine and spares rows.
func _refresh_magazines(rows: Dictionary, wanted: StringName) -> void:
	var mags: Array = _weapons[rows["weapon"].selected]["magazines"]
	var option: OptionButton = rows["magazine"]
	option.clear()
	for m in mags:
		option.add_item(m["label"])
		option.set_item_metadata(option.item_count - 1, str(m["id"]))
		if StringName(m["id"]) == wanted:
			option.select(option.item_count - 1)
	rows["magazine_row"].visible = not mags.is_empty()
	rows["spares"].get_parent().visible = not mags.is_empty()


## A labelled dropdown row (label + OptionButton of `items`, `selected` clamped into range, text at `font_size`), added to
## `parent`; returns the OptionButton.
func _option_row(parent: Control, label_text: String, items: Array, selected: int, font_size := _FONT) -> OptionButton:
	var row: Control = parent if parent is HBoxContainer else HBoxContainer.new()
	if row != parent:
		row.add_theme_constant_override("separation", 12)
		parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(160, 0)
	label.add_theme_font_size_override("font_size", font_size)
	row.add_child(label)
	var option := OptionButton.new()
	option.add_theme_font_size_override("font_size", font_size)
	option.custom_minimum_size = Vector2(200, 0)
	for item in items:
		option.add_item(str(item))
	if not items.is_empty():
		option.select(clampi(selected, 0, items.size() - 1))
	row.add_child(option)
	return option


## A checkbox row (`text`, ticked when `on`, the label column left empty so it lines up with the rows above), added to `parent`;
## returns the CheckBox.
func _check_row(parent: VBoxContainer, text: String, on: bool) -> CheckBox:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(160, 0)
	row.add_child(spacer)
	var check := CheckBox.new()
	check.text = text
	check.button_pressed = on
	check.add_theme_font_size_override("font_size", _FONT)
	row.add_child(check)
	parent.add_child(row)
	return check


## A labelled seed row (label + LineEdit), added to `parent`; returns the LineEdit so the caller can
## read it on Start. Prefilled with `value` unless it is 0, which shows as blank (= random).
func _seed_row(parent: VBoxContainer, value: int) -> LineEdit:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = "Seed"
	label.custom_minimum_size = Vector2(160, 0)
	label.add_theme_font_size_override("font_size", _FONT)
	row.add_child(label)
	var edit := LineEdit.new()
	edit.placeholder_text = "random"
	edit.text = "" if value == 0 else str(value)
	edit.custom_minimum_size = Vector2(200, 0)
	edit.add_theme_font_size_override("font_size", _FONT)
	row.add_child(edit)
	parent.add_child(row)
	return edit


## A labelled count row (label + SpinBox clamped to `0..max_value`), added to `parent`; returns the
## SpinBox so the caller can read its value on Start.
func _spin_row(parent: Control, label_text: String, value: int, max_value: int) -> SpinBox:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(160, 0)
	label.add_theme_font_size_override("font_size", _FONT)
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = max_value
	spin.step = 1
	spin.value = clampi(value, 0, max_value)
	spin.custom_minimum_size = Vector2(140, 0)
	spin.add_theme_font_size_override("font_size", _FONT)
	row.add_child(spin)
	parent.add_child(row)
	return spin


## Show a status line in the window, or hide it again when `text` is blank. Main uses it while it
## holds the start — e.g. waiting for the decision server — so the pause is never silent.
func set_status(text: String) -> void:
	if _status == null:
		return
	_status.text = text
	_status.visible = text != ""


## One side's chosen parameters as a plain dict: `{ count }` plus, when weapon choices were given,
## `weapon`, `magazine` (blank when the weapon takes none), `spares` and the grenade counts, and when outfit rows were
## given its `outfit` (`{ <slot>: "<id>" }`, "" for nothing worn and for a disabled plate pick).
func _side_config(rows: Dictionary) -> Dictionary:
	var config := { "count": int(rows["count"].value) }
	if rows.has("weapon"):
		var option: OptionButton = rows["magazine"]
		config["weapon"] = str(_weapons[rows["weapon"].selected]["id"])
		config["magazine"] = str(option.get_item_metadata(option.selected)) if option.item_count > 0 else ""
		config["spares"] = int(rows["spares"].value)
		for grenade: Dictionary in _grenades:
			config[_grenade_key(grenade)] = int(rows[_grenade_key(grenade)].value)
	if rows.has("outfit"):
		var outfit := {}
		for slot: String in rows["outfit"]:
			var option: OptionButton = rows["outfit"][slot]
			outfit[slot] = "" if option.disabled else str(option.get_item_metadata(option.selected))
		config["outfit"] = outfit
	return config


## The window's choices as they stand: `{ side, seed, lead, defenders, invaders }` (the shape `start_requested`
## carries, without `mode`). Main reads it to remember them when the window is left without starting.
## Empty until `open` has built the controls.
func current_config() -> Dictionary:
	if _side_option == null:
		return {}
	return {
		"side": _SIDES[_side_option.selected],
		"seed": _seed_edit.text.strip_edges().to_int(),
		"lead": _lead_box.button_pressed,
		"defenders": _side_config(_side_rows["defenders"]),
		"invaders": _side_config(_side_rows["invaders"]),
	}


## Gather the chosen parameters and hand them to Main with the `mode` of the button pressed. Main applies
## them, frees this window and builds the world. The start buttons are disabled on the way out: Main may
## hold the start open for a moment (waiting on the decision server), and a second press would build the
## world twice.
func _on_start(mode: String) -> void:
	for button in _start_buttons:
		button.disabled = true
	var config := current_config()
	config["mode"] = mode
	start_requested.emit(config)
