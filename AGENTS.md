# AGENTS.md — Example_Godot

A small top-down Godot 4.4 demo, organized into fourteen isolated domains under `scenes/`.

**Always load the `architecture` skill before planning any change or exploring the codebase.**
It is the map: the fourteen domains, the cross-cutting conventions, and the whole sanctioned
cross-domain interface surface. When working *inside* a domain, also load that domain's
`domain-<name>` skill for its deep implementation detail. Behaviour specs that tests assert live in
`docs/` (start with `docs/flanking-behavior.md`).
