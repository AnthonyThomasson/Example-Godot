Load the `architecture` skill, then the `domain-ai` overview skill **and its sub-skills** (`domain-ai-perception`, `domain-ai-decision`, `domain-ai-behavior`, `domain-ai-debug`), then the `godot-drive` skill (and `godot-debug` for the headless load check). Read them before doing anything else — they are the source of truth for what the AI should do and how to drive the game. The deep behaviour detail lives in the sub-skills (e.g. combat/flanking/territory/patrol in `domain-ai-behavior`, vision/hostility/memory in `domain-ai-perception`); `domain-ai` is the map.

You are going to run a structured test of every major AI behaviour variation in the game, drive results through `tools/match.py` and `tools/gcmd.py`, observe debug output, and produce a written report with findings and improvement recommendations.

If `$ARGUMENTS` names a specific behaviour (e.g. "flanking", "hostility", "vision"), focus only that section. Otherwise run the full suite in order.

---

## Setup

1. Resolve the Godot binary: `ls /Applications/Godot*.app/Contents/MacOS/Godot | head -1`
2. Run a headless smoke test first (sandbox disabled). If it fails, stop and report the errors — do not proceed with a broken build.
3. Launch the game with `mcp__godot__run_project` on project path `/Users/athomasson/Documents/projects.nosync/Example_Godot`. Wait for `[cmd] listening` to appear in `mcp__godot__get_debug_output` before continuing. Retry once if the launch hangs (empty output after ~10 s).
4. Send `python3 tools/gcmd.py help` (sandbox disabled) to confirm the command server is up.
5. Note whether the Von decision server is running. If it is not (the log shows `[von] server not found` or the NPCs hold permanently), note this and continue — behaviours that don't need Von (hostility, vision, navigation, territory gating) are still testable; Von-dependent tests (decision quality, section 10) will be marked **"Von offline — skipped"**.

Keep the game running across all tests. Use `python3 tools/match.py` with `--rounds 3 --timeout 90` for each scenario unless noted. Pipe all match output to a variable so you can quote it in the report. After all tests, `mcp__godot__stop_project`, then `pkill -f "von serve"` to clean up.

---

## Test suite

Run each scenario in order. For each one:
- Print the scenario name and the overrides you're applying.
- Run the match, capture the win/loss/timeout summary.
- Pull the last few lines of `mcp__godot__get_debug_output` after the rounds finish; look for the `(Von)` decision lines (`<NPC> (Von) COMBAT - Defender - FLANK - their left side (kitchen)  [combat auto, combat 312ms, flank 96ms]` — the full path plus per-level timing), NPC action labels, and any errors.
- Note observed behaviours that differ from what the `domain-ai` sub-skills say should happen.

### 1. Baseline — default config
No overrides. 3 rounds, random seeds. Establishes the win rate for subsequent comparison.

```
python3 tools/match.py --rounds 3 --timeout 90
```

### 2. Hostility rules

**2a. Defender: on_sight only** (normally trespass + attack)
```
--defender 'scene().get_node("Defender/GoalController").hostile_on_sight = true'
--defender 'scene().get_node("Defender/GoalController").hostile_on_trespass = false'
```
Expected: defender attacks on first visual contact even outdoors. Observe whether it leaves the house to pursue (territory should stop it if `defend_territory` is on).

**2b. Defender: retaliate only** (passive until struck)
```
--defender 'scene().get_node("Defender/GoalController").hostile_on_sight = false'
--defender 'scene().get_node("Defender/GoalController").hostile_on_trespass = false'
--defender 'scene().get_node("Defender/GoalController").hostile_on_attack = true'
```
Expected: defender holds until it takes a hit, then retaliates. Observe how long before the first shot is exchanged.

**2c. Invader: trespass trigger** (normally on_sight)
```
--invader 'scene().get_node("Invader/GoalController").hostile_on_sight = false'
--invader 'scene().get_node("Invader/GoalController").hostile_on_trespass = true'
```
Expected: invader enters the house and only then begins combat. Observe whether it navigates inside before engaging.

### 3. Pursuit on vs off

**3a. Invader: pursuit off** (normally on)
```
--invader 'scene().get_node("Invader/GoalController").pursue_hostiles = false'
```
Expected: IDLE becomes available at the root, and a merely seen hostile no longer sends every decision straight to COMBAT (only being under fire / engaged does) — Von ranks COMBAT against INVESTIGATE / SEARCH / IDLE. Watch the decision paths for IDLE picks.

