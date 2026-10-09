extends Node

## AI DECISION sub-domain: the decision PLANNER. It walks the decision tree (decision_tree.gd) top-down
## over ONE perception snapshot, asking Von one `choice` question per level through the client
## (decision_client.gd): a broad mode, then (when there is more than one) which hostile, then a tactic,
## then a concrete option — and emits the chosen leaf: the behaviour primitive to run plus its params.
## Von scores each question independently, so a drill-down is sequential requests, each conditioned on
## the path chosen so far ("Decided so far: COMBAT on Intruder → FLANK."). A level with a single option
## is taken without asking.
##
## It owns the decision POLICY as data: which nodes are offered (`requires` facts, `disabled_nodes`,
## the territorial `inside_only` filter), where a walk starts (`entry_rules` — e.g. under fire → straight
## to combat) and which state sections Von sees per level. It never builds knowledge (the snapshot comes
## from perception) and never interprets a leaf (behaviour runs it). A branch is offered only when its
## subtree still holds a leaf, so a walk never dead-ends.

const DecisionTree := preload("res://scenes/ai/decision/decision_tree.gd")

## The walk finished: `leaf` = { path, labels, primitive, params }.
signal decided(leaf: Dictionary)
## The walk could not finish (Von unreachable, or nothing to choose from).
signal failed()

# --- Config fields the controller copies from its exports before setup(). ---
## Node ids never offered for this NPC (e.g. &"idle" for one that hunts instead of doing chores).
var disabled_nodes: Array[StringName] = []
## Per-node field overrides merged over the tree's defaults: { node_id: { field: value } }.
var node_overrides: Dictionary = {}
## Ordered fact → start node: the first rule whose fact holds (and whose node has a leaf) starts the walk.
var entry_rules: Dictionary = {}
## Take a level's only option without asking Von.
var skip_single_option: bool = true
## Territory: inside a `confine` subtree (combat), drop options outside the house.
var inside_only: bool = false

var _client: Node                  ## The Von transport (decision_client.gd).
var _nodes := {}                   ## The tree with overrides merged, keyed by node id.
var _snap := {}                    ## The perception snapshot the walk in flight decides over.
var _node: StringName = &""        ## The node whose level is being decided.
var _binding := {}                 ## Bound values so far (e.g. { "target": "Intruder", "target_id": 123 }).
var _confine := false              ## Whether the walk is inside a confined subtree for a territorial NPC.
var _entry: StringName = &"root"   ## Where the walk in flight started.
var _steps: Array = []             ## The path chosen so far: [{ id, label }].
var _offered := {}                 ## The in-flight level's options: id → { kind, desc, label, … }.
var _bind_level := false           ## Whether the in-flight level is a bind step.
var _levels: Array = []            ## Per-level records of the walk in flight.
var _last_levels: Array = []       ## The last finished walk's records, for the debug snapshot.
var _prev_path: Array = []         ## Ids of the last adopted path, for the "(your current plan)" cue.
var _asked_ms := 0                 ## When the in-flight question was sent.
var _pending := false              ## Whether a walk is in flight.


## Wire the Von transport and build the tree with this NPC's overrides. The controller calls this once
## after setting the config fields.
func setup(client: Node) -> void:
	_client = client
	_client.answered.connect(_on_answered)
	_client.failed.connect(_on_failed)
	_nodes = {}
	for id in DecisionTree.NODES:
		var node: Dictionary = DecisionTree.NODES[id].duplicate(true)
		var over = node_overrides.get(id, node_overrides.get(String(id)))
		if over is Dictionary:
			node.merge(over, true)
		_nodes[id] = node


## Whether a walk is in flight.
func is_pending() -> bool:
	return _pending


## The node the walk in flight started from.
func current_entry() -> StringName:
	return _entry


## The node a walk would start from given `facts` (the first entry rule whose fact holds), ignoring
## whether that node has options — a cheap check the controller uses to decide whether a new situation
## should interrupt the walk in flight.
func entry_for(facts: Dictionary) -> StringName:
	for fact in entry_rules:
		var start := StringName(entry_rules[fact])
		if _nodes.has(start) and not disabled_nodes.has(start) and bool(facts.get(String(fact), false)):
			return start
	return &"root"


