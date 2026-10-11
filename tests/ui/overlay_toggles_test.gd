extends GameTest

## The overlay bar's bulk buttons: a group header flips just its group, "All" flips everything, each flag
## changed emits its own `overlay_toggled`, and the counts on the buttons follow the flags.

const OverlayToggles := preload("res://scenes/ui/overlay_toggles.gd")
const Registry := preload("res://scenes/ui/overlay_registry.gd")

var _bar: CanvasLayer
var _events: Array = []


func describe() -> Dictionary:
	return {
		"name": "Overlay bar flips a group or everything at once",
		"description": "A group header turns its whole group on (then off); All covers every overlay; one overlay_toggled per flag changed; counts follow set_flag.",
		"tags": ["overlays", "ui"],
		"timeout": 5.0,
	}


func run(t: TestContext) -> void:
	_bar = OverlayToggles.new()
	t.world.add_child(_bar)
	_bar.overlay_toggled.connect(func(flag, on): _events.append([flag, on]))
	_bar.setup({})

	var perception: Array = []
	for e in Registry.ENTRIES:
		if e["group"] == "Perception":
			perception.append(e["flag"])
	var total: int = Registry.ENTRIES.size()

	t.expect_eq(_label("All"), "All (0/%d)" % total, "starts with everything off")
	t.expect_eq(_label("Perception"), "Perception (0/%d)" % perception.size(), "group count starts at 0")

	# A group header turns on just its group.
	_button("Perception").pressed.emit()
	t.expect_eq(_events.size(), perception.size(), "one event per flag in the group")
	for ev in _events:
		t.check(perception.has(ev[0]) and ev[1], "%s turned on and belongs to the group" % ev[0])
	t.expect_eq(_label("All"), "All (%d/%d)" % [perception.size(), total], "All counts the group's flags")

	# Pressed again, all on → all off.
	_events.clear()
	_button("Perception").pressed.emit()
	t.expect_eq(_events.size(), perception.size(), "turning the group off emits per flag")
	t.expect_eq(_label("All"), "All (0/%d)" % total, "back to none")

	# Mixed → all on, only the missing flags emit.
	_bar.set_flag(perception[0], true)
	t.expect_eq(_label("Perception"), "Perception (1/%d)" % perception.size(), "set_flag refreshes the count")
	_events.clear()
	_button("Perception").pressed.emit()
	t.expect_eq(_events.size(), perception.size() - 1, "only flags that were off emit")

	# All turns every overlay on, then off.
	_events.clear()
	_button("All").pressed.emit()
	t.expect_eq(_label("All"), "All (%d/%d)" % [total, total], "All turns everything on")
	_button("All").pressed.emit()
	t.expect_eq(_label("All"), "All (0/%d)" % total, "All again turns everything off")

	_bar.queue_free()


func _button(prefix: String) -> Button:
	for b in _bar.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with(prefix + " ("):
			return b
	return null


func _label(prefix: String) -> String:
	var b := _button(prefix)
	return b.text if b != null else ""
