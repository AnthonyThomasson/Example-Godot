extends GameTest

## O13 (docs/outfits.md): the spectator inspector lists what the NPC it has selected wears: each garment by name (as
## `outfit_view()` names it) and each plate by name (as `LoadoutConfig.outfit_options()` labels it) with its condition as a
## percentage. Nothing is listed before an NPC is clicked, nor after a click on empty ground clears the selection. The clicks are
## real mouse input at a world point's place on screen (once the framing camera has settled); the NPC's vision overlay turning
## on shows the click selected it.

const OutfitProbe := preload("res://tests/_outfit/outfit_probe.gd")
const Inspector := preload("res://scenes/ui/hud/spectator_inspector.gd")
const OverlayToggles := preload("res://scenes/ui/overlays/overlay_toggles.gd")
const AT := Vector2(450, 250)
## Empty ground, far from the NPC: a click there clears the selection.
const GROUND := Vector2(150, 420)
const KIT := {
	"head": &"helmet", "body": &"shirt", "vest": &"plate_carrier", "pants": &"tactical_pants", "feet": &"boots",
	"front_plate": &"ceramic_iv", "back_plate": &"steel_iii",
}


func describe() -> Dictionary:
	return {
		"name": "The spectator inspector lists the selected NPC's outfit",
		"description": "Clicking an NPC in a helmet, shirt, plate carrier (ceramic front, steel back), tactical pants and boots lists every garment and both plates with their condition; clicking empty ground hides the list.",
		"tags": ["outfit", "ui", "inspector", "spectator"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.switch(&"nav.rebake", false)
	s.switch(&"ai.vision", false)
	s.von_down()
	s.lock_interaction([&"camera", &"pause"])
	s.actor(&"npc", &"defender", AT, { "speed": 0.0 })


func run(t: TestContext) -> void:
	var npc := t.actor(&"npc")
	if not OutfitProbe.require_api(t, npc):
		return
	if not t.require(not OutfitProbe.options().is_empty(), "LoadoutConfig.outfit_options() names the plates (docs/outfits.md O11)"):
		return
	OutfitProbe.wear(npc, KIT)
	var inspector := CanvasLayer.new()
	inspector.set_script(Inspector)
	t.world.add_child(inspector)
	inspector.call("setup", [npc], { "show_vision": true }, OverlayToggles.RESERVED_WIDTH)  # the width Main hands it
	await t.seconds(1.5)  # the framing camera settles, so a point's place on screen holds still

	var names: Array[String] = []
	var view := OutfitProbe.view(npc)
	for slot: String in ["head", "body", "vest", "pants", "feet"]:
		names.append(str(view.get(slot, "")))
	for side: String in ["front_plate", "back_plate"]:
		names.append(OutfitProbe.label_of(side, KIT[side]))
	t.check(not names.has(""), "every garment and plate has a name to show (%s)" % [names])
	t.check(names.all(func(n): return not _shown(inspector).contains(n)), "nothing is listed before an NPC is selected")

	await _click(t, npc.global_position)
	if not t.require(_vision_on(npc), "the click selects the NPC (its vision overlay is on)"):
		return
	var shown := _shown(inspector)
	for n: String in names:
		t.check(shown.contains(n), "the inspector lists %s:\n%s" % [n, shown])
	t.check(shown.contains("100%"), "and the plates' condition (100%%, new)")

	await _click(t, GROUND)
	t.check(not _vision_on(npc), "a click on empty ground clears the selection")
	shown = _shown(inspector)
	t.check(names.all(func(n): return not shown.contains(n)), "and the outfit list goes with it")
	inspector.queue_free()


## A left click (press and release) at world point `at`'s place on screen.
func _click(t: TestContext, at: Vector2) -> void:
	var screen := t.world.get_viewport().get_canvas_transform() * at
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	motion.global_position = screen
	TestContext.inject(motion)
	await t.frames(1)
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = screen
		click.global_position = screen
		TestContext.inject(click)
		await t.frames(1)
	await t.frames(1)


## Whether `npc`'s vision overlay is switched on.
func _vision_on(npc: Node) -> bool:
	for child in npc.get_children():
		if "show_vision" in child and bool(child.get("show_vision")):
			return true
	return false


## The text of every visible label under `node`, one per line.
func _shown(node: Node) -> String:
	var out: Array[String] = []
	for label in node.find_children("*", "Label", true, false):
		if (label as Label).is_visible_in_tree():
			out.append((label as Label).text)
	return "\n".join(out)
