class_name HitInfo extends RefCounted

## The data packet passed to a hittable object's `take_hit()`. Whatever strikes an object
## fills it in; the object and the Physics System read it to shove, deform and spray debris.
## Holds no object/projectile references, so Physics stays a leaf domain.

## World-space contact point.
var position: Vector2
## World-space surface normal at the contact (points out of the surface, toward the
## striker). May be near-zero for a point-blank hit.
var normal: Vector2 = Vector2.ZERO
## World-space unit travel direction of the striker at contact (the momentum shove
## follows this).
var direction: Vector2 = Vector2.RIGHT
## Damage dealt by this interaction (already scaled by squareness/speed by the striker).
var damage: float = 0.0
## Striker speed relative to its top speed (0–1+): scales the impact force so a fast
## shot shoves harder. 1.0 for hits without a speed notion (e.g. melee).
var speed_factor: float = 1.0
## True when the striker passed through (penetrated) rather than bounced/embedded.
## The impact transfers less momentum on a pass-through.
var penetrated: bool = false
## The node that caused the hit (the projectile, the character, …). May be null.
var source: Node = null
