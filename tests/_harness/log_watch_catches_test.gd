extends GameTest

## Harness self-test: LogWatch really sees what the engine writes to its log file. The test logs a
## warning and an error on purpose and declares both with expect_log; if LogWatch missed either, the
## unmet expectation fails the test.


func describe() -> Dictionary:
	return { "name": "LogWatch sees engine logs", "tags": ["harness", "log"], "internal": true, "timeout": 4.0 }


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	t.expect_log("harness probe warning")
	t.expect_log("harness probe error")
	await t.seconds(0.1)
	push_warning("harness probe warning")
	push_error("harness probe error")
	await t.seconds(0.5)
	t.check(true, "reached the end with both lines expected")
