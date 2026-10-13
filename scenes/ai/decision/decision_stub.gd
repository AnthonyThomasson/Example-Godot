class_name DecisionStub
extends RefCounted

## AI DECISION sub-domain: a scripted stand-in for the Von server, used by game tests. While `active`,
## decision_client.gd answers every `ask()` from here instead of making an HTTP request, so the
## perception → decision → behaviour wiring can be tested deterministically without a server. It
## decides nothing about quality — it only returns the picks a test scripted.
##
## `rules` is an ordered list of `{ pick: String, question: String (optional) }`: the first rule whose
## `pick` is among the offered option ids (and whose `question` text, when given, occurs in the level's
## question) wins; with no matching rule the first offered id is taken. `fail` makes every ask fail,
## as if the server were down. `requests` logs each ask as `{ state, question, options: Array, pick }`.

## Answer from this stub instead of the server.
static var active := false
## Fail every ask (the server-down path).
static var fail := false
static var rules: Array = []
static var requests: Array = []
## Physics frames an answer is held back, like a slow server (0 = the next frame). The old leaf keeps running meanwhile.
static var latency_frames := 0


## The id to answer `options` (id → description) with, or "" when `fail` is set. Logs the request.
static func answer(state: String, question: String, options: Dictionary) -> String:
	var pick := ""
	if not fail:
		pick = String(options.keys()[0]) if not options.is_empty() else ""
		for rule in rules:
			if options.has(rule["pick"]) and (not rule.has("question") or question.containsn(rule["question"])):
				pick = rule["pick"]
				break
	requests.append({ "state": state, "question": question, "options": options.keys(), "pick": pick })
	return pick
