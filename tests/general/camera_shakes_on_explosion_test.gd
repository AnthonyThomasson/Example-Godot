extends GameTest

## The camera shakes on an explosion, by distance and kind: hard when near, less when farther, none beyond its reach, a frag
## more than a stun. It settles back to rest afterwards. Shake is noisy, so each is read as the peak `Camera2D.offset` over the first
## 0.3 s after the event.

const CameraController = preload("res://scenes/general/camera_controller.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "The camera shakes on an explosion",
		"description": "EventBus explosion events beside, 300 px from and 5000 px from the camera: a near frag shakes it hardest, a stun less, a far one not at all, and it comes to rest.",
		"tags": ["camera", "shake", "grenade", "explosion"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.lock_interaction([&"camera"])  # a person's wheel or camera keys would move what is measured
	s.arena(Rect2(0, 0, 800, 500))


## Post an explosion `distance` px from the camera and return the peak offset (px) over the next 0.3 s.
func _shake(t: TestContext, cam: Camera2D, kind: StringName, distance: float) -> float:
	await t.seconds(2.5)  # whatever was shaking has settled
	EventBus.post(&"explosion", { "position": cam.global_position + Vector2(distance, 0), "kind": kind, "attacker": null, "radius": 250.0 if kind == &"frag" else 400.0 })
	var peak := 0.0
	for i in 18:
		await t.frames(1)
		peak = maxf(peak, cam.offset.length())
	return peak


func run(t: TestContext) -> void:
	var cam := Camera2D.new()
	cam.set_script(CameraController)
	cam.target_path = ^".."  # follow the world root
	t.world.add_child(cam)
	await t.seconds(0.5)

	var near_frag := await _shake(t, cam, &"frag", 20.0)
	var mid_frag := await _shake(t, cam, &"frag", 300.0)
	var near_stun := await _shake(t, cam, &"stun", 20.0)
	var far_frag := await _shake(t, cam, &"frag", 5000.0)
	t.check(near_frag > 2.0, "a frag beside the camera shakes it (peak offset %.2f px)" % near_frag)
	t.check(mid_frag > 0.3 and mid_frag < near_frag, "one 300 px away shakes it less (%.2f px, against %.2f)" % [mid_frag, near_frag])
	t.check(near_stun > 0.3 and near_stun < near_frag, "a stun beside it shakes it less than a frag does (%.2f px, against %.2f)" % [near_stun, near_frag])
	t.check(far_frag < 0.2, "one 5000 px away does not shake it (%.2f px)" % far_frag)
	await t.seconds(2.5)
	t.check(cam.offset.length() < 0.5, "the camera comes to rest after the shake (offset %.2f px)" % cam.offset.length())