**3b. Defender: pursuit off** (normally on)
```
--defender 'scene().get_node("Defender/GoalController").pursue_hostiles = false'
```
Expected: as 3a; with `defend_territory` still on, any COMBAT it picks keeps its options inside the house.

### 4. Territory defence

**4a. Defender: territory off**
```
--defender 'scene().get_node("Defender/GoalController").defend_territory = false'
```
Expected: defender advances outside the house to close range rather than holding a doorway fire line. Compare win rate to baseline.

**4b. Invader: territory on** (unusual — invader treating outdoor area as home ground)
```
--invader 'scene().get_node("Invader/GoalController").defend_territory = true'
```
Expected: invader fires from outside and resists being drawn in.

### 5. Flanking and team callouts

**5a. Invader: FLANK disabled** (a decision-tree node)
```
--invader 'scene().get_node("Invader/GoalController").disabled_nodes = [&"flank"]'
```
Expected: no decision path contains FLANK; the invader engages, advances or retreats instead. Compare win rate to baseline.

**5b. Multiple invaders — flank claims over the radio**
```
--invader 'scene().get_node("Main").invader_count = 3'
```
During a round, dump `python3 tools/gcmd.py ai`: an invader's `flanks` state line should name sides "taken by InvaderN" (seen, or "(radio)" from a callout), and those sides must be absent from its FLANK options (`drop_tags`). The invaders' decision paths should name different sides. Repeat with `hear_callouts = false` on every invader and compare how often two pick the same side.

**5c. FLANK never routes past a hostile** (`route_clearance`, default 120 px)
Default config, 1 round. In `python3 tools/gcmd.py ai`, a side whose route there passes a known hostile reads "route passes <name>" in the `flanks` state line.
Expected: no FLANK level's options include such a side (`drop_tags: crosses`); when every side passes a hostile, FLANK is absent from the COMBAT level. A rear flank in a fight across one room is usually blocked, because the shortest path runs right past the target. Then loosen the rule and compare how often FLANK is picked:
```
--invader 'scene().get_node("Invader/GoalController").route_clearance = 40.0'
```

**5d. ENGAGE fire spots: wide, but never in a hostile's open view** (`fire_spot_distances`, `watch_arc`)
Default config, 1 round. At an ENGAGE level the options are where you stand, firing spots named by place and cover ("behind the sofa in the kitchen", "the hallway, north of them"), each with its route band, and an ambush.
Expected: no option reads "in the open" for a spot inside a visible hostile's facing cone (`watch_arc`, default 90°) with a clear line from it. No spot's route passes a hostile. Spots can lie well beyond the 160 px ring around the NPC. Widen or narrow the sampling:
```
--invader 'scene().get_node("Invader/GoalController").fire_spot_distances = [150.0, 300.0, 450.0]'
--invader 'scene().get_node("Invader/GoalController").watch_arc = 140.0'
```
A wider `watch_arc` should leave fewer "in the open" spots.

**5e. ADVANCE and MELEE**
Default config. Expected: an ADVANCE path (`COMBAT - X - ADVANCE - halfway to them / close to them / rush them`) runs the `move` primitive (aim at the target, fire at will) and re-decides on arrival. MELEE appears at the COMBAT level only while the target is point-blank (within `punch_range` × 1.5), and is then auto-picked to its single `punch` option.

### 6. Vision and knowledge

**6a. Defender: unfamiliar with house**
```
--defender 'scene().get_node("Defender/GoalController").familiar_with_house = false'
```
Expected: defender must discover rooms before it can navigate to them; initial patrol is blind. Observe whether it gets stuck or takes much longer to engage.

**6b. Invader: omniscient vision** (vision disabled = 360° no-wall-check)
```
--invader 'scene().get_node("Invader/GoalController").vision_enabled = false'
```
Expected: invader perceives through walls and reacts immediately from spawn. Note how drastically this shifts win rate.

**6c. Invader: narrow FOV**
```
--invader 'scene().get_node("Invader/GoalController").fov_degrees = 40'
--invader 'scene().get_node("Invader/GoalController").awareness_radius = 50'
```
Expected: invader is nearly blind to its sides and has no ambient awareness bubble. Observe whether the defender can flank it undetected.

### 7. Peek-and-cover timing

Run 1 round with the default config and watch the invader's action label during an ENGAGE: its progress should alternate `in position, looking for a shot` → `in position, ducking behind cover` → `looking for a shot`. Count how many times each phase appears.

