extends GameTest

## The mouse wheel zooms a following camera (as does a trackpad's two-finger scroll): in on wheel-up, out on wheel-down, never past its
## wheel_min_zoom / wheel_max_zoom.

const CameraController = preload("res://scenes/general/camera_controller.gd")


func describe() -> Dictionary:
	return {
		"name": "Mouse wheel zooms the camera",
		"description": "A following camera zooms in on wheel-up, out on wheel-down, and stops at its zoom limits.",
		"tags": ["camera", "zoom", "input"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.lock_interaction([&"camera"])  # a person's wheel or camera keys would change what is measured
	s.arena(Rect2(0, 0, 800, 500))


func run(t: TestContext) -> void:
	var cam := Camera2D.new()
	cam.set_script(CameraController)
	cam.target_path = ^".."  # follow the world root
	t.world.add_child(cam)
	await t.seconds(0.3)

	_wheel(MOUSE_BUTTON_WHEEL_UP)
	_wheel(MOUSE_BUTTON_WHEEL_UP)
	await t.seconds(1.0)
	t.check(cam.zoom.x > 1.15, "wheel-up zoomed in (zoom %.2f)" % cam.zoom.x)

	# Two-finger trackpad scroll: up zooms in, down zooms out.
	var before := cam.zoom.x
	_scroll(-40.0)
	await t.seconds(1.0)
	t.check(cam.zoom.x > before * 1.2, "trackpad scroll up zoomed in (zoom %.2f from %.2f)" % [cam.zoom.x, before])
	_scroll(80.0)
	await t.seconds(1.0)
	t.check(cam.zoom.x < before, "trackpad scroll down zoomed out (zoom %.2f)" % cam.zoom.x)

	for i in 4:
		_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	await t.seconds(1.0)
	t.check(cam.zoom.x < 1.0, "wheel-down zoomed back out past the start (zoom %.2f)" % cam.zoom.x)

	for i in 60:
		_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	await t.seconds(2.0)
	t.expect_near(cam.zoom.x, cam.wheel_min_zoom, 0.02, "zoom stops at wheel_min_zoom")

	for i in 120:
		_wheel(MOUSE_BUTTON_WHEEL_UP)
	await t.seconds(2.0)
	t.expect_near(cam.zoom.x, cam.wheel_max_zoom, 0.02, "zoom stops at wheel_max_zoom")


## A two-finger trackpad scroll of `amount` (negative = up), as the OS delivers it.
func _scroll(amount: float) -> void:
	var event := InputEventPanGesture.new()
	event.delta = Vector2(0.0, amount)
	TestContext.inject(event)


## One wheel notch, as the OS delivers it.
func _wheel(button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	TestContext.inject(event)
