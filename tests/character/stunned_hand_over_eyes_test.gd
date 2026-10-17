extends GameTest

## S1 (ticket #56, `docs/grenades.md` G13): a blinded character covers its eyes. While blind the hand that does not hold the weapon
## (not the held item's `weapon_hand()`) eases to the face, the palm over it, and eases back to its grip as sight returns; a reload,
## which needs that hand, takes it away for as long as it lasts and it goes back to the face after. A bang that only deafens leaves
## the hands where they were. Smooth: no hand and no head moves more than an eased stance change does in one frame. Read off the
## standing skeleton (`rig()`), for a pistol and a rifle.

const Rig = preload("res://scenes/character/body/character_rig.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")

## The palm over the eyes: the hand's centre within this many body radii of the head's centre (a head is ~0.4 radii round, a fist
## ~0.3), and on the face's side of it. Held normally the free hand is two radii or more away.
const AT_FACE := 1.0
const AWAY := 1.8
## The most a hand or the head may move in one frame (px, 3D). An eased stance change moves a hand ~5 px in its first frame
## (`stance_ease` 12/s over ~30 px); the head of a standing body barely moves at all.
const HAND_STEP := 8.0
const HEAD_STEP := 3.0
const BLIND := 4.0
const AIM := Vector2(2000, 0)


func describe() -> Dictionary:
	return {
		"name": "A blinded character covers its eyes with its free hand",
		"description": "take_stun(4, 4): the hand that does not hold the gun eases over the face and back as sight returns; a reload takes it away and it goes back; a deaf-only stun leaves it; nothing jumps in a frame.",
		"tags": ["grenade", "stun", "blind", "pose", "character"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600))
	s.switch(&"nav.rebake", false)
	s.actor(&"pistol", &"puppet", Vector2(150, 120), { "start_slot": 3, "start_rounds": 5, "max_health": 100000.0 })
	s.actor(&"rifle", &"puppet", Vector2(150, 300), { "start_slot": 6, "max_health": 100000.0 })
	s.actor(&"deaf", &"puppet", Vector2(150, 480), { "start_slot": 3, "max_health": 100000.0 })


## The free hand of `c` (the one its held item does not name as the weapon hand).
func _free(c: Node) -> int:
	var item: Item = c.current_item()
	return 1 - (item.weapon_hand() if item != null else 0)


## How far `c`'s free hand is from its head (in body radii), and whether it is on the face's side of the head.
func _to_face(c: Node) -> Dictionary:
	var rig = c.rig()
	var hand: Vector3 = rig.point(Rig.HAND[_free(c)])
	var head: Vector3 = rig.point(Rig.HEAD)
	var ahead: float = Vector2(hand.x - head.x, hand.y - head.y).dot(c.facing)
	return { "gap": hand.distance_to(head) / c.radius, "ahead": ahead }


## Whether `c`'s free hand is over its eyes: within `AT_FACE` radii of the head and not behind the face.
func _at_face(c: Node) -> bool:
	var f := _to_face(c)
	return f["gap"] <= AT_FACE and f["ahead"] >= -2.0


## Every physics frame from now on, the largest one-frame move of each body's hands and head (px), kept in `jumps`.
func _watch_jumps(t: TestContext, ids: Array, jumps: Dictionary, until: Array) -> void:
	var last := {}
	while not until[0]:
		for id: StringName in ids:
			var rig = t.actor(id).rig()
			var now := [rig.point(Rig.HAND[0]), rig.point(Rig.HAND[1]), rig.point(Rig.HEAD)]
			if last.has(id):
				var j: Dictionary = jumps[id]
				j["hand"] = maxf(j["hand"], maxf(now[0].distance_to(last[id][0]), now[1].distance_to(last[id][1])))
				j["head"] = maxf(j["head"], now[2].distance_to(last[id][2]))
			last[id] = now
		await t.frames(1)


func run(t: TestContext) -> void:
	var ids := [&"pistol", &"rifle", &"deaf"]
	for id: StringName in ids:
		t.puppet(id).aim_at(t.actor(id).global_position + AIM)
	await t.seconds(1.0)
	for id: StringName in ids:
		var f := _to_face(t.actor(id))
		t.check(f["gap"] >= AWAY, "%s: unstunned, the free hand holds the gun, away from the face (%.1f radii)" % [id, f["gap"]])

	var jumps := {}
	for id: StringName in ids:
		jumps[id] = { "hand": 0.0, "head": 0.0 }
	var stop := [false]
	_watch_jumps(t, ids, jumps, stop)

	# --- Blind (and deaf): the free hand goes to the face. A bang alone: it does not.
	for id: StringName in [&"pistol", &"rifle"]:
		if not t.require(Probe.stun(t.actor(id), BLIND, BLIND), "Character.take_stun(blind, deaf) exists"):
			return
	Probe.stun(t.actor(&"deaf"), 0.0, BLIND)
	await t.frames(1)
	for id: StringName in [&"pistol", &"rifle"]:
		t.check(not _at_face(t.actor(id)), "%s: the hand does not snap to the face on the frame of the flash (%.1f radii)" % [id, _to_face(t.actor(id))["gap"]])
	await t.seconds(0.6)
	for id: StringName in [&"pistol", &"rifle"]:
		var f := _to_face(t.actor(id))
		t.check(_at_face(t.actor(id)), "%s: blinded, the free hand covers the eyes (%.1f radii from the head, %.1f px ahead of it)" % [id, f["gap"], f["ahead"]])
	var deaf := _to_face(t.actor(&"deaf"))
	t.check(deaf["gap"] >= AWAY, "deaf only: the free hand stays on the gun (%.1f radii)" % deaf["gap"])

	# --- A reload needs that hand: it leaves the face for the reload and goes back while still blind.
	var pistol := t.actor(&"pistol")
	t.puppet(&"pistol").reload()
	if t.require(await t.until(func() -> bool: return pistol.is_reloading(), 0.5), "the blinded pistol starts a reload"):
		await t.seconds(0.35)
		t.check(not _at_face(pistol) and pistol.is_reloading(), "mid-reload the free hand has left the face for the magazine (%.1f radii)" % _to_face(pistol)["gap"])
		await t.until(func() -> bool: return not pistol.is_reloading(), 3.0)
		t.check(Probe.blind(pistol), "(the reload ended while still blind)")
		await t.seconds(0.5)
		t.check(_at_face(pistol), "after the reload, still blind, the hand is back over the eyes (%.1f radii)" % _to_face(pistol)["gap"])

	# --- Sight returns: the hand goes back to the gun.
	await t.until(func() -> bool: return not Probe.blind(t.actor(&"rifle")) and not Probe.blind(pistol), BLIND + 1.0)
	await t.seconds(1.0)
	for id: StringName in [&"pistol", &"rifle"]:
		var f := _to_face(t.actor(id))
		t.check(f["gap"] >= AWAY, "%s: once it can see, the free hand is back on the gun (%.1f radii)" % [id, f["gap"]])
	stop[0] = true
	await t.frames(1)

	# --- Smooth all the way.
	for id: StringName in ids:
		t.check(jumps[id]["hand"] <= HAND_STEP, "%s: no hand moved more than %.0f px in a frame (worst %.1f px)" % [id, HAND_STEP, jumps[id]["hand"]])
		t.check(jumps[id]["head"] <= HEAD_STEP, "%s: the head never moved more than %.0f px in a frame (worst %.1f px)" % [id, HEAD_STEP, jumps[id]["head"]])
