---
name: domain-vehicle
description: Deep implementation detail for the Vehicles domain (scenes/vehicle/) — the drivable car and van: the rigid body and its bicycle driving model (steering, engine, brakes, reverse, the tyre grip solve, the handbrake slide), the doors (swing / slide / rear, eased open amount, the blocked check) and seats, the ride phase machine that walks a character to a door and poses it in and out (CharacterVehicleUse, the character's component), contacts (crashes, characters struck and hurt by closing speed, struck as one pile with what they are pressed against, furniture shoved), the hittable body (dents, debris), the two draw layers and their painters (scenes/vehicle/art/), the `vehicle` / `engine` / `skid` events and VehicleConfig. Use when editing scenes/vehicle/ or working on driving feel, getting in and out, door geometry, vehicle collisions or harm, vehicle art, or the sandbox's vehicles. Complements the `architecture` skill (interface 19 and the others it takes part in); the spec and its tests are docs/vehicles.md.
---

# Vehicles domain

A drivable **car** and **van** (one scene each, inheriting `vehicle.tscn`). Only the sandbox places them
(`sandboxes/vehicle_sandbox.gd`); Main, World-Gen and the match never do, the nav map does not carve them and the AI
does not know them (an NPC sees a parked one only as a solid body). The spec, rule by rule with the tests that pin
it, is `docs/vehicles.md` (V1 to V9).

```
player_controller (E) ─▶ Character.try_use_vehicle ─▶ CharacterVehicleUse ─▶ vehicle.board(character, door) ─▶ VehicleBoarding (the ride)
VehicleBoarding ──(move_input / aim_point, set_ride_pose, end_ride)──▶ Character;  seated driver: move_input / run_input ─▶ vehicle.drive_input
vehicle._integrate_forces ─▶ VehicleDrive.step (the bicycle)   /   contacts ─▶ crash events, characters struck (apply_impulse, take_damage)
vehicle ─▶ Deformable / Physics.spawn_debris / impact_impulse (hittable)   ;   Chassis / Roof (vehicle_visuals.gd) ─▶ painters ─▶ PixelArt
vehicle ──(&"vehicle", &"engine", &"skid")──▶ EventBus ──▶ Sound (Audio);   Camera ──(target.vehicle().view_zoom_out())──▶ vehicle
```

## Files

| File | Role |
|---|---|
| `vehicle_config.gd` (`VehicleConfig`) | Static holder: the shared numbers (getting in and out, driving, collisions, camera, the look) and one `kinds` row per kind (`car`, `van`) plus one `looks` row per kind (the painters' proportions). |
| `vehicle.gd` | Root `RigidBody2D` (control; no `class_name`, cross-file calls through the scene). Body set-up and collider, the drivable contract (interface 19), the hittable contract, seats, doors, rides, contacts, skids and every event the domain posts. Group `vehicles`. |
| `vehicle_drive.gd` | `RefCounted` (preloaded): the bicycle model, stepped inside `_integrate_forces`. Holds `steer_share`, `wheel_angle`, `braking`, `slip`, `rpm`, `engine_load`; `lock(row, speed)` is the full lock at a speed. |
| `vehicle_door.gd` | `RefCounted`: one door in the vehicle's frame: eased open amount, its pose (`angle()` / `offset()`), `stand_point`, `entry_point`, `is_clear`, `info`. |
| `vehicle_boarding.gd` | `RefCounted`: one character's ride, a timed phase machine from E beside the vehicle to its last step out. |
| `character_vehicle_use.gd` | `Node` composed by `character.gd` in code (like `CharacterInteraction`): finds vehicles, picks the door, steps the ride after the controller, abandons it on death, restores collision once the body is clear. |
| `vehicle_visuals.gd` | Draw, on the `Chassis` (`DrawLayers.UNDER_VEHICLE`, −1) and `Roof` (`DrawLayers.ABOVE`, +1) children (`layer` export), which sandwich the occupants (`STANDING`, 0) and cover what lies on the floor (`LYING`, −2: a dead body, casings, a dropped item). |
| `art/vehicle_art.gd` | The painters' shared helpers (vehicle frame → canvas, cached convex regions, door frames, side glass, tail lamps, seats, dashboard, sills). |
| `art/car_painter.gd`, `art/van_painter.gd` | A body, `opts.part` `chassis` or `roof`. |
| `art/door_painter.gd`, `art/wheel_painter.gd`, `art/lamp_painter.gd` | A door (`panel` / `glass` / `mirror`), a wheel, a lit lamp. |
| `vehicle.tscn`, `car.tscn`, `van.tscn` | The base scene (root + `Chassis` + `Roof`); car and van set only `kind` and `color`. The collider is built in `_ready` (runtime-shape convention). |

**Frames.** Rotation 0 = the nose toward +x; a vehicle's own frame has x forward and y toward its right side (left
toward −y). Every door, seat, axle and `looks` entry is in that frame. The art is painted in Art's canonical frame
(front toward +y) and drawn turned by `BODY_TURN` (−π/2).

## The body (`vehicle.gd` `_ready`)

Mass and drag from the row: `mass`, `inertia` = m(L²+W²)/12, a custom centre of mass at the origin, no gravity, damping
replaced by 0 (the model applies its own), `continuous_cd` cast-shape, `contact_monitor` with 8 contacts,
`collision_layer` / `collision_mask` = `PhysicsLayers.SOLID`, a `PhysicsMaterial` from the row's `bounce` / `friction`.
The collider is one `ConvexPolygonShape2D` of `outline()` (the `size` rectangle chamfered by `corner`). A `Deformable`
child records dents (`max_depth` `dent_max_depth`, `max_impacts` `dent_max_impacts`, `allow_chunks` off); nothing
connects its `changed`, so the collider is never rebuilt from the dents.

## Driving (`vehicle_drive.gd`, V5)

`_integrate_forces` reads the contacts first, then `VehicleDrive.step(state, row, intent, running)` writes the body's
velocities for the next step (the engine then moves it and resolves collisions). The intent is
`{ throttle, steer, handbrake, brake }` from `drive_input` (driver only, engine running) or `brake_input` (`brake`: hold to
a stop, never reverse); a cut engine zeroes it.

- **Steering:** `steer_share` (−1..1) moves toward the input at `steer_rate / steer_angle` per s (full lock in the same time at
  any speed) and `wheel_angle` = `steer_share × lock(row, speed)`. `lock` is `steer_angle` while slow; at speed it is
  `atan(steer_demand × holds × wheelbase / speed²)`, `holds` = `grip_front × wheelbase / (2 × rear lever)` (the sideways
  acceleration the front axle holds in a steady turn about the rear axle, which carries rear lever / wheelbase of the force):
  full lock asks the front tyres for exactly what they hold, so it never plows or spins at speed.
- **Along the front:** W pushes `_engine(row, mass, vx)` = `lerp(engine_force/mass, rolling + drag × top_speed², (vx/top_speed)³)`
  (at least 0): full push at rest, tapering to exactly what holds `top_speed` against rolling and drag, so full throttle
  settles at `top_speed` whatever the drag (less past it, so it slows back); × the throttle. S while rolling forward faster than
  `reverse_engage_speed` brakes (`brake × |throttle|`), else reverses with `reverse_force` up to `reverse_speed` (the same
  for W while rolling backward). `rolling` + `drag × vx²` always resist, the handbrake adds `handbrake_brake`; resistance
  moves vx toward 0 and never past it. `braking` (the brake lights) is true while the brakes hold (a held `brake` above
  `stop_speed`, or S/W against the motion).
- **Sideways (the tyres):** a sequential-impulse solve over `tyre_iterations` passes of a front impulse (along the
  turned wheel's normal) and a rear one, each clamped at `grip × mass/2 × dt`; the handbrake leaves the rear
  `handbrake_grip` (0.8 %) of its grip. Within the grip the car goes where the wheels point and pivots about the rear axle;
  past it the axle slides. **Balance:** the rear limit (`grip_rear × wheelbase / (2 × front lever)`) is kept above the front's,
  so at the limit the front slides first (understeer, stable); were the rear the weaker, a fast turn would oversteer into a
  spin. A quick turn-in at moderate speed still scrubs the front a little (the yaw has to be built), which is
  the van's larger `slip` at 240 px/s. The handbrake's share must stay a few px/s² (as locked tyres hold sideways): more damps
  the tail's swing and `vehicle/handbrake_slides_rear` fails. `slip` = the sliding speed
  left after the solve over `max(speed, slip_reference_speed)`, 0..1.
- **At rest:** with no push and under `stop_speed` (and spin under 0.05) the velocities are zeroed: static grip.
- **Engine read:** `rpm` climbs through each of `gears` bands of the top speed (from `idle_rpm` in first gear, from 0.55
  in the others, dropping at each change; a gap of 0.3 or more is jumped at once, a smaller one eased at 3/s) and stays at
  least `idle_rpm + 0.25 × |throttle|` (less of that extra as the speed rises); `engine_load` = |throttle| (0 while braking). Both 0 when the engine is off.
- `can_sleep` is off while the engine runs (the wheels and revs follow the driver at rest).

## Doors and seats (`vehicle_door.gd`)

Each `kinds` row has `seats` (id → local point) and `doors` (`id`, `kind`, `seat`, `hinge`, `handle`, `open_angle` or a
slide's `length`). The car: four `swing` doors (front_left → `driver`, front_right → `passenger`, rear_left / rear_right →
the rear seats). The van: front_left / front_right `swing`, `side` (`slide`, right flank) → `cargo_right`, rear_left /
rear_right (`rear`, swinging out behind about the back corners) → `cargo_left` / `cargo_right` (the side door and the
rear-right door share a seat).

- **Open amount:** progress 0..1, linear in time (`door_open_time` / `door_close_time` for a swing or rear door,
  `slide_time` for a slide), read eased as `amount()` = 1 − (1 − p)² (fast open that settles; a close gathers speed into
  the slam). `update(delta)` returns true on the frame a closing door shuts (the vehicle posts the close then).
- **Pose:** a swing or rear door turns `angle()` = ±`open_angle × amount` about its hinge, the sign chosen so its free
  edge goes outward (`outward`: ±y, or −x for a rear door); a slide door rolls back by `offset()` = −`length × amount`
  along x, standing `slide_pop` px out while it rolls.
- **Stand point** (also the exit spot): `radius + stand_out` out from the body, and on past the handle (away from the
  hinge) until clear of the swing; a slide door's is out from the front of its opening, clear of its track.
  **Entry point:** the middle of the opening, `0.4 × radius` outside the body.
- **`is_clear(vehicle, exclude, radius)`:** one `ConvexPolygonShape2D` query (mask `SOLID`, the vehicle and the user
  excluded) over the swept sector (the door's arm `door_clearance` longer, 7 rays over `open_angle`) or the slide track
  (twice the door's length back, `slide_pop + 2 + door_clearance` deep), then a circle of the user's radius at the
  stand point. A wall, furniture, a character or another vehicle there blocks it.
- **Seats:** `_seats` (id → holder, from boarding start to the last step out) and `_reserved` (a passenger on its way
  across); `is_free(id)` needs both empty. `release(character)` frees its seat and reservation and, for the driver's
  seat, cuts the engine.

## Getting in and out: the ride (`vehicle_boarding.gd`, V1–V4)

**Picking the door** (`CharacterVehicleUse.try_use_vehicle`, E): seated → `vehicle.exit(self)`; on foot → every door of
every vehicle in the group `vehicles` moving slower than `board_max_speed`, whose handle is within `door_reach`, sorted by
distance, and the first whose `board(character, door)` returns a ride wins. `board` refuses at speed, a taken seat, a
character already riding, or a door that is not `is_clear`; on success it takes the seat and adds a collision exception
character → vehicle. Nothing happens on the way in or out, or with no usable door.

**Phases** (`Phase`, stepped by `CharacterVehicleUse.control` every physics frame after the controller, so the ride
overrides that frame's intent):

| Phase | What happens |
|---|---|
| `WALK` | The character walks with its own walk (`move_input`, never `run_input`) along waypoints round the body (`_path`: straight, or round one or two corners of the box inflated by its radius + `walk_margin`), facing turned at `turn_rate` through `aim_point` (where it walks, the handle over the last 18 px). Given up (seat freed, door closed) if the vehicle moves at `board_max_speed` or the walk takes over `walk_timeout`. |
| `OPEN` | `open_door` (posts `door_open` / `slide_open` as a shut door starts to move); it turns to the handle and waits for the door to be fully open and itself within `face_tolerance`. |
| `STEP_IN` | A pose phase to the entry point over `_step_time` (1.5 × distance / (`speed × step_pace`), at least `step_min_time`: the smoothstep's peak stays under the walk). |
| `FOLD` | A pose phase to the seat over `fold_time`, fold 0 → 1, heading turned to forward. |
| `SEATED` | The door closes behind it; the driver starts the engine (`start_engine`: `ignition` + `engine` start). A passenger with a free driver's seat reserves it and takes `SHIFT_SEAT` (`shift_time`, then `change_seat` and the engine). Each frame `_hold_seat` poses it at the seat facing forward, and from the driver's seat `move_input` / `run_input` become `drive_input(-y, x, run)`; the keys are then cleared. |
| `BRAKE` | E while `SEATED`. A driver above `exit_max_speed` holds `brake_input` until under `stop_speed`; a passenger waits for `exit_max_speed`. Then `exit_door`: its own door if its seat is still its own and it is clear, else the nearest clear door whose seat is its own or free; none → back to `SEATED`. The driver cuts the engine here. |
| `SHIFT_OUT` | Only when the exit door belongs to another seat: a slide across to it (`shift_time`). |
| `OPEN_OUT`, `UNFOLD`, `STEP_OUT` | The door opens; the rise to the entry point (`fold_time`, fold 1 → 0, facing outward); the step to the stand point. |
| `DONE` | `release`, the door closes, `character.end_ride()`. |

`is_seated()` is `SEATED`, `SHIFT_SEAT` or `BRAKE`. A **pose phase** eases position and fold with `smoothstep`, turns the
heading at `turn_rate`, keeps positions in the vehicle's frame (so a moving vehicle carries the pose) and hands the
character `set_ride_pose(world point, facing, fold, step)`, `step` = the motion through the vehicle's frame per second ×
(1 − fold), so the legs step with the pose and not with the vehicle. **Death** (`Character._die` → `abandon()`): the seat
is freed, the door left as it is, `end_ride()`.

**After the ride** the character's exception with the vehicle stays until its circle (+`CLEAR_MARGIN` 3 px) no longer
overlaps the body (`CharacterVehicleUse._physics_process`), so stepping out never shoves the vehicle; boarding the same
vehicle again keeps it.

## Contacts and harm (V6)

`_read_contacts` (in `_integrate_forces`) keeps each touching body's strongest contact; the **closing speed** is taken
from the velocities the previous step began with (`_last_velocity`, `_last_spin`) against the other body's velocity at
the point (a `CharacterBody2D`'s own `velocity`, since its server velocity is not its own motion), along the normal out
of the vehicle. A body not touching last step is a new impact.

- **Anything but a character:** a new impact faster than `crash_min_speed` posts `crash` at once with `speed` and the
  struck `get_surface().material` (`""` for a wall or none). Walls stop the vehicle and furniture is shoved by the
  solver natively (a `RigidBody2D` pushable).
- **A pile with a living character** (the `current_item()` probe). The solver treats a character as immovable, so it stops
  the vehicle on one (and any piece pressing one) as on a wall, even on a frame where the character is already moving off.
  So for every contact whose body is a living character or a free pushable piece (`_is_piece`: a non-frozen `RigidBody2D`
  with `apply_impulse` / `get_mass`), `_pile` finds what stands in front: from a character, its own circle (`radius`)
  moved `pile_gap` on along the normal meets the next body (a living character within 60° ahead; anything else only if its
  surface faces the push, `_faces_push` by `get_rest_info` against that body alone; a pushable piece joins, anything else is
  the `blocked`); from a piece, the living characters within `pile_reach` ahead whose circles moved `pile_gap` back meet it.
  At most `pile_depth` members; furniture pressing furniture stays the solver's. No living character in it: as above.
- `_strike_pile`: the pile's speed is its slowest member's own velocity along the normal (a character's `velocity`, its walk
  and knockback, never its motion: one pressed against the vehicle is held back a frame by its slide); the closing speed is
  the vehicle's at the contact from `_last_velocity` / `_last_spin`. Moving off at least as fast: the vehicle's normal
  velocity is set back to `_last_velocity`'s. **Blocked** (a wall behind): the solver's stop stands, a new contact posts
  `crash` with the blocker's material. **Free:** an impulse `J = (1 + e) × closing × m_v m_p / (m_v + m_p)` (`m_p` all the
  members' masses; `e` = `harm_bounce` on a first touch by a character, the row's `bounce` by a piece, 0 while it keeps
  pushing) sets the vehicle's normal velocity to `_last_velocity · n − J / m_v`, and every member slower than the pile's new
  speed `pile speed + J / m_p` is queued a shove up to it (`apply_impulse(n × mass × gap)`: a character's knockback, a
  piece's native pushable). Each living character not in a pile for `rehit_time` (`_piled`, on the vehicle's own `_clock`)
  is queued a blow at `closing × m_v / (m_v + through)` (`through`: the pieces' mass between it and the vehicle). One
  run-in is one blow: the knockback friction stops a struck character faster than the car, which then catches it again.
- `_apply_struck` (in `_physics_process`, outside the flush, where a death may change bodies) applies the shoves and blows:
  `bump_character` (above `crash_min_speed`) and `take_damage(health × inverse_lerp(harm_min_speed, harm_kill_speed,
  speed))`. A dead body met at a contact keeps the vehicle's normal velocity (rolled over) and gets a collision exception (a
  corpse is on no layer but still blocks a rigid body through its mask). `process_physics_priority` −1 runs the vehicle before
  the characters, so a character shoved for the last step's contact moves off in this frame.
- Measured (`vehicle/pinned_character_crushed`, 200 px/s, chair 80, character 40): 0.1 s after the touch the car keeps 168
  px/s in the open, 130 against a character pinned on the chair, 139 striking the chair with the character behind it; harm
  25.4 open and pinned (chair and wall), 17.6 through the chair.

## Hittable (interface 3)

`get_surface()` = `{ coverage, penetration, material, color }` from the row (metal, coverage 70 car / 80 van,
penetration 90). `take_hit(hit)`: `apply_impulse(Physics.impact_impulse(hit), hit.position − global_position)`,
`Deformable.record(hit)`, `Physics.spawn_debris(get_parent(), hit, get_surface())`. No destruction; occupants are not
hit through the body (they have no collision shape while riding). `hit_marks()` = the dents for the visuals.

## Drawing (`vehicle_visuals.gd`, `art/`)

The two layers stand on the world's draw ladder (`DrawLayers`, General, interface 11): the `Chassis` at `UNDER_VEHICLE` (−1) is over
everything that lies on the floor (`LYING` −2: a body struck down and lying under or beside it, casings, a dropped item, a grenade at
rest) and the decals under it, and under the living and the occupants (`STANDING` 0); the `Roof` at `ABOVE` (+1) is over them. Test:
`vehicle/fallen_body_under_vehicle`.

- **Chassis** (under the occupants): the drop shadow (the outline pushed away from `ArtConfig.light_from` by `coverage ×
  drop_shadow_per_coverage`, in world space), the four wheels (`WheelPainter`, the front pair turned by `wheel_angle()`),
  the body's `chassis` art, then each door's `panel` at its pose (turned `frame.turn + angle()` about the hinge, or at
  `hinge + offset()`).
- **Roof** (over them): the body's `roof` art (windscreen, rear window, pillars, roof panel, lamps; the car's roof starts
  at x 10 so a driver's head and hands show through the windscreen), each glazed door's `glass` fading out over the first
  `glass_fade` of its opening, the wing mirrors (the `looks` row's `mirror` doors) swinging with their doors, the brake
  lights while `brake_lights()` (a red glow rect on the ground and `LampPainter` in `tail_on_color`), and the dents
  (`Deformation.draw_marks`).
- **Painters** (`static func paint(c, base, material, opts)`, interface 12) read their geometry from `kinds` and `looks`.
  The body painters paint the cabin through `vehicle_art.gd` (`seats`, `dashboard`, `sills`) and cut holes where each door's
  side glass goes (`clear_door_glass`), since that glass is drawn by the door. The body painters call no `cast_shadows`
  (a body is repainted for every lighting step it turns through, and the pass walks the whole canvas; bevels shade it instead);
  the small door panel does.
- **Regions:** `vehicle_art.region` builds a `PixelCanvas.ConvexShape` (`convex`: each row's and column's first and last
  inside pixel) from a vehicle-frame point test, once per geometry key and canvas size (`_regions`), and reuses it for
  every lighting step: a mask `Shape` would test every pixel on each paint, while a ConvexShape's fill, bevel and outline
  cost its edge. A test must be convex along both canvas axes.
- **Caching:** every texture goes through `PixelArt.render_turned`, lit for the nearest of `ArtConfig.turn_steps` steps
  (`_lit`) and drawn rotated to the exact angle. A layer redraws only when its `_key()` changes: the lighting step, the
  body's turn in `redraw_turn_step` steps (the shadow), each door's amount and the wheel angle in `redraw_step` steps, and
  on the roof the brake lights, the dent count and the newest dent's seed. Once the engine runs, `_warm_ahead` paints the
  body for the other lighting steps one a frame, nearest first, so turning never waits on a paint.

## Events (interface 10)

| Topic | Payload | Posted |
|---|---|---|
| `&"vehicle"` | `{ position, kind, stage }`: `ignition` (vehicle centre), `door_open` / `slide_open` (handle; a shut door starting to open), `door_close` / `slide_close` (handle; the frame it shuts), `crash` (+ `speed`, `material`), `bump_character` (+ `speed`) | `_post` |
| `&"engine"` | `{ vehicle, kind, stage }` `start` / `stop` | `start_engine` / `stop_engine` |
| `&"skid"` | `{ vehicle, stage }` `start` / `stop` | `_update_skid`: start above `skid_start_slip`, stop below `skid_stop_slip` (or at rest) |

Audio voices them and follows the loops by reading `engine_state()`, `slip()` and `speed()` duck-typed (`domain-audio`).

## Tuning (`VehicleConfig`)

- **In and out:** `door_reach` 60, `board_max_speed` 20, `exit_max_speed` 20, `door_open_time` / `door_close_time` 0.35,
  `slide_time` 0.5, `slide_pop` 3, `fold_time` 0.5, `shift_time` 0.6, `step_pace` 0.55, `step_min_time` 0.2, `turn_rate` 9,
  `face_tolerance` 0.25, `walk_timeout` 4, `stand_out` 16, `door_clearance` 3, `walk_margin` 2.
- **Driving:** `stop_speed` 1, `reverse_engage_speed` 2, `tyre_iterations` 8, `slip_reference_speed` 30, `skid_start_slip`
  0.08 / `skid_stop_slip` 0.04, `gears` 4, `idle_rpm` 0.18.
- **Collisions:** `harm_min_speed` 90, `harm_kill_speed` 300, `harm_bounce` 0.4, `pile_gap` 4, `pile_depth` 4, `pile_reach` 150,
  `rehit_time` 0.5, `crash_min_speed` 60, `dent_max_depth` 3,
  `dent_max_impacts` 24. **Camera:** `drive_zoom_out` 0.35 (read through `view_zoom_out()`; General never reads it).
- **Look:** `tyre_color`, `hub_color`, `glass_color` (alpha 0.42: see-through), `interior_color`, `seat_color`, `trim_color`,
  `cargo_floor_color`, `headlight_color`, `tail_off_color` / `tail_on_color`, `brake_glow`, `glass_fade` 0.3, `redraw_step`
  0.02, `redraw_turn_step` 0.01, and `looks` per kind (bumper, bonnet, boot, roof, roof_half, belt, screen_half,
  rear_half, pillars, glass spans per door, a_pillar, door_depth, dash, wheel, mirror doors, head / tail lamp spans, lamp).
- **Kinds** (car / van): `size` 220×110 / 260×125, `corner` 14 / 10, `mass` 400 / 700, `engine_force` 372000 / 350000,
  `top_speed` 1280 / 880, `reverse_force` 160000 / 210000, `reverse_speed` 350 / 250, `brake` 850 / 480, `handbrake_brake` 40,
  `rolling` 25, `drag` 0.00005, axles +70/−66 / +85/−80, `steer_angle` 0.65 / 0.62, `steer_rate` 3.5 / 2.5, `steer_demand` 1 / 1,
  `grip_front` / `grip_rear` 850/1100 / 330/420, `handbrake_grip` 0.008, `bounce` 0.025 (a crash near the top speed rebounds
  under 40 px/s, which rolling stops within a second: `vehicle/crash_into_wall_stops`), `friction` 0.4. Measured:
  top 1280 / 880; 0→640 in 0.75 s, van 0→440 in 0.97 s; stop from the top 1.42 / 1.70 s; full-lock radius at 100 px/s 192 /
  246 px, at 800 / 550 px/s 783 / 943 px with a body slip angle of 0.09 rad (`vehicle/top_speed`, `launch_and_brake`,
  `turn_radius`).

## Tests

The `vehicle` tests domain (`tests/vehicle/`, 30 tests) plus `tests/audio/vehicle_sounds_test.gd`, `tests/audio/vehicle_door_tone_test.gd`,
`tests/general/camera_zooms_out_driving_test.gd` and `tests/general/use_vehicle_key_test.gd`; `docs/vehicles.md` maps each
rule to them. They read the vehicle only through the drivable contract via `tests/_vehicle/vehicle_probe.gd`
(`const Probe := preload(...)`), and place vehicles with `TestSetup.vehicle` (`domain-testing`). `--changed` on
`scenes/vehicle/` runs vehicle, character, items, interaction, projectile, physics, objects, ai, perf, audio and general.

## Gotchas

- **A body added this frame is not in the space yet.** A new `RigidBody2D` joins the broadphase at the next physics step,
  so a shape query (`is_clear`, a probe's ray) on the frame it was added misses it; `TestWorld` waits a physics frame
  after placing vehicles.
- **Characters are immovable to the solver** (kinematic): without `_strike_pile` a car would stop on a character (and on a
  chair pressed against one) as on a wall. The solver stops it even on a frame the character moves off (a character the
  vehicle has pushed into is held a frame by its slide), so a living character's pile is always seen to, not only while
  closing. The shoves and harm are applied in `_physics_process`, not in the flush.
- **A character's real motion is not its pile speed:** pressed against the vehicle its `move_and_slide` barely moves it for a
  frame however hard its knockback, so measuring position deltas reads a stopped body and costs the car speed every frame;
  use its `velocity`.
- **Arena size at these speeds:** a test that runs flat out for a second or turns at full lock needs room (about 1000 px
  a second, a full-lock circle of about 200 px at walking pace).
- **The closing speed must come from the step's start velocities**: the solver has already stopped the vehicle by the
  time `_integrate_forces` sees the contact.
- **A corpse still blocks rigid bodies** (layer 0, but its mask still collides), hence the exception once a struck
  character is dead.
- The character's collision shape is disabled with `set_deferred` on the first ride pose and enabled at `end_ride`;
  the exception (from `board`) covers the walk to the door before that.
- The van's side and rear-right doors lead to the same seat (`cargo_right`): taking one makes the other's seat taken.

**Interfaces:** 3 (hittable), 4 (Vehicles → Physics: `Deformable`, `Physics.impact_impulse` / `spawn_debris`), 5
(pushable), 7 (the `current_item()` probe; the controller fields a ride writes), 10 (EventBus), 11 (`PhysicsLayers.SOLID`, `DrawLayers`),
12 (Vehicles → Art), 19 (Character ↔ Vehicle) — signatures in `architecture`.
