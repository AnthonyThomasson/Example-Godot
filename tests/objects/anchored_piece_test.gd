extends GameTest

## R8 (ticket #61): an object whose definition sets `anchored: true` is a solid piece that never moves. Four posts of a
## test definition (spawned through ObjectFactory, interface 2) are each struck one way, a walking push, a leg kick, a
## pistol shot and a frag blast, and none of them moves or turns; the shot still dents its post (the hittable contract,
## interface 3: a dent is recorded in `hit_marks()`). Each post has a twin from the same definition without `anchored`,
## struck the same way at the same time, which must be shoved: that proves each strike was strong enough to move a piece
## of that weight, so a post standing still is the anchoring and not a strike that missed.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const FROM := Vector2(300, 700)  ## Where the grenade is thrown from.
const AIM := Vector2(700, 700)  ## Where it is thrown to: its post north of here, its twin south.
## How far (px) an anchored post may drift and turn (rad): a frozen body does not move at all.
const STILL := 0.1
const STILL_TURN := 0.001
## How far (px) the unanchored twin must be shoved for the strike to count.
const SHOVED := 3.0
## The test post: a light metal circle, so the twin shows every shove plainly.
const POST := {
	"name": "Post", "shape": "circle", "size": Vector2(28, 28), "color": Color(0.32, 0.33, 0.36), "material": "metal",
	"weight": 6, "coverage": 100, "penetration": 85, "anchored": true,
}
## [strike (also the id of its striker and its post), where the striker stands, the slot it holds, where the anchored
## post stands, where the twin's striker stands, where the twin stands]
const STRIKES := [
	[&"walk", Vector2(120, 120), 2, Vector2(220, 120), Vector2(120, 260), Vector2(220, 260)],
	[&"kick", Vector2(500, 120), 2, Vector2(542, 120), Vector2(500, 260), Vector2(542, 260)],
	[&"shot", Vector2(800, 120), 3, Vector2(1000, 120), Vector2(800, 260), Vector2(1000, 260)],
]


func describe() -> Dictionary:
	return {
		"name": "An anchored piece never moves",
		"description": "Posts defined with anchored: true stay put under a walking push, a kick, a shot and a frag blast (an unanchored twin is shoved by each), and the shot still dents its post.",
		"tags": ["objects", "anchored", "pushable", "hittable", "streetlight"],
		"timeout": 24.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1400, 1000))
	s.switch(&"nav.rebake", false)  # the twins are shoved about; re-baking overlapping holes logs a sync error
	s.switch(&"projectile.flyover", false)
	var twin := POST.duplicate()
	twin.erase("anchored")
	for strike: Array in STRIKES:
		var id: StringName = strike[0]
		s.actor(id, &"puppet", strike[1], { "start_slot": strike[2], "max_health": 100000.0 })
		s.object(id, POST, strike[3])
		s.actor(_twin(id), &"puppet", strike[4], { "start_slot": strike[2], "max_health": 100000.0 })
		s.object(_twin(id), twin, strike[5])
	s.actor(&"thrower", &"puppet", FROM, { "max_health": 100000.0 })
	s.object(&"blast", POST, AIM + Vector2(0, -90))
	s.object(_twin(&"blast"), twin, AIM + Vector2(0, 90))


func _twin(id: StringName) -> StringName:
	return StringName(String(id) + "_twin")


## Where `piece` stands and how it is turned, to compare after a strike.
func _pose(piece: Node2D) -> Array:
	return [piece.global_position, piece.global_rotation]


## Check the anchored post `id` kept `before` and its twin moved from `twin_before`, after the strike `what`.
func _judge(t: TestContext, id: StringName, before: Array, twin_before: Array, what: String) -> void:
	var post: Node2D = t.object(id)
	var twin: Node2D = t.object(_twin(id))
	var moved := post.global_position.distance_to(before[0])
	var turned := absf(angle_difference(post.global_rotation, before[1]))
	var twin_moved := twin.global_position.distance_to(twin_before[0])
	t.check(twin_moved > SHOVED, "%s: the unanchored twin is shoved (%.1f px), so the strike was real" % [what, twin_moved])
	t.check(moved < STILL and turned < STILL_TURN, "%s: the anchored post stays put (moved %.2f px, turned %.4f rad)" % [what, moved, turned])


