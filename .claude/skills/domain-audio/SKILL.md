---
name: domain-audio
description: Deep implementation detail for the Audio domain (scenes/audio/) — the procedural sound system. Every sound is synthesized in code (SoundSynth recipes → AudioStreamWAV, cached by SoundBank), picked by profile (gun, material × outcome × round weight, floor surface × gait), and played by the `Sound` autoload through a capped pool of positional voices. Use when editing scenes/audio/, adding or retuning a sound (gunshots, bullet impacts, footsteps, reloads), adding a material / surface / gun voice, changing how events map to sounds, voice limits or range, or asserting on sound in a test. Complements the `architecture` skill, which holds the cross-domain interfaces.
---

# Audio domain

A leaf, like Physics and Art: it imports nothing from other domains. Other domains **post EventBus events**;
the `Sound` service (an autoload) listens and plays. There are no audio files: every sound is made by
`SoundSynth` from a recipe, so a new material or gun is a row in a table, not an asset.

```
gun.gd / projectile.gd / character*.gd ──EventBus──▶ Sound ─▶ SoundBank ─▶ SoundSynth ─▶ AudioStreamWAV
floor.gd ──SoundSurface.register──▶ SoundSurface ◀── Sound (floor under a footfall)
```

## Files

| File | Role |
|---|---|
| `sound_config.gd` (`SoundConfig`) | Static tuning: `enabled` master switch, `master_db`, `category_db`, `category_voices`, `category_range`, `range_follows_zoom`, `pitch_jitter`, `volume_jitter_db`, `sample_rate` (22050), `peak`, `variants`, the `light_power_max` / `heavy_power_min` weight bands, `rng_seed`, `prewarm`. Categories are `shot`, `impact`, `footstep`, `reload`; per-category tables (`category_db`, `_voices`, `_range`, `_jitter_scale`, `_variants`). |
| `sound_synth.gd` (`SoundSynth`) | `render(recipe, seed) -> AudioStreamWAV`. Layers: `noise` (envelope, 2-pole low-pass, 1-pole high-pass), `tone` (gliding sine), `modes` (damped resonators = how a material rings). Optional `vary` makes each seed its own take (every layer's gain, decay, cut-offs, delay and partials are nudged). Mix → optional `drive` (tanh) → normalize to `peak` → 4 ms fade → 16-bit mono. Same recipe + seed ⇒ same bytes. |
| `sound_bank.gd` (`SoundBank`) | The library. `*_profile(...)` name a sound without rendering it; `sound(profile, variant) -> { stream, level_db }` renders once and caches; `recipe_for`, `profiles()`, `clear_cache()`, `cached_count()`. Holds the `SHOTS`, `MATERIALS`, `FOOTSTEPS`, `RELOADS` tables. |
| `sound_surface.gd` (`SoundSurface`) | Static floor registry (the `BloodSurface` pattern): `register(rect, material, pattern) -> id`, `unregister(id)`, `at(pos) -> StringName` (newest floor wins; none = `outdoor`), `surface_for(material, pattern)`. |
| `sound.gd` (autoload `Sound`) | The service: EventBus listener, variant/pitch/volume choice, range cull, voice pool, `&"sound"` announcements. `active(category)`, `reset()`, static `reach_from(...)`. |

## Profiles

A profile is a `StringName` that fully determines a sound, so tests can assert on it without rendering:

| Profile | Meaning |
|---|---|
| `shot/<gun>` | `pistol`, `smg`, `rifle`. An unknown gun borrows its band's recipe (light→smg, medium→pistol, heavy→rifle). |
| `impact/<material>/<outcome>/<band>` | outcome `blocked` (embedded), `penetrate` (went through), `ricochet`. |
| `impact/<material>/punch` | A fist; no band. |
| `footstep/<surface>/<walk\|run>` | surface `wood tile stone concrete carpet outdoor`. |
| `reload/<gun>/<out\|in>` | `out`: a dry release click. `in`: a seat click, then a rack click. Both quiet and short, no rings. Unknown gun borrows its band's. |

- **Materials:** `wood metal glass ceramic stone plastic fabric foliage electronics flesh`, `wall` (what walls
  report as the empty material `""`) and `default` for anything unknown.
- **Bands** come from the round's penetration power (`SoundBank.band`): `light` < 0.9 (SMG 0.8), `medium`
  (pistol 1.0), `heavy` ≥ 1.6 (rifle 2.2). Heavier = lower pitch, louder crack, +3 dB.
- A `hard` material (metal, glass, ceramic, stone, electronics, wall) rings long on a ricochet and adds a falling
  whine; a soft one whips instead. Penetration adds a crunch, a hiss of air and a deeper thud. `thump` is how
  much low body a hit has (flesh and fabric thud, metal and glass do not). A material may also carry `heft` (metal 0.9): extra body gain, a longer thud and a quieter ring on a non-ricochet hit, so a round striking metal lands heavy.
- The synth normalizes every sound, so a quiet one says so with a `db` trim in its table row (carpet −6, fabric
  −4, a punch −6 …) which `SoundBank` folds into `level_db`.

## Events the service listens to

| Topic | Posted by | Payload (Audio reads) |
|---|---|---|
| `&"shot"` | `GunItem.secondary` (Items) | `position` (muzzle), `gun`, `power` (+ `attacker`, `automatic`, `damage`) |
| `&"hit"` | `Projectile._deal` (Projectile), `Character._on_punched` (Character) | `position`, `outcome` (`blocked`/`penetrate`/`ricochet`/`punch`), `material`, `power`, `speed_factor`, `damage`. A hit **without an `outcome`** is not a sound. A fly-over posts nothing, so it is silent. |
| `&"footfall"` | `CharacterFootsteps._report` (Character) | `position` (the sole), `foot` (0 left / 1 right), `speed`, `running` |
| `&"reload"` | `Character._post_reload` (Character) | `position`, `gun`, `power`, `stage`: `start` → the `out` sound, `done` → the `in` sound; any other stage is silent. A cancelled reload never posts `done`. |

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

## Gotchas

- `play()` outside the scene tree logs an engine error (which fails a test); voices are only ever added as
  children of the autoload, which is in the tree.
- On quit `Sound._exit_tree` frees the voices and pauses 80 ms so the mixer thread can drop their playbacks;
  without it any process that quits mid-sound reports leaked `AudioStreamPlaybackWAV` objects.
- With a camera present (the test runner has one), range culling is live: audio tests that are not about distance
  set `SoundConfig.category_range` to `Probe.EVERYWHERE` (`tests/_audio/sound_probe.gd`).
- Sounds render lazily (1–12 ms each, the whole library ~0.7 s) and, with a display, are pre-rendered in the
  background at `prewarm_budget_ms` a frame after launch, every variant of every profile (`Sound.library()`: the first variants
  first; the 330 sounds take ~1.6 s), because a variant first synthesized in a fight is a 9–35 ms hitch; headless tests render on first use
  (`Perf.warm_sounds()` in `tests/_perf/perf_probe.gd` does what the pre-warm would have by the time a match is fought).
- Headless uses the Dummy audio driver: playback is accepted and silent. Nothing here can be heard by a test.

## Adding to it

- **A gun:** add its row to `GunConfig`; give it a recipe by adding a row to `SoundBank.SHOTS` (until then it
  borrows its band's). The `shot` event already carries `gun` and `power`.
- **A material:** a row in `SoundBank.MATERIALS` (`hard`, `db`, `thump`, `modes`/`amps`/`decays`, `lp`, `grit`).
- **A floor surface:** a row in `FOOTSTEPS`, and a case in `SoundSurface.surface_for`.
- **A new category** (reload, a body falling …): a topic posted by the owning domain, a `*_profile` + recipe in
  `SoundBank`, a case in `Sound._on_posted`, entries in `SoundConfig`'s category tables, and a test.
- Audition without playing the game: `godot --headless --path . -s tools/dump_sounds.gd -- --out=DIR
  [--variants=2] [--filter=impact/metal]` writes every profile as a `.wav` and prints length, peak and render time.

## Verifying

`tools/run_tests.sh audio` (`tests/audio/`): `synth` (determinism, level, pitch, delays), `bank` (every profile
renders, cache, distinctness, library time budget), `profile_choice`, `surface`, `event_mapping` (synthetic bus
events → profiles), `sound_service` (caps, freeing, variety, reset, RNG isolation, range), `sound_switch_off`, and
the real-emitter tests `gun_shot_sound`, `impact_material_sound`, `impact_outcome_sound`, `impact_blocked_sound`,
`footstep_surface_sound`, `footstep_variety`, `footstep_tone`, `impact_weight`, `reload_sound`. Switch `audio.sound` (`SoundConfig.enabled`) turns it all off.
