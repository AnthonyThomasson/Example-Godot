---
name: domain-ai-decision
description: Deep implementation detail for the AI DECISION sub-domain (scenes/ai/decision/) — the external-model boundary. The round-trip to the local Von "System One" server: the act-centric protocol (two `choice` questions in one request — WHAT to do, and, only if holding, WHERE), argmax/top-pick selection, the decided/failed signals, and the dev-only server launcher. Use when editing scenes/ai/decision/ or working on the Von request/response, the choice questions, how a pick is chosen, the server-down fallback, or auto-starting/reusing the Von server. Complements the light `domain-ai` overview and the `architecture` skill (cross-domain interfaces).
---

# AI · Decision sub-domain (`scenes/ai/decision/`)

The THINK half: the only place the AI talks to the outside model. Von is a stateless single-shot
ranker, so this sub-domain holds no reasoning — it formats the request, POSTs it, and reports the top
pick. The decision context it sends is BUILT by the perception sub-domain; the chosen ids are
INTERPRETED by the behaviour sub-domain. This folder is purely the round-trip + the dev server.

Files:
- `decision_client.gd` — the Von HTTP client (a `Node` owning its `HTTPRequest`).
- `decision_server_launcher.gd` — dev-only `von serve` launcher (a node in `main.tscn`).

## `decision_client.gd`

Configured once by the controller: `configure(server_url, model, timeout)`.

- `request(ctx, npc_name) -> bool` — POST the perception context `{ state_text, acts, moves }` as two
  `choice` questions in one request to `/v1/systemone`:
  - `act` — "What should you do right now?" over the act menu (the real choice).
  - `move` — "If you are just holding, which place should you go to?" over the move menu; the
    behaviour consults the move pick **only** when the chosen act is `hold`.
  It keeps the menus only to validate the pick, and returns whether the request started.
- `is_pending() -> bool` — true while a request is in flight (the controller issues no new decision
  until it completes).
- `signal decided(act_id, move_id)` — emitted with Von's TOP pick for each question. The pick is the
  argmax `choice` when that id is one of this tick's offered options, else the highest-probability
  offered id (ids not offered this tick are ignored, so a stale/foreign id can never be chosen).
  Von's distributions are flat (low confidence), so taking the top pick — not sampling — keeps the NPC
  decisive and goal-coherent instead of jittering.
- `signal failed()` — emitted when a request can't start, the transport fails, the server answers
  non-200, or the response is malformed. The controller wires this to the behaviour's steady-stance
  `fallback()`. **A transport failure and an HTTP error answer are reported as different faults**: a
  4xx/5xx prints the server's own `{"detail": …}` ("server refused the decision: HTTP 422 — Failed to
  load … weights"), never "unreachable" — mislabelling a configuration fault as a connection problem
  sends you hunting the wrong thing. An identical failure is logged only ONCE per client (every NPC
  re-asks about once a second, so a persistent fault would otherwise bury the log); a success clears
  that, so a relapse is reported again. The adopted decision log line
  (`<NPC> (Von) act=… move=… intent=…`) is printed by the controller, which shows
  `act=<von's pick>→<final> [why]` whenever a policy override rewrote the choice.

## `decision_server_launcher.gd`

Development convenience: starts a local `von serve` when the game runs **from the editor** (never in
exported builds) and stops it on exit. Uses `von_path` (defaults to the `application/von/server_path`
project setting; blank = don't auto-start). A server that can still **decide** on `port` is **reused**
and left running, decided by probing `port` up to `probe_attempts` times.

**It is a root node of `main.tscn`, so all of this runs at SCENE LOAD** — while the pre-game setup
window is still open, giving the server its whole boot time before the match builds any NPC. Two
things keep that head start honest:
- A probe that is **refused** (nothing bound) short-circuits the retry budget and launches at once;
  the retries only pay off for a probe that **times out** (a slow server worth reusing). Otherwise a
  cold start wasted `probe_attempts × probe_interval` before even launching.
- The probe **POSTs a real decision** to `health_path` (`/v1/systemone`) rather than checking
  `GET /`, because an **orphaned server is worse than an absent one**. A `von serve` left by a
  hard-killed run (no `_exit_tree`) has a dead stdout pipe, so its weight fetch dies on `EPIPE`
  — permanently — while it keeps serving HTTP. A liveness check reuses it forever and every decision
  comes back `422`; asking it to decide catches it and resolves `false` with the server's own
  `detail`. Clear one by hand with `pkill -f "von serve"`. The probe doubles as a **warm-up**, so the
  first in-match decision isn't the one paying for model load.
- After launching, it keeps polling its own server until the first answer, then prints
  `[von] Decision server live on port N, Xs after scene load` — so readiness means a LIVE brain, not
  merely a spawned process.

**`resolved(live)` + `is_resolved()` / `is_live()`** is the gate contract. It fires EXACTLY once when
the question settles, and every terminal path reaches `_resolve()` — server answered (`true`), or
none is coming (`false`: exported build, blank `von_path`, failed spawn, `ready_timeout` elapsed).
`main.gd` awaits it before `_spawn_world()` so no NPC ever makes its first decision against a cold
server; a run with no server still starts (with a warning), just with NPCs that hold steady. Main
checks `is_resolved()` *before* awaiting, because the exported-build path resolves synchronously in
`_ready()` — children are readied before their parent, so the signal would otherwise be missed. Any
new terminal path here MUST resolve, or the setup window hangs forever. Output is appended to `user://von_server.log` and echoed as `[von] …` lines.
Every NPC shares the one server (its port must match the clients' `server_url`).

Note: `mcp__godot__stop_project` hard-kills Godot, so `_exit_tree` doesn't run and the Von server it
spawned is orphaned on port 8000 — `pkill -f "von serve"` clears it, and you should always do so. An
orphaned server's stdout pipe is dead, so it can never load weights again (`EPIPE` kills the fetch)
while still answering HTTP; the readiness probe above is what stops it being mistaken for a live one.
