extends GameTest

## Harness self-test, second of an ordered pair (runs after static_restore_a_test): the statics that
## test overrode are back to their defaults.


func describe() -> Dictionary:
	return { "name": "Static override restored (2/2)", "tags": ["harness", "statics"], "internal": true, "timeout": 3.0 }


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	await t.frames(2)
	t.check(BloodConfig.enabled, "BloodConfig.enabled is back on")
	t.check(PhysicsConfig.debris_enabled, "PhysicsConfig.debris_enabled is back on")