## Start a walk over `snapshot` ({ sections, sections_per_target, facts, options }), abandoning any
## walk in flight. `continuing` = the last adopted choice is still in progress, so the option that
## continues it is marked "(your current plan)"; a finished choice (arrived, interaction over) is not
## — otherwise Von would re-pick a completed tactic. Answers arrive asynchronously; the result is
## `decided` or `failed`.
func begin(snapshot: Dictionary, continuing: bool = true) -> void:
	cancel()
	if not continuing:
		_prev_path = []
	_snap = snapshot
	_binding = {}
	_steps = []
	_levels = []
	_confine = false
	_entry = &"root"
	for fact in entry_rules:
		var start := StringName(entry_rules[fact])
		if _requires_ok([StringName(fact)]) and _available(start, false):
			_entry = start
			break
	_pending = true
	_enter(_entry)


## Abandon the walk in flight (no signal is emitted for it).
func cancel() -> void:
	if _pending:
		_client.cancel()
		_pending = false


## Read-only: the walk in flight (or the last finished one) as structured data — per level, the exact
## state and question Von saw, the options offered, its probabilities, the pick, whether it was taken
## without asking, and how long Von took. Enough to replay any level offline.
func debug_state() -> Dictionary:
	return {
		"entry": String(_entry),
		"pending": _pending,
		"path": " - ".join(_steps.map(func(s): return s["label"])),
		"levels": _levels if _pending else _last_levels,
	}


## A compact per-level timing digest of the last finished walk, for the controller's log line:
## "root 112ms, combat auto, flank 96ms".
func walk_digest() -> String:
	var parts: Array = []
	for level in _last_levels:
		parts.append("%s %s" % [level["node"], "auto" if level["auto"] else "%dms" % level["ms"]])
	return ", ".join(parts)


# --- The walk -------------------------------------------------------------------------------

## Step into node `id`: record it on the path, enter its confinement, and decide its level (or finish
## at once when it is itself a leaf).
func _enter(id: StringName) -> void:
	_node = id
	var node: Dictionary = _nodes[id]
	if node.has("label"):
		_steps.append({ "id": String(id), "label": node["label"] })
	_confine = _confine or (inside_only and node.get("confine", false))
	if _is_leaf_node(node):
		_finish(id, { "id": String(id), "label": node.get("label", String(id)) })
		return
	_step()


## Decide the current node's level: list what is on offer, take a lone option without asking, else ask
## Von. An entry node that turns out empty falls back to a walk from the root.
func _step() -> void:
	var node: Dictionary = _nodes[_node]
	_bind_level = _needs_bind(node)
	_offered = _bind_offers(node) if _bind_level else {}
	if _offered.is_empty():
		_bind_level = false  # Nothing worth binding: offer the node's unbound children (e.g. RETREAT).
		_offered = _offers(_node)
	if _offered.is_empty():
		if _node == _entry and _entry != &"root":
			_entry = &"root"
			_steps = []
			_confine = false
			_enter(&"root")
		else:
			_fail_walk()
		return
	_mark_current_plan()
	if _offered.size() == 1 and skip_single_option:
		_levels.append({ "node": String(_node), "offered": _criteria(), "auto": true, "ms": 0 })
		_choose(_offered.keys()[0])
		return
	var question := _fill(node.get("bind_question" if _bind_level else "question", "Choose one."), _node)
	var state := _state_text(node, _bind_level)
	_levels.append({ "node": String(_node), "question": question, "state": state, "offered": _criteria(), "auto": false })
	_asked_ms = Time.get_ticks_msec()
	_client.ask(state, question, _criteria())


## Von answered the in-flight level: record it and follow the pick.
func _on_answered(pick: String, probabilities: Dictionary) -> void:
	if not _pending:
		return
	if not _offered.has(pick):
		_fail_walk()  # Never leave a walk hanging: a stuck walk would block every later decision.
		return
	var level: Dictionary = _levels[-1]
	level["pick"] = pick
	level["probabilities"] = probabilities
	level["ms"] = Time.get_ticks_msec() - _asked_ms
	_choose(pick)


## The transport failed: abandon the walk.
func _on_failed() -> void:
	if _pending:
		_fail_walk()


