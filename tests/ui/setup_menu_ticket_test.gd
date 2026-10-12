extends GameTest

## The setup window shows the run's ticket name above its title when one is given, and nothing when blank.

const SetupMenu := preload("res://scenes/ui/menus/setup_menu.gd")


func describe() -> Dictionary:
	return {
		"name": "Setup window shows the ticket name",
		"description": "open() with a ticket adds a label above the title; a blank or missing ticket adds none.",
		"tags": ["setup", "ui"],
		"timeout": 5.0,
	}


func run(t: TestContext) -> void:
	var tagged := SetupMenu.new()
	t.world.add_child(tagged)
	tagged.open({ "ticket": "ABC-1" })
	var label := tagged.find_child("TicketLabel", true, false) as Label
	t.check(label != null, "a ticket label is drawn")
	if label != null:
		t.expect_eq(label.text, "ABC-1", "it shows the ticket name")

	var blank := SetupMenu.new()
	t.world.add_child(blank)
	blank.open({ "ticket": "  " })
	t.check(blank.find_child("TicketLabel", true, false) == null, "a blank ticket draws no label")
