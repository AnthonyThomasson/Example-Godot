extends GameTest

## Harness self-test: TestContext decides verdicts correctly from fed log entries and assertions
## (logged warning/error fails, expect_log consumes, allowed/disabled logs pass, no-assertion test
## fails, skip stays skipped). Uses throwaway contexts, so nothing real is logged.


func describe() -> Dictionary:
	return { "name": "Context verdict rules", "tags": ["harness", "context", "log"], "internal": true, "timeout": 3.0 }


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func _ctx(t: TestContext, desc := {}) -> TestContext:
	return TestContext.new(t.world.get_tree(), desc)


static func _entry(severity: String, message: String) -> Dictionary:
	return { "severity": severity, "message": message, "location": "x.gd:1", "line": "" }


func run(t: TestContext) -> void:
	var c := _ctx(t)
	c.check(true, "fine")
	c.on_log(_entry("warning", "stray warning"))
	t.expect_eq(c.conclude(false), "FAIL", "an unexpected warning fails the test")
	t.check(c.is_finished, "and ends it")
	c.free()

	c = _ctx(t)
	c.expect_log("boom")
	c.check(true, "fine")
	c.on_log(_entry("error", "boom happened"))
	t.expect_eq(c.conclude(false), "PASS", "an expected log line is consumed")
	t.check(c.logs.is_empty(), "and not recorded as unexpected")
	c.free()

	c = _ctx(t)
	c.expect_log("never logged")
	c.check(true, "fine")
	t.expect_eq(c.conclude(false), "FAIL", "an expected log line that never appears fails")
	c.free()

	c = _ctx(t, { "allowed_logs": ["noisy"] })
	c.check(true, "fine")
	c.on_log(_entry("error", "noisy thing"))
	t.expect_eq(c.conclude(false), "PASS", "allowed_logs pass")
	c.free()

	c = _ctx(t, { "fail_on_warnings": false })
	c.check(true, "fine")
	c.on_log(_entry("warning", "ignored"))
	t.expect_eq(c.conclude(false), "PASS", "fail_on_warnings off ignores warnings")
	c.free()

	c = _ctx(t)
	t.expect_eq(c.conclude(false), "FAIL", "a non-manual test with no assertions fails")
	c.free()
	c = _ctx(t)
	t.expect_eq(c.conclude(true), "PASS", "a manual test needs none")
	c.free()

	c = _ctx(t)
	c.skip("because")
	t.expect_eq(c.conclude(false), "SKIPPED", "skip stays SKIPPED")
	c.free()

	c = _ctx(t)
	c.require(false, "stop here")
	t.check(c.is_finished and c.conclude(false) == "FAIL", "a failed require ends the test as FAIL")
	c.free()
