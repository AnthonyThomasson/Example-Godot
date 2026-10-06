Load the `architecture` skill, then the `domain-ai` skill, then the `godot-debug` skill. Read all three before doing anything else — they are the source of truth for what the AI should do and how to drive the game.

You are going to run a structured test of every major AI behaviour variation in the game, drive results through `tools/match.py` and `tools/gcmd.py`, observe debug output, and produce a written report with findings and improvement recommendations.

If `$ARGUMENTS` names a specific behaviour (e.g. "flanking", "hostility", "vision"), focus only that section. Otherwise run the full suite in order.

---

## Setup

1. Resolve the Godot binary: `ls /Applications/Godot*.app/Contents/MacOS/Godot | head -1`
2. Run a headless smoke test first (sandbox disabled). If it fails, stop and report the errors — do not proceed with a broken build.
3. Launch the game with `mcp__godot__run_project` on project path `/Users/athomasson/Documents/projects.nosync/Example_Godot`. Wait for `[cmd] listening` to appear in `mcp__godot__get_debug_output` before continuing. Retry once if the launch hangs (empty output after ~10 s).
4. Send `python3 tools/gcmd.py help` (sandbox disabled) to confirm the command server is up.
5. Note whether the Von decision server is running. If it is not (the log shows `[von] server not found` or the NPCs hold permanently), note this and continue — behaviours that don't need Von (hostility, vision, navigation, territory gating) are still testable; Von-dependent ranking tests (act selection quality) will be marked **"Von offline — skipped"**.

Keep the game running across all tests. Use `python3 tools/match.py` with `--rounds 3 --timeout 90` for each scenario unless noted. Pipe all match output to a variable so you can quote it in the report. After all tests, `mcp__godot__stop_project`, then `pkill -f "von serve"` to clean up.

---

## Test suite

Run each scenario in order. For each one:
- Print the scenario name and the overrides you're applying.
- Run the match, capture the win/loss/timeout summary.
- Pull the last few lines of `mcp__godot__get_debug_output` after the rounds finish; look for `[von]` decision logs, NPC action labels, and any errors.
- Note observed behaviours that differ from what the `domain-ai` skill says should happen.

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

**3a. Invader: pursuit off**
```
--invader 'scene().get_node("Invader/GoalController").pursue_hostiles = false'
```
Expected: invader does not patrol; after losing sight of the defender it holds its last chosen `move` destination rather than hunting.

**3b. Defender: pursuit on** (normally off — defender is territory-focused)
```
--defender 'scene().get_node("Defender/GoalController").pursue_hostiles = true'
```
Expected: defender leaves the house to chase the invader. Watch for conflict with `defend_territory` — the skill says pursuit overrides the `interact`/`hold`/`search` act but territory restricts fire-spot candidates; observe whether the defender exits the house entirely.

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

### 5. Flanking

**5a. Invader: flanking off** (normally on)
```
--invader 'scene().get_node("Invader/GoalController").flank = false'
```
Expected: invader picks nearest clear fire spot rather than working around to the side/rear. Compare win rate to baseline.

**5b. Defender: flanking on** (normally off)
```
--defender 'scene().get_node("Defender/GoalController").flank = true'
```
Observe whether the defender attempts to circle.

**5c. Multiple invaders — stigmergic spread**
Only run this if `main.gd` exposes `invader_count` via GDScript (check with `python3 tools/gcmd.py 'scene().get_node("Main").invader_count'`). If it does:
```
--invader 'scene().get_node("Main").invader_count = 3'
```
Restart a single round with flanking on and observe the action labels on each invader. They should spread around the defender rather than stacking.

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

Run 1 round with the default config, then use `gcmd.py` to read the debug log for the invader's action labels during combat. Look for the sequence: `shoot_*` → `cover` → `shoot_*`. Count how many times each phase appears in the output.

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
Expected: invader gives up pursuit very quickly and transitions to search. Compare how often rounds time out vs baseline.

**8b. Permanent hostility** (hostility_ttl = 0)
Already the default for retaliation — verify by checking:
```
python3 tools/gcmd.py 'scene().get_node("Invader/GoalController").hostility_ttl'
```
If it is > 0, run a round with it set to 0 and one with it set to 5 and compare whether the invader drops hostility mid-fight.

### 9. Navigation and stuck recovery

Teleport the player into a furniture-dense room during a live round, then observe whether NPCs path around it or enter push-through mode:
```bash
python3 tools/match.py --rounds 1 --timeout 90 &
sleep 8  # let the round start
python3 tools/gcmd.py 'tp 300 300'  # move into a tight room
```
Watch `get_debug_output` for `push_through` log lines. Note any rounds that time out — these are the strongest indicator of navigation failure.

---

## Report

After all tests, write a structured markdown report in `$ARGUMENTS`-scoped scope (or full if no argument). Include:

### Report structure

**Summary table** — one row per scenario:
| Scenario | Defender wins | Invader wins | Timeouts | Notes |
|---|---|---|---|---|

**Findings** — for each behaviour that deviated from the `domain-ai` spec or showed a clear weakness:
- What was observed
- What was expected (cite the domain-ai skill)
- Severity: **blocker** / **degraded** / **minor**

**Recommendations** — concrete, scoped to the AI domain only (no cross-domain refactors). For each one specify:
- The export or code path to change
- The expected effect on behaviour
- Risk: could this break another behaviour?

**Von dependency note** — if Von was offline, flag which findings are incomplete and what to re-run once it is available.

Publish the report as an Artifact so it has a shareable link. Title it "AI Behaviour Test Report — [today's date]".