## Follow the chosen option: bind it and re-decide the same node, step into a child node, or finish
## at a leaf.
func _choose(id: String) -> void:
	var entry: Dictionary = _offered[id]
	if _levels[-1].get("auto", false):
		_levels[-1]["pick"] = id
	match entry["kind"]:
		"bind":
			_binding.merge(entry["bind"], true)
			_steps.append({ "id": id, "label": entry["label"] })
			_step()
		"node":
			_enter(entry["node"])
		"leaf":
			_finish(entry["node"], entry["option"])


## Finish the walk at `option` under node `node_id`: merge the node's primitive params under the
## option's own, add the bound target and confinement, and emit the leaf.
func _finish(node_id: StringName, option: Dictionary) -> void:
	var node: Dictionary = _nodes[node_id]
	var params: Dictionary = node.get("params", {}).duplicate(true)
	params.merge(option.get("params", {}), true)
	if _binding.has("target_id") and not params.has("target_id"):
		params["target_id"] = _binding["target_id"]
	params["confine_inside"] = _confine
	if option["id"] != String(node_id):
		_steps.append({ "id": option["id"], "label": option.get("label", option["id"]) })
	var leaf := {
		"path": _steps.map(func(s): return s["id"]),
		"labels": _steps.map(func(s): return s["label"]),
		"primitive": node.get("primitive", &"hold"),
		"params": params,
	}
	_pending = false
	_last_levels = _levels
	_prev_path = leaf["path"]
	decided.emit(leaf)


## End the walk without a decision.
func _fail_walk() -> void:
	_pending = false
	_last_levels = _levels
	failed.emit()


# --- What a level offers ---------------------------------------------------------------------

## A bind level's options: each option of the node's bind group whose subtree still holds a leaf once
## bound (e.g. a hostile you can actually do something about).
func _bind_offers(node: Dictionary) -> Dictionary:
	var out := {}
	for opt in _group(node["bind_options"]).get("options", []):
		if _leaf_under_binding(_node, opt.get("bind", {}), _confine):
			out[opt["id"]] = { "kind": "bind", "bind": opt.get("bind", {}), "label": opt.get("label", opt["id"]), "desc": opt["desc"] }
	return out


## A node's options: its available child nodes, then every option of its option groups that passes the
## territorial filter.
func _offers(id: StringName) -> Dictionary:
	var node: Dictionary = _nodes[id]
	var out := {}
	for child in node.get("children", []):
		if _available(child, _confine):
			out[String(child)] = { "kind": "node", "node": child, "label": _nodes[child].get("label", String(child)),
				"desc": _fill(_nodes[child].get("desc", String(child)), child) }
	for group_name in node.get("options", []):
		for opt in _allowed(_group(group_name).get("options", []), _confine, node.get("drop_tags", [])):
			var key: String = opt["id"]
			while out.has(key):
				key += "_"
			out[key] = { "kind": "leaf", "node": id, "option": opt, "label": opt.get("label", key), "desc": opt["desc"] }
	return out


## Whether node `id` may be offered: present, not disabled, its facts hold, and its subtree holds a leaf.
func _available(id: StringName, confine: bool) -> bool:
	if not _nodes.has(id) or disabled_nodes.has(id):
		return false
	var node: Dictionary = _nodes[id]
	if not _requires_ok(node.get("requires", [])):
		return false
	confine = confine or (inside_only and node.get("confine", false))
	if _needs_bind(node):
		for opt in _group(node["bind_options"]).get("options", []):
			if _leaf_under_binding(id, opt.get("bind", {}), confine):
				return true
	return _has_leaf(id, confine)


## Whether `node` binds before its children now: it binds, isn't bound yet, and has something to bind.
## With nothing to bind (e.g. under fire from an unseen shooter) its unbound children are offered.
func _needs_bind(node: Dictionary) -> bool:
	return node.has("bind") and not _binding.has(String(node["bind"])) \
		and not _group(node["bind_options"]).get("options", []).is_empty()


## Whether node `id` holds a leaf once `bind` is added to the bindings (restored afterwards).
func _leaf_under_binding(id: StringName, bind: Dictionary, confine: bool) -> bool:
	var saved := _binding.duplicate()
	_binding.merge(bind, true)
	var ok := _has_leaf(id, confine)
	_binding = saved
	return ok


