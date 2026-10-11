extends GameTest

## A spectator (framing) camera can be steered by hand — the camera keys or the mouse at a screen
## edge — and returns to its automatic framing after 5 seconds without camera input.

const CameraController = preload("res://scenes/general/camera_controller.gd")


func describe() -> Dictionary:
	return {
		"name": "Spectator camera pans by hand, then returns",
		"description": "Camera keys and the screen edge pan a framing camera; 5 s idle eases it back to the combatants.",
		"tags": ["camera", "pan", "input"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.lock_interaction([&"camera"])  # a person's wheel or camera keys would change what is measured
	s.arena(Rect2(0, 0, 1000, 640))
	s.actor(&"a", &"puppet", Vector2(300, 300))
	s.actor(&"b", &"puppet", Vector2(700, 300))


func run(t: TestContext) -> void:
	var cam := Camera2D.new()
	cam.set_script(CameraController)
	cam.target_path = ^".."
	t.world.add_child(cam)
	cam.frame([t.actor(&"a"), t.actor(&"b")])
	await t.seconds(2.0)
	var home := cam.global_position
	t.expect_near(home.x, 500.0, 5.0, "the framing centres on the two combatants")

	# Camera key: pans while held.
	Input.action_press(Keybinds.CAMERA_RIGHT)
	await t.seconds(0.5)
	Input.action_release(Keybinds.CAMERA_RIGHT)
	var panned := cam.global_position
	t.check(panned.x > home.x + 100.0, "the camera key pans right (moved %.0f)" % (panned.x - home.x))

	# Held by hand: no snap back while the hold time is running.
	await t.seconds(cam.manual_hold - 1.0)
	t.check(cam.global_position.distance_to(panned) < 5.0, "the camera stays where it was left")

	# Idle past the hold: automatic framing resumes.
	await t.seconds(1.0 + 2.5)
	t.check(cam.global_position.distance_to(home) < 10.0, "5 s idle returns the camera to its framing")

	# Screen edge: the mouse against the right edge pans right.
	var edge := cam.get_viewport_rect().size.x - 2.0
	_move_mouse(Vector2(edge, 300.0))
	await t.seconds(0.5)
	t.check(cam.global_position.x > home.x + 100.0, "the mouse at the right edge pans right")

	# Leaving the window stops the edge pan.
	cam.notification(Node.NOTIFICATION_WM_MOUSE_EXIT)
	var stopped := cam.global_position
	await t.seconds(0.5)
	t.check(cam.global_position.distance_to(stopped) < 5.0, "no edge pan once the mouse has left the window")


func _move_mouse(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	TestContext.inject(event)
