class_name VehicleConfig

## Vehicles domain tuning (a static holder, like CharacterConfig): one row per kind of vehicle in `kinds`, and the
## numbers every vehicle shares (reach, the board and exit speeds, the door and fold times, harm and crash speeds).
## Distances are px, speeds px/s, accelerations px/s², angles rad. Rotation 0 = the nose toward +x; a vehicle's own
## frame has x forward and y toward its right side (its left side is toward -y).

# --- Getting in and out (V1-V4) ----------------------------------------------------------

## E picks a door whose handle is within this of the character.
static var door_reach: float = 60.0
## Boarding only while the vehicle moves slower than this.
static var board_max_speed: float = 20.0
## E while seated above this first brakes the vehicle to a stop (a driver) or waits for it (a passenger).
static var exit_max_speed: float = 20.0
## A swing or rear door eases open in this long (ease-out) and shut in this long (it gathers speed into the slam).
static var door_open_time: float = 0.35
static var door_close_time: float = 0.35
## A sliding door rolls open and shut in this long.
static var slide_time: float = 0.5
## How far (px) a sliding door stands out from the body while it rolls.
static var slide_pop: float = 3.0
## The fold down into the seat (and the rise out of it) takes this long.
static var fold_time: float = 0.5
## The slide across the bench to another seat takes this long.
static var shift_time: float = 0.6
## The step into and out of the gap is taken at this share of the character's walk speed (its peak is 1.5x the average).
static var step_pace: float = 0.55
## The shortest step into or out of the gap (s).
static var step_min_time: float = 0.2
## How fast (rad/s) the character turns while it boards or gets out.
static var turn_rate: float = 9.0
## Facing within this (rad) of the handle counts as facing the door, so the step in can begin.
static var face_tolerance: float = 0.25
## Giving up on a walk to the door that has not arrived in this long (s): something is in the way.
static var walk_timeout: float = 4.0
## The stand point beside a door is this far (px) out from the body, beyond the character's radius.
static var stand_out: float = 16.0
## The swept door (or the stand point) must clear what stands near it by this much (px).
static var door_clearance: float = 3.0
## The walk round the body keeps this far (px) beyond the character's radius off it.
static var walk_margin: float = 2.0

# --- Driving (V5) ------------------------------------------------------------------------

## Below this (with no throttle) a vehicle holds still: the tyres' static grip.
static var stop_speed: float = 1.0
## S reverses (W drives forward again) only once the vehicle is this slow the other way.
static var reverse_engage_speed: float = 2.0
## The tyre impulses are solved this many times a frame (both axles together).
static var tyre_iterations: int = 8
## slip() is the sliding speed over at least this speed (so a slow shuffle does not read as a slide).
static var slip_reference_speed: float = 30.0
## A `skid` starts above this slip() and stops below the second.
static var skid_start_slip: float = 0.08
static var skid_stop_slip: float = 0.04
## The engine's gears: revs climb through each band of the top speed and drop at the change.
static var gears: int = 4
## Revs at idle, as a share of the redline.
static var idle_rpm: float = 0.18

# --- Collisions (V6) ---------------------------------------------------------------------

## A character struck slower than this (closing speed) is shoved, not hurt.
static var harm_min_speed: float = 90.0
## A character struck at this closing speed or faster is killed; between the two, hurt in proportion.
static var harm_kill_speed: float = 300.0
## How much of the closing speed a struck character bounces off with (0 = carried along at the vehicle's speed).
static var harm_bounce: float = 0.4
## A pile in front of the vehicle (a character struck and what it is pressed against, or a piece pressed against a
## character): bodies this close (px) along the push press on one another, at most this many are followed, and a piece's
## characters are looked for within this far (px) of it.
static var pile_gap: float = 4.0
static var pile_depth: int = 4
static var pile_reach: float = 150.0
## A character struck again within this long (s) of the last time it was in a pile is the same run-in: shoved on, not hurt again.
static var rehit_time: float = 0.5
## An impact faster than this posts a crash (or a bump on a character).
static var crash_min_speed: float = 60.0
## The body's dents: deepest (px) and how many are remembered.
static var dent_max_depth: float = 3.0
static var dent_max_impacts: int = 24

# --- Camera (V8) -------------------------------------------------------------------------

## While driving, the camera zooms out by this share at the vehicle's top speed.
static var drive_zoom_out: float = 0.35

# --- Look (V3): the painters' colours, and each kind's `looks` row below ------------------

