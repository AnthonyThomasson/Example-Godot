extends GameTest

## A body the camera cannot see is neither solved nor repainted (character_visuals.gd): a walker far outside the view keeps
## its repaint count flat while one in view repaints every frame; carried into view it repaints within two frames, and
## carried back out it goes flat again. Guards the draw cost of a crowd spread over a house.

const WINDOW := 60
const FAR := Vector2(3600, 250)


func describe() -> Dictionary:
	return {
		"name": "A body out of the camera's view is not drawn",
		"description": "A walker 3400 px from the framed one stops repainting; brought into view it repaints within two frames; taken out again it stops.",
		"tags": ["draw", "camera"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 4000, 500))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.blood", false)
	s.actor(&"near", &"puppet", Vector2(200, 250), { "start_slot": 1 })
	s.actor(&"far", &"puppet", FAR, { "start_slot": 1 })
	s.camera_follow([&"near"])


func run(t: TestContext) -> void:
	await t.seconds(0.5)  # the camera settles on `near`
	t.puppet(&"near").walk(Vector2.DOWN * 0.3)
	t.puppet(&"far").walk(Vector2.DOWN * 0.3)
	await t.frames(2)
	var near_paints := await _repaints(t, &"near")
	var far_paints := await _repaints(t, &"far")
	t.check(near_paints >= WINDOW * 0.8, "the walker in view repaints nearly every frame (%d in %d)" % [near_paints, WINDOW])
	t.check(far_paints == 0, "the walker out of view does not repaint (%d)" % far_paints)

	var before := _redraws(t, &"far")
	t.actor(&"far").global_position = t.actor(&"near").global_position + Vector2(60, 0)
	await t.frames(2)
	t.check(_redraws(t, &"far") > before, "brought into view it repaints within two frames")
	await t.frames(2)
	t.actor(&"far").global_position = FAR
	await t.frames(2)
	var again := await _repaints(t, &"far")
	t.check(again == 0, "taken back out of view it stops repainting (%d)" % again)


## How many times `id`'s standing body has been drawn.
func _redraws(t: TestContext, id: StringName) -> int:
	return t.actor(id).get_node("Visuals").redraws


## Repaints of `id` over the next `WINDOW` frames.
func _repaints(t: TestContext, id: StringName) -> int:
	var before := _redraws(t, id)
	await t.frames(WINDOW)
	return _redraws(t, id) - before
