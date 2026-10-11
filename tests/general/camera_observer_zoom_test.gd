extends GameTest

## The mouse wheel also zooms a framing (spectator) camera: it scales the automatic fit, can go past
## the fit's own limits, doesn't move the camera, and the zoom stays after the 5 s pan hold.

const CameraController = preload("res://scenes/general/camera_controller.gd")


func describe() -> Dictionary:
	return {
		"name": "Mouse wheel zooms the spectator camera",
		"description": "A framing camera zooms in and out on the wheel, the zoom outlasts the pan hold, and the centre stays on the combatants.",
		"tags": ["camera", "zoom", "input", "spectator"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
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
	var fit := cam.zoom.x

	for i in 3:
		_wheel(MOUSE_BUTTON_WHEEL_UP)
	await t.seconds(1.5)
	var zoomed := fit * pow(cam.zoom_step, 3.0)
	t.expect_near(cam.zoom.x, zoomed, 0.03, "wheel-up scales the fitted zoom")
	t.expect_near(cam.global_position.x, 500.0, 5.0, "the wheel leaves the centre on the combatants")

	await t.seconds(cam.manual_hold + 2.0)
	t.expect_near(cam.zoom.x, zoomed, 0.03, "the zoom stays after the pan hold")

	for i in 6:
		_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	await t.seconds(1.5)
	t.check(cam.zoom.x < fit, "wheel-down zooms out past the fit (zoom %.2f, fit %.2f)" % [cam.zoom.x, fit])


## One wheel notch, as the OS delivers it.
func _wheel(button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
