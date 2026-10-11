class_name GameLog

## The game's "what is happening" log (shots landing, punches, house seed, Von decisions, perf
## numbers): one `say` that every domain prints through instead of `print`. On by default; the batch test
## runner turns it off so a test run shows only verdicts, and `tools/run_tests.sh --verbose` opts back
## in. Errors and warnings are not routed here — they always reach the engine log (and fail tests).
## A `class_name` static holder, like `PhysicsLayers`: there is no instance and no autoload.

## Whether `say` prints.
static var enabled: bool = true


## Print `message` when logging is on.
static func say(message: String) -> void:
	if enabled:
		print(message)
