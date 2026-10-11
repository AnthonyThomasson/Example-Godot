extends GameTest

## Harness self-test, first of an ordered pair: turns the scripted Von on (and failing) for this test only.
## von_stub_restore_b_test then checks it was switched back off.


func describe() -> Dictionary:
	return { "name": "Von stub applies (1/2)", "tags": ["harness", "statics", "von"], "internal": true, "timeout": 3.0 }


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))
	s.von_down()


func run(t: TestContext) -> void:
	await t.frames(2)
	t.check(DecisionStub.active and DecisionStub.fail, "the stub is active and failing")
