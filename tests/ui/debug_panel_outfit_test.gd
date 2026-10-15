extends GameTest

## O13 (docs/outfits.md): the player debug panel (`DebugUI`) lists what its character wears: each garment by name (as
## `outfit_view()` names it) and each plate by name (as `LoadoutConfig.outfit_options()` labels it) with its condition as a
## percentage, which falls as the plate wears. The character is shot in the front plate first, so its condition is not the
## 100% other lines (stamina) may show.

const OutfitProbe := preload("res://tests/_outfit/outfit_probe.gd")
const DebugUI := preload("res://scenes/ui/hud/debug_ui.gd")
const KIT := {
	"head": &"helmet", "body": &"shirt", "vest": &"plate_carrier", "pants": &"tactical_pants", "feet": &"boots",
	"front_plate": &"ceramic_iv", "back_plate": &"steel_iii",
}


func describe() -> Dictionary:
	return {
		"name": "The debug panel lists the outfit",
		"description": "A character in a helmet, shirt, plate carrier (ceramic front, steel back), tactical pants and boots, its front plate worn by a rifle round: the debug panel names every garment and both plates with their condition.",
		"tags": ["outfit", "ui", "debug"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 400))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.debris", false)
	s.set_static(BloodConfig, &"enabled", false)
	OutfitProbe.pin_height(s)
	s.actor(&"me", &"puppet", Vector2(OutfitProbe.TARGET_X, 200), { "max_health": 10000.0, "facing": Vector2.LEFT, "aim_point": Vector2(0, 200) })


func run(t: TestContext) -> void:
	var me := t.actor(&"me")
	if not OutfitProbe.require_api(t, me):
		return
	if not t.require(not OutfitProbe.options().is_empty(), "LoadoutConfig.outfit_options() names the plates (docs/outfits.md O11)"):
		return
	t.puppet(&"me").aim_at(Vector2(0, 200))
	OutfitProbe.wear(me, KIT)
	var panel := CanvasLayer.new()
	panel.set_script(DebugUI)
	panel.set("character_path", me.get_path())
	t.world.add_child(panel)
	OutfitProbe.fire(t, Vector2(OutfitProbe.FROM_X, 200), Vector2.RIGHT, &"rifle", 40.0)
	await t.seconds(0.3)

	var text := _text(panel)
	var view := OutfitProbe.view(me)
	for slot: String in ["head", "body", "vest", "pants", "feet"]:
		var garment := str(view.get(slot, ""))
		t.check(garment != "" and text.contains(garment), "the panel names the %s (%s)" % [slot, garment])
	for side: String in ["front_plate", "back_plate"]:
		var plate_name := OutfitProbe.label_of(side, KIT[side])
		t.check(plate_name != "" and text.contains(plate_name), "the panel names the %s (%s)" % [side, plate_name])
	var front := OutfitProbe.condition(me, "front_plate")
	t.check(front > 0.0 and front < 0.995, "a rifle round wore the front plate (%.3f)" % front)
	t.check(text.contains("%d%%" % roundi(front * 100.0)), "the panel shows the front plate's condition, %d%%:\n%s" % [roundi(front * 100.0), text])
	panel.queue_free()


## Every label's text in `node`, one per line.
func _text(node: Node) -> String:
	var out: Array[String] = []
	for label in node.find_children("*", "Label", true, false):
		out.append((label as Label).text)
	return "\n".join(out)