## Whether the (bound) node `id` is a leaf itself, or has an allowed option or an available child.
func _has_leaf(id: StringName, confine: bool) -> bool:
	var node: Dictionary = _nodes[id]
	if _is_leaf_node(node):
		return true
	for group_name in node.get("options", []):
		if not _allowed(_group(group_name).get("options", []), confine, node.get("drop_tags", [])).is_empty():
			return true
	for child in node.get("children", []):
		if _available(child, confine):
			return true
	return false


## A node that is itself the leaf: it runs a primitive and offers no options or children (e.g. WAIT).
func _is_leaf_node(node: Dictionary) -> bool:
	return node.has("primitive") and node.get("options", []).is_empty() and node.get("children", []).is_empty()


## `options` minus those carrying any `drop` tag, and minus those outside the house when `confine`
## applies.
func _allowed(options: Array, confine: bool, drop: Array = []) -> Array:
	return options.filter(func(o):
		var tags: Dictionary = o.get("tags", {})
		if confine and not tags.get("inside", true):
			return false
		for tag in drop:
			if tags.get(String(tag), false):
				return false
		return true)


## Whether every named fact holds ("!" negates); a bound name (e.g. "target") counts as true.
func _requires_ok(names: Array) -> bool:
	var facts: Dictionary = _snap.get("facts", {})
	for n in names:
		var name := String(n)
		var negate := name.begins_with("!")
		var key := name.trim_prefix("!")
		var value: bool = _binding.has(key) or bool(facts.get(key, false))
		if value == negate:
			return false
	return true


## An option group from the snapshot: the bound target's own group of that name first, else the global
## one. Each group is { summary, options: [{ id, label, desc, params, tags }] }.
func _group(name) -> Dictionary:
	var options: Dictionary = _snap.get("options", {})
	if _binding.has("target_id"):
		var per: Dictionary = options.get("per_target", {}).get(_binding["target_id"], {})
		if per.has(String(name)):
			return per[String(name)]
	return options.get(String(name), {})


# --- What Von reads --------------------------------------------------------------------------

## Fill a node's template: {target} = the bound target's name, {summary} = its summary group's summary
## (its `summary_inside` within a confined subtree, so it never advertises a filtered-out place).
func _fill(template: String, id: StringName) -> String:
	var node: Dictionary = _nodes[id]
	var summary_group = node.get("summary", node.get("options", [&""])[0] if not node.get("options", []).is_empty() else &"")
	var summary := ""
	if summary_group != &"":
		var group := _group(summary_group)
		var confined: bool = _confine or (inside_only and node.get("confine", false))
		summary = group.get("summary_inside", group.get("summary", "")) if confined else group.get("summary", "")
	var text := template.format({ "target": _binding.get("target", "the hostile"), "summary": summary })
	return text.trim_suffix(" — ").trim_suffix(" ()").strip_edges()


## The state Von sees at node `node`'s level: the goal, the node's context sections (its
## `bind_context` on a bind level; the bound target's own version of a section first), then the path
## decided so far.
func _state_text(node: Dictionary, bind_level: bool) -> String:
	var lines: Array = []
	var context: Array = node.get("bind_context", node.get("context", [])) if bind_level else node.get("context", [])
	for name in [&"goal"] + context:
		var text := _section(String(name))
		if text != "":
			lines.append(text)
	if not _steps.is_empty():
		lines.append("Decided so far: %s." % " → ".join(_steps.map(func(s): return s["label"])))
	return "\n".join(lines)


## A state section: the bound target's version when it has one, else the global one.
func _section(name: String) -> String:
	if _binding.has("target_id"):
		var per: Dictionary = _snap.get("sections_per_target", {}).get(_binding["target_id"], {})
		if per.has(name):
			return per[name]
	return _snap.get("sections", {}).get(name, "")


## Mark the offered option that continues the last adopted plan, so Von can keep a plan rather than
## flip between near-equal options each decision.
func _mark_current_plan() -> void:
	var depth := _steps.size()
	if _prev_path.size() <= depth:
		return
	for i in depth:
		if _prev_path[i] != _steps[i]["id"]:
			return
	var id: String = _prev_path[depth]
	if _offered.has(id):
		_offered[id]["desc"] += " (your current plan)"


## The in-flight level's options as id → description (what Von ranks).
func _criteria() -> Dictionary:
	var out := {}
	for id in _offered:
		out[id] = _offered[id]["desc"]
	return out
