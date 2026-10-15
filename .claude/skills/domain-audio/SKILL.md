---
name: domain-audio
description: Deep implementation detail for the Audio domain (scenes/audio/) — the procedural sound system. Every sound is synthesized in code (SoundSynth recipes → AudioStreamWAV, cached by SoundBank), picked by profile (gun, material × outcome × round weight, floor surface × gait, vehicle kind × stage, crash material × speed band), and played by the `Sound` autoload through a capped pool of positional voices, with looping voices that follow a vehicle (engine, skid). Use when editing scenes/audio/, adding or retuning a sound (gunshots, bullet impacts, footsteps, reloads, grenades, vehicle engines, doors, skids and crashes), adding a material / surface / gun voice, changing how events map to sounds, voice limits or range, or asserting on sound in a test. Complements the `architecture` skill, which holds the cross-domain interfaces.
---

# Audio domain

A leaf, like Physics and Art: it imports nothing from other domains. Other domains **post EventBus events**;
the `Sound` service (an autoload) listens and plays. There are no audio files: every sound is made by
`SoundSynth` from a recipe, so a new material or gun is a row in a table, not an asset.

```
gun.gd / projectile.gd / character*.gd / thrown_grenade.gd / explosion.gd / vehicle.gd ──EventBus──▶ Sound ─▶ SoundBank ─▶ SoundSynth ─▶ AudioStreamWAV
Sound ──(engine_state / slip / speed, duck-typed, each frame)──▶ the vehicle a loop follows
floor.gd ──SoundSurface.register──▶ SoundSurface ◀── Sound (floor under a footfall or a grenade's bounce)
main.gd ──Sound.focus = the human──▶ Sound (the muffle + tinnitus of a bang)
```

## Files

