extends GameTest

## LD3 (`docs/leadership.md`): one squad per faction, with a leader. The invaders' leader is the highest `rank`, then the
## first in spawn order; the defenders' leader is the first spawned; when the human leads (`setup`'s `leader`), the leader is the human.
## The squad (`scenes/ai/team/squad.gd`) is built the way Main builds it: `setup(faction, members, openings, rooms, leader)` over the
## characters in spawn order. Plain puppets stand in for the members: the rule reads only their `rank` and the order they came in.

const Order := preload("res://tests/_ai/order_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A squad's leader: rank, then spawn order; the human when leading",
		"description": "Invaders are led by the highest rank (spawn order breaks a tie), defenders by the first spawned, and a squad the human leads by the human (LD3).",
		"tags": ["ai", "leadership", "squad"],
		"timeout": 5.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600))
	for i in 5:
		s.actor(StringName("i%d" % i), &"puppet", Vector2(100 + i * 60, 100), { "faction": &"invader" })
	s.actor(&"d0", &"puppet", Vector2(100, 400), { "faction": &"household" })
	s.actor(&"d1", &"puppet", Vector2(200, 400), { "faction": &"household" })
	s.actor(&"me", &"puppet", Vector2(700, 300), { "faction": &"invader" })


func run(t: TestContext) -> void:
	if not t.require(ResourceLoader.exists(Order.SQUAD_SCRIPT), "the squad script exists (%s)" % Order.SQUAD_SCRIPT):
		return
	var i := [t.actor(&"i0"), t.actor(&"i1"), t.actor(&"i2"), t.actor(&"i3"), t.actor(&"i4")]
	# Spawn order i0..i4; the ranks a match's unit would carry, the lead (2) not first.
	i[0].rank = 0
	i[1].rank = 1
	i[2].rank = 2
	i[3].rank = 0
	i[4].rank = 2
	var invaders := Order.squad(t, &"invader", i)
	if not t.require(invaders != null and invaders.has_method("leader"), "the squad reports its leader (leader())"):
		return
	t.check(invaders.leader() == i[2], "the invaders are led by the highest rank, the first of the two rank-2s in spawn order (got %s)" % _name(invaders.leader()))
	t.expect_eq(invaders.members().size() if invaders.has_method("members") else -1, 5, "every invader is a member (members())")

	var defenders := Order.squad(t, &"household", [t.actor(&"d0"), t.actor(&"d1")])
	t.check(defenders.leader() == t.actor(&"d0"), "the defenders are led by the first spawned (got %s)" % _name(defenders.leader()))

	var led := Order.squad(t, &"invader", i + [t.actor(&"me")], t.actor(&"me"))
	t.check(led.leader() == t.actor(&"me"), "a squad the human leads is led by the human, whatever the ranks (got %s)" % _name(led.leader()))
	var view := Order.view(led)
	t.check(view.get("leader") == t.actor(&"me"), "the squad's view() names the leader")
	t.expect_eq((view.get("members", []) as Array).size(), 6, "and lists every member")


## A node's name for a message, or the value as text.
func _name(n: Variant) -> String:
	return String(n.name) if n is Node and is_instance_valid(n) else str(n)
