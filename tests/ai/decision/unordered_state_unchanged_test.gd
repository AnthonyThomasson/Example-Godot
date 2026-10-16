extends GameTest

## LD6 (`docs/leadership.md`), backwards compatibility: an NPC with no order walks the same tree with the same entry rules,
## and the state text Von reads is byte-identical to before the leadership system. `unordered_state_unchanged.json` beside this test is
## a capture taken before any of it was built: the first decision walk of three NPCs in the
## furnished Terrace house (an invader in the back garden searching, a defender in the hall, an invader fighting a hostile in the living
## room), each level's node, question, state text, options and pick, and the decision path adopted. Nothing in this world has an order.
## The target ids (`t_<instance id>`) are compared as `t_ID`: the id is the hostile's instance id, which shifts with any node added at
## start-up. (The Von scenario fixtures, `tools/von_scenarios`, are checked with `tools/von_probe.py`, not here.)
##
## Scripted Von (the first option offered), so the walk is the same every run.

const Maps := preload("res://tests/_ai/flank_maps.gd")

const CAPTURE := "res://tests/ai/decision/unordered_state_unchanged.json"
const IDS := [&"a", &"d", &"c"]


func describe() -> Dictionary:
	return {
		"name": "An unordered NPC's state text and path are unchanged",
		"description": "The first decision walk of three unordered NPCs matches, byte for byte, a capture taken before the leadership system: questions, state text, options, picks and the path adopted (LD6).",
		"tags": ["ai", "decision", "leadership", "order", "scripted", "regression"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s)
	s.von_script([])
	s.actor(&"a", &"invader", Vector2(1000, 190))
	s.actor(&"d", &"defender", Vector2(300, 415))
	# The fighting pair stands in the living room's south-west, out of the other two's sight (a seen ally's track would make the
	# text depend on the frame its sighting was renewed on).
	s.actor(&"c", &"invader", Vector2(90, 300), { "facing": Vector2.RIGHT, "aim_point": Vector2(330, 240) })
	s.actor(&"h", &"puppet", Vector2(330, 240), { "faction": &"household", "max_health": 1000000.0, "aim_point": Vector2(90, 300) })


func run(t: TestContext) -> void:
	var file := FileAccess.open(CAPTURE, FileAccess.READ)
	if not t.require(file != null, "the capture exists (%s)" % CAPTURE):
		return
	var expected: Dictionary = JSON.parse_string(file.get_as_text())
	for id in IDS:
		var b := t.controller(id, &"debug_state")
		var decided := await t.until(func(): return int(b.debug_state().get("decisions", 0)) >= 1 and not bool(b.debug_brain().get("pending", true)), 5.0)
		if not t.check(decided, "%s made its first decision" % id):
			continue
		var want: Dictionary = expected[String(id)]
		var got_levels: Array = b.debug_state()["decision"]["levels"]
		# The first walk is the one captured: read it before the NPC can start another.
		t.expect_eq(_ids(String(b.current_act())), want["act"], "%s adopted the same decision path" % id)
		t.expect_eq(got_levels.size(), (want["levels"] as Array).size(), "%s's walk has the same levels" % id)
		for i in mini(got_levels.size(), (want["levels"] as Array).size()):
			var got: Dictionary = got_levels[i]
			var was: Dictionary = want["levels"][i]
			var where := "%s, level %d (%s)" % [id, i, was["node"]]
			t.expect_eq(String(got.get("node", "")), was["node"], "%s: the same node" % where)
			t.expect_eq(bool(got.get("auto", false)), was["auto"], "%s: asked or auto-picked as before" % where)
			t.expect_eq(_ids(String(got.get("question", ""))), was["question"], "%s: the same question" % where)
			t.expect_eq(_ids(String(got.get("state", ""))), was["state"], "%s: the same state text, byte for byte" % where)
			t.expect_eq(_ids(JSON.stringify(got.get("offered", {}), "", true)), _ids(JSON.stringify(was["offered"], "", true)), "%s: the same options" % where)
			t.expect_eq(_ids(String(got.get("pick", ""))), was["pick"], "%s: the same pick" % where)


## `text` with every target id (`t_` and digits, the hostile's instance id) written `t_ID`.
func _ids(text: String) -> String:
	var re := RegEx.create_from_string("t_\\d+")
	return re.sub(text, "t_ID", true)