| File | Role |
|---|---|
| `sound_config.gd` (`SoundConfig`) | Static tuning: `enabled` master switch, `master_db`, `category_db`, `category_voices`, `category_range`, `range_follows_zoom`, `pitch_jitter`, `volume_jitter_db`, `sample_rate` (22050), `peak`, `variants`, the `light_power_max` / `heavy_power_min` weight bands, `rng_seed`, `prewarm`, and the deafness tuning `muffle_cutoff_hz` / `muffle_open_hz` / `muffle_attack` / `muffle_release`, `tinnitus_tail` / `tinnitus_full_s`, and the vehicles' `engine_pitch` (0.85 idle .. 2.9 redline), `engine_load_db` 4, `engine_rev_db` 3, `skid_full_slip` 0.4, `skid_pitch` 0.18, `skid_full_speed` 200, `loop_ease` 14/s, `crash_medium_speed` 150 / `crash_heavy_speed` 280 (the crash bands) and `crash_speed_ref` 180. Categories are `shot`, `impact`, `footstep`, `reload`, the grenades' `throw`, `grenade`, `explosion`, `tinnitus` and the vehicles' `engine` (−9 dB, 4 voices, 1400 px, 1 variant), `vehicle` (−2 dB, 6, 1800 px) and `skid` (−7 dB, 3, 1600 px, 1 variant); per-category tables (`category_db`, `_voices`, `_range`, `_jitter_scale`, `_variants`). |
| `sound_synth.gd` (`SoundSynth`) | `render(recipe, seed) -> AudioStreamWAV`. Layers: `noise` (envelope, 2-pole low-pass, 1-pole high-pass), `tone` (gliding sine), `modes` (damped resonators = how a material rings), `pulses` (a periodic excitation, `rate` noise bursts a second, rounded to whole pulses per clip, each `burst` s long, its level cycling through `pattern` and nudged by `spread` / `jitter`, or continuous noise at `rate` 0; shaped by `lp` / `hp`, `noise` of it heard raw and the rest rung through resonators `freqs` / `amps` / `decays`, swelled by `wobble` [cycles per clip, depth]: an engine's firing, a tyre's squeal). Optional `vary` makes each seed its own take (every layer's gain, decay, cut-offs, delay and partials are nudged). Mix → optional `drive` (tanh) → normalize to `peak` → 4 ms fade → 16-bit mono. A `loop` recipe skips the fade and its stream loops over the whole clip; in a loop whatever a layer still sounds past the clip's end is folded back onto its start (`_at`), so decaying layers and pulses join without a seam (a steady tone must still be a whole number of cycles of the length). Same recipe + seed ⇒ same bytes. |
| `sound_bank.gd` (`SoundBank`) | The library. `*_profile(...)` name a sound without rendering it; `sound(profile, variant) -> { stream, level_db }` renders once and caches; `recipe_for`, `profiles()`, `clear_cache()`, `cached_count()`. Holds the `SHOTS`, `MATERIALS`, `FOOTSTEPS`, `RELOADS` tables, the grenades' `THROWS`, `GRENADE_BODIES`, `GRENADE_SURFACES`, `EXPLOSIONS`, and the vehicles' `VEHICLES` (per kind: `db`, the engine's firing `rate` / `pattern` / `burst` / `lp` / `noise` and exhaust `pipe` resonances, the starter's `crank`, the `door` pitch and weight, whether it has a `slide` door), `ENGINE_LOOP` (1 s), `DOOR_STAGES` and `CRASH_BANDS` (`light` / `medium` / `heavy`: `db`, `body`, `crunch`, `length`, `glass`, `debris`). |
| `sound_surface.gd` (`SoundSurface`) | Static floor registry (the `BloodSurface` pattern): `register(rect, material, pattern) -> id`, `unregister(id)`, `at(pos) -> StringName` (newest floor wins; none = `outdoor`), `surface_for(material, pattern)`. |
| `sound.gd` (autoload `Sound`) | The service: EventBus listener, variant/pitch/volume choice, range cull, voice pool, `&"sound"` announcements. `active(category)`, `reset()` (also ends every loop), static `reach_from(...)`; `focus` (a character node, Main sets the human) and `muffled()` (see "Deafness"); the vehicle loops and `loop_of(vehicle, kind) -> { profile, pitch, volume_db }` (`{}` when none; see "Vehicle loops"). |

## Profiles

A profile is a `StringName` that fully determines a sound, so tests can assert on it without rendering:

| Profile | Meaning |
|---|---|
| `shot/<gun>` | `pistol`, `smg`, `rifle`. An unknown gun borrows its band's recipe (light→smg, medium→pistol, heavy→rifle). |
| `impact/<material>/<outcome>/<band>` | outcome `blocked` (embedded), `penetrate` (went through), `ricochet`. |
| `impact/<material>/punch` | A fist; no band. |
| `footstep/<surface>/<walk\|run>` | surface `wood tile stone concrete carpet outdoor`. |
| `reload/<gun>/<out\|in>` | `out`: a dry release click. `in`: a seat click, then a rack click. Both quiet and short, no rings. Unknown gun borrows its band's. |
| `throw/<kind>` | `stun` / `frag`: the lever's metal ping and a rising whoosh (the frag's ping is higher and louder). |
| `grenade/<kind>/<surface>` | A bounce: the floor's thud and the crack of contact, the shell's ring as much as the floor leaves (tile, stone ring; carpet, outdoor swallow it), a smaller second tick. `<surface>` is the `SoundSurface.at` of the landing, the open ground for an unknown one. |
| `explosion/frag` | Big and low: a crack, the boom and a sub-bass, a roar and a rumble, debris pattering down; 0.97 s (a profile may not run past 1 s, `audio/bank`). |
| `explosion/stun` | Sharp, very loud (+3 dB trim, then the category's +3), bright (a ring of high partials) and over in 0.42 s. |
| `tinnitus/whine` | A seamless 0.8 s loop of three thin tones (4.3 kHz twice, 5 Hz apart so they beat, and 6.85 kHz). |
| `engine/<car\|van>` | A seamless 1 s loop: the firing train at idle (28 / 20 firings a second through a four-cylinder `pattern`), rung through the exhaust's resonances, with block hum and valve ticks. The service pitches it by the revs. The van's is deeper (larger, lower `pipe` resonances, slower firing). An unknown kind is voiced as a car. |
| `ignition/<kind>` | The starter cranking a few strokes (a geared whine slowing at each compression), then the engine catching, racing up and settling to idle; 0.98 s. |
| `door/<kind>/<open\|close>` | In a reload's register: dry mechanical clicks over a low thunk, no creak or ring. `open`: the handle's click, the latch letting go with a low knock, and the soft thump of the door coming off its seal. `close`: the slam (the door's weight thumping home with the body's low panels, 150 / 230 Hz), the latch clicking shut into it, a dull knock of the trim. The van's door is lower and heavier. |
| `door/van/<slide_open\|slide_close>` | Only a kind with a sliding door: the roll back on its runners into the stop, and the heavy thunk of it shutting with the catch clicking home (no panel ring). |
| `skid/tyre` | A seamless 1 s loop: the rubber's stick-slip ringing a few close pitches (about 1 to 2.7 kHz) that beat and swell, over a hiss. |
| `crash/<material>/<light\|medium\|heavy>` | A vehicle striking `material` (every `MATERIALS` entry; `wall` for `""`, `default` for an unknown one), the band by the closing speed (`SoundConfig.crash_medium_speed` / `crash_heavy_speed`): the vehicle's mass thumping home (a sub boom when heavy), sheet metal folding and ringing, the struck material's own crack and ring, glass and debris after a heavy one. `crash/flesh/<band>` is a character struck: a dull, heavy thud. |

- **Materials:** `wood metal glass ceramic composite stone plastic fabric foliage electronics flesh`, `wall` (what walls
  report as the empty material `""`) and `default` for anything unknown. `composite` is the helmet's (a dull, short knock: thump 0.55,
  modes 380 / 820 / 1450 Hz); a round armour stops posts the armour's material (`metal` steel, `ceramic`, `composite`, `fabric` the soft panels,
  `docs/outfits.md` O6), so it is heard as that and not as flesh.