## The tyres' rubber and the hubs.
static var tyre_color: Color = Color(0.1, 0.1, 0.11)
static var hub_color: Color = Color(0.5, 0.51, 0.53)
## The glass: tinted, and see-through (its alpha), so a seated occupant shows under it.
static var glass_color: Color = Color(0.3, 0.42, 0.5, 0.42)
## The cabin's floor, the seats, and the black trim (bumpers, rubbers, dashboard, grille).
static var interior_color: Color = Color(0.17, 0.16, 0.16)
static var seat_color: Color = Color(0.27, 0.25, 0.23)
static var trim_color: Color = Color(0.12, 0.12, 0.13)
## A van's cargo floor (plywood over the metal).
static var cargo_floor_color: Color = Color(0.45, 0.37, 0.27)
## The lamps: headlights, and the tail lights dark and lit (braking), with the glow a lit one throws on the ground.
static var headlight_color: Color = Color(0.93, 0.92, 0.82)
static var tail_off_color: Color = Color(0.46, 0.09, 0.08)
static var tail_on_color: Color = Color(1.0, 0.2, 0.13)
static var brake_glow: Color = Color(1.0, 0.15, 0.08, 0.3)
## Door glass fades out over the first this share of the door's opening (the window goes with the door).
static var glass_fade: float = 0.3
## The drawing is repainted when the wheels turn or a door moves this much (rad, open share), or the body this much (rad).
static var redraw_step: float = 0.02
static var redraw_turn_step: float = 0.01

## The look of each kind, in the vehicle's frame (x forward, y right; px): how deep the `bumper`s are; where the
## `bonnet` ends at the windscreen's base and the `boot` begins at the rear window's; the `roof` panel's front and back
## x and half width (`roof_half`); the `belt` line's half width (the doors' tops: side glass runs between it and the
## roof); the windscreen's half width at its base (`screen_half`) and the rear window's (`rear_half`); the fixed pillars
## between door glass (`pillars`: [back x, front x]); each door's glass (`glass`: door id -> [back x, front x]); a door's
## thickness seen from above (`door_depth`); the `dash`board's [back x, front x] and the steering `wheel`'s x; which
## doors carry a `mirror`; the lamps' half-width spans (`head` / `tail`: [inner, outer] |y|) and how long they are.
static var looks := {
	&"car": {
		"bumper": 6.0, "bonnet": 58.0, "boot": -86.0, "roof": Vector2(10, -62), "roof_half": 36.0, "belt": 47.0,
		"screen_half": 45.0, "rear_half": 40.0, "pillars": [Vector2(-25, -20)],
		"glass": { &"front_left": Vector2(-20, 58), &"front_right": Vector2(-20, 58), &"rear_left": Vector2(-60, -25),
			&"rear_right": Vector2(-60, -25) },
		"a_pillar": 2.5, "door_depth": 7.0, "dash": Vector2(42, 58), "wheel": 33.0, "mirror": [&"front_left", &"front_right"],
		"head": Vector2(33, 47), "tail": Vector2(31, 47), "lamp": 7.0,
	},
	&"van": {
		"bumper": 6.0, "bonnet": 100.0, "boot": -125.0, "roof": Vector2(50, -125), "roof_half": 53.0, "belt": 56.0,
		"screen_half": 55.0, "rear_half": 0.0, "pillars": [Vector2(20, 26)],
		"glass": { &"front_left": Vector2(28, 100), &"front_right": Vector2(28, 100) },
		"a_pillar": 2.0, "door_depth": 6.0, "dash": Vector2(86, 100), "wheel": 77.0, "mirror": [&"front_left", &"front_right"],
		"head": Vector2(38, 56), "tail": Vector2(40, 59), "lamp": 4.0,
	},
}

# --- The kinds ---------------------------------------------------------------------------

