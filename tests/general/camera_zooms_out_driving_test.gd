extends GameTest

## V8 (ticket #54): the camera follows the character, which the seat carries; while it drives, the zoom eases out with the
## vehicle's speed (further the faster) and back in when it slows. Seated in a parked car the zoom is the on-foot one.

const CameraController = preload("res://scenes/general/camera_controller.gd")
const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
## The two cruising speeds (px/s), fixed numbers in reach of the car whatever its top speed and well apart (the zoom
## follows speed over top speed).
const MID_SPEED := 160.0
const FAST_SPEED := 320.0


func describe() -> Dictionary:
	return {
		"name": "The camera zooms out while driving",
		"description": "A camera following the driver: the on-foot zoom while parked, zoomed out at 160 px/s and further at 320 px/s, back to the on-foot zoom once stopped; it keeps following the driver.",
		"tags": ["camera", "zoom", "vehicle", "drive"],
		"timeout": 45.0,
	}


func configure(s: TestSetup) -> void:
	s.lock_interaction([&"camera"])  # a person's wheel or camera keys would change what is measured
	s.arena(Rect2(0, 0, 4200, 600), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", Vector2(300, 300))
	s.actor(&"me", &"puppet", Vector2(150, 80))


## Hold puppet "me" near `target` px/s for `duration` s and return the camera's zoom at the end.
func _cruise(t: TestContext, car: Node2D, cam: Camera2D, target: float, duration: float) -> float:
	await Probe.reach_speed(t, &"me", car, target, 8.0)
	await Probe.hold_speed(t, &"me", car, target, 0.0, false, duration)
	return cam.zoom.x


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car", [&"me"]):
		return
	var car := t.vehicle(&"car") as Node2D
	var me := t.actor(&"me") as Node2D
	var top: Variant = Probe.kind_value(&"car", &"top_speed")
	if not t.require(top != null, "VehicleConfig gives the car a top_speed"):
		return
	var cam := Camera2D.new()
	cam.set_script(CameraController)
	cam.target_path = ^"../me"
	t.world.add_child(cam)
	cam.make_current()  # only the current camera updates its screen centre, which the follow check reads
	await t.seconds(1.5)
	var on_foot := cam.zoom.x

	if not t.require(await Probe.board_by(t, &"me", car, &"front_left"), "the driver gets in"):
		return
	await t.seconds(1.5)
	t.expect_near(cam.zoom.x, on_foot, 0.03, "seated in the parked car the zoom is the on-foot one")

	var mid := await _cruise(t, car, cam, MID_SPEED, 1.5)
	var fast := await _cruise(t, car, cam, FAST_SPEED, 1.5)
	t.check(mid < on_foot - 0.01, "driving, the camera zooms out (%.3f at %.0f px/s, %.3f on foot)" % [mid, MID_SPEED, on_foot])
	t.check(fast < mid - 0.01, "further the faster (%.3f at %.0f px/s)" % [fast, FAST_SPEED])
	t.check(cam.get_screen_center_position().distance_to(me.global_position) < 200.0, "and keeps following the driver the seat carries")

	t.puppet(&"me").drive(-1.0, 0.0, false)
	await t.until(func(): return Probe.along(car) <= 2.0, 8.0)
	t.puppet(&"me").drive(0.0, 0.0, false)
	await t.seconds(3.0)
	t.expect_near(cam.zoom.x, on_foot, 0.03, "stopped, the zoom eases back in")
