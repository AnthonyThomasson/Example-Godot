extends Node2D

## A dead body's bleed-out pool: a BloodFlow flood-fill claims grid cells in per-frame batches, wrapping
## around walls and furniture into one continuous irregular puddle, then a front eases outward through
## them over the bleed-out duration. Started by `seed_bleed_out` at the point the body's blood leaves it.
## Despawner-tracked. Drawing lives in blood_pool_visuals.gd; this control node owns the fill only.

## Flow cells claimed per physics frame.
const FLOW_CLAIMS_PER_FRAME := 60

## The flood-fill (the visuals draw its cells).
var flow: BloodFlow
## Cells the flow still has to claim, and the seconds its front takes to sweep them.
var _flow_left := 0
var _flow_duration := 1.0

@onready var _visuals := $BloodPoolVisuals  ## The draw layer child.


## Start the pool: `cells` grid cells flowing out from its origin and leaning a random way, filling in
## over `duration` seconds once claimed. `exclude` is the body's RID(s), which the flow ignores.
func seed_bleed_out(cells: int, duration: float, exclude: Array) -> void:
	flow = BloodFlow.new(Vector2.RIGHT.rotated(randf() * TAU), exclude)
	_flow_left = cells
	_flow_duration = duration
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	# Claim the cells a batch per frame (each costs a collider query), then sweep the front.
	if _flow_left > 0 and not flow.done():
		var n := mini(FLOW_CLAIMS_PER_FRAME, _flow_left)
		_flow_left -= n
		flow.step(n, get_world_2d().direct_space_state, global_position)
	else:
		flow.advance(delta, _flow_duration)
		if flow.settled():
			set_physics_process(false)
	_visuals.queue_redraw()