```bash
python3 tools/gcmd.py 'scene().get_node("Invader/GoalController").cover_time'
python3 tools/gcmd.py 'scene().get_node("Invader/GoalController").fire_cooldown'
python3 tools/gcmd.py 'scene().get_node("Invader/GoalController").reposition_interval'
```

Try an aggressive variant with short cover time:
```
--invader 'scene().get_node("Invader/GoalController").cover_time = 0.5'
```
And a cautious variant:
```
--invader 'scene().get_node("Invader/GoalController").cover_time = 4.0'
```

### 8. Memory and commitment

**8a. Short contact memory** — contacts forgotten quickly after leaving sight
```
--invader 'scene().get_node("Invader/GoalController").contact_memory_ttl = 3.0'
```
Expected: a lost contact quickly stops being a fight target and becomes an INVESTIGATE lead ("where you last saw …", "where … was heading"). Compare how often rounds time out vs baseline. Note too that an enemy's gunfire DURING a fight does not spawn a separate "gunfire heard" lead (it is a known hostile, already covered by COMBAT / its last-seen lead) — only an UNKNOWN shooter's gunfire does (e.g. the player firing from range at an NPC that hasn't spotted them yet).

**8b. Permanent hostility** (hostility_ttl = 0)
Already the default for retaliation — verify by checking:
```
python3 tools/gcmd.py 'scene().get_node("Invader/GoalController").hostility_ttl'
```
If it is > 0, run a round with it set to 0 and one with it set to 5 and compare whether the invader drops hostility mid-fight.

**8c. Search dwell (look-around pause)** — don't re-decide the instant a room is entered
```
--invader 'scene().get_node("Invader/GoalController").pursue_hostiles = false'
--invader 'scene().get_node("Invader/GoalController").search_dwell = 5.0'
```
Expected: with no hostile known, the invader SEARCHes — it walks all the way INTO a room (its interior, not the edge), then pauses ~5 s panning its aim to look around before choosing the next room, instead of re-deciding the moment it crosses a boundary and ping-ponging between two adjacent rooms. Check `python3 tools/gcmd.py ai`: a SEARCH `move` leaf's params carry `look_around` (and no `arrive_room`), and `debug_status()` reads "reached it" while it holds through the dwell.

### 9. Navigation and stuck recovery

Teleport the player into a furniture-dense room during a live round, then observe whether NPCs path around it or enter push-through mode:
```bash
python3 tools/match.py --rounds 1 --timeout 90 &
sleep 8  # let the round start
python3 tools/gcmd.py 'tp 300 300'  # move into a tight room
```
Watch `get_debug_output` for `push_through` log lines. Note any rounds that time out — these are the strongest indicator of navigation failure.

### 10. Decision quality (Von)

Von is a classifier: whether it picks well depends on how the state and options are worded (see the
wording rules in `domain-ai-perception`). Check it directly:
```bash
python3 tools/von_probe.py --ablate        # clear-cut scenarios in tools/von_scenarios/
```
Expected: every scenario PASSes, and ablating a scenario's decisive fact changes the pick (a fact whose
removal never changes anything is not being used).

During a live round, capture real levels and inspect them:
```bash
python3 tools/gcmd.py ai > /tmp/ai.json && python3 tools/von_probe.py --capture /tmp/ai.json --out /tmp/von_captured
```
Read each level's state, question, options and probabilities. Expected: under fire the walk starts at
COMBAT (`decision.entry == "combat"`); single-option levels are `auto`; per-level Von latency (in the
`(Von)` log lines) keeps a whole decision under ~1 s.

---

## Report

After all tests, write a structured markdown report in `$ARGUMENTS`-scoped scope (or full if no argument). Include:

### Report structure

**Summary table** — one row per scenario:
| Scenario | Defender wins | Invader wins | Timeouts | Notes |
|---|---|---|---|---|

**Findings** — for each behaviour that deviated from the `domain-ai` spec or showed a clear weakness:
- What was observed
- What was expected (cite the relevant `domain-ai-<name>` sub-skill)
- Severity: **blocker** / **degraded** / **minor**

**Recommendations** — concrete, scoped to the AI domain only (no cross-domain refactors). For each one specify:
- The export or code path to change
- The expected effect on behaviour
- Risk: could this break another behaviour?

**Von dependency note** — if Von was offline, flag which findings are incomplete and what to re-run once it is available.

Publish the report as an Artifact so it has a shareable link. Title it "AI Behaviour Test Report — [today's date]".