## One row per kind. `size` is the body (length along x, width along y); `corner` its chamfer; `coverage`, `penetration`
## and `material` its ballistic surface (`get_surface`), `bounce` and `friction` its contact with what it strikes. `mass` is the rigid
## body's, `engine_force` (mass x px/s²) drives it up to `top_speed` (the speed full throttle settles at: the push tapers
## to exactly the rolling and drag there), `reverse_force` back to `reverse_speed`; `brake`, `handbrake_brake` and
## `rolling` are decelerations, `drag` the air drag (px/s² per (px/s)²). `axle_front` / `axle_rear`
## are the axles' x, `wheel_size` a wheel's (its look is the kind's `looks` row). The front wheels steer up to `steer_angle`
## (turned there in `steer_angle / steer_rate` s); at speed full lock is the angle whose turn asks the front axle for
## `steer_demand` of the grip it holds (1 = as hard as it holds; more scrubs the front wide). `grip_front` / `grip_rear`
## are the most sideways acceleration each axle holds before it slides (the rear the more, so at the limit the front lets
## go first and the vehicle runs wide rather than spinning); the handbrake leaves the rear `handbrake_grip` of its grip.
## `seats` are local points.
## `doors`: `id`, `kind` (`swing` turns about its front hinge, `slide` rolls back along the body, `rear` swings out
## behind about its back corner), `seat` (the seat behind it), `hinge` (where it turns, or a sliding door's front
## edge) and `handle` (where it is pulled, on the body's edge), `open_angle` for a swing or rear door.
static var kinds := {
	&"car": {
		"size": Vector2(220, 110), "corner": 14.0, "coverage": 70.0, "penetration": 90.0, "material": "metal",
		"mass": 400.0, "bounce": 0.025, "friction": 0.4,
		"engine_force": 372000.0, "top_speed": 1280.0, "reverse_force": 160000.0, "reverse_speed": 350.0,
		"brake": 850.0, "handbrake_brake": 40.0, "rolling": 25.0, "drag": 0.00005,
		"axle_front": 70.0, "axle_rear": -66.0, "wheel_size": Vector2(30, 14),
		"steer_angle": 0.65, "steer_rate": 3.5, "steer_demand": 1.0,
		"grip_front": 850.0, "grip_rear": 1100.0, "handbrake_grip": 0.008,
		"seats": {
			&"driver": Vector2(10, -25), &"passenger": Vector2(10, 25),
			&"rear_left": Vector2(-50, -25), &"rear_right": Vector2(-50, 25),
		},
		"doors": [
			{ "id": &"front_left", "kind": &"swing", "seat": &"driver", "hinge": Vector2(35, -55), "handle": Vector2(-20, -55), "open_angle": 1.2 },
			{ "id": &"front_right", "kind": &"swing", "seat": &"passenger", "hinge": Vector2(35, 55), "handle": Vector2(-20, 55), "open_angle": 1.2 },
			{ "id": &"rear_left", "kind": &"swing", "seat": &"rear_left", "hinge": Vector2(-25, -55), "handle": Vector2(-70, -55), "open_angle": 1.2 },
			{ "id": &"rear_right", "kind": &"swing", "seat": &"rear_right", "hinge": Vector2(-25, 55), "handle": Vector2(-70, 55), "open_angle": 1.2 },
		],
	},
	&"van": {
		"size": Vector2(260, 125), "corner": 10.0, "coverage": 80.0, "penetration": 90.0, "material": "metal",
		"mass": 700.0, "bounce": 0.025, "friction": 0.4,
		"engine_force": 350000.0, "top_speed": 880.0, "reverse_force": 210000.0, "reverse_speed": 250.0,
		"brake": 480.0, "handbrake_brake": 40.0, "rolling": 25.0, "drag": 0.00005,
		"axle_front": 85.0, "axle_rear": -80.0, "wheel_size": Vector2(34, 16),
		"steer_angle": 0.62, "steer_rate": 2.5, "steer_demand": 1.0,
		"grip_front": 330.0, "grip_rear": 420.0, "handbrake_grip": 0.008,
		"seats": {
			&"driver": Vector2(55, -28), &"passenger": Vector2(55, 28),
			&"cargo_left": Vector2(-60, -30), &"cargo_right": Vector2(-60, 30),
		},
		"doors": [
			{ "id": &"front_left", "kind": &"swing", "seat": &"driver", "hinge": Vector2(80, -62.5), "handle": Vector2(28, -62.5), "open_angle": 1.2 },
			{ "id": &"front_right", "kind": &"swing", "seat": &"passenger", "hinge": Vector2(80, 62.5), "handle": Vector2(28, 62.5), "open_angle": 1.2 },
			{ "id": &"side", "kind": &"slide", "seat": &"cargo_right", "hinge": Vector2(20, 62.5), "handle": Vector2(14, 62.5), "length": 65.0 },
			{ "id": &"rear_left", "kind": &"rear", "seat": &"cargo_left", "hinge": Vector2(-130, -62.5), "handle": Vector2(-130, -3), "open_angle": 1.65 },
			{ "id": &"rear_right", "kind": &"rear", "seat": &"cargo_right", "hinge": Vector2(-130, 62.5), "handle": Vector2(-130, 3), "open_angle": 1.65 },
		],
	},
}
