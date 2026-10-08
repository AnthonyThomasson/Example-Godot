extends RefCounted

## AI DECISION sub-domain: the DECISION TREE Von walks, as plain data. Von picks one option per level,
## top-down: a broad MODE (combat / investigate / search / idle), then within it a TACTIC, then a
## concrete OPTION (a place to move to, a position to fight from, an object to use) that ends in one
## behaviour PRIMITIVE. The planner (decision_planner.gd) walks it, one Von `choice` request per level;
## this file only describes the shape and the words Von reads. Per NPC, the controller can disable
## nodes, merge per-node overrides, and pick the entry node by situation (e.g. under fire → combat).
##
## Node fields (all optional except where noted):
##   label     — short tag shown in the path ("COMBAT"); also prefixes the HUD status.
##   desc      — the option text Von ranks when this node is offered at its parent's level. Von is a
##               CLASSIFIER: it picks the option whose text best matches the state, so a desc states
##               the SITUATION in which this option is right, in the same phrases perception writes
##               into the state ("You are badly wounded and being hit"), never an action label, and
##               no negated attributes (an encoder reads "no cover" as "cover"). The wording is
##               measured, not guessed: tools/von_probe.py checks it against clear-cut scenarios.
##               Template fields: {target} (the bound target's name) and {summary} (the summary of
##               the node's `summary` option group, else its first `options` group — specifics
##               written by perception, kept in parentheses after the situation).
##   question  — the instruction Von answers when choosing AMONG this node's children/options. It names
##               the trade-off, since Von scores options against it. Same template fields as desc.
##   context   — which perception state sections Von sees at this level (the goal is always shown).
##   children  — static child node ids, offered when their `requires` hold and their subtree has a leaf.
##   options   — option-group names (perception generators); each option becomes a leaf. A group is
##               looked up under the bound target first, then globally.
##   summary   — option-group whose summary fills {summary} (defaults to the first `options` group);
##               inside a confined subtree a group's `summary_inside` is used when it has one.
##   bind      — before its children, pick one option of group `bind_options` and bind it (e.g. which
##               hostile to fight); `bind_question` is asked, with `bind_context` sections (the options
##               already carry each candidate's details — repeating them in the state blurs the match).
##               Skipped when there is only one.
##   requires  — fact names that must be true ("!" negates); a binding name counts as a true fact.
##   confine   — this subtree is combat: a territorial NPC drops options outside the house.
##   drop_tags — options carrying any of these tags are never offered (e.g. a flank side an ally
##               already holds: Von can't weigh "taken by Invader2" — the name matches the state; or
##               one whose route passes a known hostile). A node whose options are all dropped is not
##               offered at all.
##   primitive — the behaviour primitive a leaf runs (move / engage / melee / interact / hold). FLANK
##               runs `engage` anchored at the chosen side: get there, then fight from it. ADVANCE runs
##               `move`: it only closes the distance, then the NPC re-decides how to fight.
##   params    — default primitive params, merged under each option's own params.

