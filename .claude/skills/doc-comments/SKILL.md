---
name: doc-comments
description: Keep this project's GDScript comments correct after any edit. Use whenever you add or change a `.gd` script — it defines the comment style (present-tense, describes current state; every method and property gets a short description; inline comments only for genuinely tricky logic) and gives the audit commands to verify it.
---

# Documentation & comment style

Run this after **any** change to a `.gd` file, before reporting the work done. The goal:
comments describe what the code **is now**, never how it got here.

## Rules

1. **Present-tense, current-state only.** Remove refactor/history framing: "was X",
   "renamed from", "moved to/from", "now emits", "no longer", "used to", "formerly",
   "previously", "(was hardcoded …)", and speculative "today / tomorrow / later / in
   future". Describe the thing as it currently is. (Ordinary words like "old hits",
   "keep the old collider on failure", or "we were closing on" are fine — they describe
   current behaviour, not history.)

2. **Every method and property has a short description**, written as a `##` doc comment
   (GDScript doc comment) directly above it, or as a trailing `## …` on the declaration
   line for a one-line property. Keep it to one line where possible.
   - Lifecycle overrides (`_ready`, `_process`, `_physics_process`, `_draw`, `_init`,
     `_input`) are exempt from a `##` — but if they do something non-obvious, say so in a
     short inline comment inside the body.

3. **Inline comments (`#`) only for complex or interesting business logic** — a real
   gotcha, a non-obvious algorithm step, an ordering dependency, a physics/geometry
   subtlety. Do NOT narrate obvious code. If a line reads clearly on its own, no comment.

4. **File header:** one `##` block at the top of each script saying what the file is and
   which domain it belongs to (see `AGENTS.md`). No cross-references to a file's history.

## Verify

Undocumented non-lifecycle functions (should print nothing):

```bash
cd scenes && for f in $(find . -name '*.gd'); do
  awk 'prev !~ /^[[:space:]]*##/ && $0 ~ /^[[:space:]]*(static )?func / {
    l=$0; sub(/\(.*/,"",l); gsub(/^[[:space:]]*/,"",l); print FILENAME":"NR": "l } { prev=$0 }' "$f"
done | grep -vE 'func _(ready|process|physics_process|draw|init|input)\b'
```

Member vars / signals without a preceding or trailing `##` (skim the output — a trailing
`## …` on the same line counts as documented):

```bash
cd scenes && for f in $(find . -name '*.gd'); do
  awk 'prev !~ /^##/ && prev !~ /^@onready/ && ($0 ~ /^@export/ || $0 ~ /^var / || $0 ~ /^signal /) {
    print FILENAME":"NR": "$0 } { prev=$0 }' "$f"
done
```

History/speculation sweep (each hit should be an ordinary word, not refactor framing):

```bash
cd scenes && grep -rn --include='*.gd' -iE '\b(was |were |renamed|moved to|moved from|used to|formerly|previously|today|tomorrow| later\b|in future|hardcoded|the animator)' .
```

Then run the `godot-debug` skill to confirm the file still parses and loads.
