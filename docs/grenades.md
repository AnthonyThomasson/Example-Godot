# Grenades

Two throwable grenades, for the player and for NPCs: a **stun grenade** (flash and bang: blinds, deafens, disorients) and a
**frag grenade** (a blast and real fragments). Behaviours G1 to G19 are the spec; each has a test, named under it, following the
convention of `docs/tactical-entry.md` and `docs/flanking-behavior.md`. The tests are in `tests/<domain>/` and
`tests/ai/grenade/` (`tools/run_tests.sh grenade`; the scenario tests with the real Von server need `--include-von --require-von`),
and read the game only through the interfaces named in the rules, via `tests/_ai/grenade_probe.gd`.

This file was written with the tests, before the feature (issue #35, tests first), and amended as the build and its tests taught what the
rules needed (the amendments to G7, G11, G16, G17 are marked in them).

**Verification (13 October 2026, on the finished branch).** `tools/lint.sh` and the headless load check: clean. The 51 tests this branch adds
(everything under `tests/ai/grenade/` (24), the other grenade, stun, frag and explosion tests, `navigation/furniture_beside_wall_bakes_clean` and
the new `character`, `general` and `items` ones) with `--include-von --require-von --repeat=10`: 510 runs, 510 passed (load average 4.2 before, 2.6 after).
The whole suite with `--summary --jobs=auto --include-von --require-von`: 296 passed, 0 failed, 0 skipped, 0 `gap`. `--domain=perf` alone: 9 of 9 passed
(load average 2.3 before, 2.5 after). No test is tagged `gap`.

## The real-world weapons being simulated

**Frag (the US M67).** A 400 g steel sphere with about 6.5 oz of high explosive, thrown by hand. Its fuze burns 4 to 5 seconds after the
spoon (the lever) is released. The killing radius is about 5 m and the casualty radius about 15 m; fragments are thrown further still.
The thrower is expected to take cover. (GlobalSecurity, Wikipedia: Sources.)

**Stun (the US M84).** A cylinder that makes a flash of 6 to 8 million candela and a bang of 170 to 180 dB, within about 1.5 m. Its
fuze delay is 1 to 2.3 s. The flash blinds (flash blindness) and the bang deafens, gives tinnitus and upsets the inner ear, so a person
is disoriented, confused and loses coordination and balance, for seconds. Both are meant to be temporary. Police use it to
surprise and briefly incapacitate the people in a room so that an entry team can go in with less risk, and the team goes in the moment
it goes off (Wikipedia M84; the 1983 NCJRS abstract; patent US10215544's background: "an infiltration team storms into the room").
The patent's own subject, a device that sets off several charges in sequence, is not modelled.

**Clearing a room.** Doctrine for a room that may hold a threat puts a grenade into it before anyone goes in: a frag when the room is
to be cleared of everyone, a stun when the people in it are to be taken, and the entrants stay out of the doorway's line of sight
meanwhile (the stack, `docs/tactical-entry.md`). A thrower must have a clear path to where it throws, and everyone near a frag is in
its danger zone, the thrower and its own side too.

**What is not sourced.** Almost every number below is this game's, tuned for a top-down demo with 50 HP characters; the real figures
above only set the order of magnitude (a frag that kills close and wounds at a distance; a stun with a fuse about half a frag's,
whose effect lasts seconds). The list of the game's own rules is at the end.

## Behaviours

All distances are px (the game is about 64 px to the metre, so 450 px is about 7 m); times are seconds.

### Carrying and throwing

**G1. Slots.** The stun grenade is slot **7**, the frag grenade slot **8**. Each is a *count* carried (`Item.uses_left()`), spent one per
throw. When the last one is thrown the slot is empty and the character is holding its gun again (the lowest slot that takes ammo, as
`gun_slot()` says), else its fists. Selecting a slot it does not carry does nothing. A grenade is not a gun: while one is held
`gun_slot()` is still the gun, `ammo()` reads no ammo (-1), and `reload()` does nothing. `ItemRegistry.create(7, n)` and `create(8, n)`
make the items with `n` grenades; any other item answers `uses_left() == -1` (unlimited) and `is_throwable() == false`.
`Character.item_count(slot)` reads the count carried in a slot (0 when none). `Character.throw_stats(slot)` reads what a grenade carried in
a slot tells its holder about itself, `{ kind, max_range, danger_radius, fuse, flash_cover_reach, max_blind }` (`GrenadeItem.throw_stats()`, the one dictionary
`GrenadeConfig.stats_of` makes from the kind's row; `ThrownGrenade.throw_stats()` answers the same for a live one; `{}` for any other item or an empty
slot, and `flash_cover_reach` is INF for a frag, whose blast furniture shields from at any distance). These are the numbers the AI throws by (G17): it
keeps no copy of them.
Tests: `items/grenade_last_one_empties_slot`, `items/loadout_grenade_counts` (the registry), `items/grenade_throw_stats`, `items/grenade_throw_stats_blind`.

**G2. Throw.** With a grenade held, left-click (`shoot()`) starts a throw: a short wind-up (`windup` **0.3 s**, the hand drawn back in the
new `throw` stance: `hand_stance(0) == &"throw"` during it and not after) and then the grenade leaves the weapon hand, flying toward the
character's `aim_point` and landing there, within about 40 px, but no further than `max_range` **450 px** (about 7 m): aimed past that,
it first touches down at the cap and may roll on a little (up to 100 px). The fuse starts on release; there is no cooking (holding it
with the pin pulled). A throw cannot start while another is under way, while running, reloading or busy, and a character that dies
during the wind-up throws nothing. The throw posts `&"throw"` `{ position, kind, attacker }` (`kind` is `&"stun"` or `&"frag"`). The
spoon pops off as a tiny prop.
Tests: `items/grenade_throw_lands_at_aim` (lands near the aim, count 2 to 1, the event, the stance, the 0.3 s wind-up),
`items/grenade_throw_range_capped`, `items/grenade_none_dropped_on_death` (dying mid-wind-up).

**G3. Flight.** The grenade flies a lob on a pseudo-height (as a `DroppedItem` falls). It passes over furniture whose `coverage` is below
the arc's height at that point (tables 45, beds 35, sofas 45) but strikes walls and tall furniture (wardrobes 95, bookshelves 90), and
bounces off with energy loss (`restitution` **0.35**), and bounces off characters it hits. Once down it skids and rolls to a stop
(`friction`). Nobody picks it up or throws it back. Every bounce posts `&"grenade"` `{ position, kind, stage }` with `stage = &"bounce"`,
and the resting grenade posts `stage = &"rest"` once; the Audio domain voices a bounce (G14's sounds). A grenade in flight or on the
floor, until it goes off, is a node in the group `live_grenades` with `kind`, `fuse_left()`, `danger_radius()` (a frag's 250 px blast
radius, a stun's 400 px flash radius), `throw_stats()` (below) and `thrower`.
Tests: `items/grenade_bounces_off_wall`, `items/grenade_lobs_over_table_not_wardrobe`.

**G4. Death.** A dead character's unthrown grenades vanish with it: nothing is dropped, and nothing is ever live in a dead hand.
Test: `items/grenade_none_dropped_on_death`.

**G5. Loadout.** The setup window carries a **Stun** and a **Frag** count per side, 0 to 3 each; the side dict has the integer keys
`stuns` and `frags`. The defaults are invaders 1 + 1 and defenders 0 + 0. They are saved with the rest of the setup (a save from before the grenades, which names no counts, keeps these defaults). In code,
`LoadoutConfig.normalize` keeps `stuns` / `frags` in 0..3, `LoadoutConfig.apply` gives the character that many in slots 7 and 8, and
`LoadoutConfig.grenade_options()` lists the two rows for the window (`[{ id: &"stun", label, slot: 7, max: 3 }, { id: &"frag", ..., slot: 8, ... }]`;
`options()` stays Random plus one entry per gun).
Tests: `items/loadout_grenade_counts`, `general/saved_setup_grenade_counts`.

### Frag grenade

**G6. Fuse.** **3.0 s** from release.
Test: `items/grenade_throw_lands_at_aim`.

**G7. Blast.** *(Amended after the tests phase: "frag out, take cover".)* When it goes off every hittable body with a clear line from the blast
point within `blast_radius` **250 px** takes blast damage: the full `blast_damage` **60** (a character has 50 HP) out to `kill_radius` **120 px**,
falling linearly to 0 at 250 px (`60 * (250 - d) / 130` between), measured from the blast point to the body's centre. Walls block the line.
**Cover:** a piece of furniture between the blast and a character blocks it too when its `coverage` is above the character's posture height (the
character's own `get_surface().coverage`: crouched 35, standing 60). So a crouched character behind a couch (45) is shielded and a standing one is
not; a coffee table (30) shields nobody. Fragments already behave so (they fly at a height, `docs/cover-and-stance.md`). The blast reaches
characters and objects alike through `take_hit` (so characters bleed, a character's torso armour cutting the damage by its `blast` share: `docs/outfits.md` O9; objects deform and shed debris), and each blast hit posts `&"hit"` with
`outcome = &"blast"`. Pushables in range are shoved away from the blast by `blast_impulse`, falling off with distance: furniture, living
characters (as knockback) and the ragdolls of the dead. The burst posts `&"explosion"` `{ position, kind, attacker, radius }`.
Tests: `projectile/frag_blast_by_distance` (80 px dead, about 200 px hurt by the fall-off, 400 px no blast, an object struck),
`projectile/frag_blast_blocked_by_wall`, `projectile/frag_blast_low_cover_by_posture` (behind couches: crouched, no blast; standing, the blast),
`physics/frag_blast_pushes`.

**G8. Fragments.** `fragments` **40** real projectiles leave the blast point evenly round the circle (jittered), through
`ProjectileSpawner`, with low power (`penetration` 0.4, `fragment_damage` 12, fast) and a short reach (`fragment_range` **500 px**: a
projectile can now be given a maximum range, past which it is spent). So cover, penetration, ricochet, blood, debris and impact sounds
all work as for bullets (a character's armour and hit zones too: `docs/outfits.md` O9), and each hit posts `&"hit"` with the thrower as `attacker`.
Test: `projectile/frag_fragments_hit`.

**G9. Friendly fire.** Grenades hurt and stun everyone: the thrower and its allies are not spared.
Test: `projectile/grenade_friendly_fire`.

### Stun grenade

**G10. Fuse.** **1.5 s** from release.
Test: `character/stun_flash_by_sight`.

**G11. Flash (by sight).** *(Amended after the AI phase: furniture only shields from the flash at the face.)* A character with a clear line of sight to the burst (walls block it; a piece of
furniture taller than the character blocks it only when the character is within `flash_cover_reach` **30 px** of it, on the burst's side, hunched right against it: the light comes round and over a
piece that is not at its face, so a crouched character 120 px behind a couch is flashed and one against it is not) within `flash_radius`
**400 px** is flash-blinded for up to `max_blind` **5 s**, scaled by distance (full inside 100 px, falling linearly to nothing at
400 px) and by how much it faces the burst (the dot of its facing with the direction to the burst: facing it, x1; side-on, x0.6; back to
it, x0.25; linear between those). So `blind = 5 * clamp((400 - d) / 300, 0, 1) * facing_factor`. No line of sight, no flash. The
burst posts `&"explosion"` and each character stunned posts `&"stun"` `{ character, position, blind, deaf, from }` (G13; `from` is the burst point).
Tests: `character/stun_flash_by_sight`, `character/stun_flash_cover_reach` (a crouched victim against a couch is not flashed; one 120 px behind a couch, the couch still on the line, is).

**G12. Bang (by range).** Every character within `bang_radius` **350 px** is deafened and disoriented for up to `max_deaf` **6 s**,
scaled by distance (`deaf = 6 * (1 - d / 350)`); through a wall the effect is x0.4, but furniture muffles nothing: a character out of the flash
behind a couch or a wardrobe is deafened for the whole of its distance. Within `point_blank` **30 px** it also takes
`point_blank_damage` **5**. A stun does no other damage.
Tests: `character/stun_bang_by_range`, `stun_bang_through_furniture`.

**G13. Being stunned** (the character, for the player and an NPC alike). While disoriented a character moves at most `stun_speed` **x0.45**
of its speed, with a slow drift, cannot run, and its aim sways: a wandering offset of up to `stun_sway` **25 degrees**, applied to
where its shots go. The effect tails off over the last `recover_tail` **1.5 s** (the level falls linearly from 1 to 0 over that time),
and then it is as before. `Character.take_stun(blind, deaf, from)` applies it (and posts `&"stun"`), `is_blind()`, `is_deaf()` and
`stun_level()` (0..1) read it, `stun_view()` gives `{ blind, blind_total, deaf, level }` (seconds left blind and deaf, the blind
seconds at the burst, the level) to the UI, and a new stun takes the longer of the old and new timers, blind and deaf each. The four numbers live in
`CharacterConfig` (they tune the body, not the item). A character also tells a controller what it needs to judge a place in time: `posture_coverage(posture)` (the
height of the body standing and crouched, on the coverage scale) and `run_speed()` (px/s standing and running, slower while stunned or weighed down by the outfit), so the AI keeps no copy of either.
Tests: `character/stunned_slow_and_sway`, `character/posture_and_run_reads`.

**G14. The stunned player.** The player's screen goes white at the burst and fades back over the blind time through a frozen afterimage
of the moment of the flash (`StunScreen`, `watch(character)`, `drawn()` -> `{ white, afterimage, remaining }`); a bang that only deafens
whitens nothing, and nothing happens for someone else's flash. Game audio is muffled (a low-pass) with a synthesized tinnitus whine over
the deaf time, but only for the character `Sound.focus` names (Main sets the human): a `&"sound"` of kind `&"tinnitus"` (profile
`tinnitus/...`) once per deafening of the focus, and `Sound.muffled()` true while it is deaf. The grenades sound in the world: the throw
(kind `throw`, profile `throw/...`), each bounce (kind `grenade`, profile `grenade/.../<floor under it>`), the frag (kind `explosion`,
profile `explosion/frag`: big, low, a long tail) and the stun's bang (`explosion/stun`: sharp, very loud, short). The camera shakes
on `&"explosion"` by distance and kind (`Camera2D.offset`: a frag beside it hardest, farther less, none far off, a stun less than a
frag), and the burst has its look: a flash, a fireball puff and smoke, with a scorch left under a frag, a white flash and thin smoke for
a stun (`Physics.spawn_explosion`, off with `PhysicsConfig.explosion_fx_enabled`).
Tests: `ui/stun_screen_whiteout`, `audio/grenade_sounds`, `general/camera_shakes_on_explosion`, `physics/explosion_fx`.

### AI

**G15. A stunned NPC.** While blind it sees nothing new (no sightings; contacts age as usual, so what it holds of a hostile stays at the
spot it last saw it) and starts no new decision; it stumbles, slowed and drifting, and may **fire blindly** at the last-known position
of a hostile it knew (with the sway: no shot strays more than 25 degrees off that spot). While deaf it hears no gunfire, no hits
elsewhere and no radio callouts. When the blindness lifts it re-decides from what it sees, still disoriented for the tail.
Tests: `ai/grenade/stunned_defender_blind`, `ai/grenade/deafened_npc_ignores_gunfire`.

**G16. React to a live grenade** *(amended after the tests phase: "frag out, take cover")* (a reflex outside Von, like auto-reload; it takes priority
over every primitive, committed or not). An NPC that *sees* a live grenade (in its view cone with a clear line) or *hears* one land within
`hear_grenade` **300 px**, and is inside its danger zone, radios a `grenade` callout and runs to the nearest **safe spot** it can reach before the
fuse is out. A spot is safe in either of two ways, and the NPC takes whichever is nearer: **out of line** (out of the grenade's line of sight, round
a wall corner or a doorway, or outside its danger zone, defined below: beyond the radius and the margin), or **behind cover** that shields it from the blast (G7): it crouches behind that furniture, and
a crouched character behind cover is as clear as one out of line. It then holds there, facing away or crouched, until the detonation, and
re-decides. The danger zone of a frag is a clear line to the landing within `blast_radius` plus `evade_margin` **120 px**, so **370 px**; of a stun,
a clear line within `flash_radius`, **400 px**; a stun's cover spot counts as clear only under G11's rule (furniture within `flash_cover_reach` of the body; the planner's candidates include a spot
right against the far face of whatever stands near the burst). If it cannot get clear of a stun in time, it turns its back to it (so the flash blinds it for the
back-turned share only). Allies within `callout_range` who are in that zone react the same way to the call, even when they neither saw nor heard the
grenade. A grenade it threw itself it knows about: in flight, at the spot it aimed at (no further than a throw reaches), not at the hand it just left,
and once it has come down wherever it lies. The callout is `status = &"grenade"` with `point` (the landing) and `kind`;
`GoalController.debug_grenades()` reports
`{ known: [{ point, kind, fuse_left, radius, source: &"seen" | &"heard" | &"called" | &"own" }], escape: Vector2 (Vector2.INF when it is
not running to one), throw: {} }`.
Tests: `ai/grenade/evade_frag_seen`, `ai/grenade/evade_frag_ally_warned`, `ai/grenade/evade_stun_turns_away`,
`ai/grenade/evade_frag_crouches_behind_cover` (the amendment: a couch nearer than any way out of line, the defender crouches behind it).

**G17. The GRENADE tactic (combat).** *(Amended after the tests phase: "frag out, take cover".)* A new COMBAT tactic (decision-tree id `grenade`),
offered when the NPC carries a grenade and the bound hostile's last-known spot is within throw range (450 px), has a clear throw path (no wall or
tall furniture between; low furniture is fine) but is **hidden from its line of fire** (behind cover, in the sense that a bullet would be stopped: low
furniture, a corner). Its options are "frag {target} behind their cover" and "stun {target}" (only the kinds it carries). It is never offered
- when a **known ally** would be inside that grenade's danger zone (G16) at the landing spot (the option's tag `ally_in_blast`, in the tactic's
  `drop_tags`);
- when the **NPC itself** would be inside the zone **and has no way to get safe before the fuse runs out** (tag `no_safe_spot`): it is safe if it
  can crouch behind cover that shields it from the landing spot (G7), or reach a spot out of the blast's line of sight in time. With a way to get
  safe, being inside the zone does not drop the option;
- against a hostile in its line of fire (it shoots).

The leaf runs the new `throw` primitive: it selects the grenade, aims at the spot, throws, radios `frag_out` / `bang_out` (callout `status`, as the
grenade leaves the hand: `point` the landing, `kind`), puts the gun back in hand, then takes whichever safety is nearer (the G16 plan, which knows
its own grenade: crouch behind that cover, or move out of line) and **holds it until the detonation**, then re-decides (after a stun it naturally
goes on to ADVANCE or ENGAGE while the target is blind: a hostile the NPC, or an ally, caught in the flash of a stun it threw reads "blinded by a flash"
in the state and the ADVANCE option, for a few seconds, `flashed` in memory). A thrower outside the zone has nothing to hold: it waits out the fuse
with the gun in hand and shoots what it can. The NPC decided on a snapshot of a moment ago, so when the order is adopted it may stand a few px past its range
of the spot: it then closes in until it is `THROW_RANGE_SLACK` (15 px) inside it and throws (it does not give the throw up and flap in and out of the offer at
the edge of the range). The throw is dropped, and the NPC re-decides, if the lob has become impossible (blocked by something taller than a lob clears) by the
time the wind-up starts; once the wind-up has begun the throw is committed and radioed whatever happens to the line meanwhile.
Options are `frag` and `stun`. What the AI knows of a grenade it has not thrown yet (how far it throws, its blast or flash radius, its fuse, how
near furniture must be to shield from a flash) it reads off the grenades it carries, `Character.throw_stats(slot)` (G1), and off a live one it sees
(`ThrownGrenade.throw_stats()`); it keeps no mirror of the numbers, so retuning a `GrenadeConfig` row retunes the AI (the tests
`items/grenade_throw_stats` and `ai/grenade/grenade_range_follows_the_item`). What stays the AI's own tuning are the `GoalController` exports of the
Grenades group: `hear_grenade`, `evade_margin`, `grenades_enabled`. `debug_grenades().throw` holds `{ from, to, kind, radius }` while the throw is planned (until the grenade leaves the hand).
Tests: `ai/grenade/grenade_not_offered_ally_in_blast` (an ally in the zone), `ai/grenade/grenade_not_offered_no_safe_spot` (the thrower in the zone
with a coffee table that shields nobody and nothing to hide behind: dropped; the same with a couch at hand: offered),
`ai/grenade/grenade_not_offered_clear_shot`, `ai/grenade/throw_primitive_returns_to_gun` (the mechanism, scripted Von: the far thrower throws and
returns to its gun after the bang; the near one crouches behind its couch until the bang, is unhurt, then returns to its gun);
`ai/grenade/grenade_range_drift` (scripted Von, slow answers: a thrower pushed past the range while its question is in flight closes in and throws, GRENADE picked once),
`ai/grenade/throw_dropped_when_lob_blocked` (a wardrobe across the lob while the question is in flight: nothing thrown, the grenade kept, Von asked again),
`ai/grenade/throw_committed_in_windup` (a wardrobe across the lob as the hand is drawn back: the grenade still leaves and is radioed);
`ai/grenade/combat_frag_hidden_hostile` (a thrower outside its zone), `ai/grenade/combat_frag_take_cover` (inside it, with cover at hand: throws,
crouches until the bang, unhurt), `ai/grenade/combat_stun_then_advance` (the scenarios, real Von).

**G18. Bang entry (SEARCH, then ENTER).** When the NPC (or its stack, by the claims on the radio) carries a stun, SEARCH offers two entry
tactics: **ENTER** (quiet, as before) and **STUN ENTRY** (`stun_entry`: "a doorway leads into a room where gunfire was heard or a hostile was seen going in";
Von picks against the facts, worded as measured below). The first claimer's mode travels with its claim and the stack follows it.
In a bang entry, once the stack is ready: the **thrower** (the slot-2 member if it carries a stun, else the lowest slot that does; alone,
itself) radios `bang` (`entry_step = &"bang"`, phase `bang` between `stack` and `cross`), throws the stun to the room's far side through the
doorway, and every member holds its slot turned away from the door; on the detonation the point **skips the pie** and crosses at once,
the rest follow as usual (E4 to E8 of `docs/tactical-entry.md`). If the throw is impossible (no stun left, no clear path into the room) it
falls back to a quiet entry; so it does when the call never comes (`BANG_CALL_CAP` 8 s after the stack is ready) or the stun does not go off (`BANG_BURST_CAP`
5 s after the call), and a member that sees a teammate's claim say quiet goes in quietly at once, its own claims saying so. Frags are not used at entry. Where nothing suggests the room is occupied, ENTER is the pick and nothing is thrown.
How it is made to happen (E17 of `docs/tactical-entry.md` has the rest): the entry callouts carry `bang` and `stuns`; the stack is in bang mode only if every
claim says so; the thrower steps out in front of the door (`BANG_STEP_OUT`) so that its throwing hand, 28 px to its right, is clear of the jamb, and
aims at the room's far side (85% of the room's depth, on the doorway's axis if the lob is clear). A stun grenade in flight in the doorway is not evaded by the
stack members, who hold turned away beside the wall (G16 still moves anyone else). With a stun in the stack, gunfire heard or a hostile last seen in a room a doorway leads into is
not an INVESTIGATE lead but part of the entry's wording ("gunfire heard there", "a hostile seen going in"; the room's doorway is listed first), so
Von weighs a bang against a quiet entry (measured: STUN ENTRY 0.42 to 0.44, ENTER 0.34 to 0.37 with the gunfire; the other way round without it).
Tests: `ai/grenade/stun_entry_suspect_room`, `ai/grenade/quiet_entry_unsuspected_room` (the real Von server) and, scripted, one fallback each:
`ai/grenade/bang_fallback_no_clear_lob` (wardrobes across the kitchen), `bang_fallback_stun_lost` (the thrower's stun gone after its call: the rest follow within seconds,
not after the burst cap), `bang_fallback_never_called` (a teammate that is ready and never calls), `bang_fallback_never_goes_off` (a call and no throw).

**G19. Debug overlay** `show_grenades` (a row of the overlay table, a child of every NPC, in the AI behaviour group): the planned throw arc and
landing spot with the grenade's danger radius, the live grenades the NPC knows of with their radii and fuse left (a countdown arc against the grenade's whole `fuse`), and the escape spot it
is running to. It draws from `debug_grenades()`.
Test: `ai/grenade/grenade_overlay_draws`.

## How the rules are enforced

- **Items** (`scenes/items/`): `GrenadeConfig` (the numbers above, one row per kind), `GrenadeItem` (count, wind-up, `throw` stance),
  `ThrownGrenade` (flight, bounce, fuse), the art, `ItemRegistry` (`STUN_SLOT`, `FRAG_SLOT`, `create(id, count)`), `LoadoutConfig`.
- **Character**: `item_count`, `throw_stats`, `aim_target`, `posture_coverage` and `run_speed` (what the AI judges a place in time by), the stun state
  (`take_stun`, `is_blind`, `is_deaf`, `stun_level`, `stun_view`; its numbers are `CharacterConfig`'s) and its effect on speed, running and aim, `blast_push` for ragdolls.
- **Projectile**: `Explosion.frag` / `Explosion.stun`, and `ProjectileSpawner.spawn`'s `max_range`. **Physics**: the explosion FX.
  **Audio**, **General** (camera, EventBus topics `throw`, `grenade`, `explosion`, `stun`), **UI** (`StunScreen`, the setup window,
  the overlay table) and **AI** (perception of live grenades, the throw geometry, the `grenade` and `stun_entry` nodes, the `throw`
  primitive, the evade reflex, the bang phase of `entry.gd`, the overlay).
- **The tests reach all of it duck-typed** (`has_method`, `call`, groups, topics, node ids), because most of it did not exist when they
  were written.
- **Cover** is read off `get_surface().coverage` of what lies between the blast and the character, against the character's own posture coverage;
  the tests read it with `Probe.shielded` (a ray from the blast, character bodies excluded).
- **Scenario tests** run the whole pipeline with the real Von server, the rest of the AI on and nothing scripted. Their premises are the
  puppet thrower in the evade scenarios (an invader puppet that cannot be killed, armed with one grenade the way Main arms a spawn), the
  hostile puppet that cannot be killed and never shoots in the combat scenarios, the one shot of gunfire heard in the stun entry, and the
  `take_stun` call that stands in for a grenade in the two NPC-effect scenarios (the throw itself is tested elsewhere). No behaviour switch is used in
  a scenario test: the deaf-NPC scenario has only two household defenders, so trespass hostility has nobody to act on without being switched off. The test world keeps
  the default inventory, so each scenario arms its invaders at the start of `run` with `LoadoutConfig.apply`, as Main does.

## Numbers

| | Stun | Frag |
|---|---|---|
| Slot | 7 | 8 |
| Fuse (from release) | 1.5 s | 3.0 s |
| Throw | wind-up 0.3 s, `max_range` 450 px, `restitution` 0.35 | same |
| Flash / blast radius | `flash_radius` 400 px (full inside 100) | `blast_radius` 250 px (full inside `kill_radius` 120) |
| Effect | blind up to 5 s; deaf up to 6 s within 350 px (x0.4 through a wall); 5 damage within 30 px | 60 damage; 40 fragments of 12 damage, penetration 0.4, 500 px reach |
| Danger zone (AI) | line of sight within 400 px; furniture shields only within 30 px of the body (`flash_cover_reach`) | line of sight within 370 px (250 + 120 margin); a crouched body behind cover above 35 is shielded (G7) |
| Heard landing (AI) | 300 px | 300 px |

The stun on the character: speed x0.45, sway 25 degrees, no running, tail 1.5 s.

## This game's own rules

Everything numeric in the tables, and in particular: the sizes of the radii and times (the real ones only set the order of magnitude);
the linear falloffs of the blast, the flash and the bang; the facing factor of the flash (x1, x0.6, x0.25); x0.4 through a wall; the
stun's effect on a character (G13); the lob over low furniture and the bounce off tall furniture and walls (G3); a grenade's lack of
cooking, pick-up and throw-back; the loss of every unthrown grenade at death (G4); friendly fire (G9, a fact of the real weapons, but the
absence of any rule to spare an ally is the game's); the evade reflex and its margins (G16); the GRENADE tactic and its dropping rule (G17);
the bang entry and its roles, including the turn-away hold and the point that skips the pie (G18); fragments stopped at 500 px; the
setup defaults of 1 + 1 for invaders (G5).

## Sources

How far each is to be trusted. Mixed quality; none is current doctrine for a game, and the figures are only used for scale.

- GlobalSecurity, [M67 fragmentation hand grenade](https://www.globalsecurity.org/military/systems/munitions/m67.htm): the fuze of 4 to 5
  seconds, the killing radius of about 5 m and the casualty radius of about 15 m (G6, G7, G8). The same figures are in the US Army-derived
  DOD 101 summary (`man.fas.org/dod-101`), which a search returned; this page itself could not be fetched while writing, so its wording
  has not been checked.
- [Wikipedia, M67 grenade](https://en.wikipedia.org/wiki/M67_grenade), as a search summary: the body (2.5 in steel sphere, about 6.5 oz
  of explosive), the M213 fuze of 4 to 5.5 s. The Nammo M67 data sheet was on the source list but was not read.
- [Wikipedia, M84 stun grenade](https://en.wikipedia.org/wiki/M84_stun_grenade): the fuse delay of 1 to 2.3 s, a flash of 6 to 8 million
  candela (4.5 in the text) and 170 to 180 dB within 1.5 m, and the effects: flash blindness, deafness, tinnitus, inner-ear disturbance,
  disorientation and loss of balance (G10 to G13). It gives no duration or safe distance, so the 5 s, 6 s, 400 px and 350 px are the
  game's own.
- NCJRS / OJP, [Stun grenades: uses and tactics](https://www.ojp.gov/ncjrs/virtual-library/abstracts/stun-grenades-uses-and-tactics)
  (Law and Order, 1983): the light and sound surprise and briefly incapacitate people so that an attack team can enter with less risk,
  and attack timing matters (G18). Seen only as its abstract, through a search summary.
- Patent [US10215544](https://patents.google.com/patent/US10215544B2/en), a multi-charge diversionary device: its background describes
  the conventional entry, "an infiltration team storms into the room" after the stun grenade goes off (G18). The device itself is not modelled.
- USMC / Boise State military science, [building and room clearing guide](https://boisestate.edu/sps-militaryscience/wp-content/uploads/sites/123/2014/04/building-clearroom.pdf):
  the general practice of putting a grenade into a room before the entrants cross, from beside the door. The PDF could not be read while
  writing (its text is compressed and no PDF tool was available), so nothing specific is quoted from it and G18 and G17 do not rest on it.
- G15's blind fire, G16's whole reflex, the GRENADE tactic's conditions and the stun's disorientation of the character are this game's,
  not sourced.

## Not modelled

Cooking a grenade, picking one up, throwing it back or kicking it away; grenades in the dropped-item pile; breaching charges and closed
doors (issue #21); smoke and gas grenades; frags at entry; defenders reacting to a stack at their door beyond G16; grenades setting
anything on fire; structural damage to walls beyond the usual deformation; the patent's multi-charge device; hearing damage and permanent
injury; a grenade rolled along the floor; any use of stairs or heights.
