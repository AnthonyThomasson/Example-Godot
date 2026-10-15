# AGENTS.md — Forced-Entry

A small top-down Godot 4.4 demo, organized into fourteen isolated domains under `scenes/`.

**Always load the `architecture` skill before planning any change or exploring the codebase.**
It is the map: the fourteen domains, the cross-cutting conventions, and the whole sanctioned
cross-domain interface surface. When working *inside* a domain, also load that domain's
`domain-<name>` skill for its deep implementation detail. Behaviour specs that tests assert live in
`docs/` (`docs/flanking-behavior.md`, `docs/cover-and-stance.md`, `docs/tactical-entry.md`, `docs/gaze-and-fire.md`, `docs/grenades.md`, `docs/outfits.md`).

**If you are working on a GitHub ticket (issue), invoke the `ticket` skill first.** It reads the
ticket's label and tells you which `ticket-<label>` skill to invoke (e.g. `spike` → `ticket-spike`).

**Checks:** on Stop, Claude runs only lint + the headless load check (`tools/stop_hook_checks.sh`). The game
tests run in a git pre-commit hook (`.githooks/pre-commit`, without the performance tests, which are a separate
`tools/run_tests.sh --domain=perf`); enable it once per clone with `tools/install_hooks.sh`.
