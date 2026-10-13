extends GameTest

## G3: the grenade flies a lob. It passes over furniture whose `coverage` is below the arc's height (a desk, 45) and
## strikes tall furniture (a wardrobe, 95). Two lanes, the same throw: past the desk it lands at the aim point; at the
## wardrobe it is stopped and ends on the near side.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const DESK := Vector2(300, 100)     ## 120 x 50, coverage 45
const WARDROBE := Vector2(300, 400) ## 90 x 45, coverage 95
const LANE_A := Vector2(100, 100)
const LANE_B := Vector2(100, 400)
const AIM_A := Vector2(500, 100)
const AIM_B := Vector2(500, 400)


func describe() -> Dictionary:
	return {
		"name": "A grenade lobs over a desk but not a wardrobe",
		"description": "Two throwers aim 400 px along parallel lanes: the one with a desk across the lane lands at the aim point beyond it, the one with a wardrobe across the lane ends before it.",
		"tags": ["grenade", "lob", "cover", "item"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 500))
	s.switch(&"nav.rebake", false)
	s.object(&"desk", "desk", DESK)
	s.object(&"wardrobe", "wardrobe", WARDROBE)
	s.actor(&"over", &"puppet", LANE_A, { "max_health": 100000.0 })
	s.actor(&"into", &"puppet", LANE_B, { "max_health": 100000.0 })


func run(t: TestContext) -> void:
	for who in [&"over", &"into"]:
		Probe.arm(t.actor(who), 2, 0)
	if not t.require(Probe.count(t.actor(&"over"), Probe.STUN) == 2 and Probe.count(t.actor(&"into"), Probe.STUN) == 2, "both carry stun grenades"):
		return
	t.puppet(&"over").select_slot(Probe.STUN)
	t.puppet(&"into").select_slot(Probe.STUN)
	t.puppet(&"over").aim_at(AIM_A)
	t.puppet(&"into").aim_at(AIM_B)
	await t.seconds(0.4)
	t.puppet(&"over").shoot()
	t.puppet(&"into").shoot()
	if not t.require(await Probe.wait_boom(t, &"stun", 5.0, 2), "both grenades go off"):
		return
	var lane_a: Vector2 = Vector2.INF
	var lane_b: Vector2 = Vector2.INF
	for b in Probe.booms(t, &"stun"):
		var p: Vector2 = b["data"]["position"]
		if p.y < 250.0:
			lane_a = p
		else:
			lane_b = p
	t.check(lane_a.x > DESK.x + 60.0, "over the desk: it flew past it (x %.0f, the desk's far face is at %.0f)" % [lane_a.x, DESK.x + 60.0])
	t.check(lane_a.distance_to(AIM_A) < 45.0, "and landed at the aim point (%.0f px off)" % lane_a.distance_to(AIM_A))
	t.check(lane_b.x < WARDROBE.x - 45.0 + 4.0, "into the wardrobe: it was stopped on the near side (x %.0f, the near face is at %.0f)" % [lane_b.x, WARDROBE.x - 45.0])
	t.check(lane_b.x > LANE_B.x + 40.0, "having flown toward it first (x %.0f)" % lane_b.x)
