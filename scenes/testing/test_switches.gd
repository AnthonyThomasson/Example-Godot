extends RefCounted

## Testing domain: the ONE table of named behaviour switches a test turns on or off with
## `TestSetup.switch(name, on)`. Each row maps a name onto knobs that already exist, as data:
##   actor:  { child, props } — set each of `props` to `on` on that child of every actor that has it
##           (child "" = the character itself), before the actor enters the tree; `controller: true` in place
##           of `child` targets the actor's controller child (the one with `control`, interface 7);
##   world:  { node, props }  — set each of `props` to `on` on that node of the built world;
##   static: [[Script, prop], …] — set each static var to `on`, restored after the test; a row
##           `[Script, prop, off_value]` is for a non-bool knob: on keeps its tuning, off sets off_value.
## To add a switch, add a row; test_world.gd applies them generically.

static var ROWS := {
	&"ai.vision": {
		"description": "NPCs see (off = they only learn of others by hearing, being hit or callouts).",
		"actor": { "controller": true, "props": ["vision_enabled"] },
	},
	&"ai.callouts": {
		"description": "NPCs send and hear team radio callouts.",
		"actor": { "controller": true, "props": ["send_callouts", "hear_callouts"] },
	},
	&"ai.entry": {
		"description": "Invaders enter rooms tactically: stack, slice the pie, cross, take the corners.",
		"actor": { "controller": true, "props": ["entry_enabled"] },
	},
	&"ai.entry_guard": {
		"description": "Any walk into a room that is not cleared goes in by tactical entry (needs ai.entry).",
		"actor": { "controller": true, "props": ["entry_guard"] },
	},
	&"ai.pursuit": {
		"description": "NPCs chase hostiles they have seen.",
		"actor": { "controller": true, "props": ["pursue_hostiles"] },
	},
	&"ai.territory": {
		"description": "NPCs stay inside the house (the defender preset's confinement).",
		"actor": { "controller": true, "props": ["defend_territory"] },
	},
	&"ai.hostile_on_sight": {
		"description": "NPCs treat any non-ally they see as hostile.",
		"actor": { "controller": true, "props": ["hostile_on_sight"] },
	},
	&"ai.hostile_on_trespass": {
		"description": "NPCs treat anyone inside their territory (the house) as hostile.",
		"actor": { "controller": true, "props": ["hostile_on_trespass"] },
	},
	&"ai.hostile_on_attack": {
		"description": "NPCs turn hostile toward whoever attacks them.",
		"actor": { "controller": true, "props": ["hostile_on_attack"] },
	},
	&"ai.posture": {
		"description": "NPCs crouch while fighting in place (off = they always stand).",
		"actor": { "controller": true, "props": ["posture_enabled"] },
	},
	&"nav.rebake": {
		"description": "The navmesh is re-carved as furniture is shoved around.",
		"world": { "node": "NavUpdater", "props": ["enabled"] },
	},
	&"audio.sound": {
		"description": "Shots, impacts, footsteps and reloads make sound.",
		"static": [[SoundConfig, &"enabled"]],
	},
	&"physics.blood": {
		"description": "Wounds splatter and drip blood and dead bodies bleed out.",
		"static": [[BloodConfig, &"enabled"]],
	},
	&"physics.footprints": {
		"description": "Walkers who step in wet blood leave bloody footprints.",
		"static": [[BloodConfig, &"footprints_enabled"]],
	},
	&"physics.smear": {
		"description": "Objects pushed through wet blood smear it into streaks.",
		"static": [[BloodConfig, &"smear_enabled"]],
	},
	&"physics.debris": {
		"description": "Hits spray material chips.",
		"static": [[PhysicsConfig, &"debris_enabled"]],
	},
	&"physics.hit_particles": {
		"description": "Hits burst material particles at the entry and exit points.",
		"static": [[PhysicsConfig, &"hit_particles_enabled"]],
	},
	&"lighting.enabled": {
		"description": "The dusk lighting: ambient, sky, piece lights and fixtures, flashes, and every occluder (off = the art alone).",
		"static": [[LightingConfig, &"enabled"], [LightMasks, &"shadows"]],
	},
	&"projectile.flyover": {
		"description": "Bullets may fly over partial cover (off = every shot meets what it reaches).",
		"static": [[BallisticsConfig, &"cover_flyover_scale", 0.0]],
	},
}


## Whether `name` is a known switch.
static func has(name: StringName) -> bool:
	return ROWS.has(name)


## The row for `name` ({} if unknown).
static func row(name: StringName) -> Dictionary:
	return ROWS.get(name, {})