func run(t: TestContext) -> void:
	await _walk(t)
	await _kick(t)
	await _shot(t)
	await _blast(t)


## A puppet walks straight into each post for a second and a half.
func _walk(t: TestContext) -> void:
	var before := _pose(t.object(&"walk"))
	var twin_before := _pose(t.object(_twin(&"walk")))
	t.puppet(&"walk").walk(Vector2.RIGHT)
	t.puppet(_twin(&"walk")).walk(Vector2.RIGHT)
	var walker := t.actor(&"walk")
	var post: Node2D = t.object(&"walk")
	var closest := INF
	for i in 90:
		await t.frames(1)
		closest = minf(closest, walker.global_position.distance_to(post.global_position))
	t.puppet(&"walk").stop()
	t.puppet(_twin(&"walk")).stop()
	var touch: float = walker.radius + POST["size"].x * 0.5 + 4.0
	if t.check(closest <= touch, "walk: the walker reached the anchored post (closest %.1f px, touching at %.1f)" % [closest, touch]):
		_judge(t, &"walk", before, twin_before, "walk")


## A puppet kicks each post from right beside it.
func _kick(t: TestContext) -> void:
	var post: Node2D = t.object(&"kick")
	var twin: Node2D = t.object(_twin(&"kick"))
	t.puppet(&"kick").aim_at(post.global_position)
	t.puppet(_twin(&"kick")).aim_at(twin.global_position)
	await t.seconds(0.3)
	var before := _pose(post)
	var twin_before := _pose(twin)
	t.puppet(&"kick").kick()
	t.puppet(_twin(&"kick")).kick()
	var landed := func(d: Dictionary) -> bool: return d["actor"] == &"kick" and d["body"] == post and d["hand"] == 2
	if not t.check(await t.until(func() -> bool: return t.happened(&"hit_landed", landed), 1.5), "kick: the kick lands on the anchored post"):
		return
	await t.seconds(1.0)
	_judge(t, &"kick", before, twin_before, "kick")


## A puppet shoots each post with a pistol: the anchored one is dented but not shoved.
func _shot(t: TestContext) -> void:
	var post: Node2D = t.object(&"shot")
	var twin: Node2D = t.object(_twin(&"shot"))
	t.puppet(&"shot").aim_at(post.global_position)
	t.puppet(_twin(&"shot")).aim_at(twin.global_position)
	await t.seconds(0.5)
	var before := _pose(post)
	var twin_before := _pose(twin)
	t.puppet(&"shot").shoot()
	t.puppet(_twin(&"shot")).shoot()
	var struck := func(d: Dictionary) -> bool: return d["victim"] == post
	var twin_struck := func(d: Dictionary) -> bool: return d["victim"] == twin
	if not t.check(await t.until(func() -> bool: return t.happened(&"hit", struck) and t.happened(&"hit", twin_struck), 2.0), "shot: a round strikes each post"):
		return
	await t.seconds(1.0)
	_judge(t, &"shot", before, twin_before, "shot")
	t.check(post.hit_marks().size() > 0, "shot: the anchored post is dented by the round (%d marks)" % post.hit_marks().size())


## A frag goes off between the last post and its twin.
func _blast(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	var post: Node2D = t.object(&"blast")
	Probe.arm(thrower, 0, 1)
	if not t.require(Probe.count(thrower, Probe.FRAG) == 1, "blast: the thrower carries a frag (item_count(8) = %d)" % Probe.count(thrower, Probe.FRAG)):
		return
	var before := _pose(post)
	var twin_before := _pose(t.object(_twin(&"blast")))
	await Probe.throw_at(t, &"thrower", Probe.FRAG, AIM)
	if not t.require(await Probe.wait_boom(t, &"frag", 6.0), "blast: the frag goes off"):
		return
	await t.seconds(1.5)
	if t.check(not Probe.blast_hits(t, post).is_empty(), "blast: the blast reaches the anchored post"):
		_judge(t, &"blast", before, twin_before, "blast")
