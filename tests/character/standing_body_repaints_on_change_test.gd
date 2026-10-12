extends GameTest

## A standing body is repainted only when what it draws has changed (character_visuals.gd). One standing
## still mostly stops repainting; a walking one repaints every frame; a wound, a change of the held item and
## a fresh walk each repaint it promptly, and it goes quiet again once it stops. Guards the idle cost of a
## crowd (tests/physics/crowd_deaths_stress_test.gd) without leaving a stale body on screen.

## Frames each repaint count is read over.
const WINDOW := 120


func describe() -> Dictionary:
	return {
		"name": "Standing body repaints only on change",
		"description": "A still body skips most repaints, a walking one repaints every frame, and a wound, a new held item and a walk each repaint it.",
		"tags": ["draw", "pose", "perf"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.blood", false)
	s.actor(&"still", &"puppet", Vector2(200, 100), { "start_slot": 1 })
	s.actor(&"walker", &"puppet", Vector2(150, 300), { "start_slot": 1 })


## How many times `id`'s standing body has been drawn.
func _redraws(t: TestContext, id: StringName) -> int:
	return t.actor(id).get_node("Visuals").redraws


## Repaints of `id` over the next `WINDOW` frames.
func _repaints_over_window(t: TestContext, id: StringName) -> int:
	var before := _redraws(t, id)
	await t.frames(WINDOW)
	return _redraws(t, id) - before


func run(t: TestContext) -> void:
	var still: Node = t.actor(&"still")
	for id in [&"still", &"walker"]:
		t.puppet(id).aim_at(Vector2(2000, t.actor(id).global_position.y))
	await t.seconds(1.5)

	var idle := await _repaints_over_window(t, &"still")
	t.trace("still repaints", idle)
	t.check(idle < int(WINDOW / 2.0), "a body standing still repainted %d of %d frames" % [idle, WINDOW])

	var wound_before := _redraws(t, &"still")
	var hit := HitInfo.new()
	hit.position = still.global_position + Vector2(-8, 0)
	hit.normal = Vector2.LEFT
	hit.direction = Vector2.RIGHT
	hit.damage = 1.0
	still._deformable.record(hit, still.pose.torso_angle)
	await t.frames(2)
	t.check(_redraws(t, &"still") > wound_before, "a new wound repainted the body")

	var slot_before := _redraws(t, &"still")
	t.puppet(&"still").select_slot(3)
	await t.frames(2)
	t.check(_redraws(t, &"still") > slot_before, "picking up the pistol repainted the body")

	var walker: Node = t.puppet(&"walker")
	walker.walk(Vector2.RIGHT)
	await t.seconds(0.4)
	var walking := await _repaints_over_window(t, &"walker")
	t.trace("walker repaints", walking)
	t.check(walking >= WINDOW - 10, "a walking body repainted %d of %d frames" % [walking, WINDOW])

	walker.stop()
	await t.seconds(1.5)
	var settled := await _repaints_over_window(t, &"walker")
	t.trace("stopped repaints", settled)
	t.check(settled < int(WINDOW / 2.0), "a body that stopped walking repainted %d of %d frames" % [settled, WINDOW])
