class_name DecisionBudget
extends RefCounted

## AI DECISION sub-domain: how many decision snapshots may start in one physics frame, shared by every NPC. Building
## a snapshot (the perception's `sense()`) is the costliest thing an NPC does in one frame, and NPCs that spawned or
## came under fire together want to decide on the same frame; the controller asks here before it starts one. A
## refused NPC keeps its wish and asks again next frame, so one waits at most a frame per NPC ahead of it. The
## limit is a count, not a time, so when each NPC decides never depends on the machine's speed: a test sees the
## same frames every run, and two NPCs that would claim the same flank side on one frame decide on different
## ones, each hearing the other's radio first (`tests/ai/decision/decisions_spread_over_frames_test.gd`).

## Snapshots that may start in one physics frame. One flattens the cost into a single snapshot a frame; a test
## raises it to see every NPC decide at once.
static var per_frame: int = 1

static var _frame := -1    ## The physics frame the count is for.
static var _started := 0   ## Snapshots started this frame.


## Whether a snapshot may start now: while fewer than `per_frame` have started this physics frame. A true answer
## counts as one started.
static func claim() -> bool:
	var frame := Engine.get_physics_frames()
	if frame != _frame:
		_frame = frame
		_started = 0
	if _started >= per_frame:
		return false
	_started += 1
	return true
