# Cover, height and posture

How a bullet decides what it meets, how crouching changes who gets hit, and what an NPC
does with its posture. The tests named under each behaviour assert this document.

Coverage is a **height**, 0 to 100, on one scale for everything a bullet can meet: furniture, walls and
bodies. The pieces: `projectile.gd` (the bullet), `character.gd` and `character_config.gd` (the postures),
`agent_tactics.gd` / `behavior.gd` (how an NPC uses them). See the `domain-projectile`,
`domain-character` and `domain-ai-behavior` skills.

## Behaviours

**H1. A bullet flies at one height.** Each bullet draws a height uniformly from 0 to 100 when it is fired and
keeps it for its whole flight, through ricochets and penetrations. It strikes every collider whose coverage
is above that height and flies over every collider at or below it. A collider of coverage C is therefore
cleared with chance (100 − C) / 100 (coverage 30 is cleared 70% of the time, coverage 100 never), and the same height
serves everything along the path.
`BallisticsConfig.bullet_height` pins it (0 to 100) for tests; negative is random. `cover_flyover_scale`
scales how much is flown over (0: nothing is, every shot meets what it reaches).
Tests: `cover_shared_bullet_height`, `posture_hit_chance`.

**H2. Cover shelters what is lower than it.** A shot that clears a piece of cover has a height at or above
that cover's coverage, so it also clears any body behind it that stands no higher. Worked example: cover of
50 and a standing body of 60. Of 100 shots, 50 meet the cover (and may punch through it to the body, by the
usual penetration), 10 fly over the cover and strike only the body, and 40 miss both. A crouched body (35)
behind the same cover is struck by no shot that cleared it, and the cover stops what it meets.
Tests: `cover_shared_bullet_height`.

**P1. Postures.** A character is standing or crouching (`Character.set_posture`, the player's C toggle). Each is a row of `CharacterConfig.postures`:

| posture | coverage (height) | speed | other |
|---|---|---|---|
| stand | 60 | ×1.0 | can run, can punch |
| crouch | 35 | ×0.6 | cannot run |

A body's `get_surface().coverage` is its posture's, so a crouch is struck by fewer shots in the open
(about 35% of random shots against a standing body's 60%) and hides behind lower cover. Crouching sits below the AI's
`cover_min` (40), so everything an NPC treats as cover hides a crouch. Shooting and reloading work in every posture; running is refused (and costs no
stamina) unless standing.
Tests: `posture_speed`, `posture_player_input`, `posture_hit_chance`.

**P2. Changing posture.** C toggles stand and crouch. A change waits out `posture_change_time` after the last one.
Sitting or lying on an object stands the character up and locks the posture while it lasts; a dead
character takes none and falls from the standing skeleton.
Tests: `posture_player_input`, `posture_interaction`.

**P3. How it looks.** The drawn body eases into its posture (`posture_ease`). A crouch lowers the hips and
pitches the spine forward about the pelvis (`body_crouch_pitch`, 25°, the neck pitching on so the head sits ahead
of and above the shoulders); the pelvis sits back and the chest forward by half the lean, so the body stays
centred over its feet. The hips and feet come closer together than standing, the feet stand a little ahead of
the pelvis so the knees lead over the toes, the foot on the weapon hand's side steps back (a stagger), and the
stride is shorter. A crouch is drawn like a fallen body, from above with its back showing, the weapon and fists
on top. The collision circle is the same in every posture.
The arms stay on the body: the drawn shoulders and head sit at the rig's chest and head, so the forward lean of
a crouch carries them with the sleeves; the hands are held `body_crouch_hand_ahead` further forward, and a fist
beyond the arm's reach draws its shoulder after it.
A gun against a wall: a pistol's hand is pushed back by the wall in every posture. A long gun's barrel is raised
(hands drawn in, barrel shortened) and it cannot fire until it is clear.
Tests: `crouch_rig`, `crouch_arms_attached`, `standing_body_repaints_on_change`.

**P4. Turning takes time.** A standing body faces its aim at once; a crouched one swings round at no more than
its posture's `turn` rate (5 rad/s, about 0.6 s for a half turn). The aim
point is never held back, only `facing`, so the hands, the weapon and every shot follow the slower body. Standing
up catches the body up at once.
Tests: `posture_turn_speed`.

**P5. Legs touch the world.** The legs are swept from the body centre toward where the pose puts them and rest at
the first wall or solid piece they meet (as the hands do), so a stride's toes and a crouch's knees
never draw through anything; a knee that would pass through something moves the foot back. A foot or
knee swinging into a light, pushable piece shoves it, scaled by how fast it moves into it and capped so the piece is
never driven faster than the character walks; a wall or a heavy piece only stops the leg, and a foot at rest shoves
nothing. Other characters stop a leg but are never shoved by it.
Tests: `legs_rest_on_walls`.

**A1. Fighting low.** An NPC fighting in place (an engaged NPC in position, or one holding or reloading
with a hostile known or shots landing) crouches (behind cover, in the open or pinned alike). It is a manner of carrying
out the leaf, not something Von picks, so it works with the server down.
Tests: `posture_crouches_in_fight`, `posture_pinned_crouch`.

**A2. Standing to run.** Anything travelling to a destination, and everything outside a fight, stands; a
crouched NPC stands before it runs and is never crouched while running. A crouch is held
for `posture_dwell` before it is dropped, so a peek and duck does not flicker; standing back up is never
delayed. The `ai.posture` switch (`posture_enabled`) turns it off.
Tests: `posture_stands_to_run`, `posture_crouches_in_fight`.

**A3. What Von is told.** Von's state mentions a posture only when someone is not standing: the NPC's own
("You are crouching.") and a contact it can see ("crouched low"). A standing body adds nothing, so the
existing wording is unchanged. The fact `crouched` is available to the decision tree.
Tests: `posture_in_von_state`.

## Not modelled

Sight does not depend on posture: a low body is seen exactly as a standing one (`see_over_coverage` is 60). A
shooter's posture does not change the height its bullets leave at, and a long gun against low furniture
raises as it does standing.