- **Bands** come from the round's penetration power (`SoundBank.band`): `light` < 0.9 (SMG 0.8), `medium`
  (pistol 1.0), `heavy` ≥ 1.6 (rifle 2.2). Heavier = lower pitch, louder crack (−4 / 0 / +4 dB by band).
- A `hard` material (metal, glass, ceramic, composite, stone, electronics, wall) rings long on a ricochet and adds a falling
  whine; a soft one whips instead. Penetration adds a crunch, a hiss of air and a deeper thud. `thump` is how
  much low body a hit has (flesh and fabric thud, metal and glass do not). A material may also carry `heft` (metal 0.9): extra body gain, a longer thud and a quieter ring on a non-ricochet hit, so a round striking metal lands heavy.
- The synth normalizes every sound, so a quiet one says so with a `db` trim in its table row (carpet −6, fabric
  −4, a punch −6 …) which `SoundBank` folds into `level_db`.

## Events the service listens to

| Topic | Posted by | Payload (Audio reads) |
|---|---|---|
| `&"shot"` | `GunItem.secondary` (Items) | `position` (muzzle), `gun`, `power` (+ `attacker`, `automatic`, `damage`) |
| `&"hit"` | `Projectile._deal` (Projectile), `Character._post_melee_hit` (Character: a punch or a kick) | `position`, `outcome` (`blocked`/`penetrate`/`ricochet`/`punch`), `material`, `power`, `speed_factor`, `damage`. A hit **without an `outcome`** is not a sound. A fly-over posts nothing, so it is silent. |
| `&"footfall"` | `CharacterFootsteps._report` (Character) | `position` (the sole), `foot` (0 left / 1 right), `speed`, `running` |
| `&"reload"` | `Character._post_reload` (Character) | `position`, `gun`, `power`, `stage`: `start` → the `out` sound, `done` → the `in` sound; any other stage is silent. A cancelled reload never posts `done`. |
| `&"throw"` | `GrenadeItem.secondary` (Items) as the grenade leaves the hand | `position`, `kind` → `throw/<kind>` |
| `&"grenade"` | `ThrownGrenade._post` (Items) | `position`, `kind`, `stage`: `bounce` → `grenade/<kind>/<floor under it>`; `rest` is silent. |
| `&"explosion"` | `Explosion.frag` / `.stun` (Projectile) | `position`, `kind` → `explosion/<kind>`. The same event shakes the camera (General). |
| `&"stun"` | `Character.take_stun` (Character) | `character`, `deaf`, `position`: voiced only for the `focus` character and a `deaf` > 0 (the tinnitus). A blind-only stun, or another character's, is silent. |
| `&"vehicle"` | `vehicle.gd` (Vehicles) | `position`, `kind`, `stage`: `ignition` → `ignition/<kind>`; `door_open` / `door_close` / `slide_open` / `slide_close` → `door/<kind>/<open\|close\|slide_open\|slide_close>`; `crash` (+ `speed`, `material`) → `crash/<material>/<band>`, `bump_character` (+ `speed`) → `crash/flesh/<band>`, both louder within the band by `linear_to_db(clamp(speed / crash_speed_ref, 0.5, 1.6))`. Category `vehicle`. |
| `&"engine"` | `vehicle.gd` | `vehicle`, `kind`, `stage`: `start` starts the vehicle's `engine/<kind>` loop, `stop` ends it. |
| `&"skid"` | `vehicle.gd` | `vehicle`, `stage`: `start` starts its `skid/tyre` loop, `stop` ends it. |

