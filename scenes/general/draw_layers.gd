class_name DrawLayers

## General domain: the world's draw-order ladder, shared read-only infrastructure (like `PhysicsLayers`). Every domain
## that draws on, under or over the standing world sets its `z_index` from one rung here, so what lies on the floor,
## what a vehicle covers and what flies over it keep one order however the domains change. Bottom to top:
##   FLOOR < RUG < BLOOD < LYING < UNDER_VEHICLE < STANDING < ABOVE < EFFECTS
## Within a rung the scene tree decides (later draws over).

## The room floors (Objects' `Floor`).
const FLOOR := -5
## Rugs and mats: on the floor, under blood, so a pool shows on them (Objects).
const RUG := -4
## Blood on the floor (splats, pools, prints, smears) and a frag's scorch: the decals (Physics).
const BLOOD := -3
## What lies on the floor over the decals: a dead body (Character), spent casings (Projectile), a dropped item and a
## grenade at rest (Items). A vehicle drives over all of it.
const LYING := -2
## A vehicle's under layer, its `Chassis` (shadow, wheels, body, doors): over what lies on the floor, under its
## occupants (Vehicles).
const UNDER_VEHICLE := -1
## The standing world: living characters (a vehicle's occupants among them), furniture and walls. Godot's default z.
const STANDING := 0
## Over the standing world: a vehicle's `Roof` (Vehicles), a grenade in flight (Items) and the stack markers (UI).
const ABOVE := 1
## A grenade's burst, its flash, fireball and smoke, over everything (Physics).
const EFFECTS := 4
