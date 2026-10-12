extends GameTest

## Legs shove light furniture (character_legs.gd). A prone body crawling backward drags its legs into a chair
## behind it and pushes it along before its body ever reaches it; a piece too heavy to move only stops the leg; and a
## body lying still with its legs across a chair pushes nothing (a foot at rest does not shove).

const LIGHT := {
	"name": "Chair", "shape": "rect", "size": Vector2(28, 28), "color": Color(0.6, 0.4, 0.25),
	"material": "wood", "coverage": 45.0, "penetration": 40.0, "weight": 4.0,
}
const HEAVY := {
	"name": "Safe", "shape": "rect", "size": Vector2(28, 28), "color": Color(0.4, 0.4, 0.45),
	"material": "metal", "coverage": 45.0, "penetration": 80.0, "weight": 5000.0,
}


func describe() -> Dictionary:
	return {
		"name": "Legs shove a light chair but not a heavy one or at rest",
		"description": "A prone puppet crawling backward moves a light chair with its legs before its body touches it; a heavy piece only stops the leg; a still body with its legs across a chair moves nothing.",
		"tags": ["legs", "contact", "push", "furniture", "posture", "prone"],
		"timeout": 25.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 700))
	s.set_static(CharacterConfig, &"posture_change_time", 0.0)
	s.switch(&"nav.rebake", false)
	s.actor(&"crawler", &"puppet", Vector2(520, 100), { "start_slot": 1 })
	s.object(&"chair", LIGHT, Vector2(330, 100))
	s.actor(&"crawler_heavy", &"puppet", Vector2(520, 300), { "start_slot": 1 })
	s.object(&"safe", HEAVY, Vector2(330, 300))
	s.actor(&"sleeper", &"puppet", Vector2(520, 500), { "start_slot": 1 })
	s.object(&"still_chair", LIGHT, Vector2(450, 500))


func run(t: TestContext) -> void:
	for id in [&"crawler", &"crawler_heavy", &"sleeper"]:
		var y: float = t.actor(id).global_position.y
		t.puppet(id).aim_at(Vector2(2000, y))
		t.puppet(id).set_posture(&"prone")
	await t.seconds(1.2)
	var chair := t.object(&"chair")
	var safe := t.object(&"safe")
	var still := t.object(&"still_chair")
	var chair_start: float = chair.global_position.x
	var safe_start: float = safe.global_position.x

	# Crawl backward (away from the aim): the legs trail toward the furniture.
	t.puppet(&"crawler").walk(Vector2.LEFT)
	t.puppet(&"crawler_heavy").walk(Vector2.LEFT)
	var body_touched := false
	var moved_before_body := false
	for _i in 600:
		await t.frames(1)
		var gap: float = t.actor(&"crawler").global_position.x - chair.global_position.x
		if gap < t.actor(&"crawler").radius + 14.0 + 1.0:
			body_touched = true
		if not body_touched and chair.global_position.x < chair_start - 3.0:
			moved_before_body = true
		if body_touched or t.actor(&"crawler_heavy").global_position.x < 330.0 + 14.0 + t.actor(&"crawler_heavy").radius + 10.0:
			break
	t.check(moved_before_body, "the chair was pushed along by the legs before the body touched it (moved %.1f px)" % (chair_start - chair.global_position.x))
	t.check(absf(safe.global_position.x - safe_start) < 1.0, "a heavy piece does not move (%.2f px)" % (safe.global_position.x - safe_start))
	var held := 0
	for i in 2:
		if t.actor(&"crawler_heavy").foot_clamp(i) != null:
			held += 1
	t.check(held > 0, "the heavy piece stops a leg")

	# Lying still across a chair: lying down swung the legs into it, but once settled nothing is shoved.
	var settled: Vector2 = still.global_position
	await t.seconds(1.5)
	t.check(still.global_position.distance_to(settled) < 1.0, "a body at rest pushes nothing (moved %.2f px)" % still.global_position.distance_to(settled))
