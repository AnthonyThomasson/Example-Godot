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
## True when the striker passed through the object and `exit_position` / `exit_normal` say where it
## left (a penetrating bullet); false for a ricochet, an embed or a hit with no notion of an exit.
var has_exit: bool = false
## World-space point the striker left the object at (valid when `has_exit`).
var exit_position: Vector2 = Vector2.ZERO
## World-space surface normal at the exit, pointing out of the object (valid when `has_exit`).
var exit_normal: Vector2 = Vector2.ZERO
## Blood the striker carries when it strikes this object, 0..1 (0 = none): a bullet that just passed through a
## character and is still within its carry distance. The object shows it as a bloody mark.
var blood: float = 0.0
## The height the striker flew at, on the 0..100 coverage scale (a bullet's one height), which tells a body where it was
## struck; -1 = none (a blast, which strikes the whole body).
var height: float = -1.0
## The node that caused the hit (the projectile, the character, …). May be null.
var source: Node = null