It posts `&"sound"` `{ kind, profile, variant, position, volume_db, pitch }` for every sound it accepts. That is
what tests assert on (the runner records every bus event); nothing else listens.

## How a sound is played

1. `Sound._on_posted` returns at once when `SoundConfig.enabled` is off or the topic is not its own.
2. The event becomes a profile (`SoundBank.*_profile`; a footfall asks `SoundSurface.at(position)` for the floor).
3. Range: `reach_from(category, at, camera centre, zoom)` is 0 beyond `category_range` (scaled by `1/zoom` when
   `range_follows_zoom`). No camera = in range. The same number becomes the player's `max_distance`.
4. A variant is drawn from the service's **own RNG** (`rng_seed`; never the gameplay RNG), never the one played
   last for that profile; pitch (±`pitch_jitter`, the right foot +3 %, the left −3 %) and volume (±`volume_jitter_db`)
   are jittered, both widened per category by `category_jitter_scale` (steps ×1.7). A category may have more
   takes than the default (`category_variants`: steps have 6). Loudness adds `level_db`, `category_db`, `master_db`, plus the event (a step by speed/150, a
   bullet by `speed_factor`, a punch by damage).
5. A voice is acquired: if the category is at `category_voices`, its **oldest** voice is cut off; else a free one;
   else a new `AudioStreamPlayer2D` child is made (the pool grows lazily, never past the caps' sum).
6. A voice is free when its clip has played, counted in **simulated time** (`_now += delta`), not read from the
   player — a fixed-FPS test run outpaces the audio thread.

## Why a step is not mechanical (and why it is not tinny)

A footstep is a heel strike then a softer toe tap 45–62 ms later in the same tone, with a faint cloth rustle under it
(`SoundBank._footstep`, `vary` 0.22), drawn from 6 takes that differ in level, timing and tone, with wider pitch and
volume swing than other sounds and the feet 6 % apart in pitch. The cadence itself is the walk cycle's (stride-locked),
so it is regular only as far as the walking is. Test: `tests/audio/footstep_variety_test.gd`.

**Every surface is a dull thud on purpose.** High-passed noise bursts and 1.5–2.7 kHz ring tones read as tinny, so the
heel thump leads on every surface, the scuff is a soft noise low-passed at ≤ ~2.3 kHz, and no floor keeps a ring
(they pinged): wood, tile and stone (the slate tile floor) have none and sit 3 dB quieter. Surfaces therefore sound alike (wood/tile/stone/concrete/outdoors all sit at
~150–300 Hz RMS frequency, carpet softer and quieter via its `db`; wood and tile are the deepest of the hard floors,
~150–200 Hz, with a lower, longer heel thump). Keep scuff cut-offs low and give a new surface a `thump` first. Test:
`tests/audio/footstep_tone_test.gd` (brightness ceiling 0.03 against a measured 0.010, and most energy under 300 Hz).

## Why an impact has weight

Every impact carries a low **body** thump (150→55 Hz; the material's `thump` only scales it, `0.65 + 0.35·thump`),
however hard the thing struck, so metal, glass and ceramic thud as well as ring; their rings are quieter than the body
unless the round glances off (ricochet). The round's weight band sets how much (`BANDS`: `body` 0.8 / 1.0 / 1.7,
`pitch` 1.15 / 1.0 / 0.78 — rings take half the pitch shift —, `db` −4 / 0 / +4) and adds a deep **sub** boom to the
heavier rounds (`sub` 0 / 0.35 / 0.8). Within a band the hit is louder the faster the round (`speed_factor`, clamped
0.25–1.3) or the harder the punch (damage/10, clamped 0.3–1.5). Test: `tests/audio/impact_weight_test.gd` (every
medium impact keeps ≥ 40 % of its energy under 250 Hz; low-end weight, including level, rises ≥ 1.3× light→medium and
≥ 1.8× medium→heavy). To measure, `tools/dump_sounds.gd` then analyse the `.wav`s (the test's helpers are in
`tests/_audio/sound_probe.gd`: `brightness`, `low_share`, `low_weight`).

## Why a door is a thunk, not a creak

A vehicle door sits in a reload's register: its clicks are short noise bursts (a few ms, so they carry little
energy however crisp), and the body of the sound is low tones and low resonances: the latch's knock (140 → 80 Hz), the seal's thump
(100 → 58 Hz), the slam (125 → 48 Hz) with the panels at 150 / 230 Hz (the slide door 130 / 210 Hz) and the impact noise low-passed
at ~1 kHz. No creak and no panel ring: creaks and panel rings above ~300 Hz read high-pitched. Measured (`tests/_audio/sound_probe.gd`
`low_share` under 300 Hz, the lowest of the takes): car open 0.80, car close 0.82, van open 0.87, van close 0.86, slide open 0.82,
slide close 0.86 (the test's floor 0.75; footsteps and impacts ~0.83); brightness 0.001 to 0.018, far under the reloads' clicks (up
to 0.86). Keep a new door sound's high clicks short and its weight under ~150 Hz: the 2-pole measure counts a 165 Hz tone only
~0.6 low. Test: `tests/audio/vehicle_door_tone_test.gd`.

## Deafness: `Sound.focus`, `muffled()` and the tinnitus (G14)

`Sound.focus` is a character node (Main sets the human when there is one and clears it at teardown; null = nobody's ears, so an
AI's stun is silent). Audio reads only its `stun_view()` (`deaf`), duck-typed, so it stays a leaf.

- **`muffled()`** is true while the focus's `stun_view().deaf` is above 0 (false for a null, freed or non-stunnable focus), so it
  lifts exactly when the character's deafness ends, a longer second stun included.
- **The muffle:** every game voice plays on the `GameSound` bus (made in `Sound._ready`, sent to Master, an
  `AudioEffectLowPassFilter` on it); while muffled the filter closes toward `muffle_cutoff_hz` at `muffle_attack` a second (so the bang
  that deafens is still heard, then goes dull) and lifts at `muffle_release` (the hearing comes back slowly). Headless, the Dummy
  driver accepts the bus and its effect and nothing is heard, so a test asserts `muffled()`.
- **The tinnitus:** a `&"stun"` event for the focus with `deaf` > 0 starts one `tinnitus/whine` voice on the Master bus (so the muffle
  does not dull it), once per stun (the category's one voice is replaced by a second stun). The voice loops and **follows the
  deafness**: each frame its `until` and volume come from `stun_view().deaf`, fading over `tinnitus_tail` (1.5 s) and cut when the
  deafness ends; a stun shorter than `tinnitus_full_s` starts it quieter. Its range is `1e6` (it is in the listener's own head).

## Vehicle loops (`engine`, `skid`)

One looping voice per vehicle and kind, keyed by the vehicle's instance id (`_loops`); a second `start` for the same one is ignored.
`_start_loop` plays variant 0 at the vehicle with `until` = INF (it plays until stopped) and is **not** range-culled (it lasts, and the
listener may come closer); its `max_distance` is the category's range at the camera's zoom (`_range`), kept current. Each frame
`_follow_loops` moves the voice to the vehicle and glides its pitch and level (`loop_ease`) toward `_loop_aim`, read off the vehicle
duck-typed (Audio imports nothing from Vehicles):
- **engine:** pitch `lerp(engine_pitch.x, .y, rpm)`; level = the sound's level − `engine_load_db × (1 − load)` + `engine_rev_db × rpm`
  (`engine_state()`). An engine that no longer runs ends the loop.
- **skid:** pitch `1 + skid_pitch × slip`; level + `linear_to_db(clamp(slip / skid_full_slip, 0.1, 1) × clamp(speed / skid_full_speed, 0.25, 1))`.
A loop ends on its `stop` event, its vehicle freed, its engine stopped, or its voice taken by a newer one of the category (the voice's
`loop` key is cleared when it is reacquired). `loop_of(vehicle, kind)` is what tests read.

## Gotchas

- `play()` outside the scene tree logs an engine error (which fails a test); voices are only ever added as
  children of the autoload, which is in the tree.
- On quit `Sound._exit_tree` frees the voices and pauses 80 ms so the mixer thread can drop their playbacks;
  without it any process that quits mid-sound reports leaked `AudioStreamPlaybackWAV` objects.
- With a camera present (the test runner has one), range culling is live: audio tests that are not about distance
  set `SoundConfig.category_range` to `Probe.EVERYWHERE` (`tests/_audio/sound_probe.gd`).
- Sounds render lazily (1–12 ms each for most; one variant of each of the 205 profiles took ~2.2 s in a headless run at load average
  ~3.8, against `audio/bank`'s 3000 ms budget) and, with a display, are pre-rendered in the
  background at `prewarm_budget_ms` a frame after launch, every variant of every profile (`Sound.library()`: the first variants
  first; 466 sounds), because a variant first synthesized in a fight is a 9–35 ms hitch; headless tests render on first use
  (`Perf.warm_sounds()` in `tests/_perf/perf_probe.gd` does what the pre-warm would have by the time a match is fought).
- Headless uses the Dummy audio driver: playback is accepted and silent. Nothing here can be heard by a test.

## Adding to it

- **A gun:** add its row to `GunConfig`; give it a recipe by adding a row to `SoundBank.SHOTS` (until then it
  borrows its band's). The `shot` event already carries `gun` and `power`.
- **A material:** a row in `SoundBank.MATERIALS` (`hard`, `db`, `thump`, `modes`/`amps`/`decays`, `lp`, `grit`).
- **A floor surface:** a row in `FOOTSTEPS`, and a case in `SoundSurface.surface_for`.
- **A vehicle kind:** a row in `SoundBank.VEHICLES` (until then it is voiced as a car).
- **A new category** (reload, a body falling …): a topic posted by the owning domain, a `*_profile` + recipe in
  `SoundBank`, a case in `Sound._on_posted`, entries in `SoundConfig`'s category tables, and a test.
- Audition without playing the game: `godot --headless --path . -s tools/dump_sounds.gd -- --out=DIR
  [--variants=2] [--filter=impact/metal]` writes every profile as a `.wav` and prints length, peak and render time.

## Verifying

`tools/run_tests.sh audio` (`tests/audio/`): `synth` (determinism, level, pitch, delays), `bank` (every profile
renders, cache, distinctness, library time budget), `profile_choice`, `surface`, `event_mapping` (synthetic bus
events → profiles), `sound_service` (caps, freeing, variety, reset, RNG isolation, range), `sound_switch_off`, and
the real-emitter tests `gun_shot_sound`, `impact_material_sound`, `impact_outcome_sound`, `impact_blocked_sound`,
`footstep_surface_sound`, `footstep_variety`, `footstep_tone`, `impact_weight`, `reload_sound`, `grenade_sounds` (throw, floor-voiced bounce,
`explosion/frag` against `explosion/stun`, the tinnitus and the muffle for the focus only; its range table adds the new categories, `Probe.everywhere`
in `tests/_ai/grenade_probe.gd`) and `vehicle_sounds` (ignition, the engine loop rising in pitch with speed and cut on exit, door open and
close, the van's slide door, the skid loop, a slow and a fast crash, a character struck, the van's engine deeper; through
`tests/_vehicle/vehicle_probe.gd`) and `vehicle_door_tone` (every door take no brighter than the brightest reload, over 0.75 of its
energy under 300 Hz). Switch `audio.sound` (`SoundConfig.enabled`) turns it all off.
