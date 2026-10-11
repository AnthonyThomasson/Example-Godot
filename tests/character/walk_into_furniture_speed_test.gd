extends GameTest

## Eight puppets each walk into a different piece of furniture from a different side — from the top,
## bottom, left and right and from each corner (diagonals), light pieces to heavy. Every walker's
## real speed must stay steady once it meets its piece: no lunge past walk speed and no sudden
## frame-to-frame snap while it shoves the piece.

const WALK_SPEED := 150.0
const CELL := 600.0
const START_GAP := 100.0
const FRAMES := 150
## Frames after first contact ignored: the sweep stops at the surface, so that frame's travel is partial.
const SETTLE_FRAMES := 2

## [id, walker comes from (the direction it walks is the opposite), piece definition key]
const CASES := [
	[&"from_top", Vector2(0, -1), "sofa"],
	[&"from_bottom", Vector2(0, 1), "chair"],
	[&"from_left", Vector2(-1, 0), "armchair"],
	[&"from_right", Vector2(1, 0), "bench"],
	[&"from_top_left", Vector2(-1, -1), "plant"],
	[&"from_top_right", Vector2(1, -1), "table"],
	[&"from_bottom_left", Vector2(-1, 1), "bathtub"],
	[&"from_bottom_right", Vector2(1, 1), "lamp"],
]


func describe() -> Dictionary:
	return {
		"name": "Walking into furniture keeps speed steady",
		"description": "Eight puppets walk into different furniture from the sides and corners; none's speed spikes or snaps between frames.",
		"tags": ["walk", "pushable", "locomotion"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, CELL * 4.0, CELL * 2.0))
	s.switch(&"nav.rebake", false)
	for i in CASES.size():
		var c: Array = CASES[i]
		var centre := _centre(i)
		s.object(c[0], c[2], centre)
		s.actor(c[0], &"puppet", centre + (c[1] as Vector2).normalized() * START_GAP, { "start_slot": 2 })


func run(t: TestContext) -> void:
	var prev := {}
	var max_speed := {}
	var max_jump := {}
	var contact := {}
	var since := {}
	var start := {}
	for c in CASES:
		var id: StringName = c[0]
		t.puppet(id).walk(-(c[1] as Vector2).normalized())
		prev[id] = 0.0
		max_speed[id] = 0.0
		max_jump[id] = 0.0
		contact[id] = false
		since[id] = 0
		start[id] = t.object(id).global_position
	for i in FRAMES:
		await t.frames(1)
		for id in prev:
			var sp: float = t.actor(id).get_real_velocity().length()
			t.trace(String(id), sp)
			# Only judge once the walker has touched (budged) its piece.
			if not contact[id] and t.object(id).global_position.distance_to(start[id]) > 0.5:
				contact[id] = true
				prev[id] = sp
			if contact[id]:
				since[id] += 1
			if contact[id] and since[id] <= SETTLE_FRAMES:
				prev[id] = sp
			elif contact[id]:
				max_speed[id] = maxf(max_speed[id], sp)
				max_jump[id] = maxf(max_jump[id], absf(sp - prev[id]))
				prev[id] = sp
	for id in prev:
		t.require(contact[id], "%s reached its piece" % id)
		t.check(max_speed[id] <= WALK_SPEED * 1.05, "%s never lunges past walk speed (peak %.1f)" % [id, max_speed[id]])
		t.check(max_jump[id] <= WALK_SPEED * 0.4, "%s speed never snaps between frames (max jump %.1f)" % [id, max_jump[id]])


## Middle of case `i`'s cell in the 4×2 grid.
func _centre(i: int) -> Vector2:
	return Vector2((i % 4 + 0.5) * CELL, (i / 4 + 0.5) * CELL)
