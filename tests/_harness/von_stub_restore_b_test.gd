extends GameTest

## Harness self-test: the scripted-Von stub is restored after von_stub_restore_a_test. A test with no von_script must
## see the stub off.


func describe() -> Dictionary:
	return { "name": "Von stub restored (2/2)", "tags": ["harness", "statics", "von"], "internal": true, "timeout": 3.0 }


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	await t.frames(2)
	t.check(not DecisionStub.active, "the stub is off")
	t.check(not DecisionStub.fail, "the stub is not failing")
	t.check(DecisionStub.rules.is_empty(), "no rules left over")
	t.expect_eq(DecisionStub.latency_frames, 0, "no answer delay left over")
