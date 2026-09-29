class_name Deformable extends Node

## Reusable damage-deformation component for a single primitive-shaped body (furniture).
## Add it as a child of the drawable body; on each `record(hit)` it converts the world
## contact into a local impact (dent, or a carved "missing piece" for a hard hit) and
## emits `changed`, so the owner can redraw its silhouette and rebuild its collider from
## the SAME deformed polygon (via the Deformation static helper). Walls keep their own
## per-segment recording instead (their geometry isn't a single centered shape), but they
## share the Deformation helper and PhysicsConfig knobs.

## Emitted after an impact is recorded, so visuals redraw and the collider rebuilds.
signal changed

## Recorded impacts (local space) that deform the drawn silhouette, and the accumulated
## damage (drives fill darkening). Read by the owner's visuals + collider rebuild.
var impacts: Array = []
var damage_total := 0.0  ## Accumulated dealt damage (drives fill darkening).

var _body: Node2D  ## The deformed body (parent).


func _ready() -> void:
	_body = get_parent()


## Record a damage impact from a HitInfo. Stored in local space so it rides along as the
## body is shoved/spun. `world_pos`/`world_normal` come from the striker's raycast.
func record(hit: HitInfo) -> void:
	var xf := _body.global_transform.affine_inverse()
	var local_pos := xf * hit.position
	var inward := xf.basis_xform(-hit.normal).normalized()  # into the surface
	if inward.length() < 0.01:
		inward = -local_pos.normalized() if local_pos.length() > 0.01 else Vector2.DOWN
	var depth := minf(hit.damage * PhysicsConfig.deform_depth_per_damage, PhysicsConfig.deform_max_depth)
	impacts.append({
		"pos": local_pos, "inward": inward, "depth": depth,
		"chunk": hit.damage >= PhysicsConfig.deform_chunk_damage, "seed": randi(),
	})
	if impacts.size() > PhysicsConfig.deform_max_impacts:
		impacts.pop_front()
	damage_total += hit.damage
	changed.emit()