const NODES := {
	&"root": {
		"question": "What should you do right now? Choose what best serves your goal, given any threat and what you know.",
		"context": [&"situation", &"current", &"odds", &"contacts", &"awareness"],
		"children": [&"combat", &"investigate", &"search", &"idle"],
	},
	&"combat": {
		"label": "COMBAT",
		"desc": "A hostile is in sight or known nearby, or you are being shot at ({summary})",
		"summary": &"threat",
		"requires": [&"threat_known"],
		"confine": true,
		"bind": &"target",
		"bind_options": &"hostiles",
		"bind_question": "Which hostile should you fight? Prefer the most dangerous one you can actually hit: close, armed, aiming at you or an ally.",
		"bind_context": [&"situation", &"odds", &"awareness"],
		"question": "How should you fight {target}? Shoot from where you have a clear line, flank to an open side, advance on them when they are weak, fleeing or unarmed, punch when they are point-blank, or retreat when you are badly hurt, exposed or outnumbered.",
		"context": [&"situation", &"current", &"odds", &"exposure", &"contacts", &"allies", &"flanks", &"awareness"],
		"children": [&"engage", &"flank", &"advance", &"melee", &"retreat", &"locate"],
	},
	&"engage": {
		"label": "ENGAGE",
		"desc": "You have a clear shot at {target}, and you are not badly wounded ({summary})",
		"requires": [&"target", &"has_pistol"],
		"question": "Where should you fight {target} from? Prefer a clear shot with cover close by, hidden from other hostiles; wait in ambush when they are coming to you.",
		"context": [&"current", &"exposure", &"contacts", &"allies", &"awareness"],
		"options": [&"fire_positions"],
		"primitive": &"engage",
	},
	&"flank": {
		"label": "FLANK",
		"desc": "Your line to {target} is blocked, or they are aiming at someone else ({summary})",
		"requires": [&"target"],
		"question": "Which side should you flank {target} from? Prefer a free side behind or beside them, with cover and a short, hidden route.",
		"context": [&"current", &"contacts", &"allies", &"flanks", &"exposure"],
		"options": [&"flank_sides"],
		"drop_tags": [&"held", &"crosses"],
		"primitive": &"engage",
		"params": { "style": &"peek_cover" },
	},
	&"advance": {
		"label": "ADVANCE",
		"desc": "{target} looks badly wounded, is unarmed, or is moving away from you ({summary})",
		"requires": [&"target"],
		"question": "How should you close in on {target}? Prefer cover close to them and a hidden route; rush only when they are weak, fleeing or unarmed.",
		"context": [&"current", &"exposure", &"contacts", &"allies", &"awareness"],
		"options": [&"advance_positions"],
		"primitive": &"move",
		"params": { "aim": &"target", "fire_at_will": true },
	},
	&"melee": {
		"label": "MELEE",
		"desc": "{target} is point-blank, right next to you ({summary})",
		"requires": [&"target"],
		"options": [&"melee"],
		"primitive": &"melee",
	},
	&"retreat": {
		"label": "RETREAT",
		"desc": "You are badly wounded and being hit ({summary})",
		"requires": [&"threat_known"],
		"question": "Where should you fall back to? Prefer a spot out of every hostile's sight, with cover, toward allies, and close by.",
		"context": [&"situation", &"exposure", &"contacts", &"allies", &"awareness"],
		"options": [&"retreat_positions"],
		"primitive": &"move",
		"params": { "aim": &"threat", "fire_at_will": true },
	},
	&"locate": {
		"label": "LOCATE",
		"desc": "You are being shot at by someone you cannot see ({summary})",
		"summary": &"shooter",
		"requires": [&"under_fire", &"!hostile_known"],
		"options": [&"shooter"],
		"primitive": &"move",
		"params": { "aim": &"point", "fire_at_will": true },
	},
	&"investigate": {
		"label": "INVESTIGATE",
		"desc": "You heard gunfire or lost sight of a hostile recently and know where to look ({summary})",
		"requires": [&"leads"],
		"question": "What should you check first? Prefer the freshest lead that matters most to your goal.",
		"context": [&"situation", &"current", &"contacts", &"allies", &"awareness"],
		"options": [&"leads"],
		"primitive": &"move",
		"params": { "aim": &"travel", "fire_at_will": true },
	},
	&"search": {
		"label": "SEARCH",
		"desc": "All is quiet and there are rooms left to search ({summary})",
		"question": "Where should you search next? Prefer unsearched rooms and unexplored areas, nearest first.",
		"context": [&"situation", &"current", &"awareness"],
		"options": [&"search_rooms", &"explore"],
		"primitive": &"move",
		"params": { "aim": &"travel", "fire_at_will": true },
	},
	&"idle": {
		"label": "IDLE",
		"desc": "All is quiet and you are free to go about your business",
		"question": "What should you do while things are quiet?",
		"context": [&"situation", &"current"],
		"children": [&"use", &"go", &"wait"],
	},
	&"use": {
		"label": "USE",
		"desc": "You want to use something in the house ({summary})",
		"question": "Which object should you use?",
		"context": [&"situation", &"current"],
		"options": [&"interactions"],
		"primitive": &"interact",
	},
	&"go": {
		"label": "GO",
		"desc": "You want to be somewhere else in the house",
		"question": "Where should you go?",
		"context": [&"situation", &"current"],
		"options": [&"rooms"],
		"primitive": &"move",
		"params": { "aim": &"travel" },
	},
	&"wait": {
		"label": "WAIT",
		"desc": "You should stay where you are and keep watch",
		"primitive": &"hold",
	},
}
